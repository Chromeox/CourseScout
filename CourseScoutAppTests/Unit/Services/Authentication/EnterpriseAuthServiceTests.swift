import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - Enterprise Authentication Service Tests

final class EnterpriseAuthServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: EnterpriseAuthService!
    private var mockAppwriteClient: MockAppwriteClient!
    private var mockSecurityService: MockSecurityService!
    private var mockSessionManager: MockSessionManagementService!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        mockAppwriteClient = MockAppwriteClient()
        mockSecurityService = MockSecurityService()
        mockSessionManager = MockSessionManagementService()
        cancellables = Set<AnyCancellable>()
        
        sut = EnterpriseAuthService(
            appwriteClient: mockAppwriteClient,
            securityService: mockSecurityService,
            sessionManager: mockSessionManager
        )
    }
    
    override func tearDown() {
        cancellables = nil
        sut = nil
        mockSessionManager = nil
        mockSecurityService = nil
        mockAppwriteClient = nil
        
        super.tearDown()
    }
    
    // MARK: - SSO Configuration Tests
    
    func testConfigureSSO_AzureAD_Success() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let azureConfig = TestDataFactory.createAzureADSSOConfig(tenantId: tenantId)
        let expectedConfig = TestDataFactory.createSSOConfiguration()
        mockAppwriteClient.mockSSOConfiguration = expectedConfig
        
        // When
        let result = try await sut.configureSSO(config: azureConfig)
        
        // Then
        XCTAssertEqual(result.provider, .azureAD)
        XCTAssertEqual(result.tenantId, tenantId)
        XCTAssertEqual(result.status, .active)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testConfigureSSO_GoogleWorkspace_Success() async throws {
        // Given
        let domain = "example.com"
        let googleConfig = TestDataFactory.createGoogleWorkspaceSSOConfig(domain: domain)
        let expectedConfig = TestDataFactory.createSSOConfiguration()
        mockAppwriteClient.mockSSOConfiguration = expectedConfig
        
        // When
        let result = try await sut.configureSSO(config: googleConfig)
        
        // Then
        XCTAssertEqual(result.provider, .googleWorkspace)
        XCTAssertEqual(result.domain, domain)
        XCTAssertEqual(result.status, .active)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testConfigureSSO_Okta_Success() async throws {
        // Given
        let orgUrl = "https://example.okta.com"
        let oktaConfig = TestDataFactory.createOktaSSOConfig(orgUrl: orgUrl)
        let expectedConfig = TestDataFactory.createSSOConfiguration()
        mockAppwriteClient.mockSSOConfiguration = expectedConfig
        
        // When
        let result = try await sut.configureSSO(config: oktaConfig)
        
        // Then
        XCTAssertEqual(result.provider, .okta)
        XCTAssertEqual(result.orgUrl, orgUrl)
        XCTAssertEqual(result.status, .active)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testConfigureSSO_SAML_Success() async throws {
        // Given
        let samlConfig = TestDataFactory.createSAMLSSOConfig()
        let expectedConfig = TestDataFactory.createSSOConfiguration()
        mockAppwriteClient.mockSSOConfiguration = expectedConfig
        
        // When
        let result = try await sut.configureSSO(config: samlConfig)
        
        // Then
        XCTAssertEqual(result.provider, .saml)
        XCTAssertNotNil(result.entityId)
        XCTAssertNotNil(result.ssoUrl)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testConfigureSSO_InvalidConfiguration() async {
        // Given
        let invalidConfig = SSOConfiguration(
            id: "invalid_config",
            tenantId: "test_tenant",
            provider: .azureAD,
            clientId: "", // Invalid: empty client ID
            clientSecret: "secret",
            redirectUri: "invalid-uri", // Invalid URI format
            additionalSettings: [:],
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // When & Then
        do {
            _ = try await sut.configureSSO(config: invalidConfig)
            XCTFail("Expected configuration to fail")
        } catch AuthenticationError.invalidConfiguration {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - SSO Authentication Tests
    
    func testAuthenticateWithSSO_AzureAD_Success() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .azureAD, tenantId: tenantId)
        let expectedResult = TestDataFactory.createEnterpriseAuthResult()
        
        mockAppwriteClient.mockSSOConfiguration = ssoConfig
        mockAppwriteClient.mockEnterpriseAuthResult = expectedResult
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.authenticateWithSSO(
            provider: .azureAD,
            tenantId: tenantId,
            authorizationCode: "valid_auth_code"
        )
        
        // Then
        XCTAssertEqual(result.provider, .azureAD)
        XCTAssertEqual(result.tenantId, tenantId)
        XCTAssertNotNil(result.accessToken)
        XCTAssertNotNil(result.user)
    }
    
    func testAuthenticateWithSSO_GoogleWorkspace_Success() async throws {
        // Given
        let domain = "example.com"
        let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .googleWorkspace, domain: domain)
        let expectedResult = TestDataFactory.createEnterpriseAuthResult()
        
        mockAppwriteClient.mockSSOConfiguration = ssoConfig
        mockAppwriteClient.mockEnterpriseAuthResult = expectedResult
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.authenticateWithSSO(
            provider: .googleWorkspace,
            domain: domain,
            authorizationCode: "valid_auth_code"
        )
        
        // Then
        XCTAssertEqual(result.provider, .googleWorkspace)
        XCTAssertEqual(result.domain, domain)
        XCTAssertNotNil(result.accessToken)
        XCTAssertNotNil(result.user)
    }
    
    func testAuthenticateWithSSO_Okta_Success() async throws {
        // Given
        let orgUrl = "https://example.okta.com"
        let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .okta, orgUrl: orgUrl)
        let expectedResult = TestDataFactory.createEnterpriseAuthResult()
        
        mockAppwriteClient.mockSSOConfiguration = ssoConfig
        mockAppwriteClient.mockEnterpriseAuthResult = expectedResult
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        
        // When
        let result = try await sut.authenticateWithSSO(
            provider: .okta,
            orgUrl: orgUrl,
            authorizationCode: "valid_auth_code"
        )
        
        // Then
        XCTAssertEqual(result.provider, .okta)
        XCTAssertEqual(result.orgUrl, orgUrl)
        XCTAssertNotNil(result.accessToken)
        XCTAssertNotNil(result.user)
    }
    
    func testAuthenticateWithSSO_InvalidAuthCode() async {
        // Given
        let tenantId = "test_tenant_id"
        let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .azureAD, tenantId: tenantId)
        
        mockAppwriteClient.mockSSOConfiguration = ssoConfig
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.invalidCredentials
        
        // When & Then
        do {
            _ = try await sut.authenticateWithSSO(
                provider: .azureAD,
                tenantId: tenantId,
                authorizationCode: "invalid_auth_code"
            )
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.invalidCredentials {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testAuthenticateWithSSO_ProviderNotConfigured() async {
        // Given
        let tenantId = "test_tenant_id"
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.ssoNotConfigured
        
        // When & Then
        do {
            _ = try await sut.authenticateWithSSO(
                provider: .azureAD,
                tenantId: tenantId,
                authorizationCode: "auth_code"
            )
            XCTFail("Expected authentication to fail")
        } catch AuthenticationError.ssoNotConfigured {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - SAML Authentication Tests
    
    func testAuthenticateWithSAML_Success() async throws {
        // Given
        let samlResponse = TestDataFactory.createValidSAMLResponse()
        let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .saml)
        let expectedResult = TestDataFactory.createEnterpriseAuthResult()
        
        mockAppwriteClient.mockSSOConfiguration = ssoConfig
        mockAppwriteClient.mockEnterpriseAuthResult = expectedResult
        mockSessionManager.mockCreateSessionResult = TestDataFactory.createSessionResult()
        mockSecurityService.mockValidSAMLResponse = true
        
        // When
        let result = try await sut.authenticateWithSAML(
            tenantId: "test_tenant",
            samlResponse: samlResponse
        )
        
        // Then
        XCTAssertEqual(result.provider, .saml)
        XCTAssertNotNil(result.accessToken)
        XCTAssertNotNil(result.user)
        XCTAssertEqual(mockSecurityService.validateSAMLResponseCallCount, 1)
    }
    
    func testAuthenticateWithSAML_InvalidResponse() async {
        // Given
        let invalidSamlResponse = "invalid_saml_response"
        let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .saml)
        
        mockAppwriteClient.mockSSOConfiguration = ssoConfig
        mockSecurityService.mockValidSAMLResponse = false
        
        // When & Then
        do {
            _ = try await sut.authenticateWithSAML(
                tenantId: "test_tenant",
                samlResponse: invalidSamlResponse
            )
            XCTFail("Expected SAML authentication to fail")
        } catch AuthenticationError.invalidSAMLResponse {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testAuthenticateWithSAML_ExpiredAssertion() async {
        // Given
        let expiredSamlResponse = TestDataFactory.createExpiredSAMLResponse()
        let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .saml)
        
        mockAppwriteClient.mockSSOConfiguration = ssoConfig
        mockSecurityService.shouldThrowError = true
        mockSecurityService.errorToThrow = AuthenticationError.samlAssertionExpired
        
        // When & Then
        do {
            _ = try await sut.authenticateWithSAML(
                tenantId: "test_tenant",
                samlResponse: expiredSamlResponse
            )
            XCTFail("Expected SAML authentication to fail")
        } catch AuthenticationError.samlAssertionExpired {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Enterprise User Provisioning Tests
    
    func testProvisionEnterpriseUser_Success() async throws {
        // Given
        let userInfo = TestDataFactory.createEnterpriseUserInfo()
        let tenantId = "test_tenant_id"
        let expectedUser = TestDataFactory.createEnterpriseUser()
        
        mockAppwriteClient.mockEnterpriseUser = expectedUser
        
        // When
        let result = try await sut.provisionEnterpriseUser(
            userInfo: userInfo,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertEqual(result.id, expectedUser.id)
        XCTAssertEqual(result.email, userInfo.email)
        XCTAssertEqual(result.tenantId, tenantId)
        XCTAssertEqual(result.roles.count, userInfo.roles.count)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testProvisionEnterpriseUser_DuplicateEmail() async {
        // Given
        let userInfo = TestDataFactory.createEnterpriseUserInfo(email: "duplicate@example.com")
        let tenantId = "test_tenant_id"
        
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.emailAlreadyExists
        
        // When & Then
        do {
            _ = try await sut.provisionEnterpriseUser(
                userInfo: userInfo,
                tenantId: tenantId
            )
            XCTFail("Expected provisioning to fail")
        } catch AuthenticationError.emailAlreadyExists {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testProvisionEnterpriseUser_InvalidRole() async {
        // Given
        let invalidUserInfo = EnterpriseUserInfo(
            email: "test@example.com",
            firstName: "Test",
            lastName: "User",
            department: "IT",
            jobTitle: "Developer",
            roles: ["invalid_role"], // Invalid role
            groups: [],
            attributes: [:]
        )
        let tenantId = "test_tenant_id"
        
        // When & Then
        do {
            _ = try await sut.provisionEnterpriseUser(
                userInfo: invalidUserInfo,
                tenantId: tenantId
            )
            XCTFail("Expected provisioning to fail")
        } catch AuthenticationError.invalidRole {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testDeprovisionEnterpriseUser_Success() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        
        // When
        try await sut.deprovisionEnterpriseUser(
            userId: userId,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1) // Deactivate user
        XCTAssertEqual(mockSessionManager.terminateAllUserSessionsCallCount, 1) // Terminate sessions
    }
    
    func testDeprovisionEnterpriseUser_UserNotFound() async {
        // Given
        let userId = "nonexistent_user_id"
        let tenantId = "test_tenant_id"
        
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.userNotFound
        
        // When & Then
        do {
            try await sut.deprovisionEnterpriseUser(
                userId: userId,
                tenantId: tenantId
            )
            XCTFail("Expected deprovisioning to fail")
        } catch AuthenticationError.userNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Directory Synchronization Tests
    
    func testSynchronizeDirectory_Success() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let directoryConfig = TestDataFactory.createDirectoryConfig()
        let directoryUsers = TestDataFactory.createDirectoryUsers(count: 10)
        let syncResult = TestDataFactory.createDirectorySyncResult()
        
        mockAppwriteClient.mockDirectoryConfig = directoryConfig
        mockAppwriteClient.mockDirectoryUsers = directoryUsers
        mockAppwriteClient.mockSyncResult = syncResult
        
        // When
        let result = try await sut.synchronizeDirectory(tenantId: tenantId)
        
        // Then
        XCTAssertEqual(result.totalUsers, 10)
        XCTAssertEqual(result.usersCreated, syncResult.usersCreated)
        XCTAssertEqual(result.usersUpdated, syncResult.usersUpdated)
        XCTAssertEqual(result.usersDeactivated, syncResult.usersDeactivated)
        XCTAssertEqual(result.status, .completed)
    }
    
    func testSynchronizeDirectory_NoConfig() async {
        // Given
        let tenantId = "test_tenant_id"
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.directoryNotConfigured
        
        // When & Then
        do {
            _ = try await sut.synchronizeDirectory(tenantId: tenantId)
            XCTFail("Expected synchronization to fail")
        } catch AuthenticationError.directoryNotConfigured {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSynchronizeDirectory_PartialFailure() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let directoryConfig = TestDataFactory.createDirectoryConfig()
        let directoryUsers = TestDataFactory.createDirectoryUsers(count: 10)
        let syncResult = TestDataFactory.createPartialSyncResult()
        
        mockAppwriteClient.mockDirectoryConfig = directoryConfig
        mockAppwriteClient.mockDirectoryUsers = directoryUsers
        mockAppwriteClient.mockSyncResult = syncResult
        
        // When
        let result = try await sut.synchronizeDirectory(tenantId: tenantId)
        
        // Then
        XCTAssertEqual(result.status, .partialFailure)
        XCTAssertGreaterThan(result.errors.count, 0)
        XCTAssertLessThan(result.usersCreated + result.usersUpdated, result.totalUsers)
    }
    
    // MARK: - Enterprise Policy Enforcement Tests
    
    func testEnforcePasswordPolicy_Success() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let password = "StrongP@ssw0rd123!"
        let policy = TestDataFactory.createPasswordPolicy()
        
        mockAppwriteClient.mockPasswordPolicy = policy
        mockSecurityService.mockPasswordCompliant = true
        
        // When
        let result = try await sut.validatePasswordPolicy(
            password: password,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertTrue(result.isCompliant)
        XCTAssertTrue(result.violations.isEmpty)
    }
    
    func testEnforcePasswordPolicy_Violations() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let weakPassword = "weak"
        let policy = TestDataFactory.createPasswordPolicy()
        
        mockAppwriteClient.mockPasswordPolicy = policy
        mockSecurityService.mockPasswordCompliant = false
        mockSecurityService.mockPasswordViolations = [
            .tooShort,
            .missingUppercase,
            .missingNumbers,
            .missingSpecialCharacters
        ]
        
        // When
        let result = try await sut.validatePasswordPolicy(
            password: weakPassword,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertFalse(result.isCompliant)
        XCTAssertEqual(result.violations.count, 4)
        XCTAssertContains(result.violations, .tooShort)
    }
    
    func testEnforceSessionPolicy_Success() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let sessionId = "test_session_id"
        let policy = TestDataFactory.createSessionPolicy()
        let session = TestDataFactory.createSessionInfo(id: sessionId)
        
        mockAppwriteClient.mockSessionPolicy = policy
        mockAppwriteClient.mockSessionInfo = session
        mockSecurityService.mockSessionCompliant = true
        
        // When
        let result = try await sut.validateSessionPolicy(
            sessionId: sessionId,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertTrue(result.isCompliant)
        XCTAssertFalse(result.requiresTermination)
    }
    
    func testEnforceSessionPolicy_Violations() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let sessionId = "test_session_id"
        let policy = TestDataFactory.createSessionPolicy()
        let expiredSession = TestDataFactory.createExpiredSessionInfo(id: sessionId)
        
        mockAppwriteClient.mockSessionPolicy = policy
        mockAppwriteClient.mockSessionInfo = expiredSession
        mockSecurityService.mockSessionCompliant = false
        mockSecurityService.mockSessionViolations = [.sessionExpired, .inactivityTimeout]
        
        // When
        let result = try await sut.validateSessionPolicy(
            sessionId: sessionId,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertFalse(result.isCompliant)
        XCTAssertTrue(result.requiresTermination)
        XCTAssertEqual(result.violations.count, 2)
    }
    
    // MARK: - Performance Tests
    
    func testSSOConfigurationPerformance() {
        let config = TestDataFactory.createAzureADSSOConfig(tenantId: "test_tenant")
        
        measure {
            let expectation = XCTestExpectation(description: "SSO configuration performance")
            
            Task {
                do {
                    _ = try await sut.configureSSO(config: config)
                } catch {
                    // Ignore errors for performance test
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testBulkUserProvisioningPerformance() {
        let userInfos = (1...100).map { TestDataFactory.createEnterpriseUserInfo(email: "user\($0)@example.com") }
        let tenantId = "test_tenant_id"
        
        measure {
            let expectation = XCTestExpectation(description: "Bulk provisioning performance")
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for userInfo in userInfos {
                        group.addTask {
                            do {
                                _ = try await self.sut.provisionEnterpriseUser(
                                    userInfo: userInfo,
                                    tenantId: tenantId
                                )
                            } catch {
                                // Ignore errors for performance test
                            }
                        }
                    }
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentSSOAuthentication() async {
        // Given
        let taskCount = 10
        let tenantId = "test_tenant_id"
        
        // When
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    do {
                        _ = try await self.sut.authenticateWithSSO(
                            provider: .azureAD,
                            tenantId: tenantId,
                            authorizationCode: "auth_code_\(i)"
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
            XCTAssertEqual(results.count, taskCount)
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testSSOWithSpecialCharactersInConfig() async throws {
        // Given
        let specialConfig = SSOConfiguration(
            id: "special_config",
            tenantId: "test_tenant",
            provider: .azureAD,
            clientId: "client_with_éç_special_chars",
            clientSecret: "secret_with_特殊_chars",
            redirectUri: "https://example.com/callback?param=value&other=é",
            additionalSettings: [
                "domain_hint": "example.com",
                "special_param": "value_with_éç_chars"
            ],
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let expectedResult = TestDataFactory.createSSOConfiguration()
        mockAppwriteClient.mockSSOConfiguration = expectedResult
        
        // When
        let result = try await sut.configureSSO(config: specialConfig)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testDirectorySyncWithLargeDataset() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let largeUserCount = 10000
        let directoryConfig = TestDataFactory.createDirectoryConfig()
        let largeUserSet = TestDataFactory.createDirectoryUsers(count: largeUserCount)
        let syncResult = TestDataFactory.createDirectorySyncResult(totalUsers: largeUserCount)
        
        mockAppwriteClient.mockDirectoryConfig = directoryConfig
        mockAppwriteClient.mockDirectoryUsers = largeUserSet
        mockAppwriteClient.mockSyncResult = syncResult
        
        // When
        let result = try await sut.synchronizeDirectory(tenantId: tenantId)
        
        // Then
        XCTAssertEqual(result.totalUsers, largeUserCount)
        XCTAssertEqual(result.status, .completed)
    }
}