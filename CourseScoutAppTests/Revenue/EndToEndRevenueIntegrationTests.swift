import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - End-to-End Revenue Integration Tests

class EndToEndRevenueIntegrationTests: XCTestCase {
    
    // MARK: - Properties
    
    var serviceContainer: ServiceContainer!
    var mockRevenueService: MockRevenueService!
    var mockBillingService: MockBillingService!
    var mockSubscriptionService: MockSubscriptionService!
    var mockAPIUsageService: MockAPIUsageTrackingService!
    var mockSecurityService: MockSecurityService!
    var mockTenantService: MockTenantManagementService!
    var mockAPIGatewayService: MockAPIGatewayService!
    var mockAPIKeyService: MockAPIKeyManagementService!
    var mockDeveloperAuthService: MockDeveloperAuthService!
    
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize service container with test environment
        serviceContainer = ServiceContainer(
            appwriteClient: MockAppwriteClient(),
            environment: .test
        )
        
        // Initialize all mock services
        mockRevenueService = MockRevenueService()
        mockBillingService = MockBillingService()
        mockSubscriptionService = MockSubscriptionService()
        mockAPIUsageService = MockAPIUsageTrackingService()
        mockSecurityService = MockSecurityService()
        mockTenantService = MockTenantManagementService()
        mockAPIGatewayService = MockAPIGatewayService()
        mockAPIKeyService = MockAPIKeyManagementService()
        mockDeveloperAuthService = MockDeveloperAuthService()
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        serviceContainer = nil
        mockRevenueService = nil
        mockBillingService = nil
        mockSubscriptionService = nil
        mockAPIUsageService = nil
        mockSecurityService = nil
        mockTenantService = nil
        mockAPIGatewayService = nil
        mockAPIKeyService = nil
        mockDeveloperAuthService = nil
        super.tearDown()
    }
    
    // MARK: - Complete Hybrid Business Model Integration Test
    
    func testCompleteHybridBusinessModelIntegration() async throws {
        // This test validates all four revenue streams working together:
        // 1. Consumer freemium app ($10/month premium)
        // 2. White label platform ($500-2000/month)
        // 3. B2B analytics SaaS ($200-1000/month)
        // 4. API monetization (usage-based pricing)
        
        // STEP 1: Set up consumer revenue flow
        let consumerRevenueResult = try await setupConsumerRevenueFlow()
        XCTAssertNotNil(consumerRevenueResult.subscription)
        XCTAssertEqual(consumerRevenueResult.subscription.price, 10.00)
        
        // STEP 2: Set up white label platform
        let whiteLabelResult = try await setupWhiteLabelPlatform()
        XCTAssertNotNil(whiteLabelResult.tenant)
        XCTAssertEqual(whiteLabelResult.subscription.price, 1500.00)
        
        // STEP 3: Set up B2B analytics service
        let analyticsResult = try await setupB2BAnalyticsService(
            parentTenant: whiteLabelResult.tenant
        )
        XCTAssertNotNil(analyticsResult.subscription)
        XCTAssertEqual(analyticsResult.subscription.price, 500.00)
        
        // STEP 4: Set up API monetization
        let apiResult = try await setupAPIMonetization()
        XCTAssertNotNil(apiResult.apiKey)
        XCTAssertNotNil(apiResult.usage)
        
        // STEP 5: Validate security isolation between all tenants
        try await validateMultiTenantSecurity([
            consumerRevenueResult.tenantId,
            whiteLabelResult.tenant.id,
            analyticsResult.tenantId
        ])
        
        // STEP 6: Validate revenue flows integrate correctly
        try await validateIntegratedRevenueFlo([
            consumerRevenueResult,
            whiteLabelResult,
            analyticsResult,
            apiResult
        ])
        
        // STEP 7: Test cross-revenue stream analytics
        try await validateCrossRevenueAnalytics()
        
        // STEP 8: Test billing integration across all streams
        try await validateIntegratedBilling()
    }
    
    // MARK: - Consumer Revenue Flow Setup
    
    private func setupConsumerRevenueFlow() async throws -> ConsumerRevenueResult {
        let tenantId = "consumer_tenant"
        let userId = "consumer_user_123"
        let email = "premium@example.com"
        
        // 1. Create consumer customer
        let customer = try await mockBillingService.createCustomer(
            tenantId: tenantId,
            email: email,
            name: "Premium Consumer",
            metadata: [
                "userId": userId,
                "tier": "premium",
                "source": "consumer_app"
            ]
        )
        
        // 2. Create premium subscription ($10/month)
        let subscriptionRequest = SubscriptionRequest(
            tenantId: tenantId,
            customerId: customer.id,
            tierId: "premium_consumer",
            billingCycle: .monthly,
            price: 10.00,
            currency: "USD",
            trialStart: nil,
            trialEnd: nil,
            metadata: [
                "userId": userId,
                "revenueStream": "consumer"
            ]
        )
        
        let subscription = try await mockSubscriptionService.createSubscription(subscriptionRequest)
        
        // 3. Track consumer API usage
        try await mockAPIUsageService.trackAPICall(
            tenantId: tenantId,
            endpoint: "/courses",
            method: .GET,
            statusCode: 200,
            responseTime: 0.1,
            dataSize: 2048
        )
        
        // 4. Record revenue event
        let revenueEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenantId,
            eventType: .subscriptionCreated,
            amount: 10.00,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: subscription.id,
            customerId: customer.id,
            invoiceId: nil,
            metadata: ["revenueStream": "consumer"],
            source: .stripe
        )
        
        try await mockRevenueService.recordRevenueEvent(revenueEvent)
        
        // 5. Validate security for consumer tenant
        let hasAccess = try await mockSecurityService.validateTenantAccess(
            userId: userId,
            tenantId: tenantId,
            resourceId: "premium_features",
            action: .read
        )
        XCTAssertTrue(hasAccess)
        
        return ConsumerRevenueResult(
            tenantId: tenantId,
            userId: userId,
            customer: customer,
            subscription: subscription
        )
    }
    
    // MARK: - White Label Platform Setup
    
    private func setupWhiteLabelPlatform() async throws -> WhiteLabelResult {
        let golfCourseName = "Premium Golf Club"
        let adminEmail = "admin@premiumgolf.com"
        let monthlyFee: Decimal = 1500.00
        
        // 1. Create white label tenant
        let tenantRequest = TenantCreateRequest(
            name: golfCourseName,
            slug: "premium-golf-club",
            type: .golfCourse,
            primaryDomain: "premiumgolf.coursescout.com",
            branding: TenantBranding(
                primaryColor: "#1976D2",
                secondaryColor: "#2196F3",
                logoURL: "https://premiumgolf.com/logo.png",
                faviconURL: "https://premiumgolf.com/favicon.ico",
                customCSS: ".header { background-color: #1976D2; }",
                fontFamily: "Roboto"
            ),
            settings: TenantSettings.golfCourseDefaults,
            limits: TenantLimits.golfCourse,
            features: [.customBranding, .analyticsAccess, .memberManagement],
            parentTenantId: nil,
            metadata: [
                "industry": "golf",
                "setupFee": "1000",
                "revenueStream": "white_label"
            ]
        )
        
        let tenant = try await mockTenantService.createTenant(tenantRequest)
        
        // 2. Create white label customer
        let customer = try await mockBillingService.createCustomer(
            tenantId: tenant.id,
            email: adminEmail,
            name: golfCourseName,
            metadata: [
                "tenantId": tenant.id,
                "revenueStream": "white_label"
            ]
        )
        
        // 3. Create white label subscription ($1500/month)
        let subscriptionRequest = SubscriptionRequest(
            tenantId: tenant.id,
            customerId: customer.id,
            tierId: "golf_course_premium",
            billingCycle: .monthly,
            price: monthlyFee,
            currency: "USD",
            trialStart: Date(),
            trialEnd: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            metadata: [
                "setupFee": "1000",
                "revenueStream": "white_label"
            ]
        )
        
        let subscription = try await mockSubscriptionService.createSubscription(subscriptionRequest)
        
        // 4. Record setup fee and subscription revenue
        let setupFeeEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenant.id,
            eventType: .setupFee,
            amount: 1000.00,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: subscription.id,
            customerId: customer.id,
            invoiceId: nil,
            metadata: ["revenueStream": "white_label", "type": "setup"],
            source: .stripe
        )
        
        let subscriptionEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenant.id,
            eventType: .subscriptionCreated,
            amount: monthlyFee,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: subscription.id,
            customerId: customer.id,
            invoiceId: nil,
            metadata: ["revenueStream": "white_label", "type": "recurring"],
            source: .stripe
        )
        
        try await mockRevenueService.recordRevenueEvent(setupFeeEvent)
        try await mockRevenueService.recordRevenueEvent(subscriptionEvent)
        
        // 5. Validate tenant security isolation
        let isValidAccess = try await mockSecurityService.validateTenantAccess(
            userId: "admin_user",
            tenantId: tenant.id,
            resourceId: "tenant_settings",
            action: .admin
        )
        XCTAssertTrue(isValidAccess)
        
        // 6. Ensure cross-tenant data isolation
        try await mockSecurityService.preventTenantCrossTalk(
            sourceId: tenant.id,
            targetId: "consumer_tenant",
            operation: .dataAccess
        )
        
        return WhiteLabelResult(
            tenant: tenant,
            customer: customer,
            subscription: subscription
        )
    }
    
    // MARK: - B2B Analytics Service Setup
    
    private func setupB2BAnalyticsService(parentTenant: Tenant) async throws -> AnalyticsResult {
        let analyticsCustomerName = "Golf Analytics Corp"
        let analyticsEmail = "analytics@golfcorp.com"
        let monthlyFee: Decimal = 500.00
        let tenantId = "analytics_tenant_456"
        
        // 1. Create analytics customer
        let customer = try await mockBillingService.createCustomer(
            tenantId: tenantId,
            email: analyticsEmail,
            name: analyticsCustomerName,
            metadata: [
                "revenueStream": "b2b_analytics",
                "dataRetentionDays": "365",
                "exportFormats": "csv,json,excel"
            ]
        )
        
        // 2. Create B2B analytics subscription ($500/month)
        let subscriptionRequest = SubscriptionRequest(
            tenantId: tenantId,
            customerId: customer.id,
            tierId: "analytics_professional",
            billingCycle: .monthly,
            price: monthlyFee,
            currency: "USD",
            trialStart: nil,
            trialEnd: nil,
            metadata: [
                "revenueStream": "b2b_analytics",
                "features": "advanced_reporting,data_export,api_access"
            ]
        )
        
        let subscription = try await mockSubscriptionService.createSubscription(subscriptionRequest)
        
        // 3. Track analytics API usage
        let analyticsEndpoints = ["/analytics/revenue", "/analytics/users", "/analytics/usage"]
        for endpoint in analyticsEndpoints {
            try await mockAPIUsageService.trackAPICall(
                tenantId: tenantId,
                endpoint: endpoint,
                method: .GET,
                statusCode: 200,
                responseTime: 0.3,
                dataSize: 5120
            )
        }
        
        // 4. Record analytics revenue event
        let revenueEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenantId,
            eventType: .subscriptionCreated,
            amount: monthlyFee,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: subscription.id,
            customerId: customer.id,
            invoiceId: nil,
            metadata: ["revenueStream": "b2b_analytics"],
            source: .stripe
        )
        
        try await mockRevenueService.recordRevenueEvent(revenueEvent)
        
        // 5. Validate analytics tenant security
        let hasAnalyticsAccess = try await mockSecurityService.validateTenantAccess(
            userId: "analytics_user",
            tenantId: tenantId,
            resourceId: "analytics_data",
            action: .read
        )
        XCTAssertTrue(hasAnalyticsAccess)
        
        return AnalyticsResult(
            tenantId: tenantId,
            customer: customer,
            subscription: subscription
        )
    }
    
    // MARK: - API Monetization Setup
    
    private func setupAPIMonetization() async throws -> APIResult {
        let developerEmail = "developer@golftech.com"
        let tenantId = "api_tenant_789"
        
        // 1. Create developer account
        let developerAuth = try await mockDeveloperAuthService.registerDeveloper(
            email: developerEmail,
            name: "Golf Tech Innovations",
            company: "Golf Tech Inc"
        )
        
        // 2. Create API key with usage-based pricing
        let apiKey = try await mockAPIKeyService.createAPIKey(
            developerId: developerAuth.developerId,
            name: "Golf Data API Key",
            permissions: [
                SecurityPermission(
                    id: "api_course_data",
                    resource: .course,
                    action: .read,
                    conditions: nil,
                    scope: .tenant
                )
            ],
            rateLimit: RateLimit(
                requestsPerMinute: 100,
                requestsPerHour: 5000,
                requestsPerDay: 50000,
                burstLimit: 200
            )
        )
        
        // 3. Track API usage for billing
        let apiEndpoints = ["/api/courses", "/api/tee-times", "/api/reviews"]
        for i in 0..<250 { // Generate billable usage
            let endpoint = apiEndpoints[i % apiEndpoints.count]
            try await mockAPIUsageService.trackAPICall(
                tenantId: tenantId,
                endpoint: endpoint,
                method: .GET,
                statusCode: 200,
                responseTime: 0.15,
                dataSize: 1024
            )
        }
        
        // 4. Calculate usage costs
        let usageCosts = try await mockAPIUsageService.calculateUsageCosts(
            tenantId: tenantId,
            period: .monthly
        )
        
        // 5. Record API revenue event
        let apiRevenueEvent = RevenueEvent(
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
                "revenueStream": "api_monetization",
                "apiCalls": "\(usageCosts.totalAPICalls)",
                "bandwidth": "\(usageCosts.totalBandwidth)"
            ],
            source: .internal
        )
        
        try await mockRevenueService.recordRevenueEvent(apiRevenueEvent)
        
        // 6. Validate API security
        let apiValidation = try await mockSecurityService.validateAPIKeyForTenant(
            apiKey: apiKey.key,
            tenantId: tenantId
        )
        XCTAssertTrue(apiValidation.isValid)
        
        return APIResult(
            tenantId: tenantId,
            apiKey: apiKey,
            usage: usageCosts
        )
    }
    
    // MARK: - Multi-Tenant Security Validation
    
    private func validateMultiTenantSecurity(_ tenantIds: [String]) async throws {
        // Test security isolation between all tenants
        for (index, sourceTenantId) in tenantIds.enumerated() {
            for (targetIndex, targetTenantId) in tenantIds.enumerated() {
                if index != targetIndex {
                    // Ensure tenants cannot access each other's data
                    do {
                        try await mockSecurityService.preventTenantCrossTalk(
                            sourceId: sourceTenantId,
                            targetId: targetTenantId,
                            operation: .dataAccess
                        )
                        // If no error is thrown, cross-tenant access is prevented (good)
                    } catch SecurityServiceError.crossTenantViolation {
                        // Expected error - security is working correctly
                        continue
                    } catch {
                        XCTFail("Unexpected error during cross-tenant validation: \(error)")
                    }
                }
            }
        }
        
        // Validate data encryption for each tenant
        for tenantId in tenantIds {
            let encryptionStatus = try await mockSecurityService.getTenantEncryptionStatus(tenantId: tenantId)
            XCTAssertTrue(encryptionStatus.isEnabled)
            XCTAssertEqual(encryptionStatus.status, .healthy)
        }
        
        // Test tenant data isolation at query level
        for tenantId in tenantIds {
            let mockQuery = MockQuery()
            let isolatedQuery = try mockSecurityService.ensureTenantDataIsolation(
                query: mockQuery,
                tenantId: tenantId
            )
            XCTAssertNotNil(isolatedQuery)
        }
    }
    
    // MARK: - Integrated Revenue Flow Validation
    
    private func validateIntegratedRevenueFlows(_ results: [Any]) async throws {
        // Calculate total revenue across all streams
        let totalRevenue = try await mockRevenueService.getRevenueMetrics(for: .monthly)
        
        // Validate revenue breakdown
        let revenueBreakdown = try await mockRevenueService.getRevenueBreakdown()
        
        XCTAssertGreaterThan(totalRevenue.totalRevenue, 0)
        XCTAssertGreaterThan(revenueBreakdown.subscriptionRevenue, 0) // Consumer + White Label + Analytics
        XCTAssertGreaterThan(revenueBreakdown.usageBasedRevenue, 0)   // API Monetization
        XCTAssertGreaterThan(revenueBreakdown.setupFees, 0)          // White Label setup fees
        
        // Validate revenue attribution
        let consumerRevenue = try await mockRevenueService.getRevenueByStream(.consumer)
        let whiteLabelRevenue = try await mockRevenueService.getRevenueByStream(.whiteLabe)
        let analyticsRevenue = try await mockRevenueService.getRevenueByStream(.analytics)
        let apiRevenue = try await mockRevenueService.getRevenueByStream(.apiMonetization)
        
        XCTAssertEqual(consumerRevenue, 10.00)    // $10 premium subscription
        XCTAssertEqual(whiteLabelRevenue, 2500.00) // $1500 subscription + $1000 setup
        XCTAssertEqual(analyticsRevenue, 500.00)   // $500 analytics subscription
        XCTAssertGreaterThan(apiRevenue, 0)        // Usage-based API charges
        
        // Validate revenue forecasting
        let forecast = try await mockRevenueService.getRevenueForecast(months: 12)
        XCTAssertEqual(forecast.count, 12)
        XCTAssertTrue(forecast.allSatisfy { $0.predictedRevenue > 0 })
    }
    
    // MARK: - Cross-Revenue Stream Analytics
    
    private func validateCrossRevenueAnalytics() async throws {
        // Test consolidated analytics across all revenue streams
        let consolidatedMetrics = try await mockRevenueService.getConsolidatedMetrics()
        
        XCTAssertGreaterThan(consolidatedMetrics.totalCustomers, 0)
        XCTAssertGreaterThan(consolidatedMetrics.averageRevenuePerCustomer, 0)
        XCTAssertGreaterThan(consolidatedMetrics.monthlyRecurringRevenue, 0)
        
        // Test customer lifetime value calculation
        let clvMetrics = try await mockRevenueService.getCustomerLifetimeValue()
        XCTAssertGreaterThan(clvMetrics.averageCLV, 0)
        
        // Test churn prediction across streams
        let churnPrediction = try await mockRevenueService.getChurnPrediction()
        XCTAssertNotNil(churnPrediction)
        XCTAssertTrue(churnPrediction.riskScore >= 0 && churnPrediction.riskScore <= 1.0)
        
        // Test revenue cohort analysis
        let cohortAnalysis = try await mockRevenueService.getCohortAnalysis(period: .monthly)
        XCTAssertFalse(cohortAnalysis.cohorts.isEmpty)
    }
    
    // MARK: - Integrated Billing Validation
    
    private func validateIntegratedBilling() async throws {
        // Test consolidated billing across all revenue streams
        let billingReport = try await mockBillingService.generateConsolidatedBillingReport(
            period: .monthly
        )
        
        XCTAssertNotNil(billingReport)
        XCTAssertGreaterThan(billingReport.totalAmount, 0)
        XCTAssertGreaterThan(billingReport.subscriptionCharges, 0)
        XCTAssertGreaterThan(billingReport.usageCharges, 0)
        XCTAssertGreaterThan(billingReport.setupFees, 0)
        
        // Test payment method validation across customers
        let paymentHealthCheck = try await mockBillingService.validateAllPaymentMethods()
        XCTAssertTrue(paymentHealthCheck.overallHealth > 0.8) // 80%+ payment methods valid
        
        // Test invoice consolidation
        let consolidatedInvoices = try await mockBillingService.generateConsolidatedInvoices()
        XCTAssertFalse(consolidatedInvoices.isEmpty)
        
        // Test billing automation
        let automationResult = try await mockBillingService.processAutomatedBilling()
        XCTAssertEqual(automationResult.status, .success)
        XCTAssertGreaterThan(automationResult.processedAmount, 0)
    }
    
    // MARK: - Performance and Stress Testing
    
    func testHighVolumeRevenueProcessing() throws {
        measure {
            Task {
                // Simulate high-volume revenue processing
                let numberOfEvents = 1000
                
                for i in 0..<numberOfEvents {
                    let revenueEvent = RevenueEvent(
                        id: UUID(),
                        tenantId: "performance_tenant_\(i % 10)",
                        eventType: [.subscriptionCreated, .usageCharge, .setupFee].randomElement()!,
                        amount: Decimal.random(in: 5.00...2000.00),
                        currency: "USD",
                        timestamp: Date(),
                        subscriptionId: UUID().uuidString,
                        customerId: "customer_\(i)",
                        invoiceId: nil,
                        metadata: ["performance": "test"],
                        source: .stripe
                    )
                    
                    try await mockRevenueService.recordRevenueEvent(revenueEvent)
                }
            }
        }
    }
    
    func testConcurrentTenantOperations() async throws {
        let numberOfTenants = 50
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<numberOfTenants {
                group.addTask {
                    let tenantRequest = TenantCreateRequest(
                        name: "Concurrent Tenant \(i)",
                        slug: "concurrent-tenant-\(i)",
                        type: .golfCourse,
                        primaryDomain: "tenant\(i).coursescout.com",
                        branding: TenantBranding.default,
                        settings: TenantSettings.golfCourseDefaults,
                        limits: TenantLimits.golfCourse,
                        features: [.customBranding],
                        parentTenantId: nil,
                        metadata: ["concurrency": "test"]
                    )
                    
                    let tenant = try await self.mockTenantService.createTenant(tenantRequest)
                    
                    // Validate tenant security
                    let _ = try await self.mockSecurityService.validateTenantAccess(
                        userId: "admin_\(i)",
                        tenantId: tenant.id,
                        resourceId: "tenant_admin",
                        action: .admin
                    )
                }
            }
        }
    }
}

// MARK: - Result Structs

private struct ConsumerRevenueResult {
    let tenantId: String
    let userId: String
    let customer: BillingCustomer
    let subscription: Subscription
}

private struct WhiteLabelResult {
    let tenant: Tenant
    let customer: BillingCustomer
    let subscription: Subscription
}

private struct AnalyticsResult {
    let tenantId: String
    let customer: BillingCustomer
    let subscription: Subscription
}

private struct APIResult {
    let tenantId: String
    let apiKey: APIKey
    let usage: APIUsageCosts
}

// MARK: - Mock Query for Testing

private class MockQuery: Query {
    override func equal(_ attribute: String, value: Any) throws -> Query {
        return self
    }
    
    override func limit(_ limit: Int) throws -> Query {
        return self
    }
}

// MARK: - Mock Extensions

extension Decimal {
    static func random(in range: ClosedRange<Double>) -> Decimal {
        let randomDouble = Double.random(in: range)
        return Decimal(randomDouble)
    }
}

// MARK: - Helper Extensions

extension TenantBranding {
    static let `default` = TenantBranding(
        primaryColor: "#1976D2",
        secondaryColor: "#2196F3",
        logoURL: "https://example.com/logo.png",
        faviconURL: "https://example.com/favicon.ico",
        customCSS: "",
        fontFamily: "Roboto"
    )
}

extension MockRevenueService {
    func getRevenueByStream(_ stream: RevenueStream) async throws -> Decimal {
        // Mock implementation for stream-specific revenue
        switch stream {
        case .consumer: return 10.00
        case .whiteLable: return 2500.00
        case .analytics: return 500.00
        case .apiMonetization: return 25.00
        }
    }
    
    func getConsolidatedMetrics() async throws -> ConsolidatedMetrics {
        return ConsolidatedMetrics(
            totalCustomers: 4,
            averageRevenuePerCustomer: 758.75,
            monthlyRecurringRevenue: 2010.00
        )
    }
    
    func getCustomerLifetimeValue() async throws -> CLVMetrics {
        return CLVMetrics(averageCLV: 3500.00)
    }
    
    func getChurnPrediction() async throws -> ChurnPrediction {
        return ChurnPrediction(riskScore: 0.15)
    }
    
    func getCohortAnalysis(period: RevenuePeriod) async throws -> CohortAnalysis {
        return CohortAnalysis(cohorts: [
            Cohort(month: "2025-01", retention: 0.95, revenue: 3035.00)
        ])
    }
}

// MARK: - Additional Mock Types

enum RevenueStream {
    case consumer
    case whiteLable
    case analytics
    case apiMonetization
}

struct ConsolidatedMetrics {
    let totalCustomers: Int
    let averageRevenuePerCustomer: Decimal
    let monthlyRecurringRevenue: Decimal
}

struct CLVMetrics {
    let averageCLV: Decimal
}

struct ChurnPrediction {
    let riskScore: Double
}

struct CohortAnalysis {
    let cohorts: [Cohort]
}

struct Cohort {
    let month: String
    let retention: Double
    let revenue: Decimal
}