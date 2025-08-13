import Foundation
import SwiftUI
import CoreLocation

// MARK: - Tenant Configuration Models

struct TenantConfiguration: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let displayName: String
    let domain: String
    
    // Branding configuration
    let theme: WhiteLabelTheme
    let branding: TenantBranding
    
    // Business configuration
    let businessInfo: TenantBusinessInfo
    let features: TenantFeatures
    
    // Multi-tenant data isolation
    let databaseNamespace: String
    let apiKeyPrefix: String
    
    // Status and metadata
    let isActive: Bool
    let subscriptionTier: SubscriptionTier
    let createdAt: Date
    let lastModified: Date
    
    var isValidConfiguration: Bool {
        !name.isEmpty && 
        !domain.isEmpty && 
        !databaseNamespace.isEmpty && 
        isActive &&
        theme.isComplete
    }
}

// MARK: - White Label Theme System

struct WhiteLabelTheme: Codable, Equatable {
    // Primary brand colors
    let primaryColor: ColorHex
    let secondaryColor: ColorHex
    let accentColor: ColorHex
    
    // UI component colors
    let backgroundColor: ColorHex
    let surfaceColor: ColorHex
    let textColor: ColorHex
    let subtextColor: ColorHex
    
    // Success/Error states
    let successColor: ColorHex
    let warningColor: ColorHex
    let errorColor: ColorHex
    
    // Typography
    let fontFamily: String
    let headerFontWeight: FontWeight
    let bodyFontWeight: FontWeight
    
    // UI styling
    let cornerRadius: Double
    let borderWidth: Double
    let shadowOpacity: Double
    
    // Component-specific styling
    let buttonStyle: ButtonTheme
    let cardStyle: CardTheme
    let navigationStyle: NavigationTheme
    
    // Haptic branding integration
    let hapticIntensityStyle: HapticIntensityStyle
    let brandingHapticEnabled: Bool
    
    var isComplete: Bool {
        !primaryColor.hex.isEmpty && 
        !secondaryColor.hex.isEmpty && 
        !fontFamily.isEmpty
    }
    
    // SwiftUI Color conversion
    var primarySwiftUIColor: Color {
        Color(hex: primaryColor.hex) ?? .blue
    }
    
    var secondarySwiftUIColor: Color {
        Color(hex: secondaryColor.hex) ?? .gray
    }
    
    var accentSwiftUIColor: Color {
        Color(hex: accentColor.hex) ?? .green
    }
    
    var backgroundSwiftUIColor: Color {
        Color(hex: backgroundColor.hex) ?? .white
    }
    
    var textSwiftUIColor: Color {
        Color(hex: textColor.hex) ?? .primary
    }
}

// MARK: - Tenant Branding

struct TenantBranding: Codable, Equatable {
    let logoURL: String
    let faviconURL: String
    let appIconURL: String
    
    // Marketing assets
    let heroImageURL: String?
    let backgroundImageURL: String?
    
    // Brand messaging
    let tagline: String
    let description: String
    let welcomeMessage: String
    
    // Social media
    let websiteURL: String?
    let facebookURL: String?
    let instagramURL: String?
    let twitterURL: String?
    
    var hasValidLogo: Bool {
        !logoURL.isEmpty && URL(string: logoURL) != nil
    }
    
    var hasSocialMedia: Bool {
        websiteURL != nil || facebookURL != nil || 
        instagramURL != nil || twitterURL != nil
    }
}

// MARK: - Tenant Business Information

struct TenantBusinessInfo: Codable, Equatable {
    let businessName: String
    let businessType: BusinessType
    let contactEmail: String
    let contactPhone: String
    
    // Address information
    let address: BusinessAddress
    
    // Operating details
    let timeZone: String
    let currency: String
    let locale: String
    
    // Golf-specific information
    let courseCount: Int
    let membershipCount: Int
    let averageRoundsPerDay: Int
    
    enum BusinessType: String, CaseIterable, Codable {
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
    }
}

struct BusinessAddress: Codable, Equatable {
    let street: String
    let city: String
    let state: String
    let zipCode: String
    let country: String
    let latitude: Double?
    let longitude: Double?
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var formattedAddress: String {
        "\(street), \(city), \(state) \(zipCode)"
    }
}

// MARK: - Tenant Features Configuration

struct TenantFeatures: Codable, Equatable {
    // Core golf features
    let enableBooking: Bool
    let enableScorecard: Bool
    let enableHandicapTracking: Bool
    let enableLeaderboard: Bool
    
    // Premium features
    let enableAdvancedAnalytics: Bool
    let enableWeatherIntegration: Bool
    let enableGPSRangefinder: Bool
    let enableSocialFeatures: Bool
    
    // White label specific
    let enableCustomBranding: Bool
    let enableMultiCourse: Bool
    let enableMemberManagement: Bool
    let enableRevenueTracking: Bool
    
    // Integration features
    let enableAppleWatchSync: Bool
    let enableHapticFeedback: Bool
    let enablePushNotifications: Bool
    let enableOfflineMode: Bool
    
    // Premium haptic features
    let enableTenantHapticBranding: Bool
    let enableAdvancedHaptics: Bool
    let enableCustomHapticPatterns: Bool
    
    var enabledFeaturesCount: Int {
        let features = [
            enableBooking, enableScorecard, enableHandicapTracking, 
            enableLeaderboard, enableAdvancedAnalytics, enableWeatherIntegration,
            enableGPSRangefinder, enableSocialFeatures, enableCustomBranding,
            enableMultiCourse, enableMemberManagement, enableRevenueTracking,
            enableAppleWatchSync, enableHapticFeedback, enablePushNotifications,
            enableOfflineMode, enableTenantHapticBranding, enableAdvancedHaptics,
            enableCustomHapticPatterns
        ]
        return features.filter { $0 }.count
    }
    
    var hasBasicFeatures: Bool {
        enableBooking && enableScorecard
    }
    
    var hasPremiumFeatures: Bool {
        enableAdvancedAnalytics && enableGPSRangefinder && enableWeatherIntegration
    }
    
    var hasPremiumHaptics: Bool {
        enableTenantHapticBranding && enableAdvancedHaptics && enableCustomHapticPatterns
    }
}

// MARK: - Subscription Management

enum SubscriptionTier: String, CaseIterable, Codable {
    case starter = "starter"
    case professional = "professional" 
    case enterprise = "enterprise"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .starter: return "Starter"
        case .professional: return "Professional"
        case .enterprise: return "Enterprise"
        case .custom: return "Custom"
        }
    }
    
    var maxCourses: Int {
        switch self {
        case .starter: return 1
        case .professional: return 5
        case .enterprise: return 50
        case .custom: return Int.max
        }
    }
    
    var maxMembers: Int {
        switch self {
        case .starter: return 100
        case .professional: return 1000
        case .enterprise: return 10000
        case .custom: return Int.max
        }
    }
    
    var supportsAdvancedAnalytics: Bool {
        self != .starter
    }
    
    var supportsCustomBranding: Bool {
        self == .professional || self == .enterprise || self == .custom
    }
}

// MARK: - Theme Components

struct ButtonTheme: Codable, Equatable {
    let style: ButtonStyle
    let cornerRadius: Double
    let shadowEnabled: Bool
    
    enum ButtonStyle: String, CaseIterable, Codable {
        case filled = "filled"
        case outlined = "outlined" 
        case text = "text"
        case gradient = "gradient"
    }
}

struct CardTheme: Codable, Equatable {
    let shadowEnabled: Bool
    let borderEnabled: Bool
    let cornerRadius: Double
    let elevation: Double
}

struct NavigationTheme: Codable, Equatable {
    let style: NavigationStyle
    let showTitles: Bool
    let backgroundColor: ColorHex
    
    enum NavigationStyle: String, CaseIterable, Codable {
        case standard = "standard"
        case large = "large"
        case inline = "inline"
        case compact = "compact"
    }
}

// MARK: - Haptic Theme Integration

enum HapticIntensityStyle: String, CaseIterable, Codable {
    case subtle = "subtle"
    case balanced = "balanced"  
    case dynamic = "dynamic"
    case premium = "premium"
    
    var displayName: String {
        switch self {
        case .subtle: return "Subtle"
        case .balanced: return "Balanced"
        case .dynamic: return "Dynamic"
        case .premium: return "Premium"
        }
    }
    
    var globalIntensityMultiplier: Float {
        switch self {
        case .subtle: return 0.4
        case .balanced: return 0.6
        case .dynamic: return 0.8
        case .premium: return 1.0
        }
    }
}

// MARK: - Color and Typography Helpers

struct ColorHex: Codable, Equatable {
    let hex: String
    
    init(_ hex: String) {
        self.hex = hex.hasPrefix("#") ? hex : "#\(hex)"
    }
}

enum FontWeight: String, CaseIterable, Codable {
    case light = "light"
    case regular = "regular"
    case medium = "medium"
    case semibold = "semibold"
    case bold = "bold"
    
    var swiftUIWeight: Font.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

// MARK: - SwiftUI Color Extension

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Default Themes

extension WhiteLabelTheme {
    static let golfCourseDefault = WhiteLabelTheme(
        primaryColor: ColorHex("#2E7D32"),      // Golf green
        secondaryColor: ColorHex("#795548"),     // Sand/earth
        accentColor: ColorHex("#FFC107"),        // Golf ball yellow
        backgroundColor: ColorHex("#FAFAFA"),
        surfaceColor: ColorHex("#FFFFFF"),
        textColor: ColorHex("#212121"),
        subtextColor: ColorHex("#757575"),
        successColor: ColorHex("#4CAF50"),
        warningColor: ColorHex("#FF9800"),
        errorColor: ColorHex("#F44336"),
        fontFamily: "SF Pro",
        headerFontWeight: .bold,
        bodyFontWeight: .regular,
        cornerRadius: 12.0,
        borderWidth: 1.0,
        shadowOpacity: 0.1,
        buttonStyle: ButtonTheme(style: .filled, cornerRadius: 8.0, shadowEnabled: true),
        cardStyle: CardTheme(shadowEnabled: true, borderEnabled: false, cornerRadius: 12.0, elevation: 2.0),
        navigationStyle: NavigationTheme(style: .large, showTitles: true, backgroundColor: ColorHex("#FFFFFF")),
        hapticIntensityStyle: .balanced,
        brandingHapticEnabled: true
    )
    
    static let resortDefault = WhiteLabelTheme(
        primaryColor: ColorHex("#1976D2"),       // Resort blue
        secondaryColor: ColorHex("#424242"),     // Charcoal
        accentColor: ColorHex("#FF5722"),        // Sunset orange
        backgroundColor: ColorHex("#F5F5F5"),
        surfaceColor: ColorHex("#FFFFFF"),
        textColor: ColorHex("#212121"),
        subtextColor: ColorHex("#757575"),
        successColor: ColorHex("#4CAF50"),
        warningColor: ColorHex("#FF9800"),
        errorColor: ColorHex("#F44336"),
        fontFamily: "SF Pro",
        headerFontWeight: .semibold,
        bodyFontWeight: .regular,
        cornerRadius: 16.0,
        borderWidth: 0.5,
        shadowOpacity: 0.12,
        buttonStyle: ButtonTheme(style: .gradient, cornerRadius: 24.0, shadowEnabled: true),
        cardStyle: CardTheme(shadowEnabled: true, borderEnabled: false, cornerRadius: 16.0, elevation: 4.0),
        navigationStyle: NavigationTheme(style: .large, showTitles: true, backgroundColor: ColorHex("#1976D2")),
        hapticIntensityStyle: .premium,
        brandingHapticEnabled: true
    )
}