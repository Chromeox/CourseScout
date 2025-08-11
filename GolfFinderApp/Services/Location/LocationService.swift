import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Location Service Protocol

protocol LocationServiceProtocol: ObservableObject {
    var currentLocation: CLLocationCoordinate2D? { get }
    var authorizationStatus: CLAuthorizationStatus { get }
    var isLocationEnabled: Bool { get }
    var accuracy: CLLocationAccuracy { get }
    var lastLocationUpdate: Date? { get }
    
    // Location management
    func requestLocationPermission()
    func startLocationUpdates()
    func stopLocationUpdates()
    func getCurrentLocation() async throws -> CLLocationCoordinate2D
    
    // Golf-specific location features
    func findNearbyGolfCourses(radius: Double) async throws -> [GolfCourse]
    func calculateDistanceToGolfCourse(_ course: GolfCourse) -> CLLocationDistance?
    func getLocationName(for coordinate: CLLocationCoordinate2D) async throws -> String
    
    // Golf course location accuracy
    func enableHighAccuracyMode()
    func disableHighAccuracyMode()
    func isLocationSuitableForGolfTracking() -> Bool
    
    // Background location for round tracking
    func startBackgroundLocationTracking()
    func stopBackgroundLocationTracking()
    func getLocationTrackingPoints() -> [GPSTrackingPoint]
}

// MARK: - Location Service Implementation

@MainActor
class LocationService: NSObject, LocationServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocationEnabled: Bool = false
    @Published var accuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    @Published var lastLocationUpdate: Date?
    
    // MARK: - Private Properties
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    // Golf-specific tracking
    private var golfCourseService: GolfCourseServiceProtocol?
    private var trackingPoints: [GPSTrackingPoint] = []
    private var isHighAccuracyModeEnabled = false
    private var isBackgroundTrackingEnabled = false
    
    // Performance optimization
    private var locationUpdateTimer: Timer?
    private var lastSignificantLocationUpdate: Date?
    private let minimumUpdateInterval: TimeInterval = 5.0 // 5 seconds
    private let minimumDistanceFilter: CLLocationDistance = 10.0 // 10 meters
    
    // Caching for nearby courses
    private var nearbyCoursesCache: (location: CLLocationCoordinate2D, courses: [GolfCourse], timestamp: Date)?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    init(golfCourseService: GolfCourseServiceProtocol) {
        super.init()
        self.golfCourseService = golfCourseService
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = minimumDistanceFilter
        
        // Golf-specific configuration
        locationManager.activityType = .fitness
        
        // Update published properties
        authorizationStatus = locationManager.authorizationStatus
        isLocationEnabled = CLLocationManager.locationServicesEnabled()
    }
    
    // MARK: - Location Permission Management
    
    func requestLocationPermission() {
        guard CLLocationManager.locationServicesEnabled() else {
            print("Location services are disabled")
            return
        }
        
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            print("Location access denied or restricted")
            // Could show alert directing user to settings
        case .authorizedWhenInUse:
            // Request always authorization for background golf tracking
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            print("Location authorization already granted")
        @unknown default:
            print("Unknown location authorization status")
        }
    }
    
    // MARK: - Location Updates
    
    func startLocationUpdates() {
        guard isLocationEnabled && (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways) else {
            print("Cannot start location updates - permission not granted")
            return
        }
        
        locationManager.startUpdatingLocation()
        
        // Set up periodic location updates for golf tracking accuracy
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: minimumUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.validateLocationAccuracy()
            }
        }
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
    }
    
    func getCurrentLocation() async throws -> CLLocationCoordinate2D {
        guard isLocationEnabled else {
            throw LocationError.locationServicesDisabled
        }
        
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            throw LocationError.permissionDenied
        }
        
        // If we have a recent location, return it
        if let currentLocation = currentLocation,
           let lastUpdate = lastLocationUpdate,
           Date().timeIntervalSince(lastUpdate) < 30 {
            return currentLocation
        }
        
        // Request a fresh location
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            let completionHandler: (CLLocationCoordinate2D?, LocationError?) -> Void = { location, error in
                guard !hasResumed else { return }
                hasResumed = true
                
                if let location = location {
                    continuation.resume(returning: location)
                } else {
                    continuation.resume(throwing: error ?? LocationError.locationUnavailable)
                }
            }
            
            // Set up a timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                completionHandler(nil, LocationError.timeout)
            }
            
            // Request location
            locationManager.requestLocation()
            
            // Monitor for location updates
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                if let currentLocation = self.currentLocation,
                   let lastUpdate = self.lastLocationUpdate,
                   Date().timeIntervalSince(lastUpdate) < 5 {
                    timer.invalidate()
                    completionHandler(currentLocation, nil)
                }
            }
            
            // Clean up timer after timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 16) {
                timer.invalidate()
            }
        }
    }
    
    // MARK: - Golf-Specific Features
    
    func findNearbyGolfCourses(radius: Double) async throws -> [GolfCourse] {
        let currentLocation = try await getCurrentLocation()
        
        // Check cache first
        if let cache = nearbyCoursesCache,
           Date().timeIntervalSince(cache.timestamp) < cacheValidityDuration {
            let cacheDistance = CLLocation(latitude: cache.location.latitude, longitude: cache.location.longitude)
                .distance(from: CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude))
            
            // Use cached results if we haven't moved significantly
            if cacheDistance < 1000 { // 1km
                return cache.courses
            }
        }
        
        // Fetch fresh results
        guard let golfCourseService = golfCourseService else {
            // Use service container if not injected
            let container = ServiceContainer.shared
            let service = container.golfCourseService()
            
            let courses = try await service.searchCourses(
                near: currentLocation,
                radius: radius,
                filters: nil
            )
            
            // Cache results
            nearbyCoursesCache = (currentLocation, courses, Date())
            return courses
        }
        
        let courses = try await golfCourseService.searchCourses(
            near: currentLocation,
            radius: radius,
            filters: nil
        )
        
        // Cache results
        nearbyCoursesCache = (currentLocation, courses, Date())
        return courses
    }
    
    func calculateDistanceToGolfCourse(_ course: GolfCourse) -> CLLocationDistance? {
        guard let currentLocation = currentLocation else { return nil }
        
        let currentLocationCL = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
        let courseLocation = CLLocation(latitude: course.latitude, longitude: course.longitude)
        
        return currentLocationCL.distance(from: courseLocation)
    }
    
    func getLocationName(for coordinate: CLLocationCoordinate2D) async throws -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    continuation.resume(throwing: LocationError.geocodingFailed)
                    return
                }
                
                var components: [String] = []
                
                if let name = placemark.name {
                    components.append(name)
                }
                if let locality = placemark.locality {
                    components.append(locality)
                }
                if let state = placemark.administrativeArea {
                    components.append(state)
                }
                
                let locationName = components.isEmpty ? "Unknown Location" : components.joined(separator: ", ")
                continuation.resume(returning: locationName)
            }
        }
    }
    
    // MARK: - Golf Course Location Accuracy
    
    func enableHighAccuracyMode() {
        isHighAccuracyModeEnabled = true
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0 // 5 meters for golf tracking
        
        // Restart location updates with new accuracy
        if locationManager.location != nil {
            stopLocationUpdates()
            startLocationUpdates()
        }
    }
    
    func disableHighAccuracyMode() {
        isHighAccuracyModeEnabled = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = minimumDistanceFilter
        
        // Restart location updates with standard accuracy
        if locationManager.location != nil {
            stopLocationUpdates()
            startLocationUpdates()
        }
    }
    
    func isLocationSuitableForGolfTracking() -> Bool {
        guard let location = locationManager.location else { return false }
        
        // Check accuracy - should be within 10 meters for golf tracking
        let horizontalAccuracy = location.horizontalAccuracy
        guard horizontalAccuracy > 0 && horizontalAccuracy <= 10 else { return false }
        
        // Check recency - location should be recent
        let age = Date().timeIntervalSince(location.timestamp)
        guard age < 30 else { return false }
        
        return true
    }
    
    // MARK: - Background Location Tracking
    
    func startBackgroundLocationTracking() {
        guard authorizationStatus == .authorizedAlways else {
            print("Background location tracking requires Always authorization")
            return
        }
        
        isBackgroundTrackingEnabled = true
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness
        
        // Enable significant location changes for battery efficiency
        locationManager.startMonitoringSignificantLocationChanges()
        
        startLocationUpdates()
    }
    
    func stopBackgroundLocationTracking() {
        isBackgroundTrackingEnabled = false
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
        
        locationManager.stopMonitoringSignificantLocationChanges()
        stopLocationUpdates()
    }
    
    func getLocationTrackingPoints() -> [GPSTrackingPoint] {
        return trackingPoints
    }
    
    // MARK: - Private Helper Methods
    
    private func validateLocationAccuracy() {
        guard let location = locationManager.location else { return }
        
        let accuracy = location.horizontalAccuracy
        let age = Date().timeIntervalSince(location.timestamp)
        
        if accuracy > 50 || age > 60 {
            // Poor accuracy or stale location - request fresh location
            locationManager.requestLocation()
        }
    }
    
    private func addTrackingPoint(from location: CLLocation) {
        let trackingPoint = GPSTrackingPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp,
            holeNumber: nil, // Would be set by scorecard service
            shotNumber: nil // Would be set by scorecard service
        )
        
        trackingPoints.append(trackingPoint)
        
        // Keep only recent tracking points (last 4 hours)
        let fourHoursAgo = Date().addingTimeInterval(-14400)
        trackingPoints = trackingPoints.filter { $0.timestamp > fourHoursAgo }
    }
    
    private func shouldUpdateLocation(from newLocation: CLLocation) -> Bool {
        guard let lastUpdate = lastSignificantLocationUpdate else { return true }
        
        // Always update if it's been more than the minimum interval
        if Date().timeIntervalSince(lastUpdate) >= minimumUpdateInterval {
            return true
        }
        
        // Update if we've moved significantly
        if let lastLocation = locationManager.location {
            let distance = newLocation.distance(from: lastLocation)
            return distance >= minimumDistanceFilter
        }
        
        return true
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Validate location quality
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 100 else {
            print("Location accuracy too poor: \(location.horizontalAccuracy) meters")
            return
        }
        
        // Check if we should update
        guard shouldUpdateLocation(from: location) else { return }
        
        // Update published properties
        currentLocation = location.coordinate
        accuracy = location.horizontalAccuracy
        lastLocationUpdate = Date()
        lastSignificantLocationUpdate = Date()
        
        // Add to tracking points if background tracking is enabled
        if isBackgroundTrackingEnabled {
            addTrackingPoint(from: location)
        }
        
        print("Location updated: \(location.coordinate), accuracy: \(location.horizontalAccuracy)m")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
        
        if let clError = error as? CLError {
            switch clError.code {
            case .locationUnknown:
                print("Location is currently unknown, but CLLocationManager will keep trying")
            case .denied:
                print("Location services are disabled")
                isLocationEnabled = false
            case .network:
                print("Network error while retrieving location")
            default:
                print("Other location error: \(clError.localizedDescription)")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        isLocationEnabled = CLLocationManager.locationServicesEnabled() && 
                           (status == .authorizedWhenInUse || status == .authorizedAlways)
        
        switch status {
        case .notDetermined:
            print("Location authorization not determined")
        case .denied, .restricted:
            print("Location authorization denied or restricted")
            stopLocationUpdates()
        case .authorizedWhenInUse:
            print("Location authorization granted for when in use")
            if isBackgroundTrackingEnabled {
                // Request always authorization for background tracking
                requestLocationPermission()
            }
        case .authorizedAlways:
            print("Location authorization granted for always")
        @unknown default:
            print("Unknown location authorization status: \(status.rawValue)")
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationManager(manager, didChangeAuthorization: manager.authorizationStatus)
    }
}

// MARK: - Mock Location Service for Testing

class MockLocationService: LocationServiceProtocol {
    
    @Published var currentLocation: CLLocationCoordinate2D? = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // San Francisco
    @Published var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    @Published var isLocationEnabled: Bool = true
    @Published var accuracy: CLLocationAccuracy = 5.0
    @Published var lastLocationUpdate: Date? = Date()
    
    private var mockCourses: [GolfCourse] = []
    private var trackingPoints: [GPSTrackingPoint] = []
    
    func requestLocationPermission() {
        authorizationStatus = .authorizedWhenInUse
        isLocationEnabled = true
    }
    
    func startLocationUpdates() {
        // Simulate location updates
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.lastLocationUpdate = Date()
        }
    }
    
    func stopLocationUpdates() {
        // Mock implementation
    }
    
    func getCurrentLocation() async throws -> CLLocationCoordinate2D {
        if let current = currentLocation {
            return current
        }
        throw LocationError.locationUnavailable
    }
    
    func findNearbyGolfCourses(radius: Double) async throws -> [GolfCourse] {
        // Return mock golf courses
        return mockCourses
    }
    
    func calculateDistanceToGolfCourse(_ course: GolfCourse) -> CLLocationDistance? {
        guard let currentLocation = currentLocation else { return nil }
        
        let current = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
        let courseLocation = CLLocation(latitude: course.latitude, longitude: course.longitude)
        return current.distance(from: courseLocation)
    }
    
    func getLocationName(for coordinate: CLLocationCoordinate2D) async throws -> String {
        return "Mock Location"
    }
    
    func enableHighAccuracyMode() {
        accuracy = 1.0
    }
    
    func disableHighAccuracyMode() {
        accuracy = 5.0
    }
    
    func isLocationSuitableForGolfTracking() -> Bool {
        return accuracy <= 10.0
    }
    
    func startBackgroundLocationTracking() {
        // Mock implementation
    }
    
    func stopBackgroundLocationTracking() {
        // Mock implementation
    }
    
    func getLocationTrackingPoints() -> [GPSTrackingPoint] {
        return trackingPoints
    }
    
    // Helper method to set mock courses for testing
    func setMockCourses(_ courses: [GolfCourse]) {
        mockCourses = courses
    }
    
    // Helper method to simulate location change
    func simulateLocationUpdate(_ location: CLLocationCoordinate2D) {
        currentLocation = location
        lastLocationUpdate = Date()
    }
}

// MARK: - Location Error Types

enum LocationError: Error, LocalizedError {
    case locationServicesDisabled
    case permissionDenied
    case locationUnavailable
    case geocodingFailed
    case timeout
    case accuracyTooLow
    
    var errorDescription: String? {
        switch self {
        case .locationServicesDisabled:
            return "Location services are disabled"
        case .permissionDenied:
            return "Location permission denied"
        case .locationUnavailable:
            return "Current location unavailable"
        case .geocodingFailed:
            return "Failed to get location name"
        case .timeout:
            return "Location request timed out"
        case .accuracyTooLow:
            return "Location accuracy too low for golf tracking"
        }
    }
}

// MARK: - Location Extensions for Golf Features

extension CLLocationCoordinate2D {
    
    /// Calculate distance to another coordinate in yards (common golf measurement)
    func distanceInYards(to coordinate: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let location2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let distanceInMeters = location1.distance(from: location2)
        return distanceInMeters * 1.094 // Convert meters to yards
    }
    
    /// Check if coordinate is within a golf course boundary (simplified)
    func isWithinGolfCourseBounds(_ course: GolfCourse, tolerance: Double = 500) -> Bool {
        let courseLocation = CLLocationCoordinate2D(latitude: course.latitude, longitude: course.longitude)
        let distanceInMeters = CLLocation(latitude: self.latitude, longitude: self.longitude)
            .distance(from: CLLocation(latitude: courseLocation.latitude, longitude: courseLocation.longitude))
        return distanceInMeters <= tolerance
    }
}

extension CLLocation {
    
    /// Get GPS accuracy description for golf tracking
    var golfTrackingAccuracyDescription: String {
        if horizontalAccuracy < 0 {
            return "Invalid GPS"
        } else if horizontalAccuracy <= 5 {
            return "Excellent (≤5m)"
        } else if horizontalAccuracy <= 10 {
            return "Good (≤10m)"
        } else if horizontalAccuracy <= 25 {
            return "Fair (≤25m)"
        } else {
            return "Poor (>\(Int(horizontalAccuracy))m)"
        }
    }
    
    /// Check if location is suitable for golf shot tracking
    var isSuitableForGolfTracking: Bool {
        return horizontalAccuracy > 0 && 
               horizontalAccuracy <= 10 && 
               Date().timeIntervalSince(timestamp) < 30
    }
}