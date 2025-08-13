import Foundation
import os.log

// MARK: - Watch Sync Service Implementation

class WatchSyncService: NSObject, WatchSyncServiceProtocol {
    // MARK: - Properties
    
    private let connectivityService: WatchConnectivityServiceProtocol
    private let cacheService: WatchCacheServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "Sync")
    
    // Sync state
    private var _syncStatus: WatchSyncStatus = .idle
    private var _lastSyncTime: Date?
    private var pendingSyncQueue: [SyncOperation] = []
    private var isProcessingSyncs = false
    
    // Delegates
    private var delegates: [WeakSyncDelegate] = []
    
    // Sync configuration
    private let maxRetryAttempts = 3
    private let syncTimeout: TimeInterval = 30.0
    private let batchSyncInterval: TimeInterval = 60.0 // 1 minute
    
    // Background sync timer
    private var syncTimer: Timer?
    
    // Conflict resolution
    private var conflictResolver: SyncConflictResolver
    
    // MARK: - Initialization
    
    init(connectivityService: WatchConnectivityServiceProtocol, cacheService: WatchCacheServiceProtocol) {
        self.connectivityService = connectivityService
        self.cacheService = cacheService
        self.conflictResolver = SyncConflictResolver()
        super.init()
        
        connectivityService.setDelegate(self)
        setupSyncTimer()
        loadPendingOperations()
        
        logger.info("WatchSyncService initialized")
    }
    
    // MARK: - Public Properties
    
    var lastSyncTime: Date? {
        return _lastSyncTime
    }
    
    var syncStatus: WatchSyncStatus {
        return _syncStatus
    }
    
    // MARK: - Sync Operations
    
    func syncAll() async -> Bool {
        logger.info("Starting full sync operation")
        
        setSyncStatus(.syncing)
        notifyDelegates { $0.didStartSync(type: .all) }
        
        do {
            // Sync in order of priority
            let courseSuccess = await syncCourseData()
            let roundSuccess = await syncActiveRound()
            let scorecardSuccess = await syncScorecard()
            
            let overallSuccess = courseSuccess && roundSuccess && scorecardSuccess
            
            if overallSuccess {
                _lastSyncTime = Date()
                setSyncStatus(.completed(Date()))
                await cacheService.store(_lastSyncTime!, forKey: "LastSyncTime")
            } else {
                let error = WatchSyncError.partialSyncFailure
                setSyncStatus(.failed(error))
                logger.error("Full sync completed with errors")
            }
            
            notifyDelegates { $0.didCompleteSync(type: .all, success: overallSuccess) }
            
            logger.info("Full sync operation completed: \(overallSuccess ? "success" : "partial failure")")
            return overallSuccess
            
        } catch {
            setSyncStatus(.failed(error))
            notifyDelegates { $0.didCompleteSync(type: .all, success: false) }
            logger.error("Full sync failed: \(error.localizedDescription)")
            return false
        }
    }
    
    func syncCourseData() async -> Bool {
        logger.debug("Syncing course data")
        
        let operation = SyncOperation(
            id: UUID().uuidString,
            type: .course,
            priority: .high,
            timestamp: Date(),
            retryCount: 0,
            data: nil
        )
        
        return await executeSyncOperation(operation)
    }
    
    func syncActiveRound() async -> Bool {
        logger.debug("Syncing active round")
        
        // Get current round from cache
        guard let activeRound = await cacheService.getCachedActiveRound() else {
            logger.debug("No active round to sync")
            return true // Not an error if no round exists
        }
        
        let operation = SyncOperation(
            id: UUID().uuidString,
            type: .activeRound,
            priority: .high,
            timestamp: Date(),
            retryCount: 0,
            data: activeRound
        )
        
        return await executeSyncOperation(operation)
    }
    
    func syncScorecard() async -> Bool {
        logger.debug("Syncing scorecard")
        
        let operation = SyncOperation(
            id: UUID().uuidString,
            type: .scorecard,
            priority: .medium,
            timestamp: Date(),
            retryCount: 0,
            data: nil
        )
        
        return await executeSyncOperation(operation)
    }
    
    // MARK: - Pending Sync Management
    
    func hasPendingSyncData() -> Bool {
        return !pendingSyncQueue.isEmpty
    }
    
    func processPendingSyncs() async {
        guard !isProcessingSyncs && !pendingSyncQueue.isEmpty else {
            logger.debug("No pending syncs to process or already processing")
            return
        }
        
        isProcessingSyncs = true
        logger.info("Processing \(pendingSyncQueue.count) pending sync operations")
        
        // Sort by priority and timestamp
        pendingSyncQueue.sort { operation1, operation2 in
            if operation1.priority.rawValue != operation2.priority.rawValue {
                return operation1.priority.rawValue > operation2.priority.rawValue
            }
            return operation1.timestamp < operation2.timestamp
        }
        
        var completedOperations: [String] = []
        
        for operation in pendingSyncQueue {
            let success = await executeSyncOperation(operation)
            
            if success {
                completedOperations.append(operation.id)
            } else if operation.retryCount >= maxRetryAttempts {
                logger.warning("Operation \(operation.id) exceeded max retry attempts, removing from queue")
                completedOperations.append(operation.id)
            } else {
                // Increment retry count for failed operation
                if let index = pendingSyncQueue.firstIndex(where: { $0.id == operation.id }) {
                    pendingSyncQueue[index].retryCount += 1
                }
            }
        }
        
        // Remove completed operations
        pendingSyncQueue.removeAll { completedOperations.contains($0.id) }
        
        // Save updated pending operations
        await savePendingOperations()
        
        isProcessingSyncs = false
        logger.info("Completed processing pending syncs, \(pendingSyncQueue.count) operations remaining")
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: WatchSyncDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        delegates.append(WeakSyncDelegate(delegate))
        delegates.removeAll { $0.delegate == nil }
        logger.debug("Added sync delegate")
    }
    
    func removeDelegate(_ delegate: WatchSyncDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        logger.debug("Removed sync delegate")
    }
    
    // MARK: - Private Helper Methods
    
    private func setSyncStatus(_ status: WatchSyncStatus) {
        _syncStatus = status
        logger.debug("Sync status changed to: \(status)")
    }
    
    private func executeSyncOperation(_ operation: SyncOperation) async -> Bool {
        logger.debug("Executing sync operation: \(operation.type), ID: \(operation.id)")
        
        notifyDelegates { $0.didStartSync(type: operation.type) }
        
        do {
            let success = try await performSyncOperation(operation)
            
            if success {
                logger.debug("Sync operation completed successfully: \(operation.id)")
            } else {
                logger.warning("Sync operation failed: \(operation.id)")
                // Add to pending queue for retry if not already there
                if !pendingSyncQueue.contains(where: { $0.id == operation.id }) {
                    pendingSyncQueue.append(operation)
                    await savePendingOperations()
                }
            }
            
            notifyDelegates { $0.didCompleteSync(type: operation.type, success: success) }
            return success
            
        } catch {
            logger.error("Sync operation error: \(error.localizedDescription)")
            
            // Add to pending queue for retry
            if !pendingSyncQueue.contains(where: { $0.id == operation.id }) {
                pendingSyncQueue.append(operation)
                await savePendingOperations()
            }
            
            notifyDelegates { $0.didCompleteSync(type: operation.type, success: false) }
            return false
        }
    }
    
    private func performSyncOperation(_ operation: SyncOperation) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            let timeoutTask = DispatchWorkItem {
                logger.warning("Sync operation timed out: \(operation.id)")
                continuation.resume(returning: false)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + syncTimeout, execute: timeoutTask)
            
            switch operation.type {
            case .course:
                syncCourseDataInternal { success in
                    timeoutTask.cancel()
                    continuation.resume(returning: success)
                }
                
            case .activeRound:
                if let round = operation.data as? ActiveGolfRound {
                    syncActiveRoundInternal(round) { success in
                        timeoutTask.cancel()
                        continuation.resume(returning: success)
                    }
                } else {
                    timeoutTask.cancel()
                    continuation.resume(returning: false)
                }
                
            case .scorecard:
                syncScorecardInternal { success in
                    timeoutTask.cancel()
                    continuation.resume(returning: success)
                }
                
            case .all:
                // This should not be called directly
                timeoutTask.cancel()
                continuation.resume(returning: false)
            }
        }
    }
    
    private func syncCourseDataInternal(completion: @escaping (Bool) -> Void) {
        // Request current course information from iPhone
        connectivityService.requestCurrentRound()
        
        // Simulate success for now - in real implementation, we'd wait for the response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion(true)
        }
    }
    
    private func syncActiveRoundInternal(_ round: ActiveGolfRound, completion: @escaping (Bool) -> Void) {
        // Send active round update to iPhone
        connectivityService.sendActiveRoundUpdate(round)
        
        // Simulate success for now - in real implementation, we'd wait for confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            completion(true)
        }
    }
    
    private func syncScorecardInternal(completion: @escaping (Bool) -> Void) {
        // Request scorecard updates from iPhone
        connectivityService.requestCurrentRound()
        
        // Simulate success for now
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            completion(true)
        }
    }
    
    // MARK: - Timer Management
    
    private func setupSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: batchSyncInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.processPendingSyncs()
            }
        }
        logger.debug("Sync timer started with interval: \(batchSyncInterval)s")
    }
    
    private func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
        logger.debug("Sync timer stopped")
    }
    
    // MARK: - Persistence
    
    private func savePendingOperations() async {
        await cacheService.store(pendingSyncQueue, forKey: "PendingSyncOperations")
        logger.debug("Saved \(pendingSyncQueue.count) pending sync operations")
    }
    
    private func loadPendingOperations() {
        Task {
            if let operations = await cacheService.retrieve([SyncOperation].self, forKey: "PendingSyncOperations") {
                pendingSyncQueue = operations
                logger.debug("Loaded \(pendingSyncQueue.count) pending sync operations")
            }
            
            if let lastSync = await cacheService.retrieve(Date.self, forKey: "LastSyncTime") {
                _lastSyncTime = lastSync
                logger.debug("Loaded last sync time: \(lastSync)")
            }
        }
    }
    
    // MARK: - Cleanup
    
    private func notifyDelegates<T>(_ action: (WatchSyncDelegate) -> T) {
        DispatchQueue.main.async {
            self.delegates.forEach { weakDelegate in
                if let delegate = weakDelegate.delegate {
                    _ = action(delegate)
                }
            }
            
            // Clean up nil references
            self.delegates.removeAll { $0.delegate == nil }
        }
    }
    
    deinit {
        stopSyncTimer()
        logger.debug("WatchSyncService deinitialized")
    }
}

// MARK: - WatchConnectivityDelegate Implementation

extension WatchSyncService: WatchConnectivityDelegate {
    func didReceiveActiveRoundUpdate(_ round: ActiveGolfRound) {
        logger.info("Received active round update via sync")
        
        // Handle potential conflicts
        Task {
            if let cachedRound = await cacheService.getCachedActiveRound() {
                let resolvedRound = conflictResolver.resolveActiveRoundConflict(
                    local: cachedRound,
                    remote: round
                )
                await cacheService.cacheActiveRound(resolvedRound)
                
                notifyDelegates { delegate in
                    delegate.didReceiveSyncData(type: .activeRound, data: resolvedRound)
                }
            } else {
                await cacheService.cacheActiveRound(round)
                
                notifyDelegates { delegate in
                    delegate.didReceiveSyncData(type: .activeRound, data: round)
                }
            }
        }
    }
    
    func didReceiveCourseData(_ course: SharedGolfCourse) {
        logger.info("Received course data via sync")
        
        Task {
            await cacheService.cacheCourse(course)
            
            notifyDelegates { delegate in
                delegate.didReceiveSyncData(type: .course, data: course)
            }
        }
    }
    
    func didReceiveScoreUpdate(_ scorecard: SharedScorecard) {
        logger.info("Received scorecard update via sync")
        
        notifyDelegates { delegate in
            delegate.didReceiveSyncData(type: .scorecard, data: scorecard)
        }
    }
}

// MARK: - Sync Conflict Resolver

class SyncConflictResolver {
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "SyncConflict")
    
    func resolveActiveRoundConflict(local: ActiveGolfRound, remote: ActiveGolfRound) -> ActiveGolfRound {
        logger.info("Resolving active round conflict: local hole \(local.currentHole), remote hole \(remote.currentHole)")
        
        // Use the round with the most recent activity (higher hole number or more scores)
        if remote.currentHole > local.currentHole {
            logger.debug("Using remote round (more advanced)")
            return remote
        } else if local.currentHole > remote.currentHole {
            logger.debug("Using local round (more advanced)")
            return local
        } else {
            // Same hole, use the one with more scores
            if remote.scores.count > local.scores.count {
                logger.debug("Using remote round (more scores)")
                return remote
            } else {
                logger.debug("Using local round (same or more scores)")
                return local
            }
        }
    }
    
    func resolveScorecardConflict(local: SharedScorecard, remote: SharedScorecard) -> SharedScorecard {
        logger.info("Resolving scorecard conflict")
        
        // Use the most recently updated scorecard
        if remote.updatedAt > local.updatedAt {
            logger.debug("Using remote scorecard (more recent)")
            return remote
        } else {
            logger.debug("Using local scorecard (same or more recent)")
            return local
        }
    }
}

// MARK: - Supporting Types

struct SyncOperation: Codable {
    let id: String
    let type: WatchSyncType
    let priority: SyncPriority
    let timestamp: Date
    var retryCount: Int
    let data: ActiveGolfRound? // Only used for active round syncs
    
    enum SyncPriority: Int, Codable {
        case low = 1
        case medium = 2
        case high = 3
    }
}

enum WatchSyncError: Error, LocalizedError {
    case partialSyncFailure
    case connectionTimeout
    case dataCorruption
    case conflictResolutionFailed
    
    var errorDescription: String? {
        switch self {
        case .partialSyncFailure:
            return "Some sync operations failed"
        case .connectionTimeout:
            return "Sync operation timed out"
        case .dataCorruption:
            return "Sync data is corrupted"
        case .conflictResolutionFailed:
            return "Failed to resolve sync conflicts"
        }
    }
}

private struct WeakSyncDelegate {
    weak var delegate: WatchSyncDelegate?
    
    init(_ delegate: WatchSyncDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Mock Watch Sync Service

class MockWatchSyncService: WatchSyncServiceProtocol {
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "MockSync")
    private var delegates: [WeakSyncDelegate] = []
    
    private var _lastSyncTime: Date?
    private var _syncStatus: WatchSyncStatus = .idle
    private var _hasPendingData = false
    
    init() {
        _lastSyncTime = Date().addingTimeInterval(-300) // 5 minutes ago
        logger.info("MockWatchSyncService initialized")
    }
    
    var lastSyncTime: Date? { _lastSyncTime }
    var syncStatus: WatchSyncStatus { _syncStatus }
    
    func syncAll() async -> Bool {
        logger.debug("Mock sync all")
        _syncStatus = .syncing
        
        // Simulate sync delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        _lastSyncTime = Date()
        _syncStatus = .completed(Date())
        _hasPendingData = false
        
        return true
    }
    
    func syncCourseData() async -> Bool {
        logger.debug("Mock sync course data")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        return true
    }
    
    func syncActiveRound() async -> Bool {
        logger.debug("Mock sync active round")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        return true
    }
    
    func syncScorecard() async -> Bool {
        logger.debug("Mock sync scorecard")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        return true
    }
    
    func hasPendingSyncData() -> Bool {
        return _hasPendingData
    }
    
    func processPendingSyncs() async {
        logger.debug("Mock process pending syncs")
        _hasPendingData = false
    }
    
    func setDelegate(_ delegate: WatchSyncDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        delegates.append(WeakSyncDelegate(delegate))
    }
    
    func removeDelegate(_ delegate: WatchSyncDelegate) {
        delegates.removeAll { $0.delegate === delegate }
    }
    
    // Mock control methods
    func setPendingSyncData(_ hasPending: Bool) {
        _hasPendingData = hasPending
    }
    
    func simulateSyncFailure() {
        _syncStatus = .failed(WatchSyncError.connectionTimeout)
    }
}