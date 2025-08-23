//
//  TestQuery.swift
//  OfflineHandlerDemo
//
//  Created by Artem Mkrtchyan on 8/20/25.
//

import Foundation
import SwiftData

@Model
final class TestQuery {
    var id: UUID
    var name: String
    var method: String
    var url: String
    var body: String?
    var headers: [String: String]
    
    init(id: UUID, name: String, method: String, url: String, body: String? = nil, headers: [String : String]) {
        self.id = id
        self.name = name
        self.method = method
        self.url = url
        self.body = body
        self.headers = headers
    }
    
}
