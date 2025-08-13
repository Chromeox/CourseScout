import Foundation
import WatchKit
import Combine
import os.log

// MARK: - Watch Gamification Service Protocol

protocol WatchGamificationServiceProtocol: AnyObject {
    // Leaderboard Management
    func updateLeaderboard(playerId: String, position: Int, totalPlayers: Int, positionChange: Int) async
    func getCurrentLeaderboardPosition() -> LeaderboardPosition?
    func subscribeToLeaderboardUpdates() -> AnyPublisher<LeaderboardPosition, Never>
    
    // Challenge Management
    func updateChallengeProgress(challengeId: String, progress: ChallengeProgress) async
    func getActiveChallenges() -> [ActiveChallenge]
    func subscribeToChallengeUpdates() -> AnyPublisher<ChallengeUpdate, Never>
    
    // Achievement Management
    func processAchievementUnlock(achievementId: String, tier: String, title: String, description: String) async
    func getRecentAchievements() -> [Achievement]
    func subscribeToAchievementUpdates() -> AnyPublisher<Achievement, Never>
    
    // Rating Management
    func updateRating(currentRating: Double, ratingChange: Double, projectedRating: Double?) async
    func getCurrentRating() -> PlayerRating?
    func subscribeToRatingUpdates() -> AnyPublisher<PlayerRating, Never>
    
    // Tournament Management
    func updateTournamentStatus(tournamentId: String, position: Int, standings: [[String: Any]]) async
    func getActiveTournaments() -> [ActiveTournament]
    func subscribeToTournamentUpdates() -> AnyPublisher<TournamentStatus, Never>
    
    // Notification Management
    func schedulePositionChangeNotification(positionChange: Int, delay: TimeInterval)
    func scheduleAchievementNotification(achievement: Achievement, delay: TimeInterval)
    func scheduleTournamentMilestoneNotification(milestone: String, delay: TimeInterval)
    
    // Enhanced Tournament Monitoring
    func enableLiveTournamentMonitoring(tournamentId: String, expectedDuration: TimeInterval) async
    func disableLiveTournamentMonitoring() async
    func updateLiveTournamentStandings(tournamentId: String, standings: [[String: Any]], playerPosition: Int, positionChange: Int) async
    func processNextOpponentNotification(tournamentId: String, opponentInfo: [String: Any], matchTime: Date) async
    func trackTournamentBracketProgression(tournamentId: String, bracketData: [String: Any]) async
    func updateTournamentPrizePool(tournamentId: String, prizePool: Double, projectedPayout: Double?) async
    
    // Enhanced Live Features
    func startLiveRatingTracking(playerId: String) async
    func updateLiveRatingProjection(rating: Double, projection: Double, confidenceInterval: (Double, Double), holesRemaining: Int) async
    func processLiveAchievementUnlock(achievement: Achievement, socialNotification: Bool) async
    func updateLiveHeadToHeadChallenge(challengeId: String, playerScore: Int, opponentScore: Int, matchStatus: String) async
    
    // Power Management
    func enableBatteryOptimization(_ enabled: Bool)
    func adjustUpdateFrequency(based batteryLevel: Float)
    func enableTournamentPowerMode(tournamentId: String, estimatedDuration: TimeInterval) async
    func getOptimalUpdateFrequency(for feature: GamificationFeature) -> TimeInterval
}

// MARK: - Watch Gamification Service Implementation

@MainActor
class WatchGamificationService: NSObject, WatchGamificationServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "Gamification")
    private let watchConnectivityService: WatchConnectivityService
    private let hapticService: WatchHapticFeedbackServiceProtocol
    private let notificationService: WatchNotificationServiceProtocol
    private let cacheService: WatchCacheServiceProtocol
    
    // Published properties for real-time updates
    @Published var currentLeaderboardPosition: LeaderboardPosition?
    @Published var activeChallenges: [ActiveChallenge] = []
    @Published var recentAchievements: [Achievement] = []
    @Published var currentRating: PlayerRating?
    @Published var activeTournaments: [ActiveTournament] = []
    
    // Combine subjects for subscriptions
    private let leaderboardSubject = PassthroughSubject<LeaderboardPosition, Never>()
    private let challengeSubject = PassthroughSubject<ChallengeUpdate, Never>()
    private let achievementSubject = PassthroughSubject<Achievement, Never>()
    private let ratingSubject = PassthroughSubject<PlayerRating, Never>()
    private let tournamentSubject = PassthroughSubject<TournamentStatus, Never>()
    
    // Configuration
    private var isBatteryOptimizationEnabled = false
    private var updateFrequency: TimeInterval = 5.0 // seconds
    private let maxCachedAchievements = 10
    private let maxActiveChallenges = 5
    
    // Enhanced Live Tournament Tracking
    private var liveTournamentId: String?
    private var tournamentMonitoringEnabled = false
    private var tournamentPowerModeEnabled = false
    private var liveTournamentData: [String: Any] = [:]
    private var lastTournamentUpdate: Date = Date()
    private var tournamentBracketData: [String: Any] = [:]
    private var nextOpponentInfo: [String: Any]?
    
    // Live Rating Tracking
    private var liveRatingTrackingEnabled = false
    private var currentLiveRating: Double = 0
    private var ratingProjection: (rating: Double, confidence: (Double, Double), holes: Int)?
    
    // Enhanced Performance Tracking
    private var lastUpdateTime: Date = Date()
    private var updateCount = 0
    private var backgroundTaskIdentifier: WKBackgroundTask?
    private var featureUpdateFrequencies: [GamificationFeature: TimeInterval] = [:]
    private var batteryLevelHistory: [Date: Float] = [:]
    
    // MARK: - Initialization
    
    init(
        watchConnectivityService: WatchConnectivityService,
        hapticService: WatchHapticFeedbackServiceProtocol,
        notificationService: WatchNotificationServiceProtocol,
        cacheService: WatchCacheServiceProtocol
    ) {
        self.watchConnectivityService = watchConnectivityService
        self.hapticService = hapticService
        self.notificationService = notificationService
        self.cacheService = cacheService
        
        super.init()
        
        setupGamificationService()
        loadCachedData()
    }
    
    // MARK: - Setup
    
    private func setupGamificationService() {
        logger.info("Setting up Watch Gamification Service")
        
        // Configure battery monitoring
        configureBackgroundUpdates()
        
        // Setup performance monitoring
        setupPerformanceMonitoring()
        
        logger.info("Watch Gamification Service setup complete")
    }
    
    private func loadCachedData() {
        Task {
            // Load cached gamification data
            currentLeaderboardPosition = await cacheService.retrieve(LeaderboardPosition.self, forKey: "current_leaderboard_position")
            activeChallenges = await cacheService.retrieve([ActiveChallenge].self, forKey: "active_challenges") ?? []
            recentAchievements = await cacheService.retrieve([Achievement].self, forKey: "recent_achievements") ?? []
            currentRating = await cacheService.retrieve(PlayerRating.self, forKey: "current_rating")
            activeTournaments = await cacheService.retrieve([ActiveTournament].self, forKey: "active_tournaments") ?? []
            
            logger.debug("Loaded cached gamification data")
        }
    }
    
    // MARK: - Leaderboard Management
    
    func updateLeaderboard(playerId: String, position: Int, totalPlayers: Int, positionChange: Int) async {
        let newPosition = LeaderboardPosition(
            playerId: playerId,
            position: position,
            totalPlayers: totalPlayers,
            positionChange: positionChange,
            lastUpdated: Date()
        )
        
        // Update current position
        let previousPosition = currentLeaderboardPosition?.position
        currentLeaderboardPosition = newPosition
        
        // Cache the update
        await cacheService.store(newPosition, forKey: "current_leaderboard_position")
        
        // Notify subscribers
        leaderboardSubject.send(newPosition)
        
        // Trigger haptic feedback for significant changes
        if abs(positionChange) >= 3 {
            await triggerPositionChangeHaptic(positionChange: positionChange)
        }
        
        // Schedule notification if significant improvement
        if positionChange > 5 {
            schedulePositionChangeNotification(positionChange: positionChange, delay: 1.0)
        }
        
        logger.info("Updated leaderboard position: \(position)/\(totalPlayers) (change: \(positionChange))")
    }
    
    func getCurrentLeaderboardPosition() -> LeaderboardPosition? {
        return currentLeaderboardPosition
    }
    
    func subscribeToLeaderboardUpdates() -> AnyPublisher<LeaderboardPosition, Never> {
        return leaderboardSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Challenge Management
    
    func updateChallengeProgress(challengeId: String, progress: ChallengeProgress) async {
        // Find or create challenge
        var updatedChallenges = activeChallenges
        
        if let index = updatedChallenges.firstIndex(where: { $0.challengeId == challengeId }) {
            updatedChallenges[index].progress = progress
            updatedChallenges[index].lastUpdated = Date()
        } else {
            let newChallenge = ActiveChallenge(
                challengeId: challengeId,
                title: "Challenge",
                type: .headToHead,
                progress: progress,
                startDate: Date(),
                lastUpdated: Date()
            )
            updatedChallenges.append(newChallenge)
        }
        
        // Limit number of active challenges
        if updatedChallenges.count > maxActiveChallenges {
            updatedChallenges = Array(updatedChallenges.suffix(maxActiveChallenges))
        }
        
        activeChallenges = updatedChallenges
        
        // Cache updates
        await cacheService.store(activeChallenges, forKey: "active_challenges")
        
        // Create update event
        let challengeUpdate = ChallengeUpdate(
            challengeId: challengeId,
            updateType: .challengeCompleted,
            playerId: "",
            data: [:],
            timestamp: Date()
        )
        
        // Notify subscribers
        challengeSubject.send(challengeUpdate)
        
        // Trigger haptic for milestones
        if progress.isCompleted {
            await triggerChallengeCompletionHaptic()
        }
        
        logger.info("Updated challenge progress: \(challengeId)")
    }
    
    func getActiveChallenges() -> [ActiveChallenge] {
        return activeChallenges
    }
    
    func subscribeToChallengeUpdates() -> AnyPublisher<ChallengeUpdate, Never> {
        return challengeSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Achievement Management
    
    func processAchievementUnlock(achievementId: String, tier: String, title: String, description: String) async {
        let achievement = Achievement(
            achievementId: achievementId,
            tier: tier,
            title: title,
            description: description,
            unlockedAt: Date()
        )
        
        // Add to recent achievements
        var updatedAchievements = recentAchievements
        updatedAchievements.insert(achievement, at: 0)
        
        // Limit cached achievements
        if updatedAchievements.count > maxCachedAchievements {
            updatedAchievements = Array(updatedAchievements.prefix(maxCachedAchievements))
        }
        
        recentAchievements = updatedAchievements
        
        // Cache updates
        await cacheService.store(recentAchievements, forKey: "recent_achievements")
        
        // Notify subscribers
        achievementSubject.send(achievement)
        
        // Trigger celebration haptic
        await triggerAchievementHaptic(tier: tier)
        
        // Schedule notification
        scheduleAchievementNotification(achievement: achievement, delay: 0.5)
        
        logger.info("Achievement unlocked: \(title) (\(tier))")
    }
    
    func getRecentAchievements() -> [Achievement] {
        return recentAchievements
    }
    
    func subscribeToAchievementUpdates() -> AnyPublisher<Achievement, Never> {
        return achievementSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Rating Management
    
    func updateRating(currentRating: Double, ratingChange: Double, projectedRating: Double?) async {
        let newRating = PlayerRating(
            currentRating: currentRating,
            ratingChange: ratingChange,
            projectedRating: projectedRating,
            lastUpdated: Date()
        )
        
        self.currentRating = newRating
        
        // Cache the update
        await cacheService.store(newRating, forKey: "current_rating")
        
        // Notify subscribers
        ratingSubject.send(newRating)
        
        // Trigger haptic for significant changes
        if abs(ratingChange) >= 50 {
            await triggerRatingChangeHaptic(ratingChange: ratingChange)
        }
        
        logger.info("Updated rating: \(currentRating) (change: \(ratingChange))")
    }
    
    func getCurrentRating() -> PlayerRating? {
        return currentRating
    }
    
    func subscribeToRatingUpdates() -> AnyPublisher<PlayerRating, Never> {
        return ratingSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Tournament Management
    
    func updateTournamentStatus(tournamentId: String, position: Int, standings: [[String: Any]]) async {
        // Find or create tournament
        var updatedTournaments = activeTournaments
        
        if let index = updatedTournaments.firstIndex(where: { $0.tournamentId == tournamentId }) {
            updatedTournaments[index].currentPosition = position
            updatedTournaments[index].lastUpdated = Date()
        } else {
            let newTournament = ActiveTournament(
                tournamentId: tournamentId,
                name: "Tournament",
                currentPosition: position,
                totalParticipants: standings.count,
                status: .active,
                lastUpdated: Date()
            )
            updatedTournaments.append(newTournament)
        }
        
        activeTournaments = updatedTournaments
        
        // Cache updates
        await cacheService.store(activeTournaments, forKey: "active_tournaments")
        
        // Create tournament status update
        let tournamentStatus = TournamentStatus(
            tournamentId: tournamentId,
            position: position,
            totalParticipants: standings.count,
            standings: standings,
            lastUpdated: Date()
        )
        
        // Notify subscribers
        tournamentSubject.send(tournamentStatus)
        
        // Check for milestones
        await checkTournamentMilestones(position: position, totalParticipants: standings.count)
        
        logger.info("Updated tournament status: \(tournamentId) position \(position)")
    }
    
    func getActiveTournaments() -> [ActiveTournament] {
        return activeTournaments
    }
    
    func subscribeToTournamentUpdates() -> AnyPublisher<TournamentStatus, Never> {
        return tournamentSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Notification Management
    
    func schedulePositionChangeNotification(positionChange: Int, delay: TimeInterval) {
        let title = positionChange > 0 ? "Great Job!" : "Keep Fighting!"
        let body = positionChange > 0 
            ? "You've moved up \(positionChange) positions!"
            : "Down \(abs(positionChange)) positions, but you've got this!"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.showLocalNotification(title: title, body: body)
        }
    }
    
    func scheduleAchievementNotification(achievement: Achievement, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.showLocalNotification(
                title: "🏆 \(achievement.title)",
                body: achievement.description
            )
        }
    }
    
    func scheduleTournamentMilestoneNotification(milestone: String, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.showLocalNotification(
                title: "Tournament Milestone",
                body: milestone
            )
        }
    }
    
    // MARK: - Power Management
    
    func enableBatteryOptimization(_ enabled: Bool) {
        isBatteryOptimizationEnabled = enabled
        
        if enabled {
            // Reduce update frequency
            adjustUpdateFrequency(based: WKInterfaceDevice.current().batteryLevel)
        } else {
            // Restore normal frequency
            updateFrequency = 5.0
        }
        
        logger.info("Battery optimization \(enabled ? "enabled" : "disabled")")
    }
    
    func adjustUpdateFrequency(based batteryLevel: Float) {
        guard isBatteryOptimizationEnabled else { return }
        
        switch batteryLevel {
        case 0.0..<0.2: // Low battery
            updateFrequency = 30.0 // 30 seconds
        case 0.2..<0.5: // Medium battery
            updateFrequency = 15.0 // 15 seconds
        default: // Good battery
            updateFrequency = 5.0 // 5 seconds
        }
        
        logger.debug("Adjusted update frequency to \(updateFrequency) seconds for battery level \(batteryLevel)")
    }
    
    // MARK: - Private Helper Methods
    
    private func triggerPositionChangeHaptic(positionChange: Int) async {
        if positionChange > 0 {
            hapticService.playTaptic(.success)
        } else if positionChange < -3 {
            hapticService.playTaptic(.warning)
        } else {
            hapticService.playTaptic(.medium)
        }
    }
    
    private func triggerChallengeCompletionHaptic() async {
        hapticService.playSuccessSequence()
    }
    
    private func triggerAchievementHaptic(tier: String) async {
        switch tier.lowercased() {
        case "bronze":
            hapticService.playTaptic(.light)
        case "silver":
            hapticService.playTaptic(.medium)
        case "gold", "platinum", "diamond":
            hapticService.playSuccessSequence()
        default:
            hapticService.playTaptic(.success)
        }
    }
    
    private func triggerRatingChangeHaptic(ratingChange: Double) async {
        if ratingChange > 0 {
            hapticService.playTaptic(.success)
        } else {
            hapticService.playTaptic(.warning)
        }
    }
    
    private func checkTournamentMilestones(position: Int, totalParticipants: Int) async {
        let percentile = Double(position) / Double(totalParticipants)
        
        if position == 1 {
            await triggerTournamentMilestoneHaptic(milestone: "first_place")
            scheduleTournamentMilestoneNotification(milestone: "🥇 First Place!", delay: 1.0)
        } else if position <= 3 {
            await triggerTournamentMilestoneHaptic(milestone: "top_three")
            scheduleTournamentMilestoneNotification(milestone: "🏆 Top 3!", delay: 1.0)
        } else if percentile <= 0.1 {
            await triggerTournamentMilestoneHaptic(milestone: "top_ten_percent")
            scheduleTournamentMilestoneNotification(milestone: "⭐ Top 10%!", delay: 1.0)
        }
    }
    
    private func triggerTournamentMilestoneHaptic(milestone: String) async {
        switch milestone {
        case "first_place":
            hapticService.playCustomPattern(WatchHapticPattern(
                events: [
                    WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 0.0),
                    WatchHapticEvent(intensity: 0.8, sharpness: 0.8, time: 0.2),
                    WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 0.4)
                ],
                duration: 0.6
            ))
        case "top_three":
            hapticService.playSuccessSequence()
        default:
            hapticService.playTaptic(.success)
        }
    }
    
    private func showLocalNotification(title: String, body: String) {
        // Use WatchKit notification system
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Failed to schedule notification: \(error)")
            }
        }
    }
    
    private func configureBackgroundUpdates() {
        // Configure background task handling for efficient updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundRefresh),
            name: Notification.Name("BackgroundRefresh"),
            object: nil
        )
    }
    
    @objc private func handleBackgroundRefresh() {
        backgroundTaskIdentifier = WKApplication.shared().beginBackgroundTask(
            withName: "GamificationSync"
        ) { [weak self] in
            self?.endBackgroundTask()
        }
        
        Task {
            // Perform minimal sync in background
            await performBackgroundSync()
            endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if let taskId = backgroundTaskIdentifier {
            WKApplication.shared().endBackgroundTask(taskId)
            backgroundTaskIdentifier = nil
        }
    }
    
    private func performBackgroundSync() async {
        // Minimal background sync to update critical gamification data
        logger.debug("Performing background gamification sync")
        
        // Only sync most important data to preserve battery
        // Implementation would depend on available data sources
    }
    
    private func setupPerformanceMonitoring() {
        // Track performance metrics for optimization
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.logPerformanceMetrics()
        }
    }
    
    private func logPerformanceMetrics() {
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
        
        logger.debug("Gamification service performance: \(updateCount) updates in \(timeSinceLastUpdate)s")
        
        // Reset counters
        lastUpdateTime = now
        updateCount = 0
    }
    
    // MARK: - Enhanced Tournament Monitoring
    
    /// Enable live tournament monitoring with power optimization
    func enableLiveTournamentMonitoring(tournamentId: String, expectedDuration: TimeInterval) async {
        liveTournamentId = tournamentId
        tournamentMonitoringEnabled = true
        lastTournamentUpdate = Date()
        
        // Enable tournament power mode for long tournaments
        if expectedDuration > 7200 { // 2+ hours
            await enableTournamentPowerMode(tournamentId: tournamentId, estimatedDuration: expectedDuration)
        }
        
        // Initialize tournament-specific update frequencies
        featureUpdateFrequencies[.tournament] = getOptimalUpdateFrequency(for: .tournament)
        featureUpdateFrequencies[.leaderboard] = getOptimalUpdateFrequency(for: .leaderboard)
        
        logger.info("Live tournament monitoring enabled for \(tournamentId)")
    }
    
    /// Disable live tournament monitoring and restore normal operation
    func disableLiveTournamentMonitoring() async {
        tournamentMonitoringEnabled = false
        tournamentPowerModeEnabled = false
        liveTournamentId = nil
        liveTournamentData.removeAll()
        tournamentBracketData.removeAll()
        nextOpponentInfo = nil
        
        // Restore normal update frequencies
        featureUpdateFrequencies.removeAll()
        enableBatteryOptimization(false)
        
        logger.info("Live tournament monitoring disabled")
    }
    
    /// Update live tournament standings with enhanced position tracking
    func updateLiveTournamentStandings(tournamentId: String, standings: [[String: Any]], playerPosition: Int, positionChange: Int) async {
        guard tournamentMonitoringEnabled && liveTournamentId == tournamentId else { return }
        
        liveTournamentData["standings"] = standings
        liveTournamentData["playerPosition"] = playerPosition
        liveTournamentData["positionChange"] = positionChange
        liveTournamentData["lastUpdated"] = Date()
        
        // Cache tournament data
        await cacheService.store(liveTournamentData, forKey: "live_tournament_\(tournamentId)")
        
        // Update current position tracking
        if let currentPosition = currentLeaderboardPosition {
            let newPosition = LeaderboardPosition(
                playerId: currentPosition.playerId,
                position: playerPosition,
                totalPlayers: standings.count,
                positionChange: positionChange,
                lastUpdated: Date()
            )
            
            await updateLeaderboard(
                playerId: currentPosition.playerId,
                position: playerPosition,
                totalPlayers: standings.count,
                positionChange: positionChange
            )
        }
        
        // Create tournament status update
        let tournamentStatus = TournamentStatus(
            tournamentId: tournamentId,
            position: playerPosition,
            totalParticipants: standings.count,
            standings: standings,
            lastUpdated: Date()
        )
        
        // Notify subscribers
        tournamentSubject.send(tournamentStatus)
        
        lastTournamentUpdate = Date()
        updateCount += 1
        
        logger.info("Live tournament standings updated: position \(playerPosition) of \(standings.count)")
    }
    
    /// Process next opponent notification with enhanced data
    func processNextOpponentNotification(tournamentId: String, opponentInfo: [String: Any], matchTime: Date) async {
        guard tournamentMonitoringEnabled && liveTournamentId == tournamentId else { return }
        
        nextOpponentInfo = opponentInfo
        nextOpponentInfo?["matchTime"] = matchTime.timeIntervalSince1970
        
        // Cache opponent information
        await cacheService.store(nextOpponentInfo, forKey: "next_opponent_\(tournamentId)")
        
        // Schedule pre-match notification
        let timeUntilMatch = matchTime.timeIntervalSince(Date())
        if timeUntilMatch > 1800 { // 30 minutes before
            scheduleNextOpponentReminder(opponentInfo: opponentInfo, delay: timeUntilMatch - 1800)
        }
        
        logger.info("Next opponent notification processed for \(tournamentId)")
    }
    
    /// Track tournament bracket progression with visual updates
    func trackTournamentBracketProgression(tournamentId: String, bracketData: [String: Any]) async {
        guard tournamentMonitoringEnabled && liveTournamentId == tournamentId else { return }
        
        tournamentBracketData = bracketData
        
        // Cache bracket data
        await cacheService.store(bracketData, forKey: "tournament_bracket_\(tournamentId)")
        
        // Check for advancement milestones
        if let currentRound = bracketData["currentRound"] as? Int,
           let totalRounds = bracketData["totalRounds"] as? Int {
            await checkTournamentAdvancementMilestones(currentRound: currentRound, totalRounds: totalRounds)
        }
        
        logger.info("Tournament bracket progression tracked for \(tournamentId)")
    }
    
    /// Update tournament prize pool with live calculations
    func updateTournamentPrizePool(tournamentId: String, prizePool: Double, projectedPayout: Double?) async {
        guard tournamentMonitoringEnabled && liveTournamentId == tournamentId else { return }
        
        var prizeData: [String: Any] = [
            "totalPrizePool": prizePool,
            "lastUpdated": Date()
        ]
        
        if let payout = projectedPayout {
            prizeData["projectedPayout"] = payout
        }
        
        // Cache prize information
        await cacheService.store(prizeData, forKey: "tournament_prizes_\(tournamentId)")
        
        // Trigger haptic for significant payout changes
        if let previousPayout = liveTournamentData["projectedPayout"] as? Double,
           let currentPayout = projectedPayout {
            let payoutChange = currentPayout - previousPayout
            if abs(payoutChange) > 100 { // Significant change
                hapticService.playTaptic(payoutChange > 0 ? .success : .warning)
            }
        }
        
        liveTournamentData["prizePool"] = prizePool
        liveTournamentData["projectedPayout"] = projectedPayout
        
        logger.info("Tournament prize pool updated: $\(prizePool)")
    }
    
    // MARK: - Enhanced Live Features
    
    /// Start live rating tracking with real-time updates
    func startLiveRatingTracking(playerId: String) async {
        liveRatingTrackingEnabled = true
        
        // Set optimal update frequency for live rating
        featureUpdateFrequencies[.rating] = getOptimalUpdateFrequency(for: .rating)
        
        logger.info("Live rating tracking started for \(playerId)")
    }
    
    /// Update live rating projection with confidence intervals
    func updateLiveRatingProjection(rating: Double, projection: Double, confidenceInterval: (Double, Double), holesRemaining: Int) async {
        guard liveRatingTrackingEnabled else { return }
        
        currentLiveRating = rating
        ratingProjection = (projection, confidenceInterval, holesRemaining)
        
        // Update current rating with projection
        let newRating = PlayerRating(
            currentRating: rating,
            ratingChange: projection - rating,
            projectedRating: projection,
            lastUpdated: Date()
        )
        
        await updateRating(
            currentRating: rating,
            ratingChange: projection - rating,
            projectedRating: projection
        )
        
        // Cache live rating data
        let ratingData: [String: Any] = [
            "currentRating": rating,
            "projectedRating": projection,
            "confidenceInterval": ["lower": confidenceInterval.0, "upper": confidenceInterval.1],
            "holesRemaining": holesRemaining,
            "lastUpdated": Date()
        ]
        
        await cacheService.store(ratingData, forKey: "live_rating_projection")
        
        logger.info("Live rating projection updated: \(rating) → \(projection)")
    }
    
    /// Process live achievement unlock with enhanced celebration
    func processLiveAchievementUnlock(achievement: Achievement, socialNotification: Bool) async {
        // Standard achievement processing
        await processAchievementUnlock(
            achievementId: achievement.achievementId,
            tier: achievement.tier,
            title: achievement.title,
            description: achievement.description
        )
        
        // Enhanced live features
        if socialNotification {
            await scheduleSocialAchievementSharing(achievement: achievement)
        }
        
        // Coordinate with iPhone for synchronized celebration
        await coordinateAchievementCelebration(achievement: achievement)
        
        logger.info("Live achievement unlock processed: \(achievement.title)")
    }
    
    /// Update live head-to-head challenge with real-time scoring
    func updateLiveHeadToHeadChallenge(challengeId: String, playerScore: Int, opponentScore: Int, matchStatus: String) async {
        // Find and update the challenge
        var updatedChallenges = activeChallenges
        
        if let index = updatedChallenges.firstIndex(where: { $0.challengeId == challengeId }) {
            // Update challenge with live data
            let liveProgress = ChallengeProgress(
                completedSteps: playerScore,
                totalSteps: 18, // Assuming 18 holes
                percentComplete: Double(playerScore) / 18.0 * 100,
                isCompleted: matchStatus.contains("complete"),
                currentScore: playerScore,
                targetScore: opponentScore
            )
            
            updatedChallenges[index].progress = liveProgress
            updatedChallenges[index].lastUpdated = Date()
        }
        
        activeChallenges = updatedChallenges
        
        // Cache live challenge data
        let challengeData: [String: Any] = [
            "challengeId": challengeId,
            "playerScore": playerScore,
            "opponentScore": opponentScore,
            "matchStatus": matchStatus,
            "lastUpdated": Date()
        ]
        
        await cacheService.store(challengeData, forKey: "live_challenge_\(challengeId)")
        
        // Create challenge update
        let challengeUpdate = ChallengeUpdate(
            challengeId: challengeId,
            updateType: .scoreSubmitted,
            playerId: "current_player",
            data: [:],
            timestamp: Date()
        )
        
        challengeSubject.send(challengeUpdate)
        
        // Trigger haptic for match status changes
        if matchStatus.contains("up") || matchStatus.contains("down") {
            hapticService.playTaptic(playerScore < opponentScore ? .success : .warning)
        }
        
        logger.info("Live head-to-head challenge updated: \(challengeId)")
    }
    
    // MARK: - Enhanced Power Management
    
    /// Enable tournament power mode for extended monitoring
    func enableTournamentPowerMode(tournamentId: String, estimatedDuration: TimeInterval) async {
        tournamentPowerModeEnabled = true
        
        // Adjust update frequencies based on tournament length
        if estimatedDuration > 14400 { // 4+ hours - Very conservative
            featureUpdateFrequencies[.tournament] = 60.0 // 1 minute
            featureUpdateFrequencies[.leaderboard] = 120.0 // 2 minutes
            featureUpdateFrequencies[.rating] = 180.0 // 3 minutes
        } else if estimatedDuration > 7200 { // 2+ hours - Conservative
            featureUpdateFrequencies[.tournament] = 30.0 // 30 seconds
            featureUpdateFrequencies[.leaderboard] = 60.0 // 1 minute
            featureUpdateFrequencies[.rating] = 90.0 // 1.5 minutes
        } else { // Standard tournament - Normal
            featureUpdateFrequencies[.tournament] = 15.0 // 15 seconds
            featureUpdateFrequencies[.leaderboard] = 30.0 // 30 seconds
            featureUpdateFrequencies[.rating] = 45.0 // 45 seconds
        }
        
        // Enable battery optimization
        enableBatteryOptimization(true)
        
        // Monitor battery level
        startBatteryLevelMonitoring()
        
        logger.info("Tournament power mode enabled for \(tournamentId) (duration: \(estimatedDuration)s)")
    }
    
    /// Get optimal update frequency for specific gamification features
    func getOptimalUpdateFrequency(for feature: GamificationFeature) -> TimeInterval {
        // Return custom frequency if set
        if let customFrequency = featureUpdateFrequencies[feature] {
            return customFrequency
        }
        
        // Base frequencies by feature importance and battery impact
        let baseFrequency: TimeInterval
        
        switch feature {
        case .tournament:
            baseFrequency = tournamentPowerModeEnabled ? 30.0 : 15.0
        case .leaderboard:
            baseFrequency = tournamentPowerModeEnabled ? 60.0 : 30.0
        case .rating:
            baseFrequency = liveRatingTrackingEnabled ? 45.0 : 90.0
        case .achievements:
            baseFrequency = 120.0 // Less frequent, event-driven
        case .challenges:
            baseFrequency = 60.0 // Moderate frequency
        case .social:
            baseFrequency = 180.0 // Least frequent
        }
        
        // Adjust based on battery optimization
        if isBatteryOptimizationEnabled {
            let batteryLevel = WKInterfaceDevice.current().batteryLevel
            return adjustFrequencyForBattery(baseFrequency, batteryLevel: batteryLevel)
        }
        
        return baseFrequency
    }
    
    // MARK: - Private Enhanced Helper Methods
    
    private func scheduleNextOpponentReminder(opponentInfo: [String: Any], delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            
            let opponentName = opponentInfo["name"] as? String ?? "Opponent"
            
            self.showLocalNotification(
                title: "Match Starting Soon",
                body: "Your match against \(opponentName) starts in 30 minutes"
            )
        }
    }
    
    private func checkTournamentAdvancementMilestones(currentRound: Int, totalRounds: Int) async {
        let progressPercent = Double(currentRound) / Double(totalRounds) * 100
        
        // Check for significant advancement milestones
        if currentRound == 1 && totalRounds > 1 {
            scheduleTournamentMilestoneNotification(milestone: "Tournament Started!", delay: 1.0)
        } else if progressPercent >= 50 && progressPercent < 75 {
            await hapticService.playTournamentMilestoneHaptic(milestone: "halfway")
            scheduleTournamentMilestoneNotification(milestone: "Halfway Through Tournament", delay: 1.0)
        } else if progressPercent >= 75 && progressPercent < 100 {
            await hapticService.playTournamentMilestoneHaptic(milestone: "final_stretch")
            scheduleTournamentMilestoneNotification(milestone: "Final Stretch!", delay: 1.0)
        } else if currentRound == totalRounds {
            await hapticService.playTournamentMilestoneHaptic(milestone: "tournament_complete")
            scheduleTournamentMilestoneNotification(milestone: "Tournament Complete!", delay: 1.0)
        }
    }
    
    private func scheduleSocialAchievementSharing(achievement: Achievement) async {
        // Schedule social sharing for achievement
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            // Trigger social sharing flow
            self?.logger.info("Social achievement sharing triggered for: \(achievement.title)")
        }
    }
    
    private func coordinateAchievementCelebration(achievement: Achievement) async {
        // Coordinate synchronized celebration with iPhone
        let celebrationData: [String: Any] = [
            "achievementId": achievement.achievementId,
            "tier": achievement.tier,
            "celebrationType": "synchronized",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // This would trigger iPhone coordination through watch connectivity
        logger.debug("Coordinating achievement celebration: \(achievement.title)")
    }
    
    private func adjustFrequencyForBattery(_ baseFrequency: TimeInterval, batteryLevel: Float) -> TimeInterval {
        switch batteryLevel {
        case 0.0..<0.2: // Critical battery
            return baseFrequency * 4 // Much less frequent
        case 0.2..<0.5: // Low battery
            return baseFrequency * 2 // Less frequent
        case 0.5..<0.8: // Medium battery
            return baseFrequency * 1.5 // Slightly less frequent
        default: // Good battery
            return baseFrequency // Normal frequency
        }
    }
    
    private func startBatteryLevelMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let batteryLevel = WKInterfaceDevice.current().batteryLevel
            self.batteryLevelHistory[Date()] = batteryLevel
            
            // Keep only last 12 hours of battery data
            let cutoffDate = Date().addingTimeInterval(-43200)
            self.batteryLevelHistory = self.batteryLevelHistory.filter { $0.key >= cutoffDate }
            
            // Adjust frequencies if battery optimization is enabled
            if self.isBatteryOptimizationEnabled {
                self.adjustUpdateFrequency(based: batteryLevel)
            }
        }
    }
}

// MARK: - Supporting Data Models

enum GamificationFeature {
    case tournament
    case leaderboard
    case rating
    case achievements
    case challenges
    case social
}

struct LeaderboardPosition: Codable {
    let playerId: String
    let position: Int
    let totalPlayers: Int
    let positionChange: Int
    let lastUpdated: Date
}

struct ActiveChallenge: Codable {
    let challengeId: String
    let title: String
    let type: ChallengeType
    var progress: ChallengeProgress
    let startDate: Date
    var lastUpdated: Date
}

struct ChallengeProgress: Codable {
    let completedSteps: Int
    let totalSteps: Int
    let percentComplete: Double
    let isCompleted: Bool
    let currentScore: Int?
    let targetScore: Int?
}

enum ChallengeType: String, Codable {
    case headToHead
    case tournament
    case achievement
    case social
}

struct Achievement: Codable {
    let achievementId: String
    let tier: String
    let title: String
    let description: String
    let unlockedAt: Date
}

struct PlayerRating: Codable {
    let currentRating: Double
    let ratingChange: Double
    let projectedRating: Double?
    let lastUpdated: Date
}

struct ActiveTournament: Codable {
    let tournamentId: String
    let name: String
    var currentPosition: Int
    let totalParticipants: Int
    let status: TournamentStatusType
    var lastUpdated: Date
}

enum TournamentStatusType: String, Codable {
    case active
    case completed
    case pending
}

struct TournamentStatus: Codable {
    let tournamentId: String
    let position: Int
    let totalParticipants: Int
    let standings: [[String: Any]]
    let lastUpdated: Date
    
    // Custom coding to handle the dictionary array
    enum CodingKeys: String, CodingKey {
        case tournamentId, position, totalParticipants, lastUpdated
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tournamentId = try container.decode(String.self, forKey: .tournamentId)
        position = try container.decode(Int.self, forKey: .position)
        totalParticipants = try container.decode(Int.self, forKey: .totalParticipants)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        standings = [] // Would need custom decoding for complex dictionary arrays
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tournamentId, forKey: .tournamentId)
        try container.encode(position, forKey: .position)
        try container.encode(totalParticipants, forKey: .totalParticipants)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
    
    init(tournamentId: String, position: Int, totalParticipants: Int, standings: [[String: Any]], lastUpdated: Date) {
        self.tournamentId = tournamentId
        self.position = position
        self.totalParticipants = totalParticipants
        self.standings = standings
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Mock Implementation for Testing

class MockWatchGamificationService: WatchGamificationServiceProtocol {
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "MockGamification")
    
    @Published var mockLeaderboardPosition: LeaderboardPosition?
    @Published var mockActiveChallenges: [ActiveChallenge] = []
    @Published var mockRecentAchievements: [Achievement] = []
    @Published var mockCurrentRating: PlayerRating?
    @Published var mockActiveTournaments: [ActiveTournament] = []
    
    private let leaderboardSubject = PassthroughSubject<LeaderboardPosition, Never>()
    private let challengeSubject = PassthroughSubject<ChallengeUpdate, Never>()
    private let achievementSubject = PassthroughSubject<Achievement, Never>()
    private let ratingSubject = PassthroughSubject<PlayerRating, Never>()
    private let tournamentSubject = PassthroughSubject<TournamentStatus, Never>()
    
    func updateLeaderboard(playerId: String, position: Int, totalPlayers: Int, positionChange: Int) async {
        let newPosition = LeaderboardPosition(
            playerId: playerId,
            position: position,
            totalPlayers: totalPlayers,
            positionChange: positionChange,
            lastUpdated: Date()
        )
        mockLeaderboardPosition = newPosition
        leaderboardSubject.send(newPosition)
        logger.debug("Mock leaderboard update: \(position)/\(totalPlayers)")
    }
    
    func getCurrentLeaderboardPosition() -> LeaderboardPosition? {
        return mockLeaderboardPosition
    }
    
    func subscribeToLeaderboardUpdates() -> AnyPublisher<LeaderboardPosition, Never> {
        return leaderboardSubject.eraseToAnyPublisher()
    }
    
    func updateChallengeProgress(challengeId: String, progress: ChallengeProgress) async {
        logger.debug("Mock challenge progress update: \(challengeId)")
    }
    
    func getActiveChallenges() -> [ActiveChallenge] {
        return mockActiveChallenges
    }
    
    func subscribeToChallengeUpdates() -> AnyPublisher<ChallengeUpdate, Never> {
        return challengeSubject.eraseToAnyPublisher()
    }
    
    func processAchievementUnlock(achievementId: String, tier: String, title: String, description: String) async {
        let achievement = Achievement(
            achievementId: achievementId,
            tier: tier,
            title: title,
            description: description,
            unlockedAt: Date()
        )
        mockRecentAchievements.insert(achievement, at: 0)
        achievementSubject.send(achievement)
        logger.debug("Mock achievement unlock: \(title)")
    }
    
    func getRecentAchievements() -> [Achievement] {
        return mockRecentAchievements
    }
    
    func subscribeToAchievementUpdates() -> AnyPublisher<Achievement, Never> {
        return achievementSubject.eraseToAnyPublisher()
    }
    
    func updateRating(currentRating: Double, ratingChange: Double, projectedRating: Double?) async {
        let newRating = PlayerRating(
            currentRating: currentRating,
            ratingChange: ratingChange,
            projectedRating: projectedRating,
            lastUpdated: Date()
        )
        mockCurrentRating = newRating
        ratingSubject.send(newRating)
        logger.debug("Mock rating update: \(currentRating)")
    }
    
    func getCurrentRating() -> PlayerRating? {
        return mockCurrentRating
    }
    
    func subscribeToRatingUpdates() -> AnyPublisher<PlayerRating, Never> {
        return ratingSubject.eraseToAnyPublisher()
    }
    
    func updateTournamentStatus(tournamentId: String, position: Int, standings: [[String: Any]]) async {
        logger.debug("Mock tournament update: \(tournamentId) position \(position)")
    }
    
    func getActiveTournaments() -> [ActiveTournament] {
        return mockActiveTournaments
    }
    
    func subscribeToTournamentUpdates() -> AnyPublisher<TournamentStatus, Never> {
        return tournamentSubject.eraseToAnyPublisher()
    }
    
    func schedulePositionChangeNotification(positionChange: Int, delay: TimeInterval) {
        logger.debug("Mock position change notification scheduled: \(positionChange)")
    }
    
    func scheduleAchievementNotification(achievement: Achievement, delay: TimeInterval) {
        logger.debug("Mock achievement notification scheduled: \(achievement.title)")
    }
    
    func scheduleTournamentMilestoneNotification(milestone: String, delay: TimeInterval) {
        logger.debug("Mock tournament milestone notification scheduled: \(milestone)")
    }
    
    func enableBatteryOptimization(_ enabled: Bool) {
        logger.debug("Mock battery optimization: \(enabled)")
    }
    
    func adjustUpdateFrequency(based batteryLevel: Float) {
        logger.debug("Mock update frequency adjustment for battery: \(batteryLevel)")
    }
    
    // MARK: - Enhanced Tournament Monitoring (Mock)
    
    func enableLiveTournamentMonitoring(tournamentId: String, expectedDuration: TimeInterval) async {
        logger.debug("Mock live tournament monitoring enabled: \(tournamentId)")
    }
    
    func disableLiveTournamentMonitoring() async {
        logger.debug("Mock live tournament monitoring disabled")
    }
    
    func updateLiveTournamentStandings(tournamentId: String, standings: [[String: Any]], playerPosition: Int, positionChange: Int) async {
        logger.debug("Mock live tournament standings update: \(tournamentId)")
    }
    
    func processNextOpponentNotification(tournamentId: String, opponentInfo: [String: Any], matchTime: Date) async {
        logger.debug("Mock next opponent notification: \(tournamentId)")
    }
    
    func trackTournamentBracketProgression(tournamentId: String, bracketData: [String: Any]) async {
        logger.debug("Mock tournament bracket progression: \(tournamentId)")
    }
    
    func updateTournamentPrizePool(tournamentId: String, prizePool: Double, projectedPayout: Double?) async {
        logger.debug("Mock tournament prize pool update: \(tournamentId) - $\(prizePool)")
    }
    
    // MARK: - Enhanced Live Features (Mock)
    
    func startLiveRatingTracking(playerId: String) async {
        logger.debug("Mock live rating tracking started: \(playerId)")
    }
    
    func updateLiveRatingProjection(rating: Double, projection: Double, confidenceInterval: (Double, Double), holesRemaining: Int) async {
        logger.debug("Mock live rating projection: \(rating) → \(projection)")
    }
    
    func processLiveAchievementUnlock(achievement: Achievement, socialNotification: Bool) async {
        logger.debug("Mock live achievement unlock: \(achievement.title)")
    }
    
    func updateLiveHeadToHeadChallenge(challengeId: String, playerScore: Int, opponentScore: Int, matchStatus: String) async {
        logger.debug("Mock live head-to-head update: \(challengeId)")
    }
    
    // MARK: - Enhanced Power Management (Mock)
    
    func enableTournamentPowerMode(tournamentId: String, estimatedDuration: TimeInterval) async {
        logger.debug("Mock tournament power mode enabled: \(tournamentId)")
    }
    
    func getOptimalUpdateFrequency(for feature: GamificationFeature) -> TimeInterval {
        switch feature {
        case .tournament: return 30.0
        case .leaderboard: return 60.0
        case .rating: return 90.0
        case .achievements: return 120.0
        case .challenges: return 60.0
        case .social: return 180.0
        }
    }
}