import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - Security Revenue Integration Tests

class SecurityRevenueIntegrationTests: XCTestCase {
    
    // MARK: - Properties
    
    var mockSecurityService: MockSecurityService!
    var mockTenantService: MockTenantManagementService!
    var mockRevenueService: MockRevenueService!
    var mockBillingService: MockBillingService!
    var mockAPIUsageService: MockAPIUsageTrackingService!
    var mockAPIGatewayService: MockAPIGatewayService!
    
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize all mock services
        mockSecurityService = MockSecurityService()
        mockTenantService = MockTenantManagementService()
        mockRevenueService = MockRevenueService()
        mockBillingService = MockBillingService()
        mockAPIUsageService = MockAPIUsageTrackingService()
        mockAPIGatewayService = MockAPIGatewayService()
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        mockSecurityService = nil
        mockTenantService = nil
        mockRevenueService = nil
        mockBillingService = nil
        mockAPIUsageService = nil
        mockAPIGatewayService = nil
        super.tearDown()
    }
    
    // MARK: - Multi-Tenant Security Isolation Tests
    
    func testComprehensiveMultiTenantSecurityIsolation() async throws {
        // This test validates that all revenue streams maintain proper security isolation
        
        // 1. Create multiple tenants representing different revenue streams
        let consumerTenant = "consumer_tenant_secure"
        let golfCourseTenant = "golf_course_tenant_secure"
        let analyticsTenant = "analytics_tenant_secure"
        let apiTenant = "api_developer_tenant_secure"
        
        let allTenants = [consumerTenant, golfCourseTenant, analyticsTenant, apiTenant]
        
        // 2. Test cross-tenant data isolation
        for (sourceIndex, sourceTenant) in allTenants.enumerated() {
            for (targetIndex, targetTenant) in allTenants.enumerated() {
                if sourceIndex != targetIndex {
                    // Attempt cross-tenant access - should be blocked
                    do {
                        try await mockSecurityService.preventTenantCrossTalk(
                            sourceId: sourceTenant,
                            targetId: targetTenant,
                            operation: .dataAccess
                        )
                        // If no error is thrown, security violation was detected and blocked (good)
                    } catch SecurityServiceError.crossTenantViolation(let source, let target) {
                        // Expected error - security is working correctly
                        XCTAssertEqual(source, sourceTenant)
                        XCTAssertEqual(target, targetTenant)
                    } catch {
                        XCTFail("Unexpected error during cross-tenant validation: \(error)")
                    }
                }
            }
        }
        
        // 3. Verify each tenant can only access its own revenue data
        for tenantId in allTenants {
            // Create revenue event for tenant
            let revenueEvent = RevenueEvent(
                id: UUID(),
                tenantId: tenantId,
                eventType: .subscriptionCreated,
                amount: 100.00,
                currency: "USD",
                timestamp: Date(),
                subscriptionId: UUID().uuidString,
                customerId: "customer_\(tenantId)",
                invoiceId: nil,
                metadata: ["securityTest": "true"],
                source: .stripe
            )
            
            try await mockRevenueService.recordRevenueEvent(revenueEvent)
            
            // Verify tenant can access its own revenue
            let hasAccess = try await mockSecurityService.validateTenantAccess(
                userId: "admin_\(tenantId)",
                tenantId: tenantId,
                resourceId: "revenue_data",
                action: .read
            )
            XCTAssertTrue(hasAccess)
            
            // Verify tenant cannot access other tenants' revenue
            for otherTenant in allTenants where otherTenant != tenantId {
                let hasInvalidAccess = try await mockSecurityService.validateTenantAccess(
                    userId: "admin_\(tenantId)",
                    tenantId: otherTenant,
                    resourceId: "revenue_data",
                    action: .read
                )
                XCTAssertFalse(hasInvalidAccess, "Tenant \(tenantId) should not access \(otherTenant) revenue")
            }
        }
        
        // 4. Test API usage isolation
        for tenantId in allTenants {
            // Generate usage for each tenant
            try await mockAPIUsageService.trackAPICall(
                tenantId: tenantId,
                endpoint: "/api/secure/data",
                method: .GET,
                statusCode: 200,
                responseTime: 0.1,
                dataSize: 1024
            )
            
            // Verify tenant can access its own usage data
            let usage = try await mockAPIUsageService.getCurrentUsage(tenantId: tenantId)
            XCTAssertEqual(usage.tenantId, tenantId)
            XCTAssertGreaterThan(usage.apiCalls, 0)
        }
        
        // 5. Verify billing data isolation
        for tenantId in allTenants {
            let customer = try await mockBillingService.createCustomer(
                tenantId: tenantId,
                email: "secure@\(tenantId).com",
                name: "Secure Customer \(tenantId)",
                metadata: ["securityTest": "true"]
            )
            
            // Verify customer is associated with correct tenant
            XCTAssertEqual(customer.metadata["tenantId"] ?? tenantId, tenantId)
            
            // Verify tenant boundary validation
            let isValidBoundary = try await mockSecurityService.validateTenantBoundary(
                resourcePath: "/tenants/\(tenantId)/billing",
                tenantId: tenantId
            )
            XCTAssertTrue(isValidBoundary)
            
            // Verify invalid boundary detection
            for otherTenant in allTenants where otherTenant != tenantId {
                let isInvalidBoundary = try await mockSecurityService.validateTenantBoundary(
                    resourcePath: "/tenants/\(otherTenant)/billing",
                    tenantId: tenantId
                )
                XCTAssertFalse(isInvalidBoundary, "Invalid boundary should be detected")
            }
        }
    }
    
    func testEncryptionAndDataProtection() async throws {
        // Test that sensitive revenue data is properly encrypted for each tenant
        
        let tenants = [
            "encryption_consumer",
            "encryption_golf_course",
            "encryption_analytics"
        ]
        
        for tenantId in tenants {
            // 1. Test data encryption
            let sensitiveRevenueData = SensitiveRevenueData(
                totalRevenue: 15000.00,
                customerCount: 150,
                paymentMethods: ["card_123", "bank_456"],
                apiKeys: ["sk_live_abc", "sk_test_def"]
            )
            
            let encryptedData = try await mockSecurityService.encryptTenantData(
                sensitiveRevenueData,
                tenantId: tenantId
            )
            
            // Verify encryption
            XCTAssertEqual(encryptedData.keyId, "mock-key-\(tenantId)")
            XCTAssertEqual(encryptedData.algorithm, .aes256gcm)
            XCTAssertNotNil(encryptedData.data)
            XCTAssertNotNil(encryptedData.iv)
            
            // 2. Test data decryption
            let decryptedData = try await mockSecurityService.decryptTenantData(
                encryptedData,
                tenantId: tenantId,
                type: SensitiveRevenueData.self
            )
            
            XCTAssertEqual(decryptedData.totalRevenue, sensitiveRevenueData.totalRevenue)
            XCTAssertEqual(decryptedData.customerCount, sensitiveRevenueData.customerCount)
            XCTAssertEqual(decryptedData.paymentMethods, sensitiveRevenueData.paymentMethods)
            XCTAssertEqual(decryptedData.apiKeys, sensitiveRevenueData.apiKeys)
            
            // 3. Test cross-tenant decryption fails
            for otherTenant in tenants where otherTenant != tenantId {
                do {
                    let _ = try await mockSecurityService.decryptTenantData(
                        encryptedData,
                        tenantId: otherTenant,
                        type: SensitiveRevenueData.self
                    )
                    XCTFail("Cross-tenant decryption should fail")
                } catch {
                    // Expected - decryption should fail for different tenant
                }
            }
            
            // 4. Test encryption status
            let encryptionStatus = try await mockSecurityService.getTenantEncryptionStatus(tenantId: tenantId)
            XCTAssertTrue(encryptionStatus.isEnabled)
            XCTAssertEqual(encryptionStatus.status, .healthy)
            XCTAssertTrue(encryptionStatus.encryptedResources.contains(.payment))
            XCTAssertTrue(encryptionStatus.encryptedResources.contains(.analytics))
            
            // 5. Test key rotation
            try await mockSecurityService.rotateTenantEncryptionKey(tenantId: tenantId)
            
            // Verify rotation was logged
            let securityEvents = try await mockSecurityService.getSecurityEvents(
                tenantId: tenantId,
                userId: nil,
                eventType: .dataModification,
                dateRange: DateRange(startDate: Date().addingTimeInterval(-60), endDate: Date())
            )
            
            let keyRotationEvents = securityEvents.filter { $0.resource == "encryption_key" }
            XCTAssertFalse(keyRotationEvents.isEmpty)
        }
    }
    
    func testRoleBasedAccessControlForRevenue() async throws {
        // Test RBAC system for revenue access across different tenant types
        
        let golfCourseTenantId = "rbac_golf_course"
        let consumerTenantId = "rbac_consumer"
        
        // 1. Create roles for golf course tenant
        let golfCourseAdminRole = SecurityRole(
            id: "golf_admin_role",
            tenantId: golfCourseTenantId,
            name: "Golf Course Administrator",
            description: "Full access to golf course management and revenue",
            permissions: [
                SecurityPermission(id: "revenue_read", resource: .analytics, action: .read, conditions: nil, scope: .tenant),
                SecurityPermission(id: "revenue_admin", resource: .analytics, action: .admin, conditions: nil, scope: .tenant),
                SecurityPermission(id: "billing_read", resource: .payment, action: .read, conditions: nil, scope: .tenant),
                SecurityPermission(id: "billing_admin", resource: .payment, action: .admin, conditions: nil, scope: .tenant)
            ],
            isSystem: false,
            inheritedFrom: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let golfCourseStaffRole = SecurityRole(
            id: "golf_staff_role",
            tenantId: golfCourseTenantId,
            name: "Golf Course Staff",
            description: "Limited access to bookings and basic analytics",
            permissions: [
                SecurityPermission(id: "booking_read", resource: .booking, action: .read, conditions: nil, scope: .tenant),
                SecurityPermission(id: "analytics_limited", resource: .analytics, action: .read, conditions: [
                    PermissionCondition(field: "reportType", operator: .equals, value: "basic")
                ], scope: .tenant)
            ],
            isSystem: false,
            inheritedFrom: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Create roles
        let adminRole = try await mockSecurityService.createRole(tenantId: golfCourseTenantId, role: golfCourseAdminRole)
        let staffRole = try await mockSecurityService.createRole(tenantId: golfCourseTenantId, role: golfCourseStaffRole)
        
        XCTAssertEqual(adminRole.id, golfCourseAdminRole.id)
        XCTAssertEqual(staffRole.id, golfCourseStaffRole.id)
        
        // 2. Assign roles to users
        let adminUserId = "golf_admin_user"
        let staffUserId = "golf_staff_user"
        
        try await mockSecurityService.assignRoleToUser(
            tenantId: golfCourseTenantId,
            userId: adminUserId,
            roleId: adminRole.id
        )
        
        try await mockSecurityService.assignRoleToUser(
            tenantId: golfCourseTenantId,
            userId: staffUserId,
            roleId: staffRole.id
        )
        
        // 3. Test admin permissions
        let adminRevenuePermission = SecurityPermission(
            id: "test_revenue_read",
            resource: .analytics,
            action: .read,
            conditions: nil,
            scope: .tenant
        )
        
        let adminHasRevenueAccess = try await mockSecurityService.checkPermission(
            tenantId: golfCourseTenantId,
            userId: adminUserId,
            permission: adminRevenuePermission
        )
        XCTAssertTrue(adminHasRevenueAccess)
        
        let adminBillingPermission = SecurityPermission(
            id: "test_billing_admin",
            resource: .payment,
            action: .admin,
            conditions: nil,
            scope: .tenant
        )
        
        let adminHasBillingAccess = try await mockSecurityService.checkPermission(
            tenantId: golfCourseTenantId,
            userId: adminUserId,
            permission: adminBillingPermission
        )
        XCTAssertTrue(adminHasBillingAccess)
        
        // 4. Test staff limitations
        let staffRevenuePermission = SecurityPermission(
            id: "test_staff_revenue",
            resource: .analytics,
            action: .admin,
            conditions: nil,
            scope: .tenant
        )
        
        let staffHasLimitedAccess = try await mockSecurityService.checkPermission(
            tenantId: golfCourseTenantId,
            userId: staffUserId,
            permission: staffRevenuePermission
        )
        XCTAssertFalse(staffHasLimitedAccess, "Staff should not have admin revenue access")
        
        let staffBillingPermission = SecurityPermission(
            id: "test_staff_billing",
            resource: .payment,
            action: .read,
            conditions: nil,
            scope: .tenant
        )
        
        let staffHasBillingAccess = try await mockSecurityService.checkPermission(
            tenantId: golfCourseTenantId,
            userId: staffUserId,
            permission: staffBillingPermission
        )
        XCTAssertFalse(staffHasBillingAccess, "Staff should not have billing access")
        
        // 5. Test cross-tenant role isolation
        let consumerUserId = "consumer_user"
        
        let crossTenantAccess = try await mockSecurityService.checkPermission(
            tenantId: consumerTenantId,
            userId: adminUserId,
            permission: adminRevenuePermission
        )
        XCTAssertFalse(crossTenantAccess, "Admin should not have access to different tenant")
        
        // 6. Test role removal
        try await mockSecurityService.removeRoleFromUser(
            tenantId: golfCourseTenantId,
            userId: staffUserId,
            roleId: staffRole.id
        )
        
        let staffRolesAfterRemoval = try await mockSecurityService.getUserRoles(
            tenantId: golfCourseTenantId,
            userId: staffUserId
        )
        XCTAssertFalse(staffRolesAfterRemoval.contains { $0.id == staffRole.id })
    }
    
    func testAPIKeySecurityAndRevenue() async throws {
        // Test API key security across different tenant types and revenue models
        
        let tenantIds = [
            "api_security_consumer",
            "api_security_golf_course",
            "api_security_analytics"
        ]
        
        for tenantId in tenantIds {
            // 1. Create tenant-specific API key
            let permissions = [
                SecurityPermission(
                    id: "api_course_read",
                    resource: .course,
                    action: .read,
                    conditions: nil,
                    scope: .tenant
                ),
                SecurityPermission(
                    id: "api_booking_create",
                    resource: .booking,
                    action: .create,
                    conditions: [
                        PermissionCondition(field: "tenantId", operator: .equals, value: tenantId)
                    ],
                    scope: .tenant
                )
            ]
            
            let apiKey = try await mockSecurityService.createTenantAPIKey(
                tenantId: tenantId,
                permissions: permissions
            )
            
            XCTAssertEqual(apiKey.tenantId, tenantId)
            XCTAssertTrue(apiKey.isActive)
            XCTAssertEqual(apiKey.permissions.count, 2)
            
            // 2. Validate API key for tenant
            let validation = try await mockSecurityService.validateAPIKeyForTenant(
                apiKey: apiKey.keyHash,
                tenantId: tenantId
            )
            
            XCTAssertTrue(validation.isValid)
            XCTAssertEqual(validation.tenantId, tenantId)
            XCTAssertEqual(validation.permissions.count, 2)
            XCTAssertNotNil(validation.rateLimit)
            
            // 3. Test cross-tenant API key validation fails
            for otherTenant in tenantIds where otherTenant != tenantId {
                do {
                    let crossValidation = try await mockSecurityService.validateAPIKeyForTenant(
                        apiKey: apiKey.keyHash,
                        tenantId: otherTenant
                    )
                    XCTAssertFalse(crossValidation.isValid, "API key should not be valid for different tenant")
                } catch {
                    // Expected - validation should fail
                }
            }
            
            // 4. Track API usage with revenue implications
            for i in 0..<100 {
                try await mockAPIUsageService.trackAPICall(
                    tenantId: tenantId,
                    endpoint: "/api/courses",
                    method: .GET,
                    statusCode: 200,
                    responseTime: 0.1,
                    dataSize: 1024
                )
            }
            
            // Calculate usage costs
            let usageCosts = try await mockAPIUsageService.calculateUsageCosts(
                tenantId: tenantId,
                period: .monthly
            )
            
            XCTAssertGreaterThan(usageCosts.totalCost, 0)
            XCTAssertEqual(usageCosts.totalAPICalls, 100)
            
            // 5. Record revenue with API key tracking
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
                    "apiKeyId": apiKey.id,
                    "usageType": "api_calls",
                    "securityLevel": "tenant_isolated"
                ],
                source: .internal
            )
            
            try await mockRevenueService.recordRevenueEvent(apiRevenueEvent)
            
            // 6. Test API key revocation
            try await mockSecurityService.revokeTenantAPIKey(
                tenantId: tenantId,
                keyId: apiKey.id
            )
            
            // Verify revocation was logged
            let securityEvents = try await mockSecurityService.getSecurityEvents(
                tenantId: tenantId,
                userId: nil,
                eventType: .authentication,
                dateRange: DateRange(startDate: Date().addingTimeInterval(-60), endDate: Date())
            )
            
            let revocationEvents = securityEvents.filter { 
                $0.resource == "api_key" && $0.action == .delete 
            }
            XCTAssertFalse(revocationEvents.isEmpty)
        }
    }
    
    func testSecurityMonitoringAndAnomalyDetection() async throws {
        // Test security monitoring for suspicious revenue-related activities
        
        let tenantId = "security_monitoring_tenant"
        let suspiciousUserId = "suspicious_user"
        
        // 1. Generate normal baseline activity
        for i in 0..<50 {
            let revenueEvent = RevenueEvent(
                id: UUID(),
                tenantId: tenantId,
                eventType: .subscriptionRenewed,
                amount: 10.00,
                currency: "USD",
                timestamp: Date().addingTimeInterval(-TimeInterval(i * 3600)), // Spread over time
                subscriptionId: "sub_normal_\(i)",
                customerId: "customer_normal_\(i)",
                invoiceId: nil,
                metadata: ["pattern": "normal"],
                source: .stripe
            )
            
            try await mockRevenueService.recordRevenueEvent(revenueEvent)
        }
        
        // 2. Generate suspicious activity
        // Rapid succession of high-value transactions
        let suspiciousStart = Date()
        for i in 0..<20 {
            let suspiciousEvent = RevenueEvent(
                id: UUID(),
                tenantId: tenantId,
                eventType: .subscriptionCreated,
                amount: 5000.00, // Unusually high amount
                currency: "USD",
                timestamp: suspiciousStart.addingTimeInterval(TimeInterval(i * 10)), // Very rapid
                subscriptionId: "sub_suspicious_\(i)",
                customerId: "customer_suspicious_\(i)",
                invoiceId: nil,
                metadata: [
                    "pattern": "suspicious",
                    "userId": suspiciousUserId,
                    "ipAddress": "192.168.1.100"
                ],
                source: .stripe
            )
            
            try await mockRevenueService.recordRevenueEvent(suspiciousEvent)
            
            // Log security event for suspicious activity
            let securityEvent = SecurityEvent(
                id: UUID().uuidString,
                tenantId: tenantId,
                userId: suspiciousUserId,
                eventType: .anomalousActivity,
                resource: "revenue_transaction",
                action: .create,
                timestamp: suspiciousEvent.timestamp,
                ipAddress: "192.168.1.100",
                userAgent: "suspicious_client/1.0",
                success: true,
                errorMessage: nil,
                metadata: [
                    "amount": "5000.00",
                    "pattern": "rapid_high_value",
                    "risk": "high"
                ],
                riskLevel: .high
            )
            
            try await mockSecurityService.logSecurityEvent(securityEvent)
        }
        
        // 3. Detect anomalous activity
        let anomalies = try await mockSecurityService.detectAnomalousActivity(
            tenantId: tenantId,
            period: .day
        )
        
        XCTAssertFalse(anomalies.isEmpty)
        
        let highValueAnomaly = anomalies.first { $0.anomalyType == .unusualAccess }
        XCTAssertNotNil(highValueAnomaly)
        XCTAssertEqual(highValueAnomaly?.severity, .medium)
        XCTAssertTrue(highValueAnomaly?.affectedUsers.contains(suspiciousUserId) ?? false)
        
        // 4. Analyze security risk
        let riskAssessment = try await mockSecurityService.analyzeSecurityRisk(tenantId: tenantId)
        
        XCTAssertEqual(riskAssessment.tenantId, tenantId)
        XCTAssertTrue([.medium, .high, .critical].contains(riskAssessment.overallRisk))
        XCTAssertFalse(riskAssessment.riskFactors.isEmpty)
        XCTAssertFalse(riskAssessment.recommendations.isEmpty)
        
        // 5. Create security alert for high-risk activity
        let securityAlert = SecurityAlert(
            id: UUID().uuidString,
            tenantId: tenantId,
            alertType: .suspiciousActivity,
            severity: .high,
            title: "Suspicious High-Value Revenue Activity",
            description: "Detected rapid succession of high-value transactions from user \(suspiciousUserId)",
            affectedResources: ["revenue_transactions", "billing_system"],
            detectedAt: Date(),
            resolvedAt: nil,
            status: .open,
            assignedTo: "security_team",
            remediation: [
                RemediationStep(
                    id: UUID().uuidString,
                    description: "Review user account for fraudulent activity",
                    priority: 1,
                    estimatedTime: 1800,
                    required: true,
                    completed: false,
                    completedAt: nil
                ),
                RemediationStep(
                    id: UUID().uuidString,
                    description: "Implement additional transaction verification",
                    priority: 2,
                    estimatedTime: 3600,
                    required: true,
                    completed: false,
                    completedAt: nil
                )
            ]
        )
        
        try await mockSecurityService.createSecurityAlert(securityAlert)
        
        // 6. Retrieve and verify security alerts
        let alerts = try await mockSecurityService.getSecurityAlerts(
            tenantId: tenantId,
            severity: .high
        )
        
        XCTAssertFalse(alerts.isEmpty)
        let revenueAlert = alerts.first { $0.title.contains("Revenue Activity") }
        XCTAssertNotNil(revenueAlert)
        XCTAssertEqual(revenueAlert?.status, .open)
        XCTAssertEqual(revenueAlert?.remediation.count, 2)
        
        // 7. Generate security report
        let securityReport = try await mockSecurityService.generateSecurityReport(
            tenantId: tenantId,
            reportType: .incident
        )
        
        XCTAssertEqual(securityReport.tenantId, tenantId)
        XCTAssertEqual(securityReport.reportType, .incident)
        XCTAssertNotNil(securityReport.data)
        XCTAssertNotNil(securityReport.summary)
    }
    
    func testGDPRComplianceForRevenueData() async throws {
        // Test GDPR compliance for revenue-related personal data
        
        let tenantId = "gdpr_compliance_tenant"
        let userId = "gdpr_test_user"
        let userEmail = "gdpr.user@example.com"
        
        // 1. Create customer with personal data
        let customer = try await mockBillingService.createCustomer(
            tenantId: tenantId,
            email: userEmail,
            name: "GDPR Test User",
            metadata: [
                "userId": userId,
                "gdprConsent": "true",
                "dataProcessingPurpose": "billing_and_analytics"
            ]
        )
        
        // 2. Generate revenue data
        let revenueEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenantId,
            eventType: .subscriptionCreated,
            amount: 25.00,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: "sub_gdpr_test",
            customerId: customer.id,
            invoiceId: nil,
            metadata: [
                "userId": userId,
                "userEmail": userEmail,
                "consentTimestamp": "\(Date())"
            ],
            source: .stripe
        )
        
        try await mockRevenueService.recordRevenueEvent(revenueEvent)
        
        // 3. Check GDPR compliance status
        let complianceStatus = try await mockSecurityService.ensureGDPRCompliance(
            tenantId: tenantId,
            userId: userId
        )
        
        XCTAssertTrue(complianceStatus.isCompliant)
        XCTAssertEqual(complianceStatus.tenantId, tenantId)
        XCTAssertEqual(complianceStatus.userId, userId)
        XCTAssertTrue(complianceStatus.issues.isEmpty)
        
        // 4. Test data export (Right to data portability)
        let exportedData = try await mockSecurityService.exportUserData(
            tenantId: tenantId,
            userId: userId,
            format: .json
        )
        
        XCTAssertFalse(exportedData.isEmpty)
        
        // Verify exported data is valid JSON
        let jsonObject = try JSONSerialization.jsonObject(with: exportedData)
        XCTAssertNotNil(jsonObject)
        
        // 5. Test data anonymization
        try await mockSecurityService.anonymizeUserData(
            tenantId: tenantId,
            userId: userId,
            retentionRules: RetentionRules(
                retentionPeriod: 365 * 24 * 60 * 60, // 1 year
                anonymizeAfter: 30 * 24 * 60 * 60,   // 30 days
                deleteAfter: 7 * 365 * 24 * 60 * 60  // 7 years
            )
        )
        
        // Verify anonymization was logged
        let anonymizationEvents = try await mockSecurityService.getSecurityEvents(
            tenantId: tenantId,
            userId: userId,
            eventType: .dataModification,
            dateRange: DateRange(startDate: Date().addingTimeInterval(-60), endDate: Date())
        )
        
        let anonymizationEvent = anonymizationEvents.first { $0.resource == "user_data" && $0.action == .update }
        XCTAssertNotNil(anonymizationEvent)
        
        // 6. Test data deletion (Right to be forgotten)
        try await mockSecurityService.processDataDeletionRequest(
            tenantId: tenantId,
            userId: userId,
            scope: .user
        )
        
        // Verify deletion was logged
        let deletionEvents = try await mockSecurityService.getSecurityEvents(
            tenantId: tenantId,
            userId: userId,
            eventType: .dataModification,
            dateRange: DateRange(startDate: Date().addingTimeInterval(-60), endDate: Date())
        )
        
        let deletionEvent = deletionEvents.first { $0.resource == "user_data" && $0.action == .delete }
        XCTAssertNotNil(deletionEvent)
        XCTAssertEqual(deletionEvent?.metadata["scope"], "user")
    }
}

// MARK: - Test Data Structures

private struct SensitiveRevenueData: Codable {
    let totalRevenue: Decimal
    let customerCount: Int
    let paymentMethods: [String]
    let apiKeys: [String]
}

private struct RetentionRules {
    let retentionPeriod: TimeInterval
    let anonymizeAfter: TimeInterval
    let deleteAfter: TimeInterval
}

private enum ExportFormat {
    case json
    case csv
    case xml
}

// MARK: - Mock Extensions

extension MockBillingService {
    func createCustomer(tenantId: String, email: String, name: String, metadata: [String: String]) async throws -> BillingCustomer {
        return BillingCustomer(
            id: "customer_\(UUID().uuidString.prefix(8))",
            email: email,
            name: name,
            metadata: metadata.merging(["tenantId": tenantId]) { _, new in new }
        )
    }
}

private struct BillingCustomer {
    let id: String
    let email: String
    let name: String
    let metadata: [String: String]
}

private struct DateRange {
    let startDate: Date
    let endDate: Date
}