import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - Enterprise Authentication Integration Tests

final class EnterpriseAuthIntegrationTests: XCTestCase {
    
    // MARK: - Properties
    
    private var enterpriseAuthService: EnterpriseAuthService!
    private var authService: AuthenticationService!
    private var roleService: RoleManagementService!
    private var sessionManager: SessionManagementService!
    private var userProfileService: UserProfileService!
    
    private var mockAppwriteClient: MockAppwriteClient!
    private var mockSecurityService: MockSecurityService!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        mockAppwriteClient = MockAppwriteClient()
        mockSecurityService = MockSecurityService()
        cancellables = Set<AnyCancellable>()
        
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
        
        authService = AuthenticationService(
            appwriteClient: mockAppwriteClient,
            sessionManager: sessionManager,
            securityService: mockSecurityService
        )
        
        enterpriseAuthService = EnterpriseAuthService(
            appwriteClient: mockAppwriteClient,
            securityService: mockSecurityService,
            sessionManager: sessionManager
        )
    }
    
    override func tearDown() {
        cancellables = nil
        enterpriseAuthService = nil
        authService = nil
        roleService = nil
        sessionManager = nil
        userProfileService = nil
        mockSecurityService = nil
        mockAppwriteClient = nil
        
        super.tearDown()
    }
    
    // MARK: - Azure AD Integration Tests
    
    func testAzureADEnterpriseSetup_CompleteFlow() async throws {
        // Given
        let tenantId = "azure_tenant_123"
        let enterpriseOrg = "contoso.com"
        
        // Azure AD SSO Configuration
        let azureConfig = SSOConfiguration(
            id: "azure_sso_config",
            tenantId: tenantId,
            provider: .azureAD,
            clientId: "azure_client_id",
            clientSecret: "azure_client_secret",
            redirectUri: "https://golffinder.com/auth/azure/callback",
            additionalSettings: [
                "authority": "https://login.microsoftonline.com/\(tenantId)",
                "scope": "openid profile email",
                "response_type": "code",
                "tenant_id": tenantId
            ],
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Enterprise roles setup
        let enterpriseRoles = [
            TestDataFactory.createRole(name: "Global Admin", permissions: [.manageUsers, .manageRoles, .manageEnterprise]),
            TestDataFactory.createRole(name: "Department Manager", permissions: [.manageUsers, .readUsers]),
            TestDataFactory.createRole(name: "Employee", permissions: [.readUsers])
        ]
        
        // Setup mocks
        mockAppwriteClient.mockSSOConfiguration = azureConfig
        mockAppwriteClient.mockEnterpriseRoles = enterpriseRoles
        mockAppwriteClient.mockEnterpriseAuthResult = TestDataFactory.createEnterpriseAuthResult()
        
        // When - Execute complete Azure AD setup
        // 1. Configure Azure AD SSO
        let configResult = try await enterpriseAuthService.configureSSO(config: azureConfig)
        
        // 2. Setup enterprise roles
        var createdRoles: [Role] = []
        for roleTemplate in enterpriseRoles {
            let roleData = TestDataFactory.createRoleDataFromRole(roleTemplate)
            let createdRole = try await roleService.createRole(roleData: roleData)
            createdRoles.append(createdRole)
        }
        
        // 3. Authenticate with Azure AD
        let authResult = try await enterpriseAuthService.authenticateWithSSO(
            provider: .azureAD,
            tenantId: tenantId,
            authorizationCode: "azure_auth_code_123"
        )
        
        // 4. Provision enterprise user
        let userInfo = EnterpriseUserInfo(
            email: "john.doe@contoso.com",
            firstName: "John",
            lastName: "Doe",
            department: "Engineering",
            jobTitle: "Senior Developer",
            roles: ["Department Manager"],
            groups: ["Engineering", "Developers"],
            attributes: [
                "office_location": "Seattle",
                "employee_id": "EMP001",
                "cost_center": "TECH"
            ]
        )
        
        let provisionedUser = try await enterpriseAuthService.provisionEnterpriseUser(
            userInfo: userInfo,
            tenantId: tenantId
        )
        
        // 5. Assign appropriate role
        let managerRole = createdRoles.first { $0.name == "Department Manager" }!
        let assignmentData = TestDataFactory.createRoleAssignmentData(
            userId: provisionedUser.id,
            roleId: managerRole.id,
            tenantId: tenantId
        )
        let roleAssignment = try await roleService.assignRoleToUser(assignmentData: assignmentData)
        
        // 6. Validate enterprise permissions
        let hasManageUsersPermission = try await roleService.checkUserPermission(
            userId: provisionedUser.id,
            permission: .manageUsers,
            tenantId: tenantId
        )
        
        let hasManageEnterprisePermission = try await roleService.checkUserPermission(
            userId: provisionedUser.id,
            permission: .manageEnterprise,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertEqual(configResult.provider, .azureAD)
        XCTAssertEqual(configResult.tenantId, tenantId)
        XCTAssertEqual(configResult.status, .active)
        
        XCTAssertEqual(createdRoles.count, 3)
        XCTAssertTrue(createdRoles.contains { $0.name == "Global Admin" })
        
        XCTAssertEqual(authResult.provider, .azureAD)
        XCTAssertEqual(authResult.tenantId, tenantId)
        XCTAssertNotNil(authResult.accessToken)
        
        XCTAssertEqual(provisionedUser.email, userInfo.email)
        XCTAssertEqual(provisionedUser.tenantId, tenantId)
        XCTAssertEqual(provisionedUser.roles.count, 1)
        
        XCTAssertEqual(roleAssignment.userId, provisionedUser.id)
        XCTAssertEqual(roleAssignment.roleId, managerRole.id)
        XCTAssertEqual(roleAssignment.status, .active)
        
        XCTAssertTrue(hasManageUsersPermission) // Manager has this
        XCTAssertFalse(hasManageEnterprisePermission) // Manager doesn't have this
    }
    
    func testGoogleWorkspaceIntegration_DomainBasedAuth() async throws {
        // Given
        let domain = "example.com"
        let tenantId = "google_workspace_tenant"
        
        // Google Workspace SSO Configuration
        let googleConfig = SSOConfiguration(
            id: "google_workspace_config",
            tenantId: tenantId,
            provider: .googleWorkspace,
            clientId: "google_workspace_client_id",
            clientSecret: "google_workspace_client_secret",
            redirectUri: "https://golffinder.com/auth/google/callback",
            additionalSettings: [
                "hosted_domain": domain,
                "scope": "openid profile email",
                "access_type": "offline"
            ],
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Setup domain-specific roles
        let domainRoles = [
            TestDataFactory.createRole(name: "Workspace Admin", permissions: [.manageUsers, .manageWorkspace]),
            TestDataFactory.createRole(name: "Department Head", permissions: [.manageUsers, .readUsers]),
            TestDataFactory.createRole(name: "Team Member", permissions: [.readUsers])
        ]
        
        // Setup mocks
        mockAppwriteClient.mockSSOConfiguration = googleConfig
        mockAppwriteClient.mockDomainRoles = domainRoles
        mockAppwriteClient.mockEnterpriseAuthResult = TestDataFactory.createEnterpriseAuthResult()
        
        // When - Execute Google Workspace integration
        // 1. Configure Google Workspace SSO
        let configResult = try await enterpriseAuthService.configureSSO(config: googleConfig)
        
        // 2. Authenticate with domain verification
        let authResult = try await enterpriseAuthService.authenticateWithSSO(
            provider: .googleWorkspace,
            domain: domain,
            authorizationCode: "google_workspace_auth_code"
        )
        
        // 3. Validate domain membership
        let isDomainMember = authResult.user.email?.hasSuffix("@\(domain)") ?? false
        XCTAssertTrue(isDomainMember, "User should belong to the configured domain")
        
        // 4. Auto-provision user based on domain
        let userInfo = EnterpriseUserInfo(
            email: authResult.user.email!,
            firstName: authResult.user.name ?? "Unknown",
            lastName: "User",
            department: "Auto-Provisioned",
            jobTitle: "Team Member",
            roles: ["Team Member"],
            groups: [domain],
            attributes: [
                "domain": domain,
                "auto_provisioned": "true"
            ]
        )
        
        let provisionedUser = try await enterpriseAuthService.provisionEnterpriseUser(
            userInfo: userInfo,
            tenantId: tenantId
        )
        
        // 5. Verify domain-based role assignment
        let teamMemberRole = domainRoles.first { $0.name == "Team Member" }!
        mockAppwriteClient.mockUserRoles = [teamMemberRole]
        
        let userRoles = try await roleService.getUserRoles(
            userId: provisionedUser.id,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertEqual(configResult.provider, .googleWorkspace)
        XCTAssertEqual(configResult.domain, domain)
        
        XCTAssertEqual(authResult.provider, .googleWorkspace)
        XCTAssertEqual(authResult.domain, domain)
        
        XCTAssertEqual(provisionedUser.email, authResult.user.email)
        XCTAssertTrue(provisionedUser.attributes["domain"] as? String == domain)
        
        XCTAssertEqual(userRoles.count, 1)
        XCTAssertEqual(userRoles.first?.name, "Team Member")
    }
    
    func testOktaEnterpriseIntegration_CompleteFlow() async throws {
        // Given
        let orgUrl = "https://dev-123456.okta.com"
        let tenantId = "okta_enterprise_tenant"
        
        // Okta SSO Configuration
        let oktaConfig = SSOConfiguration(
            id: "okta_sso_config",
            tenantId: tenantId,
            provider: .okta,
            clientId: "okta_client_id",
            clientSecret: "okta_client_secret",
            redirectUri: "https://golffinder.com/auth/okta/callback",
            additionalSettings: [
                "org_url": orgUrl,
                "authorization_server": "default",
                "scope": "openid profile email groups"
            ],
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Setup Okta group-based roles
        let oktaRoles = [
            TestDataFactory.createRole(name: "Okta Admin", permissions: [.manageUsers, .manageRoles, .manageOkta]),
            TestDataFactory.createRole(name: "Manager", permissions: [.manageUsers, .readUsers]),
            TestDataFactory.createRole(name: "User", permissions: [.readUsers])
        ]
        
        // Setup mocks
        mockAppwriteClient.mockSSOConfiguration = oktaConfig
        mockAppwriteClient.mockOktaRoles = oktaRoles
        mockAppwriteClient.mockEnterpriseAuthResult = TestDataFactory.createEnterpriseAuthResult()
        
        // When - Execute Okta integration
        // 1. Configure Okta SSO
        let configResult = try await enterpriseAuthService.configureSSO(config: oktaConfig)
        
        // 2. Authenticate with Okta
        let authResult = try await enterpriseAuthService.authenticateWithSSO(
            provider: .okta,
            orgUrl: orgUrl,
            authorizationCode: "okta_auth_code"
        )
        
        // 3. Process Okta groups and map to roles
        let oktaGroups = ["Engineering", "Managers", "Full-Time"]
        let userInfo = EnterpriseUserInfo(
            email: "jane.smith@company.com",
            firstName: "Jane",
            lastName: "Smith",
            department: "Engineering",
            jobTitle: "Engineering Manager",
            roles: ["Manager"], // Mapped from Okta group
            groups: oktaGroups,
            attributes: [
                "okta_org": orgUrl,
                "okta_groups": oktaGroups.joined(separator: ","),
                "employment_type": "Full-Time"
            ]
        )
        
        let provisionedUser = try await enterpriseAuthService.provisionEnterpriseUser(
            userInfo: userInfo,
            tenantId: tenantId
        )
        
        // 4. Assign role based on Okta group membership
        let managerRole = oktaRoles.first { $0.name == "Manager" }!
        let assignmentData = TestDataFactory.createRoleAssignmentData(
            userId: provisionedUser.id,
            roleId: managerRole.id,
            tenantId: tenantId
        )
        let roleAssignment = try await roleService.assignRoleToUser(assignmentData: assignmentData)
        
        // 5. Validate Okta-specific attributes
        let profile = try await userProfileService.getUserProfile(userId: provisionedUser.id)
        
        // Then
        XCTAssertEqual(configResult.provider, .okta)
        XCTAssertEqual(configResult.orgUrl, orgUrl)
        
        XCTAssertEqual(authResult.provider, .okta)
        XCTAssertEqual(authResult.orgUrl, orgUrl)
        
        XCTAssertEqual(provisionedUser.email, userInfo.email)
        XCTAssertEqual(provisionedUser.groups, oktaGroups)
        XCTAssertTrue(provisionedUser.attributes["okta_org"] as? String == orgUrl)
        
        XCTAssertEqual(roleAssignment.userId, provisionedUser.id)
        XCTAssertEqual(roleAssignment.roleId, managerRole.id)
        
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile.email, userInfo.email)
    }
    
    // MARK: - SAML Integration Tests
    
    func testSAMLEnterpriseIntegration_CompleteFlow() async throws {
        // Given
        let tenantId = "saml_enterprise_tenant"
        
        // SAML SSO Configuration
        let samlConfig = SSOConfiguration(
            id: "saml_sso_config",
            tenantId: tenantId,
            provider: .saml,
            clientId: "saml_entity_id",
            clientSecret: "saml_certificate",
            redirectUri: "https://golffinder.com/auth/saml/acs",
            additionalSettings: [
                "entity_id": "https://golffinder.com/saml/metadata",
                "sso_url": "https://enterprise-idp.com/saml/sso",
                "x509_certificate": "-----BEGIN CERTIFICATE-----\nMIIC...\n-----END CERTIFICATE-----",
                "name_id_format": "urn:oasis:names:tc:SAML:2.0:nameid-format:emailAddress",
                "signature_algorithm": "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
            ],
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // SAML response with attributes
        let samlResponse = """
        <saml2:Response xmlns:saml2="urn:oasis:names:tc:SAML:2.0:assertion">
            <saml2:Assertion>
                <saml2:Subject>
                    <saml2:NameID Format="urn:oasis:names:tc:SAML:2.0:nameid-format:emailAddress">
                        alice.johnson@enterprise.com
                    </saml2:NameID>
                </saml2:Subject>
                <saml2:AttributeStatement>
                    <saml2:Attribute Name="Department">
                        <saml2:AttributeValue>Finance</saml2:AttributeValue>
                    </saml2:Attribute>
                    <saml2:Attribute Name="Role">
                        <saml2:AttributeValue>Finance Manager</saml2:AttributeValue>
                    </saml2:Attribute>
                    <saml2:Attribute Name="Groups">
                        <saml2:AttributeValue>Finance,Managers,Full-Time</saml2:AttributeValue>
                    </saml2:Attribute>
                </saml2:AttributeStatement>
            </saml2:Assertion>
        </saml2:Response>
        """
        
        // Setup mocks
        mockAppwriteClient.mockSSOConfiguration = samlConfig
        mockAppwriteClient.mockEnterpriseAuthResult = TestDataFactory.createEnterpriseAuthResult()
        mockSecurityService.mockValidSAMLResponse = true
        mockSecurityService.mockSAMLAttributes = [
            "email": "alice.johnson@enterprise.com",
            "department": "Finance",
            "role": "Finance Manager",
            "groups": "Finance,Managers,Full-Time"
        ]
        
        // When - Execute SAML integration
        // 1. Configure SAML SSO
        let configResult = try await enterpriseAuthService.configureSSO(config: samlConfig)
        
        // 2. Authenticate with SAML response
        let authResult = try await enterpriseAuthService.authenticateWithSAML(
            tenantId: tenantId,
            samlResponse: samlResponse
        )
        
        // 3. Extract user information from SAML attributes
        let samlAttributes = mockSecurityService.mockSAMLAttributes!
        let userInfo = EnterpriseUserInfo(
            email: samlAttributes["email"] as! String,
            firstName: "Alice",
            lastName: "Johnson",
            department: samlAttributes["department"] as! String,
            jobTitle: samlAttributes["role"] as! String,
            roles: ["Finance Manager"],
            groups: (samlAttributes["groups"] as! String).components(separatedBy: ","),
            attributes: [
                "saml_name_id": "alice.johnson@enterprise.com",
                "saml_session_index": "session_123",
                "original_saml_attributes": samlAttributes
            ]
        )
        
        let provisionedUser = try await enterpriseAuthService.provisionEnterpriseUser(
            userInfo: userInfo,
            tenantId: tenantId
        )
        
        // 4. Create and assign finance manager role
        let financeRole = TestDataFactory.createRole(
            name: "Finance Manager",
            permissions: [.manageUsers, .readFinancialData, .approveExpenses]
        )
        
        let roleData = TestDataFactory.createRoleDataFromRole(financeRole)
        let createdRole = try await roleService.createRole(roleData: roleData)
        
        let assignmentData = TestDataFactory.createRoleAssignmentData(
            userId: provisionedUser.id,
            roleId: createdRole.id,
            tenantId: tenantId
        )
        let roleAssignment = try await roleService.assignRoleToUser(assignmentData: assignmentData)
        
        // 5. Validate SAML-specific session
        let deviceInfo = TestDataFactory.createDeviceInfo()
        let sessionResult = try await sessionManager.createSession(
            userId: provisionedUser.id,
            tenantId: tenantId,
            deviceInfo: deviceInfo
        )
        
        // Then
        XCTAssertEqual(configResult.provider, .saml)
        XCTAssertEqual(configResult.entityId, "https://golffinder.com/saml/metadata")
        
        XCTAssertEqual(authResult.provider, .saml)
        XCTAssertEqual(authResult.tenantId, tenantId)
        
        XCTAssertEqual(provisionedUser.email, "alice.johnson@enterprise.com")
        XCTAssertEqual(provisionedUser.department, "Finance")
        XCTAssertEqual(provisionedUser.jobTitle, "Finance Manager")
        XCTAssertTrue(provisionedUser.groups.contains("Finance"))
        XCTAssertTrue(provisionedUser.groups.contains("Managers"))
        
        XCTAssertEqual(createdRole.name, "Finance Manager")
        XCTAssertTrue(createdRole.permissions.contains(.manageUsers))
        
        XCTAssertEqual(roleAssignment.userId, provisionedUser.id)
        XCTAssertEqual(roleAssignment.roleId, createdRole.id)
        
        XCTAssertNotNil(sessionResult.accessToken)
        XCTAssertEqual(sessionResult.accessToken.userId, provisionedUser.id)
    }
    
    // MARK: - Directory Synchronization Tests
    
    func testDirectorySynchronization_LargeOrganization() async throws {
        // Given
        let tenantId = "large_org_tenant"
        let directoryConfig = DirectoryConfiguration(
            id: "directory_config",
            tenantId: tenantId,
            provider: .activeDirectory,
            connectionString: "ldap://ad.company.com:389",
            baseDN: "DC=company,DC=com",
            bindUser: "cn=service,ou=users,dc=company,dc=com",
            bindPassword: "service_password",
            userFilter: "(&(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))",
            groupFilter: "(objectClass=group)",
            syncSchedule: .daily,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Large set of directory users (simulating 1000+ employee organization)
        let directoryUsers = (1...1000).map { index in
            DirectoryUser(
                id: "user_\(index)",
                email: "employee\(index)@company.com",
                firstName: "Employee",
                lastName: "\(index)",
                department: ["Engineering", "Sales", "Marketing", "Finance", "HR"][index % 5],
                jobTitle: ["Developer", "Manager", "Director", "VP"][index % 4],
                groups: ["All Employees", "Department_\(["Engineering", "Sales", "Marketing", "Finance", "HR"][index % 5])"],
                attributes: [
                    "employee_id": "EMP\(String(format: "%04d", index))",
                    "office_location": ["New York", "San Francisco", "London", "Tokyo"][index % 4],
                    "cost_center": "CC\(index % 10)"
                ],
                isActive: true,
                lastModified: Date()
            )
        }
        
        // Setup mocks
        mockAppwriteClient.mockDirectoryConfig = directoryConfig
        mockAppwriteClient.mockDirectoryUsers = directoryUsers
        
        // Expected sync result
        let syncResult = DirectorySyncResult(
            totalUsers: 1000,
            usersCreated: 800, // 800 new users
            usersUpdated: 150, // 150 existing users updated
            usersDeactivated: 50, // 50 users no longer in directory
            groupsCreated: 25,
            groupsUpdated: 15,
            errors: [],
            startTime: Date(),
            endTime: Date().addingTimeInterval(300), // 5 minutes
            status: .completed
        )
        mockAppwriteClient.mockSyncResult = syncResult
        
        // When - Execute directory synchronization
        let result = try await enterpriseAuthService.synchronizeDirectory(tenantId: tenantId)
        
        // Validate sync statistics
        let syncStats = try await enterpriseAuthService.getDirectorySyncStatistics(tenantId: tenantId)
        
        // Then
        XCTAssertEqual(result.totalUsers, 1000)
        XCTAssertEqual(result.usersCreated, 800)
        XCTAssertEqual(result.usersUpdated, 150)
        XCTAssertEqual(result.usersDeactivated, 50)
        XCTAssertEqual(result.status, .completed)
        XCTAssertTrue(result.errors.isEmpty)
        
        XCTAssertNotNil(syncStats)
        XCTAssertEqual(syncStats.lastSyncTime, result.endTime)
        XCTAssertEqual(syncStats.totalUsers, 1000)
    }
    
    // MARK: - Enterprise Policy Enforcement Tests
    
    func testEnterpriseSecurityPolicies_Enforcement() async throws {
        // Given
        let tenantId = "security_policy_tenant"
        
        // Strong password policy
        let passwordPolicy = PasswordPolicy(
            minLength: 12,
            requireUppercase: true,
            requireLowercase: true,
            requireNumbers: true,
            requireSpecialCharacters: true,
            preventCommonPasswords: true,
            preventUserInfoInPassword: true,
            passwordHistory: 12,
            maxAge: 90
        )
        
        // Strict session policy
        let sessionPolicy = SessionPolicy(
            maxSessionDuration: 8 * 3600, // 8 hours
            inactivityTimeout: 30 * 60, // 30 minutes
            requireMFA: true,
            allowConcurrentSessions: false,
            restrictIPRange: ["192.168.1.0/24", "10.0.0.0/8"],
            requireDeviceRegistration: true
        )
        
        // Setup mocks
        mockAppwriteClient.mockPasswordPolicy = passwordPolicy
        mockAppwriteClient.mockSessionPolicy = sessionPolicy
        
        // Test cases
        let testCases = [
            (password: "weak", shouldPass: false, violations: [PasswordViolation.tooShort, .missingUppercase, .missingNumbers, .missingSpecialCharacters]),
            (password: "WeakPassword123", shouldPass: false, violations: [PasswordViolation.missingSpecialCharacters]),
            (password: "StrongP@ssw0rd123!", shouldPass: true, violations: [])
        ]
        
        // When & Then - Test password policy enforcement
        for testCase in testCases {
            mockSecurityService.mockPasswordCompliant = testCase.shouldPass
            mockSecurityService.mockPasswordViolations = testCase.violations
            
            let result = try await enterpriseAuthService.validatePasswordPolicy(
                password: testCase.password,
                tenantId: tenantId
            )
            
            XCTAssertEqual(result.isCompliant, testCase.shouldPass)
            XCTAssertEqual(result.violations.count, testCase.violations.count)
        }
        
        // Test session policy enforcement
        let sessionId = "test_session_id"
        let longSession = TestDataFactory.createSessionInfo(
            id: sessionId,
            createdAt: Date().addingTimeInterval(-10 * 3600) // 10 hours ago (exceeds 8 hour limit)
        )
        
        mockAppwriteClient.mockSessionInfo = longSession
        mockSecurityService.mockSessionCompliant = false
        mockSecurityService.mockSessionViolations = [.sessionExpired, .maxDurationExceeded]
        
        let sessionValidation = try await enterpriseAuthService.validateSessionPolicy(
            sessionId: sessionId,
            tenantId: tenantId
        )
        
        XCTAssertFalse(sessionValidation.isCompliant)
        XCTAssertTrue(sessionValidation.requiresTermination)
        XCTAssertEqual(sessionValidation.violations.count, 2)
    }
    
    // MARK: - Performance Tests
    
    func testEnterpriseAuthenticationPerformance() {
        measure {
            let expectation = XCTestExpectation(description: "Enterprise auth performance")
            
            Task {
                do {
                    // Simulate enterprise authentication flow
                    let tenantId = "perf_test_tenant"
                    
                    let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .azureAD, tenantId: tenantId)
                    _ = try await enterpriseAuthService.configureSSO(config: ssoConfig)
                    
                    let authResult = try await enterpriseAuthService.authenticateWithSSO(
                        provider: .azureAD,
                        tenantId: tenantId,
                        authorizationCode: "auth_code"
                    )
                    
                    let userInfo = TestDataFactory.createEnterpriseUserInfo()
                    _ = try await enterpriseAuthService.provisionEnterpriseUser(
                        userInfo: userInfo,
                        tenantId: tenantId
                    )
                } catch {
                    // Ignore errors for performance test
                }
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 3.0)
        }
    }
    
    func testConcurrentEnterpriseOperations() async {
        // Given
        let tenantCount = 5
        let tenantIds = (1...tenantCount).map { "tenant_\($0)" }
        
        // When
        await withTaskGroup(of: Bool.self) { group in
            for tenantId in tenantIds {
                group.addTask {
                    do {
                        // Concurrent enterprise operations
                        let ssoConfig = TestDataFactory.createSSOConfiguration(provider: .azureAD, tenantId: tenantId)
                        _ = try await self.enterpriseAuthService.configureSSO(config: ssoConfig)
                        
                        let authResult = try await self.enterpriseAuthService.authenticateWithSSO(
                            provider: .azureAD,
                            tenantId: tenantId,
                            authorizationCode: "auth_code_\(tenantId)"
                        )
                        
                        let userInfo = TestDataFactory.createEnterpriseUserInfo(email: "user@\(tenantId).com")
                        _ = try await self.enterpriseAuthService.provisionEnterpriseUser(
                            userInfo: userInfo,
                            tenantId: tenantId
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
            XCTAssertEqual(results.count, tenantCount)
            let successCount = results.filter { $0 }.count
            XCTAssertGreaterThan(successCount, tenantCount * 80 / 100) // At least 80% success rate
        }
    }
}