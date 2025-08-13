import Foundation
import Combine
import SwiftUI

// MARK: - Revenue Optimization ViewModel

@MainActor
class RevenueOptimizationViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var revenueData: [RevenueDataPoint] = []
    @Published var pricingRecommendations: [PricingRecommendation] = []
    @Published var demandForecast: [DemandForecastPoint] = []
    @Published var revenueOpportunities: [BusinessOpportunity] = []
    @Published var aiRecommendations: [AIRecommendation] = []
    @Published var revenueDistribution: [RevenueDistribution] = []
    
    // MARK: - Revenue Metrics
    @Published var totalRevenue: Double = 0
    @Published var revenuePerBooking: Double = 0
    @Published var avgDailyRevenue: Double = 0
    @Published var revenueGrowthRate: Double = 0
    
    // MARK: - Changes and Targets
    @Published var revenueChange: Double? = nil
    @Published var revenuePerBookingChange: Double? = nil
    @Published var avgDailyRevenueChange: Double? = nil
    
    @Published var revenueTarget: Double = 50000
    @Published var revenuePerBookingTarget: Double = 125
    @Published var avgDailyRevenueTarget: Double = 2500
    
    // MARK: - Demand Analytics
    @Published var peakDemandHours = "10 AM - 2 PM"
    @Published var lowDemandPeriods = "4 PM - 6 PM"
    @Published var avgCapacityUtilization: Double = 0.72
    
    // MARK: - UI State
    @Published var selectedChartType: ChartType = .line
    @Published var isRealTimeConnected = false
    @Published var isLoading = false
    
    // MARK: - Private Properties
    private var analyticsService: B2BAnalyticsServiceProtocol?
    private var currentTenantId: String?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Real-time Updates
    private var realTimeTimer: Timer?
    private let realTimeUpdateInterval: TimeInterval = 30.0
    
    // MARK: - Configuration
    
    func configure(for tenantId: String) {
        currentTenantId = tenantId
        analyticsService = ServiceContainer.shared.resolve(B2BAnalyticsServiceProtocol.self)
        
        setupRealTimeUpdates()
        setupAnalyticsSubscriptions()
    }
    
    deinit {
        stopRealTimeUpdates()
    }
    
    // MARK: - Data Loading
    
    func loadRevenueOptimizationData(tenantId: String, timeframe: RevenueTimeframe) async {
        guard !isLoading else { return }
        
        isLoading = true
        currentTenantId = tenantId
        
        do {
            async let revenueTask = loadRevenueData(tenantId: tenantId, timeframe: timeframe)
            async let pricingTask = loadPricingRecommendations(tenantId: tenantId)
            async let demandTask = loadDemandForecast(tenantId: tenantId)
            async let opportunitiesTask = loadRevenueOpportunities(tenantId: tenantId)
            async let recommendationsTask = loadAIRecommendations(tenantId: tenantId)
            async let distributionTask = loadRevenueDistribution(tenantId: tenantId)
            
            let (revenue, pricing, demand, opportunities, recommendations, distribution) = try await (
                revenueTask,
                pricingTask,
                demandTask,
                opportunitiesTask,
                recommendationsTask,
                distributionTask
            )
            
            revenueData = revenue
            pricingRecommendations = pricing
            demandForecast = demand
            revenueOpportunities = opportunities
            aiRecommendations = recommendations
            revenueDistribution = distribution
            
            updateRevenueMetrics(from: revenue)
            
        } catch {
            handleError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Private Data Loading Methods
    
    private func loadRevenueData(tenantId: String, timeframe: RevenueTimeframe) async throws -> [RevenueDataPoint] {
        guard let analyticsService = analyticsService else {
            throw RevenueOptimizationError.serviceNotAvailable
        }
        
        let period = timeframe.analyticsPeriod
        let revenueMetrics = try await analyticsService.loadRevenueMetrics(for: tenantId, period: period)
        
        return generateRevenueDataPoints(from: revenueMetrics, timeframe: timeframe)
    }
    
    private func loadPricingRecommendations(tenantId: String) async throws -> [PricingRecommendation] {
        guard let analyticsService = analyticsService else {
            throw RevenueOptimizationError.serviceNotAvailable
        }
        
        let today = Date()
        return try await analyticsService.optimizePricing(for: tenantId, date: today)
    }
    
    private func loadDemandForecast(tenantId: String) async throws -> [DemandForecastPoint] {
        guard let analyticsService = analyticsService else {
            throw RevenueOptimizationError.serviceNotAvailable
        }
        
        let today = Date()
        let predictions = try await analyticsService.predictDemand(for: tenantId, date: today)
        
        return predictions.map { prediction in
            DemandForecastPoint(
                date: prediction.date,
                predictedDemand: prediction.predictedDemand,
                confidence: 0.85 // Mock confidence level
            )
        }
    }
    
    private func loadRevenueOpportunities(tenantId: String) async throws -> [BusinessOpportunity] {
        guard let analyticsService = analyticsService else {
            throw RevenueOptimizationError.serviceNotAvailable
        }
        
        let summary = try await analyticsService.loadAnalyticsSummary(for: tenantId, period: .month)
        return summary.opportunities
    }
    
    private func loadAIRecommendations(tenantId: String) async throws -> [AIRecommendation] {
        guard let analyticsService = analyticsService else {
            throw RevenueOptimizationError.serviceNotAvailable
        }
        
        let summary = try await analyticsService.loadAnalyticsSummary(for: tenantId, period: .month)
        
        return summary.recommendations.map { insight in
            AIRecommendation(
                title: generateRecommendationTitle(for: insight),
                description: insight.recommendation,
                category: insight.category,
                priority: mapInsightPriority(insight.dataConfidence),
                expectedImpact: insight.expectedImpact,
                icon: getRecommendationIcon(for: insight.category)
            )
        }
    }
    
    private func loadRevenueDistribution(tenantId: String) async throws -> [RevenueDistribution] {
        guard let analyticsService = analyticsService else {
            throw RevenueOptimizationError.serviceNotAvailable
        }
        
        let revenueMetrics = try await analyticsService.loadRevenueMetrics(for: tenantId, period: .month)
        
        return [
            RevenueDistribution(
                category: "Green Fees",
                amount: revenueMetrics.bookingRevenue,
                color: .green
            ),
            RevenueDistribution(
                category: "Memberships",
                amount: revenueMetrics.membershipRevenue,
                color: .blue
            ),
            RevenueDistribution(
                category: "Pro Shop",
                amount: revenueMetrics.merchandiseRevenue,
                color: .orange
            ),
            RevenueDistribution(
                category: "Food & Beverage",
                amount: revenueMetrics.foodBeverageRevenue,
                color: .purple
            ),
            RevenueDistribution(
                category: "Other",
                amount: revenueMetrics.otherRevenue,
                color: .gray
            )
        ]
    }
    
    // MARK: - Data Processing
    
    private func generateRevenueDataPoints(from metrics: RevenueMetrics, timeframe: RevenueTimeframe) -> [RevenueDataPoint] {
        let calendar = Calendar.current
        let endDate = Date()
        
        // Determine the number of data points and time interval
        let (pointCount, component) = timeframe.dataPointConfiguration
        
        return (0..<pointCount).compactMap { offset in
            guard let date = calendar.date(byAdding: component, value: -offset, to: endDate) else {
                return nil
            }
            
            // Calculate values based on historical patterns with some variance
            let baseRevenue = metrics.totalRevenue / Double(pointCount)
            let revenueVariance = Double.random(in: -0.2...0.3)
            let totalRevenue = baseRevenue * (1.0 + revenueVariance)
            
            let basePerBooking = metrics.averageRevenuePerBooking
            let perBookingVariance = Double.random(in: -0.15...0.25)
            let revenuePerBooking = basePerBooking * (1.0 + perBookingVariance)
            
            // Generate forecast for future dates
            let forecast: Double? = date > endDate ? totalRevenue * 1.05 : nil
            
            return RevenueDataPoint(
                date: date,
                totalRevenue: max(0, totalRevenue),
                revenuePerBooking: max(0, revenuePerBooking),
                revenuePerMember: totalRevenue / 100, // Assuming 100 members average
                grossRevenue: totalRevenue * 1.1, // 10% higher gross
                forecast: forecast
            )
        }.reversed()
    }
    
    private func updateRevenueMetrics(from data: [RevenueDataPoint]) {
        guard !data.isEmpty else { return }
        
        // Current metrics (latest data point)
        let latest = data.last!
        totalRevenue = latest.totalRevenue
        revenuePerBooking = latest.revenuePerBooking
        
        // Calculate average daily revenue
        avgDailyRevenue = data.reduce(0) { $0 + $1.totalRevenue } / Double(data.count)
        
        // Calculate growth rate
        if data.count >= 2 {
            let previous = data[data.count - 2]
            let current = data[data.count - 1]
            
            revenueGrowthRate = (current.totalRevenue - previous.totalRevenue) / previous.totalRevenue
            revenueChange = revenueGrowthRate * 100
            
            let revenuePerBookingGrowth = (current.revenuePerBooking - previous.revenuePerBooking) / previous.revenuePerBooking
            revenuePerBookingChange = revenuePerBookingGrowth * 100
            
            // Mock daily revenue change
            avgDailyRevenueChange = Double.random(in: -5...15)
        }
    }
    
    // MARK: - Recommendation Actions
    
    func implementOpportunity(_ opportunity: BusinessOpportunity) async {
        // Simulate implementing the opportunity
        do {
            // In a real implementation, this would call backend services
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            // Remove the implemented opportunity
            revenueOpportunities.removeAll { $0.id == opportunity.id }
            
            // Update revenue metrics optimistically
            totalRevenue += opportunity.potentialRevenue * 0.5 // Assume 50% of potential is realized
            
        } catch {
            handleError(error)
        }
    }
    
    func applyRecommendation(_ recommendation: AIRecommendation) async {
        // Simulate applying the recommendation
        do {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            
            // Remove the applied recommendation
            aiRecommendations.removeAll { $0.id == recommendation.id }
            
            // Generate a new recommendation based on the applied one
            let newRecommendation = generateFollowUpRecommendation(for: recommendation)
            if let newRec = newRecommendation {
                aiRecommendations.insert(newRec, at: 0)
            }
            
        } catch {
            handleError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateRecommendationTitle(for insight: ActionableInsight) -> String {
        switch insight.category {
        case .pricing: return "Optimize Pricing Strategy"
        case .scheduling: return "Improve Schedule Efficiency"
        case .marketing: return "Enhance Marketing Campaign"
        case .operations: return "Streamline Operations"
        case .customer: return "Improve Customer Experience"
        }
    }
    
    private func mapInsightPriority(_ confidence: Double) -> AIRecommendation.Priority {
        switch confidence {
        case 0.9...1.0: return .critical
        case 0.7..<0.9: return .high
        case 0.5..<0.7: return .medium
        default: return .low
        }
    }
    
    private func getRecommendationIcon(for category: ActionableInsight.InsightCategory) -> String {
        switch category {
        case .pricing: return "dollarsign.circle"
        case .scheduling: return "calendar.circle"
        case .marketing: return "megaphone.circle"
        case .operations: return "gear.circle"
        case .customer: return "person.circle"
        }
    }
    
    private func generateFollowUpRecommendation(for applied: AIRecommendation) -> AIRecommendation? {
        let followUpTitles = [
            "Monitor Impact of Recent Changes",
            "Analyze Customer Feedback",
            "Review Performance Metrics",
            "Consider Additional Optimizations"
        ]
        
        guard let title = followUpTitles.randomElement() else { return nil }
        
        return AIRecommendation(
            title: title,
            description: "Based on your recent implementation of '\(applied.title)', consider monitoring the results and making further adjustments.",
            category: applied.category,
            priority: .medium,
            expectedImpact: "5-10% improvement",
            icon: "magnifyingglass.circle"
        )
    }
    
    // MARK: - Real-time Updates
    
    private func setupRealTimeUpdates() {
        realTimeTimer = Timer.scheduledTimer(withTimeInterval: realTimeUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshRealTimeData()
            }
        }
        isRealTimeConnected = true
    }
    
    private func stopRealTimeUpdates() {
        realTimeTimer?.invalidate()
        realTimeTimer = nil
        isRealTimeConnected = false
    }
    
    private func refreshRealTimeData() async {
        guard let tenantId = currentTenantId else { return }
        
        do {
            // Update key metrics in real-time
            if !revenueData.isEmpty {
                let latestData = revenueData.last!
                let variance = Double.random(in: -0.05...0.05)
                let updatedRevenue = latestData.totalRevenue * (1.0 + variance)
                
                // Update the latest data point
                if var lastPoint = revenueData.last {
                    lastPoint = RevenueDataPoint(
                        date: lastPoint.date,
                        totalRevenue: updatedRevenue,
                        revenuePerBooking: lastPoint.revenuePerBooking,
                        revenuePerMember: lastPoint.revenuePerMember,
                        grossRevenue: lastPoint.grossRevenue,
                        forecast: lastPoint.forecast
                    )
                    revenueData[revenueData.count - 1] = lastPoint
                    totalRevenue = updatedRevenue
                }
            }
        } catch {
            print("Failed to refresh real-time revenue data: \(error)")
        }
    }
    
    // MARK: - Analytics Subscriptions
    
    private func setupAnalyticsSubscriptions() {
        guard let analyticsService = analyticsService else { return }
        
        // Subscribe to revenue updates
        analyticsService.revenuePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] revenue in
                if let revenue = revenue {
                    self?.updateRevenueMetricsFromAnalytics(revenue)
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to predictive analytics updates
        analyticsService.predictivePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] predictive in
                if let predictive = predictive {
                    self?.updatePredictiveData(predictive)
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateRevenueMetricsFromAnalytics(_ revenue: RevenueMetrics) {
        totalRevenue = revenue.totalRevenue
        revenuePerBooking = revenue.averageRevenuePerBooking
        revenueGrowthRate = revenue.revenueGrowth / 100.0
        revenueChange = revenue.revenueGrowth
    }
    
    private func updatePredictiveData(_ predictive: PredictiveAnalytics) {
        // Update pricing recommendations
        pricingRecommendations = predictive.optimalPricing
        
        // Update demand forecast
        demandForecast = predictive.demandPredictions.map { prediction in
            DemandForecastPoint(
                date: prediction.date,
                predictedDemand: prediction.predictedDemand,
                confidence: predictive.confidence
            )
        }
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error) {
        print("Revenue optimization error: \(error)")
        // In a real implementation, you would show user-friendly error messages
        // and implement retry logic
    }
    
    // MARK: - Export and Reporting
    
    func exportRevenueData(format: ExportFormat) async -> URL? {
        // In a real implementation, this would generate export files
        return nil
    }
    
    func generateRevenueReport(type: ReportType) async -> AnalyticsReport? {
        guard let analyticsService = analyticsService,
              let tenantId = currentTenantId else { return nil }
        
        do {
            return try await analyticsService.generateReport(
                for: tenantId,
                type: type,
                period: .month
            )
        } catch {
            handleError(error)
            return nil
        }
    }
}

// MARK: - Extensions

extension RevenueTimeframe {
    var analyticsPeriod: AnalyticsPeriod {
        switch self {
        case .week: return .week
        case .month: return .month
        case .quarter: return .quarter
        case .year: return .year
        }
    }
    
    var dataPointConfiguration: (count: Int, component: Calendar.Component) {
        switch self {
        case .week: return (7, .day)
        case .month: return (30, .day)
        case .quarter: return (12, .weekOfYear)
        case .year: return (12, .month)
        }
    }
}

// MARK: - Error Types

enum RevenueOptimizationError: LocalizedError {
    case serviceNotAvailable
    case invalidTenantId
    case dataLoadingFailed(Error)
    case optimizationFailed(Error)
    case recommendationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .serviceNotAvailable:
            return "Analytics service is not available"
        case .invalidTenantId:
            return "Invalid tenant ID"
        case .dataLoadingFailed(let error):
            return "Failed to load revenue data: \(error.localizedDescription)"
        case .optimizationFailed(let error):
            return "Revenue optimization failed: \(error.localizedDescription)"
        case .recommendationFailed(let error):
            return "Failed to generate recommendations: \(error.localizedDescription)"
        }
    }
}

// MARK: - Mock Data Generation

extension RevenueOptimizationViewModel {
    private func generateMockPricingRecommendations() -> [PricingRecommendation] {
        let timeSlots = ["6:00 AM", "8:00 AM", "10:00 AM", "12:00 PM", "2:00 PM", "4:00 PM"]
        
        return timeSlots.map { timeSlot in
            let currentPrice = Double.random(in: 75...150)
            let priceAdjustment = Double.random(in: -20...30)
            let recommendedPrice = currentPrice + priceAdjustment
            let revenueLift = (priceAdjustment / currentPrice) * 100
            
            return PricingRecommendation(
                timeSlot: timeSlot,
                currentPrice: currentPrice,
                recommendedPrice: recommendedPrice,
                expectedRevenueLift: revenueLift,
                rationale: generatePricingRationale(for: timeSlot, adjustment: priceAdjustment)
            )
        }
    }
    
    private func generatePricingRationale(for timeSlot: String, adjustment: Double) -> String {
        if adjustment > 0 {
            return "High demand period - increase pricing to maximize revenue"
        } else if adjustment < -10 {
            return "Low demand period - reduce pricing to increase bookings"
        } else {
            return "Optimal pricing for current demand levels"
        }
    }
}