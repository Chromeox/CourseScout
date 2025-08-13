import Foundation
import CoreLocation
import os.log

// MARK: - Watch Golf Course Service Protocol

protocol WatchGolfCourseServiceProtocol: AnyObject {
    // Course data access
    func getCurrentCourse() async -> SharedGolfCourse?
    func getCourseById(_ courseId: String) async -> SharedGolfCourse?
    func getHoleInformation(courseId: String, holeNumber: Int) async -> SharedHoleInfo?
    func getAllHoles(for courseId: String) async -> [SharedHoleInfo]
    
    // Course navigation
    func getDistanceToPin(from location: CLLocationCoordinate2D, holeNumber: Int) async -> Int?
    func getDistanceToHazards(from location: CLLocationCoordinate2D, holeNumber: Int) async -> [(SharedHazard, Int)]
    func getRecommendedClub(for distance: Int, conditions: PlayingConditions?) -> String?
    
    // Course caching
    func preloadCourse(_ course: SharedGolfCourse) async
    func clearCourseCache()
    
    // Sync with iPhone
    func requestCourseFromiPhone(courseId: String) async -> SharedGolfCourse?
    func syncCourseData() async
    
    // Delegates
    func setDelegate(_ delegate: WatchGolfCourseDelegate)
    func removeDelegate(_ delegate: WatchGolfCourseDelegate)
}

// MARK: - Watch Golf Course Delegate

protocol WatchGolfCourseDelegate: AnyObject {
    func didUpdateCurrentCourse(_ course: SharedGolfCourse)
    func didUpdateHoleInformation(_ hole: SharedHoleInfo)
    func didReceiveCourseFromiPhone(_ course: SharedGolfCourse)
    func didFailToLoadCourse(error: Error)
}

// Default implementations
extension WatchGolfCourseDelegate {
    func didUpdateCurrentCourse(_ course: SharedGolfCourse) {}
    func didUpdateHoleInformation(_ hole: SharedHoleInfo) {}
    func didReceiveCourseFromiPhone(_ course: SharedGolfCourse) {}
    func didFailToLoadCourse(error: Error) {}
}

// MARK: - Playing Conditions

struct PlayingConditions: Codable, Equatable {
    let windSpeed: Double // mph
    let windDirection: Double // degrees
    let temperature: Double // fahrenheit
    let humidity: Double // percentage
    let elevation: Double // feet above sea level
    
    var windAdjustment: Double {
        // Simple wind adjustment factor
        if windSpeed < 5 { return 1.0 }
        else if windSpeed < 15 { return 1.1 }
        else { return 1.2 }
    }
    
    var temperatureAdjustment: Double {
        // Ball travels further in warmer weather
        if temperature < 50 { return 0.95 }
        else if temperature > 80 { return 1.05 }
        else { return 1.0 }
    }
    
    var elevationAdjustment: Double {
        // Approximately 2 yards per 1000 feet elevation
        return 1.0 + (elevation / 1000.0 * 0.02)
    }
    
    var combinedAdjustment: Double {
        return windAdjustment * temperatureAdjustment * elevationAdjustment
    }
}

// MARK: - Watch Golf Course Service Implementation

class WatchGolfCourseService: NSObject, WatchGolfCourseServiceProtocol {
    // MARK: - Properties
    
    private let connectivityService: WatchConnectivityServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "GolfCourse")
    
    // Data storage
    private var currentCourse: SharedGolfCourse?
    private var courseCache: [String: SharedGolfCourse] = [:]
    private var holeCache: [String: [SharedHoleInfo]] = [:]
    private var lastSyncTime: Date?
    
    // Delegates
    private var delegates: [WeakGolfCourseDelegate] = []
    
    // Club recommendations
    private let clubDistances: [String: (min: Int, max: Int)] = [
        "Driver": (200, 280),
        "3 Wood": (180, 240),
        "5 Wood": (160, 200),
        "3 Hybrid": (150, 190),
        "4 Iron": (140, 180),
        "5 Iron": (130, 170),
        "6 Iron": (120, 160),
        "7 Iron": (110, 150),
        "8 Iron": (100, 140),
        "9 Iron": (90, 130),
        "PW": (80, 120),
        "SW": (60, 100),
        "LW": (40, 80)
    ]
    
    // MARK: - Initialization
    
    init(connectivityService: WatchConnectivityServiceProtocol) {
        self.connectivityService = connectivityService
        super.init()
        
        connectivityService.setDelegate(self)
        logger.info("WatchGolfCourseService initialized")
    }
    
    // MARK: - Course Data Access
    
    func getCurrentCourse() async -> SharedGolfCourse? {
        if let course = currentCourse {
            logger.debug("Returning cached current course: \(course.name)")
            return course
        }
        
        // Try to sync with iPhone
        await syncCourseData()
        return currentCourse
    }
    
    func getCourseById(_ courseId: String) async -> SharedGolfCourse? {
        // Check cache first
        if let course = courseCache[courseId] {
            logger.debug("Returning cached course: \(course.name)")
            return course
        }
        
        // Request from iPhone
        return await requestCourseFromiPhone(courseId: courseId)
    }
    
    func getHoleInformation(courseId: String, holeNumber: Int) async -> SharedHoleInfo? {
        guard let holes = holeCache[courseId] else {
            // Try to load course first
            if await getCourseById(courseId) != nil {
                return holeCache[courseId]?.first { $0.holeNumber == holeNumber }
            }
            return nil
        }
        
        return holes.first { $0.holeNumber == holeNumber }
    }
    
    func getAllHoles(for courseId: String) async -> [SharedHoleInfo] {
        if let holes = holeCache[courseId] {
            return holes.sorted { $0.holeNumber < $1.holeNumber }
        }
        
        // Try to load course first
        if await getCourseById(courseId) != nil {
            return holeCache[courseId]?.sorted { $0.holeNumber < $1.holeNumber } ?? []
        }
        
        return []
    }
    
    // MARK: - Course Navigation
    
    func getDistanceToPin(from location: CLLocationCoordinate2D, holeNumber: Int) async -> Int? {
        guard let currentCourse = currentCourse,
              let hole = await getHoleInformation(courseId: currentCourse.id, holeNumber: holeNumber) else {
            return nil
        }
        
        let distance = hole.distanceToPin(from: location)
        logger.debug("Distance to pin on hole \(holeNumber): \(distance) yards")
        return distance
    }
    
    func getDistanceToHazards(from location: CLLocationCoordinate2D, holeNumber: Int) async -> [(SharedHazard, Int)] {
        guard let currentCourse = currentCourse,
              let hole = await getHoleInformation(courseId: currentCourse.id, holeNumber: holeNumber) else {
            return []
        }
        
        let hazardDistances = hole.hazards.map { hazard in
            (hazard, hazard.distanceTo(from: location))
        }
        
        return hazardDistances.sorted { $0.1 < $1.1 }
    }
    
    func getRecommendedClub(for distance: Int, conditions: PlayingConditions?) -> String? {
        let adjustedDistance: Double
        
        if let conditions = conditions {
            adjustedDistance = Double(distance) / conditions.combinedAdjustment
        } else {
            adjustedDistance = Double(distance)
        }
        
        let targetDistance = Int(adjustedDistance)
        
        // Find the best club for the adjusted distance
        for (club, range) in clubDistances {
            if targetDistance >= range.min && targetDistance <= range.max {
                logger.debug("Recommended \(club) for \(distance) yards (adjusted: \(targetDistance))")
                return club
            }
        }
        
        // If no exact match, find the closest
        let sortedClubs = clubDistances.sorted { $0.value.max < $1.value.max }
        
        if targetDistance < sortedClubs.first?.value.min ?? 0 {
            return sortedClubs.first?.key // Shortest club
        } else if targetDistance > sortedClubs.last?.value.max ?? 300 {
            return sortedClubs.last?.key // Longest club
        }
        
        return nil
    }
    
    // MARK: - Course Caching
    
    func preloadCourse(_ course: SharedGolfCourse) async {
        courseCache[course.id] = course
        
        // Generate mock hole information for demonstration
        let holes = generateMockHoles(for: course)
        holeCache[course.id] = holes
        
        logger.info("Preloaded course: \(course.name) with \(holes.count) holes")
    }
    
    func clearCourseCache() {
        courseCache.removeAll()
        holeCache.removeAll()
        currentCourse = nil
        logger.debug("Course cache cleared")
    }
    
    // MARK: - Sync with iPhone
    
    func requestCourseFromiPhone(courseId: String) async -> SharedGolfCourse? {
        logger.info("Requesting course from iPhone: \(courseId)")
        
        return await withCheckedContinuation { continuation in
            connectivityService.requestCourseInformation(courseId: courseId)
            
            // Set up timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if self.courseCache[courseId] == nil {
                    continuation.resume(returning: nil)
                }
            }
            
            // The response will be handled in the WatchConnectivityDelegate
            // When received, it will be stored in cache and can be accessed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let course = self.courseCache[courseId] {
                    continuation.resume(returning: course)
                }
            }
        }
    }
    
    func syncCourseData() async {
        let now = Date()
        
        // Only sync if it's been more than 5 minutes since last sync
        if let lastSync = lastSyncTime, now.timeIntervalSince(lastSync) < 300 {
            logger.debug("Skipping sync - too recent")
            return
        }
        
        lastSyncTime = now
        logger.info("Syncing course data with iPhone")
        
        connectivityService.requestCurrentRound()
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: WatchGolfCourseDelegate) {
        // Remove any existing weak references to the same delegate
        delegates.removeAll { $0.delegate === delegate }
        
        // Add new weak reference
        delegates.append(WeakGolfCourseDelegate(delegate))
        
        // Clean up any nil references
        delegates.removeAll { $0.delegate == nil }
        
        logger.debug("Added golf course delegate")
    }
    
    func removeDelegate(_ delegate: WatchGolfCourseDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        logger.debug("Removed golf course delegate")
    }
    
    // MARK: - Private Helper Methods
    
    private func generateMockHoles(for course: SharedGolfCourse) -> [SharedHoleInfo] {
        let baseLatitude = course.latitude
        let baseLongitude = course.longitude
        
        return (1...course.numberOfHoles).map { holeNumber in
            let par = holeNumber <= 4 || (holeNumber >= 10 && holeNumber <= 13) ? 4 : 
                     (holeNumber == 9 || holeNumber == 18 ? 5 : 3)
            let yardage = par == 3 ? Int.random(in: 120...180) :
                         par == 4 ? Int.random(in: 300...450) :
                         Int.random(in: 450...580)
            
            let teeOffset = Double(holeNumber) * 0.001
            let pinOffset = teeOffset + 0.0005
            
            let hazards = generateMockHazards(holeNumber: holeNumber, baseLatitude: baseLatitude, baseLongitude: baseLongitude)
            
            return SharedHoleInfo(
                id: "hole-\(course.id)-\(holeNumber)",
                holeNumber: holeNumber,
                par: par,
                yardage: yardage,
                handicapIndex: holeNumber,
                teeCoordinate: CLLocationCoordinate2D(
                    latitude: baseLatitude + teeOffset,
                    longitude: baseLongitude + teeOffset
                ),
                pinCoordinate: CLLocationCoordinate2D(
                    latitude: baseLatitude + pinOffset,
                    longitude: baseLongitude + pinOffset
                ),
                hazards: hazards
            )
        }
    }
    
    private func generateMockHazards(holeNumber: Int, baseLatitude: Double, baseLongitude: Double) -> [SharedHazard] {
        var hazards: [SharedHazard] = []
        
        // Add some random hazards based on hole characteristics
        let hazardCount = Int.random(in: 1...3)
        
        for i in 0..<hazardCount {
            let hazardType: SharedHazard.HazardType = [.water, .bunker, .trees].randomElement() ?? .bunker
            let hazardOffset = Double(i) * 0.0002 + Double(holeNumber) * 0.001
            
            let hazard = SharedHazard(
                id: "hazard-\(holeNumber)-\(i)",
                type: hazardType,
                coordinate: CLLocationCoordinate2D(
                    latitude: baseLatitude + hazardOffset,
                    longitude: baseLongitude + hazardOffset + 0.0001
                ),
                radius: Int.random(in: 10...50)
            )
            
            hazards.append(hazard)
        }
        
        return hazards
    }
    
    private func notifyDelegates<T>(_ action: (WatchGolfCourseDelegate) -> T) {
        DispatchQueue.main.async {
            self.delegates.forEach { weakDelegate in
                if let delegate = weakDelegate.delegate {
                    _ = action(delegate)
                }
            }
            
            // Clean up nil references
            self.delegates.removeAll { $0.delegate == nil }
        }
    }
}

// MARK: - WatchConnectivityDelegate Implementation

extension WatchGolfCourseService: WatchConnectivityDelegate {
    func didReceiveCourseData(_ course: SharedGolfCourse) {
        logger.info("Received course data from iPhone: \(course.name)")
        
        // Cache the course
        courseCache[course.id] = course
        
        // Set as current course if we don't have one
        if currentCourse == nil {
            currentCourse = course
        }
        
        // Generate hole information
        Task {
            await preloadCourse(course)
        }
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.didReceiveCourseFromiPhone(course)
            if currentCourse?.id == course.id {
                delegate.didUpdateCurrentCourse(course)
            }
        }
    }
    
    func didReceiveActiveRoundUpdate(_ round: ActiveGolfRound) {
        logger.info("Received active round update: \(round.courseName)")
        
        // Update current course if different
        if currentCourse?.id != round.courseId {
            Task {
                if let course = await getCourseById(round.courseId) {
                    currentCourse = course
                    notifyDelegates { delegate in
                        delegate.didUpdateCurrentCourse(course)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

private struct WeakGolfCourseDelegate {
    weak var delegate: WatchGolfCourseDelegate?
    
    init(_ delegate: WatchGolfCourseDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Mock Golf Course Service

class MockWatchGolfCourseService: WatchGolfCourseServiceProtocol {
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "MockGolfCourse")
    private var delegates: [WeakGolfCourseDelegate] = []
    private var currentCourse: SharedGolfCourse?
    private var courseCache: [String: SharedGolfCourse] = [:]
    private var holeCache: [String: [SharedHoleInfo]] = [:]
    
    init() {
        setupMockData()
        logger.info("MockWatchGolfCourseService initialized")
    }
    
    private func setupMockData() {
        let mockCourse = SharedGolfCourse(
            id: "mock-course-1",
            name: "Mock Golf Club",
            address: "123 Golf Course Dr",
            city: "Golf City",
            state: "CA",
            latitude: 37.7749,
            longitude: -122.4194,
            numberOfHoles: 18,
            par: 72,
            yardage: SharedCourseYardage(backTees: 6800, regularTees: 6200, forwardTees: 5400),
            hasGPS: true,
            hasDrivingRange: true,
            hasRestaurant: true,
            cartRequired: false,
            averageRating: 4.2,
            difficulty: .intermediate,
            isOpen: true,
            isActive: true
        )
        
        currentCourse = mockCourse
        courseCache[mockCourse.id] = mockCourse
        
        Task {
            await preloadCourse(mockCourse)
        }
    }
    
    func getCurrentCourse() async -> SharedGolfCourse? {
        return currentCourse
    }
    
    func getCourseById(_ courseId: String) async -> SharedGolfCourse? {
        return courseCache[courseId]
    }
    
    func getHoleInformation(courseId: String, holeNumber: Int) async -> SharedHoleInfo? {
        return holeCache[courseId]?.first { $0.holeNumber == holeNumber }
    }
    
    func getAllHoles(for courseId: String) async -> [SharedHoleInfo] {
        return holeCache[courseId] ?? []
    }
    
    func getDistanceToPin(from location: CLLocationCoordinate2D, holeNumber: Int) async -> Int? {
        return Int.random(in: 80...180) // Mock distance
    }
    
    func getDistanceToHazards(from location: CLLocationCoordinate2D, holeNumber: Int) async -> [(SharedHazard, Int)] {
        return [] // Mock - no hazards
    }
    
    func getRecommendedClub(for distance: Int, conditions: PlayingConditions?) -> String? {
        if distance < 100 { return "SW" }
        else if distance < 130 { return "9 Iron" }
        else if distance < 150 { return "7 Iron" }
        else if distance < 170 { return "5 Iron" }
        else { return "Driver" }
    }
    
    func preloadCourse(_ course: SharedGolfCourse) async {
        courseCache[course.id] = course
        // Generate mock holes similar to the real service
        let holes = (1...course.numberOfHoles).map { holeNumber in
            SharedHoleInfo(
                id: "hole-\(course.id)-\(holeNumber)",
                holeNumber: holeNumber,
                par: holeNumber <= 6 ? 4 : (holeNumber == 9 || holeNumber == 18 ? 5 : 3),
                yardage: Int.random(in: 150...450),
                handicapIndex: holeNumber,
                teeCoordinate: CLLocationCoordinate2D(latitude: course.latitude, longitude: course.longitude),
                pinCoordinate: CLLocationCoordinate2D(latitude: course.latitude + 0.001, longitude: course.longitude + 0.001),
                hazards: []
            )
        }
        holeCache[course.id] = holes
    }
    
    func clearCourseCache() {
        courseCache.removeAll()
        holeCache.removeAll()
    }
    
    func requestCourseFromiPhone(courseId: String) async -> SharedGolfCourse? {
        // Simulate delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        return courseCache[courseId]
    }
    
    func syncCourseData() async {
        // Mock sync - no operation needed
        logger.debug("Mock sync course data")
    }
    
    func setDelegate(_ delegate: WatchGolfCourseDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        delegates.append(WeakGolfCourseDelegate(delegate))
        delegates.removeAll { $0.delegate == nil }
    }
    
    func removeDelegate(_ delegate: WatchGolfCourseDelegate) {
        delegates.removeAll { $0.delegate === delegate }
    }
}