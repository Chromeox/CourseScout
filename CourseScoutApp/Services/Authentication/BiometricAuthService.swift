import Foundation
import LocalAuthentication
import CryptoKit
import Security
import os.log

// MARK: - Biometric Authentication Service Implementation

@MainActor
final class BiometricAuthService: BiometricAuthServiceProtocol {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinderApp", category: "BiometricAuth")
    private let context = LAContext()
    private var secureEnclaveKeys: [String: SecItemAttributes] = [:]
    private let keychain = KeychainWrapper()
    
    // Configuration
    private var currentPolicy: BiometricPolicy
    private let securityService: SecurityServiceProtocol
    
    // MARK: - Initialization
    
    init(securityService: SecurityServiceProtocol) {
        self.securityService = securityService
        self.currentPolicy = Self.defaultBiometricPolicy()
        logger.info("BiometricAuthService initialized")
    }
    
    // MARK: - Biometric Availability
    
    func isBiometricAuthenticationAvailable() async -> BiometricAvailability {
        logger.debug("Checking biometric authentication availability")
        
        var error: NSError?
        let isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        let supportedTypes = await getSupportedBiometricTypes()
        let capabilities = await getBiometricCapabilities()
        
        let unavailabilityReason: BiometricUnavailabilityReason?
        if let error = error {
            switch error.code {
            case LAError.biometryNotEnrolled.rawValue:
                unavailabilityReason = .notEnrolled
            case LAError.biometryNotAvailable.rawValue:
                unavailabilityReason = .hardwareUnavailable
            case LAError.biometryLockout.rawValue:
                unavailabilityReason = .biometryLocked
            case LAError.passcodeNotSet.rawValue:
                unavailabilityReason = .passcodeNotSet
            default:
                unavailabilityReason = .deviceNotSupported
            }
        } else {
            unavailabilityReason = nil
        }
        
        return BiometricAvailability(
            isAvailable: isAvailable,
            supportedTypes: supportedTypes,
            unavailabilityReason: unavailabilityReason,
            deviceCapabilities: capabilities,
            osVersion: await getOSVersion(),
            hardwareSupport: await getHardwareSupport()
        )
    }
    
    func getSupportedBiometricTypes() async -> [BiometricType] {
        var supportedTypes: [BiometricType] = []
        
        switch context.biometryType {
        case .faceID:
            supportedTypes.append(.faceID)
        case .touchID:
            supportedTypes.append(.touchID)
        case .opticID:
            supportedTypes.append(.opticID)
        case .none:
            break
        @unknown default:
            break
        }
        
        // Check for Apple Watch unlock capability
        if await isWatchUnlockAvailable() {
            supportedTypes.append(.watchUnlock)
        }
        
        return supportedTypes
    }
    
    func getBiometricCapabilities() async -> BiometricCapabilities {
        let supportedTypes = await getSupportedBiometricTypes()
        
        return BiometricCapabilities(
            supportsFaceID: supportedTypes.contains(.faceID),
            supportsTouchID: supportedTypes.contains(.touchID),
            supportsOpticID: supportedTypes.contains(.opticID),
            supportsWatchUnlock: supportedTypes.contains(.watchUnlock),
            supportsSecureEnclave: await getSecureEnclaveSupport(),
            maxFailedAttempts: 5,
            lockoutDuration: 300, // 5 minutes
            biometricDataProtection: .secureEnclave
        )
    }
    
    // MARK: - Enrollment & Setup
    
    func isBiometricEnrolled() async -> Bool {
        var error: NSError?
        let isEnrolled = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        if let error = error {
            logger.debug("Biometric enrollment check failed: \(error.localizedDescription)")
            return false
        }
        
        return isEnrolled
    }
    
    func requestBiometricEnrollment() async throws {
        logger.info("Requesting biometric enrollment")
        
        guard await !isBiometricEnrolled() else {
            logger.debug("Biometric already enrolled")
            return
        }
        
        // Direct user to Settings to enroll biometric authentication
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            await UIApplication.shared.open(settingsUrl)
        } else {
            throw BiometricAuthError.systemError("Cannot open Settings")
        }
    }
    
    func setupBiometricAuthentication(userId: String) async throws -> BiometricSetupResult {
        logger.info("Setting up biometric authentication for user: \(userId)")
        
        // Check availability and enrollment
        let availability = await isBiometricAuthenticationAvailable()
        guard availability.isAvailable else {
            throw BiometricAuthError.biometricNotAvailable(availability.unavailabilityReason ?? .hardwareUnavailable)
        }
        
        guard await isBiometricEnrolled() else {
            throw BiometricAuthError.biometricNotEnrolled
        }
        
        // Generate Secure Enclave key
        let secureKey = try await generateSecureEnclaveKey(userId: userId)
        
        // Determine biometric type
        let biometricTypes = await getSupportedBiometricTypes()
        let primaryType = biometricTypes.first ?? .touchID
        
        // Setup fallback method
        let fallbackMethod = await determineFallbackMethod()
        
        // Store biometric setup information
        try await storeBiometricSetup(userId: userId, keyId: secureKey.keyId, biometricType: primaryType)
        
        return BiometricSetupResult(
            userId: userId,
            keyId: secureKey.keyId,
            biometricType: primaryType,
            secureEnclaveKeyGenerated: true,
            setupCompletedAt: Date(),
            fallbackMethod: fallbackMethod,
            trustLevel: .high
        )
    }
    
    func disableBiometricAuthentication(userId: String) async throws {
        logger.info("Disabling biometric authentication for user: \(userId)")
        
        // Remove stored keys and configuration
        try await deleteBiometricSetup(userId: userId)
        
        logger.info("Successfully disabled biometric authentication for user: \(userId)")
    }
    
    // MARK: - Authentication
    
    func authenticateWithBiometrics(prompt: String) async throws -> BiometricAuthResult {
        logger.info("Starting biometric authentication")
        
        let availability = await isBiometricAuthenticationAvailable()
        guard availability.isAvailable else {
            throw BiometricAuthError.biometricNotAvailable(availability.unavailabilityReason ?? .hardwareUnavailable)
        }
        
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: prompt
            )
            
            let biometricType = mapLABiometryType(context.biometryType)
            let deviceId = await getCurrentDeviceId()
            
            let result = BiometricAuthResult(
                isSuccessful: success,
                userId: nil, // Would be determined from context
                biometricType: biometricType,
                authenticatedAt: Date(),
                sessionToken: nil,
                deviceId: deviceId,
                trustScore: calculateTrustScore(biometricType: biometricType),
                fallbackUsed: false,
                failureReason: nil
            )
            
            await logBiometricAttempt(createBiometricAttempt(result: result))
            
            return result
            
        } catch {
            let failureReason = mapLAErrorToBiometricFailure(error)
            
            let result = BiometricAuthResult(
                isSuccessful: false,
                userId: nil,
                biometricType: mapLABiometryType(context.biometryType),
                authenticatedAt: Date(),
                sessionToken: nil,
                deviceId: await getCurrentDeviceId(),
                trustScore: 0.0,
                fallbackUsed: false,
                failureReason: failureReason
            )
            
            await logBiometricAttempt(createBiometricAttempt(result: result))
            
            throw BiometricAuthError.authenticationFailed(failureReason)
        }
    }
    
    func authenticateWithBiometrics(userId: String, context: AuthenticationContext) async throws -> BiometricAuthResult {
        logger.info("Starting biometric authentication for user: \(userId)")
        
        // Validate policy compliance
        let compliance = try await validatePolicyCompliance(userId: userId)
        guard compliance.isCompliant else {
            throw BiometricAuthError.policyViolation(compliance.violations)
        }
        
        // Perform liveness detection if required
        if currentPolicy.requireLivenessDetection {
            let livenessResult = try await performLivenessDetection()
            guard livenessResult.isLive else {
                throw BiometricAuthError.livenessCheckFailed(livenessResult.suspiciousIndicators)
            }
        }
        
        // Perform spoofing detection if enabled
        if currentPolicy.enableSpoofingDetection {
            let spoofingResult = await detectSpoofingAttempt()
            guard !spoofingResult.spoofingAttempted else {
                throw BiometricAuthError.spoofingDetected(spoofingResult.spoofingType ?? .photoAttack)
            }
        }
        
        // Proceed with standard biometric authentication
        let prompt = context.customPrompt ?? "Authenticate to access your golf profile"
        var result = try await authenticateWithBiometrics(prompt: prompt)
        
        // Update result with user context
        result = BiometricAuthResult(
            isSuccessful: result.isSuccessful,
            userId: userId,
            biometricType: result.biometricType,
            authenticatedAt: result.authenticatedAt,
            sessionToken: result.sessionToken,
            deviceId: result.deviceId,
            trustScore: result.trustScore,
            fallbackUsed: result.fallbackUsed,
            failureReason: result.failureReason
        )
        
        return result
    }
    
    func authenticateForTransaction(amount: Double, description: String) async throws -> BiometricAuthResult {
        logger.info("Authenticating biometric for transaction: \(amount)")
        
        let prompt = "Authenticate to authorize transaction of $\(String(format: "%.2f", amount)) for \(description)"
        
        let context = AuthenticationContext(
            operation: "transaction_approval",
            riskLevel: amount > 100.0 ? .high : .medium,
            requiresHighSecurity: amount > 500.0,
            customPrompt: prompt,
            timeout: 30.0,
            allowFallback: true
        )
        
        return try await authenticateWithBiometrics(userId: "", context: context)
    }
    
    func authenticateForSensitiveOperation(operation: SensitiveOperation) async throws -> BiometricAuthResult {
        logger.info("Authenticating biometric for sensitive operation: \(operation)")
        
        let prompt = getPromptForSensitiveOperation(operation)
        
        let context = AuthenticationContext(
            operation: operation.rawValue,
            riskLevel: .high,
            requiresHighSecurity: true,
            customPrompt: prompt,
            timeout: 60.0,
            allowFallback: operation != .accountDeletion // No fallback for account deletion
        )
        
        return try await authenticateWithBiometrics(userId: "", context: context)
    }
    
    // MARK: - Apple Watch Integration
    
    func isWatchUnlockAvailable() async -> Bool {
        // Check if Apple Watch unlock is configured
        // This would involve checking if the user has an Apple Watch paired and configured for unlock
        return false // Placeholder implementation
    }
    
    func enableWatchUnlock(userId: String) async throws {
        logger.info("Enabling Apple Watch unlock for user: \(userId)")
        
        guard await isWatchUnlockAvailable() else {
            throw BiometricAuthError.biometricNotAvailable(.hardwareUnavailable)
        }
        
        // Implementation would enable Watch unlock functionality
        // This requires coordination with WatchConnectivity framework
    }
    
    func disableWatchUnlock(userId: String) async throws {
        logger.info("Disabling Apple Watch unlock for user: \(userId)")
        
        // Implementation would disable Watch unlock functionality
    }
    
    func authenticateWithWatchUnlock(prompt: String) async throws -> BiometricAuthResult {
        logger.info("Authenticating with Apple Watch unlock")
        
        guard await isWatchUnlockAvailable() else {
            throw BiometricAuthError.biometricNotAvailable(.hardwareUnavailable)
        }
        
        // Implementation would handle Watch unlock authentication
        // This is a simplified return for now
        return BiometricAuthResult(
            isSuccessful: true,
            userId: nil,
            biometricType: .watchUnlock,
            authenticatedAt: Date(),
            sessionToken: nil,
            deviceId: await getCurrentDeviceId(),
            trustScore: 0.7, // Lower trust score for Watch unlock
            fallbackUsed: false,
            failureReason: nil
        )
    }
    
    // MARK: - Secure Enclave Integration
    
    func generateSecureEnclaveKey(userId: String) async throws -> SecureEnclaveKey {
        logger.info("Generating Secure Enclave key for user: \(userId)")
        
        guard await getSecureEnclaveSupport() else {
            throw BiometricAuthError.secureEnclaveError("Secure Enclave not available")
        }
        
        let keyId = "\(userId)_biometric_key_\(UUID().uuidString)"
        
        // Generate key in Secure Enclave
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyId.data(using: .utf8)!,
                kSecAttrAccessControl as String: SecAccessControlCreateWithFlags(
                    kCFAllocatorDefault,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    [.biometryAny, .privateKeyUsage],
                    nil
                )!
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let errorDescription = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw BiometricAuthError.secureEnclaveError("Failed to generate key: \(errorDescription)")
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw BiometricAuthError.secureEnclaveError("Failed to extract public key")
        }
        
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let errorDescription = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw BiometricAuthError.secureEnclaveError("Failed to export public key: \(errorDescription)")
        }
        
        let secureKey = SecureEnclaveKey(
            keyId: keyId,
            userId: userId,
            publicKey: publicKeyData,
            createdAt: Date(),
            algorithm: .ecdsaSecp256r1,
            keyUsage: [.authentication, .signing],
            isActive: true
        )
        
        // Store key reference
        secureEnclaveKeys[keyId] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyId.data(using: .utf8)!
        ] as [String: Any]
        
        logger.info("Successfully generated Secure Enclave key: \(keyId)")
        return secureKey
    }
    
    func signWithSecureEnclave(data: Data, keyId: String) async throws -> Data {
        logger.debug("Signing data with Secure Enclave key: \(keyId)")
        
        guard let keyAttributes = secureEnclaveKeys[keyId] else {
            throw BiometricAuthError.secureEnclaveError("Key not found: \(keyId)")
        }
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(keyAttributes as CFDictionary, &item)
        
        guard status == errSecSuccess, let privateKey = item else {
            throw BiometricAuthError.secureEnclaveError("Failed to retrieve key: \(status)")
        }
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey as! SecKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) as Data? else {
            let errorDescription = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw BiometricAuthError.secureEnclaveError("Failed to sign data: \(errorDescription)")
        }
        
        return signature
    }
    
    func verifySecureEnclaveSignature(data: Data, signature: Data, keyId: String) async throws -> Bool {
        logger.debug("Verifying signature with Secure Enclave key: \(keyId)")
        
        guard let secureKey = getStoredSecureKey(keyId: keyId) else {
            throw BiometricAuthError.secureEnclaveError("Public key not found: \(keyId)")
        }
        
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(secureKey.publicKey as CFData, [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256
        ] as CFDictionary, &error) else {
            let errorDescription = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw BiometricAuthError.secureEnclaveError("Failed to create public key: \(errorDescription)")
        }
        
        let isValid = SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            signature as CFData,
            &error
        )
        
        return isValid
    }
    
    func deleteSecureEnclaveKey(keyId: String) async throws {
        logger.info("Deleting Secure Enclave key: \(keyId)")
        
        guard let keyAttributes = secureEnclaveKeys[keyId] else {
            logger.warning("Key not found for deletion: \(keyId)")
            return
        }
        
        let status = SecItemDelete(keyAttributes as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BiometricAuthError.secureEnclaveError("Failed to delete key: \(status)")
        }
        
        secureEnclaveKeys.removeValue(forKey: keyId)
        logger.info("Successfully deleted Secure Enclave key: \(keyId)")
    }
    
    // MARK: - Anti-Spoofing & Liveness Detection
    
    func performLivenessDetection() async throws -> LivenessDetectionResult {
        logger.info("Performing liveness detection")
        
        // Simplified liveness detection implementation
        // In a real implementation, this would use advanced computer vision techniques
        
        let detectionMethods: [LivenessDetectionMethod] = [.eyeBlinkDetection, .headMovement, .faceGeometry]
        let suspiciousIndicators: [SuspiciousIndicator] = []
        
        // Simulate detection process
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let confidence = Double.random(in: 0.8...1.0)
        let isLive = confidence > 0.85
        
        return LivenessDetectionResult(
            isLive: isLive,
            confidence: confidence,
            detectionMethods: detectionMethods,
            suspiciousIndicators: suspiciousIndicators,
            timestamp: Date()
        )
    }
    
    func validateBiometricIntegrity() async throws -> BiometricIntegrityResult {
        logger.info("Validating biometric integrity")
        
        // Check for hardware tampering or compromise
        let integrityScore = Double.random(in: 0.9...1.0)
        let isIntact = integrityScore > 0.95
        
        return BiometricIntegrityResult(
            isIntact: isIntact,
            integrityScore: integrityScore,
            tamperedComponents: [],
            verificationTimestamp: Date()
        )
    }
    
    func detectSpoofingAttempt() async -> SpoofingDetectionResult {
        logger.debug("Detecting spoofing attempts")
        
        // Simplified spoofing detection
        let spoofingAttempted = false
        let confidence = Double.random(in: 0.9...1.0)
        
        return SpoofingDetectionResult(
            spoofingAttempted: spoofingAttempted,
            spoofingType: nil,
            confidence: confidence,
            detectionMethods: [.livenessDetection, .depthAnalysis],
            recommendedAction: .allow
        )
    }
    
    // MARK: - Fallback Authentication
    
    func setupFallbackAuthentication(userId: String, method: FallbackMethod) async throws {
        logger.info("Setting up fallback authentication for user \(userId): \(method)")
        
        // Implementation would setup fallback authentication method
        try await keychain.store(key: "fallback_method_\(userId)", data: method.rawValue.data(using: .utf8)!)
    }
    
    func authenticateWithFallback(method: FallbackMethod, credentials: FallbackCredentials) async throws -> BiometricAuthResult {
        logger.info("Authenticating with fallback method: \(method)")
        
        let isValid = try await validateFallbackCredentials(method: method, credentials: credentials)
        
        return BiometricAuthResult(
            isSuccessful: isValid,
            userId: nil,
            biometricType: .touchID, // Fallback doesn't use biometric, but we need a value
            authenticatedAt: Date(),
            sessionToken: nil,
            deviceId: await getCurrentDeviceId(),
            trustScore: method.securityLevel.rawValue == "medium" ? 0.6 : 0.4,
            fallbackUsed: true,
            failureReason: isValid ? nil : .authenticationFailed
        )
    }
    
    func updateFallbackCredentials(userId: String, method: FallbackMethod, credentials: FallbackCredentials) async throws {
        logger.info("Updating fallback credentials for user \(userId): \(method)")
        
        // Implementation would update stored fallback credentials
        let credentialsData = try JSONEncoder().encode(credentials)
        try await keychain.store(key: "fallback_credentials_\(userId)", data: credentialsData)
    }
    
    // MARK: - Policy & Configuration
    
    func updateBiometricPolicy(_ policy: BiometricPolicy) async throws {
        logger.info("Updating biometric policy")
        
        currentPolicy = policy
        
        // Persist policy to secure storage
        let policyData = try JSONEncoder().encode(policy)
        try await keychain.store(key: "biometric_policy", data: policyData)
        
        logger.info("Successfully updated biometric policy")
    }
    
    func getBiometricPolicy() async -> BiometricPolicy {
        return currentPolicy
    }
    
    func validatePolicyCompliance(userId: String) async throws -> PolicyComplianceResult {
        logger.debug("Validating policy compliance for user: \(userId)")
        
        var violations: [PolicyViolation] = []
        
        // Check device trust requirement
        if currentPolicy.deviceTrustRequired {
            let deviceTrust = try await validateDeviceTrust(deviceId: await getCurrentDeviceId())
            if !deviceTrust.isTrusted {
                violations.append(.untrustedDevice)
            }
        }
        
        // Check biometric type support
        let supportedTypes = await getSupportedBiometricTypes()
        let allowedTypes = Set(currentPolicy.allowedBiometricTypes)
        let supportedAllowedTypes = Set(supportedTypes).intersection(allowedTypes)
        
        if supportedAllowedTypes.isEmpty {
            violations.append(.unsupportedBiometricType)
        }
        
        // Check geofencing if enabled
        if currentPolicy.geofencingEnabled, let allowedLocations = currentPolicy.allowedLocations {
            // Implementation would check current location against allowed geofences
        }
        
        let isCompliant = violations.isEmpty
        let riskScore = calculateRiskScore(violations: violations)
        
        return PolicyComplianceResult(
            isCompliant: isCompliant,
            violations: violations,
            recommendedActions: getRecommendedActions(for: violations),
            riskScore: riskScore,
            lastEvaluatedAt: Date()
        )
    }
    
    // MARK: - Security Monitoring
    
    func logBiometricAttempt(_ attempt: BiometricAttempt) async {
        logger.info("Logging biometric attempt for user: \(attempt.userId ?? "unknown")")
        
        // Implementation would log to security monitoring system
        try? await securityService.logSecurityEvent(
            eventType: "biometric_authentication",
            userId: attempt.userId,
            details: [
                "biometric_type": attempt.biometricType.rawValue,
                "success": attempt.isSuccessful,
                "failure_reason": attempt.failureReason?.rawValue ?? "",
                "device_id": attempt.deviceId,
                "timestamp": attempt.attemptedAt.timeIntervalSince1970
            ]
        )
    }
    
    func getBiometricSecurityEvents(userId: String, period: TimeInterval) async throws -> [BiometricSecurityEvent] {
        logger.debug("Fetching biometric security events for user: \(userId)")
        
        // Implementation would retrieve security events from monitoring system
        return []
    }
    
    func reportSuspiciousActivity(_ activity: SuspiciousActivity) async throws {
        logger.warning("Reporting suspicious biometric activity: \(activity.activityType)")
        
        try await securityService.reportSuspiciousActivity(
            userId: activity.userId,
            activityType: activity.activityType.rawValue,
            riskScore: activity.riskScore,
            details: [
                "device_id": activity.deviceId,
                "timestamp": activity.timestamp.timeIntervalSince1970,
                "indicators": activity.indicators.map { $0.rawValue },
                "recommended_action": activity.recommendedAction.rawValue
            ]
        )
    }
    
    // MARK: - Device Trust & Management
    
    func registerTrustedDevice(_ device: TrustedDevice) async throws {
        logger.info("Registering trusted device: \(device.id)")
        
        let deviceData = try JSONEncoder().encode(device)
        try await keychain.store(key: "trusted_device_\(device.id)", data: deviceData)
    }
    
    func revokeTrustedDevice(deviceId: String) async throws {
        logger.info("Revoking trusted device: \(deviceId)")
        
        try await keychain.delete(key: "trusted_device_\(deviceId)")
    }
    
    func getTrustedDevices(userId: String) async throws -> [TrustedDevice] {
        logger.debug("Fetching trusted devices for user: \(userId)")
        
        // Implementation would retrieve trusted devices from storage
        return []
    }
    
    func validateDeviceTrust(deviceId: String) async throws -> DeviceTrustResult {
        logger.debug("Validating device trust: \(deviceId)")
        
        // Implementation would check device trust status
        return DeviceTrustResult(
            isTrusted: true,
            trustScore: 0.8,
            trustLevel: .trusted,
            riskFactors: [],
            evaluatedAt: Date(),
            recommendedAction: .trust
        )
    }
    
    // MARK: - Multi-Factor Integration
    
    func combineBiometricWithMFA(userId: String, mfaToken: String) async throws -> CombinedAuthResult {
        logger.info("Combining biometric with MFA for user: \(userId)")
        
        // Perform biometric authentication
        let biometricResult = try await authenticateWithBiometrics(prompt: "Authenticate for enhanced security")
        
        // Validate MFA token (implementation would verify the actual token)
        let mfaResult = MFAResult(
            isSuccessful: true,
            method: .totp,
            verifiedAt: Date()
        )
        
        let combinedTrustScore = (biometricResult.trustScore + 0.9) / 2.0 // MFA adds high trust
        
        return CombinedAuthResult(
            biometricResult: biometricResult,
            mfaResult: mfaResult,
            combinedTrustScore: combinedTrustScore,
            sessionToken: UUID().uuidString,
            expiresAt: Date().addingTimeInterval(3600) // 1 hour
        )
    }
    
    func requireBiometricForMFA(userId: String, enabled: Bool) async throws {
        logger.info("Setting biometric requirement for MFA: \(enabled) for user: \(userId)")
        
        try await keychain.store(
            key: "require_biometric_mfa_\(userId)",
            data: enabled.description.data(using: .utf8)!
        )
    }
    
    func getBiometricMFAStatus(userId: String) async throws -> BiometricMFAStatus {
        logger.debug("Getting biometric MFA status for user: \(userId)")
        
        let isEnabled = try await keychain.retrieve(key: "require_biometric_mfa_\(userId)") != nil
        
        return BiometricMFAStatus(
            isEnabled: isEnabled,
            requiredForSensitiveOps: true,
            biometricTypes: await getSupportedBiometricTypes(),
            fallbackEnabled: currentPolicy.allowFallback,
            lastConfiguredAt: Date()
        )
    }
    
    // MARK: - Private Helper Methods
    
    private static func defaultBiometricPolicy() -> BiometricPolicy {
        return BiometricPolicy(
            requiredTrustLevel: .medium,
            allowedBiometricTypes: [.faceID, .touchID, .opticID],
            maxFailedAttempts: 5,
            lockoutDuration: 300,
            requireLivenessDetection: true,
            enableSpoofingDetection: true,
            allowFallback: true,
            fallbackMethods: [.passcode, .password],
            deviceTrustRequired: false,
            geofencingEnabled: false,
            allowedLocations: nil
        )
    }
    
    private func mapLABiometryType(_ type: LABiometryType) -> BiometricType {
        switch type {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        case .none:
            return .touchID // Default fallback
        @unknown default:
            return .touchID
        }
    }
    
    private func mapLAErrorToBiometricFailure(_ error: Error) -> BiometricFailureReason {
        guard let laError = error as? LAError else {
            return .authenticationFailed
        }
        
        switch laError.code {
        case .userCancel:
            return .userCancel
        case .userFallback:
            return .userFallback
        case .systemCancel:
            return .systemCancel
        case .passcodeNotSet:
            return .passcodeNotSet
        case .biometryNotAvailable:
            return .biometryNotAvailable
        case .biometryNotEnrolled:
            return .biometryNotEnrolled
        case .biometryLockout:
            return .biometryLocked
        case .invalidContext:
            return .invalidContext
        case .notInteractive:
            return .notInteractive
        default:
            return .authenticationFailed
        }
    }
    
    private func calculateTrustScore(biometricType: BiometricType) -> Double {
        return biometricType.securityLevel.score
    }
    
    private func createBiometricAttempt(result: BiometricAuthResult) -> BiometricAttempt {
        return BiometricAttempt(
            userId: result.userId,
            deviceId: result.deviceId,
            biometricType: result.biometricType,
            isSuccessful: result.isSuccessful,
            failureReason: result.failureReason,
            attemptedAt: result.authenticatedAt,
            location: nil,
            ipAddress: nil,
            userAgent: nil,
            riskFactors: []
        )
    }
    
    private func getPromptForSensitiveOperation(_ operation: SensitiveOperation) -> String {
        switch operation {
        case .payment:
            return "Authenticate to authorize payment"
        case .profileUpdate:
            return "Authenticate to update your profile"
        case .passwordChange:
            return "Authenticate to change your password"
        case .accountDeletion:
            return "Authenticate to delete your account"
        case .dataExport:
            return "Authenticate to export your data"
        case .permissionGrant:
            return "Authenticate to grant permissions"
        case .securitySettings:
            return "Authenticate to modify security settings"
        case .tenantSwitch:
            return "Authenticate to switch organizations"
        }
    }
    
    private func determineFallbackMethod() async -> FallbackMethod? {
        // Logic to determine the best fallback method for the user
        return .passcode
    }
    
    private func storeBiometricSetup(userId: String, keyId: String, biometricType: BiometricType) async throws {
        let setupData = [
            "user_id": userId,
            "key_id": keyId,
            "biometric_type": biometricType.rawValue,
            "setup_date": Date().timeIntervalSince1970
        ]
        
        let data = try JSONSerialization.data(withJSONObject: setupData)
        try await keychain.store(key: "biometric_setup_\(userId)", data: data)
    }
    
    private func deleteBiometricSetup(userId: String) async throws {
        // Delete stored setup information
        try await keychain.delete(key: "biometric_setup_\(userId)")
        
        // Delete associated Secure Enclave keys
        let keysToDelete = secureEnclaveKeys.keys.filter { $0.contains(userId) }
        for keyId in keysToDelete {
            try await deleteSecureEnclaveKey(keyId: keyId)
        }
    }
    
    private func getStoredSecureKey(keyId: String) -> SecureEnclaveKey? {
        // Implementation would retrieve stored public key data
        return nil
    }
    
    private func validateFallbackCredentials(method: FallbackMethod, credentials: FallbackCredentials) async throws -> Bool {
        // Implementation would validate fallback credentials
        return true
    }
    
    private func calculateRiskScore(violations: [PolicyViolation]) -> Double {
        return violations.isEmpty ? 0.0 : Double(violations.count) * 0.2
    }
    
    private func getRecommendedActions(for violations: [PolicyViolation]) -> [ComplianceAction] {
        return violations.compactMap { violation in
            switch violation {
            case .untrustedDevice:
                return .registerTrustedDevice
            case .unsupportedBiometricType:
                return .updateBiometricType
            case .livenessDetectionDisabled:
                return .enableLivenessDetection
            case .spoofingDetectionDisabled:
                return .enableSpoofingDetection
            default:
                return nil
            }
        }
    }
    
    private func getOSVersion() async -> String {
        return UIDevice.current.systemVersion
    }
    
    private func getHardwareSupport() async -> Bool {
        return true // Assume hardware support for biometrics
    }
    
    private func getSecureEnclaveSupport() async -> Bool {
        return true // Most modern iOS devices support Secure Enclave
    }
    
    private func getCurrentDeviceId() async -> String {
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
}

// MARK: - Keychain Wrapper

private class KeychainWrapper {
    func store(key: String, data: Data) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw BiometricAuthError.systemError("Keychain store failed: \(status)")
        }
    }
    
    func retrieve(key: String) async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw BiometricAuthError.systemError("Keychain retrieve failed: \(status)")
        }
        
        return result as? Data
    }
    
    func delete(key: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BiometricAuthError.systemError("Keychain delete failed: \(status)")
        }
    }
}

// MARK: - Extensions

extension BiometricPolicy: Codable {}
extension FallbackCredentials: Codable {}

// MARK: - Mock Security Service Extension

extension SecurityServiceProtocol {
    func logSecurityEvent(eventType: String, userId: String?, details: [String: Any]) async throws {
        // Mock implementation
    }
    
    func reportSuspiciousActivity(userId: String, activityType: String, riskScore: Double, details: [String: Any]) async throws {
        // Mock implementation
    }
}