//
//  SavedRequestListView.swift
//  OfflineHandlerDemo
//
//  Created by Artem Mkrtchyan on 8/20/25.
//

import SwiftUI
import RequestRelayKit

struct SavedRequestListView: View {
    @State private var requests: [OfflineRequest] = []
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            Group {
                if isLoading && requests.isEmpty {
                    ProgressView("Loading…")
                } else if requests.isEmpty {
                    ContentUnavailableView(
                        "No Saved Requests",
                        systemImage: "tray",
                        description: Text("Queued requests will appear here when they’re persisted by OfflineHandler.")
                    )
                } else {
                    List(requests, id: \.id) { req in
                        SavedRequestRow(req: req)
                            .listRowSeparator(.visible)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pending Sync")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await reload() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        isLoading = true
        let list = await RequestRelay.shared.listSavedRequests()
        self.requests = list.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.createdAt < $1.createdAt
        }
        isLoading = false
    }
}

private struct SavedRequestRow: View {
    let req: OfflineRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Method badge + URL
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(req.method.uppercased())
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(req.url.absoluteString)
                    .font(.subheadline).bold()
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            // Created & priority
            HStack(spacing: 12) {
                Text("Created: \(req.createdAt.formatted(date: .abbreviated, time: .shortened))")
                Text("Priority: \(req.priority)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Body preview (if UTF‑8 and non‑empty)
            if let body = req.body,
               let text = String(data: body, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            // Optional: show a single-line headers preview
            if !req.headers.isEmpty {
                Text(headersPreview(req.headers))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 6)
    }

    private func headersPreview(_ headers: [String:String]) -> String {
        // Show a compact “k=v; k=v; …” line
        headers.prefix(3).map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        + (headers.count > 3 ? " …" : "")
    }
}
