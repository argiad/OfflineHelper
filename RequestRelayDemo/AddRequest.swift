//
//  AddRequest.swift
//  OfflineHandlerDemo
//
//  Created by Artem Mkrtchyan on 8/20/25.
//

import SwiftUI
import SwiftData

struct AddRequestView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context

    @State private var name = ""
    @State private var method = "POST"
    @State private var url = ""
    @State private var requestBody = ""

    var body: some View {
        NavigationView {
            Form {
                TextField("Name", text: $name)
                Picker("Method", selection: $method) {
                    Text("GET").tag("GET")
                    Text("POST").tag("POST")
                }
                TextField("URL", text: $url)
                if method == "POST" {
                    TextEditor(text: $requestBody).frame(height: 100)
                }
            }
            .navigationTitle("New Request")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let query = TestQuery(
                            id: UUID(),
                            name: name,
                            method: method,
                            url: url,
                            body: requestBody.isEmpty ? nil : requestBody,
                            headers: [:]
                        )
                        context.insert(query)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
        }
    }
}
