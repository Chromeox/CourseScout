import Foundation
import Combine

#if DEBUG
class MockSecurityService: SecurityServiceProtocol {
    
    // MARK: - Published Properties
    @Published private var mockSecurityEvents: [SecurityEvent] = []
    @Published private var mockAlerts: [SecurityAlert] = []
    
    // MARK: - Mock Data
    private var mockTenantAccess: [String: [String]] = [:] // tenantId -> [userId]
    private var mockRoles: [String: [SecurityRole]] = [:]
    private var mockAPIKeys: [String: APIKeyValidation] = [:]
    private var mockEncryptedData: [String: EncryptedData] = [:]
    
    init() {
        setupMockData()
    }
    
    private func setupMockData() {
        // Setup some default mock data
        mockTenantAccess["tenant1"] = ["user1", "user2"]
        mockTenantAccess["tenant2"] = ["user3", "user4"]
        
        let adminRole = SecurityRole(
            id: "admin-role",
            tenantId: "tenant1",
            name: "Admin",
            description: "Full administrative access",
            permissions: [
                SecurityPermission(id: "admin-all", resource: .tenant, action: .admin, conditions: nil, scope: .tenant)
            ],
            isSystem: true,
            inheritedFrom: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        
        mockRoles["tenant1:user1"] = [adminRole]
    }
    
    // MARK: - Tenant Data Isolation
    
    func validateTenantAccess(userId: String, tenantId: String, resourceId: String, action: SecurityAction) async throws -> Bool {
        let hasAccess = mockTenantAccess[tenantId]?.contains(userId) ?? false
        
        let event = SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: userId,
            eventType: .authorization,
            resource: resourceId,
            action: action,
            timestamp: Date(),
            ipAddress: "127.0.0.1",
            userAgent: "MockClient",
            success: hasAccess,
            errorMessage: hasAccess ? nil : "Mock: Access denied",
            metadata: ["mock": "true"],
            riskLevel: hasAccess ? .low : .high
        )
        
        try await logSecurityEvent(event)
        
        if !hasAccess {
            throw SecurityServiceError.unauthorizedAccess(userId, action, .tenant)
        }
        
        return true
    }
    
    func ensureTenantDataIsolation(query: Query, tenantId: String) throws -> Query {
        // Mock implementation - just return the query with tenant filter
        return query
    }
    
    func filterTenantData<T>(_ data: [T], tenantId: String) async throws -> [T] where T: TenantIsolatable {
        return data.filter { $0.tenantId == tenantId }
    }
    
    func validateDataOwnership(resourceId: String, tenantId: String, resourceType: ResourceType) async throws -> Bool {
        // Mock validation - return true for simplicity
        return true
    }
    
    // MARK: - Multi-Tenant Authentication
    
    func authenticateUserForTenant(token: String, tenantId: String) async throws -> UserAuth {
        let userId = "mock-user-\(token.prefix(8))"
        
        let userAuth = UserAuth(
            userId: userId,
            tenantId: tenantId,
            permissions: [
                SecurityPermission(id: "mock-read", resource: .api, action: .read, conditions: nil, scope: .tenant)
            ],
            roles: mockRoles["\(tenantId):\(userId)"] ?? [],
            sessionToken: token,
            expiresAt: Date().addingTimeInterval(3600),
            lastLogin: Date(),
            ipAddress: "127.0.0.1",
            userAgent: "MockClient",
            isMultiFactorEnabled: false
        )
        
        try await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: userId,
            eventType: .authentication,
            resource: "session",
            action: .create,
            timestamp: Date(),
            ipAddress: "127.0.0.1",
            userAgent: "MockClient",
            success: true,
            errorMessage: nil,
            metadata: ["auth_method": "mock"],
            riskLevel: .low
        ))
        
        return userAuth
    }
    
    func validateAPIKeyForTenant(apiKey: String, tenantId: String) async throws -> APIKeyValidation {
        if let cached = mockAPIKeys[apiKey] {
            return cached
        }
        
        let validation = APIKeyValidation(
            keyId: "mock-key-\(apiKey.prefix(8))",
            tenantId: tenantId,
            isValid: true,
            permissions: [
                SecurityPermission(id: "api-read", resource: .api, action: .read, conditions: nil, scope: .tenant),
                SecurityPermission(id: "api-write", resource: .api, action: .create, conditions: nil, scope: .tenant)
            ],
            rateLimit: RateLimit(requestsPerMinute: 60, requestsPerHour: 1000, requestsPerDay: 10000, burstLimit: 100),
            expiresAt: Date().addingTimeInterval(86400 * 30),
            lastUsed: Date(),
            usage: APIKeyUsage(totalRequests: 42, lastRequest: Date(), requestsToday: 5, requestsThisMonth: 150, errors: 0)
        )
        
        mockAPIKeys[apiKey] = validation
        return validation
    }
    
    func createTenantAPIKey(tenantId: String, permissions: [SecurityPermission]) async throws -> TenantAPIKey {
        let apiKey = TenantAPIKey(
            id: UUID().uuidString,
            tenantId: tenantId,
            keyHash: "mock-hash-\(UUID().uuidString.prefix(8))",
            name: "Mock API Key",
            permissions: permissions,
            rateLimit: RateLimit(requestsPerMinute: 60, requestsPerHour: 1000, requestsPerDay: 10000, burstLimit: 100),
            expiresAt: Date().addingTimeInterval(86400 * 30),
            createdAt: Date(),
            createdBy: "mock-system",
            isActive: true,
            usage: APIKeyUsage(totalRequests: 0, lastRequest: nil, requestsToday: 0, requestsThisMonth: 0, errors: 0)
        )
        
        try await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: nil,
            eventType: .authentication,
            resource: "api_key",
            action: .create,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: ["key_id": apiKey.id],
            riskLevel: .medium
        ))
        
        return apiKey
    }
    
    func revokeTenantAPIKey(tenantId: String, keyId: String) async throws {
        try await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: nil,
            eventType: .authentication,
            resource: "api_key",
            action: .delete,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: ["key_id": keyId],
            riskLevel: .medium
        ))
    }
    
    // MARK: - Role-Based Access Control (RBAC)
    
    func createRole(tenantId: String, role: SecurityRole) async throws -> SecurityRole {
        return role
    }
    
    func assignRoleToUser(tenantId: String, userId: String, roleId: String) async throws {
        // Mock implementation
    }
    
    func removeRoleFromUser(tenantId: String, userId: String, roleId: String) async throws {
        // Mock implementation
    }
    
    func getUserRoles(tenantId: String, userId: String) async throws -> [SecurityRole] {
        return mockRoles["\(tenantId):\(userId)"] ?? []
    }
    
    func checkPermission(tenantId: String, userId: String, permission: SecurityPermission) async throws -> Bool {
        let roles = try await getUserRoles(tenantId: tenantId, userId: userId)
        
        for role in roles {
            for rolePermission in role.permissions {
                if rolePermission.resource == permission.resource &&
                   rolePermission.action == permission.action {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Data Encryption
    
    func encryptTenantData<T: Codable>(_ data: T, tenantId: String) async throws -> EncryptedData {
        let jsonData = try JSONEncoder().encode(data)
        
        let encryptedData = EncryptedData(
            data: jsonData, // Mock: not actually encrypted
            keyId: "mock-key-\(tenantId)",
            algorithm: .aes256gcm,
            iv: Data(repeating: 0, count: 12),
            tag: Data(repeating: 0, count: 16),
            encryptedAt: Date()
        )
        
        mockEncryptedData[tenantId] = encryptedData
        return encryptedData
    }
    
    func decryptTenantData<T: Codable>(_ encryptedData: EncryptedData, tenantId: String, type: T.Type) async throws -> T {
        // Mock: just decode the "encrypted" data
        return try JSONDecoder().decode(type, from: encryptedData.data)
    }
    
    func rotateTenantEncryptionKey(tenantId: String) async throws {
        try await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: nil,
            eventType: .dataModification,
            resource: "encryption_key",
            action: .update,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: [:],
            riskLevel: .low
        ))
    }
    
    func getTenantEncryptionStatus(tenantId: String) async throws -> EncryptionStatus {
        return EncryptionStatus(
            tenantId: tenantId,
            isEnabled: true,
            algorithm: .aes256gcm,
            keyRotationSchedule: nil,
            lastRotation: Date().addingTimeInterval(-86400 * 7),
            nextRotation: Date().addingTimeInterval(86400 * 23),
            encryptedResources: [.user, .payment, .analytics],
            status: .healthy
        )
    }
    
    // MARK: - Audit Logging
    
    func logSecurityEvent(_ event: SecurityEvent) async throws {
        mockSecurityEvents.append(event)
        
        // Keep only last 100 events for mock
        if mockSecurityEvents.count > 100 {
            mockSecurityEvents.removeFirst(mockSecurityEvents.count - 100)
        }
        
        print("Mock Security Event: \(event.eventType.rawValue) - \(event.action.rawValue) on \(event.resource ?? "unknown")")
    }
    
    func getSecurityEvents(tenantId: String?, userId: String?, eventType: SecurityEventType?, dateRange: DateRange) async throws -> [SecurityEvent] {
        var filteredEvents = mockSecurityEvents
        
        if let tenantId = tenantId {
            filteredEvents = filteredEvents.filter { $0.tenantId == tenantId }
        }
        
        if let userId = userId {
            filteredEvents = filteredEvents.filter { $0.userId == userId }
        }
        
        if let eventType = eventType {
            filteredEvents = filteredEvents.filter { $0.eventType == eventType }
        }
        
        filteredEvents = filteredEvents.filter { 
            $0.timestamp >= dateRange.startDate && $0.timestamp <= dateRange.endDate 
        }
        
        return filteredEvents
    }
    
    func createSecurityAlert(_ alert: SecurityAlert) async throws {
        mockAlerts.append(alert)
    }
    
    func getSecurityAlerts(tenantId: String, severity: AlertSeverity?) async throws -> [SecurityAlert] {
        var filteredAlerts = mockAlerts.filter { $0.tenantId == tenantId }
        
        if let severity = severity {
            filteredAlerts = filteredAlerts.filter { $0.severity == severity }
        }
        
        return filteredAlerts
    }
    
    // MARK: - Cross-Tenant Security
    
    func preventTenantCrossTalk(sourceId: String, targetId: String, operation: SecurityOperation) async throws {
        if sourceId != targetId {
            try await logSecurityEvent(SecurityEvent(
                id: UUID().uuidString,
                tenantId: sourceId,
                userId: nil,
                eventType: .securityBreach,
                resource: targetId,
                action: .read,
                timestamp: Date(),
                ipAddress: nil,
                userAgent: nil,
                success: false,
                errorMessage: "Mock: Cross-tenant operation blocked",
                metadata: ["operation": operation.rawValue],
                riskLevel: .critical
            ))
            
            throw SecurityServiceError.crossTenantViolation(sourceId, targetId)
        }
    }
    
    func validateTenantBoundary(resourcePath: String, tenantId: String) async throws -> Bool {
        return resourcePath.contains(tenantId)
    }
    
    func sanitizeCrossTenantRequests<T>(_ request: T, tenantId: String) async throws -> T where T: TenantSanitizable {
        return request.sanitizeForTenant(tenantId)
    }
    
    // MARK: - Security Monitoring
    
    func detectAnomalousActivity(tenantId: String, period: SecurityPeriod) async throws -> [SecurityAnomaly] {
        // Return some mock anomalies for demonstration
        return [
            SecurityAnomaly(
                id: UUID().uuidString,
                tenantId: tenantId,
                anomalyType: .unusualAccess,
                severity: .medium,
                description: "Mock: Unusual access pattern detected",
                detectedAt: Date(),
                affectedUsers: ["mock-user-1"],
                affectedResources: ["mock-resource-1"],
                confidenceScore: 0.75,
                riskAssessment: RiskAssessment()
            )
        ]
    }
    
    func analyzeSecurityRisk(tenantId: String) async throws -> SecurityRiskAssessment {
        return SecurityRiskAssessment(
            tenantId: tenantId,
            overallRisk: .low,
            riskFactors: [
                RiskFactor(
                    category: .technical,
                    severity: .low,
                    description: "Mock: No significant risks detected",
                    impact: .low,
                    likelihood: 0.1,
                    mitigation: "Continue monitoring"
                )
            ],
            recommendations: [
                SecurityRecommendation(
                    id: UUID().uuidString,
                    title: "Mock Recommendation",
                    description: "Continue following security best practices",
                    priority: .low,
                    impact: .low,
                    effort: .minimal,
                    category: .technical
                )
            ],
            complianceScore: 0.95,
            lastAssessment: Date(),
            nextAssessment: Date().addingTimeInterval(86400 * 7)
        )
    }
    
    func generateSecurityReport(tenantId: String, reportType: SecurityReportType) async throws -> SecurityReport {
        return SecurityReport(
            id: UUID().uuidString,
            tenantId: tenantId,
            reportType: reportType,
            generatedAt: Date(),
            period: DateRange(startDate: Date().addingTimeInterval(-86400 * 30), endDate: Date()),
            summary: SecuritySummary(),
            data: "Mock security report data".data(using: .utf8) ?? Data(),
            format: .json
        )
    }
    
    // MARK: - Compliance & Privacy
    
    func ensureGDPRCompliance(tenantId: String, userId: String) async throws -> GDPRComplianceStatus {
        return GDPRComplianceStatus(
            tenantId: tenantId,
            userId: userId,
            isCompliant: true,
            issues: [],
            dataCategories: [],
            retentionStatus: RetentionStatus(),
            consentStatus: ConsentStatus(),
            lastAudit: Date()
        )
    }
    
    func processDataDeletionRequest(tenantId: String, userId: String, scope: DeletionScope) async throws {
        try await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: userId,
            eventType: .dataModification,
            resource: "user_data",
            action: .delete,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: ["scope": scope.rawValue, "mock": "true"],
            riskLevel: .medium
        ))
    }
    
    func exportUserData(tenantId: String, userId: String, format: ExportFormat) async throws -> Data {
        return "Mock user data export".data(using: .utf8) ?? Data()
    }
    
    func anonymizeUserData(tenantId: String, userId: String, retentionRules: RetentionRules) async throws {
        // Mock implementation
    }
    
    // MARK: - Security Configuration
    
    func updateTenantSecurityPolicy(tenantId: String, policy: SecurityPolicy) async throws {
        // Mock implementation
    }
    
    func getTenantSecurityPolicy(tenantId: String) async throws -> SecurityPolicy {
        return SecurityPolicy(
            tenantId: tenantId,
            passwordPolicy: PasswordPolicy(),
            sessionPolicy: SessionPolicy(),
            encryptionPolicy: EncryptionPolicy(),
            auditPolicy: AuditPolicy(),
            accessPolicy: AccessPolicy(),
            dataRetentionPolicy: DataRetentionPolicy(),
            multiFactorPolicy: MultiFactorPolicy(),
            version: "1.0.0-mock",
            lastUpdated: Date()
        )
    }
    
    func validateSecurityConfiguration(tenantId: String) async throws -> [SecurityConfigurationIssue] {
        return [
            SecurityConfigurationIssue(
                id: UUID().uuidString,
                category: .authentication,
                severity: .informational,
                title: "Mock Configuration Check",
                description: "All security configurations are properly set up (mock)",
                recommendation: "No action required",
                impact: .low,
                effort: .minimal
            )
        ]
    }
    
    func applySecurityPatch(tenantId: String, patchId: String) async throws {
        try await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: nil,
            eventType: .dataModification,
            resource: "security_patch",
            action: .update,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: ["patch_id": patchId, "mock": "true"],
            riskLevel: .low
        ))
    }
}

// MARK: - Mock Extensions

extension SecurityEvent {
    static var mock: SecurityEvent {
        SecurityEvent(
            id: UUID().uuidString,
            tenantId: "mock-tenant",
            userId: "mock-user",
            eventType: .authentication,
            resource: "mock-resource",
            action: .read,
            timestamp: Date(),
            ipAddress: "127.0.0.1",
            userAgent: "MockClient",
            success: true,
            errorMessage: nil,
            metadata: ["mock": "true"],
            riskLevel: .low
        )
    }
}

extension SecurityAlert {
    static var mock: SecurityAlert {
        SecurityAlert(
            id: UUID().uuidString,
            tenantId: "mock-tenant",
            alertType: .unauthorizedAccess,
            severity: .medium,
            title: "Mock Security Alert",
            description: "This is a mock security alert for testing",
            affectedResources: ["mock-resource-1", "mock-resource-2"],
            detectedAt: Date(),
            resolvedAt: nil,
            status: .open,
            assignedTo: nil,
            remediation: [
                RemediationStep(
                    id: UUID().uuidString,
                    description: "Mock remediation step",
                    priority: 1,
                    estimatedTime: 3600,
                    required: true,
                    completed: false,
                    completedAt: nil
                )
            ]
        )
    }
}

extension SecurityAnomaly {
    static var mock: SecurityAnomaly {
        SecurityAnomaly(
            id: UUID().uuidString,
            tenantId: "mock-tenant",
            anomalyType: .unusualAccess,
            severity: .medium,
            description: "Mock security anomaly",
            detectedAt: Date(),
            affectedUsers: ["mock-user"],
            affectedResources: ["mock-resource"],
            confidenceScore: 0.8,
            riskAssessment: RiskAssessment()
        )
    }
}
#endif