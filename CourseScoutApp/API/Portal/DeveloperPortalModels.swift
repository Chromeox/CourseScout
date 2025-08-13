import Foundation
import Appwrite
import CryptoKit

// MARK: - API Versioning and Tiers

enum APIVersion: String, CaseIterable, Codable {
    case v1 = "v1"
    case v2 = "v2"
    
    var displayName: String {
        return rawValue.uppercased()
    }
    
    var isDeprecated: Bool {
        // v1 will be deprecated in the future
        return self == .v1
    }
}

enum APITier: String, CaseIterable, Codable {
    case free = "free"
    case premium = "premium" 
    case enterprise = "enterprise"
    case business = "business"
    
    var displayName: String {
        return rawValue.capitalized
    }
    
    var priority: Int {
        switch self {
        case .free: return 1
        case .premium: return 2
        case .enterprise: return 3
        case .business: return 4
        }
    }
    
    var dailyRequestLimit: Int {
        switch self {
        case .free: return 1000
        case .premium: return 10000
        case .enterprise: return 100000
        case .business: return -1 // Unlimited
        }
    }
    
    var rateLimitPerMinute: Int {
        switch self {
        case .free: return 16
        case .premium: return 167
        case .enterprise: return 1667
        case .business: return -1 // Unlimited
        }
    }
    
    var maxAPIKeys: Int {
        switch self {
        case .free: return 2
        case .premium: return 5
        case .enterprise: return 20
        case .business: return 50
        }
    }
    
    var supportLevel: String {
        switch self {
        case .free: return "Community"
        case .premium: return "Email"
        case .enterprise: return "Priority"
        case .business: return "Dedicated"
        }
    }
    
    var monthlyPrice: Double {
        switch self {
        case .free: return 0.0
        case .premium: return 29.0
        case .enterprise: return 199.0
        case .business: return 999.0
        }
    }
}

// MARK: - OAuth Integration Models

enum OAuthProvider: String, CaseIterable, Codable {
    case google = "google"
    case github = "github"
    case microsoft = "microsoft"
    case apple = "apple"
    
    var displayName: String {
        switch self {
        case .google: return "Google"
        case .github: return "GitHub"
        case .microsoft: return "Microsoft"
        case .apple: return "Apple"
        }
    }
    
    var iconName: String {
        return rawValue
    }
}

struct OAuthValidationResult {
    let isValid: Bool
    let provider: OAuthProvider
    let userId: String
    let email: String?
    let expiresAt: Date
}

// MARK: - API Gateway Models

protocol APIGatewayServiceProtocol {
    func processRequest<T: Codable>(_ request: APIGatewayRequest, responseType: T.Type) async throws -> APIGatewayResponse<T>
    func validateAPIKey(_ apiKey: String) async throws -> APIKeyValidationResult
    func checkRateLimit(for apiKey: String, endpoint: APIEndpoint) async throws -> RateLimitResult
    func logRequest(_ request: APIGatewayRequest, response: APIGatewayResponse<Any>) async
    func addMiddleware(_ middleware: APIMiddleware)
    func removeMiddleware(_ middlewareType: APIMiddleware.Type)
    func registerEndpoint(_ endpoint: APIEndpoint)
    func getEndpoint(path: String, version: APIVersion) -> APIEndpoint?
    func listAvailableEndpoints(for tier: APITier) -> [APIEndpoint]
    func healthCheck() async -> APIHealthStatus
    func getMetrics(for period: TimePeriod) async -> APIGatewayMetrics
}

struct APIGatewayRequest: Codable {
    let id: String
    let method: HTTPMethod
    let path: String
    let version: APIVersion
    let headers: [String: String]
    let body: Data?
    let queryParameters: [String: String]
    let apiKey: String?
    let timestamp: Date
    let clientIP: String?
    let userAgent: String?
    
    init(method: HTTPMethod, path: String, version: APIVersion = .v1, headers: [String: String] = [:], body: Data? = nil, queryParameters: [String: String] = [:], apiKey: String? = nil, clientIP: String? = nil, userAgent: String? = nil) {
        self.id = UUID().uuidString
        self.method = method
        self.path = path
        self.version = version
        self.headers = headers
        self.body = body
        self.queryParameters = queryParameters
        self.apiKey = apiKey
        self.timestamp = Date()
        self.clientIP = clientIP
        self.userAgent = userAgent
    }
}

struct APIGatewayResponse<T: Codable>: Codable {
    let data: T?
    let statusCode: Int
    let headers: [String: String]
    let requestId: String
    let processingTimeMs: Double
    let error: APIError?
    
    var isSuccess: Bool {
        return statusCode >= 200 && statusCode < 300
    }
}

enum HTTPMethod: String, Codable, CaseIterable {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
    case HEAD = "HEAD"
    case OPTIONS = "OPTIONS"
}

struct APIError: Codable, Error {
    let code: String
    let message: String
    let details: [String: Any]?
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case code, message, timestamp
    }
    
    init(code: String, message: String, details: [String: Any]? = nil) {
        self.code = code
        self.message = message
        self.details = details
        self.timestamp = Date()
    }
}

// MARK: - API Endpoint Models

struct APIEndpoint {
    let path: String
    let method: HTTPMethod
    let version: APIVersion
    let requiredTier: APITier
    let handler: (APIGatewayRequest) async throws -> String
    let description: String?
    let deprecated: Bool
    let rateLimitOverride: Int?
    
    init(path: String, method: HTTPMethod, version: APIVersion = .v1, requiredTier: APITier = .free, handler: @escaping (APIGatewayRequest) async throws -> String, description: String? = nil, deprecated: Bool = false, rateLimitOverride: Int? = nil) {
        self.path = path
        self.method = method
        self.version = version
        self.requiredTier = requiredTier
        self.handler = handler
        self.description = description
        self.deprecated = deprecated
        self.rateLimitOverride = rateLimitOverride
    }
}

protocol CourseDataAPIProtocol {
    func listCourses(request: CourseSearchRequest) async throws -> CourseSearchResponse
    func getCourseDetails(id: String, request: CourseDetailRequest) async throws -> CourseDetailResponse
    func searchCourses(request: CourseSearchRequest) async throws -> CourseSearchResponse
    func getNearbyCourses(request: NearbyCoursesRequest) async throws -> CourseSearchResponse
    func getFeaturedCourses(request: FeaturedCoursesRequest) async throws -> CourseSearchResponse
    func getPopularCourses(request: PopularCoursesRequest) async throws -> CourseSearchResponse
}

// MARK: - API Key Validation Models

struct APIKeyValidationResult {
    let isValid: Bool
    let apiKey: String
    let tier: APITier
    let userId: String
    let expiresAt: Date?
    let remainingQuota: Int?
}

// MARK: - Rate Limiting Models

struct RateLimitResult {
    let allowed: Bool
    let limit: Int
    let remaining: Int
    let windowMs: Int
    let resetTime: Date
    let retryAfter: TimeInterval?
    
    var isExceeded: Bool {
        return !allowed
    }
}

// MARK: - API Middleware Models

protocol APIMiddleware {
    func process(_ request: APIGatewayRequest) async throws -> APIGatewayRequest
    func postProcess(_ request: APIGatewayRequest, response: APIGatewayResponse<Any>) async throws -> APIGatewayResponse<Any>
    var name: String { get }
    var priority: Int { get } // Lower numbers execute first
}

// MARK: - Health Check Models

struct APIHealthStatus {
    let isHealthy: Bool
    let appwriteConnected: Bool
    let memoryUsagePercent: Double
    let averageResponseTimeMs: Double
    let activeConnections: Int
    let uptime: TimeInterval
    let timestamp: Date
    
    init(isHealthy: Bool, appwriteConnected: Bool, memoryUsagePercent: Double, averageResponseTimeMs: Double, activeConnections: Int, uptime: TimeInterval = 0, timestamp: Date = Date()) {
        self.isHealthy = isHealthy
        self.appwriteConnected = appwriteConnected
        self.memoryUsagePercent = memoryUsagePercent
        self.averageResponseTimeMs = averageResponseTimeMs
        self.activeConnections = activeConnections
        self.uptime = uptime
        self.timestamp = timestamp
    }
}

// MARK: - Metrics and Analytics Models

enum TimePeriod: String, CaseIterable {
    case lastHour = "last_hour"
    case last24Hours = "last_24_hours"
    case lastWeek = "last_week"
    case lastMonth = "last_month"
    case lastQuarter = "last_quarter"
    case lastYear = "last_year"
    
    var timeInterval: TimeInterval {
        switch self {
        case .lastHour: return 3600
        case .last24Hours: return 86400
        case .lastWeek: return 604800
        case .lastMonth: return 2592000
        case .lastQuarter: return 7776000
        case .lastYear: return 31536000
        }
    }
}

struct APIGatewayMetrics {
    let totalRequests: Int
    let successfulRequests: Int
    let failedRequests: Int
    let averageResponseTime: Double
    let medianResponseTime: Double
    let p95ResponseTime: Double
    let requestsByEndpoint: [String: Int]
    let requestsByTier: [APITier: Int]
    let errorsByType: [String: Int]
    let topUsers: [String: Int]
    let period: TimePeriod
    let generatedAt: Date
    
    init(totalRequests: Int = 0, successfulRequests: Int = 0, failedRequests: Int = 0, averageResponseTime: Double = 0.0, medianResponseTime: Double = 0.0, p95ResponseTime: Double = 0.0, requestsByEndpoint: [String: Int] = [:], requestsByTier: [APITier: Int] = [:], errorsByType: [String: Int] = [:], topUsers: [String: Int] = [:], period: TimePeriod = .lastHour, generatedAt: Date = Date()) {
        self.totalRequests = totalRequests
        self.successfulRequests = successfulRequests
        self.failedRequests = failedRequests
        self.averageResponseTime = averageResponseTime
        self.medianResponseTime = medianResponseTime
        self.p95ResponseTime = p95ResponseTime
        self.requestsByEndpoint = requestsByEndpoint
        self.requestsByTier = requestsByTier
        self.errorsByType = errorsByType
        self.topUsers = topUsers
        self.period = period
        self.generatedAt = generatedAt
    }
    
    var successRate: Double {
        guard totalRequests > 0 else { return 0.0 }
        return Double(successfulRequests) / Double(totalRequests)
    }
    
    var errorRate: Double {
        guard totalRequests > 0 else { return 0.0 }
        return Double(failedRequests) / Double(totalRequests)
    }
}

// MARK: - Developer Portal Analytics

struct DeveloperUsageAnalytics {
    let developerId: String
    let period: TimePeriod
    let totalRequests: Int
    let requestsByEndpoint: [String: Int]
    let requestsByDay: [String: Int] // ISO date string -> count
    let averageResponseTime: Double
    let errorCount: Int
    let costInCents: Double
    let quotaUsagePercent: Double
    let topErrors: [String: Int]
    let generatedAt: Date
    
    var costInDollars: Double {
        return costInCents / 100.0
    }
}

struct DeveloperPortalDashboard {
    let developer: DeveloperAccount
    let apiKeys: [APIKeyInfo]
    let recentUsage: DeveloperUsageAnalytics
    let notifications: [DeveloperNotification]
    let billingInfo: DeveloperBillingInfo
    let supportTickets: [SupportTicket]
    let generatedAt: Date
}

struct DeveloperNotification {
    let id: String
    let type: NotificationType
    let title: String
    let message: String
    let actionUrl: String?
    let actionText: String?
    let isRead: Bool
    let createdAt: Date
    let priority: NotificationPriority
    
    enum NotificationType: String, Codable {
        case quotaWarning = "quota_warning"
        case quotaExceeded = "quota_exceeded" 
        case keyExpiring = "key_expiring"
        case apiUpdate = "api_update"
        case security = "security"
        case billing = "billing"
        case maintenance = "maintenance"
        case welcome = "welcome"
    }
    
    enum NotificationPriority: String, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case urgent = "urgent"
    }
}

struct DeveloperBillingInfo {
    let currentTier: APITier
    let billingCycle: BillingCycle
    let nextBillingDate: Date?
    let currentUsageCosts: Double // in cents
    let projectedMonthlyCosts: Double // in cents
    let paymentMethod: PaymentMethod?
    let invoices: [Invoice]
    
    enum BillingCycle: String, Codable {
        case monthly = "monthly"
        case annually = "annually"
    }
    
    var currentUsageInDollars: Double {
        return currentUsageCosts / 100.0
    }
    
    var projectedMonthlyInDollars: Double {
        return projectedMonthlyCosts / 100.0
    }
}

struct PaymentMethod {
    let id: String
    let type: PaymentType
    let last4: String
    let brand: String?
    let expiryMonth: Int
    let expiryYear: Int
    let isDefault: Bool
    
    enum PaymentType: String, Codable {
        case creditCard = "credit_card"
        case debitCard = "debit_card"
        case bankAccount = "bank_account"
        case paypal = "paypal"
    }
}

struct Invoice {
    let id: String
    let number: String
    let amountInCents: Int
    let status: InvoiceStatus
    let issueDate: Date
    let dueDate: Date
    let paidDate: Date?
    let downloadUrl: String?
    
    enum InvoiceStatus: String, Codable {
        case draft = "draft"
        case open = "open"
        case paid = "paid"
        case void = "void"
        case uncollectible = "uncollectible"
    }
    
    var amountInDollars: Double {
        return Double(amountInCents) / 100.0
    }
}

struct SupportTicket {
    let id: String
    let subject: String
    let status: TicketStatus
    let priority: TicketPriority
    let category: TicketCategory
    let createdAt: Date
    let updatedAt: Date
    let responseTime: TimeInterval?
    let messages: [TicketMessage]
    
    enum TicketStatus: String, Codable {
        case open = "open"
        case inProgress = "in_progress"
        case waiting = "waiting"
        case resolved = "resolved"
        case closed = "closed"
    }
    
    enum TicketPriority: String, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case urgent = "urgent"
    }
    
    enum TicketCategory: String, Codable {
        case technical = "technical"
        case billing = "billing"
        case account = "account"
        case api = "api"
        case documentation = "documentation"
        case feature = "feature"
        case bug = "bug"
    }
}

struct TicketMessage {
    let id: String
    let content: String
    let isFromSupport: Bool
    let createdAt: Date
    let attachments: [String]
}

// MARK: - Extended Parameter Documentation

extension ParameterDocumentation {
    func toDictionary() -> [String: Any] {
        return [
            "name": name,
            "type": type,
            "description": description,
            "required": required,
            "example": example as Any
        ]
    }
}

// MARK: - Developer Portal Integration Models

struct DeveloperOnboarding {
    let step: OnboardingStep
    let isCompleted: Bool
    let completedSteps: [OnboardingStep]
    let totalSteps: Int
    let estimatedTimeRemaining: TimeInterval
    
    enum OnboardingStep: String, CaseIterable {
        case registration = "registration"
        case emailVerification = "email_verification"
        case profileSetup = "profile_setup" 
        case firstAPIKey = "first_api_key"
        case firstAPICall = "first_api_call"
        case documentation = "documentation"
        case completed = "completed"
    }
    
    var progress: Double {
        return Double(completedSteps.count) / Double(totalSteps)
    }
}

struct DeveloperAPIExplorer {
    let endpoint: APIEndpoint
    let availableExamples: [APIExample]
    let codeSnippets: [CodeExample]
    let tryItOutEnabled: Bool
    let authentication: AuthenticationDocumentation
}

struct APIExample {
    let id: String
    let name: String
    let description: String
    let requestExample: String
    let responseExample: String
    let language: ProgrammingLanguage?
}

// MARK: - Comprehensive Error Handling

enum DeveloperPortalError: Error, LocalizedError {
    case invalidDeveloperId
    case developerNotFound
    case emailNotVerified
    case accountSuspended
    case tierLimitExceeded
    case quotaExceeded
    case rateLimitExceeded
    case invalidAPIKey
    case apiKeyExpired
    case apiKeyRevoked
    case insufficientTier
    case paymentRequired
    case maintenanceMode
    case invalidRequest(String)
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidDeveloperId:
            return "Invalid developer ID provided"
        case .developerNotFound:
            return "Developer account not found"
        case .emailNotVerified:
            return "Email address must be verified before proceeding"
        case .accountSuspended:
            return "Account has been suspended. Contact support for assistance"
        case .tierLimitExceeded:
            return "Tier limit exceeded. Upgrade to a higher tier to continue"
        case .quotaExceeded:
            return "API quota exceeded for the current billing period"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please slow down your requests"
        case .invalidAPIKey:
            return "Invalid or malformed API key"
        case .apiKeyExpired:
            return "API key has expired. Please generate a new key"
        case .apiKeyRevoked:
            return "API key has been revoked"
        case .insufficientTier:
            return "This feature requires a higher tier subscription"
        case .paymentRequired:
            return "Payment is required to continue using the service"
        case .maintenanceMode:
            return "Service is temporarily unavailable for maintenance"
        case .invalidRequest(let details):
            return "Invalid request: \(details)"
        case .serverError(let details):
            return "Server error: \(details)"
        }
    }
    
    var errorCode: String {
        switch self {
        case .invalidDeveloperId: return "INVALID_DEVELOPER_ID"
        case .developerNotFound: return "DEVELOPER_NOT_FOUND"
        case .emailNotVerified: return "EMAIL_NOT_VERIFIED"
        case .accountSuspended: return "ACCOUNT_SUSPENDED"
        case .tierLimitExceeded: return "TIER_LIMIT_EXCEEDED"
        case .quotaExceeded: return "QUOTA_EXCEEDED"
        case .rateLimitExceeded: return "RATE_LIMIT_EXCEEDED"
        case .invalidAPIKey: return "INVALID_API_KEY"
        case .apiKeyExpired: return "API_KEY_EXPIRED"
        case .apiKeyRevoked: return "API_KEY_REVOKED"
        case .insufficientTier: return "INSUFFICIENT_TIER"
        case .paymentRequired: return "PAYMENT_REQUIRED"
        case .maintenanceMode: return "MAINTENANCE_MODE"
        case .invalidRequest: return "INVALID_REQUEST"
        case .serverError: return "SERVER_ERROR"
        }
    }
    
    var httpStatusCode: Int {
        switch self {
        case .invalidDeveloperId, .invalidRequest, .invalidAPIKey:
            return 400
        case .emailNotVerified, .apiKeyExpired, .apiKeyRevoked:
            return 401
        case .insufficientTier, .accountSuspended:
            return 403
        case .developerNotFound:
            return 404
        case .tierLimitExceeded, .quotaExceeded, .rateLimitExceeded:
            return 429
        case .paymentRequired:
            return 402
        case .maintenanceMode, .serverError:
            return 503
        }
    }
}

// MARK: - Advanced API Statistics

struct APIStatistics {
    let endpoint: APIEndpoint
    let totalCalls: Int
    let successRate: Double
    let averageResponseTime: Double
    let p99ResponseTime: Double
    let errorBreakdown: [String: Int]
    let popularityRank: Int
    let costPerCall: Double
    let period: TimePeriod
    
    var performanceGrade: PerformanceGrade {
        switch averageResponseTime {
        case 0..<100: return .excellent
        case 100..<500: return .good
        case 500..<1000: return .fair
        default: return .poor
        }
    }
    
    enum PerformanceGrade: String {
        case excellent = "A+"
        case good = "A"
        case fair = "B"
        case poor = "C"
    }
}

// MARK: - Advanced Developer Tools

struct APITestSuite {
    let id: String
    let name: String
    let description: String
    let tests: [APITest]
    let createdBy: String
    let createdAt: Date
    let lastRun: Date?
    let successRate: Double?
}

struct APITest {
    let id: String
    let name: String
    let endpoint: APIEndpoint
    let requestData: APIGatewayRequest
    let expectedResponse: ExpectedResponse
    let assertions: [TestAssertion]
}

struct ExpectedResponse {
    let statusCode: Int
    let headers: [String: String]?
    let bodySchema: String? // JSON Schema
    let minResponseTime: TimeInterval?
    let maxResponseTime: TimeInterval?
}

struct TestAssertion {
    let type: AssertionType
    let field: String
    let operator: ComparisonOperator
    let expectedValue: Any
    
    enum AssertionType: String {
        case statusCode = "status_code"
        case header = "header"
        case body = "body"
        case responseTime = "response_time"
    }
    
    enum ComparisonOperator: String {
        case equals = "equals"
        case notEquals = "not_equals"
        case greaterThan = "greater_than"
        case lessThan = "less_than"
        case contains = "contains"
        case notContains = "not_contains"
        case matches = "matches" // regex
    }
}

// MARK: - Developer Community Features

struct DeveloperCommunityPost {
    let id: String
    let title: String
    let content: String
    let author: DeveloperProfile
    let category: CommunityCategory
    let tags: [String]
    let upvotes: Int
    let downvotes: Int
    let replies: [CommunityReply]
    let createdAt: Date
    let updatedAt: Date
    let isPinned: Bool
    let isSolved: Bool
    
    enum CommunityCategory: String, CaseIterable {
        case general = "general"
        case help = "help"
        case showcase = "showcase"
        case feature = "feature"
        case bug = "bug"
        case announcement = "announcement"
    }
}

struct CommunityReply {
    let id: String
    let content: String
    let author: DeveloperProfile
    let upvotes: Int
    let downvotes: Int
    let createdAt: Date
    let isAcceptedSolution: Bool
}

// MARK: - Webhook Management

struct WebhookEndpoint {
    let id: String
    let url: String
    let events: [WebhookEvent]
    let secret: String
    let isActive: Bool
    let createdAt: Date
    let lastDelivery: Date?
    let successfulDeliveries: Int
    let failedDeliveries: Int
    
    enum WebhookEvent: String, CaseIterable {
        case apiKeyCreated = "api_key.created"
        case apiKeyRevoked = "api_key.revoked"
        case quotaExceeded = "quota.exceeded"
        case tierUpgraded = "tier.upgraded"
        case paymentSucceeded = "payment.succeeded"
        case paymentFailed = "payment.failed"
        case accountSuspended = "account.suspended"
    }
}

struct WebhookDelivery {
    let id: String
    let webhookId: String
    let event: WebhookEndpoint.WebhookEvent
    let payload: [String: Any]
    let attemptCount: Int
    let lastAttemptAt: Date
    let statusCode: Int?
    let responseBody: String?
    let isSuccessful: Bool
}