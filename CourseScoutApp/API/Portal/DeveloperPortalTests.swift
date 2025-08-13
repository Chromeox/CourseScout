import Foundation
import XCTest
import Appwrite
@testable import GolfFinderApp

// MARK: - Developer Portal Testing Infrastructure

@MainActor
class DeveloperPortalTestSuite: XCTestCase {
    
    // MARK: - Test Properties
    
    private var mockAppwriteClient: Client!
    private var developerAuthService: DeveloperAuthService!
    private var apiKeyManagementService: APIKeyManagementService!
    private var documentationService: DocumentationGeneratorService!
    private var sdkGeneratorService: SDKGeneratorService!
    private var testServiceContainer: ServiceContainer!
    
    // MARK: - Test Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize test environment
        mockAppwriteClient = Client()
            .setEndpoint("https://test.appwrite.io/v1")
            .setProject("test-project")
            .setSelfSigned()
        
        // Initialize services for testing
        developerAuthService = DeveloperAuthService(appwriteClient: mockAppwriteClient)
        
        let authMiddleware = AuthenticationMiddleware(appwriteClient: mockAppwriteClient)
        apiKeyManagementService = APIKeyManagementService(
            appwriteClient: mockAppwriteClient,
            authService: authMiddleware
        )
        
        documentationService = DocumentationGeneratorService(appwriteClient: mockAppwriteClient)
        sdkGeneratorService = SDKGeneratorService(appwriteClient: mockAppwriteClient)
        
        // Initialize test service container
        testServiceContainer = ServiceContainer(
            appwriteClient: mockAppwriteClient,
            environment: .test
        )
    }
    
    override func tearDown() async throws {
        developerAuthService = nil
        apiKeyManagementService = nil
        documentationService = nil
        sdkGeneratorService = nil
        testServiceContainer = nil
        mockAppwriteClient = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Developer Authentication Tests
    
    func testDeveloperRegistration() async throws {
        // Given
        let registration = DeveloperRegistration(
            email: "test@developer.com",
            password: "SecurePassword123!",
            name: "Test Developer",
            company: "Test Company"
        )
        
        // When
        let result = try await developerAuthService.registerDeveloper(registration)
        
        // Then
        XCTAssertEqual(result.email, registration.email)
        XCTAssertEqual(result.name, registration.name)
        XCTAssertEqual(result.company, registration.company)
        XCTAssertFalse(result.isEmailVerified)
        XCTAssertEqual(result.tier, .free)
    }
    
    func testDeveloperAuthentication() async throws {
        // Given
        let email = "test@developer.com"
        let password = "SecurePassword123!"
        
        // When
        let session = try await developerAuthService.authenticateDeveloper(
            email: email,
            password: password
        )
        
        // Then
        XCTAssertEqual(session.email, email)
        XCTAssertNotNil(session.accessToken)
        XCTAssertNotNil(session.refreshToken)
        XCTAssertTrue(session.expiresAt > Date())
    }
    
    func testInvalidEmailRegistration() async throws {
        // Given
        let registration = DeveloperRegistration(
            email: "invalid-email",
            password: "SecurePassword123!",
            name: "Test Developer",
            company: nil
        )
        
        // When & Then
        do {
            _ = try await developerAuthService.registerDeveloper(registration)
            XCTFail("Should have thrown invalid email error")
        } catch DeveloperAuthError.invalidEmail {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testWeakPasswordRegistration() async throws {
        // Given
        let registration = DeveloperRegistration(
            email: "test@developer.com",
            password: "weak",
            name: "Test Developer",
            company: nil
        )
        
        // When & Then
        do {
            _ = try await developerAuthService.registerDeveloper(registration)
            XCTFail("Should have thrown weak password error")
        } catch DeveloperAuthError.passwordTooWeak {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSessionRefresh() async throws {
        // Given
        let refreshToken = "valid_refresh_token"
        
        // When
        let newSession = try await developerAuthService.refreshSession(refreshToken)
        
        // Then
        XCTAssertNotNil(newSession.accessToken)
        XCTAssertNotNil(newSession.refreshToken)
        XCTAssertTrue(newSession.expiresAt > Date())
    }
    
    // MARK: - API Key Management Tests
    
    func testAPIKeyGeneration() async throws {
        // Given
        let userId = "test_user_123"
        let tier = APITier.premium
        let name = "Test API Key"
        let description = "Test key for unit testing"
        
        // When
        let apiKey = try await apiKeyManagementService.generateAPIKey(
            for: userId,
            tier: tier,
            name: name,
            description: description
        )
        
        // Then
        XCTAssertEqual(apiKey.tier, tier)
        XCTAssertEqual(apiKey.name, name)
        XCTAssertEqual(apiKey.description, description)
        XCTAssertTrue(apiKey.isActive)
        XCTAssertNotNil(apiKey.fullKey) // Should be present during creation
        XCTAssertEqual(apiKey.usageCount, 0)
        XCTAssertEqual(apiKey.currentMonthUsage, 0)
    }
    
    func testAPIKeyValidation() async throws {
        // Given
        let apiKey = "prem_abc123defghijklmnopqrstuvwxyz456"
        
        // When
        let validation = try await apiKeyManagementService.validateAPIKey(apiKey)
        
        // Then
        XCTAssertTrue(validation.isValid)
        XCTAssertNotNil(validation.keyId)
        XCTAssertNotNil(validation.userId)
        XCTAssertEqual(validation.tier, .premium)
    }
    
    func testAPIKeyRegeneration() async throws {
        // Given
        let keyId = "test_key_123"
        let userId = "test_user_123"
        
        // When
        let newKey = try await apiKeyManagementService.regenerateAPIKey(keyId, userId: userId)
        
        // Then
        XCTAssertEqual(newKey.id, keyId)
        XCTAssertNotNil(newKey.fullKey) // New key should be present
        XCTAssertEqual(newKey.usageCount, 0) // Usage should be reset
        XCTAssertEqual(newKey.currentMonthUsage, 0)
    }
    
    func testAPIKeyTierUpgrade() async throws {
        // Given
        let keyId = "test_key_123"
        let userId = "test_user_123"
        let newTier = APITier.enterprise
        
        // When
        let upgradedKey = try await apiKeyManagementService.upgradeTier(
            keyId,
            userId: userId,
            newTier: newTier
        )
        
        // Then
        XCTAssertEqual(upgradedKey.tier, newTier)
        XCTAssertEqual(upgradedKey.monthlyQuota, newTier.dailyRequestLimit * 30)
    }
    
    func testAPIKeyRevocation() async throws {
        // Given
        let keyId = "test_key_123"
        let userId = "test_user_123"
        
        // When & Then
        try await apiKeyManagementService.revokeAPIKey(keyId, userId: userId)
        
        // Verify key is revoked by trying to validate it
        do {
            let validation = try await apiKeyManagementService.validateAPIKey("revoked_key")
            XCTAssertFalse(validation.isValid)
        } catch {
            // Expected - revoked key should fail validation
        }
    }
    
    func testAPIKeyUsageTracking() async throws {
        // Given
        let keyId = "test_key_123"
        let userId = "test_user_123"
        let period = UsagePeriod.currentMonth
        
        // When
        let usage = try await apiKeyManagementService.getAPIKeyUsage(
            keyId,
            userId: userId,
            period: period
        )
        
        // Then
        XCTAssertEqual(usage.period, period)
        XCTAssertGreaterThanOrEqual(usage.totalRequests, 0)
        XCTAssertGreaterThanOrEqual(usage.successfulRequests, 0)
        XCTAssertGreaterThanOrEqual(usage.failedRequests, 0)
        XCTAssertGreaterThanOrEqual(usage.successRate, 0.0)
        XCTAssertLessThanOrEqual(usage.successRate, 1.0)
    }
    
    // MARK: - API Tier Validation Tests
    
    func testAPITierPriorityOrdering() {
        // Given & When
        let tiers: [APITier] = [.business, .free, .enterprise, .premium]
        let sortedTiers = tiers.sorted { $0.priority < $1.priority }
        
        // Then
        XCTAssertEqual(sortedTiers, [.free, .premium, .enterprise, .business])
    }
    
    func testAPITierLimits() {
        // Given
        let freeTier = APITier.free
        let premiumTier = APITier.premium
        let enterpriseTier = APITier.enterprise
        let businessTier = APITier.business
        
        // When & Then
        XCTAssertEqual(freeTier.dailyRequestLimit, 1000)
        XCTAssertEqual(premiumTier.dailyRequestLimit, 10000)
        XCTAssertEqual(enterpriseTier.dailyRequestLimit, 100000)
        XCTAssertEqual(businessTier.dailyRequestLimit, -1) // Unlimited
        
        XCTAssertEqual(freeTier.maxAPIKeys, 2)
        XCTAssertEqual(premiumTier.maxAPIKeys, 5)
        XCTAssertEqual(enterpriseTier.maxAPIKeys, 20)
        XCTAssertEqual(businessTier.maxAPIKeys, 50)
    }
    
    // MARK: - Documentation Generation Tests
    
    func testOpenAPISpecGeneration() async throws {
        // Given
        let version = APIVersion.v2
        let tier = APITier.premium
        
        // When
        let spec = try await documentationService.generateOpenAPISpec(
            version: version,
            tier: tier
        )
        
        // Then
        XCTAssertEqual(spec.openapi, "3.0.3")
        XCTAssertEqual(spec.info.title, "GolfFinder API")
        XCTAssertEqual(spec.info.version, version.rawValue)
        XCTAssertFalse(spec.paths.isEmpty)
        XCTAssertFalse(spec.servers.isEmpty)
    }
    
    func testSwaggerUIGeneration() async throws {
        // Given
        let spec = OpenAPISpecification(
            openapi: "3.0.3",
            info: OpenAPIInfo(
                title: "Test API",
                description: "Test description",
                version: "1.0.0",
                termsOfService: nil,
                contact: nil,
                license: nil
            ),
            servers: [],
            paths: [:],
            components: OpenAPIComponents(securitySchemes: [:], schemas: [:]),
            security: [],
            tags: []
        )
        
        // When
        let swaggerHTML = try await documentationService.generateSwaggerUI(for: spec)
        
        // Then
        XCTAssertTrue(swaggerHTML.contains("<!DOCTYPE html>"))
        XCTAssertTrue(swaggerHTML.contains("swagger-ui"))
        XCTAssertTrue(swaggerHTML.contains("Test API"))
    }
    
    func testPostmanCollectionGeneration() async throws {
        // Given
        let version = APIVersion.v1
        let tier = APITier.premium
        
        // When
        let collection = try await documentationService.generatePostmanCollection(
            version: version,
            tier: tier
        )
        
        // Then
        XCTAssertEqual(collection.info.name, "GolfFinder API \(version.rawValue)")
        XCTAssertFalse(collection.item.isEmpty)
        XCTAssertNotNil(collection.variable)
    }
    
    func testCodeExampleGeneration() async throws {
        // Given
        let endpoint = APIEndpoint(
            path: "/courses",
            method: .GET,
            version: .v1,
            requiredTier: .free,
            handler: { _ in return "" }
        )
        let languages: [ProgrammingLanguage] = [.swift, .javascript, .python]
        
        // When
        let examples = try await documentationService.generateCodeExamples(
            for: endpoint,
            languages: languages
        )
        
        // Then
        XCTAssertEqual(examples.count, languages.count)
        for example in examples {
            XCTAssertTrue(languages.contains(example.language))
            XCTAssertFalse(example.code.isEmpty)
            XCTAssertFalse(example.response.isEmpty)
        }
    }
    
    // MARK: - SDK Generation Tests
    
    func testSwiftSDKGeneration() async throws {
        // Given
        let version = APIVersion.v2
        let endpoints = [
            APIEndpoint(
                path: "/courses",
                method: .GET,
                version: version,
                requiredTier: .free,
                handler: { _ in return "" }
            )
        ]
        
        // When
        let sdkResult = try await sdkGeneratorService.generateSwiftSDK(
            version: version,
            endpoints: endpoints
        )
        
        // Then
        XCTAssertEqual(sdkResult.language, .swift)
        XCTAssertEqual(sdkResult.version, version.rawValue)
        XCTAssertFalse(sdkResult.files.isEmpty)
        XCTAssertNotNil(sdkResult.checksum)
        
        // Verify specific files exist
        let filePaths = sdkResult.files.map { $0.path }
        XCTAssertTrue(filePaths.contains("Sources/GolfFinderSDK/GolfFinderClient.swift"))
        XCTAssertTrue(filePaths.contains("Package.swift"))
    }
    
    func testJavaScriptSDKGeneration() async throws {
        // Given
        let version = APIVersion.v1
        let endpoints = [
            APIEndpoint(
                path: "/courses/search",
                method: .POST,
                version: version,
                requiredTier: .premium,
                handler: { _ in return "" }
            )
        ]
        
        // When
        let sdkResult = try await sdkGeneratorService.generateJavaScriptSDK(
            version: version,
            endpoints: endpoints
        )
        
        // Then
        XCTAssertEqual(sdkResult.language, .javascript)
        XCTAssertEqual(sdkResult.version, version.rawValue)
        XCTAssertFalse(sdkResult.files.isEmpty)
        
        // Verify package.json exists
        let filePaths = sdkResult.files.map { $0.path }
        XCTAssertTrue(filePaths.contains("package.json"))
        XCTAssertTrue(filePaths.contains("src/index.js"))
    }
    
    func testPythonSDKGeneration() async throws {
        // Given
        let version = APIVersion.v2
        let endpoints = [
            APIEndpoint(
                path: "/analytics",
                method: .GET,
                version: version,
                requiredTier: .enterprise,
                handler: { _ in return "" }
            )
        ]
        
        // When
        let sdkResult = try await sdkGeneratorService.generatePythonSDK(
            version: version,
            endpoints: endpoints
        )
        
        // Then
        XCTAssertEqual(sdkResult.language, .python)
        XCTAssertEqual(sdkResult.version, version.rawValue)
        
        // Verify Python-specific files
        let filePaths = sdkResult.files.map { $0.path }
        XCTAssertTrue(filePaths.contains("setup.py"))
        XCTAssertTrue(filePaths.contains("golffinder_sdk/__init__.py"))
        XCTAssertTrue(filePaths.contains("golffinder_sdk/client.py"))
    }
    
    func testSDKConfigurationValidation() async throws {
        // Given
        let validConfig = SDKConfiguration(
            baseURL: "https://api.golffinder.com",
            packageName: "golffinder-sdk",
            version: "1.0.0",
            author: "GolfFinder Team",
            license: "MIT",
            description: "Official SDK for the GolfFinder API"
        )
        
        let invalidConfig = SDKConfiguration(
            baseURL: "invalid-url",
            packageName: "",
            version: "invalid-version",
            author: "",
            license: "MIT",
            description: "Short"
        )
        
        // When
        let validResult = try await sdkGeneratorService.validateSDKConfiguration(validConfig)
        let invalidResult = try await sdkGeneratorService.validateSDKConfiguration(invalidConfig)
        
        // Then
        XCTAssertTrue(validResult.isValid)
        XCTAssertTrue(validResult.errors.isEmpty)
        
        XCTAssertFalse(invalidResult.isValid)
        XCTAssertFalse(invalidResult.errors.isEmpty)
        XCTAssertTrue(invalidResult.errors.contains { $0.contains("Package name") })
        XCTAssertTrue(invalidResult.errors.contains { $0.contains("version format") })
    }
    
    // MARK: - Service Integration Tests
    
    func testServiceContainerRegistration() async throws {
        // Given
        let container = testServiceContainer
        
        // When & Then
        let developerAuthService = container.resolve(DeveloperAuthServiceProtocol.self)
        XCTAssertNotNil(developerAuthService)
        
        let apiKeyManagementService = container.resolve(APIKeyManagementServiceProtocol.self)
        XCTAssertNotNil(apiKeyManagementService)
        
        let documentationService = container.resolve(DocumentationGeneratorServiceProtocol.self)
        XCTAssertNotNil(documentationService)
        
        let sdkGeneratorService = container.resolve(SDKGeneratorServiceProtocol.self)
        XCTAssertNotNil(sdkGeneratorService)
    }
    
    func testServiceContainerConvenienceMethods() async throws {
        // Given
        let container = testServiceContainer
        
        // When & Then
        let developerAuthService = container.developerAuthService()
        XCTAssertNotNil(developerAuthService)
        
        let apiKeyManagementService = container.apiKeyManagementService()
        XCTAssertNotNil(apiKeyManagementService)
        
        let documentationService = container.documentationGeneratorService()
        XCTAssertNotNil(documentationService)
        
        let sdkGeneratorService = container.sdkGeneratorService()
        XCTAssertNotNil(sdkGeneratorService)
    }
    
    // MARK: - Error Handling Tests
    
    func testDeveloperPortalErrorHandling() async throws {
        // Test various error scenarios
        let errors: [DeveloperPortalError] = [
            .invalidDeveloperId,
            .developerNotFound,
            .emailNotVerified,
            .accountSuspended,
            .tierLimitExceeded,
            .quotaExceeded,
            .rateLimitExceeded,
            .invalidAPIKey,
            .apiKeyExpired
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorCode.isEmpty)
            XCTAssertTrue(error.httpStatusCode >= 400)
            XCTAssertTrue(error.httpStatusCode < 600)
        }
    }
    
    // MARK: - Performance Tests
    
    func testAPIKeyGenerationPerformance() async throws {
        // Given
        let userId = "test_user_123"
        let tier = APITier.premium
        
        // When
        measure {
            Task {
                do {
                    _ = try await apiKeyManagementService.generateAPIKey(
                        for: userId,
                        tier: tier,
                        name: "Performance Test Key",
                        description: "Testing key generation performance"
                    )
                } catch {
                    XCTFail("Key generation failed: \(error)")
                }
            }
        }
    }
    
    func testDocumentationGenerationPerformance() async throws {
        // Given
        let version = APIVersion.v2
        let tier = APITier.premium
        
        // When
        measure {
            Task {
                do {
                    _ = try await documentationService.generateOpenAPISpec(
                        version: version,
                        tier: tier
                    )
                } catch {
                    XCTFail("Documentation generation failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Mock Data Validation Tests
    
    func testMockDataConsistency() async throws {
        // Test that mock services return consistent data
        let mockAuth = MockDeveloperAuthService()
        let mockAPIKey = MockAPIKeyManagementService()
        let mockDocs = MockDocumentationGeneratorService()
        let mockSDK = MockSDKGeneratorService()
        
        // Developer auth consistency
        let registration = DeveloperRegistration(
            email: "test@example.com",
            password: "password",
            name: "Test",
            company: nil
        )
        let developer = try await mockAuth.registerDeveloper(registration)
        XCTAssertNotNil(developer.id)
        XCTAssertEqual(developer.email, registration.email)
        
        // API key consistency
        let apiKey = try await mockAPIKey.generateAPIKey(
            for: developer.id,
            tier: .premium,
            name: "Test Key",
            description: "Test"
        )
        XCTAssertNotNil(apiKey.fullKey)
        XCTAssertEqual(apiKey.tier, .premium)
        
        // Documentation consistency
        let spec = try await mockDocs.generateOpenAPISpec(version: .v1, tier: .premium)
        XCTAssertEqual(spec.info.title, "GolfFinder API (Mock)")
        
        // SDK consistency
        let swiftSDK = try await mockSDK.generateSwiftSDK(version: .v1, endpoints: [])
        XCTAssertEqual(swiftSDK.language, .swift)
        XCTAssertFalse(swiftSDK.files.isEmpty)
    }
    
    // MARK: - Integration Flow Tests
    
    func testCompleteIntegrationFlow() async throws {
        // Test a complete flow from developer registration to API usage
        
        // 1. Register developer
        let registration = DeveloperRegistration(
            email: "integration@test.com",
            password: "SecurePassword123!",
            name: "Integration Test Developer",
            company: "Test Company"
        )
        let developer = try await developerAuthService.registerDeveloper(registration)
        
        // 2. Authenticate developer
        let session = try await developerAuthService.authenticateDeveloper(
            email: registration.email,
            password: registration.password
        )
        
        // 3. Generate API key
        let apiKey = try await apiKeyManagementService.generateAPIKey(
            for: developer.id,
            tier: .premium,
            name: "Integration Test Key",
            description: "Key for integration testing"
        )
        
        // 4. Validate API key
        let validation = try await apiKeyManagementService.validateAPIKey(apiKey.fullKey!)
        XCTAssertTrue(validation.isValid)
        
        // 5. Generate documentation
        let spec = try await documentationService.generateOpenAPISpec(version: .v2, tier: .premium)
        XCTAssertFalse(spec.paths.isEmpty)
        
        // 6. Generate SDK
        let endpoints = [
            APIEndpoint(
                path: "/courses",
                method: .GET,
                version: .v2,
                requiredTier: .premium,
                handler: { _ in return "" }
            )
        ]
        let sdkResult = try await sdkGeneratorService.generateSwiftSDK(version: .v2, endpoints: endpoints)
        XCTAssertFalse(sdkResult.files.isEmpty)
        
        // Verify the complete flow worked
        XCTAssertEqual(developer.email, registration.email)
        XCTAssertEqual(session.email, registration.email)
        XCTAssertEqual(apiKey.tier, .premium)
        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(spec.info.version, "v2")
        XCTAssertEqual(sdkResult.language, .swift)
    }
}

// MARK: - Test Extensions

extension XCTestCase {
    
    /// Helper method to create test developer account
    func createTestDeveloper() -> DeveloperAccount {
        return DeveloperAccount(
            id: "test_dev_\(UUID().uuidString)",
            email: "test@developer.com",
            name: "Test Developer",
            company: "Test Company",
            isEmailVerified: true,
            tier: .premium,
            createdAt: Date(),
            profile: DeveloperProfile(
                id: "profile_\(UUID().uuidString)",
                userId: "test_dev_\(UUID().uuidString)",
                email: "test@developer.com",
                name: "Test Developer",
                company: "Test Company",
                tier: .premium,
                twoFactorEnabled: false,
                totpSecret: nil,
                totpSecretPending: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }
    
    /// Helper method to create test API key
    func createTestAPIKey(tier: APITier = .premium) -> APIKeyInfo {
        return APIKeyInfo(
            id: "key_\(UUID().uuidString)",
            keyPrefix: "\(tier.rawValue.prefix(4))_abc...",
            fullKey: "\(tier.rawValue.prefix(4))_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
            tier: tier,
            name: "Test API Key",
            description: "Key for testing",
            isActive: true,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 365),
            lastUsedAt: nil,
            usageCount: 0,
            monthlyQuota: tier.dailyRequestLimit * 30,
            currentMonthUsage: 0,
            monitoringEnabled: tier != .free
        )
    }
}

// MARK: - Test Data Generators

struct TestDataGenerator {
    
    static func generateTestEndpoints(count: Int = 5) -> [APIEndpoint] {
        let paths = ["/courses", "/courses/search", "/analytics", "/predictions", "/booking"]
        let methods: [HTTPMethod] = [.GET, .POST, .PUT, .DELETE]
        let tiers: [APITier] = [.free, .premium, .enterprise, .business]
        
        return (0..<count).map { index in
            APIEndpoint(
                path: paths[index % paths.count],
                method: methods[index % methods.count],
                version: .v2,
                requiredTier: tiers[index % tiers.count],
                handler: { _ in return "test_response" },
                description: "Test endpoint \(index)"
            )
        }
    }
    
    static func generateTestDeveloperRegistrations(count: Int = 3) -> [DeveloperRegistration] {
        return (0..<count).map { index in
            DeveloperRegistration(
                email: "test\(index)@developer.com",
                password: "SecurePassword123!",
                name: "Test Developer \(index)",
                company: index % 2 == 0 ? "Test Company \(index)" : nil
            )
        }
    }
    
    static func generateTestCodeExamples(languages: [ProgrammingLanguage]) -> [CodeExample] {
        return languages.map { language in
            CodeExample(
                language: language,
                title: "Example for \(language.displayName)",
                description: "Test code example",
                code: "// Test code for \(language.displayName)",
                response: """
                {
                  "data": "test_response",
                  "status": "success"
                }
                """
            )
        }
    }
}