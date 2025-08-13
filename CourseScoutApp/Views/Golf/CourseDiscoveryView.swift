import SwiftUI
import MapKit
import CoreLocation

struct CourseDiscoveryView: View {
    
    // MARK: - Service Dependencies
    
    @ServiceInjected(GolfCourseServiceProtocol.self) private var golfCourseService
    @ServiceInjected(LocationServiceProtocol.self) private var locationService
    @ServiceInjected(WeatherServiceProtocol.self) private var weatherService
    @ServiceInjected(MapServiceProtocol.self) private var mapService
    @ServiceInjected(HapticFeedbackServiceProtocol.self) private var hapticService
    
    // MARK: - State Properties
    
    @State private var selectedCourse: GolfCourse?
    @State private var showCourseDetail = false
    @State private var showFilterSheet = false
    @State private var searchText = ""
    @State private var searchFilters = CourseSearchFilters()
    @State private var discoveredCourses: [GolfCourse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    // Weather and location state
    @State private var currentWeather: WeatherConditions?
    @State private var golfPlayabilityScore: GolfPlayabilityScore?
    @State private var optimalTeeTimes: [OptimalTeeTime] = []
    
    // Map configuration
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var showMap = true
    
    var body: some View {
        NavigationView {
            ZStack {
                if showMap {
                    mapView
                } else {
                    listView
                }
                
                // Loading overlay
                if isLoading {
                    loadingOverlay
                }
            }
            .navigationTitle("Golf Course Discovery")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    filterButton
                    toggleViewButton
                }
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    weatherButton
                }
            }
            .searchable(text: $searchText, prompt: "Search golf courses...")
            .onSubmit(of: .search) {
                performSearch()
            }
            .sheet(isPresented: $showFilterSheet) {
                CourseFilterSheet(filters: $searchFilters) {
                    applyFiltersAndSearch()
                }
            }
            .sheet(item: $selectedCourse) { course in
                CourseDetailSheet(course: course)
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .onAppear {
                setupInitialLocation()
                loadNearbyCoursesWithHaptics()
            }
        }
    }
    
    // MARK: - Map View
    
    private var mapView: some View {
        ZStack(alignment: .bottom) {
            GolfCourseMapView(
                region: $mapRegion,
                annotations: mapService.annotations,
                selectedAnnotation: $mapService.selectedAnnotation,
                onAnnotationTap: { annotation in
                    selectedCourse = annotation.course
                    hapticService.impact(.light)
                },
                onRegionChange: { region in
                    mapRegion = region
                    loadCoursesForRegion(region)
                }
            )
            
            if let playabilityScore = golfPlayabilityScore {
                golfConditionsCard(playabilityScore)
            }
        }
    }
    
    // MARK: - List View
    
    private var listView: some View {
        List {
            // Weather conditions section
            if let weather = currentWeather {
                weatherConditionsSection(weather)
            }
            
            // Optimal tee times section
            if !optimalTeeTimes.isEmpty {
                optimalTeeTimesSection
            }
            
            // Discovered courses section
            coursesSection
        }
        .refreshable {
            await refreshData()
        }
    }
    
    private var coursesSection: some View {
        Section("Nearby Golf Courses") {
            if discoveredCourses.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Golf Courses Found",
                    systemImage: "figure.golf",
                    description: Text("Try adjusting your search or location")
                )
            } else {
                ForEach(discoveredCourses) { course in
                    CourseListRow(course: course) {
                        selectedCourse = course
                        hapticService.selection()
                    }
                }
            }
        }
    }
    
    private var optimalTeeTimesSection: some View {
        Section("Optimal Tee Times Today") {
            ForEach(optimalTeeTimes.prefix(3)) { teeTime in
                OptimalTeeTimeRow(teeTime: teeTime)
            }
        }
    }
    
    // MARK: - UI Components
    
    private var filterButton: some View {
        Button(action: {
            showFilterSheet = true
            hapticService.impact(.light)
        }) {
            Image(systemName: "slider.horizontal.3")
        }
    }
    
    private var toggleViewButton: some View {
        Button(action: {
            showMap.toggle()
            hapticService.impact(.light)
        }) {
            Image(systemName: showMap ? "list.bullet" : "map")
        }
    }
    
    private var weatherButton: some View {
        Button(action: {
            loadWeatherData()
            hapticService.impact(.light)
        }) {
            if let weather = currentWeather {
                Image(systemName: weather.conditions.icon)
                    .foregroundColor(weatherIconColor(weather))
            } else {
                Image(systemName: "cloud.fill")
            }
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Finding Golf Courses...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding()
            .background(Material.regular)
            .cornerRadius(12)
        }
    }
    
    private func golfConditionsCard(_ score: GolfPlayabilityScore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.golf")
                    .foregroundColor(.green)
                Text("Golf Conditions")
                    .font(.headline)
                Spacer()
                Text("\(score.overallScore)/10")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(playabilityColor(score.overallScore))
            }
            
            HStack {
                Text(score.recommendation.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(score.conditions.temperature))°F")
                    .font(.subheadline)
            }
            
            Text(score.recommendation.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Material.regular)
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom)
    }
    
    private func weatherConditionsSection(_ weather: WeatherConditions) -> some View {
        Section("Weather Conditions") {
            HStack {
                Image(systemName: weather.conditions.icon)
                    .foregroundColor(weatherIconColor(weather))
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(weather.conditions.displayName)
                        .font(.headline)
                    Text("\(weather.formattedTemperature) • \(weather.formattedWind)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(weather.playabilityDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(playabilityColor(weather.playabilityScore))
                    Text("Golf Score: \(weather.playabilityScore)/10")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Helper Functions
    
    private func setupInitialLocation() {
        locationService.requestLocationPermission()
        
        if let currentLocation = locationService.currentLocation {
            let region = MKCoordinateRegion(
                center: currentLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
            mapRegion = region
            mapService.updateRegion(to: region)
        }
    }
    
    private func loadNearbyCoursesWithHaptics() {
        Task {
            await MainActor.run {
                isLoading = true
                hapticService.impact(.medium)
            }
            
            await loadNearbyCoursesAndWeather()
            
            await MainActor.run {
                isLoading = false
                if !discoveredCourses.isEmpty {
                    hapticService.notification(.success)
                }
            }
        }
    }
    
    @MainActor
    private func loadNearbyCoursesAndWeather() async {
        guard let currentLocation = locationService.currentLocation else {
            errorMessage = "Location not available"
            showErrorAlert = true
            return
        }
        
        do {
            // Load golf courses
            let courses = try await golfCourseService.searchCourses(
                near: currentLocation,
                radius: 25.0, // 25 mile radius
                filters: searchFilters
            )
            discoveredCourses = courses
            
            // Load weather data
            await loadWeatherData()
            
            // Load optimal tee times for today
            await loadOptimalTeeTimes()
            
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
            hapticService.notification(.error)
        }
    }
    
    private func loadWeatherData() {
        Task {
            guard let currentLocation = locationService.currentLocation else { return }
            
            do {
                let weather = try await weatherService.getCurrentWeather(for: currentLocation)
                let playability = try await weatherService.getGolfPlayabilityScore(for: currentLocation)
                
                await MainActor.run {
                    currentWeather = weather
                    golfPlayabilityScore = playability
                }
            } catch {
                print("Error loading weather: \(error)")
            }
        }
    }
    
    private func loadOptimalTeeTimes() async {
        guard let currentLocation = locationService.currentLocation else { return }
        
        do {
            let times = try await weatherService.getOptimalTeeTimesForDay(
                location: currentLocation,
                date: Date()
            )
            
            await MainActor.run {
                optimalTeeTimes = Array(times.prefix(5))
            }
        } catch {
            print("Error loading optimal tee times: \(error)")
        }
    }
    
    private func loadCoursesForRegion(_ region: MKCoordinateRegion) {
        Task {
            await mapService.loadGolfCourses(in: region)
            
            // Update discovered courses from map annotations
            await MainActor.run {
                discoveredCourses = mapService.annotations.map { $0.course }
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            loadNearbyCoursesWithHaptics()
            return
        }
        
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            do {
                let courses = try await golfCourseService.searchCourses(
                    query: searchText,
                    location: locationService.currentLocation,
                    filters: searchFilters
                )
                
                await MainActor.run {
                    discoveredCourses = courses
                    isLoading = false
                    hapticService.impact(.light)
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                    isLoading = false
                    hapticService.notification(.error)
                }
            }
        }
    }
    
    private func applyFiltersAndSearch() {
        if searchText.isEmpty {
            loadNearbyCoursesWithHaptics()
        } else {
            performSearch()
        }
    }
    
    @MainActor
    private func refreshData() async {
        await loadNearbyCoursesAndWeather()
    }
    
    // MARK: - Style Helpers
    
    private func weatherIconColor(_ weather: WeatherConditions) -> Color {
        switch weather.conditions {
        case .sunny: return .yellow
        case .partlyCloudy: return .blue
        case .overcast: return .gray
        case .lightRain, .drizzle: return .blue
        case .heavyRain, .thunderstorm: return .purple
        case .fog: return .secondary
        case .snow: return .white
        }
    }
    
    private func playabilityColor(_ score: Int) -> Color {
        switch score {
        case 8...10: return .green
        case 6...7: return .blue
        case 4...5: return .orange
        default: return .red
        }
    }
}

// MARK: - Course List Row

struct CourseListRow: View {
    let course: GolfCourse
    let onTap: () -> Void
    
    @ServiceInjected(LocationServiceProtocol.self) private var locationService
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(course.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("\(course.city), \(course.state)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        HStack {
                            Text(course.formattedRating)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                        
                        if let distance = calculateDistance() {
                            Text(String(format: "%.1f mi", distance))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                HStack {
                    difficultyBadge
                    
                    Spacer()
                    
                    Text(course.priceRange)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                
                if !course.amenities.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(course.amenities.prefix(4)), id: \.self) { amenity in
                                amenityTag(amenity)
                            }
                            
                            if course.amenities.count > 4 {
                                Text("+\(course.amenities.count - 4)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var difficultyBadge: some View {
        Text(course.difficulty.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(course.difficulty.color))
            .cornerRadius(4)
    }
    
    private func amenityTag(_ amenity: CourseAmenity) -> some View {
        HStack(spacing: 4) {
            Image(systemName: amenity.icon)
            Text(amenity.displayName)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(4)
    }
    
    private func calculateDistance() -> Double? {
        guard let userLocation = locationService.currentLocation else { return nil }
        
        let courseLocation = CLLocation(latitude: course.latitude, longitude: course.longitude)
        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let distanceMeters = courseLocation.distance(from: userCLLocation)
        return distanceMeters * 0.000621371 // Convert to miles
    }
}

// MARK: - Optimal Tee Time Row

struct OptimalTeeTimeRow: View {
    let teeTime: OptimalTeeTime
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(teeTime.timeSlot)
                    .font(.headline)
                
                Text(teeTime.recommendation)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                HStack {
                    Text("\(teeTime.playabilityScore)/10")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(playabilityColor(teeTime.playabilityScore))
                    
                    Image(systemName: scoreIcon(teeTime.playabilityScore))
                        .foregroundColor(playabilityColor(teeTime.playabilityScore))
                }
                
                Text("\(Int(teeTime.temperature))°F • \(Int(teeTime.windSpeed)) mph")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func playabilityColor(_ score: Int) -> Color {
        switch score {
        case 8...10: return .green
        case 6...7: return .blue
        case 4...5: return .orange
        default: return .red
        }
    }
    
    private func scoreIcon(_ score: Int) -> String {
        switch score {
        case 8...10: return "checkmark.circle.fill"
        case 6...7: return "checkmark.circle"
        case 4...5: return "exclamationmark.triangle"
        default: return "xmark.circle"
        }
    }
}

// MARK: - Golf Course Map View

struct GolfCourseMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let annotations: [GolfCourseAnnotation]
    @Binding var selectedAnnotation: GolfCourseAnnotation?
    let onAnnotationTap: (GolfCourseAnnotation) -> Void
    let onRegionChange: (MKCoordinateRegion) -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.userTrackingMode = .none
        mapView.showsUserLocation = true
        mapView.mapType = .standard
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update region if significantly different
        if !mapView.region.isEqual(to: region, threshold: 0.001) {
            mapView.setRegion(region, animated: true)
        }
        
        // Update annotations
        let currentAnnotations = Set(mapView.annotations.compactMap { $0 as? GolfCourseAnnotation })
        let newAnnotations = Set(annotations)
        
        let toRemove = currentAnnotations.subtracting(newAnnotations)
        let toAdd = newAnnotations.subtracting(currentAnnotations)
        
        mapView.removeAnnotations(Array(toRemove))
        mapView.addAnnotations(Array(toAdd))
        
        // Update selected annotation
        if let selected = selectedAnnotation {
            mapView.selectAnnotation(selected, animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: GolfCourseMapView
        
        init(_ parent: GolfCourseMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
            parent.onRegionChange(mapView.region)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let golfAnnotation = annotation as? GolfCourseAnnotation else { return nil }
            
            let identifier = "GolfCourse"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            
            annotationView.markerTintColor = UIColor(golfAnnotation.annotationColor)
            annotationView.glyphImage = UIImage(systemName: golfAnnotation.annotationImage)
            annotationView.canShowCallout = true
            
            // Add detail button
            let button = UIButton(type: .detailDisclosure)
            annotationView.rightCalloutAccessoryView = button
            
            return annotationView
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? GolfCourseAnnotation else { return }
            parent.selectedAnnotation = annotation
            parent.onAnnotationTap(annotation)
        }
        
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let annotation = view.annotation as? GolfCourseAnnotation else { return }
            parent.onAnnotationTap(annotation)
        }
    }
}

// MARK: - Extensions

extension MKCoordinateRegion {
    func isEqual(to other: MKCoordinateRegion, threshold: Double) -> Bool {
        return abs(center.latitude - other.center.latitude) < threshold &&
               abs(center.longitude - other.center.longitude) < threshold &&
               abs(span.latitudeDelta - other.span.latitudeDelta) < threshold &&
               abs(span.longitudeDelta - other.span.longitudeDelta) < threshold
    }
}

extension GolfCourseAnnotation: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(course.id)
    }
    
    static func == (lhs: GolfCourseAnnotation, rhs: GolfCourseAnnotation) -> Bool {
        return lhs.course.id == rhs.course.id
    }
}

// MARK: - Preview

#Preview {
    CourseDiscoveryView()
        .withServiceContainer()
}