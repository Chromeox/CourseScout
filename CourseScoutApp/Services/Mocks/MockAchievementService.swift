import Foundation
import Combine

// MARK: - Mock Achievement Service Implementation

@MainActor
class MockAchievementService: AchievementServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private var mockPlayerAchievements: [String: [PlayerAchievement]] = [:]
    private var mockAvailableAchievements: [Achievement] = []
    private var mockBadges: [String: PlayerBadgeCollection] = [:]
    private var mockChains: [AchievementChain] = []
    private var mockMilestones: [String: [UpcomingMilestone]] = [:]
    private var mockNotifications: [String: [AchievementNotification]] = [:]
    private var mockShares: [AchievementShare] = []
    
    // Publishers for testing
    private let achievementUpdateSubject = PassthroughSubject<AchievementUpdate, Error>()
    
    // Testing configuration
    var shouldThrowErrors = false
    var simulateNetworkDelay: TimeInterval = 0.1
    var unlockSuccessRate: Double = 1.0
    
    // Analytics tracking for testing
    private(set) var methodCallCounts: [String: Int] = [:]
    private(set) var lastMethodCall: String?
    private(set) var lastMethodParameters: [String: Any]?
    
    // MARK: - Initialization
    
    init() {
        setupMockData()
    }
    
    // MARK: - Achievement Management
    
    func getPlayerAchievements(playerId: String) async throws -> [PlayerAchievement] {
        trackMethodCall("getPlayerAchievements", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        return mockPlayerAchievements[playerId] ?? []
    }
    
    func getAvailableAchievements(for playerId: String) async throws -> [Achievement] {
        trackMethodCall("getAvailableAchievements", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        // Filter out already unlocked achievements
        let playerAchievements = mockPlayerAchievements[playerId] ?? []
        let unlockedIds = Set(playerAchievements.map { $0.achievementId })
        
        return mockAvailableAchievements.filter { !unlockedIds.contains($0.id) }
    }
    
    func getAchievementProgress(playerId: String, achievementId: String) async throws -> AchievementProgress? {
        trackMethodCall("getAchievementProgress", parameters: ["playerId": playerId, "achievementId": achievementId])
        
        if shouldThrowErrors {
            throw AchievementError.progressNotFound
        }
        
        await simulateDelay()
        
        // Return mock progress based on achievement ID
        let progress = generateMockProgress(for: achievementId)
        return progress
    }
    
    func unlockAchievement(playerId: String, achievementId: String, context: AchievementContext?) async throws -> AchievementUnlock {
        trackMethodCall("unlockAchievement", parameters: ["playerId": playerId, "achievementId": achievementId])
        
        if shouldThrowErrors || Double.random(in: 0...1) > unlockSuccessRate {
            throw AchievementError.unlockFailed("Mock unlock failed")
        }
        
        await simulateDelay()
        
        // Find the achievement
        guard let achievement = mockAvailableAchievements.first(where: { $0.id == achievementId }) else {
            throw AchievementError.achievementNotFound
        }
        
        // Check if already unlocked
        let existingAchievements = mockPlayerAchievements[playerId] ?? []
        if existingAchievements.contains(where: { $0.achievementId == achievementId }) {
            throw AchievementError.alreadyUnlocked
        }
        
        // Create unlock
        let unlock = AchievementUnlock(
            id: UUID().uuidString,
            achievementId: achievementId,
            playerId: playerId,
            unlockedAt: Date(),
            trigger: context?.sourceEvent.toAchievementTrigger() ?? .manualUnlock,
            context: context,
            rewards: achievement.rewards,
            isFirstTimeUnlock: !hasAnyPlayerUnlocked(achievementId: achievementId),
            celebrationTriggered: true
        )
        
        // Add to player's achievements
        let playerAchievement = PlayerAchievement(
            id: UUID().uuidString,
            achievementId: achievementId,
            playerId: playerId,
            unlockedAt: unlock.unlockedAt,
            progress: AchievementProgress(current: 100, target: 100, percentage: 100, lastUpdated: Date(), milestones: []),
            context: context,
            notificationShown: false,
            sharedAt: nil,
            celebrationTriggered: true
        )
        
        var playerAchievements = mockPlayerAchievements[playerId] ?? []
        playerAchievements.append(playerAchievement)
        mockPlayerAchievements[playerId] = playerAchievements
        
        // Send real-time update
        let update = AchievementUpdate(
            id: UUID().uuidString,
            playerId: playerId,
            updateType: .unlocked,
            achievementId: achievementId,
            data: ["tier": AnyCodable(achievement.tier.rawValue)],
            timestamp: unlock.unlockedAt
        )
        achievementUpdateSubject.send(update)
        
        return unlock
    }
    
    func processPlayerActivity(playerId: String, activity: PlayerActivity) async throws -> [AchievementUnlock] {
        trackMethodCall("processPlayerActivity", parameters: ["playerId": playerId, "activityType": activity.type.rawValue])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        var unlocks: [AchievementUnlock] = []
        
        // Simulate achievement triggers based on activity type
        let availableAchievements = try await getAvailableAchievements(for: playerId)
        let triggeredAchievements = availableAchievements.filter { achievement in
            shouldTriggerAchievement(achievement: achievement, activity: activity)
        }
        
        for achievement in triggeredAchievements.prefix(3) { // Limit to 3 unlocks per activity
            let context = AchievementContext(
                sourceEvent: activity.type.rawValue,
                additionalData: activity.data,
                timestamp: activity.timestamp,
                location: activity.location,
                courseId: activity.courseId,
                roundId: activity.roundId
            )
            
            do {
                let unlock = try await unlockAchievement(playerId: playerId, achievementId: achievement.id, context: context)
                unlocks.append(unlock)
            } catch {
                // Continue processing other achievements
            }
        }
        
        return unlocks
    }
    
    func validateAchievementUnlock(playerId: String, achievementId: String, context: AchievementContext) async throws -> Bool {
        trackMethodCall("validateAchievementUnlock", parameters: ["playerId": playerId, "achievementId": achievementId])
        
        if shouldThrowErrors {
            throw AchievementError.validationFailed
        }
        
        await simulateDelay()
        
        // Mock validation logic
        return Double.random(in: 0...1) > 0.1 // 90% validation success rate
    }
    
    // MARK: - Achievement Categories
    
    func getScoringAchievements(for playerId: String) async throws -> [PlayerAchievement] {
        trackMethodCall("getScoringAchievements", parameters: ["playerId": playerId])
        
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        return playerAchievements.filter { _ in
            // Would filter by category in real implementation
            true
        }
    }
    
    func getSocialAchievements(for playerId: String) async throws -> [PlayerAchievement] {
        trackMethodCall("getSocialAchievements", parameters: ["playerId": playerId])
        
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        return playerAchievements.filter { _ in
            true
        }
    }
    
    func getProgressAchievements(for playerId: String) async throws -> [PlayerAchievement] {
        trackMethodCall("getProgressAchievements", parameters: ["playerId": playerId])
        
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        return playerAchievements.filter { _ in
            true
        }
    }
    
    func getPremiumAchievements(for playerId: String) async throws -> [PlayerAchievement] {
        trackMethodCall("getPremiumAchievements", parameters: ["playerId": playerId])
        
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        return playerAchievements.filter { _ in
            true
        }
    }
    
    // MARK: - Badge System
    
    func getPlayerBadges(playerId: String) async throws -> PlayerBadgeCollection {
        trackMethodCall("getPlayerBadges", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        if let existing = mockBadges[playerId] {
            return existing
        }
        
        // Generate mock badge collection
        let badges = generateMockPlayerBadges(for: playerId)
        let collection = PlayerBadgeCollection(
            playerId: playerId,
            badges: badges,
            totalBadges: badges.count,
            completionPercentage: Double.random(in: 20...80),
            lastUpdated: Date()
        )
        
        mockBadges[playerId] = collection
        return collection
    }
    
    func checkBadgeProgression(playerId: String, category: BadgeCategory) async throws -> BadgeProgression {
        trackMethodCall("checkBadgeProgression", parameters: ["playerId": playerId, "category": category.rawValue])
        
        if shouldThrowErrors {
            throw AchievementError.badgeNotFound
        }
        
        await simulateDelay()
        
        return BadgeProgression(
            currentTier: .silver,
            nextTier: .gold,
            progressToNext: Double.random(in: 0.3...0.9),
            requirements: BadgeRequirements(tierRequirements: [:], prerequisites: [], exclusivityRules: []),
            canAdvance: true
        )
    }
    
    func awardBadgeTier(playerId: String, badgeId: String, tier: AchievementTier) async throws -> BadgeAward {
        trackMethodCall("awardBadgeTier", parameters: ["playerId": playerId, "badgeId": badgeId, "tier": tier.rawValue])
        
        if shouldThrowErrors {
            throw AchievementError.badgeAwardFailed("Mock error")
        }
        
        await simulateDelay()
        
        let award = BadgeAward(
            id: UUID().uuidString,
            badgeId: badgeId,
            playerId: playerId,
            tier: tier,
            awardedAt: Date(),
            previousTier: tier == .bronze ? nil : .bronze,
            celebration: BadgeCelebration(
                tier: tier,
                hapticPattern: tier.hapticPattern,
                visualEffects: [VisualEffect(type: "confetti", duration: 2.0)],
                duration: 2.0
            )
        )
        
        // Update player's badge collection
        updatePlayerBadgeCollection(playerId: playerId, badgeId: badgeId, tier: tier)
        
        return award
    }
    
    func getBadgeStatistics(badgeId: String) async throws -> BadgeStatistics {
        trackMethodCall("getBadgeStatistics", parameters: ["badgeId": badgeId])
        
        if shouldThrowErrors {
            throw AchievementError.statisticsCalculationFailed("Mock error")
        }
        
        await simulateDelay()
        
        return BadgeStatistics(
            badgeId: badgeId,
            totalAwards: Int.random(in: 100...1000),
            tierDistribution: [
                .bronze: Int.random(in: 50...200),
                .silver: Int.random(in: 30...150),
                .gold: Int.random(in: 10...100),
                .platinum: Int.random(in: 5...50),
                .diamond: Int.random(in: 1...20)
            ],
            averageTimeToUnlock: TimeInterval.random(in: 86400...2592000), // 1 day to 30 days
            rarity: BadgeRarity(
                level: .uncommon,
                unlockPercentage: Double.random(in: 5...25),
                estimatedPlayers: Int.random(in: 100...500)
            ),
            popularityRank: Int.random(in: 1...50)
        )
    }
    
    // MARK: - Achievement Chains & Linked Accomplishments
    
    func getAchievementChains(for playerId: String) async throws -> [AchievementChain] {
        trackMethodCall("getAchievementChains", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        return mockChains
    }
    
    func checkChainProgression(playerId: String, chainId: String) async throws -> ChainProgression {
        trackMethodCall("checkChainProgression", parameters: ["playerId": playerId, "chainId": chainId])
        
        if shouldThrowErrors {
            throw AchievementError.chainNotFound
        }
        
        await simulateDelay()
        
        guard let chain = mockChains.first(where: { $0.id == chainId }) else {
            throw AchievementError.chainNotFound
        }
        
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        let unlockedIds = Set(playerAchievements.map { $0.achievementId })
        let completedAchievements = chain.achievements.filter { unlockedIds.contains($0) }
        
        return ChainProgression(
            chainId: chainId,
            currentPosition: completedAchievements.count,
            totalSteps: chain.achievements.count,
            completedAchievements: completedAchievements,
            nextAchievement: chain.achievements.first { !unlockedIds.contains($0) },
            canAdvance: completedAchievements.count < chain.achievements.count,
            estimatedCompletion: Date().addingTimeInterval(86400 * 7) // 1 week
        )
    }
    
    func processChainAdvancement(playerId: String, chainId: String) async throws -> ChainAdvancement? {
        trackMethodCall("processChainAdvancement", parameters: ["playerId": playerId, "chainId": chainId])
        
        if shouldThrowErrors {
            throw AchievementError.chainNotFound
        }
        
        await simulateDelay()
        
        let progression = try await checkChainProgression(playerId: playerId, chainId: chainId)
        
        guard progression.canAdvance, let nextAchievementId = progression.nextAchievement else {
            return nil
        }
        
        // Simulate advancement
        return ChainAdvancement(
            id: UUID().uuidString,
            chainId: chainId,
            playerId: playerId,
            advancedAt: Date(),
            newPosition: progression.currentPosition + 1,
            unlockedAchievement: nextAchievementId,
            chainCompleted: progression.currentPosition + 1 >= progression.totalSteps,
            rewards: nil
        )
    }
    
    func getLinkedAchievements(achievementId: String) async throws -> [Achievement] {
        trackMethodCall("getLinkedAchievements", parameters: ["achievementId": achievementId])
        
        await simulateDelay()
        
        // Return subset of available achievements as linked
        return Array(mockAvailableAchievements.prefix(2))
    }
    
    // MARK: - Milestone Celebrations
    
    func trackMilestoneProgress(playerId: String, milestone: GameMilestone, progress: Double) async throws {
        trackMethodCall("trackMilestoneProgress", parameters: ["playerId": playerId, "milestone": milestone.rawValue, "progress": progress])
        
        if shouldThrowErrors {
            throw AchievementError.milestoneTrackingFailed("Mock error")
        }
        
        await simulateDelay()
        
        // Update milestone progress in mock data
        updateMilestoneProgress(playerId: playerId, milestone: milestone, progress: progress)
    }
    
    func triggerMilestoneCelebration(playerId: String, milestone: GameMilestone) async throws -> MilestoneCelebration {
        trackMethodCall("triggerMilestoneCelebration", parameters: ["playerId": playerId, "milestone": milestone.rawValue])
        
        if shouldThrowErrors {
            throw AchievementError.milestoneTrackingFailed("Mock error")
        }
        
        await simulateDelay()
        
        return MilestoneCelebration(
            id: UUID().uuidString,
            milestone: milestone,
            playerId: playerId,
            celebratedAt: Date(),
            rewards: MilestoneRewards(
                experienceBonus: 500,
                specialBadges: ["Milestone Badge"],
                unlockableContent: [],
                celebrationPackage: CelebrationPackage(theme: "milestone", effects: [], duration: 3.0)
            ),
            hapticTriggered: true,
            sharedAutomatically: false
        )
    }
    
    func getUpcomingMilestones(for playerId: String) async throws -> [UpcomingMilestone] {
        trackMethodCall("getUpcomingMilestones", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        return mockMilestones[playerId] ?? generateMockUpcomingMilestones(for: playerId)
    }
    
    func checkMilestoneCelebrationConditions(playerId: String, milestone: GameMilestone) async throws -> Bool {
        trackMethodCall("checkMilestoneCelebrationConditions", parameters: ["playerId": playerId, "milestone": milestone.rawValue])
        
        await simulateDelay()
        
        return Double.random(in: 0...1) > 0.5 // 50% chance of celebration conditions being met
    }
    
    // MARK: - Service Integration for Automatic Achievement Processing
    
    func processScoreAchievements(playerId: String, scorecard: ScorecardEntry, performance: PerformanceMetrics) async throws -> [AchievementUnlock] {
        trackMethodCall("processScoreAchievements", parameters: ["playerId": playerId, "score": scorecard.totalScore])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        let activity = PlayerActivity(
            type: .scoreSubmission,
            playerId: playerId,
            data: ["score": AnyCodable(scorecard.totalScore)],
            timestamp: scorecard.date,
            location: nil,
            courseId: scorecard.courseId,
            roundId: scorecard.id
        )
        
        return try await processPlayerActivity(playerId: playerId, activity: activity)
    }
    
    func processSocialAchievements(playerId: String, challengeResult: ChallengeResult, socialMetrics: SocialMetrics) async throws -> [AchievementUnlock] {
        trackMethodCall("processSocialAchievements", parameters: ["playerId": playerId, "position": challengeResult.position])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        let activity = PlayerActivity(
            type: .challengeCompletion,
            playerId: playerId,
            data: ["position": AnyCodable(challengeResult.position)],
            timestamp: challengeResult.completedAt,
            location: nil,
            courseId: nil,
            roundId: nil
        )
        
        return try await processPlayerActivity(playerId: playerId, activity: activity)
    }
    
    func processLeaderboardAchievements(playerId: String, leaderboardResult: LeaderboardResult, positionMetrics: PositionMetrics) async throws -> [AchievementUnlock] {
        trackMethodCall("processLeaderboardAchievements", parameters: ["playerId": playerId, "position": leaderboardResult.position])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        let activity = PlayerActivity(
            type: .leaderboardPosition,
            playerId: playerId,
            data: ["position": AnyCodable(leaderboardResult.position)],
            timestamp: leaderboardResult.updatedAt,
            location: nil,
            courseId: nil,
            roundId: nil
        )
        
        return try await processPlayerActivity(playerId: playerId, activity: activity)
    }
    
    func processStreakAchievements(playerId: String, streakData: StreakData) async throws -> [AchievementUnlock] {
        trackMethodCall("processStreakAchievements", parameters: ["playerId": playerId, "parStreak": streakData.parStreak])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        let activity = PlayerActivity(
            type: .streakAchievement,
            playerId: playerId,
            data: ["parStreak": AnyCodable(streakData.parStreak)],
            timestamp: Date(),
            location: nil,
            courseId: nil,
            roundId: nil
        )
        
        return try await processPlayerActivity(playerId: playerId, activity: activity)
    }
    
    // MARK: - Real-time Achievement Processing
    
    func subscribeToAchievementUpdates(playerId: String) -> AnyPublisher<AchievementUpdate, Error> {
        trackMethodCall("subscribeToAchievementUpdates", parameters: ["playerId": playerId])
        
        return achievementUpdateSubject
            .filter { $0.playerId == playerId }
            .eraseToAnyPublisher()
    }
    
    func processBackgroundAchievements(playerId: String) async throws -> BackgroundProcessingResult {
        trackMethodCall("processBackgroundAchievements", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        let mockActivities = generateMockRecentActivities(for: playerId)
        var newUnlocks: [AchievementUnlock] = []
        
        for activity in mockActivities {
            let unlocks = try await processPlayerActivity(playerId: playerId, activity: activity)
            newUnlocks.append(contentsOf: unlocks)
        }
        
        return BackgroundProcessingResult(
            processedAchievements: newUnlocks.map { $0.achievementId },
            newUnlocks: newUnlocks,
            progressUpdates: [],
            processingTime: simulateNetworkDelay,
            errors: []
        )
    }
    
    func getAchievementNotificationQueue(playerId: String) async throws -> [AchievementNotification] {
        trackMethodCall("getAchievementNotificationQueue", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        return mockNotifications[playerId] ?? generateMockNotifications(for: playerId)
    }
    
    func markNotificationDisplayed(playerId: String, notificationId: String) async throws {
        trackMethodCall("markNotificationDisplayed", parameters: ["playerId": playerId, "notificationId": notificationId])
        
        if shouldThrowErrors {
            throw AchievementError.notificationUpdateFailed("Mock error")
        }
        
        await simulateDelay()
        
        // Update notification in mock data
        updateNotificationDisplayed(playerId: playerId, notificationId: notificationId)
    }
    
    // MARK: - Achievement Analytics & Engagement Tracking
    
    func getPlayerEngagementMetrics(playerId: String) async throws -> PlayerEngagementMetrics {
        trackMethodCall("getPlayerEngagementMetrics", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        
        return PlayerEngagementMetrics(
            playerId: playerId,
            totalAchievements: playerAchievements.count,
            achievementsByCategory: [
                .scoring: Int.random(in: 5...15),
                .social: Int.random(in: 2...8),
                .progress: Int.random(in: 3...10),
                .premium: Int.random(in: 0...5)
            ],
            averageTimeToUnlock: TimeInterval.random(in: 86400...604800), // 1 day to 1 week
            engagementScore: Double.random(in: 40...95),
            lastActivityDate: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400 * 7)),
            streakDays: Int.random(in: 1...30)
        )
    }
    
    func trackAchievementInteraction(playerId: String, achievementId: String, interaction: AchievementInteraction) async throws {
        trackMethodCall("trackAchievementInteraction", parameters: ["playerId": playerId, "achievementId": achievementId, "interaction": interaction.rawValue])
        
        if shouldThrowErrors {
            throw AchievementError.trackingFailed("Mock error")
        }
        
        await simulateDelay()
        
        // Track interaction in mock analytics
        recordInteraction(playerId: playerId, achievementId: achievementId, interaction: interaction)
    }
    
    func getAchievementStatistics() async throws -> AchievementStatistics {
        trackMethodCall("getAchievementStatistics", parameters: [:])
        
        if shouldThrowErrors {
            throw AchievementError.statisticsCalculationFailed("Mock error")
        }
        
        await simulateDelay()
        
        return AchievementStatistics(
            totalAchievements: mockAvailableAchievements.count,
            totalUnlocks: mockPlayerAchievements.values.flatMap { $0 }.count,
            averageUnlocksPerPlayer: Double.random(in: 8...25),
            mostPopularAchievements: generateMockPopularAchievements(),
            rarestAchievements: generateMockRareAchievements(),
            unlockTrends: UnlockTrends(
                dailyUnlocks: generateMockDailyUnlocks(),
                trendDirection: "increasing",
                growthRate: Double.random(in: 0.02...0.15)
            ),
            categoryDistribution: [
                .scoring: 0.4,
                .social: 0.25,
                .progress: 0.2,
                .premium: 0.15
            ]
        )
    }
    
    func getAchievementJourney(playerId: String) async throws -> AchievementJourney {
        trackMethodCall("getAchievementJourney", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        
        let timeline = playerAchievements.map { achievement in
            JourneyEvent(
                timestamp: achievement.unlockedAt,
                type: "achievement_unlocked",
                description: "Unlocked achievement: \(achievement.achievementId)"
            )
        }.sorted { $0.timestamp < $1.timestamp }
        
        return AchievementJourney(
            playerId: playerId,
            timeline: timeline,
            totalProgress: Double.random(in: 15...75),
            milestones: generateMockJourneyMilestones(from: playerAchievements),
            predictions: generateMockFutureAchievements(),
            personalBests: generateMockPersonalBests()
        )
    }
    
    // MARK: - Achievement Rarity & Exclusive Unlocks
    
    func getRareAchievements() async throws -> [RareAchievement] {
        trackMethodCall("getRareAchievements", parameters: [:])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        return generateMockRareAchievements()
    }
    
    func checkExclusiveAchievementEligibility(playerId: String, achievementId: String) async throws -> Bool {
        trackMethodCall("checkExclusiveAchievementEligibility", parameters: ["playerId": playerId, "achievementId": achievementId])
        
        if shouldThrowErrors {
            throw AchievementError.validationFailed
        }
        
        await simulateDelay()
        
        return Double.random(in: 0...1) > 0.3 // 70% eligibility rate
    }
    
    func getSeasonalAchievements(season: AchievementSeason?) async throws -> [SeasonalAchievement] {
        trackMethodCall("getSeasonalAchievements", parameters: ["season": season?.rawValue ?? "all"])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        return generateMockSeasonalAchievements(for: season)
    }
    
    func processLimitedTimeAchievements(playerId: String) async throws -> [LimitedTimeOpportunity] {
        trackMethodCall("processLimitedTimeAchievements", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        return generateMockLimitedTimeOpportunities()
    }
    
    // MARK: - Haptic Feedback Integration
    
    func triggerAchievementHaptic(achievement: Achievement, tier: AchievementTier) async {
        trackMethodCall("triggerAchievementHaptic", parameters: ["achievementId": achievement.id, "tier": tier.rawValue])
        
        // Simulate haptic trigger
        await simulateDelay()
    }
    
    func triggerSynchronizedAchievementCelebration(achievement: Achievement, tier: AchievementTier) async {
        trackMethodCall("triggerSynchronizedAchievementCelebration", parameters: ["achievementId": achievement.id, "tier": tier.rawValue])
        
        // Simulate synchronized haptic celebration
        await simulateDelay()
    }
    
    func triggerMilestoneHaptics(milestone: GameMilestone, progress: Double) async {
        trackMethodCall("triggerMilestoneHaptics", parameters: ["milestone": milestone.rawValue, "progress": progress])
        
        // Simulate milestone haptics
        await simulateDelay()
    }
    
    func triggerBadgeHaptics(badge: Badge, tier: AchievementTier) async {
        trackMethodCall("triggerBadgeHaptics", parameters: ["badgeId": badge.id, "tier": tier.rawValue])
        
        // Simulate badge haptics
        await simulateDelay()
    }
    
    // MARK: - Achievement Sharing & Social Features
    
    func shareAchievement(playerId: String, achievementId: String, shareOptions: AchievementShareOptions) async throws -> AchievementShare {
        trackMethodCall("shareAchievement", parameters: ["playerId": playerId, "achievementId": achievementId])
        
        if shouldThrowErrors {
            throw AchievementError.shareFailed("Mock error")
        }
        
        await simulateDelay()
        
        let share = AchievementShare(
            id: UUID().uuidString,
            achievementId: achievementId,
            playerId: playerId,
            sharedAt: Date(),
            platform: shareOptions.platforms.first ?? .internal,
            customMessage: shareOptions.customMessage,
            reactions: generateMockShareReactions()
        )
        
        mockShares.append(share)
        return share
    }
    
    func getFriendAchievementActivities(playerId: String) async throws -> [FriendAchievementActivity] {
        trackMethodCall("getFriendAchievementActivities", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        return generateMockFriendActivities()
    }
    
    func compareAchievements(playerId: String, friendId: String) async throws -> AchievementComparison {
        trackMethodCall("compareAchievements", parameters: ["playerId": playerId, "friendId": friendId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        let friendAchievements = try await getPlayerAchievements(playerId: friendId)
        
        let playerIds = Set(playerAchievements.map { $0.achievementId })
        let friendIds = Set(friendAchievements.map { $0.achievementId })
        
        return AchievementComparison(
            playerId: playerId,
            friendId: friendId,
            playerAchievements: playerAchievements.count,
            friendAchievements: friendAchievements.count,
            commonAchievements: Array(playerIds.intersection(friendIds)),
            playerExclusive: Array(playerIds.subtracting(friendIds)),
            friendExclusive: Array(friendIds.subtracting(playerIds)),
            comparisonScore: Double.random(in: 60...90)
        )
    }
    
    func getAchievementLeaderboard(playerId: String, category: AchievementCategory?) async throws -> AchievementLeaderboard {
        trackMethodCall("getAchievementLeaderboard", parameters: ["playerId": playerId, "category": category?.rawValue ?? "all"])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        return AchievementLeaderboard(
            category: category,
            entries: generateMockLeaderboardEntries(),
            playerPosition: Int.random(in: 5...25),
            totalPlayers: Int.random(in: 100...500),
            lastUpdated: Date()
        )
    }
    
    // MARK: - Performance & Optimization
    
    func preloadAchievementData(playerId: String) async throws {
        trackMethodCall("preloadAchievementData", parameters: ["playerId": playerId])
        
        if shouldThrowErrors {
            throw AchievementError.fetchFailed("Mock error")
        }
        
        await simulateDelay()
        
        // Simulate preloading
        _ = try await getPlayerAchievements(playerId: playerId)
        _ = try await getAvailableAchievements(for: playerId)
        _ = try await getPlayerBadges(playerId: playerId)
    }
    
    func cachePlayerAchievements(playerId: String) async throws {
        trackMethodCall("cachePlayerAchievements", parameters: ["playerId": playerId])
        
        await simulateDelay()
        
        // Simulate caching
    }
    
    func clearAchievementCache(playerId: String) async throws {
        trackMethodCall("clearAchievementCache", parameters: ["playerId": playerId])
        
        await simulateDelay()
        
        // Simulate cache clearing
    }
    
    func getSystemPerformanceMetrics() async throws -> AchievementSystemMetrics {
        trackMethodCall("getSystemPerformanceMetrics", parameters: [:])
        
        await simulateDelay()
        
        return AchievementSystemMetrics(
            totalProcessingTime: simulateNetworkDelay * Double(methodCallCounts.values.reduce(0, +)),
            averageResponseTime: simulateNetworkDelay,
            cacheHitRate: Double.random(in: 0.7...0.95),
            backgroundProcessingRate: Double.random(in: 0.1...0.3),
            errorRate: shouldThrowErrors ? 1.0 : 0.0,
            activeSubscriptions: Int.random(in: 0...50)
        )
    }
}

// MARK: - Testing Utilities

extension MockAchievementService {
    
    // MARK: - Test Configuration
    
    func reset() {
        mockPlayerAchievements.removeAll()
        mockBadges.removeAll()
        mockNotifications.removeAll()
        mockShares.removeAll()
        methodCallCounts.removeAll()
        lastMethodCall = nil
        lastMethodParameters = nil
        shouldThrowErrors = false
        unlockSuccessRate = 1.0
    }
    
    func setPlayerAchievements(playerId: String, achievements: [PlayerAchievement]) {
        mockPlayerAchievements[playerId] = achievements
    }
    
    func addAvailableAchievement(_ achievement: Achievement) {
        mockAvailableAchievements.append(achievement)
    }
    
    func simulateAchievementUnlock(playerId: String, achievementId: String) {
        Task {
            let update = AchievementUpdate(
                id: UUID().uuidString,
                playerId: playerId,
                updateType: .unlocked,
                achievementId: achievementId,
                data: [:],
                timestamp: Date()
            )
            achievementUpdateSubject.send(update)
        }
    }
    
    // MARK: - Test Verification
    
    func getMethodCallCount(_ methodName: String) -> Int {
        return methodCallCounts[methodName] ?? 0
    }
    
    func wasMethodCalled(_ methodName: String) -> Bool {
        return getMethodCallCount(methodName) > 0
    }
    
    func getLastMethodCall() -> String? {
        return lastMethodCall
    }
    
    func getLastMethodParameters() -> [String: Any]? {
        return lastMethodParameters
    }
}

// MARK: - Private Helper Methods

private extension MockAchievementService {
    
    func trackMethodCall(_ methodName: String, parameters: [String: Any]) {
        methodCallCounts[methodName] = (methodCallCounts[methodName] ?? 0) + 1
        lastMethodCall = methodName
        lastMethodParameters = parameters
    }
    
    func simulateDelay() async {
        if simulateNetworkDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(simulateNetworkDelay * 1_000_000_000))
        }
    }
    
    func setupMockData() {
        // Generate mock available achievements
        mockAvailableAchievements = generateMockAchievements()
        
        // Generate mock chains
        mockChains = generateMockChains()
    }
    
    func generateMockAchievements() -> [Achievement] {
        let achievements = [
            createMockAchievement(id: "first_round", name: "First Round", category: .milestone, tier: .bronze),
            createMockAchievement(id: "break_90", name: "Break 90", category: .scoring, tier: .silver),
            createMockAchievement(id: "first_birdie", name: "First Birdie", category: .scoring, tier: .gold),
            createMockAchievement(id: "social_butterfly", name: "Social Butterfly", category: .social, tier: .silver),
            createMockAchievement(id: "consistent_player", name: "Consistent Player", category: .progress, tier: .gold),
            createMockAchievement(id: "premium_member", name: "Premium Member", category: .premium, tier: .platinum),
            createMockAchievement(id: "eagle_eye", name: "Eagle Eye", category: .scoring, tier: .diamond),
            createMockAchievement(id: "tournament_champion", name: "Tournament Champion", category: .tournament, tier: .diamond)
        ]
        
        return achievements
    }
    
    func createMockAchievement(id: String, name: String, category: AchievementCategory, tier: AchievementTier) -> Achievement {
        return Achievement(
            id: id,
            name: name,
            description: "Mock achievement: \(name)",
            category: category,
            tier: tier,
            badgeImageUrl: "https://example.com/badge/\(id).png",
            requirements: AchievementRequirements(
                primary: RequirementCriteria(type: .score, value: 80, operator: .lessThan, dataSource: "scorecard", validationRules: []),
                secondary: [],
                minimumLevel: nil,
                timeWindow: nil,
                courseRestrictions: nil,
                groupRequirements: nil
            ),
            rewards: AchievementRewards(
                experiencePoints: tier.experiencePoints,
                badges: [],
                premiumFeatures: [],
                socialRecognition: SocialRecognition(publicAnnouncement: true, leaderboardHighlight: true, friendNotification: true),
                customRewards: []
            ),
            rarity: AchievementRarity.allCases.randomElement() ?? .common,
            isHidden: Bool.random(),
            isLimitedTime: category == .seasonal,
            seasonalInfo: category == .seasonal ? SeasonalInfo(season: .summer, startDate: Date(), endDate: Date().addingTimeInterval(86400 * 30)) : nil,
            createdAt: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400 * 365)),
            updatedAt: Date()
        )
    }
    
    func generateMockChains() -> [AchievementChain] {
        return [
            AchievementChain(
                id: "beginner_journey",
                name: "Beginner's Journey",
                description: "Complete the beginner's path to golf mastery",
                achievements: ["first_round", "break_90", "first_birdie"],
                requiresSequential: true,
                rewards: ChainRewards(completionBonuses: [], progressRewards: [], exclusiveUnlocks: []),
                isComplete: false,
                completedAt: nil
            ),
            AchievementChain(
                id: "social_master",
                name: "Social Master",
                description: "Become a social golf champion",
                achievements: ["social_butterfly", "tournament_champion"],
                requiresSequential: false,
                rewards: ChainRewards(completionBonuses: [], progressRewards: [], exclusiveUnlocks: []),
                isComplete: false,
                completedAt: nil
            )
        ]
    }
    
    func generateMockProgress(for achievementId: String) -> AchievementProgress {
        let current = Double.random(in: 10...95)
        let target = 100.0
        
        return AchievementProgress(
            current: current,
            target: target,
            percentage: (current / target) * 100,
            lastUpdated: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400)),
            milestones: [
                ProgressMilestone(threshold: 25, reached: current >= 25, reachedAt: current >= 25 ? Date() : nil, reward: nil),
                ProgressMilestone(threshold: 50, reached: current >= 50, reachedAt: current >= 50 ? Date() : nil, reward: nil),
                ProgressMilestone(threshold: 75, reached: current >= 75, reachedAt: current >= 75 ? Date() : nil, reward: nil)
            ]
        )
    }
    
    func hasAnyPlayerUnlocked(achievementId: String) -> Bool {
        return mockPlayerAchievements.values.flatMap { $0 }.contains { $0.achievementId == achievementId }
    }
    
    func shouldTriggerAchievement(achievement: Achievement, activity: PlayerActivity) -> Bool {
        // Mock logic for triggering achievements based on activity
        switch (achievement.category, activity.type) {
        case (.scoring, .scoreSubmission):
            return Double.random(in: 0...1) > 0.7
        case (.social, .challengeCompletion):
            return Double.random(in: 0...1) > 0.6
        case (.milestone, _):
            return Double.random(in: 0...1) > 0.8
        case (.streak, .streakAchievement):
            return Double.random(in: 0...1) > 0.5
        default:
            return Double.random(in: 0...1) > 0.9
        }
    }
    
    func generateMockPlayerBadges(for playerId: String) -> [PlayerBadge] {
        let badgeCategories = BadgeCategory.allCases
        let randomCount = Int.random(in: 2...6)
        
        return Array(badgeCategories.shuffled().prefix(randomCount)).map { category in
            PlayerBadge(
                id: UUID().uuidString,
                badgeId: "badge_\(category.rawValue)",
                playerId: playerId,
                tier: AchievementTier.allCases.randomElement() ?? .bronze,
                acquiredAt: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400 * 30)),
                progression: BadgeProgression(
                    currentTier: .silver,
                    nextTier: .gold,
                    progressToNext: Double.random(in: 0.2...0.8),
                    requirements: BadgeRequirements(tierRequirements: [:], prerequisites: [], exclusivityRules: []),
                    canAdvance: true
                )
            )
        }
    }
    
    func updatePlayerBadgeCollection(playerId: String, badgeId: String, tier: AchievementTier) {
        var collection = mockBadges[playerId] ?? PlayerBadgeCollection(
            playerId: playerId,
            badges: [],
            totalBadges: 0,
            completionPercentage: 0,
            lastUpdated: Date()
        )
        
        // Update or add badge
        if let index = collection.badges.firstIndex(where: { $0.badgeId == badgeId }) {
            collection.badges[index] = PlayerBadge(
                id: collection.badges[index].id,
                badgeId: badgeId,
                playerId: playerId,
                tier: tier,
                acquiredAt: collection.badges[index].acquiredAt,
                progression: collection.badges[index].progression
            )
        } else {
            let newBadge = PlayerBadge(
                id: UUID().uuidString,
                badgeId: badgeId,
                playerId: playerId,
                tier: tier,
                acquiredAt: Date(),
                progression: BadgeProgression(
                    currentTier: tier,
                    nextTier: nil,
                    progressToNext: 0,
                    requirements: BadgeRequirements(tierRequirements: [:], prerequisites: [], exclusivityRules: []),
                    canAdvance: false
                )
            )
            collection.badges.append(newBadge)
        }
        
        collection.totalBadges = collection.badges.count
        collection.lastUpdated = Date()
        mockBadges[playerId] = collection
    }
    
    func updateMilestoneProgress(playerId: String, milestone: GameMilestone, progress: Double) {
        var milestones = mockMilestones[playerId] ?? []
        
        if let index = milestones.firstIndex(where: { $0.milestone == milestone }) {
            milestones[index] = UpcomingMilestone(
                id: milestones[index].id,
                milestone: milestone,
                progress: progress,
                estimatedCompletion: milestones[index].estimatedCompletion,
                requirements: milestones[index].requirements,
                rewards: milestones[index].rewards
            )
        } else {
            let newMilestone = UpcomingMilestone(
                id: UUID().uuidString,
                milestone: milestone,
                progress: progress,
                estimatedCompletion: Date().addingTimeInterval(86400 * 7),
                requirements: MilestoneRequirements(targetValue: 1.0, timeframe: nil, conditions: [], validationCriteria: []),
                rewards: MilestoneRewards(experienceBonus: 500, specialBadges: [], unlockableContent: [], celebrationPackage: CelebrationPackage(theme: "milestone", effects: [], duration: 3.0))
            )
            milestones.append(newMilestone)
        }
        
        mockMilestones[playerId] = milestones
    }
    
    func generateMockUpcomingMilestones(for playerId: String) -> [UpcomingMilestone] {
        let milestones = GameMilestone.allCases.shuffled().prefix(3)
        
        return milestones.map { milestone in
            UpcomingMilestone(
                id: UUID().uuidString,
                milestone: milestone,
                progress: Double.random(in: 0.2...0.9),
                estimatedCompletion: Date().addingTimeInterval(TimeInterval.random(in: 86400...86400 * 30)),
                requirements: MilestoneRequirements(targetValue: 1.0, timeframe: nil, conditions: [], validationCriteria: []),
                rewards: MilestoneRewards(experienceBonus: Int.random(in: 100...1000), specialBadges: [], unlockableContent: [], celebrationPackage: CelebrationPackage(theme: "milestone", effects: [], duration: 3.0))
            )
        }
    }
    
    func generateMockNotifications(for playerId: String) -> [AchievementNotification] {
        let count = Int.random(in: 1...5)
        
        return (0..<count).map { index in
            AchievementNotification(
                id: UUID().uuidString,
                playerId: playerId,
                achievementId: mockAvailableAchievements.randomElement()?.id ?? "mock_achievement",
                type: NotificationType.allCases.randomElement() ?? .achievement,
                priority: NotificationPriority.allCases.randomElement() ?? .medium,
                createdAt: Date().addingTimeInterval(-TimeInterval(index * 3600)),
                displayedAt: nil,
                data: [:]
            )
        }
    }
    
    func updateNotificationDisplayed(playerId: String, notificationId: String) {
        guard var notifications = mockNotifications[playerId] else { return }
        
        if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
            notifications[index] = AchievementNotification(
                id: notifications[index].id,
                playerId: notifications[index].playerId,
                achievementId: notifications[index].achievementId,
                type: notifications[index].type,
                priority: notifications[index].priority,
                createdAt: notifications[index].createdAt,
                displayedAt: Date(),
                data: notifications[index].data
            )
            
            mockNotifications[playerId] = notifications
        }
    }
    
    func generateMockRecentActivities(for playerId: String) -> [PlayerActivity] {
        let activities = [
            PlayerActivity(type: .scoreSubmission, playerId: playerId, data: ["score": AnyCodable(85)], timestamp: Date().addingTimeInterval(-3600), location: nil, courseId: "course1", roundId: "round1"),
            PlayerActivity(type: .challengeCompletion, playerId: playerId, data: ["position": AnyCodable(3)], timestamp: Date().addingTimeInterval(-7200), location: nil, courseId: nil, roundId: nil),
            PlayerActivity(type: .leaderboardPosition, playerId: playerId, data: ["position": AnyCodable(15)], timestamp: Date().addingTimeInterval(-10800), location: nil, courseId: nil, roundId: nil)
        ]
        
        return Array(activities.shuffled().prefix(Int.random(in: 1...3)))
    }
    
    func recordInteraction(playerId: String, achievementId: String, interaction: AchievementInteraction) {
        // Record interaction for analytics (mock implementation)
    }
    
    // MARK: - Mock Data Generators
    
    func generateMockPopularAchievements() -> [AchievementPopularity] {
        return mockAvailableAchievements.shuffled().prefix(5).map { achievement in
            AchievementPopularity(
                achievementId: achievement.id,
                unlockCount: Int.random(in: 100...1000),
                popularityScore: Double.random(in: 70...95)
            )
        }
    }
    
    func generateMockRareAchievements() -> [RareAchievement] {
        return mockAvailableAchievements.filter { $0.rarity == .rare || $0.rarity == .epic || $0.rarity == .legendary }.map { achievement in
            RareAchievement(
                id: achievement.id,
                achievement: achievement,
                unlockRate: Double.random(in: 0.01...0.05),
                totalUnlocks: Int.random(in: 5...50),
                estimatedRarity: achievement.rarity,
                exclusivityFactor: Double.random(in: 0.8...0.99)
            )
        }
    }
    
    func generateMockDailyUnlocks() -> [Date: Int] {
        var dailyUnlocks: [Date: Int] = [:]
        let calendar = Calendar.current
        
        for i in 0..<30 {
            let date = calendar.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            dailyUnlocks[date] = Int.random(in: 5...50)
        }
        
        return dailyUnlocks
    }
    
    func generateMockJourneyMilestones(from achievements: [PlayerAchievement]) -> [JourneyMilestone] {
        return achievements.prefix(3).map { achievement in
            JourneyMilestone(
                milestone: achievement.achievementId,
                achievedAt: achievement.unlockedAt,
                significance: "Major achievement milestone"
            )
        }
    }
    
    func generateMockFutureAchievements() -> [FutureAchievement] {
        return mockAvailableAchievements.shuffled().prefix(3).map { achievement in
            FutureAchievement(
                achievementId: achievement.id,
                estimatedDate: Date().addingTimeInterval(TimeInterval.random(in: 86400 * 7...86400 * 90)),
                probability: Double.random(in: 0.4...0.9)
            )
        }
    }
    
    func generateMockPersonalBests() -> [PersonalBest] {
        return [
            PersonalBest(category: "Best Score", value: 78, achievedAt: Date().addingTimeInterval(-86400 * 15)),
            PersonalBest(category: "Longest Streak", value: 12, achievedAt: Date().addingTimeInterval(-86400 * 30)),
            PersonalBest(category: "Most Birdies", value: 4, achievedAt: Date().addingTimeInterval(-86400 * 7))
        ]
    }
    
    func generateMockSeasonalAchievements(for season: AchievementSeason?) -> [SeasonalAchievement] {
        let seasonalAchievements = mockAvailableAchievements.filter { $0.isLimitedTime }
        
        return seasonalAchievements.map { achievement in
            SeasonalAchievement(
                id: achievement.id,
                achievement: achievement,
                season: season ?? .summer,
                startDate: Date().addingTimeInterval(-86400 * 10),
                endDate: Date().addingTimeInterval(86400 * 20),
                isActive: true,
                completionBonus: SeasonalBonus(multiplier: 2.0, bonusRewards: ["Seasonal Badge"])
            )
        }
    }
    
    func generateMockLimitedTimeOpportunities() -> [LimitedTimeOpportunity] {
        return mockAvailableAchievements.filter { $0.isLimitedTime }.prefix(2).map { achievement in
            LimitedTimeOpportunity(
                id: achievement.id,
                achievementId: achievement.id,
                timeRemaining: TimeInterval.random(in: 86400...86400 * 7),
                requiredActions: [
                    RequiredAction(action: "Play rounds", target: 5, current: Double.random(in: 1...4)),
                    RequiredAction(action: "Achieve birdies", target: 3, current: Double.random(in: 0...2))
                ],
                currentProgress: Double.random(in: 0.3...0.8),
                estimatedDifficulty: DifficultyLevel.allCases.randomElement() ?? .medium
            )
        }
    }
    
    func generateMockShareReactions() -> [ShareReaction] {
        return [
            ShareReaction(playerId: "friend1", reaction: "👏", timestamp: Date().addingTimeInterval(-3600)),
            ShareReaction(playerId: "friend2", reaction: "🔥", timestamp: Date().addingTimeInterval(-1800)),
            ShareReaction(playerId: "friend3", reaction: "⭐", timestamp: Date().addingTimeInterval(-900))
        ]
    }
    
    func generateMockFriendActivities() -> [FriendAchievementActivity] {
        let friendIds = ["friend1", "friend2", "friend3", "friend4"]
        
        return friendIds.shuffled().prefix(3).map { friendId in
            FriendAchievementActivity(
                id: UUID().uuidString,
                friendId: friendId,
                friendName: "Friend \(friendId)",
                achievementId: mockAvailableAchievements.randomElement()?.id ?? "mock_achievement",
                activityType: ActivityType.allCases.randomElement() ?? .unlocked,
                activityDate: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400 * 7)),
                isRecent: Bool.random()
            )
        }
    }
    
    func generateMockLeaderboardEntries() -> [LeaderboardEntry] {
        let count = Int.random(in: 10...20)
        
        return (1...count).map { position in
            LeaderboardEntry(
                playerId: "player\(position)",
                playerName: "Player \(position)",
                achievements: Int.random(in: 5...50),
                position: position
            )
        }
    }
}

// MARK: - Extensions

private extension AchievementTier {
    var experiencePoints: Int {
        switch self {
        case .bronze: return 100
        case .silver: return 250
        case .gold: return 500
        case .platinum: return 1000
        case .diamond: return 2000
        }
    }
}

private extension String {
    func toAchievementTrigger() -> AchievementTrigger {
        return AchievementTrigger(rawValue: self) ?? .systemProcessing
    }
}