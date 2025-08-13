import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - Authentication Service Tests

final class AuthenticationServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: AuthenticationService!
    private var mockAppwriteClient: MockAppwriteClient!
    private var mockSessionManager: MockSessionManagementService!
    private var mockSecurityService: MockSecurityService!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        mockAppwriteClient = MockAppwriteClient()
        mockSessionManager = MockSessionManagementService()
        mockSecurityService = MockSecurityService()
        cancellables = Set<AnyCancellable>()
        
        sut = AuthenticationService(
            appwriteClient: mockAppwriteClient,
            sessionManager: mockSessionManager,
            securityService: mockSecurityService
        )
    }
    
    override func tearDown() {
        cancellables = nil
        sut = nil
        mockSecurityService = nil
        mockSessionManager = nil
        mockAppwriteClient = nil
        
        super.tearDown()
    }
    
    // MARK: - OAuth Authentication Tests
    
    func testSignInWithGoogle_Success() async throws {
        // Given
        let expectedUser = TestDataFactory.createAuthenticatedUser()
        let expectedSession = TestDataFactory.createAppwriteSession()
        mockAppwriteClient.mockOAuthSession = expectedSession
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.signInWithGoogle()
        
        // Then
        XCTAssertEqual(result.user.id, expectedUser.id)
        XCTAssertNotNil(result.accessToken)
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(mockAppwriteClient.createOAuth2SessionCallCount, 1)
        XCTAssertEqual(mockSessionManager.createSessionCallCount, 1)
    }
    
    func testSignInWithGoogle_NetworkError() async {
        // Given
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.networkError("Connection failed")
        
        // When & Then
        do {
            _ = try await sut.signInWithGoogle()
            XCTFail("Expected authentication to fail")
        } catch let error as AuthenticationError {
            if case .networkError = error {
                // Expected
            } else {
                XCTFail("Expected network error")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        
        XCTAssertFalse(sut.isAuthenticated)
    }
    
    func testSignInWithApple_Success() async throws {
        // Given
        let expectedResult = TestDataFactory.createAuthenticationResult()
        
        // Mock Apple Sign In success
        let mockCredential = MockASAuthorizationAppleIDCredential()
        mockCredential.user = "test_user_id"
        mockCredential.email = "test@example.com"
        mockCredential.identityToken = "mock_identity_token".data(using: .utf8)
        
        // When
        let result = try await sut.signInWithApple()
        
        // Then
        XCTAssertNotNil(result.accessToken)
        XCTAssertTrue(sut.isAuthenticated)
    }
    
    func testSignInWithFacebook_Success() async throws {
        // Given
        let expectedSession = TestDataFactory.createAppwriteSession()
        mockAppwriteClient.mockOAuthSession = expectedSession
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.signInWithFacebook()
        
        // Then
        XCTAssertNotNil(result.accessToken)
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(mockAppwriteClient.createOAuth2SessionCallCount, 1)
    }
    
    func testSignInWithMicrosoft_Success() async throws {
        // Given
        let expectedSession = TestDataFactory.createAppwriteSession()
        mockAppwriteClient.mockOAuthSession = expectedSession
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.signInWithMicrosoft()
        
        // Then
        XCTAssertNotNil(result.accessToken)
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(mockAppwriteClient.createOAuth2SessionCallCount, 1)
    }
    
    // MARK: - Enterprise Authentication Tests
    
    func testSignInWithAzureAD_Success() async throws {
        // Given
        let tenantId = "test_tenant_id"
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.signInWithAzureAD(tenantId: tenantId)
        
        // Then
        XCTAssertNotNil(result.accessToken)
        XCTAssertTrue(sut.isAuthenticated)
    }
    
    func testSignInWithGoogleWorkspace_Success() async throws {
        // Given
        let domain = "example.com"
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.signInWithGoogleWorkspace(domain: domain)
        
        // Then
        XCTAssertNotNil(result.accessToken)
        XCTAssertTrue(sut.isAuthenticated)
    }
    
    func testSignInWithOkta_Success() async throws {
        // Given
        let orgUrl = "https://example.okta.com"
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.signInWithOkta(orgUrl: orgUrl)
        
        // Then
        XCTAssertNotNil(result.accessToken)
        XCTAssertTrue(sut.isAuthenticated)
    }
    
    func testSignInWithCustomOIDC_Success() async throws {
        // Given
        let oidcConfig = TestDataFactory.createOIDCConfiguration()
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.signInWithCustomOIDC(configuration: oidcConfig)
        
        // Then
        XCTAssertNotNil(result.accessToken)
        XCTAssertTrue(sut.isAuthenticated)
    }
    
    // MARK: - JWT Token Management Tests
    
    func testValidateToken_ValidToken() async throws {
        // Given
        let validToken = TestDataFactory.createValidJWTToken()
        let expectedUser = TestDataFactory.createAuthenticatedUser()
        
        // When
        let result = try await sut.validateToken(validToken)
        
        // Then
        XCTAssertTrue(result.isValid)
        XCTAssertNotNil(result.user)
        XCTAssertGreaterThan(result.remainingTime, 0)
    }
    
    func testValidateToken_ExpiredToken() async throws {
        // Given
        let expiredToken = TestDataFactory.createExpiredJWTToken()
        
        // When
        let result = try await sut.validateToken(expiredToken)
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.user)
        XCTAssertEqual(result.remainingTime, 0)
    }
    
    func testValidateToken_InvalidToken() async throws {
        // Given
        let invalidToken = "invalid.token.here"
        
        // When
        let result = try await sut.validateToken(invalidToken)
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.user)
    }
    
    func testRefreshToken_Success() async throws {
        // Given
        let refreshToken = "valid_refresh_token"
        let expectedResult = TestDataFactory.createSessionRefreshResult()
        mockSessionManager.mockRefreshResult = expectedResult
        
        // Set up authenticated user
        sut.setCurrentUser(TestDataFactory.createAuthenticatedUser())
        
        // When
        let result = try await sut.refreshToken(refreshToken)
        
        // Then
        XCTAssertNotNil(result.accessToken)
        XCTAssertEqual(mockSessionManager.refreshAccessTokenCallCount, 1)
    }
    
    func testRefreshToken_ExpiredRefreshToken() async {
        // Given
        let expiredRefreshToken = "expired_refresh_token"
        mockSessionManager.shouldThrowError = true
        mockSessionManager.errorToThrow = AuthenticationError.refreshTokenExpired
        
        // When & Then
        do {
            _ = try await sut.refreshToken(expiredRefreshToken)
            XCTFail("Expected refresh to fail")
        } catch AuthenticationError.refreshTokenExpired {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testRevokeToken_Success() async throws {
        // Given
        let token = "valid_token"
        
        // When
        try await sut.revokeToken(token)
        
        // Then
        XCTAssertEqual(mockSessionManager.revokeTokenCallCount, 1)
    }
    
    func testGetStoredToken_Success() async {
        // Given
        let expectedToken = TestDataFactory.createStoredToken()
        MockSecureKeychainHelper.mockTokenData = expectedToken
        
        // When
        let result = await sut.getStoredToken()
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.accessToken, expectedToken.accessToken)
    }
    
    func testGetStoredToken_NoToken() async {
        // Given
        MockSecureKeychainHelper.mockTokenData = nil
        
        // When
        let result = await sut.getStoredToken()
        
        // Then
        XCTAssertNil(result)
    }
    
    func testClearStoredTokens_Success() async throws {
        // Given
        sut.setCurrentUser(TestDataFactory.createAuthenticatedUser())
        
        // When
        try await sut.clearStoredTokens()
        
        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
    }
    
    // MARK: - Multi-Tenant Support Tests
    
    func testSwitchTenant_Success() async throws {
        // Given
        let tenantId = "new_tenant_id"
        let currentUser = TestDataFactory.createAuthenticatedUser()
        let targetTenant = TestDataFactory.createTenantInfo(id: tenantId)
        
        sut.setCurrentUser(currentUser)
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.switchTenant(tenantId)
        
        // Then
        XCTAssertEqual(result.newTenant.id, tenantId)
        XCTAssertEqual(result.user.id, currentUser.id)
        XCTAssertNotNil(result.newToken)
    }
    
    func testSwitchTenant_InsufficientPermissions() async {
        // Given
        let tenantId = "unauthorized_tenant_id"
        let currentUser = TestDataFactory.createAuthenticatedUser()
        sut.setCurrentUser(currentUser)
        
        // Mock validation to return false
        mockSessionManager.mockValidateTenantAccess = false
        
        // When & Then
        do {
            _ = try await sut.switchTenant(tenantId)
            XCTFail("Expected switch to fail")
        } catch AuthenticationError.insufficientPermissions {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testGetCurrentTenant_Success() async {
        // Given
        let expectedTenant = TestDataFactory.createTenantInfo()
        sut.setCurrentTenant(expectedTenant)
        
        // When
        let result = await sut.getCurrentTenant()
        
        // Then
        XCTAssertEqual(result?.id, expectedTenant.id)
    }
    
    func testGetUserTenants_Success() async throws {
        // Given
        let currentUser = TestDataFactory.createAuthenticatedUser()
        let expectedTenants = TestDataFactory.createTenantList()
        sut.setCurrentUser(currentUser)
        
        // When
        let result = try await sut.getUserTenants()
        
        // Then
        XCTAssertEqual(result.count, expectedTenants.count)
    }
    
    // MARK: - Session Management Tests
    
    func testGetCurrentSession_Success() async {
        // Given
        let currentUser = TestDataFactory.createAuthenticatedUser()
        let expectedSessions = [TestDataFactory.createSessionInfo()]
        sut.setCurrentUser(currentUser)
        mockSessionManager.mockUserSessions = expectedSessions
        
        // When
        let result = await sut.getCurrentSession()
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.userId, currentUser.id)
    }
    
    func testValidateSession_Success() async throws {
        // Given
        let sessionId = "valid_session_id"
        let expectedResult = TestDataFactory.createSessionValidationResult(isValid: true)
        mockSessionManager.mockValidationResult = expectedResult
        
        // When
        let result = try await sut.validateSession(sessionId)
        
        // Then
        XCTAssertTrue(result.isValid)
        XCTAssertNotNil(result.session)
        XCTAssertFalse(result.requiresReauth)
    }
    
    func testValidateSession_Invalid() async throws {
        // Given
        let sessionId = "invalid_session_id"
        let expectedResult = TestDataFactory.createSessionValidationResult(isValid: false)
        mockSessionManager.mockValidationResult = expectedResult
        
        // When
        let result = try await sut.validateSession(sessionId)
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.session)
    }
    
    func testTerminateSession_Success() async throws {
        // Given
        let sessionId = "session_to_terminate"
        
        // When
        try await sut.terminateSession(sessionId)
        
        // Then
        XCTAssertEqual(mockSessionManager.terminateSessionCallCount, 1)
    }
    
    func testTerminateAllSessions_Success() async throws {
        // Given
        let currentUser = TestDataFactory.createAuthenticatedUser()
        sut.setCurrentUser(currentUser)
        
        // When
        try await sut.terminateAllSessions()
        
        // Then
        XCTAssertEqual(mockSessionManager.terminateAllUserSessionsCallCount, 1)
        XCTAssertFalse(sut.isAuthenticated)
    }
    
    // MARK: - Multi-Factor Authentication Tests
    
    func testEnableMFA_Success() async throws {
        // Given
        let currentUser = TestDataFactory.createAuthenticatedUser()
        sut.setCurrentUser(currentUser)
        
        // When
        let result = try await sut.enableMFA()
        
        // Then
        XCTAssertNotNil(result.secret)
        XCTAssertNotNil(result.qrCodeURL)
        XCTAssertFalse(result.backupCodes.isEmpty)
        XCTAssertEqual(result.method, .totp)
    }
    
    func testEnableMFA_NoCurrentUser() async {
        // Given
        // No current user set
        
        // When & Then
        do {
            _ = try await sut.enableMFA()
            XCTFail("Expected MFA setup to fail")
        } catch AuthenticationError.invalidCredentials {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testDisableMFA_Success() async throws {
        // Given
        let currentUser = TestDataFactory.createAuthenticatedUser()
        sut.setCurrentUser(currentUser)
        
        // When
        try await sut.disableMFA()
        
        // Then
        // Should complete without error
    }
    
    func testValidateMFA_ValidTOTP() async throws {
        // Given
        let currentUser = TestDataFactory.createAuthenticatedUser()
        let validCode = "123456"
        sut.setCurrentUser(currentUser)
        
        // Mock MFA settings
        mockAppwriteClient.mockMFASettings = TestDataFactory.createMFASettings()
        
        // When
        let result = try await sut.validateMFA(code: validCode, method: .totp)
        
        // Then
        XCTAssertTrue(result)
    }
    
    func testValidateMFA_InvalidCode() async throws {
        // Given
        let currentUser = TestDataFactory.createAuthenticatedUser()
        let invalidCode = "000000"
        sut.setCurrentUser(currentUser)
        
        mockAppwriteClient.mockMFASettings = TestDataFactory.createMFASettings()
        
        // When
        let result = try await sut.validateMFA(code: invalidCode, method: .totp)
        
        // Then
        XCTAssertFalse(result)
    }
    
    func testValidateMFA_BackupCode() async throws {
        // Given
        let currentUser = TestDataFactory.createAuthenticatedUser()
        let backupCode = "backup123"
        sut.setCurrentUser(currentUser)
        
        let mfaSettings = TestDataFactory.createMFASettings()
        mfaSettings.backupCodes = [backupCode, "backup456"]
        mockAppwriteClient.mockMFASettings = mfaSettings
        
        // When
        let result = try await sut.validateMFA(code: backupCode, method: .backup)
        
        // Then
        XCTAssertTrue(result)
    }
    
    func testGenerateBackupCodes_Success() async throws {
        // When
        let codes = try await sut.generateBackupCodes()
        
        // Then
        XCTAssertEqual(codes.count, 10)
        XCTAssertTrue(codes.allSatisfy { $0.count == 8 })
    }
    
    // MARK: - Security & Tenant Isolation Tests
    
    func testValidateTenantAccess_HasAccess() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let userId = "test_user_id"
        mockAppwriteClient.mockTenantMemberships = [
            TestDataFactory.createTenantMembership(tenantId: tenantId, userId: userId)
        ]
        
        // When
        let result = try await sut.validateTenantAccess(tenantId, userId: userId)
        
        // Then
        XCTAssertTrue(result)
    }
    
    func testValidateTenantAccess_NoAccess() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let userId = "test_user_id"
        mockAppwriteClient.mockTenantMemberships = [] // No memberships
        
        // When
        let result = try await sut.validateTenantAccess(tenantId, userId: userId)
        
        // Then
        XCTAssertFalse(result)
    }
    
    func testAuditAuthenticationAttempt_Success() async {
        // Given
        let attempt = TestDataFactory.createAuthenticationAttempt(success: true)
        
        // When
        await sut.auditAuthenticationAttempt(attempt)
        
        // Then
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testAuditAuthenticationAttempt_Failure() async {
        // Given
        let attempt = TestDataFactory.createAuthenticationAttempt(success: false)
        
        // When
        await sut.auditAuthenticationAttempt(attempt)
        
        // Then
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    // MARK: - Authentication State Management Tests
    
    func testAuthenticationStateChanges() {
        // Given
        let expectation = XCTestExpectation(description: "Authentication state changes")
        var receivedStates: [AuthenticationState] = []
        
        sut.authenticationStateChanged
            .sink { state in
                receivedStates.append(state)
                if receivedStates.count == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        let user = TestDataFactory.createAuthenticatedUser()
        let tenant = TestDataFactory.createTenantInfo()
        
        sut.setCurrentUser(user)
        sut.setCurrentTenant(tenant)
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStates.count, 2)
        
        if case .authenticated(let receivedUser, let receivedTenant) = receivedStates.last {
            XCTAssertEqual(receivedUser.id, user.id)
            XCTAssertEqual(receivedTenant?.id, tenant.id)
        } else {
            XCTFail("Expected authenticated state")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testNetworkErrorHandling() async {
        // Given
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.networkError("Network unavailable")
        
        // When & Then
        do {
            _ = try await sut.signInWithGoogle()
            XCTFail("Expected network error")
        } catch AuthenticationError.networkError(let message) {
            XCTAssertEqual(message, "Network unavailable")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testTokenExpiredErrorHandling() async {
        // Given
        let expiredToken = TestDataFactory.createExpiredJWTToken()
        
        // When
        let result = try await sut.validateToken(expiredToken)
        
        // Then
        XCTAssertFalse(result.isValid)
    }
    
    func testMFARequiredErrorHandling() async {
        // Given
        mockSessionManager.shouldThrowError = true
        mockSessionManager.errorToThrow = AuthenticationError.mfaRequired
        
        // When & Then
        do {
            _ = try await sut.signInWithGoogle()
            XCTFail("Expected MFA required error")
        } catch AuthenticationError.mfaRequired {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Performance Tests
    
    func testAuthenticationPerformance() {
        measure {
            let expectation = XCTestExpectation(description: "Authentication performance")
            
            Task {
                do {
                    _ = try await sut.signInWithGoogle()
                } catch {
                    // Ignore errors for performance test
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testTokenValidationPerformance() {
        let token = TestDataFactory.createValidJWTToken()
        
        measure {
            let expectation = XCTestExpectation(description: "Token validation performance")
            
            Task {
                do {
                    _ = try await sut.validateToken(token)
                } catch {
                    // Ignore errors for performance test
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentAuthentication() async {
        // Given
        let taskCount = 10
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    do {
                        _ = try await self.sut.signInWithGoogle()
                    } catch {
                        // Ignore errors for concurrency test
                    }
                }
            }
        }
        
        // Then
        // Should complete without crashes or deadlocks
        XCTAssertTrue(true) // Test completion indicates success
    }
    
    func testConcurrentTokenValidation() async {
        // Given
        let token = TestDataFactory.createValidJWTToken()
        let taskCount = 20
        
        // When
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    do {
                        let result = try await self.sut.validateToken(token)
                        return result.isValid
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
            XCTAssertEqual(results.count, taskCount)
        }
    }
}

// MARK: - Extensions for Testing

extension AuthenticationService {
    func setCurrentUser(_ user: AuthenticatedUser?) {
        self._currentUser = user
    }
    
    func setCurrentTenant(_ tenant: TenantInfo?) {
        self._currentTenant = tenant
    }
}