import SwiftUI
import LocalAuthentication

// MARK: - Login View

struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        biometricService: BiometricAuthServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol
    ) {
        self._viewModel = StateObject(wrappedValue: LoginViewModel(
            authenticationService: authenticationService,
            biometricService: biometricService,
            tenantConfigurationService: tenantConfigurationService
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // Header with branding
                        headerSection
                        
                        // Main login form
                        loginFormSection
                            .padding(.horizontal, 24)
                        
                        Spacer(minLength: 40)
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .overlay(loadingOverlay)
        .sheet(isPresented: $viewModel.showProviderSelection) {
            providerSelectionSheet
        }
        .sheet(isPresented: $viewModel.showTenantSelection) {
            tenantSelectionSheet
        }
        .sheet(isPresented: $viewModel.showMFAPrompt) {
            mfaPromptSheet
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Success", isPresented: $viewModel.showSuccess) {
            Button("OK") { }
        } message: {
            Text(viewModel.successMessage)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 24) {
            // App logo or tenant branding
            if let branding = viewModel.brandingConfiguration {
                brandedHeader(branding)
            } else {
                defaultHeader
            }
            
            // Welcome message
            welcomeMessage
        }
        .padding(.top, 60)
        .padding(.bottom, 40)
        .background(headerBackground)
    }
    
    private func brandedHeader(_ branding: BrandingConfiguration) -> some View {
        VStack(spacing: 16) {
            if let logoURL = branding.logoURL {
                AsyncImage(url: logoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
                .frame(height: 80)
            }
            
            Text(branding.appName)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Color(hex: branding.primaryColor) ?? .primary)
        }
    }
    
    private var defaultHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: "golf.club.ball")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("GolfFinder")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
    }
    
    private var welcomeMessage: some View {
        VStack(spacing: 8) {
            Text("Welcome Back")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("Sign in to your account")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    private var headerBackground: some View {
        LinearGradient(
            colors: [
                viewModel.tenantTheme?.backgroundColor ?? Color(.systemBackground),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(.all, edges: .top)
    }
    
    // MARK: - Login Form Section
    
    private var loginFormSection: some View {
        VStack(spacing: 24) {
            // Mode toggle
            modeToggle
            
            // Form fields
            if viewModel.isEnterpriseMode {
                enterpriseFields
            } else {
                standardFields
            }
            
            // Biometric login (if available)
            if viewModel.canShowBiometricLogin {
                biometricLoginButton
            }
            
            // Main action buttons
            actionButtons
            
            // Alternative sign-in options
            alternativeSignInOptions
            
            // Footer links
            footerLinks
        }
    }
    
    private var modeToggle: some View {
        HStack {
            Button("Personal") {
                if viewModel.isEnterpriseMode {
                    viewModel.toggleEnterpriseMode()
                }
            }
            .foregroundColor(viewModel.isEnterpriseMode ? .secondary : .primary)
            .fontWeight(viewModel.isEnterpriseMode ? .medium : .semibold)
            
            Spacer()
            
            Button("Enterprise") {
                if !viewModel.isEnterpriseMode {
                    viewModel.toggleEnterpriseMode()
                }
            }
            .foregroundColor(viewModel.isEnterpriseMode ? .primary : .secondary)
            .fontWeight(viewModel.isEnterpriseMode ? .semibold : .medium)
        }
        .padding(.horizontal, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .fill(viewModel.tenantTheme?.primaryColor ?? Color.blue)
                .frame(width: 100, height: 2)
                .offset(x: viewModel.isEnterpriseMode ? 50 : -50),
            alignment: .bottom
        )
        .animation(.spring(response: 0.3), value: viewModel.isEnterpriseMode)
    }
    
    private var standardFields: some View {
        VStack(spacing: 16) {
            // Email field
            CustomTextField(
                title: "Email",
                text: $viewModel.email,
                placeholder: "Enter your email address",
                keyboardType: .emailAddress,
                autocapitalization: .none,
                icon: "envelope"
            )
            
            // Password field
            CustomSecureField(
                title: "Password",
                text: $viewModel.password,
                placeholder: "Enter your password",
                icon: "lock"
            )
            
            // Remember me toggle
            HStack {
                Toggle("Remember me", isOn: $viewModel.rememberMe)
                    .font(.callout)
                
                Spacer()
                
                Button("Forgot Password?") {
                    viewModel.showForgotPassword = true
                }
                .font(.callout)
                .foregroundColor(viewModel.tenantTheme?.accentColor ?? .blue)
            }
        }
    }
    
    private var enterpriseFields: some View {
        VStack(spacing: 16) {
            // Organization domain field
            VStack(alignment: .leading, spacing: 8) {
                CustomTextField(
                    title: "Organization Domain",
                    text: $viewModel.tenantDomain,
                    placeholder: "company.com",
                    keyboardType: .URL,
                    autocapitalization: .none,
                    icon: "building.2"
                )
                
                if viewModel.isDomainDiscovering {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Discovering organization...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let tenant = viewModel.discoveredTenant {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Found: \(tenant.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Provider selection (if multiple providers available)
            if viewModel.ssoProviders.count > 1 {
                providerSelectionDropdown
            }
            
            // Credentials (if required by selected provider)
            if viewModel.showCredentialFields {
                VStack(spacing: 12) {
                    CustomTextField(
                        title: "Username",
                        text: $viewModel.username,
                        placeholder: "Enter your username",
                        autocapitalization: .none,
                        icon: "person"
                    )
                    
                    CustomSecureField(
                        title: "Password",
                        text: $viewModel.password,
                        placeholder: "Enter your password",
                        icon: "lock"
                    )
                }
            }
        }
    }
    
    private var providerSelectionDropdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authentication Method")
                .font(.headline)
                .foregroundColor(.primary)
            
            Menu {
                ForEach(viewModel.ssoProviders, id: \.id) { provider in
                    Button(provider.displayName) {
                        viewModel.selectedProvider = AuthenticationProvider(rawValue: provider.type.rawValue) ?? .google
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.selectedProvider?.displayName ?? "Select Method")
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
        }
    }
    
    private var biometricLoginButton: some View {
        Button(action: viewModel.signInWithBiometrics) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.biometricType == .faceID ? "faceid" : "touchid")
                    .font(.title2)
                
                Text("Sign in with \(viewModel.biometricType == .faceID ? "Face ID" : "Touch ID")")
                    .fontWeight(.medium)
            }
            .foregroundColor(viewModel.tenantTheme?.accentColor ?? .blue)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.tenantTheme?.accentColor ?? Color.blue, lineWidth: 2)
            )
        }
        .disabled(viewModel.isLoading)
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary sign-in button
            Button(action: primarySignInAction) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    Text(viewModel.isEnterpriseMode ? "Continue with SSO" : "Sign In")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(viewModel.tenantTheme?.primaryColor ?? Color.blue)
                )
            }
            .disabled(!viewModel.isFormValid || viewModel.isLoading)
            .opacity(viewModel.isFormValid ? 1.0 : 0.6)
            
            // Sign up button
            if !viewModel.isEnterpriseMode {
                Button("Don't have an account? Sign Up") {
                    viewModel.showSignUp = true
                }
                .foregroundColor(viewModel.tenantTheme?.accentColor ?? .blue)
            }
        }
    }
    
    private var alternativeSignInOptions: some View {
        VStack(spacing: 16) {
            if !viewModel.isEnterpriseMode {
                // Divider with "or" text
                HStack {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 1)
                    
                    Text("or")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                    
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 1)
                }
                
                // OAuth provider buttons
                VStack(spacing: 12) {
                    ForEach(viewModel.availableProviders, id: \.self) { provider in
                        OAuth2Button(
                            provider: provider,
                            action: { viewModel.signInWithProvider(provider) },
                            isLoading: viewModel.isLoading && viewModel.selectedProvider == provider
                        )
                    }
                }
            }
        }
    }
    
    private var footerLinks: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button("Terms of Service") {
                    viewModel.showTermsOfService = true
                }
                
                Button("Privacy Policy") {
                    viewModel.showPrivacyPolicy = true
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            if viewModel.isEnterpriseMode {
                Button("Switch to Personal Account") {
                    viewModel.toggleEnterpriseMode()
                }
                .font(.caption)
                .foregroundColor(viewModel.tenantTheme?.accentColor ?? .blue)
            }
        }
        .padding(.top, 24)
    }
    
    // MARK: - Sheets and Overlays
    
    private var loadingOverlay: some View {
        Group {
            if viewModel.isAuthenticating {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            
                            Text("Authenticating...")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .padding(32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                        )
                    )
            }
        }
    }
    
    private var providerSelectionSheet: some View {
        NavigationView {
            List(viewModel.availableProviders, id: \.self) { provider in
                Button(action: {
                    viewModel.signInWithProvider(provider)
                    viewModel.showProviderSelection = false
                }) {
                    HStack(spacing: 16) {
                        Image(systemName: provider.iconName)
                            .foregroundColor(provider.brandColor)
                            .frame(width: 24)
                        
                        Text(provider.displayName)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Choose Sign-In Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        viewModel.showProviderSelection = false
                    }
                }
            }
        }
    }
    
    private var tenantSelectionSheet: some View {
        NavigationView {
            List(viewModel.availableTenants, id: \.id) { tenant in
                Button(action: {
                    viewModel.switchTenant(tenant)
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tenant.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let domain = tenant.domain {
                            Text(domain)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Select Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        viewModel.showTenantSelection = false
                    }
                }
            }
        }
    }
    
    private var mfaPromptSheet: some View {
        NavigationView {
            MFAPromptView(
                code: $viewModel.mfaCode,
                method: viewModel.mfaMethod,
                onSubmit: viewModel.validateMFA,
                onCancel: viewModel.dismissMFAPrompt
            )
        }
    }
    
    // MARK: - Actions
    
    private func primarySignInAction() {
        if viewModel.isEnterpriseMode {
            viewModel.signInWithEnterprise()
        } else {
            // For standard mode with email/password
            // This would typically redirect to OAuth or handle email/password login
            viewModel.showProviderSelectionSheet()
        }
    }
}

// MARK: - Supporting Views

struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .disableAutocorrection(true)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }
}

struct CustomSecureField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let icon: String
    @State private var isSecure = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
                
                Button(action: { isSecure.toggle() }) {
                    Image(systemName: isSecure ? "eye" : "eye.slash")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }
}

struct OAuth2Button: View {
    let provider: AuthenticationProvider
    let action: () -> Void
    let isLoading: Bool
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: provider.brandColor))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: provider.iconName)
                        .foregroundColor(provider.brandColor)
                        .font(.title2)
                }
                
                Text("Continue with \(provider.displayName)")
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }
}

struct MFAPromptView: View {
    @Binding var code: String
    let method: MFAMethod
    let onSubmit: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("Two-Factor Authentication")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enter the 6-digit code from your \(method.displayName)")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            TextField("000000", text: $code)
                .font(.system(.title, design: .monospaced))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .onChange(of: code) { newValue in
                    // Limit to 6 digits
                    if newValue.count > 6 {
                        code = String(newValue.prefix(6))
                    }
                    
                    // Auto-submit when 6 digits entered
                    if newValue.count == 6 {
                        onSubmit()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            
            VStack(spacing: 12) {
                Button(action: onSubmit) {
                    Text("Verify")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                        )
                }
                .disabled(code.count != 6)
                
                Button("Cancel", action: onCancel)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .navigationTitle("Verification")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Extensions

extension AuthenticationProvider {
    var iconName: String {
        switch self {
        case .google: return "globe"
        case .apple: return "apple.logo"
        case .facebook: return "person.2"
        case .microsoft: return "building.2"
        case .azureAD: return "building.2.crop.circle"
        case .googleWorkspace: return "briefcase"
        case .okta: return "shield"
        case .customOIDC: return "key"
        case .email: return "envelope"
        case .phone: return "phone"
        }
    }
    
    var brandColor: Color {
        switch self {
        case .google: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .apple: return .black
        case .facebook: return Color(red: 0.26, green: 0.41, blue: 0.70)
        case .microsoft: return Color(red: 0.00, green: 0.46, blue: 0.74)
        case .azureAD: return Color(red: 0.00, green: 0.46, blue: 0.74)
        case .googleWorkspace: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .okta: return Color(red: 0.00, green: 0.42, blue: 0.87)
        case .customOIDC: return .blue
        case .email: return .green
        case .phone: return .orange
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0
        
        let length = hexSanitized.count
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Preview

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LoginView(
                authenticationService: MockAuthenticationService(),
                biometricService: MockBiometricAuthService(),
                tenantConfigurationService: MockTenantConfigurationService()
            )
            .preferredColorScheme(.light)
            
            LoginView(
                authenticationService: MockAuthenticationService(),
                biometricService: MockBiometricAuthService(),
                tenantConfigurationService: MockTenantConfigurationService()
            )
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Mock Services for Preview

class MockAuthenticationService: AuthenticationServiceProtocol {
    var isAuthenticated: Bool = false
    var currentUser: AuthenticatedUser? = nil
    var authenticationStateChanged: AsyncStream<AuthenticationState> {
        AsyncStream { _ in }
    }
    
    func signInWithGoogle() async throws -> AuthenticationResult { throw AuthenticationError.networkError("Mock") }
    func signInWithApple() async throws -> AuthenticationResult { throw AuthenticationError.networkError("Mock") }
    func signInWithFacebook() async throws -> AuthenticationResult { throw AuthenticationError.networkError("Mock") }
    func signInWithMicrosoft() async throws -> AuthenticationResult { throw AuthenticationError.networkError("Mock") }
    func signInWithAzureAD(tenantId: String) async throws -> AuthenticationResult { throw AuthenticationError.networkError("Mock") }
    func signInWithGoogleWorkspace(domain: String) async throws -> AuthenticationResult { throw AuthenticationError.networkError("Mock") }
    func signInWithOkta(orgUrl: String) async throws -> AuthenticationResult { throw AuthenticationError.networkError("Mock") }
    func signInWithCustomOIDC(configuration: OIDCConfiguration) async throws -> AuthenticationResult { throw AuthenticationError.networkError("Mock") }
    func validateToken(_ token: String) async throws -> TokenValidationResult { throw AuthenticationError.networkError("Mock") }
    func refreshToken(_ refreshToken: String) async throws -> AuthenticationResult { throw AuthenticationError.networkError("Mock") }
    func revokeToken(_ token: String) async throws { }
    func getStoredToken() async -> StoredToken? { return nil }
    func clearStoredTokens() async throws { }
    func switchTenant(_ tenantId: String) async throws -> TenantSwitchResult { throw AuthenticationError.networkError("Mock") }
    func getCurrentTenant() async -> TenantInfo? { return nil }
    func getUserTenants() async throws -> [TenantInfo] { return [] }
    func getCurrentSession() async -> AuthenticationSession? { return nil }
    func validateSession(_ sessionId: String) async throws -> SessionValidationResult { throw AuthenticationError.networkError("Mock") }
    func terminateSession(_ sessionId: String) async throws { }
    func terminateAllSessions() async throws { }
    func enableMFA() async throws -> MFASetupResult { throw AuthenticationError.networkError("Mock") }
    func disableMFA() async throws { }
    func validateMFA(code: String, method: MFAMethod) async throws -> Bool { return false }
    func generateBackupCodes() async throws -> [String] { return [] }
    func validateTenantAccess(_ tenantId: String, userId: String) async throws -> Bool { return false }
    func auditAuthenticationAttempt(_ attempt: AuthenticationAttempt) async { }
}

class MockBiometricAuthService: BiometricAuthServiceProtocol {
    func checkBiometricAvailability() async -> BiometricAvailability {
        return BiometricAvailability(
            isAvailable: true,
            biometryType: .faceID,
            requiresEnrollment: false,
            hasSystemPasscode: true,
            errorMessage: nil
        )
    }
    
    func authenticateUser(reason: String, fallbackTitle: String?) async throws -> Bool {
        return true
    }
    
    func enableBiometricAuthentication() async throws -> Bool {
        return true
    }
    
    func disableBiometricAuthentication() async throws {
    }
    
    func isBiometricEnabled() async -> Bool {
        return true
    }
}

class MockTenantConfigurationService: TenantConfigurationServiceProtocol {
    var currentTenantPublisher: AnyPublisher<TenantInfo?, Never> {
        Just(nil).eraseToAnyPublisher()
    }
    
    func getCurrentTenant() async -> TenantInfo? { return nil }
    func getTenantConfiguration(tenantId: String) async throws -> TenantConfigurationProtocol { throw AuthenticationError.networkError("Mock") }
    func getTenantTheme(tenantId: String) async throws -> TenantTheme { throw AuthenticationError.networkError("Mock") }
    func getBrandingConfiguration(tenantId: String) async throws -> BrandingConfiguration { throw AuthenticationError.networkError("Mock") }
    func getCustomSignUpFields(tenantId: String) async throws -> [CustomSignUpField] { return [] }
}