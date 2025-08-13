import Foundation
import Appwrite

// MARK: - Usage Tracking Middleware

class UsageTrackingMiddleware: APIMiddleware {
    let priority: Int = 200 // Lower priority - runs after authentication and rate limiting
    
    // MARK: - Properties
    
    private let appwriteClient: Client?
    private let usageQueue = DispatchQueue(label: "UsageTrackingQueue", qos: .utility)
    private let billingQueue = DispatchQueue(label: "BillingQueue", qos: .utility)
    
    // MARK: - In-Memory Storage
    
    private var realtimeUsage: [String: RealtimeUsageData] = [:]
    private var billingBuffer: [UsageRecord] = []
    
    // MARK: - Configuration
    
    private let bufferFlushInterval: TimeInterval = 300 // 5 minutes
    private let maxBufferSize = 1000
    
    // MARK: - Cost Configuration per Endpoint
    
    private let endpointCosts: [String: EndpointCost] = [
        "/courses": EndpointCost(baseUnits: 1, premiumMultiplier: 1.0),
        "/courses/search": EndpointCost(baseUnits: 2, premiumMultiplier: 1.2),
        "/courses/analytics": EndpointCost(baseUnits: 10, premiumMultiplier: 2.0),
        "/predictions": EndpointCost(baseUnits: 50, premiumMultiplier: 5.0),
        "/booking/realtime": EndpointCost(baseUnits: 25, premiumMultiplier: 3.0),
        "/user/profile": EndpointCost(baseUnits: 1, premiumMultiplier: 0.5),
        "/health": EndpointCost(baseUnits: 0, premiumMultiplier: 0.1)
    ]
    
    // MARK: - Initialization
    
    init(appwriteClient: Client? = nil) {
        self.appwriteClient = appwriteClient
        setupPeriodicTasks()
    }
    
    // MARK: - APIMiddleware Implementation
    
    func process(_ request: APIGatewayRequest) async throws -> APIGatewayRequest {
        // Track the incoming request
        await trackIncomingRequest(request)
        
        return request
    }
    
    // MARK: - Usage Tracking
    
    func trackUsage(request: APIGatewayRequest, response: APIGatewayResponse<Any>) async {
        let usageRecord = createUsageRecord(request: request, response: response)
        
        await usageQueue.async {
            // Update real-time usage
            self.updateRealtimeUsage(usageRecord)
            
            // Add to billing buffer
            self.billingBuffer.append(usageRecord)
            
            // Flush buffer if it's getting too large
            if self.billingBuffer.count >= self.maxBufferSize {
                Task {
                    await self.flushBillingBuffer()
                }
            }
        }
        
        // Track usage metrics for analytics
        await trackUsageMetrics(usageRecord)
    }
    
    private func trackIncomingRequest(_ request: APIGatewayRequest) async {
        await usageQueue.async {
            let apiKey = request.apiKey
            
            if var realtimeData = self.realtimeUsage[apiKey] {
                realtimeData.incomingRequests += 1
                realtimeData.lastRequestTime = Date()
                self.realtimeUsage[apiKey] = realtimeData
            } else {
                self.realtimeUsage[apiKey] = RealtimeUsageData(
                    apiKey: apiKey,
                    incomingRequests: 1,
                    processedRequests: 0,
                    totalUnitsConsumed: 0,
                    lastRequestTime: Date(),
                    windowStart: Date()
                )
            }
        }
    }
    
    private func createUsageRecord(request: APIGatewayRequest, response: APIGatewayResponse<Any>) -> UsageRecord {
        let cost = calculateRequestCost(request: request, response: response)
        
        return UsageRecord(
            recordId: UUID().uuidString,
            apiKey: request.apiKey,
            userId: nil, // Would be populated from authentication middleware
            endpoint: request.path,
            method: request.method.rawValue,
            version: request.version.rawValue,
            statusCode: response.statusCode,
            processingTimeMs: response.processingTimeMs,
            unitsConsumed: cost.units,
            costCents: cost.cents,
            timestamp: request.timestamp,
            metadata: createUsageMetadata(request: request, response: response)
        )
    }
    
    private func calculateRequestCost(request: APIGatewayRequest, response: APIGatewayResponse<Any>) -> RequestCost {
        guard let endpointCost = endpointCosts[request.path] else {
            return RequestCost(units: 1, cents: 0.01) // Default cost
        }
        
        var units = endpointCost.baseUnits
        
        // Apply premium multiplier based on processing time
        if response.processingTimeMs > 1000 { // Slow requests cost more
            units = Int(Double(units) * endpointCost.premiumMultiplier)
        }
        
        // Apply error penalty
        if response.statusCode >= 500 {
            units = max(1, units / 2) // Reduce cost for server errors
        }
        
        // Calculate cost in cents (simplified pricing)
        let cents = Double(units) * 0.01 // 1 cent per 100 units
        
        return RequestCost(units: units, cents: cents)
    }
    
    private func createUsageMetadata(request: APIGatewayRequest, response: APIGatewayResponse<Any>) -> UsageMetadata {
        return UsageMetadata(
            userAgent: request.headers["User-Agent"],
            ipAddress: request.headers["X-Forwarded-For"],
            requestSize: request.body?.count,
            responseSize: nil, // Would calculate from response
            cacheHit: response.headers["X-Cache"] == "HIT",
            region: request.headers["X-Region"] ?? "unknown"
        )
    }
    
    private func updateRealtimeUsage(_ record: UsageRecord) {
        let apiKey = record.apiKey
        
        if var realtimeData = realtimeUsage[apiKey] {
            realtimeData.processedRequests += 1
            realtimeData.totalUnitsConsumed += record.unitsConsumed
            realtimeData.lastRequestTime = record.timestamp
            realtimeUsage[apiKey] = realtimeData
        } else {
            realtimeUsage[apiKey] = RealtimeUsageData(
                apiKey: apiKey,
                incomingRequests: 0,
                processedRequests: 1,
                totalUnitsConsumed: record.unitsConsumed,
                lastRequestTime: record.timestamp,
                windowStart: Date()
            )
        }
    }
    
    // MARK: - Billing Integration
    
    private func flushBillingBuffer() async {
        let recordsToFlush = await usageQueue.async {
            let records = self.billingBuffer
            self.billingBuffer.removeAll()
            return records
        }
        
        guard !recordsToFlush.isEmpty else { return }
        
        await billingQueue.async {
            Task {
                if let appwriteClient = self.appwriteClient {
                    await self.persistUsageRecords(recordsToFlush, client: appwriteClient)
                } else {
                    // Mock persistence for testing
                    await self.mockPersistUsageRecords(recordsToFlush)
                }
            }
        }
    }
    
    private func persistUsageRecords(_ records: [UsageRecord], client: Client) async {
        let databases = Databases(client)
        
        for record in records {
            do {
                try await databases.createDocument(
                    databaseId: Configuration.appwriteProjectId,
                    collectionId: "usage_records",
                    documentId: ID.unique(),
                    data: record.toDictionary()
                )
            } catch {
                if Configuration.environment.enableDetailedLogging {
                    print("Failed to persist usage record: \(error)")
                }
                // In production, you'd want to retry or queue for later
            }
        }
        
        print("Persisted \(records.count) usage records to database")
    }
    
    private func mockPersistUsageRecords(_ records: [UsageRecord]) async {
        if Configuration.environment.enableDetailedLogging {
            print("Mock: Persisted \(records.count) usage records")
        }
    }
    
    // MARK: - Analytics and Reporting
    
    func getRealtimeUsage(for apiKey: String) async -> RealtimeUsageData? {
        return await usageQueue.async {
            return self.realtimeUsage[apiKey]
        }
    }
    
    func getAllRealtimeUsage() async -> [String: RealtimeUsageData] {
        return await usageQueue.async {
            return self.realtimeUsage
        }
    }
    
    func getUsageReport(for apiKey: String, period: ReportingPeriod) async throws -> UsageReport {
        guard let client = appwriteClient else {
            return mockUsageReport(for: apiKey, period: period)
        }
        
        let databases = Databases(client)
        let queries = buildUsageQueries(apiKey: apiKey, period: period)
        
        do {
            let documents = try await databases.listDocuments(
                databaseId: Configuration.appwriteProjectId,
                collectionId: "usage_records",
                queries: queries
            )
            
            return processUsageDocuments(documents.documents, period: period)
        } catch {
            throw APIGatewayError.internalServerError("Failed to generate usage report: \(error)")
        }
    }
    
    func getBillingData(for apiKey: String, period: ReportingPeriod) async throws -> BillingData {
        let usageReport = try await getUsageReport(for: apiKey, period: period)
        
        return BillingData(
            apiKey: apiKey,
            period: period,
            totalRequests: usageReport.totalRequests,
            totalUnitsConsumed: usageReport.totalUnitsConsumed,
            totalCostCents: usageReport.totalCostCents,
            breakdown: usageReport.endpointBreakdown.mapValues { endpoint in
                BillingEndpointData(
                    requests: endpoint.requests,
                    unitsConsumed: endpoint.unitsConsumed,
                    costCents: endpoint.costCents
                )
            },
            generatedAt: Date()
        )
    }
    
    private func trackUsageMetrics(_ record: UsageRecord) async {
        // Send metrics to analytics service
        // This could integrate with services like DataDog, New Relic, etc.
        if Configuration.environment.enablePerformanceMonitoring {
            // Track key metrics
            let metrics = [
                "api.requests.total": 1,
                "api.units.consumed": record.unitsConsumed,
                "api.cost.cents": record.costCents,
                "api.processing_time.ms": record.processingTimeMs
            ]
            
            // In a real implementation, you'd send these to your metrics service
            if Configuration.environment.enableDetailedLogging {
                print("Usage Metrics: \(metrics)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupPeriodicTasks() {
        // Periodic buffer flush
        Timer.scheduledTimer(withTimeInterval: bufferFlushInterval, repeats: true) { _ in
            Task {
                await self.flushBillingBuffer()
            }
        }
        
        // Periodic cleanup of old real-time data
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task {
                await self.cleanupOldRealtimeData()
            }
        }
    }
    
    private func cleanupOldRealtimeData() async {
        let cutoffTime = Date().addingTimeInterval(-3600) // 1 hour ago
        
        await usageQueue.async {
            self.realtimeUsage = self.realtimeUsage.filter { _, data in
                data.lastRequestTime > cutoffTime
            }
        }
    }
    
    private func buildUsageQueries(apiKey: String, period: ReportingPeriod) -> [String] {
        let now = Date()
        let startTime: Date
        
        switch period {
        case .hour:
            startTime = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now
        case .day:
            startTime = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        case .week:
            startTime = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .month:
            startTime = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        }
        
        return [
            Query.equal("api_key", value: apiKey),
            Query.greaterThanEqual("timestamp", value: startTime.timeIntervalSince1970),
            Query.lessThanEqual("timestamp", value: now.timeIntervalSince1970)
        ]
    }
    
    private func processUsageDocuments(_ documents: [Document], period: ReportingPeriod) -> UsageReport {
        var totalRequests = 0
        var totalUnitsConsumed = 0
        var totalCostCents = 0.0
        var endpointBreakdown: [String: UsageEndpointData] = [:]
        
        for document in documents {
            let data = document.data
            let endpoint = data["endpoint"] as? String ?? "unknown"
            let unitsConsumed = data["units_consumed"] as? Int ?? 0
            let costCents = data["cost_cents"] as? Double ?? 0.0
            
            totalRequests += 1
            totalUnitsConsumed += unitsConsumed
            totalCostCents += costCents
            
            if var endpointData = endpointBreakdown[endpoint] {
                endpointData.requests += 1
                endpointData.unitsConsumed += unitsConsumed
                endpointData.costCents += costCents
                endpointBreakdown[endpoint] = endpointData
            } else {
                endpointBreakdown[endpoint] = UsageEndpointData(
                    requests: 1,
                    unitsConsumed: unitsConsumed,
                    costCents: costCents
                )
            }
        }
        
        return UsageReport(
            period: period,
            totalRequests: totalRequests,
            totalUnitsConsumed: totalUnitsConsumed,
            totalCostCents: totalCostCents,
            endpointBreakdown: endpointBreakdown,
            generatedAt: Date()
        )
    }
    
    private func mockUsageReport(for apiKey: String, period: ReportingPeriod) -> UsageReport {
        let mockData = [
            "/courses": UsageEndpointData(requests: 150, unitsConsumed: 150, costCents: 1.50),
            "/courses/analytics": UsageEndpointData(requests: 25, unitsConsumed: 250, costCents: 2.50),
            "/predictions": UsageEndpointData(requests: 5, unitsConsumed: 250, costCents: 2.50)
        ]
        
        let totalRequests = mockData.values.reduce(0) { $0 + $1.requests }
        let totalUnits = mockData.values.reduce(0) { $0 + $1.unitsConsumed }
        let totalCost = mockData.values.reduce(0.0) { $0 + $1.costCents }
        
        return UsageReport(
            period: period,
            totalRequests: totalRequests,
            totalUnitsConsumed: totalUnits,
            totalCostCents: totalCost,
            endpointBreakdown: mockData,
            generatedAt: Date()
        )
    }
}

// MARK: - Data Models

struct UsageRecord {
    let recordId: String
    let apiKey: String
    let userId: String?
    let endpoint: String
    let method: String
    let version: String
    let statusCode: Int
    let processingTimeMs: Double
    let unitsConsumed: Int
    let costCents: Double
    let timestamp: Date
    let metadata: UsageMetadata
    
    func toDictionary() -> [String: Any] {
        return [
            "record_id": recordId,
            "api_key": apiKey,
            "user_id": userId as Any,
            "endpoint": endpoint,
            "method": method,
            "version": version,
            "status_code": statusCode,
            "processing_time_ms": processingTimeMs,
            "units_consumed": unitsConsumed,
            "cost_cents": costCents,
            "timestamp": timestamp.timeIntervalSince1970,
            "metadata": [
                "user_agent": metadata.userAgent as Any,
                "ip_address": metadata.ipAddress as Any,
                "request_size": metadata.requestSize as Any,
                "response_size": metadata.responseSize as Any,
                "cache_hit": metadata.cacheHit,
                "region": metadata.region
            ]
        ]
    }
}

struct UsageMetadata {
    let userAgent: String?
    let ipAddress: String?
    let requestSize: Int?
    let responseSize: Int?
    let cacheHit: Bool
    let region: String
}

struct RealtimeUsageData {
    let apiKey: String
    var incomingRequests: Int
    var processedRequests: Int
    var totalUnitsConsumed: Int
    var lastRequestTime: Date
    let windowStart: Date
    
    var requestsPerSecond: Double {
        let elapsedTime = Date().timeIntervalSince(windowStart)
        return elapsedTime > 0 ? Double(processedRequests) / elapsedTime : 0
    }
}

struct EndpointCost {
    let baseUnits: Int
    let premiumMultiplier: Double
}

struct RequestCost {
    let units: Int
    let cents: Double
}

enum ReportingPeriod {
    case hour
    case day
    case week
    case month
}

struct UsageReport {
    let period: ReportingPeriod
    let totalRequests: Int
    let totalUnitsConsumed: Int
    let totalCostCents: Double
    let endpointBreakdown: [String: UsageEndpointData]
    let generatedAt: Date
}

struct UsageEndpointData {
    let requests: Int
    let unitsConsumed: Int
    let costCents: Double
    
    var averageUnitsPerRequest: Double {
        return requests > 0 ? Double(unitsConsumed) / Double(requests) : 0
    }
}

struct BillingData {
    let apiKey: String
    let period: ReportingPeriod
    let totalRequests: Int
    let totalUnitsConsumed: Int
    let totalCostCents: Double
    let breakdown: [String: BillingEndpointData]
    let generatedAt: Date
    
    var totalCostDollars: Double {
        return totalCostCents / 100.0
    }
}

struct BillingEndpointData {
    let requests: Int
    let unitsConsumed: Int
    let costCents: Double
}

// MARK: - Mock Usage Tracking Middleware

class MockUsageTrackingMiddleware: UsageTrackingMiddleware {
    private var mockRealtimeData: [String: RealtimeUsageData] = [:]
    private var mockBillingEnabled = true
    
    override init() {
        super.init()
        setupMockData()
    }
    
    private func setupMockData() {
        mockRealtimeData = [
            "test_api_key": RealtimeUsageData(
                apiKey: "test_api_key",
                incomingRequests: 150,
                processedRequests: 145,
                totalUnitsConsumed: 1200,
                lastRequestTime: Date(),
                windowStart: Date().addingTimeInterval(-3600)
            )
        ]
    }
    
    func setMockBillingEnabled(_ enabled: Bool) {
        mockBillingEnabled = enabled
    }
    
    override func getRealtimeUsage(for apiKey: String) async -> RealtimeUsageData? {
        return mockRealtimeData[apiKey]
    }
    
    override func getAllRealtimeUsage() async -> [String: RealtimeUsageData] {
        return mockRealtimeData
    }
}