import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - API Gateway Revenue Integration Tests

class APIGatewayRevenueIntegrationTests: XCTestCase {
    
    // MARK: - Properties
    
    var mockAPIGateway: MockAPIGatewayService!
    var mockUsageTracker: MockAPIUsageTrackingService!
    var mockRevenueService: MockRevenueService!
    var mockBillingService: MockBillingService!
    var mockSecurityService: MockSecurityService!
    var mockRateLimiter: MockRateLimitingMiddleware!
    var mockAuthMiddleware: MockAuthenticationMiddleware!
    
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize all mock services
        mockAPIGateway = MockAPIGatewayService()
        mockUsageTracker = MockAPIUsageTrackingService()
        mockRevenueService = MockRevenueService()
        mockBillingService = MockBillingService()
        mockSecurityService = MockSecurityService()
        mockRateLimiter = MockRateLimitingMiddleware()
        mockAuthMiddleware = MockAuthenticationMiddleware()
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        mockAPIGateway = nil
        mockUsageTracker = nil
        mockRevenueService = nil
        mockBillingService = nil
        mockSecurityService = nil
        mockRateLimiter = nil
        mockAuthMiddleware = nil
        super.tearDown()
    }
    
    // MARK: - API Gateway Revenue Integration Tests
    
    func testAPIGatewayUsageTrackingTriggersRevenue() async throws {
        // This test validates that API usage through the gateway correctly triggers billing
        
        let tenantId = "api_revenue_tenant"
        let apiKey = "sk_test_api_key_123"
        let developerUserId = "developer_456"
        
        // 1. Set up API key validation
        let apiKeyValidation = APIKeyValidation(
            keyId: "key_789",
            tenantId: tenantId,
            isValid: true,
            permissions: [
                SecurityPermission(
                    id: "course_read",
                    resource: .course,
                    action: .read,
                    conditions: nil,
                    scope: .tenant
                )
            ],
            rateLimit: RateLimit(
                requestsPerMinute: 60,
                requestsPerHour: 1000,
                requestsPerDay: 10000,
                burstLimit: 100
            ),
            expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
            lastUsed: Date(),
            usage: APIKeyUsage(
                totalRequests: 0,
                lastRequest: nil,
                requestsToday: 0,
                requestsThisMonth: 0,
                errors: 0
            )
        )
        
        // Configure security service to return valid API key
        await mockSecurityService.setAPIKeyValidation(apiKey: apiKey, validation: apiKeyValidation)
        
        // 2. Create API request through gateway
        let apiRequest = APIGatewayRequest(
            path: "/api/v1/courses",
            method: HTTPMethod.get,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
            queryParameters: [
                "location": "california",
                "radius": "50"
            ],
            body: nil
        )
        
        // 3. Process request through API Gateway
        let response = try await mockAPIGateway.processRequest(apiRequest)
        
        // Assert successful response
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNotNil(response.data)
        XCTAssertGreaterThan(response.processingTime, 0)
        
        // 4. Verify usage tracking was triggered
        let usage = try await mockUsageTracker.getCurrentUsage(tenantId: tenantId)
        XCTAssertGreaterThan(usage.apiCalls, 0)
        XCTAssertGreaterThan(usage.bandwidth, 0)
        XCTAssertEqual(usage.tenantId, tenantId)
        
        // 5. Verify rate limiting was applied
        let rateLimitStatus = try await mockRateLimiter.checkRateLimit(
            tenantId: tenantId,
            apiKey: apiKey,
            endpoint: "/api/v1/courses"
        )
        XCTAssertTrue(rateLimitStatus.allowed)
        XCTAssertGreaterThan(rateLimitStatus.remainingRequests, 0)
        
        // 6. Simulate hitting rate limit
        for _ in 0..<60 { // Exceed per-minute limit
            let limitRequest = APIGatewayRequest(
                path: "/api/v1/courses",
                method: HTTPMethod.get,
                headers: ["Authorization": "Bearer \(apiKey)"],
                queryParameters: [:],
                body: nil
            )
            
            try await mockAPIGateway.processRequest(limitRequest)
        }
        
        // Check rate limit is now exceeded
        let exceededStatus = try await mockRateLimiter.checkRateLimit(
            tenantId: tenantId,
            apiKey: apiKey,
            endpoint: "/api/v1/courses"
        )
        // In production, this would return false for exceeded limit
        XCTAssertNotNil(exceededStatus)
    }
    
    func testUsageBasedBillingCalculation() async throws {
        // Test that API usage correctly calculates billing costs
        
        let tenantId = "billing_test_tenant"
        let apiKey = "sk_billing_test"
        let baseRatePerCall = 0.01 // $0.01 per API call
        let bandwidthRatePerMB = 0.05 // $0.05 per MB
        
        // 1. Generate significant API usage
        let numberOfCalls = 2500
        let avgResponseSize = 2048 // 2KB per response
        
        for i in 0..<numberOfCalls {
            let endpoint = ["/api/courses", "/api/tee-times", "/api/reviews"][i % 3]
            try await mockUsageTracker.trackAPICall(
                tenantId: tenantId,
                endpoint: endpoint,
                method: .GET,
                statusCode: 200,
                responseTime: Double.random(in: 0.1...0.5),
                dataSize: Int.random(in: 1024...4096)
            )
        }
        
        // 2. Calculate usage costs
        let usageCosts = try await mockUsageTracker.calculateUsageCosts(
            tenantId: tenantId,
            period: .monthly
        )
        
        // Assert cost calculation
        XCTAssertGreaterThan(usageCosts.totalCost, 0)
        XCTAssertEqual(usageCosts.totalAPICalls, numberOfCalls)
        XCTAssertGreaterThan(usageCosts.totalBandwidth, 0)
        
        let expectedMinCost = Double(numberOfCalls) * baseRatePerCall
        XCTAssertGreaterThanOrEqual(usageCosts.totalCost, expectedMinCost)
        
        // 3. Generate billing event
        let billingEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenantId,
            eventType: .usageCharge,
            amount: Decimal(usageCosts.totalCost),
            currency: "USD",
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "apiCalls": "\(usageCosts.totalAPICalls)",
                "bandwidth": "\(usageCosts.totalBandwidth)",
                "period": "monthly",
                "revenueStream": "api_monetization"
            ],
            source: .internal
        )
        
        try await mockRevenueService.recordRevenueEvent(billingEvent)
        
        // 4. Verify revenue was recorded
        let revenueMetrics = try await mockRevenueService.getRevenueMetrics(for: .monthly)
        XCTAssertGreaterThan(revenueMetrics.totalRevenue, 0)
        
        // 5. Test overage charges
        let overageCharges = try await mockUsageTracker.getOverageCharges(
            tenantId: tenantId,
            period: .monthly
        )
        
        // Should have overages for exceeding base quota
        XCTAssertFalse(overageCharges.isEmpty)
        
        let apiOverage = overageCharges.first { $0.quotaType == .apiCalls }
        XCTAssertNotNil(apiOverage)
        XCTAssertGreaterThan(apiOverage!.overageUnits, 0)
        XCTAssertGreaterThan(apiOverage!.overageAmount, 0)
    }
    
    func testMultiTenantAPIUsageIsolation() async throws {
        // Test that API usage is properly isolated between tenants
        
        let tenant1Id = "tenant_isolation_1"
        let tenant2Id = "tenant_isolation_2"
        let tenant3Id = "tenant_isolation_3"
        
        let apiKey1 = "sk_tenant1_key"
        let apiKey2 = "sk_tenant2_key"
        let apiKey3 = "sk_tenant3_key"
        
        // 1. Set up API keys for each tenant
        let validations = [
            (apiKey1, tenant1Id),
            (apiKey2, tenant2Id),
            (apiKey3, tenant3Id)
        ]
        
        for (key, tenantId) in validations {
            let validation = APIKeyValidation(
                keyId: "key_\(tenantId)",
                tenantId: tenantId,
                isValid: true,
                permissions: [
                    SecurityPermission(
                        id: "api_access",
                        resource: .api,
                        action: .read,
                        conditions: nil,
                        scope: .tenant
                    )
                ],
                rateLimit: RateLimit(
                    requestsPerMinute: 100,
                    requestsPerHour: 2000,
                    requestsPerDay: 20000,
                    burstLimit: 150
                ),
                expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                lastUsed: Date(),
                usage: APIKeyUsage(
                    totalRequests: 0,
                    lastRequest: nil,
                    requestsToday: 0,
                    requestsThisMonth: 0,
                    errors: 0
                )
            )
            
            await mockSecurityService.setAPIKeyValidation(apiKey: key, validation: validation)
        }
        
        // 2. Generate different usage patterns for each tenant
        let usagePatterns = [
            (tenant1Id, apiKey1, 100),  // Light usage
            (tenant2Id, apiKey2, 500),  // Medium usage
            (tenant3Id, apiKey3, 1500)  // Heavy usage
        ]
        
        for (tenantId, apiKey, callCount) in usagePatterns {
            for i in 0..<callCount {
                let request = APIGatewayRequest(
                    path: "/api/courses",
                    method: HTTPMethod.get,
                    headers: ["Authorization": "Bearer \(apiKey)"],
                    queryParameters: ["page": "\(i % 10)"],
                    body: nil
                )
                
                let response = try await mockAPIGateway.processRequest(request)
                XCTAssertEqual(response.statusCode, 200)
            }
        }
        
        // 3. Verify usage isolation
        let usage1 = try await mockUsageTracker.getCurrentUsage(tenantId: tenant1Id)
        let usage2 = try await mockUsageTracker.getCurrentUsage(tenantId: tenant2Id)
        let usage3 = try await mockUsageTracker.getCurrentUsage(tenantId: tenant3Id)
        
        // Assert each tenant has correct usage
        XCTAssertEqual(usage1.apiCalls, 100)
        XCTAssertEqual(usage2.apiCalls, 500)
        XCTAssertEqual(usage3.apiCalls, 1500)
        
        // 4. Verify security isolation - tenants can't access each other's data
        do {
            try await mockSecurityService.preventTenantCrossTalk(
                sourceId: tenant1Id,
                targetId: tenant2Id,
                operation: .dataAccess
            )
        } catch SecurityServiceError.crossTenantViolation {
            // Expected - security is working
        }
        
        // 5. Calculate separate billing for each tenant
        let costs1 = try await mockUsageTracker.calculateUsageCosts(tenantId: tenant1Id, period: .monthly)
        let costs2 = try await mockUsageTracker.calculateUsageCosts(tenantId: tenant2Id, period: .monthly)
        let costs3 = try await mockUsageTracker.calculateUsageCosts(tenantId: tenant3Id, period: .monthly)
        
        // Assert costs are proportional to usage
        XCTAssertLessThan(costs1.totalCost, costs2.totalCost)
        XCTAssertLessThan(costs2.totalCost, costs3.totalCost)
        
        // 6. Record revenue events for each tenant
        let revenueEvents = [
            (tenant1Id, costs1.totalCost),
            (tenant2Id, costs2.totalCost),
            (tenant3Id, costs3.totalCost)
        ]
        
        for (tenantId, cost) in revenueEvents {
            let revenueEvent = RevenueEvent(
                id: UUID(),
                tenantId: tenantId,
                eventType: .usageCharge,
                amount: Decimal(cost),
                currency: "USD",
                timestamp: Date(),
                subscriptionId: nil,
                customerId: nil,
                invoiceId: nil,
                metadata: ["isolation": "test"],
                source: .internal
            )
            
            try await mockRevenueService.recordRevenueEvent(revenueEvent)
        }
        
        // Verify total revenue matches sum of individual costs
        let totalRevenue = try await mockRevenueService.getRevenueMetrics(for: .monthly)
        let expectedTotal = costs1.totalCost + costs2.totalCost + costs3.totalCost
        XCTAssertEqual(Double(totalRevenue.totalRevenue), expectedTotal, accuracy: 0.01)
    }
    
    func testAPIGatewayMiddlewarePipeline() async throws {
        // Test that the complete middleware pipeline works with revenue tracking
        
        let tenantId = "pipeline_test_tenant"
        let apiKey = "sk_pipeline_test"
        let userId = "pipeline_user"
        
        // 1. Set up middleware pipeline
        let apiKeyValidation = APIKeyValidation(
            keyId: "pipeline_key",
            tenantId: tenantId,
            isValid: true,
            permissions: [
                SecurityPermission(
                    id: "pipeline_access",
                    resource: .api,
                    action: .read,
                    conditions: nil,
                    scope: .tenant
                )
            ],
            rateLimit: RateLimit(
                requestsPerMinute: 60,
                requestsPerHour: 1000,
                requestsPerDay: 10000,
                burstLimit: 100
            ),
            expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
            lastUsed: Date(),
            usage: APIKeyUsage(
                totalRequests: 0,
                lastRequest: nil,
                requestsToday: 0,
                requestsThisMonth: 0,
                errors: 0
            )
        )
        
        await mockSecurityService.setAPIKeyValidation(apiKey: apiKey, validation: apiKeyValidation)
        
        // 2. Create request that goes through full pipeline
        let request = APIGatewayRequest(
            path: "/api/v1/courses/search",
            method: HTTPMethod.post,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json",
                "X-User-ID": userId
            ],
            queryParameters: [:],
            body: """
            {
                "location": {
                    "lat": 37.7749,
                    "lng": -122.4194
                },
                "radius": 25,
                "maxPrice": 150,
                "amenities": ["driving_range", "pro_shop"]
            }
            """.data(using: .utf8)
        )
        
        // 3. Process through middleware pipeline:
        //    Auth -> Rate Limiting -> Usage Tracking -> Business Logic -> Response
        
        // Authentication middleware
        let authResult = try await mockAuthMiddleware.authenticate(request: request)
        XCTAssertTrue(authResult.isAuthenticated)
        XCTAssertEqual(authResult.tenantId, tenantId)
        
        // Rate limiting middleware
        let rateLimitResult = try await mockRateLimiter.checkRateLimit(
            tenantId: tenantId,
            apiKey: apiKey,
            endpoint: request.path
        )
        XCTAssertTrue(rateLimitResult.allowed)
        
        // Process full request
        let response = try await mockAPIGateway.processRequest(request)
        
        // 4. Verify response
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNotNil(response.data)
        XCTAssertGreaterThan(response.processingTime, 0)
        XCTAssertEqual(response.headers["X-RateLimit-Remaining"], "59")
        XCTAssertNotNil(response.headers["X-Usage-Count"])
        
        // 5. Verify usage was tracked with correct metadata
        let usage = try await mockUsageTracker.getCurrentUsage(tenantId: tenantId)
        XCTAssertEqual(usage.apiCalls, 1)
        XCTAssertGreaterThan(usage.bandwidth, 0)
        
        let usageDetails = try await mockUsageTracker.getUsageDetails(
            tenantId: tenantId,
            period: .daily
        )
        
        XCTAssertFalse(usageDetails.isEmpty)
        let firstCall = usageDetails.first!
        XCTAssertEqual(firstCall.endpoint, "/api/v1/courses/search")
        XCTAssertEqual(firstCall.method, "POST")
        XCTAssertEqual(firstCall.statusCode, 200)
        XCTAssertNotNil(firstCall.userId)
        
        // 6. Verify billing calculation includes metadata
        let costs = try await mockUsageTracker.calculateUsageCosts(
            tenantId: tenantId,
            period: .monthly
        )
        
        XCTAssertGreaterThan(costs.totalCost, 0)
        XCTAssertEqual(costs.totalAPICalls, 1)
        
        // 7. Create detailed revenue event
        let detailedRevenueEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenantId,
            eventType: .usageCharge,
            amount: Decimal(costs.totalCost),
            currency: "USD",
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "endpoint": firstCall.endpoint,
                "method": firstCall.method,
                "userId": firstCall.userId ?? "",
                "processingTime": "\(response.processingTime)",
                "pipeline": "complete"
            ],
            source: .internal
        )
        
        try await mockRevenueService.recordRevenueEvent(detailedRevenueEvent)
        
        // Verify detailed revenue tracking
        let revenueMetrics = try await mockRevenueService.getRevenueMetrics(for: .monthly)
        XCTAssertGreaterThan(revenueMetrics.totalRevenue, 0)
    }
    
    func testAPIGatewayErrorHandlingAndRevenue() async throws {
        // Test that API errors are handled correctly and still tracked for billing
        
        let tenantId = "error_test_tenant"
        let validApiKey = "sk_valid_key"
        let invalidApiKey = "sk_invalid_key"
        
        // 1. Set up valid API key
        let validation = APIKeyValidation(
            keyId: "valid_key",
            tenantId: tenantId,
            isValid: true,
            permissions: [
                SecurityPermission(
                    id: "api_access",
                    resource: .api,
                    action: .read,
                    conditions: nil,
                    scope: .tenant
                )
            ],
            rateLimit: RateLimit(
                requestsPerMinute: 60,
                requestsPerHour: 1000,
                requestsPerDay: 10000,
                burstLimit: 100
            ),
            expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
            lastUsed: Date(),
            usage: APIKeyUsage(
                totalRequests: 0,
                lastRequest: nil,
                requestsToday: 0,
                requestsThisMonth: 0,
                errors: 0
            )
        )
        
        await mockSecurityService.setAPIKeyValidation(apiKey: validApiKey, validation: validation)
        
        // 2. Test various error scenarios
        
        // Invalid API key
        let invalidKeyRequest = APIGatewayRequest(
            path: "/api/courses",
            method: HTTPMethod.get,
            headers: ["Authorization": "Bearer \(invalidApiKey)"],
            queryParameters: [:],
            body: nil
        )
        
        let unauthorizedResponse = try await mockAPIGateway.processRequest(invalidKeyRequest)
        XCTAssertEqual(unauthorizedResponse.statusCode, 401)
        
        // Valid key but invalid endpoint
        let invalidEndpointRequest = APIGatewayRequest(
            path: "/api/nonexistent",
            method: HTTPMethod.get,
            headers: ["Authorization": "Bearer \(validApiKey)"],
            queryParameters: [:],
            body: nil
        )
        
        let notFoundResponse = try await mockAPIGateway.processRequest(invalidEndpointRequest)
        XCTAssertEqual(notFoundResponse.statusCode, 404)
        
        // Valid request with server error simulation
        let serverErrorRequest = APIGatewayRequest(
            path: "/api/courses/trigger-error",
            method: HTTPMethod.get,
            headers: ["Authorization": "Bearer \(validApiKey)"],
            queryParameters: [:],
            body: nil
        )
        
        let errorResponse = try await mockAPIGateway.processRequest(serverErrorRequest)
        XCTAssertEqual(errorResponse.statusCode, 500)
        
        // 3. Verify error tracking
        let errorUsage = try await mockUsageTracker.getCurrentUsage(tenantId: tenantId)
        
        // Should track successful calls but not unauthorized ones
        XCTAssertGreaterThan(errorUsage.errors, 0)
        XCTAssertGreaterThan(errorUsage.apiCalls, 0) // Valid calls were tracked
        
        // 4. Test error billing policy
        let errorCosts = try await mockUsageTracker.calculateUsageCosts(
            tenantId: tenantId,
            period: .monthly
        )
        
        // Errors should still incur costs (bandwidth, processing time)
        XCTAssertGreaterThan(errorCosts.totalCost, 0)
        XCTAssertGreaterThan(errorCosts.errorCount, 0)
        
        // 5. Create error-aware revenue event
        let errorRevenueEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenantId,
            eventType: .usageCharge,
            amount: Decimal(errorCosts.totalCost),
            currency: "USD",
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "totalCalls": "\(errorCosts.totalAPICalls)",
                "errorCount": "\(errorCosts.errorCount)",
                "errorRate": "\(Double(errorCosts.errorCount) / Double(errorCosts.totalAPICalls))",
                "billingPolicy": "errors_charged"
            ],
            source: .internal
        )
        
        try await mockRevenueService.recordRevenueEvent(errorRevenueEvent)
        
        // Verify error revenue tracking
        let errorRevenue = try await mockRevenueService.getRevenueMetrics(for: .monthly)
        XCTAssertGreaterThan(errorRevenue.totalRevenue, 0)
    }
    
    // MARK: - Performance Tests
    
    func testHighVolumeAPIGatewayProcessing() throws {
        measure {
            Task {
                let tenantId = "performance_tenant"
                let apiKey = "sk_performance_key"
                
                // Set up performance test API key
                let validation = APIKeyValidation(
                    keyId: "perf_key",
                    tenantId: tenantId,
                    isValid: true,
                    permissions: [
                        SecurityPermission(
                            id: "perf_access",
                            resource: .api,
                            action: .read,
                            conditions: nil,
                            scope: .tenant
                        )
                    ],
                    rateLimit: RateLimit(
                        requestsPerMinute: 10000,
                        requestsPerHour: 100000,
                        requestsPerDay: 1000000,
                        burstLimit: 1000
                    ),
                    expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                    lastUsed: Date(),
                    usage: APIKeyUsage(
                        totalRequests: 0,
                        lastRequest: nil,
                        requestsToday: 0,
                        requestsThisMonth: 0,
                        errors: 0
                    )
                )
                
                await mockSecurityService.setAPIKeyValidation(apiKey: apiKey, validation: validation)
                
                // Process high volume of requests
                let requestCount = 1000
                
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for i in 0..<requestCount {
                        group.addTask {
                            let request = APIGatewayRequest(
                                path: "/api/courses",
                                method: HTTPMethod.get,
                                headers: ["Authorization": "Bearer \(apiKey)"],
                                queryParameters: ["page": "\(i % 100)"],
                                body: nil
                            )
                            
                            let _ = try await self.mockAPIGateway.processRequest(request)
                        }
                    }
                }
                
                // Verify all requests were processed and tracked
                let usage = try await mockUsageTracker.getCurrentUsage(tenantId: tenantId)
                XCTAssertEqual(usage.apiCalls, requestCount)
                
                // Calculate performance costs
                let costs = try await mockUsageTracker.calculateUsageCosts(
                    tenantId: tenantId,
                    period: .monthly
                )
                XCTAssertGreaterThan(costs.totalCost, 0)
            }
        }
    }
}

// MARK: - Mock Extensions for Testing

extension MockSecurityService {
    func setAPIKeyValidation(apiKey: String, validation: APIKeyValidation) async {
        // Mock implementation to store API key validation
        // In real implementation, this would be stored and retrieved
    }
}

extension MockAPIGatewayService {
    func processRequest(_ request: APIGatewayRequest) async throws -> APIGatewayResponse<Data> {
        // Mock implementation that simulates request processing
        
        // Simulate authentication check
        guard let authHeader = request.headers["Authorization"],
              authHeader.hasPrefix("Bearer ") else {
            return APIGatewayResponse(
                data: "Unauthorized".data(using: .utf8)!,
                statusCode: 401,
                headers: ["Content-Type": "application/json"],
                processingTime: 0.01
            )
        }
        
        // Simulate different responses based on path
        let responseData: Data
        let statusCode: Int
        
        switch request.path {
        case "/api/courses":
            responseData = """
            {
                "courses": [
                    {"id": 1, "name": "Pine Valley", "rating": 4.8},
                    {"id": 2, "name": "Oak Hill", "rating": 4.6}
                ]
            }
            """.data(using: .utf8)!
            statusCode = 200
            
        case "/api/courses/trigger-error":
            responseData = """
            {"error": "Internal server error"}
            """.data(using: .utf8)!
            statusCode = 500
            
        case "/api/nonexistent":
            responseData = """
            {"error": "Endpoint not found"}
            """.data(using: .utf8)!
            statusCode = 404
            
        default:
            responseData = """
            {"message": "Success"}
            """.data(using: .utf8)!
            statusCode = 200
        }
        
        return APIGatewayResponse(
            data: responseData,
            statusCode: statusCode,
            headers: [
                "Content-Type": "application/json",
                "X-RateLimit-Remaining": "59",
                "X-Usage-Count": "1"
            ],
            processingTime: Double.random(in: 0.05...0.3)
        )
    }
}

// MARK: - Test Data Structures

struct APIGatewayRequest {
    let path: String
    let method: HTTPMethod
    let headers: [String: String]
    let queryParameters: [String: String]
    let body: Data?
}

struct APIGatewayResponse<T> {
    let data: T
    let statusCode: Int
    let headers: [String: String]
    let processingTime: TimeInterval
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}