import SwiftUI
import WatchKit
import Combine

// MARK: - Watch Tenant Switch View

struct WatchTenantSwitchView: View {
    // MARK: - Environment & Services
    
    @EnvironmentObject private var tenantConfigService: WatchTenantConfigurationService
    @EnvironmentObject private var themeService: WatchTenantThemeService
    @Environment(\.watchServiceContainer) private var serviceContainer
    
    // MARK: - State Management
    
    @State private var availableTenants: [WatchTenantContext] = []
    @State private var isLoading = false
    @State private var showOfflineMode = false
    @State private var selectedTenantId: String?
    @State private var errorMessage: String?
    @State private var syncStatus: TenantSyncStatus = .idle
    
    // MARK: - Animation State
    
    @State private var animationScale: Double = 1.0
    @State private var currentBusinessTypeIndex = 0
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Current Tenant Display
                    currentTenantSection
                    
                    // Available Tenants List
                    if !availableTenants.isEmpty {
                        availableTenantsSection
                    }
                    
                    // Offline Mode Toggle
                    offlineModeSection
                    
                    // Sync Controls
                    syncControlsSection
                }
                .padding(.horizontal, 4)
                .animation(.easeInOut(duration: 0.3), value: isLoading)
            }
            .navigationTitle("Tenants")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadAvailableTenants()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    // MARK: - Current Tenant Section
    
    private var currentTenantSection: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: tenantConfigService.currentTenantContext.businessType.iconName)
                    .foregroundColor(themeService.getPrimaryColor())
                    .font(.title3)
                    .scaleEffect(animationScale)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: animationScale)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tenantConfigService.isMultiTenantMode ? "Current Tenant" : "Default Mode")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(getCurrentTenantDisplayName())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(themeService.getTextColor())
                        .lineLimit(1)
                }
                
                Spacer()
                
                businessTypeIndicator
            }
            
            // Tenant Features Indicator
            if tenantConfigService.isMultiTenantMode {
                featuresIndicator
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(themeService.getBackgroundColor().opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(themeService.getPrimaryColor(), lineWidth: 1)
                )
        )
        .onAppear {
            animationScale = 1.1
        }
    }
    
    private var businessTypeIndicator: some View {
        VStack(spacing: 2) {
            Image(systemName: getBusinessTypeIcon())
                .foregroundColor(themeService.getSecondaryColor())
                .font(.caption)
            
            Text(tenantConfigService.currentTenantContext.businessType.shortName)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var featuresIndicator: some View {
        HStack(spacing: 4) {
            if tenantConfigService.currentTenantContext.features.enableHaptics {
                Image(systemName: "waveform")
                    .foregroundColor(themeService.getAccentColor())
                    .font(.caption2)
            }
            
            if tenantConfigService.currentTenantContext.features.enablePremiumAnalytics {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(themeService.getAccentColor())
                    .font(.caption2)
            }
            
            if tenantConfigService.currentTenantContext.features.enableConcierge {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundColor(themeService.getAccentColor())
                    .font(.caption2)
            }
            
            Spacer()
        }
        .padding(.top, 2)
    }
    
    // MARK: - Available Tenants Section
    
    private var availableTenantsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Available Tenants")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            ForEach(availableTenants, id: \.tenantId) { tenantContext in
                TenantRowView(
                    tenantContext: tenantContext,
                    isSelected: tenantContext.tenantId == tenantConfigService.currentTenantContext.tenantId,
                    isLoading: isLoading && selectedTenantId == tenantContext.tenantId
                ) {
                    switchToTenant(tenantContext)
                }
            }
        }
    }
    
    // MARK: - Offline Mode Section
    
    private var offlineModeSection: some View {
        VStack(spacing: 4) {
            Toggle(isOn: $showOfflineMode) {
                HStack {
                    Image(systemName: showOfflineMode ? "wifi.slash" : "wifi")
                        .foregroundColor(showOfflineMode ? .orange : themeService.getPrimaryColor())
                        .font(.caption)
                    
                    Text("Offline Mode")
                        .font(.caption)
                        .foregroundColor(themeService.getTextColor())
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: themeService.getAccentColor()))
            
            if showOfflineMode {
                Text("Using cached tenant data")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.top, 2)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(themeService.getBackgroundColor().opacity(0.2))
        )
    }
    
    // MARK: - Sync Controls Section
    
    private var syncControlsSection: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: syncTenantsFromiPhone) {
                    HStack(spacing: 4) {
                        Image(systemName: getSyncIcon())
                            .font(.caption)
                            .rotationEffect(.degrees(syncStatus == .syncing ? 360 : 0))
                            .animation(
                                syncStatus == .syncing ? 
                                .linear(duration: 1.0).repeatForever(autoreverses: false) : 
                                .default, 
                                value: syncStatus
                            )
                        
                        Text(getSyncStatusText())
                            .font(.caption)
                    }
                    .foregroundColor(themeService.getPrimaryColor())
                }
                .disabled(syncStatus == .syncing)
                
                Spacer()
                
                Button("Reset") {
                    resetToDefault()
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            
            // Last sync info
            if syncStatus != .idle {
                Text(getSyncStatusDescription())
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(themeService.getBackgroundColor().opacity(0.1))
        )
    }
    
    // MARK: - Helper Methods
    
    private func loadAvailableTenants() {
        if showOfflineMode {
            availableTenants = tenantConfigService.getAvailableOfflineTenants()
        } else {
            // In a real implementation, this would fetch from the iPhone or cache
            availableTenants = tenantConfigService.getAvailableOfflineTenants()
        }
    }
    
    private func switchToTenant(_ tenantContext: WatchTenantContext) {
        guard !isLoading else { return }
        
        selectedTenantId = tenantContext.tenantId
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                await serviceContainer.switchToTenant(tenantContext)
                
                // Trigger tenant branding haptic
                if let hapticService = try? serviceContainer.resolve(WatchHapticFeedbackServiceProtocol.self) as? WatchHapticFeedbackService {
                    await hapticService.triggerTenantBrandingHaptic()
                }
                
                await MainActor.run {
                    isLoading = false
                    selectedTenantId = nil
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    selectedTenantId = nil
                    errorMessage = "Failed to switch tenant: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func syncTenantsFromiPhone() {
        guard syncStatus != .syncing else { return }
        
        syncStatus = .syncing
        
        Task {
            do {
                try await tenantConfigService.syncTenantConfiguration()
                loadAvailableTenants()
                
                await MainActor.run {
                    syncStatus = .success
                }
                
                // Reset status after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    syncStatus = .idle
                }
            } catch {
                await MainActor.run {
                    syncStatus = .error(error.localizedDescription)
                    errorMessage = "Sync failed: \(error.localizedDescription)"
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    syncStatus = .idle
                }
            }
        }
    }
    
    private func resetToDefault() {
        Task {
            await serviceContainer.switchToTenant(.defaultContext)
            await themeService.resetToDefaultTheme()
            
            await MainActor.run {
                loadAvailableTenants()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private func getCurrentTenantDisplayName() -> String {
        if tenantConfigService.isMultiTenantMode,
           let tenantId = tenantConfigService.currentTenantContext.tenantId {
            return tenantId.capitalized
        }
        return "Default Golf Course"
    }
    
    private func getBusinessTypeIcon() -> String {
        return tenantConfigService.currentTenantContext.businessType.iconName
    }
    
    private func getSyncIcon() -> String {
        switch syncStatus {
        case .idle: return "arrow.triangle.2.circlepath"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }
    
    private func getSyncStatusText() -> String {
        switch syncStatus {
        case .idle: return "Sync"
        case .syncing: return "Syncing..."
        case .success: return "Synced"
        case .error: return "Error"
        }
    }
    
    private func getSyncStatusDescription() -> String {
        switch syncStatus {
        case .idle: return ""
        case .syncing: return "Syncing tenant data from iPhone..."
        case .success: return "Successfully synced tenant configurations"
        case .error(let message): return "Sync error: \(message)"
        }
    }
}

// MARK: - Tenant Row View

struct TenantRowView: View {
    let tenantContext: WatchTenantContext
    let isSelected: Bool
    let isLoading: Bool
    let onTap: () -> Void
    
    @EnvironmentObject private var themeService: WatchTenantThemeService
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Business Type Icon
                Image(systemName: tenantContext.businessType.iconName)
                    .foregroundColor(getTenantColor())
                    .font(.caption)
                    .frame(width: 20)
                
                // Tenant Info
                VStack(alignment: .leading, spacing: 1) {
                    Text(tenantContext.tenantId?.capitalized ?? "Default")
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? themeService.getPrimaryColor() : themeService.getTextColor())
                        .lineLimit(1)
                    
                    Text(tenantContext.businessType.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Status Indicator
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(themeService.getPrimaryColor())
                        .font(.caption)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected ? 
                    themeService.getPrimaryColor().opacity(0.15) : 
                    themeService.getBackgroundColor().opacity(0.1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? themeService.getPrimaryColor() : Color.clear, 
                            lineWidth: 1
                        )
                )
        )
    }
    
    private func getTenantColor() -> Color {
        if let colorHex = tenantContext.theme.primaryColor.isEmpty ? nil : tenantContext.theme.primaryColor {
            return Color(hex: colorHex) ?? themeService.getPrimaryColor()
        }
        return themeService.getPrimaryColor()
    }
}

// MARK: - Supporting Types

enum TenantSyncStatus: Equatable {
    case idle
    case syncing
    case success
    case error(String)
}

// MARK: - Preview

struct WatchTenantSwitchView_Previews: PreviewProvider {
    static var previews: some View {
        WatchTenantSwitchView()
            .environmentObject(MockWatchTenantConfigurationService())
            .environmentObject(MockWatchTenantThemeService())
            .environment(\.watchServiceContainer, WatchServiceContainer.shared)
    }
}