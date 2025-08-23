//
//  Storage.swift
//  RequestRelay
//
//  Created by Artem Mkrtchyan on 8/22/25.
//

import Foundation

// MARK: -- Storage protocol
public protocol Storage: Sendable {
    func save(_ item: QueueItem) async throws
    func loadReady(limit: Int, now: Date) async throws -> [QueueItem]
    func update(_ item: QueueItem) async throws
    func delete(id: UUID) async throws
    func countActive() async throws -> Int
    func loadByDedupeKey(_ key: String) async throws -> [QueueItem]
    func loadAll() async throws -> [QueueItem]
}
