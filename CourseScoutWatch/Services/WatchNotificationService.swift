import Foundation
import UserNotifications
import WatchKit
import os.log

// MARK: - Watch Notification Service Protocol

protocol WatchNotificationServiceProtocol: AnyObject {
    // Authorization
    func requestNotificationPermission() async -> Bool
    var authorizationStatus: UNAuthorizationStatus { get }
    
    // Golf-specific notifications
    func scheduleTeeTimeReminder(for teeTime: TeeTime) async throws
    func scheduleHoleMilestoneNotification(holeNumber: Int, par: Int) async throws
    func scheduleScoreNotification(score: Int, par: Int, holeNumber: Int) async throws
    func scheduleCraftTimerMilestone(milestone: CraftMilestone, elapsedTime: TimeInterval) async throws
    func scheduleBreathingReminder(interval: TimeInterval) async throws
    
    // Health & fitness notifications
    func scheduleHeartRateZoneNotification(zone: HeartRateZone, heartRate: Double) async throws
    func scheduleHydrationReminder() async throws
    func schedulePostRoundSummary(summary: GolfWorkoutSummary) async throws
    
    // Weather alerts
    func scheduleWeatherAlert(conditions: WeatherConditions) async throws
    func scheduleSevereWeatherWarning(warning: WeatherWarning) async throws
    
    // iPhone synchronization notifications
    func schedulePhoneDisconnectedAlert() async throws
    func scheduleDataSyncNotification(type: SyncDataType) async throws
    
    // Management
    func cancelNotification(withIdentifier identifier: String)
    func cancelAllNotifications()
    func getPendingNotifications() async -> [UNNotificationRequest]
    func getDeliveredNotifications() async -> [UNNotification]
    
    // Delegate
    func setDelegate(_ delegate: WatchNotificationDelegate)
    func removeDelegate(_ delegate: WatchNotificationDelegate)
}

// MARK: - Watch Notification Delegate

protocol WatchNotificationDelegate: AnyObject {
    func didReceiveNotification(_ notification: UNNotification, withResponse response: UNNotificationResponse?)
    func willPresentNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions
    func didFailToScheduleNotification(error: Error)
}

// Default implementations
extension WatchNotificationDelegate {
    func didReceiveNotification(_ notification: UNNotification, withResponse response: UNNotificationResponse?) {}
    func willPresentNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
    func didFailToScheduleNotification(error: Error) {}
}

// MARK: - Watch Notification Service Implementation

@MainActor
class WatchNotificationService: NSObject, WatchNotificationServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "Notifications")
    
    // Dependencies
    @WatchServiceInjected(WatchHapticFeedbackServiceProtocol.self) private var hapticService
    @WatchServiceInjected(WatchConnectivityServiceProtocol.self) private var connectivityService
    
    // State
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    // Delegate management
    private var delegates: [WeakNotificationDelegate] = []
    
    // Notification categories
    private let golfActionCategory = "GOLF_ACTION"
    private let timerActionCategory = "TIMER_ACTION"
    private let healthActionCategory = "HEALTH_ACTION"
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupNotificationCenter()
        setupNotificationCategories()
        logger.info("WatchNotificationService initialized")
    }
    
    private func setupNotificationCenter() {
        notificationCenter.delegate = self
        
        Task {
            let currentStatus = await notificationCenter.notificationSettings().authorizationStatus
            await MainActor.run {
                authorizationStatus = currentStatus
            }
        }
    }
    
    private func setupNotificationCategories() {
        // Golf action category
        let scoreAction = UNNotificationAction(
            identifier: "QUICK_SCORE",
            title: "Enter Score",
            options: []
        )
        let viewHoleAction = UNNotificationAction(
            identifier: "VIEW_HOLE",
            title: "View Hole",
            options: [.foreground]
        )
        let golfCategory = UNNotificationCategory(
            identifier: golfActionCategory,
            actions: [scoreAction, viewHoleAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Timer action category
        let pauseTimerAction = UNNotificationAction(
            identifier: "PAUSE_TIMER",
            title: "Pause",
            options: []
        )
        let completeTimerAction = UNNotificationAction(
            identifier: "COMPLETE_TIMER",
            title: "Complete",
            options: []
        )
        let timerCategory = UNNotificationCategory(
            identifier: timerActionCategory,
            actions: [pauseTimerAction, completeTimerAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Health action category
        let viewHealthAction = UNNotificationAction(
            identifier: "VIEW_HEALTH",
            title: "View Metrics",
            options: [.foreground]
        )
        let healthCategory = UNNotificationCategory(
            identifier: healthActionCategory,
            actions: [viewHealthAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([golfCategory, timerCategory, healthCategory])
    }
    
    // MARK: - Authorization
    
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            
            await MainActor.run {
                authorizationStatus = granted ? .authorized : .denied
            }
            
            logger.info("Notification permission: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription)")
            
            await MainActor.run {
                authorizationStatus = .denied
            }
            
            notifyDelegates { delegate in
                delegate.didFailToScheduleNotification(error: error)
            }
            
            return false
        }
    }
    
    // MARK: - Golf-Specific Notifications
    
    func scheduleTeeTimeReminder(for teeTime: TeeTime) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Tee Time Reminder"
        content.body = "Your tee time at \(teeTime.courseName) is in 30 minutes"
        content.sound = .default
        content.categoryIdentifier = golfActionCategory
        content.userInfo = [
            "type": "tee_time_reminder",
            "course_id": teeTime.courseId,
            "tee_time_id": teeTime.id
        ]
        
        let reminderTime = Calendar.current.date(byAdding: .minute, value: -30, to: teeTime.time) ?? teeTime.time
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderTime),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "tee_time_\(teeTime.id)",
            content: content,
            trigger: trigger
        )
        
        try await notificationCenter.add(request)
        logger.info("Scheduled tee time reminder for \(teeTime.courseName)")
    }
    
    func scheduleHoleMilestoneNotification(holeNumber: Int, par: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Hole \(holeNumber) - Par \(par)"
        content.body = "You're now on hole \(holeNumber). Good luck!"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("golf_chime.wav"))
        content.categoryIdentifier = golfActionCategory
        content.userInfo = [
            "type": "hole_milestone",
            "hole_number": holeNumber,
            "par": par
        ]
        
        let request = UNNotificationRequest(
            identifier: "hole_milestone_\(holeNumber)",
            content: content,
            trigger: nil // Immediate
        )
        
        try await notificationCenter.add(request)
        
        // Provide haptic feedback
        hapticService.playMilestoneHaptic()
        
        logger.info("Scheduled hole milestone notification for hole \(holeNumber)")
    }
    
    func scheduleScoreNotification(score: Int, par: Int, holeNumber: Int) async throws {
        let relative = score - par
        
        let content = UNMutableNotificationContent()
        content.title = "Score Recorded"
        
        switch relative {
        case -3:
            content.body = "Albatross on hole \(holeNumber)! Incredible! 🦅"
        case -2:
            content.body = "Eagle on hole \(holeNumber)! Amazing! 🦅"
        case -1:
            content.body = "Birdie on hole \(holeNumber)! Great shot! 🐦"
        case 0:
            content.body = "Par on hole \(holeNumber). Well played!"
        case 1:
            content.body = "Bogey on hole \(holeNumber). Still a solid round!"
        case 2:
            content.body = "Double bogey on hole \(holeNumber). Next hole!"
        default:
            if relative < 0 {
                content.body = "Amazing \(abs(relative))-under on hole \(holeNumber)! 🏆"
            } else {
                content.body = "Score recorded for hole \(holeNumber). Keep going!"
            }
        }
        
        content.sound = relative <= 0 ? .default : UNNotificationSound(named: UNNotificationSoundName("gentle_chime.wav"))
        content.categoryIdentifier = golfActionCategory
        content.userInfo = [
            "type": "score_recorded",
            "hole_number": holeNumber,
            "score": score,
            "par": par
        ]
        
        let request = UNNotificationRequest(
            identifier: "score_\(holeNumber)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        try await notificationCenter.add(request)
        logger.info("Scheduled score notification: \(score) on par \(par)")
    }
    
    func scheduleCraftTimerMilestone(milestone: CraftMilestone, elapsedTime: TimeInterval) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Craft Timer Milestone"
        content.body = milestone.message
        content.sound = UNNotificationSound(named: UNNotificationSoundName("meditation_chime.wav"))
        content.categoryIdentifier = timerActionCategory
        content.userInfo = [
            "type": "craft_timer_milestone",
            "milestone_id": milestone.id.uuidString,
            "elapsed_time": elapsedTime
        ]
        
        let request = UNNotificationRequest(
            identifier: "craft_milestone_\(milestone.id.uuidString)",
            content: content,
            trigger: nil
        )
        
        try await notificationCenter.add(request)
        
        // Special haptic for breathing reminders
        if milestone.includesBreathingReminder {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.hapticService.playBreathingInhale()
            }
        }
        
        logger.info("Scheduled craft timer milestone: \(milestone.message)")
    }
    
    func scheduleBreathingReminder(interval: TimeInterval) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Breathing Reminder"
        content.body = "Take a moment for mindful breathing to enhance your focus"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("breathing_bell.wav"))
        content.userInfo = [
            "type": "breathing_reminder",
            "interval": interval
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "breathing_reminder",
            content: content,
            trigger: trigger
        )
        
        try await notificationCenter.add(request)
        logger.info("Scheduled breathing reminder every \(interval) seconds")
    }
    
    // MARK: - Health & Fitness Notifications
    
    func scheduleHeartRateZoneNotification(zone: HeartRateZone, heartRate: Double) async throws {
        let content = UNMutableNotificationContent()
        
        switch zone {
        case .max:
            content.title = "High Heart Rate Alert"
            content.body = "Your heart rate is \(Int(heartRate)) BPM. Consider slowing down."
            content.sound = UNNotificationSound.defaultCritical
        case .anaerobic:
            content.title = "Intense Zone"
            content.body = "You're in the anaerobic zone (\(Int(heartRate)) BPM). Great workout!"
        case .aerobic:
            content.title = "Optimal Zone"
            content.body = "Perfect! You're in the aerobic zone (\(Int(heartRate)) BPM)."
        default:
            return // Don't notify for lower zones
        }
        
        content.categoryIdentifier = healthActionCategory
        content.userInfo = [
            "type": "heart_rate_zone",
            "zone": zone.displayName,
            "heart_rate": heartRate
        ]
        
        let request = UNNotificationRequest(
            identifier: "heart_rate_zone_\(zone.displayName)",
            content: content,
            trigger: nil
        )
        
        try await notificationCenter.add(request)
        logger.info("Scheduled heart rate zone notification: \(zone.displayName)")
    }
    
    func scheduleHydrationReminder() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Stay Hydrated"
        content.body = "Remember to drink water during your round!"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("water_drop.wav"))
        content.userInfo = [
            "type": "hydration_reminder"
        ]
        
        // Schedule for every 45 minutes during active golf
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 45 * 60, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "hydration_reminder",
            content: content,
            trigger: trigger
        )
        
        try await notificationCenter.add(request)
        logger.info("Scheduled hydration reminders")
    }
    
    func schedulePostRoundSummary(summary: GolfWorkoutSummary) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Round Complete!"
        content.body = "Great round! Score: \(summary.totalScore) • \(Int(summary.caloriesBurned)) calories • \(Int(summary.walkingDistance)) miles"
        content.sound = .default
        content.categoryIdentifier = golfActionCategory
        content.userInfo = [
            "type": "round_summary",
            "total_score": summary.totalScore,
            "calories": summary.caloriesBurned,
            "distance": summary.walkingDistance
        ]
        
        let request = UNNotificationRequest(
            identifier: "round_summary_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        try await notificationCenter.add(request)
        logger.info("Scheduled post-round summary")
    }
    
    // MARK: - Weather Alerts
    
    func scheduleWeatherAlert(conditions: WeatherConditions) async throws {
        // Only alert for significant weather changes
        guard conditions.playabilityScore <= 5 else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Weather Alert"
        content.body = "\(conditions.conditions.displayName) - Golf playability: \(conditions.playabilityScore)/10"
        content.sound = .default
        content.userInfo = [
            "type": "weather_alert",
            "conditions": conditions.conditions.rawValue,
            "playability_score": conditions.playabilityScore
        ]
        
        let request = UNNotificationRequest(
            identifier: "weather_alert_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        try await notificationCenter.add(request)
        logger.info("Scheduled weather alert: \(conditions.conditions.displayName)")
    }
    
    func scheduleSevereWeatherWarning(warning: WeatherWarning) async throws {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Severe Weather Warning"
        content.body = warning.description
        content.sound = .defaultCritical
        content.interruptionLevel = .critical
        content.userInfo = [
            "type": "severe_weather",
            "warning_type": warning.type.rawValue,
            "severity": warning.severity.rawValue
        ]
        
        let request = UNNotificationRequest(
            identifier: "severe_weather_\(warning.id)",
            content: content,
            trigger: nil
        )
        
        try await notificationCenter.add(request)
        logger.warning("Scheduled severe weather warning: \(warning.type.rawValue)")
    }
    
    // MARK: - iPhone Synchronization Notifications
    
    func schedulePhoneDisconnectedAlert() async throws {
        let content = UNMutableNotificationContent()
        content.title = "iPhone Disconnected"
        content.body = "Some features may be limited. Move closer to your iPhone or check Bluetooth."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("connection_lost.wav"))
        content.userInfo = [
            "type": "phone_disconnected"
        ]
        
        let request = UNNotificationRequest(
            identifier: "phone_disconnected",
            content: content,
            trigger: nil
        )
        
        try await notificationCenter.add(request)
        logger.info("Scheduled phone disconnected alert")
    }
    
    func scheduleDataSyncNotification(type: SyncDataType) async throws {
        let content = UNMutableNotificationContent()
        
        switch type {
        case .scorecard:
            content.title = "Scorecard Synced"
            content.body = "Your scores have been synced to your iPhone"
        case .health:
            content.title = "Health Data Synced"
            content.body = "Workout metrics synced to iPhone"
        case .course:
            content.title = "Course Data Updated"
            content.body = "Latest course information received"
        }
        
        content.sound = UNNotificationSound(named: UNNotificationSoundName("sync_complete.wav"))
        content.userInfo = [
            "type": "data_sync",
            "sync_type": type.rawValue
        ]
        
        let request = UNNotificationRequest(
            identifier: "data_sync_\(type.rawValue)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        try await notificationCenter.add(request)
        logger.info("Scheduled data sync notification: \(type.rawValue)")
    }
    
    // MARK: - Management
    
    func cancelNotification(withIdentifier identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        logger.info("Cancelled notification: \(identifier)")
    }
    
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        logger.info("Cancelled all notifications")
    }
    
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }
    
    func getDeliveredNotifications() async -> [UNNotification] {
        return await notificationCenter.deliveredNotifications()
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: WatchNotificationDelegate) {
        delegates.removeAll { $0.delegate == nil }
        delegates.append(WeakNotificationDelegate(delegate))
        logger.info("Added notification delegate")
    }
    
    func removeDelegate(_ delegate: WatchNotificationDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        logger.info("Removed notification delegate")
    }
    
    private func notifyDelegates<T>(_ action: (WatchNotificationDelegate) -> T) {
        delegates.forEach { weakDelegate in
            if let delegate = weakDelegate.delegate {
                _ = action(delegate)
            }
        }
        
        // Clean up nil references
        delegates.removeAll { $0.delegate == nil }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension WatchNotificationService: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        logger.debug("Will present notification: \(notification.request.identifier)")
        
        // Get presentation options from delegates
        var presentationOptions: UNNotificationPresentationOptions = [.banner, .sound]
        
        for delegate in delegates {
            if let delegate = delegate.delegate {
                let options = delegate.willPresentNotification(notification)
                presentationOptions = presentationOptions.union(options)
            }
        }
        
        completionHandler(presentationOptions)
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        logger.debug("Did receive notification response: \(response.actionIdentifier)")
        
        // Handle actions
        Task {
            await handleNotificationAction(response)
            
            // Notify delegates
            notifyDelegates { delegate in
                delegate.didReceiveNotification(response.notification, withResponse: response)
            }
            
            completionHandler()
        }
    }
    
    private func handleNotificationAction(_ response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case "QUICK_SCORE":
            await handleQuickScoreAction(userInfo: userInfo)
        case "VIEW_HOLE":
            await handleViewHoleAction(userInfo: userInfo)
        case "PAUSE_TIMER":
            await handlePauseTimerAction(userInfo: userInfo)
        case "COMPLETE_TIMER":
            await handleCompleteTimerAction(userInfo: userInfo)
        case "VIEW_HEALTH":
            await handleViewHealthAction(userInfo: userInfo)
        default:
            logger.debug("Unhandled notification action: \(response.actionIdentifier)")
        }
    }
    
    private func handleQuickScoreAction(userInfo: [AnyHashable: Any]) async {
        guard let holeNumber = userInfo["hole_number"] as? Int else { return }
        
        // Launch to quick score entry
        let deepLink = "golfinder://score?hole=\(holeNumber)"
        if let url = URL(string: deepLink) {
            WKExtension.shared().openSystemURL(url)
        }
        
        logger.info("Handled quick score action for hole \(holeNumber)")
    }
    
    private func handleViewHoleAction(userInfo: [AnyHashable: Any]) async {
        // Launch to current hole view
        let deepLink = "golfinder://current-hole"
        if let url = URL(string: deepLink) {
            WKExtension.shared().openSystemURL(url)
        }
        
        logger.info("Handled view hole action")
    }
    
    private func handlePauseTimerAction(userInfo: [AnyHashable: Any]) async {
        // Send pause command to timer
        let message: [String: Any] = [
            "type": "timer_command",
            "action": "pause",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        try? await connectivityService.sendMessage(message, priority: .normal)
        logger.info("Handled pause timer action")
    }
    
    private func handleCompleteTimerAction(userInfo: [AnyHashable: Any]) async {
        // Send complete command to timer
        let message: [String: Any] = [
            "type": "timer_command",
            "action": "complete",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        try? await connectivityService.sendMessage(message, priority: .normal)
        logger.info("Handled complete timer action")
    }
    
    private func handleViewHealthAction(userInfo: [AnyHashable: Any]) async {
        // Launch to health metrics view
        let deepLink = "golfinder://health"
        if let url = URL(string: deepLink) {
            WKExtension.shared().openSystemURL(url)
        }
        
        logger.info("Handled view health action")
    }
}

// MARK: - Supporting Types

struct WeatherWarning {
    let id: String
    let type: WarningType
    let severity: Severity
    let description: String
    
    enum WarningType: String {
        case thunderstorm = "thunderstorm"
        case heavyRain = "heavy_rain"
        case highWinds = "high_winds"
        case extremeTemperature = "extreme_temperature"
    }
    
    enum Severity: String {
        case watch = "watch"
        case warning = "warning"
        case emergency = "emergency"
    }
}

enum SyncDataType: String {
    case scorecard = "scorecard"
    case health = "health"
    case course = "course"
}

struct TeeTime {
    let id: String
    let courseId: String
    let courseName: String
    let time: Date
}

struct GolfWorkoutSummary {
    let totalScore: Int
    let caloriesBurned: Double
    let walkingDistance: Double
    let duration: TimeInterval
    let averageHeartRate: Double
}

private struct WeakNotificationDelegate {
    weak var delegate: WatchNotificationDelegate?
    
    init(_ delegate: WatchNotificationDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Extensions

extension WatchNotificationService {
    
    // Convenience methods for common notifications
    func notifyScoreRecorded(_ score: Int, par: Int, hole: Int) {
        Task {
            try? await scheduleScoreNotification(score: score, par: par, holeNumber: hole)
        }
    }
    
    func notifyMilestoneReached(_ milestone: CraftMilestone, elapsedTime: TimeInterval) {
        Task {
            try? await scheduleCraftTimerMilestone(milestone: milestone, elapsedTime: elapsedTime)
        }
    }
    
    func notifyHeartRateZone(_ zone: HeartRateZone, heartRate: Double) {
        Task {
            try? await scheduleHeartRateZoneNotification(zone: zone, heartRate: heartRate)
        }
    }
    
    func notifyPhoneDisconnected() {
        Task {
            try? await schedulePhoneDisconnectedAlert()
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension WatchNotificationService {
    static let mock = WatchNotificationService()
}
#endif