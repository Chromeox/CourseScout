import SwiftUI
import MapKit

struct CourseDetailSheet: View {
    let course: GolfCourse
    
    @Environment(\.dismiss) private var dismiss
    @ServiceInjected(WeatherServiceProtocol.self) private var weatherService
    @ServiceInjected(LocationServiceProtocol.self) private var locationService
    @ServiceInjected(MapServiceProtocol.self) private var mapService
    @ServiceInjected(HapticFeedbackServiceProtocol.self) private var hapticService
    @ServiceInjected(GolfCourseServiceProtocol.self) private var golfCourseService
    
    @State private var selectedTab: DetailTab = .overview
    @State private var currentWeather: WeatherConditions?
    @State private var courseConditions: CourseConditions?
    @State private var courseLayout: [HoleInfo] = []
    @State private var courseImages: [CourseImage] = []
    @State private var courseReviews: [CourseReview] = []
    @State private var isLoading = false
    @State private var showDirections = false
    @State private var route: MKRoute?
    @State private var isFavorite = false
    
    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case layout = "Layout"
        case conditions = "Conditions"
        case reviews = "Reviews"
        
        var icon: String {
            switch self {
            case .overview: return "info.circle"
            case .layout: return "map"
            case .conditions: return "cloud.sun"
            case .reviews: return "star"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header section
                headerSection
                
                // Tab selection
                tabSelector
                
                // Content based on selected tab
                ScrollView {
                    LazyVStack(spacing: 16) {
                        switch selectedTab {
                        case .overview:
                            overviewContent
                        case .layout:
                            layoutContent
                        case .conditions:
                            conditionsContent
                        case .reviews:
                            reviewsContent
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                loadCourseDetails()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            // Course hero image
            AsyncImage(url: URL(string: course.primaryImage ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [.green.opacity(0.3), .blue.opacity(0.3)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay {
                        Image(systemName: "figure.golf")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.7))
                    }
            }
            .frame(height: 200)
            .clipped()
            .overlay(alignment: .topTrailing) {
                closeButton
            }
            .overlay(alignment: .bottomLeading) {
                courseHeaderInfo
            }
        }
    }
    
    private var closeButton: some View {
        Button(action: {
            dismiss()
            hapticService.impact(.light)
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
        }
        .padding()
    }
    
    private var courseHeaderInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("\(course.city), \(course.state)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            
            HStack {
                HStack {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= Int(course.averageRating.rounded()) ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                    Text("(\(course.totalReviews))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Text(course.priceRange)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.7)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                    hapticService.impact(.light)
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.caption)
                        Text(tab.rawValue)
                            .font(.caption)
                    }
                    .foregroundColor(selectedTab == tab ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.separator),
            alignment: .bottom
        )
    }
    
    // MARK: - Overview Content
    
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Quick actions
            quickActionsSection
            
            // Course stats
            courseStatsSection
            
            // Description
            if let description = course.description {
                descriptionSection(description)
            }
            
            // Amenities
            amenitiesSection
            
            // Operating hours
            operatingHoursSection
            
            // Contact information
            contactSection
        }
    }
    
    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            actionButton("Get Directions", icon: "car.fill", color: .blue) {
                getDirections()
            }
            
            actionButton("Call Course", icon: "phone.fill", color: .green) {
                callCourse()
            }
            
            actionButton(isFavorite ? "Favorited" : "Add Favorite", 
                        icon: isFavorite ? "heart.fill" : "heart", 
                        color: .red) {
                toggleFavorite()
            }
        }
    }
    
    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            hapticService.impact(.medium)
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private var courseStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Course Information")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statCard("Par", value: "\(course.par)")
                statCard("Holes", value: "\(course.numberOfHoles)")
                statCard("Yardage", value: "\(course.yardage.regularTees)")
                statCard("Difficulty", value: course.difficulty.displayName)
            }
        }
    }
    
    private func statCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
            Text(description)
                .font(.body)
        }
    }
    
    private var amenitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Amenities")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(course.amenities, id: \.self) { amenity in
                    HStack {
                        Image(systemName: amenity.icon)
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(amenity.displayName)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
    }
    
    private var operatingHoursSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Operating Hours")
                .font(.headline)
            
            let today = Calendar.current.component(.weekday, from: Date())
            let dayName = Calendar.current.weekdaySymbols[today - 1]
            let todayHours = course.operatingHours.hoursForDay(dayName)
            
            Text("Today (\(dayName)): \(todayHours.formattedHours)")
                .font(.body)
                .fontWeight(.medium)
            
            Text("See full hours")
                .font(.caption)
                .foregroundColor(.blue)
        }
    }
    
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contact")
                .font(.headline)
            
            if let phone = course.phoneNumber {
                Text("Phone: \(phone)")
                    .font(.body)
            }
            
            if let website = course.website {
                Link("Visit Website", destination: URL(string: website)!)
                    .font(.body)
                    .foregroundColor(.blue)
            }
            
            Text(course.fullAddress)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Layout Content
    
    private var layoutContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Course Layout")
                .font(.headline)
            
            if courseLayout.isEmpty {
                ContentUnavailableView(
                    "Layout Information Unavailable",
                    systemImage: "map",
                    description: Text("Course layout details are not available")
                )
            } else {
                ForEach(courseLayout) { hole in
                    HoleDetailCard(hole: hole)
                }
            }
        }
    }
    
    // MARK: - Conditions Content
    
    private var conditionsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current weather
            if let weather = currentWeather {
                weatherSection(weather)
            }
            
            // Course conditions
            if let conditions = courseConditions {
                courseConditionsSection(conditions)
            } else {
                ContentUnavailableView(
                    "Course Conditions Unavailable",
                    systemImage: "cloud.sun",
                    description: Text("Current course conditions are not available")
                )
            }
        }
    }
    
    private func weatherSection(_ weather: WeatherConditions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Weather")
                .font(.headline)
            
            HStack {
                Image(systemName: weather.conditions.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text("\(weather.formattedTemperature)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(weather.conditions.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(weather.playabilityDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Golf Score: \(weather.playabilityScore)/10")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            
            HStack {
                weatherDetail("Wind", value: weather.formattedWind)
                Spacer()
                weatherDetail("Humidity", value: "\(Int(weather.humidity))%")
                Spacer()
                weatherDetail("UV Index", value: "\(weather.uvIndex)")
            }
        }
    }
    
    private func weatherDetail(_ title: String, value: String) -> some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    
    private func courseConditionsSection(_ conditions: CourseConditions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Course Conditions")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                conditionCard("Greens", condition: conditions.greensCondition, detail: "Speed: \(conditions.greensSpeed)")
                conditionCard("Fairways", condition: conditions.fairwayCondition, detail: conditions.firmness.displayName)
                conditionCard("Rough", condition: conditions.roughCondition, detail: conditions.moisture.displayName)
                conditionCard("Bunkers", condition: conditions.bunkerCondition, detail: "Maintained")
            }
            
            if !conditions.maintenance.isEmpty {
                maintenanceSection(conditions.maintenance)
            }
        }
    }
    
    private func conditionCard(_ title: String, condition: ConditionQuality, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(condition.displayName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(Color(condition.color))
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private func maintenanceSection(_ issues: [MaintenanceIssue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Maintenance Notes")
                .font(.subheadline)
                .fontWeight(.medium)
            
            ForEach(issues, id: \.self) { issue in
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text(issue.displayName)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Reviews Content
    
    private var reviewsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reviews")
                .font(.headline)
            
            if courseReviews.isEmpty {
                ContentUnavailableView(
                    "No Reviews Available",
                    systemImage: "star",
                    description: Text("Be the first to review this course")
                )
            } else {
                ForEach(courseReviews) { review in
                    ReviewCard(review: review)
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadCourseDetails() {
        isLoading = true
        
        Task {
            do {
                // Load course weather
                let weather = try await weatherService.getWeatherForGolfCourse(course)
                await MainActor.run {
                    currentWeather = weather
                }
                
                // Load course conditions
                let conditions = try await golfCourseService.getCourseConditions(courseId: course.id)
                await MainActor.run {
                    courseConditions = conditions
                }
                
                // Load course layout
                let layout = try await golfCourseService.getCourseLayout(courseId: course.id)
                await MainActor.run {
                    courseLayout = layout
                }
                
                // Load course images
                let images = try await golfCourseService.getCourseImages(courseId: course.id)
                await MainActor.run {
                    courseImages = images
                }
                
                // Load recent reviews
                let reviewPage = try await golfCourseService.getCourseReviews(courseId: course.id, page: 1, limit: 10)
                await MainActor.run {
                    courseReviews = reviewPage.reviews
                }
                
            } catch {
                print("Error loading course details: \(error)")
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func getDirections() {
        Task {
            do {
                let calculatedRoute = try await mapService.getDirections(to: course, from: locationService.currentLocation)
                await MainActor.run {
                    route = calculatedRoute
                    showDirections = true
                }
            } catch {
                print("Error getting directions: \(error)")
            }
        }
    }
    
    private func callCourse() {
        guard let phoneNumber = course.phoneNumber else { return }
        let phone = "tel://\(phoneNumber.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: ""))"
        guard let url = URL(string: phone) else { return }
        UIApplication.shared.open(url)
    }
    
    private func toggleFavorite() {
        isFavorite.toggle()
        
        Task {
            do {
                if isFavorite {
                    try await golfCourseService.addToFavorites(courseId: course.id, userId: "current_user")
                    hapticService.notification(.success)
                } else {
                    try await golfCourseService.removeFromFavorites(courseId: course.id, userId: "current_user")
                }
            } catch {
                // Revert on error
                await MainActor.run {
                    isFavorite.toggle()
                }
                hapticService.notification(.error)
            }
        }
    }
}

// MARK: - Supporting Views

struct HoleDetailCard: View {
    let hole: HoleInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hole \(hole.holeNumber)")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("Par \(hole.par)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                
                if let yardage = hole.yardages["Regular"] {
                    Text("\(yardage) yds")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if let description = hole.description {
                Text(description)
                    .font(.body)
            }
            
            if let proTip = hole.proTip {
                HStack {
                    Image(systemName: "lightbulb")
                        .foregroundColor(.yellow)
                    Text(proTip)
                        .font(.caption)
                        .italic()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ReviewCard: View {
    let review: CourseReview
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(review.userName)
                    .font(.headline)
                
                Spacer()
                
                HStack {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= review.rating ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }
            }
            
            if let title = review.title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Text(review.review)
                .font(.body)
            
            HStack {
                if let playedDate = review.playedDate {
                    Text("Played \(playedDate, format: .dateTime.month().day().year())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if review.isVerifiedPlay {
                    HStack {
                        Image(systemName: "checkmark.seal")
                            .foregroundColor(.blue)
                        Text("Verified")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    CourseDetailSheet(course: GolfCourse(
        id: "1",
        name: "Pebble Beach Golf Links",
        address: "1700 17 Mile Dr",
        city: "Pebble Beach",
        state: "CA",
        country: "US",
        zipCode: "93953",
        latitude: 36.5621,
        longitude: -121.9490,
        description: "One of the most beautiful and challenging golf courses in the world.",
        phoneNumber: "(831) 624-3811",
        website: "https://www.pebblebeach.com",
        email: nil,
        numberOfHoles: 18,
        par: 72,
        yardage: CourseYardage(championshipTees: 6828, backTees: 6536, regularTees: 6023, forwardTees: 5197, seniorTees: nil, juniorTees: nil),
        slope: CourseSlope(championshipSlope: 145, backSlope: 142, regularSlope: 130, forwardSlope: 122, seniorSlope: nil, juniorSlope: nil),
        rating: CourseRating(championshipRating: 75.5, backRating: 73.2, regularRating: 69.7, forwardRating: 64.8, seniorRating: nil, juniorRating: nil),
        pricing: CoursePricing(weekdayRates: [595], weekendRates: [595], twilightRates: [395], seniorRates: nil, juniorRates: nil, cartFee: 50, cartIncluded: true, membershipRequired: false, guestPolicy: .open, seasonalMultiplier: 1.0, peakTimeMultiplier: 1.0, advanceBookingDiscount: nil),
        amenities: [.drivingRange, .puttingGreen, .proShop, .restaurant, .bar],
        dressCode: .strict,
        cartPolicy: .required,
        images: [],
        virtualTour: nil,
        averageRating: 4.8,
        totalReviews: 1247,
        difficulty: .championship,
        operatingHours: OperatingHours(monday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), tuesday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), wednesday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), thursday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), friday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), saturday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), sunday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00")),
        seasonalInfo: nil,
        bookingPolicy: BookingPolicy(advanceBookingDays: 30, cancellationPolicy: "24-hour cancellation policy", noShowPolicy: "No-shows will be charged full amount", modificationPolicy: "Changes allowed up to 24 hours", depositRequired: true, depositAmount: 100, refundableDeposit: false, groupBookingMinimum: 8, onlineBookingAvailable: true, phoneBookingRequired: false),
        createdAt: Date(),
        updatedAt: Date(),
        isActive: true,
        isFeatured: true
    ))
    .withServiceContainer()
}