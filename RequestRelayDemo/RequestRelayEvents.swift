//
//  OfflineEvents.swift
//  OfflineHandler
//
//  Created by Artem Mkrtchyan on 8/21/25.
//

import Foundation
import RequestRelayKit
import Combine


@MainActor
public final class RequestRelayEvents: ObservableObject {
    // MARK: Public read-only snapshots
    @Published public private(set) var isOnline: Bool = false
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var status: RRStatus = .idle
    @Published public private(set) var lastMessage: String = ""
    @Published public private(set) var logLines: [String] = []

    // MARK: Config
    private let maxLogLines = 200

    // MARK: Internals
    private var cancellables = Set<AnyCancellable>()
    private let relay: RequestRelaying

    // MARK: Init
    /// Pass any `RequestRelaying` implementation (default your singleton).
    public init(relay: RequestRelaying ) {
        self.relay = relay
        bind()
    }

    deinit {
        cancellables.removeAll()
    }

    // MARK: Subscriptions
    private func bind() {
        // Online/offline
        relay.isOnlinePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] online in
                guard let self else { return }
                self.isOnline = online
                self.push("Network → \(online ? "ONLINE" : "OFFLINE")")
            }
            .store(in: &cancellables)

        // Running
        relay.isRunningPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                self.isRunning = running
                self.push("Relay → \(running ? "RUNNING" : "NOT RUNNING")")
            }
            .store(in: &cancellables)

        // Paused
        relay.isPausedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                guard let self else { return }
                self.isPaused = paused
                if paused { self.push("Relay → PAUSED") }
            }
            .store(in: &cancellables)

        // Detailed status
        relay.currentStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                guard let self else { return }
                self.status = newStatus
                switch newStatus {
                case .idle:       self.push("Status → IDLE")
                case .running:    self.push("Status → RUNNING")
                case .paused:     self.push("Status → PAUSED")
                case .stopped:    self.push("Status → STOPPED")
                case .error(let e):
                    self.push("Status → ERROR: \(String(describing: e))")
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Convenience controls (optional pass-throughs)
    public func start()  { relay.start() }
    public func stop()   { relay.stop()  }
    public func pause()  { relay.pause() }
    public func setOnline(_ online: Bool) { relay.setOnline(online) }

    // MARK: Logging
    private func push(_ line: String) {
        lastMessage = line
        logLines.append("[\(timestamp())] \(line)")
        if logLines.count > maxLogLines {
            logLines.removeFirst(logLines.count - maxLogLines)
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
