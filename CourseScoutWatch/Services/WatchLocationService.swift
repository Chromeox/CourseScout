import Foundation
import CoreLocation
import WatchKit
import os.log
import Combine

// MARK: - Watch Location Service Protocol

protocol WatchLocationServiceProtocol: AnyObject {
    // Location authorization
    func requestLocationPermission() async -> Bool
    var authorizationStatus: CLAuthorizationStatus { get }
    
    // Current location
    var currentLocation: CLLocationCoordinate2D? { get }
    var currentLocationAccuracy: CLLocationAccuracy { get }
    var altitude: Double? { get }
    
    // Location monitoring
    func startLocationUpdates() async throws
    func stopLocationUpdates()
    func startSignificantLocationChanges()
    func stopSignificantLocationChanges()
    
    // Golf-specific location features
    func startGolfRoundTracking() async throws
    func stopGolfRoundTracking()
    func recordShotLocation(clubType: String?) async throws -> ShotLocation
    func calculateDistanceToPin(pinCoordinate: CLLocationCoordinate2D) -> Double?
    func getDistanceToHole(holeCoordinate: CLLocationCoordinate2D) -> Double?
    
    // Battery-optimized tracking
    func enableBatteryOptimizedMode(_ enabled: Bool)
    func setDesiredAccuracy(_ accuracy: CLLocationAccuracy)
    func setDistanceFilter(_ distance: CLLocationDistance)
    
    // Course boundary detection
    func setCourseArea(_ area: GolfCourseArea)
    func isLocationOnCourse() -> Bool
    func detectHoleTransition() -> Int?
    
    // Shot tracking
    func startShotTracking() async throws
    func stopShotTracking()
    func getLastShotDistance() -> Double?
    func getShotHistory() -> [ShotLocation]
    
    // Delegate
    func setDelegate(_ delegate: WatchLocationDelegate)
    func removeDelegate(_ delegate: WatchLocationDelegate)
}

// MARK: - Watch Location Delegate

protocol WatchLocationDelegate: AnyObject {
    func didUpdateLocation(_ location: CLLocation)
    func didChangeAuthorizationStatus(_ status: CLAuthorizationStatus)
    func didEnterGolfCourse(_ course: SharedGolfCourse)
    func didExitGolfCourse(_ course: SharedGolfCourse)
    func didDetectHoleChange(from: Int, to: Int)
    func didRecordShot(_ shot: ShotLocation)
    func didEncounterLocationError(_ error: Error)
}

// Default implementations
extension WatchLocationDelegate {
    func didUpdateLocation(_ location: CLLocation) {}
    func didChangeAuthorizationStatus(_ status: CLAuthorizationStatus) {}
    func didEnterGolfCourse(_ course: SharedGolfCourse) {}
    func didExitGolfCourse(_ course: SharedGolfCourse) {}
    func didDetectHoleChange(from: Int, to: Int) {}
    func didRecordShot(_ shot: ShotLocation) {}
    func didEncounterLocationError(_ error: Error) {}
}

// MARK: - Watch Location Service Implementation

@MainActor
class WatchLocationService: NSObject, WatchLocationServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "Location")
    
    // Published properties
    @Published private(set) var currentLocation: CLLocationCoordinate2D?
    @Published private(set) var currentLocationAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    @Published private(set) var altitude: Double?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // Golf-specific tracking
    private var isTrackingGolfRound = false
    private var currentGolfCourse: SharedGolfCourse?
    private var courseArea: GolfCourseArea?
    private var currentHoleNumber: Int?
    private var lastKnownHole: Int?
    
    // Shot tracking
    private var isShotTracking = false
    private var shotHistory: [ShotLocation] = []
    private var lastShotLocation: CLLocation?
    private var shotStartTime: Date?
    
    // Battery optimization
    private var isBatteryOptimized = false
    private var standardAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private var optimizedAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters
    private var standardDistanceFilter: CLLocationDistance = kCLDistanceFilterNone
    private var optimizedDistanceFilter: CLLocationDistance = 10.0
    
    // Delegate management
    private var delegates: [WeakLocationDelegate] = []
    
    // Location history for analysis
    private var locationHistory: [LocationDataPoint] = []
    private let maxLocationHistory = 100
    
    // Timers
    private var holeDetectionTimer: Timer?
    private var batteryOptimizationTimer: Timer?
    
    // MARK: - Dependencies
    
    @WatchServiceInjected(WatchHapticFeedbackServiceProtocol.self) private var hapticService
    @WatchServiceInjected(WatchNotificationServiceProtocol.self) private var notificationService
    @WatchServiceInjected(WatchConnectivityServiceProtocol.self) private var connectivityService
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLocationManager()
        logger.info("WatchLocationService initialized")
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = standardAccuracy
        locationManager.distanceFilter = standardDistanceFilter
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - Location Authorization
    
    func requestLocationPermission() async -> Bool {
        logger.info("Requesting location permission")
        
        return await withCheckedContinuation { continuation in
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                continuation.resume(returning: true)
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
                
                // Set up a completion handler for authorization change
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let authorized = self.locationManager.authorizationStatus == .authorizedWhenInUse || 
                                   self.locationManager.authorizationStatus == .authorizedAlways
                    continuation.resume(returning: authorized)
                }
            default:
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Location Monitoring
    
    func startLocationUpdates() async throws {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            throw LocationError.authorizationDenied
        }
        
        locationManager.startUpdatingLocation()
        logger.info("Started location updates with accuracy: \(locationManager.desiredAccuracy)")
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        logger.info("Stopped location updates")
    }
    
    func startSignificantLocationChanges() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            logger.error("Significant location change monitoring not available")
            return
        }
        
        locationManager.startMonitoringSignificantLocationChanges()
        logger.info("Started monitoring significant location changes")
    }
    
    func stopSignificantLocationChanges() {
        locationManager.stopMonitoringSignificantLocationChanges()
        logger.info("Stopped monitoring significant location changes")
    }
    
    // MARK: - Golf-Specific Tracking
    
    func startGolfRoundTracking() async throws {
        guard !isTrackingGolfRound else { return }
        
        try await startLocationUpdates()
        
        isTrackingGolfRound = true
        
        // Start hole detection timer
        holeDetectionTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.detectHoleTransition()
            }
        }
        
        // Optimize for golf round tracking
        setDesiredAccuracy(kCLLocationAccuracyBest)
        setDistanceFilter(5.0) // 5 meter filter for golf precision
        
        logger.info("Started golf round tracking")
    }
    
    func stopGolfRoundTracking() {
        guard isTrackingGolfRound else { return }
        
        isTrackingGolfRound = false
        holeDetectionTimer?.invalidate()
        holeDetectionTimer = nil
        
        stopLocationUpdates()
        logger.info("Stopped golf round tracking")
    }
    
    func recordShotLocation(clubType: String?) async throws -> ShotLocation {
        guard let location = currentLocation else {
            throw LocationError.locationUnavailable
        }
        
        let currentCLLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        let shotLocation = ShotLocation(
            id: UUID(),
            coordinate: location,
            timestamp: Date(),
            accuracy: currentLocationAccuracy,
            altitude: altitude,
            clubType: clubType,
            holeNumber: currentHoleNumber,
            distance: calculateLastShotDistance(from: currentCLLocation)
        )
        
        shotHistory.append(shotLocation)
        
        // Keep only last 50 shots
        if shotHistory.count > 50 {
            shotHistory.removeFirst(shotHistory.count - 50)
        }
        
        // Provide haptic feedback
        hapticService.playTaptic(.success)
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.didRecordShot(shotLocation)
        }
        
        // Sync to iPhone
        Task {
            try? await connectivityService.sendShotLocation(shotLocation)
        }
        
        logger.info("Recorded shot location with club: \(clubType ?? "unknown")")
        return shotLocation
    }
    
    func calculateDistanceToPin(pinCoordinate: CLLocationCoordinate2D) -> Double? {
        guard let currentLoc = currentLocation else { return nil }
        
        let currentCLLocation = CLLocation(latitude: currentLoc.latitude, longitude: currentLoc.longitude)
        let pinCLLocation = CLLocation(latitude: pinCoordinate.latitude, longitude: pinCoordinate.longitude)
        
        let distanceMeters = currentCLLocation.distance(from: pinCLLocation)
        return distanceMeters * 1.09361 // Convert meters to yards
    }
    
    func getDistanceToHole(holeCoordinate: CLLocationCoordinate2D) -> Double? {
        return calculateDistanceToPin(pinCoordinate: holeCoordinate)
    }
    
    // MARK: - Battery Optimization
    
    func enableBatteryOptimizedMode(_ enabled: Bool) {
        isBatteryOptimized = enabled
        
        if enabled {
            setDesiredAccuracy(optimizedAccuracy)
            setDistanceFilter(optimizedDistanceFilter)
            
            // Start battery optimization timer
            batteryOptimizationTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
                self?.optimizeLocationUpdates()
            }
        } else {
            setDesiredAccuracy(standardAccuracy)
            setDistanceFilter(standardDistanceFilter)
            batteryOptimizationTimer?.invalidate()
        }
        
        logger.info("Battery optimization mode: \(enabled ? "enabled" : "disabled")")
    }
    
    func setDesiredAccuracy(_ accuracy: CLLocationAccuracy) {
        locationManager.desiredAccuracy = accuracy
        currentLocationAccuracy = accuracy
    }
    
    func setDistanceFilter(_ distance: CLLocationDistance) {
        locationManager.distanceFilter = distance
    }
    
    private func optimizeLocationUpdates() {
        // Adjust location updates based on activity level
        let recentMovement = locationHistory.suffix(10)
        let averageSpeed = recentMovement.compactMap { $0.speed }.reduce(0, +) / Double(recentMovement.count)
        
        if averageSpeed < 0.5 { // Very slow movement (standing still)
            setDistanceFilter(15.0)
        } else if averageSpeed < 2.0 { // Walking pace
            setDistanceFilter(10.0)
        } else { // Faster movement (cart)
            setDistanceFilter(5.0)
        }
    }
    
    // MARK: - Course Boundary Detection
    
    func setCourseArea(_ area: GolfCourseArea) {
        courseArea = area
        currentGolfCourse = area.course
        logger.info("Set course area for: \(area.course.name)")
    }
    
    func isLocationOnCourse() -> Bool {
        guard let location = currentLocation,
              let area = courseArea else { return false }
        
        return area.contains(location)
    }
    
    @discardableResult
    func detectHoleTransition() -> Int? {
        guard let location = currentLocation,
              let area = courseArea else { return nil }
        
        let detectedHole = area.detectNearestHole(to: location)
        
        if let newHole = detectedHole,
           let previousHole = currentHoleNumber,
           newHole != previousHole {
            
            // Hole transition detected
            lastKnownHole = previousHole
            currentHoleNumber = newHole
            
            // Notify delegates
            notifyDelegates { delegate in
                delegate.didDetectHoleChange(from: previousHole, to: newHole)
            }
            
            // Provide haptic feedback
            hapticService.playMilestoneHaptic()
            
            // Schedule notification
            Task {
                if let holeInfo = area.course.holes.first(where: { $0.holeNumber == newHole }) {
                    try? await notificationService.scheduleHoleMilestoneNotification(
                        holeNumber: newHole,
                        par: holeInfo.par
                    )
                }
            }
            
            logger.info("Detected hole transition: \(previousHole) → \(newHole)")
            return newHole
        } else if detectedHole != nil {
            currentHoleNumber = detectedHole
        }
        
        return detectedHole
    }
    
    // MARK: - Shot Tracking
    
    func startShotTracking() async throws {
        guard !isShotTracking else { return }
        
        isShotTracking = true
        shotStartTime = Date()
        lastShotLocation = currentLocation.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        
        // Temporarily increase accuracy for shot tracking
        setDesiredAccuracy(kCLLocationAccuracyBest)
        setDistanceFilter(1.0)
        
        logger.info("Started shot tracking")
    }
    
    func stopShotTracking() {
        guard isShotTracking else { return }
        
        isShotTracking = false
        shotStartTime = nil
        
        // Restore normal accuracy settings
        if isBatteryOptimized {
            setDesiredAccuracy(optimizedAccuracy)
            setDistanceFilter(optimizedDistanceFilter)
        } else {
            setDesiredAccuracy(standardAccuracy)
            setDistanceFilter(standardDistanceFilter)
        }
        
        logger.info("Stopped shot tracking")
    }
    
    func getLastShotDistance() -> Double? {
        guard shotHistory.count >= 2 else { return nil }
        
        let lastShot = shotHistory[shotHistory.count - 1]
        let secondLastShot = shotHistory[shotHistory.count - 2]
        
        let lastLocation = CLLocation(latitude: lastShot.coordinate.latitude, longitude: lastShot.coordinate.longitude)
        let secondLastLocation = CLLocation(latitude: secondLastShot.coordinate.latitude, longitude: secondLastShot.coordinate.longitude)
        
        let distanceMeters = lastLocation.distance(from: secondLastLocation)
        return distanceMeters * 1.09361 // Convert to yards
    }
    
    func getShotHistory() -> [ShotLocation] {
        return shotHistory
    }
    
    private func calculateLastShotDistance(from currentLocation: CLLocation) -> Double? {
        guard let lastShot = lastShotLocation else { return nil }
        
        let distanceMeters = currentLocation.distance(from: lastShot)
        return distanceMeters * 1.09361 // Convert to yards
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: WatchLocationDelegate) {
        delegates.removeAll { $0.delegate == nil }
        delegates.append(WeakLocationDelegate(delegate))
        logger.info("Added location delegate")
    }
    
    func removeDelegate(_ delegate: WatchLocationDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        logger.info("Removed location delegate")
    }
    
    private func notifyDelegates<T>(_ action: (WatchLocationDelegate) -> T) {
        delegates.forEach { weakDelegate in
            if let delegate = weakDelegate.delegate {
                _ = action(delegate)
            }
        }
        
        // Clean up nil references
        delegates.removeAll { $0.delegate == nil }
    }
    
    // MARK: - Location History Management
    
    private func addLocationToHistory(_ location: CLLocation) {
        let dataPoint = LocationDataPoint(
            location: location,
            timestamp: Date(),
            speed: location.speed
        )
        
        locationHistory.append(dataPoint)
        
        // Keep only recent history
        if locationHistory.count > maxLocationHistory {
            locationHistory.removeFirst(locationHistory.count - maxLocationHistory)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WatchLocationService: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update current location
        currentLocation = location.coordinate
        currentLocationAccuracy = location.horizontalAccuracy
        altitude = location.altitude
        
        // Add to history
        addLocationToHistory(location)
        
        // Update last shot location if tracking
        if isShotTracking {
            lastShotLocation = location
        }
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.didUpdateLocation(location)
        }
        
        logger.debug("Updated location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("Location manager failed with error: \(error.localizedDescription)")
        
        notifyDelegates { delegate in
            delegate.didEncounterLocationError(error)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        logger.info("Location authorization changed to: \(status.rawValue)")
        
        notifyDelegates { delegate in
            delegate.didChangeAuthorizationStatus(status)
        }
    }
}

// MARK: - Supporting Types

struct ShotLocation: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let accuracy: CLLocationAccuracy
    let altitude: Double?
    let clubType: String?
    let holeNumber: Int?
    let distance: Double? // Distance from previous shot
}

struct GolfCourseArea {
    let course: SharedGolfCourse
    let boundary: [CLLocationCoordinate2D]
    let holeAreas: [HoleArea]
    
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return isPointInsidePolygon(coordinate, polygon: boundary)
    }
    
    func detectNearestHole(to coordinate: CLLocationCoordinate2D) -> Int? {
        var nearestHole: Int?
        var minDistance = Double.infinity
        
        for holeArea in holeAreas {
            let holeCenter = holeArea.center
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: holeCenter.latitude, longitude: holeCenter.longitude))
            
            if distance < minDistance && distance < holeArea.radius {
                minDistance = distance
                nearestHole = holeArea.holeNumber
            }
        }
        
        return nearestHole
    }
    
    private func isPointInsidePolygon(_ point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        guard polygon.count >= 3 else { return false }
        
        var inside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            let xi = polygon[i].latitude
            let yi = polygon[i].longitude
            let xj = polygon[j].latitude
            let yj = polygon[j].longitude
            
            if ((yi > point.longitude) != (yj > point.longitude)) &&
               (point.latitude < (xj - xi) * (point.longitude - yi) / (yj - yi) + xi) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }
}

struct HoleArea {
    let holeNumber: Int
    let center: CLLocationCoordinate2D
    let radius: Double // meters
}

struct LocationDataPoint {
    let location: CLLocation
    let timestamp: Date
    let speed: CLLocationSpeed
}

private struct WeakLocationDelegate {
    weak var delegate: WatchLocationDelegate?
    
    init(_ delegate: WatchLocationDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Location Errors

enum LocationError: Error, LocalizedError {
    case authorizationDenied
    case locationUnavailable
    case trackingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Location access denied"
        case .locationUnavailable:
            return "Current location not available"
        case .trackingFailed(let message):
            return "Location tracking failed: \(message)"
        }
    }
}

// MARK: - Watch Connectivity Extensions

extension WatchConnectivityServiceProtocol {
    func sendShotLocation(_ shot: ShotLocation) async throws {
        let data: [String: Any] = [
            "type": "shot_location",
            "id": shot.id.uuidString,
            "coordinate": [
                "latitude": shot.coordinate.latitude,
                "longitude": shot.coordinate.longitude
            ],
            "timestamp": shot.timestamp.timeIntervalSince1970,
            "accuracy": shot.accuracy,
            "altitude": shot.altitude as Any,
            "club_type": shot.clubType as Any,
            "hole_number": shot.holeNumber as Any,
            "distance": shot.distance as Any
        ]
        
        try await sendMessage(data, priority: .normal)
    }
}

// MARK: - Preview Support

#if DEBUG
extension WatchLocationService {
    static let mock = WatchLocationService()
}
#endif