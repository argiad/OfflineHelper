//
//  RequestRelay.swift
//  RequestRelay
//
//  Created by Artem Mkrtchyan on 8/22/25.
//
import Foundation
import Combine
import SwiftData
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// The main relay and management class for offline/online request handling and module coordination.
/// Uses a singleton pattern for shared access and supports configuration through `Configuration`.
public final class RequestRelay {
    
    /// The shared singleton instance of `RequestRelay`, accessed on the main actor for thread safety.
    @MainActor public private(set) static var shared: RequestRelaying = RequestRelay()
    @MainActor internal static var _shared: RequestRelayingInternal {
        RequestRelay.shared as! RequestRelayingInternal
    }
    
    /// Redefines the shared singleton instance with a custom configuration.
    /// - Parameter configuration: The new configuration to apply.
    /// This method is main actor isolated for thread safety.
    @MainActor public static func redefineShared(configuration: Configuration) {
        RequestRelay.shared = RequestRelay(configuration: configuration)
    }
    
    /// The configuration object that defines parameters and storage type for the request relay.
    public var configuration: Configuration
    
    private var mainFramework: RRFramework!
    private var storage: Storage!
    private var worker: WorkerProtocol!
    private var reachability: NWReachability!
    
    /// Initializes the `RequestRelay` with a given configuration.
    /// This creates and configures all internal subsystems including storage selection and worker setup.
    /// - Parameter configuration: The configuration to use. Defaults to an empty `Configuration`.
    @MainActor
    private init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        
        // Crete Storage
        switch configuration.storageType {
        case .inMemory:
            self.storage = InMemoryStorage()
        case .swiftData:
            self.storage = (try? SwiftDataStorage.makeDefault()) ?? InMemoryStorage()
        case .custom(let model):
            self.storage = SwiftDataStorage.makeWithModelContainer(model)
        }
        self.reachability = NWReachability()
        
        //Crete worker
        let workerConfig = WorkerConfig(storage: storage,
                                        transport: URLSessionTransport(),
                                        reachability: reachability,
                                        clock: SystemClock(),
                                        logger: OSLogger())
        self.worker = Worker(cfg: workerConfig)
        
        
        // Modules initialization
        configuration._modules.forEach{ module in
            switch module {
            case .core:
                self.mainFramework = RRFramework(worker: worker, reachability: reachability)
            case .backgroundScheduler:
                RequestRelayBackground.register(identifier: configuration.backgriundTaskId) 
            }
        }
    }
    
    func pendingCountAsync() async -> Int {
        (try? await storage.countActive()) ?? 0
    }
}

extension RequestRelay: RequestRelaying {
    /// A publisher that emits updates to the running state of the request relay.
    public var isRunningPublisher: Published<Bool>.Publisher { mainFramework.$isRunning }
    /// A publisher that emits updates to the paused state of the request relay.
    public var isPausedPublisher: Published<Bool>.Publisher { mainFramework.$isPaused }
    
    public var isOnlinePublisher: Published<Bool>.Publisher { mainFramework.$isOnline }
    /// A publisher that emits updates to the current status of the request relay.
    public var currentStatusPublisher: Published<RRStatus>.Publisher { mainFramework.$currentStatus }
    
    public func listSavedRequests() async -> [OfflineRequest] {
        return (try? await storage.loadAll().map { $0.envelope }) ?? []
    }
    
    /// Starts processing requests and activates the relay.
    public func start() {
        mainFramework.start()
    }
    
    /// Stops processing requests and deactivates the relay.
    public func stop() {
        mainFramework.stop()
    }
    
    /// Sets the online/offline state of the relay.
    /// - Parameter online: Pass `true` to mark as online, `false` to mark as offline.
    public func setOnline(_ online: Bool) {
        mainFramework.setOnline(online)
    }
    
    /// Enqueues a new offline request for processing.
    /// - Parameter request: The offline request to enqueue.
    public func enqueue(_ request: OfflineRequest) {
        mainFramework.enqueue(request)
    }
    
    public func pause() {
        mainFramework.pause()
    }
    
    @MainActor
    public static func installBackgroundSchedulerIfNeeded(backgriundTaskId: String? = nil) {
            guard let backgriundTaskId = backgriundTaskId else { return }
            RequestRelayBackground.register(identifier: backgriundTaskId)
        }
}

extension RequestRelay: @MainActor RequestRelayingInternal {
    var backgroundTaskIdentifier: String { configuration.backgriundTaskId }
    
#if canImport(BackgroundTasks)
    
    @MainActor
    internal func handleBackgroundTask(_ task: BGProcessingTask,
                                       identifier: String,
                                       reschedule: @escaping (_ id: String) -> Void,
                                       clearFutureMarker: @escaping (_ id: String) -> Void) {
        // Don’t run forever if the system is about to terminate us.
        task.expirationHandler = { [weak self] in
            self?.pause()
        }
        
        Task { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            
            // Kick the relay (reachability/event-driven).
            self.start()
            
            // Give it a tiny window to spin up I/O.
            try? await Task.sleep(for: .seconds(6))
            
            // Ask for the current count (async).
            let pending = await self.pendingCountAsync()
            
            if pending > 0 {
                reschedule(identifier)
            } else {
                clearFutureMarker(identifier)
            }
            
            task.setTaskCompleted(success: true)
        }
    }
#endif

    
}

internal protocol RequestRelayingInternal {
    var backgroundTaskIdentifier: String { get }
    
#if canImport(BackgroundTasks)
    func handleBackgroundTask(_ task: BGProcessingTask,
                              identifier: String,
                              reschedule: @escaping (_ id: String) -> Void,
                              clearFutureMarker: @escaping (_ id: String) -> Void)
#endif
    
}

// MARK: - Main protocol

/// Protocol defining the main API contract for controlling the request relay
/// and observing its status updates.
public protocol RequestRelaying{
    /// A publisher that emits the current running state of the relay.
    var isRunningPublisher: Published<Bool>.Publisher { get }
    /// A publisher that emits the current paused state of the relay.
    var isPausedPublisher: Published<Bool>.Publisher { get }
    var isOnlinePublisher: Published<Bool>.Publisher { get }
    /// A publisher that emits the current detailed status of the relay.
    var currentStatusPublisher: Published<RRStatus>.Publisher { get }
    
    func listSavedRequests() async -> [OfflineRequest]
    
    /// Starts the request relay.
    func start()
    /// Stops the request relay.
    func stop()
    /// Updates the online/offline status.
    /// - Parameter online: Online state to set.
    func setOnline(_ online: Bool)
    /// Adds an offline request to the processing queue.
    /// - Parameter request: The request to enqueue.
    func enqueue(_ request: OfflineRequest)
    
    func pause()
    
}

// MARK: - Utility structures

/// Configuration settings for `RequestRelay` defining behavior, logging, storage, and modules.
public struct Configuration {
    /// Enable debug mode for additional logging.
    public var debugMode: Bool = false
    
    /// Logging level for the framework.
    public var logLevel: LogLevel = .info
    
    /// Enable caching for improved performance.
    public var cacheEnabled: Bool = true
    
    /// Storage strategy type used by the relay.
    public var storageType: StorageType = .inMemory
    
    internal var _modules: Set<ConfigurateModule> = [.core,.backgroundScheduler]
    
    /// Enables a specified module in the request relay configuration.
    /// - Parameter module: The module to enable.
    public mutating func enableModule(_ module: ConfigurateModule) {
        _modules.insert(module)
    }
    
    public var backgriundTaskId: String = "request-relay.sync"
    
    /// Creates a default configuration instance.
    public init(debugMode: Bool = false, logLevel: LogLevel = .info, cacheEnabled: Bool = true, storageType: StorageType = .inMemory) {
        
    }
}

/// Enum representing storage strategies available for caching requests.
public enum StorageType {
    /// Store requests in memory only.
    case inMemory
    /// Use SwiftData persistent storage.
    case swiftData
    /// Use a custom `ModelContainer` for storage.
    case custom(model: ModelContainer)
}

/// Log levels used by the framework for controlling log verbosity.
public enum LogLevel: String, CaseIterable {
    /// Debug level, most verbose logging.
    case debug = "DEBUG"
    /// Informational messages.
    case info = "INFO"
    /// Warnings indicating potential issues.
    case warning = "WARNING"
    /// Errors indicating failures.
    case error = "ERROR"
}

/// Modules that can be configured and enabled in the request relay.
public enum ConfigurateModule {
    /// Core module providing basic request relay functionality.
    case core
    case backgroundScheduler
}

/// Represents the various states of the request relay.
public enum RRStatus: Equatable {
    /// Relay is idle and not processing requests.
    case idle
    /// Relay is actively running.
    case running
    /// Relay is paused.
    case paused
    /// Relay has been stopped.
    case stopped
    /// Relay encountered an error.
    /// - Parameter EquatableError: The error encountered.
    case error(EquatableError)
}

/// A wrapper for errors that provides equatable conformance based on localized descriptions.
public struct EquatableError: Error, Equatable {
    private let wrapped: Error
    
    /// Initializes the wrapper with a given error.
    /// - Parameter error: The error to wrap.
    init(_ error: Error) { self.wrapped = error }
    
    /// Equality is determined by comparing localized descriptions of wrapped errors.
    public static func == (lhs: EquatableError, rhs: EquatableError) -> Bool {
        lhs.wrapped.localizedDescription == rhs.wrapped.localizedDescription
    }
}
