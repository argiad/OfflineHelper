//
//  RequestRelayBackground.swift
//  RequestRelay
//
//  Schedules and drives BGProcessing for RequestRelay.
//  Works on iOS 17+; no-ops where BackgroundTasks is unavailable.
//

import Foundation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

// MARK: - Config

internal struct RequestRelayBGConfig: Sendable {
    /// Minimum gap between background sync attempts (default 15 minutes, clamped to >= 60s).
    public var interval: TimeInterval
    public init(interval: TimeInterval = 15 * 60) { self.interval = max(60, interval) }
}

// MARK: - Keys (scoped by identifier to avoid collisions)

internal enum RRBGKeys {
    static func taskID(default id: String) -> String { id } // pass-through helper
    static func nextScheduledKey(for id: String) -> String { "requestrelay.bg.nextScheduledAt.\(id)" }
}

// MARK: - Public API

@MainActor
internal enum RequestRelayBackground {
    /// Call once at app launch to register the BG task handler.
    /// - Parameter identifier: BG task identifier. Defaults to the one configured in `RequestRelay.shared`.
    internal static func register(identifier: String? = nil) {
        #if canImport(BackgroundTasks)
        let taskID = RRBGKeys.taskID(default: identifier ?? RequestRelay._shared.backgroundTaskIdentifier)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let ptask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleProcessingTask(ptask, identifier: taskID)
        }
        #endif
    }

    /// Schedule a background sync if not already scheduled or if stale.
    /// Safe to call frequently (idempotent with a time gate).
    internal static func scheduleIfNeeded(
        identifier: String? = nil,
        config: RequestRelayBGConfig = .init()
    ) {
        #if canImport(BackgroundTasks)
        let taskID = RRBGKeys.taskID(default: identifier ?? RequestRelay._shared.backgroundTaskIdentifier)
        let key = RRBGKeys.nextScheduledKey(for: taskID)

        let now = Date()
        if let nextAt = UserDefaults.standard.object(forKey: key) as? Date, nextAt > now {
            return // already scheduled in the future
        }

        let earliest = now.addingTimeInterval(config.interval)
        let req = BGProcessingTaskRequest(identifier: taskID)
        req.earliestBeginDate = earliest
        req.requiresNetworkConnectivity = true
        req.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(req)
            UserDefaults.standard.set(earliest, forKey: key)
        } catch {
            // If submission fails (e.g., iOS throttling), nudge a shorter fallback so we’ll retry later.
            let fallback = now.addingTimeInterval(5 * 60)
            UserDefaults.standard.set(fallback, forKey: key)
        }
        #endif
    }
}

#if canImport(BackgroundTasks)
// MARK: - Internal BG handler
@MainActor
private func handleProcessingTask(_ task: BGProcessingTask, identifier: String) {
    let keyFor = RRBGKeys.nextScheduledKey

    RequestRelay._shared.handleBackgroundTask(
        task,
        identifier: identifier,
        reschedule: { id in
            RequestRelayBackground.scheduleIfNeeded(identifier: id)
        },
        clearFutureMarker: { id in
            UserDefaults.standard.removeObject(forKey: keyFor(id))
        }
    )
}

#endif
