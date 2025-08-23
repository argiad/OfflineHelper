//
//  RetryPolicy.swift
//  RequestRelay
//
//  Created by Artem Mkrtchyan on 8/22/25.
//

import Foundation

public struct RetryPolicy: Sendable {
    var maxAttempts: Int = 6                    // includes first try
    var baseBackoff: Duration = .seconds(1)
    var exponent: Double = 2.0
    var maxBackoff: Duration = .seconds(32)
    var retryableStatus: Set<Int> = [408, 425, 429, 500, 502, 503, 504]
    var respectRetryAfter: Bool = true
    var offlineShortCircuit: Bool = true
    
    public init() {}
    
    func backoff(for attempt: Int) -> Duration {
        // attempt: 1 → base, 2 → base*2, ...
        let powv = pow(exponent, Double(max(0, attempt - 1)))
        let seconds = min(Double(maxBackoff.components.seconds),
                          Double(baseBackoff.components.seconds) * powv)
        return .seconds(seconds)
    }
}

public enum DedupePolicy: Sendable {
    case keepAll
    case dropNewIfSameKeyExists
    case dropOldKeepNewest
}
