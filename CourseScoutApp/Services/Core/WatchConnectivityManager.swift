import Foundation
import WatchConnectivity
import Combine
import os.log
import CoreLocation
import HealthKit

// MARK: - iPhone-Side Watch Connectivity Manager

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject, WatchConnectivityManagerProtocol {
    
    // MARK: - Singleton
    
    static let shared = WatchConnectivityManager()
    
    // MARK: - Properties
    
    private let session: WCSession
    private let logger = Logger(subsystem: "GolfFinder", category: "WatchConnectivity")
    
    // Published state
    @Published var isWatchPaired = false
    @Published var isWatchAppInstalled = false
    @Published var isWatchReachable = false
    @Published var connectionState: WatchConnectionState = .disconnected
    @Published var syncState: WatchSyncState = .idle
    @Published var lastSyncTime: Date?
    @Published var batteryInfo: WatchBatteryInfo?
    
    // Message handling
    private let messageQueue = PriorityMessageQueue()
    private var pendingMessages = [String: PendingMessage]()
    private var messageRetryTimer: Timer?
    
    // Data synchronization
    private var syncQueue = DispatchQueue(label: "com.golffinder.watch.sync", qos: .userInitiated)
    private var dataCompressionEngine = DataCompressionEngine()
    private var conflictResolver = ConflictResolver()
    
    // Golf-specific data
    @Published var activeRound: ActiveGolfRound?
    @Published var currentScorecard: SharedScorecard?
    @Published var watchHealthMetrics: WatchHealthMetrics?
    
    // Performance monitoring
    private var performanceMonitor = WatchPerformanceMonitor()
    private var batteryOptimizer = WatchBatteryOptimizer()
    
    // Background task management
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundSyncTimer: Timer?
    
    // Delegates
    private var delegates = NSHashTable<AnyObject>.weakObjects()
    
    // MARK: - Protocol Conformance - Delegate Management
    
    func addDelegate(_ delegate: WatchConnectivityDelegate) {
        delegates.add(delegate)
    }
    
    func removeDelegate(_ delegate: WatchConnectivityDelegate) {
        delegates.remove(delegate)
    }
    
    // MARK: - Initialization
    
    private override init() {
        self.session = WCSession.default
        super.init()
        
        setupWatchConnectivity()
        setupBackgroundSync()
        setupNotificationObservers()
    }
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            logger.warning("WatchConnectivity not supported on this device")
            return
        }
        
        session.delegate = self
        session.activate()
        
        logger.info("WatchConnectivityManager initialized")
    }
    
    // MARK: - Public Interface
    
    /// Start watch connectivity and synchronization
    func startConnectivity() {
        guard WCSession.isSupported() else { return }
        
        updateConnectionState()
        startConnectionMonitoring()
        
        if isWatchReachable {
            Task {
                await performInitialSync()
            }
        }
    }
    
    /// Stop watch connectivity and clean up
    func stopConnectivity() {
        stopConnectionMonitoring()
        cancelAllPendingMessages()
        endBackgroundTask()
    }
    
    // MARK: - Golf Round Management
    
    /// Start a new golf round and sync with watch
    func startGolfRound(_ round: ActiveGolfRound) async -> Bool {
        self.activeRound = round
        
        // Prepare optimized data for watch
        let roundData = prepareRoundDataForWatch(round)
        
        // Send with high priority
        return await sendHighPriorityMessage(
            type: .startRound,
            data: roundData,
            requiresAck: true
        )
    }
    
    /// Update scorecard and sync with watch
    func updateScorecard(_ scorecard: SharedScorecard) async {
        self.currentScorecard = scorecard
        
        // Use intelligent sync to minimize data transfer
        await performIntelligentScorecardSync(scorecard)
    }
    
    /// End golf round and sync final data
    func endGolfRound() async -> Bool {
        guard let round = activeRound else { return false }
        
        let success = await sendHighPriorityMessage(
            type: .endRound,
            data: ["roundId": round.id],
            requiresAck: true
        )
        
        if success {
            self.activeRound = nil
            self.currentScorecard = nil
        }
        
        return success
    }
    
    // MARK: - Priority-based Message Queue
    
    func sendHighPriorityMessage(type: MessageType, data: [String: Any], requiresAck: Bool = false) async -> Bool {
        let message = PriorityMessage(
            id: UUID().uuidString,
            type: type,
            priority: .high,
            data: data,
            requiresAck: requiresAck,
            timestamp: Date()
        )
        
        return await sendPriorityMessage(message)
    }
    
    func sendNormalPriorityMessage(type: MessageType, data: [String: Any]) async {
        let message = PriorityMessage(
            id: UUID().uuidString,
            type: type,
            priority: .normal,
            data: data,
            requiresAck: false,
            timestamp: Date()
        )
        
        _ = await sendPriorityMessage(message)
    }
    
    private func sendPriorityMessage(_ message: PriorityMessage) async -> Bool {
        // Add to queue
        messageQueue.enqueue(message)
        
        // Process queue based on connection state
        if isWatchReachable {
            return await processMessageQueue()
        } else {
            // Store for later delivery
            storePendingMessage(message)
            return false
        }
    }
    
    // MARK: - Intelligent Data Synchronization
    
    private func performInitialSync() async {
        syncState = .syncing
        
        do {
            // Sync essential data first
            await syncEssentialData()
            
            // Then sync cached course data
            await syncCachedCourseData()
            
            // Finally sync user preferences
            await syncUserPreferences()
            
            lastSyncTime = Date()
            syncState = .completed
            
            logger.info("Initial sync completed successfully")
        } catch {
            syncState = .failed(error)
            logger.error("Initial sync failed: \(error)")
        }
    }
    
    private func performIntelligentScorecardSync(_ scorecard: SharedScorecard) async {
        // Only sync changed data
        let delta = calculateScorecardDelta(scorecard)
        
        if !delta.isEmpty {
            await sendNormalPriorityMessage(
                type: .scorecardUpdate,
                data: delta
            )
        }
    }
    
    // MARK: - Battery-Conscious Communication
    
    func enableBatteryOptimization(_ enabled: Bool) {
        batteryOptimizer.isEnabled = enabled
        
        if enabled {
            adjustSyncFrequencyForBattery()
            enableDataCompression()
        } else {
            restoreNormalSyncFrequency()
        }
    }
    
    private func adjustSyncFrequencyForBattery() {
        // Reduce sync frequency based on battery level
        guard let battery = batteryInfo else { return }
        
        if battery.level < 20 {
            // Extreme battery saving
            messageQueue.setMaxBatchSize(1)
            messageQueue.setBatchInterval(300) // 5 minutes
        } else if battery.level < 40 {
            // Moderate battery saving
            messageQueue.setMaxBatchSize(3)
            messageQueue.setBatchInterval(120) // 2 minutes
        } else {
            // Normal operation
            messageQueue.setMaxBatchSize(5)
            messageQueue.setBatchInterval(60) // 1 minute
        }
    }
    
    // MARK: - Health Data Integration
    
    func syncHealthMetrics(_ metrics: WatchHealthMetrics) {
        self.watchHealthMetrics = metrics
        
        // Process health data for golf insights
        processGolfHealthMetrics(metrics)
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.watchConnectivityManager(self, didReceiveHealthMetrics: metrics)
        }
    }
    
    private func processGolfHealthMetrics(_ metrics: WatchHealthMetrics) {
        // Calculate golf-specific insights
        if let round = activeRound {
            // Update round with health data
            round.averageHeartRate = metrics.averageHeartRate
            round.totalCalories = metrics.caloriesBurned
            round.totalSteps = metrics.stepCount
            round.totalDistance = metrics.distanceWalked
            
            // Check for fatigue indicators
            if metrics.currentHeartRate > metrics.averageHeartRate * 1.3 {
                // Suggest rest
                sendWatchNotification(
                    title: "Take a Break",
                    body: "Your heart rate is elevated. Consider taking a short rest.",
                    haptic: .notification
                )
            }
        }
    }
    
    // MARK: - Haptic Feedback Coordination
    
    func sendHapticFeedback(_ type: WatchHapticType, context: HapticContext? = nil) {
        guard isWatchReachable else { return }
        
        let hapticData: [String: Any] = [
            "type": type.rawValue,
            "intensity": context?.intensity ?? 1.0,
            "pattern": context?.pattern ?? "default"
        ]
        
        // Send immediately for haptic feedback
        session.sendMessage(
            ["haptic": hapticData],
            replyHandler: nil,
            errorHandler: { [weak self] error in
                self?.logger.error("Failed to send haptic: \(error)")
            }
        )
    }
    
    // MARK: - Gamification Integration
    
    /// Send real-time leaderboard position update to Apple Watch
    func sendLeaderboardUpdate(playerId: String, position: Int, totalPlayers: Int, positionChange: Int) async {
        let leaderboardData: [String: Any] = [
            "playerId": playerId,
            "position": position,
            "totalPlayers": totalPlayers,
            "positionChange": positionChange,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendHighPriorityMessage(
            type: .leaderboardUpdate,
            data: leaderboardData,
            requiresAck: false
        )
        
        // Send coordinated haptic feedback for significant position changes
        if abs(positionChange) >= 5 {
            let hapticType: WatchHapticType = positionChange > 0 ? .success : .warning
            sendHapticFeedback(hapticType, context: HapticContext(intensity: 0.8, pattern: "position_change"))
        }
    }
    
    /// Send live tournament standings update to Apple Watch
    func sendTournamentStandings(tournamentId: String, standings: [[String: Any]], playerPosition: Int) async {
        let tournamentData: [String: Any] = [
            "tournamentId": tournamentId,
            "standings": standings,
            "playerPosition": playerPosition,
            "lastUpdated": Date().timeIntervalSince1970
        ]
        
        await sendNormalPriorityMessage(
            type: .tournamentStandings,
            data: tournamentData
        )
    }
    
    /// Send challenge progress update to Apple Watch
    func sendChallengeProgress(challengeId: String, progress: [String: Any], status: String) async {
        let challengeData: [String: Any] = [
            "challengeId": challengeId,
            "progress": progress,
            "status": status,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendHighPriorityMessage(
            type: .challengeProgress,
            data: challengeData,
            requiresAck: false
        )
    }
    
    /// Send achievement unlock notification to Apple Watch with synchronized celebration
    func sendAchievementUnlock(achievementId: String, tier: String, title: String, description: String) async {
        let achievementData: [String: Any] = [
            "achievementId": achievementId,
            "tier": tier,
            "title": title,
            "description": description,
            "unlockedAt": Date().timeIntervalSince1970
        ]
        
        await sendHighPriorityMessage(
            type: .achievementUnlock,
            data: achievementData,
            requiresAck: true
        )
        
        // Send synchronized haptic celebration
        let hapticPattern = getAchievementHapticPattern(for: tier)
        sendHapticFeedback(.custom, context: HapticContext(pattern: hapticPattern))
    }
    
    /// Send live rating update to Apple Watch
    func sendRatingUpdate(playerId: String, currentRating: Double, ratingChange: Double, projectedRating: Double?) async {
        let ratingData: [String: Any] = [
            "playerId": playerId,
            "currentRating": currentRating,
            "ratingChange": ratingChange,
            "projectedRating": projectedRating ?? currentRating,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendNormalPriorityMessage(
            type: .ratingUpdate,
            data: ratingData
        )
    }
    
    /// Send handicap improvement notification to Apple Watch
    func sendHandicapUpdate(playerId: String, newHandicap: Double, improvement: Double, isSignificant: Bool) async {
        let handicapData: [String: Any] = [
            "playerId": playerId,
            "newHandicap": newHandicap,
            "improvement": improvement,
            "isSignificant": isSignificant,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendHighPriorityMessage(
            type: .handicapChange,
            data: handicapData,
            requiresAck: isSignificant
        )
        
        // Send haptic feedback for significant improvements
        if isSignificant {
            sendHapticFeedback(.success, context: HapticContext(intensity: 1.0, pattern: "handicap_improvement"))
        }
    }
    
    /// Send head-to-head challenge update to Apple Watch
    func sendHeadToHeadUpdate(challengeId: String, opponentId: String, playerScore: Int, opponentScore: Int, status: String) async {
        let headToHeadData: [String: Any] = [
            "challengeId": challengeId,
            "opponentId": opponentId,
            "playerScore": playerScore,
            "opponentScore": opponentScore,
            "status": status,
            "scoreDifference": playerScore - opponentScore,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendHighPriorityMessage(
            type: .headToHeadUpdate,
            data: headToHeadData,
            requiresAck: false
        )
    }
    
    /// Send tournament milestone notification to Apple Watch
    func sendTournamentMilestone(tournamentId: String, milestone: String, position: Int, prizeMoney: Double?) async {
        var milestoneData: [String: Any] = [
            "tournamentId": tournamentId,
            "milestone": milestone,
            "position": position,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let prize = prizeMoney {
            milestoneData["prizeMoney"] = prize
        }
        
        await sendHighPriorityMessage(
            type: .leaderboardMilestone,
            data: milestoneData,
            requiresAck: true
        )
        
        // Send milestone celebration haptic
        let hapticPattern = getTournamentMilestoneHapticPattern(for: milestone)
        sendHapticFeedback(.custom, context: HapticContext(pattern: hapticPattern))
    }
    
    func celebrateMilestone(_ milestone: GolfMilestone) {
        let hapticPattern = milestone.hapticPattern
        sendHapticFeedback(.custom, context: HapticContext(pattern: hapticPattern))
        
        // Also send visual notification
        sendWatchNotification(
            title: milestone.title,
            body: milestone.description,
            haptic: .success
        )
    }
    
    // MARK: - Background Processing
    
    private func setupBackgroundSync() {
        backgroundSyncTimer = Timer.scheduledTimer(
            withTimeInterval: 300, // 5 minutes
            repeats: true
        ) { [weak self] _ in
            Task {
                await self?.performBackgroundSync()
            }
        }
    }
    
    private func performBackgroundSync() async {
        guard isWatchAppInstalled else { return }
        
        beginBackgroundTask()
        
        defer {
            endBackgroundTask()
        }
        
        // Sync only essential data in background
        if let round = activeRound {
            let essentialData = extractEssentialRoundData(round)
            
            // Use application context for background sync
            updateApplicationContext(essentialData)
        }
    }
    
    private func beginBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    // MARK: - Data Compression
    
    private func compressDataForTransfer(_ data: [String: Any]) -> Data? {
        return dataCompressionEngine.compress(data)
    }
    
    private func decompressDataFromWatch(_ data: Data) -> [String: Any]? {
        return dataCompressionEngine.decompress(data)
    }
    
    // MARK: - Conflict Resolution
    
    private func resolveDataConflict(_ local: Any, remote: Any, type: ConflictType) -> Any {
        return conflictResolver.resolve(local: local, remote: remote, type: type)
    }
    
    // MARK: - Helper Methods
    
    private func updateConnectionState() {
        isWatchPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isWatchReachable = session.isReachable
        
        if isWatchReachable {
            connectionState = .connected
        } else if isWatchPaired {
            connectionState = .paired
        } else {
            connectionState = .disconnected
        }
    }
    
    private func startConnectionMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateConnectionState()
        }
    }
    
    private func stopConnectionMonitoring() {
        messageRetryTimer?.invalidate()
        messageRetryTimer = nil
    }
    
    private func notifyDelegates(block: (WatchConnectivityDelegate) -> Void) {
        delegates.allObjects.compactMap { $0 as? WatchConnectivityDelegate }.forEach(block)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("Session activation failed: \(error)")
            connectionState = .error(error)
        } else {
            logger.info("Session activated with state: \(activationState.rawValue)")
            updateConnectionState()
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        logger.info("Session became inactive")
        connectionState = .inactive
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        logger.info("Session deactivated")
        session.activate()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        updateConnectionState()
        
        if session.isReachable {
            // Process any pending messages
            Task {
                await processPendingMessages()
            }
        }
    }
    
    // MARK: - Message Handling
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleReceivedMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        let response = handleReceivedMessageWithReply(message)
        replyHandler(response)
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleApplicationContext(applicationContext)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleUserInfo(userInfo)
    }
    
    // MARK: - File Transfer
    
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        handleFileTransfer(file)
    }
    
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error {
            logger.error("File transfer failed: \(error)")
        } else {
            logger.info("File transfer completed successfully")
        }
    }
}

// MARK: - Message Processing

private extension WatchConnectivityManager {
    
    func handleReceivedMessage(_ message: [String: Any]) {
        guard let typeRaw = message["type"] as? String,
              let type = MessageType(rawValue: typeRaw) else { return }
        
        switch type {
        case .healthUpdate:
            if let metricsData = message["metrics"] as? [String: Any] {
                let metrics = WatchHealthMetrics(from: metricsData)
                syncHealthMetrics(metrics)
            }
            
        case .scorecardUpdate:
            if let scorecardData = message["scorecard"] as? [String: Any] {
                handleScorecardUpdate(scorecardData)
            }
            
        case .locationUpdate:
            if let locationData = message["location"] as? [String: Any] {
                handleLocationUpdate(locationData)
            }
            
        case .batteryInfo:
            if let batteryData = message["battery"] as? [String: Any] {
                handleBatteryUpdate(batteryData)
            }
            
        case .syncRequest:
            Task {
                await handleSyncRequest(message["data"] as? [String: Any])
            }
            
        // MARK: - Gamification Message Handling
        
        case .leaderboardUpdate:
            if let leaderboardData = message["leaderboard"] as? [String: Any] {
                handleLeaderboardUpdate(leaderboardData)
            }
            
        case .challengeProgress:
            if let challengeData = message["challenge"] as? [String: Any] {
                handleChallengeUpdate(challengeData)
            }
            
        case .achievementUnlock:
            if let achievementData = message["achievement"] as? [String: Any] {
                handleAchievementUpdate(achievementData)
            }
            
        case .ratingUpdate:
            if let ratingData = message["rating"] as? [String: Any] {
                handleRatingUpdate(ratingData)
            }
            
        case .tournamentStandings:
            if let tournamentData = message["tournament"] as? [String: Any] {
                handleTournamentUpdate(tournamentData)
            }
            
        default:
            logger.debug("Received message of type: \(type)")
        }
    }
    
    func handleReceivedMessageWithReply(_ message: [String: Any]) -> [String: Any] {
        guard let typeRaw = message["type"] as? String,
              let type = MessageType(rawValue: typeRaw) else {
            return ["success": false, "error": "Invalid message type"]
        }
        
        switch type {
        case .ping:
            return ["type": "pong", "timestamp": Date().timeIntervalSince1970]
            
        case .dataRequest:
            if let requestType = message["requestType"] as? String {
                return handleDataRequest(requestType)
            }
            
        case .syncStatus:
            return ["syncState": syncState.rawValue, "lastSync": lastSyncTime?.timeIntervalSince1970 ?? 0]
            
        default:
            return ["success": true]
        }
        
        return ["success": false]
    }
    
    func handleDataRequest(_ requestType: String) -> [String: Any] {
        switch requestType {
        case "activeRound":
            if let round = activeRound {
                return ["success": true, "data": round.toDictionary()]
            }
            
        case "scorecard":
            if let scorecard = currentScorecard {
                return ["success": true, "data": scorecard.toDictionary()]
            }
            
        case "courses":
            // Return cached courses
            return ["success": true, "data": getCachedCourses()]
            
        default:
            return ["success": false, "error": "Unknown request type"]
        }
        
        return ["success": false]
    }
}

// MARK: - Supporting Types

enum WatchConnectionState: String {
    case disconnected
    case paired
    case inactive
    case connected
    case error(Error)
    
    var description: String {
        switch self {
        case .disconnected: return "Not Paired"
        case .paired: return "Paired"
        case .inactive: return "Inactive"
        case .connected: return "Connected"
        case .error(let error): return "Error: \(error.localizedDescription)"
        }
    }
}

enum WatchSyncState: String {
    case idle
    case syncing
    case completed
    case failed(Error)
    
    var rawValue: String {
        switch self {
        case .idle: return "idle"
        case .syncing: return "syncing"
        case .completed: return "completed"
        case .failed: return "failed"
        }
    }
}

enum MessageType: String {
    case startRound
    case endRound
    case scorecardUpdate
    case healthUpdate
    case locationUpdate
    case batteryInfo
    case syncRequest
    case syncStatus
    case ping
    case pong
    case dataRequest
    case hapticFeedback
    case notification
    
    // MARK: - Gamification Message Types
    
    // Leaderboard Updates
    case leaderboardUpdate
    case livePositionChange
    case tournamentStandings
    case leaderboardMilestone
    
    // Challenge Updates
    case challengeInvitation
    case challengeProgress
    case challengeComplete
    case headToHeadUpdate
    case tournamentBracketUpdate
    
    // Achievement Updates
    case achievementUnlock
    case badgeAcquired
    case milestoneReached
    case streakUpdate
    
    // Rating Updates
    case ratingUpdate
    case handicapChange
    case strokesGainedUpdate
    case performanceFeedback
    
    // Social Updates
    case friendChallengeUpdate
    case tournamentRegistration
    case socialNotification
    
    // Live Tournament Monitoring
    case liveTournamentStandings
    case tournamentBracketUpdate
    case tournamentMilestone
    case tournamentPrizeUpdate
    case nextOpponentNotification
    
    // Live Challenge Monitoring
    case liveHeadToHeadUpdate
    case challengeMilestoneProgress
    case challengeCompletionAlert
    case friendChallengeStanding
    
    // Enhanced Achievement System
    case badgeProgressUpdate
    case achievementChainProgress
    case socialAchievementUnlock
    case achievementLeaderboardUpdate
    
    // Real-time Rating System
    case liveRatingProjection
    case ratingMilestoneReached
    case handicapProjection
    case strokesGainedLive
}

enum MessagePriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

struct PriorityMessage {
    let id: String
    let type: MessageType
    let priority: MessagePriority
    let data: [String: Any]
    let requiresAck: Bool
    let timestamp: Date
    var retryCount: Int = 0
}

struct PendingMessage {
    let message: PriorityMessage
    let completion: ((Bool) -> Void)?
    let timeout: TimeInterval
}

struct WatchBatteryInfo {
    let level: Float // 0-100
    let state: BatteryState
    let isLowPowerMode: Bool
    let estimatedTimeRemaining: TimeInterval?
}

enum BatteryState: String {
    case unknown
    case unplugged
    case charging
    case full
}

struct WatchHealthMetrics {
    let heartRate: Double
    let averageHeartRate: Double
    let caloriesBurned: Double
    let stepCount: Int
    let distanceWalked: Double
    let currentHeartRate: Double
    let heartRateZone: HeartRateZone
    
    init(from dictionary: [String: Any]) {
        self.heartRate = dictionary["heartRate"] as? Double ?? 0
        self.averageHeartRate = dictionary["averageHeartRate"] as? Double ?? 0
        self.caloriesBurned = dictionary["caloriesBurned"] as? Double ?? 0
        self.stepCount = dictionary["stepCount"] as? Int ?? 0
        self.distanceWalked = dictionary["distanceWalked"] as? Double ?? 0
        self.currentHeartRate = dictionary["currentHeartRate"] as? Double ?? 0
        
        if let zoneRaw = dictionary["heartRateZone"] as? String {
            self.heartRateZone = HeartRateZone(rawValue: zoneRaw) ?? .moderate
        } else {
            self.heartRateZone = .moderate
        }
    }
}

enum HeartRateZone: String {
    case resting
    case light
    case moderate
    case hard
    case maximum
}

struct HapticContext {
    let intensity: Double
    let pattern: String
    
    init(intensity: Double = 1.0, pattern: String = "default") {
        self.intensity = intensity
        self.pattern = pattern
    }
}

enum WatchHapticType: String {
    case light
    case medium
    case heavy
    case success
    case warning
    case error
    case notification
    case custom
}

struct GolfMilestone {
    let title: String
    let description: String
    let hapticPattern: String
    
    static let birdie = GolfMilestone(
        title: "Birdie!",
        description: "Great shot! One under par",
        hapticPattern: "celebration"
    )
    
    static let eagle = GolfMilestone(
        title: "Eagle!",
        description: "Amazing! Two under par",
        hapticPattern: "major_celebration"
    )
    
    static let personalBest = GolfMilestone(
        title: "Personal Best!",
        description: "New record score",
        hapticPattern: "achievement"
    )
}

// MARK: - Delegate Protocol

protocol WatchConnectivityDelegate: AnyObject {
    func watchConnectivityManager(_ manager: WatchConnectivityManager, didChangeConnectionState state: WatchConnectionState)
    func watchConnectivityManager(_ manager: WatchConnectivityManager, didReceiveHealthMetrics metrics: WatchHealthMetrics)
    func watchConnectivityManager(_ manager: WatchConnectivityManager, didUpdateScorecard scorecard: SharedScorecard)
    func watchConnectivityManager(_ manager: WatchConnectivityManager, didReceiveBatteryInfo info: WatchBatteryInfo)
}

// MARK: - Helper Classes

class PriorityMessageQueue {
    private var queue = [PriorityMessage]()
    private let lock = NSLock()
    private var maxBatchSize = 5
    private var batchInterval: TimeInterval = 60
    
    func enqueue(_ message: PriorityMessage) {
        lock.lock()
        defer { lock.unlock() }
        
        queue.append(message)
        queue.sort { $0.priority > $1.priority }
    }
    
    func dequeue() -> PriorityMessage? {
        lock.lock()
        defer { lock.unlock() }
        
        return queue.isEmpty ? nil : queue.removeFirst()
    }
    
    func dequeueBatch(maxCount: Int) -> [PriorityMessage] {
        lock.lock()
        defer { lock.unlock() }
        
        let count = min(maxCount, queue.count)
        guard count > 0 else { return [] }
        
        let batch = Array(queue.prefix(count))
        queue.removeFirst(count)
        return batch
    }
    
    func setMaxBatchSize(_ size: Int) {
        maxBatchSize = size
    }
    
    func setBatchInterval(_ interval: TimeInterval) {
        batchInterval = interval
    }
}

class DataCompressionEngine {
    func compress(_ data: [String: Any]) -> Data? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return nil }
        return jsonData.compressed(using: .zlib)
    }
    
    func decompress(_ data: Data) -> [String: Any]? {
        guard let decompressed = try? data.decompressed(using: .zlib),
              let json = try? JSONSerialization.jsonObject(with: decompressed) as? [String: Any] else {
            return nil
        }
        return json
    }
}

class ConflictResolver {
    enum ConflictType {
        case scorecard
        case location
        case settings
    }
    
    func resolve(local: Any, remote: Any, type: ConflictType) -> Any {
        switch type {
        case .scorecard:
            // Use most recent scorecard
            if let localScore = local as? SharedScorecard,
               let remoteScore = remote as? SharedScorecard {
                return localScore.lastUpdated > remoteScore.lastUpdated ? localScore : remoteScore
            }
            
        case .location:
            // Use most accurate location
            if let localLoc = local as? CLLocation,
               let remoteLoc = remote as? CLLocation {
                return localLoc.horizontalAccuracy < remoteLoc.horizontalAccuracy ? localLoc : remoteLoc
            }
            
        case .settings:
            // Prefer local settings
            return local
        }
        
        return local
    }
}

class WatchPerformanceMonitor {
    private var metrics = [String: Double]()
    
    func recordMetric(_ name: String, value: Double) {
        metrics[name] = value
    }
    
    func getAverageLatency() -> Double {
        return metrics["latency"] ?? 0
    }
}

class WatchBatteryOptimizer {
    var isEnabled = false
    
    func optimizeForBatteryLife() {
        // Implement battery optimization strategies
    }
}

// MARK: - Extensions

extension Data {
    func compressed(using algorithm: NSData.CompressionAlgorithm) -> Data? {
        return (self as NSData).compressed(using: algorithm) as Data?
    }
    
    func decompressed(using algorithm: NSData.CompressionAlgorithm) -> Data? {
        return (self as NSData).decompressed(using: algorithm) as Data?
    }
}

extension WatchConnectivityManager {
    
    // Helper methods for data preparation
    
    private func prepareRoundDataForWatch(_ round: ActiveGolfRound) -> [String: Any] {
        return [
            "id": round.id,
            "courseId": round.courseId,
            "courseName": round.courseName,
            "startTime": round.startTime.timeIntervalSince1970,
            "currentHole": round.currentHole,
            "totalHoles": round.totalHoles
        ]
    }
    
    private func extractEssentialRoundData(_ round: ActiveGolfRound) -> [String: Any] {
        return [
            "roundId": round.id,
            "currentHole": round.currentHole,
            "score": round.currentScore,
            "lastUpdate": Date().timeIntervalSince1970
        ]
    }
    
    private func calculateScorecardDelta(_ scorecard: SharedScorecard) -> [String: Any] {
        // Calculate only changed fields
        var delta: [String: Any] = ["id": scorecard.id]
        
        // Add only modified holes
        if let modifiedHoles = scorecard.modifiedHoles {
            delta["modifiedHoles"] = modifiedHoles
        }
        
        delta["totalScore"] = scorecard.totalScore
        delta["lastUpdated"] = scorecard.lastUpdated.timeIntervalSince1970
        
        return delta
    }
    
    private func storePendingMessage(_ message: PriorityMessage) {
        pendingMessages[message.id] = PendingMessage(
            message: message,
            completion: nil,
            timeout: 300 // 5 minutes
        )
    }
    
    private func processPendingMessages() async {
        for (id, pending) in pendingMessages {
            _ = await sendPriorityMessage(pending.message)
            pendingMessages.removeValue(forKey: id)
        }
    }
    
    private func processMessageQueue() async -> Bool {
        guard let message = messageQueue.dequeue() else { return false }
        
        do {
            if let compressed = compressDataForTransfer(message.data) {
                // Send compressed data
                try await sendCompressedMessage(message, data: compressed)
                return true
            } else {
                // Send uncompressed
                try await sendRawMessage(message)
                return true
            }
        } catch {
            logger.error("Failed to send message: \(error)")
            
            // Retry logic
            if message.retryCount < 3 {
                var retryMessage = message
                retryMessage.retryCount += 1
                messageQueue.enqueue(retryMessage)
            }
            
            return false
        }
    }
    
    private func sendCompressedMessage(_ message: PriorityMessage, data: Data) async throws {
        let wrapper: [String: Any] = [
            "compressed": true,
            "type": message.type.rawValue,
            "data": data,
            "id": message.id
        ]
        
        if message.requiresAck {
            try await withCheckedThrowingContinuation { continuation in
                session.sendMessage(wrapper, replyHandler: { reply in
                    continuation.resume()
                }, errorHandler: { error in
                    continuation.resume(throwing: error)
                })
            }
        } else {
            session.sendMessage(wrapper)
        }
    }
    
    private func sendRawMessage(_ message: PriorityMessage) async throws {
        let wrapper: [String: Any] = [
            "compressed": false,
            "type": message.type.rawValue,
            "data": message.data,
            "id": message.id
        ]
        
        if message.requiresAck {
            try await withCheckedThrowingContinuation { continuation in
                session.sendMessage(wrapper, replyHandler: { reply in
                    continuation.resume()
                }, errorHandler: { error in
                    continuation.resume(throwing: error)
                })
            }
        } else {
            session.sendMessage(wrapper)
        }
    }
    
    private func handleScorecardUpdate(_ data: [String: Any]) {
        // Process scorecard update from watch
        if let scorecard = SharedScorecard(from: data) {
            self.currentScorecard = scorecard
            notifyDelegates { delegate in
                delegate.watchConnectivityManager(self, didUpdateScorecard: scorecard)
            }
        }
    }
    
    private func handleLocationUpdate(_ data: [String: Any]) {
        // Process location update from watch
        if let lat = data["latitude"] as? Double,
           let lon = data["longitude"] as? Double {
            let location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            // Update location in appropriate service
        }
    }
    
    private func handleBatteryUpdate(_ data: [String: Any]) {
        if let level = data["level"] as? Float,
           let stateRaw = data["state"] as? String,
           let state = BatteryState(rawValue: stateRaw) {
            
            let info = WatchBatteryInfo(
                level: level,
                state: state,
                isLowPowerMode: data["lowPowerMode"] as? Bool ?? false,
                estimatedTimeRemaining: data["timeRemaining"] as? TimeInterval
            )
            
            self.batteryInfo = info
            adjustSyncFrequencyForBattery()
            
            notifyDelegates { delegate in
                delegate.watchConnectivityManager(self, didReceiveBatteryInfo: info)
            }
        }
    }
    
    private func handleApplicationContext(_ context: [String: Any]) {
        // Handle background updates via application context
        logger.debug("Received application context update")
    }
    
    private func handleUserInfo(_ userInfo: [String: Any]) {
        // Handle guaranteed delivery messages
        logger.debug("Received user info")
    }
    
    private func handleFileTransfer(_ file: WCSessionFile) {
        // Handle file transfers (e.g., course maps, images)
        logger.debug("Received file: \(file.fileURL)")
    }
    
    private func handleSyncRequest(_ data: [String: Any]?) async {
        guard let data = data,
              let syncType = data["syncType"] as? String else { return }
        
        switch syncType {
        case "full":
            await performInitialSync()
        case "scorecard":
            if let scorecard = currentScorecard {
                await updateScorecard(scorecard)
            }
        case "courses":
            await syncCachedCourseData()
        default:
            break
        }
    }
    
    private func syncEssentialData() async {
        // Sync only the most important data first
        if let round = activeRound {
            _ = await sendHighPriorityMessage(
                type: .syncRequest,
                data: ["syncType": "activeRound", "data": prepareRoundDataForWatch(round)],
                requiresAck: true
            )
        }
    }
    
    private func syncCachedCourseData() async {
        // Sync cached course data
        let courses = getCachedCourses()
        if !courses.isEmpty {
            await sendNormalPriorityMessage(
                type: .syncRequest,
                data: ["syncType": "courses", "data": courses]
            )
        }
    }
    
    private func syncUserPreferences() async {
        // Sync user preferences and settings
        let preferences = getUserPreferences()
        await sendNormalPriorityMessage(
            type: .syncRequest,
            data: ["syncType": "preferences", "data": preferences]
        )
    }
    
    private func getCachedCourses() -> [[String: Any]] {
        // Return cached courses from local storage
        return []
    }
    
    private func getUserPreferences() -> [String: Any] {
        // Return user preferences
        return [:]
    }
    
    private func restoreNormalSyncFrequency() {
        messageQueue.setMaxBatchSize(5)
        messageQueue.setBatchInterval(60)
    }
    
    private func enableDataCompression() {
        // Enable compression for all messages
    }
    
    private func cancelAllPendingMessages() {
        pendingMessages.removeAll()
    }
    
    private func sendWatchNotification(title: String, body: String, haptic: WatchHapticType) {
        let notification: [String: Any] = [
            "title": title,
            "body": body,
            "haptic": haptic.rawValue
        ]
        
        session.sendMessage(
            ["notification": notification],
            replyHandler: nil,
            errorHandler: nil
        )
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidEnterBackground() {
        Task {
            await performBackgroundSync()
        }
    }
    
    @objc private func handleAppWillEnterForeground() {
        updateConnectionState()
        
        if isWatchReachable {
            Task {
                await processPendingMessages()
            }
        }
    }
    
    // MARK: - Gamification Message Handlers
    
    private func handleLeaderboardUpdate(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let position = data["position"] as? Int,
              let totalPlayers = data["totalPlayers"] as? Int else { return }
        
        let positionChange = data["positionChange"] as? Int ?? 0
        
        logger.info("Leaderboard update: Player \(playerId) at position \(position)/\(totalPlayers), change: \(positionChange)")
        
        // Notify delegates about leaderboard changes
        notifyDelegates { delegate in
            if let gamificationDelegate = delegate as? WatchGamificationDelegate {
                gamificationDelegate.watchConnectivityManager(self, didReceiveLeaderboardUpdate: LeaderboardUpdate(
                    playerId: playerId,
                    position: position,
                    totalPlayers: totalPlayers,
                    positionChange: positionChange
                ))
            }
        }
    }
    
    private func handleChallengeUpdate(_ data: [String: Any]) {
        guard let challengeId = data["challengeId"] as? String,
              let status = data["status"] as? String else { return }
        
        logger.info("Challenge update: \(challengeId) status: \(status)")
        
        notifyDelegates { delegate in
            if let gamificationDelegate = delegate as? WatchGamificationDelegate {
                gamificationDelegate.watchConnectivityManager(self, didReceiveChallengeUpdate: ChallengeUpdate(
                    challengeId: challengeId,
                    updateType: .challengeCompleted, // Map from status string
                    playerId: "",
                    data: data,
                    timestamp: Date()
                ))
            }
        }
    }
    
    private func handleAchievementUpdate(_ data: [String: Any]) {
        guard let achievementId = data["achievementId"] as? String,
              let tier = data["tier"] as? String,
              let title = data["title"] as? String else { return }
        
        logger.info("Achievement unlocked: \(title) (\(tier))")
        
        notifyDelegates { delegate in
            if let gamificationDelegate = delegate as? WatchGamificationDelegate {
                gamificationDelegate.watchConnectivityManager(self, didReceiveAchievementUnlock: AchievementUnlock(
                    achievementId: achievementId,
                    tier: tier,
                    title: title,
                    description: data["description"] as? String ?? ""
                ))
            }
        }
    }
    
    private func handleRatingUpdate(_ data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let currentRating = data["currentRating"] as? Double,
              let ratingChange = data["ratingChange"] as? Double else { return }
        
        logger.info("Rating update: Player \(playerId) rating: \(currentRating) (change: \(ratingChange))")
        
        notifyDelegates { delegate in
            if let gamificationDelegate = delegate as? WatchGamificationDelegate {
                gamificationDelegate.watchConnectivityManager(self, didReceiveRatingUpdate: RatingUpdate(
                    playerId: playerId,
                    currentRating: currentRating,
                    ratingChange: ratingChange,
                    projectedRating: data["projectedRating"] as? Double
                ))
            }
        }
    }
    
    private func handleTournamentUpdate(_ data: [String: Any]) {
        guard let tournamentId = data["tournamentId"] as? String,
              let playerPosition = data["playerPosition"] as? Int else { return }
        
        logger.info("Tournament update: \(tournamentId) player position: \(playerPosition)")
        
        notifyDelegates { delegate in
            if let gamificationDelegate = delegate as? WatchGamificationDelegate {
                gamificationDelegate.watchConnectivityManager(self, didReceiveTournamentUpdate: TournamentUpdate(
                    tournamentId: tournamentId,
                    playerPosition: playerPosition,
                    standings: data["standings"] as? [[String: Any]] ?? []
                ))
            }
        }
    }
    
    // MARK: - Haptic Pattern Helpers
    
    private func getAchievementHapticPattern(for tier: String) -> String {
        switch tier.lowercased() {
        case "bronze":
            return "achievement_bronze"
        case "silver":
            return "achievement_silver"
        case "gold":
            return "achievement_gold"
        case "platinum":
            return "achievement_platinum"
        case "diamond":
            return "achievement_diamond"
        default:
            return "achievement_default"
        }
    }
    
    private func getTournamentMilestoneHapticPattern(for milestone: String) -> String {
        switch milestone.lowercased() {
        case "qualifying":
            return "tournament_qualifying"
        case "advancing":
            return "tournament_advancing"
        case "top_ten":
            return "tournament_top_ten"
        case "top_three":
            return "tournament_top_three"
        case "winner":
            return "tournament_winner"
        default:
            return "tournament_milestone"
        }
    }
    
    // MARK: - Enhanced Live Tournament Monitoring
    
    /// Send live tournament standings with detailed position tracking
    func sendLiveTournamentStandings(
        tournamentId: String,
        playerPosition: Int,
        positionChange: Int,
        standings: [[String: Any]],
        leaderboard: [String: Any],
        nextUpdate: TimeInterval
    ) async {
        let tournamentData: [String: Any] = [
            "tournamentId": tournamentId,
            "playerPosition": playerPosition,
            "positionChange": positionChange,
            "standings": standings,
            "leaderboard": leaderboard,
            "nextUpdateIn": nextUpdate,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendHighPriorityMessage(
            type: .liveTournamentStandings,
            data: tournamentData,
            requiresAck: false
        )
        
        // Trigger haptic for significant position changes
        if abs(positionChange) >= 3 {
            let hapticType: WatchHapticType = positionChange > 0 ? .success : .warning
            sendHapticFeedback(hapticType, context: HapticContext(intensity: 0.9, pattern: "live_position_change"))
        }
    }
    
    /// Send tournament bracket progression updates
    func sendTournamentBracketUpdate(
        tournamentId: String,
        bracketPosition: [String: Any],
        nextOpponent: [String: Any]?,
        roundInfo: [String: Any]
    ) async {
        let bracketData: [String: Any] = [
            "tournamentId": tournamentId,
            "bracketPosition": bracketPosition,
            "nextOpponent": nextOpponent as Any,
            "roundInfo": roundInfo,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendNormalPriorityMessage(
            type: .tournamentBracketUpdate,
            data: bracketData
        )
    }
    
    /// Send next opponent notification for tournament play
    func sendNextOpponentNotification(
        tournamentId: String,
        opponentInfo: [String: Any],
        matchTime: Date,
        roundDetails: [String: Any]
    ) async {
        let opponentData: [String: Any] = [
            "tournamentId": tournamentId,
            "opponentInfo": opponentInfo,
            "matchTime": matchTime.timeIntervalSince1970,
            "roundDetails": roundDetails,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendHighPriorityMessage(
            type: .nextOpponentNotification,
            data: opponentData,
            requiresAck: true
        )
        
        // Send notification haptic
        sendHapticFeedback(.notification, context: HapticContext(intensity: 0.7, pattern: "opponent_notification"))
    }
    
    /// Send tournament prize pool and payout updates
    func sendTournamentPrizeUpdate(
        tournamentId: String,
        currentPrizePool: Double,
        projectedPayout: Double?,
        position: Int
    ) async {
        let prizeData: [String: Any] = [
            "tournamentId": tournamentId,
            "currentPrizePool": currentPrizePool,
            "projectedPayout": projectedPayout as Any,
            "position": position,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendNormalPriorityMessage(
            type: .tournamentPrizeUpdate,
            data: prizeData
        )
    }
    
    // MARK: - Enhanced Live Challenge Monitoring
    
    /// Send live head-to-head challenge updates with real-time scoring
    func sendLiveHeadToHeadUpdate(
        challengeId: String,
        playerScore: Int,
        opponentScore: Int,
        holeByHole: [[String: Any]],
        matchStatus: String,
        holesRemaining: Int
    ) async {
        let headToHeadData: [String: Any] = [
            "challengeId": challengeId,
            "playerScore": playerScore,
            "opponentScore": opponentScore,
            "holeByHole": holeByHole,
            "matchStatus": matchStatus,
            "holesRemaining": holesRemaining,
            "scoreDifference": playerScore - opponentScore,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendHighPriorityMessage(
            type: .liveHeadToHeadUpdate,
            data: headToHeadData,
            requiresAck: false
        )
        
        // Trigger haptic for match status changes
        if matchStatus.contains("up") || matchStatus.contains("down") {
            let hapticType: WatchHapticType = playerScore < opponentScore ? .success : .warning
            sendHapticFeedback(hapticType, context: HapticContext(intensity: 0.6, pattern: "match_status"))
        }
    }
    
    /// Send challenge milestone progress notifications
    func sendChallengeMilestoneProgress(
        challengeId: String,
        milestoneType: String,
        progress: Double,
        target: Double,
        isCompleted: Bool
    ) async {
        let milestoneData: [String: Any] = [
            "challengeId": challengeId,
            "milestoneType": milestoneType,
            "progress": progress,
            "target": target,
            "percentComplete": (progress / target) * 100,
            "isCompleted": isCompleted,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        let messageType: MessageType = isCompleted ? .challengeCompletionAlert : .challengeMilestoneProgress
        
        await sendHighPriorityMessage(
            type: messageType,
            data: milestoneData,
            requiresAck: isCompleted
        )
        
        // Celebration haptic for completed milestones
        if isCompleted {
            sendHapticFeedback(.success, context: HapticContext(intensity: 1.0, pattern: "milestone_celebration"))
        }
    }
    
    /// Send friend challenge standings update
    func sendFriendChallengeStanding(
        challengeId: String,
        standings: [[String: Any]],
        playerPosition: Int,
        friendsParticipating: [String]
    ) async {
        let standingData: [String: Any] = [
            "challengeId": challengeId,
            "standings": standings,
            "playerPosition": playerPosition,
            "friendsParticipating": friendsParticipating,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendNormalPriorityMessage(
            type: .friendChallengeStanding,
            data: standingData
        )
    }
    
    // MARK: - Enhanced Achievement System
    
    /// Send badge progress update with visual indicators
    func sendBadgeProgressUpdate(
        badgeId: String,
        badgeName: String,
        currentProgress: Int,
        targetProgress: Int,
        tier: String
    ) async {
        let badgeData: [String: Any] = [
            "badgeId": badgeId,
            "badgeName": badgeName,
            "currentProgress": currentProgress,
            "targetProgress": targetProgress,
            "tier": tier,
            "percentComplete": Double(currentProgress) / Double(targetProgress) * 100,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendNormalPriorityMessage(
            type: .badgeProgressUpdate,
            data: badgeData
        )
    }
    
    /// Send achievement chain progress for linked achievements
    func sendAchievementChainProgress(
        chainId: String,
        chainName: String,
        completedAchievements: [String],
        totalAchievements: Int,
        nextAchievement: [String: Any]?
    ) async {
        let chainData: [String: Any] = [
            "chainId": chainId,
            "chainName": chainName,
            "completedCount": completedAchievements.count,
            "totalCount": totalAchievements,
            "completedAchievements": completedAchievements,
            "nextAchievement": nextAchievement as Any,
            "percentComplete": Double(completedAchievements.count) / Double(totalAchievements) * 100,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendNormalPriorityMessage(
            type: .achievementChainProgress,
            data: chainData
        )
    }
    
    /// Send social achievement unlock with friend notifications
    func sendSocialAchievementUnlock(
        achievementId: String,
        title: String,
        description: String,
        tier: String,
        friendsToNotify: [String]
    ) async {
        let socialAchievementData: [String: Any] = [
            "achievementId": achievementId,
            "title": title,
            "description": description,
            "tier": tier,
            "friendsToNotify": friendsToNotify,
            "unlockedAt": Date().timeIntervalSince1970
        ]
        
        await sendHighPriorityMessage(
            type: .socialAchievementUnlock,
            data: socialAchievementData,
            requiresAck: true
        )
        
        // Enhanced celebration haptic for social achievements
        let hapticPattern = getSocialAchievementHapticPattern(for: tier)
        sendHapticFeedback(.custom, context: HapticContext(pattern: hapticPattern))
    }
    
    // MARK: - Real-time Rating System
    
    /// Send live rating projection during active rounds
    func sendLiveRatingProjection(
        playerId: String,
        currentRating: Double,
        projectedRating: Double,
        confidenceInterval: (lower: Double, upper: Double),
        holesRemaining: Int
    ) async {
        let ratingData: [String: Any] = [
            "playerId": playerId,
            "currentRating": currentRating,
            "projectedRating": projectedRating,
            "confidenceInterval": [
                "lower": confidenceInterval.lower,
                "upper": confidenceInterval.upper
            ],
            "holesRemaining": holesRemaining,
            "ratingChange": projectedRating - currentRating,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendNormalPriorityMessage(
            type: .liveRatingProjection,
            data: ratingData
        )
    }
    
    /// Send rating milestone reached notification
    func sendRatingMilestoneReached(
        playerId: String,
        milestoneType: String,
        newRating: Double,
        previousMilestone: Double?,
        nextMilestone: Double?
    ) async {
        let milestoneData: [String: Any] = [
            "playerId": playerId,
            "milestoneType": milestoneType,
            "newRating": newRating,
            "previousMilestone": previousMilestone as Any,
            "nextMilestone": nextMilestone as Any,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendHighPriorityMessage(
            type: .ratingMilestoneReached,
            data: milestoneData,
            requiresAck: true
        )
        
        // Milestone celebration haptic
        sendHapticFeedback(.success, context: HapticContext(intensity: 0.9, pattern: "rating_milestone"))
    }
    
    /// Send live strokes gained feedback
    func sendStrokesGainedLive(
        playerId: String,
        strokesGained: [String: Double],
        roundTotal: Double,
        categoryLeaders: [String: String]
    ) async {
        let strokesData: [String: Any] = [
            "playerId": playerId,
            "strokesGained": strokesGained,
            "roundTotal": roundTotal,
            "categoryLeaders": categoryLeaders,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendNormalPriorityMessage(
            type: .strokesGainedLive,
            data: strokesData
        )
    }
    
    // MARK: - Power-Efficient Tournament Monitoring
    
    /// Enable tournament monitoring mode with battery optimization
    func enableTournamentMonitoringMode(tournamentId: String, expectedDuration: TimeInterval) async {
        let monitoringData: [String: Any] = [
            "tournamentId": tournamentId,
            "expectedDuration": expectedDuration,
            "batteryOptimization": true,
            "updateFrequency": "adaptive",
            "priority": "tournament"
        ]
        
        await sendHighPriorityMessage(
            type: .syncRequest,
            data: ["syncType": "tournament_monitoring", "data": monitoringData],
            requiresAck: true
        )
        
        // Enable battery optimization for long tournaments
        if expectedDuration > 14400 { // 4+ hours
            enableBatteryOptimization(true)
        }
        
        logger.info("Tournament monitoring mode enabled for \(tournamentId)")
    }
    
    /// Disable tournament monitoring mode and restore normal operation
    func disableTournamentMonitoringMode() async {
        await sendNormalPriorityMessage(
            type: .syncRequest,
            data: ["syncType": "tournament_monitoring_stop"]
        )
        
        // Restore normal battery settings
        enableBatteryOptimization(false)
        
        logger.info("Tournament monitoring mode disabled")
    }
    
    // MARK: - Enhanced Haptic Pattern Helpers
    
    private func getSocialAchievementHapticPattern(for tier: String) -> String {
        switch tier.lowercased() {
        case "bronze":
            return "social_achievement_bronze"
        case "silver":
            return "social_achievement_silver"
        case "gold":
            return "social_achievement_gold"
        case "platinum":
            return "social_achievement_platinum"
        case "diamond":
            return "social_achievement_diamond"
        default:
            return "social_achievement_default"
        }
    }
}

// MARK: - Placeholder Types (to be defined in separate files)

struct ActiveGolfRound {
    let id: String
    let courseId: String
    let courseName: String
    let startTime: Date
    var currentHole: Int
    let totalHoles: Int
    var currentScore: Int
    var averageHeartRate: Double?
    var totalCalories: Double?
    var totalSteps: Int?
    var totalDistance: Double?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "courseId": courseId,
            "courseName": courseName,
            "startTime": startTime.timeIntervalSince1970,
            "currentHole": currentHole,
            "totalHoles": totalHoles,
            "currentScore": currentScore
        ]
        
        if let heartRate = averageHeartRate {
            dict["averageHeartRate"] = heartRate
        }
        if let calories = totalCalories {
            dict["totalCalories"] = calories
        }
        if let steps = totalSteps {
            dict["totalSteps"] = steps
        }
        if let distance = totalDistance {
            dict["totalDistance"] = distance
        }
        
        return dict
    }
}

struct SharedScorecard {
    let id: String
    let roundId: String
    var holes: [HoleScore]
    var totalScore: Int
    var lastUpdated: Date
    var modifiedHoles: [Int]?
    
    init?(from dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let roundId = dictionary["roundId"] as? String else { return nil }
        
        self.id = id
        self.roundId = roundId
        self.totalScore = dictionary["totalScore"] as? Int ?? 0
        
        if let timestamp = dictionary["lastUpdated"] as? TimeInterval {
            self.lastUpdated = Date(timeIntervalSince1970: timestamp)
        } else {
            self.lastUpdated = Date()
        }
        
        self.holes = []
        self.modifiedHoles = dictionary["modifiedHoles"] as? [Int]
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "roundId": roundId,
            "totalScore": totalScore,
            "lastUpdated": lastUpdated.timeIntervalSince1970
        ]
        
        if let modified = modifiedHoles {
            dict["modifiedHoles"] = modified
        }
        
        return dict
    }
}

struct HoleScore {
    let holeNumber: Int
    var strokes: Int
    let par: Int
    var putts: Int?
    var fairwayHit: Bool?
    var greenInRegulation: Bool?
}

// MARK: - Gamification Supporting Types

struct LeaderboardUpdate {
    let playerId: String
    let position: Int
    let totalPlayers: Int
    let positionChange: Int
}

struct AchievementUnlock {
    let achievementId: String
    let tier: String
    let title: String
    let description: String
}

struct RatingUpdate {
    let playerId: String
    let currentRating: Double
    let ratingChange: Double
    let projectedRating: Double?
}

struct TournamentUpdate {
    let tournamentId: String
    let playerPosition: Int
    let standings: [[String: Any]]
}

// MARK: - Enhanced Gamification Delegate Protocol

protocol WatchGamificationDelegate: AnyObject {
    func watchConnectivityManager(_ manager: WatchConnectivityManager, didReceiveLeaderboardUpdate update: LeaderboardUpdate)
    func watchConnectivityManager(_ manager: WatchConnectivityManager, didReceiveChallengeUpdate update: ChallengeUpdate)
    func watchConnectivityManager(_ manager: WatchConnectivityManager, didReceiveAchievementUnlock achievement: AchievementUnlock)
    func watchConnectivityManager(_ manager: WatchConnectivityManager, didReceiveRatingUpdate rating: RatingUpdate)
    func watchConnectivityManager(_ manager: WatchConnectivityManager, didReceiveTournamentUpdate tournament: TournamentUpdate)
}