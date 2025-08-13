import Foundation
import Combine
import Appwrite

// MARK: - Achievement Service Implementation

@MainActor
class AchievementService: AchievementServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let appwriteManager: AppwriteManager
    private var subscriptions = Set<AnyCancellable>()
    private var realtimeSubscriptions = [String: AnyCancellable]()
    private let cache = AchievementCache()
    
    // Publishers for real-time updates
    private let achievementUpdateSubject = PassthroughSubject<AchievementUpdate, Error>()
    
    // MARK: - Configuration
    
    private let databaseId = "golf_finder_db"
    private let achievementsCollection = "achievements"
    private let playerAchievementsCollection = "player_achievements"
    private let achievementProgressCollection = "achievement_progress"
    private let badgesCollection = "badges"
    private let playerBadgesCollection = "player_badges"
    private let chainsCollection = "achievement_chains"
    private let milestonesCollection = "milestones"
    private let notificationsCollection = "achievement_notifications"
    private let analyticsCollection = "achievement_analytics"
    
    // MARK: - Service Dependencies
    
    private var ratingEngineService: RatingEngineServiceProtocol?
    private var socialChallengeService: SocialChallengeServiceProtocol?
    private var leaderboardService: LeaderboardServiceProtocol?
    private var hapticFeedbackService: HapticFeedbackServiceProtocol?
    
    // MARK: - Performance Configuration
    
    private let maxConcurrentProcessing = 5
    private let backgroundProcessingInterval: TimeInterval = 300 // 5 minutes
    private var isBackgroundProcessingEnabled = true
    private var backgroundTimer: Timer?
    
    // MARK: - Initialization
    
    init(appwriteManager: AppwriteManager = .shared) {
        self.appwriteManager = appwriteManager
        setupBackgroundProcessing()
        preloadCriticalData()
    }
    
    deinit {
        backgroundTimer?.invalidate()
        unsubscribeFromAll()
    }
    
    // MARK: - Dependency Injection
    
    func configure(
        ratingEngineService: RatingEngineServiceProtocol,
        socialChallengeService: SocialChallengeServiceProtocol,
        leaderboardService: LeaderboardServiceProtocol,
        hapticFeedbackService: HapticFeedbackServiceProtocol
    ) {
        self.ratingEngineService = ratingEngineService
        self.socialChallengeService = socialChallengeService
        self.leaderboardService = leaderboardService
        self.hapticFeedbackService = hapticFeedbackService
    }
    
    // MARK: - Achievement Management
    
    func getPlayerAchievements(playerId: String) async throws -> [PlayerAchievement] {
        // Check cache first
        if let cached = cache.getPlayerAchievements(playerId: playerId) {
            return cached
        }
        
        let queries = [
            Query.equal("player_id", value: playerId),
            Query.orderDesc("unlocked_at")
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: playerAchievementsCollection,
                queries: queries
            )
            
            let achievements = try response.documents.compactMap { document in
                try mapDocumentToPlayerAchievement(document)
            }
            
            // Cache the results
            cache.setPlayerAchievements(playerId: playerId, achievements: achievements)
            return achievements
            
        } catch {
            throw AchievementError.fetchFailed(error.localizedDescription)
        }
    }
    
    func getAvailableAchievements(for playerId: String) async throws -> [Achievement] {
        // Get player's current achievements to filter out already unlocked ones
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        let unlockedAchievementIds = Set(playerAchievements.map { $0.achievementId })
        
        let queries = [
            Query.equal("is_active", value: true),
            Query.orderDesc("created_at")
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: achievementsCollection,
                queries: queries
            )
            
            let allAchievements = try response.documents.compactMap { document in
                try mapDocumentToAchievement(document)
            }
            
            // Filter out already unlocked achievements and hidden ones player can't see yet
            let availableAchievements = allAchievements.filter { achievement in
                !unlockedAchievementIds.contains(achievement.id) &&
                (!achievement.isHidden || await shouldShowHiddenAchievement(playerId: playerId, achievement: achievement))
            }
            
            return availableAchievements
            
        } catch {
            throw AchievementError.fetchFailed(error.localizedDescription)
        }
    }
    
    func getAchievementProgress(playerId: String, achievementId: String) async throws -> AchievementProgress? {
        let queries = [
            Query.equal("player_id", value: playerId),
            Query.equal("achievement_id", value: achievementId)
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: achievementProgressCollection,
                queries: queries
            )
            
            guard let document = response.documents.first else {
                return nil
            }
            
            return try mapDocumentToAchievementProgress(document)
            
        } catch {
            throw AchievementError.progressNotFound
        }
    }
    
    func unlockAchievement(playerId: String, achievementId: String, context: AchievementContext?) async throws -> AchievementUnlock {
        // Validate achievement exists and player is eligible
        guard let achievement = try await getAchievement(id: achievementId) else {
            throw AchievementError.achievementNotFound
        }
        
        // Check if already unlocked
        let existingAchievements = try await getPlayerAchievements(playerId: playerId)
        if existingAchievements.contains(where: { $0.achievementId == achievementId }) {
            throw AchievementError.alreadyUnlocked
        }
        
        // Validate unlock if context provided
        if let context = context {
            let isValid = try await validateAchievementUnlock(playerId: playerId, achievementId: achievementId, context: context)
            if !isValid {
                throw AchievementError.validationFailed
            }
        }
        
        let unlockId = ID.unique()
        let unlockedAt = Date()
        
        // Create achievement unlock record
        let achievementUnlock = AchievementUnlock(
            id: unlockId,
            achievementId: achievementId,
            playerId: playerId,
            unlockedAt: unlockedAt,
            trigger: context?.sourceEvent.toAchievementTrigger() ?? .manualUnlock,
            context: context,
            rewards: achievement.rewards,
            isFirstTimeUnlock: await isFirstTimeUnlock(achievementId: achievementId),
            celebrationTriggered: false
        )
        
        // Create player achievement record
        let playerAchievement = PlayerAchievement(
            id: ID.unique(),
            achievementId: achievementId,
            playerId: playerId,
            unlockedAt: unlockedAt,
            progress: AchievementProgress(current: 100, target: 100, percentage: 100, lastUpdated: unlockedAt, milestones: []),
            context: context,
            notificationShown: false,
            sharedAt: nil,
            celebrationTriggered: false
        )
        
        do {
            // Store player achievement
            let playerAchievementData = try mapPlayerAchievementToDocument(playerAchievement)
            _ = try await appwriteManager.databases.createDocument(
                databaseId: databaseId,
                collectionId: playerAchievementsCollection,
                documentId: playerAchievement.id,
                data: playerAchievementData
            )
            
            // Process rewards
            try await processAchievementRewards(playerId: playerId, rewards: achievement.rewards)
            
            // Trigger haptic feedback
            await triggerAchievementHaptic(achievement: achievement, tier: achievement.tier)
            
            // Send real-time update
            let update = AchievementUpdate(
                id: ID.unique(),
                playerId: playerId,
                updateType: .unlocked,
                achievementId: achievementId,
                data: ["tier": AnyCodable(achievement.tier.rawValue)],
                timestamp: unlockedAt
            )
            achievementUpdateSubject.send(update)
            
            // Clear cache
            cache.clearPlayerCache(playerId: playerId)
            
            // Schedule notification
            try await scheduleAchievementNotification(playerId: playerId, achievement: achievement)
            
            // Check for chain progressions
            try await checkAndProcessChainProgressions(playerId: playerId, newAchievementId: achievementId)
            
            return achievementUnlock
            
        } catch {
            throw AchievementError.unlockFailed(error.localizedDescription)
        }
    }
    
    func processPlayerActivity(playerId: String, activity: PlayerActivity) async throws -> [AchievementUnlock] {
        var unlocks: [AchievementUnlock] = []
        
        // Get available achievements for processing
        let availableAchievements = try await getAvailableAchievements(for: playerId)
        
        // Process each achievement to see if activity triggers unlock
        for achievement in availableAchievements {
            if await checkAchievementEligibility(playerId: playerId, achievement: achievement, activity: activity) {
                do {
                    let context = AchievementContext(
                        sourceEvent: activity.type.rawValue,
                        additionalData: activity.data,
                        timestamp: activity.timestamp,
                        location: activity.location,
                        courseId: activity.courseId,
                        roundId: activity.roundId
                    )
                    
                    let unlock = try await unlockAchievement(playerId: playerId, achievementId: achievement.id, context: context)
                    unlocks.append(unlock)
                    
                } catch {
                    // Log error but continue processing other achievements
                    print("Failed to unlock achievement \(achievement.id): \(error)")
                }
            } else {
                // Update progress if not unlocked yet
                try await updateAchievementProgress(playerId: playerId, achievement: achievement, activity: activity)
            }
        }
        
        return unlocks
    }
    
    func validateAchievementUnlock(playerId: String, achievementId: String, context: AchievementContext) async throws -> Bool {
        guard let achievement = try await getAchievement(id: achievementId) else {
            return false
        }
        
        // Validate primary requirement
        let primaryValid = await validateRequirement(playerId: playerId, requirement: achievement.requirements.primary, context: context)
        
        // Validate secondary requirements
        for requirement in achievement.requirements.secondary {
            let secondaryValid = await validateRequirement(playerId: playerId, requirement: requirement, context: context)
            if !secondaryValid {
                return false
            }
        }
        
        // Check time window if specified
        if let timeWindow = achievement.requirements.timeWindow {
            let cutoffDate = Date().addingTimeInterval(-timeWindow)
            if context.timestamp < cutoffDate {
                return false
            }
        }
        
        // Check course restrictions
        if let courseRestrictions = achievement.requirements.courseRestrictions,
           let courseId = context.courseId {
            if !courseRestrictions.contains(courseId) {
                return false
            }
        }
        
        // Validate group requirements if applicable
        if let groupReqs = achievement.requirements.groupRequirements {
            let groupValid = await validateGroupRequirements(playerId: playerId, groupReqs: groupReqs, context: context)
            if !groupValid {
                return false
            }
        }
        
        return primaryValid
    }
    
    // MARK: - Achievement Categories
    
    func getScoringAchievements(for playerId: String) async throws -> [PlayerAchievement] {
        return try await getPlayerAchievementsByCategory(playerId: playerId, category: .scoring)
    }
    
    func getSocialAchievements(for playerId: String) async throws -> [PlayerAchievement] {
        return try await getPlayerAchievementsByCategory(playerId: playerId, category: .social)
    }
    
    func getProgressAchievements(for playerId: String) async throws -> [PlayerAchievement] {
        return try await getPlayerAchievementsByCategory(playerId: playerId, category: .progress)
    }
    
    func getPremiumAchievements(for playerId: String) async throws -> [PlayerAchievement] {
        return try await getPlayerAchievementsByCategory(playerId: playerId, category: .premium)
    }
    
    // MARK: - Badge System
    
    func getPlayerBadges(playerId: String) async throws -> PlayerBadgeCollection {
        let queries = [
            Query.equal("player_id", value: playerId),
            Query.orderDesc("acquired_at")
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: playerBadgesCollection,
                queries: queries
            )
            
            let badges = try response.documents.compactMap { document in
                try mapDocumentToPlayerBadge(document)
            }
            
            let totalPossibleBadges = try await getTotalBadgeCount()
            let completionPercentage = totalPossibleBadges > 0 ? Double(badges.count) / Double(totalPossibleBadges) * 100 : 0
            
            return PlayerBadgeCollection(
                playerId: playerId,
                badges: badges,
                totalBadges: badges.count,
                completionPercentage: completionPercentage,
                lastUpdated: Date()
            )
            
        } catch {
            throw AchievementError.fetchFailed(error.localizedDescription)
        }
    }
    
    func checkBadgeProgression(playerId: String, category: BadgeCategory) async throws -> BadgeProgression {
        // Get player's current badge in this category
        let playerBadges = try await getPlayerBadges(playerId: playerId)
        let categoryBadge = playerBadges.badges.first { badge in
            // Would need to lookup badge details to check category
            return false // Simplified for now
        }
        
        // Get the badge definition for this category
        guard let badge = try await getBadgeByCategory(category: category) else {
            throw AchievementError.badgeNotFound
        }
        
        let currentTier = categoryBadge?.tier ?? .bronze
        let nextTier = getNextTier(currentTier)
        
        // Calculate progress to next tier
        let progress = try await calculateBadgeProgress(playerId: playerId, badge: badge, currentTier: currentTier, targetTier: nextTier)
        
        return BadgeProgression(
            currentTier: currentTier,
            nextTier: nextTier,
            progressToNext: progress,
            requirements: badge.requirements,
            canAdvance: progress >= 1.0
        )
    }
    
    func awardBadgeTier(playerId: String, badgeId: String, tier: AchievementTier) async throws -> BadgeAward {
        // Get existing player badge or create new one
        let playerBadges = try await getPlayerBadges(playerId: playerId)
        let existingBadge = playerBadges.badges.first { $0.badgeId == badgeId }
        
        let previousTier = existingBadge?.tier
        let awardId = ID.unique()
        let awardedAt = Date()
        
        // Create or update player badge
        let playerBadge = PlayerBadge(
            id: existingBadge?.id ?? ID.unique(),
            badgeId: badgeId,
            playerId: playerId,
            tier: tier,
            acquiredAt: existingBadge?.acquiredAt ?? awardedAt,
            progression: BadgeProgression(
                currentTier: tier,
                nextTier: getNextTier(tier),
                progressToNext: 0,
                requirements: BadgeRequirements(tierRequirements: [:], prerequisites: [], exclusivityRules: []),
                canAdvance: tier != .diamond
            )
        )
        
        do {
            let data = try mapPlayerBadgeToDocument(playerBadge)
            
            if existingBadge != nil {
                _ = try await appwriteManager.databases.updateDocument(
                    databaseId: databaseId,
                    collectionId: playerBadgesCollection,
                    documentId: playerBadge.id,
                    data: data
                )
            } else {
                _ = try await appwriteManager.databases.createDocument(
                    databaseId: databaseId,
                    collectionId: playerBadgesCollection,
                    documentId: playerBadge.id,
                    data: data
                )
            }
            
            // Create badge award record
            let badgeAward = BadgeAward(
                id: awardId,
                badgeId: badgeId,
                playerId: playerId,
                tier: tier,
                awardedAt: awardedAt,
                previousTier: previousTier,
                celebration: BadgeCelebration(
                    tier: tier,
                    hapticPattern: tier.hapticPattern,
                    visualEffects: tier.visualEffects,
                    duration: tier.celebrationDuration
                )
            )
            
            // Trigger haptic feedback
            await triggerBadgeHaptics(badge: Badge.placeholder(id: badgeId), tier: tier)
            
            // Send real-time update
            let update = AchievementUpdate(
                id: ID.unique(),
                playerId: playerId,
                updateType: .badgeAwarded,
                achievementId: badgeId,
                data: ["tier": AnyCodable(tier.rawValue), "previousTier": AnyCodable(previousTier?.rawValue)],
                timestamp: awardedAt
            )
            achievementUpdateSubject.send(update)
            
            return badgeAward
            
        } catch {
            throw AchievementError.badgeAwardFailed(error.localizedDescription)
        }
    }
    
    func getBadgeStatistics(badgeId: String) async throws -> BadgeStatistics {
        // Query player badges to calculate statistics
        let queries = [Query.equal("badge_id", value: badgeId)]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: playerBadgesCollection,
                queries: queries
            )
            
            let playerBadges = try response.documents.compactMap { document in
                try mapDocumentToPlayerBadge(document)
            }
            
            // Calculate tier distribution
            var tierDistribution: [AchievementTier: Int] = [:]
            for tier in AchievementTier.allCases {
                tierDistribution[tier] = playerBadges.filter { $0.tier == tier }.count
            }
            
            // Calculate average time to unlock
            let totalUnlockTimes = playerBadges.compactMap { badge in
                Date().timeIntervalSince(badge.acquiredAt)
            }
            let averageTimeToUnlock = totalUnlockTimes.isEmpty ? 0 : totalUnlockTimes.reduce(0, +) / Double(totalUnlockTimes.count)
            
            // Determine rarity
            let totalPlayers = try await getTotalPlayerCount()
            let unlockRate = totalPlayers > 0 ? Double(playerBadges.count) / Double(totalPlayers) : 0
            let rarity = BadgeRarity(level: determineRarity(unlockRate: unlockRate), unlockPercentage: unlockRate * 100, estimatedPlayers: playerBadges.count)
            
            return BadgeStatistics(
                badgeId: badgeId,
                totalAwards: playerBadges.count,
                tierDistribution: tierDistribution,
                averageTimeToUnlock: averageTimeToUnlock,
                rarity: rarity,
                popularityRank: try await calculateBadgePopularityRank(badgeId: badgeId)
            )
            
        } catch {
            throw AchievementError.statisticsCalculationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Achievement Chains & Linked Accomplishments
    
    func getAchievementChains(for playerId: String) async throws -> [AchievementChain] {
        let queries = [Query.orderDesc("created_at")]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: chainsCollection,
                queries: queries
            )
            
            let chains = try response.documents.compactMap { document in
                try mapDocumentToAchievementChain(document)
            }
            
            // Calculate completion status for each chain
            var playerChains: [AchievementChain] = []
            let playerAchievements = try await getPlayerAchievements(playerId: playerId)
            let unlockedAchievementIds = Set(playerAchievements.map { $0.achievementId })
            
            for var chain in chains {
                let completedAchievements = chain.achievements.filter { unlockedAchievementIds.contains($0) }
                chain = AchievementChain(
                    id: chain.id,
                    name: chain.name,
                    description: chain.description,
                    achievements: chain.achievements,
                    requiresSequential: chain.requiresSequential,
                    rewards: chain.rewards,
                    isComplete: completedAchievements.count == chain.achievements.count,
                    completedAt: chain.isComplete ? Date() : nil
                )
                playerChains.append(chain)
            }
            
            return playerChains
            
        } catch {
            throw AchievementError.fetchFailed(error.localizedDescription)
        }
    }
    
    func checkChainProgression(playerId: String, chainId: String) async throws -> ChainProgression {
        guard let chain = try await getAchievementChain(id: chainId) else {
            throw AchievementError.chainNotFound
        }
        
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        let unlockedAchievementIds = Set(playerAchievements.map { $0.achievementId })
        
        let completedAchievements = chain.achievements.filter { unlockedAchievementIds.contains($0) }
        
        let currentPosition: Int
        let nextAchievement: String?
        let canAdvance: Bool
        
        if chain.requiresSequential {
            // Find the first uncompleted achievement in sequence
            currentPosition = chain.achievements.firstIndex { !unlockedAchievementIds.contains($0) } ?? chain.achievements.count
            nextAchievement = currentPosition < chain.achievements.count ? chain.achievements[currentPosition] : nil
            canAdvance = currentPosition < chain.achievements.count
        } else {
            // Any achievement can be completed in any order
            currentPosition = completedAchievements.count
            nextAchievement = chain.achievements.first { !unlockedAchievementIds.contains($0) }
            canAdvance = nextAchievement != nil
        }
        
        // Estimate completion date based on player's achievement velocity
        let estimatedCompletion = await calculateEstimatedChainCompletion(playerId: playerId, chain: chain, currentPosition: currentPosition)
        
        return ChainProgression(
            chainId: chainId,
            currentPosition: currentPosition,
            totalSteps: chain.achievements.count,
            completedAchievements: completedAchievements,
            nextAchievement: nextAchievement,
            canAdvance: canAdvance,
            estimatedCompletion: estimatedCompletion
        )
    }
    
    func processChainAdvancement(playerId: String, chainId: String) async throws -> ChainAdvancement? {
        let progression = try await checkChainProgression(playerId: playerId, chainId: chainId)
        
        guard progression.canAdvance else {
            return nil
        }
        
        guard let chain = try await getAchievementChain(id: chainId),
              let nextAchievementId = progression.nextAchievement else {
            return nil
        }
        
        // Check if the next achievement can be unlocked
        if await canUnlockNextChainAchievement(playerId: playerId, chain: chain, nextAchievementId: nextAchievementId) {
            let context = AchievementContext(
                sourceEvent: "chain_progression",
                additionalData: ["chainId": AnyCodable(chainId)],
                timestamp: Date(),
                location: nil,
                courseId: nil,
                roundId: nil
            )
            
            _ = try await unlockAchievement(playerId: playerId, achievementId: nextAchievementId, context: context)
            
            let advancement = ChainAdvancement(
                id: ID.unique(),
                chainId: chainId,
                playerId: playerId,
                advancedAt: Date(),
                newPosition: progression.currentPosition + 1,
                unlockedAchievement: nextAchievementId,
                chainCompleted: progression.currentPosition + 1 >= progression.totalSteps,
                rewards: progression.currentPosition + 1 >= progression.totalSteps ? chain.rewards : nil
            )
            
            // Send real-time update
            let update = AchievementUpdate(
                id: ID.unique(),
                playerId: playerId,
                updateType: advancement.chainCompleted ? .chainCompleted : .progressUpdated,
                achievementId: chainId,
                data: ["newPosition": AnyCodable(advancement.newPosition)],
                timestamp: advancement.advancedAt
            )
            achievementUpdateSubject.send(update)
            
            return advancement
        }
        
        return nil
    }
    
    func getLinkedAchievements(achievementId: String) async throws -> [Achievement] {
        // Implementation would query achievements that are linked to the given achievement
        // For now, return empty array
        return []
    }
    
    // MARK: - Milestone Celebrations
    
    func trackMilestoneProgress(playerId: String, milestone: GameMilestone, progress: Double) async throws {
        // Create or update milestone progress record
        let progressData = [
            "player_id": playerId,
            "milestone": milestone.rawValue,
            "progress": progress,
            "last_updated": Date().iso8601
        ]
        
        do {
            // Check if progress record exists
            let queries = [
                Query.equal("player_id", value: playerId),
                Query.equal("milestone", value: milestone.rawValue)
            ]
            
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: milestonesCollection,
                queries: queries
            )
            
            if let existingDoc = response.documents.first {
                // Update existing progress
                _ = try await appwriteManager.databases.updateDocument(
                    databaseId: databaseId,
                    collectionId: milestonesCollection,
                    documentId: existingDoc.id,
                    data: progressData
                )
            } else {
                // Create new progress record
                _ = try await appwriteManager.databases.createDocument(
                    databaseId: databaseId,
                    collectionId: milestonesCollection,
                    documentId: ID.unique(),
                    data: progressData
                )
            }
            
            // Check if milestone should trigger celebration
            if progress >= 1.0 {
                let celebration = try await triggerMilestoneCelebration(playerId: playerId, milestone: milestone)
                print("Milestone celebration triggered: \(celebration)")
            }
            
        } catch {
            throw AchievementError.milestoneTrackingFailed(error.localizedDescription)
        }
    }
    
    func triggerMilestoneCelebration(playerId: String, milestone: GameMilestone) async throws -> MilestoneCelebration {
        let celebrationId = ID.unique()
        let celebratedAt = Date()
        
        // Generate milestone rewards
        let rewards = generateMilestoneRewards(for: milestone)
        
        let celebration = MilestoneCelebration(
            id: celebrationId,
            milestone: milestone,
            playerId: playerId,
            celebratedAt: celebratedAt,
            rewards: rewards,
            hapticTriggered: false,
            sharedAutomatically: false
        )
        
        // Trigger milestone haptics
        await triggerMilestoneHaptics(milestone: milestone, progress: 1.0)
        
        // Send real-time update
        let update = AchievementUpdate(
            id: ID.unique(),
            playerId: playerId,
            updateType: .milestoneReached,
            achievementId: milestone.rawValue,
            data: ["rewards": AnyCodable(rewards.experienceBonus)],
            timestamp: celebratedAt
        )
        achievementUpdateSubject.send(update)
        
        return celebration
    }
    
    func getUpcomingMilestones(for playerId: String) async throws -> [UpcomingMilestone] {
        // Get player's current progress on various milestones
        let queries = [Query.equal("player_id", value: playerId)]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: milestonesCollection,
                queries: queries
            )
            
            var upcomingMilestones: [UpcomingMilestone] = []
            
            for document in response.documents {
                guard let milestoneString = document.data["milestone"]?.value as? String,
                      let milestone = GameMilestone(rawValue: milestoneString),
                      let progress = document.data["progress"]?.value as? Double,
                      progress < 1.0 else {
                    continue
                }
                
                let requirements = generateMilestoneRequirements(for: milestone)
                let rewards = generateMilestoneRewards(for: milestone)
                let estimatedCompletion = await calculateEstimatedMilestoneCompletion(playerId: playerId, milestone: milestone, currentProgress: progress)
                
                let upcomingMilestone = UpcomingMilestone(
                    id: document.id,
                    milestone: milestone,
                    progress: progress,
                    estimatedCompletion: estimatedCompletion,
                    requirements: requirements,
                    rewards: rewards
                )
                
                upcomingMilestones.append(upcomingMilestone)
            }
            
            return upcomingMilestones.sorted { $0.progress > $1.progress }
            
        } catch {
            throw AchievementError.fetchFailed(error.localizedDescription)
        }
    }
    
    func checkMilestoneCelebrationConditions(playerId: String, milestone: GameMilestone) async throws -> Bool {
        // Get milestone progress
        let queries = [
            Query.equal("player_id", value: playerId),
            Query.equal("milestone", value: milestone.rawValue)
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: milestonesCollection,
                queries: queries
            )
            
            guard let document = response.documents.first,
                  let progress = document.data["progress"]?.value as? Double else {
                return false
            }
            
            return progress >= 1.0
            
        } catch {
            return false
        }
    }
    
    // MARK: - Service Integration for Automatic Achievement Processing
    
    func processScoreAchievements(playerId: String, scorecard: ScorecardEntry, performance: PerformanceMetrics) async throws -> [AchievementUnlock] {
        var unlocks: [AchievementUnlock] = []
        
        // Create activity context from scorecard
        let activity = PlayerActivity(
            type: .scoreSubmission,
            playerId: playerId,
            data: [
                "score": AnyCodable(scorecard.totalScore),
                "courseId": AnyCodable(scorecard.courseId),
                "holeScores": AnyCodable(scorecard.holeScores),
                "handicap": AnyCodable(scorecard.handicap),
                "scoringAverage": AnyCodable(performance.scoringAverage),
                "consistency": AnyCodable(performance.consistency)
            ],
            timestamp: scorecard.date,
            location: LocationContext(courseId: scorecard.courseId, latitude: nil, longitude: nil, timestamp: scorecard.date),
            courseId: scorecard.courseId,
            roundId: scorecard.id
        )
        
        // Process scoring-specific achievements
        let newUnlocks = try await processPlayerActivity(playerId: playerId, activity: activity)
        unlocks.append(contentsOf: newUnlocks)
        
        // Check for specific scoring milestones
        try await checkScoringMilestones(playerId: playerId, scorecard: scorecard, performance: performance)
        
        // Update streaks
        try await updateStreakProgress(playerId: playerId, scorecard: scorecard)
        
        return unlocks
    }
    
    func processSocialAchievements(playerId: String, challengeResult: ChallengeResult, socialMetrics: SocialMetrics) async throws -> [AchievementUnlock] {
        var unlocks: [AchievementUnlock] = []
        
        // Create activity context from challenge result
        let activity = PlayerActivity(
            type: .challengeCompletion,
            playerId: playerId,
            data: [
                "challengeId": AnyCodable(challengeResult.challengeId),
                "position": AnyCodable(challengeResult.position),
                "totalParticipants": AnyCodable(challengeResult.totalParticipants),
                "challengesWon": AnyCodable(socialMetrics.challengesWon),
                "challengesParticipated": AnyCodable(socialMetrics.challengesParticipated),
                "friendsInvited": AnyCodable(socialMetrics.friendsInvited)
            ],
            timestamp: challengeResult.completedAt,
            location: nil,
            courseId: nil,
            roundId: nil
        )
        
        // Process social-specific achievements
        let newUnlocks = try await processPlayerActivity(playerId: playerId, activity: activity)
        unlocks.append(contentsOf: newUnlocks)
        
        // Check for social milestones
        try await checkSocialMilestones(playerId: playerId, challengeResult: challengeResult, socialMetrics: socialMetrics)
        
        return unlocks
    }
    
    func processLeaderboardAchievements(playerId: String, leaderboardResult: LeaderboardResult, positionMetrics: PositionMetrics) async throws -> [AchievementUnlock] {
        var unlocks: [AchievementUnlock] = []
        
        // Create activity context from leaderboard result
        let activity = PlayerActivity(
            type: .leaderboardPosition,
            playerId: playerId,
            data: [
                "leaderboardId": AnyCodable(leaderboardResult.leaderboardId),
                "position": AnyCodable(leaderboardResult.position),
                "previousPosition": AnyCodable(leaderboardResult.previousPosition),
                "totalPlayers": AnyCodable(leaderboardResult.totalPlayers),
                "positionsGained": AnyCodable(positionMetrics.positionsGained),
                "bestPosition": AnyCodable(positionMetrics.bestPosition)
            ],
            timestamp: leaderboardResult.updatedAt,
            location: nil,
            courseId: nil,
            roundId: nil
        )
        
        // Process leaderboard-specific achievements
        let newUnlocks = try await processPlayerActivity(playerId: playerId, activity: activity)
        unlocks.append(contentsOf: newUnlocks)
        
        // Check for leaderboard milestones
        try await checkLeaderboardMilestones(playerId: playerId, leaderboardResult: leaderboardResult, positionMetrics: positionMetrics)
        
        return unlocks
    }
    
    func processStreakAchievements(playerId: String, streakData: StreakData) async throws -> [AchievementUnlock] {
        var unlocks: [AchievementUnlock] = []
        
        // Create activity context from streak data
        let activity = PlayerActivity(
            type: .streakAchievement,
            playerId: playerId,
            data: [
                "parStreak": AnyCodable(streakData.parStreak),
                "birdieStreak": AnyCodable(streakData.birdieStreak),
                "consistencyStreak": AnyCodable(streakData.consistencyStreak),
                "playingStreak": AnyCodable(streakData.playingStreak)
            ],
            timestamp: Date(),
            location: nil,
            courseId: nil,
            roundId: nil
        )
        
        // Process streak-specific achievements
        let newUnlocks = try await processPlayerActivity(playerId: playerId, activity: activity)
        unlocks.append(contentsOf: newUnlocks)
        
        return unlocks
    }
    
    // MARK: - Real-time Achievement Processing
    
    func subscribeToAchievementUpdates(playerId: String) -> AnyPublisher<AchievementUpdate, Error> {
        // Set up real-time subscription for player achievement updates
        let realtimeStream = appwriteManager.realtime.subscribe(
            channels: ["databases.\(databaseId).collections.\(playerAchievementsCollection).documents"]
        )
        
        let subscription = realtimeStream
            .compactMap { [weak self] response in
                self?.processAchievementRealtimeUpdate(response, for: playerId)
            }
            .subscribe(achievementUpdateSubject)
        
        realtimeSubscriptions[playerId] = subscription
        
        return achievementUpdateSubject
            .filter { $0.playerId == playerId }
            .eraseToAnyPublisher()
    }
    
    func processBackgroundAchievements(playerId: String) async throws -> BackgroundProcessingResult {
        let startTime = Date()
        var processedAchievements: [String] = []
        var newUnlocks: [AchievementUnlock] = []
        var progressUpdates: [AchievementProgress] = []
        var errors: [ProcessingError] = []
        
        do {
            // Get player's recent activities that might trigger achievements
            let recentActivities = try await getRecentPlayerActivities(playerId: playerId)
            
            for activity in recentActivities {
                do {
                    let unlocks = try await processPlayerActivity(playerId: playerId, activity: activity)
                    newUnlocks.append(contentsOf: unlocks)
                    processedAchievements.append(contentsOf: unlocks.map { $0.achievementId })
                } catch {
                    errors.append(ProcessingError(
                        error: error.localizedDescription,
                        context: "Activity processing: \(activity.type)",
                        timestamp: Date()
                    ))
                }
            }
            
            // Update progress for all available achievements
            let availableAchievements = try await getAvailableAchievements(for: playerId)
            for achievement in availableAchievements {
                do {
                    if let progress = try await getAchievementProgress(playerId: playerId, achievementId: achievement.id) {
                        progressUpdates.append(progress)
                    }
                } catch {
                    errors.append(ProcessingError(
                        error: error.localizedDescription,
                        context: "Progress update: \(achievement.id)",
                        timestamp: Date()
                    ))
                }
            }
            
        } catch {
            errors.append(ProcessingError(
                error: error.localizedDescription,
                context: "Background processing initialization",
                timestamp: Date()
            ))
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return BackgroundProcessingResult(
            processedAchievements: processedAchievements,
            newUnlocks: newUnlocks,
            progressUpdates: progressUpdates,
            processingTime: processingTime,
            errors: errors
        )
    }
    
    func getAchievementNotificationQueue(playerId: String) async throws -> [AchievementNotification] {
        let queries = [
            Query.equal("player_id", value: playerId),
            Query.isNull("displayed_at"),
            Query.orderDesc("created_at")
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: notificationsCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToAchievementNotification(document)
            }
            
        } catch {
            throw AchievementError.fetchFailed(error.localizedDescription)
        }
    }
    
    func markNotificationDisplayed(playerId: String, notificationId: String) async throws {
        let updatedData = [
            "displayed_at": Date().iso8601
        ]
        
        do {
            _ = try await appwriteManager.databases.updateDocument(
                databaseId: databaseId,
                collectionId: notificationsCollection,
                documentId: notificationId,
                data: updatedData
            )
        } catch {
            throw AchievementError.notificationUpdateFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Achievement Analytics & Engagement Tracking
    
    func getPlayerEngagementMetrics(playerId: String) async throws -> PlayerEngagementMetrics {
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        
        // Calculate achievements by category
        var achievementsByCategory: [AchievementCategory: Int] = [:]
        for category in AchievementCategory.allCases {
            achievementsByCategory[category] = 0
        }
        
        for achievement in playerAchievements {
            // Would need to lookup achievement details to get category
            // Simplified for now
        }
        
        // Calculate average time to unlock
        let unlockTimes = playerAchievements.map { achievement in
            Date().timeIntervalSince(achievement.unlockedAt)
        }
        let averageTimeToUnlock = unlockTimes.isEmpty ? 0 : unlockTimes.reduce(0, +) / Double(unlockTimes.count)
        
        // Calculate engagement score based on various factors
        let engagementScore = calculateEngagementScore(playerAchievements: playerAchievements)
        
        // Find last activity date
        let lastActivityDate = playerAchievements.max(by: { $0.unlockedAt < $1.unlockedAt })?.unlockedAt ?? Date.distantPast
        
        // Calculate streak days (simplified)
        let streakDays = try await calculatePlayerStreakDays(playerId: playerId)
        
        return PlayerEngagementMetrics(
            playerId: playerId,
            totalAchievements: playerAchievements.count,
            achievementsByCategory: achievementsByCategory,
            averageTimeToUnlock: averageTimeToUnlock,
            engagementScore: engagementScore,
            lastActivityDate: lastActivityDate,
            streakDays: streakDays
        )
    }
    
    func trackAchievementInteraction(playerId: String, achievementId: String, interaction: AchievementInteraction) async throws {
        let interactionData = [
            "player_id": playerId,
            "achievement_id": achievementId,
            "interaction": interaction.rawValue,
            "timestamp": Date().iso8601
        ]
        
        do {
            _ = try await appwriteManager.databases.createDocument(
                databaseId: databaseId,
                collectionId: analyticsCollection,
                documentId: ID.unique(),
                data: interactionData
            )
        } catch {
            throw AchievementError.trackingFailed(error.localizedDescription)
        }
    }
    
    func getAchievementStatistics() async throws -> AchievementStatistics {
        // Get total achievements
        let totalAchievementsResponse = try await appwriteManager.databases.listDocuments(
            databaseId: databaseId,
            collectionId: achievementsCollection,
            queries: [Query.limit(1000)]
        )
        let totalAchievements = totalAchievementsResponse.total
        
        // Get total unlocks
        let totalUnlocksResponse = try await appwriteManager.databases.listDocuments(
            databaseId: databaseId,
            collectionId: playerAchievementsCollection,
            queries: [Query.limit(1000)]
        )
        let totalUnlocks = totalUnlocksResponse.total
        
        // Calculate average unlocks per player
        let totalPlayers = try await getTotalPlayerCount()
        let averageUnlocksPerPlayer = totalPlayers > 0 ? Double(totalUnlocks) / Double(totalPlayers) : 0
        
        // Get most popular achievements (simplified)
        let mostPopularAchievements: [AchievementPopularity] = []
        
        // Get rarest achievements (simplified)
        let rarestAchievements = try await getRareAchievements()
        
        // Calculate unlock trends (simplified)
        let unlockTrends = UnlockTrends(
            dailyUnlocks: [:],
            trendDirection: "stable",
            growthRate: 0.05
        )
        
        // Calculate category distribution (simplified)
        let categoryDistribution: [AchievementCategory: Double] = [:]
        
        return AchievementStatistics(
            totalAchievements: totalAchievements,
            totalUnlocks: totalUnlocks,
            averageUnlocksPerPlayer: averageUnlocksPerPlayer,
            mostPopularAchievements: mostPopularAchievements,
            rarestAchievements: rarestAchievements,
            unlockTrends: unlockTrends,
            categoryDistribution: categoryDistribution
        )
    }
    
    func getAchievementJourney(playerId: String) async throws -> AchievementJourney {
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        
        // Create timeline from achievement unlocks
        let timeline = playerAchievements.map { achievement in
            JourneyEvent(
                timestamp: achievement.unlockedAt,
                type: "achievement_unlocked",
                description: "Unlocked achievement: \(achievement.achievementId)"
            )
        }.sorted { $0.timestamp < $1.timestamp }
        
        // Calculate total progress
        let totalPossibleAchievements = try await getTotalAchievementCount()
        let totalProgress = totalPossibleAchievements > 0 ? Double(playerAchievements.count) / Double(totalPossibleAchievements) * 100 : 0
        
        // Get milestones (simplified)
        let milestones = playerAchievements.compactMap { achievement in
            JourneyMilestone(
                milestone: achievement.achievementId,
                achievedAt: achievement.unlockedAt,
                significance: "Achievement unlocked"
            )
        }
        
        // Predict future achievements (simplified)
        let predictions: [FutureAchievement] = []
        
        // Get personal bests (simplified)
        let personalBests: [PersonalBest] = []
        
        return AchievementJourney(
            playerId: playerId,
            timeline: timeline,
            totalProgress: totalProgress,
            milestones: milestones,
            predictions: predictions,
            personalBests: personalBests
        )
    }
    
    // MARK: - Achievement Rarity & Exclusive Unlocks
    
    func getRareAchievements() async throws -> [RareAchievement] {
        // Query all achievements and calculate their unlock rates
        let achievementsResponse = try await appwriteManager.databases.listDocuments(
            databaseId: databaseId,
            collectionId: achievementsCollection,
            queries: [Query.limit(1000)]
        )
        
        let achievements = try achievementsResponse.documents.compactMap { document in
            try mapDocumentToAchievement(document)
        }
        
        var rareAchievements: [RareAchievement] = []
        let totalPlayers = try await getTotalPlayerCount()
        
        for achievement in achievements {
            // Get unlock count for this achievement
            let unlockQueries = [Query.equal("achievement_id", value: achievement.id)]
            let unlockResponse = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: playerAchievementsCollection,
                queries: unlockQueries
            )
            
            let unlockCount = unlockResponse.total
            let unlockRate = totalPlayers > 0 ? Double(unlockCount) / Double(totalPlayers) : 0
            
            // Consider rare if unlock rate is less than 5%
            if unlockRate < 0.05 {
                let rareAchievement = RareAchievement(
                    id: achievement.id,
                    achievement: achievement,
                    unlockRate: unlockRate,
                    totalUnlocks: unlockCount,
                    estimatedRarity: determineRarity(unlockRate: unlockRate),
                    exclusivityFactor: calculateExclusivityFactor(unlockRate: unlockRate)
                )
                rareAchievements.append(rareAchievement)
            }
        }
        
        return rareAchievements.sorted { $0.unlockRate < $1.unlockRate }
    }
    
    func checkExclusiveAchievementEligibility(playerId: String, achievementId: String) async throws -> Bool {
        guard let achievement = try await getAchievement(id: achievementId) else {
            return false
        }
        
        // Check if achievement has exclusivity rules
        guard let exclusivityRules = achievement.requirements.groupRequirements?.allowedGroups else {
            return true // No exclusivity rules, eligible
        }
        
        // Check player's group memberships or premium status
        let playerGroups = try await getPlayerGroups(playerId: playerId)
        
        for allowedGroup in exclusivityRules {
            if playerGroups.contains(allowedGroup) {
                return true
            }
        }
        
        return false
    }
    
    func getSeasonalAchievements(season: AchievementSeason?) async throws -> [SeasonalAchievement] {
        var queries = [
            Query.equal("is_seasonal", value: true),
            Query.orderDesc("created_at")
        ]
        
        if let season = season {
            queries.append(Query.equal("season", value: season.rawValue))
        }
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: achievementsCollection,
                queries: queries
            )
            
            let achievements = try response.documents.compactMap { document in
                try mapDocumentToAchievement(document)
            }
            
            return achievements.compactMap { achievement in
                guard let seasonalInfo = achievement.seasonalInfo else { return nil }
                
                let isActive = Date() >= seasonalInfo.startDate && Date() <= seasonalInfo.endDate
                
                return SeasonalAchievement(
                    id: achievement.id,
                    achievement: achievement,
                    season: seasonalInfo.season,
                    startDate: seasonalInfo.startDate,
                    endDate: seasonalInfo.endDate,
                    isActive: isActive,
                    completionBonus: seasonalInfo.season == .holiday ? SeasonalBonus(multiplier: 2.0, bonusRewards: ["Holiday Badge"]) : nil
                )
            }
            
        } catch {
            throw AchievementError.fetchFailed(error.localizedDescription)
        }
    }
    
    func processLimitedTimeAchievements(playerId: String) async throws -> [LimitedTimeOpportunity] {
        let seasonalAchievements = try await getSeasonalAchievements(season: nil)
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        let unlockedIds = Set(playerAchievements.map { $0.achievementId })
        
        var opportunities: [LimitedTimeOpportunity] = []
        
        for seasonal in seasonalAchievements {
            guard seasonal.isActive && !unlockedIds.contains(seasonal.id) else { continue }
            
            let timeRemaining = seasonal.endDate.timeIntervalSinceNow
            guard timeRemaining > 0 else { continue }
            
            // Calculate current progress toward achievement
            let progress = try await calculateAchievementProgressValue(playerId: playerId, achievement: seasonal.achievement)
            
            // Generate required actions
            let requiredActions = await generateRequiredActions(for: seasonal.achievement, currentProgress: progress)
            
            let opportunity = LimitedTimeOpportunity(
                id: seasonal.id,
                achievementId: seasonal.achievement.id,
                timeRemaining: timeRemaining,
                requiredActions: requiredActions,
                currentProgress: progress,
                estimatedDifficulty: estimateDifficulty(for: seasonal.achievement, currentProgress: progress)
            )
            
            opportunities.append(opportunity)
        }
        
        return opportunities.sorted { $0.timeRemaining < $1.timeRemaining }
    }
    
    // MARK: - Haptic Feedback Integration
    
    func triggerAchievementHaptic(achievement: Achievement, tier: AchievementTier) async {
        await hapticFeedbackService?.provideAchievementUnlockHaptic(tier: tier)
    }
    
    func triggerSynchronizedAchievementCelebration(achievement: Achievement, tier: AchievementTier) async {
        await hapticFeedbackService?.provideSynchronizedAchievementHaptic(tier: tier)
    }
    
    func triggerMilestoneHaptics(milestone: GameMilestone, progress: Double) async {
        await hapticFeedbackService?.provideMilestoneHaptic(milestone: milestone)
    }
    
    func triggerBadgeHaptics(badge: Badge, tier: AchievementTier) async {
        await hapticFeedbackService?.provideBadgeAcquisitionHaptic(badgeType: badge.category.toBadgeType())
    }
    
    // MARK: - Achievement Sharing & Social Features
    
    func shareAchievement(playerId: String, achievementId: String, shareOptions: AchievementShareOptions) async throws -> AchievementShare {
        let shareId = ID.unique()
        let sharedAt = Date()
        
        let achievementShare = AchievementShare(
            id: shareId,
            achievementId: achievementId,
            playerId: playerId,
            sharedAt: sharedAt,
            platform: shareOptions.platforms.first ?? .internal,
            customMessage: shareOptions.customMessage,
            reactions: []
        )
        
        // Store share record
        let shareData = try mapAchievementShareToDocument(achievementShare)
        
        do {
            _ = try await appwriteManager.databases.createDocument(
                databaseId: databaseId,
                collectionId: "achievement_shares",
                documentId: shareId,
                data: shareData
            )
            
            // Update player achievement to mark as shared
            let playerAchievements = try await getPlayerAchievements(playerId: playerId)
            if let playerAchievement = playerAchievements.first(where: { $0.achievementId == achievementId }) {
                let updatedData = ["shared_at": sharedAt.iso8601]
                _ = try await appwriteManager.databases.updateDocument(
                    databaseId: databaseId,
                    collectionId: playerAchievementsCollection,
                    documentId: playerAchievement.id,
                    data: updatedData
                )
            }
            
            return achievementShare
            
        } catch {
            throw AchievementError.shareFailed(error.localizedDescription)
        }
    }
    
    func getFriendAchievementActivities(playerId: String) async throws -> [FriendAchievementActivity] {
        // Implementation would query friend relationships and their recent achievements
        // For now, return empty array
        return []
    }
    
    func compareAchievements(playerId: String, friendId: String) async throws -> AchievementComparison {
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        let friendAchievements = try await getPlayerAchievements(playerId: friendId)
        
        let playerAchievementIds = Set(playerAchievements.map { $0.achievementId })
        let friendAchievementIds = Set(friendAchievements.map { $0.achievementId })
        
        let commonAchievements = Array(playerAchievementIds.intersection(friendAchievementIds))
        let playerExclusive = Array(playerAchievementIds.subtracting(friendAchievementIds))
        let friendExclusive = Array(friendAchievementIds.subtracting(playerAchievementIds))
        
        // Calculate comparison score based on achievements
        let comparisonScore = calculateComparisonScore(
            playerCount: playerAchievements.count,
            friendCount: friendAchievements.count,
            commonCount: commonAchievements.count
        )
        
        return AchievementComparison(
            playerId: playerId,
            friendId: friendId,
            playerAchievements: playerAchievements.count,
            friendAchievements: friendAchievements.count,
            commonAchievements: commonAchievements,
            playerExclusive: playerExclusive,
            friendExclusive: friendExclusive,
            comparisonScore: comparisonScore
        )
    }
    
    func getAchievementLeaderboard(playerId: String, category: AchievementCategory?) async throws -> AchievementLeaderboard {
        // Implementation would query all players and their achievement counts
        // For now, return simplified leaderboard
        return AchievementLeaderboard(
            category: category,
            entries: [],
            playerPosition: nil,
            totalPlayers: 0,
            lastUpdated: Date()
        )
    }
    
    // MARK: - Performance & Optimization
    
    func preloadAchievementData(playerId: String) async throws {
        // Preload frequently accessed data
        _ = try await getPlayerAchievements(playerId: playerId)
        _ = try await getAvailableAchievements(for: playerId)
        _ = try await getPlayerBadges(playerId: playerId)
    }
    
    func cachePlayerAchievements(playerId: String) async throws {
        let achievements = try await getPlayerAchievements(playerId: playerId)
        cache.setPlayerAchievements(playerId: playerId, achievements: achievements)
    }
    
    func clearAchievementCache(playerId: String) async throws {
        cache.clearPlayerCache(playerId: playerId)
    }
    
    func getSystemPerformanceMetrics() async throws -> AchievementSystemMetrics {
        // Calculate system performance metrics
        return AchievementSystemMetrics(
            totalProcessingTime: 0,
            averageResponseTime: 0,
            cacheHitRate: cache.getCacheHitRate(),
            backgroundProcessingRate: 0,
            errorRate: 0,
            activeSubscriptions: realtimeSubscriptions.count
        )
    }
    
    // MARK: - Cleanup
    
    func unsubscribeFromAll() {
        realtimeSubscriptions.values.forEach { $0.cancel() }
        realtimeSubscriptions.removeAll()
    }
}

// MARK: - Private Implementation

private extension AchievementService {
    
    // MARK: - Setup & Configuration
    
    func setupBackgroundProcessing() {
        guard isBackgroundProcessingEnabled else { return }
        
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: backgroundProcessingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performBackgroundProcessing()
            }
        }
    }
    
    func preloadCriticalData() {
        Task {
            do {
                // Preload achievement definitions
                _ = try await appwriteManager.databases.listDocuments(
                    databaseId: databaseId,
                    collectionId: achievementsCollection,
                    queries: [Query.limit(100)]
                )
                
                // Preload badge definitions
                _ = try await appwriteManager.databases.listDocuments(
                    databaseId: databaseId,
                    collectionId: badgesCollection,
                    queries: [Query.limit(100)]
                )
                
                print("✅ Achievement system critical data preloaded")
            } catch {
                print("❌ Failed to preload achievement data: \(error)")
            }
        }
    }
    
    func performBackgroundProcessing() async {
        // Get active players for background processing
        // This would typically be players who have been active recently
        let activePlayers = await getActivePlayersForBackgroundProcessing()
        
        for playerId in activePlayers {
            do {
                let result = try await processBackgroundAchievements(playerId: playerId)
                if !result.newUnlocks.isEmpty {
                    print("Background processing unlocked \(result.newUnlocks.count) achievements for player \(playerId)")
                }
            } catch {
                print("Background processing failed for player \(playerId): \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    func shouldShowHiddenAchievement(playerId: String, achievement: Achievement) async -> Bool {
        // Logic to determine if a hidden achievement should be shown
        // Could be based on player level, prerequisites, etc.
        return false
    }
    
    func getAchievement(id: String) async throws -> Achievement? {
        do {
            let document = try await appwriteManager.databases.getDocument(
                databaseId: databaseId,
                collectionId: achievementsCollection,
                documentId: id
            )
            return try mapDocumentToAchievement(document)
        } catch {
            return nil
        }
    }
    
    func isFirstTimeUnlock(achievementId: String) async -> Bool {
        let queries = [Query.equal("achievement_id", value: achievementId)]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: playerAchievementsCollection,
                queries: queries
            )
            return response.total == 0
        } catch {
            return true
        }
    }
    
    func processAchievementRewards(playerId: String, rewards: AchievementRewards) async throws {
        // Process experience points, badges, premium features, etc.
        // Implementation would integrate with player progression system
    }
    
    func scheduleAchievementNotification(playerId: String, achievement: Achievement) async throws {
        let notificationData = [
            "player_id": playerId,
            "achievement_id": achievement.id,
            "type": NotificationType.achievement.rawValue,
            "priority": NotificationPriority.high.rawValue,
            "created_at": Date().iso8601,
            "data": ["tier": achievement.tier.rawValue, "name": achievement.name]
        ]
        
        _ = try await appwriteManager.databases.createDocument(
            databaseId: databaseId,
            collectionId: notificationsCollection,
            documentId: ID.unique(),
            data: notificationData
        )
    }
    
    func checkAndProcessChainProgressions(playerId: String, newAchievementId: String) async throws {
        let chains = try await getAchievementChains(for: playerId)
        
        for chain in chains {
            if chain.achievements.contains(newAchievementId) {
                _ = try await processChainAdvancement(playerId: playerId, chainId: chain.id)
            }
        }
    }
    
    func checkAchievementEligibility(playerId: String, achievement: Achievement, activity: PlayerActivity) async -> Bool {
        // Complex logic to check if activity satisfies achievement requirements
        // This would involve checking the achievement's requirements against the activity data
        return false // Simplified for now
    }
    
    func updateAchievementProgress(playerId: String, achievement: Achievement, activity: PlayerActivity) async throws {
        // Update progress for achievements that aren't unlocked yet
        // Implementation would calculate new progress based on activity
    }
    
    func validateRequirement(playerId: String, requirement: RequirementCriteria, context: AchievementContext) async -> Bool {
        // Validate individual requirement criteria
        // Implementation would check requirement type and validate against context data
        return true // Simplified for now
    }
    
    func validateGroupRequirements(playerId: String, groupReqs: GroupRequirements, context: AchievementContext) async -> Bool {
        // Validate group-based requirements
        return true // Simplified for now
    }
    
    func getPlayerAchievementsByCategory(playerId: String, category: AchievementCategory) async throws -> [PlayerAchievement] {
        let playerAchievements = try await getPlayerAchievements(playerId: playerId)
        
        // Would need to lookup achievement details to filter by category
        // For now, return all achievements
        return playerAchievements
    }
    
    // MARK: - Badge System Helpers
    
    func getTotalBadgeCount() async throws -> Int {
        let response = try await appwriteManager.databases.listDocuments(
            databaseId: databaseId,
            collectionId: badgesCollection,
            queries: [Query.limit(1)]
        )
        return response.total
    }
    
    func getBadgeByCategory(category: BadgeCategory) async throws -> Badge? {
        let queries = [Query.equal("category", value: category.rawValue)]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: badgesCollection,
                queries: queries
            )
            
            guard let document = response.documents.first else { return nil }
            return try mapDocumentToBadge(document)
        } catch {
            return nil
        }
    }
    
    func getNextTier(_ tier: AchievementTier) -> AchievementTier? {
        switch tier {
        case .bronze: return .silver
        case .silver: return .gold
        case .gold: return .platinum
        case .platinum: return .diamond
        case .diamond: return nil
        }
    }
    
    func calculateBadgeProgress(playerId: String, badge: Badge, currentTier: AchievementTier, targetTier: AchievementTier?) async throws -> Double {
        // Calculate progress toward next badge tier
        return 0.5 // Simplified for now
    }
    
    func getTotalPlayerCount() async throws -> Int {
        // Would query players collection to get total count
        return 1000 // Simplified for now
    }
    
    func determineRarity(unlockRate: Double) -> AchievementRarity {
        switch unlockRate {
        case 0..<0.01: return .mythic
        case 0.01..<0.02: return .legendary
        case 0.02..<0.05: return .epic
        case 0.05..<0.15: return .rare
        case 0.15..<0.35: return .uncommon
        default: return .common
        }
    }
    
    func calculateBadgePopularityRank(badgeId: String) async throws -> Int {
        // Calculate popularity rank among all badges
        return 1 // Simplified for now
    }
    
    // MARK: - Chain System Helpers
    
    func getAchievementChain(id: String) async throws -> AchievementChain? {
        do {
            let document = try await appwriteManager.databases.getDocument(
                databaseId: databaseId,
                collectionId: chainsCollection,
                documentId: id
            )
            return try mapDocumentToAchievementChain(document)
        } catch {
            return nil
        }
    }
    
    func calculateEstimatedChainCompletion(playerId: String, chain: AchievementChain, currentPosition: Int) async -> Date? {
        // Calculate estimated completion based on player's achievement velocity
        return nil // Simplified for now
    }
    
    func canUnlockNextChainAchievement(playerId: String, chain: AchievementChain, nextAchievementId: String) async -> Bool {
        // Check if the next achievement in chain can be unlocked
        return false // Simplified for now
    }
    
    // MARK: - Milestone System Helpers
    
    func generateMilestoneRewards(for milestone: GameMilestone) -> MilestoneRewards {
        // Generate appropriate rewards for milestone
        return MilestoneRewards(
            experienceBonus: 100,
            specialBadges: [],
            unlockableContent: [],
            celebrationPackage: CelebrationPackage(theme: "celebration", effects: [], duration: 3.0)
        )
    }
    
    func generateMilestoneRequirements(for milestone: GameMilestone) -> MilestoneRequirements {
        // Generate requirements for milestone
        return MilestoneRequirements(
            targetValue: 1.0,
            timeframe: nil,
            conditions: [],
            validationCriteria: []
        )
    }
    
    func calculateEstimatedMilestoneCompletion(playerId: String, milestone: GameMilestone, currentProgress: Double) async -> Date? {
        // Calculate estimated completion based on progress velocity
        return nil // Simplified for now
    }
    
    // MARK: - Service Integration Helpers
    
    func checkScoringMilestones(playerId: String, scorecard: ScorecardEntry, performance: PerformanceMetrics) async throws {
        // Check for scoring-related milestones
        if scorecard.totalScore <= 72 {
            try await trackMilestoneProgress(playerId: playerId, milestone: .breakingPar, progress: 1.0)
        }
        
        // Check for birdie/eagle in holeScores
        if scorecard.holeScores.contains { $0 < 4 } {
            try await trackMilestoneProgress(playerId: playerId, milestone: .firstBirdie, progress: 1.0)
        }
    }
    
    func updateStreakProgress(playerId: String, scorecard: ScorecardEntry) async throws {
        // Update various streak counters
        // Implementation would track par streaks, birdie streaks, etc.
    }
    
    func checkSocialMilestones(playerId: String, challengeResult: ChallengeResult, socialMetrics: SocialMetrics) async throws {
        // Check for social-related milestones
        if challengeResult.position == 1 {
            // Won a challenge
        }
        
        if socialMetrics.challengesParticipated >= 10 {
            // Milestone for participation
        }
    }
    
    func checkLeaderboardMilestones(playerId: String, leaderboardResult: LeaderboardResult, positionMetrics: PositionMetrics) async throws {
        // Check for leaderboard-related milestones
        if leaderboardResult.position <= 10 {
            // Top 10 milestone
        }
        
        if leaderboardResult.position == 1 {
            // First place milestone
        }
    }
    
    func getRecentPlayerActivities(playerId: String) async throws -> [PlayerActivity] {
        // Get recent activities that might trigger achievements
        return [] // Simplified for now
    }
    
    func getActivePlayersForBackgroundProcessing() async -> [String] {
        // Get list of players who should have background achievement processing
        return [] // Simplified for now
    }
    
    func processAchievementRealtimeUpdate(_ response: AppwriteModels.RealtimeResponse, for playerId: String) -> AchievementUpdate? {
        // Process real-time updates from Appwrite
        return nil // Simplified for now
    }
    
    // MARK: - Analytics Helpers
    
    func calculateEngagementScore(playerAchievements: [PlayerAchievement]) -> Double {
        // Calculate engagement score based on achievement activity
        let recentAchievements = playerAchievements.filter { $0.unlockedAt > Date().addingTimeInterval(-86400 * 30) }
        return min(100.0, Double(recentAchievements.count) * 10.0)
    }
    
    func calculatePlayerStreakDays(playerId: String) async throws -> Int {
        // Calculate consecutive days player has been active
        return 5 // Simplified for now
    }
    
    // MARK: - Rarity & Exclusivity Helpers
    
    func calculateExclusivityFactor(unlockRate: Double) -> Double {
        return max(0.1, 1.0 - unlockRate)
    }
    
    func getPlayerGroups(playerId: String) async throws -> [String] {
        // Get player's group memberships
        return [] // Simplified for now
    }
    
    func calculateAchievementProgressValue(playerId: String, achievement: Achievement) async throws -> Double {
        // Calculate current progress toward achievement
        return 0.5 // Simplified for now
    }
    
    func generateRequiredActions(for achievement: Achievement, currentProgress: Double) async -> [RequiredAction] {
        // Generate list of actions needed to complete achievement
        return []
    }
    
    func estimateDifficulty(for achievement: Achievement, currentProgress: Double) -> DifficultyLevel {
        // Estimate difficulty based on achievement requirements and current progress
        return .medium
    }
    
    // MARK: - Social Features Helpers
    
    func calculateComparisonScore(playerCount: Int, friendCount: Int, commonCount: Int) -> Double {
        // Calculate comparison score between players
        let total = playerCount + friendCount
        guard total > 0 else { return 0 }
        return Double(commonCount * 2) / Double(total) * 100
    }
    
    func getTotalAchievementCount() async throws -> Int {
        let response = try await appwriteManager.databases.listDocuments(
            databaseId: databaseId,
            collectionId: achievementsCollection,
            queries: [Query.limit(1)]
        )
        return response.total
    }
    
    // MARK: - Document Mapping
    
    func mapDocumentToAchievement(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> Achievement {
        return Achievement(
            id: document.id,
            name: document.data["name"]?.value as? String ?? "",
            description: document.data["description"]?.value as? String ?? "",
            category: AchievementCategory(rawValue: document.data["category"]?.value as? String ?? "scoring") ?? .scoring,
            tier: AchievementTier(rawValue: document.data["tier"]?.value as? String ?? "bronze") ?? .bronze,
            badgeImageUrl: document.data["badge_image_url"]?.value as? String,
            requirements: AchievementRequirements(
                primary: RequirementCriteria(type: .score, value: 80, operator: .lessThan, dataSource: "scorecard", validationRules: []),
                secondary: [],
                minimumLevel: nil,
                timeWindow: nil,
                courseRestrictions: nil,
                groupRequirements: nil
            ),
            rewards: AchievementRewards(
                experiencePoints: document.data["experience_points"]?.value as? Int ?? 100,
                badges: [],
                premiumFeatures: [],
                socialRecognition: SocialRecognition(publicAnnouncement: true, leaderboardHighlight: true, friendNotification: true),
                customRewards: []
            ),
            rarity: AchievementRarity(rawValue: document.data["rarity"]?.value as? String ?? "common") ?? .common,
            isHidden: document.data["is_hidden"]?.value as? Bool ?? false,
            isLimitedTime: document.data["is_limited_time"]?.value as? Bool ?? false,
            seasonalInfo: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    func mapDocumentToPlayerAchievement(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> PlayerAchievement {
        return PlayerAchievement(
            id: document.id,
            achievementId: document.data["achievement_id"]?.value as? String ?? "",
            playerId: document.data["player_id"]?.value as? String ?? "",
            unlockedAt: Date(), // Would parse from document
            progress: AchievementProgress(current: 100, target: 100, percentage: 100, lastUpdated: Date(), milestones: []),
            context: nil,
            notificationShown: document.data["notification_shown"]?.value as? Bool ?? false,
            sharedAt: nil,
            celebrationTriggered: document.data["celebration_triggered"]?.value as? Bool ?? false
        )
    }
    
    func mapDocumentToAchievementProgress(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> AchievementProgress {
        let current = document.data["current"]?.value as? Double ?? 0
        let target = document.data["target"]?.value as? Double ?? 100
        
        return AchievementProgress(
            current: current,
            target: target,
            percentage: target > 0 ? (current / target) * 100 : 0,
            lastUpdated: Date(),
            milestones: []
        )
    }
    
    func mapDocumentToPlayerBadge(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> PlayerBadge {
        return PlayerBadge(
            id: document.id,
            badgeId: document.data["badge_id"]?.value as? String ?? "",
            playerId: document.data["player_id"]?.value as? String ?? "",
            tier: AchievementTier(rawValue: document.data["tier"]?.value as? String ?? "bronze") ?? .bronze,
            acquiredAt: Date(),
            progression: BadgeProgression(
                currentTier: .bronze,
                nextTier: .silver,
                progressToNext: 0,
                requirements: BadgeRequirements(tierRequirements: [:], prerequisites: [], exclusivityRules: []),
                canAdvance: true
            )
        )
    }
    
    func mapDocumentToBadge(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> Badge {
        return Badge(
            id: document.id,
            name: document.data["name"]?.value as? String ?? "",
            description: document.data["description"]?.value as? String ?? "",
            category: BadgeCategory(rawValue: document.data["category"]?.value as? String ?? "scorer") ?? .scorer,
            imageUrl: document.data["image_url"]?.value as? String ?? "",
            tiers: [],
            requirements: BadgeRequirements(tierRequirements: [:], prerequisites: [], exclusivityRules: []),
            isExclusive: document.data["is_exclusive"]?.value as? Bool ?? false,
            rarity: BadgeRarity(level: .common, unlockPercentage: 50, estimatedPlayers: 100)
        )
    }
    
    func mapDocumentToAchievementChain(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> AchievementChain {
        return AchievementChain(
            id: document.id,
            name: document.data["name"]?.value as? String ?? "",
            description: document.data["description"]?.value as? String ?? "",
            achievements: [], // Would parse from document
            requiresSequential: document.data["requires_sequential"]?.value as? Bool ?? false,
            rewards: ChainRewards(completionBonuses: [], progressRewards: [], exclusiveUnlocks: []),
            isComplete: false,
            completedAt: nil
        )
    }
    
    func mapDocumentToAchievementNotification(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> AchievementNotification {
        return AchievementNotification(
            id: document.id,
            playerId: document.data["player_id"]?.value as? String ?? "",
            achievementId: document.data["achievement_id"]?.value as? String ?? "",
            type: NotificationType(rawValue: document.data["type"]?.value as? String ?? "achievement") ?? .achievement,
            priority: NotificationPriority(rawValue: document.data["priority"]?.value as? String ?? "medium") ?? .medium,
            createdAt: Date(),
            displayedAt: nil,
            data: [:]
        )
    }
    
    func mapPlayerAchievementToDocument(_ achievement: PlayerAchievement) throws -> [String: Any] {
        return [
            "achievement_id": achievement.achievementId,
            "player_id": achievement.playerId,
            "unlocked_at": achievement.unlockedAt.iso8601,
            "notification_shown": achievement.notificationShown,
            "celebration_triggered": achievement.celebrationTriggered
        ]
    }
    
    func mapPlayerBadgeToDocument(_ badge: PlayerBadge) throws -> [String: Any] {
        return [
            "badge_id": badge.badgeId,
            "player_id": badge.playerId,
            "tier": badge.tier.rawValue,
            "acquired_at": badge.acquiredAt.iso8601
        ]
    }
    
    func mapAchievementShareToDocument(_ share: AchievementShare) throws -> [String: Any] {
        return [
            "achievement_id": share.achievementId,
            "player_id": share.playerId,
            "shared_at": share.sharedAt.iso8601,
            "platform": share.platform.rawValue,
            "custom_message": share.customMessage ?? ""
        ]
    }
}

// MARK: - Achievement Cache

private class AchievementCache {
    private var playerAchievements: [String: [PlayerAchievement]] = [:]
    private var availableAchievements: [Achievement] = []
    private var cacheQueue = DispatchQueue(label: "achievement.cache", attributes: .concurrent)
    private var cacheHits = 0
    private var cacheRequests = 0
    
    func getPlayerAchievements(playerId: String) -> [PlayerAchievement]? {
        return cacheQueue.sync {
            cacheRequests += 1
            if let achievements = playerAchievements[playerId] {
                cacheHits += 1
                return achievements
            }
            return nil
        }
    }
    
    func setPlayerAchievements(playerId: String, achievements: [PlayerAchievement]) {
        cacheQueue.async(flags: .barrier) {
            self.playerAchievements[playerId] = achievements
        }
    }
    
    func clearPlayerCache(playerId: String) {
        cacheQueue.async(flags: .barrier) {
            self.playerAchievements.removeValue(forKey: playerId)
        }
    }
    
    func clearAllCache() {
        cacheQueue.async(flags: .barrier) {
            self.playerAchievements.removeAll()
            self.availableAchievements.removeAll()
        }
    }
    
    func getCacheHitRate() -> Double {
        return cacheQueue.sync {
            guard cacheRequests > 0 else { return 0 }
            return Double(cacheHits) / Double(cacheRequests)
        }
    }
}

// MARK: - Supporting Enums & Extensions

enum PlayerActivityType: String, Codable {
    case scoreSubmission = "score_submission"
    case challengeCompletion = "challenge_completion"
    case leaderboardPosition = "leaderboard_position"
    case streakAchievement = "streak_achievement"
    case socialActivity = "social_activity"
    case milestoneReached = "milestone_reached"
}

struct PlayerActivity: Codable, Equatable {
    let type: PlayerActivityType
    let playerId: String
    let data: [String: AnyCodable]
    let timestamp: Date
    let location: LocationContext?
    let courseId: String?
    let roundId: String?
}

// MARK: - Error Types

enum AchievementError: Error {
    case fetchFailed(String)
    case achievementNotFound
    case alreadyUnlocked
    case validationFailed
    case unlockFailed(String)
    case progressNotFound
    case badgeNotFound
    case badgeAwardFailed(String)
    case statisticsCalculationFailed(String)
    case chainNotFound
    case milestoneTrackingFailed(String)
    case trackingFailed(String)
    case notificationUpdateFailed(String)
    case shareFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .fetchFailed(let error):
            return "Failed to fetch achievement data: \(error)"
        case .achievementNotFound:
            return "Achievement not found"
        case .alreadyUnlocked:
            return "Achievement already unlocked"
        case .validationFailed:
            return "Achievement unlock validation failed"
        case .unlockFailed(let error):
            return "Failed to unlock achievement: \(error)"
        case .progressNotFound:
            return "Achievement progress not found"
        case .badgeNotFound:
            return "Badge not found"
        case .badgeAwardFailed(let error):
            return "Failed to award badge: \(error)"
        case .statisticsCalculationFailed(let error):
            return "Failed to calculate statistics: \(error)"
        case .chainNotFound:
            return "Achievement chain not found"
        case .milestoneTrackingFailed(let error):
            return "Failed to track milestone: \(error)"
        case .trackingFailed(let error):
            return "Failed to track interaction: \(error)"
        case .notificationUpdateFailed(let error):
            return "Failed to update notification: \(error)"
        case .shareFailed(let error):
            return "Failed to share achievement: \(error)"
        }
    }
}

// MARK: - Extensions

private extension String {
    func toAchievementTrigger() -> AchievementTrigger {
        return AchievementTrigger(rawValue: self) ?? .systemProcessing
    }
}

private extension AchievementTier {
    var hapticPattern: String {
        switch self {
        case .bronze: return "achievement_bronze"
        case .silver: return "achievement_silver"
        case .gold: return "achievement_gold"
        case .platinum: return "achievement_platinum"
        case .diamond: return "achievement_diamond"
        }
    }
    
    var visualEffects: [VisualEffect] {
        return [VisualEffect(type: "celebration", duration: celebrationDuration)]
    }
    
    var celebrationDuration: TimeInterval {
        switch self {
        case .bronze: return 1.0
        case .silver: return 1.5
        case .gold: return 2.0
        case .platinum: return 2.5
        case .diamond: return 3.0
        }
    }
}

private extension BadgeCategory {
    func toBadgeType() -> BadgeType {
        switch self {
        case .scorer: return .scoring
        case .socialite: return .social
        case .improver: return .improvement
        case .competitor: return .tournament
        case .explorer: return .course
        case .mentor: return .social
        case .collector: return .scoring
        case .legend: return .tournament
        }
    }
}

private extension Badge {
    static func placeholder(id: String) -> Badge {
        return Badge(
            id: id,
            name: "Badge",
            description: "Badge description",
            category: .scorer,
            imageUrl: "",
            tiers: [],
            requirements: BadgeRequirements(tierRequirements: [:], prerequisites: [], exclusivityRules: []),
            isExclusive: false,
            rarity: BadgeRarity(level: .common, unlockPercentage: 50, estimatedPlayers: 100)
        )
    }
}

private extension Date {
    var iso8601: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}