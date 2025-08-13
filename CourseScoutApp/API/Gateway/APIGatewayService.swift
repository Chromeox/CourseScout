import Foundation
import Appwrite
import Combine

// MARK: - API Gateway Service Protocol

protocol APIGatewayServiceProtocol {
    // MARK: - Core Gateway Operations
    func processRequest<T: Codable>(_ request: APIGatewayRequest, responseType: T.Type) async throws -> APIGatewayResponse<T>
    func validateAPIKey(_ apiKey: String) async throws -> APIKeyValidationResult
    func checkRateLimit(for apiKey: String, endpoint: APIEndpoint) async throws -> RateLimitResult
    func logRequest(_ request: APIGatewayRequest, response: APIGatewayResponse<Any>) async
    
    // MARK: - Middleware Pipeline
    func addMiddleware(_ middleware: APIMiddleware)
    func removeMiddleware(_ middlewareType: APIMiddleware.Type)
    
    // MARK: - Endpoint Management
    func registerEndpoint(_ endpoint: APIEndpoint)
    func getEndpoint(path: String, version: APIVersion) -> APIEndpoint?
    func listAvailableEndpoints(for tier: APITier) -> [APIEndpoint]
    
    // MARK: - Health and Monitoring
    func healthCheck() async -> APIHealthStatus
    func getMetrics(for period: TimePeriod) async -> APIGatewayMetrics
}

// MARK: - API Gateway Service Implementation

@MainActor
class APIGatewayService: APIGatewayServiceProtocol, ObservableObject {
    // MARK: - Properties
    
    private let appwriteClient: Client
    private let usageTracker: UsageTrackingMiddleware
    private let rateLimiter: RateLimitingMiddleware
    private let authenticator: AuthenticationMiddleware
    
    @Published var isHealthy: Bool = true
    @Published var activeConnections: Int = 0
    @Published var requestsPerSecond: Double = 0.0
    
    // MARK: - Middleware Pipeline
    private var middlewareStack: [APIMiddleware] = []
    
    // MARK: - Endpoint Registry
    private var endpoints: [String: APIEndpoint] = [:]
    
    // MARK: - Performance Monitoring
    private var metrics: APIGatewayMetrics = APIGatewayMetrics()
    
    // MARK: - Service Dependencies
    @ServiceInjected(APIUsageTrackingServiceProtocol.self) private var usageTracker
    @ServiceInjected(RevenueServiceProtocol.self) private var revenueService
    @ServiceInjected(BillingServiceProtocol.self) private var billingService
    private let metricsQueue = DispatchQueue(label: "APIGatewayMetrics", qos: .utility)
    
    // MARK: - Rate Limiting Cache
    private let rateLimitCache = NSCache<NSString, RateLimitState>()
    
    // MARK: - Initialization
    
    init(appwriteClient: Client) {
        self.appwriteClient = appwriteClient
        self.usageTracker = UsageTrackingMiddleware()
        self.rateLimiter = RateLimitingMiddleware()
        self.authenticator = AuthenticationMiddleware(appwriteClient: appwriteClient)
        
        setupDefaultMiddleware()
        registerDefaultEndpoints()
        startMetricsCollection()
    }
    
    // MARK: - Core Gateway Operations
    
    func processRequest<T: Codable>(_ request: APIGatewayRequest, responseType: T.Type) async throws -> APIGatewayResponse<T> {
        let startTime = Date()
        
        do {
            // Execute middleware pipeline
            let processedRequest = try await executeMiddlewarePipeline(request)
            
            // Find and execute endpoint
            guard let endpoint = getEndpoint(path: processedRequest.path, version: processedRequest.version) else {
                throw APIGatewayError.endpointNotFound(processedRequest.path)
            }
            
            // Check endpoint access permissions
            try await validateEndpointAccess(endpoint: endpoint, apiKey: processedRequest.apiKey)
            
            // Execute the endpoint
            let result = try await executeEndpoint(endpoint, request: processedRequest, responseType: responseType)
            
            // Create successful response
            let response = APIGatewayResponse<T>(
                data: result,
                statusCode: 200,
                headers: ["X-API-Version": processedRequest.version.rawValue],
                requestId: processedRequest.requestId,
                processingTimeMs: Date().timeIntervalSince(startTime) * 1000
            )
            
            // Log the request/response
            await logRequest(processedRequest, response: APIGatewayResponse<Any>(
                data: result,
                statusCode: response.statusCode,
                headers: response.headers,
                requestId: response.requestId,
                processingTimeMs: response.processingTimeMs
            ))
            
            return response
            
        } catch {
            // Handle errors and create error response
            let errorResponse = APIGatewayResponse<T>(
                data: nil,
                statusCode: (error as? APIGatewayError)?.statusCode ?? 500,
                headers: ["X-Error": error.localizedDescription],
                requestId: request.requestId,
                processingTimeMs: Date().timeIntervalSince(startTime) * 1000,
                error: error
            )
            
            await logRequest(request, response: APIGatewayResponse<Any>(
                data: nil,
                statusCode: errorResponse.statusCode,
                headers: errorResponse.headers,
                requestId: errorResponse.requestId,
                processingTimeMs: errorResponse.processingTimeMs,
                error: error
            ))
            
            throw error
        }
    }
    
    func validateAPIKey(_ apiKey: String) async throws -> APIKeyValidationResult {
        return try await authenticator.validateAPIKey(apiKey)
    }
    
    func checkRateLimit(for apiKey: String, endpoint: APIEndpoint) async throws -> RateLimitResult {
        return try await rateLimiter.checkRateLimit(apiKey: apiKey, endpoint: endpoint)
    }
    
    func logRequest(_ request: APIGatewayRequest, response: APIGatewayResponse<Any>) async {
        await usageTracker.trackUsage(request: request, response: response)
        
        // Track usage for billing and revenue
        await trackUsageForBilling(request, response: response)
        
        // Record API revenue metrics
        await recordAPIRevenueMetrics(request, response: response)
        
        // Update metrics
        await updateMetrics(request: request, response: response)
        
        // Log for debugging (in development)
        if Configuration.environment.enableDetailedLogging {
            print("API Gateway: \(request.method) \(request.path) - \(response.statusCode) (\(String(format: "%.2f", response.processingTimeMs))ms)")
        }
    }
    
    // MARK: - Middleware Management
    
    func addMiddleware(_ middleware: APIMiddleware) {
        middlewareStack.append(middleware)
        middlewareStack.sort { $0.priority < $1.priority }
    }
    
    func removeMiddleware(_ middlewareType: APIMiddleware.Type) {
        middlewareStack.removeAll { type(of: $0) == middlewareType }
    }
    
    // MARK: - Endpoint Management
    
    func registerEndpoint(_ endpoint: APIEndpoint) {
        let key = "\(endpoint.version.rawValue):\(endpoint.path)"
        endpoints[key] = endpoint
    }
    
    func getEndpoint(path: String, version: APIVersion) -> APIEndpoint? {
        let key = "\(version.rawValue):\(path)"
        return endpoints[key]
    }
    
    func listAvailableEndpoints(for tier: APITier) -> [APIEndpoint] {
        return endpoints.values.filter { endpoint in
            endpoint.requiredTier.priority <= tier.priority
        }
    }
    
    // MARK: - Health and Monitoring
    
    func healthCheck() async -> APIHealthStatus {
        let appwriteHealthy = await checkAppwriteHealth()
        let memoryUsage = getCurrentMemoryUsage()
        let responseTime = await measureAverageResponseTime()
        
        let status = APIHealthStatus(
            isHealthy: appwriteHealthy && memoryUsage < 80.0,
            appwriteConnected: appwriteHealthy,
            memoryUsagePercent: memoryUsage,
            averageResponseTimeMs: responseTime,
            activeConnections: activeConnections,
            timestamp: Date()
        )
        
        await MainActor.run {
            self.isHealthy = status.isHealthy
        }
        
        return status
    }
    
    func getMetrics(for period: TimePeriod) async -> APIGatewayMetrics {
        return await metricsQueue.async {
            return self.metrics.filtered(for: period)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func setupDefaultMiddleware() {
        addMiddleware(authenticator)
        addMiddleware(rateLimiter)
        addMiddleware(usageTracker)
    }
    
    private func registerDefaultEndpoints() {
        // Register Course Data API endpoints
        registerEndpoint(APIEndpoint(
            path: "/courses",
            method: .GET,
            version: .v1,
            requiredTier: .free,
            handler: { _ in return "Course data endpoint" }
        ))
        
        registerEndpoint(APIEndpoint(
            path: "/courses/analytics",
            method: .GET,
            version: .v1,
            requiredTier: .premium,
            handler: { _ in return "Advanced analytics endpoint" }
        ))
        
        registerEndpoint(APIEndpoint(
            path: "/predictions",
            method: .POST,
            version: .v2,
            requiredTier: .enterprise,
            handler: { _ in return "Predictive insights endpoint" }
        ))
        
        registerEndpoint(APIEndpoint(
            path: "/booking/realtime",
            method: .GET,
            version: .v2,
            requiredTier: .business,
            handler: { _ in return "Real-time booking endpoint" }
        ))
    }
    
    private func executeMiddlewarePipeline(_ request: APIGatewayRequest) async throws -> APIGatewayRequest {
        var processedRequest = request
        
        for middleware in middlewareStack {
            processedRequest = try await middleware.process(processedRequest)
        }
        
        return processedRequest
    }
    
    private func validateEndpointAccess(endpoint: APIEndpoint, apiKey: String) async throws {
        let validationResult = try await validateAPIKey(apiKey)
        
        guard validationResult.tier.priority >= endpoint.requiredTier.priority else {
            throw APIGatewayError.insufficientTier(required: endpoint.requiredTier, current: validationResult.tier)
        }
        
        let rateLimitResult = try await checkRateLimit(for: apiKey, endpoint: endpoint)
        
        guard rateLimitResult.allowed else {
            throw APIGatewayError.rateLimitExceeded(
                limit: rateLimitResult.limit,
                windowMs: rateLimitResult.windowMs,
                resetTime: rateLimitResult.resetTime
            )
        }
    }
    
    private func executeEndpoint<T: Codable>(_ endpoint: APIEndpoint, request: APIGatewayRequest, responseType: T.Type) async throws -> T {
        // This would typically route to the actual endpoint implementation
        // For now, we'll simulate the endpoint execution
        
        switch endpoint.path {
        case "/courses":
            return try await executeCourseDataEndpoint(request, responseType: responseType)
        case "/courses/analytics":
            return try await executeAnalyticsEndpoint(request, responseType: responseType)
        case "/predictions":
            return try await executePredictionsEndpoint(request, responseType: responseType)
        case "/booking/realtime":
            return try await executeRealtimeBookingEndpoint(request, responseType: responseType)
        default:
            throw APIGatewayError.endpointNotImplemented(endpoint.path)
        }
    }
    
    private func executeCourseDataEndpoint<T: Codable>(_ request: APIGatewayRequest, responseType: T.Type) async throws -> T {
        // Simulate course data retrieval
        let mockData = ["courses": ["Golf Course 1", "Golf Course 2"]]
        let jsonData = try JSONSerialization.data(withJSONObject: mockData)
        return try JSONDecoder().decode(responseType, from: jsonData)
    }
    
    private func executeAnalyticsEndpoint<T: Codable>(_ request: APIGatewayRequest, responseType: T.Type) async throws -> T {
        // Simulate analytics data
        let mockData = ["analytics": ["total_rounds": 1500, "avg_score": 85.2]]
        let jsonData = try JSONSerialization.data(withJSONObject: mockData)
        return try JSONDecoder().decode(responseType, from: jsonData)
    }
    
    private func executePredictionsEndpoint<T: Codable>(_ request: APIGatewayRequest, responseType: T.Type) async throws -> T {
        // Simulate predictive insights
        let mockData = ["predictions": ["optimal_tee_time": "14:00", "weather_score": 8.5]]
        let jsonData = try JSONSerialization.data(withJSONObject: mockData)
        return try JSONDecoder().decode(responseType, from: jsonData)
    }
    
    private func executeRealtimeBookingEndpoint<T: Codable>(_ request: APIGatewayRequest, responseType: T.Type) async throws -> T {
        // Simulate real-time booking data
        let mockData = ["realtime": ["available_slots": 12, "last_update": Date().timeIntervalSince1970]]
        let jsonData = try JSONSerialization.data(withJSONObject: mockData)
        return try JSONDecoder().decode(responseType, from: jsonData)
    }
    
    private func startMetricsCollection() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task {
                await self.collectMetrics()
            }
        }
    }
    
    private func collectMetrics() async {
        let currentTime = Date()
        
        await metricsQueue.async {
            self.metrics.updateTimestamp = currentTime
            // Additional metrics collection logic would go here
        }
    }
    
    // MARK: - Revenue Integration Methods
    
    private func trackUsageForBilling(_ request: APIGatewayRequest, response: APIGatewayResponse<Any>) async {
        guard let apiKey = request.headers["x-api-key"],
              let tenantId = request.tenantId else {
            return
        }
        
        do {
            // Track API usage for billing
            try await usageTracker.trackAPICall(
                tenantId: tenantId,
                endpoint: request.path,
                method: HTTPMethod(rawValue: request.method.rawValue) ?? .GET,
                statusCode: response.statusCode,
                responseTime: response.processingTime,
                dataSize: response.data?.count ?? 0
            )
            
            // Check if usage triggers billing events
            let currentUsage = try await usageTracker.getCurrentUsage(tenantId: tenantId)
            await checkBillingThresholds(tenantId: tenantId, usage: currentUsage)
            
        } catch {
            print("Failed to track usage for billing: \(error)")
        }
    }
    
    private func checkBillingThresholds(tenantId: String, usage: APIUsage) async {
        do {
            // Check if user has exceeded their plan limits
            let overageCharges = try await usageTracker.getOverageCharges(tenantId: tenantId, period: .monthly)
            
            if !overageCharges.isEmpty {
                // Record revenue event for overage charges
                for charge in overageCharges {
                    let revenueEvent = RevenueEvent(
                        id: UUID(),
                        tenantId: tenantId,
                        eventType: .usageCharge,
                        amount: charge.amount,
                        currency: "USD",
                        timestamp: Date(),
                        subscriptionId: nil,
                        customerId: tenantId,
                        invoiceId: nil,
                        metadata: [
                            "overage_type": charge.type.rawValue,
                            "quantity": String(charge.quantity)
                        ],
                        source: .manual
                    )
                    
                    try await revenueService.recordRevenueEvent(revenueEvent)
                }
                
                // Create billing invoice for overage charges
                try await billingService.createOverageInvoice(
                    tenantId: tenantId,
                    charges: overageCharges,
                    billingPeriod: Date()
                )
            }
            
        } catch {
            print("Failed to check billing thresholds: \(error)")
        }
    }
    
    private func recordAPIRevenueMetrics(_ request: APIGatewayRequest, response: APIGatewayResponse<Any>) async {
        guard let tenantId = request.tenantId else { return }
        
        do {
            // Calculate API call cost based on tier
            let validationResult = try await validateAPIKey(request.headers["x-api-key"] ?? "")
            let costPerCall = getCostPerAPICall(tier: validationResult.tier)
            
            if costPerCall > 0 {
                let revenueEvent = RevenueEvent(
                    id: UUID(),
                    tenantId: tenantId,
                    eventType: .usageCharge,
                    amount: costPerCall,
                    currency: "USD",
                    timestamp: Date(),
                    subscriptionId: nil,
                    customerId: tenantId,
                    invoiceId: nil,
                    metadata: [
                        "endpoint": request.path,
                        "method": request.method.rawValue,
                        "tier": validationResult.tier.rawValue
                    ],
                    source: .manual
                )
                
                try await revenueService.recordRevenueEvent(revenueEvent)
            }
            
        } catch {
            print("Failed to record API revenue metrics: \(error)")
        }
    }
    
    private func getCostPerAPICall(tier: APITier) -> Decimal {
        switch tier {
        case .free:
            return 0.0
        case .developer:
            return 0.001 // $0.001 per call
        case .startup:
            return 0.002 // $0.002 per call  
        case .business:
            return 0.005 // $0.005 per call
        case .enterprise:
            return 0.010 // $0.01 per call
        }
    }
    
    private func updateMetrics(request: APIGatewayRequest, response: APIGatewayResponse<Any>) async {
        await metricsQueue.async {
            self.metrics.totalRequests += 1
            
            if response.statusCode >= 200 && response.statusCode < 300 {
                self.metrics.successfulRequests += 1
            } else {
                self.metrics.failedRequests += 1
            }
            
            self.metrics.totalProcessingTimeMs += response.processingTimeMs
            self.metrics.averageProcessingTimeMs = self.metrics.totalProcessingTimeMs / Double(self.metrics.totalRequests)
            
            // Update requests per second (simplified calculation)
            let now = Date()
            if self.metrics.lastRequestTime != nil {
                let timeDiff = now.timeIntervalSince(self.metrics.lastRequestTime!)
                if timeDiff > 0 {
                    self.metrics.requestsPerSecond = 1.0 / timeDiff
                }
            }
            self.metrics.lastRequestTime = now
        }
        
        // Update published property on main actor
        await MainActor.run {
            self.requestsPerSecond = metrics.requestsPerSecond
        }
    }
    
    private func checkAppwriteHealth() async -> Bool {
        do {
            let health = try await appwriteClient.health.get()
            return health.status == "pass"
        } catch {
            return false
        }
    }
    
    private func getCurrentMemoryUsage() -> Double {
        let info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size)
            let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
            return (usedMemory / totalMemory) * 100.0
        }
        
        return 0.0
    }
    
    private func measureAverageResponseTime() async -> Double {
        return await metricsQueue.async {
            return self.metrics.averageProcessingTimeMs
        }
    }
}

// MARK: - Data Models

struct APIGatewayRequest {
    let requestId: String
    let path: String
    let method: HTTPMethod
    let version: APIVersion
    let apiKey: String
    let headers: [String: String]
    let body: Data?
    let queryParameters: [String: String]
    let timestamp: Date
    
    init(path: String, method: HTTPMethod, version: APIVersion, apiKey: String, headers: [String: String] = [:], body: Data? = nil, queryParameters: [String: String] = [:]) {
        self.requestId = UUID().uuidString
        self.path = path
        self.method = method
        self.version = version
        self.apiKey = apiKey
        self.headers = headers
        self.body = body
        self.queryParameters = queryParameters
        self.timestamp = Date()
    }
}

struct APIGatewayResponse<T: Codable> {
    let data: T?
    let statusCode: Int
    let headers: [String: String]
    let requestId: String
    let processingTimeMs: Double
    let error: Error?
    
    init(data: T? = nil, statusCode: Int, headers: [String: String] = [:], requestId: String, processingTimeMs: Double, error: Error? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.requestId = requestId
        self.processingTimeMs = processingTimeMs
        self.error = error
    }
}

struct APIEndpoint {
    let path: String
    let method: HTTPMethod
    let version: APIVersion
    let requiredTier: APITier
    let handler: (APIGatewayRequest) async throws -> Any
    
    init(path: String, method: HTTPMethod, version: APIVersion, requiredTier: APITier, handler: @escaping (APIGatewayRequest) async throws -> Any) {
        self.path = path
        self.method = method
        self.version = version
        self.requiredTier = requiredTier
        self.handler = handler
    }
}

enum HTTPMethod: String, Codable {
    case GET, POST, PUT, DELETE, PATCH
}

enum APIVersion: String, Codable {
    case v1 = "v1"
    case v2 = "v2"
}

enum APITier: String, Codable {
    case free = "free"
    case premium = "premium"
    case enterprise = "enterprise"
    case business = "business"
    
    var priority: Int {
        switch self {
        case .free: return 0
        case .premium: return 1
        case .enterprise: return 2
        case .business: return 3
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
}

struct APIKeyValidationResult {
    let isValid: Bool
    let apiKey: String
    let tier: APITier
    let userId: String?
    let expiresAt: Date?
    let remainingQuota: Int?
}

struct RateLimitResult {
    let allowed: Bool
    let limit: Int
    let remaining: Int
    let windowMs: Int
    let resetTime: Date
}

struct RateLimitState {
    var count: Int
    let windowStart: Date
    let limit: Int
    let windowMs: Int
    
    var isExpired: Bool {
        Date().timeIntervalSince(windowStart) > Double(windowMs) / 1000.0
    }
}

struct APIHealthStatus {
    let isHealthy: Bool
    let appwriteConnected: Bool
    let memoryUsagePercent: Double
    let averageResponseTimeMs: Double
    let activeConnections: Int
    let timestamp: Date
}

struct APIGatewayMetrics {
    var totalRequests: Int = 0
    var successfulRequests: Int = 0
    var failedRequests: Int = 0
    var totalProcessingTimeMs: Double = 0.0
    var averageProcessingTimeMs: Double = 0.0
    var requestsPerSecond: Double = 0.0
    var lastRequestTime: Date?
    var updateTimestamp: Date = Date()
    
    func filtered(for period: TimePeriod) -> APIGatewayMetrics {
        // Implementation would filter metrics based on time period
        return self
    }
}

enum TimePeriod {
    case hour
    case day
    case week
    case month
}

// MARK: - Middleware Protocol

protocol APIMiddleware {
    var priority: Int { get }
    func process(_ request: APIGatewayRequest) async throws -> APIGatewayRequest
}

// MARK: - API Gateway Errors

enum APIGatewayError: Error, LocalizedError {
    case endpointNotFound(String)
    case endpointNotImplemented(String)
    case invalidAPIKey
    case insufficientTier(required: APITier, current: APITier)
    case rateLimitExceeded(limit: Int, windowMs: Int, resetTime: Date)
    case authenticationFailed
    case internalServerError(String)
    
    var statusCode: Int {
        switch self {
        case .endpointNotFound:
            return 404
        case .endpointNotImplemented:
            return 501
        case .invalidAPIKey, .authenticationFailed:
            return 401
        case .insufficientTier:
            return 403
        case .rateLimitExceeded:
            return 429
        case .internalServerError:
            return 500
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .endpointNotFound(let path):
            return "Endpoint not found: \(path)"
        case .endpointNotImplemented(let path):
            return "Endpoint not implemented: \(path)"
        case .invalidAPIKey:
            return "Invalid API key"
        case .insufficientTier(let required, let current):
            return "Insufficient tier: requires \(required.rawValue), current \(current.rawValue)"
        case .rateLimitExceeded(let limit, let windowMs, let resetTime):
            return "Rate limit exceeded: \(limit) requests per \(windowMs)ms window. Resets at \(resetTime)"
        case .authenticationFailed:
            return "Authentication failed"
        case .internalServerError(let message):
            return "Internal server error: \(message)"
        }
    }
}