import Foundation
import CoreLocation
import WatchKit

// MARK: - Watch GPS Service Protocol

protocol WatchGPSServiceProtocol: AnyObject {
    var currentLocation: CLLocationCoordinate2D? { get }
    var isLocationEnabled: Bool { get }
    var locationAccuracy: Double { get }
    
    func startLocationUpdates()
    func stopLocationUpdates()
    func requestLocationPermission() async -> Bool
    
    func setDelegate(_ delegate: WatchGPSDelegate)
    func removeDelegate(_ delegate: WatchGPSDelegate)
}

protocol WatchGPSDelegate: AnyObject {
    func didUpdateLocation(_ location: CLLocationCoordinate2D, accuracy: Double)
    func didFailToGetLocation(error: Error)
    func didChangeLocationPermission(_ status: CLAuthorizationStatus)
}

// MARK: - Watch Workout Service Protocol

protocol WatchWorkoutServiceProtocol: AnyObject {
    var isWorkoutActive: Bool { get }
    var currentWorkout: GolfWorkout? { get }
    
    func startGolfWorkout(courseId: String, courseName: String) async -> Bool
    func endGolfWorkout() async -> GolfWorkout?
    func pauseWorkout()
    func resumeWorkout()
    
    func recordMilestone(_ milestone: WorkoutMilestone)
    func getWorkoutStatistics() -> WorkoutStatistics?
    
    func setDelegate(_ delegate: WatchWorkoutDelegate)
    func removeDelegate(_ delegate: WatchWorkoutDelegate)
}

protocol WatchWorkoutDelegate: AnyObject {
    func didStartWorkout(_ workout: GolfWorkout)
    func didEndWorkout(_ workout: GolfWorkout)
    func didRecordMilestone(_ milestone: WorkoutMilestone)
    func didUpdateHeartRate(_ heartRate: Double)
}

// MARK: - Watch Haptic Feedback Service Protocol

protocol WatchHapticFeedbackServiceProtocol: AnyObject {
    func playTaptic(_ type: WatchTapticType)
    func playCustomPattern(_ pattern: WatchHapticPattern)
    func playSuccessSequence()
    func playErrorSequence()
    func playNavigationFeedback()
    func playScoreFeedback(relativeToPar: Int)
    
    func setHapticEnabled(_ enabled: Bool)
    var isHapticEnabled: Bool { get }
}

enum WatchTapticType {
    case light
    case medium
    case heavy
    case success
    case error
    case warning
    case notification
}

struct WatchHapticPattern {
    let events: [WatchHapticEvent]
    let duration: TimeInterval
}

struct WatchHapticEvent {
    let intensity: Float // 0.0 - 1.0
    let sharpness: Float // 0.0 - 1.0
    let time: TimeInterval
}

// MARK: - Watch Complication Service Protocol

protocol WatchComplicationServiceProtocol: AnyObject {
    func getCurrentComplicationData() -> WatchComplicationData?
    func updateComplications()
    func scheduleComplicationUpdates(for round: ActiveGolfRound)
    func clearComplicationData()
    
    func getSupportedComplicationFamilies() -> [ComplicationFamily]
    func getTimelineEntries(for family: ComplicationFamily, limit: Int) -> [ComplicationTimelineEntry]
}

struct WatchComplicationData {
    let currentHole: Int?
    let currentScore: String?
    let courseId: String?
    let courseName: String?
    let lastUpdated: Date
}

enum ComplicationFamily {
    case modularSmall
    case modularLarge
    case utilitarianSmall
    case utilitarianLarge
    case circularSmall
    case extraLarge
    case graphicCorner
    case graphicBezel
    case graphicCircular
    case graphicRectangular
}

struct ComplicationTimelineEntry {
    let date: Date
    let data: WatchComplicationData
}

// MARK: - Watch Notification Service Protocol

protocol WatchNotificationServiceProtocol: AnyObject {
    func scheduleScoreReminder(for holeNumber: Int, delay: TimeInterval)
    func cancelScoreReminder(for holeNumber: Int)
    func sendRoundCompletionNotification(_ scorecard: SharedScorecard)
    func sendMilestoneNotification(_ milestone: String, score: String)
    
    func requestNotificationPermission() async -> Bool
    var notificationPermissionStatus: NotificationPermissionStatus { get }
}

enum NotificationPermissionStatus {
    case notDetermined
    case denied
    case authorized
    case provisional
}

// MARK: - Watch Cache Service Protocol

protocol WatchCacheServiceProtocol: AnyObject {
    func store<T: Codable>(_ object: T, forKey key: String) async
    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) async -> T?
    func remove(forKey key: String) async
    func clearCache() async
    
    func getCacheSize() -> Int64
    func performCacheCleanup() async
    
    // Golf-specific caching
    func cacheCourse(_ course: SharedGolfCourse) async
    func getCachedCourse(id: String) async -> SharedGolfCourse?
    func cacheActiveRound(_ round: ActiveGolfRound) async
    func getCachedActiveRound() async -> ActiveGolfRound?
}

// MARK: - Watch Sync Service Protocol

protocol WatchSyncServiceProtocol: AnyObject {
    func syncAll() async -> Bool
    func syncCourseData() async -> Bool
    func syncActiveRound() async -> Bool
    func syncScorecard() async -> Bool
    
    func hasPendingSyncData() -> Bool
    func processPendingSyncs() async
    
    var lastSyncTime: Date? { get }
    var syncStatus: WatchSyncStatus { get }
    
    func setDelegate(_ delegate: WatchSyncDelegate)
    func removeDelegate(_ delegate: WatchSyncDelegate)
}

protocol WatchSyncDelegate: AnyObject {
    func didStartSync(type: WatchSyncType)
    func didCompleteSync(type: WatchSyncType, success: Bool)
    func didReceiveSyncData(type: WatchSyncType, data: Any)
}

enum WatchSyncStatus {
    case idle
    case syncing
    case failed(Error)
    case completed(Date)
}

enum WatchSyncType {
    case course
    case activeRound
    case scorecard
    case all
}

// MARK: - Watch Analytics Service Protocol

protocol WatchAnalyticsServiceProtocol: AnyObject {
    func trackEvent(_ event: WatchAnalyticsEvent)
    func trackScreenView(_ screen: String)
    func trackUserAction(_ action: String, parameters: [String: Any]?)
    func trackPerformanceMetric(_ metric: String, value: Double)
    
    func setUserProperty(_ property: String, value: String)
    func incrementCounter(_ counter: String)
    
    var isEnabled: Bool { get set }
    func flush() async
}

struct WatchAnalyticsEvent {
    let name: String
    let parameters: [String: Any]
    let timestamp: Date
}

// MARK: - Watch Performance Service Protocol

protocol WatchPerformanceServiceProtocol: AnyObject {
    func startPerformanceMonitoring()
    func stopPerformanceMonitoring()
    
    func recordAppLaunchTime(_ time: TimeInterval)
    func recordScreenLoadTime(screen: String, time: TimeInterval)
    func recordServiceCallTime(service: String, method: String, time: TimeInterval)
    
    func getCurrentMemoryUsage() -> MemoryUsage
    func getBatteryLevel() -> Double
    func getThermalState() -> ProcessInfo.ThermalState
    
    func getPerformanceReport() -> WatchPerformanceReport
}

struct MemoryUsage {
    let used: Int64 // bytes
    let available: Int64 // bytes
    let total: Int64 // bytes
    
    var usedPercentage: Double {
        return Double(used) / Double(total) * 100.0
    }
}

struct WatchPerformanceReport {
    let averageAppLaunchTime: TimeInterval
    let screenLoadTimes: [String: TimeInterval]
    let serviceCallTimes: [String: TimeInterval]
    let averageMemoryUsage: Double
    let batteryUsageRate: Double
    let reportGenerated: Date
}

// MARK: - Golf-Specific Models

struct GolfWorkout {
    let id: String
    let courseId: String
    let courseName: String
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval { endTime?.timeIntervalSince(startTime) ?? Date().timeIntervalSince(startTime) }
    
    let workoutType: WorkoutType
    var statistics: WorkoutStatistics
}

enum WorkoutType {
    case golf18Holes
    case golf9Holes
    case drivingRange
    case putting
}

struct WorkoutStatistics {
    var totalDistance: Double // meters walked
    var averageHeartRate: Double
    var maxHeartRate: Double
    var caloriesBurned: Double
    var steps: Int
    
    // Golf-specific stats
    var holesCompleted: Int
    var shotsTracked: Int
    var averageShotDistance: Double?
}

struct WorkoutMilestone {
    let id: String
    let workoutId: String
    let type: MilestoneType
    let timestamp: Date
    let data: [String: Any]
}

enum MilestoneType {
    case holeCompleted(holeNumber: Int)
    case frontNineCompleted
    case backNineCompleted
    case roundCompleted
    case personalBest(category: String)
    case heartRateZone(zone: Int)
}

// MARK: - Mock Service Protocols (for testing)

// These would be implemented as simple mock classes for testing
protocol MockWatchGolfCourseServiceProtocol: WatchGolfCourseServiceProtocol {}
protocol MockWatchScorecardServiceProtocol: WatchScorecardServiceProtocol {}
protocol MockWatchGPSServiceProtocol: WatchGPSServiceProtocol {}
protocol MockWatchWorkoutServiceProtocol: WatchWorkoutServiceProtocol {}
protocol MockWatchHapticFeedbackServiceProtocol: WatchHapticFeedbackServiceProtocol {}
protocol MockWatchComplicationServiceProtocol: WatchComplicationServiceProtocol {}
protocol MockWatchNotificationServiceProtocol: WatchNotificationServiceProtocol {}
protocol MockWatchCacheServiceProtocol: WatchCacheServiceProtocol {}
protocol MockWatchSyncServiceProtocol: WatchSyncServiceProtocol {}
protocol MockWatchAnalyticsServiceProtocol: WatchAnalyticsServiceProtocol {}
protocol MockWatchPerformanceServiceProtocol: WatchPerformanceServiceProtocol {}