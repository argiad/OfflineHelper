//
//  ContentView.swift
//  OfflineHandlerDemo
//
//  Created by Artem Mkrtchyan on 8/19/25.
//

import SwiftUI
import SwiftData
import RequestRelayKit

struct ContentView: View {
    @StateObject private var offlineEvents = RequestRelayEvents(relay: RequestRelay.shared)

    @Environment(\.modelContext) private var modelContext
    init() { }
    
    var body: some View {
        TabView {
            RequestListView()
                .tabItem {
                    Label("Requests", systemImage: "plus.circle")
                }
            
            SavedRequestListView()
                .tabItem {
                    Label("Saved", systemImage: "tray.full")
                }
        }
        .environmentObject(offlineEvents)
    }

}

#Preview {
    ContentView()
        .modelContainer(for: TestQuery.self, inMemory: true)
}
