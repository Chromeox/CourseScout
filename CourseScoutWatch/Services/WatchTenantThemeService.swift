import Foundation
import SwiftUI
import WatchKit
import Combine
import os.log

// MARK: - Watch Tenant Theme Service Protocol

protocol WatchTenantThemeServiceProtocol: AnyObject {
    // Current theme state
    var currentTheme: WatchTenantTheme { get }
    var currentBusinessType: WatchBusinessType { get }
    
    // Theme management
    func applyTenantTheme(_ theme: WatchTenantTheme) async
    func resetToDefaultTheme() async
    func getThemeForBusinessType(_ businessType: WatchBusinessType) -> WatchTenantTheme
    
    // UI Element Theming
    func getPrimaryColor() -> Color
    func getSecondaryColor() -> Color
    func getAccentColor() -> Color
    func getTextColor() -> Color
    func getBackgroundColor() -> Color
    func getFont(_ style: WatchFontStyle) -> Font
    
    // Business Type Specific UI
    func getBusinessTypeIcon() -> String
    func getBusinessTypeColorScheme() -> WatchColorScheme
    func getComplicationColors() -> WatchComplicationColors
    
    // Dynamic theming
    func getContextualTheme(for feature: WatchTenantFeature) -> WatchFeatureTheme
    func getHapticPattern(for interaction: WatchInteractionType) -> WatchHapticPattern
    
    // Publishers
    var themeDidChange: AnyPublisher<WatchTenantTheme, Never> { get }
    var businessTypeDidChange: AnyPublisher<WatchBusinessType, Never> { get }
}

// MARK: - Supporting Types

enum WatchFontStyle: String, CaseIterable {
    case headline = "headline"
    case body = "body"
    case caption = "caption"
    case title = "title"
    case callout = "callout"
    
    var systemFont: Font {
        switch self {
        case .headline: return .headline
        case .body: return .body
        case .caption: return .caption
        case .title: return .title
        case .callout: return .callout
        }
    }
}

struct WatchColorScheme {
    let primary: Color
    let secondary: Color
    let accent: Color
    let background: Color
    let text: Color
    let success: Color
    let warning: Color
    let error: Color
    
    static let defaultScheme = WatchColorScheme(
        primary: Color.green,
        secondary: Color.blue,
        accent: Color.orange,
        background: Color.black,
        text: Color.white,
        success: Color.green,
        warning: Color.yellow,
        error: Color.red
    )
}

struct WatchComplicationColors {
    let tintColor: Color
    let backgroundColor: Color
    let textColor: Color
    let borderColor: Color
    
    static let defaultColors = WatchComplicationColors(
        tintColor: .green,
        backgroundColor: .clear,
        textColor: .white,
        borderColor: .gray
    )
}

struct WatchFeatureTheme {
    let feature: WatchTenantFeature
    let primaryColor: Color
    let iconName: String
    let accentColor: Color
    let isEnabled: Bool
}

enum WatchInteractionType: String, CaseIterable {
    case buttonTap = "button_tap"
    case scoreInput = "score_input"
    case navigation = "navigation"
    case notification = "notification"
    case success = "success"
    case error = "error"
    case milestone = "milestone"
}

struct WatchHapticPattern {
    let type: WKHapticType
    let intensity: Double
    let duration: TimeInterval
    let businessTypeVariation: WatchBusinessType?
}

// MARK: - Watch Tenant Theme Service Implementation

@MainActor
class WatchTenantThemeService: WatchTenantThemeServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var currentTheme: WatchTenantTheme = .defaultTheme
    @Published private(set) var currentBusinessType: WatchBusinessType = .golfCourse
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "TenantTheme")
    
    // MARK: - Publishers
    
    private let themeSubject = CurrentValueSubject<WatchTenantTheme, Never>(.defaultTheme)
    private let businessTypeSubject = CurrentValueSubject<WatchBusinessType, Never>(.golfCourse)
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Color Cache
    
    private var colorCache: [String: Color] = [:]
    private var businessTypeThemes: [WatchBusinessType: WatchTenantTheme] = [:]
    
    // MARK: - Initialization
    
    init() {
        setupPublisherBindings()
        initializeBusinessTypeThemes()
        logger.info("WatchTenantThemeService initialized")
    }
    
    // MARK: - Publishers
    
    var themeDidChange: AnyPublisher<WatchTenantTheme, Never> {
        themeSubject.eraseToAnyPublisher()
    }
    
    var businessTypeDidChange: AnyPublisher<WatchBusinessType, Never> {
        businessTypeSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Theme Management
    
    func applyTenantTheme(_ theme: WatchTenantTheme) async {
        logger.info("Applying tenant theme")
        
        currentTheme = theme
        themeSubject.send(theme)
        
        // Clear color cache to force regeneration
        colorCache.removeAll()
        
        logger.debug("Tenant theme applied successfully")
    }
    
    func resetToDefaultTheme() async {
        logger.info("Resetting to default theme")
        await applyTenantTheme(.defaultTheme)
        businessTypeSubject.send(.golfCourse)
    }
    
    func getThemeForBusinessType(_ businessType: WatchBusinessType) -> WatchTenantTheme {
        return businessTypeThemes[businessType] ?? .defaultTheme
    }
    
    // MARK: - UI Element Theming
    
    func getPrimaryColor() -> Color {
        return getCachedColor(currentTheme.primaryColor, key: "primary")
    }
    
    func getSecondaryColor() -> Color {
        return getCachedColor(currentTheme.secondaryColor, key: "secondary")
    }
    
    func getAccentColor() -> Color {
        return getCachedColor(currentTheme.accentColor, key: "accent")
    }
    
    func getTextColor() -> Color {
        return getCachedColor(currentTheme.textColor, key: "text")
    }
    
    func getBackgroundColor() -> Color {
        return getCachedColor(currentTheme.backgroundColor, key: "background")
    }
    
    func getFont(_ style: WatchFontStyle) -> Font {
        // For now, return system fonts; in production, you might load custom fonts
        if currentTheme.fontFamily != "San Francisco" {
            // Custom font handling would go here
        }
        return style.systemFont
    }
    
    // MARK: - Business Type Specific UI
    
    func getBusinessTypeIcon() -> String {
        switch currentBusinessType {
        case .golfCourse:
            return "sportscourt.fill"
        case .golfResort:
            return "building.2.crop.circle.fill"
        case .countryClub:
            return "crown.fill"
        case .publicCourse:
            return "person.3.fill"
        case .privateClub:
            return "lock.shield.fill"
        case .golfAcademy:
            return "graduationcap.fill"
        }
    }
    
    func getBusinessTypeColorScheme() -> WatchColorScheme {
        let baseColors = WatchColorScheme.defaultScheme
        let primary = getPrimaryColor()
        let secondary = getSecondaryColor()
        
        return WatchColorScheme(
            primary: primary,
            secondary: secondary,
            accent: getAccentColor(),
            background: getBackgroundColor(),
            text: getTextColor(),
            success: currentBusinessType.hasPremiumFeatures ? Color.green : baseColors.success,
            warning: Color.yellow,
            error: Color.red
        )
    }
    
    func getComplicationColors() -> WatchComplicationColors {
        return WatchComplicationColors(
            tintColor: getPrimaryColor(),
            backgroundColor: getBackgroundColor().opacity(0.8),
            textColor: getTextColor(),
            borderColor: getSecondaryColor().opacity(0.6)
        )
    }
    
    // MARK: - Dynamic Theming
    
    func getContextualTheme(for feature: WatchTenantFeature) -> WatchFeatureTheme {
        let baseColor = getPrimaryColor()
        let accentColor = getAccentColor()
        
        let (iconName, featureColor) = getFeatureIconAndColor(feature)
        
        return WatchFeatureTheme(
            feature: feature,
            primaryColor: featureColor,
            iconName: iconName,
            accentColor: accentColor,
            isEnabled: true
        )
    }
    
    func getHapticPattern(for interaction: WatchInteractionType) -> WatchHapticPattern {
        switch interaction {
        case .buttonTap:
            return WatchHapticPattern(
                type: .click,
                intensity: currentBusinessType.hasEliteFeatures ? 0.8 : 0.6,
                duration: 0.1,
                businessTypeVariation: currentBusinessType
            )
        case .scoreInput:
            return WatchHapticPattern(
                type: .notification(.success),
                intensity: 0.7,
                duration: 0.2,
                businessTypeVariation: currentBusinessType
            )
        case .navigation:
            return WatchHapticPattern(
                type: .selection,
                intensity: 0.5,
                duration: 0.05,
                businessTypeVariation: nil
            )
        case .notification:
            return WatchHapticPattern(
                type: .notification(.warning),
                intensity: currentBusinessType.hasPremiumFeatures ? 1.0 : 0.8,
                duration: 0.3,
                businessTypeVariation: currentBusinessType
            )
        case .success:
            return WatchHapticPattern(
                type: .notification(.success),
                intensity: 1.0,
                duration: 0.4,
                businessTypeVariation: currentBusinessType
            )
        case .error:
            return WatchHapticPattern(
                type: .notification(.failure),
                intensity: 1.0,
                duration: 0.5,
                businessTypeVariation: currentBusinessType
            )
        case .milestone:
            return WatchHapticPattern(
                type: currentBusinessType.hasEliteFeatures ? .start : .notification(.success),
                intensity: 1.0,
                duration: 0.6,
                businessTypeVariation: currentBusinessType
            )
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func setupPublisherBindings() {
        themeSubject.sink { [weak self] theme in
            self?.currentTheme = theme
        }.store(in: &cancellables)
        
        businessTypeSubject.sink { [weak self] businessType in
            self?.currentBusinessType = businessType
        }.store(in: &cancellables)
    }
    
    private func initializeBusinessTypeThemes() {
        // Golf Course - Professional Green
        businessTypeThemes[.golfCourse] = WatchTenantTheme(
            primaryColor: "#2E7D32",
            secondaryColor: "#4CAF50",
            accentColor: "#8BC34A",
            textColor: "#FFFFFF",
            backgroundColor: "#1B1B1B",
            fontFamily: "San Francisco",
            logoURL: nil
        )
        
        // Golf Resort - Luxury Blue
        businessTypeThemes[.golfResort] = WatchTenantTheme(
            primaryColor: "#1565C0",
            secondaryColor: "#2196F3",
            accentColor: "#64B5F6",
            textColor: "#FFFFFF",
            backgroundColor: "#0D1B2A",
            fontFamily: "San Francisco",
            logoURL: nil
        )
        
        // Country Club - Elite Gold
        businessTypeThemes[.countryClub] = WatchTenantTheme(
            primaryColor: "#E65100",
            secondaryColor: "#FF9800",
            accentColor: "#FFB74D",
            textColor: "#FFFFFF",
            backgroundColor: "#1A1A1A",
            fontFamily: "San Francisco",
            logoURL: nil
        )
        
        // Public Course - Community Teal
        businessTypeThemes[.publicCourse] = WatchTenantTheme(
            primaryColor: "#00695C",
            secondaryColor: "#26A69A",
            accentColor: "#80CBC4",
            textColor: "#FFFFFF",
            backgroundColor: "#1B1B1B",
            fontFamily: "San Francisco",
            logoURL: nil
        )
        
        // Private Club - Exclusive Purple
        businessTypeThemes[.privateClub] = WatchTenantTheme(
            primaryColor: "#4A148C",
            secondaryColor: "#7B1FA2",
            accentColor: "#BA68C8",
            textColor: "#FFFFFF",
            backgroundColor: "#0A0A0A",
            fontFamily: "San Francisco",
            logoURL: nil
        )
        
        // Golf Academy - Educational Orange
        businessTypeThemes[.golfAcademy] = WatchTenantTheme(
            primaryColor: "#D84315",
            secondaryColor: "#FF5722",
            accentColor: "#FF8A65",
            textColor: "#FFFFFF",
            backgroundColor: "#1B1B1B",
            fontFamily: "San Francisco",
            logoURL: nil
        )
    }
    
    private func getCachedColor(_ hexString: String, key: String) -> Color {
        if let cachedColor = colorCache[key] {
            return cachedColor
        }
        
        let color = Color(hex: hexString) ?? .white
        colorCache[key] = color
        return color
    }
    
    private func getFeatureIconAndColor(_ feature: WatchTenantFeature) -> (String, Color) {
        let baseColor = getPrimaryColor()
        
        switch feature {
        case .scorecard:
            return ("list.number", baseColor)
        case .gps:
            return ("location.fill", Color.blue)
        case .workout:
            return ("figure.golf", Color.green)
        case .haptics:
            return ("waveform", Color.orange)
        case .complications:
            return ("app.badge.fill", baseColor)
        case .notifications:
            return ("bell.fill", Color.red)
        case .premiumAnalytics:
            return ("chart.line.uptrend.xyaxis", Color.purple)
        case .concierge:
            return ("person.crop.circle.badge.checkmark", Color.blue)
        case .memberServices:
            return ("crown.fill", Color.yellow)
        }
    }
}

// MARK: - Mock Implementation

class MockWatchTenantThemeService: WatchTenantThemeServiceProtocol, ObservableObject {
    @Published private(set) var currentTheme: WatchTenantTheme = .defaultTheme
    @Published private(set) var currentBusinessType: WatchBusinessType = .golfCourse
    
    private let themeSubject = CurrentValueSubject<WatchTenantTheme, Never>(.defaultTheme)
    private let businessTypeSubject = CurrentValueSubject<WatchBusinessType, Never>(.golfCourse)
    
    var themeDidChange: AnyPublisher<WatchTenantTheme, Never> {
        themeSubject.eraseToAnyPublisher()
    }
    
    var businessTypeDidChange: AnyPublisher<WatchBusinessType, Never> {
        businessTypeSubject.eraseToAnyPublisher()
    }
    
    func applyTenantTheme(_ theme: WatchTenantTheme) async {
        currentTheme = theme
        themeSubject.send(theme)
    }
    
    func resetToDefaultTheme() async {
        currentTheme = .defaultTheme
        themeSubject.send(.defaultTheme)
    }
    
    func getThemeForBusinessType(_ businessType: WatchBusinessType) -> WatchTenantTheme {
        return .defaultTheme
    }
    
    func getPrimaryColor() -> Color { .green }
    func getSecondaryColor() -> Color { .blue }
    func getAccentColor() -> Color { .orange }
    func getTextColor() -> Color { .white }
    func getBackgroundColor() -> Color { .black }
    func getFont(_ style: WatchFontStyle) -> Font { style.systemFont }
    
    func getBusinessTypeIcon() -> String { "sportscourt.fill" }
    func getBusinessTypeColorScheme() -> WatchColorScheme { .defaultScheme }
    func getComplicationColors() -> WatchComplicationColors { .defaultColors }
    
    func getContextualTheme(for feature: WatchTenantFeature) -> WatchFeatureTheme {
        return WatchFeatureTheme(
            feature: feature,
            primaryColor: .green,
            iconName: "circle.fill",
            accentColor: .orange,
            isEnabled: true
        )
    }
    
    func getHapticPattern(for interaction: WatchInteractionType) -> WatchHapticPattern {
        return WatchHapticPattern(
            type: .click,
            intensity: 0.6,
            duration: 0.1,
            businessTypeVariation: .golfCourse
        )
    }
}

// MARK: - Color Extension for Hex Support

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
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    var hex: String {
        guard let components = cgColor?.components, components.count >= 3 else {
            return "#FFFFFF"
        }
        
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        
        return String(format: "#%02X%02X%02X", 
                      lroundf(r * 255), 
                      lroundf(g * 255), 
                      lroundf(b * 255))
    }
}