import Foundation
import LocalAuthentication
import Combine
@testable import GolfFinderApp

// MARK: - Mock Appwrite Client

class MockAppwriteClient: Client {
    
    // MARK: - Mock Properties
    
    var createOAuth2SessionCallCount = 0
    var createDocumentCallCount = 0
    var listDocumentsCallCount = 0
    var updateDocumentCallCount = 0
    var deleteDocumentCallCount = 0
    
    var shouldThrowError = false
    var errorToThrow: Error = AuthenticationError.networkError("Mock error")
    
    var mockOAuthSession: Session?
    var mockMFASettings: MockMFASettings?
    var mockTenantMemberships: [TenantMembership] = []
    
    // MARK: - OAuth Session Methods
    
    func createOAuth2Session(
        provider: String,
        success: String,
        failure: String,
        scopes: [String]
    ) async throws -> Session {
        createOAuth2SessionCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        return mockOAuthSession ?? TestDataFactory.createAppwriteSession()
    }
    
    // MARK: - Document Methods
    
    func createDocument(
        databaseId: String,
        collectionId: String,
        documentId: String,
        data: [String: Any]
    ) async throws -> Document {
        createDocumentCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        return TestDataFactory.createAppwriteDocument(data: data)
    }
    
    func listDocuments(
        databaseId: String,
        collectionId: String,
        queries: [Query]
    ) async throws -> DocumentList {
        listDocumentsCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        if collectionId == "mfa_settings" && mockMFASettings != nil {
            return TestDataFactory.createDocumentList(with: [mockMFASettings!.toDocument()])
        }
        
        if collectionId == "tenant_memberships" {
            let membershipDocs = mockTenantMemberships.map { $0.toDocument() }
            return TestDataFactory.createDocumentList(with: membershipDocs)
        }
        
        return TestDataFactory.createDocumentList(with: [])
    }
    
    func updateDocument(
        databaseId: String,
        collectionId: String,
        documentId: String,
        data: [String: Any]
    ) async throws -> Document {
        updateDocumentCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        return TestDataFactory.createAppwriteDocument(data: data)
    }
    
    func deleteDocument(
        databaseId: String,
        collectionId: String,
        documentId: String
    ) async throws {
        deleteDocumentCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
    }
}

// MARK: - Mock Session Management Service

class MockSessionManagementService: SessionManagementServiceProtocol {
    
    // MARK: - Mock Properties
    
    var createSessionCallCount = 0
    var validateSessionCallCount = 0
    var terminateSessionCallCount = 0
    var terminateAllUserSessionsCallCount = 0
    var refreshAccessTokenCallCount = 0
    var revokeTokenCallCount = 0
    var getUserSessionsCallCount = 0
    
    var shouldThrowError = false
    var errorToThrow: Error = AuthenticationError.networkError("Mock session error")
    
    var mockCreateSessionResult: SessionCreationResult?
    var mockValidationResult: SessionValidationServiceResult?
    var mockRefreshResult: SessionRefreshResult?
    var mockUserSessions: [SessionInfo] = []
    var mockValidateTenantAccess = true
    
    // MARK: - Session Management Methods
    
    func createSession(userId: String, tenantId: String?, deviceInfo: DeviceInfo) async throws -> SessionCreationResult {
        createSessionCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        return mockCreateSessionResult ?? TestDataFactory.createSessionResult()
    }
    
    func validateSession(sessionId: String) async throws -> SessionValidationServiceResult {
        validateSessionCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        return mockValidationResult ?? TestDataFactory.createSessionValidationServiceResult(isValid: true)
    }
    
    func terminateSession(sessionId: String) async throws {
        terminateSessionCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
    }
    
    func terminateAllUserSessions(userId: String, excludeCurrentDevice: Bool) async throws {
        terminateAllUserSessionsCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
    }
    
    func refreshAccessToken(refreshToken: String) async throws -> SessionRefreshResult {
        refreshAccessTokenCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        return mockRefreshResult ?? TestDataFactory.createSessionRefreshResult()
    }
    
    func revokeToken(token: String, tokenType: TokenType) async throws {
        revokeTokenCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
    }
    
    func getUserSessions(userId: String) async throws -> [SessionInfo] {
        getUserSessionsCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        return mockUserSessions
    }
}

// MARK: - Mock Security Service

class MockSecurityService: SecurityServiceProtocol {
    
    // MARK: - Mock Properties
    
    var evaluateDeviceTrustCallCount = 0
    var checkForRequiredSecurityUpdatesCallCount = 0
    
    var mockDeviceTrust: DeviceTrustLevel = .trusted
    var mockRequiresSecurityUpdate = false
    
    // MARK: - Security Methods
    
    func evaluateDeviceTrust() async -> DeviceTrustLevel {
        evaluateDeviceTrustCallCount += 1
        return mockDeviceTrust
    }
    
    func checkForRequiredSecurityUpdates() async -> Bool {
        checkForRequiredSecurityUpdatesCallCount += 1
        return mockRequiresSecurityUpdate
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
        // Mock encryption - just return data for testing
        return data
    }
    
    func decryptSensitiveData(_ encryptedData: Data) throws -> Data {
        // Mock decryption - just return data for testing
        return encryptedData
    }
}

// MARK: - Mock LAContext

class MockLAContext: LAContext {
    
    // MARK: - Mock Properties
    
    var evaluatePolicyCallCount = 0
    var canEvaluatePolicyCallCount = 0
    
    var mockBiometryType: LABiometryType = .faceID
    var mockCanEvaluatePolicy = true
    var mockError: Error?
    var mockEvaluateSuccess = true
    var mockEvaluateError: Error?
    var mockPasscodeEvaluateSuccess = false
    
    var lastPolicy: LAPolicy?
    var lastReason: String?
    var wasSecurityValidationCalled = false
    
    // MARK: - Override Properties
    
    override var biometryType: LABiometryType {
        return mockBiometryType
    }
    
    // MARK: - Override Methods
    
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        canEvaluatePolicyCallCount += 1
        
        if let mockError = mockError {
            error?.pointee = mockError as NSError
        }
        
        return mockCanEvaluatePolicy
    }
    
    override func evaluatePolicy(
        _ policy: LAPolicy,
        localizedReason: String,
        reply: @escaping (Bool, Error?) -> Void
    ) {
        evaluatePolicyCallCount += 1
        lastPolicy = policy
        lastReason = localizedReason
        
        // Simulate high security validation
        if localizedReason.contains("Secure operation") {
            wasSecurityValidationCalled = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.mockEvaluateSuccess {
                reply(true, nil)
            } else {
                // If biometric fails and passcode is available, try passcode
                if !self.mockEvaluateSuccess && 
                   policy == .deviceOwnerAuthenticationWithBiometrics &&
                   self.mockPasscodeEvaluateSuccess {
                    
                    // Simulate fallback to passcode
                    self.evaluatePolicy(
                        .deviceOwnerAuthentication,
                        localizedReason: localizedReason,
                        reply: reply
                    )
                    return
                }
                
                reply(false, self.mockEvaluateError)
            }
        }
    }
}

// MARK: - Mock Secure Storage

class MockSecureStorage {
    
    // MARK: - Mock Properties
    
    var saveCallCount = 0
    var loadCallCount = 0
    var deleteCallCount = 0
    
    var mockSaveSuccess = true
    var mockLoadValue: Any?
    var lastKey: String?
    var lastValue: Any?
    var lastLoadKey: String?
    
    // MARK: - Storage Methods
    
    func save(key: String, value: Any) throws {
        saveCallCount += 1
        lastKey = key
        lastValue = value
        
        if !mockSaveSuccess {
            throw AuthenticationError.systemError("Failed to save to secure storage")
        }
    }
    
    func load(key: String) -> Any? {
        loadCallCount += 1
        lastLoadKey = key
        return mockLoadValue
    }
    
    func delete(key: String) throws {
        deleteCallCount += 1
        lastKey = key
    }
}

// MARK: - Mock Configuration

class MockConfiguration {
    
    // MARK: - Mock Properties
    
    var mockSecurityLevel: SecurityLevel = .standard
    var mockBiometricTimeout: TimeInterval = 30.0
    var mockMaxRetryAttempts = 3
    
    // MARK: - Configuration Properties
    
    var securityLevel: SecurityLevel {
        return mockSecurityLevel
    }
    
    var biometricTimeout: TimeInterval {
        return mockBiometricTimeout
    }
    
    var maxRetryAttempts: Int {
        return mockMaxRetryAttempts
    }
}

// MARK: - Mock Apple Sign In Credential

class MockASAuthorizationAppleIDCredential: ASAuthorizationAppleIDCredential {
    
    // MARK: - Mock Properties
    
    var mockUser: String = "test_user_id"
    var mockEmail: String?
    var mockFullName: PersonNameComponents?
    var mockIdentityToken: Data?
    var mockAuthorizationCode: Data?
    
    // MARK: - Override Properties
    
    override var user: String {
        return mockUser
    }
    
    override var email: String? {
        return mockEmail
    }
    
    override var fullName: PersonNameComponents? {
        return mockFullName
    }
    
    override var identityToken: Data? {
        return mockIdentityToken
    }
    
    override var authorizationCode: Data? {
        return mockAuthorizationCode
    }
}

// MARK: - Mock MFA Settings

class MockMFASettings {
    var secret: String = "MOCK_SECRET_12345"
    var backupCodes: [String] = ["backup123", "backup456"]
    var enabled: Bool = true
    
    func toDocument() -> Document {
        return TestDataFactory.createAppwriteDocument(data: [
            "secret": secret,
            "backup_codes": backupCodes,
            "enabled": enabled
        ])
    }
}

// MARK: - Mock Secure Keychain Helper

class MockSecureKeychainHelper {
    static var mockTokenData: StoredToken?
    
    static func load(key: String) -> Data? {
        guard let token = mockTokenData else { return nil }
        
        do {
            return try JSONEncoder().encode(token)
        } catch {
            return nil
        }
    }
    
    static func save(key: String, data: Data, requiresBiometrics: Bool) throws {
        // Mock save operation
    }
    
    static func delete(key: String) throws {
        // Mock delete operation
    }
    
    static func encrypt(data: Data) throws -> Data {
        return data // Mock encryption
    }
    
    static func decrypt(data: Data) throws -> Data {
        return data // Mock decryption
    }
}

// MARK: - Supporting Types

enum SecurityLevel {
    case low
    case standard
    case high
    case maximum
}

enum TokenType {
    case accessToken
    case refreshToken
    case idToken
}

struct DeviceInfo {
    let deviceId: String
    let name: String
    let model: String
    let osVersion: String
    let appVersion: String
    let platform: Platform
    let screenResolution: String
    let biometricCapabilities: [BiometricCapability]
    let isJailbroken: Bool
    let isEmulator: Bool
    let fingerprint: String
    
    enum Platform {
        case iOS
        case android
        case web
    }
    
    enum BiometricCapability {
        case faceID
        case touchID
        case opticID
        case voiceID
    }
}

struct SessionCreationResult {
    let sessionId: String
    let accessToken: AccessToken
    let refreshToken: RefreshToken
    let expiresAt: Date
    let tenantId: String?
}

struct SessionValidationServiceResult {
    let isValid: Bool
    let session: SessionInfo?
    let requiresReauth: Bool
    let suspiciousActivity: Bool
}

struct SessionRefreshResult {
    let newAccessToken: AccessToken
    let newRefreshToken: RefreshToken?
    let expiresAt: Date
}

struct SessionInfo {
    let id: String
    let userId: String
    let tenantId: String?
    let deviceId: String
    let createdAt: Date
    let lastAccessedAt: Date
    let expiresAt: Date
    let ipAddress: String
    let userAgent: String
    let isActive: Bool
}

struct AccessToken {
    let token: String
    let expiresAt: Date
    let scopes: [String]
}

struct RefreshToken {
    let token: String
    let expiresAt: Date
}

struct DeviceIntegrityResult {
    let isIntegrityVerified: Bool
    let jailbrokenDetected: Bool
    let debuggerDetected: Bool
    let emulatorDetected: Bool
    let riskLevel: RiskLevel
    
    enum RiskLevel {
        case low
        case medium
        case high
        case critical
    }
}

// MARK: - Extensions for Testing

extension TenantMembership {
    func toDocument() -> Document {
        return TestDataFactory.createAppwriteDocument(data: [
            "user_id": userId,
            "tenant_id": tenantId,
            "role": role.rawValue,
            "is_active": isActive
        ])
    }
}

// MARK: - Service Protocol Extensions

protocol SecurityServiceProtocol {
    func evaluateDeviceTrust() async -> DeviceTrustLevel
    func checkForRequiredSecurityUpdates() async -> Bool
    func validateDeviceIntegrity() async throws -> DeviceIntegrityResult
    func encryptSensitiveData(_ data: Data) throws -> Data
    func decryptSensitiveData(_ encryptedData: Data) throws -> Data
}

protocol SessionManagementServiceProtocol {
    func createSession(userId: String, tenantId: String?, deviceInfo: DeviceInfo) async throws -> SessionCreationResult
    func validateSession(sessionId: String) async throws -> SessionValidationServiceResult
    func terminateSession(sessionId: String) async throws
    func terminateAllUserSessions(userId: String, excludeCurrentDevice: Bool) async throws
    func refreshAccessToken(refreshToken: String) async throws -> SessionRefreshResult
    func revokeToken(token: String, tokenType: TokenType) async throws
    func getUserSessions(userId: String) async throws -> [SessionInfo]
}

// MARK: - Test Utilities

extension MockSecureKeychainHelper {
    static func reset() {
        mockTokenData = nil
    }
}

extension MockAppwriteClient {
    func reset() {
        createOAuth2SessionCallCount = 0
        createDocumentCallCount = 0
        listDocumentsCallCount = 0
        updateDocumentCallCount = 0
        deleteDocumentCallCount = 0
        shouldThrowError = false
        mockOAuthSession = nil
        mockMFASettings = nil
        mockTenantMemberships = []
    }
}

extension MockSessionManagementService {
    func reset() {
        createSessionCallCount = 0
        validateSessionCallCount = 0
        terminateSessionCallCount = 0
        terminateAllUserSessionsCallCount = 0
        refreshAccessTokenCallCount = 0
        revokeTokenCallCount = 0
        getUserSessionsCallCount = 0
        shouldThrowError = false
        mockCreateSessionResult = nil
        mockValidationResult = nil
        mockRefreshResult = nil
        mockUserSessions = []
        mockValidateTenantAccess = true
    }
}

extension MockLAContext {
    func reset() {
        evaluatePolicyCallCount = 0
        canEvaluatePolicyCallCount = 0
        mockBiometryType = .faceID
        mockCanEvaluatePolicy = true
        mockError = nil
        mockEvaluateSuccess = true
        mockEvaluateError = nil
        mockPasscodeEvaluateSuccess = false
        lastPolicy = nil
        lastReason = nil
        wasSecurityValidationCalled = false
    }
}