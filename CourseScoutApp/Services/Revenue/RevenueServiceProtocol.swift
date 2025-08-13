import Foundation
import Combine
import Appwrite

// MARK: - Revenue Service Protocol

protocol RevenueServiceProtocol: AnyObject {
    // Revenue Analytics
    var totalRevenue: AnyPublisher<Decimal, Never> { get }
    var monthlyRecurringRevenue: AnyPublisher<Decimal, Never> { get }
    var annualRecurringRevenue: AnyPublisher<Decimal, Never> { get }
    var churnRate: AnyPublisher<Double, Never> { get }
    
    // Revenue Operations
    func getRevenueMetrics(for period: RevenuePeriod) async throws -> RevenueMetrics
    func getRevenueByTenant(tenantId: String, period: RevenuePeriod) async throws -> TenantRevenue
    func getRevenueForecast(months: Int) async throws -> [RevenueForecast]
    func getRevenueBreakdown() async throws -> RevenueBreakdown
    
    // Revenue Events
    func recordRevenueEvent(_ event: RevenueEvent) async throws
    func getRevenueEvents(for tenantId: String?, dateRange: DateRange) async throws -> [RevenueEvent]
    
    // Revenue Reporting
    func generateRevenueReport(for period: RevenuePeriod, format: ReportFormat) async throws -> RevenueReport
    func exportRevenueData(dateRange: DateRange, format: ExportFormat) async throws -> Data
    
    // Revenue Intelligence
    func analyzeRevenueGrowth() async throws -> RevenueGrowthAnalysis
    func detectRevenueAnomalies() async throws -> [RevenueAnomaly]
    func getRevenueInsights() async throws -> [RevenueInsight]
}

// MARK: - Supporting Types

struct RevenueMetrics: Codable {
    let totalRevenue: Decimal
    let recurringRevenue: Decimal
    let oneTimeRevenue: Decimal
    let refunds: Decimal
    let netRevenue: Decimal
    let customerCount: Int
    let averageRevenuePerUser: Decimal
    let lifetimeValue: Decimal
    let churnRate: Double
    let growthRate: Double
    let period: RevenuePeriod
    let generatedAt: Date
}

struct TenantRevenue: Codable {
    let tenantId: String
    let tenantName: String
    let totalRevenue: Decimal
    let subscriptionRevenue: Decimal
    let usageRevenue: Decimal
    let customerCount: Int
    let averageRevenuePerUser: Decimal
    let subscriptionTier: SubscriptionTier?
    let billingCycle: BillingCycle
    let period: RevenuePeriod
}

struct RevenueForecast: Codable {
    let month: Date
    let predictedRevenue: Decimal
    let confidenceInterval: ConfidenceInterval
    let factors: [ForecastFactor]
    let scenario: ForecastScenario
}

struct RevenueBreakdown: Codable {
    let subscriptionRevenue: Decimal
    let usageBasedRevenue: Decimal
    let oneTimeCharges: Decimal
    let setupFees: Decimal
    let addOnRevenue: Decimal
    let refundsAndCredits: Decimal
    let revenueByTier: [String: Decimal]
    let revenueByRegion: [String: Decimal]
    let revenueByChannel: [String: Decimal]
}

struct RevenueEvent: Codable, Identifiable {
    let id: UUID
    let tenantId: String
    let eventType: RevenueEventType
    let amount: Decimal
    let currency: String
    let timestamp: Date
    let subscriptionId: String?
    let customerId: String?
    let invoiceId: String?
    let metadata: [String: String]
    let source: RevenueSource
}

struct RevenueReport: Codable {
    let id: UUID
    let title: String
    let period: RevenuePeriod
    let generatedAt: Date
    let metrics: RevenueMetrics
    let breakdown: RevenueBreakdown
    let trends: [RevenueTrend]
    let insights: [RevenueInsight]
    let format: ReportFormat
    let data: Data?
}

struct RevenueGrowthAnalysis: Codable {
    let currentGrowthRate: Double
    let quarterOverQuarterGrowth: Double
    let yearOverYearGrowth: Double
    let growthTrend: GrowthTrend
    let growthDrivers: [GrowthDriver]
    let projectedGrowth: Double
    let benchmarkComparison: BenchmarkComparison?
}

struct RevenueAnomaly: Codable, Identifiable {
    let id: UUID
    let detectedAt: Date
    let anomalyType: AnomalyType
    let severity: AnomalySeverity
    let description: String
    let affectedRevenue: Decimal
    let possibleCauses: [String]
    let recommendedActions: [String]
    let tenantId: String?
}

struct RevenueInsight: Codable, Identifiable {
    let id: UUID
    let title: String
    let description: String
    let insightType: InsightType
    let impact: ImpactLevel
    let recommendation: String
    let potentialValue: Decimal?
    let confidence: Double
    let createdAt: Date
    let expiresAt: Date?
}

// MARK: - Enumerations

enum RevenuePeriod: String, CaseIterable, Codable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case quarterly = "quarterly"
    case yearly = "yearly"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        case .custom: return "Custom"
        }
    }
}

enum RevenueEventType: String, CaseIterable, Codable {
    case subscriptionCreated = "subscription_created"
    case subscriptionRenewed = "subscription_renewed"
    case subscriptionUpgraded = "subscription_upgraded"
    case subscriptionDowngraded = "subscription_downgraded"
    case subscriptionCancelled = "subscription_cancelled"
    case usageCharge = "usage_charge"
    case oneTimePayment = "one_time_payment"
    case refund = "refund"
    case chargeback = "chargeback"
    case credit = "credit"
    case setupFee = "setup_fee"
    case addOnPurchase = "addon_purchase"
}

enum RevenueSource: String, CaseIterable, Codable {
    case stripe = "stripe"
    case applePay = "apple_pay"
    case googlePay = "google_pay"
    case bankTransfer = "bank_transfer"
    case invoice = "invoice"
    case manual = "manual"
    case migration = "migration"
}

enum ReportFormat: String, CaseIterable, Codable {
    case pdf = "pdf"
    case excel = "excel"
    case csv = "csv"
    case json = "json"
    case html = "html"
}

enum ExportFormat: String, CaseIterable, Codable {
    case csv = "csv"
    case json = "json"
    case excel = "excel"
    case xml = "xml"
}

enum ForecastScenario: String, CaseIterable, Codable {
    case conservative = "conservative"
    case realistic = "realistic"
    case optimistic = "optimistic"
}

enum GrowthTrend: String, CaseIterable, Codable {
    case accelerating = "accelerating"
    case steady = "steady"
    case declining = "declining"
    case volatile = "volatile"
}

enum AnomalyType: String, CaseIterable, Codable {
    case suddenDrop = "sudden_drop"
    case suddenSpike = "sudden_spike"
    case unusualPattern = "unusual_pattern"
    case missingData = "missing_data"
    case dataInconsistency = "data_inconsistency"
}

enum AnomalySeverity: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum InsightType: String, CaseIterable, Codable {
    case optimization = "optimization"
    case warning = "warning"
    case opportunity = "opportunity"
    case trend = "trend"
    case prediction = "prediction"
}

enum ImpactLevel: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

// MARK: - Additional Supporting Types

struct ConfidenceInterval: Codable {
    let lowerBound: Decimal
    let upperBound: Decimal
    let confidence: Double
}

struct ForecastFactor: Codable {
    let name: String
    let impact: Double
    let confidence: Double
    let description: String
}

struct RevenueTrend: Codable {
    let metric: String
    let direction: TrendDirection
    let magnitude: Double
    let period: RevenuePeriod
    let significance: Double
}

struct GrowthDriver: Codable {
    let name: String
    let contribution: Double
    let trend: GrowthTrend
    let description: String
}

struct BenchmarkComparison: Codable {
    let industryAverage: Double
    let percentile: Int
    let comparison: ComparisonResult
    let benchmark: String
}

enum TrendDirection: String, CaseIterable, Codable {
    case increasing = "increasing"
    case decreasing = "decreasing"
    case stable = "stable"
}

enum ComparisonResult: String, CaseIterable, Codable {
    case aboveAverage = "above_average"
    case belowAverage = "below_average"
    case average = "average"
}

struct DateRange: Codable {
    let startDate: Date
    let endDate: Date
    
    var isValid: Bool {
        return startDate <= endDate
    }
    
    var duration: TimeInterval {
        return endDate.timeIntervalSince(startDate)
    }
}

// MARK: - Revenue Service Errors

enum RevenueServiceError: Error, LocalizedError {
    case invalidPeriod
    case invalidDateRange
    case tenantNotFound(String)
    case insufficientData
    case calculationError(String)
    case exportFailed(String)
    case anomalyDetectionFailed(String)
    case forecastFailed(String)
    case networkError(Error)
    case authorizationError
    
    var errorDescription: String? {
        switch self {
        case .invalidPeriod:
            return "Invalid revenue period specified"
        case .invalidDateRange:
            return "Invalid date range provided"
        case .tenantNotFound(let tenantId):
            return "Tenant with ID \(tenantId) not found"
        case .insufficientData:
            return "Insufficient data for revenue calculation"
        case .calculationError(let message):
            return "Revenue calculation failed: \(message)"
        case .exportFailed(let message):
            return "Revenue data export failed: \(message)"
        case .anomalyDetectionFailed(let message):
            return "Anomaly detection failed: \(message)"
        case .forecastFailed(let message):
            return "Revenue forecast failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authorizationError:
            return "Unauthorized access to revenue data"
        }
    }
}

// MARK: - Revenue Service Configuration

struct RevenueServiceConfiguration {
    let anomalyDetectionEnabled: Bool
    let forecastingEnabled: Bool
    let realtimeUpdatesEnabled: Bool
    let cachingEnabled: Bool
    let encryptionEnabled: Bool
    let auditLoggingEnabled: Bool
    let benchmarkingEnabled: Bool
    let insightGenerationEnabled: Bool
    
    static let `default` = RevenueServiceConfiguration(
        anomalyDetectionEnabled: true,
        forecastingEnabled: true,
        realtimeUpdatesEnabled: true,
        cachingEnabled: true,
        encryptionEnabled: true,
        auditLoggingEnabled: true,
        benchmarkingEnabled: false,
        insightGenerationEnabled: true
    )
}