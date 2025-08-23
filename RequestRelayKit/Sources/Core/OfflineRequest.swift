//
//  OfflineRequest.swift
//  RequestRelay
//
//  Created by Artem Mkrtchyan on 8/21/25.
//

import Foundation

public struct OfflineRequest: Sendable, Codable, Equatable, Hashable {
    public let id: UUID
    public let url: URL
    public let method: String        // "GET", "POST", ...
    public let headers: [String:String]
    public let body: Data?
    public let priority: Int         // higher = earlier
    public let createdAt: Date
    public let dedupeKey: String?

    public init(id: UUID = .init(),
                url: URL,
                method: String,
                headers: [String:String] = [:],
                body: Data? = nil,
                priority: Int = 0,
                createdAt: Date = .init(),
                dedupeKey: String? = nil) {
        self.id = id
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.priority = priority
        self.createdAt = createdAt
        self.dedupeKey = dedupeKey
    }
}

public extension OfflineRequest {
    /// Initialize from a `URLRequest`.
    /// - Parameters:
    ///   - request: The URLRequest to capture.
    ///   - priority: Optional priority (defaults to 0).
    ///   - dedupeKey: Optional deduplication key.
    init?(request: URLRequest,
          priority: Int = 0,
          dedupeKey: String? = nil) {
        // Need a valid URL
        guard let url = request.url else { return nil }
        let method = request.httpMethod ?? "GET"
        
        // Extract headers as [String:String]
        var headerDict: [String:String] = [:]
        if let headers = request.allHTTPHeaderFields {
            headerDict = headers
        }

        self.init(
            url: url,
            method: method,
            headers: headerDict,
            body: request.httpBody,
            priority: priority,
            createdAt: Date(),
            dedupeKey: dedupeKey
        )
    }
}
