import Foundation
import Combine
import SwiftUI
import Appwrite

// MARK: - Tenant Configuration Service Implementation

@MainActor
class TenantConfigurationService: TenantConfigurationServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var currentTenant: TenantConfiguration?
    @Published private(set) var currentTheme: WhiteLabelTheme = .golfCourseDefault
    @Published private(set) var availableTenants: [TenantConfiguration] = []
    @Published private(set) var isMultiTenantMode: Bool = false
    
    // MARK: - Private Properties
    private let appwriteClient: Client
    private let databaseId = "golf-finder-db"
    private let tenantCollectionId = "tenant-configurations"
    private let cacheService: CacheServiceProtocol
    private let analyticsService: AnalyticsServiceProtocol
    private let securityService: SecurityServiceProtocol
    
    // MARK: - Reactive Publishers
    private let currentTenantSubject = CurrentValueSubject<TenantConfiguration?, Never>(nil)
    private let themeChangedSubject = CurrentValueSubject<WhiteLabelTheme, Never>(.golfCourseDefault)
    private let tenantSwitchedSubject = CurrentValueSubject<String?, Never>(nil)
    
    // MARK: - Preview Management
    private var previewedTheme: WhiteLabelTheme?
    private var originalTheme: WhiteLabelTheme?
    
    // MARK: - Performance Metrics
    private var tenantSwitchStartTime: Date?
    private var configurationCache: [String: TenantConfiguration] = [:]
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes
    private var lastCacheUpdate: Date = Date()
    
    // MARK: - Initialization
    
    init(appwriteClient: Client, 
         cacheService: CacheServiceProtocol,
         analyticsService: AnalyticsServiceProtocol,
         securityService: SecurityServiceProtocol) {
        self.appwriteClient = appwriteClient
        self.cacheService = cacheService
        self.analyticsService = analyticsService
        self.securityService = securityService
        
        // Set up reactive bindings
        currentTenantSubject.sink { [weak self] tenant in
            self?.currentTenant = tenant
        }.store(in: &cancellables)
        
        themeChangedSubject.sink { [weak self] theme in
            self?.currentTheme = theme
        }.store(in: &cancellables)
        
        // Initialize with default configuration
        Task {
            await loadDefaultConfiguration()
        }
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
        // Check cache first
        if let cachedTenant = getCachedTenant(id: id) {
            return cachedTenant
        }
        
        let databases = Databases(appwriteClient)
        
        do {
            let document = try await databases.getDocument(
                databaseId: databaseId,
                collectionId: tenantCollectionId,
                documentId: id
            )
            
            let configuration = try parseTenantDocument(document)
            
            // Cache the configuration
            configurationCache[id] = configuration
            lastCacheUpdate = Date()
            
            return configuration
            
        } catch {
            analyticsService.track("tenant_load_error", parameters: [
                "tenant_id": id,
                "error": error.localizedDescription
            ])
            throw TenantConfigurationError.tenantNotFound(id: id)
        }
    }
    
    func switchTenant(to tenantId: String) async throws {
        tenantSwitchStartTime = Date()
        
        // Validate tenant access
        guard validateTenantAccess(for: tenantId) else {
            throw TenantConfigurationError.accessDenied(tenantId: tenantId)
        }
        
        let previousTenantId = currentTenant?.id
        
        do {
            let tenant = try await loadTenant(by: tenantId)
            
            // Switch tenant context
            currentTenantSubject.send(tenant)
            themeChangedSubject.send(tenant.theme)
            tenantSwitchedSubject.send(tenantId)
            
            // Update multi-tenant mode
            isMultiTenantMode = true
            
            // Track the switch
            trackTenantSwitch(from: previousTenantId, to: tenantId)
            
            // Store in cache for quick access
            try await cacheService.store(key: "current_tenant_id", value: tenantId)
            
        } catch {
            analyticsService.track("tenant_switch_error", parameters: [
                "tenant_id": tenantId,
                "error": error.localizedDescription
            ])
            throw error
        }
    }
    
    func createTenant(_ configuration: TenantConfiguration) async throws {
        let validation = validateTenant(configuration)
        guard validation.isValid else {
            throw TenantConfigurationError.invalidConfiguration(errors: validation.errors)
        }
        
        let databases = Databases(appwriteClient)
        
        do {
            let documentData = try encodeTenantConfiguration(configuration)
            
            _ = try await databases.createDocument(
                databaseId: databaseId,
                collectionId: tenantCollectionId,
                documentId: configuration.id,
                data: documentData
            )
            
            // Add to available tenants
            availableTenants.append(configuration)
            
            // Cache the new tenant
            configurationCache[configuration.id] = configuration
            
            analyticsService.track("tenant_created", parameters: [
                "tenant_id": configuration.id,
                "business_type": configuration.businessInfo.businessType.rawValue
            ])
            
        } catch {
            analyticsService.track("tenant_creation_error", parameters: [
                "tenant_id": configuration.id,
                "error": error.localizedDescription
            ])
            throw TenantConfigurationError.creationFailed(error: error)
        }
    }
    
    func updateTenant(_ configuration: TenantConfiguration) async throws {
        let validation = validateTenant(configuration)
        guard validation.isValid else {
            throw TenantConfigurationError.invalidConfiguration(errors: validation.errors)
        }
        
        let databases = Databases(appwriteClient)
        
        do {
            let documentData = try encodeTenantConfiguration(configuration)
            
            _ = try await databases.updateDocument(
                databaseId: databaseId,
                collectionId: tenantCollectionId,
                documentId: configuration.id,
                data: documentData
            )
            
            // Update cache
            configurationCache[configuration.id] = configuration
            
            // If this is the current tenant, update the theme
            if currentTenant?.id == configuration.id {
                currentTenantSubject.send(configuration)
                themeChangedSubject.send(configuration.theme)
            }
            
            analyticsService.track("tenant_updated", parameters: [
                "tenant_id": configuration.id
            ])
            
        } catch {
            analyticsService.track("tenant_update_error", parameters: [
                "tenant_id": configuration.id,
                "error": error.localizedDescription
            ])
            throw TenantConfigurationError.updateFailed(error: error)
        }
    }
    
    func deleteTenant(id: String) async throws {
        let databases = Databases(appwriteClient)
        
        do {
            try await databases.deleteDocument(
                databaseId: databaseId,
                collectionId: tenantCollectionId,
                documentId: id
            )
            
            // Remove from available tenants
            availableTenants.removeAll { $0.id == id }
            
            // Remove from cache
            configurationCache.removeValue(forKey: id)
            
            // If this was the current tenant, reset
            if currentTenant?.id == id {
                await resetToDefaultConfiguration()
            }
            
            analyticsService.track("tenant_deleted", parameters: [
                "tenant_id": id
            ])
            
        } catch {
            analyticsService.track("tenant_deletion_error", parameters: [
                "tenant_id": id,
                "error": error.localizedDescription
            ])
            throw TenantConfigurationError.deletionFailed(error: error)
        }
    }
    
    func validateTenant(_ configuration: TenantConfiguration) -> TenantValidationResult {
        var errors: [TenantValidationError] = []
        var warnings: [TenantValidationWarning] = []
        
        // Required field validation
        if configuration.id.isEmpty {
            errors.append(.missingTenantId)
        }
        
        if configuration.domain.isEmpty || !isValidDomain(configuration.domain) {
            errors.append(.invalidDomain)
        }
        
        if configuration.databaseNamespace.isEmpty {
            errors.append(.missingDatabaseNamespace)
        }
        
        if !configuration.theme.isComplete {
            errors.append(.invalidTheme)
        }
        
        if !configuration.branding.hasValidLogo {
            errors.append(.missingBranding)
        }
        
        // Business info validation
        if configuration.businessInfo.businessName.isEmpty ||
           configuration.businessInfo.contactEmail.isEmpty {
            errors.append(.invalidBusinessInfo)
        }
        
        // Warning conditions
        if configuration.branding.tagline.isEmpty {
            warnings.append(.missingOptionalBranding)
        }
        
        if configuration.subscriptionTier == .starter {
            warnings.append(.lowSubscriptionTier)
        }
        
        // Theme contrast validation
        if !hasGoodContrast(configuration.theme) {
            warnings.append(.suboptimalThemeColors)
        }
        
        return TenantValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    // MARK: - Theme Management
    
    func updateTheme(_ theme: WhiteLabelTheme) async throws {
        let previousTheme = currentTheme
        
        // Validate theme
        guard theme.isComplete else {
            throw TenantConfigurationError.invalidTheme
        }
        
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
            // Update theme directly if no current tenant
            themeChangedSubject.send(theme)
        }
        
        trackThemeChange(from: previousTheme, to: theme)
    }
    
    func resetToDefaultTheme() async {
        let defaultTheme = WhiteLabelTheme.golfCourseDefault
        try? await updateTheme(defaultTheme)
    }
    
    func previewTheme(_ theme: WhiteLabelTheme) async {
        originalTheme = currentTheme
        previewedTheme = theme
        themeChangedSubject.send(theme)
    }
    
    func commitPreviewedTheme() async {
        if let previewedTheme = previewedTheme {
            try? await updateTheme(previewedTheme)
        }
        clearPreviewState()
    }
    
    func discardPreviewedTheme() async {
        if let originalTheme = originalTheme {
            themeChangedSubject.send(originalTheme)
        }
        clearPreviewState()
    }
    
    // MARK: - Multi-tenant Data Management
    
    func getTenantDatabaseNamespace() -> String {
        return currentTenant?.databaseNamespace ?? "default"
    }
    
    func getTenantAPIKey() -> String {
        guard let tenant = currentTenant else { return "" }
        return "\(tenant.apiKeyPrefix)_\(tenant.id)"
    }
    
    func isolateTenantData<T: Codable>(data: T, for tenantId: String) -> T {
        // In a real implementation, this would add tenant-specific metadata
        // For now, return the data as-is since it's handled at the service level
        return data
    }
    
    func validateTenantAccess(for tenantId: String) -> Bool {
        // Implement tenant access validation
        // Check user permissions, subscription status, etc.
        return true // Simplified for demo
    }
    
    // MARK: - Configuration Management
    
    func validateConfiguration() throws {
        guard let tenant = currentTenant else {
            throw TenantConfigurationError.noCurrentTenant
        }
        
        let validation = validateTenant(tenant)
        if validation.hasErrors {
            throw TenantConfigurationError.invalidConfiguration(errors: validation.errors)
        }
    }
    
    func getConfigurationHealth() -> TenantConfigurationHealth {
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
            overallHealth: validation.isHealthy ? .excellent : (validation.hasErrors ? .critical : .warning),
            themeHealth: tenant.theme.isComplete ? .excellent : .warning,
            brandingHealth: tenant.branding.hasValidLogo ? .excellent : .warning,
            businessInfoHealth: !tenant.businessInfo.businessName.isEmpty ? .excellent : .warning,
            featuresHealth: tenant.features.hasBasicFeatures ? .excellent : .warning,
            performanceScore: calculatePerformanceScore(tenant),
            lastHealthCheck: Date()
        )
    }
    
    func syncTenantConfiguration() async throws {
        guard let tenantId = currentTenant?.id else { return }
        
        do {
            let updatedTenant = try await loadTenant(by: tenantId)
            currentTenantSubject.send(updatedTenant)
            themeChangedSubject.send(updatedTenant.theme)
        } catch {
            throw TenantConfigurationError.syncFailed(error: error)
        }
    }
    
    // MARK: - Analytics and Monitoring
    
    func trackTenantSwitch(from previousTenantId: String?, to newTenantId: String) {
        let switchDuration = tenantSwitchStartTime?.timeIntervalSinceNow ?? 0
        
        analyticsService.track("tenant_switched", parameters: [
            "previous_tenant_id": previousTenantId ?? "none",
            "new_tenant_id": newTenantId,
            "switch_duration": abs(switchDuration)
        ])
    }
    
    func trackThemeChange(from previousTheme: WhiteLabelTheme, to newTheme: WhiteLabelTheme) {
        analyticsService.track("theme_changed", parameters: [
            "previous_primary_color": previousTheme.primaryColor.hex,
            "new_primary_color": newTheme.primaryColor.hex,
            "font_family": newTheme.fontFamily
        ])
    }
    
    func getTenantUsageMetrics() async -> TenantUsageMetrics {
        guard let tenant = currentTenant else {
            return TenantUsageMetrics(
                tenantId: "",
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
        
        // In a real implementation, this would fetch actual metrics
        return TenantUsageMetrics(
            tenantId: tenant.id,
            activeUsers: 42,
            dailyRounds: 18,
            bookingsToday: 25,
            revenueToday: 1250.0,
            averageSessionDuration: 1800, // 30 minutes
            featureUsageStats: [
                "booking": 89,
                "scorecard": 65,
                "weather": 34,
                "gps": 78
            ],
            performanceMetrics: TenantPerformanceMetrics(
                averageResponseTime: 0.25,
                errorRate: 0.01,
                cacheHitRate: 0.85,
                databaseQueryCount: 152,
                memoryUsage: 64.5,
                cpuUsage: 12.3
            ),
            lastUpdated: Date()
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func loadDefaultConfiguration() async {
        // Try to load the last used tenant
        if let cachedTenantId: String = try? await cacheService.retrieve(key: "current_tenant_id"),
           let tenant = try? await loadTenant(by: cachedTenantId) {
            currentTenantSubject.send(tenant)
            themeChangedSubject.send(tenant.theme)
        } else {
            // Use default theme
            themeChangedSubject.send(.golfCourseDefault)
        }
    }
    
    private func resetToDefaultConfiguration() async {
        currentTenantSubject.send(nil)
        themeChangedSubject.send(.golfCourseDefault)
        isMultiTenantMode = false
        
        try? await cacheService.remove(key: "current_tenant_id")
    }
    
    private func getCachedTenant(id: String) -> TenantConfiguration? {
        let cacheAge = Date().timeIntervalSince(lastCacheUpdate)
        guard cacheAge < cacheExpirationTime else {
            configurationCache.removeAll()
            lastCacheUpdate = Date()
            return nil
        }
        
        return configurationCache[id]
    }
    
    private func parseTenantDocument(_ document: Document) throws -> TenantConfiguration {
        let data = document.data
        
        // Parse the document data into TenantConfiguration
        // This is simplified - in a real app you'd have proper JSON decoding
        
        guard let id = data["id"] as? String,
              let name = data["name"] as? String,
              let displayName = data["display_name"] as? String,
              let domain = data["domain"] as? String else {
            throw TenantConfigurationError.invalidDocumentFormat
        }
        
        // For demo purposes, return a basic configuration
        return TenantConfiguration(
            id: id,
            name: name,
            displayName: displayName,
            domain: domain,
            theme: .golfCourseDefault,
            branding: TenantBranding(
                logoURL: "https://example.com/logo.png",
                faviconURL: "https://example.com/favicon.ico",
                appIconURL: "https://example.com/app-icon.png",
                heroImageURL: nil,
                backgroundImageURL: nil,
                tagline: "Your Golf Experience",
                description: "Professional golf course management",
                welcomeMessage: "Welcome to our golf course!",
                websiteURL: "https://example.com",
                facebookURL: nil,
                instagramURL: nil,
                twitterURL: nil
            ),
            businessInfo: TenantBusinessInfo(
                businessName: displayName,
                businessType: .golfCourse,
                contactEmail: "info@\(domain)",
                contactPhone: "+1-555-0123",
                address: BusinessAddress(
                    street: "123 Golf Course Dr",
                    city: "Golf City",
                    state: "GS",
                    zipCode: "12345",
                    country: "USA",
                    latitude: 37.7749,
                    longitude: -122.4194
                ),
                timeZone: "America/New_York",
                currency: "USD",
                locale: "en_US",
                courseCount: 1,
                membershipCount: 500,
                averageRoundsPerDay: 50
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
            databaseNamespace: "tenant_\(id)",
            apiKeyPrefix: "gf_\(id)",
            isActive: true,
            subscriptionTier: .professional,
            createdAt: Date(),
            lastModified: Date()
        )
    }
    
    private func encodeTenantConfiguration(_ configuration: TenantConfiguration) throws -> [String: Any] {
        // In a real implementation, this would properly encode the configuration
        return [
            "id": configuration.id,
            "name": configuration.name,
            "display_name": configuration.displayName,
            "domain": configuration.domain,
            "is_active": configuration.isActive,
            "subscription_tier": configuration.subscriptionTier.rawValue,
            "database_namespace": configuration.databaseNamespace,
            "api_key_prefix": configuration.apiKeyPrefix,
            "created_at": configuration.createdAt.timeIntervalSince1970,
            "last_modified": Date().timeIntervalSince1970
        ]
    }
    
    private func isValidDomain(_ domain: String) -> Bool {
        let domainRegex = "^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", domainRegex).evaluate(with: domain)
    }
    
    private func hasGoodContrast(_ theme: WhiteLabelTheme) -> Bool {
        // Simplified contrast checking - in a real app you'd calculate actual contrast ratios
        return !theme.primaryColor.hex.isEmpty && !theme.textColor.hex.isEmpty
    }
    
    private func calculatePerformanceScore(_ tenant: TenantConfiguration) -> Double {
        var score = 100.0
        
        // Deduct points for missing optimizations
        if tenant.features.enabledFeaturesCount > 12 {
            score -= 10 // Too many features enabled
        }
        
        if !tenant.features.enableOfflineMode {
            score -= 5 // No offline caching
        }
        
        return max(0, score)
    }
    
    private func clearPreviewState() {
        previewedTheme = nil
        originalTheme = nil
    }
}

// MARK: - Configuration Errors

enum TenantConfigurationError: LocalizedError {
    case tenantNotFound(id: String)
    case accessDenied(tenantId: String)
    case invalidConfiguration(errors: [TenantValidationError])
    case creationFailed(error: Error)
    case updateFailed(error: Error)
    case deletionFailed(error: Error)
    case syncFailed(error: Error)
    case noCurrentTenant
    case invalidTheme
    case invalidDocumentFormat
    
    var errorDescription: String? {
        switch self {
        case .tenantNotFound(let id):
            return "Tenant not found: \(id)"
        case .accessDenied(let tenantId):
            return "Access denied for tenant: \(tenantId)"
        case .invalidConfiguration(let errors):
            return "Invalid configuration: \(errors.map { $0.localizedDescription }.joined(separator: ", "))"
        case .creationFailed(let error):
            return "Failed to create tenant: \(error.localizedDescription)"
        case .updateFailed(let error):
            return "Failed to update tenant: \(error.localizedDescription)"
        case .deletionFailed(let error):
            return "Failed to delete tenant: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Failed to sync configuration: \(error.localizedDescription)"
        case .noCurrentTenant:
            return "No current tenant configured"
        case .invalidTheme:
            return "Invalid theme configuration"
        case .invalidDocumentFormat:
            return "Invalid document format"
        }
    }
}