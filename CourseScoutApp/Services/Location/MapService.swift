import Foundation
import MapKit
import SwiftUI
import CoreLocation
import Combine

// MARK: - Map Service Protocol

protocol MapServiceProtocol: ObservableObject {
    // Map region management
    var currentRegion: MKCoordinateRegion { get }
    var annotations: [GolfCourseAnnotation] { get }
    var selectedAnnotation: GolfCourseAnnotation? { get }
    
    // Map operations
    func updateRegion(to region: MKCoordinateRegion)
    func centerMap(on coordinate: CLLocationCoordinate2D, radius: Double)
    func fitMapToAnnotations()
    
    // Golf course annotations
    func loadGolfCourses(in region: MKCoordinateRegion) async
    func addGolfCourseAnnotations(_ courses: [GolfCourse])
    func removeAllAnnotations()
    func selectAnnotation(_ annotation: GolfCourseAnnotation)
    func deselectAnnotation()
    
    // Clustering and performance
    func enableClustering(_ enable: Bool)
    func setClusteringDistance(_ distance: Double)
    var isClusteringEnabled: Bool { get }
    
    // Map overlays
    func addWeatherOverlay(for region: MKCoordinateRegion) async
    func removeWeatherOverlay()
    func addTrafficOverlay(_ enable: Bool)
    
    // Route planning
    func getDirections(to course: GolfCourse, from location: CLLocationCoordinate2D?) async throws -> MKRoute
    func showRoute(_ route: MKRoute)
    func clearRoute()
}

// MARK: - Golf Course Annotation

class GolfCourseAnnotation: NSObject, MKAnnotation {
    let course: GolfCourse
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    
    // Additional golf-specific properties
    let difficulty: DifficultyLevel
    let averageRating: Double
    let priceRange: String
    let distance: CLLocationDistance?
    
    init(course: GolfCourse, userLocation: CLLocationCoordinate2D? = nil) {
        self.course = course
        self.coordinate = course.coordinate
        self.title = course.name
        self.difficulty = course.difficulty
        self.averageRating = course.averageRating
        self.priceRange = course.priceRange
        
        // Calculate distance if user location is available
        if let userLocation = userLocation {
            let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            let courseCLLocation = CLLocation(latitude: course.latitude, longitude: course.longitude)
            self.distance = userCLLocation.distance(from: courseCLLocation)
            
            let distanceMiles = distance! * 0.000621371 // Convert meters to miles
            self.subtitle = String(format: "%.1f mi • %@ • %@", distanceMiles, course.formattedRating, course.priceRange)
        } else {
            self.distance = nil
            self.subtitle = "\(course.formattedRating) ⭐ • \(course.priceRange)"
        }
        
        super.init()
    }
    
    // Custom annotation view configuration
    var annotationImage: String {
        switch difficulty {
        case .beginner: return "flag.fill"
        case .intermediate: return "flag.2.crossed.fill"
        case .advanced: return "crown.fill"
        case .championship: return "star.fill"
        }
    }
    
    var annotationColor: UIColor {
        switch difficulty {
        case .beginner: return .systemGreen
        case .intermediate: return .systemBlue
        case .advanced: return .systemOrange
        case .championship: return .systemRed
        }
    }
}

// MARK: - Clustered Annotation

class GolfCourseClusterAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let memberAnnotations: [GolfCourseAnnotation]
    
    init(memberAnnotations: [GolfCourseAnnotation]) {
        self.memberAnnotations = memberAnnotations
        
        // Calculate center coordinate
        let totalLat = memberAnnotations.reduce(0) { $0 + $1.coordinate.latitude }
        let totalLon = memberAnnotations.reduce(0) { $0 + $1.coordinate.longitude }
        let count = Double(memberAnnotations.count)
        
        self.coordinate = CLLocationCoordinate2D(
            latitude: totalLat / count,
            longitude: totalLon / count
        )
        
        self.title = "\(memberAnnotations.count) Golf Courses"
        
        // Create subtitle with difficulty distribution
        let difficultyCount = Dictionary(grouping: memberAnnotations, by: { $0.difficulty })
            .mapValues { $0.count }
        
        let sortedDifficulties = difficultyCount.sorted { $0.value > $1.value }
        let topDifficulty = sortedDifficulties.first?.key.displayName ?? "Mixed"
        self.subtitle = "\(topDifficulty) & more"
        
        super.init()
    }
    
    var averageRating: Double {
        let totalRating = memberAnnotations.reduce(0) { $0 + $1.averageRating }
        return totalRating / Double(memberAnnotations.count)
    }
    
    var priceRange: String {
        let prices = memberAnnotations.compactMap { annotation -> Double? in
            let priceString = annotation.course.pricing.baseWeekdayRate
            return priceString
        }
        
        guard !prices.isEmpty else { return "Varies" }
        
        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 0
        return "$\(Int(minPrice))-$\(Int(maxPrice))"
    }
}

// MARK: - Weather Overlay

class WeatherOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let weatherData: WeatherConditions
    
    init(region: MKCoordinateRegion, weather: WeatherConditions) {
        self.coordinate = region.center
        self.weatherData = weather
        
        // Convert region to map rect
        let topLeft = CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        )
        let bottomRight = CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        )
        
        let topLeftMapPoint = MKMapPoint(topLeft)
        let bottomRightMapPoint = MKMapPoint(bottomRight)
        
        self.boundingMapRect = MKMapRect(
            x: topLeftMapPoint.x,
            y: topLeftMapPoint.y,
            width: bottomRightMapPoint.x - topLeftMapPoint.x,
            height: bottomRightMapPoint.y - topLeftMapPoint.y
        )
        
        super.init()
    }
}

// MARK: - Route Overlay

class GolfRouteOverlay: NSObject, MKOverlay {
    let route: MKRoute
    
    var coordinate: CLLocationCoordinate2D {
        route.polyline.coordinate
    }
    
    var boundingMapRect: MKMapRect {
        route.polyline.boundingMapRect
    }
    
    init(route: MKRoute) {
        self.route = route
        super.init()
    }
}

// MARK: - Map Service Implementation

@MainActor
class MapService: MapServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795), // Center of US
        span: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 10.0)
    )
    
    @Published var annotations: [GolfCourseAnnotation] = []
    @Published var selectedAnnotation: GolfCourseAnnotation?
    @Published var isClusteringEnabled: Bool = true
    
    // MARK: - Private Properties
    
    private var golfCourseService: GolfCourseServiceProtocol?
    private var weatherService: WeatherServiceProtocol?
    private var locationService: LocationServiceProtocol?
    
    private var clusteringDistance: Double = 100000 // 100km in meters
    private var clusteredAnnotations: [GolfCourseClusterAnnotation] = []
    
    // Overlays
    private var weatherOverlay: WeatherOverlay?
    private var routeOverlay: GolfRouteOverlay?
    private var isTrafficEnabled: Bool = false
    
    // Performance optimization
    private var lastRegionUpdate: Date = Date()
    private let regionUpdateThreshold: TimeInterval = 1.0 // 1 second
    private var courseLoadTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init() {
        setupServices()
    }
    
    init(golfCourseService: GolfCourseServiceProtocol, 
         weatherService: WeatherServiceProtocol, 
         locationService: LocationServiceProtocol) {
        self.golfCourseService = golfCourseService
        self.weatherService = weatherService
        self.locationService = locationService
    }
    
    private func setupServices() {
        let container = ServiceContainer.shared
        self.golfCourseService = container.golfCourseService()
        self.weatherService = container.weatherService()
        self.locationService = container.locationService()
    }
    
    // MARK: - Map Region Management
    
    func updateRegion(to region: MKCoordinateRegion) {
        let now = Date()
        
        // Throttle region updates to avoid excessive API calls
        guard now.timeIntervalSince(lastRegionUpdate) > regionUpdateThreshold else { return }
        
        lastRegionUpdate = now
        currentRegion = region
        
        // Load golf courses for the new region
        Task {
            await loadGolfCourses(in: region)
        }
    }
    
    func centerMap(on coordinate: CLLocationCoordinate2D, radius: Double) {
        let radiusInDegrees = radius / 111000.0 // Approximate conversion from meters to degrees
        
        let newRegion = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: radiusInDegrees * 2,
                longitudeDelta: radiusInDegrees * 2
            )
        )
        
        updateRegion(to: newRegion)
    }
    
    func fitMapToAnnotations() {
        guard !annotations.isEmpty else { return }
        
        var minLat = annotations.first!.coordinate.latitude
        var maxLat = minLat
        var minLon = annotations.first!.coordinate.longitude
        var maxLon = minLon
        
        for annotation in annotations {
            minLat = min(minLat, annotation.coordinate.latitude)
            maxLat = max(maxLat, annotation.coordinate.latitude)
            minLon = min(minLon, annotation.coordinate.longitude)
            maxLon = max(maxLon, annotation.coordinate.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.2, // Add 20% padding
            longitudeDelta: (maxLon - minLon) * 1.2
        )
        
        let region = MKCoordinateRegion(center: center, span: span)
        updateRegion(to: region)
    }
    
    // MARK: - Golf Course Annotations
    
    func loadGolfCourses(in region: MKCoordinateRegion) async {
        // Cancel any existing load task
        courseLoadTask?.cancel()
        
        courseLoadTask = Task { @MainActor in
            guard let golfCourseService = golfCourseService else { return }
            
            do {
                // Calculate search radius from region span
                let radiusInDegrees = max(region.span.latitudeDelta, region.span.longitudeDelta) / 2
                let radiusInMeters = radiusInDegrees * 111000 // Convert to meters
                let radiusInMiles = radiusInMeters * 0.000621371 // Convert to miles
                
                let courses = try await golfCourseService.searchCourses(
                    near: region.center,
                    radius: radiusInMiles,
                    filters: nil
                )
                
                // Check if task was cancelled
                guard !Task.isCancelled else { return }
                
                addGolfCourseAnnotations(courses)
                
            } catch {
                print("Error loading golf courses: \(error)")
            }
        }
    }
    
    func addGolfCourseAnnotations(_ courses: [GolfCourse]) {
        // Get user location for distance calculation
        let userLocation = locationService?.currentLocation
        
        let newAnnotations = courses.map { course in
            GolfCourseAnnotation(course: course, userLocation: userLocation)
        }
        
        // Update annotations on main thread
        annotations = newAnnotations
        
        // Apply clustering if enabled
        if isClusteringEnabled {
            applyClustering()
        }
    }
    
    func removeAllAnnotations() {
        annotations.removeAll()
        clusteredAnnotations.removeAll()
        selectedAnnotation = nil
    }
    
    func selectAnnotation(_ annotation: GolfCourseAnnotation) {
        selectedAnnotation = annotation
    }
    
    func deselectAnnotation() {
        selectedAnnotation = nil
    }
    
    // MARK: - Clustering and Performance
    
    func enableClustering(_ enable: Bool) {
        isClusteringEnabled = enable
        
        if enable {
            applyClustering()
        } else {
            clusteredAnnotations.removeAll()
        }
    }
    
    func setClusteringDistance(_ distance: Double) {
        clusteringDistance = distance
        
        if isClusteringEnabled {
            applyClustering()
        }
    }
    
    private func applyClustering() {
        guard !annotations.isEmpty else {
            clusteredAnnotations.removeAll()
            return
        }
        
        var clusters: [GolfCourseClusterAnnotation] = []
        var unclustered = annotations
        
        while !unclustered.isEmpty {
            let baseAnnotation = unclustered.removeFirst()
            var clusterMembers = [baseAnnotation]
            
            // Find nearby annotations to cluster
            var i = 0
            while i < unclustered.count {
                let candidate = unclustered[i]
                let distance = CLLocation(latitude: baseAnnotation.coordinate.latitude, 
                                        longitude: baseAnnotation.coordinate.longitude)
                    .distance(from: CLLocation(latitude: candidate.coordinate.latitude,
                                             longitude: candidate.coordinate.longitude))
                
                if distance <= clusteringDistance {
                    clusterMembers.append(candidate)
                    unclustered.remove(at: i)
                } else {
                    i += 1
                }
            }
            
            // Create cluster if we have multiple annotations
            if clusterMembers.count > 1 {
                let cluster = GolfCourseClusterAnnotation(memberAnnotations: clusterMembers)
                clusters.append(cluster)
            }
        }
        
        clusteredAnnotations = clusters
    }
    
    // MARK: - Map Overlays
    
    func addWeatherOverlay(for region: MKCoordinateRegion) async {
        guard let weatherService = weatherService else { return }
        
        do {
            let weather = try await weatherService.getCurrentWeather(for: region.center)
            
            await MainActor.run {
                weatherOverlay = WeatherOverlay(region: region, weather: weather)
            }
        } catch {
            print("Error adding weather overlay: \(error)")
        }
    }
    
    func removeWeatherOverlay() {
        weatherOverlay = nil
    }
    
    func addTrafficOverlay(_ enable: Bool) {
        isTrafficEnabled = enable
        // Traffic overlay would be implemented in the MapView using MKMapView's showsTraffic property
    }
    
    // MARK: - Route Planning
    
    func getDirections(to course: GolfCourse, from location: CLLocationCoordinate2D?) async throws -> MKRoute {
        let startLocation: CLLocationCoordinate2D
        
        if let providedLocation = location {
            startLocation = providedLocation
        } else if let userLocation = locationService?.currentLocation {
            startLocation = userLocation
        } else {
            throw MapError.locationUnavailable
        }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: startLocation))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: course.coordinate))
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else {
                throw MapError.routeNotFound
            }
            
            return route
        } catch {
            print("Error calculating route: \(error)")
            throw MapError.routeCalculationFailed(error.localizedDescription)
        }
    }
    
    func showRoute(_ route: MKRoute) {
        routeOverlay = GolfRouteOverlay(route: route)
        
        // Adjust map region to fit the route
        let routeRect = route.polyline.boundingMapRect
        let region = MKCoordinateRegion(routeRect)
        updateRegion(to: region)
    }
    
    func clearRoute() {
        routeOverlay = nil
    }
}

// MARK: - Mock Map Service

class MockMapService: MapServiceProtocol, ObservableObject {
    
    @Published var currentRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    @Published var annotations: [GolfCourseAnnotation] = []
    @Published var selectedAnnotation: GolfCourseAnnotation?
    @Published var isClusteringEnabled: Bool = true
    
    private var mockCourses: [GolfCourse] = []
    
    init() {
        setupMockCourses()
        generateMockAnnotations()
    }
    
    func updateRegion(to region: MKCoordinateRegion) {
        currentRegion = region
    }
    
    func centerMap(on coordinate: CLLocationCoordinate2D, radius: Double) {
        let radiusInDegrees = radius / 111000.0
        
        currentRegion = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: radiusInDegrees * 2,
                longitudeDelta: radiusInDegrees * 2
            )
        )
    }
    
    func fitMapToAnnotations() {
        guard !annotations.isEmpty else { return }
        
        // Mock implementation - just zoom out a bit
        currentRegion = MKCoordinateRegion(
            center: currentRegion.center,
            span: MKCoordinateSpan(
                latitudeDelta: 0.5,
                longitudeDelta: 0.5
            )
        )
    }
    
    func loadGolfCourses(in region: MKCoordinateRegion) async {
        // Mock loading delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Filter mock courses to the region
        let filteredCourses = mockCourses.filter { course in
            let latDiff = abs(course.latitude - region.center.latitude)
            let lonDiff = abs(course.longitude - region.center.longitude)
            return latDiff <= region.span.latitudeDelta/2 && lonDiff <= region.span.longitudeDelta/2
        }
        
        addGolfCourseAnnotations(filteredCourses)
    }
    
    func addGolfCourseAnnotations(_ courses: [GolfCourse]) {
        annotations = courses.map { course in
            GolfCourseAnnotation(course: course, userLocation: currentRegion.center)
        }
    }
    
    func removeAllAnnotations() {
        annotations.removeAll()
        selectedAnnotation = nil
    }
    
    func selectAnnotation(_ annotation: GolfCourseAnnotation) {
        selectedAnnotation = annotation
    }
    
    func deselectAnnotation() {
        selectedAnnotation = nil
    }
    
    func enableClustering(_ enable: Bool) {
        isClusteringEnabled = enable
    }
    
    func setClusteringDistance(_ distance: Double) {
        // Mock implementation
    }
    
    func addWeatherOverlay(for region: MKCoordinateRegion) async {
        // Mock implementation
    }
    
    func removeWeatherOverlay() {
        // Mock implementation
    }
    
    func addTrafficOverlay(_ enable: Bool) {
        // Mock implementation
    }
    
    func getDirections(to course: GolfCourse, from location: CLLocationCoordinate2D?) async throws -> MKRoute {
        // Mock route calculation
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentRegion.center))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: course.coordinate))
        
        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        
        guard let route = response.routes.first else {
            throw MapError.routeNotFound
        }
        
        return route
    }
    
    func showRoute(_ route: MKRoute) {
        // Mock implementation
    }
    
    func clearRoute() {
        // Mock implementation
    }
    
    private func setupMockCourses() {
        // Create some mock golf courses around San Francisco Bay Area
        mockCourses = [
            createMockCourse(name: "Pebble Beach Golf Links", lat: 36.5621, lon: -121.9490, difficulty: .championship),
            createMockCourse(name: "TPC Harding Park", lat: 37.7281, lon: -122.4786, difficulty: .advanced),
            createMockCourse(name: "Olympic Club", lat: 37.7066, lon: -122.4849, difficulty: .championship),
            createMockCourse(name: "Presidio Golf Course", lat: 37.7984, lon: -122.4667, difficulty: .intermediate),
            createMockCourse(name: "Lincoln Park Golf Course", lat: 37.7843, lon: -122.5015, difficulty: .beginner),
            createMockCourse(name: "Sharp Park Golf Course", lat: 37.6299, lon: -122.4949, difficulty: .intermediate)
        ]
    }
    
    private func createMockCourse(name: String, lat: Double, lon: Double, difficulty: DifficultyLevel) -> GolfCourse {
        return GolfCourse(
            id: UUID().uuidString,
            name: name,
            address: "123 Golf Course Dr",
            city: "San Francisco",
            state: "CA",
            country: "US",
            zipCode: "94102",
            latitude: lat,
            longitude: lon,
            description: "Mock golf course",
            phoneNumber: "(415) 123-4567",
            website: nil,
            email: nil,
            numberOfHoles: 18,
            par: 72,
            yardage: CourseYardage(championshipTees: 7000, backTees: 6500, regularTees: 6000, forwardTees: 5500, seniorTees: nil, juniorTees: nil),
            slope: CourseSlope(championshipSlope: 125, backSlope: 120, regularSlope: 115, forwardSlope: 110, seniorSlope: nil, juniorSlope: nil),
            rating: CourseRating(championshipRating: 74.0, backRating: 71.0, regularRating: 68.0, forwardRating: 65.0, seniorRating: nil, juniorRating: nil),
            pricing: CoursePricing(weekdayRates: [75], weekendRates: [100], twilightRates: [50], seniorRates: nil, juniorRates: nil, cartFee: 25, cartIncluded: false, membershipRequired: false, guestPolicy: .open, seasonalMultiplier: 1.0, peakTimeMultiplier: 1.2, advanceBookingDiscount: nil),
            amenities: [.drivingRange, .puttingGreen, .proShop, .restaurant],
            dressCode: .moderate,
            cartPolicy: .optional,
            images: [],
            virtualTour: nil,
            averageRating: Double.random(in: 3.5...5.0),
            totalReviews: Int.random(in: 50...500),
            difficulty: difficulty,
            operatingHours: OperatingHours(monday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), tuesday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), wednesday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), thursday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), friday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), saturday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), sunday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00")),
            seasonalInfo: nil,
            bookingPolicy: BookingPolicy(advanceBookingDays: 7, cancellationPolicy: "", noShowPolicy: "", modificationPolicy: "", depositRequired: false, depositAmount: nil, refundableDeposit: true, groupBookingMinimum: nil, onlineBookingAvailable: true, phoneBookingRequired: false),
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true,
            isFeatured: false
        )
    }
    
    private func generateMockAnnotations() {
        addGolfCourseAnnotations(mockCourses)
    }
}

// MARK: - Map Error Types

enum MapError: Error, LocalizedError {
    case locationUnavailable
    case routeNotFound
    case routeCalculationFailed(String)
    case weatherOverlayFailed(String)
    case clusteringFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "Location not available for route calculation"
        case .routeNotFound:
            return "No route found to destination"
        case .routeCalculationFailed(let message):
            return "Route calculation failed: \(message)"
        case .weatherOverlayFailed(let message):
            return "Weather overlay failed: \(message)"
        case .clusteringFailed(let message):
            return "Annotation clustering failed: \(message)"
        }
    }
}

// MARK: - MapKit Extensions

extension MKCoordinateRegion {
    
    /// Calculate the approximate radius in meters from the center to the edge of the region
    var radiusInMeters: Double {
        let center = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let edge = CLLocation(
            latitude: center.latitude + span.latitudeDelta / 2,
            longitude: center.longitude
        )
        return center.distance(from: edge)
    }
    
    /// Check if a coordinate is within this region
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let latRange = (center.latitude - span.latitudeDelta / 2)...(center.latitude + span.latitudeDelta / 2)
        let lonRange = (center.longitude - span.longitudeDelta / 2)...(center.longitude + span.longitudeDelta / 2)
        
        return latRange.contains(coordinate.latitude) && lonRange.contains(coordinate.longitude)
    }
}

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return abs(lhs.latitude - rhs.latitude) < 0.0001 && abs(lhs.longitude - rhs.longitude) < 0.0001
    }
}

extension MKMapItem {
    
    /// Create a map item for a golf course
    convenience init(golfCourse: GolfCourse) {
        let placemark = MKPlacemark(
            coordinate: golfCourse.coordinate,
            addressDictionary: [
                CNPostalAddressStreetKey: golfCourse.address,
                CNPostalAddressCityKey: golfCourse.city,
                CNPostalAddressStateKey: golfCourse.state,
                CNPostalAddressPostalCodeKey: golfCourse.zipCode,
                CNPostalAddressCountryKey: golfCourse.country
            ]
        )
        
        self.init(placemark: placemark)
        self.name = golfCourse.name
        self.phoneNumber = golfCourse.phoneNumber
        self.url = golfCourse.website != nil ? URL(string: golfCourse.website!) : nil
    }
}

// MARK: - Golf-Specific Map Utilities

extension MKRoute {
    
    /// Get golf-optimized travel instructions
    var golfTravelSummary: String {
        let distanceMiles = distance * 0.000621371
        let travelTimeMinutes = Int(expectedTravelTime / 60)
        
        return String(format: "%.1f miles • %d min drive", distanceMiles, travelTimeMinutes)
    }
    
    /// Check if route is suitable for golf cart (if course allows cart travel to nearby holes)
    var isCartFriendly: Bool {
        // Simplified check - routes under 2 miles might be cart-friendly
        let distanceMiles = distance * 0.000621371
        return distanceMiles < 2.0
    }
}

extension GolfCourse {
    
    /// Convert golf course to MKAnnotation for direct use in MapKit
    var mapAnnotation: GolfCourseAnnotation {
        return GolfCourseAnnotation(course: self)
    }
    
    /// Get map item for navigation
    var mapItem: MKMapItem {
        return MKMapItem(golfCourse: self)
    }
}