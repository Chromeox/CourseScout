import SwiftUI
import MapKit

// MARK: - Branded Course Detail Sheet

struct BrandedCourseDetailSheet: View {
    
    let course: SharedGolfCourse
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var showingBooking = false
    @State private var showingDirections = false
    @State private var region: MKCoordinateRegion
    
    // MARK: - Tenant Theming
    @TenantInjected(\.theme) private var theme: WhiteLabelTheme
    @TenantInjected(\.branding) private var branding: TenantBranding
    @TenantInjected(\.features) private var features: TenantFeatures
    @TenantInjected(\.displayName, default: "Golf Course") private var brandName: String
    
    // MARK: - Services
    @ServiceInjected(HapticFeedbackServiceProtocol.self)
    private var hapticService: HapticFeedbackServiceProtocol
    
    @ServiceInjected(AnalyticsServiceProtocol.self)
    private var analyticsService: AnalyticsServiceProtocol
    
    init(course: SharedGolfCourse) {
        self.course = course
        self._region = State(initialValue: MKCoordinateRegion(
            center: course.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header Image and Basic Info
                    headerSection
                    
                    // Tab Selector
                    tabSelector
                    
                    // Tab Content
                    tabContent
                }
            }
            .background(theme.backgroundSwiftUIColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        hapticService.impact(.light)
                        dismiss()
                    }
                    .foregroundColor(theme.primarySwiftUIColor)
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if features.enableSocialFeatures {
                        shareButton
                    }
                    favoriteButton
                }
            }
            .sheet(isPresented: $showingBooking) {
                BrandedBookingSheet(course: course)
            }
        }
        .tenantThemed()
        .onAppear {
            trackViewAppearance()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            // Course Image
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [theme.primarySwiftUIColor.opacity(0.8), theme.accentSwiftUIColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 250)
                    .overlay(
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.3))
                    )
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(course.name)
                        .font(.title.weight(theme.headerFontWeight.swiftUIWeight))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
                    
                    Text(course.shortAddress)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 1, y: 1)
                }
                .padding()
            }
            
            // Quick Stats
            quickStatsSection
        }
    }
    
    // MARK: - Quick Stats Section
    
    private var quickStatsSection: some View {
        HStack(spacing: 20) {
            StatCard(
                icon: "flag.fill",
                value: "\(course.numberOfHoles)",
                label: "Holes",
                theme: theme
            )
            
            StatCard(
                icon: "target",
                value: "\(course.par)",
                label: "Par",
                theme: theme
            )
            
            StatCard(
                icon: "star.fill",
                value: course.formattedRating,
                label: "Rating",
                theme: theme
            )
            
            StatCard(
                icon: "ruler",
                value: course.yardageRange,
                label: "Yards",
                theme: theme
            )
        }
        .padding()
        .background(theme.surfaceSwiftUIColor)
        .shadow(
            color: .black.opacity(theme.shadowOpacity),
            radius: 2,
            x: 0,
            y: -1
        )
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(
                title: "Overview",
                isSelected: selectedTab == 0,
                theme: theme
            ) {
                selectedTab = 0
                hapticService.selection()
            }
            
            TabButton(
                title: "Details",
                isSelected: selectedTab == 1,
                theme: theme
            ) {
                selectedTab = 1
                hapticService.selection()
            }
            
            if features.enableGPSRangefinder {
                TabButton(
                    title: "Map",
                    isSelected: selectedTab == 2,
                    theme: theme
                ) {
                    selectedTab = 2
                    hapticService.selection()
                }
            }
        }
        .background(theme.surfaceSwiftUIColor)
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch selectedTab {
            case 0:
                overviewTab
            case 1:
                detailsTab
            case 2:
                mapTab
            default:
                overviewTab
            }
        }
        .padding()
    }
    
    // MARK: - Overview Tab
    
    private var overviewTab: some View {
        VStack(spacing: 20) {
            // Description
            VStack(alignment: .leading, spacing: 8) {
                Text("About This Course")
                    .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                    .foregroundColor(theme.textSwiftUIColor)
                
                Text("Experience exceptional golf at \(course.name), featuring \(course.numberOfHoles) holes of championship play. This \(course.difficulty.displayName.lowercased()) course offers challenges for golfers of all skill levels.")
                    .font(.body.weight(theme.bodyFontWeight.swiftUIWeight))
                    .foregroundColor(theme.subtextSwiftUIColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Features and Amenities
            if course.hasGPS || course.hasDrivingRange || course.hasRestaurant {
                featuresSection
            }
            
            // Weather Integration
            if features.enableWeatherIntegration {
                weatherSection
            }
            
            // Action Buttons
            actionButtonsSection
        }
    }
    
    // MARK: - Details Tab
    
    private var detailsTab: some View {
        VStack(spacing: 20) {
            // Course Specifications
            courseSpecificationsSection
            
            // Difficulty Information
            difficultySection
            
            // Operating Hours
            operatingHoursSection
            
            // Contact Information
            contactSection
        }
    }
    
    // MARK: - Map Tab
    
    private var mapTab: some View {
        VStack(spacing: 16) {
            Map(coordinateRegion: $region, annotationItems: [course]) { course in
                MapPin(coordinate: course.coordinate, tint: theme.primarySwiftUIColor)
            }
            .frame(height: 300)
            .cornerRadius(theme.cornerRadius)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Location")
                    .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                    .foregroundColor(theme.textSwiftUIColor)
                
                Text(course.address)
                    .font(.body)
                    .foregroundColor(theme.subtextSwiftUIColor)
                
                Button("Get Directions") {
                    hapticService.impact(.medium)
                    openDirections()
                }
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding()
                .tenantThemedButton()
            }
        }
    }
    
    // MARK: - Supporting Sections
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Features & Amenities")
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                if course.hasGPS {
                    FeatureCard(
                        icon: "location.circle.fill",
                        title: "GPS Rangefinder",
                        subtitle: "Precise yardages",
                        theme: theme
                    )
                }
                
                if course.hasDrivingRange {
                    FeatureCard(
                        icon: "target",
                        title: "Driving Range",
                        subtitle: "Practice facility",
                        theme: theme
                    )
                }
                
                if course.hasRestaurant {
                    FeatureCard(
                        icon: "fork.knife",
                        title: "Restaurant",
                        subtitle: "Dining available",
                        theme: theme
                    )
                }
                
                if course.cartRequired {
                    FeatureCard(
                        icon: "car.fill",
                        title: "Cart Required",
                        subtitle: "Mandatory golf carts",
                        theme: theme
                    )
                }
            }
        }
    }
    
    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Weather")
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("72°F")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(theme.textSwiftUIColor)
                    
                    Text("Partly Cloudy")
                        .font(.subheadline)
                        .foregroundColor(theme.subtextSwiftUIColor)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Wind: 8 mph")
                        .font(.caption)
                        .foregroundColor(theme.subtextSwiftUIColor)
                    
                    Text("Humidity: 65%")
                        .font(.caption)
                        .foregroundColor(theme.subtextSwiftUIColor)
                }
            }
            .padding()
            .background(theme.surfaceSwiftUIColor)
            .cornerRadius(theme.cornerRadius)
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            if features.enableBooking {
                Button("Book Tee Time") {
                    hapticService.impact(.medium)
                    showingBooking = true
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .tenantThemedButton()
            }
            
            HStack(spacing: 12) {
                Button("Call Course") {
                    hapticService.impact(.light)
                    callCourse()
                }
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding()
                .tenantThemedButton(isSecondary: true)
                
                Button("Directions") {
                    hapticService.impact(.light)
                    openDirections()
                }
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding()
                .tenantThemedButton(isSecondary: true)
            }
        }
    }
    
    private var courseSpecificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Course Specifications")
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            VStack(spacing: 8) {
                SpecRow(label: "Total Holes", value: "\(course.numberOfHoles)", theme: theme)
                SpecRow(label: "Total Par", value: "\(course.par)", theme: theme)
                SpecRow(label: "Back Tees", value: "\(course.yardage.backTees) yards", theme: theme)
                SpecRow(label: "Regular Tees", value: "\(course.yardage.regularTees) yards", theme: theme)
                SpecRow(label: "Forward Tees", value: "\(course.yardage.forwardTees) yards", theme: theme)
            }
        }
    }
    
    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Difficulty Level")
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            HStack {
                Circle()
                    .fill(course.difficultyColor)
                    .frame(width: 20, height: 20)
                
                Text(course.difficulty.displayName)
                    .font(.body.weight(.medium))
                    .foregroundColor(theme.textSwiftUIColor)
                
                Spacer()
                
                Text(course.difficulty.shortName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(course.difficultyColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(course.difficultyColor.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }
    
    private var operatingHoursSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operating Hours")
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Today: 6:00 AM - 8:00 PM")
                    .font(.body.weight(.medium))
                    .foregroundColor(theme.textSwiftUIColor)
                
                Text("Open daily, weather permitting")
                    .font(.subheadline)
                    .foregroundColor(theme.subtextSwiftUIColor)
            }
        }
    }
    
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contact Information")
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            VStack(alignment: .leading, spacing: 8) {
                ContactRow(
                    icon: "phone.fill",
                    text: "+1 (555) 123-4567",
                    theme: theme
                ) {
                    callCourse()
                }
                
                ContactRow(
                    icon: "location.fill",
                    text: course.address,
                    theme: theme
                ) {
                    openDirections()
                }
                
                if let website = branding.websiteURL {
                    ContactRow(
                        icon: "globe",
                        text: website,
                        theme: theme
                    ) {
                        openWebsite(website)
                    }
                }
            }
        }
    }
    
    // MARK: - Toolbar Buttons
    
    private var shareButton: some View {
        Button {
            hapticService.impact(.light)
            shareCourse()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(theme.primarySwiftUIColor)
        }
    }
    
    private var favoriteButton: some View {
        Button {
            hapticService.selection()
            toggleFavorite()
        } label: {
            Image(systemName: "heart") // Could be heart.fill if favorited
                .foregroundColor(theme.primarySwiftUIColor)
        }
    }
    
    // MARK: - Actions
    
    private func callCourse() {
        if let url = URL(string: "tel://+15551234567") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openDirections() {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: course.coordinate))
        mapItem.name = course.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
    
    private func openWebsite(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func shareCourse() {
        // Implement sharing functionality
    }
    
    private func toggleFavorite() {
        // Implement favorite toggling
    }
    
    private func trackViewAppearance() {
        analyticsService.track("course_detail_viewed", parameters: [
            "course_id": course.id,
            "course_name": course.name,
            "brand_name": brandName,
            "rating": course.averageRating,
            "difficulty": course.difficulty.rawValue
        ])
    }
}

// MARK: - Supporting Components

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let theme: WhiteLabelTheme
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(theme.primarySwiftUIColor)
            
            Text(value)
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            Text(label)
                .font(.caption)
                .foregroundColor(theme.subtextSwiftUIColor)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let theme: WhiteLabelTheme
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.body.weight(isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? theme.primarySwiftUIColor : theme.subtextSwiftUIColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(isSelected ? theme.primarySwiftUIColor.opacity(0.1) : Color.clear)
                )
                .overlay(
                    Rectangle()
                        .fill(isSelected ? theme.primarySwiftUIColor : Color.clear)
                        .frame(height: 2),
                    alignment: .bottom
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let theme: WhiteLabelTheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(theme.accentSwiftUIColor)
            
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.textSwiftUIColor)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(theme.subtextSwiftUIColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(theme.surfaceSwiftUIColor)
        .cornerRadius(theme.cornerRadius)
        .shadow(
            color: .black.opacity(theme.shadowOpacity),
            radius: 1,
            x: 0,
            y: 1
        )
    }
}

struct SpecRow: View {
    let label: String
    let value: String
    let theme: WhiteLabelTheme
    
    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(theme.subtextSwiftUIColor)
            
            Spacer()
            
            Text(value)
                .font(.body.weight(.medium))
                .foregroundColor(theme.textSwiftUIColor)
        }
    }
}

struct ContactRow: View {
    let icon: String
    let text: String
    let theme: WhiteLabelTheme
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(theme.primarySwiftUIColor)
                    .frame(width: 20)
                
                Text(text)
                    .font(.body)
                    .foregroundColor(theme.textSwiftUIColor)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(theme.subtextSwiftUIColor)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Placeholder Booking Sheet

struct BrandedBookingSheet: View {
    let course: SharedGolfCourse
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Booking for \(course.name)")
                    .font(.title2)
                    .padding()
                
                Text("Booking functionality would be implemented here")
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Book Tee Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BrandedCourseDetailSheet(
        course: SharedGolfCourse(
            id: "pine-valley",
            name: "Pine Valley Golf Course",
            address: "123 Golf Drive",
            city: "Pine Valley",
            state: "CA",
            latitude: 37.7749,
            longitude: -122.4194,
            numberOfHoles: 18,
            par: 72,
            yardage: SharedCourseYardage(backTees: 7200, regularTees: 6800, forwardTees: 6200),
            hasGPS: true,
            hasDrivingRange: true,
            hasRestaurant: true,
            cartRequired: false,
            averageRating: 4.5,
            difficulty: .intermediate,
            isOpen: true,
            isActive: true
        )
    )
    .environmentObject(ServiceContainer.shared)
}