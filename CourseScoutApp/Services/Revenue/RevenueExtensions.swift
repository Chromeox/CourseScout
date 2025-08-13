import Foundation
import Combine

// MARK: - Missing Types and Extensions

// Revenue Period enumeration
enum RevenuePeriod: String, CaseIterable, Codable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case quarterly = "quarterly"
    case yearly = "yearly"
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }
}

// Tenant Revenue structure
struct TenantRevenue: Codable {
    let tenantId: String
    let period: RevenuePeriod
    let totalRevenue: Decimal
    let subscriptionRevenue: Decimal
    let overageRevenue: Decimal
    let refunds: Decimal
    let netRevenue: Decimal
    let revenueGrowth: Double
    let generatedAt: Date
}

// Revenue Forecast structure
struct RevenueForecast: Codable {
    let period: Date
    let predictedRevenue: Decimal
    let confidence: Double
    let factors: [String]
}

// Revenue Breakdown structure
struct RevenueBreakdown: Codable {
    let subscriptions: Decimal
    let oneTimePayments: Decimal
    let overageCharges: Decimal
    let refunds: Decimal
    let taxes: Decimal
    let netRevenue: Decimal
    let byTier: [String: Decimal]
    let byRegion: [String: Decimal]
    
    #if DEBUG
    static let mock = RevenueBreakdown(
        subscriptions: 15000.00,
        oneTimePayments: 2500.00,
        overageCharges: 1200.00,
        refunds: -300.00,
        taxes: 1680.00,
        netRevenue: 17420.00,
        byTier: [
            "starter": 2000.00,
            "professional": 8000.00,
            "enterprise": 5000.00
        ],
        byRegion: [
            "US": 12000.00,
            "EU": 3000.00,
            "APAC": 2000.00
        ]
    )
    #endif
}

// Revenue Event structure
struct RevenueEvent: Codable {
    let id: String
    let type: RevenueEventType
    let tenantId: String
    let amount: Decimal
    let currency: String
    let timestamp: Date
    let metadata: [String: String]
}

// Revenue Event Type enumeration
enum RevenueEventType: String, CaseIterable, Codable {
    case subscriptionCreated = "subscription_created"
    case subscriptionUpgraded = "subscription_upgraded"
    case subscriptionDowngraded = "subscription_downgraded"
    case subscriptionCanceled = "subscription_canceled"
    case paymentSucceeded = "payment_succeeded"
    case paymentFailed = "payment_failed"
    case refundIssued = "refund_issued"
    case overageCharged = "overage_charged"
}

// Revenue Report structure
struct RevenueReport: Codable {
    let tenantId: String
    let period: RevenuePeriod
    let startDate: Date
    let endDate: Date
    let metrics: RevenueMetrics
    let breakdown: RevenueBreakdown
    let insights: [RevenueInsight]
    let recommendations: [RevenueOptimization]
    let generatedAt: Date
    
    #if DEBUG
    static let mock = RevenueReport(
        tenantId: "tenant_001",
        period: .monthly,
        startDate: Date().addingTimeInterval(-86400 * 30),
        endDate: Date(),
        metrics: RevenueMetrics.mock,
        breakdown: RevenueBreakdown.mock,
        insights: [RevenueInsight.mock],
        recommendations: [RevenueOptimization.mock],
        generatedAt: Date()
    )
    #endif
}

// Revenue Insight structure
struct RevenueInsight: Codable {
    let id: String
    let type: InsightType
    let title: String
    let description: String
    let impact: InsightImpact
    let confidence: Double
    let actionable: Bool
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = RevenueInsight(
        id: "insight_001",
        type: .growth,
        title: "Strong Q4 Performance",
        description: "Revenue increased 25% compared to previous quarter",
        impact: .high,
        confidence: 0.95,
        actionable: true,
        metadata: ["growth_rate": "0.25"]
    )
    #endif
}

// Insight Type enumeration
enum InsightType: String, CaseIterable, Codable {
    case growth = "growth"
    case decline = "decline"
    case seasonal = "seasonal"
    case anomaly = "anomaly"
    case opportunity = "opportunity"
    case risk = "risk"
}

// Insight Impact enumeration
enum InsightImpact: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

// Revenue Optimization structure
struct RevenueOptimization: Codable {
    let id: String
    let title: String
    let description: String
    let category: OptimizationCategory
    let potentialImpact: Decimal
    let effort: OptimizationEffort
    let priority: OptimizationPriority
    let actionItems: [String]
    
    #if DEBUG
    static let mock = RevenueOptimization(
        id: "opt_001",
        title: "Implement Usage-Based Pricing",
        description: "Add usage-based pricing tiers to capture more value from high-usage customers",
        category: .pricing,
        potentialImpact: 5000.00,
        effort: .medium,
        priority: .high,
        actionItems: [
            "Analyze usage patterns",
            "Design new pricing tiers",
            "Implement billing logic",
            "Migrate existing customers"
        ]
    )
    #endif
}

// Optimization Category enumeration
enum OptimizationCategory: String, CaseIterable, Codable {
    case pricing = "pricing"
    case retention = "retention"
    case acquisition = "acquisition"
    case upselling = "upselling"
    case cost = "cost"
    case product = "product"
}

// Optimization Effort enumeration
enum OptimizationEffort: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
}

// Optimization Priority enumeration
enum OptimizationPriority: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case urgent = "urgent"
}

// Usage Profile structure
struct UsageProfile: Codable {
    let tenantId: String
    let apiCallsPerMonth: Int
    let storageUsageGB: Double
    let bandwidthUsageGB: Double
    let activeUsers: Int
    let peakUsagePattern: String
    let features: [String]
}

// Subscription Request structure
struct SubscriptionRequest: Codable {
    let tenantId: String
    let customerId: String
    let tierId: String
    let billingCycle: BillingCycle
    let price: Decimal
    let currency: String
    let trialStart: Date?
    let trialEnd: Date?
    let metadata: [String: String]
}

// Subscription Update structure
struct SubscriptionUpdate: Codable {
    let status: SubscriptionStatus?
    let price: Decimal?
    let billingCycle: BillingCycle?
    let metadata: [String: String]?
}

// Cancellation Reason enumeration
enum CancellationReason: String, CaseIterable, Codable {
    case customerRequest = "customer_request"
    case nonPayment = "non_payment"
    case fraud = "fraud"
    case businessClosure = "business_closure"
    case featureLimitations = "feature_limitations"
    case pricing = "pricing"
    case competition = "competition"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .customerRequest: return "Customer Request"
        case .nonPayment: return "Non-Payment"
        case .fraud: return "Fraud"
        case .businessClosure: return "Business Closure"
        case .featureLimitations: return "Feature Limitations"
        case .pricing: return "Pricing"
        case .competition: return "Competition"
        case .other: return "Other"
        }
    }
}

// Subscription Event structure
struct SubscriptionEvent: Codable, Identifiable {
    let id: String
    let subscriptionId: String
    let type: SubscriptionEventType
    let description: String
    let timestamp: Date
    let metadata: [String: String]
}

// Subscription Event Type enumeration
enum SubscriptionEventType: String, CaseIterable, Codable {
    case created = "created"
    case activated = "activated"
    case upgraded = "upgraded"
    case downgraded = "downgraded"
    case paused = "paused"
    case resumed = "resumed"
    case canceled = "canceled"
    case renewed = "renewed"
    case failed = "failed"
}

// Proration Result structure
struct ProrationResult: Codable {
    let subscriptionId: String
    let oldTier: SubscriptionTier
    let newTier: SubscriptionTier
    let effectiveDate: Date
    let prorationAmount: Decimal
    let creditAmount: Decimal
    let chargeAmount: Decimal
    let nextBillingDate: Date
}

// Subscription Metrics structure
struct SubscriptionMetrics: Codable {
    let totalSubscriptions: Int
    let activeSubscriptions: Int
    let monthlyRecurringRevenue: Decimal
    let averageRevenuePerUser: Decimal
    let churnRate: Double
    let growthRate: Double
    let lifetimeValue: Decimal
}

// Payment Status enumeration
enum PaymentStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case processing = "processing"
    case succeeded = "succeeded"
    case failed = "failed"
    case canceled = "canceled"
    case refunded = "refunded"
    case disputed = "disputed"
}

// Trend Direction enumeration
enum TrendDirection: String, CaseIterable, Codable {
    case improving = "improving"
    case declining = "declining"
    case stable = "stable"
}

// MARK: - Security Enhancements

// Secure API Key structure with validation
struct SecureAPIKey: Codable {
    let keyId: String
    private let encryptedKey: String
    let permissions: [APIPermission]
    let expiresAt: Date?
    let lastUsedAt: Date?
    let createdAt: Date
    
    init(keyId: String, key: String, permissions: [APIPermission], expiresAt: Date? = nil) throws {
        guard !key.isEmpty else {
            throw SecurityError.invalidAPIKey("API key cannot be empty")
        }
        
        guard key.count >= 32 else {
            throw SecurityError.invalidAPIKey("API key must be at least 32 characters")
        }
        
        self.keyId = keyId
        self.encryptedKey = try SecurityUtils.encrypt(key)
        self.permissions = permissions
        self.expiresAt = expiresAt
        self.lastUsedAt = nil
        self.createdAt = Date()
    }
    
    func validateKey(_ providedKey: String) throws -> Bool {
        let decryptedKey = try SecurityUtils.decrypt(encryptedKey)
        return decryptedKey == providedKey
    }
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
}

// API Permission enumeration
enum APIPermission: String, CaseIterable, Codable {
    case read = "read"
    case write = "write"
    case delete = "delete"
    case admin = "admin"
    case billing = "billing"
    case analytics = "analytics"
}

// Security Error enumeration
enum SecurityError: Error, LocalizedError {
    case invalidAPIKey(String)
    case insufficientPermissions(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidInput(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey(let message):
            return "Invalid API key: \(message)"
        case .insufficientPermissions(let message):
            return "Insufficient permissions: \(message)"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        }
    }
}

// Security Utilities
struct SecurityUtils {
    static func encrypt(_ data: String) throws -> String {
        // Mock implementation - in production, use proper encryption
        guard !data.isEmpty else {
            throw SecurityError.encryptionFailed("Cannot encrypt empty data")
        }
        return "encrypted_\(data.hashValue)"
    }
    
    static func decrypt(_ encryptedData: String) throws -> String {
        // Mock implementation - in production, use proper decryption
        guard encryptedData.hasPrefix("encrypted_") else {
            throw SecurityError.decryptionFailed("Invalid encrypted data format")
        }
        return String(encryptedData.dropFirst("encrypted_".count))
    }
    
    static func validateInput(_ input: String, maxLength: Int = 1000) throws {
        guard !input.isEmpty else {
            throw SecurityError.invalidInput("Input cannot be empty")
        }
        
        guard input.count <= maxLength else {
            throw SecurityError.invalidInput("Input exceeds maximum length of \(maxLength)")
        }
        
        // Check for potential injection attacks
        let dangerousPatterns = ["<script", "javascript:", "onload=", "onerror=", "SELECT ", "INSERT ", "UPDATE ", "DELETE "]
        for pattern in dangerousPatterns {
            if input.localizedCaseInsensitiveContains(pattern) {
                throw SecurityError.invalidInput("Input contains potentially dangerous content")
            }
        }
    }
}

// MARK: - Performance Enhancements

// Cached Result wrapper for performance optimization
struct CachedResult<T: Codable>: Codable {
    let data: T
    let cachedAt: Date
    let expiresAt: Date
    
    init(data: T, cacheLifetime: TimeInterval = 300) { // 5 minutes default
        self.data = data
        self.cachedAt = Date()
        self.expiresAt = Date().addingTimeInterval(cacheLifetime)
    }
    
    var isValid: Bool {
        return Date() < expiresAt
    }
}

// Performance Metrics structure
struct PerformanceMetrics: Codable {
    let operationName: String
    let executionTime: TimeInterval
    let memoryUsage: UInt64?
    let cacheHitRate: Double?
    let errorRate: Double?
    let timestamp: Date
    
    init(operationName: String, executionTime: TimeInterval) {
        self.operationName = operationName
        self.executionTime = executionTime
        self.memoryUsage = nil
        self.cacheHitRate = nil
        self.errorRate = nil
        self.timestamp = Date()
    }
}

// Performance Monitor
class PerformanceMonitor {
    private static var metrics: [PerformanceMetrics] = []
    
    static func track<T>(operation: String, block: () throws -> T) rethrows -> T {
        let startTime = Date()
        let result = try block()
        let executionTime = Date().timeIntervalSince(startTime)
        
        let metric = PerformanceMetrics(operationName: operation, executionTime: executionTime)
        metrics.append(metric)
        
        // Log slow operations
        if executionTime > 1.0 {
            print("⚠️ Slow operation detected: \(operation) took \(executionTime)s")
        }
        
        return result
    }
    
    static func getMetrics() -> [PerformanceMetrics] {
        return metrics
    }
    
    static func clearMetrics() {
        metrics.removeAll()
    }
}