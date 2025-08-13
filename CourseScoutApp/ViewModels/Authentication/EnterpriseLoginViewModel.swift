import Foundation
import SwiftUI
import Combine
import LocalAuthentication
import os.log

// MARK: - Enterprise Login View Model

@MainActor
final class EnterpriseLoginViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var organizationDomain: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var showSuccess: Bool = false
    @Published var successMessage: String = ""
    
    // MARK: - Enterprise Configuration
    
    @Published var discoveredTenant: TenantInfo?
    @Published var tenantConfiguration: EnterpriseTenantConfiguration?
    @Published var ssoProviders: [EnterpriseProvider] = []
    @Published var selectedProvider: EnterpriseProvider?
    @Published var showProviderSelection: Bool = false
    @Published var isDomainDiscovering: Bool = false
    
    // MARK: - SSO Flow
    
    @Published var ssoRedirectURL: URL?
    @Published var showSSOWebView: Bool = false
    @Published var ssoState: String = ""
    @Published var isProcessingSSOCallback: Bool = false
    
    // MARK: - Multi-Factor Authentication
    
    @Published var requiresMFA: Bool = false
    @Published var showMFAPrompt: Bool = false
    @Published var mfaMethod: MFAMethod = .totp
    @Published var mfaCode: String = ""
    @Published var mfaChallengeId: String = ""
    @Published var availableMFAMethods: [MFAMethod] = []
    
    // MARK: - Role Selection
    
    @Published var availableRoles: [TenantRole] = []
    @Published var selectedRole: TenantRole?
    @Published var showRoleSelection: Bool = false
    @Published var requiresRoleSelection: Bool = false
    
    // MARK: - Device Registration
    
    @Published var isDeviceRegistered: Bool = false
    @Published var showDeviceRegistration: Bool = false
    @Published var deviceTrustLevel: DeviceTrustLevel = .unknown
    @Published var requiresDeviceApproval: Bool = false
    
    // MARK: - Compliance & Security
    
    @Published var complianceCheck: ComplianceCheckResult?
    @Published var showComplianceWarning: Bool = false
    @Published var securityPolicyViolations: [SecurityPolicyViolation] = []
    @Published var requiresSecurityUpdate: Bool = false
    
    // MARK: - Tenant Branding
    
    @Published var tenantBranding: TenantBranding?
    @Published var customLoginFlow: CustomLoginFlow?
    @Published var brandedAssets: BrandedAssets?
    
    // MARK: - Form Validation
    
    @Published var domainError: String = ""
    @Published var usernameError: String = ""
    @Published var passwordError: String = ""
    @Published var mfaError: String = ""
    
    // MARK: - Dependencies
    
    private let authenticationService: AuthenticationServiceProtocol
    private let enterpriseAuthService: EnterpriseAuthServiceProtocol
    private let tenantConfigurationService: TenantConfigurationServiceProtocol
    private let securityService: SecurityServiceProtocol
    private let complianceService: ComplianceServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderApp", category: "EnterpriseLoginViewModel")
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var domainDiscoveryTask: Task<Void, Never>?
    private var ssoTimer: Timer?
    
    // MARK: - Computed Properties
    
    var isFormValid: Bool {
        if selectedProvider?.requiresCredentials == true {
            return !username.isEmpty && !password.isEmpty
        } else {
            return !organizationDomain.isEmpty
        }
    }
    
    var canProceedWithSSO: Bool {
        return discoveredTenant != nil && selectedProvider != nil
    }
    
    var loginButtonTitle: String {
        if selectedProvider?.type == .sso {
            return "Continue with \(selectedProvider?.displayName ?? "SSO")"
        } else {
            return "Sign In"
        }
    }
    
    var showCredentialFields: Bool {
        return selectedProvider?.requiresCredentials == true
    }
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        enterpriseAuthService: EnterpriseAuthServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol,
        securityService: SecurityServiceProtocol,
        complianceService: ComplianceServiceProtocol
    ) {
        self.authenticationService = authenticationService
        self.enterpriseAuthService = enterpriseAuthService
        self.tenantConfigurationService = tenantConfigurationService
        self.securityService = securityService
        self.complianceService = complianceService
        
        setupObservers()
        logger.info("EnterpriseLoginViewModel initialized")
    }
    
    deinit {
        domainDiscoveryTask?.cancel()
        ssoTimer?.invalidate()
    }
    
    // MARK: - Setup Methods
    
    private func setupObservers() {
        // Real-time domain discovery
        $organizationDomain
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] domain in
                if !domain.isEmpty {
                    self?.discoverTenantFromDomain(domain)
                }
            }
            .store(in: &cancellables)
        
        // Form validation
        $username
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] username in
                self?.validateUsername(username)
            }
            .store(in: &cancellables)
        
        $password
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] password in
                self?.validatePassword(password)
            }
            .store(in: &cancellables)
        
        $mfaCode
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] code in
                self?.validateMFACode(code)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Domain Discovery
    
    private func discoverTenantFromDomain(_ domain: String) {
        domainDiscoveryTask?.cancel()
        
        domainDiscoveryTask = Task {
            await MainActor.run {
                self.isDomainDiscovering = true
                self.domainError = ""
            }
            
            do {
                let tenant = try await enterpriseAuthService.discoverTenant(domain: domain)
                let configuration = try await enterpriseAuthService.getTenantConfiguration(tenantId: tenant.id)
                let providers = try await enterpriseAuthService.getAvailableProviders(tenantId: tenant.id)
                let branding = try await tenantConfigurationService.getTenantBranding(tenantId: tenant.id)
                
                await MainActor.run {
                    self.discoveredTenant = tenant
                    self.tenantConfiguration = configuration
                    self.ssoProviders = providers
                    self.tenantBranding = branding
                    self.isDomainDiscovering = false
                    
                    // Auto-select provider if only one is available
                    if providers.count == 1 {
                        self.selectedProvider = providers.first
                    } else if providers.count > 1 {
                        self.showProviderSelection = true
                    }
                    
                    // Load custom login flow if available
                    self.loadCustomLoginFlow(tenant.id)
                }
                
                logger.info("Discovered tenant: \(tenant.name) for domain: \(domain)")
                
            } catch {
                await MainActor.run {
                    self.isDomainDiscovering = false
                    self.discoveredTenant = nil
                    self.tenantConfiguration = nil
                    self.ssoProviders = []
                    self.domainError = self.mapDiscoveryError(error)
                }
                
                logger.warning("Failed to discover tenant for domain \(domain): \(error.localizedDescription)")
            }
        }
    }
    
    private func loadCustomLoginFlow(_ tenantId: String) {
        Task {
            do {
                let customFlow = try await tenantConfigurationService.getCustomLoginFlow(tenantId: tenantId)
                let assets = try await tenantConfigurationService.getBrandedAssets(tenantId: tenantId)
                
                await MainActor.run {
                    self.customLoginFlow = customFlow
                    self.brandedAssets = assets
                }
                
            } catch {
                logger.error("Failed to load custom login flow: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Authentication Methods
    
    func signInWithSSO() {
        guard let provider = selectedProvider,
              let tenant = discoveredTenant else {
            showError = true
            errorMessage = "Please select an authentication provider"
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                // Perform security and compliance checks
                try await performPreAuthenticationChecks()
                
                let result: AuthenticationResult
                
                switch provider.type {
                case .azureAD:
                    result = try await authenticationService.signInWithAzureAD(tenantId: tenant.domain ?? tenant.id)
                case .googleWorkspace:
                    result = try await authenticationService.signInWithGoogleWorkspace(domain: tenant.domain ?? organizationDomain)
                case .okta:
                    result = try await authenticationService.signInWithOkta(orgUrl: provider.endpoint ?? "")
                case .saml:
                    result = try await enterpriseAuthService.signInWithSAML(
                        tenantId: tenant.id,
                        providerConfig: provider.configuration
                    )
                case .oidc:
                    result = try await authenticationService.signInWithCustomOIDC(
                        configuration: provider.oidcConfiguration
                    )
                case .sso:
                    // Handle generic SSO flow
                    result = try await handleGenericSSO(provider: provider, tenant: tenant)
                }
                
                await handleSuccessfulAuthentication(result)
                
            } catch {
                await handleAuthenticationError(error)
            }
        }
    }
    
    func signInWithCredentials() {
        guard isFormValid else {
            showError = true
            errorMessage = "Please fill in all required fields"
            return
        }
        
        guard let tenant = discoveredTenant else {
            showError = true
            errorMessage = "Organization not found"
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                // Perform security and compliance checks
                try await performPreAuthenticationChecks()
                
                let result = try await enterpriseAuthService.signInWithCredentials(
                    tenantId: tenant.id,
                    username: username,
                    password: password
                )
                
                await handleSuccessfulAuthentication(result)
                
            } catch {
                await handleAuthenticationError(error)
            }
        }
    }
    
    // MARK: - SSO Flow Management
    
    private func handleGenericSSO(provider: EnterpriseProvider, tenant: TenantInfo) async throws -> AuthenticationResult {
        // Generate SSO state for security
        ssoState = generateSecureState()
        
        // Build SSO redirect URL
        let ssoURL = try await enterpriseAuthService.buildSSORedirectURL(
            tenantId: tenant.id,
            providerId: provider.id,
            state: ssoState,
            redirectURI: "golffinder://auth/sso/callback"
        )
        
        await MainActor.run {
            self.ssoRedirectURL = ssoURL
            self.showSSOWebView = true
        }
        
        // Start SSO timeout timer
        startSSOTimer()
        
        // Return placeholder - actual result will come from SSO callback
        throw AuthenticationError.userCancelled
    }
    
    func handleSSOCallback(url: URL) {
        Task {
            await MainActor.run {
                self.isProcessingSSOCallback = true
                self.showSSOWebView = false
            }
            
            do {
                ssoTimer?.invalidate()
                
                let result = try await enterpriseAuthService.processSSOCallback(
                    callbackURL: url,
                    expectedState: ssoState
                )
                
                await handleSuccessfulAuthentication(result)
                
            } catch {
                await handleAuthenticationError(error)
            }
        }
    }
    
    private func startSSOTimer() {
        ssoTimer?.invalidate()
        ssoTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.cancelSSO()
            }
        }
    }
    
    func cancelSSO() {
        ssoTimer?.invalidate()
        showSSOWebView = false
        isProcessingSSOCallback = false
        ssoRedirectURL = nil
        ssoState = ""
        
        showError = true
        errorMessage = "SSO authentication was cancelled or timed out"
    }
    
    // MARK: - Multi-Factor Authentication
    
    func validateMFA() {
        guard !mfaCode.isEmpty else {
            mfaError = "Please enter the verification code"
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.mfaError = ""
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
                        self.showSuccess = true
                        self.successMessage = "Authentication completed successfully"
                    }
                } else {
                    await MainActor.run {
                        self.mfaError = "Invalid verification code"
                        self.isLoading = false
                    }
                }
                
            } catch {
                await MainActor.run {
                    self.mfaError = "Verification failed: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    func requestMFAMethod(_ method: MFAMethod) {
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                try await enterpriseAuthService.requestMFAChallenge(
                    challengeId: mfaChallengeId,
                    method: method
                )
                
                await MainActor.run {
                    self.mfaMethod = method
                    self.isLoading = false
                    self.showSuccess = true
                    self.successMessage = "Verification code sent via \(method.displayName)"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.mfaError = "Failed to send verification code"
                }
            }
        }
    }
    
    // MARK: - Role Selection
    
    func selectRole(_ role: TenantRole) {
        Task {
            await MainActor.run {
                self.selectedRole = role
                self.isLoading = true
            }
            
            do {
                try await enterpriseAuthService.assignUserRole(
                    userId: authenticationService.currentUser?.id ?? "",
                    tenantId: discoveredTenant?.id ?? "",
                    role: role
                )
                
                await MainActor.run {
                    self.showRoleSelection = false
                    self.isLoading = false
                    self.showSuccess = true
                    self.successMessage = "Role assigned successfully"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to assign role: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Security & Compliance
    
    private func performPreAuthenticationChecks() async throws {
        // Check device compliance
        let complianceResult = await complianceService.checkDeviceCompliance()
        
        await MainActor.run {
            self.complianceCheck = complianceResult
        }
        
        if !complianceResult.isCompliant {
            await MainActor.run {
                self.showComplianceWarning = true
                self.securityPolicyViolations = complianceResult.violations
            }
            
            if complianceResult.blockAuthentication {
                throw AuthenticationError.complianceViolation("Device does not meet security requirements")
            }
        }
        
        // Check device trust level
        let trustLevel = await securityService.evaluateDeviceTrust()
        
        await MainActor.run {
            self.deviceTrustLevel = trustLevel
        }
        
        if trustLevel == .untrusted {
            await MainActor.run {
                self.requiresDeviceApproval = true
            }
            
            // In a stricter environment, you might block here
            logger.warning("Untrusted device attempting authentication")
        }
        
        // Check for required security updates
        let requiresUpdate = await securityService.checkForRequiredSecurityUpdates()
        
        if requiresUpdate {
            await MainActor.run {
                self.requiresSecurityUpdate = true
                self.showError = true
                self.errorMessage = "Please update your app to the latest version for security"
            }
            
            throw AuthenticationError.configurationError("Security update required")
        }
    }
    
    // MARK: - Result Handling
    
    private func handleSuccessfulAuthentication(_ result: AuthenticationResult) async {
        // Check if additional steps are required
        if let tenant = result.tenant,
           let config = tenantConfiguration {
            
            // Check if role selection is required
            if config.requiresRoleSelection && result.user.tenantMemberships.isEmpty {
                await MainActor.run {
                    self.availableRoles = config.availableRoles
                    self.showRoleSelection = true
                    self.requiresRoleSelection = true
                    self.isLoading = false
                }
                return
            }
            
            // Check if device registration is required
            if config.requiresDeviceRegistration && !isDeviceRegistered {
                await MainActor.run {
                    self.showDeviceRegistration = true
                    self.isLoading = false
                }
                return
            }
        }
        
        // Authentication completed successfully
        await MainActor.run {
            self.isLoading = false
            self.showSuccess = true
            self.successMessage = "Welcome to \(result.tenant?.name ?? "your organization")!"
        }
        
        logger.info("Enterprise authentication successful for tenant: \(result.tenant?.name ?? "unknown")")
    }
    
    private func handleAuthenticationError(_ error: Error) async {
        await MainActor.run {
            self.isLoading = false
            self.isProcessingSSOCallback = false
            self.showError = true
            
            if let authError = error as? AuthenticationError {
                switch authError {
                case .mfaRequired:
                    self.requiresMFA = true
                    self.showMFAPrompt = true
                    self.errorMessage = ""
                    return
                case .tenantNotFound:
                    self.errorMessage = "Organization not found. Please check your domain."
                case .tenantInactive:
                    self.errorMessage = "Your organization account is inactive. Please contact your administrator."
                case .insufficientPermissions:
                    self.errorMessage = "You don't have permission to access this organization."
                case .deviceNotTrusted:
                    self.errorMessage = "This device is not authorized. Please contact your IT administrator."
                case .geofenceViolation:
                    self.errorMessage = "Authentication from this location is not allowed."
                default:
                    self.errorMessage = authError.localizedDescription
                }
            } else {
                self.errorMessage = "Authentication failed. Please try again."
            }
        }
        
        logger.error("Enterprise authentication failed: \(error.localizedDescription)")
    }
    
    // MARK: - Validation Methods
    
    private func validateUsername(_ username: String) {
        if username.isEmpty {
            usernameError = ""
        } else if username.count < 3 {
            usernameError = "Username must be at least 3 characters"
        } else {
            usernameError = ""
        }
    }
    
    private func validatePassword(_ password: String) {
        if password.isEmpty {
            passwordError = ""
        } else if password.count < 8 {
            passwordError = "Password must be at least 8 characters"
        } else {
            passwordError = ""
        }
    }
    
    private func validateMFACode(_ code: String) {
        if code.isEmpty {
            mfaError = ""
        } else if code.count != 6 || !code.allSatisfy(\.isNumber) {
            mfaError = "Please enter a 6-digit code"
        } else {
            mfaError = ""
        }
    }
    
    // MARK: - Helper Methods
    
    private func mapDiscoveryError(_ error: Error) -> String {
        if let authError = error as? AuthenticationError {
            switch authError {
            case .tenantNotFound:
                return "Organization not found for this domain"
            case .networkError:
                return "Network error. Please check your connection."
            default:
                return "Unable to find organization configuration"
            }
        }
        return "Domain lookup failed"
    }
    
    private func generateSecureState() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
    
    // MARK: - UI Actions
    
    func selectProvider(_ provider: EnterpriseProvider) {
        selectedProvider = provider
        showProviderSelection = false
        
        // Load provider-specific configuration
        loadProviderConfiguration(provider)
    }
    
    private func loadProviderConfiguration(_ provider: EnterpriseProvider) {
        Task {
            do {
                let config = try await enterpriseAuthService.getProviderConfiguration(
                    tenantId: discoveredTenant?.id ?? "",
                    providerId: provider.id
                )
                
                await MainActor.run {
                    // Update UI based on provider configuration
                    if provider.requiresCredentials {
                        // Show username/password fields
                    }
                    
                    if provider.supportsMFA {
                        self.availableMFAMethods = config.supportedMFAMethods
                    }
                }
                
            } catch {
                logger.error("Failed to load provider configuration: \(error.localizedDescription)")
            }
        }
    }
    
    func dismissError() {
        showError = false
        errorMessage = ""
    }
    
    func dismissSuccess() {
        showSuccess = false
        successMessage = ""
    }
    
    func dismissComplianceWarning() {
        showComplianceWarning = false
    }
    
    func clearForm() {
        organizationDomain = ""
        username = ""
        password = ""
        mfaCode = ""
        clearErrors()
    }
    
    func clearErrors() {
        domainError = ""
        usernameError = ""
        passwordError = ""
        mfaError = ""
    }
}

// MARK: - Supporting Types

struct EnterpriseTenantConfiguration {
    let requiresCredentials: Bool
    let requiresMFA: Bool
    let requiresRoleSelection: Bool
    let requiresDeviceRegistration: Bool
    let allowedMFAMethods: [MFAMethod]
    let availableRoles: [TenantRole]
    let sessionTimeout: TimeInterval
    let passwordPolicy: PasswordPolicy
    let securityPolicy: TenantSecurityPolicy
}

struct EnterpriseProvider {
    let id: String
    let type: ProviderType
    let displayName: String
    let iconURL: URL?
    let endpoint: String?
    let requiresCredentials: Bool
    let supportsMFA: Bool
    let configuration: [String: Any]
    let oidcConfiguration: OIDCConfiguration
    
    enum ProviderType {
        case azureAD
        case googleWorkspace
        case okta
        case saml
        case oidc
        case sso
    }
}

struct TenantBranding {
    let logoURL: URL?
    let primaryColor: String
    let secondaryColor: String
    let backgroundColor: String
    let customCSS: String?
    let welcomeMessage: String?
    let loginInstructions: String?
}

struct CustomLoginFlow {
    let steps: [LoginStep]
    let customFields: [CustomField]
    let termsOfServiceURL: URL?
    let privacyPolicyURL: URL?
    let supportContactInfo: String?
}

struct BrandedAssets {
    let logoImage: Data?
    let backgroundImage: Data?
    let iconImage: Data?
    let customFonts: [String: Data]
}

struct ComplianceCheckResult {
    let isCompliant: Bool
    let violations: [SecurityPolicyViolation]
    let blockAuthentication: Bool
    let warningsOnly: Bool
    let checkTimestamp: Date
}

struct SecurityPolicyViolation {
    let type: ViolationType
    let severity: Severity
    let description: String
    let remediation: String?
    
    enum ViolationType {
        case outdatedOS
        case jailbrokenDevice
        case malwareDetected
        case networkSecurityIssue
        case appIntegrityViolation
        case debuggerDetected
    }
    
    enum Severity {
        case low
        case medium
        case high
        case critical
    }
}

enum DeviceTrustLevel {
    case unknown
    case untrusted
    case basic
    case trusted
    case highlyTrusted
    
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .untrusted: return "Untrusted"
        case .basic: return "Basic Trust"
        case .trusted: return "Trusted"
        case .highlyTrusted: return "Highly Trusted"
        }
    }
    
    var color: Color {
        switch self {
        case .unknown: return .gray
        case .untrusted: return .red
        case .basic: return .orange
        case .trusted: return .blue
        case .highlyTrusted: return .green
        }
    }
}

struct PasswordPolicy {
    let minimumLength: Int
    let requiresUppercase: Bool
    let requiresLowercase: Bool
    let requiresNumbers: Bool
    let requiresSpecialCharacters: Bool
    let disallowedPasswords: [String]
    let historyCount: Int
    let expirationDays: Int?
}

enum LoginStep {
    case domainEntry
    case providerSelection
    case credentialEntry
    case mfaVerification
    case roleSelection
    case deviceRegistration
    case complianceCheck
    case completion
}

struct CustomField {
    let key: String
    let label: String
    let type: FieldType
    let required: Bool
    let defaultValue: String?
    let validationRegex: String?
    
    enum FieldType {
        case text
        case email
        case select(options: [String])
        case checkbox
        case hidden
    }
}

// MARK: - Service Protocols

protocol EnterpriseAuthServiceProtocol {
    func discoverTenant(domain: String) async throws -> TenantInfo
    func getTenantConfiguration(tenantId: String) async throws -> EnterpriseTenantConfiguration
    func getAvailableProviders(tenantId: String) async throws -> [EnterpriseProvider]
    func getProviderConfiguration(tenantId: String, providerId: String) async throws -> ProviderConfiguration
    func signInWithCredentials(tenantId: String, username: String, password: String) async throws -> AuthenticationResult
    func signInWithSAML(tenantId: String, providerConfig: [String: Any]) async throws -> AuthenticationResult
    func buildSSORedirectURL(tenantId: String, providerId: String, state: String, redirectURI: String) async throws -> URL
    func processSSOCallback(callbackURL: URL, expectedState: String) async throws -> AuthenticationResult
    func requestMFAChallenge(challengeId: String, method: MFAMethod) async throws
    func assignUserRole(userId: String, tenantId: String, role: TenantRole) async throws
}

protocol ComplianceServiceProtocol {
    func checkDeviceCompliance() async -> ComplianceCheckResult
}

struct ProviderConfiguration {
    let supportedMFAMethods: [MFAMethod]
    let requiresDeviceRegistration: Bool
    let customAttributes: [String: Any]
}

// MARK: - Preview Support

extension EnterpriseLoginViewModel {
    static var preview: EnterpriseLoginViewModel {
        let mockAuth = ServiceContainer.shared.resolve(AuthenticationServiceProtocol.self)!
        let mockEnterprise = MockEnterpriseAuthService()
        let mockTenant = ServiceContainer.shared.resolve(TenantConfigurationServiceProtocol.self)!
        let mockSecurity = ServiceContainer.shared.resolve(SecurityServiceProtocol.self)!
        let mockCompliance = MockComplianceService()
        
        return EnterpriseLoginViewModel(
            authenticationService: mockAuth,
            enterpriseAuthService: mockEnterprise,
            tenantConfigurationService: mockTenant,
            securityService: mockSecurity,
            complianceService: mockCompliance
        )
    }
}

// MARK: - Mock Services

class MockEnterpriseAuthService: EnterpriseAuthServiceProtocol {
    func discoverTenant(domain: String) async throws -> TenantInfo {
        return TenantInfo(
            id: "tenant_1",
            name: "Sample Golf Club",
            domain: domain,
            logoURL: nil,
            primaryColor: "#007AFF",
            isActive: true,
            subscription: TenantSubscription(
                plan: "enterprise",
                userLimit: 1000,
                featuresEnabled: ["sso", "mfa", "device_management"],
                expiresAt: nil,
                isTrialAccount: false
            ),
            settings: TenantSettings(
                authenticationMethods: [.azureAD, .googleWorkspace],
                mfaRequired: true,
                sessionTimeout: 3600,
                allowedDomains: [domain],
                ssoEnabled: true,
                loginBrandingEnabled: true
            )
        )
    }
    
    func getTenantConfiguration(tenantId: String) async throws -> EnterpriseTenantConfiguration {
        return EnterpriseTenantConfiguration(
            requiresCredentials: false,
            requiresMFA: true,
            requiresRoleSelection: false,
            requiresDeviceRegistration: true,
            allowedMFAMethods: [.totp, .sms],
            availableRoles: [.member, .admin],
            sessionTimeout: 3600,
            passwordPolicy: PasswordPolicy(
                minimumLength: 8,
                requiresUppercase: true,
                requiresLowercase: true,
                requiresNumbers: true,
                requiresSpecialCharacters: true,
                disallowedPasswords: [],
                historyCount: 5,
                expirationDays: 90
            ),
            securityPolicy: TenantSecurityPolicy(
                requiresBiometricForLogin: false,
                requiresBiometricForTransactions: true,
                requiresAdditionalAuthForSensitiveActions: true,
                allowsPasscodeFallback: true,
                minimumSecurityLevel: .enhanced,
                allowsBiometricSkip: false
            )
        )
    }
    
    func getAvailableProviders(tenantId: String) async throws -> [EnterpriseProvider] {
        return [
            EnterpriseProvider(
                id: "azure_ad",
                type: .azureAD,
                displayName: "Azure Active Directory",
                iconURL: nil,
                endpoint: nil,
                requiresCredentials: false,
                supportsMFA: true,
                configuration: [:],
                oidcConfiguration: OIDCConfiguration(
                    issuer: URL(string: "https://login.microsoftonline.com/tenant/v2.0")!,
                    clientId: "client_id",
                    clientSecret: "client_secret",
                    redirectURI: "golffinder://auth/callback",
                    scopes: ["openid", "email", "profile"],
                    additionalParameters: [:]
                )
            )
        ]
    }
    
    func getProviderConfiguration(tenantId: String, providerId: String) async throws -> ProviderConfiguration {
        return ProviderConfiguration(
            supportedMFAMethods: [.totp, .sms],
            requiresDeviceRegistration: true,
            customAttributes: [:]
        )
    }
    
    func signInWithCredentials(tenantId: String, username: String, password: String) async throws -> AuthenticationResult {
        // Mock implementation
        throw AuthenticationError.mfaRequired
    }
    
    func signInWithSAML(tenantId: String, providerConfig: [String: Any]) async throws -> AuthenticationResult {
        // Mock implementation
        throw AuthenticationError.unsupportedProvider
    }
    
    func buildSSORedirectURL(tenantId: String, providerId: String, state: String, redirectURI: String) async throws -> URL {
        return URL(string: "https://login.microsoftonline.com/oauth2/authorize?client_id=123&state=\(state)")!
    }
    
    func processSSOCallback(callbackURL: URL, expectedState: String) async throws -> AuthenticationResult {
        // Mock implementation
        throw AuthenticationError.invalidCredentials
    }
    
    func requestMFAChallenge(challengeId: String, method: MFAMethod) async throws {
        // Mock implementation
    }
    
    func assignUserRole(userId: String, tenantId: String, role: TenantRole) async throws {
        // Mock implementation
    }
}

class MockComplianceService: ComplianceServiceProtocol {
    func checkDeviceCompliance() async -> ComplianceCheckResult {
        return ComplianceCheckResult(
            isCompliant: true,
            violations: [],
            blockAuthentication: false,
            warningsOnly: false,
            checkTimestamp: Date()
        )
    }
}