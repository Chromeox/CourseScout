import Foundation
import SwiftUI
import Combine
import LocalAuthentication
import os.log

// MARK: - Biometric Setup View Model

@MainActor
final class BiometricSetupViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var showSuccess: Bool = false
    @Published var successMessage: String = ""
    
    // MARK: - Biometric Availability
    
    @Published var biometricAvailability: BiometricAvailability?
    @Published var biometryType: LABiometryType = .none
    @Published var isAvailable: Bool = false
    @Published var requiresEnrollment: Bool = false
    @Published var hasSystemPasscode: Bool = false
    
    // MARK: - Setup Flow
    
    @Published var currentStep: SetupStep = .introduction
    @Published var isEnabled: Bool = false
    @Published var showPermissionRequest: Bool = false
    @Published var permissionGranted: Bool = false
    @Published var showBiometricPrompt: Bool = false
    @Published var setupComplete: Bool = false
    
    // MARK: - Configuration
    
    @Published var enableForLogin: Bool = true
    @Published var enableForTransactions: Bool = true
    @Published var enableForSettings: Bool = false
    @Published var requireAdditionalAuth: Bool = false
    @Published var fallbackToPasscode: Bool = true
    
    // MARK: - Testing & Validation
    
    @Published var isTestingBiometrics: Bool = false
    @Published var testResult: BiometricTestResult?
    @Published var showTestResults: Bool = false
    
    // MARK: - White Label Customization
    
    @Published var customBiometricPrompts: BiometricPromptConfiguration?
    @Published var tenantSecurityPolicy: TenantSecurityPolicy?
    
    // MARK: - Dependencies
    
    private let biometricService: BiometricAuthServiceProtocol
    private let securityService: SecurityServiceProtocol
    private let tenantConfigurationService: TenantConfigurationServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderApp", category: "BiometricSetupViewModel")
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let hapticFeedback = UINotificationFeedbackGenerator()
    
    // MARK: - Computed Properties
    
    var biometricTypeDisplayName: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Biometric Authentication"
        }
    }
    
    var biometricIcon: String {
        switch biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        default:
            return "person.badge.key.fill"
        }
    }
    
    var setupSteps: [SetupStep] {
        return [.introduction, .availability, .permissions, .configuration, .testing, .completion]
    }
    
    var currentStepIndex: Int {
        return setupSteps.firstIndex(of: currentStep) ?? 0
    }
    
    var progressPercentage: Double {
        return Double(currentStepIndex + 1) / Double(setupSteps.count)
    }
    
    var canProceed: Bool {
        switch currentStep {
        case .introduction:
            return true
        case .availability:
            return isAvailable
        case .permissions:
            return permissionGranted
        case .configuration:
            return true
        case .testing:
            return testResult?.success == true
        case .completion:
            return false
        }
    }
    
    var securityLevelDescription: String {
        let level = calculateSecurityLevel()
        switch level {
        case .basic:
            return "Basic security with biometric authentication for login only"
        case .enhanced:
            return "Enhanced security with biometric authentication for multiple actions"
        case .maximum:
            return "Maximum security with biometric authentication and additional verification"
        }
    }
    
    // MARK: - Initialization
    
    init(
        biometricService: BiometricAuthServiceProtocol,
        securityService: SecurityServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol
    ) {
        self.biometricService = biometricService
        self.securityService = securityService
        self.tenantConfigurationService = tenantConfigurationService
        
        setupObservers()
        checkInitialAvailability()
        loadTenantConfiguration()
        logger.info("BiometricSetupViewModel initialized")
    }
    
    // MARK: - Setup Methods
    
    private func setupObservers() {
        // Monitor biometric availability changes
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.checkBiometricAvailability()
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkInitialAvailability() {
        Task {
            await checkBiometricAvailability()
        }
    }
    
    private func loadTenantConfiguration() {
        Task {
            do {
                if let tenant = await tenantConfigurationService.getCurrentTenant() {
                    let prompts = try await tenantConfigurationService.getBiometricPromptConfiguration(tenantId: tenant.id)
                    let policy = try await tenantConfigurationService.getTenantSecurityPolicy(tenantId: tenant.id)
                    
                    await MainActor.run {
                        self.customBiometricPrompts = prompts
                        self.tenantSecurityPolicy = policy
                        self.applyTenantSecurityPolicy(policy)
                    }
                }
            } catch {
                logger.error("Failed to load tenant configuration: \(error.localizedDescription)")
            }
        }
    }
    
    private func applyTenantSecurityPolicy(_ policy: TenantSecurityPolicy) {
        // Apply tenant-specific security requirements
        if policy.requiresBiometricForLogin {
            enableForLogin = true
        }
        
        if policy.requiresBiometricForTransactions {
            enableForTransactions = true
        }
        
        if policy.requiresAdditionalAuthForSensitiveActions {
            requireAdditionalAuth = true
        }
        
        fallbackToPasscode = policy.allowsPasscodeFallback
    }
    
    // MARK: - Biometric Availability
    
    func checkBiometricAvailability() async {
        await MainActor.run {
            self.isLoading = true
        }
        
        let availability = await biometricService.checkBiometricAvailability()
        
        await MainActor.run {
            self.biometricAvailability = availability
            self.biometryType = availability.biometryType
            self.isAvailable = availability.isAvailable
            self.requiresEnrollment = availability.requiresEnrollment
            self.hasSystemPasscode = availability.hasSystemPasscode
            self.isLoading = false
            
            logger.info("Biometric availability checked: \(availability.isAvailable ? "Available" : "Not available")")
        }
        
        // Auto-advance if on availability step
        if currentStep == .availability && isAvailable {
            await MainActor.run {
                self.proceedToNextStep()
            }
        }
    }
    
    // MARK: - Setup Flow Navigation
    
    func proceedToNextStep() {
        let currentIndex = currentStepIndex
        if currentIndex < setupSteps.count - 1 {
            currentStep = setupSteps[currentIndex + 1]
            handleStepTransition()
        }
    }
    
    func goToPreviousStep() {
        let currentIndex = currentStepIndex
        if currentIndex > 0 {
            currentStep = setupSteps[currentIndex - 1]
        }
    }
    
    func skipToStep(_ step: SetupStep) {
        currentStep = step
        handleStepTransition()
    }
    
    private func handleStepTransition() {
        switch currentStep {
        case .availability:
            Task {
                await checkBiometricAvailability()
            }
        case .permissions:
            requestBiometricPermission()
        case .testing:
            // Auto-start testing if user has proceeded this far
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.testBiometricAuthentication()
            }
        default:
            break
        }
    }
    
    // MARK: - Permission Handling
    
    func requestBiometricPermission() {
        showPermissionRequest = true
    }
    
    func grantPermission() {
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showPermissionRequest = false
            }
            
            do {
                // Test biometric authentication to establish permission
                let success = try await biometricService.authenticateUser(
                    reason: customBiometricPrompts?.setupReason ?? "Enable biometric authentication for secure access",
                    fallbackTitle: "Use Passcode"
                )
                
                await MainActor.run {
                    self.permissionGranted = success
                    self.isLoading = false
                    
                    if success {
                        self.hapticFeedback.notificationOccurred(.success)
                        self.showSuccess = true
                        self.successMessage = "Permission granted successfully"
                        
                        // Auto-advance after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.dismissSuccess()
                            self.proceedToNextStep()
                        }
                    } else {
                        self.showError = true
                        self.errorMessage = "Permission is required to use biometric authentication"
                    }
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to grant permission: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func denyPermission() {
        permissionGranted = false
        showPermissionRequest = false
        showError = true
        errorMessage = "Biometric authentication requires permission to access your device's security features"
    }
    
    // MARK: - Configuration
    
    func updateConfiguration() {
        // Configuration is updated in real-time through Published properties
        logger.debug("Biometric configuration updated")
    }
    
    func resetToDefaults() {
        enableForLogin = true
        enableForTransactions = true
        enableForSettings = false
        requireAdditionalAuth = false
        fallbackToPasscode = true
    }
    
    // MARK: - Testing
    
    func testBiometricAuthentication() {
        Task {
            await MainActor.run {
                self.isTestingBiometrics = true
                self.testResult = nil
            }
            
            do {
                let startTime = Date()
                let success = try await biometricService.authenticateUser(
                    reason: customBiometricPrompts?.testReason ?? "Test biometric authentication",
                    fallbackTitle: "Use Passcode"
                )
                let duration = Date().timeIntervalSince(startTime)
                
                let result = BiometricTestResult(
                    success: success,
                    duration: duration,
                    biometryType: biometryType,
                    timestamp: Date(),
                    errorMessage: success ? nil : "Authentication failed"
                )
                
                await MainActor.run {
                    self.testResult = result
                    self.isTestingBiometrics = false
                    self.showTestResults = true
                    
                    if success {
                        self.hapticFeedback.notificationOccurred(.success)
                    } else {
                        self.hapticFeedback.notificationOccurred(.error)
                    }
                }
                
            } catch {
                let result = BiometricTestResult(
                    success: false,
                    duration: 0,
                    biometryType: biometryType,
                    timestamp: Date(),
                    errorMessage: error.localizedDescription
                )
                
                await MainActor.run {
                    self.testResult = result
                    self.isTestingBiometrics = false
                    self.showTestResults = true
                    self.hapticFeedback.notificationOccurred(.error)
                }
            }
        }
    }
    
    func retryTest() {
        showTestResults = false
        testResult = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.testBiometricAuthentication()
        }
    }
    
    // MARK: - Setup Completion
    
    func completeBiometricSetup() {
        guard permissionGranted, testResult?.success == true else {
            showError = true
            errorMessage = "Please complete all setup steps before finishing"
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                // Save biometric configuration
                let configuration = BiometricConfiguration(
                    enabledForLogin: enableForLogin,
                    enabledForTransactions: enableForTransactions,
                    enabledForSettings: enableForSettings,
                    requiresAdditionalAuth: requireAdditionalAuth,
                    allowsPasscodeFallback: fallbackToPasscode,
                    biometryType: biometryType
                )
                
                try await biometricService.saveBiometricConfiguration(configuration)
                
                // Enable biometric authentication
                let success = try await biometricService.enableBiometricAuthentication()
                
                await MainActor.run {
                    self.isEnabled = success
                    self.setupComplete = true
                    self.currentStep = .completion
                    self.isLoading = false
                    
                    if success {
                        self.hapticFeedback.notificationOccurred(.success)
                        self.showSuccess = true
                        self.successMessage = "Biometric authentication setup complete!"
                    } else {
                        self.showError = true
                        self.errorMessage = "Failed to enable biometric authentication"
                    }
                }
                
                logger.info("Biometric setup completed successfully")
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to complete setup: \(error.localizedDescription)"
                }
                
                logger.error("Biometric setup failed: \(error.localizedDescription)")
            }
        }
    }
    
    func skipBiometricSetup() {
        setupComplete = true
        currentStep = .completion
        showSuccess = true
        successMessage = "You can enable biometric authentication later in Settings"
    }
    
    // MARK: - Utility Methods
    
    private func calculateSecurityLevel() -> SecurityLevel {
        var score = 0
        
        if enableForLogin { score += 1 }
        if enableForTransactions { score += 2 }
        if enableForSettings { score += 1 }
        if requireAdditionalAuth { score += 2 }
        if !fallbackToPasscode { score += 1 }
        
        switch score {
        case 0...2: return .basic
        case 3...4: return .enhanced
        default: return .maximum
        }
    }
    
    func getBiometricSetupSummary() -> BiometricSetupSummary {
        return BiometricSetupSummary(
            biometryType: biometryType,
            isEnabled: isEnabled,
            configuration: BiometricConfiguration(
                enabledForLogin: enableForLogin,
                enabledForTransactions: enableForTransactions,
                enabledForSettings: enableForSettings,
                requiresAdditionalAuth: requireAdditionalAuth,
                allowsPasscodeFallback: fallbackToPasscode,
                biometryType: biometryType
            ),
            securityLevel: calculateSecurityLevel(),
            setupDate: Date()
        )
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
    
    func dismissTestResults() {
        showTestResults = false
    }
    
    func restartSetup() {
        currentStep = .introduction
        setupComplete = false
        isEnabled = false
        permissionGranted = false
        testResult = nil
        resetToDefaults()
    }
}

// MARK: - Supporting Types

enum SetupStep: CaseIterable {
    case introduction
    case availability
    case permissions
    case configuration
    case testing
    case completion
    
    var title: String {
        switch self {
        case .introduction: return "Welcome"
        case .availability: return "Device Check"
        case .permissions: return "Permissions"
        case .configuration: return "Configuration"
        case .testing: return "Testing"
        case .completion: return "Complete"
        }
    }
    
    var description: String {
        switch self {
        case .introduction: return "Set up biometric authentication for secure access"
        case .availability: return "Checking device capabilities"
        case .permissions: return "Grant permission to use biometric features"
        case .configuration: return "Configure your security preferences"
        case .testing: return "Test biometric authentication"
        case .completion: return "Setup complete!"
        }
    }
    
    var icon: String {
        switch self {
        case .introduction: return "hand.wave.fill"
        case .availability: return "checkmark.shield.fill"
        case .permissions: return "key.fill"
        case .configuration: return "gear"
        case .testing: return "testtube.2"
        case .completion: return "checkmark.circle.fill"
        }
    }
}

struct BiometricTestResult {
    let success: Bool
    let duration: TimeInterval
    let biometryType: LABiometryType
    let timestamp: Date
    let errorMessage: String?
    
    var formattedDuration: String {
        return String(format: "%.2f seconds", duration)
    }
    
    var statusDescription: String {
        return success ? "✅ Test Passed" : "❌ Test Failed"
    }
}

struct BiometricConfiguration {
    let enabledForLogin: Bool
    let enabledForTransactions: Bool
    let enabledForSettings: Bool
    let requiresAdditionalAuth: Bool
    let allowsPasscodeFallback: Bool
    let biometryType: LABiometryType
}

struct BiometricSetupSummary {
    let biometryType: LABiometryType
    let isEnabled: Bool
    let configuration: BiometricConfiguration
    let securityLevel: SecurityLevel
    let setupDate: Date
}

struct BiometricPromptConfiguration {
    let setupReason: String
    let testReason: String
    let loginReason: String
    let transactionReason: String
    let settingsReason: String
    let fallbackTitle: String
    let cancelTitle: String
}

struct TenantSecurityPolicy {
    let requiresBiometricForLogin: Bool
    let requiresBiometricForTransactions: Bool
    let requiresAdditionalAuthForSensitiveActions: Bool
    let allowsPasscodeFallback: Bool
    let minimumSecurityLevel: SecurityLevel
    let allowsBiometricSkip: Bool
}

enum SecurityLevel: Int, CaseIterable {
    case basic = 1
    case enhanced = 2
    case maximum = 3
    
    var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .enhanced: return "Enhanced"
        case .maximum: return "Maximum"
        }
    }
    
    var color: Color {
        switch self {
        case .basic: return .orange
        case .enhanced: return .blue
        case .maximum: return .green
        }
    }
}

// MARK: - Extensions

extension BiometricAuthServiceProtocol {
    func saveBiometricConfiguration(_ configuration: BiometricConfiguration) async throws {
        // Implementation would save configuration to secure storage
    }
}

extension TenantConfigurationServiceProtocol {
    func getBiometricPromptConfiguration(tenantId: String) async throws -> BiometricPromptConfiguration {
        // Implementation would fetch tenant-specific prompts
        return BiometricPromptConfiguration(
            setupReason: "Enable biometric authentication for your golf club account",
            testReason: "Test biometric authentication",
            loginReason: "Sign in to your golf club account",
            transactionReason: "Authorize this transaction",
            settingsReason: "Access security settings",
            fallbackTitle: "Use Passcode",
            cancelTitle: "Cancel"
        )
    }
    
    func getTenantSecurityPolicy(tenantId: String) async throws -> TenantSecurityPolicy {
        // Implementation would fetch tenant security requirements
        return TenantSecurityPolicy(
            requiresBiometricForLogin: false,
            requiresBiometricForTransactions: true,
            requiresAdditionalAuthForSensitiveActions: false,
            allowsPasscodeFallback: true,
            minimumSecurityLevel: .basic,
            allowsBiometricSkip: true
        )
    }
}

// MARK: - Preview Support

extension BiometricSetupViewModel {
    static var preview: BiometricSetupViewModel {
        let mockBiometric = ServiceContainer.shared.resolve(BiometricAuthServiceProtocol.self)!
        let mockSecurity = ServiceContainer.shared.resolve(SecurityServiceProtocol.self)!
        let mockTenant = ServiceContainer.shared.resolve(TenantConfigurationServiceProtocol.self)!
        
        return BiometricSetupViewModel(
            biometricService: mockBiometric,
            securityService: mockSecurity,
            tenantConfigurationService: mockTenant
        )
    }
}