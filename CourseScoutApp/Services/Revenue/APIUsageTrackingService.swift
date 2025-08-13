import Foundation
import Combine
import Appwrite
import os.log

// MARK: - API Usage Tracking Service Protocol

protocol APIUsageTrackingServiceProtocol: AnyObject {
    // Usage Tracking
    var currentUsage: AnyPublisher<[String: APIUsage], Never> { get }
    var rateLimitStatus: AnyPublisher<[String: RateLimitStatus], Never> { get }
    
    func trackAPICall(tenantId: String, endpoint: String, method: HTTPMethod, statusCode: Int, responseTime: TimeInterval, dataSize: Int) async throws
    func getCurrentUsage(tenantId: String) async throws -> APIUsage
    func getUsageHistory(tenantId: String, period: RevenuePeriod) async throws -> [APIUsageSnapshot]
    func getUsageByEndpoint(tenantId: String, period: RevenuePeriod) async throws -> [EndpointUsage]
    
    // Rate Limiting
    func checkRateLimit(tenantId: String, endpoint: String) async throws -> RateLimitResult
    func getRateLimitStatus(tenantId: String) async throws -> RateLimitStatus
    func updateRateLimits(tenantId: String, limits: RateLimits) async throws
    func resetRateLimit(tenantId: String, endpoint: String?) async throws
    
    // Quota Management
    func checkQuota(tenantId: String, quotaType: QuotaType) async throws -> QuotaResult
    func getQuotaStatus(tenantId: String) async throws -> [QuotaStatus]
    func updateQuota(tenantId: String, quotaType: QuotaType, limit: Int, period: QuotaPeriod) async throws
    func resetQuota(tenantId: String, quotaType: QuotaType) async throws
    
    // Usage Analytics
    func getUsageAnalytics(tenantId: String, period: RevenuePeriod) async throws -> UsageAnalytics
    func getUsageTrends(tenantId: String, metric: UsageMetric, period: RevenuePeriod) async throws -> [UsageTrend]
    func detectUsageAnomalies(tenantId: String) async throws -> [UsageAnomaly]
    func getUsagePrediction(tenantId: String, days: Int) async throws -> UsagePrediction
    
    // Billing Integration
    func calculateUsageCosts(tenantId: String, period: RevenuePeriod) async throws -> UsageCosts
    func getOverageCharges(tenantId: String, period: RevenuePeriod) async throws -> [OverageCharge]
    func exportUsageData(tenantId: String, period: RevenuePeriod, format: ExportFormat) async throws -> Data
    
    // Monitoring & Alerts
    func configureUsageAlerts(tenantId: String, alerts: [UsageAlert]) async throws
    func getUsageAlerts(tenantId: String) async throws -> [UsageAlert]
    func checkUsageThresholds(tenantId: String) async throws -> [ThresholdViolation]
    
    // Delegate
    func setDelegate(_ delegate: APIUsageTrackingDelegate)
    func removeDelegate(_ delegate: APIUsageTrackingDelegate)
}

// MARK: - API Usage Tracking Delegate

protocol APIUsageTrackingDelegate: AnyObject {
    func didExceedRateLimit(tenantId: String, endpoint: String, limit: Int, window: TimeInterval)
    func didExceedQuota(tenantId: String, quotaType: QuotaType, used: Int, limit: Int)
    func didDetectUsageAnomaly(tenantId: String, anomaly: UsageAnomaly)
    func didReachUsageThreshold(tenantId: String, threshold: UsageThreshold, percentage: Double)
    func didUpdateUsage(tenantId: String, usage: APIUsage)
}

// Default implementations
extension APIUsageTrackingDelegate {
    func didExceedRateLimit(tenantId: String, endpoint: String, limit: Int, window: TimeInterval) {}
    func didExceedQuota(tenantId: String, quotaType: QuotaType, used: Int, limit: Int) {}
    func didDetectUsageAnomaly(tenantId: String, anomaly: UsageAnomaly) {}
    func didReachUsageThreshold(tenantId: String, threshold: UsageThreshold, percentage: Double) {}
    func didUpdateUsage(tenantId: String, usage: APIUsage) {}
}

// MARK: - API Usage Tracking Service Implementation

@MainActor
class APIUsageTrackingService: NSObject, APIUsageTrackingServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinder", category: "APIUsageTracking")
    
    // Published properties
    @Published private var usageData: [String: APIUsage] = [:]
    @Published private var rateLimitData: [String: RateLimitStatus] = [:]
    @Published private var quotaData: [String: [QuotaStatus]] = [:]
    
    // Combine publishers
    var currentUsage: AnyPublisher<[String: APIUsage], Never> {
        $usageData.eraseToAnyPublisher()
    }
    
    var rateLimitStatus: AnyPublisher<[String: RateLimitStatus], Never> {
        $rateLimitData.eraseToAnyPublisher()
    }
    
    // Dependencies
    @ServiceInjected(TenantManagementServiceProtocol.self) private var tenantService
    
    // Storage
    private var usageHistory: [String: [APIUsageSnapshot]] = [:]
    private var endpointUsage: [String: [EndpointUsage]] = [:]
    private var rateLimitBuckets: [String: [String: RateLimitBucket]] = [:]
    private var quotaBuckets: [String: [QuotaType: QuotaBucket]] = [:]
    
    // Configuration
    private var usageAlerts: [String: [UsageAlert]] = [:]
    private var rateLimits: [String: RateLimits] = [:]
    
    // Delegate management
    private var delegates: [WeakUsageDelegate] = []
    
    // Timers for cleanup and monitoring
    private var cleanupTimer: Timer?
    private var monitoringTimer: Timer?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupTimers()
        loadDefaultRateLimits()
        logger.info("APIUsageTrackingService initialized")
    }
    
    private func setupTimers() {
        // Cleanup expired rate limit buckets every minute
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.cleanupExpiredBuckets()
            }
        }
        
        // Monitor usage thresholds every 5 minutes
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.monitorUsageThresholds()
            }
        }
    }
    
    private func loadDefaultRateLimits() {
        // Set default rate limits for different tenant types
        rateLimits["default"] = RateLimits(
            globalLimit: 1000,
            globalWindow: 3600, // 1 hour
            endpointLimits: [
                "courses": EndpointRateLimit(limit: 100, window: 300), // 5 minutes
                "bookings": EndpointRateLimit(limit: 50, window: 300),
                "users": EndpointRateLimit(limit: 200, window: 3600),
                "search": EndpointRateLimit(limit: 500, window: 3600)
            ]
        )
    }
    
    // MARK: - Usage Tracking
    
    func trackAPICall(tenantId: String, endpoint: String, method: HTTPMethod, statusCode: Int, responseTime: TimeInterval, dataSize: Int) async throws {
        // Validate tenant exists
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let timestamp = Date()
        
        // Update current usage
        var currentUsage = usageData[tenantId] ?? APIUsage.empty(tenantId: tenantId)
        currentUsage.apiCalls += 1
        currentUsage.bandwidth += Double(dataSize) / (1024 * 1024) // Convert to MB
        
        // Update endpoint-specific usage
        if currentUsage.breakdown.endpoints[endpoint] != nil {
            currentUsage.breakdown.endpoints[endpoint]! += 1
        } else {
            currentUsage.breakdown.endpoints[endpoint] = 1
        }
        
        // Update method usage
        if currentUsage.breakdown.methods[method.rawValue] != nil {
            currentUsage.breakdown.methods[method.rawValue]! += 1
        } else {
            currentUsage.breakdown.methods[method.rawValue] = 1
        }
        
        // Update status code tracking
        if currentUsage.breakdown.statusCodes[statusCode] != nil {
            currentUsage.breakdown.statusCodes[statusCode]! += 1
        } else {
            currentUsage.breakdown.statusCodes[statusCode] = 1
        }
        
        // Update error count
        if statusCode >= 400 {
            currentUsage.breakdown.errors += 1
        }
        
        // Update average response time
        let totalResponseTime = currentUsage.breakdown.avgResponseTime * Double(currentUsage.apiCalls - 1) + responseTime
        currentUsage.breakdown.avgResponseTime = totalResponseTime / Double(currentUsage.apiCalls)
        
        currentUsage.period = timestamp
        
        // Store updated usage
        usageData[tenantId] = currentUsage
        
        // Add to usage history
        let snapshot = APIUsageSnapshot(
            timestamp: timestamp,
            tenantId: tenantId,
            endpoint: endpoint,
            method: method,
            statusCode: statusCode,
            responseTime: responseTime,
            dataSize: dataSize
        )
        
        if usageHistory[tenantId] != nil {
            usageHistory[tenantId]?.append(snapshot)
            
            // Keep only last 10,000 entries per tenant
            if usageHistory[tenantId]!.count > 10000 {
                usageHistory[tenantId]?.removeFirst(usageHistory[tenantId]!.count - 10000)
            }
        } else {
            usageHistory[tenantId] = [snapshot]
        }
        
        // Update endpoint usage aggregation
        updateEndpointUsage(tenantId: tenantId, endpoint: endpoint, timestamp: timestamp)
        
        // Update rate limit buckets
        updateRateLimitBuckets(tenantId: tenantId, endpoint: endpoint, timestamp: timestamp)
        
        // Update quota buckets
        updateQuotaBuckets(tenantId: tenantId, timestamp: timestamp)
        
        // Check thresholds and notify delegates
        await checkAndNotifyThresholds(tenantId: tenantId, usage: currentUsage)
        
        // Notify delegates of usage update
        notifyDelegates { delegate in
            delegate.didUpdateUsage(tenantId: tenantId, usage: currentUsage)
        }
        
        logger.debug("Tracked API call for tenant \(tenantId): \(method.rawValue) \(endpoint) - \(statusCode)")
    }
    
    func getCurrentUsage(tenantId: String) async throws -> APIUsage {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        return usageData[tenantId] ?? APIUsage.empty(tenantId: tenantId)
    }
    
    func getUsageHistory(tenantId: String, period: RevenuePeriod) async throws -> [APIUsageSnapshot] {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let startDate = getStartDate(for: period)
        return usageHistory[tenantId]?.filter { $0.timestamp >= startDate } ?? []
    }
    
    func getUsageByEndpoint(tenantId: String, period: RevenuePeriod) async throws -> [EndpointUsage] {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let startDate = getStartDate(for: period)
        return endpointUsage[tenantId]?.filter { $0.period >= startDate } ?? []
    }
    
    // MARK: - Rate Limiting
    
    func checkRateLimit(tenantId: String, endpoint: String) async throws -> RateLimitResult {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let limits = getRateLimitsForTenant(tenantId)
        let now = Date()
        
        // Check global rate limit
        let globalBucket = getRateLimitBucket(tenantId: tenantId, endpoint: "_global")
        let globalAllowed = checkBucketLimit(bucket: globalBucket, limit: limits.globalLimit, window: limits.globalWindow, now: now)
        
        if !globalAllowed {
            // Notify delegates
            notifyDelegates { delegate in
                delegate.didExceedRateLimit(tenantId: tenantId, endpoint: "_global", limit: limits.globalLimit, window: limits.globalWindow)
            }
            
            return RateLimitResult(
                allowed: false,
                limit: limits.globalLimit,
                remaining: 0,
                resetTime: now.addingTimeInterval(limits.globalWindow),
                retryAfter: limits.globalWindow
            )
        }
        
        // Check endpoint-specific rate limit
        if let endpointLimit = limits.endpointLimits[endpoint] {
            let endpointBucket = getRateLimitBucket(tenantId: tenantId, endpoint: endpoint)
            let endpointAllowed = checkBucketLimit(bucket: endpointBucket, limit: endpointLimit.limit, window: endpointLimit.window, now: now)
            
            if !endpointAllowed {
                // Notify delegates
                notifyDelegates { delegate in
                    delegate.didExceedRateLimit(tenantId: tenantId, endpoint: endpoint, limit: endpointLimit.limit, window: endpointLimit.window)
                }
                
                return RateLimitResult(
                    allowed: false,
                    limit: endpointLimit.limit,
                    remaining: 0,
                    resetTime: now.addingTimeInterval(endpointLimit.window),
                    retryAfter: endpointLimit.window
                )
            }
            
            return RateLimitResult(
                allowed: true,
                limit: endpointLimit.limit,
                remaining: max(0, endpointLimit.limit - endpointBucket.count),
                resetTime: endpointBucket.windowStart.addingTimeInterval(endpointLimit.window),
                retryAfter: 0
            )
        }
        
        return RateLimitResult(
            allowed: true,
            limit: limits.globalLimit,
            remaining: max(0, limits.globalLimit - globalBucket.count),
            resetTime: globalBucket.windowStart.addingTimeInterval(limits.globalWindow),
            retryAfter: 0
        )
    }
    
    func getRateLimitStatus(tenantId: String) async throws -> RateLimitStatus {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let limits = getRateLimitsForTenant(tenantId)
        var endpointStatuses: [String: EndpointRateLimitStatus] = [:]
        
        // Get status for each endpoint
        for (endpoint, limit) in limits.endpointLimits {
            let bucket = getRateLimitBucket(tenantId: tenantId, endpoint: endpoint)
            endpointStatuses[endpoint] = EndpointRateLimitStatus(
                endpoint: endpoint,
                limit: limit.limit,
                used: bucket.count,
                remaining: max(0, limit.limit - bucket.count),
                resetTime: bucket.windowStart.addingTimeInterval(limit.window)
            )
        }
        
        // Get global status
        let globalBucket = getRateLimitBucket(tenantId: tenantId, endpoint: "_global")
        
        let status = RateLimitStatus(
            tenantId: tenantId,
            globalLimit: limits.globalLimit,
            globalUsed: globalBucket.count,
            globalRemaining: max(0, limits.globalLimit - globalBucket.count),
            globalResetTime: globalBucket.windowStart.addingTimeInterval(limits.globalWindow),
            endpointStatuses: endpointStatuses,
            lastUpdated: Date()
        )
        
        rateLimitData[tenantId] = status
        return status
    }
    
    func updateRateLimits(tenantId: String, limits: RateLimits) async throws {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        rateLimits[tenantId] = limits
        logger.info("Updated rate limits for tenant: \(tenantId)")
    }
    
    func resetRateLimit(tenantId: String, endpoint: String?) async throws {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        if let endpoint = endpoint {
            // Reset specific endpoint
            rateLimitBuckets[tenantId]?[endpoint] = nil
        } else {
            // Reset all rate limits for tenant
            rateLimitBuckets[tenantId] = [:]
        }
        
        logger.info("Reset rate limits for tenant: \(tenantId), endpoint: \(endpoint ?? "all")")
    }
    
    // MARK: - Quota Management
    
    func checkQuota(tenantId: String, quotaType: QuotaType) async throws -> QuotaResult {
        guard let tenant = try await tenantService.getTenant(id: tenantId) else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let bucket = getQuotaBucket(tenantId: tenantId, quotaType: quotaType)
        let limit = getQuotaLimit(tenant: tenant, quotaType: quotaType)
        
        let remaining = max(0, limit - bucket.count)
        let allowed = bucket.count < limit
        
        if !allowed {
            // Notify delegates
            notifyDelegates { delegate in
                delegate.didExceedQuota(tenantId: tenantId, quotaType: quotaType, used: bucket.count, limit: limit)
            }
        }
        
        return QuotaResult(
            allowed: allowed,
            quotaType: quotaType,
            limit: limit,
            used: bucket.count,
            remaining: remaining,
            period: bucket.period,
            resetTime: bucket.resetTime
        )
    }
    
    func getQuotaStatus(tenantId: String) async throws -> [QuotaStatus] {
        guard let tenant = try await tenantService.getTenant(id: tenantId) else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        var statuses: [QuotaStatus] = []
        
        for quotaType in QuotaType.allCases {
            let bucket = getQuotaBucket(tenantId: tenantId, quotaType: quotaType)
            let limit = getQuotaLimit(tenant: tenant, quotaType: quotaType)
            
            statuses.append(QuotaStatus(
                quotaType: quotaType,
                limit: limit,
                used: bucket.count,
                remaining: max(0, limit - bucket.count),
                period: bucket.period,
                resetTime: bucket.resetTime,
                lastUpdated: Date()
            ))
        }
        
        quotaData[tenantId] = statuses
        return statuses
    }
    
    func updateQuota(tenantId: String, quotaType: QuotaType, limit: Int, period: QuotaPeriod) async throws {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        // Update quota bucket with new limit
        let bucket = getQuotaBucket(tenantId: tenantId, quotaType: quotaType)
        bucket.limit = limit
        bucket.period = period
        
        logger.info("Updated quota for tenant \(tenantId), type: \(quotaType.rawValue), limit: \(limit)")
    }
    
    func resetQuota(tenantId: String, quotaType: QuotaType) async throws {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        quotaBuckets[tenantId]?[quotaType] = nil
        logger.info("Reset quota for tenant \(tenantId), type: \(quotaType.rawValue)")
    }
    
    // MARK: - Usage Analytics
    
    func getUsageAnalytics(tenantId: String, period: RevenuePeriod) async throws -> UsageAnalytics {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let history = try await getUsageHistory(tenantId: tenantId, period: period)
        let endpointUsage = try await getUsageByEndpoint(tenantId: tenantId, period: period)
        
        // Calculate analytics
        let totalCalls = history.count
        let uniqueEndpoints = Set(history.map { $0.endpoint }).count
        let avgResponseTime = history.isEmpty ? 0 : history.map { $0.responseTime }.reduce(0, +) / Double(history.count)
        let errorRate = totalCalls == 0 ? 0 : Double(history.filter { $0.statusCode >= 400 }.count) / Double(totalCalls)
        
        // Peak usage analysis
        let peakHour = calculatePeakUsageHour(history: history)
        let peakDay = calculatePeakUsageDay(history: history)
        
        // Top endpoints
        let endpointCounts = Dictionary(grouping: history, by: { $0.endpoint })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        let topEndpoints = Array(endpointCounts.prefix(10))
        
        return UsageAnalytics(
            tenantId: tenantId,
            period: period,
            totalAPICalls: totalCalls,
            uniqueEndpoints: uniqueEndpoints,
            averageResponseTime: avgResponseTime,
            errorRate: errorRate,
            peakUsageHour: peakHour,
            peakUsageDay: peakDay,
            topEndpoints: topEndpoints.map { ($0.key, $0.value) },
            bandwidthUsed: calculateBandwidthUsage(history: history),
            costEstimate: try await calculateUsageCosts(tenantId: tenantId, period: period),
            generatedAt: Date()
        )
    }
    
    func getUsageTrends(tenantId: String, metric: UsageMetric, period: RevenuePeriod) async throws -> [UsageTrend] {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let history = try await getUsageHistory(tenantId: tenantId, period: period)
        
        // Group by time intervals based on period
        let timeInterval: TimeInterval
        switch period {
        case .daily:
            timeInterval = 3600 // 1 hour
        case .weekly:
            timeInterval = 86400 // 1 day
        case .monthly:
            timeInterval = 86400 // 1 day
        case .quarterly, .yearly:
            timeInterval = 604800 // 1 week
        case .custom:
            timeInterval = 86400 // 1 day
        }
        
        let groupedData = Dictionary(grouping: history) { snapshot in
            let timeSlot = floor(snapshot.timestamp.timeIntervalSince1970 / timeInterval) * timeInterval
            return Date(timeIntervalSince1970: timeSlot)
        }
        
        var trends: [UsageTrend] = []
        
        for (date, snapshots) in groupedData.sorted(by: { $0.key < $1.key }) {
            let value: Double
            switch metric {
            case .apiCalls:
                value = Double(snapshots.count)
            case .responseTime:
                value = snapshots.map { $0.responseTime }.reduce(0, +) / Double(snapshots.count)
            case .errorRate:
                value = Double(snapshots.filter { $0.statusCode >= 400 }.count) / Double(snapshots.count)
            case .bandwidth:
                value = snapshots.map { Double($0.dataSize) }.reduce(0, +) / (1024 * 1024) // MB
            }
            
            trends.append(UsageTrend(
                timestamp: date,
                metric: metric,
                value: value
            ))
        }
        
        return trends
    }
    
    func detectUsageAnomalies(tenantId: String) async throws -> [UsageAnomaly] {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let history = try await getUsageHistory(tenantId: tenantId, period: .weekly)
        var anomalies: [UsageAnomaly] = []
        
        // Detect sudden spikes in API calls
        let hourlyUsage = Dictionary(grouping: history) { snapshot in
            let hour = Calendar.current.dateComponents([.year, .month, .day, .hour], from: snapshot.timestamp)
            return Calendar.current.date(from: hour) ?? snapshot.timestamp
        }.mapValues { $0.count }
        
        let values = Array(hourlyUsage.values)
        if !values.isEmpty {
            let mean = Double(values.reduce(0, +)) / Double(values.count)
            let variance = values.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(values.count)
            let standardDeviation = sqrt(variance)
            
            let threshold = mean + (2.5 * standardDeviation) // 2.5 sigma threshold
            
            for (timestamp, count) in hourlyUsage {
                if Double(count) > threshold {
                    anomalies.append(UsageAnomaly(
                        id: UUID().uuidString,
                        tenantId: tenantId,
                        type: .suddenSpike,
                        metric: .apiCalls,
                        timestamp: timestamp,
                        value: Double(count),
                        expectedValue: mean,
                        severity: calculateAnomalySeverity(value: Double(count), expected: mean, threshold: threshold),
                        description: "Unusual spike in API calls detected: \(count) calls in one hour (expected ~\(Int(mean)))"
                    ))
                }
            }
        }
        
        // Detect error rate anomalies
        let hourlyErrors = Dictionary(grouping: history.filter { $0.statusCode >= 400 }) { snapshot in
            let hour = Calendar.current.dateComponents([.year, .month, .day, .hour], from: snapshot.timestamp)
            return Calendar.current.date(from: hour) ?? snapshot.timestamp
        }.mapValues { $0.count }
        
        for (timestamp, errorCount) in hourlyErrors {
            let totalCount = hourlyUsage[timestamp] ?? 0
            if totalCount > 0 {
                let errorRate = Double(errorCount) / Double(totalCount)
                if errorRate > 0.1 { // 10% error rate threshold
                    anomalies.append(UsageAnomaly(
                        id: UUID().uuidString,
                        tenantId: tenantId,
                        type: .highErrorRate,
                        metric: .errorRate,
                        timestamp: timestamp,
                        value: errorRate,
                        expectedValue: 0.05,
                        severity: errorRate > 0.2 ? .high : .medium,
                        description: "High error rate detected: \(Int(errorRate * 100))% errors in one hour"
                    ))
                }
            }
        }
        
        // Notify delegates of anomalies
        for anomaly in anomalies {
            notifyDelegates { delegate in
                delegate.didDetectUsageAnomaly(tenantId: tenantId, anomaly: anomaly)
            }
        }
        
        return anomalies
    }
    
    func getUsagePrediction(tenantId: String, days: Int) async throws -> UsagePrediction {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let history = try await getUsageHistory(tenantId: tenantId, period: .monthly)
        
        // Simple linear regression for prediction
        let dailyUsage = Dictionary(grouping: history) { snapshot in
            Calendar.current.startOfDay(for: snapshot.timestamp)
        }.mapValues { $0.count }
        
        let sortedData = dailyUsage.sorted { $0.key < $1.key }
        
        if sortedData.count < 7 { // Need at least a week of data
            throw UsageTrackingError.insufficientData("Need at least 7 days of usage data for prediction")
        }
        
        // Calculate trend
        let values = sortedData.map { Double($0.value) }
        let n = Double(values.count)
        let sumX = (0..<values.count).map(Double.init).reduce(0, +)
        let sumY = values.reduce(0, +)
        let sumXY = zip(0..<values.count, values).map { Double($0) * $1 }.reduce(0, +)
        let sumX2 = (0..<values.count).map { Double($0) * Double($0) }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n
        
        // Generate predictions
        var predictions: [UsagePredictionPoint] = []
        for day in 1...days {
            let x = Double(sortedData.count + day - 1)
            let predicted = intercept + slope * x
            let confidence = max(0.5, 1.0 - (Double(day) * 0.05)) // Decreasing confidence over time
            
            predictions.append(UsagePredictionPoint(
                date: Calendar.current.date(byAdding: .day, value: day, to: Date()) ?? Date(),
                predictedAPICalls: Int(max(0, predicted)),
                confidence: confidence
            ))
        }
        
        return UsagePrediction(
            tenantId: tenantId,
            predictionPeriod: days,
            predictions: predictions,
            model: "linear_regression",
            accuracy: calculatePredictionAccuracy(slope: slope),
            generatedAt: Date()
        )
    }
    
    // MARK: - Billing Integration
    
    func calculateUsageCosts(tenantId: String, period: RevenuePeriod) async throws -> UsageCosts {
        guard let tenant = try await tenantService.getTenant(id: tenantId) else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let usage = try await getCurrentUsage(tenantId: tenantId)
        let overages = try await getOverageCharges(tenantId: tenantId, period: period)
        
        // Get subscription tier for pricing
        let subscription = try? await subscriptionService.getSubscription(id: tenant.subscriptionId ?? "")
        let tier = subscription?.tier ?? SubscriptionTier.starter
        
        var totalCost: Decimal = 0
        var breakdown: [String: Decimal] = [:]
        
        // Calculate API call overage costs
        if usage.apiCalls > tier.limits.apiCallsPerMonth {
            let overage = usage.apiCalls - tier.limits.apiCallsPerMonth
            let cost = Decimal(overage) * tier.overageRates.apiCallRate
            totalCost += cost
            breakdown["api_calls"] = cost
        }
        
        // Calculate storage overage costs
        if usage.storageUsed > Double(tier.limits.storageGB) {
            let overage = usage.storageUsed - Double(tier.limits.storageGB)
            let cost = Decimal(overage) * tier.overageRates.storageRate
            totalCost += cost
            breakdown["storage"] = cost
        }
        
        // Calculate bandwidth costs (if applicable)
        if usage.bandwidth > Double(tier.limits.storageGB * 10) { // Assume 10x storage for bandwidth
            let overage = usage.bandwidth - Double(tier.limits.storageGB * 10)
            let cost = Decimal(overage) * 0.10 // $0.10 per GB bandwidth
            totalCost += cost
            breakdown["bandwidth"] = cost
        }
        
        return UsageCosts(
            tenantId: tenantId,
            period: period,
            totalCost: totalCost,
            breakdown: breakdown,
            overageCharges: overages,
            currency: "USD",
            calculatedAt: Date()
        )
    }
    
    func getOverageCharges(tenantId: String, period: RevenuePeriod) async throws -> [OverageCharge] {
        guard let tenant = try await tenantService.getTenant(id: tenantId) else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let usage = try await getCurrentUsage(tenantId: tenantId)
        let subscription = try? await subscriptionService.getSubscription(id: tenant.subscriptionId ?? "")
        let tier = subscription?.tier ?? SubscriptionTier.starter
        
        var charges: [OverageCharge] = []
        
        // API calls overage
        if usage.apiCalls > tier.limits.apiCallsPerMonth {
            let overage = usage.apiCalls - tier.limits.apiCallsPerMonth
            charges.append(OverageCharge(
                type: .apiCalls,
                quantity: overage,
                rate: tier.overageRates.apiCallRate,
                amount: Decimal(overage) * tier.overageRates.apiCallRate,
                description: "\(overage) API calls over \(tier.limits.apiCallsPerMonth) limit"
            ))
        }
        
        // Storage overage
        if usage.storageUsed > Double(tier.limits.storageGB) {
            let overage = usage.storageUsed - Double(tier.limits.storageGB)
            charges.append(OverageCharge(
                type: .storage,
                quantity: Int(overage),
                rate: tier.overageRates.storageRate,
                amount: Decimal(overage) * tier.overageRates.storageRate,
                description: "\(Int(overage)) GB storage over \(tier.limits.storageGB) GB limit"
            ))
        }
        
        return charges
    }
    
    func exportUsageData(tenantId: String, period: RevenuePeriod, format: ExportFormat) async throws -> Data {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let usage = try await getCurrentUsage(tenantId: tenantId)
        let history = try await getUsageHistory(tenantId: tenantId, period: period)
        let analytics = try await getUsageAnalytics(tenantId: tenantId, period: period)
        
        let exportData = UsageExportData(
            tenantId: tenantId,
            period: period,
            currentUsage: usage,
            history: history,
            analytics: analytics,
            exportedAt: Date()
        )
        
        switch format {
        case .json:
            return try JSONEncoder().encode(exportData)
        case .csv:
            return try convertUsageToCSV(exportData)
        case .excel:
            return try convertUsageToExcel(exportData)
        case .xml:
            return try convertUsageToXML(exportData)
        }
    }
    
    // MARK: - Monitoring & Alerts
    
    func configureUsageAlerts(tenantId: String, alerts: [UsageAlert]) async throws {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        usageAlerts[tenantId] = alerts
        logger.info("Configured \(alerts.count) usage alerts for tenant: \(tenantId)")
    }
    
    func getUsageAlerts(tenantId: String) async throws -> [UsageAlert] {
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        return usageAlerts[tenantId] ?? []
    }
    
    func checkUsageThresholds(tenantId: String) async throws -> [ThresholdViolation] {
        guard let tenant = try await tenantService.getTenant(id: tenantId) else {
            throw UsageTrackingError.tenantNotFound(tenantId)
        }
        
        let usage = try await getCurrentUsage(tenantId: tenantId)
        let alerts = usageAlerts[tenantId] ?? []
        var violations: [ThresholdViolation] = []
        
        for alert in alerts {
            let currentValue: Double
            let limit: Double
            
            switch alert.threshold.type {
            case .apiCalls:
                currentValue = Double(usage.apiCalls)
                limit = Double(tenant.limits.apiCallsPerMonth)
            case .storage:
                currentValue = usage.storageUsed
                limit = Double(tenant.limits.storageGB)
            case .bandwidth:
                currentValue = usage.bandwidth
                limit = Double(tenant.limits.storageGB * 10) // Assume 10x storage for bandwidth
            case .errorRate:
                currentValue = usage.breakdown.errors > 0 ? Double(usage.breakdown.errors) / Double(usage.apiCalls) : 0
                limit = 0.05 // 5% error rate threshold
            }
            
            let percentage = currentValue / limit
            
            if percentage >= alert.threshold.percentage {
                let violation = ThresholdViolation(
                    alertId: alert.id,
                    threshold: alert.threshold,
                    currentValue: currentValue,
                    limit: limit,
                    percentage: percentage,
                    severity: calculateViolationSeverity(percentage: percentage),
                    detectedAt: Date()
                )
                
                violations.append(violation)
                
                // Notify delegates
                notifyDelegates { delegate in
                    delegate.didReachUsageThreshold(tenantId: tenantId, threshold: alert.threshold, percentage: percentage)
                }
            }
        }
        
        return violations
    }
    
    // MARK: - Helper Methods
    
    private func updateEndpointUsage(tenantId: String, endpoint: String, timestamp: Date) {
        let dateKey = Calendar.current.startOfDay(for: timestamp)
        
        if endpointUsage[tenantId] == nil {
            endpointUsage[tenantId] = []
        }
        
        if let existingIndex = endpointUsage[tenantId]?.firstIndex(where: { $0.endpoint == endpoint && Calendar.current.startOfDay(for: $0.period) == dateKey }) {
            endpointUsage[tenantId]?[existingIndex].requestCount += 1
        } else {
            endpointUsage[tenantId]?.append(EndpointUsage(
                endpoint: endpoint,
                requestCount: 1,
                period: dateKey
            ))
        }
    }
    
    private func updateRateLimitBuckets(tenantId: String, endpoint: String, timestamp: Date) {
        if rateLimitBuckets[tenantId] == nil {
            rateLimitBuckets[tenantId] = [:]
        }
        
        // Update global bucket
        let globalBucket = getRateLimitBucket(tenantId: tenantId, endpoint: "_global")
        let limits = getRateLimitsForTenant(tenantId)
        updateBucket(bucket: globalBucket, window: limits.globalWindow, timestamp: timestamp)
        
        // Update endpoint-specific bucket
        if let endpointLimit = limits.endpointLimits[endpoint] {
            let endpointBucket = getRateLimitBucket(tenantId: tenantId, endpoint: endpoint)
            updateBucket(bucket: endpointBucket, window: endpointLimit.window, timestamp: timestamp)
        }
    }
    
    private func updateQuotaBuckets(tenantId: String, timestamp: Date) {
        if quotaBuckets[tenantId] == nil {
            quotaBuckets[tenantId] = [:]
        }
        
        for quotaType in QuotaType.allCases {
            let bucket = getQuotaBucket(tenantId: tenantId, quotaType: quotaType)
            
            // Check if we need to reset the bucket
            let shouldReset: Bool
            switch bucket.period {
            case .hourly:
                shouldReset = !Calendar.current.isDate(timestamp, equalTo: bucket.resetTime, toGranularity: .hour)
            case .daily:
                shouldReset = !Calendar.current.isDate(timestamp, equalTo: bucket.resetTime, toGranularity: .day)
            case .monthly:
                shouldReset = !Calendar.current.isDate(timestamp, equalTo: bucket.resetTime, toGranularity: .month)
            }
            
            if shouldReset {
                bucket.count = 0
                bucket.resetTime = getNextResetTime(from: timestamp, period: bucket.period)
            }
            
            bucket.count += 1
        }
    }
    
    private func getRateLimitBucket(tenantId: String, endpoint: String) -> RateLimitBucket {
        if rateLimitBuckets[tenantId] == nil {
            rateLimitBuckets[tenantId] = [:]
        }
        
        if rateLimitBuckets[tenantId]?[endpoint] == nil {
            rateLimitBuckets[tenantId]?[endpoint] = RateLimitBucket(
                count: 0,
                windowStart: Date(),
                lastRequest: Date()
            )
        }
        
        return rateLimitBuckets[tenantId]![endpoint]!
    }
    
    private func getQuotaBucket(tenantId: String, quotaType: QuotaType) -> QuotaBucket {
        if quotaBuckets[tenantId] == nil {
            quotaBuckets[tenantId] = [:]
        }
        
        if quotaBuckets[tenantId]?[quotaType] == nil {
            quotaBuckets[tenantId]?[quotaType] = QuotaBucket(
                count: 0,
                limit: 0,
                period: .monthly,
                resetTime: getNextResetTime(from: Date(), period: .monthly)
            )
        }
        
        return quotaBuckets[tenantId]![quotaType]!
    }
    
    private func getRateLimitsForTenant(_ tenantId: String) -> RateLimits {
        return rateLimits[tenantId] ?? rateLimits["default"]!
    }
    
    private func checkBucketLimit(bucket: RateLimitBucket, limit: Int, window: TimeInterval, now: Date) -> Bool {
        // Check if window has expired
        if now.timeIntervalSince(bucket.windowStart) >= window {
            bucket.count = 0
            bucket.windowStart = now
        }
        
        return bucket.count < limit
    }
    
    private func updateBucket(bucket: RateLimitBucket, window: TimeInterval, timestamp: Date) {
        // Check if window has expired
        if timestamp.timeIntervalSince(bucket.windowStart) >= window {
            bucket.count = 1
            bucket.windowStart = timestamp
        } else {
            bucket.count += 1
        }
        
        bucket.lastRequest = timestamp
    }
    
    private func getQuotaLimit(tenant: Tenant, quotaType: QuotaType) -> Int {
        switch quotaType {
        case .apiCalls:
            return tenant.limits.apiCallsPerMonth
        case .storage:
            return tenant.limits.storageGB * 1024 * 1024 * 1024 // Convert to bytes
        case .users:
            return tenant.limits.maxUsers
        case .courses:
            return tenant.limits.maxCourses
        case .bookings:
            return tenant.limits.maxBookings
        }
    }
    
    private func getNextResetTime(from date: Date, period: QuotaPeriod) -> Date {
        let calendar = Calendar.current
        
        switch period {
        case .hourly:
            return calendar.date(byAdding: .hour, value: 1, to: calendar.dateInterval(of: .hour, for: date)?.start ?? date) ?? date
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: calendar.dateInterval(of: .month, for: date)?.start ?? date) ?? date
        }
    }
    
    private func getStartDate(for period: RevenuePeriod) -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch period {
        case .daily:
            return calendar.startOfDay(for: now)
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .monthly:
            return calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .quarterly:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .yearly:
            return calendar.dateInterval(of: .year, for: now)?.start ?? now
        case .custom:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        }
    }
    
    private func calculatePeakUsageHour(history: [APIUsageSnapshot]) -> Int {
        let hourlyUsage = Dictionary(grouping: history, by: { Calendar.current.component(.hour, from: $0.timestamp) })
            .mapValues { $0.count }
        
        return hourlyUsage.max(by: { $0.value < $1.value })?.key ?? 0
    }
    
    private func calculatePeakUsageDay(history: [APIUsageSnapshot]) -> Int {
        let dailyUsage = Dictionary(grouping: history, by: { Calendar.current.component(.weekday, from: $0.timestamp) })
            .mapValues { $0.count }
        
        return dailyUsage.max(by: { $0.value < $1.value })?.key ?? 1
    }
    
    private func calculateBandwidthUsage(history: [APIUsageSnapshot]) -> Double {
        return history.map { Double($0.dataSize) }.reduce(0, +) / (1024 * 1024) // Convert to MB
    }
    
    private func calculateAnomalySeverity(value: Double, expected: Double, threshold: Double) -> AnomalySeverity {
        let deviation = value / expected
        
        if deviation > 5.0 {
            return .critical
        } else if deviation > 3.0 {
            return .high
        } else if deviation > 2.0 {
            return .medium
        } else {
            return .low
        }
    }
    
    private func calculatePredictionAccuracy(slope: Double) -> Double {
        // Simplified accuracy calculation based on trend consistency
        return max(0.5, 1.0 - abs(slope) / 100.0)
    }
    
    private func calculateViolationSeverity(percentage: Double) -> AnomalySeverity {
        if percentage >= 1.0 {
            return .critical
        } else if percentage >= 0.9 {
            return .high
        } else if percentage >= 0.8 {
            return .medium
        } else {
            return .low
        }
    }
    
    private func checkAndNotifyThresholds(tenantId: String, usage: APIUsage) async {
        do {
            let violations = try await checkUsageThresholds(tenantId: tenantId)
            for violation in violations {
                logger.warning("Usage threshold violated for tenant \(tenantId): \(violation.threshold.type.rawValue) at \(violation.percentage * 100)%")
            }
        } catch {
            logger.error("Failed to check usage thresholds for tenant \(tenantId): \(error)")
        }
    }
    
    private func cleanupExpiredBuckets() async {
        let now = Date()
        
        // Cleanup rate limit buckets
        for (tenantId, buckets) in rateLimitBuckets {
            let limits = getRateLimitsForTenant(tenantId)
            
            for (endpoint, bucket) in buckets {
                let window = endpoint == "_global" ? limits.globalWindow : (limits.endpointLimits[endpoint]?.window ?? limits.globalWindow)
                
                if now.timeIntervalSince(bucket.lastRequest) > window * 2 { // Keep for 2x window duration
                    rateLimitBuckets[tenantId]?[endpoint] = nil
                }
            }
        }
        
        // Cleanup quota buckets
        for (tenantId, buckets) in quotaBuckets {
            for (quotaType, bucket) in buckets {
                if now > bucket.resetTime.addingTimeInterval(86400) { // Keep for 1 day after reset
                    quotaBuckets[tenantId]?[quotaType] = nil
                }
            }
        }
        
        logger.debug("Cleaned up expired rate limit and quota buckets")
    }
    
    private func monitorUsageThresholds() async {
        for tenantId in usageData.keys {
            do {
                _ = try await checkUsageThresholds(tenantId: tenantId)
            } catch {
                logger.error("Failed to monitor usage thresholds for tenant \(tenantId): \(error)")
            }
        }
    }
    
    // Data conversion helpers
    private func convertUsageToCSV(_ data: UsageExportData) throws -> Data {
        var csv = "timestamp,endpoint,method,status_code,response_time,data_size\n"
        
        for snapshot in data.history {
            csv += "\(snapshot.timestamp),\(snapshot.endpoint),\(snapshot.method.rawValue),\(snapshot.statusCode),\(snapshot.responseTime),\(snapshot.dataSize)\n"
        }
        
        return csv.data(using: .utf8) ?? Data()
    }
    
    private func convertUsageToExcel(_ data: UsageExportData) throws -> Data {
        // Placeholder for Excel conversion
        throw UsageTrackingError.exportFailed("Excel export not implemented")
    }
    
    private func convertUsageToXML(_ data: UsageExportData) throws -> Data {
        // Placeholder for XML conversion
        throw UsageTrackingError.exportFailed("XML export not implemented")
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: APIUsageTrackingDelegate) {
        delegates.removeAll { $0.delegate == nil }
        delegates.append(WeakUsageDelegate(delegate))
    }
    
    func removeDelegate(_ delegate: APIUsageTrackingDelegate) {
        delegates.removeAll { $0.delegate === delegate }
    }
    
    private func notifyDelegates<T>(_ action: (APIUsageTrackingDelegate) -> T) {
        delegates.forEach { weakDelegate in
            if let delegate = weakDelegate.delegate {
                _ = action(delegate)
            }
        }
        
        // Clean up nil references
        delegates.removeAll { $0.delegate == nil }
    }
    
    deinit {
        cleanupTimer?.invalidate()
        monitoringTimer?.invalidate()
    }
}

// MARK: - Supporting Types

private struct WeakUsageDelegate {
    weak var delegate: APIUsageTrackingDelegate?
    
    init(_ delegate: APIUsageTrackingDelegate) {
        self.delegate = delegate
    }
}

private class RateLimitBucket: ObservableObject {
    var count: Int
    var windowStart: Date
    var lastRequest: Date
    
    init(count: Int, windowStart: Date, lastRequest: Date) {
        self.count = count
        self.windowStart = windowStart
        self.lastRequest = lastRequest
    }
}

private class QuotaBucket: ObservableObject {
    var count: Int
    var limit: Int
    var period: QuotaPeriod
    var resetTime: Date
    
    init(count: Int, limit: Int, period: QuotaPeriod, resetTime: Date) {
        self.count = count
        self.limit = limit
        self.period = period
        self.resetTime = resetTime
    }
}

// MARK: - Mock Implementation

#if DEBUG
class MockAPIUsageTrackingService: APIUsageTrackingServiceProtocol {
    @Published private var mockUsage: [String: APIUsage] = [:]
    @Published private var mockRateLimits: [String: RateLimitStatus] = [:]
    
    var currentUsage: AnyPublisher<[String: APIUsage], Never> {
        $mockUsage.eraseToAnyPublisher()
    }
    
    var rateLimitStatus: AnyPublisher<[String: RateLimitStatus], Never> {
        $mockRateLimits.eraseToAnyPublisher()
    }
    
    func trackAPICall(tenantId: String, endpoint: String, method: HTTPMethod, statusCode: Int, responseTime: TimeInterval, dataSize: Int) async throws {
        var usage = mockUsage[tenantId] ?? APIUsage.empty(tenantId: tenantId)
        usage.apiCalls += 1
        mockUsage[tenantId] = usage
    }
    
    func getCurrentUsage(tenantId: String) async throws -> APIUsage {
        return mockUsage[tenantId] ?? APIUsage.empty(tenantId: tenantId)
    }
    
    func getUsageHistory(tenantId: String, period: RevenuePeriod) async throws -> [APIUsageSnapshot] { return [] }
    func getUsageByEndpoint(tenantId: String, period: RevenuePeriod) async throws -> [EndpointUsage] { return [] }
    func checkRateLimit(tenantId: String, endpoint: String) async throws -> RateLimitResult { return RateLimitResult.mock }
    func getRateLimitStatus(tenantId: String) async throws -> RateLimitStatus { return RateLimitStatus.mock }
    func updateRateLimits(tenantId: String, limits: RateLimits) async throws {}
    func resetRateLimit(tenantId: String, endpoint: String?) async throws {}
    func checkQuota(tenantId: String, quotaType: QuotaType) async throws -> QuotaResult { return QuotaResult.mock }
    func getQuotaStatus(tenantId: String) async throws -> [QuotaStatus] { return [QuotaStatus.mock] }
    func updateQuota(tenantId: String, quotaType: QuotaType, limit: Int, period: QuotaPeriod) async throws {}
    func resetQuota(tenantId: String, quotaType: QuotaType) async throws {}
    func getUsageAnalytics(tenantId: String, period: RevenuePeriod) async throws -> UsageAnalytics { return UsageAnalytics.mock }
    func getUsageTrends(tenantId: String, metric: UsageMetric, period: RevenuePeriod) async throws -> [UsageTrend] { return [] }
    func detectUsageAnomalies(tenantId: String) async throws -> [UsageAnomaly] { return [] }
    func getUsagePrediction(tenantId: String, days: Int) async throws -> UsagePrediction { return UsagePrediction.mock }
    func calculateUsageCosts(tenantId: String, period: RevenuePeriod) async throws -> UsageCosts { return UsageCosts.mock }
    func getOverageCharges(tenantId: String, period: RevenuePeriod) async throws -> [OverageCharge] { return [] }
    func exportUsageData(tenantId: String, period: RevenuePeriod, format: ExportFormat) async throws -> Data { return Data() }
    func configureUsageAlerts(tenantId: String, alerts: [UsageAlert]) async throws {}
    func getUsageAlerts(tenantId: String) async throws -> [UsageAlert] { return [] }
    func checkUsageThresholds(tenantId: String) async throws -> [ThresholdViolation] { return [] }
    func setDelegate(_ delegate: APIUsageTrackingDelegate) {}
    func removeDelegate(_ delegate: APIUsageTrackingDelegate) {}
}
#endif