import Foundation
import Combine
import SwiftUI

// MARK: - Tenant Configuration Service Protocol

protocol TenantConfigurationServiceProtocol: AnyObject {
    // MARK: - Published Properties
    var currentTenant: TenantConfiguration? { get }
    var currentTheme: WhiteLabelTheme { get }
    var availableTenants: [TenantConfiguration] { get }
    var isMultiTenantMode: Bool { get }
    
    // MARK: - Publishers for Reactive Updates
    var currentTenantPublisher: AnyPublisher<TenantConfiguration?, Never> { get }
    var themeChangedPublisher: AnyPublisher<WhiteLabelTheme, Never> { get }
    var tenantSwitchedPublisher: AnyPublisher<String?, Never> { get }
    
    // MARK: - Tenant Management
    func loadTenant(by id: String) async throws -> TenantConfiguration
    func switchTenant(to tenantId: String) async throws
    func createTenant(_ configuration: TenantConfiguration) async throws
    func updateTenant(_ configuration: TenantConfiguration) async throws
    func deleteTenant(id: String) async throws
    func validateTenant(_ configuration: TenantConfiguration) -> TenantValidationResult
    
    // MARK: - Theme Management
    func updateTheme(_ theme: WhiteLabelTheme) async throws
    func resetToDefaultTheme() async
    func previewTheme(_ theme: WhiteLabelTheme) async
    func commitPreviewedTheme() async
    func discardPreviewedTheme() async
    
    // MARK: - Multi-tenant Data Management
    func getTenantDatabaseNamespace() -> String
    func getTenantAPIKey() -> String
    func isolateTenantData<T: Codable>(data: T, for tenantId: String) -> T
    func validateTenantAccess(for tenantId: String) -> Bool
    
    // MARK: - Configuration Validation
    func validateConfiguration() throws
    func getConfigurationHealth() -> TenantConfigurationHealth
    func syncTenantConfiguration() async throws
    
    // MARK: - Analytics and Monitoring
    func trackTenantSwitch(from: String?, to: String)
    func trackThemeChange(from: WhiteLabelTheme, to: WhiteLabelTheme)
    func getTenantUsageMetrics() async -> TenantUsageMetrics
}

// MARK: - Supporting Data Structures

struct TenantValidationResult {
    let isValid: Bool
    let errors: [TenantValidationError]
    let warnings: [TenantValidationWarning]
    
    var hasErrors: Bool { !errors.isEmpty }
    var hasWarnings: Bool { !warnings.isEmpty }
    var isHealthy: Bool { isValid && errors.isEmpty }
}

enum TenantValidationError: LocalizedError {
    case missingTenantId
    case invalidDomain
    case missingBranding
    case invalidTheme
    case insufficientPermissions
    case subscriptionExpired
    case invalidBusinessInfo
    case missingDatabaseNamespace
    
    var errorDescription: String? {
        switch self {
        case .missingTenantId:
            return "Tenant ID is required"
        case .invalidDomain:
            return "Domain format is invalid"
        case .missingBranding:
            return "Branding configuration is incomplete"
        case .invalidTheme:
            return "Theme configuration is invalid"
        case .insufficientPermissions:
            return "Insufficient permissions for this tenant"
        case .subscriptionExpired:
            return "Tenant subscription has expired"
        case .invalidBusinessInfo:
            return "Business information is incomplete"
        case .missingDatabaseNamespace:
            return "Database namespace is required"
        }
    }
}

enum TenantValidationWarning {
    case missingOptionalBranding
    case suboptimalThemeColors
    case incompleteBusinessInfo
    case lowSubscriptionTier
    case performanceImpact
    
    var description: String {
        switch self {
        case .missingOptionalBranding:
            return "Some optional branding elements are missing"
        case .suboptimalThemeColors:
            return "Theme colors may not provide optimal contrast"
        case .incompleteBusinessInfo:
            return "Business information could be more complete"
        case .lowSubscriptionTier:
            return "Current subscription tier limits available features"
        case .performanceImpact:
            return "Current configuration may impact performance"
        }
    }
}

struct TenantConfigurationHealth {
    let overallHealth: HealthStatus
    let themeHealth: HealthStatus
    let brandingHealth: HealthStatus
    let businessInfoHealth: HealthStatus
    let featuresHealth: HealthStatus
    let performanceScore: Double
    let lastHealthCheck: Date
    
    enum HealthStatus {
        case excellent
        case good
        case warning
        case critical
        
        var displayName: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .warning: return "Warning"
            case .critical: return "Critical"
            }
        }
        
        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }
}

struct TenantUsageMetrics {
    let tenantId: String
    let activeUsers: Int
    let dailyRounds: Int
    let bookingsToday: Int
    let revenueToday: Double
    let averageSessionDuration: TimeInterval
    let featureUsageStats: [String: Int]
    let performanceMetrics: TenantPerformanceMetrics
    let lastUpdated: Date
}

struct TenantPerformanceMetrics {
    let averageResponseTime: TimeInterval
    let errorRate: Double
    let cacheHitRate: Double
    let databaseQueryCount: Int
    let memoryUsage: Double
    let cpuUsage: Double
}

// MARK: - Tenant Context

@MainActor
class TenantContext: ObservableObject {
    @Published private(set) var currentTenant: TenantConfiguration?
    @Published private(set) var currentTheme: WhiteLabelTheme
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private let configurationService: TenantConfigurationServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(configurationService: TenantConfigurationServiceProtocol) {
        self.configurationService = configurationService
        self.currentTheme = configurationService.currentTheme
        
        // Subscribe to configuration changes
        configurationService.currentTenantPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTenant)
        
        configurationService.themeChangedPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTheme)
    }
    
    func switchTenant(to tenantId: String) async {
        isLoading = true
        error = nil
        
        do {
            try await configurationService.switchTenant(to: tenantId)
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    func updateTheme(_ theme: WhiteLabelTheme) async {
        isLoading = true
        error = nil
        
        do {
            try await configurationService.updateTheme(theme)
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
}

// MARK: - SwiftUI Environment Integration

private struct TenantContextKey: EnvironmentKey {
    static let defaultValue: TenantContext? = nil
}

extension EnvironmentValues {
    var tenantContext: TenantContext? {
        get { self[TenantContextKey.self] }
        set { self[TenantContextKey.self] = newValue }
    }
}

// MARK: - Property Wrappers for Tenant Access

@propertyWrapper
struct TenantInjected<T> {
    private let keyPath: KeyPath<TenantConfiguration, T>
    private let defaultValue: T
    
    init(_ keyPath: KeyPath<TenantConfiguration, T>, default defaultValue: T) {
        self.keyPath = keyPath
        self.defaultValue = defaultValue
    }
    
    var wrappedValue: T {
        guard let tenant = ServiceContainer.shared.resolve(TenantConfigurationServiceProtocol.self).currentTenant else {
            return defaultValue
        }
        return tenant[keyPath: keyPath]
    }
}

@propertyWrapper
struct ThemeInjected<T> {
    private let keyPath: KeyPath<WhiteLabelTheme, T>
    
    init(_ keyPath: KeyPath<WhiteLabelTheme, T>) {
        self.keyPath = keyPath
    }
    
    var wrappedValue: T {
        let theme = ServiceContainer.shared.resolve(TenantConfigurationServiceProtocol.self).currentTheme
        return theme[keyPath: keyPath]
    }
}

// MARK: - View Modifiers for Tenant Theming

struct TenantThemedView: ViewModifier {
    @TenantInjected(\.theme) private var theme: WhiteLabelTheme
    
    func body(content: Content) -> some View {
        content
            .background(theme.backgroundSwiftUIColor)
            .foregroundColor(theme.textSwiftUIColor)
            .font(.system(size: 16, weight: theme.bodyFontWeight.swiftUIWeight))
    }
}

struct TenantThemedButton: ViewModifier {
    @TenantInjected(\.theme) private var theme: WhiteLabelTheme
    let isSecondary: Bool
    
    init(isSecondary: Bool = false) {
        self.isSecondary = isSecondary
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                isSecondary ? theme.secondarySwiftUIColor : theme.primarySwiftUIColor
            )
            .foregroundColor(.white)
            .cornerRadius(theme.buttonStyle.cornerRadius)
            .font(.system(size: 16, weight: .medium))
            .shadow(
                color: .black.opacity(theme.buttonStyle.shadowEnabled ? 0.1 : 0),
                radius: 2,
                x: 0,
                y: 1
            )
    }
}

extension View {
    func tenantThemed() -> some View {
        modifier(TenantThemedView())
    }
    
    func tenantThemedButton(isSecondary: Bool = false) -> some View {
        modifier(TenantThemedButton(isSecondary: isSecondary))
    }
}