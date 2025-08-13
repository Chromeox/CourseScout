import Foundation
import SwiftUI
import Combine
import LocalAuthentication
import PhotosUI
import os.log

// MARK: - Profile View Model

@MainActor
final class ProfileViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var user: AuthenticatedUser?
    @Published var userProfile: UserProfile?
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var showSuccess: Bool = false
    @Published var successMessage: String = ""
    
    // MARK: - Profile Editing
    
    @Published var isEditing: Bool = false
    @Published var editedFirstName: String = ""
    @Published var editedLastName: String = ""
    @Published var editedEmail: String = ""
    @Published var editedPhoneNumber: String = ""
    @Published var editedBiography: String = ""
    @Published var editedJobTitle: String = ""
    @Published var editedDepartment: String = ""
    @Published var editedLocation: String = ""
    @Published var editedWebsite: String = ""
    
    // MARK: - Profile Photo
    
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var profileImage: UIImage?
    @Published var showPhotoActionSheet: Bool = false
    @Published var showCamera: Bool = false
    @Published var showPhotoPicker: Bool = false
    @Published var isUploadingPhoto: Bool = false
    
    // MARK: - Preferences
    
    @Published var language: String = "en"
    @Published var timezone: String = ""
    @Published var emailNotifications: Bool = true
    @Published var pushNotifications: Bool = true
    @Published var smsNotifications: Bool = false
    @Published var securityAlerts: Bool = true
    @Published var marketingEmails: Bool = false
    @Published var profileVisibility: ProfileVisibility = .public
    @Published var analyticsOptOut: Bool = false
    
    // MARK: - Security Settings
    
    @Published var showSecuritySettings: Bool = false
    @Published var isMFAEnabled: Bool = false
    @Published var showMFASetup: Bool = false
    @Published var mfaSetupResult: MFASetupResult?
    @Published var showBackupCodes: Bool = false
    @Published var backupCodes: [String] = []
    @Published var biometricEnabled: Bool = false
    @Published var showBiometricSetup: Bool = false
    
    // MARK: - Account Management
    
    @Published var showChangePassword: Bool = false
    @Published var currentPassword: String = ""
    @Published var newPassword: String = ""
    @Published var confirmNewPassword: String = ""
    @Published var showDeleteAccount: Bool = false
    @Published var deleteAccountConfirmation: String = ""
    @Published var showExportData: Bool = false
    
    // MARK: - Session Management
    
    @Published var activeSessions: [AuthenticationSession] = []
    @Published var showSessionManager: Bool = false
    @Published var isLoadingSessions: Bool = false
    
    // MARK: - Tenant Management
    
    @Published var userTenants: [TenantInfo] = []
    @Published var currentTenant: TenantInfo?
    @Published var showTenantSwitcher: Bool = false
    @Published var isLoadingTenants: Bool = false
    
    // MARK: - Form Validation
    
    @Published var emailError: String = ""
    @Published var phoneError: String = ""
    @Published var websiteError: String = ""
    @Published var passwordError: String = ""
    @Published var confirmPasswordError: String = ""
    
    // MARK: - Dependencies
    
    private let authenticationService: AuthenticationServiceProtocol
    private let userProfileService: UserProfileServiceProtocol
    private let biometricService: BiometricAuthServiceProtocol
    private let sessionService: SessionManagementServiceProtocol
    private let consentService: ConsentManagementServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderApp", category: "ProfileViewModel")
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let emailValidator = EmailValidator()
    private let phoneValidator = PhoneNumberValidator()
    private let passwordValidator = PasswordValidator()
    
    // MARK: - Computed Properties
    
    var fullName: String {
        guard let profile = userProfile else { return user?.name ?? "" }
        return "\(profile.firstName) \(profile.lastName)"
    }
    
    var isFormValid: Bool {
        return !editedFirstName.isEmpty &&
               !editedLastName.isEmpty &&
               emailValidator.isValid(editedEmail) &&
               (editedPhoneNumber.isEmpty || phoneValidator.isValid(editedPhoneNumber)) &&
               (editedWebsite.isEmpty || isValidURL(editedWebsite))
    }
    
    var isPasswordChangeValid: Bool {
        return !currentPassword.isEmpty &&
               passwordValidator.isValid(newPassword) &&
               newPassword == confirmNewPassword
    }
    
    var canDeleteAccount: Bool {
        return deleteAccountConfirmation.lowercased() == "delete my account"
    }
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        userProfileService: UserProfileServiceProtocol,
        biometricService: BiometricAuthServiceProtocol,
        sessionService: SessionManagementServiceProtocol,
        consentService: ConsentManagementServiceProtocol
    ) {
        self.authenticationService = authenticationService
        self.userProfileService = userProfileService
        self.biometricService = biometricService
        self.sessionService = sessionService
        self.consentService = consentService
        
        setupObservers()
        loadUserProfile()
        logger.info("ProfileViewModel initialized")
    }
    
    // MARK: - Setup Methods
    
    private func setupObservers() {
        // Monitor authentication state
        authenticationService.authenticationStateChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case .authenticated(let user, let tenant) = state {
                    self?.user = user
                    self?.currentTenant = tenant
                    self?.loadUserProfile()
                } else if case .unauthenticated = state {
                    self?.user = nil
                    self?.userProfile = nil
                    self?.currentTenant = nil
                }
            }
            .store(in: &cancellables)
        
        // Monitor selected photo changes
        $selectedPhotoItem
            .sink { [weak self] item in
                if let item = item {
                    self?.loadSelectedPhoto(item)
                }
            }
            .store(in: &cancellables)
        
        // Real-time validation
        setupFormValidation()
    }
    
    private func setupFormValidation() {
        $editedEmail
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] email in
                self?.validateEmail(email)
            }
            .store(in: &cancellables)
        
        $editedPhoneNumber
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] phone in
                self?.validatePhoneNumber(phone)
            }
            .store(in: &cancellables)
        
        $editedWebsite
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] website in
                self?.validateWebsite(website)
            }
            .store(in: &cancellables)
        
        $newPassword
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] password in
                self?.validateNewPassword(password)
            }
            .store(in: &cancellables)
        
        $confirmNewPassword
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] confirmPassword in
                self?.validateConfirmPassword(confirmPassword)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    
    func loadUserProfile() {
        guard let user = authenticationService.currentUser else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                let profile = try await userProfileService.getUserProfile(userId: user.id)
                let preferences = try await userProfileService.getUserPreferences(userId: user.id)
                let mfaStatus = try await authenticationService.getMFAStatus()
                let biometricStatus = await biometricService.isBiometricEnabled()
                
                await MainActor.run {
                    self.userProfile = profile
                    self.updateEditedFields(from: profile)
                    self.updatePreferences(from: preferences)
                    self.isMFAEnabled = mfaStatus
                    self.biometricEnabled = biometricStatus
                    self.isLoading = false
                }
                
                // Load profile image
                if let imageURL = profile.profileImageURL {
                    await loadProfileImage(from: imageURL)
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to load profile: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func loadActiveSessions() {
        guard let user = user else { return }
        
        Task {
            await MainActor.run {
                self.isLoadingSessions = true
            }
            
            do {
                let sessions = try await sessionService.getUserSessions(userId: user.id)
                
                await MainActor.run {
                    self.activeSessions = sessions.map { session in
                        AuthenticationSession(
                            id: session.id,
                            userId: session.userId,
                            tenantId: session.tenantId,
                            deviceId: session.deviceId,
                            createdAt: session.createdAt,
                            lastAccessedAt: session.lastAccessedAt,
                            expiresAt: session.expiresAt,
                            ipAddress: session.ipAddress,
                            userAgent: session.userAgent,
                            isActive: session.isActive
                        )
                    }
                    self.isLoadingSessions = false
                }
                
            } catch {
                await MainActor.run {
                    self.isLoadingSessions = false
                    self.showError = true
                    self.errorMessage = "Failed to load sessions: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func loadUserTenants() {
        Task {
            await MainActor.run {
                self.isLoadingTenants = true
            }
            
            do {
                let tenants = try await authenticationService.getUserTenants()
                
                await MainActor.run {
                    self.userTenants = tenants
                    self.isLoadingTenants = false
                }
                
            } catch {
                await MainActor.run {
                    self.isLoadingTenants = false
                    self.showError = true
                    self.errorMessage = "Failed to load tenants: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Profile Management
    
    func startEditing() {
        isEditing = true
        if let profile = userProfile {
            updateEditedFields(from: profile)
        }
    }
    
    func cancelEditing() {
        isEditing = false
        clearEditedFields()
        clearErrors()
    }
    
    func saveProfile() {
        guard isFormValid else {
            showError = true
            errorMessage = "Please correct the errors in the form"
            return
        }
        
        guard let userId = user?.id else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                let updatedProfile = UserProfileUpdate(
                    firstName: editedFirstName,
                    lastName: editedLastName,
                    email: editedEmail,
                    phoneNumber: editedPhoneNumber.isEmpty ? nil : editedPhoneNumber,
                    biography: editedBiography.isEmpty ? nil : editedBiography,
                    jobTitle: editedJobTitle.isEmpty ? nil : editedJobTitle,
                    department: editedDepartment.isEmpty ? nil : editedDepartment,
                    location: editedLocation.isEmpty ? nil : editedLocation,
                    website: editedWebsite.isEmpty ? nil : editedWebsite
                )
                
                let profile = try await userProfileService.updateUserProfile(
                    userId: userId,
                    update: updatedProfile
                )
                
                await MainActor.run {
                    self.userProfile = profile
                    self.isEditing = false
                    self.isLoading = false
                    self.showSuccess = true
                    self.successMessage = "Profile updated successfully"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to update profile: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func updatePreferences() {
        guard let userId = user?.id else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                let preferences = UserPreferences(
                    language: language,
                    timezone: timezone,
                    notifications: NotificationPreferences(
                        emailNotifications: emailNotifications,
                        pushNotifications: pushNotifications,
                        smsNotifications: smsNotifications,
                        securityAlerts: securityAlerts
                    ),
                    privacy: PrivacySettings(
                        profileVisibility: profileVisibility,
                        dataProcessingConsent: true,
                        analyticsOptOut: analyticsOptOut,
                        marketingOptOut: !marketingEmails
                    )
                )
                
                try await userProfileService.updateUserPreferences(
                    userId: userId,
                    preferences: preferences
                )
                
                await MainActor.run {
                    self.isLoading = false
                    self.showSuccess = true
                    self.successMessage = "Preferences updated successfully"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to update preferences: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Photo Management
    
    private func loadSelectedPhoto(_ item: PhotosPickerItem) {
        Task {
            await MainActor.run {
                self.isUploadingPhoto = true
            }
            
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    
                    await MainActor.run {
                        self.profileImage = image
                    }
                    
                    await uploadProfilePhoto(image)
                }
            } catch {
                await MainActor.run {
                    self.isUploadingPhoto = false
                    self.showError = true
                    self.errorMessage = "Failed to load selected photo"
                }
            }
        }
    }
    
    private func uploadProfilePhoto(_ image: UIImage) async {
        guard let userId = user?.id,
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            await MainActor.run {
                self.isUploadingPhoto = false
                self.showError = true
                self.errorMessage = "Failed to process image"
            }
            return
        }
        
        do {
            let imageURL = try await userProfileService.uploadProfilePhoto(
                userId: userId,
                imageData: imageData,
                filename: "profile.jpg"
            )
            
            await MainActor.run {
                self.userProfile?.profileImageURL = imageURL
                self.isUploadingPhoto = false
                self.showSuccess = true
                self.successMessage = "Profile photo updated successfully"
            }
            
        } catch {
            await MainActor.run {
                self.isUploadingPhoto = false
                self.showError = true
                self.errorMessage = "Failed to upload photo: \(error.localizedDescription)"
            }
        }
    }
    
    private func loadProfileImage(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    self.profileImage = image
                }
            }
        } catch {
            logger.error("Failed to load profile image: \(error.localizedDescription)")
        }
    }
    
    func removeProfilePhoto() {
        guard let userId = user?.id else { return }
        
        Task {
            await MainActor.run {
                self.isUploadingPhoto = true
            }
            
            do {
                try await userProfileService.removeProfilePhoto(userId: userId)
                
                await MainActor.run {
                    self.profileImage = nil
                    self.userProfile?.profileImageURL = nil
                    self.isUploadingPhoto = false
                    self.showSuccess = true
                    self.successMessage = "Profile photo removed"
                }
                
            } catch {
                await MainActor.run {
                    self.isUploadingPhoto = false
                    self.showError = true
                    self.errorMessage = "Failed to remove photo: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Security Management
    
    func enableMFA() {
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                let setupResult = try await authenticationService.enableMFA()
                
                await MainActor.run {
                    self.mfaSetupResult = setupResult
                    self.showMFASetup = true
                    self.isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to enable MFA: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func disableMFA() {
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                try await authenticationService.disableMFA()
                
                await MainActor.run {
                    self.isMFAEnabled = false
                    self.isLoading = false
                    self.showSuccess = true
                    self.successMessage = "Multi-factor authentication disabled"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to disable MFA: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func generateBackupCodes() {
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                let codes = try await authenticationService.generateBackupCodes()
                
                await MainActor.run {
                    self.backupCodes = codes
                    self.showBackupCodes = true
                    self.isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to generate backup codes: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func enableBiometrics() {
        Task {
            let success = try await biometricService.enableBiometricAuthentication()
            
            await MainActor.run {
                self.biometricEnabled = success
                if success {
                    self.showSuccess = true
                    self.successMessage = "Biometric authentication enabled"
                }
            }
        }
    }
    
    func disableBiometrics() {
        Task {
            try await biometricService.disableBiometricAuthentication()
            
            await MainActor.run {
                self.biometricEnabled = false
                self.showSuccess = true
                self.successMessage = "Biometric authentication disabled"
            }
        }
    }
    
    // MARK: - Password Management
    
    func changePassword() {
        guard isPasswordChangeValid else {
            showError = true
            errorMessage = "Please check your password entries"
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                try await userProfileService.changePassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword
                )
                
                await MainActor.run {
                    self.isLoading = false
                    self.showChangePassword = false
                    self.currentPassword = ""
                    self.newPassword = ""
                    self.confirmNewPassword = ""
                    self.showSuccess = true
                    self.successMessage = "Password changed successfully"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to change password: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Session Management
    
    func terminateSession(_ sessionId: String) {
        Task {
            do {
                try await authenticationService.terminateSession(sessionId)
                await loadActiveSessions()
                
                await MainActor.run {
                    self.showSuccess = true
                    self.successMessage = "Session terminated"
                }
                
            } catch {
                await MainActor.run {
                    self.showError = true
                    self.errorMessage = "Failed to terminate session: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func terminateAllOtherSessions() {
        Task {
            do {
                try await authenticationService.terminateAllSessions()
                await loadActiveSessions()
                
                await MainActor.run {
                    self.showSuccess = true
                    self.successMessage = "All other sessions terminated"
                }
                
            } catch {
                await MainActor.run {
                    self.showError = true
                    self.errorMessage = "Failed to terminate sessions: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Account Management
    
    func exportAccountData() {
        guard let userId = user?.id else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                let exportURL = try await userProfileService.exportUserData(userId: userId)
                
                await MainActor.run {
                    self.isLoading = false
                    self.showSuccess = true
                    self.successMessage = "Data export will be sent to your email"
                }
                
                // In a real app, you might also share the file directly
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to export data: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func deleteAccount() {
        guard canDeleteAccount else {
            showError = true
            errorMessage = "Please type 'delete my account' to confirm"
            return
        }
        
        guard let userId = user?.id else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                try await userProfileService.deleteUserAccount(userId: userId)
                
                // This would typically sign the user out and redirect to login
                try await authenticationService.clearStoredTokens()
                
                await MainActor.run {
                    self.isLoading = false
                    self.showDeleteAccount = false
                    // Navigation to login would be handled by the parent view
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to delete account: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Tenant Management
    
    func switchTenant(_ tenant: TenantInfo) {
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                let result = try await authenticationService.switchTenant(tenant.id)
                
                await MainActor.run {
                    self.currentTenant = result.newTenant
                    self.user = result.user
                    self.isLoading = false
                    self.showTenantSwitcher = false
                    self.showSuccess = true
                    self.successMessage = "Switched to \(tenant.name)"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to switch tenant: \(error.localizedDescription)"
                }
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
    
    private func validateWebsite(_ website: String) {
        if website.isEmpty {
            websiteError = ""
        } else if !isValidURL(website) {
            websiteError = "Please enter a valid website URL"
        } else {
            websiteError = ""
        }
    }
    
    private func validateNewPassword(_ password: String) {
        if password.isEmpty {
            passwordError = ""
        } else {
            let validation = passwordValidator.validate(password)
            passwordError = validation.isValid ? "" : validation.errorMessage
        }
    }
    
    private func validateConfirmPassword(_ confirmPassword: String) {
        if confirmPassword.isEmpty {
            confirmPasswordError = ""
        } else if newPassword != confirmPassword {
            confirmPasswordError = "Passwords do not match"
        } else {
            confirmPasswordError = ""
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateEditedFields(from profile: UserProfile) {
        editedFirstName = profile.firstName
        editedLastName = profile.lastName
        editedEmail = profile.email
        editedPhoneNumber = profile.phoneNumber ?? ""
        editedBiography = profile.biography ?? ""
        editedJobTitle = profile.jobTitle ?? ""
        editedDepartment = profile.department ?? ""
        editedLocation = profile.location ?? ""
        editedWebsite = profile.website ?? ""
    }
    
    private func updatePreferences(from preferences: UserPreferences) {
        language = preferences.language
        timezone = preferences.timezone
        emailNotifications = preferences.notifications.emailNotifications
        pushNotifications = preferences.notifications.pushNotifications
        smsNotifications = preferences.notifications.smsNotifications
        securityAlerts = preferences.notifications.securityAlerts
        marketingEmails = !preferences.privacy.marketingOptOut
        profileVisibility = preferences.privacy.profileVisibility
        analyticsOptOut = preferences.privacy.analyticsOptOut
    }
    
    private func clearEditedFields() {
        editedFirstName = ""
        editedLastName = ""
        editedEmail = ""
        editedPhoneNumber = ""
        editedBiography = ""
        editedJobTitle = ""
        editedDepartment = ""
        editedLocation = ""
        editedWebsite = ""
    }
    
    private func clearErrors() {
        emailError = ""
        phoneError = ""
        websiteError = ""
        passwordError = ""
        confirmPasswordError = ""
    }
    
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString.hasPrefix("http") ? urlString : "https://\(urlString)") else {
            return false
        }
        return url.scheme != nil && url.host != nil
    }
    
    // MARK: - UI Actions
    
    func dismissError() {
        showError = false
        errorMessage = ""
    }
    
    func dismissSuccess() {
        showSuccess = false
        successMessage = ""
    }
    
    func showPhotoActions() {
        showPhotoActionSheet = true
    }
    
    func showSecurityScreen() {
        showSecuritySettings = true
    }
    
    func showSessionManagerScreen() {
        showSessionManager = true
        loadActiveSessions()
    }
    
    func showTenantSwitcherScreen() {
        showTenantSwitcher = true
        loadUserTenants()
    }
}

// MARK: - Supporting Types

struct UserProfile {
    let id: String
    let firstName: String
    let lastName: String
    let email: String
    let phoneNumber: String?
    var profileImageURL: URL?
    let biography: String?
    let jobTitle: String?
    let department: String?
    let location: String?
    let website: String?
    let createdAt: Date
    let updatedAt: Date
}

struct UserProfileUpdate {
    let firstName: String
    let lastName: String
    let email: String
    let phoneNumber: String?
    let biography: String?
    let jobTitle: String?
    let department: String?
    let location: String?
    let website: String?
}

// MARK: - Extensions

extension AuthenticationService {
    func getMFAStatus() async throws -> Bool {
        // This would check if MFA is enabled for the current user
        return false // Placeholder
    }
}

extension UserProfileServiceProtocol {
    func changePassword(currentPassword: String, newPassword: String) async throws {
        // Implementation would validate current password and update to new one
    }
    
    func exportUserData(userId: String) async throws -> URL {
        // Implementation would generate user data export
        return URL(string: "https://example.com/export")!
    }
    
    func deleteUserAccount(userId: String) async throws {
        // Implementation would handle account deletion
    }
    
    func uploadProfilePhoto(userId: String, imageData: Data, filename: String) async throws -> URL {
        // Implementation would upload photo and return URL
        return URL(string: "https://example.com/photos/\(userId)/\(filename)")!
    }
    
    func removeProfilePhoto(userId: String) async throws {
        // Implementation would remove user's profile photo
    }
}

// MARK: - Preview Support

extension ProfileViewModel {
    static var preview: ProfileViewModel {
        let mockAuth = ServiceContainer.shared.resolve(AuthenticationServiceProtocol.self)!
        let mockProfile = ServiceContainer.shared.resolve(UserProfileServiceProtocol.self)!
        let mockBiometric = ServiceContainer.shared.resolve(BiometricAuthServiceProtocol.self)!
        let mockSession = ServiceContainer.shared.resolve(SessionManagementServiceProtocol.self)!
        let mockConsent = ServiceContainer.shared.resolve(ConsentManagementServiceProtocol.self)!
        
        return ProfileViewModel(
            authenticationService: mockAuth,
            userProfileService: mockProfile,
            biometricService: mockBiometric,
            sessionService: mockSession,
            consentService: mockConsent
        )
    }
}