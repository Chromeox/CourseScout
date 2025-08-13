import Foundation
import WatchKit
import Combine
import os.log

// MARK: - Watch Tenant Configuration Service Protocol

protocol WatchTenantConfigurationServiceProtocol: AnyObject {
    // Current tenant context
    var currentTenantContext: WatchTenantContext { get }
    var isMultiTenantMode: Bool { get }
    
    // Tenant management
    func switchToTenant(_ context: WatchTenantContext) async
    func loadTenantFromiPhone(_ tenantId: String) async throws -> WatchTenantContext
    func syncTenantConfiguration() async throws
    func getCachedTenantContext(for tenantId: String) -> WatchTenantContext?
    
    // Offline tenant management
    func getAvailableOfflineTenants() -> [WatchTenantContext]
    func cacheTenantsForOfflineUse(_ tenants: [WatchTenantContext]) async
    func getLastUsedTenant() -> WatchTenantContext?
    
    // Business type specific features
    func getEnabledFeatures() -> WatchTenantFeatures
    func isFeatureEnabled(_ feature: WatchTenantFeature) -> Bool
    func getBusinessTypeCapabilities() -> WatchBusinessTypeCapabilities
    
    // Publishers
    var tenantDidChange: AnyPublisher<WatchTenantContext, Never> { get }
    var featuresDidChange: AnyPublisher<WatchTenantFeatures, Never> { get }
}

// MARK: - Watch Tenant Features Enum

enum WatchTenantFeature: String, CaseIterable {
    case scorecard = "scorecard"
    case gps = "gps"
    case workout = "workout"
    case haptics = "haptics"
    case complications = "complications"
    case notifications = "notifications"
    case premiumAnalytics = "premium_analytics"
    case concierge = "concierge"
    case memberServices = "member_services"
}

// MARK: - Business Type Capabilities

struct WatchBusinessTypeCapabilities {
    let businessType: WatchBusinessType
    let maxComplications: Int
    let supportsConcierge: Bool
    let supportsMemberServices: Bool
    let hasCustomBranding: Bool
    let hasAdvancedAnalytics: Bool
    let hapticPatternCount: Int
    
    static func capabilities(for businessType: WatchBusinessType) -> WatchBusinessTypeCapabilities {
        switch businessType {
        case .golfCourse:
            return WatchBusinessTypeCapabilities(
                businessType: businessType,
                maxComplications: 3,
                supportsConcierge: false,
                supportsMemberServices: false,
                hasCustomBranding: true,
                hasAdvancedAnalytics: false,
                hapticPatternCount: 5
            )
        case .golfResort:
            return WatchBusinessTypeCapabilities(
                businessType: businessType,
                maxComplications: 5,
                supportsConcierge: true,
                supportsMemberServices: false,
                hasCustomBranding: true,
                hasAdvancedAnalytics: true,
                hapticPatternCount: 8
            )
        case .countryClub:
            return WatchBusinessTypeCapabilities(
                businessType: businessType,
                maxComplications: 4,
                supportsConcierge: true,
                supportsMemberServices: true,
                hasCustomBranding: true,
                hasAdvancedAnalytics: true,
                hapticPatternCount: 10
            )
        case .publicCourse:
            return WatchBusinessTypeCapabilities(
                businessType: businessType,
                maxComplications: 2,
                supportsConcierge: false,
                supportsMemberServices: false,
                hasCustomBranding: false,
                hasAdvancedAnalytics: false,
                hapticPatternCount: 3
            )
        case .privateClub:
            return WatchBusinessTypeCapabilities(
                businessType: businessType,
                maxComplications: 6,
                supportsConcierge: true,
                supportsMemberServices: true,
                hasCustomBranding: true,
                hasAdvancedAnalytics: true,
                hapticPatternCount: 12
            )
        case .golfAcademy:
            return WatchBusinessTypeCapabilities(
                businessType: businessType,
                maxComplications: 3,
                supportsConcierge: false,
                supportsMemberServices: false,
                hasCustomBranding: true,
                hasAdvancedAnalytics: false,
                hapticPatternCount: 6
            )
        }
    }
}

// MARK: - Watch Tenant Configuration Service Implementation

@MainActor
class WatchTenantConfigurationService: WatchTenantConfigurationServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var currentTenantContext: WatchTenantContext = .defaultContext
    @Published private(set) var isMultiTenantMode: Bool = false
    
    // MARK: - Private Properties
    
    private let connectivityService: WatchConnectivityServiceProtocol
    private let cacheService: WatchCacheServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "TenantConfiguration")
    
    // MARK: - Publishers
    
    private let tenantSubject = CurrentValueSubject<WatchTenantContext, Never>(.defaultContext)
    private let featuresSubject = CurrentValueSubject<WatchTenantFeatures, Never>(.basicFeatures)
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Cache Management
    
    private var tenantCache: [String: WatchTenantContext] = [:]
    private var offlineTenants: [WatchTenantContext] = []
    private let cacheExpirationTime: TimeInterval = 3600 // 1 hour
    private var lastCacheUpdate: Date = Date()
    
    // MARK: - Initialization
    
    init(connectivityService: WatchConnectivityServiceProtocol, cacheService: WatchCacheServiceProtocol) {
        self.connectivityService = connectivityService
        self.cacheService = cacheService
        
        setupPublisherBindings()
        loadCachedConfiguration()
        
        logger.info("WatchTenantConfigurationService initialized")
    }
    
    // MARK: - Publishers
    
    var tenantDidChange: AnyPublisher<WatchTenantContext, Never> {
        tenantSubject.eraseToAnyPublisher()
    }
    
    var featuresDidChange: AnyPublisher<WatchTenantFeatures, Never> {
        featuresSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Tenant Management
    
    func switchToTenant(_ context: WatchTenantContext) async {
        logger.info("Switching to tenant: \(context.tenantId ?? "default")")
        
        currentTenantContext = context
        isMultiTenantMode = context.tenantId != nil
        
        // Update publishers
        tenantSubject.send(context)
        featuresSubject.send(context.features)
        
        // Cache the context
        if let tenantId = context.tenantId {
            tenantCache[tenantId] = context
            
            // Save to persistent cache
            await saveTenantContext(context)
            await saveLastUsedTenant(context)
        }
        
        logger.debug("Successfully switched to tenant: \(context.tenantId ?? "default")")
    }
    
    func loadTenantFromiPhone(_ tenantId: String) async throws -> WatchTenantContext {
        logger.info("Loading tenant from iPhone: \(tenantId)")
        
        // Check cache first
        if let cachedContext = getCachedTenantContext(for: tenantId) {
            logger.debug("Returning cached tenant context for: \(tenantId)")
            return cachedContext
        }
        
        // Request from iPhone via connectivity
        return try await withCheckedThrowingContinuation { continuation in
            let message: [String: Any] = [
                "type": "requestTenantConfiguration",
                "tenantId": tenantId,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            connectivityService.sendMessage(
                message,
                replyHandler: { [weak self] response in
                    Task { @MainActor in
                        do {
                            let context = try await self?.parseTenantResponse(response, tenantId: tenantId)
                            if let context = context {
                                // Cache the loaded context
                                self?.tenantCache[tenantId] = context
                                await self?.saveTenantContext(context)
                                continuation.resume(returning: context)
                            } else {
                                continuation.resume(throwing: WatchTenantError.invalidResponse)
                            }
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                },
                errorHandler: { error in
                    continuation.resume(throwing: error)
                }
            )
        }
    }
    
    func syncTenantConfiguration() async throws {
        guard let tenantId = currentTenantContext.tenantId else {
            logger.debug("No tenant to sync, using default configuration")
            return
        }
        
        do {
            let updatedContext = try await loadTenantFromiPhone(tenantId)
            await switchToTenant(updatedContext)
            logger.info("Successfully synced tenant configuration: \(tenantId)")
        } catch {
            logger.error("Failed to sync tenant configuration: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getCachedTenantContext(for tenantId: String) -> WatchTenantContext? {
        // Check memory cache
        if let cached = tenantCache[tenantId] {
            return cached
        }
        
        // Check if in offline tenants
        return offlineTenants.first { $0.tenantId == tenantId }
    }
    
    // MARK: - Offline Management
    
    func getAvailableOfflineTenants() -> [WatchTenantContext] {
        return offlineTenants
    }
    
    func cacheTenantsForOfflineUse(_ tenants: [WatchTenantContext]) async {
        offlineTenants = tenants
        
        // Save to persistent storage
        do {
            let data = try JSONEncoder().encode(tenants)
            await cacheService.store(key: "offline_tenants", value: data)
            logger.info("Cached \(tenants.count) tenants for offline use")
        } catch {
            logger.error("Failed to cache offline tenants: \(error.localizedDescription)")
        }
    }
    
    func getLastUsedTenant() -> WatchTenantContext? {
        // Try to load from cache
        guard let data: Data = try? await cacheService.retrieve(key: "last_used_tenant"),
              let context = try? JSONDecoder().decode(WatchTenantContext.self, from: data) else {
            return nil
        }
        
        return context
    }
    
    // MARK: - Feature Management
    
    func getEnabledFeatures() -> WatchTenantFeatures {
        return currentTenantContext.features
    }
    
    func isFeatureEnabled(_ feature: WatchTenantFeature) -> Bool {
        let features = currentTenantContext.features
        
        switch feature {
        case .scorecard: return features.enableScorecard
        case .gps: return features.enableGPS
        case .workout: return features.enableWorkout
        case .haptics: return features.enableHaptics
        case .complications: return features.enableComplications
        case .notifications: return features.enableNotifications
        case .premiumAnalytics: return features.enablePremiumAnalytics
        case .concierge: return features.enableConcierge
        case .memberServices: return features.enableMemberServices
        }
    }
    
    func getBusinessTypeCapabilities() -> WatchBusinessTypeCapabilities {
        return WatchBusinessTypeCapabilities.capabilities(for: currentTenantContext.businessType)
    }
    
    // MARK: - Private Helper Methods
    
    private func setupPublisherBindings() {
        tenantSubject.sink { [weak self] context in
            self?.currentTenantContext = context
            self?.isMultiTenantMode = context.tenantId != nil
        }.store(in: &cancellables)
    }
    
    private func loadCachedConfiguration() {
        Task {
            // Load offline tenants
            if let data: Data = try? await cacheService.retrieve(key: "offline_tenants"),
               let tenants = try? JSONDecoder().decode([WatchTenantContext].self, from: data) {
                offlineTenants = tenants
                logger.debug("Loaded \(tenants.count) offline tenants")
            }
            
            // Load last used tenant
            if let lastUsed = getLastUsedTenant() {
                await switchToTenant(lastUsed)
                logger.info("Restored last used tenant: \(lastUsed.tenantId ?? "default")")
            }
        }
    }
    
    private func parseTenantResponse(_ response: [String: Any], tenantId: String) async throws -> WatchTenantContext {
        guard let tenantData = response["tenantContext"] as? [String: Any] else {
            throw WatchTenantError.invalidResponse
        }
        
        // Parse basic tenant information
        let businessTypeRaw = tenantData["businessType"] as? String ?? "golf_course"
        let businessType = WatchBusinessType(rawValue: businessTypeRaw) ?? .golfCourse
        
        let databaseNamespace = tenantData["databaseNamespace"] as? String ?? "tenant_\(tenantId)"
        
        // Parse theme
        let themeData = tenantData["theme"] as? [String: Any] ?? [:]
        let theme = WatchTenantTheme(
            primaryColor: themeData["primaryColor"] as? String ?? "#2E7D32",
            secondaryColor: themeData["secondaryColor"] as? String ?? "#4CAF50",
            accentColor: themeData["accentColor"] as? String ?? "#8BC34A",
            textColor: themeData["textColor"] as? String ?? "#FFFFFF",
            backgroundColor: themeData["backgroundColor"] as? String ?? "#1B1B1B",
            fontFamily: themeData["fontFamily"] as? String ?? "San Francisco",
            logoURL: themeData["logoURL"] as? String
        )
        
        // Parse features based on business type
        let features: WatchTenantFeatures
        if businessType.hasEliteFeatures {
            features = .eliteFeatures
        } else if businessType.hasPremiumFeatures {
            features = .premiumFeatures
        } else {
            features = .basicFeatures
        }
        
        return WatchTenantContext(
            tenantId: tenantId,
            businessType: businessType,
            theme: theme,
            features: features,
            databaseNamespace: databaseNamespace
        )
    }
    
    private func saveTenantContext(_ context: WatchTenantContext) async {
        guard let tenantId = context.tenantId else { return }
        
        do {
            let data = try JSONEncoder().encode(context)
            await cacheService.store(key: "tenant_\(tenantId)", value: data)
        } catch {
            logger.error("Failed to save tenant context: \(error.localizedDescription)")
        }
    }
    
    private func saveLastUsedTenant(_ context: WatchTenantContext) async {
        do {
            let data = try JSONEncoder().encode(context)
            await cacheService.store(key: "last_used_tenant", value: data)
        } catch {
            logger.error("Failed to save last used tenant: \(error.localizedDescription)")
        }
    }
}

// MARK: - Mock Implementation

class MockWatchTenantConfigurationService: WatchTenantConfigurationServiceProtocol, ObservableObject {
    @Published private(set) var currentTenantContext: WatchTenantContext = .defaultContext
    @Published private(set) var isMultiTenantMode: Bool = false
    
    private let tenantSubject = CurrentValueSubject<WatchTenantContext, Never>(.defaultContext)
    private let featuresSubject = CurrentValueSubject<WatchTenantFeatures, Never>(.basicFeatures)
    
    var tenantDidChange: AnyPublisher<WatchTenantContext, Never> {
        tenantSubject.eraseToAnyPublisher()
    }
    
    var featuresDidChange: AnyPublisher<WatchTenantFeatures, Never> {
        featuresSubject.eraseToAnyPublisher()
    }
    
    func switchToTenant(_ context: WatchTenantContext) async {
        currentTenantContext = context
        isMultiTenantMode = context.tenantId != nil
        tenantSubject.send(context)
        featuresSubject.send(context.features)
    }
    
    func loadTenantFromiPhone(_ tenantId: String) async throws -> WatchTenantContext {
        // Return mock context based on tenant ID
        return WatchTenantContext(
            tenantId: tenantId,
            businessType: .countryClub,
            theme: .defaultTheme,
            features: .premiumFeatures,
            databaseNamespace: "tenant_\(tenantId)"
        )
    }
    
    func syncTenantConfiguration() async throws {
        // Mock sync - no operation
    }
    
    func getCachedTenantContext(for tenantId: String) -> WatchTenantContext? {
        return nil
    }
    
    func getAvailableOfflineTenants() -> [WatchTenantContext] {
        return [
            WatchTenantContext(
                tenantId: "mock_golf_resort",
                businessType: .golfResort,
                theme: .defaultTheme,
                features: .premiumFeatures,
                databaseNamespace: "tenant_mock_golf_resort"
            ),
            WatchTenantContext(
                tenantId: "mock_country_club",
                businessType: .countryClub,
                theme: .defaultTheme,
                features: .eliteFeatures,
                databaseNamespace: "tenant_mock_country_club"
            )
        ]
    }
    
    func cacheTenantsForOfflineUse(_ tenants: [WatchTenantContext]) async {
        // Mock caching - no operation
    }
    
    func getLastUsedTenant() -> WatchTenantContext? {
        return nil
    }
    
    func getEnabledFeatures() -> WatchTenantFeatures {
        return currentTenantContext.features
    }
    
    func isFeatureEnabled(_ feature: WatchTenantFeature) -> Bool {
        return true // Mock always returns enabled
    }
    
    func getBusinessTypeCapabilities() -> WatchBusinessTypeCapabilities {
        return WatchBusinessTypeCapabilities.capabilities(for: currentTenantContext.businessType)
    }
}

// MARK: - Watch Tenant Errors

enum WatchTenantError: LocalizedError {
    case invalidResponse
    case tenantNotFound
    case syncFailed
    case cacheError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid tenant response from iPhone"
        case .tenantNotFound:
            return "Tenant not found"
        case .syncFailed:
            return "Failed to sync tenant configuration"
        case .cacheError:
            return "Failed to access tenant cache"
        }
    }
}