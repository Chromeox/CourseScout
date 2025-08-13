import Foundation
import WatchKit
import os.log
import Combine

// MARK: - Watch Performance Service Protocol

protocol WatchPerformanceServiceProtocol: AnyObject {
    // Battery monitoring
    var batteryLevel: Float { get }
    var batteryState: WKInterfaceDeviceBatteryState { get }
    var isLowPowerModeEnabled: Bool { get }
    
    // Performance monitoring
    func startPerformanceMonitoring()
    func stopPerformanceMonitoring()
    func getCurrentPerformanceMetrics() -> WatchPerformanceMetrics
    func getPerformanceHistory() -> [WatchPerformanceSnapshot]
    
    // Battery optimization
    func enableBatteryOptimization()
    func disableBatteryOptimization()
    func optimizeForGolfRound()
    func optimizeForCraftTimer()
    func optimizeForLowBattery()
    
    // Adaptive performance
    func setPerformanceMode(_ mode: WatchPerformanceMode)
    func getRecommendedPerformanceMode() -> WatchPerformanceMode
    func enableAdaptivePerformance()
    func disableAdaptivePerformance()
    
    // System resource monitoring
    func getMemoryUsage() -> MemoryUsage
    func getCPUUsage() -> Double
    func getDiskUsage() -> DiskUsage
    func getNetworkUsage() -> NetworkUsage
    
    // Alerts and recommendations
    func getBatteryOptimizationRecommendations() -> [OptimizationRecommendation]
    func getPerformanceWarnings() -> [PerformanceWarning]
    
    // Delegate
    func setDelegate(_ delegate: WatchPerformanceDelegate)
    func removeDelegate(_ delegate: WatchPerformanceDelegate)
}

// MARK: - Watch Performance Delegate

protocol WatchPerformanceDelegate: AnyObject {
    func didUpdateBatteryLevel(_ level: Float)
    func didChangeBatteryState(_ state: WKInterfaceDeviceBatteryState)
    func didEnterLowPowerMode()
    func didExitLowPowerMode()
    func didDetectPerformanceIssue(_ issue: PerformanceIssue)
    func didUpdatePerformanceMetrics(_ metrics: WatchPerformanceMetrics)
    func shouldOptimizeForBattery() -> Bool
}

// Default implementations
extension WatchPerformanceDelegate {
    func didUpdateBatteryLevel(_ level: Float) {}
    func didChangeBatteryState(_ state: WKInterfaceDeviceBatteryState) {}
    func didEnterLowPowerMode() {}
    func didExitLowPowerMode() {}
    func didDetectPerformanceIssue(_ issue: PerformanceIssue) {}
    func didUpdatePerformanceMetrics(_ metrics: WatchPerformanceMetrics) {}
    func shouldOptimizeForBattery() -> Bool { return true }
}

// MARK: - Watch Performance Service Implementation

@MainActor
class WatchPerformanceService: NSObject, WatchPerformanceServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let device = WKInterfaceDevice.current()
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "Performance")
    
    // Published properties
    @Published private(set) var batteryLevel: Float = 1.0
    @Published private(set) var batteryState: WKInterfaceDeviceBatteryState = .unknown
    @Published private(set) var isLowPowerModeEnabled: Bool = false
    @Published private(set) var currentPerformanceMode: WatchPerformanceMode = .balanced
    
    // Performance monitoring
    private var isMonitoring = false
    private var performanceTimer: Timer?
    private var performanceHistory: [WatchPerformanceSnapshot] = []
    private let maxHistoryCount = 100
    
    // Battery optimization
    private var isBatteryOptimized = false
    private var isAdaptivePerformanceEnabled = true
    private var lastBatteryCheck = Date()
    private var lowBatteryThreshold: Float = 0.20 // 20%
    private var criticalBatteryThreshold: Float = 0.10 // 10%
    
    // Delegate management
    private var delegates: [WeakPerformanceDelegate] = []
    
    // Optimization state
    private var optimizationRecommendations: [OptimizationRecommendation] = []
    private var performanceWarnings: [PerformanceWarning] = []
    
    // Service dependencies tracking
    private var activeServices: Set<String> = []
    private var servicePerformanceMetrics: [String: ServicePerformanceMetrics] = [:]
    
    // MARK: - Dependencies
    
    @WatchServiceInjected(WatchHapticFeedbackServiceProtocol.self) private var hapticService
    @WatchServiceInjected(WatchNotificationServiceProtocol.self) private var notificationService
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupBatteryMonitoring()
        setupPerformanceMonitoring()
        logger.info("WatchPerformanceService initialized")
    }
    
    private func setupBatteryMonitoring() {
        // Enable battery monitoring
        device.isBatteryMonitoringEnabled = true
        
        // Get initial battery state
        updateBatteryInfo()
        
        // Set up battery state change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateChanged),
            name: NSNotification.Name.WKInterfaceDeviceBatteryStateDidChange,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryLevelChanged),
            name: NSNotification.Name.WKInterfaceDeviceBatteryLevelDidChange,
            object: nil
        )
    }
    
    private func setupPerformanceMonitoring() {
        // Start with balanced performance mode
        setPerformanceMode(.balanced)
        
        // Enable adaptive performance by default
        enableAdaptivePerformance()
    }
    
    @objc private func batteryStateChanged() {
        updateBatteryInfo()
    }
    
    @objc private func batteryLevelChanged() {
        updateBatteryInfo()
    }
    
    private func updateBatteryInfo() {
        let previousLevel = batteryLevel
        let previousState = batteryState
        
        batteryLevel = device.batteryLevel
        batteryState = device.batteryState
        
        // Check for low power mode
        let wasLowPowerMode = isLowPowerModeEnabled
        isLowPowerModeEnabled = batteryLevel < lowBatteryThreshold
        
        // Notify delegates of changes
        if previousLevel != batteryLevel {
            notifyDelegates { delegate in
                delegate.didUpdateBatteryLevel(batteryLevel)
            }
        }
        
        if previousState != batteryState {
            notifyDelegates { delegate in
                delegate.didChangeBatteryState(batteryState)
            }
        }
        
        if isLowPowerModeEnabled != wasLowPowerMode {
            if isLowPowerModeEnabled {
                notifyDelegates { delegate in
                    delegate.didEnterLowPowerMode()
                }
                handleLowBatteryMode()
            } else {
                notifyDelegates { delegate in
                    delegate.didExitLowPowerMode()
                }
                handleNormalBatteryMode()
            }
        }
        
        // Update optimization recommendations
        updateOptimizationRecommendations()
        
        logger.debug("Battery updated: \(batteryLevel * 100)% - State: \(batteryState.rawValue)")
    }
    
    // MARK: - Performance Monitoring
    
    func startPerformanceMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.collectPerformanceSnapshot()
            }
        }
        
        logger.info("Started performance monitoring")
    }
    
    func stopPerformanceMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        performanceTimer?.invalidate()
        performanceTimer = nil
        
        logger.info("Stopped performance monitoring")
    }
    
    private func collectPerformanceSnapshot() {
        let snapshot = WatchPerformanceSnapshot(
            timestamp: Date(),
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            memoryUsage: getMemoryUsage(),
            cpuUsage: getCPUUsage(),
            diskUsage: getDiskUsage(),
            networkUsage: getNetworkUsage(),
            activeServices: activeServices,
            performanceMode: currentPerformanceMode
        )
        
        performanceHistory.append(snapshot)
        
        // Limit history size
        if performanceHistory.count > maxHistoryCount {
            performanceHistory.removeFirst()
        }
        
        // Analyze performance and detect issues
        analyzePerformance(snapshot)
        
        // Update current metrics
        let currentMetrics = getCurrentPerformanceMetrics()
        notifyDelegates { delegate in
            delegate.didUpdatePerformanceMetrics(currentMetrics)
        }
    }
    
    func getCurrentPerformanceMetrics() -> WatchPerformanceMetrics {
        return WatchPerformanceMetrics(
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            memoryUsage: getMemoryUsage(),
            cpuUsage: getCPUUsage(),
            diskUsage: getDiskUsage(),
            networkUsage: getNetworkUsage(),
            activeServices: activeServices.count,
            performanceMode: currentPerformanceMode,
            isOptimized: isBatteryOptimized,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }
    
    func getPerformanceHistory() -> [WatchPerformanceSnapshot] {
        return performanceHistory
    }
    
    private func analyzePerformance(_ snapshot: WatchPerformanceSnapshot) {
        var detectedIssues: [PerformanceIssue] = []
        
        // Check memory usage
        if snapshot.memoryUsage.usedPercentage > 0.85 {
            detectedIssues.append(.highMemoryUsage(snapshot.memoryUsage.usedPercentage))
        }
        
        // Check CPU usage
        if snapshot.cpuUsage > 0.80 {
            detectedIssues.append(.highCPUUsage(snapshot.cpuUsage))
        }
        
        // Check battery drain rate
        if performanceHistory.count >= 2 {
            let previousSnapshot = performanceHistory[performanceHistory.count - 2]
            let batteryDrain = previousSnapshot.batteryLevel - snapshot.batteryLevel
            let timeInterval = snapshot.timestamp.timeIntervalSince(previousSnapshot.timestamp)
            let drainRate = batteryDrain / Float(timeInterval / 60.0) // Per minute
            
            if drainRate > 0.01 { // More than 1% per minute
                detectedIssues.append(.rapidBatteryDrain(drainRate))
            }
        }
        
        // Check for too many active services
        if activeServices.count > 6 {
            detectedIssues.append(.tooManyActiveServices(activeServices.count))
        }
        
        // Notify delegates of issues
        for issue in detectedIssues {
            notifyDelegates { delegate in
                delegate.didDetectPerformanceIssue(issue)
            }
        }
    }
    
    // MARK: - Battery Optimization
    
    func enableBatteryOptimization() {
        guard !isBatteryOptimized else { return }
        
        isBatteryOptimized = true
        
        // Apply battery optimization strategies
        applyBatteryOptimizations()
        
        logger.info("Enabled battery optimization")
    }
    
    func disableBatteryOptimization() {
        guard isBatteryOptimized else { return }
        
        isBatteryOptimized = false
        
        // Restore normal performance settings
        restoreNormalPerformance()
        
        logger.info("Disabled battery optimization")
    }
    
    func optimizeForGolfRound() {
        setPerformanceMode(.golf)
        enableBatteryOptimization()
        
        // Golf-specific optimizations
        applyGolfOptimizations()
        
        logger.info("Optimized for golf round")
    }
    
    func optimizeForCraftTimer() {
        setPerformanceMode(.timer)
        
        // Timer-specific optimizations (less aggressive than golf)
        applyTimerOptimizations()
        
        logger.info("Optimized for craft timer")
    }
    
    func optimizeForLowBattery() {
        setPerformanceMode(.batterySaver)
        enableBatteryOptimization()
        
        // Aggressive battery saving measures
        applyLowBatteryOptimizations()
        
        logger.info("Optimized for low battery")
    }
    
    private func applyBatteryOptimizations() {
        // Reduce haptic feedback intensity
        hapticService.setIntensity(0.7)
        
        // Reduce location update frequency
        notifyServicesOfOptimization(.batteryOptimization)
        
        // Dim screen brightness slightly
        // Note: WatchOS automatically manages this
    }
    
    private func applyGolfOptimizations() {
        // Prioritize location and health services
        prioritizeService("location")
        prioritizeService("health")
        
        // Reduce non-essential background tasks
        deprioritizeService("notifications")
        
        // Optimize workout tracking
        notifyServicesOfOptimization(.golfOptimization)
    }
    
    private func applyTimerOptimizations() {
        // Focus on timer accuracy and notifications
        prioritizeService("timer")
        prioritizeService("notifications")
        
        // Reduce location updates
        deprioritizeService("location")
        
        notifyServicesOfOptimization(.timerOptimization)
    }
    
    private func applyLowBatteryOptimizations() {
        // Aggressive power saving
        hapticService.setIntensity(0.5)
        
        // Minimize all non-essential services
        deprioritizeService("notifications")
        deprioritizeService("connectivity")
        
        // Reduce update frequencies
        notifyServicesOfOptimization(.aggressiveBatteryOptimization)
    }
    
    private func restoreNormalPerformance() {
        // Restore normal haptic feedback
        hapticService.setIntensity(1.0)
        
        // Restore normal service priorities
        for service in activeServices {
            restoreServicePriority(service)
        }
        
        notifyServicesOfOptimization(.normalPerformance)
    }
    
    private func handleLowBatteryMode() {
        if isAdaptivePerformanceEnabled {
            optimizeForLowBattery()
        }
        
        // Schedule low battery notification
        Task {
            try? await notificationService.scheduleLowBatteryAlert(level: batteryLevel)
        }
    }
    
    private func handleNormalBatteryMode() {
        if isBatteryOptimized && batteryLevel > (lowBatteryThreshold + 0.1) {
            // Restore normal performance if battery has recovered
            disableBatteryOptimization()
        }
    }
    
    // MARK: - Performance Modes
    
    func setPerformanceMode(_ mode: WatchPerformanceMode) {
        currentPerformanceMode = mode
        
        switch mode {
        case .batterySaver:
            applyLowBatteryOptimizations()
        case .balanced:
            applyBalancedOptimizations()
        case .performance:
            applyPerformanceOptimizations()
        case .golf:
            applyGolfOptimizations()
        case .timer:
            applyTimerOptimizations()
        }
        
        logger.info("Set performance mode to: \(mode.rawValue)")
    }
    
    func getRecommendedPerformanceMode() -> WatchPerformanceMode {
        if batteryLevel < criticalBatteryThreshold {
            return .batterySaver
        } else if batteryLevel < lowBatteryThreshold {
            return .balanced
        } else if isCharging {
            return .performance
        } else {
            return .balanced
        }
    }
    
    func enableAdaptivePerformance() {
        isAdaptivePerformanceEnabled = true
        
        // Start adaptive performance monitoring
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.adaptPerformance()
            }
        }
        
        logger.info("Enabled adaptive performance")
    }
    
    func disableAdaptivePerformance() {
        isAdaptivePerformanceEnabled = false
        logger.info("Disabled adaptive performance")
    }
    
    private func adaptPerformance() {
        guard isAdaptivePerformanceEnabled else { return }
        
        let recommendedMode = getRecommendedPerformanceMode()
        
        if recommendedMode != currentPerformanceMode {
            setPerformanceMode(recommendedMode)
        }
    }
    
    private func applyBalancedOptimizations() {
        // Standard performance with moderate optimizations
        hapticService.setIntensity(0.8)
        notifyServicesOfOptimization(.balancedOptimization)
    }
    
    private func applyPerformanceOptimizations() {
        // Maximum performance, minimal optimizations
        hapticService.setIntensity(1.0)
        notifyServicesOfOptimization(.performanceOptimization)
    }
    
    // MARK: - System Resource Monitoring
    
    func getMemoryUsage() -> MemoryUsage {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024 / 1024
            let totalMB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024
            
            return MemoryUsage(
                used: usedMB,
                total: totalMB,
                usedPercentage: usedMB / totalMB
            )
        } else {
            return MemoryUsage(used: 0, total: 0, usedPercentage: 0)
        }
    }
    
    func getCPUUsage() -> Double {
        var info = processor_info_array_t.allocate(capacity: 1)
        var numCpuInfo = mach_msg_type_number_t()
        var numCpus = natural_t()
        
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpus, &info, &numCpuInfo)
        
        if result == KERN_SUCCESS {
            let cpuLoadInfo = info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: 1) { $0 }
            
            let userTime = Double(cpuLoadInfo.pointee.cpu_ticks.0)
            let systemTime = Double(cpuLoadInfo.pointee.cpu_ticks.1)
            let idleTime = Double(cpuLoadInfo.pointee.cpu_ticks.2)
            
            let totalTime = userTime + systemTime + idleTime
            let usage = (userTime + systemTime) / totalTime
            
            info.deallocate()
            
            return usage
        } else {
            return 0.0
        }
    }
    
    func getDiskUsage() -> DiskUsage {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory() as String)
        
        do {
            let values = try fileURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])
            
            if let availableCapacity = values.volumeAvailableCapacityForImportantUsage,
               let totalCapacity = values.volumeTotalCapacity {
                
                let usedCapacity = totalCapacity - availableCapacity
                let usedPercentage = Double(usedCapacity) / Double(totalCapacity)
                
                return DiskUsage(
                    used: Double(usedCapacity) / 1024 / 1024,
                    available: Double(availableCapacity) / 1024 / 1024,
                    total: Double(totalCapacity) / 1024 / 1024,
                    usedPercentage: usedPercentage
                )
            }
        } catch {
            logger.error("Failed to get disk usage: \(error.localizedDescription)")
        }
        
        return DiskUsage(used: 0, available: 0, total: 0, usedPercentage: 0)
    }
    
    func getNetworkUsage() -> NetworkUsage {
        // Simplified network usage monitoring
        // In a full implementation, you would track actual network statistics
        return NetworkUsage(
            bytesReceived: 0,
            bytesSent: 0,
            packetsReceived: 0,
            packetsSent: 0
        )
    }
    
    // MARK: - Recommendations and Warnings
    
    func getBatteryOptimizationRecommendations() -> [OptimizationRecommendation] {
        updateOptimizationRecommendations()
        return optimizationRecommendations
    }
    
    func getPerformanceWarnings() -> [PerformanceWarning] {
        updatePerformanceWarnings()
        return performanceWarnings
    }
    
    private func updateOptimizationRecommendations() {
        optimizationRecommendations.removeAll()
        
        if batteryLevel < lowBatteryThreshold {
            optimizationRecommendations.append(.enableBatterySaver)
        }
        
        if activeServices.count > 5 {
            optimizationRecommendations.append(.reduceActiveServices)
        }
        
        let memoryUsage = getMemoryUsage()
        if memoryUsage.usedPercentage > 0.80 {
            optimizationRecommendations.append(.optimizeMemoryUsage)
        }
        
        if !isBatteryOptimized && batteryLevel < 0.5 {
            optimizationRecommendations.append(.enableBatteryOptimization)
        }
    }
    
    private func updatePerformanceWarnings() {
        performanceWarnings.removeAll()
        
        if batteryLevel < criticalBatteryThreshold {
            performanceWarnings.append(.criticalBattery)
        }
        
        let memoryUsage = getMemoryUsage()
        if memoryUsage.usedPercentage > 0.90 {
            performanceWarnings.append(.highMemoryUsage)
        }
        
        if getCPUUsage() > 0.90 {
            performanceWarnings.append(.highCPUUsage)
        }
    }
    
    // MARK: - Service Management
    
    func registerActiveService(_ serviceName: String) {
        activeServices.insert(serviceName)
        updateServiceMetrics(serviceName)
    }
    
    func unregisterActiveService(_ serviceName: String) {
        activeServices.remove(serviceName)
        servicePerformanceMetrics.removeValue(forKey: serviceName)
    }
    
    private func updateServiceMetrics(_ serviceName: String) {
        let metrics = ServicePerformanceMetrics(
            name: serviceName,
            memoryUsage: getMemoryUsage().used / Double(activeServices.count),
            cpuUsage: getCPUUsage() / Double(activeServices.count),
            lastUpdated: Date()
        )
        
        servicePerformanceMetrics[serviceName] = metrics
    }
    
    private func prioritizeService(_ serviceName: String) {
        // In a full implementation, this would adjust system priorities
        logger.debug("Prioritized service: \(serviceName)")
    }
    
    private func deprioritizeService(_ serviceName: String) {
        // In a full implementation, this would adjust system priorities
        logger.debug("Deprioritized service: \(serviceName)")
    }
    
    private func restoreServicePriority(_ serviceName: String) {
        // In a full implementation, this would restore normal priorities
        logger.debug("Restored priority for service: \(serviceName)")
    }
    
    private func notifyServicesOfOptimization(_ optimization: OptimizationType) {
        // Notify all services about optimization changes
        let notification = Notification(name: .watchPerformanceOptimizationChanged, userInfo: [
            "optimization": optimization
        ])
        NotificationCenter.default.post(notification)
    }
    
    // MARK: - Computed Properties
    
    private var isCharging: Bool {
        return batteryState == .charging
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: WatchPerformanceDelegate) {
        delegates.removeAll { $0.delegate == nil }
        delegates.append(WeakPerformanceDelegate(delegate))
        logger.info("Added performance delegate")
    }
    
    func removeDelegate(_ delegate: WatchPerformanceDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        logger.info("Removed performance delegate")
    }
    
    private func notifyDelegates<T>(_ action: (WatchPerformanceDelegate) -> T) {
        delegates.forEach { weakDelegate in
            if let delegate = weakDelegate.delegate {
                _ = action(delegate)
            }
        }
        
        // Clean up nil references
        delegates.removeAll { $0.delegate == nil }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopPerformanceMonitoring()
    }
}

// MARK: - Supporting Types

enum WatchPerformanceMode: String, CaseIterable {
    case batterySaver = "battery_saver"
    case balanced = "balanced"
    case performance = "performance"
    case golf = "golf"
    case timer = "timer"
    
    var displayName: String {
        switch self {
        case .batterySaver: return "Battery Saver"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        case .golf: return "Golf Mode"
        case .timer: return "Timer Mode"
        }
    }
}

enum OptimizationType {
    case normalPerformance
    case batteryOptimization
    case balancedOptimization
    case performanceOptimization
    case golfOptimization
    case timerOptimization
    case aggressiveBatteryOptimization
}

struct WatchPerformanceMetrics {
    let batteryLevel: Float
    let batteryState: WKInterfaceDeviceBatteryState
    let memoryUsage: MemoryUsage
    let cpuUsage: Double
    let diskUsage: DiskUsage
    let networkUsage: NetworkUsage
    let activeServices: Int
    let performanceMode: WatchPerformanceMode
    let isOptimized: Bool
    let uptime: TimeInterval
}

struct WatchPerformanceSnapshot {
    let timestamp: Date
    let batteryLevel: Float
    let batteryState: WKInterfaceDeviceBatteryState
    let memoryUsage: MemoryUsage
    let cpuUsage: Double
    let diskUsage: DiskUsage
    let networkUsage: NetworkUsage
    let activeServices: Set<String>
    let performanceMode: WatchPerformanceMode
}

struct MemoryUsage {
    let used: Double // MB
    let total: Double // MB
    let usedPercentage: Double
}

struct DiskUsage {
    let used: Double // MB
    let available: Double // MB
    let total: Double // MB
    let usedPercentage: Double
}

struct NetworkUsage {
    let bytesReceived: UInt64
    let bytesSent: UInt64
    let packetsReceived: UInt64
    let packetsSent: UInt64
}

struct ServicePerformanceMetrics {
    let name: String
    let memoryUsage: Double
    let cpuUsage: Double
    let lastUpdated: Date
}

enum PerformanceIssue {
    case highMemoryUsage(Double)
    case highCPUUsage(Double)
    case rapidBatteryDrain(Float)
    case tooManyActiveServices(Int)
}

enum OptimizationRecommendation: String, CaseIterable {
    case enableBatterySaver = "enable_battery_saver"
    case reduceActiveServices = "reduce_active_services"
    case optimizeMemoryUsage = "optimize_memory_usage"
    case enableBatteryOptimization = "enable_battery_optimization"
    
    var title: String {
        switch self {
        case .enableBatterySaver: return "Enable Battery Saver"
        case .reduceActiveServices: return "Reduce Active Features"
        case .optimizeMemoryUsage: return "Optimize Memory Usage"
        case .enableBatteryOptimization: return "Enable Battery Optimization"
        }
    }
    
    var description: String {
        switch self {
        case .enableBatterySaver: return "Switch to battery saver mode to extend battery life"
        case .reduceActiveServices: return "Disable unnecessary features to improve performance"
        case .optimizeMemoryUsage: return "Close unused apps and clear memory"
        case .enableBatteryOptimization: return "Enable battery optimization for longer usage"
        }
    }
}

enum PerformanceWarning: String, CaseIterable {
    case criticalBattery = "critical_battery"
    case highMemoryUsage = "high_memory_usage"
    case highCPUUsage = "high_cpu_usage"
    
    var title: String {
        switch self {
        case .criticalBattery: return "Critical Battery Level"
        case .highMemoryUsage: return "High Memory Usage"
        case .highCPUUsage: return "High CPU Usage"
        }
    }
    
    var description: String {
        switch self {
        case .criticalBattery: return "Battery level is critically low. Consider charging soon."
        case .highMemoryUsage: return "Memory usage is high. App may become slow or crash."
        case .highCPUUsage: return "CPU usage is high. Performance may be degraded."
        }
    }
}

private struct WeakPerformanceDelegate {
    weak var delegate: WatchPerformanceDelegate?
    
    init(_ delegate: WatchPerformanceDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let watchPerformanceOptimizationChanged = Notification.Name("WatchPerformanceOptimizationChanged")
}

// MARK: - Notification Service Extension

extension WatchNotificationServiceProtocol {
    func scheduleLowBatteryAlert(level: Float) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Low Battery"
        content.body = "Battery level is at \(Int(level * 100))%. Consider enabling battery saver mode."
        content.sound = .default
        content.userInfo = [
            "type": "low_battery",
            "battery_level": level
        ]
        
        let request = UNNotificationRequest(
            identifier: "low_battery_alert",
            content: content,
            trigger: nil
        )
        
        try await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Haptic Service Extension

extension WatchHapticFeedbackServiceProtocol {
    func setIntensity(_ intensity: Float) {
        // This would adjust haptic intensity if supported by the service
        // Implementation would depend on the actual haptic service interface
    }
}

// MARK: - Preview Support

#if DEBUG
extension WatchPerformanceService {
    static let mock = WatchPerformanceService()
}
#endif