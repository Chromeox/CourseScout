import Foundation
import Combine
import SwiftUI

/// ViewModel for Tenant Haptic Preferences Configuration
/// Manages haptic settings, business type optimization, and usage analytics
@MainActor
class TenantHapticPreferencesViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var preferences: TenantHapticPreferences = .default
    @Published var hapticCapabilities: HapticCapabilities = HapticCapabilities(
        supportsCoreHaptics: false,
        supportsAdvancedPatterns: false,
        supportsWatchConnectivity: false,
        maxSimultaneousEvents: 0
    )
    @Published var currentBusinessType: BusinessType = .golfCourse
    @Published var businessTypeRecommendations: [HapticRecommendation] = []
    @Published var usageMetrics: HapticUsageMetrics = HapticUsageMetrics(
        totalUsage: 0,
        dailyAverage: 0,
        mostUsedPattern: "N/A"
    )
    @Published var updateSuccessMessage: String?
    @Published var updateErrorMessage: String?
    @Published var isLoading: Bool = false
    
    // MARK: - Private Properties
    
    private var contextIntensities: [HapticContextType: Float] = [
        .booking: 0.6,
        .analytics: 0.4,
        .management: 0.7,
        .branding: 0.5,
        .emergency: 0.9
    ]
    
    private var originalPreferences: TenantHapticPreferences = .default
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Services
    
    @ServiceInjected(HapticFeedbackServiceProtocol.self)
    private var hapticService: HapticFeedbackServiceProtocol
    
    @ServiceInjected(TenantConfigurationServiceProtocol.self)
    private var tenantConfigService: TenantConfigurationServiceProtocol
    
    @ServiceInjected(AnalyticsServiceProtocol.self)
    private var analyticsService: AnalyticsServiceProtocol
    
    // MARK: - Computed Properties
    
    var currentTenantId: String {
        return tenantConfigService.currentTenant?.id ?? "default"
    }
    
    var hasUnsavedChanges: Bool {
        return preferences != originalPreferences
    }
    
    var canUseLuxuryHaptics: Bool {
        guard let currentTenant = tenantConfigService.currentTenant else { return false }
        return currentTenant.businessInfo.businessType.supportsLuxuryHaptics
    }
    
    var recommendedIntensityLevel: TenantHapticIntensity {
        return currentBusinessType.defaultHapticIntensity
    }
    
    // MARK: - Initialization
    
    init() {
        setupObservation()
        loadHapticCapabilities()
        loadBusinessTypeRecommendations()
    }
    
    // MARK: - Public Methods
    
    func loadCurrentPreferences() async {
        isLoading = true
        defer { isLoading = false }
        
        // Load current tenant haptic preferences
        if let currentPrefs = hapticService.getTenantHapticPreferences() {
            preferences = currentPrefs
            originalPreferences = currentPrefs
        }
        
        // Load current tenant business type
        if let tenant = tenantConfigService.currentTenant {
            currentBusinessType = tenant.businessInfo.businessType
            loadBusinessTypeRecommendations()
        }
        
        // Load usage metrics
        await loadUsageMetrics()
        
        // Track preferences view
        trackPreferencesViewed()
    }
    
    func savePreferences() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await hapticService.updateTenantHapticPreferences(preferences)
            originalPreferences = preferences
            updateSuccessMessage = "Haptic preferences saved successfully"
            
            // Clear success message after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.updateSuccessMessage = nil
            }
            
            trackPreferencesSaved()
            
        } catch {
            updateErrorMessage = "Failed to save preferences: \(error.localizedDescription)"
            
            // Clear error message after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.updateErrorMessage = nil
            }
        }
    }
    
    func resetToDefaults() {
        let defaultPrefs = getDefaultPreferencesForBusinessType()
        preferences = defaultPrefs
        
        // Reset context intensities
        contextIntensities = getDefaultContextIntensities()
        
        trackPreferencesReset()
    }
    
    func updateContextIntensity(for context: HapticContextType, intensity: Float) {
        contextIntensities[context] = intensity
        
        // Update preferences based on context intensities
        updatePreferencesFromContextIntensities()
        
        trackContextIntensityChanged(context: context, intensity: intensity)
    }
    
    func getContextIntensity(for context: HapticContextType) -> Float {
        return contextIntensities[context] ?? 0.6
    }
    
    func optimizeForBusinessType() {
        let optimizedPrefs = getOptimizedPreferencesForBusinessType()
        preferences = optimizedPrefs
        
        trackBusinessTypeOptimization()
    }
    
    func exportHapticSettings() {
        let settingsData = createExportData()
        
        // Create export file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportURL = documentsPath.appendingPathComponent("haptic_settings_\(currentTenantId).json")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: settingsData, options: .prettyPrinted)
            try jsonData.write(to: exportURL)
            
            updateSuccessMessage = "Settings exported to Documents folder"
            trackSettingsExported()
            
        } catch {
            updateErrorMessage = "Failed to export settings: \(error.localizedDescription)"
        }
    }
    
    func importHapticSettings(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let settingsDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let importedPrefs = parseImportedSettings(settingsDict) {
                preferences = importedPrefs
                updateSuccessMessage = "Settings imported successfully"
                trackSettingsImported()
            } else {
                updateErrorMessage = "Invalid settings file format"
            }
            
        } catch {
            updateErrorMessage = "Failed to import settings: \(error.localizedDescription)"
        }
    }
    
    func validateCurrentSettings() -> [HapticValidationIssue] {
        var issues: [HapticValidationIssue] = []
        
        // Check if luxury haptics are enabled but not supported
        if preferences.globalIntensity == .luxury && !canUseLuxuryHaptics {
            issues.append(.luxuryHapticsNotSupported)
        }
        
        // Check if watch sync is enabled but watch not available
        if preferences.watchSyncEnabled && !hapticCapabilities.supportsWatchConnectivity {
            issues.append(.watchSyncNotAvailable)
        }
        
        // Check for performance concerns
        if preferences.globalIntensity == .luxury && !preferences.batteryOptimized {
            issues.append(.batteryOptimizationRecommended)
        }
        
        // Check accessibility settings
        if preferences.globalIntensity != .minimal && !preferences.accessibilityOptimized {
            let reducedMotionEnabled = UIAccessibility.isReduceMotionEnabled
            if reducedMotionEnabled {
                issues.append(.accessibilityOptimizationRecommended)
            }
        }
        
        return issues
    }
    
    func getRecommendedSettings() -> TenantHapticPreferences {
        return getOptimizedPreferencesForBusinessType()
    }
    
    // MARK: - Private Methods
    
    private func setupObservation() {
        // Observe preference changes for auto-save
        $preferences
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] newPreferences in
                Task {
                    await self?.autoSaveIfNeeded(newPreferences)
                }
            }
            .store(in: &cancellables)
        
        // Observe tenant changes
        tenantConfigService.currentTenantPublisher
            .sink { [weak self] tenant in
                if let tenant = tenant {
                    self?.currentBusinessType = tenant.businessInfo.businessType
                    self?.loadBusinessTypeRecommendations()
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadHapticCapabilities() {
        hapticCapabilities = hapticService.checkHapticCapabilities()
    }
    
    private func loadBusinessTypeRecommendations() {
        businessTypeRecommendations = generateRecommendations(for: currentBusinessType)
    }
    
    private func loadUsageMetrics() async {
        // This would typically load from analytics service
        // For now, we'll generate sample metrics
        usageMetrics = HapticUsageMetrics(
            totalUsage: Int.random(in: 500...2000),
            dailyAverage: Double.random(in: 15...50),
            mostUsedPattern: "Course Discovery"
        )
    }
    
    private func generateRecommendations(for businessType: BusinessType) -> [HapticRecommendation] {
        switch businessType {
        case .golfCourse:
            return [
                HapticRecommendation(
                    title: "Balanced Experience",
                    description: "Standard intensity for general golf course operations",
                    icon: "gauge.medium"
                ),
                HapticRecommendation(
                    title: "Booking Focus",
                    description: "Enhanced haptics during tee time booking",
                    icon: "calendar.badge.plus"
                ),
                HapticRecommendation(
                    title: "Accessibility",
                    description: "Consider reduced motion preferences",
                    icon: "accessibility"
                )
            ]
            
        case .golfResort:
            return [
                HapticRecommendation(
                    title: "Luxury Experience",
                    description: "Premium haptic patterns for resort feel",
                    icon: "crown"
                ),
                HapticRecommendation(
                    title: "Multi-Service",
                    description: "Enhanced haptics across resort services",
                    icon: "building.2"
                ),
                HapticRecommendation(
                    title: "Brand Signature",
                    description: "Unique haptic branding for recognition",
                    icon: "seal"
                )
            ]
            
        case .countryClub:
            return [
                HapticRecommendation(
                    title: "Exclusive Feel",
                    description: "Sophisticated haptic patterns for members",
                    icon: "star.circle"
                ),
                HapticRecommendation(
                    title: "Premium Booking",
                    description: "Enhanced member booking experience",
                    icon: "person.badge.key"
                ),
                HapticRecommendation(
                    title: "Event Notifications",
                    description: "Distinct haptics for club events",
                    icon: "bell.badge"
                )
            ]
            
        case .publicCourse:
            return [
                HapticRecommendation(
                    title: "Welcoming Experience",
                    description: "Inclusive haptic patterns for all players",
                    icon: "hand.wave"
                ),
                HapticRecommendation(
                    title: "Simple Navigation",
                    description: "Clear haptic feedback for easy navigation",
                    icon: "arrow.triangle.turn.up.right.diamond"
                ),
                HapticRecommendation(
                    title: "Cost Effective",
                    description: "Battery optimized for longer sessions",
                    icon: "battery.100percent"
                )
            ]
            
        case .privateClub:
            return [
                HapticRecommendation(
                    title: "Elite Experience",
                    description: "Premium haptics for private club ambiance",
                    icon: "diamond"
                ),
                HapticRecommendation(
                    title: "Member Priority",
                    description: "Enhanced booking and services",
                    icon: "star.square"
                ),
                HapticRecommendation(
                    title: "Exclusive Events",
                    description: "Special haptic patterns for tournaments",
                    icon: "trophy"
                )
            ]
            
        case .golfAcademy:
            return [
                HapticRecommendation(
                    title: "Learning Focus",
                    description: "Educational haptic patterns for instruction",
                    icon: "graduationcap"
                ),
                HapticRecommendation(
                    title: "Progress Feedback",
                    description: "Achievement haptics for skill milestones",
                    icon: "chart.line.uptrend.xyaxis"
                ),
                HapticRecommendation(
                    title: "Gentle Guidance",
                    description: "Subtle haptics for learning environment",
                    icon: "hand.point.right"
                )
            ]
        }
    }
    
    private func getDefaultPreferencesForBusinessType() -> TenantHapticPreferences {
        let defaultIntensity = currentBusinessType.defaultHapticIntensity
        
        return TenantHapticPreferences(
            isEnabled: true,
            globalIntensity: defaultIntensity,
            brandingHapticEnabled: currentBusinessType.supportsLuxuryHaptics,
            analyticsHapticsEnabled: true,
            managementHapticsEnabled: true,
            bookingHapticsEnabled: true,
            customPatterns: [:],
            accessibilityOptimized: false,
            batteryOptimized: currentBusinessType == .publicCourse,
            watchSyncEnabled: hapticCapabilities.supportsWatchConnectivity
        )
    }
    
    private func getOptimizedPreferencesForBusinessType() -> TenantHapticPreferences {
        var optimized = getDefaultPreferencesForBusinessType()
        
        // Apply business-specific optimizations
        switch currentBusinessType {
        case .golfResort, .privateClub:
            optimized.globalIntensity = .luxury
            optimized.brandingHapticEnabled = true
            
        case .countryClub:
            optimized.globalIntensity = .enhanced
            optimized.brandingHapticEnabled = true
            
        case .publicCourse:
            optimized.globalIntensity = .standard
            optimized.batteryOptimized = true
            optimized.accessibilityOptimized = true
            
        case .golfAcademy:
            optimized.globalIntensity = .minimal
            optimized.accessibilityOptimized = true
            
        case .golfCourse:
            optimized.globalIntensity = .standard
        }
        
        return optimized
    }
    
    private func getDefaultContextIntensities() -> [HapticContextType: Float] {
        let profile = currentBusinessType.hapticProfile
        
        return [
            .booking: profile.bookingIntensity,
            .analytics: profile.analyticsIntensity,
            .management: profile.managementIntensity,
            .branding: profile.brandingIntensity,
            .emergency: profile.emergencyIntensity
        ]
    }
    
    private func updatePreferencesFromContextIntensities() {
        // This would update the preferences based on context intensities
        // For now, we'll just ensure consistency
    }
    
    private func autoSaveIfNeeded(_ newPreferences: TenantHapticPreferences) async {
        // Only auto-save if significant changes and user has been idle
        if hasUnsavedChanges {
            // Implement auto-save logic here if desired
        }
    }
    
    private func createExportData() -> [String: Any] {
        return [
            "version": "1.0",
            "tenantId": currentTenantId,
            "businessType": currentBusinessType.rawValue,
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "preferences": [
                "isEnabled": preferences.isEnabled,
                "globalIntensity": preferences.globalIntensity.rawValue,
                "brandingHapticEnabled": preferences.brandingHapticEnabled,
                "analyticsHapticsEnabled": preferences.analyticsHapticsEnabled,
                "managementHapticsEnabled": preferences.managementHapticsEnabled,
                "bookingHapticsEnabled": preferences.bookingHapticsEnabled,
                "accessibilityOptimized": preferences.accessibilityOptimized,
                "batteryOptimized": preferences.batteryOptimized,
                "watchSyncEnabled": preferences.watchSyncEnabled
            ],
            "contextIntensities": contextIntensities.mapValues { $0 }
        ]
    }
    
    private func parseImportedSettings(_ data: [String: Any]?) -> TenantHapticPreferences? {
        guard let data = data,
              let prefsData = data["preferences"] as? [String: Any] else {
            return nil
        }
        
        // Parse the imported preferences
        let isEnabled = prefsData["isEnabled"] as? Bool ?? true
        let globalIntensityRaw = prefsData["globalIntensity"] as? String ?? "standard"
        let globalIntensity = TenantHapticIntensity(rawValue: globalIntensityRaw) ?? .standard
        
        return TenantHapticPreferences(
            isEnabled: isEnabled,
            globalIntensity: globalIntensity,
            brandingHapticEnabled: prefsData["brandingHapticEnabled"] as? Bool ?? true,
            analyticsHapticsEnabled: prefsData["analyticsHapticsEnabled"] as? Bool ?? true,
            managementHapticsEnabled: prefsData["managementHapticsEnabled"] as? Bool ?? true,
            bookingHapticsEnabled: prefsData["bookingHapticsEnabled"] as? Bool ?? true,
            customPatterns: [:],
            accessibilityOptimized: prefsData["accessibilityOptimized"] as? Bool ?? false,
            batteryOptimized: prefsData["batteryOptimized"] as? Bool ?? false,
            watchSyncEnabled: prefsData["watchSyncEnabled"] as? Bool ?? true
        )
    }
    
    // MARK: - Analytics Tracking
    
    private func trackPreferencesViewed() {
        Task {
            await analyticsService.trackEvent(.hapticPreferencesViewed, properties: [
                "tenantId": currentTenantId,
                "businessType": currentBusinessType.rawValue
            ])
        }
    }
    
    private func trackPreferencesSaved() {
        Task {
            await analyticsService.trackEvent(.hapticPreferencesSaved, properties: [
                "tenantId": currentTenantId,
                "globalIntensity": preferences.globalIntensity.rawValue,
                "brandingEnabled": preferences.brandingHapticEnabled,
                "watchSyncEnabled": preferences.watchSyncEnabled
            ])
        }
    }
    
    private func trackPreferencesReset() {
        Task {
            await analyticsService.trackEvent(.hapticPreferencesReset, properties: [
                "tenantId": currentTenantId,
                "businessType": currentBusinessType.rawValue
            ])
        }
    }
    
    private func trackContextIntensityChanged(context: HapticContextType, intensity: Float) {
        Task {
            await analyticsService.trackEvent(.hapticContextIntensityChanged, properties: [
                "tenantId": currentTenantId,
                "context": "\(context)",
                "intensity": intensity
            ])
        }
    }
    
    private func trackBusinessTypeOptimization() {
        Task {
            await analyticsService.trackEvent(.hapticBusinessTypeOptimization, properties: [
                "tenantId": currentTenantId,
                "businessType": currentBusinessType.rawValue,
                "newIntensity": preferences.globalIntensity.rawValue
            ])
        }
    }
    
    private func trackSettingsExported() {
        Task {
            await analyticsService.trackEvent(.hapticSettingsExported, properties: [
                "tenantId": currentTenantId
            ])
        }
    }
    
    private func trackSettingsImported() {
        Task {
            await analyticsService.trackEvent(.hapticSettingsImported, properties: [
                "tenantId": currentTenantId
            ])
        }
    }
}

// MARK: - Supporting Types

enum HapticValidationIssue {
    case luxuryHapticsNotSupported
    case watchSyncNotAvailable
    case batteryOptimizationRecommended
    case accessibilityOptimizationRecommended
    
    var title: String {
        switch self {
        case .luxuryHapticsNotSupported:
            return "Luxury Haptics Not Supported"
        case .watchSyncNotAvailable:
            return "Watch Sync Not Available"
        case .batteryOptimizationRecommended:
            return "Battery Optimization Recommended"
        case .accessibilityOptimizationRecommended:
            return "Accessibility Optimization Recommended"
        }
    }
    
    var description: String {
        switch self {
        case .luxuryHapticsNotSupported:
            return "Your current subscription tier does not support luxury haptic patterns."
        case .watchSyncNotAvailable:
            return "Apple Watch is not connected or supported on this device."
        case .batteryOptimizationRecommended:
            return "Enable battery optimization for better battery life with luxury haptics."
        case .accessibilityOptimizationRecommended:
            return "Enable accessibility optimization when Reduce Motion is enabled."
        }
    }
    
    var severity: ValidationSeverity {
        switch self {
        case .luxuryHapticsNotSupported:
            return .error
        case .watchSyncNotAvailable:
            return .warning
        case .batteryOptimizationRecommended:
            return .suggestion
        case .accessibilityOptimizationRecommended:
            return .suggestion
        }
    }
}

enum ValidationSeverity {
    case error, warning, suggestion
    
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .suggestion: return .blue
        }
    }
    
    var systemImage: String {
        switch self {
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.triangle"
        case .suggestion: return "lightbulb"
        }
    }
}

// MARK: - Analytics Event Extensions

extension AnalyticsEvent {
    static let hapticPreferencesViewed = AnalyticsEvent.custom("haptic_preferences_viewed")
    static let hapticPreferencesSaved = AnalyticsEvent.custom("haptic_preferences_saved")
    static let hapticPreferencesReset = AnalyticsEvent.custom("haptic_preferences_reset")
    static let hapticContextIntensityChanged = AnalyticsEvent.custom("haptic_context_intensity_changed")
    static let hapticBusinessTypeOptimization = AnalyticsEvent.custom("haptic_business_type_optimization")
    static let hapticSettingsExported = AnalyticsEvent.custom("haptic_settings_exported")
    static let hapticSettingsImported = AnalyticsEvent.custom("haptic_settings_imported")
}

// MARK: - Extensions

extension TenantHapticIntensity {
    init?(rawValue: String) {
        switch rawValue {
        case "minimal": self = .minimal
        case "standard": self = .standard
        case "enhanced": self = .enhanced
        case "luxury": self = .luxury
        default: return nil
        }
    }
    
    var rawValue: String {
        switch self {
        case .minimal: return "minimal"
        case .standard: return "standard"
        case .enhanced: return "enhanced"
        case .luxury: return "luxury"
        }
    }
}