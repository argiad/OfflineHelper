//
//  File.swift
//  RequestRelay
//
//  Created by Artem Mkrtchyan on 8/22/25.
//

import Foundation
import Network

// MARK: - URLSession Transport

struct URLSessionTransport: Transport {
    let session: URLSession = .shared

    func send(_ req: OfflineRequest) async throws -> TransportResponse {
        var urlReq = URLRequest(url: req.url)
        urlReq.httpMethod = req.method
        urlReq.httpBody = req.body
        for (k, v) in req.headers { urlReq.setValue(v, forHTTPHeaderField: k) }

        do {
            let (data, response) = try await session.data(for: urlReq)
            guard let http = response as? HTTPURLResponse else { throw TransportError.invalidResponse }
            let headers = http.allHeaderFields.reduce(into: [String:String]()) { acc, kv in
                if let key = kv.key as? String, let val = kv.value as? CustomStringConvertible {
                    acc[key] = val.description
                }
            }
            return TransportResponse(statusCode: http.statusCode, headers: headers, body: data)
        } catch {
            throw TransportError.network(error)
        }
    }
}

// MARK: - NWPath Reachability

actor NWReachability: Reachability {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "reachability.queue")

    private var current: Bool = false
    private let stream: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation

    init() {
        var cont: AsyncStream<Bool>.Continuation!
        self.stream = AsyncStream<Bool> { continuation in
            cont = continuation
        }
        self.continuation = cont
        self.monitor = NWPathMonitor()

        // Bridge NWPathMonitor callback into the actor safely
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = (path.status == .satisfied)
            Task { await self?.update(reachable) }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
        continuation.finish()
    }

    // MARK: Reachability
    func isReachable() async -> Bool { current }
    func changes() async -> AsyncStream<Bool> { stream }

    // MARK: Internal
    private func update(_ reachable: Bool) {
        current = reachable
        continuation.yield(reachable)
    }
}

// MARK: - System Clock & Logger

struct SystemClock: Clock {
    func now() -> Date { Date() }
    func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

struct OSLogger: Logger {
    func log(_ level: LogLevel, _ message: String) {
        #if DEBUG
        print("[\(level)] \(message)")
        #endif
    }
}

public extension Date {
    /// Adds a Swift Concurrency `Duration` to a `Date`.
    func adding(_ duration: Duration) -> Date {
        let seconds = Double(duration.components.seconds) +
                      Double(duration.components.attoseconds) / 1e18
        return self.addingTimeInterval(seconds)
    }

    /// Mutating version
    mutating func add(_ duration: Duration) {
        self = adding(duration)
    }
}
