import Foundation
import Combine
import SwiftUI

// MARK: - Mock Tenant Configuration Service

@MainActor
class MockTenantConfigurationService: TenantConfigurationServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var currentTenant: TenantConfiguration?
    @Published private(set) var currentTheme: WhiteLabelTheme = .golfCourseDefault
    @Published private(set) var availableTenants: [TenantConfiguration] = []
    @Published private(set) var isMultiTenantMode: Bool = false
    
    // MARK: - Mock Data Storage
    private var mockTenants: [String: TenantConfiguration] = [:]
    private var mockUsageMetrics: [String: TenantUsageMetrics] = [:]
    
    // MARK: - Reactive Publishers
    private let currentTenantSubject = CurrentValueSubject<TenantConfiguration?, Never>(nil)
    private let themeChangedSubject = CurrentValueSubject<WhiteLabelTheme, Never>(.golfCourseDefault)
    private let tenantSwitchedSubject = CurrentValueSubject<String?, Never>(nil)
    
    // MARK: - Mock Configuration
    var shouldSimulateNetworkDelay = true
    var networkDelay: TimeInterval = 0.5
    var shouldFailOperations = false
    var mockErrorToThrow: Error?
    
    // MARK: - Analytics Tracking
    private var tenantSwitchEvents: [(from: String?, to: String, timestamp: Date)] = []
    private var themeChangeEvents: [(from: WhiteLabelTheme, to: WhiteLabelTheme, timestamp: Date)] = []
    private var operationMetrics: [String: Int] = [:]
    
    // MARK: - Initialization
    
    init() {
        setupMockData()
        
        // Set up reactive bindings
        currentTenantSubject.sink { [weak self] tenant in
            self?.currentTenant = tenant
        }.store(in: &cancellables)
        
        themeChangedSubject.sink { [weak self] theme in
            self?.currentTheme = theme
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Publishers
    
    var currentTenantPublisher: AnyPublisher<TenantConfiguration?, Never> {
        currentTenantSubject.eraseToAnyPublisher()
    }
    
    var themeChangedPublisher: AnyPublisher<WhiteLabelTheme, Never> {
        themeChangedSubject.eraseToAnyPublisher()
    }
    
    var tenantSwitchedPublisher: AnyPublisher<String?, Never> {
        tenantSwitchedSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Tenant Management
    
    func loadTenant(by id: String) async throws -> TenantConfiguration {
        trackOperation("loadTenant")
        
        if shouldSimulateNetworkDelay {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        if shouldFailOperations {
            throw mockErrorToThrow ?? MockTenantError.tenantNotFound
        }
        
        guard let tenant = mockTenants[id] else {
            throw MockTenantError.tenantNotFound
        }
        
        return tenant
    }
    
    func switchTenant(to tenantId: String) async throws {
        trackOperation("switchTenant")
        
        let previousTenantId = currentTenant?.id
        
        if shouldSimulateNetworkDelay {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        if shouldFailOperations {
            throw mockErrorToThrow ?? MockTenantError.switchFailed
        }
        
        let tenant = try await loadTenant(by: tenantId)
        
        currentTenantSubject.send(tenant)
        themeChangedSubject.send(tenant.theme)
        tenantSwitchedSubject.send(tenantId)
        
        isMultiTenantMode = true
        
        trackTenantSwitch(from: previousTenantId, to: tenantId)
    }
    
    func createTenant(_ configuration: TenantConfiguration) async throws {
        trackOperation("createTenant")
        
        if shouldSimulateNetworkDelay {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        if shouldFailOperations {
            throw mockErrorToThrow ?? MockTenantError.creationFailed
        }
        
        let validation = validateTenant(configuration)
        guard validation.isValid else {
            throw MockTenantError.invalidConfiguration
        }
        
        mockTenants[configuration.id] = configuration
        availableTenants.append(configuration)
        
        // Create mock usage metrics
        createMockUsageMetrics(for: configuration.id)
    }
    
    func updateTenant(_ configuration: TenantConfiguration) async throws {
        trackOperation("updateTenant")
        
        if shouldSimulateNetworkDelay {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        if shouldFailOperations {
            throw mockErrorToThrow ?? MockTenantError.updateFailed
        }
        
        let validation = validateTenant(configuration)
        guard validation.isValid else {
            throw MockTenantError.invalidConfiguration
        }
        
        mockTenants[configuration.id] = configuration
        
        if let index = availableTenants.firstIndex(where: { $0.id == configuration.id }) {
            availableTenants[index] = configuration
        }
        
        // Update current tenant if it's the same one
        if currentTenant?.id == configuration.id {
            currentTenantSubject.send(configuration)
            themeChangedSubject.send(configuration.theme)
        }
    }
    
    func deleteTenant(id: String) async throws {
        trackOperation("deleteTenant")
        
        if shouldSimulateNetworkDelay {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        if shouldFailOperations {
            throw mockErrorToThrow ?? MockTenantError.deletionFailed
        }
        
        mockTenants.removeValue(forKey: id)
        mockUsageMetrics.removeValue(forKey: id)
        availableTenants.removeAll { $0.id == id }
        
        // Reset current tenant if deleted
        if currentTenant?.id == id {
            currentTenantSubject.send(nil)
            themeChangedSubject.send(.golfCourseDefault)
            isMultiTenantMode = false
        }
    }
    
    func validateTenant(_ configuration: TenantConfiguration) -> TenantValidationResult {
        var errors: [TenantValidationError] = []
        var warnings: [TenantValidationWarning] = []
        
        // Basic validation
        if configuration.id.isEmpty {
            errors.append(.missingTenantId)
        }
        
        if configuration.domain.isEmpty {
            errors.append(.invalidDomain)
        }
        
        if configuration.databaseNamespace.isEmpty {
            errors.append(.missingDatabaseNamespace)
        }
        
        if !configuration.theme.isComplete {
            errors.append(.invalidTheme)
        }
        
        if configuration.businessInfo.businessName.isEmpty {
            errors.append(.invalidBusinessInfo)
        }
        
        // Warnings
        if configuration.branding.tagline.isEmpty {
            warnings.append(.missingOptionalBranding)
        }
        
        if configuration.subscriptionTier == .starter {
            warnings.append(.lowSubscriptionTier)
        }
        
        return TenantValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    // MARK: - Theme Management
    
    func updateTheme(_ theme: WhiteLabelTheme) async throws {
        trackOperation("updateTheme")
        
        if shouldSimulateNetworkDelay {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        if shouldFailOperations {
            throw mockErrorToThrow ?? MockTenantError.themeUpdateFailed
        }
        
        let previousTheme = currentTheme
        
        if var tenant = currentTenant {
            tenant = TenantConfiguration(
                id: tenant.id,
                name: tenant.name,
                displayName: tenant.displayName,
                domain: tenant.domain,
                theme: theme,
                branding: tenant.branding,
                businessInfo: tenant.businessInfo,
                features: tenant.features,
                databaseNamespace: tenant.databaseNamespace,
                apiKeyPrefix: tenant.apiKeyPrefix,
                isActive: tenant.isActive,
                subscriptionTier: tenant.subscriptionTier,
                createdAt: tenant.createdAt,
                lastModified: Date()
            )
            
            try await updateTenant(tenant)
        } else {
            themeChangedSubject.send(theme)
        }
        
        trackThemeChange(from: previousTheme, to: theme)
    }
    
    func resetToDefaultTheme() async {
        trackOperation("resetToDefaultTheme")
        try? await updateTheme(.golfCourseDefault)
    }
    
    func previewTheme(_ theme: WhiteLabelTheme) async {
        trackOperation("previewTheme")
        themeChangedSubject.send(theme)
    }
    
    func commitPreviewedTheme() async {
        trackOperation("commitPreviewedTheme")
        // In mock, we just keep the current theme
    }
    
    func discardPreviewedTheme() async {
        trackOperation("discardPreviewedTheme")
        if let tenant = currentTenant {
            themeChangedSubject.send(tenant.theme)
        } else {
            themeChangedSubject.send(.golfCourseDefault)
        }
    }
    
    // MARK: - Multi-tenant Data Management
    
    func getTenantDatabaseNamespace() -> String {
        trackOperation("getTenantDatabaseNamespace")
        return currentTenant?.databaseNamespace ?? "default_mock"
    }
    
    func getTenantAPIKey() -> String {
        trackOperation("getTenantAPIKey")
        guard let tenant = currentTenant else { return "mock_api_key" }
        return "mock_\(tenant.apiKeyPrefix)_\(tenant.id)"
    }
    
    func isolateTenantData<T: Codable>(data: T, for tenantId: String) -> T {
        trackOperation("isolateTenantData")
        return data // Mock implementation just returns data as-is
    }
    
    func validateTenantAccess(for tenantId: String) -> Bool {
        trackOperation("validateTenantAccess")
        return mockTenants.keys.contains(tenantId)
    }
    
    // MARK: - Configuration Management
    
    func validateConfiguration() throws {
        trackOperation("validateConfiguration")
        
        if shouldFailOperations {
            throw mockErrorToThrow ?? MockTenantError.configurationInvalid
        }
        
        guard let tenant = currentTenant else {
            throw MockTenantError.noCurrentTenant
        }
        
        let validation = validateTenant(tenant)
        if validation.hasErrors {
            throw MockTenantError.configurationInvalid
        }
    }
    
    func getConfigurationHealth() -> TenantConfigurationHealth {
        trackOperation("getConfigurationHealth")
        
        guard let tenant = currentTenant else {
            return TenantConfigurationHealth(
                overallHealth: .critical,
                themeHealth: .critical,
                brandingHealth: .critical,
                businessInfoHealth: .critical,
                featuresHealth: .critical,
                performanceScore: 0.0,
                lastHealthCheck: Date()
            )
        }
        
        let validation = validateTenant(tenant)
        
        return TenantConfigurationHealth(
            overallHealth: validation.isHealthy ? .excellent : .warning,
            themeHealth: tenant.theme.isComplete ? .excellent : .warning,
            brandingHealth: tenant.branding.hasValidLogo ? .good : .warning,
            businessInfoHealth: !tenant.businessInfo.businessName.isEmpty ? .excellent : .critical,
            featuresHealth: tenant.features.hasBasicFeatures ? .excellent : .warning,
            performanceScore: 85.5,
            lastHealthCheck: Date()
        )
    }
    
    func syncTenantConfiguration() async throws {
        trackOperation("syncTenantConfiguration")
        
        if shouldSimulateNetworkDelay {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        if shouldFailOperations {
            throw mockErrorToThrow ?? MockTenantError.syncFailed
        }
        
        // Mock sync - just trigger a refresh
        if let tenantId = currentTenant?.id {
            let tenant = try await loadTenant(by: tenantId)
            currentTenantSubject.send(tenant)
            themeChangedSubject.send(tenant.theme)
        }
    }
    
    // MARK: - Analytics and Monitoring
    
    func trackTenantSwitch(from: String?, to: String) {
        tenantSwitchEvents.append((from: from, to: to, timestamp: Date()))
    }
    
    func trackThemeChange(from: WhiteLabelTheme, to: WhiteLabelTheme) {
        themeChangeEvents.append((from: from, to: to, timestamp: Date()))
    }
    
    func getTenantUsageMetrics() async -> TenantUsageMetrics {
        trackOperation("getTenantUsageMetrics")
        
        if shouldSimulateNetworkDelay {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        guard let tenant = currentTenant else {
            return createDefaultUsageMetrics()
        }
        
        return mockUsageMetrics[tenant.id] ?? createDefaultUsageMetrics()
    }
    
    // MARK: - Mock Data Setup
    
    private func setupMockData() {
        // Create sample golf course tenant
        let golfCourseTenant = TenantConfiguration(
            id: "pinevalley-gc",
            name: "pinevalley",
            displayName: "Pine Valley Golf Course",
            domain: "pinevalley.golffinder.com",
            theme: .golfCourseDefault,
            branding: TenantBranding(
                logoURL: "https://example.com/pinevalley-logo.png",
                faviconURL: "https://example.com/pinevalley-favicon.ico",
                appIconURL: "https://example.com/pinevalley-app-icon.png",
                heroImageURL: "https://example.com/pinevalley-hero.jpg",
                backgroundImageURL: nil,
                tagline: "Where Legends Are Born",
                description: "Experience championship golf at its finest with our award-winning 18-hole course.",
                welcomeMessage: "Welcome to Pine Valley Golf Course! Ready for an unforgettable round?",
                websiteURL: "https://www.pinevalleygolf.com",
                facebookURL: "https://facebook.com/pinevalleygolf",
                instagramURL: "https://instagram.com/pinevalleygolf",
                twitterURL: nil
            ),
            businessInfo: TenantBusinessInfo(
                businessName: "Pine Valley Golf Course",
                businessType: .golfCourse,
                contactEmail: "info@pinevalleygolf.com",
                contactPhone: "+1-555-GOLF-001",
                address: BusinessAddress(
                    street: "1234 Golf Course Drive",
                    city: "Pine Valley",
                    state: "CA",
                    zipCode: "90210",
                    country: "USA",
                    latitude: 34.0522,
                    longitude: -118.2437
                ),
                timeZone: "America/Los_Angeles",
                currency: "USD",
                locale: "en_US",
                courseCount: 1,
                membershipCount: 750,
                averageRoundsPerDay: 85
            ),
            features: TenantFeatures(
                enableBooking: true,
                enableScorecard: true,
                enableHandicapTracking: true,
                enableLeaderboard: true,
                enableAdvancedAnalytics: true,
                enableWeatherIntegration: true,
                enableGPSRangefinder: true,
                enableSocialFeatures: true,
                enableCustomBranding: true,
                enableMultiCourse: false,
                enableMemberManagement: true,
                enableRevenueTracking: true,
                enableAppleWatchSync: true,
                enableHapticFeedback: true,
                enablePushNotifications: true,
                enableOfflineMode: true
            ),
            databaseNamespace: "tenant_pinevalley_gc",
            apiKeyPrefix: "gf_pinevalley",
            isActive: true,
            subscriptionTier: .professional,
            createdAt: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
            lastModified: Date()
        )
        
        // Create sample resort tenant
        let resortTenant = TenantConfiguration(
            id: "oceanview-resort",
            name: "oceanview",
            displayName: "Oceanview Golf Resort",
            domain: "oceanview.golffinder.com",
            theme: .resortDefault,
            branding: TenantBranding(
                logoURL: "https://example.com/oceanview-logo.png",
                faviconURL: "https://example.com/oceanview-favicon.ico",
                appIconURL: "https://example.com/oceanview-app-icon.png",
                heroImageURL: "https://example.com/oceanview-hero.jpg",
                backgroundImageURL: "https://example.com/oceanview-bg.jpg",
                tagline: "Golf Paradise by the Sea",
                description: "Luxury golf resort featuring two championship courses with breathtaking ocean views.",
                welcomeMessage: "Welcome to Oceanview Golf Resort! Your luxury golf experience awaits.",
                websiteURL: "https://www.oceanviewresort.com",
                facebookURL: "https://facebook.com/oceanviewresort",
                instagramURL: "https://instagram.com/oceanviewresort",
                twitterURL: "https://twitter.com/oceanviewresort"
            ),
            businessInfo: TenantBusinessInfo(
                businessName: "Oceanview Golf Resort",
                businessType: .golfResort,
                contactEmail: "reservations@oceanviewresort.com",
                contactPhone: "+1-555-OCEAN-01",
                address: BusinessAddress(
                    street: "5678 Coastal Highway",
                    city: "Oceanview",
                    state: "FL",
                    zipCode: "33139",
                    country: "USA",
                    latitude: 25.7617,
                    longitude: -80.1918
                ),
                timeZone: "America/New_York",
                currency: "USD",
                locale: "en_US",
                courseCount: 2,
                membershipCount: 1200,
                averageRoundsPerDay: 150
            ),
            features: TenantFeatures(
                enableBooking: true,
                enableScorecard: true,
                enableHandicapTracking: true,
                enableLeaderboard: true,
                enableAdvancedAnalytics: true,
                enableWeatherIntegration: true,
                enableGPSRangefinder: true,
                enableSocialFeatures: true,
                enableCustomBranding: true,
                enableMultiCourse: true,
                enableMemberManagement: true,
                enableRevenueTracking: true,
                enableAppleWatchSync: true,
                enableHapticFeedback: true,
                enablePushNotifications: true,
                enableOfflineMode: true
            ),
            databaseNamespace: "tenant_oceanview_resort",
            apiKeyPrefix: "gf_oceanview",
            isActive: true,
            subscriptionTier: .enterprise,
            createdAt: Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date(),
            lastModified: Date()
        )
        
        mockTenants = [
            golfCourseTenant.id: golfCourseTenant,
            resortTenant.id: resortTenant
        ]
        
        availableTenants = Array(mockTenants.values)
        
        // Create usage metrics for each tenant
        createMockUsageMetrics(for: golfCourseTenant.id)
        createMockUsageMetrics(for: resortTenant.id)
    }
    
    private func createMockUsageMetrics(for tenantId: String) {
        let metrics = TenantUsageMetrics(
            tenantId: tenantId,
            activeUsers: Int.random(in: 25...150),
            dailyRounds: Int.random(in: 30...120),
            bookingsToday: Int.random(in: 15...75),
            revenueToday: Double.random(in: 850...3500),
            averageSessionDuration: TimeInterval.random(in: 900...2700), // 15-45 minutes
            featureUsageStats: [
                "booking": Int.random(in: 45...95),
                "scorecard": Int.random(in: 60...90),
                "weather": Int.random(in: 20...60),
                "gps": Int.random(in: 70...95),
                "leaderboard": Int.random(in: 30...70),
                "social": Int.random(in: 15...50)
            ],
            performanceMetrics: TenantPerformanceMetrics(
                averageResponseTime: Double.random(in: 0.1...0.8),
                errorRate: Double.random(in: 0.001...0.05),
                cacheHitRate: Double.random(in: 0.75...0.95),
                databaseQueryCount: Int.random(in: 50...300),
                memoryUsage: Double.random(in: 30...120),
                cpuUsage: Double.random(in: 5...35)
            ),
            lastUpdated: Date()
        )
        
        mockUsageMetrics[tenantId] = metrics
    }
    
    private func createDefaultUsageMetrics() -> TenantUsageMetrics {
        return TenantUsageMetrics(
            tenantId: "unknown",
            activeUsers: 0,
            dailyRounds: 0,
            bookingsToday: 0,
            revenueToday: 0,
            averageSessionDuration: 0,
            featureUsageStats: [:],
            performanceMetrics: TenantPerformanceMetrics(
                averageResponseTime: 0,
                errorRate: 0,
                cacheHitRate: 0,
                databaseQueryCount: 0,
                memoryUsage: 0,
                cpuUsage: 0
            ),
            lastUpdated: Date()
        )
    }
    
    private func trackOperation(_ operation: String) {
        operationMetrics[operation, default: 0] += 1
    }
    
    // MARK: - Testing Helpers
    
    func getTenantSwitchEvents() -> [(from: String?, to: String, timestamp: Date)] {
        return tenantSwitchEvents
    }
    
    func getThemeChangeEvents() -> [(from: WhiteLabelTheme, to: WhiteLabelTheme, timestamp: Date)] {
        return themeChangeEvents
    }
    
    func getOperationMetrics() -> [String: Int] {
        return operationMetrics
    }
    
    func resetMockData() {
        setupMockData()
        tenantSwitchEvents.removeAll()
        themeChangeEvents.removeAll()
        operationMetrics.removeAll()
        currentTenantSubject.send(nil)
        themeChangedSubject.send(.golfCourseDefault)
        isMultiTenantMode = false
    }
}

// MARK: - Mock Errors

enum MockTenantError: LocalizedError {
    case tenantNotFound
    case switchFailed
    case creationFailed
    case updateFailed
    case deletionFailed
    case themeUpdateFailed
    case configurationInvalid
    case noCurrentTenant
    case syncFailed
    
    var errorDescription: String? {
        switch self {
        case .tenantNotFound:
            return "Mock: Tenant not found"
        case .switchFailed:
            return "Mock: Failed to switch tenant"
        case .creationFailed:
            return "Mock: Failed to create tenant"
        case .updateFailed:
            return "Mock: Failed to update tenant"
        case .deletionFailed:
            return "Mock: Failed to delete tenant"
        case .themeUpdateFailed:
            return "Mock: Failed to update theme"
        case .configurationInvalid:
            return "Mock: Configuration is invalid"
        case .noCurrentTenant:
            return "Mock: No current tenant"
        case .syncFailed:
            return "Mock: Sync failed"
        }
    }
}