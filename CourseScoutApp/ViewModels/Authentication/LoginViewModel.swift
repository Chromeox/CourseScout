import Foundation
import SwiftUI
import Combine
import LocalAuthentication
import os.log

// MARK: - Login View Model

@MainActor
final class LoginViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var showBiometricPrompt: Bool = false
    @Published var rememberMe: Bool = false
    @Published var selectedProvider: AuthenticationProvider = .google
    @Published var showProviderSelection: Bool = false
    @Published var isEnterpriseMode: Bool = false
    @Published var tenantDomain: String = ""
    @Published var showTenantSelection: Bool = false
    @Published var availableTenants: [TenantInfo] = []
    @Published var isAuthenticating: Bool = false
    @Published var showMFAPrompt: Bool = false
    @Published var mfaCode: String = ""
    @Published var mfaMethod: MFAMethod = .totp
    @Published var mfaChallengeId: String = ""
    
    // MARK: - Authentication State
    
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: AuthenticatedUser?
    @Published var currentTenant: TenantInfo?
    
    // MARK: - UI State
    
    @Published var showSignUp: Bool = false
    @Published var showForgotPassword: Bool = false
    @Published var canUseBiometrics: Bool = false
    @Published var biometricType: LABiometryType = .none
    @Published var showPrivacyPolicy: Bool = false
    @Published var showTermsOfService: Bool = false
    
    // MARK: - White Label Theming
    
    @Published var tenantTheme: TenantTheme?
    @Published var brandingConfiguration: BrandingConfiguration?
    
    // MARK: - Dependencies
    
    private let authenticationService: AuthenticationServiceProtocol
    private let biometricService: BiometricAuthServiceProtocol
    private let tenantConfigurationService: TenantConfigurationServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderApp", category: "LoginViewModel")
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var authStateTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    
    var availableProviders: [AuthenticationProvider] {
        if isEnterpriseMode {
            return [.azureAD, .googleWorkspace, .okta, .customOIDC]
        } else {
            return [.google, .apple, .facebook, .microsoft]
        }
    }
    
    var isLoginFormValid: Bool {
        if isEnterpriseMode {
            return !tenantDomain.isEmpty
        } else {
            return !email.isEmpty && !password.isEmpty
        }
    }
    
    var canShowBiometricLogin: Bool {
        return canUseBiometrics && !isEnterpriseMode && authenticationService.isAuthenticated
    }
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        biometricService: BiometricAuthServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol
    ) {
        self.authenticationService = authenticationService
        self.biometricService = biometricService
        self.tenantConfigurationService = tenantConfigurationService
        
        setupObservers()
        checkBiometricAvailability()
        loadStoredCredentials()
        logger.info("LoginViewModel initialized")
    }
    
    deinit {
        authStateTask?.cancel()
    }
    
    // MARK: - Setup Methods
    
    private func setupObservers() {
        // Monitor authentication state changes
        authStateTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await state in authenticationService.authenticationStateChanged {
                await self.handleAuthenticationStateChange(state)
            }
        }
        
        // Monitor tenant configuration changes
        tenantConfigurationService.currentTenantPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tenant in
                self?.currentTenant = tenant
                self?.loadTenantBranding(tenant)
            }
            .store(in: &cancellables)
    }
    
    private func checkBiometricAvailability() {
        Task {
            let availability = await biometricService.checkBiometricAvailability()
            await MainActor.run {
                self.canUseBiometrics = availability.isAvailable
                self.biometricType = availability.biometryType
            }
        }
    }
    
    private func loadStoredCredentials() {
        Task {
            // Check if user has stored authentication data
            if let storedToken = await authenticationService.getStoredToken() {
                // Validate the stored token
                do {
                    let validationResult = try await authenticationService.validateToken(storedToken.accessToken)
                    if validationResult.isValid {
                        self.isAuthenticated = true
                        self.currentUser = validationResult.user
                        self.currentTenant = validationResult.tenant
                        logger.info("Restored authentication session from stored token")
                    }
                } catch {
                    logger.warning("Failed to validate stored token: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func loadTenantBranding(_ tenant: TenantInfo?) {
        guard let tenant = tenant else {
            self.tenantTheme = nil
            self.brandingConfiguration = nil
            return
        }
        
        Task {
            do {
                let theme = try await tenantConfigurationService.getTenantTheme(tenantId: tenant.id)
                let branding = try await tenantConfigurationService.getBrandingConfiguration(tenantId: tenant.id)
                
                await MainActor.run {
                    self.tenantTheme = theme
                    self.brandingConfiguration = branding
                }
            } catch {
                logger.error("Failed to load tenant branding: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Authentication State Handling
    
    private func handleAuthenticationStateChange(_ state: AuthenticationState) async {
        await MainActor.run {
            self.authenticationState = state
            
            switch state {
            case .unauthenticated:
                self.isAuthenticated = false
                self.currentUser = nil
                self.currentTenant = nil
                self.isLoading = false
                self.isAuthenticating = false
                
            case .authenticating:
                self.isAuthenticating = true
                self.isLoading = true
                self.showError = false
                
            case .authenticated(let user, let tenant):
                self.isAuthenticated = true
                self.currentUser = user
                self.currentTenant = tenant
                self.isLoading = false
                self.isAuthenticating = false
                self.showError = false
                
            case .expired:
                self.isAuthenticated = false
                self.currentUser = nil
                self.showError = true
                self.errorMessage = "Your session has expired. Please sign in again."
                self.isLoading = false
                self.isAuthenticating = false
                
            case .error(let error):
                self.isAuthenticated = false
                self.isLoading = false
                self.isAuthenticating = false
                self.showError = true
                self.errorMessage = error.localizedDescription
                
            case .tenantSwitching:
                self.isLoading = true
                
            case .mfaRequired(let challengeId):
                self.showMFAPrompt = true
                self.mfaChallengeId = challengeId
                self.isLoading = false
            }
        }
    }
    
    // MARK: - OAuth Authentication Methods
    
    func signInWithProvider(_ provider: AuthenticationProvider) {
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
                self.selectedProvider = provider
            }
            
            do {
                let result: AuthenticationResult
                
                switch provider {
                case .google:
                    result = try await authenticationService.signInWithGoogle()
                case .apple:
                    result = try await authenticationService.signInWithApple()
                case .facebook:
                    result = try await authenticationService.signInWithFacebook()
                case .microsoft:
                    result = try await authenticationService.signInWithMicrosoft()
                default:
                    throw AuthenticationError.unsupportedProvider
                }
                
                await handleSuccessfulAuthentication(result)
                
            } catch {
                await handleAuthenticationError(error)
            }
        }
    }
    
    // MARK: - Enterprise Authentication Methods
    
    func signInWithEnterprise() {
        guard !tenantDomain.isEmpty else {
            showError = true
            errorMessage = "Please enter your organization domain"
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                let result: AuthenticationResult
                
                switch selectedProvider {
                case .azureAD:
                    result = try await authenticationService.signInWithAzureAD(tenantId: tenantDomain)
                case .googleWorkspace:
                    result = try await authenticationService.signInWithGoogleWorkspace(domain: tenantDomain)
                case .okta:
                    result = try await authenticationService.signInWithOkta(orgUrl: tenantDomain)
                case .customOIDC:
                    // This would require additional configuration
                    throw AuthenticationError.configurationError("Custom OIDC not configured")
                default:
                    throw AuthenticationError.unsupportedProvider
                }
                
                await handleSuccessfulAuthentication(result)
                
            } catch {
                await handleAuthenticationError(error)
            }
        }
    }
    
    // MARK: - Biometric Authentication
    
    func signInWithBiometrics() {
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                let success = try await biometricService.authenticateUser(
                    reason: "Use biometrics to sign in to GolfFinder",
                    fallbackTitle: "Use Passcode"
                )
                
                if success {
                    // Retrieve stored token and validate
                    if let storedToken = await authenticationService.getStoredToken() {
                        let validationResult = try await authenticationService.validateToken(storedToken.accessToken)
                        
                        if validationResult.isValid {
                            await MainActor.run {
                                self.isAuthenticated = true
                                self.currentUser = validationResult.user
                                self.currentTenant = validationResult.tenant
                                self.isLoading = false
                            }
                            
                            logger.info("Biometric authentication successful")
                        } else {
                            throw AuthenticationError.tokenExpired
                        }
                    } else {
                        throw AuthenticationError.invalidCredentials
                    }
                } else {
                    throw AuthenticationError.biometricFailed
                }
                
            } catch {
                await handleAuthenticationError(error)
            }
        }
    }
    
    // MARK: - MFA Handling
    
    func validateMFA() {
        guard !mfaCode.isEmpty else {
            showError = true
            errorMessage = "Please enter the verification code"
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                let isValid = try await authenticationService.validateMFA(
                    code: mfaCode,
                    method: mfaMethod
                )
                
                if isValid {
                    await MainActor.run {
                        self.showMFAPrompt = false
                        self.mfaCode = ""
                        self.isLoading = false
                    }
                    logger.info("MFA validation successful")
                } else {
                    await MainActor.run {
                        self.showError = true
                        self.errorMessage = "Invalid verification code. Please try again."
                        self.isLoading = false
                    }
                }
                
            } catch {
                await handleAuthenticationError(error)
            }
        }
    }
    
    // MARK: - Tenant Management
    
    func switchTenant(_ tenant: TenantInfo) {
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                let result = try await authenticationService.switchTenant(tenant.id)
                
                await MainActor.run {
                    self.currentTenant = result.newTenant
                    self.currentUser = result.user
                    self.isLoading = false
                    self.showTenantSelection = false
                }
                
                logger.info("Switched to tenant: \(tenant.name)")
                
            } catch {
                await handleAuthenticationError(error)
            }
        }
    }
    
    func loadUserTenants() {
        Task {
            do {
                let tenants = try await authenticationService.getUserTenants()
                
                await MainActor.run {
                    self.availableTenants = tenants
                    self.showTenantSelection = !tenants.isEmpty
                }
                
            } catch {
                logger.error("Failed to load user tenants: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                try await authenticationService.clearStoredTokens()
                
                await MainActor.run {
                    self.isAuthenticated = false
                    self.currentUser = nil
                    self.currentTenant = nil
                    self.isLoading = false
                    self.email = ""
                    self.password = ""
                    self.tenantDomain = ""
                }
                
                logger.info("User signed out successfully")
                
            } catch {
                logger.error("Sign out failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - UI Actions
    
    func toggleEnterpriseMode() {
        isEnterpriseMode.toggle()
        showError = false
        email = ""
        password = ""
        tenantDomain = ""
    }
    
    func showProviderSelectionSheet() {
        showProviderSelection = true
    }
    
    func dismissError() {
        showError = false
        errorMessage = ""
    }
    
    func dismissMFAPrompt() {
        showMFAPrompt = false
        mfaCode = ""
        mfaChallengeId = ""
    }
    
    // MARK: - Helper Methods
    
    private func handleSuccessfulAuthentication(_ result: AuthenticationResult) async {
        await MainActor.run {
            self.isAuthenticated = true
            self.currentUser = result.user
            self.currentTenant = result.tenant
            self.isLoading = false
            self.showError = false
            
            // Clear form data
            self.email = ""
            self.password = ""
            self.tenantDomain = ""
        }
        
        logger.info("Authentication successful for user: \(result.user.id)")
    }
    
    private func handleAuthenticationError(_ error: Error) async {
        await MainActor.run {
            self.isLoading = false
            self.isAuthenticating = false
            self.showError = true
            
            if let authError = error as? AuthenticationError {
                self.errorMessage = authError.localizedDescription
            } else {
                self.errorMessage = "An unexpected error occurred. Please try again."
            }
        }
        
        logger.error("Authentication failed: \(error.localizedDescription)")
    }
}

// MARK: - Supporting Types

struct TenantTheme {
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color
    let backgroundColor: Color
    let textColor: Color
    let logoURL: URL?
    let fontFamily: String?
}

struct BrandingConfiguration {
    let appName: String
    let logoURL: URL?
    let primaryColor: String
    let secondaryColor: String
    let termsOfServiceURL: URL?
    let privacyPolicyURL: URL?
    let supportEmail: String?
    let customDomain: String?
}

// MARK: - Preview Support

extension LoginViewModel {
    static var preview: LoginViewModel {
        let mockAuth = ServiceContainer.shared.resolve(AuthenticationServiceProtocol.self)!
        let mockBiometric = ServiceContainer.shared.resolve(BiometricAuthServiceProtocol.self)!
        let mockTenant = ServiceContainer.shared.resolve(TenantConfigurationServiceProtocol.self)!
        
        return LoginViewModel(
            authenticationService: mockAuth,
            biometricService: mockBiometric,
            tenantConfigurationService: mockTenant
        )
    }
}