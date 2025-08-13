import SwiftUI
import Combine
import Charts

// MARK: - Course Admin Dashboard View

struct CourseAdminDashboard: View {
    
    // MARK: - Dependencies
    @TenantInjected private var tenantService: TenantConfigurationServiceProtocol
    @TenantInjected private var analyticsService: B2BAnalyticsServiceProtocol
    @ServiceInjected(HapticFeedbackServiceProtocol.self) private var hapticService
    
    // MARK: - State Management
    @StateObject private var viewModel = CourseAdminDashboardViewModel()
    @State private var selectedTimeframe: TimeFrameOption = .today
    @State private var isRefreshing = false
    @State private var showingExportOptions = false
    @State private var showingAlertDetail: AnalyticsAlert?
    @State private var animateMetrics = false
    
    // MARK: - Current Tenant Context
    @State private var currentTenant: TenantConfiguration?
    private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // MARK: - Dashboard Header
                    dashboardHeader
                    
                    // MARK: - Critical Alerts Banner
                    if !viewModel.criticalAlerts.isEmpty {
                        criticalAlertsSection
                    }
                    
                    // MARK: - Key Performance Indicators
                    kpiSection
                    
                    // MARK: - Revenue Analytics Chart
                    revenueChartSection
                    
                    // MARK: - Live Bookings Overview
                    liveBookingsSection
                    
                    // MARK: - Quick Actions Grid
                    quickActionsSection
                    
                    // MARK: - Performance Summary Cards
                    performanceCardsSection
                    
                    // MARK: - Recent Activity Feed
                    recentActivitySection
                }
                .padding(.horizontal)
                .refreshable {
                    await refreshDashboard()
                }
            }
            .navigationTitle("Course Admin")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Time Frame Selector
                    Menu {
                        ForEach(TimeFrameOption.allCases, id: \.self) { option in
                            Button(option.displayName) {
                                selectedTimeframe = option
                                hapticService.selectionChanged()
                                Task { await loadDashboardData() }
                            }
                        }
                    } label: {
                        Label(selectedTimeframe.displayName, systemImage: "calendar")
                            .foregroundColor(tenantTheme.primarySwiftUIColor)
                    }
                    
                    // Export Button
                    Button {
                        showingExportOptions = true
                        hapticService.buttonPressed()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(tenantTheme.primarySwiftUIColor)
                    }
                    
                    // Refresh Button
                    Button {
                        hapticService.buttonPressed()
                        Task { await refreshDashboard() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(tenantTheme.primarySwiftUIColor)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(.linear(duration: 1).repeatCount(isRefreshing ? 100 : 0), value: isRefreshing)
                    }
                }
            }
        }
        .onAppear {
            setupTenantContext()
            Task { await loadDashboardData() }
        }
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsSheet(
                tenantId: currentTenant?.id ?? "",
                timeframe: selectedTimeframe,
                analyticsService: analyticsService
            )
        }
        .sheet(item: $showingAlertDetail) { alert in
            AlertDetailSheet(alert: alert, analyticsService: analyticsService)
        }
        .animation(.easeInOut(duration: 0.3), value: animateMetrics)
    }
    
    // MARK: - Dashboard Header
    
    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentTenant?.displayName ?? "Golf Course Admin")
                        .font(.title2.weight(.bold))
                        .foregroundColor(tenantTheme.textSwiftUIColor)
                    
                    Text("Executive Dashboard")
                        .font(.subheadline)
                        .foregroundColor(tenantTheme.textSwiftUIColor.opacity(0.7))
                }
                
                Spacer()
                
                // Health Status Indicator
                if let health = viewModel.overallHealth {
                    HealthStatusBadge(health: health)
                }
            }
            
            // Last Updated Indicator
            if let lastUpdated = viewModel.lastUpdated {
                Text("Last updated: \(lastUpdated, formatter: DateFormatter.timeOnly)")
                    .font(.caption)
                    .foregroundColor(tenantTheme.textSwiftUIColor.opacity(0.6))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                .fill(tenantTheme.surfaceSwiftUIColor)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Critical Alerts Section
    
    private var criticalAlertsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Critical Alerts")
                .font(.headline)
                .foregroundColor(.red)
            
            ForEach(viewModel.criticalAlerts.prefix(3), id: \.id) { alert in
                AlertCard(alert: alert) {
                    showingAlertDetail = alert
                }
            }
            
            if viewModel.criticalAlerts.count > 3 {
                Button("View All \(viewModel.criticalAlerts.count) Alerts") {
                    // Navigate to full alerts view
                }
                .foregroundColor(tenantTheme.primarySwiftUIColor)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - KPI Section
    
    private var kpiSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            KPICard(
                title: "Today's Revenue",
                value: viewModel.todayRevenue,
                formatter: .currency,
                trend: viewModel.revenueTrend,
                icon: "dollarsign.circle.fill",
                color: tenantTheme.primarySwiftUIColor
            )
            
            KPICard(
                title: "Active Bookings",
                value: Double(viewModel.activeBookings),
                formatter: .number,
                trend: viewModel.bookingsTrend,
                icon: "calendar.circle.fill",
                color: .blue
            )
            
            KPICard(
                title: "Course Utilization",
                value: viewModel.courseUtilization,
                formatter: .percentage,
                trend: viewModel.utilizationTrend,
                icon: "chart.line.uptrend.xyaxis.circle.fill",
                color: .green
            )
            
            KPICard(
                title: "Member Satisfaction",
                value: viewModel.memberSatisfaction,
                formatter: .rating,
                trend: viewModel.satisfactionTrend,
                icon: "star.circle.fill",
                color: .orange
            )
        }
        .scaleEffect(animateMetrics ? 1.0 : 0.95)
    }
    
    // MARK: - Revenue Chart Section
    
    private var revenueChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revenue Trends")
                .font(.headline)
                .foregroundColor(tenantTheme.textSwiftUIColor)
            
            Chart(viewModel.revenueData) { dataPoint in
                LineMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Revenue", dataPoint.revenue)
                )
                .foregroundStyle(tenantTheme.primarySwiftUIColor.gradient)
                .lineStyle(StrokeStyle(lineWidth: 3))
                
                AreaMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Revenue", dataPoint.revenue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [tenantTheme.primarySwiftUIColor.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .currency(code: "USD"))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                .fill(tenantTheme.surfaceSwiftUIColor)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Live Bookings Section
    
    private var liveBookingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live Bookings")
                    .font(.headline)
                    .foregroundColor(tenantTheme.textSwiftUIColor)
                
                Spacer()
                
                NavigationLink(destination: BookingManagementView()) {
                    Text("Manage All")
                        .font(.caption)
                        .foregroundColor(tenantTheme.primarySwiftUIColor)
                }
            }
            
            if viewModel.liveBookings.isEmpty {
                EmptyStateView(
                    title: "No Active Bookings",
                    subtitle: "All bookings for today have been completed",
                    systemImage: "checkmark.circle"
                )
                .frame(height: 120)
            } else {
                ForEach(viewModel.liveBookings.prefix(5), id: \.id) { booking in
                    LiveBookingCard(booking: booking)
                }
                
                if viewModel.liveBookings.count > 5 {
                    Button("View All \(viewModel.liveBookings.count) Bookings") {
                        // Navigate to full booking management
                    }
                    .foregroundColor(tenantTheme.primarySwiftUIColor)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                .fill(tenantTheme.surfaceSwiftUIColor)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(tenantTheme.textSwiftUIColor)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                QuickActionButton(
                    title: "New Booking",
                    icon: "plus.circle.fill",
                    color: tenantTheme.primarySwiftUIColor
                ) {
                    // Navigate to booking creation
                }
                
                QuickActionButton(
                    title: "Member Check-in",
                    icon: "person.badge.plus",
                    color: .blue
                ) {
                    // Navigate to member check-in
                }
                
                QuickActionButton(
                    title: "Course Status",
                    icon: "flag.circle.fill",
                    color: .green
                ) {
                    // Navigate to course status management
                }
                
                QuickActionButton(
                    title: "Weather Alert",
                    icon: "cloud.rain.circle.fill",
                    color: .orange
                ) {
                    // Handle weather alert
                }
                
                QuickActionButton(
                    title: "Staff Schedule",
                    icon: "person.3.fill",
                    color: .purple
                ) {
                    // Navigate to staff scheduling
                }
                
                QuickActionButton(
                    title: "Reports",
                    icon: "chart.bar.doc.horizontal.fill",
                    color: .gray
                ) {
                    showingExportOptions = true
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                .fill(tenantTheme.surfaceSwiftUIColor)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Performance Cards Section
    
    private var performanceCardsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            PerformanceCard(
                title: "Operational Efficiency",
                value: viewModel.operationalEfficiency,
                target: 0.85,
                icon: "gear.circle.fill",
                color: .blue
            )
            
            PerformanceCard(
                title: "Staff Productivity",
                value: viewModel.staffProductivity,
                target: 0.90,
                icon: "person.crop.circle.fill",
                color: .green
            )
            
            PerformanceCard(
                title: "Equipment Status",
                value: viewModel.equipmentStatus,
                target: 0.95,
                icon: "wrench.adjustable.circle.fill",
                color: .orange
            )
            
            PerformanceCard(
                title: "Weather Impact",
                value: viewModel.weatherImpact,
                target: 0.20,
                icon: "cloud.sun.circle.fill",
                color: .purple,
                isInverted: true
            )
        }
    }
    
    // MARK: - Recent Activity Section
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .foregroundColor(tenantTheme.textSwiftUIColor)
            
            if viewModel.recentActivities.isEmpty {
                EmptyStateView(
                    title: "No Recent Activity",
                    subtitle: "Activity will appear here as events occur",
                    systemImage: "clock.arrow.circlepath"
                )
                .frame(height: 100)
            } else {
                ForEach(viewModel.recentActivities.prefix(10), id: \.id) { activity in
                    ActivityCard(activity: activity)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                .fill(tenantTheme.surfaceSwiftUIColor)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Helper Views
    
    private var tenantTheme: WhiteLabelTheme {
        currentTenant?.theme ?? .golfCourseDefault
    }
    
    // MARK: - Methods
    
    private func setupTenantContext() {
        tenantService.currentTenantPublisher
            .receive(on: DispatchQueue.main)
            .sink { tenant in
                currentTenant = tenant
                if let tenant = tenant {
                    viewModel.configure(for: tenant.id)
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadDashboardData() async {
        guard let tenantId = currentTenant?.id else { return }
        
        await MainActor.run {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                animateMetrics = true
            }
        }
        
        await viewModel.loadDashboardData(
            tenantId: tenantId,
            timeframe: selectedTimeframe
        )
        
        await MainActor.run {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                animateMetrics = false
            }
        }
    }
    
    private func refreshDashboard() async {
        await MainActor.run {
            isRefreshing = true
        }
        
        await loadDashboardData()
        
        await MainActor.run {
            isRefreshing = false
        }
        
        hapticService.notificationOccurred(.success)
    }
}

// MARK: - Supporting Views

struct HealthStatusBadge: View {
    let health: B2BAnalyticsSummary.HealthStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: health.icon)
                .font(.caption)
            Text(health.displayName)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(health.color.opacity(0.2))
        )
        .foregroundColor(health.color)
    }
}

struct AlertCard: View {
    let alert: AnalyticsAlert
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: alert.severity.icon)
                    .foregroundColor(alert.severity.color)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Text(alert.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct KPICard: View {
    let title: String
    let value: Double
    let formatter: KPIFormatter
    let trend: TrendDirection?
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Spacer()
                
                if let trend = trend {
                    TrendIndicator(trend: trend)
                }
            }
            
            Text(formatter.format(value))
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

struct TrendIndicator: View {
    let trend: TrendDirection
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: trend.icon)
                .font(.caption)
            Text(trend.displayText)
                .font(.caption.weight(.medium))
        }
        .foregroundColor(trend.color)
    }
}

struct PerformanceCard: View {
    let title: String
    let value: Double
    let target: Double
    let icon: String
    let color: Color
    let isInverted: Bool
    
    init(title: String, value: Double, target: Double, icon: String, color: Color, isInverted: Bool = false) {
        self.title = title
        self.value = value
        self.target = target
        self.icon = icon
        self.color = color
        self.isInverted = isInverted
    }
    
    private var performanceScore: Double {
        isInverted ? (1.0 - value) / (1.0 - target) : value / target
    }
    
    private var performanceColor: Color {
        let score = performanceScore
        if score >= 1.0 { return .green }
        else if score >= 0.8 { return .blue }
        else if score >= 0.6 { return .orange }
        else { return .red }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Spacer()
                
                Text("\(Int(performanceScore * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundColor(performanceColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: min(performanceScore, 1.0))
                    .tint(performanceColor)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LiveBookingCard: View {
    let booking: LiveBooking
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(booking.playerName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                
                Text("Tee Time: \(booking.teeTime, formatter: DateFormatter.timeOnly)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                StatusBadge(status: booking.status)
                
                Text("Hole \(booking.currentHole)/18")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct StatusBadge: View {
    let status: BookingStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(status.color.opacity(0.2))
            )
            .foregroundColor(status.color)
    }
}

struct ActivityCard: View {
    let activity: RecentActivity
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.icon)
                .font(.subheadline)
                .foregroundColor(activity.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.description)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Text(activity.timestamp, formatter: DateFormatter.timeAgo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Supporting Types and Extensions

enum TimeFrameOption: String, CaseIterable {
    case today = "today"
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    
    var displayName: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .quarter: return "This Quarter"
        }
    }
    
    var analyticsPeriod: AnalyticsPeriod {
        switch self {
        case .today: return .day
        case .week: return .week
        case .month: return .month
        case .quarter: return .quarter
        }
    }
}

enum KPIFormatter {
    case currency
    case number
    case percentage
    case rating
    
    func format(_ value: Double) -> String {
        switch self {
        case .currency:
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            return formatter.string(from: NSNumber(value: value)) ?? "$0"
        case .number:
            return String(format: "%.0f", value)
        case .percentage:
            return String(format: "%.1f%%", value * 100)
        case .rating:
            return String(format: "%.1f ⭐", value)
        }
    }
}

enum TrendDirection {
    case up(Double)
    case down(Double)
    case neutral
    
    var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .neutral: return "minus"
        }
    }
    
    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .neutral: return .gray
        }
    }
    
    var displayText: String {
        switch self {
        case .up(let value): return "+\(String(format: "%.1f", value))%"
        case .down(let value): return "-\(String(format: "%.1f", value))%"
        case .neutral: return "0%"
        }
    }
}

// MARK: - Data Models

struct LiveBooking: Identifiable {
    let id = UUID()
    let playerName: String
    let teeTime: Date
    let currentHole: Int
    let status: BookingStatus
}

enum BookingStatus {
    case checkedIn
    case onCourse
    case finished
    case cancelled
    
    var displayName: String {
        switch self {
        case .checkedIn: return "Checked In"
        case .onCourse: return "On Course"
        case .finished: return "Finished"
        case .cancelled: return "Cancelled"
        }
    }
    
    var color: Color {
        switch self {
        case .checkedIn: return .blue
        case .onCourse: return .green
        case .finished: return .gray
        case .cancelled: return .red
        }
    }
}

struct RecentActivity: Identifiable {
    let id = UUID()
    let description: String
    let timestamp: Date
    let icon: String
    let color: Color
}

struct RevenueDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let revenue: Double
}

// MARK: - Extensions

extension DateFormatter {
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let timeAgo: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Property Wrapper for Tenant Injection

@propertyWrapper
struct TenantInjected<T> {
    private let serviceType: T.Type
    
    init(_ serviceType: T.Type) {
        self.serviceType = serviceType
    }
    
    var wrappedValue: T {
        ServiceContainer.shared.resolve(serviceType)
    }
}