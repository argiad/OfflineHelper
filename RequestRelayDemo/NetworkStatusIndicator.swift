//
//  NetworkStatusIndicator.swift
//  OfflineHandlerDemo
//
//  Created by Artem Mkrtchyan on 8/20/25.
//

import SwiftUI

struct NetworkStatusIndicator: View {
    @EnvironmentObject var events: RequestRelayEvents

    var body: some View {
        Circle()
            .fill(events.isOnline ? .green : .red)
            .frame(width: 12, height: 12)
    }
}
