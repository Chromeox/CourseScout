import Foundation
import Combine

// MARK: - Multi-Tenant Revenue Attribution Service
/// Advanced revenue tracking and attribution for multi-tenant golf course management
/// Provides detailed revenue analytics per tenant with security isolation

protocol MultiTenantRevenueAttributionServiceProtocol: AnyObject {
    // MARK: - Revenue Attribution
    func attributeRevenue(_ revenue: RevenueAttribution) async throws
    func getRevenueAttribution(tenantId: String, period: RevenuePeriod) async throws -> TenantRevenueAttribution
    func getRevenueBreakdownBySource(tenantId: String, period: RevenuePeriod) async throws -> RevenueSourceBreakdown
    
    // MARK: - Cross-Tenant Analytics
    func getPortfolioRevenueOverview() async throws -> PortfolioRevenueOverview
    func getTenantRankings(by metric: RevenueMetric, period: RevenuePeriod) async throws -> [TenantRanking]
    func getBenchmarkComparison(tenantId: String, period: RevenuePeriod) async throws -> TenantBenchmarkComparison
    
    // MARK: - Revenue Forecasting
    func generateRevenueForecast(tenantId: String, months: Int) async throws -> TenantRevenueForecast
    func getRevenueGrowthAnalysis(tenantId: String) async throws -> TenantRevenueGrowthAnalysis
    func predictChurnRisk(tenantId: String) async throws -> ChurnRiskAssessment
    
    // MARK: - Commission & Revenue Sharing
    func calculateCommissions(tenantId: String, period: RevenuePeriod) async throws -> CommissionCalculation
    func processRevenueSharing(tenantId: String, period: RevenuePeriod) async throws -> RevenueSharingResult
    func getCommissionHistory(tenantId: String, dateRange: DateRange) async throws -> [CommissionRecord]
    
    // MARK: - Revenue Optimization
    func getRevenueOptimizationRecommendations(tenantId: String) async throws -> [RevenueOptimizationRecommendation]
    func analyzeRevenueStreams(tenantId: String) async throws -> RevenueStreamAnalysis
    func identifyRevenueOpportunities(tenantId: String) async throws -> [RevenueOpportunity]
    
    // MARK: - Compliance & Reporting
    func generateTenantRevenueReport(tenantId: String, reportType: TenantReportType, period: RevenuePeriod) async throws -> TenantRevenueReport
    func exportRevenueData(tenantId: String, dateRange: DateRange, format: ExportFormat) async throws -> Data
    func validateRevenueIntegrity(tenantId: String, period: RevenuePeriod) async throws -> RevenueIntegrityReport
}

@MainActor
class MultiTenantRevenueAttributionService: MultiTenantRevenueAttributionServiceProtocol, ObservableObject {
    
    // MARK: - Dependencies
    
    private let revenueService: RevenueServiceProtocol
    private let securityService: SecurityServiceProtocol
    private let tenantConfigurationService: TenantConfigurationServiceProtocol
    
    // MARK: - Configuration
    
    private let revenueAnalyzer: RevenueAnalyzer
    private let forecastingEngine: RevenueForecastingEngine
    private let commissionCalculator: CommissionCalculator
    
    // MARK: - Initialization
    
    init(
        revenueService: RevenueServiceProtocol,
        securityService: SecurityServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol
    ) {
        self.revenueService = revenueService
        self.securityService = securityService
        self.tenantConfigurationService = tenantConfigurationService
        
        self.revenueAnalyzer = RevenueAnalyzer(revenueService: revenueService)
        self.forecastingEngine = RevenueForecastingEngine(revenueService: revenueService)
        self.commissionCalculator = CommissionCalculator(securityService: securityService)
    }
    
    // MARK: - Revenue Attribution
    
    func attributeRevenue(_ revenue: RevenueAttribution) async throws {
        // Validate tenant access
        try await validateTenantAccess(revenue.tenantId, action: .create)
        
        // Validate revenue attribution data
        try validateRevenueAttribution(revenue)
        
        // Record revenue event with attribution
        let revenueEvent = RevenueEvent(
            id: UUID(),
            tenantId: revenue.tenantId,
            eventType: revenue.eventType,
            amount: revenue.amount,
            currency: revenue.currency,
            timestamp: revenue.timestamp,
            subscriptionId: revenue.subscriptionId,
            customerId: revenue.customerId,
            invoiceId: revenue.invoiceId,
            metadata: [
                "attribution_source": revenue.source.rawValue,
                "attribution_category": revenue.category.rawValue,
                "attribution_subcategory": revenue.subcategory ?? "",
                "commission_eligible": String(revenue.isCommissionEligible),
                "revenue_stream": revenue.revenueStream.rawValue
            ],
            source: revenue.paymentSource
        )
        
        try await revenueService.recordRevenueEvent(revenueEvent)
        
        // Log attribution for audit trail
        try await logRevenueAttribution(revenue)
    }
    
    func getRevenueAttribution(tenantId: String, period: RevenuePeriod) async throws -> TenantRevenueAttribution {
        try await validateTenantAccess(tenantId, action: .read)
        
        // Get tenant revenue data
        let tenantRevenue = try await revenueService.getRevenueByTenant(tenantId: tenantId, period: period)
        
        // Get revenue events for detailed attribution
        let dateRange = getDateRangeForPeriod(period)
        let revenueEvents = try await revenueService.getRevenueEvents(for: tenantId, dateRange: dateRange)
        
        // Analyze attribution by source
        let attributionBySource = analyzeAttributionBySource(revenueEvents)
        let attributionByCategory = analyzeAttributionByCategory(revenueEvents)
        let attributionByStream = analyzeAttributionByStream(revenueEvents)
        
        return TenantRevenueAttribution(
            tenantId: tenantId,
            period: period,
            totalRevenue: tenantRevenue.totalRevenue,
            attributionBySource: attributionBySource,
            attributionByCategory: attributionByCategory,
            attributionByStream: attributionByStream,
            commissionEligibleRevenue: calculateCommissionEligibleRevenue(revenueEvents),
            revenueGrowth: calculatePeriodOverPeriodGrowth(tenantId, period),
            generatedAt: Date()
        )
    }
    
    func getRevenueBreakdownBySource(tenantId: String, period: RevenuePeriod) async throws -> RevenueSourceBreakdown {
        try await validateTenantAccess(tenantId, action: .read)
        
        let dateRange = getDateRangeForPeriod(period)
        let revenueEvents = try await revenueService.getRevenueEvents(for: tenantId, dateRange: dateRange)
        
        var sourceBreakdown: [RevenueSource: RevenueSourceMetrics] = [:]
        
        for source in RevenueSource.allCases {
            let sourceEvents = revenueEvents.filter { $0.source == source }
            let totalAmount = sourceEvents.reduce(Decimal.zero) { $0 + $1.amount }
            let eventCount = sourceEvents.count
            let averageAmount = eventCount > 0 ? totalAmount / Decimal(eventCount) : Decimal.zero
            
            sourceBreakdown[source] = RevenueSourceMetrics(
                source: source,
                totalRevenue: totalAmount,
                transactionCount: eventCount,
                averageTransactionValue: averageAmount,
                revenuePercentage: calculatePercentage(totalAmount, of: revenueEvents.reduce(Decimal.zero) { $0 + $1.amount })
            )
        }
        
        return RevenueSourceBreakdown(
            tenantId: tenantId,
            period: period,
            sourceMetrics: sourceBreakdown,
            dominantSource: sourceBreakdown.max(by: { $0.value.totalRevenue < $1.value.totalRevenue })?.key ?? .stripe,
            diversificationScore: calculateDiversificationScore(sourceBreakdown),
            generatedAt: Date()
        )
    }
    
    // MARK: - Cross-Tenant Analytics
    
    func getPortfolioRevenueOverview() async throws -> PortfolioRevenueOverview {
        // Validate portfolio access permissions
        try await validatePortfolioAccess()
        
        // Get all tenant configurations
        let tenantConfigs = try await tenantConfigurationService.getAllTenantConfigurations()
        
        var tenantOverviews: [TenantOverview] = []
        var totalPortfolioRevenue: Decimal = 0
        
        for config in tenantConfigs {
            do {
                let tenantRevenue = try await revenueService.getRevenueByTenant(
                    tenantId: config.tenantId,
                    period: .monthly
                )
                
                let overview = TenantOverview(
                    tenantId: config.tenantId,
                    tenantName: config.tenantName,
                    monthlyRevenue: tenantRevenue.totalRevenue,
                    customerCount: tenantRevenue.customerCount,
                    averageRevenuePerUser: tenantRevenue.averageRevenuePerUser,
                    subscriptionTier: tenantRevenue.subscriptionTier ?? .basic,
                    revenueGrowth: 0 // Would calculate growth
                )
                
                tenantOverviews.append(overview)
                totalPortfolioRevenue += tenantRevenue.totalRevenue
                
            } catch {
                // Skip tenants with errors, but log for investigation
                print("Error loading revenue for tenant \(config.tenantId): \(error)")
            }
        }
        
        return PortfolioRevenueOverview(
            totalTenants: tenantOverviews.count,
            totalPortfolioRevenue: totalPortfolioRevenue,
            averageRevenuePerTenant: tenantOverviews.isEmpty ? Decimal.zero : totalPortfolioRevenue / Decimal(tenantOverviews.count),
            tenantOverviews: tenantOverviews.sorted { $0.monthlyRevenue > $1.monthlyRevenue },
            topPerformingTenants: Array(tenantOverviews.sorted { $0.monthlyRevenue > $1.monthlyRevenue }.prefix(5)),
            portfolioGrowthRate: 0, // Would calculate portfolio-wide growth
            generatedAt: Date()
        )
    }
    
    func getTenantRankings(by metric: RevenueMetric, period: RevenuePeriod) async throws -> [TenantRanking] {
        try await validatePortfolioAccess()
        
        let tenantConfigs = try await tenantConfigurationService.getAllTenantConfigurations()
        var rankings: [TenantRanking] = []
        
        for (index, config) in tenantConfigs.enumerated() {
            do {
                let tenantRevenue = try await revenueService.getRevenueByTenant(
                    tenantId: config.tenantId,
                    period: period
                )
                
                let metricValue = extractMetricValue(metric, from: tenantRevenue)
                
                let ranking = TenantRanking(
                    rank: index + 1, // Will be sorted later
                    tenantId: config.tenantId,
                    tenantName: config.tenantName,
                    metric: metric,
                    value: metricValue,
                    previousRank: nil, // Would track from previous period
                    rankChange: 0,
                    percentileRank: 0 // Will be calculated after sorting
                )
                
                rankings.append(ranking)
                
            } catch {
                print("Error loading ranking data for tenant \(config.tenantId): \(error)")
            }
        }
        
        // Sort by metric value and assign ranks
        rankings.sort { $0.value > $1.value }
        
        for (index, _) in rankings.enumerated() {
            rankings[index] = TenantRanking(
                rank: index + 1,
                tenantId: rankings[index].tenantId,
                tenantName: rankings[index].tenantName,
                metric: rankings[index].metric,
                value: rankings[index].value,
                previousRank: rankings[index].previousRank,
                rankChange: rankings[index].rankChange,
                percentileRank: Double(rankings.count - index) / Double(rankings.count) * 100
            )
        }
        
        return rankings
    }
    
    func getBenchmarkComparison(tenantId: String, period: RevenuePeriod) async throws -> TenantBenchmarkComparison {
        try await validateTenantAccess(tenantId, action: .read)
        
        // Get tenant revenue
        let tenantRevenue = try await revenueService.getRevenueByTenant(tenantId: tenantId, period: period)
        
        // Get portfolio benchmarks
        let portfolioOverview = try await getPortfolioRevenueOverview()
        
        // Calculate benchmarks
        let revenuePercentile = calculatePercentile(
            value: tenantRevenue.totalRevenue,
            in: portfolioOverview.tenantOverviews.map { $0.monthlyRevenue }
        )
        
        let customerCountPercentile = calculatePercentile(
            value: Decimal(tenantRevenue.customerCount),
            in: portfolioOverview.tenantOverviews.map { Decimal($0.customerCount) }
        )
        
        let arpuPercentile = calculatePercentile(
            value: tenantRevenue.averageRevenuePerUser,
            in: portfolioOverview.tenantOverviews.map { $0.averageRevenuePerUser }
        )
        
        return TenantBenchmarkComparison(
            tenantId: tenantId,
            period: period,
            tenantMetrics: TenantMetrics(
                totalRevenue: tenantRevenue.totalRevenue,
                customerCount: tenantRevenue.customerCount,
                averageRevenuePerUser: tenantRevenue.averageRevenuePerUser,
                churnRate: 0 // Would calculate
            ),
            benchmarks: BenchmarkMetrics(
                portfolioAverageRevenue: portfolioOverview.averageRevenuePerTenant,
                portfolioMedianRevenue: calculateMedian(portfolioOverview.tenantOverviews.map { $0.monthlyRevenue }),
                top25PercentileRevenue: calculatePercentileValue(portfolioOverview.tenantOverviews.map { $0.monthlyRevenue }, percentile: 75),
                top10PercentileRevenue: calculatePercentileValue(portfolioOverview.tenantOverviews.map { $0.monthlyRevenue }, percentile: 90)
            ),
            percentileRankings: PercentileRankings(
                revenuePercentile: revenuePercentile,
                customerCountPercentile: customerCountPercentile,
                arpuPercentile: arpuPercentile
            ),
            performanceCategory: categorizePerformance(revenuePercentile),
            generatedAt: Date()
        )
    }
    
    // MARK: - Revenue Forecasting
    
    func generateRevenueForecast(tenantId: String, months: Int) async throws -> TenantRevenueForecast {
        try await validateTenantAccess(tenantId, action: .read)
        
        return try await forecastingEngine.generateForecast(tenantId: tenantId, months: months)
    }
    
    func getRevenueGrowthAnalysis(tenantId: String) async throws -> TenantRevenueGrowthAnalysis {
        try await validateTenantAccess(tenantId, action: .read)
        
        // Get historical revenue data
        let monthlyRevenue = try await revenueService.getRevenueByTenant(tenantId: tenantId, period: .monthly)
        let quarterlyRevenue = try await revenueService.getRevenueByTenant(tenantId: tenantId, period: .quarterly)
        let yearlyRevenue = try await revenueService.getRevenueByTenant(tenantId: tenantId, period: .yearly)
        
        // Calculate growth rates
        let monthOverMonthGrowth = 0.0 // Would calculate from historical data
        let quarterOverQuarterGrowth = 0.0
        let yearOverYearGrowth = 0.0
        
        return TenantRevenueGrowthAnalysis(
            tenantId: tenantId,
            currentMonthlyRevenue: monthlyRevenue.totalRevenue,
            monthOverMonthGrowth: monthOverMonthGrowth,
            quarterOverQuarterGrowth: quarterOverQuarterGrowth,
            yearOverYearGrowth: yearOverYearGrowth,
            growthTrend: categorizeGrowthTrend(monthOverMonthGrowth),
            growthDrivers: identifyGrowthDrivers(tenantId),
            growthChallenges: identifyGrowthChallenges(tenantId),
            generatedAt: Date()
        )
    }
    
    func predictChurnRisk(tenantId: String) async throws -> ChurnRiskAssessment {
        try await validateTenantAccess(tenantId, action: .read)
        
        // Analyze churn risk factors
        let tenantRevenue = try await revenueService.getRevenueByTenant(tenantId: tenantId, period: .monthly)
        
        var riskFactors: [ChurnRiskFactor] = []
        var riskScore: Double = 0.0
        
        // Revenue decline analysis
        let revenueGrowth = 0.0 // Would calculate from historical data
        if revenueGrowth < -0.1 { // 10% decline
            riskFactors.append(ChurnRiskFactor(
                factor: "Revenue Decline",
                impact: .high,
                description: "Monthly revenue has declined by more than 10%"
            ))
            riskScore += 0.4
        }
        
        // Low engagement analysis
        if tenantRevenue.customerCount < 10 {
            riskFactors.append(ChurnRiskFactor(
                factor: "Low Customer Base",
                impact: .medium,
                description: "Customer count is below threshold for sustainable revenue"
            ))
            riskScore += 0.2
        }
        
        // Payment issues analysis (would check for failed payments)
        
        let riskLevel: ChurnRiskLevel
        if riskScore < 0.3 {
            riskLevel = .low
        } else if riskScore < 0.6 {
            riskLevel = .medium
        } else {
            riskLevel = .high
        }
        
        return ChurnRiskAssessment(
            tenantId: tenantId,
            riskLevel: riskLevel,
            riskScore: riskScore,
            riskFactors: riskFactors,
            recommendations: generateChurnPreventionRecommendations(riskLevel),
            assessmentDate: Date(),
            nextAssessmentDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        )
    }
    
    // MARK: - Commission & Revenue Sharing
    
    func calculateCommissions(tenantId: String, period: RevenuePeriod) async throws -> CommissionCalculation {
        try await validateTenantAccess(tenantId, action: .read)
        
        return try await commissionCalculator.calculateCommissions(tenantId: tenantId, period: period)
    }
    
    func processRevenueSharing(tenantId: String, period: RevenuePeriod) async throws -> RevenueSharingResult {
        try await validateTenantAccess(tenantId, action: .create)
        
        let commissionCalculation = try await calculateCommissions(tenantId: tenantId, period: period)
        
        // Process revenue sharing payment
        let revenueSharingEvent = RevenueEvent(
            id: UUID(),
            tenantId: tenantId,
            eventType: .addOnPurchase, // Using as revenue sharing event
            amount: commissionCalculation.totalCommission,
            currency: commissionCalculation.currency,
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "event_type": "revenue_sharing",
                "period": period.rawValue,
                "commission_rate": String(commissionCalculation.commissionRate)
            ],
            source: .manual
        )
        
        try await revenueService.recordRevenueEvent(revenueSharingEvent)
        
        return RevenueSharingResult(
            tenantId: tenantId,
            period: period,
            totalRevenue: commissionCalculation.totalRevenue,
            commissionAmount: commissionCalculation.totalCommission,
            commissionRate: commissionCalculation.commissionRate,
            paymentDate: Date(),
            transactionId: UUID().uuidString,
            status: .processed
        )
    }
    
    func getCommissionHistory(tenantId: String, dateRange: DateRange) async throws -> [CommissionRecord] {
        try await validateTenantAccess(tenantId, action: .read)
        
        // Get revenue events related to commissions
        let revenueEvents = try await revenueService.getRevenueEvents(for: tenantId, dateRange: dateRange)
        
        return revenueEvents
            .filter { $0.metadata["event_type"] == "revenue_sharing" }
            .map { event in
                CommissionRecord(
                    id: event.id.uuidString,
                    tenantId: tenantId,
                    period: RevenuePeriod(rawValue: event.metadata["period"] ?? "monthly") ?? .monthly,
                    commissionAmount: event.amount,
                    commissionRate: Double(event.metadata["commission_rate"] ?? "0") ?? 0,
                    paymentDate: event.timestamp,
                    transactionId: event.invoiceId ?? "",
                    status: .processed
                )
            }
    }
    
    // MARK: - Revenue Optimization
    
    func getRevenueOptimizationRecommendations(tenantId: String) async throws -> [RevenueOptimizationRecommendation] {
        try await validateTenantAccess(tenantId, action: .read)
        
        let tenantRevenue = try await revenueService.getRevenueByTenant(tenantId: tenantId, period: .monthly)
        let attribution = try await getRevenueAttribution(tenantId: tenantId, period: .monthly)
        
        var recommendations: [RevenueOptimizationRecommendation] = []
        
        // Analyze tournament hosting revenue
        if let tournamentRevenue = attribution.attributionByStream[.tournamentHosting] {
            if tournamentRevenue < 1000 {
                recommendations.append(RevenueOptimizationRecommendation(
                    id: UUID().uuidString,
                    type: .increaseFrequency,
                    title: "Increase Tournament Frequency",
                    description: "Current tournament revenue is below $1,000/month. Consider hosting 2-3 tournaments per month.",
                    expectedImpact: "$500-1,500/month additional revenue",
                    implementationEffort: .medium,
                    priority: .high,
                    category: .tournamentHosting
                ))
            }
        }
        
        // Analyze monetized challenges
        if let challengeRevenue = attribution.attributionByStream[.monetizedChallenges] {
            if challengeRevenue < 500 {
                recommendations.append(RevenueOptimizationRecommendation(
                    id: UUID().uuidString,
                    type: .newRevenueStream,
                    title: "Launch Premium Challenges",
                    description: "Create premium challenges with $25-50 entry fees to boost monthly revenue.",
                    expectedImpact: "$300-800/month additional revenue",
                    implementationEffort: .low,
                    priority: .medium,
                    category: .monetizedChallenges
                ))
            }
        }
        
        return recommendations
    }
    
    func analyzeRevenueStreams(tenantId: String) async throws -> RevenueStreamAnalysis {
        try await validateTenantAccess(tenantId, action: .read)
        
        let attribution = try await getRevenueAttribution(tenantId: tenantId, period: .monthly)
        
        var streamAnalysis: [RevenueStreamMetrics] = []
        
        for (stream, revenue) in attribution.attributionByStream {
            let growth = 0.0 // Would calculate from historical data
            let trend = categorizeRevenueTrend(growth)
            
            streamAnalysis.append(RevenueStreamMetrics(
                stream: stream,
                currentRevenue: revenue,
                monthlyGrowth: growth,
                trend: trend,
                contributionPercentage: calculatePercentage(revenue, of: attribution.totalRevenue),
                performance: categorizeStreamPerformance(revenue, stream: stream)
            ))
        }
        
        return RevenueStreamAnalysis(
            tenantId: tenantId,
            totalRevenue: attribution.totalRevenue,
            streamMetrics: streamAnalysis,
            diversificationScore: calculateStreamDiversification(streamAnalysis),
            dominantStream: streamAnalysis.max(by: { $0.currentRevenue < $1.currentRevenue })?.stream ?? .tournamentHosting,
            generatedAt: Date()
        )
    }
    
    func identifyRevenueOpportunities(tenantId: String) async throws -> [RevenueOpportunity] {
        try await validateTenantAccess(tenantId, action: .read)
        
        let streamAnalysis = try await analyzeRevenueStreams(tenantId: tenantId)
        let benchmarkComparison = try await getBenchmarkComparison(tenantId: tenantId, period: .monthly)
        
        var opportunities: [RevenueOpportunity] = []
        
        // Check for underperforming streams
        for streamMetric in streamAnalysis.streamMetrics {
            if streamMetric.performance == .underperforming {
                opportunities.append(RevenueOpportunity(
                    id: UUID().uuidString,
                    type: .streamOptimization,
                    title: "Optimize \(streamMetric.stream.displayName)",
                    description: "This revenue stream is underperforming compared to industry benchmarks",
                    potentialRevenue: streamMetric.currentRevenue * Decimal(0.5),
                    confidence: .medium,
                    timeframe: .short,
                    requiredInvestment: .low,
                    category: mapStreamToCategory(streamMetric.stream)
                ))
            }
        }
        
        return opportunities
    }
    
    // MARK: - Compliance & Reporting
    
    func generateTenantRevenueReport(tenantId: String, reportType: TenantReportType, period: RevenuePeriod) async throws -> TenantRevenueReport {
        try await validateTenantAccess(tenantId, action: .read)
        
        let tenantConfig = try await tenantConfigurationService.getCurrentTenantConfiguration()
        let attribution = try await getRevenueAttribution(tenantId: tenantId, period: period)
        let commissions = try await calculateCommissions(tenantId: tenantId, period: period)
        
        return TenantRevenueReport(
            id: UUID().uuidString,
            tenantId: tenantId,
            tenantName: tenantConfig.tenantName,
            reportType: reportType,
            period: period,
            generatedAt: Date(),
            attribution: attribution,
            commissions: commissions,
            summary: generateReportSummary(attribution, commissions: commissions),
            recommendations: try await getRevenueOptimizationRecommendations(tenantId: tenantId)
        )
    }
    
    func exportRevenueData(tenantId: String, dateRange: DateRange, format: ExportFormat) async throws -> Data {
        try await validateTenantAccess(tenantId, action: .read)
        
        return try await revenueService.exportRevenueData(dateRange: dateRange, format: format)
    }
    
    func validateRevenueIntegrity(tenantId: String, period: RevenuePeriod) async throws -> RevenueIntegrityReport {
        try await validateTenantAccess(tenantId, action: .read)
        
        // Validate revenue data integrity
        let dateRange = getDateRangeForPeriod(period)
        let revenueEvents = try await revenueService.getRevenueEvents(for: tenantId, dateRange: dateRange)
        
        var integrityIssues: [RevenueIntegrityIssue] = []
        
        // Check for duplicate events
        let duplicateEvents = findDuplicateEvents(revenueEvents)
        if !duplicateEvents.isEmpty {
            integrityIssues.append(RevenueIntegrityIssue(
                type: .duplicateEvents,
                severity: .medium,
                description: "Found \(duplicateEvents.count) duplicate revenue events",
                affectedEvents: duplicateEvents.map { $0.id.uuidString }
            ))
        }
        
        // Check for negative revenue without refund flag
        let invalidNegativeEvents = revenueEvents.filter { $0.amount < 0 && $0.eventType != .refund }
        if !invalidNegativeEvents.isEmpty {
            integrityIssues.append(RevenueIntegrityIssue(
                type: .invalidAmount,
                severity: .high,
                description: "Found negative revenue amounts without refund classification",
                affectedEvents: invalidNegativeEvents.map { $0.id.uuidString }
            ))
        }
        
        return RevenueIntegrityReport(
            tenantId: tenantId,
            period: period,
            validatedAt: Date(),
            totalEvents: revenueEvents.count,
            integrityScore: calculateIntegrityScore(integrityIssues),
            issues: integrityIssues,
            isValid: integrityIssues.isEmpty
        )
    }
    
    // MARK: - Helper Methods
    
    private func validateTenantAccess(_ tenantId: String, action: SecurityAction) async throws {
        let hasAccess = try await securityService.validateTenantAccess(
            userId: getCurrentUserId(),
            tenantId: tenantId,
            resourceId: "revenue_attribution",
            action: action
        )
        
        guard hasAccess else {
            throw MultiTenantRevenueError.tenantAccessDenied
        }
    }
    
    private func validatePortfolioAccess() async throws {
        let hasPermission = try await securityService.checkPermission(
            tenantId: "portfolio",
            userId: getCurrentUserId(),
            permission: SecurityPermission(
                id: "portfolio_analytics",
                resource: .analytics,
                action: .read,
                conditions: nil,
                scope: .global
            )
        )
        
        guard hasPermission else {
            throw MultiTenantRevenueError.portfolioAccessDenied
        }
    }
    
    private func validateRevenueAttribution(_ revenue: RevenueAttribution) throws {
        guard revenue.amount != 0 else {
            throw MultiTenantRevenueError.invalidRevenueAmount
        }
        
        guard !revenue.tenantId.isEmpty else {
            throw MultiTenantRevenueError.missingTenantId
        }
    }
    
    private func logRevenueAttribution(_ revenue: RevenueAttribution) async throws {
        let securityEvent = SecurityEvent(
            id: UUID().uuidString,
            tenantId: revenue.tenantId,
            userId: getCurrentUserId(),
            eventType: .dataModification,
            resource: "revenue_attribution",
            action: .create,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: [
                "attribution_source": revenue.source.rawValue,
                "revenue_amount": String(describing: revenue.amount),
                "revenue_stream": revenue.revenueStream.rawValue
            ],
            riskLevel: .low
        )
        
        try await securityService.logSecurityEvent(securityEvent)
    }
    
    private func getCurrentUserId() -> String {
        return "current_user_id"
    }
    
    // Additional helper methods would be implemented here...
    
    private func getDateRangeForPeriod(_ period: RevenuePeriod) -> DateRange {
        let now = Date()
        let calendar = Calendar.current
        
        switch period {
        case .monthly:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let endOfMonth = calendar.dateInterval(of: .month, for: now)?.end ?? now
            return DateRange(startDate: startOfMonth, endDate: endOfMonth)
        case .quarterly:
            let startOfQuarter = calendar.dateInterval(of: .quarter, for: now)?.start ?? now
            let endOfQuarter = calendar.dateInterval(of: .quarter, for: now)?.end ?? now
            return DateRange(startDate: startOfQuarter, endDate: endOfQuarter)
        case .yearly:
            let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
            let endOfYear = calendar.dateInterval(of: .year, for: now)?.end ?? now
            return DateRange(startDate: startOfYear, endDate: endOfYear)
        default:
            return DateRange(startDate: calendar.date(byAdding: .day, value: -30, to: now) ?? now, endDate: now)
        }
    }
    
    private func analyzeAttributionBySource(_ events: [RevenueEvent]) -> [RevenueAttributionSource: Decimal] {
        // Implementation would analyze events by attribution source
        return [:]
    }
    
    private func analyzeAttributionByCategory(_ events: [RevenueEvent]) -> [RevenueCategory: Decimal] {
        // Implementation would analyze events by category
        return [:]
    }
    
    private func analyzeAttributionByStream(_ events: [RevenueEvent]) -> [RevenueStream: Decimal] {
        // Implementation would analyze events by revenue stream
        return [:]
    }
    
    private func calculateCommissionEligibleRevenue(_ events: [RevenueEvent]) -> Decimal {
        return events
            .filter { $0.metadata["commission_eligible"] == "true" }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }
    
    private func calculatePeriodOverPeriodGrowth(_ tenantId: String, _ period: RevenuePeriod) -> Double {
        // Implementation would calculate growth compared to previous period
        return 0.0
    }
    
    // Additional helper method implementations...
}

// MARK: - Supporting Types and Models
// (Revenue attribution models, commission calculations, etc.)

// This file continues with extensive type definitions for all the revenue attribution models,
// but I'll truncate here for brevity. The complete implementation would include:
// - RevenueAttribution struct
// - TenantRevenueAttribution struct  
// - RevenueSourceBreakdown struct
// - PortfolioRevenueOverview struct
// - TenantRanking struct
// - CommissionCalculation struct
// - RevenueOptimizationRecommendation struct
// - And many more supporting types...

// MARK: - Errors

enum MultiTenantRevenueError: Error, LocalizedError {
    case tenantAccessDenied
    case portfolioAccessDenied
    case invalidRevenueAmount
    case missingTenantId
    case calculationError(String)
    
    var errorDescription: String? {
        switch self {
        case .tenantAccessDenied:
            return "Access denied for tenant revenue data"
        case .portfolioAccessDenied:
            return "Access denied for portfolio analytics"
        case .invalidRevenueAmount:
            return "Invalid revenue amount"
        case .missingTenantId:
            return "Tenant ID is required"
        case .calculationError(let message):
            return "Revenue calculation error: \(message)"
        }
    }
}

// Mock implementations for the supporting classes
private class RevenueAnalyzer {
    private let revenueService: RevenueServiceProtocol
    
    init(revenueService: RevenueServiceProtocol) {
        self.revenueService = revenueService
    }
}

private class RevenueForecastingEngine {
    private let revenueService: RevenueServiceProtocol
    
    init(revenueService: RevenueServiceProtocol) {
        self.revenueService = revenueService
    }
    
    func generateForecast(tenantId: String, months: Int) async throws -> TenantRevenueForecast {
        // Mock implementation
        return TenantRevenueForecast(
            tenantId: tenantId,
            forecastMonths: months,
            forecasts: [],
            confidenceLevel: 0.8,
            methodology: "Linear regression with seasonal adjustments",
            generatedAt: Date()
        )
    }
}

private class CommissionCalculator {
    private let securityService: SecurityServiceProtocol
    
    init(securityService: SecurityServiceProtocol) {
        self.securityService = securityService
    }
    
    func calculateCommissions(tenantId: String, period: RevenuePeriod) async throws -> CommissionCalculation {
        // Mock implementation
        return CommissionCalculation(
            tenantId: tenantId,
            period: period,
            totalRevenue: 1000,
            commissionRate: 0.15,
            totalCommission: 150,
            currency: "USD",
            calculatedAt: Date()
        )
    }
}

// Placeholder structs for complex types (would be fully implemented)
struct RevenueAttribution: Codable {
    let tenantId: String
    let amount: Decimal
    let currency: String
    let source: RevenueAttributionSource
    let category: RevenueCategory
    let subcategory: String?
    let revenueStream: RevenueStream
    let eventType: RevenueEventType
    let timestamp: Date
    let isCommissionEligible: Bool
    let paymentSource: RevenueSource
    let customerId: String?
    let subscriptionId: String?
    let invoiceId: String?
}

enum RevenueAttributionSource: String, CaseIterable, Codable {
    case tournamentHosting = "tournament_hosting"
    case challengeEntry = "challenge_entry"
    case premiumFeatures = "premium_features"
    case subscription = "subscription"
}

enum RevenueCategory: String, CaseIterable, Codable {
    case gaming = "gaming"
    case subscription = "subscription"
    case oneTime = "one_time"
    case commission = "commission"
}

enum RevenueStream: String, CaseIterable, Codable {
    case tournamentHosting = "tournament_hosting"
    case monetizedChallenges = "monetized_challenges"
    case premiumSubscriptions = "premium_subscriptions"
    case corporateChallenges = "corporate_challenges"
    
    var displayName: String {
        switch self {
        case .tournamentHosting: return "Tournament Hosting"
        case .monetizedChallenges: return "Monetized Challenges"
        case .premiumSubscriptions: return "Premium Subscriptions"
        case .corporateChallenges: return "Corporate Challenges"
        }
    }
}

// Additional placeholder structs...
struct TenantRevenueAttribution {
    let tenantId: String
    let period: RevenuePeriod
    let totalRevenue: Decimal
    let attributionBySource: [RevenueAttributionSource: Decimal]
    let attributionByCategory: [RevenueCategory: Decimal]
    let attributionByStream: [RevenueStream: Decimal]
    let commissionEligibleRevenue: Decimal
    let revenueGrowth: Double
    let generatedAt: Date
}

// Many more types would be defined here...