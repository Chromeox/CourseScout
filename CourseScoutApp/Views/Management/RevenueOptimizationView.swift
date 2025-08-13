import SwiftUI
import Combine
import Charts

// MARK: - Revenue Optimization View

struct RevenueOptimizationView: View {
    
    // MARK: - Dependencies
    @TenantInjected private var tenantService: TenantConfigurationServiceProtocol
    @TenantInjected private var analyticsService: B2BAnalyticsServiceProtocol
    @ServiceInjected(HapticFeedbackServiceProtocol.self) private var hapticService
    
    // MARK: - State Management
    @StateObject private var viewModel = RevenueOptimizationViewModel()
    @State private var selectedTimeframe: RevenueTimeframe = .month
    @State private var selectedMetric: RevenueMetric = .total
    @State private var showingOptimizationDetails = false
    @State private var showingPricingStrategy = false
    @State private var showingRecommendationDetail: RevenueRecommendation?
    @State private var selectedRecommendation: RevenueRecommendation?
    
    // MARK: - Current Tenant Context
    @State private var currentTenant: TenantConfiguration?
    private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // MARK: - Header Controls
                    headerControlsSection
                    
                    // MARK: - Key Revenue Metrics
                    revenueMetricsSection
                    
                    // MARK: - Revenue Analytics Chart
                    revenueAnalyticsChart
                    
                    // MARK: - Pricing Optimization Cards
                    pricingOptimizationSection
                    
                    // MARK: - Demand Forecasting
                    demandForecastingSection
                    
                    // MARK: - Revenue Opportunities
                    revenueOpportunitiesSection
                    
                    // MARK: - Performance Recommendations
                    performanceRecommendationsSection
                    
                    // MARK: - Revenue Distribution Analysis
                    revenueDistributionSection
                }
                .padding()
            }
            .navigationTitle("Revenue Optimization")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Optimization Settings
                    Button {
                        showingOptimizationDetails = true
                        hapticService.buttonPressed()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(tenantTheme.primarySwiftUIColor)
                    }
                    
                    // Pricing Strategy
                    Button {
                        showingPricingStrategy = true
                        hapticService.buttonPressed()
                    } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(tenantTheme.primarySwiftUIColor)
                    }
                }
            }
        }
        .onAppear {
            setupTenantContext()
            Task { await loadRevenueData() }
        }
        .refreshable {
            await loadRevenueData()
        }
        .sheet(isPresented: $showingOptimizationDetails) {
            OptimizationSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingPricingStrategy) {
            PricingStrategySheet(
                pricingRecommendations: viewModel.pricingRecommendations,
                tenantTheme: tenantTheme
            )
        }
        .sheet(item: $showingRecommendationDetail) { recommendation in
            RecommendationDetailSheet(
                recommendation: recommendation,
                viewModel: viewModel,
                tenantTheme: tenantTheme
            )
        }
    }
    
    // MARK: - Header Controls Section
    
    private var headerControlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Revenue Performance")
                    .font(.headline)
                    .foregroundColor(tenantTheme.textSwiftUIColor)
                
                Spacer()
                
                // Real-time Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRealTimeConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    
                    Text(viewModel.isRealTimeConnected ? "Live" : "Offline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Timeframe and Metric Selectors
            HStack {
                // Timeframe Picker
                Picker("Timeframe", selection: $selectedTimeframe) {
                    ForEach(RevenueTimeframe.allCases, id: \.self) { timeframe in
                        Text(timeframe.displayName).tag(timeframe)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedTimeframe) { _, _ in
                    hapticService.selectionChanged()
                    Task { await loadRevenueData() }
                }
                
                Spacer()
                
                // Metric Selector
                Menu {
                    ForEach(RevenueMetric.allCases, id: \.self) { metric in
                        Button(metric.displayName) {
                            selectedMetric = metric
                            hapticService.selectionChanged()
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedMetric.displayName)
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption.weight(.medium))
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
    
    // MARK: - Revenue Metrics Section
    
    private var revenueMetricsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            RevenueMetricCard(
                title: "Total Revenue",
                value: viewModel.totalRevenue,
                change: viewModel.revenueChange,
                target: viewModel.revenueTarget,
                icon: "dollarsign.circle.fill",
                color: tenantTheme.primarySwiftUIColor,
                formatter: .currency
            )
            
            RevenueMetricCard(
                title: "Revenue per Booking",
                value: viewModel.revenuePerBooking,
                change: viewModel.revenuePerBookingChange,
                target: viewModel.revenuePerBookingTarget,
                icon: "chart.bar.fill",
                color: .green,
                formatter: .currency
            )
            
            RevenueMetricCard(
                title: "Avg Daily Revenue",
                value: viewModel.avgDailyRevenue,
                change: viewModel.avgDailyRevenueChange,
                target: viewModel.avgDailyRevenueTarget,
                icon: "calendar.badge.clock",
                color: .blue,
                formatter: .currency
            )
            
            RevenueMetricCard(
                title: "Revenue Growth",
                value: viewModel.revenueGrowthRate,
                change: nil,
                target: 0.15, // 15% target growth
                icon: "arrow.up.right.circle.fill",
                color: .orange,
                formatter: .percentage
            )
        }
    }
    
    // MARK: - Revenue Analytics Chart
    
    private var revenueAnalyticsChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Revenue Trends")
                    .font(.headline)
                    .foregroundColor(tenantTheme.textSwiftUIColor)
                
                Spacer()
                
                // Chart Type Toggle
                HStack {
                    ForEach(ChartType.allCases, id: \.self) { type in
                        Button {
                            viewModel.selectedChartType = type
                            hapticService.selectionChanged()
                        } label: {
                            Image(systemName: type.icon)
                                .font(.caption)
                                .foregroundColor(
                                    viewModel.selectedChartType == type ? 
                                    tenantTheme.primarySwiftUIColor : .secondary
                                )
                        }
                    }
                }
            }
            
            Chart(viewModel.revenueData) { dataPoint in
                switch viewModel.selectedChartType {
                case .line:
                    LineMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Revenue", dataPoint.getValue(for: selectedMetric))
                    )
                    .foregroundStyle(tenantTheme.primarySwiftUIColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    
                case .bar:
                    BarMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Revenue", dataPoint.getValue(for: selectedMetric))
                    )
                    .foregroundStyle(tenantTheme.primarySwiftUIColor.gradient)
                    
                case .area:
                    AreaMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Revenue", dataPoint.getValue(for: selectedMetric))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tenantTheme.primarySwiftUIColor.opacity(0.6), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                
                // Add forecast line if available
                if let forecast = dataPoint.forecast {
                    LineMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Forecast", forecast)
                    )
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                }
            }
            .frame(height: 250)
            .chartXAxis {
                AxisMarks(values: .stride(by: selectedTimeframe.axisStride)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: selectedTimeframe.axisFormat)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .currency(code: "USD"))
                }
            }
            .chartLegend(position: .top)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                .fill(tenantTheme.surfaceSwiftUIColor)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Pricing Optimization Section
    
    private var pricingOptimizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pricing Optimization")
                    .font(.headline)
                    .foregroundColor(tenantTheme.textSwiftUIColor)
                
                Spacer()
                
                Button("View Strategy") {
                    showingPricingStrategy = true
                }
                .font(.caption)
                .foregroundColor(tenantTheme.primarySwiftUIColor)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(viewModel.pricingRecommendations.prefix(4), id: \.id) { recommendation in
                    PricingOptimizationCard(
                        recommendation: recommendation,
                        tenantTheme: tenantTheme,
                        onTap: {
                            showingRecommendationDetail = recommendation
                        }
                    )
                }
            }
            
            if viewModel.pricingRecommendations.count > 4 {
                Button("View All \(viewModel.pricingRecommendations.count) Recommendations") {
                    showingPricingStrategy = true
                }
                .foregroundColor(tenantTheme.primarySwiftUIColor)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                .fill(tenantTheme.surfaceSwiftUIColor)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Demand Forecasting Section
    
    private var demandForecastingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Demand Forecasting")
                .font(.headline)
                .foregroundColor(tenantTheme.textSwiftUIColor)
            
            Chart(viewModel.demandForecast) { dataPoint in
                LineMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Predicted Demand", dataPoint.predictedDemand)
                )
                .foregroundStyle(.blue.gradient)
                .lineStyle(StrokeStyle(lineWidth: 3))
                
                AreaMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Predicted Demand", dataPoint.predictedDemand)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(height: 150)
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
                    AxisValueLabel(format: .percent.precision(.fractionLength(0)))
                }
            }
            
            // Demand Insights
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                DemandInsightCard(
                    title: "Peak Hours",
                    value: viewModel.peakDemandHours,
                    color: .red
                )
                
                DemandInsightCard(
                    title: "Low Demand",
                    value: viewModel.lowDemandPeriods,
                    color: .blue
                )
                
                DemandInsightCard(
                    title: "Capacity Utilization",
                    value: "\(Int(viewModel.avgCapacityUtilization * 100))%",
                    color: .green
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                .fill(tenantTheme.surfaceSwiftUIColor)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Revenue Opportunities Section
    
    private var revenueOpportunitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revenue Opportunities")
                .font(.headline)
                .foregroundColor(tenantTheme.textSwiftUIColor)
            
            if viewModel.revenueOpportunities.isEmpty {
                EmptyStateView(
                    title: "No Opportunities Found",
                    subtitle: "All revenue streams are optimized",
                    systemImage: "checkmark.circle"
                )
                .frame(height: 120)
            } else {
                ForEach(viewModel.revenueOpportunities.prefix(3), id: \.id) { opportunity in
                    RevenueOpportunityCard(
                        opportunity: opportunity,
                        tenantTheme: tenantTheme,
                        onImplement: {
                            Task {
                                await viewModel.implementOpportunity(opportunity)
                            }
                        }
                    )
                }
                
                if viewModel.revenueOpportunities.count > 3 {
                    Button("View All \(viewModel.revenueOpportunities.count) Opportunities") {
                        // Navigate to full opportunities view
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
    
    // MARK: - Performance Recommendations Section
    
    private var performanceRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Recommendations")
                .font(.headline)
                .foregroundColor(tenantTheme.textSwiftUIColor)
            
            ForEach(viewModel.aiRecommendations.prefix(3), id: \.id) { recommendation in
                AIRecommendationCard(
                    recommendation: recommendation,
                    tenantTheme: tenantTheme,
                    onApply: {
                        Task {
                            await viewModel.applyRecommendation(recommendation)
                        }
                    }
                )
            }
            
            if viewModel.aiRecommendations.count > 3 {
                Button("View All \(viewModel.aiRecommendations.count) Recommendations") {
                    // Navigate to full recommendations view
                }
                .foregroundColor(tenantTheme.primarySwiftUIColor)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: tenantTheme.cornerRadius)
                .fill(tenantTheme.surfaceSwiftUIColor)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Revenue Distribution Section
    
    private var revenueDistributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revenue Distribution")
                .font(.headline)
                .foregroundColor(tenantTheme.textSwiftUIColor)
            
            Chart(viewModel.revenueDistribution, id: \.category) { distribution in
                SectorMark(
                    angle: .value("Revenue", distribution.amount),
                    innerRadius: .ratio(0.4),
                    angularInset: 2
                )
                .foregroundStyle(distribution.color.gradient)
                .opacity(0.8)
            }
            .frame(height: 200)
            
            // Distribution Legend
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(viewModel.revenueDistribution, id: \.category) { distribution in
                    HStack {
                        Circle()
                            .fill(distribution.color)
                            .frame(width: 12, height: 12)
                        
                        Text(distribution.category)
                            .font(.caption)
                        
                        Spacer()
                        
                        Text(distribution.amount.formatted(.currency(code: "USD")))
                            .font(.caption.weight(.medium))
                    }
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
    
    private func loadRevenueData() async {
        guard let tenantId = currentTenant?.id else { return }
        await viewModel.loadRevenueOptimizationData(
            tenantId: tenantId,
            timeframe: selectedTimeframe
        )
    }
}

// MARK: - Supporting Views

struct RevenueMetricCard: View {
    let title: String
    let value: Double
    let change: Double?
    let target: Double?
    let icon: String
    let color: Color
    let formatter: MetricFormatter
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Spacer()
                
                if let change = change {
                    TrendIndicator(trend: change >= 0 ? .up(abs(change)) : .down(abs(change)))
                }
            }
            
            Text(formatter.format(value))
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)
            
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let target = target {
                    let progress = value / target
                    let progressColor = progress >= 1.0 ? Color.green : (progress >= 0.8 ? Color.orange : Color.red)
                    
                    Text("\(Int(progress * 100))% of target")
                        .font(.caption)
                        .foregroundColor(progressColor)
                }
            }
            
            if let target = target {
                ProgressView(value: min(value / target, 1.0))
                    .tint(value >= target ? .green : .orange)
                    .scaleEffect(y: 2)
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

struct PricingOptimizationCard: View {
    let recommendation: PricingRecommendation
    let tenantTheme: WhiteLabelTheme
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(recommendation.timeSlot)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if recommendation.expectedRevenueLift > 0 {
                        Text("+\(String(format: "%.1f", recommendation.expectedRevenueLift))%")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.green)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(recommendation.currentPrice.formatted(.currency(code: "USD")))
                            .font(.subheadline.weight(.medium))
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggested")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(recommendation.recommendedPrice.formatted(.currency(code: "USD")))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(tenantTheme.primarySwiftUIColor)
                    }
                    
                    Spacer()
                }
                
                Text(recommendation.rationale)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tenantTheme.primarySwiftUIColor.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(tenantTheme.primarySwiftUIColor.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DemandInsightCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.1))
        )
    }
}

struct RevenueOpportunityCard: View {
    let opportunity: BusinessOpportunity
    let tenantTheme: WhiteLabelTheme
    let onImplement: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(opportunity.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                
                Text(opportunity.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Text("Potential: \(opportunity.potentialRevenue.formatted(.currency(code: "USD")))")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    Text("ROI: \(String(format: "%.0f", opportunity.estimatedROI))%")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            Button(action: onImplement) {
                Text("Implement")
                    .font(.caption.weight(.medium))
                    .foregroundColor(tenantTheme.primarySwiftUIColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(tenantTheme.primarySwiftUIColor, lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
        )
    }
}

struct AIRecommendationCard: View {
    let recommendation: AIRecommendation
    let tenantTheme: WhiteLabelTheme
    let onApply: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: recommendation.icon)
                    .font(.title3)
                    .foregroundColor(recommendation.priority.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Text(recommendation.category.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(recommendation.priority.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(recommendation.priority.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(recommendation.priority.color.opacity(0.2))
                    )
            }
            
            Text(recommendation.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            HStack {
                Text("Expected Impact: \(recommendation.expectedImpact)")
                    .font(.caption)
                    .foregroundColor(.green)
                
                Spacer()
                
                Button(action: onApply) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Apply")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(tenantTheme.primarySwiftUIColor)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(recommendation.priority.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Enums and Supporting Types

enum RevenueTimeframe: String, CaseIterable {
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"
    
    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "Quarter"
        case .year: return "Year"
        }
    }
    
    var axisStride: Calendar.Component {
        switch self {
        case .week: return .day
        case .month: return .weekOfYear
        case .quarter: return .month
        case .year: return .quarter
        }
    }
    
    var axisFormat: Date.FormatStyle {
        switch self {
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.month(.abbreviated).day()
        case .quarter: return .dateTime.month(.abbreviated)
        case .year: return .dateTime.quarter()
        }
    }
}

enum RevenueMetric: String, CaseIterable {
    case total = "total"
    case perBooking = "per_booking"
    case perMember = "per_member"
    case gross = "gross"
    
    var displayName: String {
        switch self {
        case .total: return "Total Revenue"
        case .perBooking: return "Per Booking"
        case .perMember: return "Per Member"
        case .gross: return "Gross Revenue"
        }
    }
}

enum ChartType: String, CaseIterable {
    case line = "line"
    case bar = "bar"
    case area = "area"
    
    var icon: String {
        switch self {
        case .line: return "chart.xyaxis.line"
        case .bar: return "chart.bar"
        case .area: return "chart.area"
        }
    }
}

enum MetricFormatter {
    case currency
    case percentage
    case number
    
    func format(_ value: Double) -> String {
        switch self {
        case .currency:
            return value.formatted(.currency(code: "USD"))
        case .percentage:
            return value.formatted(.percent.precision(.fractionLength(1)))
        case .number:
            return String(format: "%.0f", value)
        }
    }
}

// MARK: - Data Models

struct RevenueDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let totalRevenue: Double
    let revenuePerBooking: Double
    let revenuePerMember: Double
    let grossRevenue: Double
    let forecast: Double?
    
    func getValue(for metric: RevenueMetric) -> Double {
        switch metric {
        case .total: return totalRevenue
        case .perBooking: return revenuePerBooking
        case .perMember: return revenuePerMember
        case .gross: return grossRevenue
        }
    }
}

struct DemandForecastPoint: Identifiable {
    let id = UUID()
    let date: Date
    let predictedDemand: Double
    let confidence: Double
}

struct RevenueDistribution: Identifiable {
    let id = UUID()
    let category: String
    let amount: Double
    let color: Color
}

struct AIRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let category: ActionableInsight.InsightCategory
    let priority: Priority
    let expectedImpact: String
    let icon: String
    
    enum Priority: String, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
        
        var displayName: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .critical: return "Critical"
            }
        }
        
        var color: Color {
            switch self {
            case .low: return .gray
            case .medium: return .blue
            case .high: return .orange
            case .critical: return .red
            }
        }
    }
}

// MARK: - Extensions

extension ActionableInsight.InsightCategory {
    var displayName: String {
        switch self {
        case .pricing: return "Pricing"
        case .scheduling: return "Scheduling"
        case .marketing: return "Marketing"
        case .operations: return "Operations"
        case .customer: return "Customer Experience"
        }
    }
}