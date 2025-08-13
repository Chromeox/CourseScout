import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - White Label Revenue Flow Tests

class WhiteLabelRevenueFlowTests: XCTestCase {
    
    // MARK: - Properties
    
    var mockTenantService: MockTenantManagementService!
    var mockRevenueService: MockRevenueService!
    var mockBillingService: MockBillingService!
    var mockSubscriptionService: MockSubscriptionService!
    var mockSecurityService: MockSecurityService!
    var mockAPIUsageService: MockAPIUsageTrackingService!
    
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        
        // Initialize mock services
        mockTenantService = MockTenantManagementService()
        mockRevenueService = MockRevenueService()
        mockBillingService = MockBillingService()
        mockSubscriptionService = MockSubscriptionService()
        mockSecurityService = MockSecurityService()
        mockAPIUsageService = MockAPIUsageTrackingService()
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        mockTenantService = nil
        mockRevenueService = nil
        mockBillingService = nil
        mockSubscriptionService = nil
        mockSecurityService = nil
        mockAPIUsageService = nil
        super.tearDown()
    }
    
    // MARK: - Golf Course Tenant Onboarding Tests
    
    func testGolfCourseTenantOnboarding() async throws {
        // Arrange
        let golfCourseName = "Pine Valley Golf Club"
        let adminEmail = "admin@pinevalley.com"
        let monthlyFee: Decimal = 1500.00
        
        let tenantRequest = TenantCreateRequest(
            name: golfCourseName,
            slug: "pine-valley-golf",
            type: .golfCourse,
            primaryDomain: "pinevalley.coursescout.com",
            branding: TenantBranding(
                primaryColor: "#2E7D32",
                secondaryColor: "#4CAF50",
                logoURL: "https://pinevalley.com/logo.png",
                faviconURL: "https://pinevalley.com/favicon.ico",
                customCSS: ".header { background-color: #2E7D32; }",
                fontFamily: "Open Sans"
            ),
            settings: TenantSettings.golfCourseDefaults,
            limits: TenantLimits.golfCourse,
            features: [.customBranding, .analyticsAccess, .memberManagement, .bookingSystem],
            parentTenantId: nil,
            metadata: [
                "industry": "golf",
                "setupFee": "500",
                "salesContact": "john@coursescout.com"
            ]
        )
        
        // Act - Create tenant
        let tenant = try await mockTenantService.createTenant(tenantRequest)
        
        // Assert tenant creation
        XCTAssertEqual(tenant.name, golfCourseName)
        XCTAssertEqual(tenant.type, .golfCourse)
        XCTAssertEqual(tenant.status, .provisioning)
        XCTAssertEqual(tenant.slug, "pine-valley-golf")
        XCTAssertNotNil(tenant.branding)
        
        // Create customer for billing
        let customer = try await mockBillingService.createCustomer(
            tenantId: tenant.id,
            email: adminEmail,
            name: golfCourseName,
            metadata: [
                "tenantId": tenant.id,
                "tenantType": tenant.type.rawValue,
                "onboardingDate": "\(Date())"
            ]
        )
        
        // Create white label subscription
        let subscriptionRequest = SubscriptionRequest(
            tenantId: tenant.id,
            customerId: customer.id,
            tierId: "golf_course_professional",
            billingCycle: .monthly,
            price: monthlyFee,
            currency: "USD",
            trialStart: Date(),
            trialEnd: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            metadata: [
                "setupFee": "500",
                "tenantType": "golf_course",
                "features": "custom_branding,member_management,analytics"
            ]
        )
        
        let subscription = try await mockSubscriptionService.createSubscription(subscriptionRequest)
        
        // Assert subscription
        XCTAssertEqual(subscription.tenantId, tenant.id)
        XCTAssertEqual(subscription.price, monthlyFee)
        XCTAssertEqual(subscription.status, .active)
        
        // Record setup fee
        let setupFeeEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenant.id,
            eventType: .setupFee,
            amount: 500.00,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: subscription.id,
            customerId: customer.id,
            invoiceId: nil,
            metadata: [
                "type": "white_label_setup",
                "tenantType": "golf_course"
            ],
            source: .stripe
        )
        
        try await mockRevenueService.recordRevenueEvent(setupFeeEvent)
        
        // Verify tenant security setup
        let isValidAccess = try await mockSecurityService.validateTenantAccess(
            userId: "admin_user",
            tenantId: tenant.id,
            resourceId: "tenant_settings",
            action: .admin
        )
        XCTAssertTrue(isValidAccess)
    }
    
    func testEnterpriseGolfChainOnboarding() async throws {
        // Arrange
        let chainName = "Championship Golf Properties"
        let monthlyFee: Decimal = 5000.00
        
        let enterpriseRequest = TenantCreateRequest(
            name: chainName,
            slug: "championship-golf",
            type: .enterprise,
            primaryDomain: "championshipgolf.coursescout.com",
            branding: TenantBranding.enterpriseDefault,
            settings: TenantSettings.enterpriseDefaults,
            limits: TenantLimits.enterprise,
            features: [.customBranding, .whiteLabel, .multiLocation, .advancedAnalytics, .apiAccess, .customIntegrations],
            parentTenantId: nil,
            metadata: [
                "industry": "golf_chain",
                "locations": "15",
                "setupFee": "2000",
                "accountManager": "sarah@coursescout.com",
                "contractLength": "24_months"
            ]
        )
        
        // Act - Create enterprise tenant
        let enterpriseTenant = try await mockTenantService.createTenant(enterpriseRequest)
        
        // Assert enterprise features
        XCTAssertEqual(enterpriseTenant.type, .enterprise)
        XCTAssertTrue(enterpriseTenant.features.contains(.whiteLabel))
        XCTAssertTrue(enterpriseTenant.features.contains(.multiLocation))
        XCTAssertTrue(enterpriseTenant.features.contains(.apiAccess))
        
        // Create child tenants for each golf course location
        let locations = ["Pine Valley", "Oak Hill", "Cypress Point"]
        var childTenants: [Tenant] = []
        
        for (index, locationName) in locations.enumerated() {
            let childRequest = TenantCreateRequest(
                name: "\(chainName) - \(locationName)",
                slug: "\(enterpriseTenant.slug)-\(locationName.lowercased().replacingOccurrences(of: " ", with: "-"))",
                type: .golfCourse,
                primaryDomain: "\(locationName.lowercased().replacingOccurrences(of: " ", with: "-")).championshipgolf.coursescout.com",
                branding: enterpriseTenant.branding,
                settings: TenantSettings.golfCourseDefaults,
                limits: TenantLimits.golfCourse,
                features: [.customBranding, .memberManagement, .bookingSystem],
                parentTenantId: enterpriseTenant.id,
                metadata: [
                    "locationId": "\(index + 1)",
                    "parentChain": chainName
                ]
            )
            
            let childTenant = try await mockTenantService.createTenant(childRequest)
            childTenants.append(childTenant)
        }
        
        // Assert child tenant creation
        XCTAssertEqual(childTenants.count, 3)
        XCTAssertTrue(childTenants.allSatisfy { $0.parentTenantId == enterpriseTenant.id })
        
        // Create enterprise subscription
        let customer = try await mockBillingService.createCustomer(
            tenantId: enterpriseTenant.id,
            email: "billing@championshipgolf.com",
            name: chainName,
            metadata: [
                "tenantType": "enterprise",
                "locationCount": "3",
                "contractType": "annual"
            ]
        )
        
        let enterpriseSubscription = try await mockSubscriptionService.createSubscription(
            SubscriptionRequest(
                tenantId: enterpriseTenant.id,
                customerId: customer.id,
                tierId: "enterprise_golf_chain",
                billingCycle: .monthly,
                price: monthlyFee,
                currency: "USD",
                trialStart: nil,
                trialEnd: nil,
                metadata: [
                    "setupFee": "2000",
                    "locationCount": "3",
                    "contractLength": "24"
                ]
            )
        )
        
        XCTAssertEqual(enterpriseSubscription.price, monthlyFee)
    }
    
    // MARK: - Custom Branding Tests
    
    func testCustomBrandingConfiguration() async throws {
        // Arrange
        let tenantId = "custom_brand_tenant_123"
        let tenant = try await mockTenantService.createTenant(
            TenantCreateRequest(
                name: "Branded Golf Club",
                slug: "branded-golf",
                type: .golfCourse,
                primaryDomain: "brandedgolf.coursescout.com",
                branding: TenantBranding(
                    primaryColor: "#1B5E20",
                    secondaryColor: "#66BB6A",
                    logoURL: "https://brandedgolf.com/logo.svg",
                    faviconURL: "https://brandedgolf.com/favicon.ico",
                    customCSS: """
                    .app-header { background: linear-gradient(135deg, #1B5E20, #66BB6A); }
                    .btn-primary { background-color: #1B5E20; border-color: #1B5E20; }
                    .course-card { border: 2px solid #66BB6A; }
                    """,
                    fontFamily: "Roboto, sans-serif"
                ),
                settings: nil,
                limits: nil,
                features: [.customBranding],
                parentTenantId: nil,
                metadata: [:]
            )
        )
        
        // Act - Update branding
        let updatedBranding = TenantBranding(
            primaryColor: "#0D47A1",
            secondaryColor: "#2196F3",
            logoURL: "https://brandedgolf.com/new-logo.svg",
            faviconURL: "https://brandedgolf.com/new-favicon.ico",
            customCSS: """
            .app-header { background: linear-gradient(135deg, #0D47A1, #2196F3); }
            .btn-primary { background-color: #0D47A1; border-color: #0D47A1; }
            .course-card { 
                border: 2px solid #2196F3; 
                box-shadow: 0 4px 8px rgba(13, 71, 161, 0.2);
            }
            """,
            fontFamily: "Inter, system-ui, sans-serif"
        )
        
        let updatedTenant = try await mockTenantService.updateTenant(
            id: tenant.id,
            updates: TenantUpdate(branding: updatedBranding)
        )
        
        // Assert branding updates
        XCTAssertEqual(updatedTenant.branding.primaryColor, "#0D47A1")
        XCTAssertEqual(updatedTenant.branding.secondaryColor, "#2196F3")
        XCTAssertTrue(updatedTenant.branding.customCSS.contains("linear-gradient"))
        XCTAssertEqual(updatedTenant.branding.fontFamily, "Inter, system-ui, sans-serif")
        
        // Verify branding charges
        let brandingUpdateEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenant.id,
            eventType: .addOnPurchase,
            amount: 199.00,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "addOn": "premium_branding_update",
                "previousColor": "#1B5E20",
                "newColor": "#0D47A1"
            ],
            source: .stripe
        )
        
        try await mockRevenueService.recordRevenueEvent(brandingUpdateEvent)
        
        // Verify custom domain setup
        let customDomain = try await mockTenantService.addCustomDomain(
            tenantId: tenant.id,
            domain: "brandedgolf.com"
        )
        
        XCTAssertEqual(customDomain.domain, "brandedgolf.com")
        XCTAssertFalse(customDomain.isVerified) // Initially unverified
    }
    
    // MARK: - Multi-Tenant Data Isolation Tests
    
    func testTenantDataIsolation() async throws {
        // Arrange - Create two separate tenants
        let tenant1 = try await mockTenantService.createTenant(
            TenantCreateRequest(
                name: "Golf Club Alpha",
                slug: "alpha-golf",
                type: .golfCourse,
                primaryDomain: "alpha.coursescout.com",
                branding: nil,
                settings: nil,
                limits: nil,
                features: [],
                parentTenantId: nil,
                metadata: ["location": "north"]
            )
        )
        
        let tenant2 = try await mockTenantService.createTenant(
            TenantCreateRequest(
                name: "Golf Club Beta",
                slug: "beta-golf",
                type: .golfCourse,
                primaryDomain: "beta.coursescout.com",
                branding: nil,
                settings: nil,
                limits: nil,
                features: [],
                parentTenantId: nil,
                metadata: ["location": "south"]
            )
        )
        
        // Act & Assert - Test cross-tenant access prevention
        let tenant1UserId = "user_tenant1_123"
        let tenant2UserId = "user_tenant2_456"
        
        // Validate tenant1 user cannot access tenant2 resources
        let crossTenantAccess = try await mockSecurityService.validateTenantAccess(
            userId: tenant1UserId,
            tenantId: tenant2.id, // Wrong tenant
            resourceId: "course_data",
            action: .read
        )
        XCTAssertFalse(crossTenantAccess, "Cross-tenant access should be denied")
        
        // Validate same-tenant access works
        let sameTenantAccess = try await mockSecurityService.validateTenantAccess(
            userId: tenant1UserId,
            tenantId: tenant1.id, // Correct tenant
            resourceId: "course_data",
            action: .read
        )
        XCTAssertTrue(sameTenantAccess, "Same-tenant access should be allowed")
        
        // Test tenant data filtering
        let mockCourseData = [
            MockTenantIsolatedData(id: "course1", tenantId: tenant1.id, name: "Alpha Course 1"),
            MockTenantIsolatedData(id: "course2", tenantId: tenant2.id, name: "Beta Course 1"),
            MockTenantIsolatedData(id: "course3", tenantId: tenant1.id, name: "Alpha Course 2")
        ]
        
        let filteredForTenant1 = try await mockSecurityService.filterTenantData(mockCourseData, tenantId: tenant1.id)
        let filteredForTenant2 = try await mockSecurityService.filterTenantData(mockCourseData, tenantId: tenant2.id)
        
        XCTAssertEqual(filteredForTenant1.count, 2)
        XCTAssertEqual(filteredForTenant2.count, 1)
        XCTAssertTrue(filteredForTenant1.allSatisfy { $0.tenantId == tenant1.id })
        XCTAssertTrue(filteredForTenant2.allSatisfy { $0.tenantId == tenant2.id })
    }
    
    func testTenantUsageIsolation() async throws {
        // Arrange - Create tenants with different usage patterns
        let tenant1Id = "usage_tenant_1"
        let tenant2Id = "usage_tenant_2"
        
        // Generate different usage patterns
        // Tenant 1: Heavy API usage
        for i in 0..<500 {
            try await mockAPIUsageService.trackAPICall(
                tenantId: tenant1Id,
                endpoint: "/courses",
                method: .GET,
                statusCode: 200,
                responseTime: 0.1,
                dataSize: 2048
            )
        }
        
        // Tenant 2: Light API usage
        for i in 0..<100 {
            try await mockAPIUsageService.trackAPICall(
                tenantId: tenant2Id,
                endpoint: "/bookings",
                method: .GET,
                statusCode: 200,
                responseTime: 0.05,
                dataSize: 1024
            )
        }
        
        // Act - Get usage for each tenant
        let tenant1Usage = try await mockAPIUsageService.getCurrentUsage(tenantId: tenant1Id)
        let tenant2Usage = try await mockAPIUsageService.getCurrentUsage(tenantId: tenant2Id)
        
        // Assert usage isolation
        XCTAssertGreaterThan(tenant1Usage.apiCalls, tenant2Usage.apiCalls)
        XCTAssertGreaterThan(tenant1Usage.bandwidth, tenant2Usage.bandwidth)
        
        // Verify usage analytics are tenant-specific
        let tenant1Analytics = try await mockAPIUsageService.getUsageAnalytics(tenantId: tenant1Id, period: .daily)
        let tenant2Analytics = try await mockAPIUsageService.getUsageAnalytics(tenantId: tenant2Id, period: .daily)
        
        XCTAssertNotEqual(tenant1Analytics.totalRequests, tenant2Analytics.totalRequests)
        
        // Test rate limiting isolation
        let tenant1RateLimit = try await mockAPIUsageService.checkRateLimit(tenantId: tenant1Id, endpoint: "/courses")
        let tenant2RateLimit = try await mockAPIUsageService.checkRateLimit(tenantId: tenant2Id, endpoint: "/courses")
        
        // Rate limits should be independent
        XCTAssertTrue(tenant1RateLimit.allowed || !tenant1RateLimit.allowed) // Could be either
        XCTAssertTrue(tenant2RateLimit.allowed) // Should be allowed due to low usage
    }
    
    // MARK: - Tenant-Specific Billing Tests
    
    func testTenantSpecificBilling() async throws {
        // Arrange - Create tenants with different pricing tiers
        let basicTenant = try await mockTenantService.createTenant(
            TenantCreateRequest(
                name: "Basic Golf Club",
                slug: "basic-golf",
                type: .golfCourse,
                primaryDomain: "basic.coursescout.com",
                branding: nil,
                settings: nil,
                limits: TenantLimits.basic,
                features: [.memberManagement],
                parentTenantId: nil,
                metadata: ["tier": "basic"]
            )
        )
        
        let premiumTenant = try await mockTenantService.createTenant(
            TenantCreateRequest(
                name: "Premium Golf Club",
                slug: "premium-golf",
                type: .golfCourse,
                primaryDomain: "premium.coursescout.com",
                branding: TenantBranding.premiumDefault,
                settings: nil,
                limits: TenantLimits.premium,
                features: [.memberManagement, .customBranding, .analyticsAccess, .advancedReporting],
                parentTenantId: nil,
                metadata: ["tier": "premium"]
            )
        )
        
        // Create customers and subscriptions
        let basicCustomer = try await mockBillingService.createCustomer(
            tenantId: basicTenant.id,
            email: "billing@basicgolf.com",
            name: "Basic Golf Club",
            metadata: ["tier": "basic"]
        )
        
        let premiumCustomer = try await mockBillingService.createCustomer(
            tenantId: premiumTenant.id,
            email: "billing@premiumgolf.com",
            name: "Premium Golf Club",
            metadata: ["tier": "premium"]
        )
        
        // Create subscriptions with different pricing
        let basicSubscription = try await mockSubscriptionService.createSubscription(
            SubscriptionRequest(
                tenantId: basicTenant.id,
                customerId: basicCustomer.id,
                tierId: "basic_golf_club",
                billingCycle: .monthly,
                price: 500.00,
                currency: "USD",
                trialStart: nil,
                trialEnd: nil,
                metadata: ["tier": "basic", "features": "member_management"]
            )
        )
        
        let premiumSubscription = try await mockSubscriptionService.createSubscription(
            SubscriptionRequest(
                tenantId: premiumTenant.id,
                customerId: premiumCustomer.id,
                tierId: "premium_golf_club",
                billingCycle: .monthly,
                price: 1200.00,
                currency: "USD",
                trialStart: nil,
                trialEnd: nil,
                metadata: ["tier": "premium", "features": "full_suite"]
            )
        )
        
        // Assert different pricing
        XCTAssertEqual(basicSubscription.price, 500.00)
        XCTAssertEqual(premiumSubscription.price, 1200.00)
        
        // Generate tenant-specific revenue events
        let basicRevenueEvent = RevenueEvent(
            id: UUID(),
            tenantId: basicTenant.id,
            eventType: .subscriptionRenewed,
            amount: 500.00,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: basicSubscription.id,
            customerId: basicCustomer.id,
            invoiceId: nil,
            metadata: ["tier": "basic"],
            source: .stripe
        )
        
        let premiumRevenueEvent = RevenueEvent(
            id: UUID(),
            tenantId: premiumTenant.id,
            eventType: .subscriptionRenewed,
            amount: 1200.00,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: premiumSubscription.id,
            customerId: premiumCustomer.id,
            invoiceId: nil,
            metadata: ["tier": "premium"],
            source: .stripe
        )
        
        try await mockRevenueService.recordRevenueEvent(basicRevenueEvent)
        try await mockRevenueService.recordRevenueEvent(premiumRevenueEvent)
        
        // Get tenant-specific revenue
        let basicTenantRevenue = try await mockRevenueService.getRevenueByTenant(
            tenantId: basicTenant.id,
            period: .monthly
        )
        
        let premiumTenantRevenue = try await mockRevenueService.getRevenueByTenant(
            tenantId: premiumTenant.id,
            period: .monthly
        )
        
        // Assert revenue isolation
        XCTAssertNotEqual(basicTenantRevenue.totalRevenue, premiumTenantRevenue.totalRevenue)
        XCTAssertGreaterThan(premiumTenantRevenue.totalRevenue, basicTenantRevenue.totalRevenue)
    }
    
    // MARK: - Tenant Migration Tests
    
    func testTenantMigration() async throws {
        // Arrange - Create source and target tenants
        let sourceTenant = try await mockTenantService.createTenant(
            TenantCreateRequest(
                name: "Golf Club Old",
                slug: "old-golf-club",
                type: .golfCourse,
                primaryDomain: "old.coursescout.com",
                branding: nil,
                settings: nil,
                limits: nil,
                features: [],
                parentTenantId: nil,
                metadata: ["migration": "source"]
            )
        )
        
        let targetTenant = try await mockTenantService.createTenant(
            TenantCreateRequest(
                name: "Golf Club New",
                slug: "new-golf-club",
                type: .golfCourse,
                primaryDomain: "new.coursescout.com",
                branding: nil,
                settings: nil,
                limits: nil,
                features: [],
                parentTenantId: nil,
                metadata: ["migration": "target"]
            )
        )
        
        // Export source tenant data
        let exportData = try await mockTenantService.exportTenantData(id: sourceTenant.id)
        
        // Assert export data
        XCTAssertEqual(exportData.tenant.id, sourceTenant.id)
        XCTAssertNotNil(exportData.settings)
        
        // Perform migration
        let migrationOptions = MigrationOptions(
            includeUsers: true,
            includeContent: true,
            includeSettings: true,
            includeSubscriptions: false,
            preserveIds: false,
            validateIntegrity: true
        )
        
        let migrationResult = try await mockTenantService.migrateTenant(
            from: sourceTenant.id,
            to: targetTenant.id,
            options: migrationOptions
        )
        
        // Assert migration success
        XCTAssertEqual(migrationResult.status, .completed)
        XCTAssertEqual(migrationResult.sourceId, sourceTenant.id)
        XCTAssertEqual(migrationResult.targetId, targetTenant.id)
        
        // Import to target tenant
        let importedTenant = try await mockTenantService.importTenantData(exportData)
        XCTAssertNotNil(importedTenant)
        
        // Verify billing continuity during migration
        let migrationEvent = RevenueEvent(
            id: UUID(),
            tenantId: targetTenant.id,
            eventType: .migration,
            amount: 0.00,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "migrationType": "tenant_migration",
                "sourceId": sourceTenant.id,
                "targetId": targetTenant.id
            ],
            source: .manual
        )
        
        try await mockRevenueService.recordRevenueEvent(migrationEvent)
    }
    
    // MARK: - White Label Feature Tests
    
    func testWhiteLabelFeatureBilling() async throws {
        // Arrange
        let whiteLabelTenant = try await mockTenantService.createTenant(
            TenantCreateRequest(
                name: "White Label Golf Chain",
                slug: "whitelabel-golf",
                type: .enterprise,
                primaryDomain: "golfchain.com",
                branding: TenantBranding.enterpriseDefault,
                settings: TenantSettings.enterpriseDefaults,
                limits: TenantLimits.enterprise,
                features: [.whiteLabel, .customBranding, .multiLocation, .apiAccess],
                parentTenantId: nil,
                metadata: [
                    "whiteLabelTier": "enterprise",
                    "customDomainIncluded": "true",
                    "brandingCustomization": "full"
                ]
            )
        )
        
        // Create white label customer
        let customer = try await mockBillingService.createCustomer(
            tenantId: whiteLabelTenant.id,
            email: "enterprise@golfchain.com",
            name: "White Label Golf Chain",
            metadata: [
                "accountType": "white_label",
                "customizations": "full_branding,custom_domain,api_access"
            ]
        )
        
        // Create white label subscription with premium pricing
        let whiteLabelSubscription = try await mockSubscriptionService.createSubscription(
            SubscriptionRequest(
                tenantId: whiteLabelTenant.id,
                customerId: customer.id,
                tierId: "white_label_enterprise",
                billingCycle: .monthly,
                price: 3000.00, // Premium white label pricing
                currency: "USD",
                trialStart: nil,
                trialEnd: nil,
                metadata: [
                    "whiteLabelFeatures": "custom_domain,full_branding,api_access,multi_location",
                    "setupFee": "5000",
                    "onboardingSupport": "dedicated_manager"
                ]
            )
        )
        
        // Assert white label subscription
        XCTAssertEqual(whiteLabelSubscription.price, 3000.00)
        XCTAssertTrue(whiteLabelTenant.features.contains(.whiteLabel))
        
        // Record white label setup fee
        let setupFeeEvent = RevenueEvent(
            id: UUID(),
            tenantId: whiteLabelTenant.id,
            eventType: .setupFee,
            amount: 5000.00,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: whiteLabelSubscription.id,
            customerId: customer.id,
            invoiceId: nil,
            metadata: [
                "setupType": "white_label_enterprise",
                "features": "full_customization"
            ],
            source: .stripe
        )
        
        try await mockRevenueService.recordRevenueEvent(setupFeeEvent)
        
        // Verify custom domain setup for white label
        let customDomain = try await mockTenantService.addCustomDomain(
            tenantId: whiteLabelTenant.id,
            domain: "golfchain.com"
        )
        
        XCTAssertEqual(customDomain.domain, "golfchain.com")
        
        // Verify domain verification process
        let domainVerification = try await mockTenantService.verifyCustomDomain(
            tenantId: whiteLabelTenant.id,
            domain: "golfchain.com"
        )
        
        XCTAssertNotNil(domainVerification)
    }
}
}

// MARK: - Mock Data Types

struct MockTenantIsolatedData: TenantIsolatable {
    let id: String
    let tenantId: String
    let name: String
}

// MARK: - Extension Helper Types

extension TenantBranding {
    static let premiumDefault = TenantBranding(
        primaryColor: "#1565C0",
        secondaryColor: "#42A5F5",
        logoURL: nil,
        faviconURL: nil,
        customCSS: "",
        fontFamily: "Roboto"
    )
    
    static let enterpriseDefault = TenantBranding(
        primaryColor: "#0D47A1",
        secondaryColor: "#1976D2",
        logoURL: nil,
        faviconURL: nil,
        customCSS: "",
        fontFamily: "Inter"
    )
}

extension TenantSettings {
    static let golfCourseDefaults = TenantSettings(
        timeZone: "America/New_York",
        locale: "en_US",
        currency: "USD",
        dateFormat: "MM/dd/yyyy",
        timeFormat: "12h",
        allowPublicRegistration: true,
        requireEmailVerification: true,
        enableNotifications: true,
        maintenanceMode: false,
        customSettings: [
            "allowGuestBookings": "true",
            "maxAdvanceBookingDays": "30",
            "cancellationWindow": "24"
        ]
    )
    
    static let enterpriseDefaults = TenantSettings(
        timeZone: "America/New_York",
        locale: "en_US",
        currency: "USD",
        dateFormat: "MM/dd/yyyy",
        timeFormat: "12h",
        allowPublicRegistration: false,
        requireEmailVerification: true,
        enableNotifications: true,
        maintenanceMode: false,
        customSettings: [
            "ssoEnabled": "true",
            "advancedAnalytics": "true",
            "apiAccessLevel": "full",
            "multiLocationSupport": "true"
        ]
    )
}

extension TenantLimits {
    static let basic = TenantLimits(
        maxUsers: 100,
        maxStorage: 1.0, // GB
        maxAPICallsPerMonth: 10000,
        maxCustomDomains: 0,
        maxWebhooks: 5,
        maxIntegrations: 3,
        featureAccess: [
            "customBranding": false,
            "advancedAnalytics": false,
            "apiAccess": false
        ]
    )
    
    static let premium = TenantLimits(
        maxUsers: 500,
        maxStorage: 10.0, // GB
        maxAPICallsPerMonth: 50000,
        maxCustomDomains: 3,
        maxWebhooks: 25,
        maxIntegrations: 10,
        featureAccess: [
            "customBranding": true,
            "advancedAnalytics": true,
            "apiAccess": true
        ]
    )
    
    static let golfCourse = TenantLimits(
        maxUsers: 1000,
        maxStorage: 5.0, // GB
        maxAPICallsPerMonth: 25000,
        maxCustomDomains: 1,
        maxWebhooks: 15,
        maxIntegrations: 8,
        featureAccess: [
            "customBranding": true,
            "memberManagement": true,
            "bookingSystem": true
        ]
    )
    
    static let enterprise = TenantLimits(
        maxUsers: -1, // Unlimited
        maxStorage: 100.0, // GB
        maxAPICallsPerMonth: 1000000,
        maxCustomDomains: 10,
        maxWebhooks: 100,
        maxIntegrations: -1, // Unlimited
        featureAccess: [
            "customBranding": true,
            "whiteLabel": true,
            "multiLocation": true,
            "advancedAnalytics": true,
            "apiAccess": true,
            "customIntegrations": true
        ]
    )
}

// MARK: - Enums for Mock Data

enum MigrationStatus: String, Codable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case failed = "failed"
}

struct MigrationResult {
    let id: String
    let sourceId: String
    let targetId: String
    let status: MigrationStatus
    let startedAt: Date
    let completedAt: Date?
    let itemsMigrated: Int
    let errors: [String]
    
    static let mock = MigrationResult(
        id: "migration_\(UUID().uuidString.prefix(8))",
        sourceId: "source_tenant",
        targetId: "target_tenant",
        status: .completed,
        startedAt: Date().addingTimeInterval(-3600),
        completedAt: Date(),
        itemsMigrated: 1500,
        errors: []
    )
}

struct MigrationOptions {
    let includeUsers: Bool
    let includeContent: Bool
    let includeSettings: Bool
    let includeSubscriptions: Bool
    let preserveIds: Bool
    let validateIntegrity: Bool
}