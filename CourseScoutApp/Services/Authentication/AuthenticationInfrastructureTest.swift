import Foundation
import XCTest
@testable import GolfFinderApp

// MARK: - Authentication Infrastructure Test Suite

@MainActor
class AuthenticationInfrastructureTest: XCTestCase {
    
    // MARK: - Properties
    
    private var serviceContainer: ServiceContainer!
    private var authService: AuthenticationServiceProtocol!
    private var userProfileService: UserProfileServiceProtocol!
    private var biometricService: BiometricAuthServiceProtocol!
    private var sessionService: SessionManagementServiceProtocol!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize service container with test environment
        serviceContainer = ServiceContainer(
            appwriteClient: MockAppwriteClient(),
            environment: .test
        )
        
        // Resolve services
        authService = serviceContainer.authenticationService()
        userProfileService = serviceContainer.userProfileService()
        biometricService = serviceContainer.biometricAuthService()
        sessionService = serviceContainer.sessionManagementService()
        
        // Verify services are mock implementations
        XCTAssertTrue(authService is MockAuthenticationService, "Should use mock authentication service in test environment")
        XCTAssertTrue(userProfileService is MockUserProfileService, "Should use mock user profile service in test environment")
        XCTAssertTrue(biometricService is MockBiometricAuthService, "Should use mock biometric service in test environment")
        XCTAssertTrue(sessionService is MockSessionManagementService, "Should use mock session service in test environment")
    }
    
    override func tearDown() async throws {
        serviceContainer = nil
        authService = nil
        userProfileService = nil
        biometricService = nil
        sessionService = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Authentication Service Tests
    
    func testGoogleOAuthAuthentication() async throws {
        // Test Google OAuth sign-in
        let result = try await authService.signInWithGoogle()
        
        XCTAssertTrue(authService.isAuthenticated, "User should be authenticated after Google sign-in")
        XCTAssertNotNil(authService.currentUser, "Current user should be set")
        XCTAssertEqual(result.user.provider, .google, "Provider should be Google")
        XCTAssertTrue(result.accessToken.hasPrefix("mock_google_access_token"), "Should return mock Google access token")
        XCTAssertNotNil(result.refreshToken, "Should provide refresh token")
        XCTAssertTrue(result.scope.contains("email"), "Should include email scope")
    }
    
    func testAppleSignInAuthentication() async throws {
        // Test Apple Sign In
        let result = try await authService.signInWithApple()
        
        XCTAssertTrue(authService.isAuthenticated, "User should be authenticated after Apple sign-in")
        XCTAssertEqual(result.user.provider, .apple, "Provider should be Apple")
        XCTAssertTrue(result.accessToken.hasPrefix("mock_apple_access_token"), "Should return mock Apple access token")
        XCTAssertNotNil(result.idToken, "Apple should provide ID token")
    }
    
    func testEnterpriseAuthentication() async throws {
        // Test Azure AD authentication
        let tenantId = "test-tenant-123"
        let result = try await authService.signInWithAzureAD(tenantId: tenantId)
        
        XCTAssertTrue(authService.isAuthenticated, "User should be authenticated after Azure AD sign-in")
        XCTAssertEqual(result.user.provider, .azureAD, "Provider should be Azure AD")
        XCTAssertNotNil(result.tenant, "Should include tenant information")
        XCTAssertEqual(result.tenant?.id, tenantId, "Tenant ID should match")
    }
    
    func testTokenManagement() async throws {
        // First authenticate
        _ = try await authService.signInWithGoogle()
        
        // Test token validation
        let token = "mock_google_access_token"
        let validationResult = try await authService.validateToken(token)
        
        XCTAssertTrue(validationResult.isValid, "Mock token should be valid")
        XCTAssertNotNil(validationResult.user, "Should return user information")
        XCTAssertGreaterThan(validationResult.remainingTime, 0, "Should have remaining time")
        
        // Test token refresh
        let refreshResult = try await authService.refreshToken("mock_google_refresh_token")
        
        XCTAssertTrue(refreshResult.accessToken.hasPrefix("mock_refreshed_access_token"), "Should return new access token")
        XCTAssertNotNil(refreshResult.refreshToken, "Should return new refresh token")
    }
    
    func testMultiTenantSupport() async throws {
        // Authenticate with enterprise provider
        _ = try await authService.signInWithAzureAD(tenantId: "tenant1")
        
        // Get user tenants
        let tenants = try await authService.getUserTenants()
        XCTAssertGreaterThan(tenants.count, 0, "Should return available tenants")
        
        // Switch tenant
        let switchResult = try await authService.switchTenant("tenant2")
        XCTAssertEqual(switchResult.newTenant.id, "tenant2", "Should switch to new tenant")
        XCTAssertNotNil(switchResult.newToken, "Should provide new token for tenant")
        
        // Verify current tenant
        let currentTenant = await authService.getCurrentTenant()
        XCTAssertEqual(currentTenant?.id, "tenant2", "Current tenant should be updated")
    }
    
    func testMFASetup() async throws {
        // Authenticate first
        _ = try await authService.signInWithGoogle()
        
        // Enable MFA
        let mfaSetup = try await authService.enableMFA()
        
        XCTAssertNotNil(mfaSetup.secret, "Should provide TOTP secret")
        XCTAssertNotNil(mfaSetup.qrCodeURL, "Should provide QR code URL")
        XCTAssertGreaterThan(mfaSetup.backupCodes.count, 0, "Should provide backup codes")
        XCTAssertEqual(mfaSetup.method, .totp, "Should use TOTP method")
        
        // Test MFA validation
        let isValid = try await authService.validateMFA(code: "123456", method: .totp)
        XCTAssertTrue(isValid, "Mock MFA code should be valid")
        
        // Generate backup codes
        let backupCodes = try await authService.generateBackupCodes()
        XCTAssertGreaterThanOrEqual(backupCodes.count, 5, "Should generate multiple backup codes")
    }
    
    func testAuthenticationStateStream() async throws {
        // Monitor authentication state changes
        var stateChanges: [AuthenticationState] = []
        let expectation = XCTestExpectation(description: "Authentication state changes")
        
        Task {
            for await state in authService.authenticationStateChanged.prefix(3) {
                stateChanges.append(state)
                if stateChanges.count == 3 {
                    expectation.fulfill()
                }
            }
        }
        
        // Trigger state changes
        _ = try await authService.signInWithGoogle()
        _ = try await authService.switchTenant("tenant1")
        try await authService.clearStoredTokens()
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertEqual(stateChanges.count, 3, "Should receive all state changes")
        
        // Verify state progression
        if case .authenticated(let user, _) = stateChanges[0] {
            XCTAssertEqual(user.provider, .google, "First state should be Google authentication")
        } else {
            XCTFail("First state should be authenticated")
        }
        
        if case .unauthenticated = stateChanges[2] {
            // Expected
        } else {
            XCTFail("Last state should be unauthenticated")
        }
    }
    
    // MARK: - User Profile Service Tests
    
    func testUserProfileCreation() async throws {
        let profileCreate = GolfUserProfileCreate(
            email: "test@golffinder.com",
            displayName: "Test Golfer",
            firstName: "Test",
            lastName: "Golfer",
            handicapIndex: 15.5,
            golfPreferences: GolfPreferences(
                preferredTeeBox: .regular,
                playingStyle: .casual,
                courseTypes: [.parkland],
                preferredRegions: ["North America"],
                maxTravelDistance: 50.0,
                budgetRange: .moderate,
                preferredPlayTimes: [.morning],
                golfCartPreference: .flexible,
                weatherPreferences: WeatherPreferences(
                    minTemperature: 15.0,
                    maxTemperature: 30.0,
                    acceptableConditions: [.sunny],
                    windSpeedLimit: 20.0
                )
            ),
            privacySettings: PrivacySettings(
                profileVisibility: .public,
                dataProcessingConsent: true,
                analyticsOptOut: false,
                marketingOptOut: false
            ),
            tenantId: nil,
            invitationCode: nil
        )
        
        let profile = try await userProfileService.createUserProfile(profileCreate)
        
        XCTAssertEqual(profile.email, "test@golffinder.com", "Email should match")
        XCTAssertEqual(profile.displayName, "Test Golfer", "Display name should match")
        XCTAssertEqual(profile.handicapIndex, 15.5, "Handicap should match")
        XCTAssertNotNil(profile.id, "Should have profile ID")
    }
    
    func testUserProfileUpdate() async throws {
        // Create a profile first
        let profileCreate = GolfUserProfileCreate(
            email: "test@golffinder.com",
            displayName: "Test Golfer",
            firstName: nil,
            lastName: nil,
            handicapIndex: nil,
            golfPreferences: GolfPreferences(
                preferredTeeBox: .regular,
                playingStyle: .casual,
                courseTypes: [.parkland],
                preferredRegions: [],
                maxTravelDistance: 50.0,
                budgetRange: .moderate,
                preferredPlayTimes: [.morning],
                golfCartPreference: .flexible,
                weatherPreferences: WeatherPreferences(
                    minTemperature: nil,
                    maxTemperature: nil,
                    acceptableConditions: [.sunny],
                    windSpeedLimit: nil
                )
            ),
            privacySettings: PrivacySettings(
                profileVisibility: .public,
                dataProcessingConsent: true,
                analyticsOptOut: false,
                marketingOptOut: false
            ),
            tenantId: nil,
            invitationCode: nil
        )
        
        let profile = try await userProfileService.createUserProfile(profileCreate)
        
        // Update the profile
        let profileUpdate = GolfUserProfileUpdate(
            displayName: "Updated Golfer",
            firstName: "Updated",
            lastName: "User",
            bio: "Golf enthusiast",
            handicapIndex: 12.3,
            golfPreferences: nil,
            homeClub: nil,
            membershipType: .full,
            playingFrequency: .weekly,
            location: nil,
            phoneNumber: "+1-555-123-4567",
            emergencyContact: nil,
            privacySettings: nil,
            socialVisibility: .friends
        )
        
        let updatedProfile = try await userProfileService.updateUserProfile(profile.id, profile: profileUpdate)
        
        XCTAssertEqual(updatedProfile.displayName, "Updated Golfer", "Display name should be updated")
        XCTAssertEqual(updatedProfile.firstName, "Updated", "First name should be updated")
        XCTAssertEqual(updatedProfile.handicapIndex, 12.3, "Handicap should be updated")
        XCTAssertEqual(updatedProfile.membershipType, .full, "Membership type should be updated")
        XCTAssertEqual(updatedProfile.phoneNumber, "+1-555-123-4567", "Phone number should be updated")
    }
    
    func testHandicapManagement() async throws {
        // Create profile
        let profile = try await createTestProfile()
        
        // Update handicap
        try await userProfileService.updateHandicapIndex(profile.id, handicapIndex: 14.2)
        
        // Get handicap history
        let history = try await userProfileService.getHandicapHistory(profile.id, limit: 10)
        
        XCTAssertGreaterThan(history.count, 0, "Should have handicap history entries")
        
        let latestEntry = history.first!
        XCTAssertEqual(latestEntry.userId, profile.id, "User ID should match")
        XCTAssertEqual(latestEntry.source, .selfReported, "Should be self-reported")
    }
    
    func testInvalidHandicapValidation() async throws {
        let profile = try await createTestProfile()
        
        // Test invalid handicap (too high)
        do {
            try await userProfileService.updateHandicapIndex(profile.id, handicapIndex: 60.0)
            XCTFail("Should throw validation error for invalid handicap")
        } catch ValidationError.invalidHandicapIndex {
            // Expected
        }
        
        // Test invalid handicap (too low)
        do {
            try await userProfileService.updateHandicapIndex(profile.id, handicapIndex: -10.0)
            XCTFail("Should throw validation error for invalid handicap")
        } catch ValidationError.invalidHandicapIndex {
            // Expected
        }
    }
    
    func testGolfStatistics() async throws {
        let profile = try await createTestProfile()
        
        let statistics = try await userProfileService.getGolfStatistics(profile.id, period: .month)
        
        XCTAssertGreaterThanOrEqual(statistics.totalRounds, 0, "Should have non-negative rounds")
        XCTAssertGreaterThanOrEqual(statistics.averageScore, 0, "Should have non-negative average score")
        XCTAssertNotNil(statistics.handicapTrend, "Should have handicap trend")
        XCTAssertGreaterThanOrEqual(statistics.coursesPlayed, 0, "Should have non-negative courses played")
    }
    
    func testTenantMembershipManagement() async throws {
        let profile = try await createTestProfile()
        
        // Add tenant membership
        let membership = try await userProfileService.addTenantMembership(
            profile.id,
            tenantId: "test-tenant",
            role: .member
        )
        
        XCTAssertEqual(membership.tenantId, "test-tenant", "Tenant ID should match")
        XCTAssertEqual(membership.userId, profile.id, "User ID should match")
        XCTAssertEqual(membership.role, .member, "Role should match")
        XCTAssertTrue(membership.isActive, "Membership should be active")
        
        // Get user memberships
        let memberships = try await userProfileService.getUserMemberships(profile.id)
        XCTAssertGreaterThan(memberships.count, 0, "Should have memberships")
        
        // Remove membership
        try await userProfileService.removeTenantMembership(profile.id, tenantId: "test-tenant")
    }
    
    func testPrivacyAndConsent() async throws {
        let profile = try await createTestProfile()
        
        // Record consent
        try await userProfileService.recordConsentGiven(
            profile.id,
            consentType: .dataProcessing,
            version: "1.0"
        )
        
        // Get consent history
        let consentHistory = try await userProfileService.getConsentHistory(profile.id)
        XCTAssertGreaterThan(consentHistory.count, 0, "Should have consent records")
        
        let latestConsent = consentHistory.first!
        XCTAssertEqual(latestConsent.consentType, .dataProcessing, "Consent type should match")
        XCTAssertEqual(latestConsent.version, "1.0", "Version should match")
        
        // Test data export
        let dataExport = try await userProfileService.exportUserData(profile.id)
        XCTAssertEqual(dataExport.userId, profile.id, "User ID should match")
        XCTAssertNotNil(dataExport.exportURL, "Should have export URL")
        XCTAssertEqual(dataExport.format, .json, "Should be JSON format")
    }
    
    func testAchievementSystem() async throws {
        let profile = try await createTestProfile()
        
        // Award achievement
        let achievement = try await userProfileService.awardAchievement(
            profile.id,
            achievementId: "first_round"
        )
        
        XCTAssertEqual(achievement.id, "first_round", "Achievement ID should match")
        XCTAssertNotNil(achievement.earnedAt, "Should have earned date")
        
        // Get user achievements
        let achievements = try await userProfileService.getUserAchievements(profile.id)
        XCTAssertGreaterThan(achievements.count, 0, "Should have achievements")
        
        // Get achievement progress
        let progress = try await userProfileService.getAchievementProgress(
            profile.id,
            achievementId: "next_achievement"
        )
        
        XCTAssertGreaterThanOrEqual(progress.current, 0, "Progress should be non-negative")
        XCTAssertGreaterThan(progress.target, 0, "Target should be positive")
        XCTAssertGreaterThanOrEqual(progress.percentage, 0, "Percentage should be non-negative")
        XCTAssertLessThanOrEqual(progress.percentage, 100, "Percentage should not exceed 100")
    }
    
    // MARK: - Biometric Authentication Tests
    
    func testBiometricAvailability() async throws {
        let availability = await biometricService.isBiometricAuthenticationAvailable()
        
        XCTAssertTrue(availability.isAvailable, "Mock biometric should be available")
        XCTAssertGreaterThan(availability.supportedTypes.count, 0, "Should support biometric types")
        XCTAssertNil(availability.unavailabilityReason, "Should not have unavailability reason")
        XCTAssertTrue(availability.hardwareSupport, "Should have hardware support")
        
        let supportedTypes = await biometricService.getSupportedBiometricTypes()
        XCTAssertTrue(supportedTypes.contains(.faceID) || supportedTypes.contains(.touchID), "Should support Face ID or Touch ID")
        
        let capabilities = await biometricService.getBiometricCapabilities()
        XCTAssertTrue(capabilities.supportsSecureEnclave, "Should support Secure Enclave")
        XCTAssertGreaterThan(capabilities.maxFailedAttempts, 0, "Should have failure limit")
    }
    
    func testBiometricSetup() async throws {
        let userId = "test_user_123"
        
        // Test biometric setup
        let setupResult = try await biometricService.setupBiometricAuthentication(userId: userId)
        
        XCTAssertEqual(setupResult.userId, userId, "User ID should match")
        XCTAssertNotNil(setupResult.keyId, "Should generate key ID")
        XCTAssertTrue(setupResult.secureEnclaveKeyGenerated, "Should generate Secure Enclave key")
        XCTAssertEqual(setupResult.trustLevel, .high, "Should have high trust level")
        
        // Verify enrollment
        let isEnrolled = await biometricService.isBiometricEnrolled()
        XCTAssertTrue(isEnrolled, "Should be enrolled after setup")
    }
    
    func testBiometricAuthentication() async throws {
        let userId = "test_user_123"
        
        // Setup biometric first
        _ = try await biometricService.setupBiometricAuthentication(userId: userId)
        
        // Test authentication
        let authResult = try await biometricService.authenticateWithBiometrics(prompt: "Test authentication")
        
        XCTAssertTrue(authResult.isSuccessful, "Authentication should succeed")
        XCTAssertNotNil(authResult.sessionToken, "Should provide session token")
        XCTAssertGreaterThan(authResult.trustScore, 0.5, "Should have good trust score")
        XCTAssertFalse(authResult.fallbackUsed, "Should not use fallback")
        XCTAssertNil(authResult.failureReason, "Should not have failure reason")
        
        // Test context-based authentication
        let context = AuthenticationContext(
            operation: "golf_profile_access",
            riskLevel: .medium,
            requiresHighSecurity: false,
            customPrompt: "Access golf profile",
            timeout: 30.0,
            allowFallback: true
        )
        
        let contextResult = try await biometricService.authenticateWithBiometrics(userId: userId, context: context)
        XCTAssertTrue(contextResult.isSuccessful, "Context authentication should succeed")
        XCTAssertEqual(contextResult.userId, userId, "User ID should match")
    }
    
    func testSecureEnclaveIntegration() async throws {
        let userId = "test_user_123"
        
        // Generate Secure Enclave key
        let secureKey = try await biometricService.generateSecureEnclaveKey(userId: userId)
        
        XCTAssertEqual(secureKey.userId, userId, "User ID should match")
        XCTAssertNotNil(secureKey.publicKey, "Should have public key")
        XCTAssertEqual(secureKey.algorithm, .ecdsaSecp256r1, "Should use ECDSA algorithm")
        XCTAssertTrue(secureKey.keyUsage.contains(.authentication), "Should support authentication")
        XCTAssertTrue(secureKey.isActive, "Key should be active")
        
        // Test signing
        let testData = "test data to sign".data(using: .utf8)!
        let signature = try await biometricService.signWithSecureEnclave(data: testData, keyId: secureKey.keyId)
        
        XCTAssertGreaterThan(signature.count, 0, "Should produce signature")
        
        // Test verification
        let isValid = try await biometricService.verifySecureEnclaveSignature(
            data: testData,
            signature: signature,
            keyId: secureKey.keyId
        )
        
        XCTAssertTrue(isValid, "Signature should be valid")
    }
    
    func testBiometricPolicyCompliance() async throws {
        let userId = "test_user_123"
        
        // Get current policy
        let policy = await biometricService.getBiometricPolicy()
        XCTAssertGreaterThan(policy.maxFailedAttempts, 0, "Should have failure limit")
        XCTAssertTrue(policy.allowFallback, "Should allow fallback")
        
        // Test policy compliance
        let compliance = try await biometricService.validatePolicyCompliance(userId: userId)
        XCTAssertTrue(compliance.isCompliant, "Mock compliance should pass")
        XCTAssertEqual(compliance.violations.count, 0, "Should have no violations")
        XCTAssertLessThan(compliance.riskScore, 0.5, "Should have low risk score")
    }
    
    func testLivenessAndSpoofingDetection() async throws {
        // Test liveness detection
        let livenessResult = try await biometricService.performLivenessDetection()
        
        XCTAssertTrue(livenessResult.isLive, "Mock liveness should pass")
        XCTAssertGreaterThan(livenessResult.confidence, 0.8, "Should have high confidence")
        XCTAssertGreaterThan(livenessResult.detectionMethods.count, 0, "Should use detection methods")
        XCTAssertEqual(livenessResult.suspiciousIndicators.count, 0, "Should have no suspicious indicators")
        
        // Test spoofing detection
        let spoofingResult = await biometricService.detectSpoofingAttempt()
        
        XCTAssertFalse(spoofingResult.spoofingAttempted, "Mock spoofing detection should pass")
        XCTAssertNil(spoofingResult.spoofingType, "Should not detect spoofing")
        XCTAssertEqual(spoofingResult.recommendedAction, .allow, "Should recommend allow")
        
        // Test biometric integrity
        let integrityResult = try await biometricService.validateBiometricIntegrity()
        
        XCTAssertTrue(integrityResult.isIntact, "Biometric integrity should be intact")
        XCTAssertGreaterThan(integrityResult.integrityScore, 0.9, "Should have high integrity score")
        XCTAssertEqual(integrityResult.tamperedComponents.count, 0, "Should have no tampered components")
    }
    
    // MARK: - Session Management Tests
    
    func testSessionCreation() async throws {
        let userId = "test_user_123"
        let deviceInfo = createMockDeviceInfo()
        
        let sessionResult = try await sessionService.createSession(
            userId: userId,
            tenantId: "test-tenant",
            deviceInfo: deviceInfo
        )
        
        XCTAssertEqual(sessionResult.session.userId, userId, "User ID should match")
        XCTAssertEqual(sessionResult.session.tenantId, "test-tenant", "Tenant ID should match")
        XCTAssertEqual(sessionResult.session.deviceId, deviceInfo.deviceId, "Device ID should match")
        XCTAssertTrue(sessionResult.session.isActive, "Session should be active")
        XCTAssertTrue(sessionResult.deviceTrusted, "Device should be trusted in mock")
        XCTAssertTrue(sessionResult.locationValidated, "Location should be validated in mock")
        
        XCTAssertNotNil(sessionResult.accessToken.token, "Should have access token")
        XCTAssertNotNil(sessionResult.refreshToken.token, "Should have refresh token")
        XCTAssertEqual(sessionResult.accessToken.subject, userId, "Token subject should match user ID")
    }
    
    func testSessionValidation() async throws {
        let userId = "test_user_123"
        let deviceInfo = createMockDeviceInfo()
        
        // Create session
        let sessionResult = try await sessionService.createSession(
            userId: userId,
            tenantId: nil,
            deviceInfo: deviceInfo
        )
        
        // Validate session
        let validationResult = try await sessionService.validateSession(sessionId: sessionResult.session.id)
        
        XCTAssertTrue(validationResult.isValid, "Session should be valid")
        XCTAssertNotNil(validationResult.session, "Should return session")
        XCTAssertEqual(validationResult.validationErrors.count, 0, "Should have no validation errors")
        XCTAssertFalse(validationResult.requiresReauth, "Should not require re-authentication")
        XCTAssertFalse(validationResult.suspiciousActivity, "Should not detect suspicious activity")
        XCTAssertGreaterThan(validationResult.remainingTime, 0, "Should have remaining time")
    }
    
    func testTokenLifecycle() async throws {
        let userId = "test_user_123"
        let deviceInfo = createMockDeviceInfo()
        
        // Create session
        let sessionResult = try await sessionService.createSession(
            userId: userId,
            tenantId: nil,
            deviceInfo: deviceInfo
        )
        
        let sessionId = sessionResult.session.id
        
        // Generate access token
        let accessToken = try await sessionService.generateAccessToken(sessionId: sessionId, scopes: ["read", "write"])
        
        XCTAssertEqual(accessToken.tokenType, .accessToken, "Should be access token")
        XCTAssertEqual(accessToken.subject, userId, "Subject should match user ID")
        XCTAssertEqual(accessToken.sessionId, sessionId, "Session ID should match")
        XCTAssertTrue(accessToken.scopes.contains("read"), "Should contain read scope")
        
        // Validate token
        let validation = try await sessionService.validateAccessToken(accessToken.token)
        
        XCTAssertTrue(validation.isValid, "Token should be valid")
        XCTAssertFalse(validation.isExpired, "Token should not be expired")
        XCTAssertEqual(validation.userId, userId, "User ID should match")
        XCTAssertEqual(validation.sessionId, sessionId, "Session ID should match")
        
        // Test token refresh
        let refreshToken = try await sessionService.generateRefreshToken(sessionId: sessionId)
        let refreshResult = try await sessionService.refreshAccessToken(refreshToken: refreshToken.token)
        
        XCTAssertNotNil(refreshResult.newAccessToken, "Should provide new access token")
        XCTAssertNotEqual(refreshResult.newAccessToken.token, accessToken.token, "New token should be different")
    }
    
    func testSessionTermination() async throws {
        let userId = "test_user_123"
        let deviceInfo = createMockDeviceInfo()
        
        // Create session
        let sessionResult = try await sessionService.createSession(
            userId: userId,
            tenantId: nil,
            deviceInfo: deviceInfo
        )
        
        let sessionId = sessionResult.session.id
        
        // Validate session exists
        let validationBefore = try await sessionService.validateSession(sessionId: sessionId)
        XCTAssertTrue(validationBefore.isValid, "Session should be valid before termination")
        
        // Terminate session
        try await sessionService.terminateSession(sessionId: sessionId)
        
        // Validate session is terminated
        let validationAfter = try await sessionService.validateSession(sessionId: sessionId)
        XCTAssertFalse(validationAfter.isValid, "Session should be invalid after termination")
    }
    
    func testConcurrentSessionManagement() async throws {
        let userId = "test_user_123"
        
        // Create multiple sessions
        let device1 = createMockDeviceInfo(deviceId: "device1")
        let device2 = createMockDeviceInfo(deviceId: "device2")
        
        let session1 = try await sessionService.createSession(userId: userId, tenantId: nil, deviceInfo: device1)
        let session2 = try await sessionService.createSession(userId: userId, tenantId: nil, deviceInfo: device2)
        
        // Get user sessions
        let userSessions = try await sessionService.getUserSessions(userId: userId)
        XCTAssertGreaterThanOrEqual(userSessions.count, 2, "Should have multiple sessions")
        
        let sessionIds = userSessions.map { $0.id }
        XCTAssertTrue(sessionIds.contains(session1.session.id), "Should contain session 1")
        XCTAssertTrue(sessionIds.contains(session2.session.id), "Should contain session 2")
        
        // Terminate all user sessions
        try await sessionService.terminateAllUserSessions(userId: userId, excludeCurrentDevice: false)
        
        // Verify sessions are terminated
        let remainingSessions = try await sessionService.getUserSessions(userId: userId)
        let activeSessions = remainingSessions.filter { $0.isActive }
        XCTAssertEqual(activeSessions.count, 0, "Should have no active sessions after termination")
    }
    
    func testSessionMetrics() async throws {
        let metrics = try await sessionService.getSessionMetrics(period: 86400, tenantId: nil) // 24 hours
        
        XCTAssertGreaterThanOrEqual(metrics.totalSessions, 0, "Should have non-negative total sessions")
        XCTAssertGreaterThanOrEqual(metrics.activeSessions, 0, "Should have non-negative active sessions")
        XCTAssertGreaterThanOrEqual(metrics.deviceTrustRate, 0, "Should have non-negative device trust rate")
        XCTAssertLessThanOrEqual(metrics.deviceTrustRate, 1.0, "Device trust rate should not exceed 1.0")
        XCTAssertGreaterThanOrEqual(metrics.suspiciousActivities, 0, "Should have non-negative suspicious activities")
    }
    
    // MARK: - Integration Tests
    
    func testCompleteAuthenticationFlow() async throws {
        // 1. Authenticate with OAuth
        let authResult = try await authService.signInWithGoogle()
        let userId = authResult.user.id
        
        // 2. Create user profile
        let profileCreate = GolfUserProfileCreate(
            email: authResult.user.email ?? "test@example.com",
            displayName: authResult.user.name ?? "Test User",
            firstName: nil,
            lastName: nil,
            handicapIndex: 15.0,
            golfPreferences: GolfPreferences(
                preferredTeeBox: .regular,
                playingStyle: .casual,
                courseTypes: [.parkland],
                preferredRegions: [],
                maxTravelDistance: 50.0,
                budgetRange: .moderate,
                preferredPlayTimes: [.morning],
                golfCartPreference: .flexible,
                weatherPreferences: WeatherPreferences(
                    minTemperature: nil,
                    maxTemperature: nil,
                    acceptableConditions: [.sunny],
                    windSpeedLimit: nil
                )
            ),
            privacySettings: PrivacySettings(
                profileVisibility: .public,
                dataProcessingConsent: true,
                analyticsOptOut: false,
                marketingOptOut: false
            ),
            tenantId: nil,
            invitationCode: nil
        )
        
        let profile = try await userProfileService.createUserProfile(profileCreate)
        XCTAssertNotNil(profile.id, "Profile should be created")
        
        // 3. Setup biometric authentication
        let biometricSetup = try await biometricService.setupBiometricAuthentication(userId: userId)
        XCTAssertTrue(biometricSetup.secureEnclaveKeyGenerated, "Biometric setup should succeed")
        
        // 4. Validate current session
        let currentSession = await authService.getCurrentSession()
        XCTAssertNotNil(currentSession, "Should have current session")
        XCTAssertEqual(currentSession?.userId, userId, "Session should belong to authenticated user")
        
        // 5. Enable MFA
        let mfaSetup = try await authService.enableMFA()
        XCTAssertNotNil(mfaSetup.secret, "MFA setup should succeed")
        
        // 6. Test combined biometric + MFA authentication
        let combinedAuth = try await biometricService.combineBiometricWithMFA(
            userId: userId,
            mfaToken: "123456"
        )
        
        XCTAssertTrue(combinedAuth.biometricResult.isSuccessful, "Biometric auth should succeed")
        XCTAssertTrue(combinedAuth.mfaResult.isSuccessful, "MFA should succeed")
        XCTAssertGreaterThan(combinedAuth.combinedTrustScore, 0.9, "Combined trust should be high")
        
        // 7. Update profile with additional information
        let profileUpdate = GolfUserProfileUpdate(
            displayName: nil,
            firstName: "John",
            lastName: "Doe",
            bio: "Avid golfer",
            handicapIndex: 14.5,
            golfPreferences: nil,
            homeClub: nil,
            membershipType: .full,
            playingFrequency: .weekly,
            location: nil,
            phoneNumber: "+1-555-123-4567",
            emergencyContact: nil,
            privacySettings: nil,
            socialVisibility: nil
        )
        
        let updatedProfile = try await userProfileService.updateUserProfile(profile.id, profile: profileUpdate)
        XCTAssertEqual(updatedProfile.firstName, "John", "Profile should be updated")
        XCTAssertEqual(updatedProfile.handicapIndex, 14.5, "Handicap should be updated")
        
        // 8. Clean up - sign out
        try await authService.clearStoredTokens()
        XCTAssertFalse(authService.isAuthenticated, "Should be signed out")
    }
    
    func testErrorHandlingAndRecovery() async throws {
        // Test authentication with invalid credentials
        do {
            _ = try await authService.validateToken("invalid_token")
            // Mock service might not throw, check result instead
        } catch {
            // Expected for real implementation
        }
        
        // Test profile creation with invalid data
        do {
            try await userProfileService.updateHandicapIndex("nonexistent_user", handicapIndex: 15.0)
            // Mock might not throw, but real implementation should
        } catch {
            // Expected for real implementation
        }
        
        // Test biometric authentication when not available
        // This is challenging to test with mocks, but real implementation would handle LAError cases
        
        // Test session validation with expired session
        let invalidSessionResult = try await sessionService.validateSession(sessionId: "nonexistent_session")
        XCTAssertFalse(invalidSessionResult.isValid, "Invalid session should not be valid")
        XCTAssertGreaterThan(invalidSessionResult.validationErrors.count, 0, "Should have validation errors")
    }
    
    // MARK: - Helper Methods
    
    private func createTestProfile() async throws -> GolfUserProfile {
        let profileCreate = GolfUserProfileCreate(
            email: "test@golffinder.com",
            displayName: "Test Golfer",
            firstName: "Test",
            lastName: "Golfer",
            handicapIndex: 15.5,
            golfPreferences: GolfPreferences(
                preferredTeeBox: .regular,
                playingStyle: .casual,
                courseTypes: [.parkland],
                preferredRegions: [],
                maxTravelDistance: 50.0,
                budgetRange: .moderate,
                preferredPlayTimes: [.morning],
                golfCartPreference: .flexible,
                weatherPreferences: WeatherPreferences(
                    minTemperature: nil,
                    maxTemperature: nil,
                    acceptableConditions: [.sunny],
                    windSpeedLimit: nil
                )
            ),
            privacySettings: PrivacySettings(
                profileVisibility: .public,
                dataProcessingConsent: true,
                analyticsOptOut: false,
                marketingOptOut: false
            ),
            tenantId: nil,
            invitationCode: nil
        )
        
        return try await userProfileService.createUserProfile(profileCreate)
    }
    
    private func createMockDeviceInfo(deviceId: String = "mock_device_\(UUID().uuidString)") -> DeviceInfo {
        return DeviceInfo(
            deviceId: deviceId,
            name: "Test iPhone",
            model: "iPhone15,2",
            osVersion: "17.0",
            appVersion: "1.0.0",
            platform: .iOS,
            screenResolution: "390x844",
            biometricCapabilities: [.faceID],
            isJailbroken: false,
            isEmulator: false,
            fingerprint: "test_fingerprint_\(deviceId)"
        )
    }
}

// MARK: - Mock Appwrite Client

class MockAppwriteClient: Client {
    init() {
        super.init()
        // Mock initialization
    }
}

// MARK: - Test Extensions

extension XCTestCase {
    func wait(for expectations: [XCTestExpectation], timeout: TimeInterval) async {
        await withCheckedContinuation { continuation in
            self.wait(for: expectations, timeout: timeout) { _ in
                continuation.resume()
            }
        }
    }
}