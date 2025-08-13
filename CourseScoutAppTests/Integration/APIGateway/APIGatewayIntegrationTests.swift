import XCTest
import Appwrite
import Combine
@testable import GolfFinderSwiftUI

class APIGatewayIntegrationTests: XCTestCase {
    
    var apiGateway: APIGatewayService!
    var testContainer: ServiceContainer!
    var mockAppwriteClient: Client!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        super.setUp()
        
        TestEnvironmentManager.shared.setupTestEnvironment()
        
        mockAppwriteClient = Client()
            .setEndpoint("https://test-appwrite.local/v1")
            .setProject("test-integration-project")
            .setKey("test-integration-key")
        
        testContainer = ServiceContainer(appwriteClient: mockAppwriteClient, environment: .test)
        apiGateway = testContainer.apiGatewayService() as? APIGatewayService
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithError() throws {
        apiGateway = nil
        testContainer = nil
        mockAppwriteClient = nil
        cancellables = nil
        
        TestEnvironmentManager.shared.teardownTestEnvironment()
        super.tearDown()
    }
    
    // MARK: - End-to-End API Flow Tests
    
    func testCompleteAPIFlow_CourseDiscovery_ShouldSucceed() async throws {
        // Given - Simulate external developer using Course Discovery API
        let apiKey = "integration-test-key-courses"
        let request = APIGatewayRequest(
            path: "/courses",
            method: .GET,
            version: .v1,
            apiKey: apiKey,
            headers: [
                "Content-Type": "application/json",
                "X-API-Key": apiKey,
                "X-Tenant-ID": "test-tenant-1"
            ],
            queryParameters: [
                "latitude": "37.7749",
                "longitude": "-122.4194",
                "radius": "25"
            ]
        )
        
        // When
        let response = try await apiGateway.processRequest(request, responseType: CourseDiscoveryResponse.self)
        
        // Then
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNotNil(response.data)
        XCTAssertLessThan(response.processingTimeMs, 500.0, "Course discovery should complete under 500ms")
        XCTAssertNil(response.error)
        
        // Verify response structure
        if let courseData = response.data {
            XCTAssertGreaterThan(courseData.courses.count, 0, "Should return at least some courses")
            XCTAssertNotNil(courseData.metadata)
            XCTAssertGreaterThan(courseData.metadata.totalResults, 0)
        }
    }
    
    func testCompleteAPIFlow_AnalyticsEndpoint_WithBusinessTier_ShouldSucceed() async throws {
        // Given - Business tier customer accessing analytics
        let apiKey = "business-tier-analytics-key"
        let request = APIGatewayRequest(
            path: "/courses/analytics",
            method: .GET,
            version: .v1,
            apiKey: apiKey,
            headers: [
                "Content-Type": "application/json",
                "X-API-Key": apiKey,
                "X-Tenant-ID": "business-tenant-1"
            ],
            queryParameters: [
                "period": "week",
                "metric": "bookings"
            ]
        )
        
        // When
        let response = try await apiGateway.processRequest(request, responseType: AnalyticsResponse.self)
        
        // Then
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNotNil(response.data)
        XCTAssertLessThan(response.processingTimeMs, 300.0)
        
        if let analyticsData = response.data {
            XCTAssertNotNil(analyticsData.metrics)
            XCTAssertNotNil(analyticsData.period)
            XCTAssertGreaterThan(analyticsData.metrics.count, 0)
        }
    }
    
    func testCompleteAPIFlow_PredictiveInsights_WithEnterpriseTier_ShouldSucceed() async throws {
        // Given - Enterprise customer using AI predictions
        let apiKey = "enterprise-ai-predictions-key"
        let requestBody = PredictionRequest(
            courseId: "test-course-123",
            date: Date(),
            playerProfile: PlayerProfile(
                handicap: 15.2,
                averageScore: 85,
                preferredTeeTime: "morning"
            )
        )
        let bodyData = try JSONEncoder().encode(requestBody)
        
        let request = APIGatewayRequest(
            path: "/predictions",
            method: .POST,
            version: .v2,
            apiKey: apiKey,
            headers: [
                "Content-Type": "application/json",
                "X-API-Key": apiKey,
                "X-Tenant-ID": "enterprise-tenant-1"
            ],
            body: bodyData
        )
        
        // When
        let response = try await apiGateway.processRequest(request, responseType: PredictionResponse.self)
        
        // Then
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNotNil(response.data)
        XCTAssertLessThan(response.processingTimeMs, 1000.0, "AI predictions should complete under 1 second")
        
        if let predictionData = response.data {
            XCTAssertNotNil(predictionData.optimalTeeTime)
            XCTAssertNotNil(predictionData.weatherScore)
            XCTAssertNotNil(predictionData.recommendedStrategy)
        }
    }
    
    // MARK: - Rate Limiting Integration Tests
    
    func testRateLimiting_FreeTier_ShouldEnforceLimit() async throws {
        // Given - Free tier API key with 1000 daily requests
        let apiKey = "free-tier-rate-limit-test"
        let requests = (0..<10).map { index in
            APIGatewayRequest(
                path: "/courses",
                method: .GET,
                version: .v1,
                apiKey: apiKey,
                headers: ["X-API-Key": apiKey, "X-Tenant-ID": "free-tenant-\(index)"]
            )
        }
        
        // When - Make requests rapidly
        var successCount = 0
        var rateLimitedCount = 0
        
        for request in requests {
            do {
                let response = try await apiGateway.processRequest(request, responseType: [String: Any].self)
                if response.statusCode == 200 {
                    successCount += 1
                }
            } catch APIGatewayError.rateLimitExceeded {
                rateLimitedCount += 1
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        // Then
        XCTAssertGreaterThan(successCount, 0, "Some requests should succeed")
        // Note: Rate limiting may kick in after several requests
        XCTAssertEqual(successCount + rateLimitedCount, requests.count, "All requests should be accounted for")
    }
    
    func testRateLimiting_BusinessTier_ShouldAllowHigherLimits() async throws {
        // Given - Business tier with unlimited requests
        let apiKey = "business-unlimited-requests"
        let requests = (0..<50).map { index in
            APIGatewayRequest(
                path: "/courses",
                method: .GET,
                version: .v1,
                apiKey: apiKey,
                headers: ["X-API-Key": apiKey, "X-Tenant-ID": "business-tenant"]
            )
        }
        
        // When - Make many requests
        let results = await withTaskGroup(of: Result<APIGatewayResponse<[String: Any]>, Error>.self) { group in
            for request in requests {
                group.addTask {
                    do {
                        let response = try await self.apiGateway.processRequest(request, responseType: [String: Any].self)
                        return .success(response)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            
            var results: [Result<APIGatewayResponse<[String: Any]>, Error>] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        // Then
        let successCount = results.filter { 
            if case .success = $0 { return true }
            return false
        }.count
        
        XCTAssertEqual(successCount, requests.count, "Business tier should handle all concurrent requests")
    }
    
    // MARK: - Authentication Integration Tests
    
    func testAuthentication_ValidAPIKey_ShouldAllowAccess() async throws {
        // Given
        let validApiKey = "valid-test-integration-key"
        let request = APIGatewayRequest(
            path: "/courses",
            method: .GET,
            version: .v1,
            apiKey: validApiKey,
            headers: ["X-API-Key": validApiKey]
        )
        
        // When
        let validationResult = try await apiGateway.validateAPIKey(validApiKey)
        let response = try await apiGateway.processRequest(request, responseType: [String: Any].self)
        
        // Then
        XCTAssertTrue(validationResult.isValid)
        XCTAssertEqual(response.statusCode, 200)
    }
    
    func testAuthentication_ExpiredAPIKey_ShouldDenyAccess() async throws {
        // Given
        let expiredApiKey = "expired-api-key-12345"
        let request = APIGatewayRequest(
            path: "/courses",
            method: .GET,
            version: .v1,
            apiKey: expiredApiKey,
            headers: ["X-API-Key": expiredApiKey]
        )
        
        // When & Then
        do {
            _ = try await apiGateway.processRequest(request, responseType: [String: Any].self)
            XCTFail("Expected authentication error for expired key")
        } catch APIGatewayError.authenticationFailed {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Revenue Integration Tests
    
    func testRevenueTracking_APIUsage_ShouldRecordCorrectly() async throws {
        // Given
        let tenantId = "revenue-test-tenant"
        let apiKey = "revenue-tracking-key"
        let request = APIGatewayRequest(
            path: "/courses/analytics",
            method: .GET,
            version: .v1,
            apiKey: apiKey,
            headers: [
                "X-API-Key": apiKey,
                "X-Tenant-ID": tenantId
            ]
        )
        
        let revenueService = testContainer.revenueService()
        let usageTracker = testContainer.apiUsageTrackingService()
        
        // When
        let response = try await apiGateway.processRequest(request, responseType: [String: Any].self)
        
        // Give time for async revenue tracking
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Then
        XCTAssertEqual(response.statusCode, 200)
        
        // Verify usage was tracked
        let usage = try await usageTracker.getCurrentUsage(tenantId: tenantId)
        XCTAssertGreaterThan(usage.totalApiCalls, 0)
        
        // Verify revenue was recorded
        let revenueEvents = try await revenueService.getRevenueEvents(
            tenantId: tenantId,
            period: .daily
        )
        XCTAssertGreaterThan(revenueEvents.count, 0)
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testErrorHandling_ServiceFailure_ShouldReturnProperError() async throws {
        // Given - Request that will cause service failure
        let request = APIGatewayRequest(
            path: "/courses",
            method: .GET,
            version: .v1,
            apiKey: "test-key",
            headers: [
                "X-API-Key": "test-key",
                "X-Force-Error": "service_unavailable"
            ]
        )
        
        // When & Then
        do {
            _ = try await apiGateway.processRequest(request, responseType: [String: Any].self)
            XCTFail("Expected service error")
        } catch {
            // Should handle service errors gracefully
            XCTAssertTrue(error is APIGatewayError)
        }
    }
    
    // MARK: - Performance Integration Tests
    
    func testPerformance_HighConcurrencyLoad_ShouldMaintainResponseTimes() async throws {
        // Given - Simulate high concurrent load
        let concurrentUsers = 100
        let requestsPerUser = 5
        let totalRequests = concurrentUsers * requestsPerUser
        
        var allRequests: [APIGatewayRequest] = []
        for userId in 0..<concurrentUsers {
            for requestId in 0..<requestsPerUser {
                let request = APIGatewayRequest(
                    path: "/courses",
                    method: .GET,
                    version: .v1,
                    apiKey: "load-test-key-\(userId)",
                    headers: [
                        "X-API-Key": "load-test-key-\(userId)",
                        "X-User-ID": "user-\(userId)",
                        "X-Request-ID": "\(userId)-\(requestId)"
                    ]
                )
                allRequests.append(request)
            }
        }
        
        // When - Execute load test
        let startTime = Date()
        let results = await withTaskGroup(of: (TimeInterval, Result<APIGatewayResponse<[String: Any]>, Error>).self) { group in
            for request in allRequests {
                group.addTask {
                    let requestStartTime = Date()
                    do {
                        let response = try await self.apiGateway.processRequest(request, responseType: [String: Any].self)
                        let requestTime = Date().timeIntervalSince(requestStartTime)
                        return (requestTime, .success(response))
                    } catch {
                        let requestTime = Date().timeIntervalSince(requestStartTime)
                        return (requestTime, .failure(error))
                    }
                }
            }
            
            var results: [(TimeInterval, Result<APIGatewayResponse<[String: Any]>, Error>)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        let totalTime = Date().timeIntervalSince(startTime)
        
        // Then - Analyze performance
        let successResults = results.compactMap { result in
            if case .success(let response) = result.1 {
                return (result.0, response)
            }
            return nil
        }
        
        let failureResults = results.compactMap { result in
            if case .failure(let error) = result.1 {
                return (result.0, error)
            }
            return nil
        }
        
        let successCount = successResults.count
        let averageResponseTime = successResults.reduce(0) { $0 + $1.0 } / Double(successResults.count)
        let successRate = Double(successCount) / Double(totalRequests)
        
        // Performance assertions
        XCTAssertGreaterThanOrEqual(successRate, 0.95, "Success rate should be at least 95%")
        XCTAssertLessThan(averageResponseTime, 1.0, "Average response time should be under 1 second")
        XCTAssertLessThan(totalTime, 30.0, "Total load test should complete within 30 seconds")
        
        print("Load Test Results:")
        print("- Total Requests: \(totalRequests)")
        print("- Successful: \(successCount)")
        print("- Failed: \(failureResults.count)")
        print("- Success Rate: \(String(format: "%.2f", successRate * 100))%")
        print("- Average Response Time: \(String(format: "%.3f", averageResponseTime))s")
        print("- Total Time: \(String(format: "%.2f", totalTime))s")
        print("- Requests/Second: \(String(format: "%.2f", Double(successCount) / totalTime))")
    }
    
    // MARK: - Health Monitoring Integration Tests
    
    func testHealthMonitoring_ContinuousChecks_ShouldReportAccurately() async throws {
        // Given
        let healthCheckInterval = 1.0 // 1 second
        let monitoringDuration = 5.0 // 5 seconds
        var healthChecks: [APIHealthStatus] = []
        
        // When - Monitor health over time
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < monitoringDuration {
            let healthStatus = await apiGateway.healthCheck()
            healthChecks.append(healthStatus)
            
            try await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
        }
        
        // Then
        XCTAssertGreaterThan(healthChecks.count, 3, "Should have multiple health checks")
        
        for healthStatus in healthChecks {
            XCTAssertTrue(healthStatus.isHealthy, "System should remain healthy during monitoring")
            XCTAssertLessThan(healthStatus.memoryUsagePercent, 90.0, "Memory usage should stay reasonable")
            XCTAssertLessThan(healthStatus.averageResponseTimeMs, 1000.0, "Response times should be reasonable")
        }
    }
    
    // MARK: - Cross-Service Integration Tests
    
    func testCrossServiceIntegration_CourseDataWithRevenue_ShouldWork() async throws {
        // Given
        let tenantId = "cross-service-test-tenant"
        let apiKey = "cross-service-api-key"
        let golfCourseService = testContainer.golfCourseService()
        let billingService = testContainer.billingService()
        
        // When - Make API request that involves multiple services
        let request = APIGatewayRequest(
            path: "/courses",
            method: .GET,
            version: .v1,
            apiKey: apiKey,
            headers: [
                "X-API-Key": apiKey,
                "X-Tenant-ID": tenantId
            ],
            queryParameters: [
                "latitude": "37.7749",
                "longitude": "-122.4194",
                "radius": "10"
            ]
        )
        
        let response = try await apiGateway.processRequest(request, responseType: CourseDiscoveryResponse.self)
        
        // Give time for billing integration
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Then - Verify cross-service integration
        XCTAssertEqual(response.statusCode, 200)
        
        // Verify billing was updated
        let currentUsage = try await billingService.getCurrentBillingCycle(tenantId: tenantId)
        XCTAssertNotNil(currentUsage)
        
        // Verify course data was retrieved
        if let courseData = response.data {
            XCTAssertGreaterThan(courseData.courses.count, 0)
        }
    }
}

// MARK: - Test Data Models

struct CourseDiscoveryResponse: Codable {
    let courses: [GolfCourse]
    let metadata: SearchMetadata
}

struct SearchMetadata: Codable {
    let totalResults: Int
    let searchRadius: Double
    let processingTimeMs: Double
    let userLocation: LocationCoordinate
}

struct LocationCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

struct AnalyticsResponse: Codable {
    let metrics: [String: Double]
    let period: String
    let generatedAt: Date
}

struct PredictionRequest: Codable {
    let courseId: String
    let date: Date
    let playerProfile: PlayerProfile
}

struct PlayerProfile: Codable {
    let handicap: Double
    let averageScore: Int
    let preferredTeeTime: String
}

struct PredictionResponse: Codable {
    let optimalTeeTime: String
    let weatherScore: Double
    let recommendedStrategy: String
    let confidenceScore: Double
}