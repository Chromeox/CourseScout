import SwiftUI
import Combine

// MARK: - Customization Manager

@MainActor
class CustomizationManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var currentCustomization: TenantCustomization?
    @Published private(set) var availableThemes: [WhiteLabelTheme] = []
    @Published private(set) var isPreviewMode = false
    @Published private(set) var previewConfiguration: TenantConfiguration?
    
    // MARK: - Services
    @ServiceInjected(TenantConfigurationServiceProtocol.self)
    private var tenantService: TenantConfigurationServiceProtocol
    
    @ServiceInjected(HapticFeedbackServiceProtocol.self)
    private var hapticService: HapticFeedbackServiceProtocol
    
    // MARK: - Reactive State
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        setupAvailableThemes()
        subscribeToTenantChanges()
    }
    
    // MARK: - Theme Management
    
    func applyTheme(_ theme: WhiteLabelTheme, animated: Bool = true) async {
        hapticService.impact(.light)
        
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                Task {
                    try? await tenantService.updateTheme(theme)
                }
            }
        } else {
            try? await tenantService.updateTheme(theme)
        }
    }
    
    func previewTheme(_ theme: WhiteLabelTheme) async {
        hapticService.impact(.light)
        isPreviewMode = true
        await tenantService.previewTheme(theme)
    }
    
    func commitPreview() async {
        hapticService.notification(.success)
        await tenantService.commitPreviewedTheme()
        isPreviewMode = false
    }
    
    func discardPreview() async {
        hapticService.impact(.medium)
        await tenantService.discardPreviewedTheme()
        isPreviewMode = false
    }
    
    func resetToDefault() async {
        hapticService.impact(.medium)
        await tenantService.resetToDefaultTheme()
    }
    
    // MARK: - Customization Operations
    
    func updateBranding(_ branding: TenantBranding) async throws {
        guard var tenant = tenantService.currentTenant else {
            throw CustomizationError.noCurrentTenant
        }
        
        tenant = TenantConfiguration(
            id: tenant.id,
            name: tenant.name,
            displayName: tenant.displayName,
            domain: tenant.domain,
            theme: tenant.theme,
            branding: branding,
            businessInfo: tenant.businessInfo,
            features: tenant.features,
            databaseNamespace: tenant.databaseNamespace,
            apiKeyPrefix: tenant.apiKeyPrefix,
            isActive: tenant.isActive,
            subscriptionTier: tenant.subscriptionTier,
            createdAt: tenant.createdAt,
            lastModified: Date()
        )
        
        try await tenantService.updateTenant(tenant)
        hapticService.notification(.success)
    }
    
    func updateFeatures(_ features: TenantFeatures) async throws {
        guard var tenant = tenantService.currentTenant else {
            throw CustomizationError.noCurrentTenant
        }
        
        tenant = TenantConfiguration(
            id: tenant.id,
            name: tenant.name,
            displayName: tenant.displayName,
            domain: tenant.domain,
            theme: tenant.theme,
            branding: tenant.branding,
            businessInfo: tenant.businessInfo,
            features: features,
            databaseNamespace: tenant.databaseNamespace,
            apiKeyPrefix: tenant.apiKeyPrefix,
            isActive: tenant.isActive,
            subscriptionTier: tenant.subscriptionTier,
            createdAt: tenant.createdAt,
            lastModified: Date()
        )
        
        try await tenantService.updateTenant(tenant)
        hapticService.notification(.success)
    }
    
    func generateCustomTheme(
        primaryColor: Color,
        accentColor: Color? = nil,
        fontFamily: String? = nil
    ) -> WhiteLabelTheme {
        let baseTheme = tenantService.currentTheme
        let resolvedAccentColor = accentColor ?? primaryColor.opacity(0.7)
        let resolvedFontFamily = fontFamily ?? baseTheme.fontFamily
        
        return WhiteLabelTheme(
            primaryColor: ColorHex(primaryColor.toHex()),
            secondaryColor: baseTheme.secondaryColor,
            accentColor: ColorHex(resolvedAccentColor.toHex()),
            backgroundColor: baseTheme.backgroundColor,
            surfaceColor: baseTheme.surfaceColor,
            textColor: baseTheme.textColor,
            subtextColor: baseTheme.subtextColor,
            successColor: baseTheme.successColor,
            warningColor: baseTheme.warningColor,
            errorColor: baseTheme.errorColor,
            fontFamily: resolvedFontFamily,
            headerFontWeight: baseTheme.headerFontWeight,
            bodyFontWeight: baseTheme.bodyFontWeight,
            cornerRadius: baseTheme.cornerRadius,
            borderWidth: baseTheme.borderWidth,
            shadowOpacity: baseTheme.shadowOpacity,
            buttonStyle: baseTheme.buttonStyle,
            cardStyle: baseTheme.cardStyle,
            navigationStyle: baseTheme.navigationStyle
        )
    }
    
    func exportCustomization() -> TenantCustomizationExport? {
        guard let tenant = tenantService.currentTenant else { return nil }
        
        return TenantCustomizationExport(
            tenantId: tenant.id,
            theme: tenant.theme,
            branding: tenant.branding,
            features: tenant.features,
            exportDate: Date(),
            version: "1.0"
        )
    }
    
    func importCustomization(_ export: TenantCustomizationExport) async throws {
        guard let tenant = tenantService.currentTenant else {
            throw CustomizationError.noCurrentTenant
        }
        
        // Update theme
        try await tenantService.updateTheme(export.theme)
        
        // Update branding
        try await updateBranding(export.branding)
        
        // Update features
        try await updateFeatures(export.features)
        
        hapticService.notification(.success)
    }
    
    // MARK: - Template Management
    
    func getTemplates() -> [TenantTemplate] {
        return [
            .golfCourseClassic,
            .golfCourseModern,
            .resortLuxury,
            .countryClubTraditional,
            .publicCourseAccessible
        ]
    }
    
    func applyTemplate(_ template: TenantTemplate) async throws {
        guard let tenant = tenantService.currentTenant else {
            throw CustomizationError.noCurrentTenant
        }
        
        let updatedTenant = template.apply(to: tenant)
        try await tenantService.updateTenant(updatedTenant)
        
        hapticService.notification(.success)
    }
    
    // MARK: - Private Methods
    
    private func setupAvailableThemes() {
        availableThemes = [
            .golfCourseDefault,
            .resortDefault,
            createDarkTheme(),
            createVibrantTheme(),
            createMinimalTheme(),
            createProfessionalTheme()
        ]
    }
    
    private func subscribeToTenantChanges() {
        tenantService.currentTenantPublisher
            .sink { [weak self] tenant in
                self?.updateCustomization(for: tenant)
            }
            .store(in: &cancellables)
    }
    
    private func updateCustomization(for tenant: TenantConfiguration?) {
        currentCustomization = tenant.map { tenant in
            TenantCustomization(
                tenantId: tenant.id,
                theme: tenant.theme,
                branding: tenant.branding,
                features: tenant.features,
                lastModified: tenant.lastModified
            )
        }
    }
    
    // MARK: - Theme Variants
    
    private func createDarkTheme() -> WhiteLabelTheme {
        WhiteLabelTheme(
            primaryColor: ColorHex("#1E88E5"),
            secondaryColor: ColorHex("#37474F"),
            accentColor: ColorHex("#FFC107"),
            backgroundColor: ColorHex("#121212"),
            surfaceColor: ColorHex("#1E1E1E"),
            textColor: ColorHex("#FFFFFF"),
            subtextColor: ColorHex("#B0B0B0"),
            successColor: ColorHex("#4CAF50"),
            warningColor: ColorHex("#FF9800"),
            errorColor: ColorHex("#F44336"),
            fontFamily: "SF Pro",
            headerFontWeight: .bold,
            bodyFontWeight: .regular,
            cornerRadius: 8.0,
            borderWidth: 1.0,
            shadowOpacity: 0.3,
            buttonStyle: ButtonTheme(style: .filled, cornerRadius: 8.0, shadowEnabled: true),
            cardStyle: CardTheme(shadowEnabled: true, borderEnabled: false, cornerRadius: 8.0, elevation: 4.0),
            navigationStyle: NavigationTheme(style: .large, showTitles: true, backgroundColor: ColorHex("#1E1E1E"))
        )
    }
    
    private func createVibrantTheme() -> WhiteLabelTheme {
        WhiteLabelTheme(
            primaryColor: ColorHex("#E91E63"),
            secondaryColor: ColorHex("#9C27B0"),
            accentColor: ColorHex("#FF5722"),
            backgroundColor: ColorHex("#FAFAFA"),
            surfaceColor: ColorHex("#FFFFFF"),
            textColor: ColorHex("#212121"),
            subtextColor: ColorHex("#757575"),
            successColor: ColorHex("#4CAF50"),
            warningColor: ColorHex("#FF9800"),
            errorColor: ColorHex("#F44336"),
            fontFamily: "SF Pro",
            headerFontWeight: .bold,
            bodyFontWeight: .medium,
            cornerRadius: 20.0,
            borderWidth: 2.0,
            shadowOpacity: 0.15,
            buttonStyle: ButtonTheme(style: .gradient, cornerRadius: 25.0, shadowEnabled: true),
            cardStyle: CardTheme(shadowEnabled: true, borderEnabled: true, cornerRadius: 20.0, elevation: 6.0),
            navigationStyle: NavigationTheme(style: .large, showTitles: true, backgroundColor: ColorHex("#E91E63"))
        )
    }
    
    private func createMinimalTheme() -> WhiteLabelTheme {
        WhiteLabelTheme(
            primaryColor: ColorHex("#263238"),
            secondaryColor: ColorHex("#607D8B"),
            accentColor: ColorHex("#00BCD4"),
            backgroundColor: ColorHex("#FAFAFA"),
            surfaceColor: ColorHex("#FFFFFF"),
            textColor: ColorHex("#212121"),
            subtextColor: ColorHex("#757575"),
            successColor: ColorHex("#4CAF50"),
            warningColor: ColorHex("#FF9800"),
            errorColor: ColorHex("#F44336"),
            fontFamily: "SF Pro",
            headerFontWeight: .regular,
            bodyFontWeight: .light,
            cornerRadius: 4.0,
            borderWidth: 1.0,
            shadowOpacity: 0.05,
            buttonStyle: ButtonTheme(style: .outlined, cornerRadius: 4.0, shadowEnabled: false),
            cardStyle: CardTheme(shadowEnabled: false, borderEnabled: true, cornerRadius: 4.0, elevation: 0.0),
            navigationStyle: NavigationTheme(style: .inline, showTitles: true, backgroundColor: ColorHex("#FFFFFF"))
        )
    }
    
    private func createProfessionalTheme() -> WhiteLabelTheme {
        WhiteLabelTheme(
            primaryColor: ColorHex("#1565C0"),
            secondaryColor: ColorHex("#455A64"),
            accentColor: ColorHex("#FFA726"),
            backgroundColor: ColorHex("#F5F5F5"),
            surfaceColor: ColorHex("#FFFFFF"),
            textColor: ColorHex("#212121"),
            subtextColor: ColorHex("#616161"),
            successColor: ColorHex("#388E3C"),
            warningColor: ColorHex("#F57C00"),
            errorColor: ColorHex("#D32F2F"),
            fontFamily: "SF Pro",
            headerFontWeight: .semibold,
            bodyFontWeight: .regular,
            cornerRadius: 6.0,
            borderWidth: 1.0,
            shadowOpacity: 0.08,
            buttonStyle: ButtonTheme(style: .filled, cornerRadius: 6.0, shadowEnabled: true),
            cardStyle: CardTheme(shadowEnabled: true, borderEnabled: false, cornerRadius: 6.0, elevation: 2.0),
            navigationStyle: NavigationTheme(style: .standard, showTitles: true, backgroundColor: ColorHex("#1565C0"))
        )
    }
}

// MARK: - Supporting Data Structures

struct TenantCustomization {
    let tenantId: String
    let theme: WhiteLabelTheme
    let branding: TenantBranding
    let features: TenantFeatures
    let lastModified: Date
}

struct TenantCustomizationExport: Codable {
    let tenantId: String
    let theme: WhiteLabelTheme
    let branding: TenantBranding
    let features: TenantFeatures
    let exportDate: Date
    let version: String
}

// MARK: - Template System

struct TenantTemplate {
    let id: String
    let name: String
    let description: String
    let category: TemplateCategory
    let theme: WhiteLabelTheme
    let branding: TenantBranding
    let features: TenantFeatures
    let previewImageURL: String?
    
    enum TemplateCategory: String, CaseIterable {
        case golfCourse = "golf_course"
        case resort = "resort"
        case countryClub = "country_club"
        case publicCourse = "public_course"
        
        var displayName: String {
            switch self {
            case .golfCourse: return "Golf Course"
            case .resort: return "Resort"
            case .countryClub: return "Country Club"
            case .publicCourse: return "Public Course"
            }
        }
    }
    
    func apply(to tenant: TenantConfiguration) -> TenantConfiguration {
        return TenantConfiguration(
            id: tenant.id,
            name: tenant.name,
            displayName: tenant.displayName,
            domain: tenant.domain,
            theme: theme,
            branding: branding,
            businessInfo: tenant.businessInfo,
            features: features,
            databaseNamespace: tenant.databaseNamespace,
            apiKeyPrefix: tenant.apiKeyPrefix,
            isActive: tenant.isActive,
            subscriptionTier: tenant.subscriptionTier,
            createdAt: tenant.createdAt,
            lastModified: Date()
        )
    }
}

// MARK: - Predefined Templates

extension TenantTemplate {
    static let golfCourseClassic = TenantTemplate(
        id: "golf-course-classic",
        name: "Classic Golf Course",
        description: "Traditional golf course design with green and gold colors",
        category: .golfCourse,
        theme: .golfCourseDefault,
        branding: TenantBranding(
            logoURL: "https://example.com/classic-logo.png",
            faviconURL: "https://example.com/classic-favicon.ico",
            appIconURL: "https://example.com/classic-app-icon.png",
            heroImageURL: "https://example.com/classic-hero.jpg",
            backgroundImageURL: nil,
            tagline: "Where Tradition Meets Excellence",
            description: "Experience championship golf in a traditional setting",
            welcomeMessage: "Welcome to our classic golf course experience!",
            websiteURL: nil,
            facebookURL: nil,
            instagramURL: nil,
            twitterURL: nil
        ),
        features: TenantFeatures(
            enableBooking: true,
            enableScorecard: true,
            enableHandicapTracking: true,
            enableLeaderboard: true,
            enableAdvancedAnalytics: false,
            enableWeatherIntegration: true,
            enableGPSRangefinder: true,
            enableSocialFeatures: false,
            enableCustomBranding: true,
            enableMultiCourse: false,
            enableMemberManagement: true,
            enableRevenueTracking: false,
            enableAppleWatchSync: true,
            enableHapticFeedback: true,
            enablePushNotifications: true,
            enableOfflineMode: true
        ),
        previewImageURL: "https://example.com/classic-preview.jpg"
    )
    
    static let golfCourseModern = TenantTemplate(
        id: "golf-course-modern",
        name: "Modern Golf Course",
        description: "Contemporary design with clean lines and vibrant colors",
        category: .golfCourse,
        theme: WhiteLabelTheme(
            primaryColor: ColorHex("#2196F3"),
            secondaryColor: ColorHex("#607D8B"),
            accentColor: ColorHex("#FF5722"),
            backgroundColor: ColorHex("#FAFAFA"),
            surfaceColor: ColorHex("#FFFFFF"),
            textColor: ColorHex("#212121"),
            subtextColor: ColorHex("#757575"),
            successColor: ColorHex("#4CAF50"),
            warningColor: ColorHex("#FF9800"),
            errorColor: ColorHex("#F44336"),
            fontFamily: "SF Pro",
            headerFontWeight: .medium,
            bodyFontWeight: .regular,
            cornerRadius: 12.0,
            borderWidth: 0.5,
            shadowOpacity: 0.12,
            buttonStyle: ButtonTheme(style: .filled, cornerRadius: 24.0, shadowEnabled: true),
            cardStyle: CardTheme(shadowEnabled: true, borderEnabled: false, cornerRadius: 16.0, elevation: 4.0),
            navigationStyle: NavigationTheme(style: .large, showTitles: true, backgroundColor: ColorHex("#2196F3"))
        ),
        branding: TenantBranding(
            logoURL: "https://example.com/modern-logo.png",
            faviconURL: "https://example.com/modern-favicon.ico",
            appIconURL: "https://example.com/modern-app-icon.png",
            heroImageURL: "https://example.com/modern-hero.jpg",
            backgroundImageURL: "https://example.com/modern-bg.jpg",
            tagline: "Golf Reimagined",
            description: "Modern golf experience with cutting-edge technology",
            welcomeMessage: "Experience the future of golf!",
            websiteURL: nil,
            facebookURL: nil,
            instagramURL: nil,
            twitterURL: nil
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
        previewImageURL: "https://example.com/modern-preview.jpg"
    )
    
    static let resortLuxury = TenantTemplate(
        id: "resort-luxury",
        name: "Luxury Resort",
        description: "Premium resort experience with sophisticated styling",
        category: .resort,
        theme: .resortDefault,
        branding: TenantBranding(
            logoURL: "https://example.com/luxury-logo.png",
            faviconURL: "https://example.com/luxury-favicon.ico",
            appIconURL: "https://example.com/luxury-app-icon.png",
            heroImageURL: "https://example.com/luxury-hero.jpg",
            backgroundImageURL: "https://example.com/luxury-bg.jpg",
            tagline: "Luxury Beyond Compare",
            description: "Exceptional golf resort experience with world-class amenities",
            welcomeMessage: "Welcome to luxury redefined!",
            websiteURL: nil,
            facebookURL: nil,
            instagramURL: nil,
            twitterURL: nil
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
        previewImageURL: "https://example.com/luxury-preview.jpg"
    )
    
    static let countryClubTraditional = TenantTemplate(
        id: "country-club-traditional",
        name: "Traditional Country Club",
        description: "Elegant country club with timeless appeal",
        category: .countryClub,
        theme: WhiteLabelTheme(
            primaryColor: ColorHex("#8BC34A"),
            secondaryColor: ColorHex("#795548"),
            accentColor: ColorHex("#FFC107"),
            backgroundColor: ColorHex("#F8F8F8"),
            surfaceColor: ColorHex("#FFFFFF"),
            textColor: ColorHex("#2E2E2E"),
            subtextColor: ColorHex("#666666"),
            successColor: ColorHex("#4CAF50"),
            warningColor: ColorHex("#FF9800"),
            errorColor: ColorHex("#F44336"),
            fontFamily: "SF Pro",
            headerFontWeight: .semibold,
            bodyFontWeight: .regular,
            cornerRadius: 8.0,
            borderWidth: 1.0,
            shadowOpacity: 0.1,
            buttonStyle: ButtonTheme(style: .filled, cornerRadius: 6.0, shadowEnabled: true),
            cardStyle: CardTheme(shadowEnabled: true, borderEnabled: true, cornerRadius: 8.0, elevation: 2.0),
            navigationStyle: NavigationTheme(style: .standard, showTitles: true, backgroundColor: ColorHex("#8BC34A"))
        ),
        branding: TenantBranding(
            logoURL: "https://example.com/traditional-logo.png",
            faviconURL: "https://example.com/traditional-favicon.ico",
            appIconURL: "https://example.com/traditional-app-icon.png",
            heroImageURL: "https://example.com/traditional-hero.jpg",
            backgroundImageURL: nil,
            tagline: "Heritage and Honor",
            description: "Traditional country club values with modern amenities",
            welcomeMessage: "Welcome to our esteemed country club!",
            websiteURL: nil,
            facebookURL: nil,
            instagramURL: nil,
            twitterURL: nil
        ),
        features: TenantFeatures(
            enableBooking: true,
            enableScorecard: true,
            enableHandicapTracking: true,
            enableLeaderboard: true,
            enableAdvancedAnalytics: false,
            enableWeatherIntegration: true,
            enableGPSRangefinder: true,
            enableSocialFeatures: true,
            enableCustomBranding: true,
            enableMultiCourse: false,
            enableMemberManagement: true,
            enableRevenueTracking: false,
            enableAppleWatchSync: true,
            enableHapticFeedback: true,
            enablePushNotifications: true,
            enableOfflineMode: true
        ),
        previewImageURL: "https://example.com/traditional-preview.jpg"
    )
    
    static let publicCourseAccessible = TenantTemplate(
        id: "public-course-accessible",
        name: "Accessible Public Course",
        description: "Welcoming public course design focused on accessibility",
        category: .publicCourse,
        theme: WhiteLabelTheme(
            primaryColor: ColorHex("#4CAF50"),
            secondaryColor: ColorHex("#388E3C"),
            accentColor: ColorHex("#FF9800"),
            backgroundColor: ColorHex("#FAFAFA"),
            surfaceColor: ColorHex("#FFFFFF"),
            textColor: ColorHex("#212121"),
            subtextColor: ColorHex("#757575"),
            successColor: ColorHex("#4CAF50"),
            warningColor: ColorHex("#FF9800"),
            errorColor: ColorHex("#F44336"),
            fontFamily: "SF Pro",
            headerFontWeight: .medium,
            bodyFontWeight: .regular,
            cornerRadius: 10.0,
            borderWidth: 1.0,
            shadowOpacity: 0.1,
            buttonStyle: ButtonTheme(style: .filled, cornerRadius: 10.0, shadowEnabled: true),
            cardStyle: CardTheme(shadowEnabled: true, borderEnabled: false, cornerRadius: 10.0, elevation: 2.0),
            navigationStyle: NavigationTheme(style: .large, showTitles: true, backgroundColor: ColorHex("#4CAF50"))
        ),
        branding: TenantBranding(
            logoURL: "https://example.com/public-logo.png",
            faviconURL: "https://example.com/public-favicon.ico",
            appIconURL: "https://example.com/public-app-icon.png",
            heroImageURL: "https://example.com/public-hero.jpg",
            backgroundImageURL: nil,
            tagline: "Golf for Everyone",
            description: "Accessible golf experience for players of all skill levels",
            welcomeMessage: "Welcome! Let's play golf together!",
            websiteURL: nil,
            facebookURL: nil,
            instagramURL: nil,
            twitterURL: nil
        ),
        features: TenantFeatures(
            enableBooking: true,
            enableScorecard: true,
            enableHandicapTracking: false,
            enableLeaderboard: false,
            enableAdvancedAnalytics: false,
            enableWeatherIntegration: true,
            enableGPSRangefinder: true,
            enableSocialFeatures: false,
            enableCustomBranding: false,
            enableMultiCourse: false,
            enableMemberManagement: false,
            enableRevenueTracking: false,
            enableAppleWatchSync: true,
            enableHapticFeedback: true,
            enablePushNotifications: true,
            enableOfflineMode: true
        ),
        previewImageURL: "https://example.com/public-preview.jpg"
    )
}

// MARK: - Customization Errors

enum CustomizationError: LocalizedError {
    case noCurrentTenant
    case invalidTheme
    case invalidBranding
    case featureNotSupported
    case templateNotFound
    
    var errorDescription: String? {
        switch self {
        case .noCurrentTenant:
            return "No current tenant to customize"
        case .invalidTheme:
            return "Invalid theme configuration"
        case .invalidBranding:
            return "Invalid branding configuration"
        case .featureNotSupported:
            return "Feature not supported in current subscription tier"
        case .templateNotFound:
            return "Template not found"
        }
    }
}

// MARK: - Color Extension

extension Color {
    func toHex() -> String {
        let uic = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uic.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let rgb: Int = (Int)(red * 255) << 16 | (Int)(green * 255) << 8 | (Int)(blue * 255) << 0
        return String(format: "#%06x", rgb)
    }
}