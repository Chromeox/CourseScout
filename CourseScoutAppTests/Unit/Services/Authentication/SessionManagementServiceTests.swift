import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - Session Management Service Tests

final class SessionManagementServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: SessionManagementService!
    private var mockAppwriteClient: MockAppwriteClient!
    private var mockSecurityService: MockSecurityService!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        mockAppwriteClient = MockAppwriteClient()
        mockSecurityService = MockSecurityService()
        cancellables = Set<AnyCancellable>()
        
        sut = SessionManagementService(
            appwriteClient: mockAppwriteClient,
            securityService: mockSecurityService
        )
    }
    
    override func tearDown() {
        cancellables = nil
        sut = nil
        mockSecurityService = nil
        mockAppwriteClient = nil
        
        super.tearDown()
    }
    
    // MARK: - Session Creation Tests
    
    func testCreateSession_Success() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let deviceInfo = TestDataFactory.createDeviceInfo()
        let expectedResult = TestDataFactory.createSessionResult()
        mockAppwriteClient.mockSessionResult = expectedResult
        
        // When
        let result = try await sut.createSession(
            userId: userId,
            tenantId: tenantId,
            deviceInfo: deviceInfo
        )
        
        // Then
        XCTAssertEqual(result.accessToken.userId, userId)
        XCTAssertEqual(result.accessToken.tenantId, tenantId)
        XCTAssertNotNil(result.refreshToken)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testCreateSession_DuplicateDeviceSession() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let deviceInfo = TestDataFactory.createDeviceInfo()
        
        // Mock existing session for same device
        let existingSession = TestDataFactory.createSessionInfo(userId: userId, deviceId: deviceInfo.deviceId)
        mockAppwriteClient.mockExistingSessions = [existingSession]
        
        let expectedResult = TestDataFactory.createSessionResult()
        mockAppwriteClient.mockSessionResult = expectedResult
        
        // When
        let result = try await sut.createSession(
            userId: userId,
            tenantId: tenantId,
            deviceInfo: deviceInfo
        )
        
        // Then
        XCTAssertNotNil(result)
        // Should invalidate existing session and create new one
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1) // Invalidate old
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1) // Create new
    }
    
    func testCreateSession_MaxSessionsExceeded() async {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let deviceInfo = TestDataFactory.createDeviceInfo()
        
        // Mock max sessions already exist
        let existingSessions = (1...10).map { TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_\($0)") }
        mockAppwriteClient.mockExistingSessions = existingSessions
        
        // When & Then
        do {
            _ = try await sut.createSession(userId: userId, tenantId: tenantId, deviceInfo: deviceInfo)
            XCTFail("Expected session creation to fail")
        } catch AuthenticationError.maxSessionsExceeded {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateSession_SuspiciousDevice() async {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let suspiciousDevice = TestDataFactory.createSuspiciousDeviceInfo()
        mockSecurityService.mockSuspiciousActivity = true
        
        // When & Then
        do {
            _ = try await sut.createSession(userId: userId, tenantId: tenantId, deviceInfo: suspiciousDevice)
            XCTFail("Expected session creation to fail")
        } catch AuthenticationError.suspiciousActivity {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Session Validation Tests
    
    func testValidateSession_ValidSession() async throws {
        // Given
        let sessionId = "valid_session_id"
        let validSession = TestDataFactory.createSessionInfo(id: sessionId, isActive: true)
        mockAppwriteClient.mockSessionInfo = validSession
        
        // When
        let result = try await sut.validateSession(sessionId: sessionId)
        
        // Then
        XCTAssertTrue(result.isValid)
        XCTAssertNotNil(result.session)
        XCTAssertFalse(result.requiresReauth)
        XCTAssertFalse(result.suspiciousActivity)
    }
    
    func testValidateSession_ExpiredSession() async throws {
        // Given
        let sessionId = "expired_session_id"
        let expiredSession = TestDataFactory.createExpiredSessionInfo(id: sessionId)
        mockAppwriteClient.mockSessionInfo = expiredSession
        
        // When
        let result = try await sut.validateSession(sessionId: sessionId)
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.session)
        XCTAssertTrue(result.requiresReauth)
    }
    
    func testValidateSession_InactiveSession() async throws {
        // Given
        let sessionId = "inactive_session_id"
        let inactiveSession = TestDataFactory.createSessionInfo(id: sessionId, isActive: false)
        mockAppwriteClient.mockSessionInfo = inactiveSession
        
        // When
        let result = try await sut.validateSession(sessionId: sessionId)
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.session)
        XCTAssertTrue(result.requiresReauth)
    }
    
    func testValidateSession_SuspiciousActivity() async throws {
        // Given
        let sessionId = "suspicious_session_id"
        let session = TestDataFactory.createSessionInfo(id: sessionId, isActive: true)
        mockAppwriteClient.mockSessionInfo = session
        mockSecurityService.mockSuspiciousActivity = true
        
        // When
        let result = try await sut.validateSession(sessionId: sessionId)
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.session)
        XCTAssertTrue(result.suspiciousActivity)
    }
    
    func testValidateSession_NotFound() async throws {
        // Given
        let sessionId = "nonexistent_session_id"
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.sessionNotFound
        
        // When
        let result = try await sut.validateSession(sessionId: sessionId)
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.session)
    }
    
    // MARK: - Token Refresh Tests
    
    func testRefreshAccessToken_Success() async throws {
        // Given
        let refreshToken = "valid_refresh_token"
        let originalSession = TestDataFactory.createSessionInfo()
        let refreshResult = TestDataFactory.createSessionRefreshResult()
        
        mockAppwriteClient.mockSessionInfo = originalSession
        mockAppwriteClient.mockRefreshResult = refreshResult
        
        // When
        let result = try await sut.refreshAccessToken(refreshToken: refreshToken)
        
        // Then
        XCTAssertNotNil(result.newAccessToken)
        XCTAssertNotNil(result.newRefreshToken)
        XCTAssertGreaterThan(result.newAccessToken.expiresAt, Date())
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testRefreshAccessToken_ExpiredRefreshToken() async {
        // Given
        let expiredRefreshToken = "expired_refresh_token"
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.refreshTokenExpired
        
        // When & Then
        do {
            _ = try await sut.refreshAccessToken(refreshToken: expiredRefreshToken)
            XCTFail("Expected refresh to fail")
        } catch AuthenticationError.refreshTokenExpired {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testRefreshAccessToken_InvalidRefreshToken() async {
        // Given
        let invalidRefreshToken = "invalid_refresh_token"
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.invalidCredentials
        
        // When & Then
        do {
            _ = try await sut.refreshAccessToken(refreshToken: invalidRefreshToken)
            XCTFail("Expected refresh to fail")
        } catch AuthenticationError.invalidCredentials {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testRefreshAccessToken_TokenRotation() async throws {
        // Given
        let refreshToken = "valid_refresh_token"
        let originalSession = TestDataFactory.createSessionInfo()
        let refreshResult = TestDataFactory.createSessionRefreshResult()
        
        mockAppwriteClient.mockSessionInfo = originalSession
        mockAppwriteClient.mockRefreshResult = refreshResult
        
        // When
        let result = try await sut.refreshAccessToken(refreshToken: refreshToken)
        
        // Then
        // Refresh token should be rotated (new token different from old)
        XCTAssertNotEqual(result.newRefreshToken?.token, refreshToken)
        XCTAssertNotNil(result.newRefreshToken)
    }
    
    // MARK: - Session Termination Tests
    
    func testTerminateSession_Success() async throws {
        // Given
        let sessionId = "session_to_terminate"
        let sessionToTerminate = TestDataFactory.createSessionInfo(id: sessionId, isActive: true)
        mockAppwriteClient.mockSessionInfo = sessionToTerminate
        
        // When
        try await sut.terminateSession(sessionId: sessionId)
        
        // Then
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testTerminateSession_NotFound() async {
        // Given
        let sessionId = "nonexistent_session_id"
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.sessionNotFound
        
        // When & Then
        do {
            try await sut.terminateSession(sessionId: sessionId)
            XCTFail("Expected termination to fail")
        } catch AuthenticationError.sessionNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testTerminateAllUserSessions_Success() async throws {
        // Given
        let userId = "test_user_id"
        let excludeCurrentDevice = false
        let userSessions = [
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_1"),
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_2"),
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_3")
        ]
        mockAppwriteClient.mockUserSessions = userSessions
        
        // When
        try await sut.terminateAllUserSessions(userId: userId, excludeCurrentDevice: excludeCurrentDevice)
        
        // Then
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 3) // All sessions updated
    }
    
    func testTerminateAllUserSessions_ExcludeCurrentDevice() async throws {
        // Given
        let userId = "test_user_id"
        let currentDeviceId = "current_device"
        let excludeCurrentDevice = true
        
        let userSessions = [
            TestDataFactory.createSessionInfo(userId: userId, deviceId: currentDeviceId),
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_2"),
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_3")
        ]
        mockAppwriteClient.mockUserSessions = userSessions
        
        // Mock current device detection
        mockAppwriteClient.mockCurrentDeviceId = currentDeviceId
        
        // When
        try await sut.terminateAllUserSessions(userId: userId, excludeCurrentDevice: excludeCurrentDevice)
        
        // Then
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 2) // Only other sessions updated
    }
    
    // MARK: - Token Revocation Tests
    
    func testRevokeToken_AccessToken() async throws {
        // Given
        let token = "access_token_to_revoke"
        let tokenType = TokenType.accessToken
        let sessionInfo = TestDataFactory.createSessionInfo()
        mockAppwriteClient.mockSessionInfo = sessionInfo
        
        // When
        try await sut.revokeToken(token: token, tokenType: tokenType)
        
        // Then
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testRevokeToken_RefreshToken() async throws {
        // Given
        let token = "refresh_token_to_revoke"
        let tokenType = TokenType.refreshToken
        let sessionInfo = TestDataFactory.createSessionInfo()
        mockAppwriteClient.mockSessionInfo = sessionInfo
        
        // When
        try await sut.revokeToken(token: token, tokenType: tokenType)
        
        // Then
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testRevokeToken_InvalidToken() async {
        // Given
        let invalidToken = "invalid_token"
        let tokenType = TokenType.accessToken
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.invalidCredentials
        
        // When & Then
        do {
            try await sut.revokeToken(token: invalidToken, tokenType: tokenType)
            XCTFail("Expected revocation to fail")
        } catch AuthenticationError.invalidCredentials {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Session Queries Tests
    
    func testGetUserSessions_Success() async throws {
        // Given
        let userId = "test_user_id"
        let expectedSessions = [
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_1"),
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_2")
        ]
        mockAppwriteClient.mockUserSessions = expectedSessions
        
        // When
        let result = try await sut.getUserSessions(userId: userId)
        
        // Then
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.userId == userId })
    }
    
    func testGetActiveSessions_Success() async throws {
        // Given
        let userId = "test_user_id"
        let allSessions = [
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_1", isActive: true),
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_2", isActive: false),
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "device_3", isActive: true)
        ]
        mockAppwriteClient.mockUserSessions = allSessions
        
        // When
        let result = try await sut.getActiveSessions(userId: userId)
        
        // Then
        XCTAssertEqual(result.count, 2) // Only active sessions
        XCTAssertTrue(result.allSatisfy { $0.isActive })
    }
    
    func testGetSessionsByDevice_Success() async throws {
        // Given
        let userId = "test_user_id"
        let deviceId = "target_device"
        let allSessions = [
            TestDataFactory.createSessionInfo(userId: userId, deviceId: deviceId),
            TestDataFactory.createSessionInfo(userId: userId, deviceId: "other_device"),
            TestDataFactory.createSessionInfo(userId: userId, deviceId: deviceId)
        ]
        mockAppwriteClient.mockUserSessions = allSessions
        
        // When
        let result = try await sut.getSessionsByDevice(userId: userId, deviceId: deviceId)
        
        // Then
        XCTAssertEqual(result.count, 2) // Only sessions for target device
        XCTAssertTrue(result.allSatisfy { $0.deviceId == deviceId })
    }
    
    // MARK: - Session Analytics Tests
    
    func testGetSessionAnalytics_Success() async throws {
        // Given
        let userId = "test_user_id"
        let timeRange = DateInterval(start: Date().addingTimeInterval(-7*24*3600), end: Date())
        let sessions = TestDataFactory.createSessionAnalyticsData(userId: userId, timeRange: timeRange)
        mockAppwriteClient.mockSessionAnalytics = sessions
        
        // When
        let result = try await sut.getSessionAnalytics(userId: userId, timeRange: timeRange)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result.totalSessions, 0)
        XCTAssertGreaterThan(result.averageSessionDuration, 0)
    }
    
    func testGetDeviceStatistics_Success() async throws {
        // Given
        let userId = "test_user_id"
        let deviceStats = TestDataFactory.createDeviceStatistics(userId: userId)
        mockAppwriteClient.mockDeviceStatistics = deviceStats
        
        // When
        let result = try await sut.getDeviceStatistics(userId: userId)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result.uniqueDevices, 0)
        XCTAssertFalse(result.deviceBreakdown.isEmpty)
    }
    
    // MARK: - Security Monitoring Tests
    
    func testDetectAnomalousActivity_LoginFromNewLocation() async throws {
        // Given
        let userId = "test_user_id"
        let newLocation = LocationInfo(city: "Unknown City", country: "Unknown Country", latitude: 0.0, longitude: 0.0)
        let deviceInfo = TestDataFactory.createDeviceInfo()
        
        mockSecurityService.mockAnomalousActivity = true
        
        // When
        let result = try await sut.analyzeSessionSecurity(
            userId: userId,
            deviceInfo: deviceInfo,
            location: newLocation
        )
        
        // Then
        XCTAssertTrue(result.hasAnomalousActivity)
        XCTAssertContains(result.securityFlags, .newLocationLogin)
    }
    
    func testDetectAnomalousActivity_UnusualTimeLogin() async throws {
        // Given
        let userId = "test_user_id"
        let deviceInfo = TestDataFactory.createDeviceInfo()
        let unusualTime = Date() // 3 AM local time
        
        mockSecurityService.mockAnomalousActivity = true
        
        // When
        let result = try await sut.analyzeSessionSecurity(
            userId: userId,
            deviceInfo: deviceInfo,
            loginTime: unusualTime
        )
        
        // Then
        XCTAssertTrue(result.hasAnomalousActivity)
        XCTAssertContains(result.securityFlags, .unusualTimeLogin)
    }
    
    func testDetectAnomalousActivity_MultipleFailedAttempts() async throws {
        // Given
        let userId = "test_user_id"
        let deviceInfo = TestDataFactory.createDeviceInfo()
        
        // Mock multiple recent failed attempts
        mockSecurityService.mockFailedAttempts = 5
        mockSecurityService.mockAnomalousActivity = true
        
        // When
        let result = try await sut.analyzeSessionSecurity(
            userId: userId,
            deviceInfo: deviceInfo
        )
        
        // Then
        XCTAssertTrue(result.hasAnomalousActivity)
        XCTAssertContains(result.securityFlags, .multipleFailedAttempts)
    }
    
    // MARK: - Performance Tests
    
    func testSessionCreationPerformance() {
        let userId = "test_user_id"
        let deviceInfo = TestDataFactory.createDeviceInfo()
        
        measure {
            let expectation = XCTestExpectation(description: "Session creation performance")
            
            Task {
                do {
                    _ = try await sut.createSession(
                        userId: userId,
                        tenantId: nil,
                        deviceInfo: deviceInfo
                    )
                } catch {
                    // Ignore errors for performance test
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testBulkSessionValidationPerformance() {
        let sessionIds = (1...100).map { "session_\($0)" }
        
        measure {
            let expectation = XCTestExpectation(description: "Bulk validation performance")
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for sessionId in sessionIds {
                        group.addTask {
                            do {
                                _ = try await self.sut.validateSession(sessionId: sessionId)
                            } catch {
                                // Ignore errors for performance test
                            }
                        }
                    }
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentSessionOperations() async {
        // Given
        let userId = "test_user_id"
        let deviceInfo = TestDataFactory.createDeviceInfo()
        let taskCount = 10
        
        // When
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    do {
                        if i % 2 == 0 {
                            _ = try await self.sut.createSession(
                                userId: userId,
                                tenantId: nil,
                                deviceInfo: deviceInfo
                            )
                        } else {
                            _ = try await self.sut.validateSession(sessionId: "session_\(i)")
                        }
                        return true
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
    
    // MARK: - Edge Case Tests
    
    func testSessionWithInvalidDeviceInfo() async {
        // Given
        let userId = "test_user_id"
        let invalidDeviceInfo = DeviceInfo(
            deviceId: "", // Empty device ID
            name: "Test Device",
            model: "iPhone",
            osVersion: "15.0",
            appVersion: "1.0",
            platform: .iOS,
            screenResolution: "375x812",
            biometricCapabilities: [],
            isJailbroken: false,
            isEmulator: false,
            fingerprint: "test_fingerprint"
        )
        
        // When & Then
        do {
            _ = try await sut.createSession(
                userId: userId,
                tenantId: nil,
                deviceInfo: invalidDeviceInfo
            )
            XCTFail("Expected session creation to fail")
        } catch AuthenticationError.invalidInput {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSessionWithExtremeDateValues() async throws {
        // Given
        let userId = "test_user_id"
        let deviceInfo = TestDataFactory.createDeviceInfo()
        
        // Test with session that expires far in the future
        let farFutureSession = SessionInfo(
            id: "future_session",
            userId: userId,
            tenantId: nil,
            deviceId: deviceInfo.deviceId,
            createdAt: Date(),
            lastAccessedAt: Date(),
            expiresAt: Date(timeIntervalSince1970: 4102444800), // Year 2100
            ipAddress: "127.0.0.1",
            userAgent: "TestAgent",
            isActive: true
        )
        
        mockAppwriteClient.mockSessionInfo = farFutureSession
        
        // When
        let result = try await sut.validateSession(sessionId: "future_session")
        
        // Then
        XCTAssertTrue(result.isValid)
        XCTAssertNotNil(result.session)
    }
}