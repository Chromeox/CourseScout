import SwiftUI

// MARK: - Branded Filter Sheet

struct BrandedFilterSheet: View {
    
    @Binding var selectedFilter: CourseFilter
    let onApply: (CourseFilter) -> Void
    let onReset: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var tempFilter: CourseFilter
    
    // MARK: - Tenant Theming
    @TenantInjected(\.theme) private var theme: WhiteLabelTheme
    @TenantInjected(\.branding) private var branding: TenantBranding
    @TenantInjected(\.features) private var features: TenantFeatures
    
    // MARK: - Services
    @ServiceInjected(HapticFeedbackServiceProtocol.self)
    private var hapticService: HapticFeedbackServiceProtocol
    
    init(
        selectedFilter: Binding<CourseFilter>,
        onApply: @escaping (CourseFilter) -> Void,
        onReset: @escaping () -> Void
    ) {
        self._selectedFilter = selectedFilter
        self.onApply = onApply
        self.onReset = onReset
        self._tempFilter = State(initialValue: selectedFilter.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Filter Options
                ScrollView {
                    VStack(spacing: 20) {
                        filterOptionsSection
                        
                        if features.enableAdvancedAnalytics {
                            advancedFiltersSection
                        }
                        
                        if features.enableGPSRangefinder || features.enableWeatherIntegration {
                            featureFiltersSection
                        }
                        
                        amenityFiltersSection
                        
                        Spacer(minLength: 100) // Space for bottom buttons
                    }
                    .padding()
                }
                
                // Bottom Actions
                bottomActionsSection
            }
            .background(theme.backgroundSwiftUIColor)
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tenantThemed()
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Brand Logo and Title
            HStack {
                AsyncImage(url: URL(string: branding.logoURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(theme.primarySwiftUIColor)
                }
                .frame(width: 32, height: 32)
                
                Text("Filter Courses")
                    .font(.title2.weight(theme.headerFontWeight.swiftUIWeight))
                    .foregroundColor(theme.textSwiftUIColor)
                
                Spacer()
                
                Button("Done") {
                    hapticService.impact(.light)
                    dismiss()
                }
                .font(.body.weight(.medium))
                .foregroundColor(theme.primarySwiftUIColor)
            }
            
            // Current Selection
            if tempFilter != .all {
                HStack {
                    Image(systemName: tempFilter.systemImage)
                        .foregroundColor(theme.accentSwiftUIColor)
                    
                    Text("Current: \(tempFilter.displayName)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.textSwiftUIColor)
                    
                    Spacer()
                    
                    Button("Clear") {
                        hapticService.impact(.light)
                        tempFilter = .all
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(theme.secondarySwiftUIColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(theme.accentSwiftUIColor.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(theme.surfaceSwiftUIColor)
        .shadow(
            color: .black.opacity(theme.shadowOpacity),
            radius: 2,
            x: 0,
            y: 1
        )
    }
    
    // MARK: - Filter Options Section
    
    private var filterOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter Options")
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(CourseFilter.allCases, id: \.self) { filter in
                    FilterOptionCard(
                        filter: filter,
                        isSelected: tempFilter == filter,
                        theme: theme
                    ) {
                        hapticService.selection()
                        tempFilter = filter
                    }
                }
            }
        }
    }
    
    // MARK: - Advanced Filters Section
    
    private var advancedFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced Filters")
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            VStack(spacing: 8) {
                AdvancedFilterRow(
                    title: "Rating 4.5+",
                    subtitle: "Exceptional courses only",
                    icon: "star.fill",
                    isSelected: tempFilter == .highRated,
                    theme: theme
                ) {
                    hapticService.selection()
                    tempFilter = tempFilter == .highRated ? .all : .highRated
                }
                
                AdvancedFilterRow(
                    title: "Featured Courses",
                    subtitle: "Editor's picks and premium courses",
                    icon: "crown.fill",
                    isSelected: tempFilter == .featured,
                    theme: theme
                ) {
                    hapticService.selection()
                    tempFilter = tempFilter == .featured ? .all : .featured
                }
            }
        }
    }
    
    // MARK: - Feature Filters Section
    
    private var featureFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Technology Features")
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            VStack(spacing: 8) {
                if features.enableGPSRangefinder {
                    AdvancedFilterRow(
                        title: "GPS Enabled",
                        subtitle: "Courses with GPS rangefinder support",
                        icon: "location.circle.fill",
                        isSelected: tempFilter == .hasGPS,
                        theme: theme
                    ) {
                        hapticService.selection()
                        tempFilter = tempFilter == .hasGPS ? .all : .hasGPS
                    }
                }
            }
        }
    }
    
    // MARK: - Amenity Filters Section
    
    private var amenityFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Course Amenities")
                .font(.headline.weight(theme.headerFontWeight.swiftUIWeight))
                .foregroundColor(theme.textSwiftUIColor)
            
            VStack(spacing: 8) {
                AdvancedFilterRow(
                    title: "Restaurant & Bar",
                    subtitle: "Dining options available",
                    icon: "fork.knife",
                    isSelected: tempFilter == .hasRestaurant,
                    theme: theme
                ) {
                    hapticService.selection()
                    tempFilter = tempFilter == .hasRestaurant ? .all : .hasRestaurant
                }
                
                AdvancedFilterRow(
                    title: "Nearby Courses",
                    subtitle: "Within 25 miles of your location",
                    icon: "location.fill",
                    isSelected: tempFilter == .nearby,
                    theme: theme
                ) {
                    hapticService.selection()
                    tempFilter = tempFilter == .nearby ? .all : .nearby
                }
            }
        }
    }
    
    // MARK: - Bottom Actions Section
    
    private var bottomActionsSection: some View {
        VStack(spacing: 12) {
            Divider()
            
            HStack(spacing: 12) {
                // Reset Button
                Button("Reset All") {
                    hapticService.impact(.medium)
                    tempFilter = .all
                    onReset()
                }
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding()
                .background(theme.surfaceSwiftUIColor)
                .foregroundColor(theme.subtextSwiftUIColor)
                .cornerRadius(theme.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .stroke(theme.subtextSwiftUIColor.opacity(0.3), lineWidth: 1)
                )
                
                // Apply Button
                Button("Apply Filter") {
                    hapticService.notification(.success)
                    onApply(tempFilter)
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .tenantThemedButton()
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(theme.backgroundSwiftUIColor)
    }
}

// MARK: - Filter Option Card

struct FilterOptionCard: View {
    let filter: CourseFilter
    let isSelected: Bool
    let theme: WhiteLabelTheme
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: filter.systemImage)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : theme.primarySwiftUIColor)
                
                Text(filter.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(isSelected ? .white : theme.textSwiftUIColor)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.vertical, 12)
            .background(
                isSelected ? theme.primarySwiftUIColor : theme.surfaceSwiftUIColor
            )
            .cornerRadius(theme.cornerRadius)
            .shadow(
                color: .black.opacity(isSelected ? theme.shadowOpacity * 2 : theme.shadowOpacity),
                radius: isSelected ? 4 : 2,
                x: 0,
                y: isSelected ? 2 : 1
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Advanced Filter Row

struct AdvancedFilterRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let theme: WhiteLabelTheme
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? theme.primarySwiftUIColor : theme.subtextSwiftUIColor)
                    .frame(width: 24, height: 24)
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(theme.textSwiftUIColor)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(theme.subtextSwiftUIColor)
                }
                
                Spacer()
                
                // Selection Indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? theme.primarySwiftUIColor : theme.subtextSwiftUIColor)
            }
            .padding()
            .background(isSelected ? theme.primarySwiftUIColor.opacity(0.1) : theme.surfaceSwiftUIColor)
            .cornerRadius(theme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(
                        isSelected ? theme.primarySwiftUIColor.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Quick Filter Chips

struct QuickFilterChips: View {
    let filters: [CourseFilter]
    @Binding var selectedFilter: CourseFilter
    let theme: WhiteLabelTheme
    let onFilterTap: (CourseFilter) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    FilterChip(
                        filter: filter,
                        isSelected: selectedFilter == filter,
                        theme: theme
                    ) {
                        onFilterTap(filter)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct FilterChip: View {
    let filter: CourseFilter
    let isSelected: Bool
    let theme: WhiteLabelTheme
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: filter.systemImage)
                    .font(.caption)
                
                Text(filter.displayName)
                    .font(.caption.weight(.medium))
            }
            .foregroundColor(isSelected ? .white : theme.primarySwiftUIColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? theme.primarySwiftUIColor : theme.primarySwiftUIColor.opacity(0.1)
            )
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    BrandedFilterSheet(
        selectedFilter: .constant(.all),
        onApply: { _ in },
        onReset: { }
    )
    .environmentObject(ServiceContainer.shared)
}