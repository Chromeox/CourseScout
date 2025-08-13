import Foundation
import Combine

// MARK: - Subscription Models

struct Subscription: Codable, Identifiable {
    let id: String
    var tenantId: String
    let customerId: String
    var tier: SubscriptionTier
    let billingCycle: BillingCycle
    var status: SubscriptionStatus
    let currentPeriodStart: Date
    var currentPeriodEnd: Date
    let createdAt: Date
    var updatedAt: Date?
    var cancelledAt: Date?
    var pausedAt: Date?
    var pausedUntil: Date?
    var billingAmount: Decimal
    let currency: String
    let paymentMethodId: String
    var lastBillingDate: Date?
    var nextBillingDate: Date?
    var stripeSubscriptionId: String?
    var cancellationReason: CancellationReason?
    var discounts: [Discount]?
    var pendingTierChange: PendingTierChange?
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = Subscription(
        id: "sub_123",
        tenantId: "tenant_456",
        customerId: "cus_789",
        tier: SubscriptionTier.professional,
        billingCycle: .monthly,
        status: .active,
        currentPeriodStart: Date(),
        currentPeriodEnd: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date(),
        createdAt: Date(),
        billingAmount: 99.00,
        currency: "USD",
        paymentMethodId: "pm_123",
        metadata: [:]
    )
    #endif
}

struct SubscriptionRequest: Codable {
    let tenantId: String
    let customerId: String
    let tierId: String
    let billingCycle: BillingCycle
    let paymentMethodId: String
    let currency: String?
    let metadata: [String: String]
}

struct SubscriptionUpdate: Codable {
    let paymentMethodId: String?
    let billingCycle: BillingCycle?
    let metadata: [String: String]?
}

struct PendingTierChange: Codable {
    let newTier: SubscriptionTier
    let effectiveDate: Date
    let changeType: TierChangeType
    let createdAt: Date = Date()
}

// MARK: - Subscription Tier

struct SubscriptionTier: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let price: Decimal
    let currency: String
    let limits: TierLimits
    let features: [String]
    let overageRates: OverageRates
    let availableForTenantTypes: [TenantType]
    let isCustom: Bool
    let billingCycles: [BillingCycle]
    let metadata: [String: String]
    
    // Predefined tiers
    static let starter = SubscriptionTier(
        id: "starter",
        name: "starter",
        displayName: "Starter",
        description: "Perfect for individuals and small teams",
        price: 29.00,
        currency: "USD",
        limits: TierLimits(
            apiCallsPerMonth: 10000,
            storageGB: 5,
            maxUsers: 3,
            maxCourses: 10,
            maxBookings: 50,
            supportLevel: .email
        ),
        features: [
            "Basic course management",
            "Simple booking system",
            "Email support",
            "Mobile app access",
            "Basic analytics"
        ],
        overageRates: OverageRates(
            apiCallRate: 0.001,
            storageRate: 2.00,
            userRate: 10.00
        ),
        availableForTenantTypes: [.individual, .smallBusiness],
        isCustom: false,
        billingCycles: [.monthly, .yearly],
        metadata: [:]
    )
    
    static let professional = SubscriptionTier(
        id: "professional",
        name: "professional",
        displayName: "Professional",
        description: "Advanced features for growing golf businesses",
        price: 99.00,
        currency: "USD",
        limits: TierLimits(
            apiCallsPerMonth: 100000,
            storageGB: 50,
            maxUsers: 25,
            maxCourses: 100,
            maxBookings: 1000,
            supportLevel: .priority
        ),
        features: [
            "Advanced course management",
            "Comprehensive booking system",
            "Multi-location support",
            "Advanced analytics",
            "Priority support",
            "White-label options",
            "API access",
            "Custom integrations"
        ],
        overageRates: OverageRates(
            apiCallRate: 0.0008,
            storageRate: 1.50,
            userRate: 8.00
        ),
        availableForTenantTypes: [.smallBusiness, .medium, .enterprise],
        isCustom: false,
        billingCycles: [.monthly, .quarterly, .yearly],
        metadata: [:]
    )
    
    static let enterprise = SubscriptionTier(
        id: "enterprise",
        name: "enterprise",
        displayName: "Enterprise",
        description: "Full-featured solution for large organizations",
        price: 299.00,
        currency: "USD",
        limits: TierLimits(
            apiCallsPerMonth: 1000000,
            storageGB: 500,
            maxUsers: 1000,
            maxCourses: 1000,
            maxBookings: 10000,
            supportLevel: .dedicated
        ),
        features: [
            "Unlimited course management",
            "Enterprise booking system",
            "Multi-tenant architecture",
            "Advanced analytics & reporting",
            "Dedicated support",
            "Complete white-labeling",
            "Full API access",
            "Custom development",
            "SLA guarantees",
            "Advanced security"
        ],
        overageRates: OverageRates(
            apiCallRate: 0.0005,
            storageRate: 1.00,
            userRate: 5.00
        ),
        availableForTenantTypes: [.enterprise, .custom],
        isCustom: false,
        billingCycles: [.monthly, .quarterly, .yearly],
        metadata: [:]
    )
    
    static let custom = SubscriptionTier(
        id: "custom",
        name: "custom",
        displayName: "Custom",
        description: "Tailored solution for unique requirements",
        price: 999.00,
        currency: "USD",
        limits: TierLimits(
            apiCallsPerMonth: Int.max,
            storageGB: Int.max,
            maxUsers: Int.max,
            maxCourses: Int.max,
            maxBookings: Int.max,
            supportLevel: .dedicated
        ),
        features: [
            "Unlimited everything",
            "Custom development",
            "Dedicated infrastructure",
            "24/7 dedicated support",
            "Custom SLA",
            "On-premise options",
            "Complete customization"
        ],
        overageRates: OverageRates(
            apiCallRate: 0.0001,
            storageRate: 0.50,
            userRate: 3.00
        ),
        availableForTenantTypes: [.custom],
        isCustom: true,
        billingCycles: [.monthly, .quarterly, .yearly],
        metadata: [:]
    )
}

struct TierLimits: Codable {
    let apiCallsPerMonth: Int
    let storageGB: Int
    let maxUsers: Int
    let maxCourses: Int
    let maxBookings: Int
    let supportLevel: SupportLevel
}

struct OverageRates: Codable {
    let apiCallRate: Decimal // Per API call
    let storageRate: Decimal // Per GB per month
    let userRate: Decimal // Per additional user per month
}

// MARK: - Billing Models

struct BillingResult: Codable {
    let id: String
    let amount: Decimal
    let currency: String
    let status: PaymentStatus
    let externalId: String? // Stripe payment intent ID
    let processedAt: Date
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = BillingResult(
        id: "bill_123",
        amount: 99.00,
        currency: "USD",
        status: .succeeded,
        externalId: "pi_123",
        processedAt: Date(),
        metadata: [:]
    )
    #endif
}

struct UpcomingCharge: Codable, Identifiable {
    let id: String
    let amount: Decimal
    let currency: String
    let description: String
    let dueDate: Date
    let type: ChargeType
    
    #if DEBUG
    static let mock = UpcomingCharge(
        id: "charge_123",
        amount: 99.00,
        currency: "USD",
        description: "Monthly subscription",
        dueDate: Date(),
        type: .subscription
    )
    #endif
}

struct Discount: Codable, Identifiable {
    let id: String
    let name: String
    let type: DiscountType
    let value: Decimal
    let validFrom: Date
    let validUntil: Date?
    let maxUses: Int?
    let currentUses: Int
    let applicableToTiers: [String]?
    let createdAt: Date
}

// MARK: - Analytics Models

struct SubscriptionMetrics: Codable {
    let totalSubscriptions: Int
    let activeSubscriptions: Int
    let newSubscriptions: Int
    let cancelledSubscriptions: Int
    let churnRate: Double
    let averageRevenuePerUser: Decimal
    let lifetimeValue: Decimal
    let subscriptionsByTier: [String: Int]
    let retentionRate: Double
    let upgradeRate: Double
    let downgradeRate: Double
    
    #if DEBUG
    static let mock = SubscriptionMetrics(
        totalSubscriptions: 150,
        activeSubscriptions: 142,
        newSubscriptions: 15,
        cancelledSubscriptions: 8,
        churnRate: 0.056,
        averageRevenuePerUser: 125.50,
        lifetimeValue: 2510.00,
        subscriptionsByTier: ["starter": 45, "professional": 67, "enterprise": 30],
        retentionRate: 0.944,
        upgradeRate: 0.12,
        downgradeRate: 0.03
    )
    #endif
}

struct ChurnAnalysis: Codable {
    let totalChurned: Int
    let churnRate: Double
    let churnReasons: [CancellationReason: Int]
    let churnByTier: [String: Int]
    let averageLifespan: TimeInterval
    let predictedChurn: [String: Double]
    let retentionStrategies: [String]
    
    #if DEBUG
    static let mock = ChurnAnalysis(
        totalChurned: 8,
        churnRate: 0.056,
        churnReasons: [.price: 3, .featureLack: 2, .competitor: 2, .other: 1],
        churnByTier: ["starter": 5, "professional": 2, "enterprise": 1],
        averageLifespan: 86400 * 365, // 1 year
        predictedChurn: ["high_risk": 0.15, "medium_risk": 0.25, "low_risk": 0.60],
        retentionStrategies: ["Improve onboarding", "Feature requests", "Competitive pricing"]
    )
    #endif
}

struct SubscriptionForecast: Codable {
    let month: Date
    let predictedSubscriptions: Int
    let predictedRevenue: Decimal
    let predictedChurn: Int
    let confidence: Double
    
    #if DEBUG
    static let mock = SubscriptionForecast(
        month: Date(),
        predictedSubscriptions: 165,
        predictedRevenue: 20700.00,
        predictedChurn: 9,
        confidence: 0.87
    )
    #endif
}

// MARK: - Usage Models

struct UsageProfile: Codable {
    let apiCallsPerMonth: Int
    let storageGB: Double
    let usersCount: Int
    let peakUsageTime: Date?
    let averageSessionDuration: TimeInterval
    let features: [String]
}

struct APIUsage: Codable {
    let tenantId: String
    let apiCalls: Int
    let storageUsed: Double
    let bandwidth: Double
    let period: Date
    let breakdown: UsageBreakdown
}

struct UsageBreakdown: Codable {
    let endpoints: [String: Int]
    let methods: [String: Int]
    let statusCodes: [Int: Int]
    let errors: Int
    let avgResponseTime: Double
}

// MARK: - Enumerations

enum SubscriptionStatus: String, CaseIterable, Codable {
    case active = "active"
    case inactive = "inactive"
    case cancelled = "cancelled"
    case paused = "paused"
    case pastDue = "past_due"
    case trialing = "trialing"
    case incomplete = "incomplete"
}

enum BillingCycle: String, CaseIterable, Codable {
    case monthly = "monthly"
    case quarterly = "quarterly"
    case yearly = "yearly"
    
    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }
    
    var months: Int {
        switch self {
        case .monthly: return 1
        case .quarterly: return 3
        case .yearly: return 12
        }
    }
}

enum CancellationReason: String, CaseIterable, Codable {
    case userRequested = "user_requested"
    case paymentFailed = "payment_failed"
    case fraudulent = "fraudulent"
    case other = "other"
    case price = "price"
    case featureLack = "feature_lack"
    case competitor = "competitor"
    case businessClosure = "business_closure"
    case downgrade = "downgrade"
    case duplicate = "duplicate"
    
    var displayName: String {
        switch self {
        case .userRequested: return "User Requested"
        case .paymentFailed: return "Payment Failed"
        case .fraudulent: return "Fraudulent Activity"
        case .other: return "Other"
        case .price: return "Price Concerns"
        case .featureLack: return "Missing Features"
        case .competitor: return "Competitor"
        case .businessClosure: return "Business Closure"
        case .downgrade: return "Downgrade"
        case .duplicate: return "Duplicate Account"
        }
    }
}

enum TierChangeType: String, CaseIterable, Codable {
    case upgrade = "upgrade"
    case downgrade = "downgrade"
    case change = "change"
}

enum TenantType: String, CaseIterable, Codable {
    case individual = "individual"
    case smallBusiness = "small_business"
    case medium = "medium"
    case enterprise = "enterprise"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .individual: return "Individual"
        case .smallBusiness: return "Small Business"
        case .medium: return "Medium Business"
        case .enterprise: return "Enterprise"
        case .custom: return "Custom"
        }
    }
}

enum SupportLevel: String, CaseIterable, Codable {
    case email = "email"
    case priority = "priority"
    case dedicated = "dedicated"
    
    var displayName: String {
        switch self {
        case .email: return "Email Support"
        case .priority: return "Priority Support"
        case .dedicated: return "Dedicated Support"
        }
    }
}

enum PaymentStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case processing = "processing"
    case succeeded = "succeeded"
    case failed = "failed"
    case cancelled = "cancelled"
    case refunded = "refunded"
}

enum ChargeType: String, CaseIterable, Codable {
    case subscription = "subscription"
    case usage = "usage"
    case setup = "setup"
    case addon = "addon"
    case tax = "tax"
    case discount = "discount"
}

enum DiscountType: String, CaseIterable, Codable {
    case percentage = "percentage"
    case fixed = "fixed"
    
    var displayName: String {
        switch self {
        case .percentage: return "Percentage"
        case .fixed: return "Fixed Amount"
        }
    }
}

// MARK: - Error Types

enum SubscriptionError: Error, LocalizedError {
    case subscriptionNotFound(String)
    case invalidRequest(String)
    case invalidTier(String)
    case invalidStatus(SubscriptionStatus)
    case invalidUpgrade(from: String, to: String)
    case invalidDowngrade(from: String, to: String)
    case tenantNotFound(String)
    case billingFailed(Error)
    case renewalFailed(Error)
    case subscriptionLimitReached(String)
    case paymentMethodRequired
    case tierNotAvailable(String)
    case cancellationNotAllowed
    case pauseNotAllowed
    case resumeNotAllowed
    case transferNotAllowed
    case networkError(Error)
    case authorizationError
    
    var errorDescription: String? {
        switch self {
        case .subscriptionNotFound(let id):
            return "Subscription with ID \(id) not found"
        case .invalidRequest(let message):
            return "Invalid subscription request: \(message)"
        case .invalidTier(let tierId):
            return "Invalid subscription tier: \(tierId)"
        case .invalidStatus(let status):
            return "Invalid subscription status for this operation: \(status.rawValue)"
        case .invalidUpgrade(let from, let to):
            return "Cannot upgrade from \(from) to \(to)"
        case .invalidDowngrade(let from, let to):
            return "Cannot downgrade from \(from) to \(to)"
        case .tenantNotFound(let id):
            return "Tenant with ID \(id) not found"
        case .billingFailed(let error):
            return "Billing failed: \(error.localizedDescription)"
        case .renewalFailed(let error):
            return "Renewal failed: \(error.localizedDescription)"
        case .subscriptionLimitReached(let tenantId):
            return "Subscription limit reached for tenant: \(tenantId)"
        case .paymentMethodRequired:
            return "Payment method is required"
        case .tierNotAvailable(let tier):
            return "Subscription tier not available: \(tier)"
        case .cancellationNotAllowed:
            return "Cancellation is not allowed for this subscription"
        case .pauseNotAllowed:
            return "Pausing is not allowed for this subscription"
        case .resumeNotAllowed:
            return "Resuming is not allowed for this subscription"
        case .transferNotAllowed:
            return "Transfer is not allowed for this subscription"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authorizationError:
            return "Authorization error: insufficient permissions"
        }
    }
}