import Foundation
import WatchKit
import os.log

// MARK: - Watch Service Lifecycle

enum WatchServiceLifecycle {
    case singleton // Single instance throughout Watch session
    case scoped // New instance per container scope
    case transient // New instance every time
}

// MARK: - Watch Environment Configuration

enum WatchServiceEnvironment {
    case development
    case test
    case production
    
    var useMockServices: Bool {
        switch self {
        case .test:
            return true
        case .development:
            return WKInterfaceDevice.current().systemName.contains("Simulator")
        case .production:
            return false
        }
    }
    
    var enableAnalytics: Bool {
        switch self {
        case .test:
            return false
        case .development, .production:
            return true
        }
    }
}

// MARK: - Multi-Tenant Watch Context

struct WatchTenantContext {
    let tenantId: String?
    let businessType: WatchBusinessType
    let theme: WatchTenantTheme
    let features: WatchTenantFeatures
    let databaseNamespace: String
    
    static let defaultContext = WatchTenantContext(
        tenantId: nil,
        businessType: .golfCourse,
        theme: .defaultTheme,
        features: .basicFeatures,
        databaseNamespace: "default"
    )
}

enum WatchBusinessType: String, CaseIterable, Codable {
    case golfCourse = "golf_course"
    case golfResort = "golf_resort" 
    case countryClub = "country_club"
    case publicCourse = "public_course"
    case privateClub = "private_club"
    case golfAcademy = "golf_academy"
    
    var displayName: String {
        switch self {
        case .golfCourse: return "Golf Course"
        case .golfResort: return "Golf Resort"
        case .countryClub: return "Country Club"
        case .publicCourse: return "Public Course"
        case .privateClub: return "Private Club"
        case .golfAcademy: return "Golf Academy"
        }
    }
    
    var hasBasicFeatures: Bool { true }
    var hasPremiumFeatures: Bool {
        switch self {
        case .golfResort, .countryClub, .privateClub:
            return true
        default:
            return false
        }
    }
    var hasEliteFeatures: Bool {
        switch self {
        case .privateClub:
            return true
        default:
            return false
        }
    }
}

struct WatchTenantTheme: Codable {
    let primaryColor: String
    let secondaryColor: String
    let accentColor: String
    let textColor: String
    let backgroundColor: String
    let fontFamily: String
    let logoURL: String?
    
    static let defaultTheme = WatchTenantTheme(
        primaryColor: "#2E7D32",
        secondaryColor: "#4CAF50", 
        accentColor: "#8BC34A",
        textColor: "#FFFFFF",
        backgroundColor: "#1B1B1B",
        fontFamily: "San Francisco",
        logoURL: nil
    )
}

struct WatchTenantFeatures: Codable {
    let enableScorecard: Bool
    let enableGPS: Bool
    let enableWorkout: Bool
    let enableHaptics: Bool
    let enableComplications: Bool
    let enableNotifications: Bool
    let enablePremiumAnalytics: Bool
    let enableConcierge: Bool
    let enableMemberServices: Bool
    
    static let basicFeatures = WatchTenantFeatures(
        enableScorecard: true,
        enableGPS: true,
        enableWorkout: true,
        enableHaptics: true,
        enableComplications: true,
        enableNotifications: true,
        enablePremiumAnalytics: false,
        enableConcierge: false,
        enableMemberServices: false
    )
    
    static let premiumFeatures = WatchTenantFeatures(
        enableScorecard: true,
        enableGPS: true,
        enableWorkout: true,
        enableHaptics: true,
        enableComplications: true,
        enableNotifications: true,
        enablePremiumAnalytics: true,
        enableConcierge: true,
        enableMemberServices: false
    )
    
    static let eliteFeatures = WatchTenantFeatures(
        enableScorecard: true,
        enableGPS: true,
        enableWorkout: true,
        enableHaptics: true,
        enableComplications: true,
        enableNotifications: true,
        enablePremiumAnalytics: true,
        enableConcierge: true,
        enableMemberServices: true
    )
}

// MARK: - Watch Service Container

@MainActor
class WatchServiceContainer: ObservableObject {
    // MARK: - Singleton Access
    
    static let shared = WatchServiceContainer()
    
    // MARK: - Configuration
    
    @Published var environment: WatchServiceEnvironment = .development
    @Published var currentTenantContext: WatchTenantContext = .defaultContext
    @Published var isMultiTenantMode: Bool = false
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "ServiceContainer")
    
    // MARK: - Service Storage
    
    private var singletonServices: [String: Any] = [:]
    private var serviceRegistrations: [String: WatchServiceRegistration] = [:]
    
    // MARK: - Multi-Tenant Service Storage
    
    private var tenantSpecificServices: [String: [String: Any]] = [:]  // [tenantId: [serviceKey: service]]
    private var tenantContextCache: [String: WatchTenantContext] = [:]
    private var availableTenants: [String] = []
    
    // MARK: - Performance Optimization for Watch
    
    private var serviceAccessMetrics: [String: WatchServiceAccessMetrics] = [:]
    private let serviceCreationQueue = DispatchQueue(label: "WatchGolfServiceCreation", qos: .userInitiated)
    private var preloadedServices: Set<String> = []
    private var batteryOptimizedServices: Set<String> = []
    
    // MARK: - Watch-Specific Properties
    
    private var isLowPowerModeActive: Bool = false
    private var lastBackgroundRefresh: Date = Date()
    private let backgroundRefreshInterval: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    private init() {
        registerDefaultWatchServices()
        observeBatteryState()
        logger.info("WatchServiceContainer initialized")
    }
    
    // For testing purposes
    init(environment: WatchServiceEnvironment = .test) {
        self.environment = environment
        registerDefaultWatchServices()
        logger.info("WatchServiceContainer initialized for testing")
    }
    
    // MARK: - Service Registration
    
    private func registerDefaultWatchServices() {
        // MARK: - Watch Connectivity Services
        
        register(
            WatchConnectivityServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchConnectivityService()
            }
            return WatchConnectivityService()
        }
        
        // MARK: - Golf Services (Watch-Optimized)
        
        register(
            WatchGolfCourseServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchGolfCourseService()
            }
            let connectivityService = container.resolve(WatchConnectivityServiceProtocol.self)
            return WatchGolfCourseService(connectivityService: connectivityService)
        }
        
        register(
            WatchScorecardServiceProtocol.self,
            lifecycle: .scoped // New instance per round
        ) { container in
            if container.environment.useMockServices {
                return MockWatchScorecardService()
            }
            let connectivityService = container.resolve(WatchConnectivityServiceProtocol.self)
            return WatchScorecardService(connectivityService: connectivityService)
        }
        
        register(
            WatchGPSServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchGPSService()
            }
            return WatchGPSService()
        }
        
        register(
            WatchWorkoutServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchWorkoutService()
            }
            return WatchWorkoutService()
        }
        
        // MARK: - Watch UI and Interaction Services
        
        register(
            WatchHapticFeedbackServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchHapticFeedbackService()
            }
            return WatchHapticFeedbackService()
        }
        
        register(
            WatchComplicationServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchComplicationService()
            }
            return WatchComplicationService()
        }
        
        register(
            WatchNotificationServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchNotificationService()
            }
            return WatchNotificationService()
        }
        
        // MARK: - Watch Data and Storage Services
        
        register(
            WatchCacheServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchCacheService()
            }
            return WatchCacheService()
        }
        
        register(
            WatchSyncServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchSyncService()
            }
            let connectivityService = container.resolve(WatchConnectivityServiceProtocol.self)
            let cacheService = container.resolve(WatchCacheServiceProtocol.self)
            return WatchSyncService(connectivityService: connectivityService, cacheService: cacheService)
        }
        
        // MARK: - Watch Analytics and Performance Services
        
        register(
            WatchAnalyticsServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices || !container.environment.enableAnalytics {
                return MockWatchAnalyticsService()
            }
            return WatchAnalyticsService()
        }
        
        register(
            WatchPerformanceServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchPerformanceService()
            }
            return WatchPerformanceService()
        }
        
        logger.debug("Registered \(serviceRegistrations.count) Watch services")
        
        // Register multi-tenant services
        registerMultiTenantServices()
        
        // Register gamification services
        registerGamificationServices()
    }
    
    // MARK: - Multi-Tenant Service Registration
    
    private func registerMultiTenantServices() {
        // MARK: - Tenant Configuration Services
        
        register(
            WatchTenantConfigurationServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchTenantConfigurationService()
            }
            let connectivityService = container.resolve(WatchConnectivityServiceProtocol.self)
            let cacheService = container.resolve(WatchCacheServiceProtocol.self)
            return WatchTenantConfigurationService(
                connectivityService: connectivityService,
                cacheService: cacheService
            )
        }
        
        register(
            WatchTenantThemeServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchTenantThemeService()
            }
            return WatchTenantThemeService()
        }
        
        // MARK: - Enhanced Multi-Tenant Watch Connectivity
        
        register(
            MultiTenantWatchConnectivityServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockMultiTenantWatchConnectivityService()
            }
            let baseConnectivity = container.resolve(WatchConnectivityServiceProtocol.self)
            let tenantConfig = container.resolve(WatchTenantConfigurationServiceProtocol.self)
            return MultiTenantWatchConnectivityService(
                baseService: baseConnectivity,
                tenantService: tenantConfig
            )
        }
        
        logger.debug("Registered multi-tenant Watch services")
    }
    
    // MARK: - Gamification Service Registration
    
    private func registerGamificationServices() {
        logger.debug("Registering Watch gamification services")
        
        // Watch Gamification Service
        register(
            WatchGamificationServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchGamificationService()
            }
            
            let connectivity = container.resolve(WatchConnectivityServiceProtocol.self)
            let haptic = container.resolve(WatchHapticFeedbackServiceProtocol.self)
            let notification = container.resolve(WatchNotificationServiceProtocol.self)
            let cache = container.resolve(WatchCacheServiceProtocol.self)
            
            return WatchGamificationService(
                watchConnectivityService: connectivity,
                hapticService: haptic,
                notificationService: notification,
                cacheService: cache
            )
        }
        
        // Watch Power Optimization Service
        register(
            WatchPowerOptimizationServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchPowerOptimizationService()
            }
            
            return WatchPowerOptimizationService()
        }
        
        logger.debug("Registered Watch gamification services")
    }
    
    // MARK: - Generic Service Registration
    
    func register<T>(
        _ protocolType: T.Type,
        lifecycle: WatchServiceLifecycle,
        factory: @escaping (WatchServiceContainer) -> T
    ) {
        let key = String(describing: protocolType)
        serviceRegistrations[key] = WatchServiceRegistration(
            lifecycle: lifecycle,
            factory: { container in
                factory(container)
            }
        )
        
        logger.debug("Registered Watch service: \(key)")
    }
    
    // MARK: - Service Resolution
    
    func resolve<T>(_ protocolType: T.Type) -> T {
        let key = String(describing: protocolType)
        let startTime = DispatchTime.now()
        
        guard let registration = serviceRegistrations[key] else {
            logger.error("Watch service not registered: \(key)")
            fatalError("Watch service not registered: \(key)")
        }
        
        let service: T
        
        switch registration.lifecycle {
        case .singleton:
            if let existingService = singletonServices[key] as? T {
                recordServiceAccess(key: key, creationTime: 0, fromCache: true)
                return existingService
            }
            
            service = registration.factory(self) as! T
            singletonServices[key] = service
            
        case .scoped:
            service = registration.factory(self) as! T
            
        case .transient:
            service = registration.factory(self) as! T
        }
        
        let creationTime = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        recordServiceAccess(key: key, creationTime: creationTime, fromCache: false)
        
        return service
    }
    
    // MARK: - Convenience Methods for Watch Services
    
    func watchConnectivityService() -> WatchConnectivityServiceProtocol {
        return resolve(WatchConnectivityServiceProtocol.self)
    }
    
    func watchGolfCourseService() -> WatchGolfCourseServiceProtocol {
        return resolve(WatchGolfCourseServiceProtocol.self)
    }
    
    func watchScorecardService() -> WatchScorecardServiceProtocol {
        return resolve(WatchScorecardServiceProtocol.self)
    }
    
    func watchGPSService() -> WatchGPSServiceProtocol {
        return resolve(WatchGPSServiceProtocol.self)
    }
    
    func watchWorkoutService() -> WatchWorkoutServiceProtocol {
        return resolve(WatchWorkoutServiceProtocol.self)
    }
    
    func watchHapticFeedbackService() -> WatchHapticFeedbackServiceProtocol {
        return resolve(WatchHapticFeedbackServiceProtocol.self)
    }
    
    func watchComplicationService() -> WatchComplicationServiceProtocol {
        return resolve(WatchComplicationServiceProtocol.self)
    }
    
    func watchSyncService() -> WatchSyncServiceProtocol {
        return resolve(WatchSyncServiceProtocol.self)
    }
    
    func watchAnalyticsService() -> WatchAnalyticsServiceProtocol {
        return resolve(WatchAnalyticsServiceProtocol.self)
    }
    
    // MARK: - Gamification Service Convenience Methods
    
    func watchGamificationService() -> WatchGamificationServiceProtocol {
        return resolve(WatchGamificationServiceProtocol.self)
    }
    
    func watchPowerOptimizationService() -> WatchPowerOptimizationServiceProtocol {
        return resolve(WatchPowerOptimizationServiceProtocol.self)
    }
    
    // MARK: - Multi-Tenant Convenience Methods
    
    func watchTenantConfigurationService() -> WatchTenantConfigurationServiceProtocol {
        return resolve(WatchTenantConfigurationServiceProtocol.self)
    }
    
    func watchTenantThemeService() -> WatchTenantThemeServiceProtocol {
        return resolve(WatchTenantThemeServiceProtocol.self)
    }
    
    func multiTenantWatchConnectivityService() -> MultiTenantWatchConnectivityServiceProtocol {
        return resolve(MultiTenantWatchConnectivityServiceProtocol.self)
    }
    
    // MARK: - Environment Configuration
    
    func configure(for environment: WatchServiceEnvironment) {
        self.environment = environment
        singletonServices.removeAll()
        preloadedServices.removeAll()
        
        logger.info("WatchServiceContainer configured for environment: \(environment)")
        
        // Reconfigure services based on environment
        if environment == .production {
            enableBatteryOptimizations()
        }
    }
    
    // MARK: - Multi-Tenant Management
    
    func switchToTenant(_ tenantContext: WatchTenantContext) async {
        let previousTenantId = currentTenantContext.tenantId
        let startTime = Date()
        
        logger.info("Switching Watch to tenant: \(tenantContext.tenantId ?? "default")")
        
        // Update current context
        currentTenantContext = tenantContext
        isMultiTenantMode = tenantContext.tenantId != nil
        
        // Cache tenant context
        if let tenantId = tenantContext.tenantId {
            tenantContextCache[tenantId] = tenantContext
            if !availableTenants.contains(tenantId) {
                availableTenants.append(tenantId)
            }
        }
        
        // Clear tenant-specific services to force recreation with new context
        if let previousId = previousTenantId {
            tenantSpecificServices.removeValue(forKey: previousId)
        }
        
        // Notify tenant configuration service
        let tenantConfigService = watchTenantConfigurationService()
        await tenantConfigService.switchToTenant(tenantContext)
        
        // Update theme service
        let themeService = watchTenantThemeService()
        await themeService.applyTenantTheme(tenantContext.theme)
        
        // Update multi-tenant connectivity
        let connectivityService = multiTenantWatchConnectivityService()
        await connectivityService.switchTenantContext(tenantContext)
        
        // Update tenant-aware services
        await updateTenantAwareServices(with: tenantContext)
        
        let switchDuration = Date().timeIntervalSince(startTime)
        logger.info("Watch tenant switch completed in \(switchDuration)s")
        
        // Track tenant switch
        watchAnalyticsService().track("watch_tenant_switched", parameters: [
            "previous_tenant": previousTenantId ?? "none",
            "new_tenant": tenantContext.tenantId ?? "default",
            "business_type": tenantContext.businessType.rawValue,
            "switch_duration": switchDuration
        ])
    }
    
    func getTenantSpecificService<T>(_ serviceType: T.Type, for tenantId: String) -> T? {
        let serviceKey = String(describing: serviceType)
        return tenantSpecificServices[tenantId]?[serviceKey] as? T
    }
    
    func setTenantSpecificService<T>(_ service: T, for tenantId: String, serviceType: T.Type) {
        let serviceKey = String(describing: serviceType)
        if tenantSpecificServices[tenantId] == nil {
            tenantSpecificServices[tenantId] = [:]
        }
        tenantSpecificServices[tenantId]?[serviceKey] = service
    }
    
    func getAvailableTenants() -> [String] {
        return availableTenants
    }
    
    func getCachedTenantContext(for tenantId: String) -> WatchTenantContext? {
        return tenantContextCache[tenantId]
    }
    
    private func updateTenantAwareServices(with context: WatchTenantContext) async {
        // Update haptic feedback service with tenant-specific patterns
        if let hapticService = singletonServices["WatchHapticFeedbackServiceProtocol"] as? WatchHapticFeedbackService {
            await hapticService.updateTenantContext(context)
        }
        
        // Update complication service with tenant branding
        if let complicationService = singletonServices["WatchComplicationServiceProtocol"] as? WatchComplicationService {
            await complicationService.updateTenantBranding(context.theme)
        }
        
        // Update notification service with tenant-specific settings
        if let notificationService = singletonServices["WatchNotificationServiceProtocol"] as? WatchNotificationService {
            await notificationService.updateTenantConfiguration(context)
        }
        
        logger.debug("Updated tenant-aware services for tenant: \(context.tenantId ?? "default")")
    }
    
    // MARK: - Watch-Specific Optimizations
    
    private func observeBatteryState() {
        // Monitor battery state for optimization
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateDidChange),
            name: ProcessInfo.processInfo.thermalStateDidChangeNotification,
            object: nil
        )
        
        logger.debug("Started observing battery state for optimization")
    }
    
    @objc private func batteryStateDidChange() {
        let thermalState = ProcessInfo.processInfo.thermalState
        let wasLowPowerActive = isLowPowerModeActive
        
        isLowPowerModeActive = thermalState == .critical || thermalState == .serious
        
        if isLowPowerModeActive != wasLowPowerActive {
            if isLowPowerModeActive {
                enableBatteryOptimizations()
                logger.info("Enabled battery optimizations due to thermal state: \(thermalState)")
            } else {
                disableBatteryOptimizations()
                logger.info("Disabled battery optimizations - thermal state improved: \(thermalState)")
            }
        }
    }
    
    private func enableBatteryOptimizations() {
        // Reduce service activity for battery optimization
        batteryOptimizedServices = Set(serviceRegistrations.keys)
        
        // Notify services to reduce activity
        for (key, _) in singletonServices {
            if let service = singletonServices[key] as? WatchBatteryOptimizable {
                service.enableBatteryOptimization()
            }
        }
        
        logger.debug("Enabled battery optimizations for \(batteryOptimizedServices.count) services")
    }
    
    private func disableBatteryOptimizations() {
        // Resume normal service activity
        for serviceName in batteryOptimizedServices {
            if let service = singletonServices[serviceName] as? WatchBatteryOptimizable {
                service.disableBatteryOptimization()
            }
        }
        
        batteryOptimizedServices.removeAll()
        logger.debug("Disabled battery optimizations")
    }
    
    // MARK: - Performance Monitoring
    
    private func recordServiceAccess(key: String, creationTime: Double, fromCache: Bool) {
        if var metrics = serviceAccessMetrics[key] {
            metrics.accessCount += 1
            metrics.totalCreationTime += creationTime
            metrics.averageCreationTime = metrics.totalCreationTime / Double(metrics.accessCount)
            metrics.cacheHitRate = fromCache ?
                (metrics.cacheHitRate * Double(metrics.accessCount - 1) + 1.0) / Double(metrics.accessCount) :
                (metrics.cacheHitRate * Double(metrics.accessCount - 1)) / Double(metrics.accessCount)
            metrics.lastAccessTime = Date()
            serviceAccessMetrics[key] = metrics
        } else {
            serviceAccessMetrics[key] = WatchServiceAccessMetrics(
                serviceName: key,
                accessCount: 1,
                totalCreationTime: creationTime,
                averageCreationTime: creationTime,
                cacheHitRate: fromCache ? 1.0 : 0.0,
                lastAccessTime: Date()
            )
        }
    }
    
    func getServiceMetrics() -> [WatchServiceAccessMetrics] {
        return Array(serviceAccessMetrics.values).sorted { $0.accessCount > $1.accessCount }
    }
    
    // MARK: - Service Preloading for Critical Watch Services
    
    func preloadCriticalWatchServices() async {
        let criticalServices = [
            "WatchConnectivityServiceProtocol",
            "WatchGPSServiceProtocol",
            "WatchHapticFeedbackServiceProtocol",
            "WatchCacheServiceProtocol",
            "WatchSyncServiceProtocol",
            "WatchGamificationServiceProtocol",
            "WatchPowerOptimizationServiceProtocol"
        ]
        
        logger.info("Preloading \(criticalServices.count) critical Watch services")
        
        await withTaskGroup(of: Void.self) { group in
            for serviceKey in criticalServices {
                group.addTask { [weak self] in
                    await self?.preloadService(serviceKey)
                }
            }
        }
        
        logger.info("Critical Watch services preloading completed")
    }
    
    private func preloadService(_ serviceKey: String) async {
        guard !preloadedServices.contains(serviceKey),
              let registration = serviceRegistrations[serviceKey],
              registration.lifecycle == .singleton else {
            return
        }
        
        let service = registration.factory(self)
        singletonServices[serviceKey] = service
        preloadedServices.insert(serviceKey)
        
        recordServiceAccess(key: serviceKey, creationTime: 0, fromCache: false)
        logger.debug("Preloaded Watch service: \(serviceKey)")
    }
    
    // MARK: - Background Refresh Management
    
    func performBackgroundRefresh() {
        guard Date().timeIntervalSince(lastBackgroundRefresh) >= backgroundRefreshInterval else {
            logger.debug("Background refresh skipped - too recent")
            return
        }
        
        lastBackgroundRefresh = Date()
        
        // Refresh critical services in background
        Task {
            await refreshBackgroundServices()
        }
        
        logger.debug("Started background refresh")
    }
    
    private func refreshBackgroundServices() async {
        let backgroundServices = [
            "WatchSyncServiceProtocol",
            "WatchCacheServiceProtocol",
            "WatchGamificationServiceProtocol"
        ]
        
        for serviceKey in backgroundServices {
            if let service = singletonServices[serviceKey] as? WatchBackgroundRefreshable {
                await service.performBackgroundRefresh()
            }
        }
        
        logger.debug("Background refresh completed")
    }
    
    // MARK: - Cleanup and Memory Management
    
    func performMemoryCleanup() {
        // Clean up transient services and old metrics
        let cutoffTime = Date().addingTimeInterval(-3600) // 1 hour ago
        
        serviceAccessMetrics = serviceAccessMetrics.filter { _, metrics in
            metrics.lastAccessTime > cutoffTime
        }
        
        // Notify services to clean up
        for (_, service) in singletonServices {
            if let cleanupService = service as? WatchMemoryCleanable {
                cleanupService.performMemoryCleanup()
            }
        }
        
        logger.debug("Performed memory cleanup")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        logger.debug("WatchServiceContainer deinitialized")
    }
}

// MARK: - Service Registration Helper

private struct WatchServiceRegistration {
    let lifecycle: WatchServiceLifecycle
    let factory: (WatchServiceContainer) -> Any
}

// MARK: - Watch-Specific Service Protocols

protocol WatchBatteryOptimizable {
    func enableBatteryOptimization()
    func disableBatteryOptimization()
}

protocol WatchBackgroundRefreshable {
    func performBackgroundRefresh() async
}

protocol WatchMemoryCleanable {
    func performMemoryCleanup()
}

// MARK: - WatchKit Environment Integration

private struct WatchServiceContainerKey: EnvironmentKey {
    static let defaultValue: WatchServiceContainer = .shared
}

extension EnvironmentValues {
    var watchServiceContainer: WatchServiceContainer {
        get { self[WatchServiceContainerKey.self] }
        set { self[WatchServiceContainerKey.self] = newValue }
    }
}

// MARK: - SwiftUI Property Wrapper for Watch Services

@propertyWrapper
struct WatchServiceInjected<T> {
    private let serviceType: T.Type
    
    init(_ serviceType: T.Type) {
        self.serviceType = serviceType
    }
    
    var wrappedValue: T {
        WatchServiceContainer.shared.resolve(serviceType)
    }
}

// MARK: - View Modifier for Watch Service Container

struct WatchServiceContainerModifier: ViewModifier {
    let container: WatchServiceContainer
    
    func body(content: Content) -> some View {
        content
            .environmentObject(container)
            .environment(\.watchServiceContainer, container)
    }
}

extension View {
    func withWatchServiceContainer(_ container: WatchServiceContainer = WatchServiceContainer.shared) -> some View {
        modifier(WatchServiceContainerModifier(container: container))
    }
}

// MARK: - Performance Monitoring Data Structures

struct WatchServiceAccessMetrics {
    let serviceName: String
    var accessCount: Int
    var totalCreationTime: Double
    var averageCreationTime: Double
    var cacheHitRate: Double
    var lastAccessTime: Date
    
    var formattedAverageCreationTime: String {
        String(format: "%.2f ms", averageCreationTime)
    }
    
    var formattedCacheHitRate: String {
        String(format: "%.1f%%", cacheHitRate * 100)
    }
    
    var batteryEfficiencyScore: Double {
        // Higher cache hit rate and lower creation time = better battery efficiency
        return (cacheHitRate * 0.7) + ((1.0 - min(averageCreationTime / 100.0, 1.0)) * 0.3)
    }
}