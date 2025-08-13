import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - Authentication Flow Integration Tests

final class AuthenticationFlowTests: XCTestCase {
    
    // MARK: - Properties
    
    private var authService: AuthenticationService!
    private var userProfileService: UserProfileService!
    private var sessionManager: SessionManagementService!
    private var biometricService: BiometricAuthService!
    private var consentService: ConsentManagementService!
    private var roleService: RoleManagementService!
    private var enterpriseService: EnterpriseAuthService!
    
    private var mockAppwriteClient: MockAppwriteClient!
    private var mockSecurityService: MockSecurityService!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        mockAppwriteClient = MockAppwriteClient()
        mockSecurityService = MockSecurityService()
        cancellables = Set<AnyCancellable>()
        
        // Initialize services with shared dependencies
        sessionManager = SessionManagementService(
            appwriteClient: mockAppwriteClient,
            securityService: mockSecurityService
        )
        
        userProfileService = UserProfileService(
            appwriteClient: mockAppwriteClient,
            securityService: mockSecurityService
        )
        
        biometricService = BiometricAuthService(
            securityService: mockSecurityService
        )
        
        consentService = ConsentManagementService(
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
        cancellables = nil
        authService = nil
        userProfileService = nil
        sessionManager = nil
        biometricService = nil
        consentService = nil
        roleService = nil
        enterpriseService = nil
        mockSecurityService = nil
        mockAppwriteClient = nil
        
        super.tearDown()
    }
    
    // MARK: - Complete Authentication Flow Tests
    
    func testCompleteGoogleAuthFlow_Success() async throws {
        // Given
        let expectedUser = TestDataFactory.createAuthenticatedUser()
        let expectedSession = TestDataFactory.createSessionResult()
        let expectedProfile = TestDataFactory.createUserProfile()
        let consentData = TestDataFactory.createGDPRConsentData()
        let consentRecord = TestDataFactory.createConsentRecord()
        
        // Setup mocks for the complete flow
        mockAppwriteClient.mockOAuthSession = TestDataFactory.createAppwriteSession()
        mockAppwriteClient.mockSessionResult = expectedSession
        mockAppwriteClient.mockUserProfile = expectedProfile
        mockAppwriteClient.mockConsentRecord = consentRecord
        
        // When - Execute complete flow
        let authResult = try await authService.signInWithGoogle()
        
        // Create user profile
        let profileData = TestDataFactory.createUserProfileDataFromAuth(authResult.user)
        let profile = try await userProfileService.createUserProfile(profileData)
        
        // Record GDPR consent
        let consent = try await consentService.recordGDPRConsent(
            userId: authResult.user.id,
            consentData: consentData
        )
        
        // Validate session
        let sessionValidation = try await sessionManager.validateSession(
            sessionId: expectedSession.accessToken.sessionId
        )
        
        // Then
        XCTAssertNotNil(authResult.accessToken)
        XCTAssertEqual(authResult.user.provider, .google)
        XCTAssertTrue(authService.isAuthenticated)
        
        XCTAssertEqual(profile.id, authResult.user.id)
        XCTAssertEqual(profile.email, authResult.user.email)
        
        XCTAssertEqual(consent.userId, authResult.user.id)
        XCTAssertEqual(consent.consentType, .gdpr)
        XCTAssertEqual(consent.status, .granted)
        
        XCTAssertTrue(sessionValidation.isValid)
        XCTAssertNotNil(sessionValidation.session)
    }
    
    func testCompleteAppleAuthFlow_WithBiometrics() async throws {
        // Given
        let expectedUser = TestDataFactory.createAuthenticatedUser(provider: .apple)
        let expectedSession = TestDataFactory.createSessionResult()
        let biometricSetup = TestDataFactory.createBiometricSetupData()
        
        // Setup mocks
        mockAppwriteClient.mockAppleAuthResult = expectedUser
        mockAppwriteClient.mockSessionResult = expectedSession
        mockSecurityService.mockBiometricAvailable = true
        mockSecurityService.mockBiometricSetupResult = TestDataFactory.createBiometricSetupResult()
        
        // When - Execute Apple auth with biometric setup
        let authResult = try await authService.signInWithApple()
        
        // Setup biometric authentication
        let biometricResult = try await biometricService.setupBiometricAuth(
            userId: authResult.user.id,
            biometricData: biometricSetup
        )
        
        // Test biometric authentication
        let biometricAuth = try await biometricService.authenticateWithBiometrics(
            userId: authResult.user.id,
            promptReason: "Authenticate to access your account"
        )
        
        // Then
        XCTAssertEqual(authResult.user.provider, .apple)
        XCTAssertTrue(authService.isAuthenticated)
        
        XCTAssertTrue(biometricResult.isEnabled)
        XCTAssertEqual(biometricResult.userId, authResult.user.id)
        
        XCTAssertTrue(biometricAuth.success)
        XCTAssertEqual(biometricAuth.userId, authResult.user.id)
    }
    
    func testEnterpriseAuthFlow_AzureAD_Success() async throws {
        // Given
        let tenantId = "enterprise_tenant_id"
        let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .azureAD, tenantId: tenantId)
        let enterpriseUser = TestDataFactory.createEnterpriseUser()
        let adminRole = TestDataFactory.createRole(name: "Enterprise Admin")
        
        // Setup mocks
        mockAppwriteClient.mockSSOConfiguration = ssoConfig
        mockAppwriteClient.mockEnterpriseUser = enterpriseUser
        mockAppwriteClient.mockRole = adminRole
        mockAppwriteClient.mockRoleAssignment = TestDataFactory.createRoleAssignment(
            userId: enterpriseUser.id,
            roleId: adminRole.id,
            tenantId: tenantId
        )
        
        // When - Execute enterprise authentication flow
        // 1. Configure SSO
        let configResult = try await enterpriseService.configureSSO(config: ssoConfig)
        
        // 2. Authenticate with SSO
        let authResult = try await enterpriseService.authenticateWithSSO(
            provider: .azureAD,
            tenantId: tenantId,
            authorizationCode: "valid_auth_code"
        )
        
        // 3. Provision enterprise user
        let userInfo = TestDataFactory.createEnterpriseUserInfoFromAuth(authResult.user)
        let provisionedUser = try await enterpriseService.provisionEnterpriseUser(
            userInfo: userInfo,
            tenantId: tenantId
        )
        
        // 4. Assign role
        let assignmentData = TestDataFactory.createRoleAssignmentData(
            userId: provisionedUser.id,
            roleId: adminRole.id,
            tenantId: tenantId
        )
        let roleAssignment = try await roleService.assignRoleToUser(assignmentData: assignmentData)
        
        // 5. Validate permissions
        let hasPermission = try await roleService.checkUserPermission(
            userId: provisionedUser.id,
            permission: .manageUsers,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertEqual(configResult.provider, .azureAD)
        XCTAssertEqual(configResult.status, .active)
        
        XCTAssertEqual(authResult.provider, .azureAD)
        XCTAssertEqual(authResult.tenantId, tenantId)
        
        XCTAssertEqual(provisionedUser.tenantId, tenantId)
        XCTAssertEqual(provisionedUser.email, userInfo.email)
        
        XCTAssertEqual(roleAssignment.userId, provisionedUser.id)
        XCTAssertEqual(roleAssignment.roleId, adminRole.id)
        XCTAssertEqual(roleAssignment.status, .active)
        
        XCTAssertTrue(hasPermission)
    }
    
    func testMultiTenantAuthFlow_TenantSwitching() async throws {
        // Given
        let user = TestDataFactory.createAuthenticatedUser()
        let tenant1 = TestDataFactory.createTenantInfo(id: "tenant_1")
        let tenant2 = TestDataFactory.createTenantInfo(id: "tenant_2")
        
        // User has memberships in both tenants
        user.tenantMemberships = [
            TestDataFactory.createTenantMembership(tenantId: tenant1.id, userId: user.id),
            TestDataFactory.createTenantMembership(tenantId: tenant2.id, userId: user.id)
        ]
        
        // Setup mocks
        mockAppwriteClient.mockAuthenticatedUser = user
        mockAppwriteClient.mockTenantInfo = tenant1
        mockAppwriteClient.mockUserTenants = [tenant1, tenant2]
        
        // When - Execute multi-tenant flow
        // 1. Initial authentication
        let authResult = try await authService.signInWithGoogle()
        authService.setCurrentUser(user)
        
        // 2. Get user tenants
        let userTenants = try await authService.getUserTenants()
        
        // 3. Switch to tenant 1
        mockAppwriteClient.mockTenantInfo = tenant1
        let switchResult1 = try await authService.switchTenant(tenant1.id)
        
        // 4. Validate tenant context
        let currentTenant1 = await authService.getCurrentTenant()
        
        // 5. Switch to tenant 2
        mockAppwriteClient.mockTenantInfo = tenant2
        let switchResult2 = try await authService.switchTenant(tenant2.id)
        
        // 6. Validate new tenant context
        let currentTenant2 = await authService.getCurrentTenant()
        
        // Then
        XCTAssertEqual(userTenants.count, 2)
        XCTAssertTrue(userTenants.contains { $0.id == tenant1.id })
        XCTAssertTrue(userTenants.contains { $0.id == tenant2.id })
        
        XCTAssertEqual(switchResult1.newTenant.id, tenant1.id)
        XCTAssertEqual(currentTenant1?.id, tenant1.id)
        
        XCTAssertEqual(switchResult2.newTenant.id, tenant2.id)
        XCTAssertEqual(currentTenant2?.id, tenant2.id)
    }
    
    func testAuthFlowWithConsentManagement_GDPR() async throws {
        // Given
        let user = TestDataFactory.createAuthenticatedUser()
        let gdprConsent = TestDataFactory.createGDPRConsentData()
        let cookieConsent = TestDataFactory.createCookieConsentData(essential: true, analytics: true)
        let marketingConsent = TestDataFactory.createMarketingConsentData(granted: false)
        
        // Setup mocks
        mockAppwriteClient.mockAuthenticatedUser = user
        mockAppwriteClient.mockConsentRecords = []
        
        // When - Execute auth flow with comprehensive consent management
        // 1. Authenticate user
        let authResult = try await authService.signInWithGoogle()
        authService.setCurrentUser(user)
        
        // 2. Record GDPR consent
        let gdprRecord = try await consentService.recordGDPRConsent(
            userId: user.id,
            consentData: gdprConsent
        )
        
        // 3. Record cookie consent
        let cookieRecord = try await consentService.recordCookieConsent(
            userId: user.id,
            cookieConsent: cookieConsent
        )
        
        // 4. Record marketing consent (denied)
        let marketingRecord = try await consentService.recordMarketingConsent(
            userId: user.id,
            marketingConsent: marketingConsent
        )
        
        // 5. Validate required consents
        let requiredConsents: [ConsentType] = [.gdpr, .cookies]
        mockAppwriteClient.mockConsentRecords = [gdprRecord, cookieRecord, marketingRecord]
        
        let validationResult = try await consentService.validateRequiredConsents(
            userId: user.id,
            requiredConsents: requiredConsents
        )
        
        // 6. Check consent history
        let consentHistory = try await consentService.getConsentHistory(
            userId: user.id,
            consentType: .gdpr
        )
        
        // Then
        XCTAssertEqual(gdprRecord.userId, user.id)
        XCTAssertEqual(gdprRecord.consentType, .gdpr)
        XCTAssertEqual(gdprRecord.status, .granted)
        
        XCTAssertEqual(cookieRecord.consentType, .cookies)
        XCTAssertTrue(cookieRecord.cookieCategories.contains(.essential))
        XCTAssertTrue(cookieRecord.cookieCategories.contains(.analytics))
        
        XCTAssertEqual(marketingRecord.consentType, .marketing)
        XCTAssertEqual(marketingRecord.status, .denied)
        
        XCTAssertTrue(validationResult.isValid)
        XCTAssertTrue(validationResult.missingConsents.isEmpty)
        
        XCTAssertGreaterThan(consentHistory.count, 0)
        XCTAssertTrue(consentHistory.allSatisfy { $0.consentType == .gdpr })
    }
    
    func testSessionManagementFlow_FullLifecycle() async throws {
        // Given
        let user = TestDataFactory.createAuthenticatedUser()
        let deviceInfo = TestDataFactory.createDeviceInfo()
        let tenantId = "test_tenant_id"
        
        // Setup mocks
        mockAppwriteClient.mockSessionResult = TestDataFactory.createSessionResult()
        mockAppwriteClient.mockSessionInfo = TestDataFactory.createSessionInfo()
        
        // When - Execute complete session lifecycle
        // 1. Create session
        let sessionResult = try await sessionManager.createSession(
            userId: user.id,
            tenantId: tenantId,
            deviceInfo: deviceInfo
        )
        
        // 2. Validate session
        let validationResult = try await sessionManager.validateSession(
            sessionId: sessionResult.accessToken.sessionId
        )
        
        // 3. Refresh token
        mockAppwriteClient.mockRefreshResult = TestDataFactory.createSessionRefreshResult()
        let refreshResult = try await sessionManager.refreshAccessToken(
            refreshToken: sessionResult.refreshToken.token
        )
        
        // 4. Get user sessions
        let userSessions = try await sessionManager.getUserSessions(userId: user.id)
        
        // 5. Get active sessions
        let activeSessions = try await sessionManager.getActiveSessions(userId: user.id)
        
        // 6. Terminate session
        try await sessionManager.terminateSession(
            sessionId: sessionResult.accessToken.sessionId
        )
        
        // Then
        XCTAssertNotNil(sessionResult.accessToken.token)
        XCTAssertNotNil(sessionResult.refreshToken.token)
        XCTAssertEqual(sessionResult.accessToken.userId, user.id)
        
        XCTAssertTrue(validationResult.isValid)
        XCTAssertNotNil(validationResult.session)
        
        XCTAssertNotNil(refreshResult.newAccessToken)
        XCTAssertNotNil(refreshResult.newRefreshToken)
        
        XCTAssertGreaterThan(userSessions.count, 0)
        XCTAssertTrue(userSessions.allSatisfy { $0.userId == user.id })
        
        XCTAssertGreaterThan(activeSessions.count, 0)
        XCTAssertTrue(activeSessions.allSatisfy { $0.isActive })
    }
    
    func testRoleBasedAccessControl_Flow() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let user = TestDataFactory.createAuthenticatedUser()
        
        // Create roles with different permission levels
        let adminRole = TestDataFactory.createRole(
            name: "Admin",
            permissions: [.manageUsers, .manageRoles, .readUsers, .writeUsers]
        )
        let editorRole = TestDataFactory.createRole(
            name: "Editor",
            permissions: [.readUsers, .writeUsers]
        )
        let viewerRole = TestDataFactory.createRole(
            name: "Viewer",
            permissions: [.readUsers]
        )
        
        // Setup mocks
        mockAppwriteClient.mockRoles = [adminRole, editorRole, viewerRole]
        mockAppwriteClient.mockRoleAssignment = TestDataFactory.createRoleAssignment()
        
        // When - Execute RBAC flow
        // 1. Create roles
        let adminRoleData = TestDataFactory.createRoleDataFromRole(adminRole)
        let createdAdminRole = try await roleService.createRole(roleData: adminRoleData)
        
        // 2. Assign admin role to user
        let assignmentData = TestDataFactory.createRoleAssignmentData(
            userId: user.id,
            roleId: adminRole.id,
            tenantId: tenantId
        )
        let roleAssignment = try await roleService.assignRoleToUser(assignmentData: assignmentData)
        
        // 3. Check user permissions
        let hasManageUsersPermission = try await roleService.checkUserPermission(
            userId: user.id,
            permission: .manageUsers,
            tenantId: tenantId
        )
        
        let hasDeleteUsersPermission = try await roleService.checkUserPermission(
            userId: user.id,
            permission: .deleteUsers,
            tenantId: tenantId
        )
        
        // 4. Get user's effective permissions
        mockAppwriteClient.mockUserRoles = [adminRole]
        let effectivePermissions = try await roleService.getUserEffectivePermissions(
            userId: user.id,
            tenantId: tenantId
        )
        
        // 5. Switch to editor role
        try await roleService.removeRoleFromUser(
            userId: user.id,
            roleId: adminRole.id,
            tenantId: tenantId
        )
        
        let editorAssignmentData = TestDataFactory.createRoleAssignmentData(
            userId: user.id,
            roleId: editorRole.id,
            tenantId: tenantId
        )
        let editorAssignment = try await roleService.assignRoleToUser(assignmentData: editorAssignmentData)
        
        // 6. Verify reduced permissions
        mockAppwriteClient.mockUserRoles = [editorRole]
        let hasManageUsersAsEditor = try await roleService.checkUserPermission(
            userId: user.id,
            permission: .manageUsers,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertEqual(createdAdminRole.name, adminRole.name)
        XCTAssertEqual(createdAdminRole.permissions.count, adminRole.permissions.count)
        
        XCTAssertEqual(roleAssignment.userId, user.id)
        XCTAssertEqual(roleAssignment.roleId, adminRole.id)
        
        XCTAssertTrue(hasManageUsersPermission) // Admin has this permission
        XCTAssertFalse(hasDeleteUsersPermission) // Admin doesn't have this permission
        
        XCTAssertEqual(effectivePermissions.count, adminRole.permissions.count)
        XCTAssertTrue(effectivePermissions.contains(.manageUsers))
        
        XCTAssertEqual(editorAssignment.roleId, editorRole.id)
        XCTAssertFalse(hasManageUsersAsEditor) // Editor doesn't have this permission
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testAuthFlowWithNetworkErrors_Resilience() async {
        // Given
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.networkError("Connection failed")
        
        // When & Then
        do {
            _ = try await authService.signInWithGoogle()
            XCTFail("Expected network error")
        } catch AuthenticationError.networkError(let message) {
            XCTAssertEqual(message, "Connection failed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Verify system state remains consistent
        XCTAssertFalse(authService.isAuthenticated)
        XCTAssertNil(authService.currentUser)
    }
    
    func testAuthFlowWithConsentViolations_Blocking() async throws {
        // Given
        let user = TestDataFactory.createAuthenticatedUser()
        let requiredConsents: [ConsentType] = [.gdpr, .cookies, .marketing]
        
        // Setup mocks - user only has GDPR consent
        let gdprConsent = TestDataFactory.createConsentRecord(consentType: .gdpr)
        mockAppwriteClient.mockConsentRecords = [gdprConsent]
        mockAppwriteClient.mockAuthenticatedUser = user
        
        // When
        let authResult = try await authService.signInWithGoogle()
        authService.setCurrentUser(user)
        
        let validationResult = try await consentService.validateRequiredConsents(
            userId: user.id,
            requiredConsents: requiredConsents
        )
        
        // Then
        XCTAssertTrue(authService.isAuthenticated) // Authentication succeeded
        XCTAssertFalse(validationResult.isValid) // But consent validation failed
        XCTAssertEqual(validationResult.missingConsents.count, 2) // Missing cookies and marketing
        XCTAssertTrue(validationResult.missingConsents.contains(.cookies))
        XCTAssertTrue(validationResult.missingConsents.contains(.marketing))
    }
    
    // MARK: - Performance Integration Tests
    
    func testConcurrentAuthOperations() async {
        // Given
        let userCount = 10
        let users = (1...userCount).map { TestDataFactory.createAuthenticatedUser(id: "user_\($0)") }
        
        // When
        await withTaskGroup(of: Bool.self) { group in
            for user in users {
                group.addTask {
                    do {
                        // Simulate concurrent authentication operations
                        let profileData = TestDataFactory.createUserProfileDataFromAuth(user)
                        _ = try await self.userProfileService.createUserProfile(profileData)
                        
                        let deviceInfo = TestDataFactory.createDeviceInfo()
                        _ = try await self.sessionManager.createSession(
                            userId: user.id,
                            tenantId: nil,
                            deviceInfo: deviceInfo
                        )
                        
                        let consentData = TestDataFactory.createGDPRConsentData()
                        _ = try await self.consentService.recordGDPRConsent(
                            userId: user.id,
                            consentData: consentData
                        )
                        
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
            XCTAssertEqual(results.count, userCount)
            // At least 80% should succeed in concurrent scenario
            let successCount = results.filter { $0 }.count
            XCTAssertGreaterThan(successCount, userCount * 80 / 100)
        }
    }
    
    func testAuthFlowPerformanceBenchmark() {
        measure {
            let expectation = XCTestExpectation(description: "Complete auth flow performance")
            
            Task {
                do {
                    // Simulate complete authentication flow
                    let authResult = try await authService.signInWithGoogle()
                    
                    let profileData = TestDataFactory.createUserProfileDataFromAuth(authResult.user)
                    _ = try await userProfileService.createUserProfile(profileData)
                    
                    let consentData = TestDataFactory.createGDPRConsentData()
                    _ = try await consentService.recordGDPRConsent(
                        userId: authResult.user.id,
                        consentData: consentData
                    )
                    
                    let deviceInfo = TestDataFactory.createDeviceInfo()
                    _ = try await sessionManager.createSession(
                        userId: authResult.user.id,
                        tenantId: nil,
                        deviceInfo: deviceInfo
                    )
                } catch {
                    // Ignore errors for performance test
                }
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
}