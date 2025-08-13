import SwiftUI
import CoreHaptics

/// Tenant Haptic Preferences Configuration View
/// Allows golf course operators to customize haptic feedback experiences for their brand
struct TenantHapticPreferencesView: View {
    
    // MARK: - View Model
    @StateObject private var viewModel = TenantHapticPreferencesViewModel()
    
    // MARK: - State Management
    @State private var showingPreview = false
    @State private var showingAdvancedSettings = false
    @State private var isTestingPattern = false
    @State private var selectedTestPattern: HapticTestPattern = .branding
    
    // MARK: - Tenant Integration
    @TenantInjected(\.theme) private var theme: WhiteLabelTheme
    @TenantInjected(\.branding) private var branding: TenantBranding
    @TenantInjected(\.features) private var features: TenantFeatures
    @TenantInjected(\.displayName, default: "Golf Course") private var brandName: String
    
    // MARK: - Services
    @ServiceInjected(HapticFeedbackServiceProtocol.self)
    private var hapticService: HapticFeedbackServiceProtocol
    
    @ServiceInjected(TenantConfigurationServiceProtocol.self)
    private var tenantConfigService: TenantConfigurationServiceProtocol
    
    var body: some View {
        NavigationView {
            Form {
                // Haptic Experience Overview
                hapticOverviewSection
                
                // Basic Settings
                basicSettingsSection
                
                // Intensity Configuration
                intensityConfigurationSection
                
                // Feature-Specific Settings
                featureSettingsSection
                
                // Advanced Settings
                if showingAdvancedSettings {
                    advancedSettingsSection
                }
                
                // Testing and Preview
                testingSection
                
                // Business Type Integration
                businessTypeSection
            }
            .navigationTitle("Haptic Experience")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Advanced Settings") {
                            showingAdvancedSettings.toggle()
                        }
                        
                        Button("Reset to Defaults") {
                            resetToDefaults()
                        }
                        
                        Button("Export Settings") {
                            exportSettings()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(theme.primarySwiftUIColor)
                    }
                }
            }
        }
        .tenantThemed()
        .onAppear {
            Task {
                await viewModel.loadCurrentPreferences()
            }
        }
        .onChange(of: viewModel.preferences) { _, newPreferences in
            Task {
                await updateTenantHapticPreferences(newPreferences)
            }
        }
    }
    
    // MARK: - Haptic Overview Section
    
    private var hapticOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "waveform.path")
                        .foregroundColor(theme.primarySwiftUIColor)
                        .font(.title2)
                    
                    VStack(alignment: .leading) {
                        Text("Premium Haptic Experience")
                            .font(.headline)
                            .foregroundColor(theme.textSwiftUIColor)
                        
                        Text("for \(brandName)")
                            .font(.subheadline)
                            .foregroundColor(theme.subtextSwiftUIColor)
                    }
                    
                    Spacer()
                    
                    Button("Preview") {
                        showingPreview = true
                    }
                    .tenantThemedButton(isSecondary: true)
                }
                
                // Haptic Capabilities Overview
                HapticCapabilitiesView(capabilities: viewModel.hapticCapabilities)
            }
        } header: {
            Text("Haptic Experience Overview")
        } footer: {
            Text("Customize tactile feedback to match your \(brandName) brand experience. Haptic feedback enhances user engagement and accessibility.")
        }
    }
    
    // MARK: - Basic Settings Section
    
    private var basicSettingsSection: some View {
        Section {
            // Enable/Disable Haptics
            Toggle("Enable Haptic Feedback", isOn: $viewModel.preferences.isEnabled)
                .tint(theme.primarySwiftUIColor)
                .onChange(of: viewModel.preferences.isEnabled) { _, newValue in
                    if newValue {
                        Task {
                            await testHapticFeedback(.selection)
                        }
                    }
                }
            
            // Global Intensity
            VStack(alignment: .leading, spacing: 8) {
                Text("Experience Intensity")
                    .font(.subheadline)
                    .foregroundColor(theme.textSwiftUIColor)
                
                IntensitySlider(
                    intensity: $viewModel.preferences.globalIntensity,
                    theme: theme,
                    hapticService: hapticService
                )
            }
            
            // Brand Haptic Signature
            HStack {
                VStack(alignment: .leading) {
                    Text("Brand Haptic Signature")
                        .font(.subheadline)
                    
                    Text("Unique haptic pattern for your brand")
                        .font(.caption)
                        .foregroundColor(theme.subtextSwiftUIColor)
                }
                
                Spacer()
                
                Toggle("", isOn: $viewModel.preferences.brandingHapticEnabled)
                    .tint(theme.accentSwiftUIColor)
            }
        } header: {
            Text("Basic Settings")
        }
    }
    
    // MARK: - Intensity Configuration Section
    
    private var intensityConfigurationSection: some View {
        Section {
            ForEach(HapticContextType.allCases, id: \.self) { context in
                HapticContextRow(
                    context: context,
                    intensity: viewModel.getContextIntensity(for: context),
                    theme: theme
                ) { newIntensity in
                    viewModel.updateContextIntensity(for: context, intensity: newIntensity)
                }
            }
        } header: {
            Text("Context-Specific Intensities")
        } footer: {
            Text("Fine-tune haptic intensity for different interaction contexts.")
        }
    }
    
    // MARK: - Feature Settings Section
    
    private var featureSettingsSection: some View {
        Section {
            FeatureToggleRow(
                title: "Golf Course Discovery",
                description: "Haptic feedback during course search and selection",
                isEnabled: $viewModel.preferences.analyticsHapticsEnabled,
                theme: theme
            )
            
            FeatureToggleRow(
                title: "Booking Experience",
                description: "Enhanced haptic feedback during tee time booking",
                isEnabled: $viewModel.preferences.bookingHapticsEnabled,
                theme: theme
            )
            
            FeatureToggleRow(
                title: "Management Operations",
                description: "Haptic feedback for administrative actions",
                isEnabled: $viewModel.preferences.managementHapticsEnabled,
                theme: theme
            )
            
            FeatureToggleRow(
                title: "Apple Watch Sync",
                description: "Synchronize haptics with paired Apple Watch",
                isEnabled: $viewModel.preferences.watchSyncEnabled,
                theme: theme
            )
        } header: {
            Text("Feature-Specific Haptics")
        }
    }
    
    // MARK: - Advanced Settings Section
    
    private var advancedSettingsSection: some View {
        Section {
            // Accessibility Optimization
            Toggle("Accessibility Optimized", isOn: $viewModel.preferences.accessibilityOptimized)
                .tint(theme.primarySwiftUIColor)
            
            // Battery Optimization
            Toggle("Battery Optimized", isOn: $viewModel.preferences.batteryOptimized)
                .tint(theme.primarySwiftUIColor)
            
            // Custom Pattern Editor
            NavigationLink(destination: CustomHapticPatternEditor()) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(theme.primarySwiftUIColor)
                    
                    VStack(alignment: .leading) {
                        Text("Custom Patterns")
                        Text("\(viewModel.preferences.customPatterns.count) patterns")
                            .font(.caption)
                            .foregroundColor(theme.subtextSwiftUIColor)
                    }
                    
                    Spacer()
                }
            }
            
            // Performance Analytics
            NavigationLink(destination: HapticAnalyticsView()) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(theme.primarySwiftUIColor)
                    
                    Text("Haptic Analytics")
                    
                    Spacer()
                    
                    Text(viewModel.usageMetrics.formattedUsageCount)
                        .font(.caption)
                        .foregroundColor(theme.subtextSwiftUIColor)
                }
            }
        } header: {
            Text("Advanced Settings")
        }
    }
    
    // MARK: - Testing Section
    
    private var testingSection: some View {
        Section {
            VStack(spacing: 16) {
                // Test Pattern Selector
                Picker("Test Pattern", selection: $selectedTestPattern) {
                    ForEach(HapticTestPattern.allCases, id: \.self) { pattern in
                        Text(pattern.displayName).tag(pattern)
                    }
                }
                .pickerStyle(.segmented)
                
                // Test Button
                Button(action: testSelectedPattern) {
                    HStack {
                        if isTestingPattern {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "play.circle.fill")
                        }
                        
                        Text(isTestingPattern ? "Testing..." : "Test Haptic Pattern")
                    }
                }
                .disabled(isTestingPattern || !viewModel.preferences.isEnabled)
                .tenantThemedButton()
                
                // Haptic Library
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(HapticLibraryPattern.allCases, id: \.self) { pattern in
                            HapticLibraryButton(
                                pattern: pattern,
                                theme: theme
                            ) {
                                Task {
                                    await testLibraryPattern(pattern)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        } header: {
            Text("Testing & Preview")
        } footer: {
            Text("Test different haptic patterns to experience how they feel with your current settings.")
        }
    }
    
    // MARK: - Business Type Section
    
    private var businessTypeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "building.2")
                        .foregroundColor(theme.primarySwiftUIColor)
                    
                    Text("Business Type Integration")
                        .font(.headline)
                    
                    Spacer()
                }
                
                BusinessTypeHapticCard(
                    businessType: viewModel.currentBusinessType,
                    theme: theme,
                    recommendations: viewModel.businessTypeRecommendations
                )
            }
        } header: {
            Text("Optimized for Your Business")
        } footer: {
            Text("Haptic settings are automatically optimized based on your business type for the best user experience.")
        }
    }
    
    // MARK: - Action Methods
    
    private func testSelectedPattern() {
        guard !isTestingPattern else { return }
        
        isTestingPattern = true
        
        Task {
            switch selectedTestPattern {
            case .branding:
                await hapticService.playTenantBrandingHaptic()
            case .booking:
                await hapticService.tenantBookingHaptic(stage: .confirmed, intensity: viewModel.preferences.globalIntensity)
            case .analytics:
                await hapticService.analyticsInteractionHaptic(type: .goalReached)
            case .discovery:
                await hapticService.courseDiscoveryHaptic(type: .courseSelected)
            case .success:
                await hapticService.tenantSuccessHaptic(achievement: .satisfactionGoalMet)
            case .emergency:
                await hapticService.emergencyAlertHaptic(alert: .weatherWarning(severity: .warning), tenant: viewModel.currentTenantId)
            }
            
            // Add a delay to prevent rapid testing
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                isTestingPattern = false
            }
        }
    }
    
    private func testLibraryPattern(_ pattern: HapticLibraryPattern) async {
        let hapticPattern = pattern.hapticPattern
        await hapticService.playCustomPattern(hapticPattern)
    }
    
    private func testHapticFeedback(_ type: HapticFeedbackType) async {
        switch type {
        case .selection:
            hapticService.selection()
        case .success:
            hapticService.success()
        case .warning:
            hapticService.warning()
        case .error:
            hapticService.error()
        default:
            hapticService.lightImpact()
        }
    }
    
    private func updateTenantHapticPreferences(_ preferences: TenantHapticPreferences) async {
        do {
            try await hapticService.updateTenantHapticPreferences(preferences)
            viewModel.updateSuccessMessage = "Haptic preferences updated successfully"
        } catch {
            viewModel.updateErrorMessage = error.localizedDescription
        }
    }
    
    private func resetToDefaults() {
        withAnimation {
            viewModel.resetToDefaults()
        }
        
        Task {
            await testHapticFeedback(.success)
        }
    }
    
    private func exportSettings() {
        viewModel.exportHapticSettings()
    }
}

// MARK: - Supporting View Components

struct IntensitySlider: View {
    @Binding var intensity: TenantHapticIntensity
    let theme: WhiteLabelTheme
    let hapticService: HapticFeedbackServiceProtocol
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(TenantHapticIntensity.allCases, id: \.self) { level in
                    Button(level.displayName) {
                        intensity = level
                        
                        Task {
                            await hapticService.courseDiscoveryHaptic(type: .courseSelected)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        intensity == level ? theme.primarySwiftUIColor : Color.clear
                    )
                    .foregroundColor(
                        intensity == level ? .white : theme.textSwiftUIColor
                    )
                    .cornerRadius(8)
                    .font(.caption.weight(.medium))
                }
            }
            
            Text(intensity.description)
                .font(.caption2)
                .foregroundColor(theme.subtextSwiftUIColor)
        }
    }
}

struct HapticContextRow: View {
    let context: HapticContextType
    @State var intensity: Float
    let theme: WhiteLabelTheme
    let onIntensityChanged: (Float) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.displayName)
                    .font(.subheadline)
                
                Spacer()
                
                Text(String(format: "%.0f%%", intensity * 100))
                    .font(.caption)
                    .foregroundColor(theme.subtextSwiftUIColor)
            }
            
            Slider(value: $intensity, in: 0.1...1.0, step: 0.1) {
                Text(context.displayName)
            }
            .tint(theme.primarySwiftUIColor)
            .onChange(of: intensity) { _, newValue in
                onIntensityChanged(newValue)
            }
        }
    }
}

struct FeatureToggleRow: View {
    let title: String
    let description: String
    @Binding var isEnabled: Bool
    let theme: WhiteLabelTheme
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(theme.subtextSwiftUIColor)
            }
            
            Spacer()
            
            Toggle("", isOn: $isEnabled)
                .tint(theme.accentSwiftUIColor)
        }
    }
}

struct HapticLibraryButton: View {
    let pattern: HapticLibraryPattern
    let theme: WhiteLabelTheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: pattern.systemImage)
                    .font(.title2)
                
                Text(pattern.displayName)
                    .font(.caption2)
            }
            .padding(12)
            .background(theme.surfaceSwiftUIColor)
            .foregroundColor(theme.textSwiftUIColor)
            .cornerRadius(8)
        }
    }
}

struct HapticCapabilitiesView: View {
    let capabilities: HapticCapabilities
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Device Capabilities")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                CapabilityItem(
                    title: "Core Haptics",
                    isSupported: capabilities.supportsCoreHaptics
                )
                
                CapabilityItem(
                    title: "Advanced Patterns",
                    isSupported: capabilities.supportsAdvancedPatterns
                )
                
                CapabilityItem(
                    title: "Watch Sync",
                    isSupported: capabilities.supportsWatchConnectivity
                )
                
                CapabilityItem(
                    title: "\(capabilities.maxSimultaneousEvents) Events",
                    isSupported: capabilities.maxSimultaneousEvents > 0
                )
            }
        }
    }
}

struct CapabilityItem: View {
    let title: String
    let isSupported: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isSupported ? .green : .red)
                .font(.caption)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct BusinessTypeHapticCard: View {
    let businessType: BusinessType
    let theme: WhiteLabelTheme
    let recommendations: [HapticRecommendation]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(businessType.displayName)
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
                
                Text("Optimized")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.accentSwiftUIColor.opacity(0.2))
                    .foregroundColor(theme.accentSwiftUIColor)
                    .cornerRadius(4)
            }
            
            ForEach(recommendations, id: \.title) { recommendation in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: recommendation.icon)
                        .foregroundColor(theme.primarySwiftUIColor)
                        .font(.caption)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recommendation.title)
                            .font(.caption.weight(.medium))
                        
                        Text(recommendation.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(theme.surfaceSwiftUIColor)
        .cornerRadius(8)
    }
}

// MARK: - Supporting Types and Extensions

enum HapticTestPattern: String, CaseIterable {
    case branding = "branding"
    case booking = "booking"
    case analytics = "analytics"
    case discovery = "discovery"
    case success = "success"
    case emergency = "emergency"
    
    var displayName: String {
        switch self {
        case .branding: return "Branding"
        case .booking: return "Booking"
        case .analytics: return "Analytics"
        case .discovery: return "Discovery"
        case .success: return "Success"
        case .emergency: return "Alert"
        }
    }
}

enum HapticLibraryPattern: String, CaseIterable {
    case gentle = "gentle"
    case medium = "medium"
    case strong = "strong"
    case pulse = "pulse"
    case wave = "wave"
    case burst = "burst"
    
    var displayName: String {
        switch self {
        case .gentle: return "Gentle"
        case .medium: return "Medium"
        case .strong: return "Strong"
        case .pulse: return "Pulse"
        case .wave: return "Wave"
        case .burst: return "Burst"
        }
    }
    
    var systemImage: String {
        switch self {
        case .gentle: return "waveform.path"
        case .medium: return "waveform.path.ecg"
        case .strong: return "waveform.path.badge.plus"
        case .pulse: return "dot.radiowaves.left.and.right"
        case .wave: return "water.waves"
        case .burst: return "burst.fill"
        }
    }
    
    var hapticPattern: HapticPattern {
        switch self {
        case .gentle:
            return HapticPattern(
                name: "Gentle Touch",
                events: [HapticEvent(time: 0.0, intensity: 0.3, sharpness: 0.2, duration: 0.2)],
                duration: 0.2
            )
        case .medium:
            return HapticPattern(
                name: "Medium Impact",
                events: [HapticEvent(time: 0.0, intensity: 0.6, sharpness: 0.5, duration: 0.15)],
                duration: 0.15
            )
        case .strong:
            return HapticPattern(
                name: "Strong Impact",
                events: [HapticEvent(time: 0.0, intensity: 0.9, sharpness: 0.8, duration: 0.1)],
                duration: 0.1
            )
        case .pulse:
            return HapticPattern(
                name: "Pulse",
                events: [
                    HapticEvent(time: 0.0, intensity: 0.5, sharpness: 0.5, duration: 0.1),
                    HapticEvent(time: 0.2, intensity: 0.5, sharpness: 0.5, duration: 0.1)
                ],
                duration: 0.3
            )
        case .wave:
            return HapticPattern(
                name: "Wave",
                events: [
                    HapticEvent(time: 0.0, intensity: 0.3, sharpness: 0.3, duration: 0.15),
                    HapticEvent(time: 0.15, intensity: 0.6, sharpness: 0.5, duration: 0.15),
                    HapticEvent(time: 0.3, intensity: 0.3, sharpness: 0.3, duration: 0.15)
                ],
                duration: 0.45
            )
        case .burst:
            return HapticPattern(
                name: "Burst",
                events: [
                    HapticEvent(time: 0.0, intensity: 0.8, sharpness: 0.9, duration: 0.05),
                    HapticEvent(time: 0.1, intensity: 0.6, sharpness: 0.7, duration: 0.05),
                    HapticEvent(time: 0.2, intensity: 0.4, sharpness: 0.5, duration: 0.05)
                ],
                duration: 0.25
            )
        }
    }
}

extension HapticContextType {
    static var allCases: [HapticContextType] {
        [.booking, .analytics, .management, .branding, .emergency]
    }
    
    var displayName: String {
        switch self {
        case .booking: return "Booking Experience"
        case .analytics: return "Data & Analytics"
        case .management: return "Management Operations"
        case .branding: return "Brand Experience"
        case .emergency: return "Emergency Alerts"
        }
    }
}

extension TenantHapticIntensity {
    static var allCases: [TenantHapticIntensity] {
        [.minimal, .standard, .enhanced, .luxury]
    }
    
    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .enhanced: return "Enhanced"
        case .luxury: return "Luxury"
        }
    }
    
    var description: String {
        switch self {
        case .minimal: return "Subtle, accessibility-focused feedback"
        case .standard: return "Balanced feedback for general use"
        case .enhanced: return "Pronounced feedback for premium feel"
        case .luxury: return "Rich, multi-layered premium experience"
        }
    }
}

struct HapticRecommendation {
    let title: String
    let description: String
    let icon: String
}

struct HapticUsageMetrics {
    let totalUsage: Int
    let dailyAverage: Double
    let mostUsedPattern: String
    
    var formattedUsageCount: String {
        if totalUsage > 1000 {
            return String(format: "%.1fK", Double(totalUsage) / 1000.0)
        }
        return "\(totalUsage)"
    }
}

// MARK: - Placeholder Views for Navigation

struct CustomHapticPatternEditor: View {
    var body: some View {
        Text("Custom Haptic Pattern Editor")
            .navigationTitle("Pattern Editor")
    }
}

struct HapticAnalyticsView: View {
    var body: some View {
        Text("Haptic Analytics Dashboard")
            .navigationTitle("Haptic Analytics")
    }
}

// MARK: - Preview

#Preview {
    TenantHapticPreferencesView()
        .environmentObject(ServiceContainer.shared)
}