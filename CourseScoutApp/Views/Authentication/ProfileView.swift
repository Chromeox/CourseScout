import SwiftUI
import Combine

// MARK: - Profile View

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        biometricService: BiometricAuthServiceProtocol,
        securityService: SecurityServiceProtocol,
        sessionManagementService: SessionManagementServiceProtocol
    ) {
        self._viewModel = StateObject(wrappedValue: ProfileViewModel(
            authenticationService: authenticationService,
            biometricService: biometricService,
            securityService: securityService,
            sessionManagementService: sessionManagementService
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            List {
                // Profile header
                profileHeaderSection
                
                // Account information
                accountInformationSection
                
                // Security settings
                securitySettingsSection
                
                // Privacy settings
                privacySettingsSection
                
                // Session management
                sessionManagementSection
                
                // Data management
                dataManagementSection
                
                // Support and help
                supportSection
                
                // Sign out
                signOutSection
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        viewModel.showEditProfile = true
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .sheet(isPresented: $viewModel.showEditProfile) {
            editProfileSheet
        }
        .sheet(isPresented: $viewModel.showSecuritySettings) {
            securitySettingsSheet
        }
        .sheet(isPresented: $viewModel.showPrivacySettings) {
            privacySettingsSheet
        }
        .sheet(isPresented: $viewModel.showSessionManagement) {
            sessionManagementSheet
        }
        .sheet(isPresented: $viewModel.showMFASetup) {
            mfaSetupSheet
        }
        .sheet(isPresented: $viewModel.showBiometricSetup) {
            biometricSetupSheet
        }
        .confirmationDialog(
            "Sign Out",
            isPresented: $viewModel.showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                viewModel.signOut()
            }
            Button("Sign Out All Devices", role: .destructive) {
                viewModel.signOutAllDevices()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose how you want to sign out")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Success", isPresented: $viewModel.showSuccess) {
            Button("OK") { viewModel.dismissSuccess() }
        } message: {
            Text(viewModel.successMessage)
        }
        .task {
            await viewModel.loadProfile()
        }
    }
    
    // MARK: - Profile Header Section
    
    private var profileHeaderSection: some View {
        Section {
            HStack(spacing: 16) {
                // Profile image
                AsyncImage(url: viewModel.user?.profileImageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Text(viewModel.user?.initials ?? "")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.user?.fullName ?? "User")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(viewModel.user?.email ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let tenant = viewModel.currentTenant {
                        HStack {
                            Image(systemName: "building.2")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text(tenant.name)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Account status indicator
                    accountStatusIndicator
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
    
    private var accountStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.accountStatus.color)
                .frame(width: 8, height: 8)
            
            Text(viewModel.accountStatus.description)
                .font(.caption)
                .foregroundColor(viewModel.accountStatus.color)
        }
    }
    
    // MARK: - Account Information Section
    
    private var accountInformationSection: some View {
        Section("Account Information") {
            ProfileRow(
                icon: "person.circle",
                title: "Personal Information",
                subtitle: "Name, email, phone number",
                action: { viewModel.showEditProfile = true }
            )
            
            if viewModel.showTenantInfo {
                ProfileRow(
                    icon: "building.2",
                    title: "Organization",
                    subtitle: viewModel.currentTenant?.name ?? "No organization",
                    action: { viewModel.showTenantManagement = true }
                )
            }
            
            ProfileRow(
                icon: "clock",
                title: "Account Created",
                subtitle: viewModel.formattedCreationDate,
                action: nil
            )
            
            if let lastLogin = viewModel.formattedLastLogin {
                ProfileRow(
                    icon: "clock.arrow.circlepath",
                    title: "Last Sign In",
                    subtitle: lastLogin,
                    action: nil
                )
            }
        }
    }
    
    // MARK: - Security Settings Section
    
    private var securitySettingsSection: some View {
        Section("Security") {
            ProfileRow(
                icon: "key",
                title: "Change Password",
                subtitle: "Update your password",
                action: { viewModel.showChangePassword = true }
            )
            
            ProfileToggleRow(
                icon: "number.square",
                title: "Two-Factor Authentication",
                subtitle: viewModel.mfaEnabled ? "Enabled" : "Disabled",
                isOn: $viewModel.mfaEnabled,
                action: { enabled in
                    if enabled {
                        viewModel.enableMFA()
                    } else {
                        viewModel.disableMFA()
                    }
                }
            )
            
            if viewModel.biometricAvailable {
                ProfileToggleRow(
                    icon: viewModel.biometricType == .faceID ? "faceid" : "touchid",
                    title: "Biometric Authentication",
                    subtitle: viewModel.biometricEnabled ? "Enabled" : "Disabled",
                    isOn: $viewModel.biometricEnabled,
                    action: { enabled in
                        if enabled {
                            viewModel.enableBiometrics()
                        } else {
                            viewModel.disableBiometrics()
                        }
                    }
                )
            }
            
            ProfileRow(
                icon: "shield",
                title: "Security Settings",
                subtitle: "Advanced security options",
                action: { viewModel.showSecuritySettings = true }
            )
        }
    }
    
    // MARK: - Privacy Settings Section
    
    private var privacySettingsSection: some View {
        Section("Privacy") {
            ProfileRow(
                icon: "hand.raised",
                title: "Privacy Settings",
                subtitle: "Manage your privacy preferences",
                action: { viewModel.showPrivacySettings = true }
            )
            
            ProfileRow(
                icon: "doc.text",
                title: "Data Export",
                subtitle: "Download your data",
                action: { viewModel.requestDataExport() }
            )
            
            ProfileRow(
                icon: "trash",
                title: "Delete Account",
                subtitle: "Permanently delete your account",
                destructive: true,
                action: { viewModel.showDeleteAccountConfirmation = true }
            )
        }
    }
    
    // MARK: - Session Management Section
    
    private var sessionManagementSection: some View {
        Section("Sessions") {
            ProfileRow(
                icon: "desktopcomputer",
                title: "Active Sessions",
                subtitle: "\(viewModel.activeSessions.count) active sessions",
                action: { viewModel.showSessionManagement = true }
            )
            
            ProfileRow(
                icon: "power",
                title: "Sign Out Other Devices",
                subtitle: "End all other sessions",
                action: { viewModel.signOutOtherDevices() }
            )
        }
    }
    
    // MARK: - Data Management Section
    
    private var dataManagementSection: some View {
        Section("Data Management") {
            ProfileToggleRow(
                icon: "icloud",
                title: "Sync Data",
                subtitle: viewModel.dataSyncEnabled ? "Enabled" : "Disabled",
                isOn: $viewModel.dataSyncEnabled,
                action: { enabled in
                    viewModel.toggleDataSync(enabled)
                }
            )
            
            ProfileToggleRow(
                icon: "wifi",
                title: "Offline Mode",
                subtitle: viewModel.offlineModeEnabled ? "Enabled" : "Disabled",
                isOn: $viewModel.offlineModeEnabled,
                action: { enabled in
                    viewModel.toggleOfflineMode(enabled)
                }
            )
            
            ProfileRow(
                icon: "arrow.clockwise",
                title: "Clear Cache",
                subtitle: "Free up storage space",
                action: { viewModel.clearCache() }
            )
        }
    }
    
    // MARK: - Support Section
    
    private var supportSection: some View {
        Section("Support") {
            ProfileRow(
                icon: "questionmark.circle",
                title: "Help Center",
                subtitle: "Get help and support",
                action: { viewModel.showHelpCenter = true }
            )
            
            ProfileRow(
                icon: "envelope",
                title: "Contact Support",
                subtitle: "Send us a message",
                action: { viewModel.contactSupport() }
            )
            
            ProfileRow(
                icon: "star",
                title: "Rate App",
                subtitle: "Rate us in the App Store",
                action: { viewModel.rateApp() }
            )
        }
    }
    
    // MARK: - Sign Out Section
    
    private var signOutSection: some View {
        Section {
            Button(action: { viewModel.showSignOutConfirmation = true }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.red)
                        .frame(width: 24)
                    
                    Text("Sign Out")
                        .foregroundColor(.red)
                    
                    Spacer()
                }
            }
            .disabled(viewModel.isLoading)
        }
    }
    
    // MARK: - Sheets
    
    private var editProfileSheet: some View {
        NavigationView {
            EditProfileView(viewModel: viewModel)
                .navigationTitle("Edit Profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            viewModel.showEditProfile = false
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            viewModel.saveProfile()
                        }
                        .disabled(!viewModel.hasProfileChanges || viewModel.isLoading)
                    }
                }
        }
    }
    
    private var securitySettingsSheet: some View {
        NavigationView {
            SecuritySettingsView(viewModel: viewModel)
                .navigationTitle("Security Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            viewModel.showSecuritySettings = false
                        }
                    }
                }
        }
    }
    
    private var privacySettingsSheet: some View {
        NavigationView {
            PrivacySettingsView(viewModel: viewModel)
                .navigationTitle("Privacy Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            viewModel.showPrivacySettings = false
                        }
                    }
                }
        }
    }
    
    private var sessionManagementSheet: some View {
        NavigationView {
            SessionManagementView(viewModel: viewModel)
                .navigationTitle("Active Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            viewModel.showSessionManagement = false
                        }
                    }
                }
        }
    }
    
    private var mfaSetupSheet: some View {
        NavigationView {
            MFASetupView(viewModel: viewModel)
        }
    }
    
    private var biometricSetupSheet: some View {
        NavigationView {
            BiometricSetupView(
                biometricService: viewModel.biometricService,
                onCompletion: { success in
                    viewModel.showBiometricSetup = false
                    if success {
                        viewModel.biometricEnabled = true
                    }
                }
            )
        }
    }
}

// MARK: - Supporting Views

struct ProfileRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var destructive: Bool = false
    let action: (() -> Void)?
    
    var body: some View {
        Button(action: action ?? {}) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(destructive ? .red : .blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(destructive ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if action != nil {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .disabled(action == nil)
    }
}

struct ProfileToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let action: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Toggle("", isOn: $isOn)
                .onChange(of: isOn) { newValue in
                    action(newValue)
                }
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        Form {
            Section("Personal Information") {
                HStack {
                    Text("First Name")
                    Spacer()
                    TextField("First Name", text: $viewModel.editFirstName)
                        .multilineTextAlignment(.trailing)
                }
                
                HStack {
                    Text("Last Name")
                    Spacer()
                    TextField("Last Name", text: $viewModel.editLastName)
                        .multilineTextAlignment(.trailing)
                }
                
                HStack {
                    Text("Email")
                    Spacer()
                    TextField("Email", text: $viewModel.editEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                }
                
                HStack {
                    Text("Phone")
                    Spacer()
                    TextField("Phone Number", text: $viewModel.editPhone)
                        .keyboardType(.phonePad)
                        .multilineTextAlignment(.trailing)
                }
            }
            
            Section("Preferences") {
                Picker("Language", selection: $viewModel.editLanguage) {
                    ForEach(viewModel.availableLanguages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                
                Picker("Time Zone", selection: $viewModel.editTimeZone) {
                    ForEach(viewModel.availableTimeZones, id: \.identifier) { timeZone in
                        Text(timeZone.displayName).tag(timeZone.identifier)
                    }
                }
            }
        }
    }
}

// MARK: - Security Settings View

struct SecuritySettingsView: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        List {
            Section("Multi-Factor Authentication") {
                if viewModel.mfaEnabled {
                    ProfileRow(
                        icon: "checkmark.circle.fill",
                        title: "MFA Enabled",
                        subtitle: "Your account is protected with 2FA",
                        action: nil
                    )
                    
                    Button("View Backup Codes") {
                        viewModel.showBackupCodes = true
                    }
                    
                    Button("Regenerate Backup Codes") {
                        viewModel.regenerateBackupCodes()
                    }
                    
                    Button("Disable MFA") {
                        viewModel.disableMFA()
                    }
                    .foregroundColor(.red)
                } else {
                    ProfileRow(
                        icon: "exclamationmark.triangle",
                        title: "MFA Disabled",
                        subtitle: "Enable for better security",
                        action: { viewModel.enableMFA() }
                    )
                }
            }
            
            Section("Login Security") {
                ProfileToggleRow(
                    icon: "location",
                    title: "Login Location Tracking",
                    subtitle: viewModel.loginLocationTrackingEnabled ? "Enabled" : "Disabled",
                    isOn: $viewModel.loginLocationTrackingEnabled,
                    action: { enabled in
                        viewModel.toggleLoginLocationTracking(enabled)
                    }
                )
                
                ProfileToggleRow(
                    icon: "bell",
                    title: "Login Notifications",
                    subtitle: viewModel.loginNotificationsEnabled ? "Enabled" : "Disabled",
                    isOn: $viewModel.loginNotificationsEnabled,
                    action: { enabled in
                        viewModel.toggleLoginNotifications(enabled)
                    }
                )
            }
        }
    }
}

// MARK: - Privacy Settings View

struct PrivacySettingsView: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        List {
            Section("Data Collection") {
                ProfileToggleRow(
                    icon: "chart.bar",
                    title: "Analytics",
                    subtitle: viewModel.analyticsEnabled ? "Enabled" : "Disabled",
                    isOn: $viewModel.analyticsEnabled,
                    action: { enabled in
                        viewModel.toggleAnalytics(enabled)
                    }
                )
                
                ProfileToggleRow(
                    icon: "location",
                    title: "Location Services",
                    subtitle: viewModel.locationServicesEnabled ? "Enabled" : "Disabled",
                    isOn: $viewModel.locationServicesEnabled,
                    action: { enabled in
                        viewModel.toggleLocationServices(enabled)
                    }
                )
            }
            
            Section("Marketing") {
                ProfileToggleRow(
                    icon: "envelope",
                    title: "Email Marketing",
                    subtitle: viewModel.emailMarketingEnabled ? "Enabled" : "Disabled",
                    isOn: $viewModel.emailMarketingEnabled,
                    action: { enabled in
                        viewModel.toggleEmailMarketing(enabled)
                    }
                )
                
                ProfileToggleRow(
                    icon: "bell",
                    title: "Push Notifications",
                    subtitle: viewModel.pushNotificationsEnabled ? "Enabled" : "Disabled",
                    isOn: $viewModel.pushNotificationsEnabled,
                    action: { enabled in
                        viewModel.togglePushNotifications(enabled)
                    }
                )
            }
        }
    }
}

// MARK: - Session Management View

struct SessionManagementView: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        List {
            ForEach(viewModel.activeSessions, id: \.id) { session in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: session.deviceIcon)
                            .foregroundColor(.blue)
                        
                        Text(session.deviceName)
                            .font(.headline)
                        
                        if session.isCurrent {
                            Text("Current")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        Button("End") {
                            viewModel.terminateSession(session.id)
                        }
                        .foregroundColor(.red)
                        .disabled(session.isCurrent)
                    }
                    
                    Text("Last active: \(session.lastActiveFormatted)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(session.location) • \(session.ipAddress)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Extensions

extension AccountStatus {
    var color: Color {
        switch self {
        case .active: return .green
        case .pending: return .orange
        case .suspended: return .red
        case .restricted: return .yellow
        }
    }
    
    var description: String {
        switch self {
        case .active: return "Active"
        case .pending: return "Pending Verification"
        case .suspended: return "Suspended"
        case .restricted: return "Restricted"
        }
    }
}

extension AuthenticatedUser {
    var initials: String {
        let firstInitial = firstName.first?.uppercased() ?? ""
        let lastInitial = lastName.first?.uppercased() ?? ""
        return "\(firstInitial)\(lastInitial)"
    }
    
    var fullName: String {
        return "\(firstName) \(lastName)"
    }
}

// MARK: - Preview

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(
            authenticationService: MockAuthenticationService(),
            biometricService: MockBiometricAuthService(),
            securityService: MockSecurityService(),
            sessionManagementService: MockSessionManagementService()
        )
    }
}

class MockSecurityService: SecurityServiceProtocol {
    func evaluateDeviceTrust() async -> DeviceTrustLevel {
        return .trusted
    }
    
    func checkForRequiredSecurityUpdates() async -> Bool {
        return false
    }
    
    func validateDeviceIntegrity() async throws -> DeviceIntegrityResult {
        return DeviceIntegrityResult(
            isIntegrityVerified: true,
            jailbrokenDetected: false,
            debuggerDetected: false,
            emulatorDetected: false,
            riskLevel: .low
        )
    }
    
    func encryptSensitiveData(_ data: Data) throws -> Data {
        return data
    }
    
    func decryptSensitiveData(_ encryptedData: Data) throws -> Data {
        return encryptedData
    }
}

class MockSessionManagementService: SessionManagementServiceProtocol {
    func createSession(userId: String, tenantId: String?, deviceInfo: DeviceInfo) async throws -> SessionCreationResult {
        throw AuthenticationError.networkError("Mock")
    }
    
    func validateSession(sessionId: String) async throws -> SessionValidationServiceResult {
        throw AuthenticationError.networkError("Mock")
    }
    
    func terminateSession(sessionId: String) async throws {
    }
    
    func terminateAllUserSessions(userId: String, excludeCurrentDevice: Bool) async throws {
    }
    
    func refreshAccessToken(refreshToken: String) async throws -> SessionRefreshResult {
        throw AuthenticationError.networkError("Mock")
    }
    
    func revokeToken(token: String, tokenType: TokenType) async throws {
    }
    
    func getUserSessions(userId: String) async throws -> [SessionInfo] {
        return []
    }
}