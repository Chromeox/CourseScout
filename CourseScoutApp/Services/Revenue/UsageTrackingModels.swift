import Foundation
import Combine

// MARK: - Core Usage Models

struct APIUsageSnapshot: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let tenantId: String
    let endpoint: String
    let method: HTTPMethod
    let statusCode: Int
    let responseTime: TimeInterval
    let dataSize: Int
}

struct EndpointUsage: Codable {
    let endpoint: String
    var requestCount: Int
    let period: Date
}

// MARK: - Rate Limiting Models

struct RateLimits: Codable {
    let globalLimit: Int
    let globalWindow: TimeInterval
    let endpointLimits: [String: EndpointRateLimit]
}

struct EndpointRateLimit: Codable {
    let limit: Int
    let window: TimeInterval
}

struct RateLimitResult: Codable {
    let allowed: Bool
    let limit: Int
    let remaining: Int
    let resetTime: Date
    let retryAfter: TimeInterval
    
    #if DEBUG
    static let mock = RateLimitResult(
        allowed: true,
        limit: 1000,
        remaining: 750,
        resetTime: Date().addingTimeInterval(3600),
        retryAfter: 0
    )
    #endif
}

struct RateLimitStatus: Codable {
    let tenantId: String
    let globalLimit: Int
    let globalUsed: Int
    let globalRemaining: Int
    let globalResetTime: Date
    let endpointStatuses: [String: EndpointRateLimitStatus]
    let lastUpdated: Date
    
    #if DEBUG
    static let mock = RateLimitStatus(
        tenantId: "tenant_001",
        globalLimit: 1000,
        globalUsed: 250,
        globalRemaining: 750,
        globalResetTime: Date().addingTimeInterval(3600),
        endpointStatuses: [
            "courses": EndpointRateLimitStatus(
                endpoint: "courses",
                limit: 100,
                used: 25,
                remaining: 75,
                resetTime: Date().addingTimeInterval(300)
            )
        ],
        lastUpdated: Date()
    )
    #endif
}

struct EndpointRateLimitStatus: Codable {
    let endpoint: String
    let limit: Int
    let used: Int
    let remaining: Int
    let resetTime: Date
}

// MARK: - Quota Management Models

struct QuotaResult: Codable {
    let allowed: Bool
    let quotaType: QuotaType
    let limit: Int
    let used: Int
    let remaining: Int
    let period: QuotaPeriod
    let resetTime: Date
    
    #if DEBUG
    static let mock = QuotaResult(
        allowed: true,
        quotaType: .apiCalls,
        limit: 100000,
        used: 75000,
        remaining: 25000,
        period: .monthly,
        resetTime: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    )
    #endif
}

struct QuotaStatus: Codable {
    let quotaType: QuotaType
    let limit: Int
    let used: Int
    let remaining: Int
    let period: QuotaPeriod
    let resetTime: Date
    let lastUpdated: Date
    
    #if DEBUG
    static let mock = QuotaStatus(
        quotaType: .apiCalls,
        limit: 100000,
        used: 75000,
        remaining: 25000,
        period: .monthly,
        resetTime: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date(),
        lastUpdated: Date()
    )
    #endif
}

// MARK: - Usage Analytics Models

struct UsageAnalytics: Codable {
    let tenantId: String
    let period: RevenuePeriod
    let totalAPICalls: Int
    let uniqueEndpoints: Int
    let averageResponseTime: Double
    let errorRate: Double
    let peakUsageHour: Int
    let peakUsageDay: Int
    let topEndpoints: [(String, Int)]
    let bandwidthUsed: Double
    let costEstimate: UsageCosts
    let generatedAt: Date
    
    #if DEBUG
    static let mock = UsageAnalytics(
        tenantId: "tenant_001",
        period: .monthly,
        totalAPICalls: 75000,
        uniqueEndpoints: 15,
        averageResponseTime: 125.5,
        errorRate: 0.032,
        peakUsageHour: 14,
        peakUsageDay: 3,
        topEndpoints: [("courses", 30000), ("bookings", 25000), ("users", 20000)],
        bandwidthUsed: 1250.5,
        costEstimate: UsageCosts.mock,
        generatedAt: Date()
    )
    #endif
}

struct UsageTrend: Codable {
    let timestamp: Date
    let metric: UsageMetric
    let value: Double
}

struct UsageAnomaly: Codable, Identifiable {
    let id: String
    let tenantId: String
    let type: UsageAnomalyType
    let metric: UsageMetric
    let timestamp: Date
    let value: Double
    let expectedValue: Double
    let severity: AnomalySeverity
    let description: String
}

struct UsagePrediction: Codable {
    let tenantId: String
    let predictionPeriod: Int
    let predictions: [UsagePredictionPoint]
    let model: String
    let accuracy: Double
    let generatedAt: Date
    
    #if DEBUG
    static let mock = UsagePrediction(
        tenantId: "tenant_001",
        predictionPeriod: 30,
        predictions: [
            UsagePredictionPoint(
                date: Date().addingTimeInterval(86400),
                predictedAPICalls: 2500,
                confidence: 0.87
            )
        ],
        model: "linear_regression",
        accuracy: 0.85,
        generatedAt: Date()
    )
    #endif
}

struct UsagePredictionPoint: Codable {
    let date: Date
    let predictedAPICalls: Int
    let confidence: Double
}

// MARK: - Billing & Cost Models

struct UsageCosts: Codable {
    let tenantId: String
    let period: RevenuePeriod
    let totalCost: Decimal
    let breakdown: [String: Decimal]
    let overageCharges: [OverageCharge]
    let currency: String
    let calculatedAt: Date
    
    #if DEBUG
    static let mock = UsageCosts(
        tenantId: "tenant_001",
        period: .monthly,
        totalCost: 25.50,
        breakdown: [
            "api_calls": 15.00,
            "storage": 10.50
        ],
        overageCharges: [],
        currency: "USD",
        calculatedAt: Date()
    )
    #endif
}

struct OverageCharge: Codable {
    let type: OverageType
    let quantity: Int
    let rate: Decimal
    let amount: Decimal
    let description: String
}

// MARK: - Alert & Monitoring Models

struct UsageAlert: Codable, Identifiable {
    let id: String
    let tenantId: String
    let threshold: UsageThreshold
    let enabled: Bool
    let channels: [NotificationChannel]
    let createdAt: Date
    let lastTriggered: Date?
}

struct UsageThreshold: Codable {
    let type: UsageThresholdType
    let percentage: Double
    let value: Double?
}

struct ThresholdViolation: Codable {
    let alertId: String
    let threshold: UsageThreshold
    let currentValue: Double
    let limit: Double
    let percentage: Double
    let severity: AnomalySeverity
    let detectedAt: Date
}

// MARK: - Export Models

struct UsageExportData: Codable {
    let tenantId: String
    let period: RevenuePeriod
    let currentUsage: APIUsage
    let history: [APIUsageSnapshot]
    let analytics: UsageAnalytics
    let exportedAt: Date
}

// MARK: - HTTP Models

enum HTTPMethod: String, CaseIterable, Codable {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
    case HEAD = "HEAD"
    case OPTIONS = "OPTIONS"
}

// MARK: - Enumerations

enum QuotaType: String, CaseIterable, Codable {
    case apiCalls = "api_calls"
    case storage = "storage"
    case users = "users"
    case courses = "courses"
    case bookings = "bookings"
    
    var displayName: String {
        switch self {
        case .apiCalls: return "API Calls"
        case .storage: return "Storage"
        case .users: return "Users"
        case .courses: return "Courses"
        case .bookings: return "Bookings"
        }
    }
}

enum QuotaPeriod: String, CaseIterable, Codable {
    case hourly = "hourly"
    case daily = "daily"
    case monthly = "monthly"
    
    var displayName: String {
        switch self {
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        case .monthly: return "Monthly"
        }
    }
}

enum UsageMetric: String, CaseIterable, Codable {
    case apiCalls = "api_calls"
    case responseTime = "response_time"
    case errorRate = "error_rate"
    case bandwidth = "bandwidth"
    
    var displayName: String {
        switch self {
        case .apiCalls: return "API Calls"
        case .responseTime: return "Response Time"
        case .errorRate: return "Error Rate"
        case .bandwidth: return "Bandwidth"
        }
    }
    
    var unit: String {
        switch self {
        case .apiCalls: return "calls"
        case .responseTime: return "ms"
        case .errorRate: return "%"
        case .bandwidth: return "MB"
        }
    }
}

enum UsageAnomalyType: String, CaseIterable, Codable {
    case suddenSpike = "sudden_spike"
    case suddenDrop = "sudden_drop"
    case highErrorRate = "high_error_rate"
    case slowResponse = "slow_response"
    case unusualPattern = "unusual_pattern"
    
    var displayName: String {
        switch self {
        case .suddenSpike: return "Sudden Spike"
        case .suddenDrop: return "Sudden Drop"
        case .highErrorRate: return "High Error Rate"
        case .slowResponse: return "Slow Response"
        case .unusualPattern: return "Unusual Pattern"
        }
    }
}

enum AnomalySeverity: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
    
    var color: String {
        switch self {
        case .low: return "#4CAF50"
        case .medium: return "#FF9800"
        case .high: return "#FF5722"
        case .critical: return "#F44336"
        }
    }
}

enum OverageType: String, CaseIterable, Codable {
    case apiCalls = "api_calls"
    case storage = "storage"
    case bandwidth = "bandwidth"
    case users = "users"
    
    var displayName: String {
        switch self {
        case .apiCalls: return "API Calls"
        case .storage: return "Storage"
        case .bandwidth: return "Bandwidth"
        case .users: return "Users"
        }
    }
}

enum UsageThresholdType: String, CaseIterable, Codable {
    case apiCalls = "api_calls"
    case storage = "storage"
    case bandwidth = "bandwidth"
    case errorRate = "error_rate"
    
    var displayName: String {
        switch self {
        case .apiCalls: return "API Calls"
        case .storage: return "Storage"
        case .bandwidth: return "Bandwidth"
        case .errorRate: return "Error Rate"
        }
    }
}

enum NotificationChannel: String, CaseIterable, Codable {
    case email = "email"
    case webhook = "webhook"
    case push = "push"
    case slack = "slack"
    
    var displayName: String {
        switch self {
        case .email: return "Email"
        case .webhook: return "Webhook"
        case .push: return "Push Notification"
        case .slack: return "Slack"
        }
    }
}

// MARK: - Extensions

extension APIUsage {
    static func empty(tenantId: String) -> APIUsage {
        return APIUsage(
            tenantId: tenantId,
            apiCalls: 0,
            storageUsed: 0.0,
            bandwidth: 0.0,
            period: Date(),
            breakdown: UsageBreakdown(
                endpoints: [:],
                methods: [:],
                statusCodes: [:],
                errors: 0,
                avgResponseTime: 0.0
            )
        )
    }
}

// MARK: - Error Types

enum UsageTrackingError: Error, LocalizedError {
    case tenantNotFound(String)
    case rateLimitExceeded(String, String)
    case quotaExceeded(String, QuotaType)
    case invalidConfiguration(String)
    case insufficientData(String)
    case exportFailed(String)
    case anomalyDetectionFailed(String)
    case predictionFailed(String)
    case alertConfigurationFailed(String)
    case networkError(Error)
    case authorizationError
    
    var errorDescription: String? {
        switch self {
        case .tenantNotFound(let tenantId):
            return "Tenant with ID \(tenantId) not found"
        case .rateLimitExceeded(let tenantId, let endpoint):
            return "Rate limit exceeded for tenant \(tenantId) on endpoint \(endpoint)"
        case .quotaExceeded(let tenantId, let quotaType):
            return "Quota exceeded for tenant \(tenantId): \(quotaType.displayName)"
        case .invalidConfiguration(let message):
            return "Invalid usage tracking configuration: \(message)"
        case .insufficientData(let message):
            return "Insufficient data for analysis: \(message)"
        case .exportFailed(let message):
            return "Usage data export failed: \(message)"
        case .anomalyDetectionFailed(let message):
            return "Anomaly detection failed: \(message)"
        case .predictionFailed(let message):
            return "Usage prediction failed: \(message)"
        case .alertConfigurationFailed(let message):
            return "Alert configuration failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authorizationError:
            return "Authorization error: insufficient permissions"
        }
    }
}

// MARK: - Utility Extensions

extension Array where Element == (String, Int) {
    static func + (lhs: [(String, Int)], rhs: [(String, Int)]) -> [(String, Int)] {
        var result = Dictionary<String, Int>()
        
        for (key, value) in lhs {
            result[key] = (result[key] ?? 0) + value
        }
        
        for (key, value) in rhs {
            result[key] = (result[key] ?? 0) + value
        }
        
        return result.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}