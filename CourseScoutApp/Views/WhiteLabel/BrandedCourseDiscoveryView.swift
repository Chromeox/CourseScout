import SwiftUI
import MapKit
import Combine

// MARK: - Branded Course Discovery View

struct BrandedCourseDiscoveryView: View {
    
    // MARK: - View Model
    @StateObject private var viewModel = BrandedCourseDiscoveryViewModel()
    @StateObject private var customizationManager = CustomizationManager()
    
    // MARK: - State Management
    @State private var searchText = ""
    @State private var selectedFilter = CourseFilter.all
    @State private var showingFilters = false
    @State private var showingMapView = false
    @State private var selectedCourse: SharedGolfCourse?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    // MARK: - Revenue Analytics State
    @State private var showingRevenueDashboard = false
    @State private var revenueMetrics: RevenueMetrics?
    @State private var usageAnalytics: UsageAnalytics?
    @State private var isLoadingAnalytics = false
    
    // MARK: - Tenant Theming
    @TenantInjected(\.theme) private var theme: WhiteLabelTheme
    @TenantInjected(\.branding) private var branding: TenantBranding
    @TenantInjected(\.features) private var features: TenantFeatures
    @TenantInjected(\.displayName, default: "Golf Finder") private var brandName: String
    
    // MARK: - Services
    @ServiceInjected(HapticFeedbackServiceProtocol.self)
    private var hapticService: HapticFeedbackServiceProtocol
    
    @ServiceInjected(TenantConfigurationServiceProtocol.self)
    private var tenantConfigService: TenantConfigurationServiceProtocol
    
    @ServiceInjected(RevenueServiceProtocol.self)
    private var revenueService: RevenueServiceProtocol
    
    @ServiceInjected(APIUsageTrackingServiceProtocol.self)
    private var usageTrackingService: APIUsageTrackingServiceProtocol
    
    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundSwiftUIColor
                    .ignoresSafeArea()
                
                if showingMapView {
                    mapView
                        .transition(.scale)
                } else {
                    listView
                        .transition(.opacity)
                }
            }
            .navigationTitle(brandName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if features.hasRevenueDashboard {
                        revenueDashboardButton
                    }
                    viewModeToggle
                    filterButton
                }
                
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    brandLogo
                }
            }
            .searchable(text: $searchText, prompt: "Search \(brandName) courses...")
            .sheet(isPresented: $showingFilters) {
                filterSheet
            }
            .sheet(isPresented: $showingRevenueDashboard) {
                revenueDashboard
            }
            .sheet(item: $selectedCourse) { course in
                BrandedCourseDetailSheet(course: course)
            }
        }
        .tenantThemed()
        .onAppear {
            Task {
                await configureTenantHaptics()
                await viewModel.loadCourses()
                await trackViewAppearance()
                
                // Play tenant branding haptic on first appearance
                await hapticService.playTenantBrandingHaptic()
            }
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchCourses(query: newValue)
            Task {
                await hapticService.courseDiscoveryHaptic(type: .searchResultFound)
            }
        }
        .onChange(of: selectedFilter) { _, newValue in
            viewModel.filterCourses(by: newValue)
            Task {
                await hapticService.courseDiscoveryHaptic(type: .filterApplied)
            }
        }
    }
    
    // MARK: - Brand Logo
    
    private var brandLogo: some View {
        AsyncImage(url: URL(string: branding.logoURL)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            Image(systemName: "flag.circle.fill")
                .foregroundColor(theme.primarySwiftUIColor)
        }
        .frame(width: 32, height: 32)
        .cornerRadius(6)
    }
    
    // MARK: - View Mode Toggle
    
    private var viewModeToggle: some View {
        Button(action: toggleViewMode) {
            Image(systemName: showingMapView ? "list.bullet" : "map")
                .foregroundColor(theme.primarySwiftUIColor)
        }
        .tenantThemedButton()
    }
    
    // MARK: - Filter Button
    
    private var filterButton: some View {
        Button(action: showFilters) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundColor(theme.primarySwiftUIColor)
        }
    }
    
    // MARK: - Revenue Dashboard Button
    
    private var revenueDashboardButton: some View {
        Button(action: showRevenueDashboard) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundColor(theme.accentSwiftUIColor)
        }
        .disabled(isLoadingAnalytics)
    }
    
    // MARK: - List View
    
    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Welcome Banner
                if !branding.welcomeMessage.isEmpty {
                    welcomeBanner
                }
                
                // Featured Courses
                if !viewModel.featuredCourses.isEmpty {
                    featuredCoursesSection
                }
                
                // Course List
                coursesSection
                
                // Load More Button
                if viewModel.hasMoreCourses {
                    loadMoreButton
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.refreshCourses()
            await hapticService.courseDiscoveryHaptic(type: .searchResultFound)
        }
    }
    
    // MARK: - Welcome Banner
    
    private var welcomeBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(branding.tagline)
                        .font(.title2.weight(theme.headerFontWeight.swiftUIWeight))
                        .foregroundColor(theme.textSwiftUIColor)
                    
                    Text(branding.welcomeMessage)
                        .font(.body.weight(theme.bodyFontWeight.swiftUIWeight))
                        .foregroundColor(theme.subtextSwiftUIColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                if let heroImageURL = branding.heroImageURL {
                    AsyncImage(url: URL(string: heroImageURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: theme.cornerRadius)
                            .fill(theme.primarySwiftUIColor.opacity(0.1))
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(theme.cornerRadius)
                }
            }
        }
        .padding()
        .background(theme.surfaceSwiftUIColor)
        .cornerRadius(theme.cornerRadius)
        .shadow(
            color: .black.opacity(theme.shadowOpacity),
            radius: 4,
            x: 0,
            y: 2
        )
    }
    
    // MARK: - Featured Courses Section
    
    private var featuredCoursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Featured Courses")
                    .font(.title2.weight(theme.headerFontWeight.swiftUIWeight))
                    .foregroundColor(theme.textSwiftUIColor)
                
                Spacer()
                
                Button("View All") {
                    // Navigate to all featured courses
                    hapticService.impact(.light)
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.primarySwiftUIColor)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(viewModel.featuredCourses, id: \.id) { course in
                        FeaturedCourseCard(course: course) {
                            selectCourse(course)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Courses Section
    
    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("All Courses")
                    .font(.title2.weight(theme.headerFontWeight.swiftUIWeight))
                    .foregroundColor(theme.textSwiftUIColor)
                
                Spacer()
                
                Text("\(viewModel.filteredCourses.count) courses")
                    .font(.subheadline)
                    .foregroundColor(theme.subtextSwiftUIColor)
            }
            
            ForEach(viewModel.filteredCourses, id: \.id) { course in
                BrandedCourseCard(course: course) {
                    selectCourse(course)
                }
            }
        }
    }
    
    // MARK: - Load More Button
    
    private var loadMoreButton: some View {
        Button("Load More Courses") {
            Task {
                await viewModel.loadMoreCourses()
                hapticService.impact(.light)
            }
        }
        .font(.body.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding()
        .tenantThemedButton()
        .disabled(viewModel.isLoading)
    }
    
    // MARK: - Map View
    
    private var mapView: some View {
        Map(coordinateRegion: $region, annotationItems: viewModel.filteredCourses) { course in
            MapAnnotation(coordinate: course.coordinate) {
                CourseMapPin(course: course) {
                    selectCourse(course)
                }
            }
        }
        .onAppear {
            updateMapRegion()
        }
    }
    
    // MARK: - Filter Sheet
    
    private var filterSheet: some View {
        BrandedFilterSheet(
            selectedFilter: $selectedFilter,
            onApply: { filter in
                selectedFilter = filter
                showingFilters = false
                hapticService.notification(.success)
            },
            onReset: {
                selectedFilter = .all
                hapticService.impact(.medium)
            }
        )
    }
    
    // MARK: - Revenue Dashboard
    
    private var revenueDashboard: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoadingAnalytics {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .foregroundColor(theme.primarySwiftUIColor)
                            Text("Loading revenue analytics...")
                                .foregroundColor(theme.subtextSwiftUIColor)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        revenueSummarySection
                        usageMetricsSection
                        revenueBreakdownSection
                    }
                }
                .padding()
            }
            .navigationTitle("Revenue Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingRevenueDashboard = false
                    }
                    .foregroundColor(theme.primarySwiftUIColor)
                }
            }
            .background(theme.backgroundSwiftUIColor)
        }
        .onAppear {
            loadRevenueAnalytics()
        }
    }
    
    private var revenueSummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revenue Summary")
                .font(.headline)
                .foregroundColor(theme.textSwiftUIColor)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                RevenueMetricCard(
                    title: "Monthly Revenue",
                    value: revenueMetrics?.totalRevenue.formatted(.currency(code: "USD")) ?? "$0",
                    trend: .up,
                    trendValue: "+12.5%",
                    color: theme.primarySwiftUIColor
                )
                
                RevenueMetricCard(
                    title: "Active Users",
                    value: "\(revenueMetrics?.customerCount ?? 0)",
                    trend: .up,
                    trendValue: "+8.3%",
                    color: theme.accentSwiftUIColor
                )
                
                RevenueMetricCard(
                    title: "ARPU",
                    value: revenueMetrics?.averageRevenuePerUser.formatted(.currency(code: "USD")) ?? "$0",
                    trend: .up,
                    trendValue: "+3.2%",
                    color: .green
                )
                
                RevenueMetricCard(
                    title: "Churn Rate",
                    value: String(format: "%.1f%%", (revenueMetrics?.churnRate ?? 0) * 100),
                    trend: .down,
                    trendValue: "-0.8%",
                    color: .orange
                )
            }
        }
    }
    
    private var usageMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Usage Metrics")
                .font(.headline)
                .foregroundColor(theme.textSwiftUIColor)
            
            VStack(spacing: 12) {
                UsageMetricRow(
                    title: "Total API Calls",
                    value: "\(usageAnalytics?.totalAPICalls ?? 0)",
                    subtitle: "This month"
                )
                
                UsageMetricRow(
                    title: "Avg Response Time",
                    value: String(format: "%.0fms", usageAnalytics?.averageResponseTime ?? 0),
                    subtitle: "Across all endpoints"
                )
                
                UsageMetricRow(
                    title: "Error Rate",
                    value: String(format: "%.2f%%", (usageAnalytics?.errorRate ?? 0) * 100),
                    subtitle: "Success rate: \(String(format: "%.1f%%", 100 - (usageAnalytics?.errorRate ?? 0) * 100))"
                )
                
                UsageMetricRow(
                    title: "Unique Endpoints",
                    value: "\(usageAnalytics?.uniqueEndpoints ?? 0)",
                    subtitle: "Active endpoints"
                )
            }
            .padding()
            .background(theme.cardSwiftUIColor)
            .cornerRadius(12)
        }
    }
    
    private var revenueBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revenue Breakdown")
                .font(.headline)
                .foregroundColor(theme.textSwiftUIColor)
            
            VStack(spacing: 8) {
                RevenueBreakdownRow(
                    title: "Subscription Revenue",
                    amount: revenueMetrics?.recurringRevenue ?? 0,
                    percentage: 0.75,
                    color: theme.primarySwiftUIColor
                )
                
                RevenueBreakdownRow(
                    title: "Usage Overage",
                    amount: revenueMetrics?.oneTimeRevenue ?? 0,
                    percentage: 0.20,
                    color: theme.accentSwiftUIColor
                )
                
                RevenueBreakdownRow(
                    title: "One-time Payments",
                    amount: 0,
                    percentage: 0.05,
                    color: .green
                )
            }
            .padding()
            .background(theme.cardSwiftUIColor)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Actions
    
    private func toggleViewMode() {
        hapticService.impact(.medium)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            showingMapView.toggle()
        }
    }
    
    private func showFilters() {
        hapticService.impact(.light)
        showingFilters = true
    }
    
    private func showRevenueDashboard() {
        hapticService.impact(.light)
        showingRevenueDashboard = true
    }
    
    private func loadRevenueAnalytics() {
        guard let tenantId = viewModel.currentTenantId else { return }
        
        isLoadingAnalytics = true
        
        Task {
            do {
                // Load revenue metrics
                revenueMetrics = try await revenueService.getRevenueMetrics(for: .monthly)
                
                // Load usage analytics
                usageAnalytics = try await usageTrackingService.getUsageAnalytics(
                    tenantId: tenantId,
                    period: .monthly
                )
                
                await MainActor.run {
                    isLoadingAnalytics = false
                }
            } catch {
                print("Failed to load revenue analytics: \(error)")
                await MainActor.run {
                    isLoadingAnalytics = false
                }
            }
        }
    }
    
    private func selectCourse(_ course: SharedGolfCourse) {
        hapticService.selection()
        selectedCourse = course
        
        Task {
            await viewModel.trackCourseSelection(course)
        }
    }
    
    private func updateMapRegion() {
        guard !viewModel.filteredCourses.isEmpty else { return }
        
        let coordinates = viewModel.filteredCourses.map { $0.coordinate }
        let center = CLLocationCoordinate2D(
            latitude: coordinates.map { $0.latitude }.reduce(0, +) / Double(coordinates.count),
            longitude: coordinates.map { $0.longitude }.reduce(0, +) / Double(coordinates.count)
        )
        
        region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }
    
    private func trackViewAppearance() async {
        await viewModel.trackViewAppearance(
            brandName: brandName,
            theme: theme.primaryColor.hex,
            viewMode: showingMapView ? "map" : "list"
        )
    }
}

// MARK: - Featured Course Card

struct FeaturedCourseCard: View {
    let course: SharedGolfCourse
    let onTap: () -> Void
    
    @TenantInjected(\.theme) private var theme: WhiteLabelTheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Course Image Placeholder
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(theme.primarySwiftUIColor.opacity(0.1))
                    .frame(width: 200, height: 120)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(theme.primarySwiftUIColor)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.name)
                        .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                        .foregroundColor(theme.textSwiftUIColor)
                        .lineLimit(2)
                    
                    Text(course.shortAddress)
                        .font(.subheadline)
                        .foregroundColor(theme.subtextSwiftUIColor)
                    
                    HStack {
                        HStack(spacing: 2) {
                            ForEach(0..<5) { star in
                                Image(systemName: star < Int(course.averageRating) ? "star.fill" : "star")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                        }
                        
                        Spacer()
                        
                        Text("\(course.numberOfHoles) holes")
                            .font(.caption)
                            .foregroundColor(theme.subtextSwiftUIColor)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(theme.surfaceSwiftUIColor)
        .cornerRadius(theme.cornerRadius)
        .shadow(
            color: .black.opacity(theme.shadowOpacity),
            radius: 2,
            x: 0,
            y: 1
        )
    }
}

// MARK: - Branded Course Card

struct BrandedCourseCard: View {
    let course: SharedGolfCourse
    let onTap: () -> Void
    
    @TenantInjected(\.theme) private var theme: WhiteLabelTheme
    @TenantInjected(\.features) private var features: TenantFeatures
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Course Image
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(theme.primarySwiftUIColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "flag.circle.fill")
                            .foregroundColor(theme.primarySwiftUIColor)
                            .font(.title2)
                    )
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(course.name)
                        .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                        .foregroundColor(theme.textSwiftUIColor)
                        .multilineTextAlignment(.leading)
                    
                    Text(course.shortAddress)
                        .font(.subheadline)
                        .foregroundColor(theme.subtextSwiftUIColor)
                    
                    HStack {
                        // Rating
                        HStack(spacing: 2) {
                            ForEach(0..<5) { star in
                                Image(systemName: star < Int(course.averageRating) ? "star.fill" : "star")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                            
                            Text(course.formattedRating)
                                .font(.caption)
                                .foregroundColor(theme.subtextSwiftUIColor)
                        }
                        
                        Spacer()
                        
                        // Course Info
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(course.numberOfHoles) holes")
                                .font(.caption.weight(.medium))
                                .foregroundColor(theme.textSwiftUIColor)
                            
                            Text("Par \(course.par)")
                                .font(.caption)
                                .foregroundColor(theme.subtextSwiftUIColor)
                        }
                    }
                    
                    // Features
                    if features.enableGPSRangefinder || features.enableWeatherIntegration {
                        HStack(spacing: 8) {
                            if features.enableGPSRangefinder && course.hasGPS {
                                FeatureBadge(icon: "location", text: "GPS", color: theme.accentSwiftUIColor)
                            }
                            
                            if features.enableWeatherIntegration {
                                FeatureBadge(icon: "cloud.sun", text: "Weather", color: theme.successSwiftUIColor)
                            }
                            
                            if course.hasRestaurant {
                                FeatureBadge(icon: "fork.knife", text: "Dining", color: theme.primarySwiftUIColor)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(theme.subtextSwiftUIColor)
                    .font(.caption)
            }
            .padding()
        }
        .buttonStyle(PlainButtonStyle())
        .background(theme.surfaceSwiftUIColor)
        .cornerRadius(theme.cornerRadius)
        .shadow(
            color: .black.opacity(theme.shadowOpacity),
            radius: 2,
            x: 0,
            y: 1
        )
    }
}

// MARK: - Feature Badge

struct FeatureBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Course Map Pin

struct CourseMapPin: View {
    let course: SharedGolfCourse
    let onTap: () -> Void
    
    @TenantInjected(\.theme) private var theme: WhiteLabelTheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Circle()
                    .fill(theme.primarySwiftUIColor)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "flag.fill")
                            .foregroundColor(.white)
                            .font(.caption)
                    )
                
                Text(course.name)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(theme.textSwiftUIColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(theme.surfaceSwiftUIColor.opacity(0.9))
                    .cornerRadius(4)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Action Methods
    
    private func configureTenantHaptics() async {
        guard let currentTenant = tenantConfigService.currentTenant else { return }
        
        // Create tenant haptic configuration based on current tenant
        let hapticConfiguration = TenantHapticConfiguration(
            tenantId: currentTenant.id,
            businessType: getBusinessHapticType(from: currentTenant.businessInfo.businessType),
            brandingSignature: getBrandingSignature(for: currentTenant),
            preferences: getTenantHapticPreferences(for: currentTenant),
            intensityProfile: getIntensityProfile(for: currentTenant),
            accessibilitySettings: getAccessibilitySettings(for: currentTenant)
        )
        
        await hapticService.configureTenantHaptics(configuration: hapticConfiguration)
    }
    
    private func toggleViewMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showingMapView.toggle()
        }
        
        Task {
            await hapticService.courseDiscoveryHaptic(type: .mapInteraction)
        }
    }
    
    private func showFilters() {
        showingFilters = true
        
        Task {
            await hapticService.courseDiscoveryHaptic(type: .filterApplied)
        }
    }
    
    private func trackViewAppearance() async {
        // Analytics tracking with haptic confirmation
        await hapticService.courseDiscoveryHaptic(type: .searchResultFound)
    }
    
    // MARK: - Tenant Haptic Configuration Helpers
    
    private func getBusinessHapticType(from businessType: BusinessType) -> BusinessHapticType {
        switch businessType {
        case .golfCourse:
            return .golfCourse(intensity: .standard)
        case .golfResort:
            return .golfResort(luxury: .luxury)
        case .countryClub:
            return .countryClub(exclusivity: .exclusive)
        case .publicCourse:
            return .publicCourse(accessibility: .welcoming)
        case .privateClub:
            return .privateClub(premium: .premium)
        case .golfAcademy:
            return .golfAcademy(education: .learning)
        }
    }
    
    private func getBrandingSignature(for tenant: TenantConfiguration) -> HapticBrandingSignature {
        // Return appropriate branding signature based on tenant type
        switch tenant.businessInfo.businessType {
        case .golfResort, .countryClub:
            return .resortLuxury
        default:
            return .golfCourseClassic
        }
    }
    
    private func getTenantHapticPreferences(for tenant: TenantConfiguration) -> TenantHapticPreferences {
        return TenantHapticPreferences(
            isEnabled: tenant.features.enableHapticFeedback,
            globalIntensity: getGlobalIntensityFromTheme(),
            brandingHapticEnabled: tenant.features.enableTenantHapticBranding,
            analyticsHapticsEnabled: tenant.features.enableAdvancedAnalytics,
            managementHapticsEnabled: true,
            bookingHapticsEnabled: tenant.features.enableBooking,
            customPatterns: [:],
            accessibilityOptimized: false,
            batteryOptimized: false,
            watchSyncEnabled: tenant.features.enableAppleWatchSync
        )
    }
    
    private func getIntensityProfile(for tenant: TenantConfiguration) -> TenantIntensityProfile {
        return tenant.businessInfo.businessType.hapticProfile
    }
    
    private func getAccessibilitySettings(for tenant: TenantConfiguration) -> TenantAccessibilitySettings {
        return .standard
    }
    
    private func getGlobalIntensityFromTheme() -> TenantHapticIntensity {
        switch theme.hapticIntensityStyle {
        case .subtle:
            return .minimal
        case .balanced:
            return .standard
        case .dynamic:
            return .enhanced
        case .premium:
            return .luxury
        }
    }
}

// MARK: - Revenue Dashboard Components

struct RevenueMetricCard: View {
    let title: String
    let value: String
    let trend: TrendDirection
    let trendValue: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundColor(.primary)
            
            HStack(spacing: 4) {
                Image(systemName: trend == .up ? "arrow.up" : "arrow.down")
                    .font(.caption)
                Text(trendValue)
                    .font(.caption)
            }
            .foregroundColor(trend == .up ? .green : .red)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    enum TrendDirection {
        case up, down
    }
}

struct UsageMetricRow: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
    }
}

struct RevenueBreakdownRow: View {
    let title: String
    let amount: Decimal
    let percentage: Double
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(amount.formatted(.currency(code: "USD")))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(color)
                        .frame(width: 50 * percentage, height: 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(2)
                    
                    Text("\(Int(percentage * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Filter Types

enum CourseFilter: String, CaseIterable {
    case all = "all"
    case nearby = "nearby"
    case featured = "featured"
    case highRated = "high_rated"
    case hasGPS = "has_gps"
    case hasRestaurant = "has_restaurant"
    
    var displayName: String {
        switch self {
        case .all: return "All Courses"
        case .nearby: return "Nearby"
        case .featured: return "Featured"
        case .highRated: return "Highly Rated"
        case .hasGPS: return "GPS Enabled"
        case .hasRestaurant: return "Has Restaurant"
        }
    }
    
    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .nearby: return "location"
        case .featured: return "star"
        case .highRated: return "hand.thumbsup"
        case .hasGPS: return "location.circle"
        case .hasRestaurant: return "fork.knife"
        }
    }
}

// MARK: - Preview

#Preview {
    BrandedCourseDiscoveryView()
        .environmentObject(ServiceContainer.shared)
}