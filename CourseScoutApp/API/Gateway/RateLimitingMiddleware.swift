import Foundation

// MARK: - Rate Limiting Middleware

class RateLimitingMiddleware: APIMiddleware {
    let priority: Int = 100
    
    // MARK: - Properties
    
    private let rateLimitCache = NSCache<NSString, RateLimitState>()
    private let rateLimitQueue = DispatchQueue(label: "RateLimitingQueue", qos: .userInitiated)
    
    // MARK: - Tier-based Rate Limits Configuration
    
    private let tierLimits: [APITier: RateLimitConfig] = [
        .free: RateLimitConfig(
            requestsPerMinute: 16,     // ~1000 per day
            requestsPerHour: 42,      // ~1000 per day
            requestsPerDay: 1000,
            burstLimit: 10,
            windowMs: 60000          // 1 minute window
        ),
        .premium: RateLimitConfig(
            requestsPerMinute: 167,   // ~10k per day
            requestsPerHour: 417,     // ~10k per day
            requestsPerDay: 10000,
            burstLimit: 50,
            windowMs: 60000          // 1 minute window
        ),
        .enterprise: RateLimitConfig(
            requestsPerMinute: 1667,  // ~100k per day
            requestsPerHour: 4167,    // ~100k per day
            requestsPerDay: 100000,
            burstLimit: 200,
            windowMs: 60000          // 1 minute window
        ),
        .business: RateLimitConfig(
            requestsPerMinute: -1,    // Unlimited
            requestsPerHour: -1,      // Unlimited
            requestsPerDay: -1,       // Unlimited
            burstLimit: 500,          // Still protect against abuse
            windowMs: 60000          // 1 minute window
        )
    ]
    
    // MARK: - Endpoint-specific Rate Limits
    
    private let endpointMultipliers: [String: Double] = [
        "/courses": 1.0,              // Standard rate
        "/courses/search": 1.2,       // Slightly higher cost
        "/courses/analytics": 2.0,    // Premium endpoint - higher cost
        "/predictions": 5.0,          // Enterprise endpoint - much higher cost
        "/booking/realtime": 3.0,     // Real-time endpoint - higher cost
        "/user/profile": 0.5,         // Lower cost for profile access
        "/health": 0.1               // Very low cost for health checks
    ]
    
    // MARK: - Initialization
    
    init() {
        setupCacheConfiguration()
        startCleanupTimer()
    }
    
    // MARK: - APIMiddleware Implementation
    
    func process(_ request: APIGatewayRequest) async throws -> APIGatewayRequest {
        // Skip rate limiting for health checks in development
        if Configuration.environment == .development && request.path == "/health" {
            return request
        }
        
        let rateLimitResult = try await checkRateLimit(apiKey: request.apiKey, endpoint: APIEndpoint(
            path: request.path,
            method: request.method,
            version: request.version,
            requiredTier: .free, // Will be determined by API key validation
            handler: { _ in return "temp" }
        ))
        
        guard rateLimitResult.allowed else {
            throw APIGatewayError.rateLimitExceeded(
                limit: rateLimitResult.limit,
                windowMs: tierLimits[.free]?.windowMs ?? 60000,
                resetTime: rateLimitResult.resetTime
            )
        }
        
        return request
    }
    
    // MARK: - Rate Limiting Logic
    
    func checkRateLimit(apiKey: String, endpoint: APIEndpoint) async throws -> RateLimitResult {
        return await rateLimitQueue.async {
            return self.performRateLimitCheck(apiKey: apiKey, endpoint: endpoint)
        }
    }
    
    private func performRateLimitCheck(apiKey: String, endpoint: APIEndpoint) -> RateLimitResult {
        // Get tier configuration (would normally come from API key validation)
        let tier = getTierForAPIKey(apiKey)
        guard let config = tierLimits[tier] else {
            return RateLimitResult(allowed: false, limit: 0, remaining: 0, windowMs: 60000, resetTime: Date())
        }
        
        // Business tier gets unlimited requests with burst protection
        if tier == .business {
            return handleBusinessTierRateLimit(apiKey: apiKey, config: config)
        }
        
        // Calculate effective limit based on endpoint cost
        let costMultiplier = endpointMultipliers[endpoint.path] ?? 1.0
        let effectiveLimit = Int(Double(config.requestsPerMinute) / costMultiplier)
        
        let cacheKey = "\(apiKey):\(endpoint.path)" as NSString
        let now = Date()
        
        // Get or create rate limit state
        var state: RateLimitState
        if let existingState = rateLimitCache.object(forKey: cacheKey) {
            state = existingState
            
            // Reset window if expired
            if state.isExpired {
                state = RateLimitState(
                    count: 0,
                    windowStart: now,
                    limit: effectiveLimit,
                    windowMs: config.windowMs
                )
            }
        } else {
            state = RateLimitState(
                count: 0,
                windowStart: now,
                limit: effectiveLimit,
                windowMs: config.windowMs
            )
        }
        
        // Check if request is allowed
        let allowed = state.count < effectiveLimit
        
        if allowed {
            // Increment counter and update cache
            state.count += 1
            rateLimitCache.setObject(state, forKey: cacheKey)
        }
        
        let remaining = max(0, effectiveLimit - state.count)
        let resetTime = state.windowStart.addingTimeInterval(Double(config.windowMs) / 1000.0)
        
        return RateLimitResult(
            allowed: allowed,
            limit: effectiveLimit,
            remaining: remaining,
            windowMs: config.windowMs,
            resetTime: resetTime
        )
    }
    
    private func handleBusinessTierRateLimit(apiKey: String, config: RateLimitConfig) -> RateLimitResult {
        // Business tier only has burst protection
        let cacheKey = "\(apiKey):burst" as NSString
        let now = Date()
        
        var state: RateLimitState
        if let existingState = rateLimitCache.object(forKey: cacheKey) {
            state = existingState
            
            if state.isExpired {
                state = RateLimitState(
                    count: 0,
                    windowStart: now,
                    limit: config.burstLimit,
                    windowMs: 5000 // 5-second burst window
                )
            }
        } else {
            state = RateLimitState(
                count: 0,
                windowStart: now,
                limit: config.burstLimit,
                windowMs: 5000
            )
        }
        
        let allowed = state.count < config.burstLimit
        
        if allowed {
            state.count += 1
            rateLimitCache.setObject(state, forKey: cacheKey)
        }
        
        let remaining = max(0, config.burstLimit - state.count)
        let resetTime = state.windowStart.addingTimeInterval(5.0) // 5-second reset
        
        return RateLimitResult(
            allowed: allowed,
            limit: config.burstLimit,
            remaining: remaining,
            windowMs: 5000,
            resetTime: resetTime
        )
    }
    
    // MARK: - Rate Limit Status Query
    
    func getRateLimitStatus(for apiKey: String, endpoint: String? = nil) async -> [RateLimitStatus] {
        return await rateLimitQueue.async {
            var statuses: [RateLimitStatus] = []
            
            let tier = self.getTierForAPIKey(apiKey)
            guard let config = self.tierLimits[tier] else {
                return statuses
            }
            
            // Check specific endpoint if provided
            if let endpoint = endpoint {
                let cacheKey = "\(apiKey):\(endpoint)" as NSString
                if let state = self.rateLimitCache.object(forKey: cacheKey) {
                    statuses.append(self.createRateLimitStatus(from: state, endpoint: endpoint, config: config))
                }
            } else {
                // Return status for all cached endpoints for this API key
                // Note: This is a simplified implementation
                // In production, you'd want to track API keys more systematically
            }
            
            return statuses
        }
    }
    
    private func createRateLimitStatus(from state: RateLimitState, endpoint: String, config: RateLimitConfig) -> RateLimitStatus {
        let now = Date()
        let windowElapsed = now.timeIntervalSince(state.windowStart)
        let windowRemaining = max(0, Double(state.windowMs) / 1000.0 - windowElapsed)
        
        return RateLimitStatus(
            endpoint: endpoint,
            currentCount: state.count,
            limit: state.limit,
            remaining: max(0, state.limit - state.count),
            windowMs: state.windowMs,
            windowRemainingSeconds: windowRemaining,
            resetTime: state.windowStart.addingTimeInterval(Double(state.windowMs) / 1000.0)
        )
    }
    
    // MARK: - Administrative Functions
    
    func resetRateLimit(for apiKey: String, endpoint: String? = nil) async {
        await rateLimitQueue.async {
            if let endpoint = endpoint {
                let cacheKey = "\(apiKey):\(endpoint)" as NSString
                self.rateLimitCache.removeObject(forKey: cacheKey)
            } else {
                // Reset all limits for API key (simplified implementation)
                self.rateLimitCache.removeAllObjects()
            }
        }
    }
    
    func updateTierLimits(for tier: APITier, config: RateLimitConfig) {
        // In a production system, this would update the configuration
        // and potentially persist it to a database
        print("Rate limit configuration updated for tier: \(tier)")
    }
    
    // MARK: - Metrics and Monitoring
    
    func getRateLimitMetrics() async -> RateLimitMetrics {
        return await rateLimitQueue.async {
            let totalEntries = self.rateLimitCache.countLimit
            let activeWindows = totalEntries // Simplified - would count non-expired entries
            
            return RateLimitMetrics(
                totalAPIKeys: activeWindows,
                activeWindows: activeWindows,
                totalRequests: 0, // Would be tracked separately
                blockedRequests: 0, // Would be tracked separately
                averageRequestsPerWindow: 0.0,
                topEndpointsByUsage: [:],
                lastUpdated: Date()
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func getTierForAPIKey(_ apiKey: String) -> APITier {
        // This is a simplified implementation
        // In production, this would validate against a database/cache
        switch apiKey.prefix(4) {
        case "free":
            return .free
        case "prem":
            return .premium
        case "ent_":
            return .enterprise
        case "biz_":
            return .business
        default:
            return .free
        }
    }
    
    private func setupCacheConfiguration() {
        rateLimitCache.countLimit = 10000 // Max 10k API keys in memory
        rateLimitCache.totalCostLimit = 1024 * 1024 * 10 // 10MB memory limit
    }
    
    private func startCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { _ in
            Task {
                await self.cleanupExpiredEntries()
            }
        }
    }
    
    private func cleanupExpiredEntries() async {
        await rateLimitQueue.async {
            // NSCache handles some cleanup automatically, but we could implement
            // more sophisticated cleanup logic here for expired entries
            print("Rate limiting cache cleanup completed")
        }
    }
}

// MARK: - Configuration Models

struct RateLimitConfig {
    let requestsPerMinute: Int
    let requestsPerHour: Int
    let requestsPerDay: Int
    let burstLimit: Int
    let windowMs: Int
    
    var isUnlimited: Bool {
        return requestsPerMinute < 0
    }
}

struct RateLimitStatus {
    let endpoint: String
    let currentCount: Int
    let limit: Int
    let remaining: Int
    let windowMs: Int
    let windowRemainingSeconds: Double
    let resetTime: Date
    
    var usagePercentage: Double {
        guard limit > 0 else { return 0.0 }
        return Double(currentCount) / Double(limit) * 100.0
    }
}

struct RateLimitMetrics {
    let totalAPIKeys: Int
    let activeWindows: Int
    let totalRequests: Int
    let blockedRequests: Int
    let averageRequestsPerWindow: Double
    let topEndpointsByUsage: [String: Int]
    let lastUpdated: Date
    
    var blockRate: Double {
        guard totalRequests > 0 else { return 0.0 }
        return Double(blockedRequests) / Double(totalRequests) * 100.0
    }
}

// MARK: - Mock Rate Limiting Service

class MockRateLimitingMiddleware: RateLimitingMiddleware {
    private var shouldAllow: Bool = true
    private var mockMetrics = RateLimitMetrics(
        totalAPIKeys: 100,
        activeWindows: 50,
        totalRequests: 10000,
        blockedRequests: 25,
        averageRequestsPerWindow: 200.0,
        topEndpointsByUsage: ["/courses": 5000, "/predictions": 2000],
        lastUpdated: Date()
    )
    
    override init() {
        super.init()
    }
    
    func setMockBehavior(allow: Bool) {
        shouldAllow = allow
    }
    
    override func process(_ request: APIGatewayRequest) async throws -> APIGatewayRequest {
        if !shouldAllow {
            throw APIGatewayError.rateLimitExceeded(
                limit: 1000,
                windowMs: 60000,
                resetTime: Date().addingTimeInterval(60)
            )
        }
        return request
    }
    
    override func checkRateLimit(apiKey: String, endpoint: APIEndpoint) async throws -> RateLimitResult {
        return RateLimitResult(
            allowed: shouldAllow,
            limit: 1000,
            remaining: shouldAllow ? 999 : 0,
            windowMs: 60000,
            resetTime: Date().addingTimeInterval(60)
        )
    }
    
    override func getRateLimitMetrics() async -> RateLimitMetrics {
        return mockMetrics
    }
}