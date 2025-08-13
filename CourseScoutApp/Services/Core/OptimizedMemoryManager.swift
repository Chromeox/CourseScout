import Foundation
import Combine
import os.log

// MARK: - Optimized Memory Manager

@MainActor
class OptimizedMemoryManager: ObservableObject {
    
    // MARK: - Properties
    
    static let shared = OptimizedMemoryManager()
    
    private let logger = Logger(subsystem: "GolfFinder.Performance", category: "MemoryManager")
    
    // Memory monitoring
    @Published var currentMemoryUsage: MemoryUsage = MemoryUsage()
    @Published var memoryPressureLevel: MemoryPressureLevel = .normal
    @Published var memoryWarnings: [MemoryWarning] = []
    
    // Subscription management
    private var activeSubscriptions: Set<String> = []
    private var subscriptionPriorities: [String: SubscriptionPriority] = [:]
    private var subscriptionMetadata: [String: SubscriptionMetadata] = [:]
    
    // Memory pools for reusable objects
    private let coursePool = ObjectPool<GolfCourse>(maxSize: 100)
    private let leaderboardEntryPool = ObjectPool<LeaderboardEntry>(maxSize: 500)
    private let healthMetricsPool = ObjectPool<GolfHealthMetrics>(maxSize: 50)
    
    // Cleanup scheduling
    private var memoryCleanupTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    
    // Configuration
    private let memoryWarningThreshold: UInt64 = 150 * 1024 * 1024 // 150MB
    private let criticalMemoryThreshold: UInt64 = 200 * 1024 * 1024 // 200MB
    private let cleanupInterval: TimeInterval = 30.0 // 30 seconds
    
    // MARK: - Initialization
    
    private init() {
        setupMemoryMonitoring()
        setupAutomaticCleanup()
        logger.info("OptimizedMemoryManager initialized")
    }
    
    // MARK: - Memory Monitoring
    
    func updateMemoryUsage() {
        let usage = getCurrentMemoryUsage()
        currentMemoryUsage = usage
        
        // Update pressure level
        let newPressureLevel = determinePressureLevel(usage: usage)
        if newPressureLevel != memoryPressureLevel {
            memoryPressureLevel = newPressureLevel
            logger.warning("Memory pressure level changed to: \(newPressureLevel)")
            
            if newPressureLevel == .high || newPressureLevel == .critical {
                Task {
                    await performEmergencyCleanup()
                }
            }
        }
    }
    
    func getCurrentMemoryUsage() -> MemoryUsage {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return MemoryUsage()
        }
        
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = UInt64(info.resident_size)
        
        return MemoryUsage(
            totalPhysical: physicalMemory,
            usedByApp: usedMemory,
            availablePhysical: physicalMemory - usedMemory,
            memoryPressure: Double(usedMemory) / Double(physicalMemory)
        )
    }
    
    // MARK: - Subscription Management
    
    func registerSubscription(
        id: String,
        type: SubscriptionType,
        priority: SubscriptionPriority,
        estimatedMemoryUsage: UInt64,
        cleanupHandler: @escaping () async -> Void
    ) {
        activeSubscriptions.insert(id)
        subscriptionPriorities[id] = priority
        subscriptionMetadata[id] = SubscriptionMetadata(
            id: id,
            type: type,
            priority: priority,
            estimatedMemoryUsage: estimatedMemoryUsage,
            createdAt: Date(),
            lastActivity: Date(),
            cleanupHandler: cleanupHandler
        )
        
        logger.debug("Registered subscription: \(id) (\(type), \(priority))")
        
        // Check if we need to clean up low-priority subscriptions
        if memoryPressureLevel == .high || memoryPressureLevel == .critical {
            Task {
                await cleanupLowPrioritySubscriptions()
            }
        }
    }
    
    func unregisterSubscription(id: String) {
        activeSubscriptions.remove(id)
        subscriptionPriorities.removeValue(forKey: id)
        subscriptionMetadata.removeValue(forKey: id)
        
        logger.debug("Unregistered subscription: \(id)")
    }
    
    func updateSubscriptionActivity(id: String) {
        subscriptionMetadata[id]?.lastActivity = Date()
    }
    
    // MARK: - Object Pool Management
    
    func borrowCourse() -> GolfCourse? {
        return coursePool.borrow()
    }
    
    func returnCourse(_ course: GolfCourse) {
        coursePool.return(course)
    }
    
    func borrowLeaderboardEntry() -> LeaderboardEntry? {
        return leaderboardEntryPool.borrow()
    }
    
    func returnLeaderboardEntry(_ entry: LeaderboardEntry) {
        leaderboardEntryPool.return(entry)
    }
    
    func borrowHealthMetrics() -> GolfHealthMetrics? {
        return healthMetricsPool.borrow()
    }
    
    func returnHealthMetrics(_ metrics: GolfHealthMetrics) {
        healthMetricsPool.return(metrics)
    }
    
    // MARK: - Memory Optimization
    
    func performMemoryOptimization() async {
        logger.info("Starting memory optimization")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let initialMemory = getCurrentMemoryUsage()
        
        // 1. Clean up expired subscriptions
        await cleanupExpiredSubscriptions()
        
        // 2. Optimize object pools
        optimizeObjectPools()
        
        // 3. Request cache cleanup from services
        await requestCacheCleanup()
        
        // 4. Trim object pools
        trimObjectPools()
        
        // 5. Force garbage collection hint
        autoreleasepool {
            // This encourages garbage collection
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let finalMemory = getCurrentMemoryUsage()
        let savedMemory = Int64(initialMemory.usedByApp) - Int64(finalMemory.usedByApp)
        
        logger.info("Memory optimization completed in \(String(format: "%.3f", endTime - startTime))s, saved \(ByteCountFormatter().string(fromByteCount: savedMemory))")
        
        updateMemoryUsage()
    }
    
    func performEmergencyCleanup() async {
        logger.warning("Performing emergency memory cleanup")
        
        // More aggressive cleanup for emergency situations
        
        // 1. Stop all low-priority subscriptions
        await stopLowPrioritySubscriptions()
        
        // 2. Clear all object pools
        clearObjectPools()
        
        // 3. Request immediate cache cleanup
        await requestImmediateCacheCleanup()
        
        // 4. Add memory warning
        addMemoryWarning(
            level: .critical,
            message: "Emergency memory cleanup performed",
            recommendation: "Consider closing unused features"
        )
        
        updateMemoryUsage()
    }
    
    // MARK: - Memory Warnings
    
    func addMemoryWarning(level: MemoryWarning.Level, message: String, recommendation: String) {
        let warning = MemoryWarning(
            id: UUID().uuidString,
            level: level,
            message: message,
            recommendation: recommendation,
            timestamp: Date()
        )
        
        memoryWarnings.append(warning)
        
        // Keep only the last 10 warnings
        if memoryWarnings.count > 10 {
            memoryWarnings.removeFirst(memoryWarnings.count - 10)
        }
        
        logger.warning("Memory warning: \(message)")
    }
    
    func clearMemoryWarnings() {
        memoryWarnings.removeAll()
    }
    
    // MARK: - Statistics
    
    func getMemoryStatistics() -> MemoryStatistics {
        return MemoryStatistics(
            currentUsage: currentMemoryUsage,
            pressureLevel: memoryPressureLevel,
            activeSubscriptions: activeSubscriptions.count,
            objectPoolStats: ObjectPoolStats(
                coursePoolSize: coursePool.size,
                leaderboardPoolSize: leaderboardEntryPool.size,
                healthMetricsPoolSize: healthMetricsPool.size
            ),
            warnings: memoryWarnings
        )
    }
}

// MARK: - Private Methods

private extension OptimizedMemoryManager {
    
    func setupMemoryMonitoring() {
        // Monitor memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleSystemMemoryWarning()
                }
            }
            .store(in: &subscriptions)
        
        // Monitor app lifecycle
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.performBackgroundCleanup()
                }
            }
            .store(in: &subscriptions)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateMemoryUsage()
                }
            }
            .store(in: &subscriptions)
    }
    
    func setupAutomaticCleanup() {
        memoryCleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performRoutineCleanup()
            }
        }
    }
    
    func handleSystemMemoryWarning() {
        addMemoryWarning(
            level: .high,
            message: "System memory warning received",
            recommendation: "Some features may be temporarily disabled"
        )
        
        Task {
            await performEmergencyCleanup()
        }
    }
    
    func performBackgroundCleanup() async {
        logger.debug("Performing background cleanup")
        
        // More aggressive cleanup when app is backgrounded
        await cleanupInactiveSubscriptions()
        clearObjectPools()
    }
    
    func performRoutineCleanup() async {
        updateMemoryUsage()
        
        // Only perform routine cleanup if memory pressure is moderate or higher
        if memoryPressureLevel == .moderate || memoryPressureLevel == .high {
            await performMemoryOptimization()
        }
    }
    
    func determinePressureLevel(usage: MemoryUsage) -> MemoryPressureLevel {
        if usage.usedByApp > criticalMemoryThreshold {
            return .critical
        } else if usage.usedByApp > memoryWarningThreshold {
            return .high
        } else if usage.memoryPressure > 0.7 {
            return .moderate
        } else {
            return .normal
        }
    }
    
    func cleanupExpiredSubscriptions() async {
        let now = Date()
        let expirationThreshold: TimeInterval = 300 // 5 minutes
        
        let expiredSubscriptions = subscriptionMetadata.compactMap { (id, metadata) -> String? in
            let timeSinceLastActivity = now.timeIntervalSince(metadata.lastActivity)
            return timeSinceLastActivity > expirationThreshold ? id : nil
        }
        
        for subscriptionId in expiredSubscriptions {
            if let metadata = subscriptionMetadata[subscriptionId] {
                await metadata.cleanupHandler()
                unregisterSubscription(id: subscriptionId)
            }
        }
        
        if !expiredSubscriptions.isEmpty {
            logger.debug("Cleaned up \(expiredSubscriptions.count) expired subscriptions")
        }
    }
    
    func cleanupLowPrioritySubscriptions() async {
        let lowPrioritySubscriptions = subscriptionMetadata.compactMap { (id, metadata) -> String? in
            return metadata.priority == .low ? id : nil
        }
        
        for subscriptionId in lowPrioritySubscriptions {
            if let metadata = subscriptionMetadata[subscriptionId] {
                await metadata.cleanupHandler()
                unregisterSubscription(id: subscriptionId)
            }
        }
        
        if !lowPrioritySubscriptions.isEmpty {
            logger.debug("Cleaned up \(lowPrioritySubscriptions.count) low-priority subscriptions")
        }
    }
    
    func cleanupInactiveSubscriptions() async {
        let now = Date()
        let inactivityThreshold: TimeInterval = 120 // 2 minutes
        
        let inactiveSubscriptions = subscriptionMetadata.compactMap { (id, metadata) -> String? in
            let timeSinceLastActivity = now.timeIntervalSince(metadata.lastActivity)
            return timeSinceLastActivity > inactivityThreshold && metadata.priority != .critical ? id : nil
        }
        
        for subscriptionId in inactiveSubscriptions {
            if let metadata = subscriptionMetadata[subscriptionId] {
                await metadata.cleanupHandler()
                unregisterSubscription(id: subscriptionId)
            }
        }
        
        if !inactiveSubscriptions.isEmpty {
            logger.debug("Cleaned up \(inactiveSubscriptions.count) inactive subscriptions")
        }
    }
    
    func stopLowPrioritySubscriptions() async {
        let subscriptionsToStop = subscriptionMetadata.compactMap { (id, metadata) -> String? in
            return metadata.priority == .low || metadata.priority == .normal ? id : nil
        }
        
        for subscriptionId in subscriptionsToStop {
            if let metadata = subscriptionMetadata[subscriptionId] {
                await metadata.cleanupHandler()
                unregisterSubscription(id: subscriptionId)
            }
        }
        
        logger.warning("Stopped \(subscriptionsToStop.count) low-priority subscriptions for emergency cleanup")
    }
    
    func optimizeObjectPools() {
        coursePool.optimize()
        leaderboardEntryPool.optimize()
        healthMetricsPool.optimize()
    }
    
    func trimObjectPools() {
        coursePool.trim(to: 20)
        leaderboardEntryPool.trim(to: 100)
        healthMetricsPool.trim(to: 10)
    }
    
    func clearObjectPools() {
        coursePool.clear()
        leaderboardEntryPool.clear()
        healthMetricsPool.clear()
    }
    
    func requestCacheCleanup() async {
        // Request cleanup from various services
        NotificationCenter.default.post(name: .memoryPressureCleanupRequested, object: nil)
    }
    
    func requestImmediateCacheCleanup() async {
        // Request immediate cleanup from various services
        NotificationCenter.default.post(name: .emergencyMemoryCleanupRequested, object: nil)
    }
}

// MARK: - Object Pool

private class ObjectPool<T> {
    private var objects: [T] = []
    private let maxSize: Int
    private let queue = DispatchQueue(label: "ObjectPool", attributes: .concurrent)
    
    init(maxSize: Int) {
        self.maxSize = maxSize
    }
    
    var size: Int {
        queue.sync { objects.count }
    }
    
    func borrow() -> T? {
        return queue.sync {
            guard !objects.isEmpty else { return nil }
            return objects.removeLast()
        }
    }
    
    func `return`(_ object: T) {
        queue.async(flags: .barrier) {
            guard self.objects.count < self.maxSize else { return }
            self.objects.append(object)
        }
    }
    
    func optimize() {
        queue.async(flags: .barrier) {
            // Remove objects if we're over the optimal size
            let optimalSize = self.maxSize / 2
            if self.objects.count > optimalSize {
                self.objects.removeLast(self.objects.count - optimalSize)
            }
        }
    }
    
    func trim(to size: Int) {
        queue.async(flags: .barrier) {
            if self.objects.count > size {
                self.objects.removeLast(self.objects.count - size)
            }
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) {
            self.objects.removeAll()
        }
    }
}

// MARK: - Supporting Types

struct MemoryUsage {
    let totalPhysical: UInt64
    let usedByApp: UInt64
    let availablePhysical: UInt64
    let memoryPressure: Double
    
    init() {
        self.totalPhysical = 0
        self.usedByApp = 0
        self.availablePhysical = 0
        self.memoryPressure = 0.0
    }
    
    init(totalPhysical: UInt64, usedByApp: UInt64, availablePhysical: UInt64, memoryPressure: Double) {
        self.totalPhysical = totalPhysical
        self.usedByApp = usedByApp
        self.availablePhysical = availablePhysical
        self.memoryPressure = memoryPressure
    }
    
    var formattedUsedMemory: String {
        ByteCountFormatter().string(fromByteCount: Int64(usedByApp))
    }
    
    var formattedTotalMemory: String {
        ByteCountFormatter().string(fromByteCount: Int64(totalPhysical))
    }
    
    var usagePercentage: Double {
        totalPhysical > 0 ? Double(usedByApp) / Double(totalPhysical) * 100 : 0
    }
}

enum MemoryPressureLevel: String, CaseIterable {
    case normal = "normal"
    case moderate = "moderate"
    case high = "high"
    case critical = "critical"
    
    var color: String {
        switch self {
        case .normal: return "green"
        case .moderate: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }
    
    var description: String {
        switch self {
        case .normal: return "Normal"
        case .moderate: return "Moderate Pressure"
        case .high: return "High Pressure"
        case .critical: return "Critical"
        }
    }
}

enum SubscriptionType: String, CaseIterable {
    case leaderboard = "leaderboard"
    case realTimeScores = "realtime_scores"
    case courseUpdates = "course_updates"
    case healthMetrics = "health_metrics"
    case locationUpdates = "location_updates"
    case weatherUpdates = "weather_updates"
}

enum SubscriptionPriority: String, CaseIterable {
    case critical = "critical"
    case high = "high"
    case normal = "normal"
    case low = "low"
}

struct SubscriptionMetadata {
    let id: String
    let type: SubscriptionType
    let priority: SubscriptionPriority
    let estimatedMemoryUsage: UInt64
    let createdAt: Date
    var lastActivity: Date
    let cleanupHandler: () async -> Void
}

struct MemoryWarning: Identifiable {
    let id: String
    let level: Level
    let message: String
    let recommendation: String
    let timestamp: Date
    
    enum Level: String, CaseIterable {
        case info = "info"
        case warning = "warning"
        case high = "high"
        case critical = "critical"
        
        var color: String {
            switch self {
            case .info: return "blue"
            case .warning: return "yellow"
            case .high: return "orange"
            case .critical: return "red"
            }
        }
    }
}

struct ObjectPoolStats {
    let coursePoolSize: Int
    let leaderboardPoolSize: Int
    let healthMetricsPoolSize: Int
}

struct MemoryStatistics {
    let currentUsage: MemoryUsage
    let pressureLevel: MemoryPressureLevel
    let activeSubscriptions: Int
    let objectPoolStats: ObjectPoolStats
    let warnings: [MemoryWarning]
}

// MARK: - Notification Names

extension Notification.Name {
    static let memoryPressureCleanupRequested = Notification.Name("memoryPressureCleanupRequested")
    static let emergencyMemoryCleanupRequested = Notification.Name("emergencyMemoryCleanupRequested")
}