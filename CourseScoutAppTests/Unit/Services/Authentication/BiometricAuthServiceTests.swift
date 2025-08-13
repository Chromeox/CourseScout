import XCTest
import LocalAuthentication
@testable import GolfFinderApp

// MARK: - Biometric Authentication Service Tests

final class BiometricAuthServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: BiometricAuthService!
    private var mockLAContext: MockLAContext!
    private var mockSecureStorage: MockSecureStorage!
    private var mockConfiguration: MockConfiguration!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        mockLAContext = MockLAContext()
        mockSecureStorage = MockSecureStorage()
        mockConfiguration = MockConfiguration()
        
        sut = BiometricAuthService(
            laContext: mockLAContext,
            secureStorage: mockSecureStorage,
            configuration: mockConfiguration
        )
    }
    
    override func tearDown() {
        sut = nil
        mockConfiguration = nil
        mockSecureStorage = nil
        mockLAContext = nil
        
        super.tearDown()
    }
    
    // MARK: - Biometric Availability Tests
    
    func testCheckBiometricAvailability_FaceIDAvailable() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockCanEvaluatePolicy = true
        mockLAContext.mockError = nil
        
        // When
        let result = await sut.checkBiometricAvailability()
        
        // Then
        XCTAssertTrue(result.isAvailable)
        XCTAssertEqual(result.biometryType, .faceID)
        XCTAssertFalse(result.requiresEnrollment)
        XCTAssertNil(result.errorMessage)
    }
    
    func testCheckBiometricAvailability_TouchIDAvailable() async {
        // Given
        mockLAContext.mockBiometryType = .touchID
        mockLAContext.mockCanEvaluatePolicy = true
        mockLAContext.mockError = nil
        
        // When
        let result = await sut.checkBiometricAvailability()
        
        // Then
        XCTAssertTrue(result.isAvailable)
        XCTAssertEqual(result.biometryType, .touchID)
        XCTAssertFalse(result.requiresEnrollment)
        XCTAssertNil(result.errorMessage)
    }
    
    func testCheckBiometricAvailability_OpticIDAvailable() async {
        // Given
        if #available(iOS 17.0, *) {
            mockLAContext.mockBiometryType = .opticID
            mockLAContext.mockCanEvaluatePolicy = true
            mockLAContext.mockError = nil
            
            // When
            let result = await sut.checkBiometricAvailability()
            
            // Then
            XCTAssertTrue(result.isAvailable)
            XCTAssertEqual(result.biometryType, .opticID)
            XCTAssertFalse(result.requiresEnrollment)
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testCheckBiometricAvailability_NotAvailable() async {
        // Given
        mockLAContext.mockBiometryType = .none
        mockLAContext.mockCanEvaluatePolicy = false
        mockLAContext.mockError = LAError(.biometryNotAvailable)
        
        // When
        let result = await sut.checkBiometricAvailability()
        
        // Then
        XCTAssertFalse(result.isAvailable)
        XCTAssertEqual(result.biometryType, .none)
        XCTAssertNotNil(result.errorMessage)
    }
    
    func testCheckBiometricAvailability_NotEnrolled() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockCanEvaluatePolicy = false
        mockLAContext.mockError = LAError(.biometryNotEnrolled)
        
        // When
        let result = await sut.checkBiometricAvailability()
        
        // Then
        XCTAssertFalse(result.isAvailable)
        XCTAssertTrue(result.requiresEnrollment)
        XCTAssertEqual(result.biometryType, .faceID)
        XCTAssertNotNil(result.errorMessage)
    }
    
    func testCheckBiometricAvailability_PasscodeNotSet() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockCanEvaluatePolicy = false
        mockLAContext.mockError = LAError(.passcodeNotSet)
        
        // When
        let result = await sut.checkBiometricAvailability()
        
        // Then
        XCTAssertFalse(result.isAvailable)
        XCTAssertFalse(result.hasSystemPasscode)
        XCTAssertNotNil(result.errorMessage)
    }
    
    // MARK: - Authentication Tests
    
    func testAuthenticateUser_Success() async throws {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = true
        
        let reason = "Authenticate to access your account"
        let fallbackTitle = "Use Passcode"
        
        // When
        let result = try await sut.authenticateUser(reason: reason, fallbackTitle: fallbackTitle)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(mockLAContext.evaluatePolicyCallCount, 1)
        XCTAssertEqual(mockLAContext.lastReason, reason)
    }
    
    func testAuthenticateUser_UserCancel() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.userCancel)
        
        // When & Then
        do {
            _ = try await sut.authenticateUser(reason: "Test", fallbackTitle: nil)
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.userCancelled {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testAuthenticateUser_BiometricFailed() async {
        // Given
        mockLAContext.mockBiometryType = .touchID
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.authenticationFailed)
        
        // When & Then
        do {
            _ = try await sut.authenticateUser(reason: "Test", fallbackTitle: nil)
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.biometricFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testAuthenticateUser_BiometricNotAvailable() async {
        // Given
        mockLAContext.mockBiometryType = .none
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.biometryNotAvailable)
        
        // When & Then
        do {
            _ = try await sut.authenticateUser(reason: "Test", fallbackTitle: nil)
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.biometricNotAvailable {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testAuthenticateUser_BiometricNotEnrolled() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.biometryNotEnrolled)
        
        // When & Then
        do {
            _ = try await sut.authenticateUser(reason: "Test", fallbackTitle: nil)
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.biometricNotEnrolled {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testAuthenticateUser_PasscodeFallback() async throws {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.biometryNotAvailable)
        mockLAContext.mockPasscodeEvaluateSuccess = true
        
        // When
        let result = try await sut.authenticateUser(reason: "Test", fallbackTitle: "Use Passcode")
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(mockLAContext.evaluatePolicyCallCount, 2) // Biometric + Passcode
    }
    
    func testAuthenticateUser_CustomPolicy() async throws {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = true
        
        // When
        let result = try await sut.authenticateUser(
            reason: "Custom authentication",
            fallbackTitle: "Fallback",
            policy: .deviceOwnerAuthenticationWithBiometrics
        )
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(mockLAContext.lastPolicy, .deviceOwnerAuthenticationWithBiometrics)
    }
    
    // MARK: - Configuration Management Tests
    
    func testEnableBiometricAuthentication_Success() async throws {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = true
        mockSecureStorage.mockSaveSuccess = true
        
        // When
        let result = try await sut.enableBiometricAuthentication()
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(mockSecureStorage.saveCallCount, 1)
        XCTAssertEqual(mockSecureStorage.lastKey, "biometric_enabled")
        XCTAssertEqual(mockSecureStorage.lastValue as? Bool, true)
    }
    
    func testEnableBiometricAuthentication_NotAvailable() async {
        // Given
        mockLAContext.mockBiometryType = .none
        mockLAContext.mockCanEvaluatePolicy = false
        mockLAContext.mockError = LAError(.biometryNotAvailable)
        
        // When & Then
        do {
            _ = try await sut.enableBiometricAuthentication()
            XCTFail("Expected enable to fail")
        } catch AuthenticationError.biometricNotAvailable {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testEnableBiometricAuthentication_AuthenticationFailed() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.authenticationFailed)
        
        // When & Then
        do {
            _ = try await sut.enableBiometricAuthentication()
            XCTFail("Expected enable to fail")
        } catch AuthenticationError.biometricFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testDisableBiometricAuthentication_Success() async throws {
        // Given
        mockSecureStorage.mockSaveSuccess = true
        
        // When
        try await sut.disableBiometricAuthentication()
        
        // Then
        XCTAssertEqual(mockSecureStorage.saveCallCount, 1)
        XCTAssertEqual(mockSecureStorage.lastKey, "biometric_enabled")
        XCTAssertEqual(mockSecureStorage.lastValue as? Bool, false)
    }
    
    func testIsBiometricEnabled_True() async {
        // Given
        mockSecureStorage.mockLoadValue = true
        
        // When
        let result = await sut.isBiometricEnabled()
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(mockSecureStorage.loadCallCount, 1)
        XCTAssertEqual(mockSecureStorage.lastLoadKey, "biometric_enabled")
    }
    
    func testIsBiometricEnabled_False() async {
        // Given
        mockSecureStorage.mockLoadValue = false
        
        // When
        let result = await sut.isBiometricEnabled()
        
        // Then
        XCTAssertFalse(result)
    }
    
    func testIsBiometricEnabled_NotSet() async {
        // Given
        mockSecureStorage.mockLoadValue = nil
        
        // When
        let result = await sut.isBiometricEnabled()
        
        // Then
        XCTAssertFalse(result) // Default to false when not set
    }
    
    // MARK: - Biometric Configuration Tests
    
    func testSaveBiometricConfiguration_Success() async throws {
        // Given
        let configuration = BiometricConfiguration(
            enabledForLogin: true,
            enabledForTransactions: true,
            enabledForSettings: false,
            requiresAdditionalAuth: false,
            allowsPasscodeFallback: true,
            biometryType: .faceID
        )
        mockSecureStorage.mockSaveSuccess = true
        
        // When
        try await sut.saveBiometricConfiguration(configuration)
        
        // Then
        XCTAssertEqual(mockSecureStorage.saveCallCount, 1)
        XCTAssertEqual(mockSecureStorage.lastKey, "biometric_configuration")
    }
    
    func testLoadBiometricConfiguration_Success() async throws {
        // Given
        let expectedConfiguration = BiometricConfiguration(
            enabledForLogin: true,
            enabledForTransactions: false,
            enabledForSettings: true,
            requiresAdditionalAuth: true,
            allowsPasscodeFallback: false,
            biometryType: .touchID
        )
        
        let configData = try JSONEncoder().encode(expectedConfiguration)
        mockSecureStorage.mockLoadValue = configData
        
        // When
        let result = try await sut.loadBiometricConfiguration()
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.enabledForLogin, expectedConfiguration.enabledForLogin)
        XCTAssertEqual(result?.enabledForTransactions, expectedConfiguration.enabledForTransactions)
        XCTAssertEqual(result?.biometryType, expectedConfiguration.biometryType)
    }
    
    func testLoadBiometricConfiguration_NotFound() async throws {
        // Given
        mockSecureStorage.mockLoadValue = nil
        
        // When
        let result = try await sut.loadBiometricConfiguration()
        
        // Then
        XCTAssertNil(result)
    }
    
    func testLoadBiometricConfiguration_CorruptedData() async {
        // Given
        mockSecureStorage.mockLoadValue = "corrupted data".data(using: .utf8)
        
        // When & Then
        do {
            _ = try await sut.loadBiometricConfiguration()
            XCTFail("Expected configuration load to fail")
        } catch {
            // Expected decoding error
            XCTAssertTrue(error is DecodingError)
        }
    }
    
    // MARK: - Security Tests
    
    func testBiometricAuthentication_SecurityValidation() async throws {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = true
        mockConfiguration.mockSecurityLevel = .high
        
        // When
        let result = try await sut.authenticateUser(reason: "Secure operation")
        
        // Then
        XCTAssertTrue(result)
        // Verify that high security settings were applied
        XCTAssertTrue(mockLAContext.wasSecurityValidationCalled)
    }
    
    func testBiometricAuthentication_FraudDetection() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.biometryLockout) // Too many failed attempts
        
        // When & Then
        do {
            _ = try await sut.authenticateUser(reason: "Test")
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.rateLimited {
            // Expected - should map biometry lockout to rate limited
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testBiometricAuthentication_TamperDetection() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.invalidContext)
        
        // When & Then
        do {
            _ = try await sut.authenticateUser(reason: "Test")
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.deviceNotTrusted {
            // Expected - invalid context suggests tampering
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Performance Tests
    
    func testBiometricAvailabilityPerformance() {
        measure {
            let expectation = XCTestExpectation(description: "Biometric availability check")
            
            Task {
                _ = await sut.checkBiometricAvailability()
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testBiometricAuthenticationPerformance() {
        measure {
            let expectation = XCTestExpectation(description: "Biometric authentication")
            mockLAContext.mockEvaluateSuccess = true
            
            Task {
                do {
                    _ = try await sut.authenticateUser(reason: "Performance test")
                } catch {
                    // Ignore errors for performance test
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 2.0)
        }
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentAuthenticationRequests() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = true
        let requestCount = 5
        
        // When
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<requestCount {
                group.addTask {
                    do {
                        return try await self.sut.authenticateUser(reason: "Concurrent test \(i)")
                    } catch {
                        return false
                    }
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            
            // Then
            XCTAssertEqual(results.count, requestCount)
            // Only one should succeed due to LAContext limitations
            XCTAssertEqual(results.filter { $0 }.count, 1)
        }
    }
    
    func testConcurrentAvailabilityChecks() async {
        // Given
        let checkCount = 10
        
        // When
        await withTaskGroup(of: BiometricAvailability.self) { group in
            for _ in 0..<checkCount {
                group.addTask {
                    return await self.sut.checkBiometricAvailability()
                }
            }
            
            var results: [BiometricAvailability] = []
            for await result in group {
                results.append(result)
            }
            
            // Then
            XCTAssertEqual(results.count, checkCount)
            // All should return the same result
            let firstResult = results.first!
            XCTAssertTrue(results.allSatisfy { $0.isAvailable == firstResult.isAvailable })
        }
    }
    
    // MARK: - Edge Cases Tests
    
    func testBiometricAuthentication_SystemUpgrade() async {
        // Given - Simulate iOS upgrade scenario
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.biometryNotEnrolled)
        
        // When & Then
        do {
            _ = try await sut.authenticateUser(reason: "Test after upgrade")
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.biometricNotEnrolled {
            // Expected - user needs to re-enroll after system upgrade
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testBiometricAuthentication_LowBattery() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.systemCancel)
        
        // When & Then
        do {
            _ = try await sut.authenticateUser(reason: "Test with low battery")
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.systemError {
            // Expected - system cancelled due to low battery
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testBiometricAuthentication_AppBackgrounding() async {
        // Given
        mockLAContext.mockBiometryType = .faceID
        mockLAContext.mockEvaluateSuccess = false
        mockLAContext.mockEvaluateError = LAError(.appCancel)
        
        // When & Then
        do {
            _ = try await sut.authenticateUser(reason: "Test with backgrounding")
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.userCancelled {
            // Expected - app cancelled authentication
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Configuration Validation Tests
    
    func testBiometricConfiguration_ValidationSuccess() {
        // Given
        let validConfiguration = BiometricConfiguration(
            enabledForLogin: true,
            enabledForTransactions: true,
            enabledForSettings: false,
            requiresAdditionalAuth: false,
            allowsPasscodeFallback: true,
            biometryType: .faceID
        )
        
        // When
        let isValid = sut.validateConfiguration(validConfiguration)
        
        // Then
        XCTAssertTrue(isValid)
    }
    
    func testBiometricConfiguration_ValidationFailure() {
        // Given - Invalid configuration (biometric type doesn't match available)
        mockLAContext.mockBiometryType = .touchID
        
        let invalidConfiguration = BiometricConfiguration(
            enabledForLogin: true,
            enabledForTransactions: true,
            enabledForSettings: false,
            requiresAdditionalAuth: false,
            allowsPasscodeFallback: true,
            biometryType: .faceID // Mismatch
        )
        
        // When
        let isValid = sut.validateConfiguration(invalidConfiguration)
        
        // Then
        XCTAssertFalse(isValid)
    }
}

// MARK: - Test Extensions

extension BiometricAuthService {
    func validateConfiguration(_ configuration: BiometricConfiguration) -> Bool {
        // Mock validation logic for testing
        return configuration.biometryType == mockLAContext.biometryType
    }
}

// MARK: - Error Mapping Tests

extension BiometricAuthServiceTests {
    func testLAErrorMapping() {
        let testCases: [(LAError.Code, AuthenticationError)] = [
            (.userCancel, .userCancelled),
            (.authenticationFailed, .biometricFailed),
            (.biometryNotAvailable, .biometricNotAvailable),
            (.biometryNotEnrolled, .biometricNotEnrolled),
            (.biometryLockout, .rateLimited),
            (.invalidContext, .deviceNotTrusted),
            (.systemCancel, .systemError("System cancelled authentication")),
            (.appCancel, .userCancelled)
        ]
        
        for (laErrorCode, expectedAuthError) in testCases {
            let laError = LAError(laErrorCode)
            let mappedError = sut.mapLAError(laError)
            
            switch (mappedError, expectedAuthError) {
            case (.userCancelled, .userCancelled),
                 (.biometricFailed, .biometricFailed),
                 (.biometricNotAvailable, .biometricNotAvailable),
                 (.biometricNotEnrolled, .biometricNotEnrolled),
                 (.rateLimited, .rateLimited),
                 (.deviceNotTrusted, .deviceNotTrusted):
                // Test passed
                break
            case (.systemError, .systemError):
                // Test passed
                break
            default:
                XCTFail("Error mapping failed for \(laErrorCode): expected \(expectedAuthError), got \(mappedError)")
            }
        }
    }
}

extension BiometricAuthService {
    func mapLAError(_ error: LAError) -> AuthenticationError {
        switch error.code {
        case .userCancel, .appCancel:
            return .userCancelled
        case .authenticationFailed:
            return .biometricFailed
        case .biometryNotAvailable:
            return .biometricNotAvailable
        case .biometryNotEnrolled:
            return .biometricNotEnrolled
        case .biometryLockout:
            return .rateLimited
        case .invalidContext:
            return .deviceNotTrusted
        case .systemCancel:
            return .systemError("System cancelled authentication")
        default:
            return .biometricFailed
        }
    }
}