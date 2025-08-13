import Foundation
import Combine

// MARK: - Tenant Models

struct Tenant: Codable, Identifiable {
    let id: String
    var name: String
    let slug: String
    let type: TenantType
    var status: TenantStatus
    var primaryDomain: String?
    var customDomains: [CustomDomain]
    var branding: TenantBranding
    var settings: TenantSettings
    var limits: TenantLimits
    var features: [String]
    let parentTenantId: String?
    let createdAt: Date
    var updatedAt: Date?
    var suspendedAt: Date?
    var suspensionReason: SuspensionReason?
    var subscriptionId: String?
    let metadata: [String: String]
    
    // Sample tenants for development
    #if DEBUG
    static let sampleGolfCourse = Tenant(
        id: "tenant_golf_001",
        name: "Pebble Beach Golf Links",
        slug: "pebble-beach",
        type: .enterprise,
        status: .active,
        primaryDomain: "pebblebeach.golffinder.app",
        customDomains: [
            CustomDomain(
                domain: "pebblebeach.com",
                isVerified: true,
                verificationToken: "pb_verified_123",
                sslCertificate: nil,
                addedAt: Date(),
                verifiedAt: Date()
            )
        ],
        branding: TenantBranding(
            primaryColor: "#1B5E20",
            secondaryColor: "#4CAF50",
            logoUrl: "https://example.com/pebble-beach-logo.png",
            faviconUrl: "https://example.com/pebble-beach-favicon.ico",
            customCSS: nil,
            whiteLabel: true
        ),
        settings: TenantSettings.default,
        limits: TenantLimits.enterprise,
        features: ["golf_management", "advanced_booking", "analytics", "api_access"],
        parentTenantId: nil,
        createdAt: Date().addingTimeInterval(-86400 * 30), // 30 days ago
        subscriptionId: "sub_pebble_beach_001",
        metadata: [
            "industry": "golf",
            "location": "Pebble Beach, CA",
            "established": "1919"
        ]
    )
    
    static let sampleEnterprise = Tenant(
        id: "tenant_ent_001",
        name: "Golf Enterprise Solutions",
        slug: "golf-enterprise",
        type: .enterprise,
        status: .active,
        primaryDomain: "enterprise.golffinder.app",
        customDomains: [],
        branding: TenantBranding.enterprise,
        settings: TenantSettings.default,
        limits: TenantLimits.enterprise,
        features: ["multi_tenant", "white_label", "api_access", "advanced_analytics"],
        parentTenantId: nil,
        createdAt: Date().addingTimeInterval(-86400 * 60), // 60 days ago
        metadata: ["segment": "enterprise", "contract_type": "annual"]
    )
    
    static let sampleStartup = Tenant(
        id: "tenant_start_001",
        name: "Green Golf Startup",
        slug: "green-golf",
        type: .smallBusiness,
        status: .active,
        primaryDomain: "greengolf.golffinder.app",
        customDomains: [],
        branding: TenantBranding.startup,
        settings: TenantSettings.default,
        limits: TenantLimits.professional,
        features: ["basic_booking", "course_management"],
        parentTenantId: nil,
        createdAt: Date().addingTimeInterval(-86400 * 7), // 7 days ago
        metadata: ["segment": "startup", "referral_source": "product_hunt"]
    )
    #endif
}

struct TenantCreateRequest: Codable {
    let name: String
    let slug: String
    let type: TenantType
    let primaryDomain: String?
    let branding: TenantBranding?
    let settings: TenantSettings?
    let limits: TenantLimits?
    let features: [String]?
    let parentTenantId: String?
    let metadata: [String: String]?
}

struct TenantUpdate: Codable {
    let name: String?
    let status: TenantStatus?
    let branding: TenantBranding?
    let settings: TenantSettings?
    let limits: TenantLimits?
    let features: [String]?
    let metadata: [String: String]?
}

// MARK: - Tenant Branding

struct TenantBranding: Codable {
    let primaryColor: String
    let secondaryColor: String
    let logoUrl: String?
    let faviconUrl: String?
    let customCSS: String?
    let whiteLabel: Bool
    
    static let `default` = TenantBranding(
        primaryColor: "#1976D2",
        secondaryColor: "#2196F3",
        logoUrl: nil,
        faviconUrl: nil,
        customCSS: nil,
        whiteLabel: false
    )
    
    static let enterprise = TenantBranding(
        primaryColor: "#0D47A1",
        secondaryColor: "#1565C0",
        logoUrl: "https://example.com/enterprise-logo.png",
        faviconUrl: "https://example.com/enterprise-favicon.ico",
        customCSS: """
        .app-header { background: linear-gradient(45deg, #0D47A1, #1565C0); }
        .btn-primary { background-color: #0D47A1; border-color: #0D47A1; }
        """,
        whiteLabel: true
    )
    
    static let startup = TenantBranding(
        primaryColor: "#388E3C",
        secondaryColor: "#4CAF50",
        logoUrl: nil,
        faviconUrl: nil,
        customCSS: nil,
        whiteLabel: false
    )
}

// MARK: - Tenant Settings

struct TenantSettings: Codable {
    let timezone: String
    let locale: String
    let currency: String
    let dateFormat: String
    let timeFormat: String
    let allowRegistration: Bool
    let requireEmailVerification: Bool
    let enableTwoFactor: Bool
    let sessionTimeout: Int // minutes
    let maxLoginAttempts: Int
    let enableAuditLog: Bool
    let enableApiAccess: Bool
    let enableWebhooks: Bool
    let webhookUrl: String?
    let notificationSettings: NotificationSettings
    let securitySettings: SecuritySettings
    
    static let `default` = TenantSettings(
        timezone: "UTC",
        locale: "en_US",
        currency: "USD",
        dateFormat: "MM/dd/yyyy",
        timeFormat: "12",
        allowRegistration: true,
        requireEmailVerification: true,
        enableTwoFactor: false,
        sessionTimeout: 480, // 8 hours
        maxLoginAttempts: 5,
        enableAuditLog: true,
        enableApiAccess: false,
        enableWebhooks: false,
        webhookUrl: nil,
        notificationSettings: NotificationSettings.default,
        securitySettings: SecuritySettings.default
    )
}

struct NotificationSettings: Codable {
    let emailNotifications: Bool
    let pushNotifications: Bool
    let smsNotifications: Bool
    let webhookNotifications: Bool
    let notificationTypes: [String]
    
    static let `default` = NotificationSettings(
        emailNotifications: true,
        pushNotifications: true,
        smsNotifications: false,
        webhookNotifications: false,
        notificationTypes: ["booking_confirmed", "payment_successful", "system_maintenance"]
    )
}

struct SecuritySettings: Codable {
    let passwordMinLength: Int
    let passwordRequireSpecialChars: Bool
    let passwordRequireNumbers: Bool
    let passwordRequireUppercase: Bool
    let passwordExpiryDays: Int?
    let ipWhitelist: [String]?
    let enableRateLimiting: Bool
    let rateLimitRequests: Int
    let rateLimitWindow: Int // seconds
    
    static let `default` = SecuritySettings(
        passwordMinLength: 8,
        passwordRequireSpecialChars: false,
        passwordRequireNumbers: false,
        passwordRequireUppercase: false,
        passwordExpiryDays: nil,
        ipWhitelist: nil,
        enableRateLimiting: true,
        rateLimitRequests: 100,
        rateLimitWindow: 3600 // 1 hour
    )
}

// MARK: - Tenant Limits

struct TenantLimits: Codable {
    let apiCallsPerMonth: Int
    let storageGB: Int
    let bandwidthGB: Int
    let maxUsers: Int
    let maxCourses: Int
    let maxBookings: Int
    let maxChildTenants: Int
    let maxCustomDomains: Int
    let maxWebhooks: Int
    let supportLevel: SupportLevel
    let slaUptime: Double?
    let backupRetentionDays: Int
    
    static func `default`(for type: TenantType) -> TenantLimits {
        switch type {
        case .individual:
            return TenantLimits.individual
        case .smallBusiness:
            return TenantLimits.smallBusiness
        case .medium:
            return TenantLimits.medium
        case .enterprise:
            return TenantLimits.enterprise
        case .custom:
            return TenantLimits.custom
        }
    }
    
    static let individual = TenantLimits(
        apiCallsPerMonth: 5000,
        storageGB: 1,
        bandwidthGB: 5,
        maxUsers: 1,
        maxCourses: 5,
        maxBookings: 20,
        maxChildTenants: 0,
        maxCustomDomains: 0,
        maxWebhooks: 0,
        supportLevel: .email,
        slaUptime: nil,
        backupRetentionDays: 7
    )
    
    static let smallBusiness = TenantLimits(
        apiCallsPerMonth: 25000,
        storageGB: 10,
        bandwidthGB: 50,
        maxUsers: 5,
        maxCourses: 25,
        maxBookings: 500,
        maxChildTenants: 0,
        maxCustomDomains: 1,
        maxWebhooks: 2,
        supportLevel: .email,
        slaUptime: 0.95,
        backupRetentionDays: 14
    )
    
    static let medium = TenantLimits(
        apiCallsPerMonth: 100000,
        storageGB: 50,
        bandwidthGB: 200,
        maxUsers: 25,
        maxCourses: 100,
        maxBookings: 2000,
        maxChildTenants: 3,
        maxCustomDomains: 3,
        maxWebhooks: 5,
        supportLevel: .priority,
        slaUptime: 0.98,
        backupRetentionDays: 30
    )
    
    static let professional = TenantLimits(
        apiCallsPerMonth: 100000,
        storageGB: 50,
        bandwidthGB: 200,
        maxUsers: 25,
        maxCourses: 100,
        maxBookings: 1000,
        maxChildTenants: 0,
        maxCustomDomains: 2,
        maxWebhooks: 3,
        supportLevel: .priority,
        slaUptime: 0.97,
        backupRetentionDays: 30
    )
    
    static let enterprise = TenantLimits(
        apiCallsPerMonth: 1000000,
        storageGB: 500,
        bandwidthGB: 2000,
        maxUsers: 1000,
        maxCourses: 1000,
        maxBookings: 50000,
        maxChildTenants: 50,
        maxCustomDomains: 10,
        maxWebhooks: 20,
        supportLevel: .dedicated,
        slaUptime: 0.995,
        backupRetentionDays: 90
    )
    
    static let custom = TenantLimits(
        apiCallsPerMonth: Int.max,
        storageGB: Int.max,
        bandwidthGB: Int.max,
        maxUsers: Int.max,
        maxCourses: Int.max,
        maxBookings: Int.max,
        maxChildTenants: Int.max,
        maxCustomDomains: Int.max,
        maxWebhooks: Int.max,
        supportLevel: .dedicated,
        slaUptime: 0.999,
        backupRetentionDays: 365
    )
    
    static func childDefault(from parent: TenantLimits) -> TenantLimits {
        return TenantLimits(
            apiCallsPerMonth: parent.apiCallsPerMonth / 10,
            storageGB: parent.storageGB / 10,
            bandwidthGB: parent.bandwidthGB / 10,
            maxUsers: parent.maxUsers / 5,
            maxCourses: parent.maxCourses / 5,
            maxBookings: parent.maxBookings / 10,
            maxChildTenants: 0,
            maxCustomDomains: 0,
            maxWebhooks: parent.maxWebhooks / 5,
            supportLevel: parent.supportLevel,
            slaUptime: parent.slaUptime,
            backupRetentionDays: parent.backupRetentionDays
        )
    }
}

// MARK: - Custom Domain Models

struct CustomDomain: Codable {
    let domain: String
    var isVerified: Bool
    let verificationToken: String
    var sslCertificate: SSLCertificate?
    let addedAt: Date
    var verifiedAt: Date?
}

struct SSLCertificate: Codable {
    let certificate: String
    let privateKey: String
    let issuer: String
    let expiryDate: Date
    let isValid: Bool
}

struct DomainVerification: Codable {
    let domain: String
    let isVerified: Bool
    let verifiedAt: Date?
    let dnsRecords: [DNSRecord]
    let challenges: [DomainChallenge]
    
    #if DEBUG
    static let mock = DomainVerification(
        domain: "example.com",
        isVerified: true,
        verifiedAt: Date(),
        dnsRecords: [
            DNSRecord(type: "CNAME", name: "@", value: "app.golffinder.com", ttl: 300)
        ],
        challenges: [
            DomainChallenge(
                type: .dns,
                token: "verification_token_123",
                instructions: "Add this TXT record to verify domain"
            )
        ]
    )
    #endif
}

struct DNSRecord: Codable {
    let type: String
    let name: String
    let value: String
    let ttl: Int
}

struct DomainChallenge: Codable {
    let type: DomainChallengeType
    let token: String
    let instructions: String
}

enum DomainChallengeType: String, Codable {
    case dns = "dns"
    case http = "http"
}

// MARK: - Tenant Analytics Models

struct TenantMetrics: Codable {
    let tenantId: String
    let period: RevenuePeriod
    let activeUsers: Int
    let totalRevenue: Decimal
    let apiUsage: APIUsage
    let storageUsage: Double
    let bandwidth: Double
    let errorRate: Double
    let uptime: Double
    let responseTime: Double
    let customerSatisfaction: Double
    
    #if DEBUG
    static let mock = TenantMetrics(
        tenantId: "tenant_001",
        period: .monthly,
        activeUsers: 45,
        totalRevenue: 5600.00,
        apiUsage: APIUsage(
            tenantId: "tenant_001",
            apiCalls: 75000,
            storageUsed: 25.5,
            bandwidth: 120.0,
            period: Date(),
            breakdown: UsageBreakdown(
                endpoints: ["courses": 30000, "bookings": 25000, "users": 20000],
                methods: ["GET": 50000, "POST": 20000, "PUT": 4000, "DELETE": 1000],
                statusCodes: [200: 70000, 400: 3000, 500: 2000],
                errors: 5000,
                avgResponseTime: 125.0
            )
        ),
        storageUsage: 25.5,
        bandwidth: 120.0,
        errorRate: 0.067,
        uptime: 0.998,
        responseTime: 125.0,
        customerSatisfaction: 4.3
    )
    #endif
}

struct TenantUsage: Codable {
    let tenantId: String
    let period: RevenuePeriod
    let apiCalls: Int
    let storageUsed: Double
    let bandwidthUsed: Double
    let activeUsers: Int
    let limits: TenantLimits
    let overages: TenantOverages
    let projectedUsage: TenantUsageProjection
    let generatedAt: Date
    
    #if DEBUG
    static let mock = TenantUsage(
        tenantId: "tenant_001",
        period: .monthly,
        apiCalls: 75000,
        storageUsed: 25.5,
        bandwidthUsed: 120.0,
        activeUsers: 45,
        limits: TenantLimits.professional,
        overages: TenantOverages(
            apiCallsOverage: 0,
            storageOverage: 0,
            bandwidthOverage: 0,
            usersOverage: 0
        ),
        projectedUsage: TenantUsageProjection(
            projectedApiCalls: 82500,
            projectedStorage: 28.1,
            projectedBandwidth: 132.0,
            projectedUsers: 50,
            confidence: 0.85
        ),
        generatedAt: Date()
    )
    #endif
}

struct TenantOverages: Codable {
    let apiCallsOverage: Int
    let storageOverage: Double
    let bandwidthOverage: Double
    let usersOverage: Int
}

struct TenantUsageProjection: Codable {
    let projectedApiCalls: Int
    let projectedStorage: Double
    let projectedBandwidth: Double
    let projectedUsers: Int
    let confidence: Double
}

struct TenantHealthScore: Codable {
    let tenantId: String
    let score: Double
    let grade: HealthGrade
    let factors: [HealthFactor]
    let recommendations: [String]
    let trends: [HealthTrend]
    let lastCalculated: Date
    let nextCalculation: Date
    
    #if DEBUG
    static let mock = TenantHealthScore(
        tenantId: "tenant_001",
        score: 87.5,
        grade: .good,
        factors: [
            HealthFactor(name: "Uptime", value: 0.998, weight: 0.4, impact: 39.2),
            HealthFactor(name: "Error Rate", value: 0.933, weight: 0.3, impact: 28.0),
            HealthFactor(name: "Usage Efficiency", value: 0.75, weight: 0.2, impact: 15.0),
            HealthFactor(name: "Customer Satisfaction", value: 0.86, weight: 0.1, impact: 8.6)
        ],
        recommendations: [
            "Optimize API response times",
            "Implement better error handling",
            "Consider upgrading plan for better performance"
        ],
        trends: [
            HealthTrend(metric: "uptime", direction: .improving, change: 0.002),
            HealthTrend(metric: "errors", direction: .stable, change: 0.0),
            HealthTrend(metric: "satisfaction", direction: .improving, change: 0.1)
        ],
        lastCalculated: Date(),
        nextCalculation: Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
    )
    #endif
}

struct HealthFactor: Codable {
    let name: String
    let value: Double
    let weight: Double
    let impact: Double
}

struct HealthTrend: Codable {
    let metric: String
    let direction: TrendDirection
    let change: Double
}

// MARK: - Migration Models

struct MigrationOptions: Codable {
    let includeUsers: Bool
    let includeCourses: Bool
    let includeBookings: Bool
    let includeSettings: Bool
    let includeMetadata: Bool
    let validateData: Bool
    let createBackup: Bool
    
    static let dataTransfer = MigrationOptions(
        includeUsers: true,
        includeCourses: true,
        includeBookings: true,
        includeSettings: false,
        includeMetadata: true,
        validateData: true,
        createBackup: true
    )
    
    static let fullMigration = MigrationOptions(
        includeUsers: true,
        includeCourses: true,
        includeBookings: true,
        includeSettings: true,
        includeMetadata: true,
        validateData: true,
        createBackup: true
    )
}

struct MigrationResult: Codable {
    let migrationId: String
    let fromTenantId: String
    let toTenantId: String
    let status: MigrationStatus
    let startTime: Date
    let endTime: Date
    let migratedItems: [String]
    let errors: [String]
    let statistics: MigrationStatistics
    
    #if DEBUG
    static let mock = MigrationResult(
        migrationId: "migration_123",
        fromTenantId: "tenant_001",
        toTenantId: "tenant_002",
        status: .completed,
        startTime: Date().addingTimeInterval(-3600),
        endTime: Date(),
        migratedItems: ["users", "courses", "bookings"],
        errors: [],
        statistics: MigrationStatistics(
            totalItems: 3,
            successfulItems: 3,
            failedItems: 0
        )
    )
    #endif
}

struct MigrationStatistics: Codable {
    let totalItems: Int
    let successfulItems: Int
    let failedItems: Int
}

// MARK: - Export/Import Models

struct TenantExportData: Codable {
    let tenant: Tenant
    let users: [TenantUser]
    let courses: [TenantCourse]
    let bookings: [TenantBooking]
    let settings: TenantSettings
    let exportedAt: Date
}

struct TenantUser: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let role: String
    let createdAt: Date
}

struct TenantCourse: Codable, Identifiable {
    let id: String
    let name: String
    let location: String
    let holes: Int
    let par: Int
    let createdAt: Date
}

struct TenantBooking: Codable, Identifiable {
    let id: String
    let courseId: String
    let userId: String
    let teeTime: Date
    let players: Int
    let status: String
    let createdAt: Date
}

// MARK: - Enumerations

enum TenantStatus: String, CaseIterable, Codable {
    case active = "active"
    case inactive = "inactive"
    case suspended = "suspended"
    case deleted = "deleted"
    case provisioning = "provisioning"
    
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .inactive: return "Inactive"
        case .suspended: return "Suspended"
        case .deleted: return "Deleted"
        case .provisioning: return "Provisioning"
        }
    }
}

enum SuspensionReason: String, CaseIterable, Codable {
    case nonPayment = "non_payment"
    case violation = "violation"
    case security = "security"
    case abuse = "abuse"
    case maintenance = "maintenance"
    case requested = "requested"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .nonPayment: return "Non-Payment"
        case .violation: return "Terms Violation"
        case .security: return "Security Issue"
        case .abuse: return "Abuse"
        case .maintenance: return "Maintenance"
        case .requested: return "User Requested"
        case .other: return "Other"
        }
    }
}

enum LimitType: String, CaseIterable, Codable {
    case apiCalls = "api_calls"
    case storage = "storage"
    case bandwidth = "bandwidth"
    case users = "users"
    case courses = "courses"
    case bookings = "bookings"
    case customDomains = "custom_domains"
    case webhooks = "webhooks"
    
    var displayName: String {
        switch self {
        case .apiCalls: return "API Calls"
        case .storage: return "Storage"
        case .bandwidth: return "Bandwidth"
        case .users: return "Users"
        case .courses: return "Courses"
        case .bookings: return "Bookings"
        case .customDomains: return "Custom Domains"
        case .webhooks: return "Webhooks"
        }
    }
}

enum HealthGrade: String, CaseIterable, Codable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case critical = "critical"
    
    var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .critical: return "Critical"
        }
    }
    
    var color: String {
        switch self {
        case .excellent: return "#4CAF50"
        case .good: return "#8BC34A"
        case .fair: return "#FFC107"
        case .poor: return "#FF9800"
        case .critical: return "#F44336"
        }
    }
}

enum MigrationStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case partiallyCompleted = "partially_completed"
    case failed = "failed"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .partiallyCompleted: return "Partially Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Error Types

enum TenantError: Error, LocalizedError {
    case tenantNotFound(String)
    case invalidRequest(String)
    case slugAlreadyExists(String)
    case domainAlreadyExists(String)
    case domainNotFound(String)
    case invalidDomain(String)
    case invalidStatus(TenantStatus)
    case tenantNotActive(String)
    case accessDenied(String)
    case deletionNotAllowed(String)
    case childTenantsNotAllowed(String)
    case childTenantLimitReached(String)
    case provisioningFailed(String)
    case migrationFailed(String)
    case exportFailed(String)
    case importFailed(String)
    case healthCheckFailed(String)
    case networkError(Error)
    case authorizationError
    
    var errorDescription: String? {
        switch self {
        case .tenantNotFound(let id):
            return "Tenant with ID \(id) not found"
        case .invalidRequest(let message):
            return "Invalid tenant request: \(message)"
        case .slugAlreadyExists(let slug):
            return "Tenant slug '\(slug)' already exists"
        case .domainAlreadyExists(let domain):
            return "Domain '\(domain)' is already in use"
        case .domainNotFound(let domain):
            return "Domain '\(domain)' not found"
        case .invalidDomain(let domain):
            return "Invalid domain format: \(domain)"
        case .invalidStatus(let status):
            return "Invalid tenant status for this operation: \(status.rawValue)"
        case .tenantNotActive(let id):
            return "Tenant \(id) is not active"
        case .accessDenied(let id):
            return "Access denied to tenant: \(id)"
        case .deletionNotAllowed(let reason):
            return "Tenant deletion not allowed: \(reason)"
        case .childTenantsNotAllowed(let parentId):
            return "Parent tenant \(parentId) cannot have child tenants"
        case .childTenantLimitReached(let parentId):
            return "Child tenant limit reached for parent: \(parentId)"
        case .provisioningFailed(let message):
            return "Tenant provisioning failed: \(message)"
        case .migrationFailed(let message):
            return "Tenant migration failed: \(message)"
        case .exportFailed(let message):
            return "Tenant export failed: \(message)"
        case .importFailed(let message):
            return "Tenant import failed: \(message)"
        case .healthCheckFailed(let message):
            return "Tenant health check failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authorizationError:
            return "Authorization error: insufficient permissions"
        }
    }
}