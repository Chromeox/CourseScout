import XCTest
import Appwrite
import Combine
@testable import GolfFinderSwiftUI

class APIGatewayServiceTests: XCTestCase {
    
    var sut: APIGatewayService!
    var mockAppwriteClient: Client!
    var testContainer: ServiceContainer!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        super.setUp()
        
        // Set up test environment
        TestEnvironmentManager.shared.setupTestEnvironment()
        
        // Create mock Appwrite client
        mockAppwriteClient = Client()
            .setEndpoint("https://test-appwrite.local/v1")
            .setProject("test-project-id")
            .setKey("test-api-key")
        
        // Create test service container
        testContainer = ServiceContainer(appwriteClient: mockAppwriteClient, environment: .test)
        
        // Initialize system under test
        sut = APIGatewayService(appwriteClient: mockAppwriteClient)
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithError() throws {
        sut = nil
        mockAppwriteClient = nil
        testContainer = nil
        cancellables = nil
        
        TestEnvironmentManager.shared.teardownTestEnvironment()
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testAPIGatewayService_WhenInitialized_ShouldSetupDefaultConfiguration() throws {
        // Given & When (setup in setUp)
        
        // Then
        XCTAssertNotNil(sut)
        XCTAssertTrue(sut.isHealthy)
        XCTAssertEqual(sut.activeConnections, 0)
        XCTAssertEqual(sut.requestsPerSecond, 0.0)
    }
    
    // MARK: - API Key Validation Tests
    
    func testValidateAPIKey_WithValidKey_ShouldReturnValidResult() async throws {
        // Given
        let validAPIKey = TestDataFactory.shared.createMockAPIKeyValidationResult(isValid: true, tier: .business)
        
        // When
        let result = try await sut.validateAPIKey(validAPIKey.apiKey)
        
        // Then
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.tier, .business)
        XCTAssertNotNil(result.userId)
        XCTAssertNotNil(result.expiresAt)
    }
    
    func testValidateAPIKey_WithInvalidKey_ShouldThrowError() async throws {
        // Given
        let invalidAPIKey = "invalid-key-12345"
        
        // When & Then
        do {
            _ = try await sut.validateAPIKey(invalidAPIKey)
            XCTFail("Expected APIGatewayError.invalidAPIKey to be thrown")
        } catch APIGatewayError.invalidAPIKey {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Request Processing Tests
    
    func testProcessRequest_WithValidRequest_ShouldReturnSuccessResponse() async throws {
        // Given
        let request = TestDataFactory.shared.createMockAPIGatewayRequest(
            path: "/courses",
            method: .GET
        )
        
        // When
        let response = try await sut.processRequest(request, responseType: [String: Any].self)
        
        // Then
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNotNil(response.data)
        XCTAssertEqual(response.requestId, request.requestId)
        XCTAssertGreaterThan(response.processingTimeMs, 0)
        XCTAssertNil(response.error)
    }
    
    func testProcessRequest_WithInvalidEndpoint_ShouldThrowEndpointNotFoundError() async throws {
        // Given
        let request = TestDataFactory.shared.createMockAPIGatewayRequest(
            path: "/invalid-endpoint",
            method: .GET
        )
        
        // When & Then
        do {
            _ = try await sut.processRequest(request, responseType: [String: Any].self)
            XCTFail("Expected APIGatewayError.endpointNotFound to be thrown")
        } catch APIGatewayError.endpointNotFound(let path) {
            XCTAssertEqual(path, "/invalid-endpoint")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testProcessRequest_WithRateLimitExceeded_ShouldThrowRateLimitError() async throws {
        // Given
        let request = TestDataFactory.shared.createMockAPIGatewayRequest()
        let endpoint = APIEndpoint(
            path: "/courses",
            method: .GET,
            version: .v1,
            requiredTier: .free,
            handler: { _ in return "test" }
        )
        
        // Simulate rate limit exceeded by making multiple rapid requests
        for _ in 0..<100 {
            try? await sut.checkRateLimit(for: request.apiKey, endpoint: endpoint)
        }
        
        // When & Then
        do {
            _ = try await sut.processRequest(request, responseType: [String: Any].self)
            XCTFail("Expected APIGatewayError.rateLimitExceeded to be thrown")
        } catch APIGatewayError.rateLimitExceeded(let limit, let windowMs, let resetTime) {
            XCTAssertGreaterThan(limit, 0)
            XCTAssertGreaterThan(windowMs, 0)
            XCTAssertGreaterThan(resetTime.timeIntervalSinceNow, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Endpoint Management Tests
    
    func testRegisterEndpoint_ShouldAddEndpointToRegistry() {
        // Given
        let endpoint = APIEndpoint(
            path: "/test",
            method: .POST,
            version: .v2,
            requiredTier: .premium,
            handler: { _ in return "test response" }
        )
        
        // When
        sut.registerEndpoint(endpoint)
        
        // Then
        let retrievedEndpoint = sut.getEndpoint(path: "/test", version: .v2)
        XCTAssertNotNil(retrievedEndpoint)
        XCTAssertEqual(retrievedEndpoint?.path, "/test")
        XCTAssertEqual(retrievedEndpoint?.method, .POST)
        XCTAssertEqual(retrievedEndpoint?.version, .v2)
        XCTAssertEqual(retrievedEndpoint?.requiredTier, .premium)
    }
    
    func testListAvailableEndpoints_ForFreeTier_ShouldReturnOnlyFreeEndpoints() {
        // Given
        let freeEndpoint = APIEndpoint(path: "/free", method: .GET, version: .v1, requiredTier: .free) { _ in return "free" }
        let premiumEndpoint = APIEndpoint(path: "/premium", method: .GET, version: .v1, requiredTier: .premium) { _ in return "premium" }
        
        sut.registerEndpoint(freeEndpoint)
        sut.registerEndpoint(premiumEndpoint)
        
        // When
        let availableEndpoints = sut.listAvailableEndpoints(for: .free)
        
        // Then
        XCTAssertTrue(availableEndpoints.contains { $0.path == "/free" })
        XCTAssertFalse(availableEndpoints.contains { $0.path == "/premium" })
    }
    
    func testListAvailableEndpoints_ForBusinessTier_ShouldReturnAllEndpoints() {
        // Given
        let freeEndpoint = APIEndpoint(path: "/free", method: .GET, version: .v1, requiredTier: .free) { _ in return "free" }
        let premiumEndpoint = APIEndpoint(path: "/premium", method: .GET, version: .v1, requiredTier: .premium) { _ in return "premium" }
        let businessEndpoint = APIEndpoint(path: "/business", method: .GET, version: .v1, requiredTier: .business) { _ in return "business" }
        
        sut.registerEndpoint(freeEndpoint)
        sut.registerEndpoint(premiumEndpoint)
        sut.registerEndpoint(businessEndpoint)
        
        // When
        let availableEndpoints = sut.listAvailableEndpoints(for: .business)
        
        // Then
        XCTAssertEqual(availableEndpoints.count, 3)
        XCTAssertTrue(availableEndpoints.contains { $0.path == "/free" })
        XCTAssertTrue(availableEndpoints.contains { $0.path == "/premium" })
        XCTAssertTrue(availableEndpoints.contains { $0.path == "/business" })
    }
    
    // MARK: - Health Check Tests
    
    func testHealthCheck_WithHealthySystem_ShouldReturnHealthyStatus() async throws {
        // When
        let healthStatus = await sut.healthCheck()
        
        // Then
        XCTAssertTrue(healthStatus.isHealthy)
        XCTAssertTrue(healthStatus.appwriteConnected)
        XCTAssertLessThan(healthStatus.memoryUsagePercent, 100.0)
        XCTAssertGreaterThanOrEqual(healthStatus.averageResponseTimeMs, 0)
        XCTAssertGreaterThanOrEqual(healthStatus.activeConnections, 0)
        XCTAssertNotNil(healthStatus.timestamp)
    }
    
    // MARK: - Metrics Tests
    
    func testGetMetrics_ShouldReturnCurrentMetrics() async throws {
        // Given
        let request = TestDataFactory.shared.createMockAPIGatewayRequest()
        
        // Process a few requests to generate metrics
        for _ in 0..<5 {
            try? await sut.processRequest(request, responseType: [String: Any].self)
        }
        
        // When
        let metrics = await sut.getMetrics(for: .hour)
        
        // Then
        XCTAssertGreaterThan(metrics.totalRequests, 0)
        XCTAssertGreaterThanOrEqual(metrics.successfulRequests, 0)
        XCTAssertGreaterThanOrEqual(metrics.failedRequests, 0)
        XCTAssertGreaterThanOrEqual(metrics.averageProcessingTimeMs, 0)
    }
    
    // MARK: - Performance Tests
    
    func testProcessRequest_PerformanceUnder200ms() async throws {
        // Given
        let request = TestDataFactory.shared.createMockAPIGatewayRequest()
        
        // When
        let startTime = Date()
        let response = try await sut.processRequest(request, responseType: [String: Any].self)
        let processingTime = Date().timeIntervalSince(startTime) * 1000
        
        // Then
        XCTAssertLessThan(processingTime, 200.0, "API Gateway should process requests under 200ms")
        XCTAssertLessThan(response.processingTimeMs, 200.0, "Response processing time should be under 200ms")
    }
    
    func testConcurrentRequests_ShouldHandleMultipleRequestsSimultaneously() async throws {
        // Given
        let requestCount = 50
        let requests = (0..<requestCount).map { index in
            TestDataFactory.shared.createMockAPIGatewayRequest(
                path: "/courses",
                method: .GET,
                apiKey: "test-key-\(index)"
            )
        }
        
        // When
        let startTime = Date()
        let responses = await withTaskGroup(of: (Int, Result<APIGatewayResponse<[String: Any]>, Error>).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask {
                    do {
                        let response = try await self.sut.processRequest(request, responseType: [String: Any].self)
                        return (index, .success(response))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            
            var results: [(Int, Result<APIGatewayResponse<[String: Any]>, Error>)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        let totalTime = Date().timeIntervalSince(startTime) * 1000
        
        // Then
        XCTAssertEqual(responses.count, requestCount)
        XCTAssertLessThan(totalTime, 5000.0, "50 concurrent requests should complete within 5 seconds")
        
        let successCount = responses.filter { 
            if case .success = $0.1 { return true }
            return false
        }.count
        
        XCTAssertGreaterThanOrEqual(successCount, requestCount * 95 / 100, "At least 95% of concurrent requests should succeed")
    }
    
    // MARK: - Error Handling Tests
    
    func testProcessRequest_WithNetworkError_ShouldHandleGracefully() async throws {
        // Given
        let request = TestDataFactory.shared.createMockAPIGatewayRequest(path: "/error-endpoint")
        
        // When & Then
        do {
            _ = try await sut.processRequest(request, responseType: [String: Any].self)
            XCTFail("Expected error to be thrown")
        } catch {
            // Error should be handled gracefully
            XCTAssertTrue(error is APIGatewayError)
        }
    }
    
    // MARK: - Memory Tests
    
    func testAPIGatewayService_MemoryUsage_ShouldStayUnder500MB() async throws {
        // Given
        let initialMemory = getCurrentMemoryUsage()
        
        // When - Process many requests
        for i in 0..<1000 {
            let request = TestDataFactory.shared.createMockAPIGatewayRequest(apiKey: "test-key-\(i)")
            try? await sut.processRequest(request, responseType: [String: Any].self)
        }
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Then
        XCTAssertLessThan(memoryIncrease, 500_000_000, "Memory increase should be less than 500MB after processing 1000 requests")
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentMemoryUsage() -> Int64 {
        let info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        }
        
        return 0
    }
}

// MARK: - Test Extensions

extension APIGatewayRequest {
    var tenantId: String? {
        return headers["X-Tenant-ID"]
    }
}

extension APIGatewayResponse where T == [String: Any] {
    var processingTime: TimeInterval {
        return processingTimeMs / 1000.0
    }
}

// MARK: - Mock API Middleware for Testing

class MockAPIMiddleware: APIMiddleware {
    let priority: Int = 100
    var processCallCount = 0
    
    func process(_ request: APIGatewayRequest) async throws -> APIGatewayRequest {
        processCallCount += 1
        return request
    }
}

// MARK: - Performance Test Helpers

class APIGatewayPerformanceTestHelper {
    
    static func measureResponseTime(for operation: () async throws -> Void) async -> TimeInterval {
        let startTime = Date()
        do {
            try await operation()
        } catch {
            // Ignore errors for performance measurement
        }
        return Date().timeIntervalSince(startTime)
    }
    
    static func runLoadTest(
        requests: [APIGatewayRequest],
        gateway: APIGatewayService,
        concurrentUsers: Int = 100
    ) async -> LoadTestResults {
        let startTime = Date()
        
        let results = await withTaskGroup(of: RequestResult.self) { group in
            let requestChunks = requests.chunked(into: requests.count / concurrentUsers)
            
            for chunk in requestChunks {
                group.addTask {
                    var successCount = 0
                    var errorCount = 0
                    var totalResponseTime: TimeInterval = 0
                    
                    for request in chunk {
                        let requestStartTime = Date()
                        do {
                            _ = try await gateway.processRequest(request, responseType: [String: Any].self)
                            successCount += 1
                        } catch {
                            errorCount += 1
                        }
                        totalResponseTime += Date().timeIntervalSince(requestStartTime)
                    }
                    
                    return RequestResult(
                        successCount: successCount,
                        errorCount: errorCount,
                        averageResponseTime: totalResponseTime / Double(chunk.count)
                    )
                }
            }
            
            var allResults: [RequestResult] = []
            for await result in group {
                allResults.append(result)
            }
            return allResults
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        let totalSuccess = results.reduce(0) { $0 + $1.successCount }
        let totalErrors = results.reduce(0) { $0 + $1.errorCount }
        let averageResponseTime = results.reduce(0) { $0 + $1.averageResponseTime } / Double(results.count)
        
        return LoadTestResults(
            totalRequests: totalSuccess + totalErrors,
            successfulRequests: totalSuccess,
            failedRequests: totalErrors,
            totalTime: totalTime,
            averageResponseTime: averageResponseTime,
            requestsPerSecond: Double(totalSuccess + totalErrors) / totalTime,
            successRate: Double(totalSuccess) / Double(totalSuccess + totalErrors)
        )
    }
}

struct RequestResult {
    let successCount: Int
    let errorCount: Int
    let averageResponseTime: TimeInterval
}

struct LoadTestResults {
    let totalRequests: Int
    let successfulRequests: Int
    let failedRequests: Int
    let totalTime: TimeInterval
    let averageResponseTime: TimeInterval
    let requestsPerSecond: Double
    let successRate: Double
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}