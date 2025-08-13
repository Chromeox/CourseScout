import Foundation
import Combine
import Appwrite

// MARK: - Security Service Protocol

protocol SecurityServiceProtocol: AnyObject {
    // MARK: - Tenant Data Isolation
    func validateTenantAccess(userId: String, tenantId: String, resourceId: String, action: SecurityAction) async throws -> Bool
    func ensureTenantDataIsolation(query: Query, tenantId: String) throws -> Query
    func filterTenantData<T>(_ data: [T], tenantId: String) async throws -> [T] where T: TenantIsolatable
    func validateDataOwnership(resourceId: String, tenantId: String, resourceType: ResourceType) async throws -> Bool
    
    // MARK: - Multi-Tenant Authentication
    func authenticateUserForTenant(token: String, tenantId: String) async throws -> UserAuth
    func validateAPIKeyForTenant(apiKey: String, tenantId: String) async throws -> APIKeyValidation
    func createTenantAPIKey(tenantId: String, permissions: [SecurityPermission]) async throws -> TenantAPIKey
    func revokeTenantAPIKey(tenantId: String, keyId: String) async throws
    
    // MARK: - Role-Based Access Control (RBAC)
    func createRole(tenantId: String, role: SecurityRole) async throws -> SecurityRole
    func assignRoleToUser(tenantId: String, userId: String, roleId: String) async throws
    func removeRoleFromUser(tenantId: String, userId: String, roleId: String) async throws
    func getUserRoles(tenantId: String, userId: String) async throws -> [SecurityRole]
    func checkPermission(tenantId: String, userId: String, permission: SecurityPermission) async throws -> Bool
    
    // MARK: - Data Encryption
    func encryptTenantData<T: Codable>(_ data: T, tenantId: String) async throws -> EncryptedData
    func decryptTenantData<T: Codable>(_ encryptedData: EncryptedData, tenantId: String, type: T.Type) async throws -> T
    func rotateTenantEncryptionKey(tenantId: String) async throws
    func getTenantEncryptionStatus(tenantId: String) async throws -> EncryptionStatus
    
    // MARK: - Audit Logging
    func logSecurityEvent(_ event: SecurityEvent) async throws
    func getSecurityEvents(tenantId: String?, userId: String?, eventType: SecurityEventType?, dateRange: DateRange) async throws -> [SecurityEvent]
    func createSecurityAlert(_ alert: SecurityAlert) async throws
    func getSecurityAlerts(tenantId: String, severity: AlertSeverity?) async throws -> [SecurityAlert]
    
    // MARK: - Cross-Tenant Security
    func preventTenantCrossTalk(sourceId: String, targetId: String, operation: SecurityOperation) async throws
    func validateTenantBoundary(resourcePath: String, tenantId: String) async throws -> Bool
    func sanitizeCrossTenantRequests<T>(_ request: T, tenantId: String) async throws -> T where T: TenantSanitizable
    
    // MARK: - Security Monitoring
    func detectAnomalousActivity(tenantId: String, period: SecurityPeriod) async throws -> [SecurityAnomaly]
    func analyzeSecurityRisk(tenantId: String) async throws -> SecurityRiskAssessment
    func generateSecurityReport(tenantId: String, reportType: SecurityReportType) async throws -> SecurityReport
    
    // MARK: - Compliance & Privacy
    func ensureGDPRCompliance(tenantId: String, userId: String) async throws -> GDPRComplianceStatus
    func processDataDeletionRequest(tenantId: String, userId: String, scope: DeletionScope) async throws
    func exportUserData(tenantId: String, userId: String, format: ExportFormat) async throws -> Data
    func anonymizeUserData(tenantId: String, userId: String, retentionRules: RetentionRules) async throws
    
    // MARK: - Security Configuration
    func updateTenantSecurityPolicy(tenantId: String, policy: SecurityPolicy) async throws
    func getTenantSecurityPolicy(tenantId: String) async throws -> SecurityPolicy
    func validateSecurityConfiguration(tenantId: String) async throws -> [SecurityConfigurationIssue]
    func applySecurityPatch(tenantId: String, patchId: String) async throws
}

// MARK: - Security Models

struct UserAuth {
    let userId: String
    let tenantId: String
    let permissions: [SecurityPermission]
    let roles: [SecurityRole]
    let sessionToken: String
    let expiresAt: Date
    let lastLogin: Date
    let ipAddress: String?
    let userAgent: String?
    let isMultiFactorEnabled: Bool
}

struct APIKeyValidation {
    let keyId: String
    let tenantId: String
    let isValid: Bool
    let permissions: [SecurityPermission]
    let rateLimit: RateLimit?
    let expiresAt: Date?
    let lastUsed: Date?
    let usage: APIKeyUsage
}

struct TenantAPIKey {
    let id: String
    let tenantId: String
    let keyHash: String
    let name: String
    let permissions: [SecurityPermission]
    let rateLimit: RateLimit?
    let expiresAt: Date?
    let createdAt: Date
    let createdBy: String
    let isActive: Bool
    let usage: APIKeyUsage
}

struct SecurityRole {
    let id: String
    let tenantId: String
    let name: String
    let description: String
    let permissions: [SecurityPermission]
    let isSystem: Bool
    let inheritedFrom: [String]
    let createdAt: Date
    let updatedAt: Date
}

struct SecurityPermission {
    let id: String
    let resource: ResourceType
    let action: SecurityAction
    let conditions: [PermissionCondition]?
    let scope: PermissionScope
    
    enum PermissionScope {
        case tenant
        case user
        case resource
        case global
    }
}

struct EncryptedData {
    let data: Data
    let keyId: String
    let algorithm: EncryptionAlgorithm
    let iv: Data
    let tag: Data?
    let encryptedAt: Date
    
    enum EncryptionAlgorithm: String {
        case aes256gcm = "AES-256-GCM"
        case chacha20poly1305 = "ChaCha20-Poly1305"
    }
}

struct EncryptionStatus {
    let tenantId: String
    let isEnabled: Bool
    let algorithm: EncryptedData.EncryptionAlgorithm
    let keyRotationSchedule: KeyRotationSchedule?
    let lastRotation: Date?
    let nextRotation: Date?
    let encryptedResources: [ResourceType]
    let status: EncryptionHealth
    
    enum EncryptionHealth {
        case healthy
        case warning
        case critical
        case keyRotationNeeded
    }
}

struct SecurityEvent {
    let id: String
    let tenantId: String?
    let userId: String?
    let eventType: SecurityEventType
    let resource: String?
    let action: SecurityAction
    let timestamp: Date
    let ipAddress: String?
    let userAgent: String?
    let success: Bool
    let errorMessage: String?
    let metadata: [String: String]
    let riskLevel: RiskLevel
}

struct SecurityAlert {
    let id: String
    let tenantId: String
    let alertType: SecurityAlertType
    let severity: AlertSeverity
    let title: String
    let description: String
    let affectedResources: [String]
    let detectedAt: Date
    let resolvedAt: Date?
    let status: AlertStatus
    let assignedTo: String?
    let remediation: [RemediationStep]
}

struct SecurityAnomaly {
    let id: String
    let tenantId: String
    let anomalyType: AnomalyType
    let severity: AnomalySeverity
    let description: String
    let detectedAt: Date
    let affectedUsers: [String]
    let affectedResources: [String]
    let confidenceScore: Double
    let riskAssessment: RiskAssessment
}

struct SecurityRiskAssessment {
    let tenantId: String
    let overallRisk: RiskLevel
    let riskFactors: [RiskFactor]
    let recommendations: [SecurityRecommendation]
    let complianceScore: Double
    let lastAssessment: Date
    let nextAssessment: Date
}

struct SecurityReport {
    let id: String
    let tenantId: String
    let reportType: SecurityReportType
    let generatedAt: Date
    let period: DateRange
    let summary: SecuritySummary
    let data: Data
    let format: ExportFormat
}

struct GDPRComplianceStatus {
    let tenantId: String
    let userId: String
    let isCompliant: Bool
    let issues: [ComplianceIssue]
    let dataCategories: [DataCategory]
    let retentionStatus: RetentionStatus
    let consentStatus: ConsentStatus
    let lastAudit: Date
}

struct SecurityPolicy {
    let tenantId: String
    let passwordPolicy: PasswordPolicy
    let sessionPolicy: SessionPolicy
    let encryptionPolicy: EncryptionPolicy
    let auditPolicy: AuditPolicy
    let accessPolicy: AccessPolicy
    let dataRetentionPolicy: DataRetentionPolicy
    let multiFactorPolicy: MultiFactorPolicy
    let version: String
    let lastUpdated: Date
}

struct SecurityConfigurationIssue {
    let id: String
    let category: ConfigurationCategory
    let severity: IssueSeverity
    let title: String
    let description: String
    let recommendation: String
    let impact: SecurityImpact
    let effort: RemediationEffort
}

// MARK: - Enumerations

enum SecurityAction: String, CaseIterable, Codable {
    case create = "create"
    case read = "read"
    case update = "update"
    case delete = "delete"
    case list = "list"
    case execute = "execute"
    case admin = "admin"
    case audit = "audit"
}

enum ResourceType: String, CaseIterable, Codable {
    case course = "course"
    case booking = "booking"
    case user = "user"
    case tenant = "tenant"
    case payment = "payment"
    case analytics = "analytics"
    case api = "api"
    case report = "report"
}

enum SecurityEventType: String, CaseIterable, Codable {
    case authentication = "authentication"
    case authorization = "authorization"
    case dataAccess = "data_access"
    case dataModification = "data_modification"
    case privilegeEscalation = "privilege_escalation"
    case anomalousActivity = "anomalous_activity"
    case policyViolation = "policy_violation"
    case securityBreach = "security_breach"
}

enum SecurityOperation: String, CaseIterable, Codable {
    case dataAccess = "data_access"
    case dataModification = "data_modification"
    case apiCall = "api_call"
    case reporting = "reporting"
    case administration = "administration"
}

enum SecurityPeriod: String, CaseIterable, Codable {
    case hour = "hour"
    case day = "day"
    case week = "week"
    case month = "month"
    case quarter = "quarter"
}

enum AlertSeverity: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum RiskLevel: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum SecurityAlertType: String, CaseIterable, Codable {
    case unauthorizedAccess = "unauthorized_access"
    case suspiciousActivity = "suspicious_activity"
    case dataLeak = "data_leak"
    case brute = "brute_force"
    case malwareDetected = "malware_detected"
    case complianceViolation = "compliance_violation"
}

enum AnomalyType: String, CaseIterable, Codable {
    case unusualAccess = "unusual_access"
    case dataExfiltration = "data_exfiltration"
    case privilegeAbuse = "privilege_abuse"
    case anomalousLogin = "anomalous_login"
    case suspiciousAPI = "suspicious_api"
}

enum SecurityReportType: String, CaseIterable, Codable {
    case audit = "audit"
    case compliance = "compliance"
    case risk = "risk"
    case incident = "incident"
    case usage = "usage"
}

enum DeletionScope: String, CaseIterable, Codable {
    case user = "user"
    case tenant = "tenant"
    case all = "all"
}

enum ConfigurationCategory: String, CaseIterable, Codable {
    case authentication = "authentication"
    case authorization = "authorization"
    case encryption = "encryption"
    case audit = "audit"
    case network = "network"
    case compliance = "compliance"
}

enum IssueSeverity: String, CaseIterable, Codable {
    case informational = "informational"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum SecurityImpact: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum RemediationEffort: String, CaseIterable, Codable {
    case minimal = "minimal"
    case low = "low"
    case medium = "medium"
    case high = "high"
}

// MARK: - Protocol Extensions

protocol TenantIsolatable {
    var tenantId: String { get }
}

protocol TenantSanitizable {
    func sanitizeForTenant(_ tenantId: String) -> Self
}

// MARK: - Supporting Types

struct RateLimit {
    let requestsPerMinute: Int
    let requestsPerHour: Int
    let requestsPerDay: Int
    let burstLimit: Int
}

struct APIKeyUsage {
    let totalRequests: Int
    let lastRequest: Date?
    let requestsToday: Int
    let requestsThisMonth: Int
    let errors: Int
}

struct PermissionCondition {
    let field: String
    let operator: ConditionOperator
    let value: String
    
    enum ConditionOperator: String {
        case equals = "eq"
        case notEquals = "ne"
        case contains = "contains"
        case startsWith = "starts_with"
        case endsWith = "ends_with"
        case greaterThan = "gt"
        case lessThan = "lt"
    }
}

struct KeyRotationSchedule {
    let frequency: RotationFrequency
    let nextRotation: Date
    let autoRotate: Bool
    
    enum RotationFrequency: String {
        case monthly = "monthly"
        case quarterly = "quarterly"
        case yearly = "yearly"
        case custom = "custom"
    }
}

struct RemediationStep {
    let id: String
    let description: String
    let priority: Int
    let estimatedTime: TimeInterval
    let required: Bool
    let completed: Bool
    let completedAt: Date?
}

struct RiskFactor {
    let category: RiskCategory
    let severity: RiskLevel
    let description: String
    let impact: SecurityImpact
    let likelihood: Double
    let mitigation: String?
    
    enum RiskCategory: String {
        case technical = "technical"
        case operational = "operational"
        case compliance = "compliance"
        case strategic = "strategic"
    }
}

struct SecurityRecommendation {
    let id: String
    let title: String
    let description: String
    let priority: RecommendationPriority
    let impact: SecurityImpact
    let effort: RemediationEffort
    let category: ConfigurationCategory
    
    enum RecommendationPriority: String {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }
}

// Additional supporting structs would be implemented for other complex types...

// MARK: - Security Service Errors

enum SecurityServiceError: Error, LocalizedError {
    case tenantNotFound(String)
    case unauthorizedAccess(String, SecurityAction, ResourceType)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keyRotationFailed(String)
    case invalidAPIKey(String)
    case invalidPermissions([SecurityPermission])
    case crossTenantViolation(String, String)
    case complianceViolation(String, String)
    case securityPolicyViolation(String)
    case auditLogFailed(String)
    case dataIsolationFailed(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .tenantNotFound(let tenantId):
            return "Tenant not found: \(tenantId)"
        case .unauthorizedAccess(let userId, let action, let resource):
            return "Unauthorized access: User \(userId) cannot \(action.rawValue) \(resource.rawValue)"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .keyRotationFailed(let message):
            return "Key rotation failed: \(message)"
        case .invalidAPIKey(let keyId):
            return "Invalid API key: \(keyId)"
        case .invalidPermissions(let permissions):
            return "Invalid permissions: \(permissions.map { $0.id }.joined(separator: ", "))"
        case .crossTenantViolation(let source, let target):
            return "Cross-tenant violation: \(source) -> \(target)"
        case .complianceViolation(let type, let message):
            return "Compliance violation (\(type)): \(message)"
        case .securityPolicyViolation(let message):
            return "Security policy violation: \(message)"
        case .auditLogFailed(let message):
            return "Audit log failed: \(message)"
        case .dataIsolationFailed(let message):
            return "Data isolation failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}