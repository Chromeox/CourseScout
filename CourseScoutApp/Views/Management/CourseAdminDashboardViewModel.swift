import Foundation
import Combine
import SwiftUI

// MARK: - Course Admin Dashboard ViewModel

@MainActor
class CourseAdminDashboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var todayRevenue: Double = 0
    @Published var activeBookings: Int = 0
    @Published var courseUtilization: Double = 0
    @Published var memberSatisfaction: Double = 0
    
    // MARK: - Trend Data
    @Published var revenueTrend: TrendDirection? = nil
    @Published var bookingsTrend: TrendDirection? = nil
    @Published var utilizationTrend: TrendDirection? = nil
    @Published var satisfactionTrend: TrendDirection? = nil
    
    // MARK: - Dashboard State
    @Published var overallHealth: B2BAnalyticsSummary.HealthStatus? = nil
    @Published var criticalAlerts: [AnalyticsAlert] = []
    @Published var liveBookings: [LiveBooking] = []
    @Published var recentActivities: [RecentActivity] = []
    @Published var revenueData: [RevenueDataPoint] = []
    
    // MARK: - Performance Metrics
    @Published var operationalEfficiency: Double = 0
    @Published var staffProductivity: Double = 0
    @Published var equipmentStatus: Double = 0
    @Published var weatherImpact: Double = 0
    
    // MARK: - Loading States
    @Published var isLoading = false
    @Published var lastUpdated: Date? = nil
    
    // MARK: - Private Properties
    private var analyticsService: B2BAnalyticsServiceProtocol?
    private var tenantService: TenantConfigurationServiceProtocol?
    private var currentTenantId: String?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Real-time Update Timer
    private var realTimeTimer: Timer?
    
    // MARK: - Initialization
    
    init() {
        setupRealtimeUpdates()
    }
    
    deinit {
        stopRealTimeUpdates()
    }
    
    // MARK: - Configuration
    
    func configure(for tenantId: String) {
        currentTenantId = tenantId
        analyticsService = ServiceContainer.shared.resolve(B2BAnalyticsServiceProtocol.self)
        tenantService = ServiceContainer.shared.resolve(TenantConfigurationServiceProtocol.self)
        
        setupAnalyticsSubscriptions()
    }
    
    // MARK: - Data Loading
    
    func loadDashboardData(tenantId: String, timeframe: TimeFrameOption) async {
        guard !isLoading else { return }
        
        isLoading = true
        currentTenantId = tenantId
        
        do {
            async let summaryTask = loadAnalyticsSummary(tenantId: tenantId, period: timeframe.analyticsPeriod)
            async let revenueTask = loadRevenueMetrics(tenantId: tenantId, period: timeframe.analyticsPeriod)
            async let behaviorTask = loadPlayerBehaviorMetrics(tenantId: tenantId, period: timeframe.analyticsPeriod)
            async let liveDataTask = loadLiveData(tenantId: tenantId)
            async let activitiesTask = loadRecentActivities(tenantId: tenantId)
            
            let (summary, revenue, behavior, liveData, activities) = try await (
                summaryTask,
                revenueTask,
                behaviorTask,
                liveDataTask,
                activitiesTask
            )
            
            // Update UI with loaded data
            updateKPIs(summary: summary, revenue: revenue, behavior: behavior)
            updateDashboardState(summary: summary, liveData: liveData, activities: activities)
            generateRevenueChartData(revenue: revenue, period: timeframe.analyticsPeriod)
            updatePerformanceMetrics(summary: summary, behavior: behavior)
            
            lastUpdated = Date()
            
        } catch {
            handleLoadingError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Private Data Loading Methods
    
    private func loadAnalyticsSummary(tenantId: String, period: AnalyticsPeriod) async throws -> B2BAnalyticsSummary {
        guard let analyticsService = analyticsService else {
            throw DashboardError.serviceNotAvailable
        }
        
        return try await analyticsService.loadAnalyticsSummary(for: tenantId, period: period)
    }
    
    private func loadRevenueMetrics(tenantId: String, period: AnalyticsPeriod) async throws -> RevenueMetrics {
        guard let analyticsService = analyticsService else {
            throw DashboardError.serviceNotAvailable
        }
        
        return try await analyticsService.loadRevenueMetrics(for: tenantId, period: period)
    }
    
    private func loadPlayerBehaviorMetrics(tenantId: String, period: AnalyticsPeriod) async throws -> PlayerBehaviorMetrics {
        guard let analyticsService = analyticsService else {
            throw DashboardError.serviceNotAvailable
        }
        
        return try await analyticsService.loadPlayerBehaviorMetrics(for: tenantId, period: period)
    }
    
    private func loadLiveData(tenantId: String) async throws -> RealTimeStats {
        guard let analyticsService = analyticsService else {
            throw DashboardError.serviceNotAvailable
        }
        
        return try await analyticsService.getRealTimeStats(for: tenantId)
    }
    
    private func loadRecentActivities(tenantId: String) async throws -> [RecentActivity] {
        // In a real implementation, this would fetch from a dedicated service
        // For now, generate mock activities based on current data
        return generateMockRecentActivities()
    }
    
    // MARK: - UI State Updates
    
    private func updateKPIs(summary: B2BAnalyticsSummary, revenue: RevenueMetrics, behavior: PlayerBehaviorMetrics) {
        todayRevenue = summary.totalRevenue
        activeBookings = summary.totalBookings
        courseUtilization = calculateCourseUtilization(behavior: behavior)
        memberSatisfaction = summary.averageRating
        
        // Calculate trends
        revenueTrend = calculateTrend(current: summary.totalRevenue, growth: summary.revenueGrowth)
        bookingsTrend = calculateTrend(current: Double(summary.totalBookings), growth: summary.bookingGrowth)
        utilizationTrend = calculateTrend(current: courseUtilization, growth: 5.2) // Mock data
        satisfactionTrend = calculateTrend(current: summary.averageRating, growth: 2.1) // Mock data
    }
    
    private func updateDashboardState(summary: B2BAnalyticsSummary, liveData: RealTimeStats, activities: [RecentActivity]) {
        overallHealth = summary.healthStatus
        criticalAlerts = summary.criticalAlerts
        recentActivities = activities
        
        // Generate live bookings from real-time stats
        liveBookings = generateLiveBookings(from: liveData)
    }
    
    private func generateRevenueChartData(revenue: RevenueMetrics, period: AnalyticsPeriod) {
        let calendar = Calendar.current
        let endDate = Date()
        
        let dayCount = period == .day ? 7 : (period == .week ? 4 : 12)
        let componentToAdd: Calendar.Component = period == .day ? .day : (period == .week ? .weekOfYear : .month)
        
        revenueData = (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: componentToAdd, value: -offset, to: endDate) else { return nil }
            
            // Generate revenue data based on historical patterns
            let baseRevenue = revenue.totalRevenue / Double(dayCount)
            let variance = Double.random(in: -0.3...0.3)
            let dayRevenue = baseRevenue * (1.0 + variance)
            
            return RevenueDataPoint(date: date, revenue: max(0, dayRevenue))
        }.reversed()
    }
    
    private func updatePerformanceMetrics(summary: B2BAnalyticsSummary, behavior: PlayerBehaviorMetrics) {
        // Calculate performance metrics based on available data
        operationalEfficiency = calculateOperationalEfficiency(summary: summary, behavior: behavior)
        staffProductivity = calculateStaffProductivity(summary: summary)
        equipmentStatus = calculateEquipmentStatus()
        weatherImpact = calculateWeatherImpact()
    }
    
    // MARK: - Calculation Methods
    
    private func calculateCourseUtilization(behavior: PlayerBehaviorMetrics) -> Double {
        // Calculate utilization based on bookings vs capacity
        let totalCapacity = 18 * 4 * 12 // 18 holes, 4 groups per hour, 12 hours
        let actualBookings = behavior.totalUsers
        return min(1.0, Double(actualBookings) / Double(totalCapacity))
    }
    
    private func calculateTrend(current: Double, growth: Double) -> TrendDirection {
        if abs(growth) < 1.0 {
            return .neutral
        } else if growth > 0 {
            return .up(growth)
        } else {
            return .down(abs(growth))
        }
    }
    
    private func calculateOperationalEfficiency(summary: B2BAnalyticsSummary, behavior: PlayerBehaviorMetrics) -> Double {
        // Composite score based on multiple factors
        let revenueScore = min(1.0, summary.totalRevenue / 10000) // Normalized to $10k daily
        let utilizationScore = courseUtilization
        let satisfactionScore = summary.averageRating / 5.0
        
        return (revenueScore + utilizationScore + satisfactionScore) / 3.0
    }
    
    private func calculateStaffProductivity(summary: B2BAnalyticsSummary) -> Double {
        // Mock calculation - in real app would use actual staff metrics
        let baseProductivity = 0.75
        let revenueBonus = min(0.25, summary.revenueGrowth / 100.0)
        return min(1.0, baseProductivity + revenueBonus)
    }
    
    private func calculateEquipmentStatus() -> Double {
        // Mock calculation - in real app would integrate with equipment monitoring
        return Double.random(in: 0.85...0.98)
    }
    
    private func calculateWeatherImpact() -> Double {
        // Mock calculation - in real app would use weather service
        return Double.random(in: 0.05...0.25)
    }
    
    // MARK: - Mock Data Generation
    
    private func generateLiveBookings(from liveData: RealTimeStats) -> [LiveBooking] {
        let playerNames = ["John Smith", "Sarah Johnson", "Mike Wilson", "Emily Brown", "David Lee", "Jennifer Davis"]
        let currentTime = Date()
        
        return (0..<min(liveData.currentBookings, 8)).map { index in
            let teeTime = Calendar.current.date(byAdding: .hour, value: -index, to: currentTime) ?? currentTime
            let currentHole = Int.random(in: 1...18)
            let status: BookingStatus = currentHole < 18 ? .onCourse : .finished
            
            return LiveBooking(
                playerName: playerNames[index % playerNames.count],
                teeTime: teeTime,
                currentHole: currentHole,
                status: status
            )
        }
    }
    
    private func generateMockRecentActivities() -> [RecentActivity] {
        let activities = [
            ("New booking confirmed", "calendar.badge.plus", Color.green),
            ("Member checked in", "person.crop.circle.badge.checkmark", Color.blue),
            ("Weather alert resolved", "sun.max", Color.orange),
            ("Course maintenance completed", "wrench.fill", Color.purple),
            ("Staff shift change", "person.2.fill", Color.gray),
            ("Payment processed", "creditcard.fill", Color.green)
        ]
        
        let currentTime = Date()
        
        return activities.enumerated().map { index, activity in
            let timestamp = Calendar.current.date(byAdding: .minute, value: -(index * 15), to: currentTime) ?? currentTime
            
            return RecentActivity(
                description: activity.0,
                timestamp: timestamp,
                icon: activity.1,
                color: activity.2
            )
        }
    }
    
    // MARK: - Real-time Updates
    
    private func setupRealtimeUpdates() {
        realTimeTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshRealTimeData()
            }
        }
    }
    
    private func stopRealTimeUpdates() {
        realTimeTimer?.invalidate()
        realTimeTimer = nil
    }
    
    private func refreshRealTimeData() async {
        guard let tenantId = currentTenantId else { return }
        
        do {
            let liveData = try await loadLiveData(tenantId: tenantId)
            liveBookings = generateLiveBookings(from: liveData)
            
            // Update recent activities with new data
            let newActivities = generateMockRecentActivities()
            if !newActivities.isEmpty {
                recentActivities = newActivities
            }
            
            lastUpdated = Date()
        } catch {
            print("Failed to refresh real-time data: \(error)")
        }
    }
    
    // MARK: - Analytics Subscriptions
    
    private func setupAnalyticsSubscriptions() {
        guard let analyticsService = analyticsService else { return }
        
        // Subscribe to alerts updates
        analyticsService.alertsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alerts in
                self?.criticalAlerts = alerts.filter { $0.severity == .critical }
            }
            .store(in: &cancellables)
        
        // Subscribe to summary updates
        analyticsService.summaryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                if let summary = summary {
                    self?.overallHealth = summary.healthStatus
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Error Handling
    
    private func handleLoadingError(_ error: Error) {
        print("Dashboard loading error: \(error)")
        // In a real app, you would show user-friendly error messages
        // and possibly retry logic
    }
    
    // MARK: - Public Methods
    
    func refreshData() async {
        guard let tenantId = currentTenantId else { return }
        await loadDashboardData(tenantId: tenantId, timeframe: .today)
    }
    
    func acknowledgeAlert(_ alertId: String) async {
        guard let analyticsService = analyticsService else { return }
        
        do {
            try await analyticsService.acknowledgeAlert(alertId: alertId)
            criticalAlerts.removeAll { $0.id == alertId }
        } catch {
            print("Failed to acknowledge alert: \(error)")
        }
    }
    
    func exportDashboardData(format: ExportFormat, period: AnalyticsPeriod) async -> AnalyticsExport? {
        guard let analyticsService = analyticsService,
              let tenantId = currentTenantId else { return nil }
        
        do {
            return try await analyticsService.exportAnalytics(
                for: tenantId,
                format: format,
                period: period
            )
        } catch {
            print("Failed to export dashboard data: \(error)")
            return nil
        }
    }
}

// MARK: - Dashboard Errors

enum DashboardError: LocalizedError {
    case serviceNotAvailable
    case invalidTenantId
    case dataLoadingFailed(Error)
    case exportFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .serviceNotAvailable:
            return "Analytics service is not available"
        case .invalidTenantId:
            return "Invalid tenant ID provided"
        case .dataLoadingFailed(let error):
            return "Failed to load dashboard data: \(error.localizedDescription)"
        case .exportFailed(let error):
            return "Failed to export data: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting Extensions

extension B2BAnalyticsSummary.HealthStatus {
    var icon: String {
        switch self {
        case .excellent: return "checkmark.circle.fill"
        case .good: return "checkmark.circle"
        case .fair: return "exclamationmark.triangle"
        case .poor: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }
    
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

extension AnalyticsAlert.AlertSeverity {
    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "exclamationmark.circle"
        case .critical: return "exclamationmark.octagon"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .yellow
        case .error: return .orange
        case .critical: return .red
        }
    }
}