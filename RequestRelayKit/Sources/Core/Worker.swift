//
//  Worker.swift
//  RequestRelay
//
//  Created by Artem Mkrtchyan on 8/21/25.
//

import Foundation

actor Worker: WorkerProtocol {
    private let cfg: WorkerConfig
    private var running = false
    private var nextTimerTask: Task<Void, Never>?

    init(cfg: WorkerConfig) { self.cfg = cfg }

    func stop() {
        running = false
        nextTimerTask?.cancel()
        nextTimerTask = nil
    }

    func enqueue(_ request: OfflineRequest) async {
        // Dedupe policy (minimal)
        if let key = request.dedupeKey {
            if cfg.dedupe == .dropNewIfSameKeyExists,
               let existing = try? await cfg.storage.loadByDedupeKey(key),
               existing.isEmpty == false { // (ok for Swift)
                cfg.logger.log(.info, "Dropped new \(request.id) due to dedupe")
                return
            }
        }
        let item = QueueItem(envelope: request, now: cfg.clock.now())
        try? await cfg.storage.save(item)
        // Try to send sooner if online
        Task { await kick() }
    }

    func kick() {
        guard !running else { return }
        running = true
        Task { [weak self] in
            guard let self else { return }
            await self.drainLoop()
        }
    }

    private func schedule(at date: Date) {
        nextTimerTask?.cancel()
        let delay = max(0, date.timeIntervalSince(cfg.clock.now()))
        nextTimerTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 {
                await self.cfg.clock.sleep(for: .seconds(delay))
            }
            await self.kick()
        }
    }

    private func nextReadyBatch(now: Date) async -> [QueueItem] {
        // Storage should already order by (priority desc, nextAttemptAt asc, createdAt asc)
        (try? await cfg.storage.loadReady(limit: cfg.batchSize, now: now)) ?? []
    }

    private func classify(_ code: Int, headers: [String:String]) -> FailureKind? {
        if code == 429 {
            if cfg.retry.respectRetryAfter,
               let ra = headers.first(where: { $0.key.lowercased() == "retry-after" })?.value,
               let secs = TimeInterval(ra) {
                return .rateLimited(retryAfter: .seconds(secs))
            }
            return .rateLimited(retryAfter: nil)
        }
        if code >= 500 { return .serverError }
        if code == 408 || code == 425 || code == 409 { return .conflictRetryable }
        if code >= 400 { return .clientTerminal }
        return nil // success
    }

    private func drainLoop() async {
        defer { running = false }
        while await cfg.reachability.isReachable() {
            let now = cfg.clock.now()
            let batch = await nextReadyBatch(now: now)
            if batch.isEmpty {
                // Find next delayed item to schedule wakeup
                if let soonest = findSoonestReadyDate() {
                    schedule(at: soonest)
                }
                return
            }

            for var item in batch {
                // Dispatch
                item.state = .inFlight
                try? await cfg.storage.update(item)
                cfg.logger.log(.debug, "Dispatch \(item.id) attempt \(item.attempt + 1)")

                do {
                    let resp = try await cfg.transport.send(item.envelope)
                    if let kind = classify(resp.statusCode, headers: resp.headers) {
                        // Failure path (retryable/non)
                        try await handleFailure(item: item, kind: kind)
                    } else {
                        // Success
                        item.state = .succeeded
                        try? await cfg.storage.update(item)
                        try? await cfg.storage.delete(id: item.id)
                        cfg.logger.log(.info, "Succeeded \(item.id) [\(resp.statusCode)]")
                    }
                } catch {
                    // Network failure
                    try? await handleFailure(item: item, kind: .network)
                }
            }
        }
        // Offline: schedule nothing (reachability will kick later)
    }

    private func handleFailure(item: QueueItem, kind: FailureKind) async throws {
        var mutable = item
        mutable.attempt += 1
        let willRetry: Bool
        var delay: Duration? = nil

        switch kind {
        case .clientTerminal:
            willRetry = false
        case .rateLimited(let retryAfter):
            if let d = retryAfter { delay = d; willRetry = true }
            else {
                if mutable.attempt < cfg.retry.maxAttempts {
                    delay = cfg.retry.backoff(for: mutable.attempt)
                    willRetry = true
                } else { willRetry = false }
            }
        default:
            if mutable.attempt < cfg.retry.maxAttempts { delay = cfg.retry.backoff(for: mutable.attempt); willRetry = true }
            else { willRetry = false }
        }

        if willRetry {
            mutable.state = .delayed
            let now = cfg.clock.now()
            let next = delay ?? .seconds(1)
            mutable.nextAttemptAt = now.addingTimeInterval(TimeInterval(next.components.seconds))
            try? await cfg.storage.update(mutable)
            cfg.logger.log(.warning, "Retry \(mutable.id) in \(next.components.seconds)s")
        } else {
            mutable.state = .failed
            try? await cfg.storage.update(mutable)
            cfg.logger.log(.error, "Failed \(mutable.id) (no more retries)")
        }
    }

    private func findSoonestReadyDate() -> Date? {
        // Simple approach: ask storage for one “next soonest” delayed item by time.
        // If your storage doesn’t offer it yet, just return nil (no timer).
        // Implementers can extend Storage to add `loadSoonestDelayed()` if desired.
        return nil
    }
}

public protocol WorkerProtocol: Sendable {
    func kick() async
    func stop() async
    func enqueue(_ request: OfflineRequest) async
}

public struct WorkerConfig: Sendable {
    let storage: Storage
    let transport: Transport
    let reachability: Reachability
    let clock: Clock
    let logger: Logger
    let retry: RetryPolicy
    let dedupe: DedupePolicy
    let batchSize: Int

    public init(storage: Storage,
                transport: Transport,
                reachability: Reachability,
                clock: Clock,
                logger: Logger,
                retry: RetryPolicy = .init(),
                dedupe: DedupePolicy = .keepAll,
                batchSize: Int = 10) {
        self.storage = storage
        self.transport = transport
        self.reachability = reachability
        self.clock = clock
        self.logger = logger
        self.retry = retry
        self.dedupe = dedupe
        self.batchSize = max(1, batchSize)
    }
    
    static func makeDefaultConfig() -> WorkerConfig {
        WorkerConfig(
            storage: InMemoryStorage(),
            transport: URLSessionTransport(),
            reachability: NWReachability(),
            clock: SystemClock(),
            logger: OSLogger()
        )
    }
}

// MARK: - Transport

public struct TransportResponse: Sendable {
    let statusCode: Int
    let headers: [String:String]
    let body: Data
}

public enum TransportError: Error, Sendable {
    case network(Error)
    case invalidResponse
}

public protocol Transport: Sendable {
    func send(_ req: OfflineRequest) async throws -> TransportResponse
}

// MARK: - Reachability

public protocol Reachability: Sendable {
    func isReachable() async -> Bool
    func changes() async -> AsyncStream<Bool>
}

// MARK: - Clock & Logger

public protocol Clock: Sendable {
    func now() -> Date
    func sleep(for duration: Duration) async
}

public protocol Logger: Sendable {
    func log(_ level: LogLevel, _ message: String)
}
