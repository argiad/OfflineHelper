//
//  SwiftDataStorage.swift
//  RequestRelay
//
//  Created by Artem Mkrtchyan on 8/22/25.
//

import Foundation
import SwiftData

@ModelActor
public actor SwiftDataStorage: Storage {


    public static func makeDefault() throws -> SwiftDataStorage {
        let schema = Schema([QueueItemRecord.self])
        let storeURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("RequestRelay.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        return SwiftDataStorage(modelContainer: container)
    }

    public static func makeWithModelContainer(_ modelContainer: ModelContainer) -> SwiftDataStorage {
        SwiftDataStorage(modelContainer: modelContainer)
    }

    // Upsert
    public func save(_ item: QueueItem) throws {
        if let rec = try fetchRecord(id: item.id) {
            try rec.update(from: item)
        } else {
            let rec = try QueueItemRecord(from: item)
            modelContext.insert(rec)
        }
        try modelContext.save()
    }

    public func update(_ item: QueueItem) throws { try save(item) }

    public func delete(id: UUID) throws {
        if let rec = try fetchRecord(id: id) {
            modelContext.delete(rec)
            try modelContext.save()
        }
    }

    public func countActive() throws -> Int {
        let active: Set<String> = ["pending", "inFlight", "delayed"]
        let fd = FetchDescriptor<QueueItemRecord>(
            predicate: #Predicate { active.contains($0.stateRaw) }
        )
        return try modelContext.fetchCount(fd)
    }

    public func loadByDedupeKey(_ key: String) throws -> [QueueItem] {
        let fd = FetchDescriptor<QueueItemRecord>(
            predicate: #Predicate { $0.dedupeKey == key },
            sortBy: [
                .init(\.envelopeCreatedAt, order: .forward),
                .init(\.id, order: .forward)
            ]
        )
        return try modelContext.fetch(fd).map { try $0.asDomain() }
    }

    public func loadAll() throws -> [QueueItem] {
        let fd = FetchDescriptor<QueueItemRecord>(
            sortBy: [
                .init(\.envelopeCreatedAt, order: .forward),
                .init(\.id, order: .forward)
            ]
        )
        return try modelContext.fetch(fd).map { try $0.asDomain() }
    }

    public func loadReady(limit: Int, now: Date) throws -> [QueueItem] {
        let ok: Set<String> = ["pending", "delayed"]
        var fd = FetchDescriptor<QueueItemRecord>(
            predicate: #Predicate { ok.contains($0.stateRaw) && $0.nextAttemptAt <= now },
            sortBy: [
                .init(\.priority, order: .reverse),
                .init(\.nextAttemptAt, order: .forward),
                .init(\.envelopeCreatedAt, order: .forward),
                .init(\.id, order: .forward)
            ]
        )
        fd.fetchLimit = max(0, limit)
        return try modelContext.fetch(fd).map { try $0.asDomain() }
    }

    // Helpers
    private func fetchRecord(id: UUID) throws -> QueueItemRecord? {
        var fd = FetchDescriptor<QueueItemRecord>(
            predicate: #Predicate { $0.id == id }
        )
        fd.fetchLimit = 1

        let results: [QueueItemRecord] = try modelContext.fetch(fd)
        return results.first
    }
}

