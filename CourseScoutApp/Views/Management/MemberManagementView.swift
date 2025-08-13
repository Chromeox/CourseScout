import SwiftUI
import Combine
import Charts

// MARK: - Member Management View

struct MemberManagementView: View {
    
    // MARK: - Dependencies
    @TenantInjected private var tenantService: TenantConfigurationServiceProtocol
    @TenantInjected private var analyticsService: B2BAnalyticsServiceProtocol
    @ServiceInjected(UserProfileServiceProtocol.self) private var userService
    @ServiceInjected(HapticFeedbackServiceProtocol.self) private var hapticService
    
    // MARK: - State Management
    @StateObject private var viewModel = MemberManagementViewModel()
    @State private var selectedTab: MemberTab = .overview
    @State private var searchText = ""
    @State private var selectedSegment: MemberSegment? = nil
    @State private var showingMemberDetail: Member? = nil
    @State private var showingAddMember = false
    @State private var showingExportOptions = false
    @State private var showingBulkActions = false
    @State private var selectedMembers: Set<String> = []
    
    // MARK: - Filter and Sort State
    @State private var filterOptions = MemberFilterOptions()
    @State private var sortOption: MemberSortOption = .name
    @State private var sortAscending = true
    
    // MARK: - Current Tenant Context
    @State private var currentTenant: TenantConfiguration?
    private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // MARK: - Tab Selector
                tabSelectorSection
                
                // MARK: - Content Based on Selected Tab
                TabView(selection: $selectedTab) {
                    // Overview Tab
                    overviewTabContent
                        .tag(MemberTab.overview)
                    
                    // Members Database Tab
                    membersTabContent
                        .tag(MemberTab.members)
                    
                    // Analytics Tab
                    analyticsTabContent
                        .tag(MemberTab.analytics)
                    
                    // Segments Tab
                    segmentsTabContent
                        .tag(MemberTab.segments)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: selectedTab)
                
                // MARK: - Bulk Actions Bar
                if !selectedMembers.isEmpty {
                    bulkActionsBar
                }
            }
            .navigationTitle("Member Management")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Export Button
                    Button {
                        showingExportOptions = true
                        hapticService.buttonPressed()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(tenantTheme.primarySwiftUIColor)
                    }
                    
                    // Add Member Button
                    Button {
                        showingAddMember = true
                        hapticService.buttonPressed()
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(tenantTheme.primarySwiftUIColor)
                    }
                }
            }
        }
        .onAppear {
            setupTenantContext()
            Task { await loadMemberData() }
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberSheet { member in
                Task { await viewModel.addMember(member) }
            }
        }
        .sheet(item: $showingMemberDetail) { member in
            MemberDetailSheet(member: member, viewModel: viewModel)
        }
        .sheet(isPresented: $showingExportOptions) {
            MemberExportSheet(
                members: viewModel.filteredMembers,
                tenantId: currentTenant?.id ?? ""
            )
        }
    }
    
    // MARK: - Tab Selector
    
    private var tabSelectorSection: some View {
        HStack {
            ForEach(MemberTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                    hapticService.selectionChanged()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.title3)
                        Text(tab.displayName)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(selectedTab == tab ? tenantTheme.primarySwiftUIColor : .secondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.systemGray5)),
            alignment: .bottom
        )
    }
    
    // MARK: - Overview Tab Content
    
    private var overviewTabContent: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Member Stats Cards
                memberStatsSection
                
                // Growth Trends Chart
                memberGrowthChart
                
                // Engagement Overview
                engagementOverviewSection
                
                // Recent Activity
                recentMemberActivity
            }
            .padding()
        }
        .refreshable {
            await loadMemberData()
        }
    }
    
    // MARK: - Member Stats Section
    
    private var memberStatsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            MemberStatCard(
                title: "Total Members",
                value: "\(viewModel.totalMembersCount)",
                trend: viewModel.memberGrowthTrend,
                icon: "person.3.fill",
                color: tenantTheme.primarySwiftUIColor
            )
            
            MemberStatCard(
                title: "Active Members",
                value: "\(viewModel.activeMembersCount)",
                trend: viewModel.activityTrend,
                icon: "figure.golf",
                color: .green
            )
            
            MemberStatCard(
                title: "New This Month",
                value: "\(viewModel.newMembersThisMonth)",
                trend: viewModel.acquisitionTrend,
                icon: "person.badge.plus",
                color: .blue
            )
            
            MemberStatCard(
                title: "Retention Rate",
                value: "\(Int(viewModel.retentionRate * 100))%",
                trend: viewModel.retentionTrend,
                icon: "arrow.triangle.2.circlepath",
                color: .orange
            )
        }
    }
    
    // MARK: - Member Growth Chart
    
    private var memberGrowthChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Member Growth Trends")
                .font(.headline)
                .foregroundColor(tenantTheme.textSwiftUIColor)
            
            Chart(viewModel.memberGrowthData) { dataPoint in
                LineMark(
                    x: .value("Month", dataPoint.month),
                    y: .value("New Members", dataPoint.newMembers)
                )
                .foregroundStyle(tenantTheme.primarySwiftUIColor.gradient)
                .lineStyle(StrokeStyle(lineWidth: 3))
                
                AreaMark(
                    x: .value("Month", dataPoint.month),
                    y: .value("New Members", dataPoint.newMembers)
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
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
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
    
    // MARK: - Engagement Overview Section
    
    private var engagementOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Member Engagement")
                .font(.headline)
                .foregroundColor(tenantTheme.textSwiftUIColor)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                EngagementMetricCard(
                    title: "Avg Visits/Month",
                    value: String(format: "%.1f", viewModel.averageVisitsPerMonth),
                    color: .blue
                )
                
                EngagementMetricCard(
                    title: "Avg Spend",
                    value: viewModel.averageSpending.formatted(.currency(code: "USD")),
                    color: .green
                )
                
                EngagementMetricCard(
                    title: "Satisfaction",
                    value: "\(String(format: "%.1f", viewModel.memberSatisfactionScore)) ⭐",
                    color: .orange
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
    
    // MARK: - Recent Member Activity
    
    private var recentMemberActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .foregroundColor(tenantTheme.textSwiftUIColor)
                
                Spacer()
                
                Button("View All") {
                    // Navigate to full activity view
                }
                .font(.caption)
                .foregroundColor(tenantTheme.primarySwiftUIColor)
            }
            
            if viewModel.recentActivities.isEmpty {
                EmptyStateView(
                    title: "No Recent Activity",
                    subtitle: "Member activity will appear here",
                    systemImage: "clock.arrow.circlepath"
                )
                .frame(height: 120)
            } else {
                ForEach(viewModel.recentActivities.prefix(5), id: \.id) { activity in
                    MemberActivityCard(activity: activity)
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
    
    // MARK: - Members Tab Content
    
    private var membersTabContent: some View {
        VStack(spacing: 0) {
            // Search and Filter Bar
            memberSearchAndFilterSection
            
            // Members List
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredMembers, id: \.id) { member in
                        MemberListCard(
                            member: member,
                            isSelected: selectedMembers.contains(member.id),
                            showBulkSelection: showingBulkActions,
                            tenantTheme: tenantTheme,
                            onTap: {
                                if showingBulkActions {
                                    toggleMemberSelection(member.id)
                                } else {
                                    showingMemberDetail = member
                                }
                            },
                            onToggleSelection: {
                                toggleMemberSelection(member.id)
                            }
                        )
                    }
                }
                .padding()
            }
            .refreshable {
                await viewModel.refreshMembers()
            }
        }
    }
    
    // MARK: - Search and Filter Section
    
    private var memberSearchAndFilterSection: some View {
        VStack(spacing: 12) {
            HStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search members...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { _, _ in
                            viewModel.filterMembers(
                                searchText: searchText,
                                options: filterOptions,
                                sortOption: sortOption,
                                ascending: sortAscending
                            )
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            viewModel.clearFilters()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                )
                
                // Bulk Actions Toggle
                Button {
                    showingBulkActions.toggle()
                    if !showingBulkActions {
                        selectedMembers.removeAll()
                    }
                    hapticService.selectionChanged()
                } label: {
                    Image(systemName: showingBulkActions ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundColor(tenantTheme.primarySwiftUIColor)
                }
            }
            
            // Sort and Filter Options
            HStack {
                // Sort Picker
                Menu {
                    ForEach(MemberSortOption.allCases, id: \.self) { option in
                        Button {
                            if sortOption == option {
                                sortAscending.toggle()
                            } else {
                                sortOption = option
                                sortAscending = true
                            }
                            applyFiltersAndSort()
                        } label: {
                            HStack {
                                Text(option.displayName)
                                if sortOption == option {
                                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortOption.displayName)
                        if sortOption != .name || !sortAscending {
                            Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                .font(.caption)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(tenantTheme.primarySwiftUIColor)
                }
                
                Spacer()
                
                // Filter Summary
                if filterOptions.hasActiveFilters {
                    Text("\(filterOptions.activeFilterCount) filters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Analytics Tab Content
    
    private var analyticsTabContent: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Member Segmentation Chart
                memberSegmentationChart
                
                // Lifecycle Analytics
                memberLifecycleAnalytics
                
                // Retention Analysis
                retentionAnalysisSection
                
                // Revenue per Member
                revenuePerMemberSection
            }
            .padding()
        }
        .refreshable {
            await viewModel.refreshAnalytics()
        }
    }
    
    // MARK: - Member Segmentation Chart
    
    private var memberSegmentationChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Member Segmentation")
                .font(.headline)
                .foregroundColor(tenantTheme.textSwiftUIColor)
            
            Chart(viewModel.memberSegments, id: \.name) { segment in
                SectorMark(
                    angle: .value("Count", segment.memberCount),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(segment.color.gradient)
                .opacity(selectedSegment?.name == segment.name ? 1.0 : 0.7)
            }
            .frame(height: 200)
            .chartAngleSelection(value: .constant(nil))
            .onTapGesture { location in
                // Handle segment selection
            }
            
            // Segment Legend
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(viewModel.memberSegments, id: \.name) { segment in
                    Button {
                        selectedSegment = selectedSegment?.name == segment.name ? nil : segment
                    } label: {
                        HStack {
                            Circle()
                                .fill(segment.color)
                                .frame(width: 12, height: 12)
                            
                            Text(segment.name)
                                .font(.caption)
                            
                            Spacer()
                            
                            Text("\(segment.memberCount)")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
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
    
    // MARK: - Segments Tab Content
    
    private var segmentsTabContent: some View {
        VStack(spacing: 0) {
            // Segment Overview
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.memberSegments, id: \.name) { segment in
                        MemberSegmentCard(
                            segment: segment,
                            tenantTheme: tenantTheme,
                            onTap: {
                                selectedSegment = segment
                                // Show segment details
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .refreshable {
            await viewModel.refreshSegments()
        }
    }
    
    // MARK: - Bulk Actions Bar
    
    private var bulkActionsBar: some View {
        HStack {
            Text("\(selectedMembers.count) selected")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 16) {
                Button {
                    // Send message to selected members
                } label: {
                    HStack {
                        Image(systemName: "message")
                        Text("Message")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(tenantTheme.primarySwiftUIColor)
                }
                
                Button {
                    // Export selected members
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.blue)
                }
                
                Button {
                    // Delete selected members
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: -2)
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
    
    private func loadMemberData() async {
        guard let tenantId = currentTenant?.id else { return }
        await viewModel.loadMemberData(tenantId: tenantId)
    }
    
    private func toggleMemberSelection(_ memberId: String) {
        if selectedMembers.contains(memberId) {
            selectedMembers.remove(memberId)
        } else {
            selectedMembers.insert(memberId)
        }
        hapticService.selectionChanged()
    }
    
    private func applyFiltersAndSort() {
        viewModel.filterMembers(
            searchText: searchText,
            options: filterOptions,
            sortOption: sortOption,
            ascending: sortAscending
        )
    }
}

// MARK: - Supporting Views

struct MemberStatCard: View {
    let title: String
    let value: String
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
            
            Text(value)
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

struct EngagementMetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
}

struct MemberActivityCard: View {
    let activity: MemberActivity
    
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

struct MemberListCard: View {
    let member: Member
    let isSelected: Bool
    let showBulkSelection: Bool
    let tenantTheme: WhiteLabelTheme
    let onTap: () -> Void
    let onToggleSelection: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                if showBulkSelection {
                    Button(action: onToggleSelection) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? tenantTheme.primarySwiftUIColor : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Member Avatar
                AsyncImage(url: URL(string: member.profileImageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(tenantTheme.primarySwiftUIColor.opacity(0.3))
                        .overlay(
                            Text(member.initials)
                                .font(.caption.weight(.medium))
                                .foregroundColor(tenantTheme.primarySwiftUIColor)
                        )
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(member.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(member.membershipType.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(member.membershipType.color.opacity(0.2))
                            )
                            .foregroundColor(member.membershipType.color)
                    }
                    
                    HStack {
                        Text(member.email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        HStack {
                            Image(systemName: "calendar")
                            Text("Last Visit: \(member.lastVisit, formatter: DateFormatter.shortDate)")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? tenantTheme.primarySwiftUIColor : Color(.systemGray5),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MemberSegmentCard: View {
    let segment: MemberSegment
    let tenantTheme: WhiteLabelTheme
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(segment.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(segment.memberCount) members")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(segment.color)
                }
                
                Text(segment.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avg Revenue")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(segment.averageRevenue.formatted(.currency(code: "USD")))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Growth")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(segment.growthTrend >= 0 ? "+\(String(format: "%.1f", segment.growthTrend))%" : "\(String(format: "%.1f", segment.growthTrend))%")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(segment.growthTrend >= 0 ? .green : .red)
                    }
                }
                
                ProgressView(value: segment.memberCount, total: Double(viewModel.totalMembersCount))
                    .tint(segment.color)
                    .scaleEffect(y: 2)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(segment.color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(segment.color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Enums and Supporting Types

enum MemberTab: String, CaseIterable {
    case overview = "overview"
    case members = "members"
    case analytics = "analytics"
    case segments = "segments"
    
    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .members: return "Members"
        case .analytics: return "Analytics"
        case .segments: return "Segments"
        }
    }
    
    var icon: String {
        switch self {
        case .overview: return "chart.line.uptrend.xyaxis"
        case .members: return "person.3.fill"
        case .analytics: return "chart.pie.fill"
        case .segments: return "rectangle.3.group.fill"
        }
    }
}

enum MemberSortOption: String, CaseIterable {
    case name = "name"
    case joinDate = "join_date"
    case lastVisit = "last_visit"
    case revenue = "revenue"
    case visits = "visits"
    
    var displayName: String {
        switch self {
        case .name: return "Name"
        case .joinDate: return "Join Date"
        case .lastVisit: return "Last Visit"
        case .revenue: return "Revenue"
        case .visits: return "Visits"
        }
    }
}

struct MemberFilterOptions {
    var membershipTypes: Set<Member.MembershipType> = []
    var activityStatus: Set<Member.ActivityStatus> = []
    var joinDateRange: ClosedRange<Date>?
    var revenueRange: ClosedRange<Double>?
    
    var hasActiveFilters: Bool {
        !membershipTypes.isEmpty || !activityStatus.isEmpty || 
        joinDateRange != nil || revenueRange != nil
    }
    
    var activeFilterCount: Int {
        var count = 0
        if !membershipTypes.isEmpty { count += 1 }
        if !activityStatus.isEmpty { count += 1 }
        if joinDateRange != nil { count += 1 }
        if revenueRange != nil { count += 1 }
        return count
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
    
    static let timeAgo: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

extension Member {
    var initials: String {
        let names = name.split(separator: " ")
        return names.compactMap { $0.first }.map(String.init).joined()
    }
    
    enum MembershipType: String, CaseIterable, Codable {
        case basic = "basic"
        case premium = "premium"
        case vip = "vip"
        case corporate = "corporate"
        
        var displayName: String {
            switch self {
            case .basic: return "Basic"
            case .premium: return "Premium"
            case .vip: return "VIP"
            case .corporate: return "Corporate"
            }
        }
        
        var color: Color {
            switch self {
            case .basic: return .gray
            case .premium: return .blue
            case .vip: return .purple
            case .corporate: return .green
            }
        }
    }
    
    enum ActivityStatus: String, CaseIterable, Codable {
        case active = "active"
        case inactive = "inactive"
        case dormant = "dormant"
        
        var displayName: String {
            switch self {
            case .active: return "Active"
            case .inactive: return "Inactive"
            case .dormant: return "Dormant"
            }
        }
        
        var color: Color {
            switch self {
            case .active: return .green
            case .inactive: return .orange
            case .dormant: return .red
            }
        }
    }
}