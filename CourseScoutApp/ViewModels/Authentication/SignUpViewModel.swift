import Foundation
import SwiftUI
import Combine
import LocalAuthentication
import os.log

// MARK: - SignUp View Model

@MainActor
final class SignUpViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var phoneNumber: String = ""
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var showSuccess: Bool = false
    @Published var successMessage: String = ""
    
    // MARK: - Agreement & Consent
    
    @Published var agreedToTerms: Bool = false
    @Published var agreedToPrivacy: Bool = false
    @Published var agreedToMarketing: Bool = false
    @Published var showTermsSheet: Bool = false
    @Published var showPrivacySheet: Bool = false
    
    // MARK: - Form Validation
    
    @Published var emailError: String = ""
    @Published var passwordError: String = ""
    @Published var confirmPasswordError: String = ""
    @Published var nameError: String = ""
    @Published var phoneError: String = ""
    
    // MARK: - OAuth Sign Up
    
    @Published var selectedProvider: AuthenticationProvider = .google
    @Published var showProviderSelection: Bool = false
    @Published var isOAuthSignUp: Bool = false
    
    // MARK: - Enterprise Sign Up
    
    @Published var isEnterpriseSignUp: Bool = false
    @Published var organizationName: String = ""
    @Published var organizationDomain: String = ""
    @Published var jobTitle: String = ""
    @Published var department: String = ""
    @Published var invitationCode: String = ""
    
    // MARK: - White Label Configuration
    
    @Published var tenantConfiguration: TenantConfiguration?
    @Published var brandingTheme: TenantTheme?
    @Published var customSignUpFields: [CustomSignUpField] = []
    
    // MARK: - Dependencies
    
    private let authenticationService: AuthenticationServiceProtocol
    private let userProfileService: UserProfileServiceProtocol
    private let consentService: ConsentManagementServiceProtocol
    private let tenantConfigurationService: TenantConfigurationServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderApp", category: "SignUpViewModel")
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let emailValidator = EmailValidator()
    private let passwordValidator = PasswordValidator()
    private let phoneValidator = PhoneNumberValidator()
    
    // MARK: - Computed Properties
    
    var isFormValid: Bool {
        return isBasicInfoValid && 
               isPasswordValid && 
               areAgreementsValid &&
               isEnterpriseInfoValid
    }
    
    var isBasicInfoValid: Bool {
        return !firstName.isEmpty &&
               !lastName.isEmpty &&
               emailValidator.isValid(email) &&
               (phoneNumber.isEmpty || phoneValidator.isValid(phoneNumber))
    }
    
    var isPasswordValid: Bool {
        return passwordValidator.isValid(password) &&
               password == confirmPassword
    }
    
    var areAgreementsValid: Bool {
        return agreedToTerms && agreedToPrivacy
    }
    
    var isEnterpriseInfoValid: Bool {
        if isEnterpriseSignUp {
            return !organizationName.isEmpty &&
                   !organizationDomain.isEmpty
        }
        return true
    }
    
    var passwordStrength: PasswordStrength {
        return passwordValidator.calculateStrength(password)
    }
    
    var availableProviders: [AuthenticationProvider] {
        if isEnterpriseSignUp {
            return [.azureAD, .googleWorkspace, .okta]
        } else {
            return [.google, .apple, .facebook, .microsoft]
        }
    }
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        userProfileService: UserProfileServiceProtocol,
        consentService: ConsentManagementServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol
    ) {
        self.authenticationService = authenticationService
        self.userProfileService = userProfileService
        self.consentService = consentService
        self.tenantConfigurationService = tenantConfigurationService
        
        setupValidation()
        loadTenantConfiguration()
        logger.info("SignUpViewModel initialized")
    }
    
    // MARK: - Setup Methods
    
    private func setupValidation() {
        // Real-time email validation
        $email
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] email in
                self?.validateEmail(email)
            }
            .store(in: &cancellables)
        
        // Real-time password validation
        $password
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] password in
                self?.validatePassword(password)
            }
            .store(in: &cancellables)
        
        // Real-time confirm password validation
        $confirmPassword
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] confirmPassword in
                self?.validateConfirmPassword(confirmPassword)
            }
            .store(in: &cancellables)
        
        // Real-time phone validation
        $phoneNumber
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] phone in
                self?.validatePhoneNumber(phone)
            }
            .store(in: &cancellables)
    }
    
    private func loadTenantConfiguration() {
        Task {
            do {
                if let tenant = await tenantConfigurationService.getCurrentTenant() {
                    let config = try await tenantConfigurationService.getTenantConfiguration(tenantId: tenant.id)
                    let theme = try await tenantConfigurationService.getTenantTheme(tenantId: tenant.id)
                    let customFields = try await tenantConfigurationService.getCustomSignUpFields(tenantId: tenant.id)
                    
                    await MainActor.run {
                        self.tenantConfiguration = config
                        self.brandingTheme = theme
                        self.customSignUpFields = customFields
                    }
                }
            } catch {
                logger.error("Failed to load tenant configuration: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Validation Methods
    
    private func validateEmail(_ email: String) {
        if email.isEmpty {
            emailError = ""
        } else if !emailValidator.isValid(email) {
            emailError = "Please enter a valid email address"
        } else {
            emailError = ""
            checkEmailAvailability(email)
        }
    }
    
    private func validatePassword(_ password: String) {
        if password.isEmpty {
            passwordError = ""
        } else {
            let validationResult = passwordValidator.validate(password)
            passwordError = validationResult.isValid ? "" : validationResult.errorMessage
        }
    }
    
    private func validateConfirmPassword(_ confirmPassword: String) {
        if confirmPassword.isEmpty {
            confirmPasswordError = ""
        } else if password != confirmPassword {
            confirmPasswordError = "Passwords do not match"
        } else {
            confirmPasswordError = ""
        }
    }
    
    private func validatePhoneNumber(_ phone: String) {
        if phone.isEmpty {
            phoneError = ""
        } else if !phoneValidator.isValid(phone) {
            phoneError = "Please enter a valid phone number"
        } else {
            phoneError = ""
        }
    }
    
    private func checkEmailAvailability(_ email: String) {
        Task {
            do {
                let isAvailable = try await userProfileService.isEmailAvailable(email)
                await MainActor.run {
                    if !isAvailable {
                        self.emailError = "This email is already registered"
                    }
                }
            } catch {
                logger.error("Failed to check email availability: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Sign Up Methods
    
    func signUp() {
        guard isFormValid else {
            showError = true
            errorMessage = "Please fill in all required fields correctly"
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                // Create user profile
                let userProfile = UserProfileCreation(
                    email: email,
                    firstName: firstName,
                    lastName: lastName,
                    phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
                    organizationName: isEnterpriseSignUp ? organizationName : nil,
                    organizationDomain: isEnterpriseSignUp ? organizationDomain : nil,
                    jobTitle: isEnterpriseSignUp ? jobTitle : nil,
                    department: isEnterpriseSignUp ? department : nil,
                    customFields: customSignUpFields.reduce(into: [:]) { dict, field in
                        dict[field.key] = field.value
                    }
                )
                
                // Record consent
                let consentRecord = ConsentRecord(
                    termsOfService: agreedToTerms,
                    privacyPolicy: agreedToPrivacy,
                    marketing: agreedToMarketing,
                    timestamp: Date(),
                    ipAddress: await getCurrentIPAddress(),
                    userAgent: getCurrentUserAgent()
                )
                
                // Create account
                let authResult = try await createUserAccount(
                    profile: userProfile,
                    password: password,
                    consent: consentRecord
                )
                
                await handleSuccessfulSignUp(authResult)
                
            } catch {
                await handleSignUpError(error)
            }
        }
    }
    
    func signUpWithProvider(_ provider: AuthenticationProvider) {
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
                self.selectedProvider = provider
                self.isOAuthSignUp = true
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
                case .azureAD:
                    result = try await authenticationService.signInWithAzureAD(tenantId: organizationDomain)
                case .googleWorkspace:
                    result = try await authenticationService.signInWithGoogleWorkspace(domain: organizationDomain)
                case .okta:
                    result = try await authenticationService.signInWithOkta(orgUrl: organizationDomain)
                default:
                    throw AuthenticationError.unsupportedProvider
                }
                
                // For OAuth sign up, we still need to collect additional profile info
                // and consent if this is a new user
                if await isNewUser(result.user) {
                    await handleOAuthNewUser(result)
                } else {
                    await handleSuccessfulSignUp(result)
                }
                
            } catch {
                await handleSignUpError(error)
            }
        }
    }
    
    // MARK: - Enterprise Sign Up
    
    func signUpWithInvitation() {
        guard !invitationCode.isEmpty else {
            showError = true
            errorMessage = "Please enter your invitation code"
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                // Validate invitation code
                let invitation = try await validateInvitationCode(invitationCode)
                
                // Pre-fill organization info from invitation
                await MainActor.run {
                    self.organizationName = invitation.organizationName
                    self.organizationDomain = invitation.organizationDomain
                    self.isEnterpriseSignUp = true
                }
                
                // Continue with regular sign up process
                await signUp()
                
            } catch {
                await handleSignUpError(error)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createUserAccount(
        profile: UserProfileCreation,
        password: String,
        consent: ConsentRecord
    ) async throws -> AuthenticationResult {
        
        // Create the user account through the profile service
        let user = try await userProfileService.createUserProfile(profile)
        
        // Record consent
        try await consentService.recordConsent(userId: user.id, consent: consent)
        
        // For email/password signup, we would typically:
        // 1. Create the authentication credentials
        // 2. Send email verification
        // 3. Create a session token
        
        // This is simplified - in practice you'd integrate with your auth provider
        let authResult = AuthenticationResult(
            accessToken: "temp_token", // Would be generated by auth service
            refreshToken: "temp_refresh",
            idToken: nil,
            user: AuthenticatedUser(
                id: user.id,
                email: user.email,
                name: "\(user.firstName) \(user.lastName)",
                profileImageURL: user.profileImageURL,
                provider: .email,
                tenantMemberships: [],
                lastLoginAt: Date(),
                createdAt: Date(),
                preferences: UserPreferences(
                    language: "en",
                    timezone: TimeZone.current.identifier,
                    notifications: NotificationPreferences(
                        emailNotifications: true,
                        pushNotifications: true,
                        smsNotifications: false,
                        securityAlerts: true
                    ),
                    privacy: PrivacySettings(
                        profileVisibility: .public,
                        dataProcessingConsent: consent.privacyPolicy,
                        analyticsOptOut: false,
                        marketingOptOut: !consent.marketing
                    )
                )
            ),
            tenant: nil,
            expiresAt: Date().addingTimeInterval(3600),
            tokenType: "Bearer",
            scope: []
        )
        
        return authResult
    }
    
    private func isNewUser(_ user: AuthenticatedUser) async -> Bool {
        // Check if this is a new user based on creation date or profile completeness
        return user.createdAt.timeIntervalSinceNow > -60 // Created in last minute
    }
    
    private func handleOAuthNewUser(_ result: AuthenticationResult) async {
        // For OAuth new users, we might need additional profile info
        await MainActor.run {
            // Pre-fill available information from OAuth provider
            if let email = result.user.email {
                self.email = email
            }
            
            if let name = result.user.name {
                let components = name.components(separatedBy: " ")
                self.firstName = components.first ?? ""
                self.lastName = components.dropFirst().joined(separator: " ")
            }
            
            // Show additional info collection if needed
            // For now, proceed with the available info
        }
        
        await handleSuccessfulSignUp(result)
    }
    
    private func validateInvitationCode(_ code: String) async throws -> InvitationInfo {
        // Validate the invitation code with the backend
        // This is a placeholder implementation
        return InvitationInfo(
            code: code,
            organizationName: "Sample Golf Club",
            organizationDomain: "samplegolf.com",
            expiresAt: Date().addingTimeInterval(86400),
            isValid: true
        )
    }
    
    private func handleSuccessfulSignUp(_ result: AuthenticationResult) async {
        await MainActor.run {
            self.isLoading = false
            self.showSuccess = true
            self.successMessage = "Account created successfully! Welcome to GolfFinder."
            
            // Clear form
            self.clearForm()
        }
        
        logger.info("Sign up successful for user: \(result.user.id)")
    }
    
    private func handleSignUpError(_ error: Error) async {
        await MainActor.run {
            self.isLoading = false
            self.showError = true
            
            if let authError = error as? AuthenticationError {
                self.errorMessage = authError.localizedDescription
            } else {
                self.errorMessage = "An error occurred during sign up. Please try again."
            }
        }
        
        logger.error("Sign up failed: \(error.localizedDescription)")
    }
    
    // MARK: - UI Actions
    
    func toggleEnterpriseMode() {
        isEnterpriseSignUp.toggle()
        clearEnterpriseFields()
    }
    
    func showProviderSelectionSheet() {
        showProviderSelection = true
    }
    
    func showTermsOfService() {
        showTermsSheet = true
    }
    
    func showPrivacyPolicy() {
        showPrivacySheet = true
    }
    
    func dismissError() {
        showError = false
        errorMessage = ""
    }
    
    func dismissSuccess() {
        showSuccess = false
        successMessage = ""
    }
    
    func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        firstName = ""
        lastName = ""
        phoneNumber = ""
        agreedToTerms = false
        agreedToPrivacy = false
        agreedToMarketing = false
        clearEnterpriseFields()
        clearErrors()
    }
    
    func clearEnterpriseFields() {
        organizationName = ""
        organizationDomain = ""
        jobTitle = ""
        department = ""
        invitationCode = ""
    }
    
    func clearErrors() {
        emailError = ""
        passwordError = ""
        confirmPasswordError = ""
        nameError = ""
        phoneError = ""
    }
    
    // MARK: - Utility Methods
    
    private func getCurrentIPAddress() async -> String {
        // Implementation would get current IP address
        return "127.0.0.1"
    }
    
    private func getCurrentUserAgent() -> String {
        return "GolfFinderApp/1.0 iOS/\(UIDevice.current.systemVersion)"
    }
}

// MARK: - Supporting Types

struct UserProfileCreation {
    let email: String
    let firstName: String
    let lastName: String
    let phoneNumber: String?
    let organizationName: String?
    let organizationDomain: String?
    let jobTitle: String?
    let department: String?
    let customFields: [String: String]
}

struct ConsentRecord {
    let termsOfService: Bool
    let privacyPolicy: Bool
    let marketing: Bool
    let timestamp: Date
    let ipAddress: String
    let userAgent: String
}

struct InvitationInfo {
    let code: String
    let organizationName: String
    let organizationDomain: String
    let expiresAt: Date
    let isValid: Bool
}

struct TenantConfiguration {
    let requiresInvitation: Bool
    let allowedDomains: [String]
    let customFields: [CustomSignUpField]
    let termsOfServiceURL: URL?
    let privacyPolicyURL: URL?
}

struct CustomSignUpField {
    let key: String
    let label: String
    let type: FieldType
    let isRequired: Bool
    let placeholder: String?
    var value: String = ""
    
    enum FieldType {
        case text
        case email
        case phone
        case dropdown(options: [String])
        case multiline
    }
}

// MARK: - Validators

class EmailValidator {
    func isValid(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }
}

class PasswordValidator {
    func isValid(_ password: String) -> Bool {
        return password.count >= 8 &&
               password.contains { $0.isLowercase } &&
               password.contains { $0.isUppercase } &&
               password.contains { $0.isNumber } &&
               password.contains { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }
    }
    
    func validate(_ password: String) -> (isValid: Bool, errorMessage: String) {
        var errors: [String] = []
        
        if password.count < 8 {
            errors.append("at least 8 characters")
        }
        
        if !password.contains(where: { $0.isLowercase }) {
            errors.append("a lowercase letter")
        }
        
        if !password.contains(where: { $0.isUppercase }) {
            errors.append("an uppercase letter")
        }
        
        if !password.contains(where: { $0.isNumber }) {
            errors.append("a number")
        }
        
        if !password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }) {
            errors.append("a special character")
        }
        
        if errors.isEmpty {
            return (true, "")
        } else {
            return (false, "Password must contain " + errors.joined(separator: ", "))
        }
    }
    
    func calculateStrength(_ password: String) -> PasswordStrength {
        var score = 0
        
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.contains(where: { $0.isLowercase }) { score += 1 }
        if password.contains(where: { $0.isUppercase }) { score += 1 }
        if password.contains(where: { $0.isNumber }) { score += 1 }
        if password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }) { score += 1 }
        
        switch score {
        case 0...2: return .weak
        case 3...4: return .medium
        case 5...6: return .strong
        default: return .strong
        }
    }
}

enum PasswordStrength: CaseIterable {
    case weak, medium, strong
    
    var color: Color {
        switch self {
        case .weak: return .red
        case .medium: return .orange
        case .strong: return .green
        }
    }
    
    var description: String {
        switch self {
        case .weak: return "Weak"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}

class PhoneNumberValidator {
    func isValid(_ phone: String) -> Bool {
        let phoneRegex = "^[+]?[1-9]\\d{1,14}$"
        let cleanPhone = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        return NSPredicate(format: "SELF MATCHES %@", phoneRegex).evaluate(with: cleanPhone)
    }
}

// MARK: - Preview Support

extension SignUpViewModel {
    static var preview: SignUpViewModel {
        let mockAuth = ServiceContainer.shared.resolve(AuthenticationServiceProtocol.self)!
        let mockProfile = ServiceContainer.shared.resolve(UserProfileServiceProtocol.self)!
        let mockConsent = ServiceContainer.shared.resolve(ConsentManagementServiceProtocol.self)!
        let mockTenant = ServiceContainer.shared.resolve(TenantConfigurationServiceProtocol.self)!
        
        return SignUpViewModel(
            authenticationService: mockAuth,
            userProfileService: mockProfile,
            consentService: mockConsent,
            tenantConfigurationService: mockTenant
        )
    }
}