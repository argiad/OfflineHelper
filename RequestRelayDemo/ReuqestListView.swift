//
//  ReuqestListView.swift
//  OfflineHandlerDemo
//
//  Created by Artem Mkrtchyan on 8/20/25.
//

import SwiftUI
import SwiftData
import RequestRelayKit

struct RequestListView: View {
    @Query private var queries: [TestQuery]
    @State private var isPresentingEditor = false
    @Environment(\.modelContext) var context
    @EnvironmentObject var events: RequestRelayEvents

    var body: some View {
        NavigationView {
            List(queries) { query in
                VStack(alignment: .leading) {
                    Text(query.name).bold()
                    Text(query.url).font(.footnote)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                context.delete(query)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        Task {
                            if let url = URL(string: query.url) {
                                var request = URLRequest(url: url)
                                request.httpMethod = query.method
                                request.httpBody = query.body?.data(using: .utf8)
                                request.allHTTPHeaderFields = query.headers

                                await performResilientRequest(request, isOnline: events.isOnline)
                            }
                        }
                    } label: {
                        Label("Send", systemImage: "paperplane")
                    }
                    .tint(.blue)
                }
            }
            .navigationTitle("Test Queries")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NetworkStatusIndicator()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isPresentingEditor = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingEditor) {
                AddRequestView()
            }
        }
    }
    
    private func performResilientRequest(
        _ request: URLRequest,
        isOnline: Bool
    ) async {
        guard isOnline else {
            RequestRelay.shared.enqueue(OfflineRequest(request: request)!)
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let status = httpResponse.statusCode
                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"

                print("HTTP \(status):\n\(bodyString)")

                if status >= 400 {
                    RequestRelay.shared.enqueue(OfflineRequest(request: request)!)
                    
                }
            }
        } catch {
            print("Request failed: \(error.localizedDescription)")
            RequestRelay.shared.enqueue(OfflineRequest(request: request)!)
        }
    }
}
