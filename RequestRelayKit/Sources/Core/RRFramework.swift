//
//  File.swift
//  RequestRelay
//
//  Created by Artem Mkrtchyan on 8/22/25.
//

import UIKit
import Combine

internal final class RRFramework: @unchecked Sendable, ObservableObject {
    
    // MARK: - Published Properties
    @Published internal private(set) var isRunning: Bool = false
    @Published internal private(set) var isPaused: Bool = false
    @Published internal private(set) var isOnline: Bool = false
    @Published internal private(set) var currentStatus: RRStatus = .idle
    
    private var worker: WorkerProtocol!
    
    init(worker: WorkerProtocol, reachability: NWReachability) {
        self.worker = worker
        
        // reachability bridge
        Task { [weak self] in
            let stream = await reachability.changes()
            for await online in stream {
                self?.isOnline = online
                if online { await self?.worker.kick() }
            }
        }
    }
}

extension RRFramework: RRFrameworkProtocol {
    func start(){
        isRunning = true
    }
    func stop(){}
    func pause(){}
    func setOnline(_ online: Bool){
        isOnline = online
    }
    func enqueue(_ request: OfflineRequest){
        Task {
            await worker.enqueue(request)
        }
    }
}

internal protocol RRFrameworkProtocol {
    func start()
    func stop()
    func pause()
    func setOnline(_ online: Bool)
    func enqueue(_ request: OfflineRequest)
}
