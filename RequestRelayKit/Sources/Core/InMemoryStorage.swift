//
//  InMemoryStorage.swift
//  RequestRelay
//
//  Created by Artem Mkrtchyan on 8/22/25.
//

import Foundation

actor InMemoryStorage: Storage {

    private var items: [UUID: QueueItem] = [:]
    private let lock = NSLock()  // protects `items`
    
    func save(_ item: QueueItem) throws {
        lock.lock(); defer { lock.unlock() }
        items[item.id] = item
    }

    func loadReady(limit: Int, now: Date) throws -> [QueueItem] {
        lock.lock(); defer { lock.unlock() }
        let ready = items.values.filter { i in
            (i.state == .pending || i.state == .delayed) && i.nextAttemptAt <= now
        }
        .sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            if a.nextAttemptAt != b.nextAttemptAt { return a.nextAttemptAt < b.nextAttemptAt }
            if a.envelope.createdAt != b.envelope.createdAt { return a.envelope.createdAt < b.envelope.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
        return Array(ready.prefix(limit))
    }

    func update(_ item: QueueItem) throws {
        lock.lock(); defer { lock.unlock() }
        items[item.id] = item
    }

    func delete(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        items.removeValue(forKey: id)
    }

    func countActive() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return items.values.reduce(into: 0) { count, i in
            switch i.state {
            case .pending, .inFlight, .delayed: count += 1
            default: break
            }
        }
    }

    func loadByDedupeKey(_ key: String) throws -> [QueueItem] {
        lock.lock(); defer { lock.unlock() }
        return items.values.filter { $0.envelope.dedupeKey == key }
    }
    
    func loadAll() throws -> [QueueItem] {
        Array(items.values)
    }
}
