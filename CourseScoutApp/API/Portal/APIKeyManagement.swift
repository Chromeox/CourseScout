import Foundation
import Appwrite
import CryptoKit

// MARK: - API Key Management Service Protocol

protocol APIKeyManagementServiceProtocol {
    // MARK: - Key Generation and Management
    func generateAPIKey(for userId: String, tier: APITier, name: String?, description: String?) async throws -> APIKeyInfo
    func listAPIKeys(for userId: String) async throws -> [APIKeyInfo]
    func getAPIKeyDetails(_ keyId: String, userId: String) async throws -> APIKeyDetails
    func updateAPIKey(_ keyId: String, userId: String, update: APIKeyUpdate) async throws -> APIKeyInfo
    func regenerateAPIKey(_ keyId: String, userId: String) async throws -> APIKeyInfo
    func revokeAPIKey(_ keyId: String, userId: String) async throws
    
    // MARK: - Key Validation and Status
    func validateAPIKey(_ apiKey: String) async throws -> APIKeyValidation
    func getAPIKeyUsage(_ keyId: String, userId: String, period: UsagePeriod) async throws -> APIKeyUsageStats
    func checkKeyQuota(_ keyId: String) async throws -> QuotaStatus
    
    // MARK: - Tier Management
    func upgradeTier(_ keyId: String, userId: String, newTier: APITier) async throws -> APIKeyInfo
    func downgradeTier(_ keyId: String, userId: String, newTier: APITier) async throws -> APIKeyInfo
    func getTierLimits(_ tier: APITier) -> TierLimits
    
    // MARK: - Security and Monitoring
    func rotateAPIKey(_ keyId: String, userId: String) async throws -> APIKeyRotationResult
    func enableKeyMonitoring(_ keyId: String, userId: String) async throws
    func disableKeyMonitoring(_ keyId: String, userId: String) async throws
    func getSecurityEvents(for keyId: String, userId: String) async throws -> [SecurityEvent]
}

// MARK: - API Key Management Service Implementation

@MainActor
class APIKeyManagementService: APIKeyManagementServiceProtocol, ObservableObject {
    // MARK: - Properties
    
    private let appwriteClient: Client
    private let databases: Databases
    private let authService: AuthenticationMiddleware
    
    @Published var managedKeys: [APIKeyInfo] = []
    @Published var isLoading: Bool = false
    
    // MARK: - Configuration
    
    private let keyExpirationDays: [APITier: Int] = [
        .free: 365,      // 1 year
        .premium: 730,   // 2 years
        .enterprise: -1, // Never expires
        .business: -1    // Never expires
    ]
    
    private let maxKeysPerTier: [APITier: Int] = [
        .free: 2,
        .premium: 5,
        .enterprise: 20,
        .business: 50
    ]
    
    // MARK: - Security
    
    private let keyValidationCache = NSCache<NSString, CachedKeyValidation>()
    private let securityEventTracker = SecurityEventTracker()
    
    // MARK: - Initialization
    
    init(appwriteClient: Client, authService: AuthenticationMiddleware) {
        self.appwriteClient = appwriteClient
        self.databases = Databases(appwriteClient)
        self.authService = authService
        
        setupCacheConfiguration()
    }
    
    // MARK: - Key Generation and Management
    
    func generateAPIKey(for userId: String, tier: APITier, name: String?, description: String?) async throws -> APIKeyInfo {
        isLoading = true
        defer { isLoading = false }
        
        // Check if user can create more keys for this tier
        let existingKeys = try await listAPIKeys(for: userId)
        let keysForTier = existingKeys.filter { $0.tier == tier && $0.isActive }
        
        guard keysForTier.count < (maxKeysPerTier[tier] ?? 1) else {
            throw APIKeyManagementError.tierKeyLimitExceeded(tier: tier, limit: maxKeysPerTier[tier] ?? 1)
        }
        
        // Generate secure API key
        let apiKey = generateSecureAPIKey(tier: tier)
        let keyHash = hashAPIKey(apiKey)
        
        // Calculate expiration date
        let expiresAt: Date?
        if let expirationDays = keyExpirationDays[tier], expirationDays > 0 {
            expiresAt = Calendar.current.date(byAdding: .day, value: expirationDays, to: Date())
        } else {
            expiresAt = nil // Never expires
        }
        
        // Create key record in database
        let keyData: [String: Any] = [
            "user_id": userId,
            "api_key_hash": keyHash,
            "key_prefix": String(apiKey.prefix(8)), // Store prefix for identification
            "tier": tier.rawValue,
            "name": name ?? "API Key \(Date().formatted(.dateTime.day().month().year()))",
            "description": description ?? "",
            "is_active": true,
            "created_at": Date().timeIntervalSince1970,
            "expires_at": expiresAt?.timeIntervalSince1970 as Any,
            "last_used_at": NSNull(),
            "usage_count": 0,
            "monthly_quota": tier.dailyRequestLimit * 30,
            "current_month_usage": 0,
            "monitoring_enabled": tier != .free,
            "rate_limit_config": createRateLimitConfig(for: tier)
        ]
        
        let document = try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: ID.unique(),
            data: keyData
        )
        
        let keyInfo = APIKeyInfo(
            id: document.id,
            keyPrefix: String(apiKey.prefix(8)) + "...",
            fullKey: apiKey, // Only returned during creation
            tier: tier,
            name: name ?? "API Key \(Date().formatted(.dateTime.day().month().year()))",
            description: description ?? "",
            isActive: true,
            createdAt: Date(),
            expiresAt: expiresAt,
            lastUsedAt: nil,
            usageCount: 0,
            monthlyQuota: tier.dailyRequestLimit * 30,
            currentMonthUsage: 0,
            monitoringEnabled: tier != .free
        )
        
        // Track security event
        await securityEventTracker.trackEvent(
            .keyGenerated,
            keyId: document.id,
            userId: userId,
            metadata: ["tier": tier.rawValue, "name": name ?? ""]
        )
        
        // Update published array
        managedKeys.append(keyInfo)
        
        return keyInfo
    }
    
    func listAPIKeys(for userId: String) async throws -> [APIKeyInfo] {
        let queries = [
            Query.equal("user_id", value: userId),
            Query.orderDesc("created_at")
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            queries: queries
        )
        
        let keys = try documents.documents.map { document in
            try parseAPIKeyInfo(from: document)
        }
        
        await MainActor.run {
            self.managedKeys = keys
        }
        
        return keys
    }
    
    func getAPIKeyDetails(_ keyId: String, userId: String) async throws -> APIKeyDetails {
        // Verify ownership
        let document = try await databases.getDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId
        )
        
        guard document.data["user_id"] as? String == userId else {
            throw APIKeyManagementError.keyNotFound
        }
        
        // Get usage statistics
        let usageStats = try await getAPIKeyUsage(keyId, userId: userId, period: .currentMonth)
        
        // Get recent security events
        let securityEvents = try await getSecurityEvents(for: keyId, userId: userId)
        
        return APIKeyDetails(
            info: try parseAPIKeyInfo(from: document),
            usageStats: usageStats,
            recentSecurityEvents: Array(securityEvents.prefix(10)),
            permissions: getKeyPermissions(tier: APITier(rawValue: document.data["tier"] as? String ?? "free") ?? .free),
            rateLimits: parseRateLimitConfig(from: document.data)
        )
    }
    
    func updateAPIKey(_ keyId: String, userId: String, update: APIKeyUpdate) async throws -> APIKeyInfo {
        // Verify ownership first
        let existingDocument = try await databases.getDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId
        )
        
        guard existingDocument.data["user_id"] as? String == userId else {
            throw APIKeyManagementError.keyNotFound
        }
        
        var updateData: [String: Any] = [
            "updated_at": Date().timeIntervalSince1970
        ]
        
        if let name = update.name {
            updateData["name"] = name
        }
        
        if let description = update.description {
            updateData["description"] = description
        }
        
        if let monitoringEnabled = update.monitoringEnabled {
            updateData["monitoring_enabled"] = monitoringEnabled
        }
        
        let updatedDocument = try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId,
            data: updateData
        )
        
        // Track security event
        await securityEventTracker.trackEvent(
            .keyUpdated,
            keyId: keyId,
            userId: userId,
            metadata: update.toDictionary()
        )
        
        return try parseAPIKeyInfo(from: updatedDocument)
    }
    
    func regenerateAPIKey(_ keyId: String, userId: String) async throws -> APIKeyInfo {
        // Get existing key info
        let existingDocument = try await databases.getDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId
        )
        
        guard existingDocument.data["user_id"] as? String == userId else {
            throw APIKeyManagementError.keyNotFound
        }
        
        let tier = APITier(rawValue: existingDocument.data["tier"] as? String ?? "free") ?? .free
        
        // Generate new API key
        let newAPIKey = generateSecureAPIKey(tier: tier)
        let newKeyHash = hashAPIKey(newAPIKey)
        
        // Update in database
        let updateData: [String: Any] = [
            "api_key_hash": newKeyHash,
            "key_prefix": String(newAPIKey.prefix(8)),
            "regenerated_at": Date().timeIntervalSince1970,
            "usage_count": 0, // Reset usage count
            "current_month_usage": 0 // Reset monthly usage
        ]
        
        let updatedDocument = try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId,
            data: updateData
        )
        
        // Invalidate cache for old key
        keyValidationCache.removeAllObjects()
        
        // Track security event
        await securityEventTracker.trackEvent(
            .keyRegenerated,
            keyId: keyId,
            userId: userId
        )
        
        var keyInfo = try parseAPIKeyInfo(from: updatedDocument)
        keyInfo.fullKey = newAPIKey // Include full key in response
        
        return keyInfo
    }
    
    func revokeAPIKey(_ keyId: String, userId: String) async throws {
        // Verify ownership
        let existingDocument = try await databases.getDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId
        )
        
        guard existingDocument.data["user_id"] as? String == userId else {
            throw APIKeyManagementError.keyNotFound
        }
        
        // Deactivate the key
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId,
            data: [
                "is_active": false,
                "revoked_at": Date().timeIntervalSince1970
            ]
        )
        
        // Remove from cache
        keyValidationCache.removeAllObjects()
        
        // Track security event
        await securityEventTracker.trackEvent(
            .keyRevoked,
            keyId: keyId,
            userId: userId
        )
        
        // Update local array
        managedKeys.removeAll { $0.id == keyId }
    }
    
    // MARK: - Key Validation and Status
    
    func validateAPIKey(_ apiKey: String) async throws -> APIKeyValidation {
        // Check cache first
        let cacheKey = NSString(string: apiKey)
        if let cached = keyValidationCache.object(forKey: cacheKey),
           !cached.isExpired {
            return cached.validation
        }
        
        // Hash the API key for lookup
        let keyHash = hashAPIKey(apiKey)
        
        let queries = [
            Query.equal("api_key_hash", value: keyHash),
            Query.equal("is_active", value: true)
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            queries: queries
        )
        
        guard let document = documents.documents.first else {
            let validation = APIKeyValidation(
                isValid: false,
                keyId: nil,
                userId: nil,
                tier: .free,
                expiresAt: nil,
                quotaStatus: .unlimited,
                lastValidated: Date()
            )
            return validation
        }
        
        // Check expiration
        let isExpired: Bool
        if let expiresAtTimestamp = document.data["expires_at"] as? Double {
            isExpired = Date().timeIntervalSince1970 > expiresAtTimestamp
        } else {
            isExpired = false
        }
        
        // Check quota
        let quotaStatus = try await checkKeyQuotaInternal(document: document)
        
        let validation = APIKeyValidation(
            isValid: !isExpired && quotaStatus != .exceeded,
            keyId: document.id,
            userId: document.data["user_id"] as? String,
            tier: APITier(rawValue: document.data["tier"] as? String ?? "free") ?? .free,
            expiresAt: isExpired ? Date(timeIntervalSince1970: document.data["expires_at"] as? Double ?? 0) : nil,
            quotaStatus: quotaStatus,
            lastValidated: Date()
        )
        
        // Cache the validation result
        let cached = CachedKeyValidation(
            validation: validation,
            timestamp: Date(),
            ttlSeconds: 300 // 5 minutes
        )
        keyValidationCache.setObject(cached, forKey: cacheKey)
        
        // Update last used timestamp
        if validation.isValid {
            try await updateLastUsed(keyId: document.id)
        }
        
        return validation
    }
    
    func getAPIKeyUsage(_ keyId: String, userId: String, period: UsagePeriod) async throws -> APIKeyUsageStats {
        // Verify ownership
        let document = try await databases.getDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId
        )
        
        guard document.data["user_id"] as? String == userId else {
            throw APIKeyManagementError.keyNotFound
        }
        
        // Get usage records from usage tracking service
        let (startDate, endDate) = getDateRange(for: period)
        
        let usageQueries = [
            Query.equal("api_key", value: keyId),
            Query.greaterThanEqual("timestamp", value: startDate.timeIntervalSince1970),
            Query.lessThanEqual("timestamp", value: endDate.timeIntervalSince1970)
        ]
        
        let usageDocuments = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "usage_records",
            queries: usageQueries
        )
        
        return calculateUsageStats(from: usageDocuments.documents, period: period)
    }
    
    func checkKeyQuota(_ keyId: String) async throws -> QuotaStatus {
        let document = try await databases.getDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId
        )
        
        return try await checkKeyQuotaInternal(document: document)
    }
    
    // MARK: - Tier Management
    
    func upgradeTier(_ keyId: String, userId: String, newTier: APITier) async throws -> APIKeyInfo {
        guard newTier.priority > APITier.free.priority else {
            throw APIKeyManagementError.invalidTierUpgrade
        }
        
        let updateData: [String: Any] = [
            "tier": newTier.rawValue,
            "monthly_quota": newTier.dailyRequestLimit * 30,
            "rate_limit_config": createRateLimitConfig(for: newTier),
            "upgraded_at": Date().timeIntervalSince1970
        ]
        
        let updatedDocument = try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId,
            data: updateData
        )
        
        // Clear cache
        keyValidationCache.removeAllObjects()
        
        // Track security event
        await securityEventTracker.trackEvent(
            .tierUpgraded,
            keyId: keyId,
            userId: userId,
            metadata: ["new_tier": newTier.rawValue]
        )
        
        return try parseAPIKeyInfo(from: updatedDocument)
    }
    
    func downgradeTier(_ keyId: String, userId: String, newTier: APITier) async throws -> APIKeyInfo {
        let updateData: [String: Any] = [
            "tier": newTier.rawValue,
            "monthly_quota": newTier.dailyRequestLimit * 30,
            "rate_limit_config": createRateLimitConfig(for: newTier),
            "downgraded_at": Date().timeIntervalSince1970
        ]
        
        let updatedDocument = try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId,
            data: updateData
        )
        
        // Clear cache
        keyValidationCache.removeAllObjects()
        
        // Track security event
        await securityEventTracker.trackEvent(
            .tierDowngraded,
            keyId: keyId,
            userId: userId,
            metadata: ["new_tier": newTier.rawValue]
        )
        
        return try parseAPIKeyInfo(from: updatedDocument)
    }
    
    func getTierLimits(_ tier: APITier) -> TierLimits {
        return TierLimits(
            tier: tier,
            dailyRequestLimit: tier.dailyRequestLimit,
            monthlyRequestLimit: tier.dailyRequestLimit * 30,
            rateLimitPerMinute: getRateLimitPerMinute(for: tier),
            maxAPIKeys: maxKeysPerTier[tier] ?? 1,
            expirationDays: keyExpirationDays[tier],
            features: getTierFeatures(tier),
            costPerThousandRequests: getTierCostPerThousand(tier)
        )
    }
    
    // MARK: - Security and Monitoring
    
    func rotateAPIKey(_ keyId: String, userId: String) async throws -> APIKeyRotationResult {
        // Generate new key while keeping old one active for grace period
        let oldKey = try await getAPIKeyDetails(keyId, userId: userId)
        let newKeyInfo = try await regenerateAPIKey(keyId, userId: userId)
        
        // Schedule old key deactivation (grace period of 24 hours)
        let gracePeriodEnd = Date().addingTimeInterval(86400)
        
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId,
            data: [
                "rotation_grace_period_end": gracePeriodEnd.timeIntervalSince1970
            ]
        )
        
        return APIKeyRotationResult(
            newKey: newKeyInfo,
            gracePeriodEnd: gracePeriodEnd,
            rotatedAt: Date()
        )
    }
    
    func enableKeyMonitoring(_ keyId: String, userId: String) async throws {
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId,
            data: ["monitoring_enabled": true]
        )
    }
    
    func disableKeyMonitoring(_ keyId: String, userId: String) async throws {
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId,
            data: ["monitoring_enabled": false]
        )
    }
    
    func getSecurityEvents(for keyId: String, userId: String) async throws -> [SecurityEvent] {
        return await securityEventTracker.getEvents(for: keyId, userId: userId)
    }
    
    // MARK: - Helper Methods
    
    private func generateSecureAPIKey(tier: APITier) -> String {
        let prefix = tier.rawValue.prefix(4).lowercased()
        let randomPart = generateSecureRandomString(length: 32)
        return "\(prefix)_\(randomPart)"
    }
    
    private func generateSecureRandomString(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    private func hashAPIKey(_ apiKey: String) -> String {
        let data = Data(apiKey.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func setupCacheConfiguration() {
        keyValidationCache.countLimit = 1000
        keyValidationCache.totalCostLimit = 1024 * 1024 * 5 // 5MB
    }
    
    private func parseAPIKeyInfo(from document: Document) throws -> APIKeyInfo {
        let data = document.data
        return APIKeyInfo(
            id: document.id,
            keyPrefix: (data["key_prefix"] as? String ?? "") + "...",
            fullKey: nil, // Never return full key except during creation
            tier: APITier(rawValue: data["tier"] as? String ?? "free") ?? .free,
            name: data["name"] as? String ?? "",
            description: data["description"] as? String ?? "",
            isActive: data["is_active"] as? Bool ?? false,
            createdAt: Date(timeIntervalSince1970: data["created_at"] as? Double ?? 0),
            expiresAt: (data["expires_at"] as? Double).map { Date(timeIntervalSince1970: $0) },
            lastUsedAt: (data["last_used_at"] as? Double).map { Date(timeIntervalSince1970: $0) },
            usageCount: data["usage_count"] as? Int ?? 0,
            monthlyQuota: data["monthly_quota"] as? Int ?? 1000,
            currentMonthUsage: data["current_month_usage"] as? Int ?? 0,
            monitoringEnabled: data["monitoring_enabled"] as? Bool ?? false
        )
    }
    
    private func createRateLimitConfig(for tier: APITier) -> [String: Any] {
        return [
            "requests_per_minute": getRateLimitPerMinute(for: tier),
            "burst_limit": getBurstLimit(for: tier),
            "window_ms": 60000
        ]
    }
    
    private func getRateLimitPerMinute(for tier: APITier) -> Int {
        switch tier {
        case .free: return 16
        case .premium: return 167
        case .enterprise: return 1667
        case .business: return -1 // Unlimited
        }
    }
    
    private func getBurstLimit(for tier: APITier) -> Int {
        switch tier {
        case .free: return 10
        case .premium: return 50
        case .enterprise: return 200
        case .business: return 500
        }
    }
    
    private func getTierFeatures(_ tier: APITier) -> [String] {
        switch tier {
        case .free:
            return ["Basic API access", "1,000 requests/day", "Community support"]
        case .premium:
            return ["Advanced analytics", "10,000 requests/day", "Email support", "Custom webhooks"]
        case .enterprise:
            return ["All premium features", "100,000 requests/day", "Priority support", "SLA guarantee", "Custom integrations"]
        case .business:
            return ["All enterprise features", "Unlimited requests", "Dedicated support", "Custom solutions"]
        }
    }
    
    private func getTierCostPerThousand(_ tier: APITier) -> Double {
        switch tier {
        case .free: return 0.0
        case .premium: return 0.01
        case .enterprise: return 0.005
        case .business: return 0.002
        }
    }
    
    private func checkKeyQuotaInternal(document: Document) async throws -> QuotaStatus {
        let tier = APITier(rawValue: document.data["tier"] as? String ?? "free") ?? .free
        let monthlyQuota = document.data["monthly_quota"] as? Int ?? tier.dailyRequestLimit * 30
        let currentUsage = document.data["current_month_usage"] as? Int ?? 0
        
        if tier == .business || monthlyQuota <= 0 {
            return .unlimited
        }
        
        let usagePercentage = Double(currentUsage) / Double(monthlyQuota)
        
        if usagePercentage >= 1.0 {
            return .exceeded
        } else if usagePercentage >= 0.9 {
            return .nearLimit(remaining: monthlyQuota - currentUsage, percentage: usagePercentage)
        } else {
            return .withinLimit(used: currentUsage, total: monthlyQuota, percentage: usagePercentage)
        }
    }
    
    private func updateLastUsed(keyId: String) async throws {
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: keyId,
            data: [
                "last_used_at": Date().timeIntervalSince1970,
                "usage_count": Query.increment("usage_count", by: 1)
            ]
        )
    }
    
    private func getDateRange(for period: UsagePeriod) -> (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current
        
        switch period {
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            let start = calendar.startOfDay(for: yesterday)
            let end = calendar.startOfDay(for: now)
            return (start, end)
        case .currentWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            return (start, now)
        case .currentMonth:
            let start = calendar.dateInterval(of: .month, for: now)!.start
            return (start, now)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)!
            return (start, now)
        }
    }
    
    private func calculateUsageStats(from documents: [Document], period: UsagePeriod) -> APIKeyUsageStats {
        var totalRequests = 0
        var successfulRequests = 0
        var failedRequests = 0
        var totalCostCents = 0.0
        var endpointUsage: [String: Int] = [:]
        
        for document in documents {
            let data = document.data
            let statusCode = data["status_code"] as? Int ?? 500
            let endpoint = data["endpoint"] as? String ?? "unknown"
            let costCents = data["cost_cents"] as? Double ?? 0.0
            
            totalRequests += 1
            totalCostCents += costCents
            
            if statusCode >= 200 && statusCode < 400 {
                successfulRequests += 1
            } else {
                failedRequests += 1
            }
            
            endpointUsage[endpoint, default: 0] += 1
        }
        
        return APIKeyUsageStats(
            period: period,
            totalRequests: totalRequests,
            successfulRequests: successfulRequests,
            failedRequests: failedRequests,
            successRate: totalRequests > 0 ? Double(successfulRequests) / Double(totalRequests) : 0.0,
            totalCostCents: totalCostCents,
            endpointUsage: endpointUsage,
            generatedAt: Date()
        )
    }
    
    private func getKeyPermissions(tier: APITier) -> [String] {
        switch tier {
        case .free:
            return ["/courses", "/health"]
        case .premium:
            return ["/courses", "/courses/search", "/courses/analytics", "/health"]
        case .enterprise:
            return ["/courses", "/courses/search", "/courses/analytics", "/predictions", "/health"]
        case .business:
            return ["/courses", "/courses/search", "/courses/analytics", "/predictions", "/booking/realtime", "/health"]
        }
    }
    
    private func parseRateLimitConfig(from data: [String: Any]) -> RateLimitConfiguration {
        guard let config = data["rate_limit_config"] as? [String: Any] else {
            return RateLimitConfiguration(requestsPerMinute: 16, burstLimit: 10, windowMs: 60000)
        }
        
        return RateLimitConfiguration(
            requestsPerMinute: config["requests_per_minute"] as? Int ?? 16,
            burstLimit: config["burst_limit"] as? Int ?? 10,
            windowMs: config["window_ms"] as? Int ?? 60000
        )
    }
}

// MARK: - Data Models

struct APIKeyInfo {
    let id: String
    let keyPrefix: String
    var fullKey: String? // Only populated during creation/regeneration
    let tier: APITier
    let name: String
    let description: String
    let isActive: Bool
    let createdAt: Date
    let expiresAt: Date?
    let lastUsedAt: Date?
    let usageCount: Int
    let monthlyQuota: Int
    let currentMonthUsage: Int
    let monitoringEnabled: Bool
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
    var quotaUsagePercentage: Double {
        guard monthlyQuota > 0 else { return 0.0 }
        return Double(currentMonthUsage) / Double(monthlyQuota)
    }
}

struct APIKeyDetails {
    let info: APIKeyInfo
    let usageStats: APIKeyUsageStats
    let recentSecurityEvents: [SecurityEvent]
    let permissions: [String]
    let rateLimits: RateLimitConfiguration
}

struct APIKeyUpdate {
    let name: String?
    let description: String?
    let monitoringEnabled: Bool?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let name = name { dict["name"] = name }
        if let description = description { dict["description"] = description }
        if let monitoring = monitoringEnabled { dict["monitoring_enabled"] = monitoring }
        return dict
    }
}

struct APIKeyValidation {
    let isValid: Bool
    let keyId: String?
    let userId: String?
    let tier: APITier
    let expiresAt: Date?
    let quotaStatus: QuotaStatus
    let lastValidated: Date
}

struct CachedKeyValidation {
    let validation: APIKeyValidation
    let timestamp: Date
    let ttlSeconds: TimeInterval
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > ttlSeconds
    }
}

enum UsagePeriod: String, CaseIterable {
    case today = "today"
    case yesterday = "yesterday"
    case currentWeek = "current_week"
    case currentMonth = "current_month"
    case last30Days = "last_30_days"
}

struct APIKeyUsageStats {
    let period: UsagePeriod
    let totalRequests: Int
    let successfulRequests: Int
    let failedRequests: Int
    let successRate: Double
    let totalCostCents: Double
    let endpointUsage: [String: Int]
    let generatedAt: Date
    
    var totalCostDollars: Double {
        return totalCostCents / 100.0
    }
}

enum QuotaStatus {
    case unlimited
    case withinLimit(used: Int, total: Int, percentage: Double)
    case nearLimit(remaining: Int, percentage: Double)
    case exceeded
}

struct TierLimits {
    let tier: APITier
    let dailyRequestLimit: Int
    let monthlyRequestLimit: Int
    let rateLimitPerMinute: Int
    let maxAPIKeys: Int
    let expirationDays: Int?
    let features: [String]
    let costPerThousandRequests: Double
}

struct APIKeyRotationResult {
    let newKey: APIKeyInfo
    let gracePeriodEnd: Date
    let rotatedAt: Date
}

struct RateLimitConfiguration {
    let requestsPerMinute: Int
    let burstLimit: Int
    let windowMs: Int
}

// MARK: - Security Event Tracking

class SecurityEventTracker {
    private var events: [SecurityEvent] = []
    private let eventQueue = DispatchQueue(label: "SecurityEvents", qos: .utility)
    
    func trackEvent(_ type: SecurityEventType, keyId: String, userId: String, metadata: [String: Any] = [:]) async {
        let event = SecurityEvent(
            id: UUID().uuidString,
            type: type,
            keyId: keyId,
            userId: userId,
            timestamp: Date(),
            metadata: metadata
        )
        
        await eventQueue.async {
            self.events.append(event)
            
            // Keep only last 1000 events in memory
            if self.events.count > 1000 {
                self.events.removeFirst(self.events.count - 1000)
            }
        }
    }
    
    func getEvents(for keyId: String, userId: String) async -> [SecurityEvent] {
        return await eventQueue.async {
            return self.events.filter { $0.keyId == keyId && $0.userId == userId }
                .sorted { $0.timestamp > $1.timestamp }
        }
    }
}

struct SecurityEvent {
    let id: String
    let type: SecurityEventType
    let keyId: String
    let userId: String
    let timestamp: Date
    let metadata: [String: Any]
}

enum SecurityEventType {
    case keyGenerated
    case keyRegenerated
    case keyRevoked
    case keyUpdated
    case tierUpgraded
    case tierDowngraded
    case suspiciousActivity
    case quotaExceeded
    case rateLimitExceeded
}

// MARK: - Errors

enum APIKeyManagementError: Error, LocalizedError {
    case keyNotFound
    case tierKeyLimitExceeded(tier: APITier, limit: Int)
    case invalidTierUpgrade
    case keyGenerationFailed
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .keyNotFound:
            return "API key not found or you don't have permission to access it"
        case .tierKeyLimitExceeded(let tier, let limit):
            return "Maximum number of API keys (\(limit)) reached for tier \(tier.rawValue)"
        case .invalidTierUpgrade:
            return "Invalid tier upgrade requested"
        case .keyGenerationFailed:
            return "Failed to generate API key"
        case .unauthorized:
            return "Unauthorized to perform this action"
        }
    }
}

// MARK: - Mock API Key Management Service

class MockAPIKeyManagementService: APIKeyManagementServiceProtocol {
    private var mockKeys: [APIKeyInfo] = [
        APIKeyInfo(
            id: "key_1",
            keyPrefix: "prem_abc...",
            fullKey: nil,
            tier: .premium,
            name: "Production API Key",
            description: "Main production key",
            isActive: true,
            createdAt: Date().addingTimeInterval(-86400),
            expiresAt: Date().addingTimeInterval(86400 * 365),
            lastUsedAt: Date().addingTimeInterval(-3600),
            usageCount: 15420,
            monthlyQuota: 300000,
            currentMonthUsage: 125000,
            monitoringEnabled: true
        )
    ]
    
    func generateAPIKey(for userId: String, tier: APITier, name: String?, description: String?) async throws -> APIKeyInfo {
        let newKey = APIKeyInfo(
            id: "key_\(mockKeys.count + 1)",
            keyPrefix: "\(tier.rawValue.prefix(4))_xyz...",
            fullKey: "\(tier.rawValue.prefix(4))_xyzabcdefghijklmnopqrstuvwxyz123456",
            tier: tier,
            name: name ?? "API Key \(mockKeys.count + 1)",
            description: description ?? "",
            isActive: true,
            createdAt: Date(),
            expiresAt: tier == .business ? nil : Date().addingTimeInterval(86400 * 365),
            lastUsedAt: nil,
            usageCount: 0,
            monthlyQuota: tier.dailyRequestLimit * 30,
            currentMonthUsage: 0,
            monitoringEnabled: tier != .free
        )
        
        mockKeys.append(newKey)
        return newKey
    }
    
    func listAPIKeys(for userId: String) async throws -> [APIKeyInfo] {
        return mockKeys
    }
    
    func getAPIKeyDetails(_ keyId: String, userId: String) async throws -> APIKeyDetails {
        guard let key = mockKeys.first(where: { $0.id == keyId }) else {
            throw APIKeyManagementError.keyNotFound
        }
        
        return APIKeyDetails(
            info: key,
            usageStats: APIKeyUsageStats(
                period: .currentMonth,
                totalRequests: key.usageCount,
                successfulRequests: Int(Double(key.usageCount) * 0.95),
                failedRequests: Int(Double(key.usageCount) * 0.05),
                successRate: 0.95,
                totalCostCents: Double(key.usageCount) * 0.01,
                endpointUsage: ["/courses": key.usageCount / 2, "/analytics": key.usageCount / 2],
                generatedAt: Date()
            ),
            recentSecurityEvents: [],
            permissions: ["/courses", "/analytics"],
            rateLimits: RateLimitConfiguration(requestsPerMinute: 167, burstLimit: 50, windowMs: 60000)
        )
    }
    
    func updateAPIKey(_ keyId: String, userId: String, update: APIKeyUpdate) async throws -> APIKeyInfo {
        guard let index = mockKeys.firstIndex(where: { $0.id == keyId }) else {
            throw APIKeyManagementError.keyNotFound
        }
        
        var key = mockKeys[index]
        if let name = update.name {
            key = APIKeyInfo(
                id: key.id, keyPrefix: key.keyPrefix, fullKey: key.fullKey, tier: key.tier,
                name: name, description: key.description, isActive: key.isActive,
                createdAt: key.createdAt, expiresAt: key.expiresAt, lastUsedAt: key.lastUsedAt,
                usageCount: key.usageCount, monthlyQuota: key.monthlyQuota,
                currentMonthUsage: key.currentMonthUsage, monitoringEnabled: key.monitoringEnabled
            )
        }
        
        mockKeys[index] = key
        return key
    }
    
    func regenerateAPIKey(_ keyId: String, userId: String) async throws -> APIKeyInfo {
        guard let index = mockKeys.firstIndex(where: { $0.id == keyId }) else {
            throw APIKeyManagementError.keyNotFound
        }
        
        var key = mockKeys[index]
        key.fullKey = "\(key.tier.rawValue.prefix(4))_newkey123456789012345678901234"
        mockKeys[index] = key
        return key
    }
    
    func revokeAPIKey(_ keyId: String, userId: String) async throws {
        mockKeys.removeAll { $0.id == keyId }
    }
    
    func validateAPIKey(_ apiKey: String) async throws -> APIKeyValidation {
        return APIKeyValidation(
            isValid: true,
            keyId: "key_1",
            userId: "user_123",
            tier: .premium,
            expiresAt: nil,
            quotaStatus: .withinLimit(used: 125000, total: 300000, percentage: 0.42),
            lastValidated: Date()
        )
    }
    
    func getAPIKeyUsage(_ keyId: String, userId: String, period: UsagePeriod) async throws -> APIKeyUsageStats {
        return APIKeyUsageStats(
            period: period,
            totalRequests: 15420,
            successfulRequests: 14649,
            failedRequests: 771,
            successRate: 0.95,
            totalCostCents: 154.20,
            endpointUsage: ["/courses": 10000, "/analytics": 5420],
            generatedAt: Date()
        )
    }
    
    func checkKeyQuota(_ keyId: String) async throws -> QuotaStatus {
        return .withinLimit(used: 125000, total: 300000, percentage: 0.42)
    }
    
    func upgradeTier(_ keyId: String, userId: String, newTier: APITier) async throws -> APIKeyInfo {
        guard let index = mockKeys.firstIndex(where: { $0.id == keyId }) else {
            throw APIKeyManagementError.keyNotFound
        }
        
        let key = mockKeys[index]
        let upgradedKey = APIKeyInfo(
            id: key.id, keyPrefix: key.keyPrefix, fullKey: key.fullKey, tier: newTier,
            name: key.name, description: key.description, isActive: key.isActive,
            createdAt: key.createdAt, expiresAt: key.expiresAt, lastUsedAt: key.lastUsedAt,
            usageCount: key.usageCount, monthlyQuota: newTier.dailyRequestLimit * 30,
            currentMonthUsage: key.currentMonthUsage, monitoringEnabled: key.monitoringEnabled
        )
        
        mockKeys[index] = upgradedKey
        return upgradedKey
    }
    
    func downgradeTier(_ keyId: String, userId: String, newTier: APITier) async throws -> APIKeyInfo {
        return try await upgradeTier(keyId, userId: userId, newTier: newTier)
    }
    
    func getTierLimits(_ tier: APITier) -> TierLimits {
        return TierLimits(
            tier: tier,
            dailyRequestLimit: tier.dailyRequestLimit,
            monthlyRequestLimit: tier.dailyRequestLimit * 30,
            rateLimitPerMinute: tier == .free ? 16 : 167,
            maxAPIKeys: tier == .free ? 2 : 5,
            expirationDays: tier == .business ? nil : 365,
            features: ["API Access", "Analytics"],
            costPerThousandRequests: 0.01
        )
    }
    
    func rotateAPIKey(_ keyId: String, userId: String) async throws -> APIKeyRotationResult {
        let key = try await regenerateAPIKey(keyId, userId: userId)
        return APIKeyRotationResult(
            newKey: key,
            gracePeriodEnd: Date().addingTimeInterval(86400),
            rotatedAt: Date()
        )
    }
    
    func enableKeyMonitoring(_ keyId: String, userId: String) async throws {
        // Mock implementation
    }
    
    func disableKeyMonitoring(_ keyId: String, userId: String) async throws {
        // Mock implementation
    }
    
    func getSecurityEvents(for keyId: String, userId: String) async throws -> [SecurityEvent] {
        return []
    }
}