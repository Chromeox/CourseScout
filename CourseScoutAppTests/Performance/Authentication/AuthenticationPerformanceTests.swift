import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - Authentication Performance Tests

final class AuthenticationPerformanceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var authService: AuthenticationService!
    private var sessionManager: SessionManagementService!
    private var userProfileService: UserProfileService!
    private var roleService: RoleManagementService!
    private var enterpriseService: EnterpriseAuthService!
    
    private var mockAppwriteClient: MockAppwriteClient!
    private var mockSecurityService: MockSecurityService!
    private var performanceMonitor: PerformanceMonitor!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        mockAppwriteClient = MockAppwriteClient()
        mockSecurityService = MockSecurityService()
        performanceMonitor = PerformanceMonitor()
        
        // Initialize services
        sessionManager = SessionManagementService(
            appwriteClient: mockAppwriteClient,
            securityService: mockSecurityService
        )
        
        userProfileService = UserProfileService(
            appwriteClient: mockAppwriteClient,
            securityService: mockSecurityService
        )
        
        roleService = RoleManagementService(
            appwriteClient: mockAppwriteClient,
            securityService: mockSecurityService
        )
        
        enterpriseService = EnterpriseAuthService(
            appwriteClient: mockAppwriteClient,
            securityService: mockSecurityService,
            sessionManager: sessionManager
        )
        
        authService = AuthenticationService(
            appwriteClient: mockAppwriteClient,
            sessionManager: sessionManager,
            securityService: mockSecurityService
        )
    }
    
    override func tearDown() {
        performanceMonitor = nil
        authService = nil
        sessionManager = nil
        userProfileService = nil
        roleService = nil
        enterpriseService = nil
        mockSecurityService = nil
        mockAppwriteClient = nil
        
        super.tearDown()
    }
    
    // MARK: - Authentication Performance Tests
    
    func testAuthenticationPerformance_SingleUserLogin() {
        // Given
        let expectedUser = TestDataFactory.createAuthenticatedUser()
        let expectedSession = TestDataFactory.createSessionResult()
        mockAppwriteClient.mockOAuthSession = TestDataFactory.createAppwriteSession()
        mockAppwriteClient.mockSessionResult = expectedSession
        
        // When - Measure authentication performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "Single user login")
            
            Task {
                do {
                    _ = try await authService.signInWithGoogle()
                } catch {
                    // Ignore errors for performance test
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    func testAuthenticationPerformance_ConcurrentUserLogins() {
        // Given
        let userCount = 100
        let users = (1...userCount).map { TestDataFactory.createAuthenticatedUser(id: "user_\($0)") }
        
        // Setup mocks for concurrent requests
        mockAppwriteClient.mockOAuthSession = TestDataFactory.createAppwriteSession()
        mockAppwriteClient.mockSessionResult = TestDataFactory.createSessionResult()
        
        // When - Measure concurrent authentication performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            let expectation = XCTestExpectation(description: "Concurrent user logins")
            expectation.expectedFulfillmentCount = userCount
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for user in users {
                        group.addTask {
                            do {
                                _ = try await self.authService.signInWithGoogle()
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    func testAuthenticationPerformance_TokenValidation() {
        // Given
        let user = TestDataFactory.createAuthenticatedUser()
        let validToken = try! authService.generateJWT(for: user)
        
        // When - Measure token validation performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "Token validation")
            expectation.expectedFulfillmentCount = 1000 // Validate 1000 tokens
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 1...1000 {
                        group.addTask {
                            do {
                                _ = try await self.authService.validateToken(validToken)
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    func testAuthenticationPerformance_JWTGeneration() {
        // Given
        let user = TestDataFactory.createAuthenticatedUser()
        
        // When - Measure JWT generation performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for _ in 1...1000 {
                do {
                    _ = try authService.generateJWT(
                        for: user,
                        tenantId: "test_tenant",
                        scopes: ["read", "write"]
                    )
                } catch {
                    // Ignore errors for performance test
                }
            }
        }
    }
    
    // MARK: - Session Management Performance Tests
    
    func testSessionPerformance_SessionCreation() {
        // Given
        let user = TestDataFactory.createAuthenticatedUser()
        let deviceInfo = TestDataFactory.createDeviceInfo()
        mockAppwriteClient.mockSessionResult = TestDataFactory.createSessionResult()
        
        // When - Measure session creation performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "Session creation")
            expectation.expectedFulfillmentCount = 100
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for i in 1...100 {
                        group.addTask {
                            let modifiedDeviceInfo = DeviceInfo(
                                deviceId: "device_\(i)",
                                name: deviceInfo.name,
                                model: deviceInfo.model,
                                osVersion: deviceInfo.osVersion,
                                appVersion: deviceInfo.appVersion,
                                platform: deviceInfo.platform,
                                screenResolution: deviceInfo.screenResolution,
                                biometricCapabilities: deviceInfo.biometricCapabilities,
                                isJailbroken: deviceInfo.isJailbroken,
                                isEmulator: deviceInfo.isEmulator,
                                fingerprint: "fingerprint_\(i)"
                            )
                            
                            do {
                                _ = try await self.sessionManager.createSession(
                                    userId: user.id,
                                    tenantId: nil,
                                    deviceInfo: modifiedDeviceInfo
                                )
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 15.0)
        }
    }
    
    func testSessionPerformance_SessionValidation() {
        // Given
        let sessionId = "test_session_id"
        let validSession = TestDataFactory.createSessionInfo(id: sessionId, isActive: true)
        mockAppwriteClient.mockSessionInfo = validSession
        
        // When - Measure session validation performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "Session validation")
            expectation.expectedFulfillmentCount = 500
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 1...500 {
                        group.addTask {
                            do {
                                _ = try await self.sessionManager.validateSession(sessionId: sessionId)
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    func testSessionPerformance_TokenRefresh() {
        // Given
        let refreshToken = "valid_refresh_token"
        let refreshResult = TestDataFactory.createSessionRefreshResult()
        mockAppwriteClient.mockRefreshResult = refreshResult
        
        // When - Measure token refresh performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "Token refresh")
            expectation.expectedFulfillmentCount = 100
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 1...100 {
                        group.addTask {
                            do {
                                _ = try await self.sessionManager.refreshAccessToken(refreshToken: refreshToken)
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    // MARK: - User Profile Performance Tests
    
    func testUserProfilePerformance_ProfileCreation() {
        // Given
        let profileData = TestDataFactory.createUserProfileData()
        let expectedProfile = TestDataFactory.createUserProfile()
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When - Measure profile creation performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "Profile creation")
            expectation.expectedFulfillmentCount = 200
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for i in 1...200 {
                        group.addTask {
                            let modifiedProfileData = UserProfileCreationData(
                                email: "user\(i)@example.com",
                                name: profileData.name,
                                phoneNumber: profileData.phoneNumber,
                                dateOfBirth: profileData.dateOfBirth,
                                preferences: profileData.preferences
                            )
                            
                            do {
                                _ = try await self.userProfileService.createUserProfile(modifiedProfileData)
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 15.0)
        }
    }
    
    func testUserProfilePerformance_ProfileRetrieval() {
        // Given
        let userId = "test_user_id"
        let expectedProfile = TestDataFactory.createUserProfile(id: userId)
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When - Measure profile retrieval performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "Profile retrieval")
            expectation.expectedFulfillmentCount = 1000
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 1...1000 {
                        group.addTask {
                            do {
                                _ = try await self.userProfileService.getUserProfile(userId: userId)
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    func testUserProfilePerformance_BulkProfileUpdates() {
        // Given
        let userIds = (1...100).map { "user_\($0)" }
        let updates = TestDataFactory.createUserProfileUpdates()
        let expectedProfile = TestDataFactory.createUserProfile()
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When - Measure bulk profile updates performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            let expectation = XCTestExpectation(description: "Bulk profile updates")
            expectation.expectedFulfillmentCount = userIds.count
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for userId in userIds {
                        group.addTask {
                            do {
                                _ = try await self.userProfileService.updateUserProfile(userId: userId, updates: updates)
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 20.0)
        }
    }
    
    // MARK: - Role Management Performance Tests
    
    func testRolePerformance_PermissionChecking() {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let permissions = Permission.allCases
        let userRoles = [TestDataFactory.createRole(permissions: permissions)]
        mockAppwriteClient.mockUserRoles = userRoles
        
        // When - Measure permission checking performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "Permission checking")
            expectation.expectedFulfillmentCount = permissions.count * 10 // Check each permission 10 times
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 1...10 {
                        for permission in permissions {
                            group.addTask {
                                do {
                                    _ = try await self.roleService.checkUserPermission(
                                        userId: userId,
                                        permission: permission,
                                        tenantId: tenantId
                                    )
                                } catch {
                                    // Ignore errors for performance test
                                }
                                expectation.fulfill()
                            }
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 15.0)
        }
    }
    
    func testRolePerformance_BulkRoleAssignment() {
        // Given
        let userIds = (1...50).map { "user_\($0)" }
        let roleId = "test_role_id"
        let tenantId = "test_tenant_id"
        let expectedAssignment = TestDataFactory.createRoleAssignment()
        mockAppwriteClient.mockRoleAssignment = expectedAssignment
        
        // When - Measure bulk role assignment performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            let expectation = XCTestExpectation(description: "Bulk role assignment")
            expectation.expectedFulfillmentCount = userIds.count
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for userId in userIds {
                        group.addTask {
                            let assignmentData = TestDataFactory.createRoleAssignmentData(
                                userId: userId,
                                roleId: roleId,
                                tenantId: tenantId
                            )
                            
                            do {
                                _ = try await self.roleService.assignRoleToUser(assignmentData: assignmentData)
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 15.0)
        }
    }
    
    // MARK: - Enterprise Authentication Performance Tests
    
    func testEnterprisePerformance_SSOAuthentication() {
        // Given
        let tenantId = "enterprise_tenant"
        let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .azureAD, tenantId: tenantId)
        let authResult = TestDataFactory.createEnterpriseAuthResult()
        
        mockAppwriteClient.mockSSOConfiguration = ssoConfig
        mockAppwriteClient.mockEnterpriseAuthResult = authResult
        
        // When - Measure SSO authentication performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "SSO authentication")
            expectation.expectedFulfillmentCount = 50
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for i in 1...50 {
                        group.addTask {
                            do {
                                _ = try await self.enterpriseService.authenticateWithSSO(
                                    provider: .azureAD,
                                    tenantId: tenantId,
                                    authorizationCode: "auth_code_\(i)"
                                )
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 20.0)
        }
    }
    
    func testEnterprisePerformance_UserProvisioning() {
        // Given
        let tenantId = "enterprise_tenant"
        let enterpriseUser = TestDataFactory.createEnterpriseUser()
        mockAppwriteClient.mockEnterpriseUser = enterpriseUser
        
        // When - Measure user provisioning performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "User provisioning")
            expectation.expectedFulfillmentCount = 100
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for i in 1...100 {
                        group.addTask {
                            let userInfo = TestDataFactory.createEnterpriseUserInfo(email: "user\(i)@enterprise.com")
                            
                            do {
                                _ = try await self.enterpriseService.provisionEnterpriseUser(
                                    userInfo: userInfo,
                                    tenantId: tenantId
                                )
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 25.0)
        }
    }
    
    // MARK: - Memory Performance Tests
    
    func testMemoryPerformance_AuthenticationFlow() {
        // Given
        let initialMemory = performanceMonitor.getCurrentMemoryUsage()
        
        // When - Execute multiple authentication flows and measure memory
        measure(metrics: [XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "Authentication memory test")
            expectation.expectedFulfillmentCount = 1000
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 1...1000 {
                        group.addTask {
                            autoreleasepool {
                                do {
                                    let user = TestDataFactory.createAuthenticatedUser()
                                    let profileData = TestDataFactory.createUserProfileDataFromAuth(user)
                                    _ = try await self.userProfileService.createUserProfile(profileData)
                                    
                                    let deviceInfo = TestDataFactory.createDeviceInfo()
                                    _ = try await self.sessionManager.createSession(
                                        userId: user.id,
                                        tenantId: nil,
                                        deviceInfo: deviceInfo
                                    )
                                } catch {
                                    // Ignore errors for performance test
                                }
                                expectation.fulfill()
                            }
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
        
        // Then - Verify memory usage is reasonable
        let finalMemory = performanceMonitor.getCurrentMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Memory increase should be less than 50MB for 1000 operations
        XCTAssertLessThan(memoryIncrease, 50 * 1024 * 1024, "Memory usage should be reasonable")
    }
    
    func testMemoryPerformance_ConcurrentSessions() {
        // Given
        let sessionCount = 500
        
        // When - Create many concurrent sessions and measure memory
        measure(metrics: [XCTMemoryMetric()]) {
            let expectation = XCTestExpectation(description: "Concurrent sessions memory test")
            expectation.expectedFulfillmentCount = sessionCount
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for i in 1...sessionCount {
                        group.addTask {
                            autoreleasepool {
                                let user = TestDataFactory.createAuthenticatedUser(id: "user_\(i)")
                                let deviceInfo = TestDataFactory.createDeviceInfo(deviceId: "device_\(i)")
                                
                                do {
                                    _ = try await self.sessionManager.createSession(
                                        userId: user.id,
                                        tenantId: nil,
                                        deviceInfo: deviceInfo
                                    )
                                } catch {
                                    // Ignore errors for performance test
                                }
                                expectation.fulfill()
                            }
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 20.0)
        }
    }
    
    // MARK: - CPU Performance Tests
    
    func testCPUPerformance_CryptographicOperations() {
        // Given
        let user = TestDataFactory.createAuthenticatedUser()
        
        // When - Measure CPU usage for cryptographic operations
        measure(metrics: [XCTCPUMetric()]) {
            for _ in 1...100 {
                autoreleasepool {
                    do {
                        // JWT generation (cryptographic signing)
                        _ = try authService.generateJWT(for: user)
                        
                        // Password hashing
                        _ = mockSecurityService.hashPassword("testPassword123!")
                        
                        // Data encryption
                        _ = try mockSecurityService.encryptSensitiveData("sensitive data")
                    } catch {
                        // Ignore errors for performance test
                    }
                }
            }
        }
    }
    
    func testCPUPerformance_PermissionCalculations() {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let complexRole = TestDataFactory.createRole(
            permissions: Permission.allCases,
            inheritedRoles: ["parent_role_1", "parent_role_2"]
        )
        mockAppwriteClient.mockUserRoles = [complexRole]
        
        // When - Measure CPU usage for complex permission calculations
        measure(metrics: [XCTCPUMetric()]) {
            let expectation = XCTestExpectation(description: "Permission calculations")
            expectation.expectedFulfillmentCount = 1000
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 1...1000 {
                        group.addTask {
                            do {
                                // Complex permission checking with inheritance
                                _ = try await self.roleService.getUserEffectivePermissions(
                                    userId: userId,
                                    tenantId: tenantId
                                )
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 15.0)
        }
    }
    
    // MARK: - Network Performance Tests
    
    func testNetworkPerformance_HighLatencyScenario() {
        // Given - Simulate high latency network conditions
        mockAppwriteClient.simulateNetworkLatency = 500 // 500ms latency
        
        let user = TestDataFactory.createAuthenticatedUser()
        let expectedSession = TestDataFactory.createSessionResult()
        mockAppwriteClient.mockSessionResult = expectedSession
        
        // When - Measure performance under high latency
        measure(metrics: [XCTClockMetric()]) {
            let expectation = XCTestExpectation(description: "High latency authentication")
            expectation.expectedFulfillmentCount = 10
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 1...10 {
                        group.addTask {
                            do {
                                _ = try await self.authService.signInWithGoogle()
                            } catch {
                                // Ignore errors for performance test
                            }
                            expectation.fulfill()
                        }
                    }
                }
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
        
        // Reset latency
        mockAppwriteClient.simulateNetworkLatency = 0
    }
    
    func testNetworkPerformance_RequestBatching() {
        // Given
        let userIds = (1...100).map { "user_\($0)" }
        let expectedProfile = TestDataFactory.createUserProfile()
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When - Measure performance of batched vs individual requests
        var individualRequestTime: TimeInterval = 0
        var batchedRequestTime: TimeInterval = 0
        
        // Individual requests
        measure(metrics: [XCTClockMetric()]) {
            let startTime = Date()
            let expectation = XCTestExpectation(description: "Individual requests")
            expectation.expectedFulfillmentCount = userIds.count
            
            Task {
                for userId in userIds {
                    do {
                        _ = try await self.userProfileService.getUserProfile(userId: userId)
                    } catch {
                        // Ignore errors for performance test
                    }
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 20.0)
            individualRequestTime = Date().timeIntervalSince(startTime)
        }
        
        // Batched requests (if available)
        measure(metrics: [XCTClockMetric()]) {
            let startTime = Date()
            let expectation = XCTestExpectation(description: "Batched requests")
            
            Task {
                do {
                    _ = try await self.userProfileService.getBatchUserProfiles(userIds: userIds)
                } catch {
                    // Ignore errors for performance test
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10.0)
            batchedRequestTime = Date().timeIntervalSince(startTime)
        }
        
        // Then - Batched requests should be significantly faster
        if batchedRequestTime > 0 {
            XCTAssertLessThan(batchedRequestTime, individualRequestTime * 0.5,
                             "Batched requests should be at least 50% faster")
        }
    }
    
    // MARK: - Stress Testing
    
    func testStressTesting_AuthenticationSystem() {
        // Given
        let stressTestDuration: TimeInterval = 60 // 1 minute stress test
        let maxConcurrentOperations = 200
        
        var completedOperations = 0
        var failedOperations = 0
        
        // When - Run stress test
        let expectation = XCTestExpectation(description: "Stress test")
        let startTime = Date()
        
        Task {
            await withTaskGroup(of: Bool.self) { group in
                while Date().timeIntervalSince(startTime) < stressTestDuration {
                    if group.addTaskUnlessCancelled {
                        group.addTask {
                            let operationType = Int.random(in: 1...4)
                            
                            do {
                                switch operationType {
                                case 1:
                                    _ = try await self.authService.signInWithGoogle()
                                case 2:
                                    let user = TestDataFactory.createAuthenticatedUser()
                                    let deviceInfo = TestDataFactory.createDeviceInfo()
                                    _ = try await self.sessionManager.createSession(
                                        userId: user.id,
                                        tenantId: nil,
                                        deviceInfo: deviceInfo
                                    )
                                case 3:
                                    let profileData = TestDataFactory.createUserProfileData()
                                    _ = try await self.userProfileService.createUserProfile(profileData)
                                case 4:
                                    let userId = "stress_test_user"
                                    let permission = Permission.allCases.randomElement()!
                                    _ = try await self.roleService.checkUserPermission(
                                        userId: userId,
                                        permission: permission,
                                        tenantId: "stress_tenant"
                                    )
                                default:
                                    break
                                }
                                return true
                            } catch {
                                return false
                            }
                        }
                    }
                    
                    // Limit concurrent operations
                    if group.isEmpty == false {
                        for await result in group {
                            if result {
                                completedOperations += 1
                            } else {
                                failedOperations += 1
                            }
                            break
                        }
                    }
                }
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: stressTestDuration + 30)
        
        // Then - Verify system stability
        let totalOperations = completedOperations + failedOperations
        let successRate = Double(completedOperations) / Double(totalOperations) * 100
        
        print("Stress Test Results:")
        print("- Total Operations: \(totalOperations)")
        print("- Completed: \(completedOperations)")
        print("- Failed: \(failedOperations)")
        print("- Success Rate: \(String(format: "%.1f", successRate))%")
        print("- Operations/Second: \(String(format: "%.1f", Double(totalOperations) / stressTestDuration))")
        
        XCTAssertGreaterThan(successRate, 85.0, "Success rate should be above 85% under stress")
        XCTAssertGreaterThan(Double(totalOperations) / stressTestDuration, 10.0, "Should handle at least 10 operations per second")
    }
}

// MARK: - Performance Monitoring

class PerformanceMonitor {
    
    func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        } else {
            return 0
        }
    }
    
    func measureExecutionTime<T>(_ operation: () throws -> T) rethrows -> (result: T, time: TimeInterval) {
        let startTime = Date()
        let result = try operation()
        let executionTime = Date().timeIntervalSince(startTime)
        return (result, executionTime)
    }
    
    func measureAsyncExecutionTime<T>(_ operation: () async throws -> T) async rethrows -> (result: T, time: TimeInterval) {
        let startTime = Date()
        let result = try await operation()
        let executionTime = Date().timeIntervalSince(startTime)
        return (result, executionTime)
    }
}

// MARK: - Extensions for Testing

extension UserProfileService {
    func getBatchUserProfiles(userIds: [String]) async throws -> [UserProfile] {
        // Simulated batch operation
        var profiles: [UserProfile] = []
        for userId in userIds {
            do {
                let profile = try await getUserProfile(userId: userId)
                profiles.append(profile)
            } catch {
                // Continue with other profiles
            }
        }
        return profiles
    }
}

extension MockAppwriteClient {
    var simulateNetworkLatency: Int {
        get { return _simulateNetworkLatency }
        set { _simulateNetworkLatency = newValue }
    }
    
    private var _simulateNetworkLatency: Int = 0
}