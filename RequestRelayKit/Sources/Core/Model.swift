//
//  Model.swift
//  RequestRelay
//
//  Created by Artem Mkrtchyan on 8/21/25.
//

import Foundation
import SwiftData

public enum ItemState: String, Sendable, Codable {
    case pending
    case inFlight
    case delayed
    case failed
    case succeeded
    case canceled
}

public enum FailureKind: Sendable {
    case network
    case rateLimited(retryAfter: Duration?)
    case serverError
    case clientTerminal
    case conflictRetryable
    case authExpired
}

public struct FailureMeta: Sendable, Codable, Equatable, Hashable {
    let kind: String
    let detail: String
}

public struct QueueItem: Sendable, Codable, Equatable, Hashable {
    var id: UUID { envelope.id }
    var envelope: OfflineRequest
    var priority: Int
    var state: ItemState
    var attempt: Int
    var nextAttemptAt: Date
    var lastError: FailureMeta?

    init(envelope: OfflineRequest, now: Date) {
        self.envelope = envelope
        self.priority = envelope.priority
        self.state = .pending
        self.attempt = 0
        self.nextAttemptAt = now
        self.lastError = nil
    }
}

// MARK: - SwiftData model

@Model
final class QueueItemRecord {
    @Attribute(.unique) var id: UUID        // If this errors, see fallback below
    var stateRaw: String
    var nextAttemptAt: Date
    var priority: Int
    var envelopeCreatedAt: Date
    var dedupeKey: String?

    // Full domain payload
    var blob: Data

    init(from item: QueueItem) throws {
        self.id = item.id
        self.stateRaw = item.state.rawValue
        self.nextAttemptAt = item.nextAttemptAt
        self.priority = item.priority
        self.envelopeCreatedAt = item.envelope.createdAt
        self.dedupeKey = item.envelope.dedupeKey
        self.blob = try JSONEncoder().encode(item)
    }

    func update(from item: QueueItem) throws {
        self.stateRaw = item.state.rawValue
        self.nextAttemptAt = item.nextAttemptAt
        self.priority = item.priority
        self.envelopeCreatedAt = item.envelope.createdAt
        self.dedupeKey = item.envelope.dedupeKey
        self.blob = try JSONEncoder().encode(item)
    }

    func asDomain() throws -> QueueItem {
        try JSONDecoder().decode(QueueItem.self, from: blob)
    }
}
