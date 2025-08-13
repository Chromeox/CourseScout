import Foundation
import LocalAuthentication
import CryptoKit

// MARK: - Biometric Authentication Service Protocol

protocol BiometricAuthServiceProtocol {
    // MARK: - Biometric Availability
    func isBiometricAuthenticationAvailable() async -> BiometricAvailability
    func getSupportedBiometricTypes() async -> [BiometricType]
    func getBiometricCapabilities() async -> BiometricCapabilities
    
    // MARK: - Enrollment & Setup
    func isBiometricEnrolled() async -> Bool
    func requestBiometricEnrollment() async throws
    func setupBiometricAuthentication(userId: String) async throws -> BiometricSetupResult
    func disableBiometricAuthentication(userId: String) async throws
    
    // MARK: - Authentication
    func authenticateWithBiometrics(prompt: String) async throws -> BiometricAuthResult
    func authenticateWithBiometrics(userId: String, context: AuthenticationContext) async throws -> BiometricAuthResult
    func authenticateForTransaction(amount: Double, description: String) async throws -> BiometricAuthResult
    func authenticateForSensitiveOperation(operation: SensitiveOperation) async throws -> BiometricAuthResult
    
    // MARK: - Apple Watch Integration
    func isWatchUnlockAvailable() async -> Bool
    func enableWatchUnlock(userId: String) async throws
    func disableWatchUnlock(userId: String) async throws
    func authenticateWithWatchUnlock(prompt: String) async throws -> BiometricAuthResult
    
    // MARK: - Secure Enclave Integration
    func generateSecureEnclaveKey(userId: String) async throws -> SecureEnclaveKey
    func signWithSecureEnclave(data: Data, keyId: String) async throws -> Data
    func verifySecureEnclaveSignature(data: Data, signature: Data, keyId: String) async throws -> Bool
    func deleteSecureEnclaveKey(keyId: String) async throws
    
    // MARK: - Anti-Spoofing & Liveness Detection
    func performLivenessDetection() async throws -> LivenessDetectionResult
    func validateBiometricIntegrity() async throws -> BiometricIntegrityResult
    func detectSpoofingAttempt() async -> SpoofingDetectionResult
    
    // MARK: - Fallback Authentication
    func setupFallbackAuthentication(userId: String, method: FallbackMethod) async throws
    func authenticateWithFallback(method: FallbackMethod, credentials: FallbackCredentials) async throws -> BiometricAuthResult
    func updateFallbackCredentials(userId: String, method: FallbackMethod, credentials: FallbackCredentials) async throws
    
    // MARK: - Policy & Configuration
    func updateBiometricPolicy(_ policy: BiometricPolicy) async throws
    func getBiometricPolicy() async -> BiometricPolicy
    func validatePolicyCompliance(userId: String) async throws -> PolicyComplianceResult
    
    // MARK: - Security Monitoring
    func logBiometricAttempt(_ attempt: BiometricAttempt) async
    func getBiometricSecurityEvents(userId: String, period: TimeInterval) async throws -> [BiometricSecurityEvent]
    func reportSuspiciousBiometricActivity(_ activity: SuspiciousActivity) async throws
    
    // MARK: - Device Trust & Management
    func registerTrustedDevice(_ device: TrustedDevice) async throws
    func revokeTrustedDevice(deviceId: String) async throws
    func getTrustedDevices(userId: String) async throws -> [TrustedDevice]
    func validateDeviceTrust(deviceId: String) async throws -> DeviceTrustResult
    
    // MARK: - Multi-Factor Integration
    func combineBiometricWithMFA(userId: String, mfaToken: String) async throws -> CombinedAuthResult
    func requireBiometricForMFA(userId: String, enabled: Bool) async throws
    func getBiometricMFAStatus(userId: String) async throws -> BiometricMFAStatus
}

// MARK: - Biometric Models

struct BiometricAvailability {
    let isAvailable: Bool
    let supportedTypes: [BiometricType]
    let unavailabilityReason: BiometricUnavailabilityReason?
    let deviceCapabilities: BiometricCapabilities
    let osVersion: String
    let hardwareSupport: Bool
}

struct BiometricCapabilities {
    let supportsFaceID: Bool
    let supportsTouchID: Bool
    let supportsOpticID: Bool
    let supportsWatchUnlock: Bool
    let supportsSecureEnclave: Bool
    let maxFailedAttempts: Int
    let lockoutDuration: TimeInterval
    let biometricDataProtection: BiometricDataProtection
}

struct BiometricSetupResult {
    let userId: String
    let keyId: String
    let biometricType: BiometricType
    let secureEnclaveKeyGenerated: Bool
    let setupCompletedAt: Date
    let fallbackMethod: FallbackMethod?
    let trustLevel: BiometricTrustLevel
}

struct BiometricAuthResult {
    let isSuccessful: Bool
    let userId: String?
    let biometricType: BiometricType
    let authenticatedAt: Date
    let sessionToken: String?
    let deviceId: String
    let trustScore: Double
    let fallbackUsed: Bool
    let failureReason: BiometricFailureReason?
}

struct SecureEnclaveKey {
    let keyId: String
    let userId: String
    let publicKey: Data
    let createdAt: Date
    let algorithm: SecureEnclaveAlgorithm
    let keyUsage: [KeyUsage]
    let isActive: Bool
}

struct LivenessDetectionResult {
    let isLive: Bool
    let confidence: Double
    let detectionMethods: [LivenessDetectionMethod]
    let suspiciousIndicators: [SuspiciousIndicator]
    let timestamp: Date
}

struct BiometricIntegrityResult {
    let isIntact: Bool
    let integrityScore: Double
    let tamperedComponents: [BiometricComponent]
    let verificationTimestamp: Date
}

struct SpoofingDetectionResult {
    let spoofingAttempted: Bool
    let spoofingType: SpoofingType?
    let confidence: Double
    let detectionMethods: [SpoofingDetectionMethod]
    let recommendedAction: SecurityAction
}

struct FallbackCredentials {
    let method: FallbackMethod
    let hashedValue: Data
    let salt: Data
    let iterations: Int
    let algorithm: HashingAlgorithm
    let createdAt: Date
    let lastUsedAt: Date?
}

struct BiometricPolicy {
    let requiredTrustLevel: BiometricTrustLevel
    let allowedBiometricTypes: [BiometricType]
    let maxFailedAttempts: Int
    let lockoutDuration: TimeInterval
    let requireLivenessDetection: Bool
    let enableSpoofingDetection: Bool
    let allowFallback: Bool
    let fallbackMethods: [FallbackMethod]
    let deviceTrustRequired: Bool
    let geofencingEnabled: Bool
    let allowedLocations: [GeofenceRegion]?
}

struct PolicyComplianceResult {
    let isCompliant: Bool
    let violations: [PolicyViolation]
    let recommendedActions: [ComplianceAction]
    let riskScore: Double
    let lastEvaluatedAt: Date
}

struct BiometricAttempt {
    let userId: String?
    let deviceId: String
    let biometricType: BiometricType
    let isSuccessful: Bool
    let failureReason: BiometricFailureReason?
    let attemptedAt: Date
    let location: GeographicLocation?
    let ipAddress: String?
    let userAgent: String?
    let riskFactors: [RiskFactor]
}

struct BiometricSecurityEvent {
    let id: String
    let eventType: BiometricEventType
    let userId: String
    let deviceId: String
    let severity: SecurityEventSeverity
    let timestamp: Date
    let details: [String: Any]
    let resolved: Bool
    let resolvedAt: Date?
}

struct SuspiciousActivity {
    let userId: String
    let activityType: SuspiciousActivityType
    let deviceId: String
    let timestamp: Date
    let riskScore: Double
    let indicators: [SuspiciousIndicator]
    let location: GeographicLocation?
    let recommendedAction: SecurityAction
}

struct TrustedDevice {
    let id: String
    let userId: String
    let deviceName: String
    let deviceType: DeviceType
    let osVersion: String
    let modelIdentifier: String
    let registeredAt: Date
    let lastUsedAt: Date
    let trustLevel: DeviceTrustLevel
    let biometricCapabilities: BiometricCapabilities
    let secureEnclaveAvailable: Bool
    let isActive: Bool
}

struct DeviceTrustResult {
    let isTrusted: Bool
    let trustScore: Double
    let trustLevel: DeviceTrustLevel
    let riskFactors: [DeviceRiskFactor]
    let evaluatedAt: Date
    let recommendedAction: TrustAction
}

struct CombinedAuthResult {
    let biometricResult: BiometricAuthResult
    let mfaResult: MFAResult
    let combinedTrustScore: Double
    let sessionToken: String
    let expiresAt: Date
}

struct BiometricMFAStatus {
    let isEnabled: Bool
    let requiredForSensitiveOps: Bool
    let biometricTypes: [BiometricType]
    let fallbackEnabled: Bool
    let lastConfiguredAt: Date
}

struct AuthenticationContext {
    let operation: String
    let riskLevel: RiskLevel
    let requiresHighSecurity: Bool
    let customPrompt: String?
    let timeout: TimeInterval?
    let allowFallback: Bool
}

// MARK: - Geographic and Location Models

struct GeographicLocation {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    let city: String?
    let country: String?
}

struct GeofenceRegion {
    let id: String
    let name: String
    let centerLatitude: Double
    let centerLongitude: Double
    let radius: Double
    let isAllowed: Bool
}

struct MFAResult {
    let isSuccessful: Bool
    let method: MFAMethod
    let verifiedAt: Date
}

// MARK: - Enums

enum BiometricType: String, CaseIterable {
    case faceID = "face_id"
    case touchID = "touch_id"
    case opticID = "optic_id"
    case voiceID = "voice_id"
    case watchUnlock = "watch_unlock"
    
    var displayName: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .voiceID: return "Voice ID"
        case .watchUnlock: return "Apple Watch Unlock"
        }
    }
    
    var securityLevel: BiometricSecurityLevel {
        switch self {
        case .faceID, .opticID: return .high
        case .touchID: return .medium
        case .voiceID: return .medium
        case .watchUnlock: return .low
        }
    }
}

enum BiometricUnavailabilityReason: String, CaseIterable {
    case notEnrolled = "not_enrolled"
    case hardwareUnavailable = "hardware_unavailable"
    case osNotSupported = "os_not_supported"
    case biometryLocked = "biometry_locked"
    case passcodeNotSet = "passcode_not_set"
    case deviceNotSupported = "device_not_supported"
}

enum BiometricDataProtection: String, CaseIterable {
    case secureEnclave = "secure_enclave"
    case keychain = "keychain"
    case none = "none"
}

enum BiometricTrustLevel: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
    
    var score: Double {
        switch self {
        case .low: return 0.25
        case .medium: return 0.50
        case .high: return 0.75
        case .critical: return 1.0
        }
    }
}

enum BiometricFailureReason: String, CaseIterable {
    case userCancel = "user_cancel"
    case userFallback = "user_fallback"
    case systemCancel = "system_cancel"
    case passcodeNotSet = "passcode_not_set"
    case biometryNotAvailable = "biometry_not_available"
    case biometryNotEnrolled = "biometry_not_enrolled"
    case biometryLocked = "biometry_locked"
    case invalidContext = "invalid_context"
    case notInteractive = "not_interactive"
    case authenticationFailed = "authentication_failed"
    case spoofingDetected = "spoofing_detected"
    case livenessCheckFailed = "liveness_check_failed"
    case deviceNotTrusted = "device_not_trusted"
    case geofenceViolation = "geofence_violation"
    case policyViolation = "policy_violation"
}

enum SecureEnclaveAlgorithm: String, CaseIterable {
    case ecdsaSecp256r1 = "ecdsa_secp256r1"
    case ecdsaSecp384r1 = "ecdsa_secp384r1"
    case ecdsaSecp521r1 = "ecdsa_secp521r1"
}

enum KeyUsage: String, CaseIterable {
    case authentication = "authentication"
    case signing = "signing"
    case encryption = "encryption"
    case keyAgreement = "key_agreement"
}

enum LivenessDetectionMethod: String, CaseIterable {
    case eyeBlinkDetection = "eye_blink_detection"
    case headMovement = "head_movement"
    case faceGeometry = "face_geometry"
    case skinTexture = "skin_texture"
    case bloodFlow = "blood_flow"
    case depthSensing = "depth_sensing"
    case motionAnalysis = "motion_analysis"
}

enum SuspiciousIndicator: String, CaseIterable {
    case maskDetected = "mask_detected"
    case photoDetected = "photo_detected"
    case videoDetected = "video_detected"
    case fakeFingerprintDetected = "fake_fingerprint_detected"
    case unusualBehaviorPattern = "unusual_behavior_pattern"
    case multipleFailedAttempts = "multiple_failed_attempts"
    case deviceTamperingDetected = "device_tampering_detected"
    case locationAnomalyDetected = "location_anomaly_detected"
}

enum BiometricComponent: String, CaseIterable {
    case camera = "camera"
    case touchSensor = "touch_sensor"
    case depthSensor = "depth_sensor"
    case secureEnclave = "secure_enclave"
    case biometricSensor = "biometric_sensor"
}

enum SpoofingType: String, CaseIterable {
    case photoAttack = "photo_attack"
    case videoAttack = "video_attack"
    case maskAttack = "mask_attack"
    case fingerprintMold = "fingerprint_mold"
    case deepfake = "deepfake"
    case replayAttack = "replay_attack"
}

enum SpoofingDetectionMethod: String, CaseIterable {
    case livenessDetection = "liveness_detection"
    case depthAnalysis = "depth_analysis"
    case motionDetection = "motion_detection"
    case textureAnalysis = "texture_analysis"
    case challengeResponse = "challenge_response"
    case behaviorAnalysis = "behavior_analysis"
}

enum SecurityAction: String, CaseIterable {
    case allow = "allow"
    case warn = "warn"
    case block = "block"
    case require_additional_auth = "require_additional_auth"
    case flag_for_review = "flag_for_review"
    case temporary_lockout = "temporary_lockout"
    case permanent_ban = "permanent_ban"
}

enum FallbackMethod: String, CaseIterable {
    case passcode = "passcode"
    case password = "password"
    case pin = "pin"
    case securityQuestions = "security_questions"
    case email = "email"
    case sms = "sms"
    case backupCodes = "backup_codes"
    
    var displayName: String {
        switch self {
        case .passcode: return "Device Passcode"
        case .password: return "Password"
        case .pin: return "PIN"
        case .securityQuestions: return "Security Questions"
        case .email: return "Email Verification"
        case .sms: return "SMS Verification"
        case .backupCodes: return "Backup Codes"
        }
    }
    
    var securityLevel: BiometricSecurityLevel {
        switch self {
        case .passcode, .password: return .medium
        case .pin, .securityQuestions: return .low
        case .email, .sms, .backupCodes: return .medium
        }
    }
}

enum HashingAlgorithm: String, CaseIterable {
    case sha256 = "sha256"
    case sha512 = "sha512"
    case pbkdf2 = "pbkdf2"
    case scrypt = "scrypt"
    case argon2 = "argon2"
}

enum PolicyViolation: String, CaseIterable {
    case insufficientTrustLevel = "insufficient_trust_level"
    case unsupportedBiometricType = "unsupported_biometric_type"
    case tooManyFailedAttempts = "too_many_failed_attempts"
    case livenessDetectionDisabled = "liveness_detection_disabled"
    case spoofingDetectionDisabled = "spoofing_detection_disabled"
    case untrustedDevice = "untrusted_device"
    case geofenceViolation = "geofence_violation"
    case fallbackNotAllowed = "fallback_not_allowed"
}

enum ComplianceAction: String, CaseIterable {
    case enableLivenessDetection = "enable_liveness_detection"
    case enableSpoofingDetection = "enable_spoofing_detection"
    case registerTrustedDevice = "register_trusted_device"
    case updateBiometricType = "update_biometric_type"
    case resetFailedAttempts = "reset_failed_attempts"
    case updateLocationPermissions = "update_location_permissions"
    case configureFallbackMethod = "configure_fallback_method"
}

enum RiskFactor: String, CaseIterable {
    case newDevice = "new_device"
    case unusualLocation = "unusual_location"
    case unusualTime = "unusual_time"
    case multipleFailures = "multiple_failures"
    case suspiciousPattern = "suspicious_pattern"
    case deviceTampering = "device_tampering"
    case networkAnomaly = "network_anomaly"
}

enum BiometricEventType: String, CaseIterable {
    case successfulAuthentication = "successful_authentication"
    case failedAuthentication = "failed_authentication"
    case spoofingAttempt = "spoofing_attempt"
    case deviceTampering = "device_tampering"
    case policyViolation = "policy_violation"
    case suspiciousActivity = "suspicious_activity"
    case biometricEnrollment = "biometric_enrollment"
    case biometricDisabled = "biometric_disabled"
    case fallbackUsed = "fallback_used"
}

enum SecurityEventSeverity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum SuspiciousActivityType: String, CaseIterable {
    case rapidMultipleAttempts = "rapid_multiple_attempts"
    case locationJumping = "location_jumping"
    case deviceCloning = "device_cloning"
    case biometricBypass = "biometric_bypass"
    case anomalousPattern = "anomalous_pattern"
    case timeBasedAnomaly = "time_based_anomaly"
}

enum DeviceType: String, CaseIterable {
    case iPhone = "iPhone"
    case iPad = "iPad"
    case iPadMini = "iPad_mini"
    case iPadPro = "iPad_pro"
    case appleWatch = "apple_watch"
    case macBook = "macbook"
    case iMac = "imac"
    case macPro = "mac_pro"
    case macStudio = "mac_studio"
    case unknown = "unknown"
}

enum DeviceTrustLevel: String, CaseIterable {
    case untrusted = "untrusted"
    case basic = "basic"
    case trusted = "trusted"
    case highlyTrusted = "highly_trusted"
    
    var score: Double {
        switch self {
        case .untrusted: return 0.0
        case .basic: return 0.33
        case .trusted: return 0.66
        case .highlyTrusted: return 1.0
        }
    }
}

enum DeviceRiskFactor: String, CaseIterable {
    case jailbroken = "jailbroken"
    case debuggerAttached = "debugger_attached"
    case emulator = "emulator"
    case rootedDevice = "rooted_device"
    case tamperingDetected = "tampering_detected"
    case unknownDevice = "unknown_device"
    case outdatedOS = "outdated_os"
    case compromisedDevice = "compromised_device"
}

enum TrustAction: String, CaseIterable {
    case trust = "trust"
    case verify = "verify"
    case challenge = "challenge"
    case reject = "reject"
    case quarantine = "quarantine"
}

enum RiskLevel: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum BiometricSecurityLevel: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum SensitiveOperation: String, CaseIterable {
    case payment = "payment"
    case profileUpdate = "profile_update"
    case passwordChange = "password_change"
    case accountDeletion = "account_deletion"
    case dataExport = "data_export"
    case permissionGrant = "permission_grant"
    case securitySettings = "security_settings"
    case tenantSwitch = "tenant_switch"
}

// MARK: - Error Types

enum BiometricAuthError: LocalizedError, Equatable {
    case biometricNotAvailable(BiometricUnavailabilityReason)
    case biometricNotEnrolled
    case biometricLocked
    case authenticationFailed(BiometricFailureReason)
    case spoofingDetected(SpoofingType)
    case livenessCheckFailed([SuspiciousIndicator])
    case deviceNotTrusted(DeviceRiskFactor)
    case policyViolation([PolicyViolation])
    case secureEnclaveError(String)
    case fallbackNotAvailable
    case geofenceViolation
    case rateLimited
    case systemError(String)
    case networkError(String)
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .biometricNotAvailable(let reason):
            return "Biometric authentication is not available: \(reason.rawValue)"
        case .biometricNotEnrolled:
            return "No biometric data is enrolled on this device"
        case .biometricLocked:
            return "Biometric authentication is locked. Use your passcode to unlock"
        case .authenticationFailed(let reason):
            return "Biometric authentication failed: \(reason.rawValue)"
        case .spoofingDetected(let type):
            return "Spoofing attempt detected: \(type.rawValue)"
        case .livenessCheckFailed(let indicators):
            return "Liveness check failed: \(indicators.map(\.rawValue).joined(separator: ", "))"
        case .deviceNotTrusted(let factor):
            return "Device is not trusted: \(factor.rawValue)"
        case .policyViolation(let violations):
            return "Policy violation: \(violations.map(\.rawValue).joined(separator: ", "))"
        case .secureEnclaveError(let message):
            return "Secure Enclave error: \(message)"
        case .fallbackNotAvailable:
            return "Fallback authentication method is not available"
        case .geofenceViolation:
            return "Authentication from this location is not allowed"
        case .rateLimited:
            return "Too many authentication attempts. Please try again later"
        case .systemError(let message):
            return "System error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}