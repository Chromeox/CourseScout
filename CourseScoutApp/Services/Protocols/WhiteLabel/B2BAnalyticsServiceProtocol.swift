import Foundation
import Combine

// MARK: - B2B Analytics Service Protocol

protocol B2BAnalyticsServiceProtocol: AnyObject {
    
    // MARK: - Published Properties
    var currentSummary: B2BAnalyticsSummary? { get }
    var revenueMetrics: RevenueMetrics? { get }
    var playerBehaviorMetrics: PlayerBehaviorMetrics? { get }
    var predictiveAnalytics: PredictiveAnalytics? { get }
    var isLoading: Bool { get }
    var lastUpdated: Date? { get }
    
    // MARK: - Reactive Publishers
    var summaryPublisher: AnyPublisher<B2BAnalyticsSummary?, Never> { get }
    var revenuePublisher: AnyPublisher<RevenueMetrics?, Never> { get }
    var behaviorPublisher: AnyPublisher<PlayerBehaviorMetrics?, Never> { get }
    var predictivePublisher: AnyPublisher<PredictiveAnalytics?, Never> { get }
    var alertsPublisher: AnyPublisher<[AnalyticsAlert], Never> { get }
    
    // MARK: - Data Loading and Refresh
    func loadAnalyticsSummary(for tenantId: String, period: AnalyticsPeriod) async throws -> B2BAnalyticsSummary
    func loadRevenueMetrics(for tenantId: String, period: AnalyticsPeriod) async throws -> RevenueMetrics
    func loadPlayerBehaviorMetrics(for tenantId: String, period: AnalyticsPeriod) async throws -> PlayerBehaviorMetrics
    func loadPredictiveAnalytics(for tenantId: String, period: AnalyticsPeriod) async throws -> PredictiveAnalytics
    
    func refreshAllMetrics(for tenantId: String, period: AnalyticsPeriod) async throws
    func refreshMetricsInBackground(for tenantId: String) async
    
    // MARK: - Custom Analytics Queries
    func getRevenueBreakdown(for tenantId: String, startDate: Date, endDate: Date) async throws -> [RevenueCategory]
    func getBookingTrends(for tenantId: String, period: AnalyticsPeriod) async throws -> [DailyRevenue]
    func getUserSegmentAnalysis(for tenantId: String) async throws -> [UserSegment]
    func getFeatureAdoptionMetrics(for tenantId: String) async throws -> [FeatureUsageMetric]
    
    // MARK: - Real-time Analytics
    func startRealTimeUpdates(for tenantId: String)
    func stopRealTimeUpdates()
    func getRealTimeStats(for tenantId: String) async throws -> RealTimeStats
    
    // MARK: - Comparative Analytics
    func compareMetrics(tenantId: String, period1: AnalyticsPeriod, period2: AnalyticsPeriod) async throws -> AnalyticsComparison
    func getBenchmarkData(for tenantId: String, category: BenchmarkCategory) async throws -> BenchmarkData
    func getIndustryComparison(for tenantId: String) async throws -> IndustryBenchmark
    
    // MARK: - Export and Reporting
    func exportAnalytics(for tenantId: String, format: ExportFormat, period: AnalyticsPeriod) async throws -> AnalyticsExport
    func generateReport(for tenantId: String, type: ReportType, period: AnalyticsPeriod) async throws -> AnalyticsReport
    func scheduleAutomaticReports(for tenantId: String, schedule: ReportSchedule) async throws
    
    // MARK: - Alerts and Notifications
    func getActiveAlerts(for tenantId: String) async throws -> [AnalyticsAlert]
    func acknowledgeAlert(alertId: String) async throws
    func configureAlertThresholds(for tenantId: String, thresholds: AlertThresholds) async throws
    
    // MARK: - Predictive Modeling
    func generateRevenueForecast(for tenantId: String, timeframe: ForecastTimeframe) async throws -> [RevenueForecast]
    func identifyChurnRisk(for tenantId: String) async throws -> [ChurnPrediction]
    func optimizePricing(for tenantId: String, date: Date) async throws -> [PricingRecommendation]
    func predictDemand(for tenantId: String, date: Date) async throws -> [DemandPrediction]
    
    // MARK: - Configuration and Settings
    func updateAnalyticsSettings(for tenantId: String, settings: AnalyticsSettings) async throws
    func getAnalyticsSettings(for tenantId: String) async throws -> AnalyticsSettings
    func validateDataAccess(for tenantId: String) async throws -> Bool
    
    // MARK: - Data Quality and Validation
    func validateDataIntegrity(for tenantId: String) async throws -> DataIntegrityReport
    func getDataSourceStatus(for tenantId: String) async throws -> [DataSourceStatus]
    func repairDataInconsistencies(for tenantId: String) async throws
}

// MARK: - Supporting Data Structures

struct UserSegment: Codable, Identifiable {
    let id: String
    let name: String
    let userCount: Int
    let averageRevenue: Double
    let retentionRate: Double
    let characteristics: [String: String]
    let growthTrend: Double
}

struct RealTimeStats: Codable {
    let activeUsers: Int
    let currentBookings: Int
    let todayRevenue: Double
    let averageSessionDuration: TimeInterval
    let conversionRate: Double
    let lastUpdated: Date
}

struct AnalyticsComparison: Codable, Identifiable {
    let id: String
    let tenantId: String
    let period1: AnalyticsPeriod
    let period2: AnalyticsPeriod
    let revenueComparison: MetricComparison
    let userComparison: MetricComparison
    let bookingComparison: MetricComparison
    let insights: [ComparisonInsight]
}

struct MetricComparison: Codable {
    let value1: Double
    let value2: Double
    let change: Double
    let changePercentage: Double
    let trend: TrendDirection
    
    enum TrendDirection: String, CaseIterable, Codable {
        case up = "up"
        case down = "down"
        case stable = "stable"
        
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .stable: return .blue
            }
        }
    }
}

struct ComparisonInsight: Codable, Identifiable {
    let id: String
    let metric: String
    let insight: String
    let impact: ImpactLevel
    let recommendation: String
    
    enum ImpactLevel: String, CaseIterable, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }
}

struct BenchmarkData: Codable, Identifiable {
    let id: String
    let category: BenchmarkCategory
    let tenantValue: Double
    let industryAverage: Double
    let industryTop25: Double
    let industryTop10: Double
    let percentile: Double
    let insights: [BenchmarkInsight]
}

enum BenchmarkCategory: String, CaseIterable, Codable {
    case revenue = "revenue"
    case conversion = "conversion"
    case retention = "retention"
    case satisfaction = "satisfaction"
    case efficiency = "efficiency"
}

struct BenchmarkInsight: Codable, Identifiable {
    let id: String
    let metric: String
    let performance: PerformanceLevel
    let gapToIndustryLeader: Double
    let improvementOpportunity: String
    
    enum PerformanceLevel: String, CaseIterable, Codable {
        case leadingEdge = "leading_edge"
        case aboveAverage = "above_average"
        case average = "average"
        case belowAverage = "below_average"
        case needsImprovement = "needs_improvement"
        
        var color: Color {
            switch self {
            case .leadingEdge: return .green
            case .aboveAverage: return .blue
            case .average: return .yellow
            case .belowAverage: return .orange
            case .needsImprovement: return .red
            }
        }
    }
}

struct IndustryBenchmark: Codable, Identifiable {
    let id: String
    let industry: String
    let tenantPerformance: TenantPerformance
    let competitorAnalysis: [CompetitorMetric]
    let marketPosition: MarketPosition
    let growthOpportunities: [String]
}

struct TenantPerformance: Codable {
    let overallRanking: Int
    let totalCompetitors: Int
    let percentile: Double
    let strongAreas: [String]
    let improvementAreas: [String]
}

struct CompetitorMetric: Codable, Identifiable {
    let id: String
    let competitorType: String // "Direct", "Indirect", "Industry Leader"
    let averageRevenue: Double
    let averageRating: Double
    let marketShare: Double
}

struct MarketPosition: Codable {
    let position: String // "Leader", "Challenger", "Follower", "Niche"
    let marketShare: Double
    let growthRate: Double
    let competitiveAdvantages: [String]
    let threats: [String]
}

// MARK: - Export and Reporting

enum ExportFormat: String, CaseIterable, Codable {
    case pdf = "pdf"
    case excel = "xlsx"
    case csv = "csv"
    case json = "json"
    case powerbi = "powerbi"
    
    var displayName: String {
        switch self {
        case .pdf: return "PDF Report"
        case .excel: return "Excel Spreadsheet"
        case .csv: return "CSV Data"
        case .json: return "JSON Data"
        case .powerbi: return "Power BI Dataset"
        }
    }
}

enum ReportType: String, CaseIterable, Codable {
    case executive = "executive"
    case detailed = "detailed"
    case financial = "financial"
    case operational = "operational"
    case marketing = "marketing"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .executive: return "Executive Summary"
        case .detailed: return "Detailed Analytics"
        case .financial: return "Financial Performance"
        case .operational: return "Operational Metrics"
        case .marketing: return "Marketing Analytics"
        case .custom: return "Custom Report"
        }
    }
}

struct ReportSchedule: Codable {
    let frequency: ReportFrequency
    let recipients: [String]
    let format: ExportFormat
    let type: ReportType
    let deliveryTime: String // "09:00"
    let timezone: String
    
    enum ReportFrequency: String, CaseIterable, Codable {
        case daily = "daily"
        case weekly = "weekly"
        case monthly = "monthly"
        case quarterly = "quarterly"
    }
}

struct AnalyticsExport: Codable {
    let id: String
    let format: ExportFormat
    let dataURL: String
    let size: Int // File size in bytes
    let generatedAt: Date
    let expiresAt: Date
}

struct AnalyticsReport: Codable, Identifiable {
    let id: String
    let type: ReportType
    let title: String
    let summary: String
    let keyInsights: [String]
    let sections: [ReportSection]
    let recommendations: [ActionableInsight]
    let generatedAt: Date
    let period: AnalyticsPeriod
}

struct ReportSection: Codable, Identifiable {
    let id: String
    let title: String
    let content: String
    let charts: [ChartDefinition]
    let tables: [TableDefinition]
}

struct ChartDefinition: Codable, Identifiable {
    let id: String
    let type: ChartType
    let title: String
    let dataPoints: [ChartDataPoint]
    let configuration: ChartConfiguration
    
    enum ChartType: String, CaseIterable, Codable {
        case line = "line"
        case bar = "bar"
        case pie = "pie"
        case area = "area"
        case scatter = "scatter"
        case heatmap = "heatmap"
    }
}

struct ChartDataPoint: Codable, Identifiable {
    let id: String
    let x: Double
    let y: Double
    let label: String?
    let color: String?
}

struct ChartConfiguration: Codable {
    let showLegend: Bool
    let showAxisLabels: Bool
    let colorScheme: String
    let animation: Bool
}

struct TableDefinition: Codable, Identifiable {
    let id: String
    let title: String
    let headers: [String]
    let rows: [[String]]
    let sortable: Bool
    let searchable: Bool
}

// MARK: - Alert Configuration

struct AlertThresholds: Codable {
    let revenueDropThreshold: Double // Percentage drop
    let conversionDropThreshold: Double
    let churnRateThreshold: Double
    let userGrowthThreshold: Double
    let errorRateThreshold: Double
    let responseTimeThreshold: Double
    let customThresholds: [String: Double]
}

struct AnalyticsSettings: Codable {
    let tenantId: String
    let dataRetentionDays: Int
    let realTimeUpdatesEnabled: Bool
    let alertsEnabled: Bool
    let alertThresholds: AlertThresholds
    let reportSchedules: [ReportSchedule]
    let customDashboards: [DashboardConfiguration]
    let dataSourceConnections: [DataSourceConnection]
}

struct DashboardConfiguration: Codable, Identifiable {
    let id: String
    let name: String
    let layout: [DashboardWidget]
    let isDefault: Bool
    let createdBy: String
    let lastModified: Date
}

struct DashboardWidget: Codable, Identifiable {
    let id: String
    let type: WidgetType
    let position: WidgetPosition
    let size: WidgetSize
    let configuration: WidgetConfiguration
    
    enum WidgetType: String, CaseIterable, Codable {
        case metric = "metric"
        case chart = "chart"
        case table = "table"
        case alert = "alert"
        case kpi = "kpi"
        case text = "text"
    }
}

struct WidgetPosition: Codable {
    let x: Int
    let y: Int
}

struct WidgetSize: Codable {
    let width: Int
    let height: Int
}

struct WidgetConfiguration: Codable {
    let title: String
    let metric: String?
    let chartType: ChartDefinition.ChartType?
    let timeRange: String?
    let refreshInterval: Int?
    let customSettings: [String: String]?
}

struct DataSourceConnection: Codable, Identifiable {
    let id: String
    let name: String
    let type: DataSourceType
    let connectionString: String
    let isActive: Bool
    let lastSync: Date?
    let syncFrequency: Int // Minutes
    
    enum DataSourceType: String, CaseIterable, Codable {
        case database = "database"
        case api = "api"
        case file = "file"
        case stream = "stream"
        case webhook = "webhook"
    }
}

// MARK: - Data Quality

struct DataIntegrityReport: Codable, Identifiable {
    let id: String
    let tenantId: String
    let overallScore: Double // 0.0-1.0
    let issues: [DataIssue]
    let recommendations: [DataRecommendation]
    let lastValidation: Date
    
    var healthStatus: DataHealthStatus {
        switch overallScore {
        case 0.95...1.0: return .excellent
        case 0.9..<0.95: return .good
        case 0.8..<0.9: return .fair
        case 0.7..<0.8: return .poor
        default: return .critical
        }
    }
    
    enum DataHealthStatus: String, CaseIterable, Codable {
        case excellent = "excellent"
        case good = "good"
        case fair = "fair"
        case poor = "poor"
        case critical = "critical"
        
        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .fair: return .yellow
            case .poor: return .orange
            case .critical: return .red
            }
        }
    }
}

struct DataIssue: Codable, Identifiable {
    let id: String
    let severity: IssueSeverity
    let category: IssueCategory
    let description: String
    let affectedRecords: Int
    let detectedAt: Date
    let autoRepairable: Bool
    
    enum IssueSeverity: String, CaseIterable, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }
    
    enum IssueCategory: String, CaseIterable, Codable {
        case missing = "missing_data"
        case duplicate = "duplicate_data"
        case inconsistent = "inconsistent_data"
        case outdated = "outdated_data"
        case invalid = "invalid_data"
    }
}

struct DataRecommendation: Codable, Identifiable {
    let id: String
    let issue: String
    let recommendation: String
    let expectedImprovement: Double
    let implementationEffort: EffortLevel
    
    enum EffortLevel: String, CaseIterable, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
    }
}

struct DataSourceStatus: Codable, Identifiable {
    let id: String
    let name: String
    let status: ConnectionStatus
    let lastSync: Date?
    let recordCount: Int
    let errorCount: Int
    let latency: Double // Milliseconds
    
    enum ConnectionStatus: String, CaseIterable, Codable {
        case connected = "connected"
        case disconnected = "disconnected"
        case error = "error"
        case syncing = "syncing"
        
        var color: Color {
            switch self {
            case .connected: return .green
            case .disconnected: return .gray
            case .error: return .red
            case .syncing: return .blue
            }
        }
    }
}

// MARK: - Forecasting

enum ForecastTimeframe: String, CaseIterable, Codable {
    case week = "1_week"
    case month = "1_month"
    case quarter = "3_months"
    case halfYear = "6_months"
    case year = "1_year"
    
    var displayName: String {
        switch self {
        case .week: return "1 Week"
        case .month: return "1 Month"
        case .quarter: return "3 Months"
        case .halfYear: return "6 Months"
        case .year: return "1 Year"
        }
    }
}