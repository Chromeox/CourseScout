import Foundation
import Combine

// MARK: - Achievement Service Protocol

@MainActor
protocol AchievementServiceProtocol: ObservableObject {
    
    // MARK: - Achievement Management
    
    /// Retrieve all achievements for a specific player
    func getPlayerAchievements(playerId: String) async throws -> [PlayerAchievement]
    
    /// Retrieve available achievements that can be unlocked
    func getAvailableAchievements(for playerId: String) async throws -> [Achievement]
    
    /// Get achievement progress for a specific player
    func getAchievementProgress(playerId: String, achievementId: String) async throws -> AchievementProgress?
    
    /// Unlock an achievement for a player
    func unlockAchievement(playerId: String, achievementId: String, context: AchievementContext?) async throws -> AchievementUnlock
    
    /// Check and process potential achievements based on player activity
    func processPlayerActivity(playerId: String, activity: PlayerActivity) async throws -> [AchievementUnlock]
    
    /// Validate achievement unlock to prevent fraud
    func validateAchievementUnlock(playerId: String, achievementId: String, context: AchievementContext) async throws -> Bool
    
    // MARK: - Achievement Categories
    
    /// Get scoring achievements (birdies, eagles, score milestones)
    func getScoringAchievements(for playerId: String) async throws -> [PlayerAchievement]
    
    /// Get social achievements (challenges, referrals, community)
    func getSocialAchievements(for playerId: String) async throws -> [PlayerAchievement]
    
    /// Get progress achievements (handicap improvements, consistency)
    func getProgressAchievements(for playerId: String) async throws -> [PlayerAchievement]
    
    /// Get premium achievements (exclusive badges, tournament hosting)
    func getPremiumAchievements(for playerId: String) async throws -> [PlayerAchievement]
    
    // MARK: - Badge System
    
    /// Get player's badge collection
    func getPlayerBadges(playerId: String) async throws -> PlayerBadgeCollection
    
    /// Check badge progression and tier advancement
    func checkBadgeProgression(playerId: String, category: BadgeCategory) async throws -> BadgeProgression
    
    /// Award badge tier advancement
    func awardBadgeTier(playerId: String, badgeId: String, tier: AchievementTier) async throws -> BadgeAward
    
    /// Get badge statistics and rarity information
    func getBadgeStatistics(badgeId: String) async throws -> BadgeStatistics
    
    // MARK: - Achievement Chains & Linked Accomplishments
    
    /// Get achievement chains for a player
    func getAchievementChains(for playerId: String) async throws -> [AchievementChain]
    
    /// Check if achievement chain requirements are met
    func checkChainProgression(playerId: String, chainId: String) async throws -> ChainProgression
    
    /// Process achievement chain advancement
    func processChainAdvancement(playerId: String, chainId: String) async throws -> ChainAdvancement?
    
    /// Get linked achievements that unlock together
    func getLinkedAchievements(achievementId: String) async throws -> [Achievement]
    
    // MARK: - Milestone Celebrations
    
    /// Track milestone progress for celebrations
    func trackMilestoneProgress(playerId: String, milestone: GameMilestone, progress: Double) async throws
    
    /// Trigger milestone celebration
    func triggerMilestoneCelebration(playerId: String, milestone: GameMilestone) async throws -> MilestoneCelebration
    
    /// Get upcoming milestones for a player
    func getUpcomingMilestones(for playerId: String) async throws -> [UpcomingMilestone]
    
    /// Check if milestone celebration conditions are met
    func checkMilestoneCelebrationConditions(playerId: String, milestone: GameMilestone) async throws -> Bool
    
    // MARK: - Service Integration for Automatic Achievement Processing
    
    /// Process scoring-related achievements from RatingEngineService
    func processScoreAchievements(playerId: String, scorecard: ScorecardEntry, performance: PerformanceMetrics) async throws -> [AchievementUnlock]
    
    /// Process social achievements from SocialChallengeService
    func processSocialAchievements(playerId: String, challengeResult: ChallengeResult, socialMetrics: SocialMetrics) async throws -> [AchievementUnlock]
    
    /// Process leaderboard achievements from LeaderboardService
    func processLeaderboardAchievements(playerId: String, leaderboardResult: LeaderboardResult, positionMetrics: PositionMetrics) async throws -> [AchievementUnlock]
    
    /// Process streaks and consistency achievements
    func processStreakAchievements(playerId: String, streakData: StreakData) async throws -> [AchievementUnlock]
    
    // MARK: - Real-time Achievement Processing
    
    /// Subscribe to real-time achievement updates
    func subscribeToAchievementUpdates(playerId: String) -> AnyPublisher<AchievementUpdate, Error>
    
    /// Process background achievement calculations
    func processBackgroundAchievements(playerId: String) async throws -> BackgroundProcessingResult
    
    /// Get achievement notification queue
    func getAchievementNotificationQueue(playerId: String) async throws -> [AchievementNotification]
    
    /// Mark achievement notification as displayed
    func markNotificationDisplayed(playerId: String, notificationId: String) async throws
    
    // MARK: - Achievement Analytics & Engagement Tracking
    
    /// Get player engagement metrics
    func getPlayerEngagementMetrics(playerId: String) async throws -> PlayerEngagementMetrics
    
    /// Track achievement interaction
    func trackAchievementInteraction(playerId: String, achievementId: String, interaction: AchievementInteraction) async throws
    
    /// Get achievement unlock rate statistics
    func getAchievementStatistics() async throws -> AchievementStatistics
    
    /// Get player's achievement journey and timeline
    func getAchievementJourney(playerId: String) async throws -> AchievementJourney
    
    // MARK: - Achievement Rarity & Exclusive Unlocks
    
    /// Get rare achievements based on unlock frequency
    func getRareAchievements() async throws -> [RareAchievement]
    
    /// Check exclusive achievement eligibility
    func checkExclusiveAchievementEligibility(playerId: String, achievementId: String) async throws -> Bool
    
    /// Get seasonal or time-limited achievements
    func getSeasonalAchievements(season: AchievementSeason?) async throws -> [SeasonalAchievement]
    
    /// Process limited-time achievement opportunities
    func processLimitedTimeAchievements(playerId: String) async throws -> [LimitedTimeOpportunity]
    
    // MARK: - Haptic Feedback Integration
    
    /// Trigger haptic feedback for achievement unlock
    func triggerAchievementHaptic(achievement: Achievement, tier: AchievementTier) async
    
    /// Coordinate synchronized haptic feedback with Apple Watch
    func triggerSynchronizedAchievementCelebration(achievement: Achievement, tier: AchievementTier) async
    
    /// Trigger milestone celebration haptics
    func triggerMilestoneHaptics(milestone: GameMilestone, progress: Double) async
    
    /// Trigger badge acquisition haptics
    func triggerBadgeHaptics(badge: Badge, tier: AchievementTier) async
    
    // MARK: - Achievement Sharing & Social Features
    
    /// Share achievement unlock with friends
    func shareAchievement(playerId: String, achievementId: String, shareOptions: AchievementShareOptions) async throws -> AchievementShare
    
    /// Get friend achievement activities
    func getFriendAchievementActivities(playerId: String) async throws -> [FriendAchievementActivity]
    
    /// Compare achievements with friends
    func compareAchievements(playerId: String, friendId: String) async throws -> AchievementComparison
    
    /// Get achievement leaderboard among friends
    func getAchievementLeaderboard(playerId: String, category: AchievementCategory?) async throws -> AchievementLeaderboard
    
    // MARK: - Performance & Optimization
    
    /// Preload critical achievement data
    func preloadAchievementData(playerId: String) async throws
    
    /// Cache frequently accessed achievements
    func cachePlayerAchievements(playerId: String) async throws
    
    /// Clear achievement cache
    func clearAchievementCache(playerId: String) async throws
    
    /// Get achievement system performance metrics
    func getSystemPerformanceMetrics() async throws -> AchievementSystemMetrics
}

// MARK: - Supporting Data Models

// MARK: - Achievement Models

struct Achievement: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let category: AchievementCategory
    let tier: AchievementTier
    let badgeImageUrl: String?
    let requirements: AchievementRequirements
    let rewards: AchievementRewards
    let rarity: AchievementRarity
    let isHidden: Bool
    let isLimitedTime: Bool
    let seasonalInfo: SeasonalInfo?
    let createdAt: Date
    let updatedAt: Date
}

struct PlayerAchievement: Codable, Identifiable, Equatable {
    let id: String
    let achievementId: String
    let playerId: String
    let unlockedAt: Date
    let progress: AchievementProgress
    let context: AchievementContext?
    let notificationShown: Bool
    let sharedAt: Date?
    let celebrationTriggered: Bool
}

struct AchievementProgress: Codable, Equatable {
    let current: Double
    let target: Double
    let percentage: Double
    let lastUpdated: Date
    let milestones: [ProgressMilestone]
    
    var isCompleted: Bool {
        current >= target
    }
}

struct AchievementUnlock: Codable, Identifiable, Equatable {
    let id: String
    let achievementId: String
    let playerId: String
    let unlockedAt: Date
    let trigger: AchievementTrigger
    let context: AchievementContext?
    let rewards: AchievementRewards
    let isFirstTimeUnlock: Bool
    let celebrationTriggered: Bool
}

struct AchievementContext: Codable, Equatable {
    let sourceEvent: String
    let additionalData: [String: AnyCodable]
    let timestamp: Date
    let location: LocationContext?
    let courseId: String?
    let roundId: String?
}

// MARK: - Badge System Models

struct PlayerBadgeCollection: Codable, Equatable {
    let playerId: String
    let badges: [PlayerBadge]
    let totalBadges: Int
    let completionPercentage: Double
    let lastUpdated: Date
}

struct PlayerBadge: Codable, Identifiable, Equatable {
    let id: String
    let badgeId: String
    let playerId: String
    let tier: AchievementTier
    let acquiredAt: Date
    let progression: BadgeProgression
}

struct Badge: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let category: BadgeCategory
    let imageUrl: String
    let tiers: [BadgeTier]
    let requirements: BadgeRequirements
    let isExclusive: Bool
    let rarity: BadgeRarity
}

struct BadgeProgression: Codable, Equatable {
    let currentTier: AchievementTier
    let nextTier: AchievementTier?
    let progressToNext: Double
    let requirements: BadgeRequirements
    let canAdvance: Bool
}

struct BadgeAward: Codable, Identifiable, Equatable {
    let id: String
    let badgeId: String
    let playerId: String
    let tier: AchievementTier
    let awardedAt: Date
    let previousTier: AchievementTier?
    let celebration: BadgeCelebration
}

struct BadgeStatistics: Codable, Equatable {
    let badgeId: String
    let totalAwards: Int
    let tierDistribution: [AchievementTier: Int]
    let averageTimeToUnlock: TimeInterval
    let rarity: BadgeRarity
    let popularityRank: Int
}

// MARK: - Achievement Chain Models

struct AchievementChain: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let achievements: [String] // Achievement IDs in order
    let requiresSequential: Bool
    let rewards: ChainRewards
    let isComplete: Bool
    let completedAt: Date?
}

struct ChainProgression: Codable, Equatable {
    let chainId: String
    let currentPosition: Int
    let totalSteps: Int
    let completedAchievements: [String]
    let nextAchievement: String?
    let canAdvance: Bool
    let estimatedCompletion: Date?
}

struct ChainAdvancement: Codable, Identifiable, Equatable {
    let id: String
    let chainId: String
    let playerId: String
    let advancedAt: Date
    let newPosition: Int
    let unlockedAchievement: String?
    let chainCompleted: Bool
    let rewards: ChainRewards?
}

// MARK: - Milestone Models

struct MilestoneCelebration: Codable, Identifiable, Equatable {
    let id: String
    let milestone: GameMilestone
    let playerId: String
    let celebratedAt: Date
    let rewards: MilestoneRewards
    let hapticTriggered: Bool
    let sharedAutomatically: Bool
}

struct UpcomingMilestone: Codable, Identifiable, Equatable {
    let id: String
    let milestone: GameMilestone
    let progress: Double
    let estimatedCompletion: Date?
    let requirements: MilestoneRequirements
    let rewards: MilestoneRewards
}

struct ProgressMilestone: Codable, Equatable {
    let threshold: Double
    let reached: Bool
    let reachedAt: Date?
    let reward: MilestoneReward?
}

// MARK: - Service Integration Models

struct ScorecardEntry: Codable, Equatable {
    let id: String
    let playerId: String
    let courseId: String
    let totalScore: Int
    let date: Date
    let holeScores: [Int]
    let handicap: Double?
    let conditions: PlayingConditions
}

struct PerformanceMetrics: Codable, Equatable {
    let scoringAverage: Double
    let consistency: Double
    let improvement: Double
    let streaks: StreakData
    let strengths: [PerformanceStrength]
}

struct ChallengeResult: Codable, Equatable {
    let challengeId: String
    let playerId: String
    let position: Int
    let totalParticipants: Int
    let score: Int?
    let completedAt: Date
    let type: ChallengeType
}

struct SocialMetrics: Codable, Equatable {
    let challengesWon: Int
    let challengesParticipated: Int
    let friendsInvited: Int
    let communityContributions: Int
    let helpfulVotes: Int
}

struct LeaderboardResult: Codable, Equatable {
    let leaderboardId: String
    let playerId: String
    let position: Int
    let previousPosition: Int?
    let totalPlayers: Int
    let score: Double
    let updatedAt: Date
}

struct PositionMetrics: Codable, Equatable {
    let positionsGained: Int
    let bestPosition: Int
    let consistencyRating: Double
    let timeInTopTen: TimeInterval
    let timeInTopThree: TimeInterval
}

struct StreakData: Codable, Equatable {
    let parStreak: Int
    let birdieStreak: Int
    let consistencyStreak: Int
    let playingStreak: Int
    let currentStreaks: [StreakType: Int]
    let longestStreaks: [StreakType: Int]
}

// MARK: - Real-time & Background Processing Models

struct AchievementUpdate: Codable, Identifiable, Equatable {
    let id: String
    let playerId: String
    let updateType: AchievementUpdateType
    let achievementId: String?
    let data: [String: AnyCodable]
    let timestamp: Date
}

struct BackgroundProcessingResult: Codable, Equatable {
    let processedAchievements: [String]
    let newUnlocks: [AchievementUnlock]
    let progressUpdates: [AchievementProgress]
    let processingTime: TimeInterval
    let errors: [ProcessingError]
}

struct AchievementNotification: Codable, Identifiable, Equatable {
    let id: String
    let playerId: String
    let achievementId: String
    let type: NotificationType
    let priority: NotificationPriority
    let createdAt: Date
    let displayedAt: Date?
    let data: [String: AnyCodable]
}

// MARK: - Analytics & Engagement Models

struct PlayerEngagementMetrics: Codable, Equatable {
    let playerId: String
    let totalAchievements: Int
    let achievementsByCategory: [AchievementCategory: Int]
    let averageTimeToUnlock: TimeInterval
    let engagementScore: Double
    let lastActivityDate: Date
    let streakDays: Int
}

struct AchievementStatistics: Codable, Equatable {
    let totalAchievements: Int
    let totalUnlocks: Int
    let averageUnlocksPerPlayer: Double
    let mostPopularAchievements: [AchievementPopularity]
    let rarestAchievements: [RareAchievement]
    let unlockTrends: UnlockTrends
    let categoryDistribution: [AchievementCategory: Double]
}

struct AchievementJourney: Codable, Equatable {
    let playerId: String
    let timeline: [JourneyEvent]
    let totalProgress: Double
    let milestones: [JourneyMilestone]
    let predictions: [FutureAchievement]
    let personalBests: [PersonalBest]
}

// MARK: - Rarity & Exclusive Models

struct RareAchievement: Codable, Identifiable, Equatable {
    let id: String
    let achievement: Achievement
    let unlockRate: Double
    let totalUnlocks: Int
    let estimatedRarity: AchievementRarity
    let exclusivityFactor: Double
}

struct SeasonalAchievement: Codable, Identifiable, Equatable {
    let id: String
    let achievement: Achievement
    let season: AchievementSeason
    let startDate: Date
    let endDate: Date
    let isActive: Bool
    let completionBonus: SeasonalBonus?
}

struct LimitedTimeOpportunity: Codable, Identifiable, Equatable {
    let id: String
    let achievementId: String
    let timeRemaining: TimeInterval
    let requiredActions: [RequiredAction]
    let currentProgress: Double
    let estimatedDifficulty: DifficultyLevel
}

// MARK: - Social Features Models

struct AchievementShare: Codable, Identifiable, Equatable {
    let id: String
    let achievementId: String
    let playerId: String
    let sharedAt: Date
    let platform: SharePlatform
    let customMessage: String?
    let reactions: [ShareReaction]
}

struct FriendAchievementActivity: Codable, Identifiable, Equatable {
    let id: String
    let friendId: String
    let friendName: String
    let achievementId: String
    let activityType: ActivityType
    let activityDate: Date
    let isRecent: Bool
}

struct AchievementComparison: Codable, Equatable {
    let playerId: String
    let friendId: String
    let playerAchievements: Int
    let friendAchievements: Int
    let commonAchievements: [String]
    let playerExclusive: [String]
    let friendExclusive: [String]
    let comparisonScore: Double
}

struct AchievementLeaderboard: Codable, Equatable {
    let category: AchievementCategory?
    let entries: [LeaderboardEntry]
    let playerPosition: Int?
    let totalPlayers: Int
    let lastUpdated: Date
}

// MARK: - Performance Models

struct AchievementSystemMetrics: Codable, Equatable {
    let totalProcessingTime: TimeInterval
    let averageResponseTime: TimeInterval
    let cacheHitRate: Double
    let backgroundProcessingRate: Double
    let errorRate: Double
    let activeSubscriptions: Int
}

// MARK: - Supporting Enums

enum AchievementCategory: String, Codable, CaseIterable {
    case scoring = "scoring"
    case social = "social"
    case progress = "progress"
    case premium = "premium"
    case seasonal = "seasonal"
    case streak = "streak"
    case milestone = "milestone"
    case tournament = "tournament"
    case course = "course"
    case community = "community"
}

enum AchievementTier: String, Codable, CaseIterable {
    case bronze = "bronze"
    case silver = "silver"
    case gold = "gold"
    case platinum = "platinum"
    case diamond = "diamond"
    
    var sortOrder: Int {
        switch self {
        case .bronze: return 1
        case .silver: return 2
        case .gold: return 3
        case .platinum: return 4
        case .diamond: return 5
        }
    }
}

enum AchievementRarity: String, Codable, CaseIterable {
    case common = "common"
    case uncommon = "uncommon"
    case rare = "rare"
    case epic = "epic"
    case legendary = "legendary"
    case mythic = "mythic"
}

enum BadgeCategory: String, Codable, CaseIterable {
    case scorer = "scorer"
    case socialite = "socialite"
    case improver = "improver"
    case competitor = "competitor"
    case explorer = "explorer"
    case mentor = "mentor"
    case collector = "collector"
    case legend = "legend"
}

enum AchievementTrigger: String, Codable {
    case scoreSubmission = "score_submission"
    case challengeCompletion = "challenge_completion"
    case leaderboardPosition = "leaderboard_position"
    case streakAchievement = "streak_achievement"
    case manualUnlock = "manual_unlock"
    case systemProcessing = "system_processing"
    case socialActivity = "social_activity"
    case milestoneReached = "milestone_reached"
}

enum AchievementUpdateType: String, Codable {
    case unlocked = "unlocked"
    case progressUpdated = "progress_updated"
    case tierAdvanced = "tier_advanced"
    case chainCompleted = "chain_completed"
    case milestoneReached = "milestone_reached"
    case badgeAwarded = "badge_awarded"
}

enum NotificationType: String, Codable {
    case achievement = "achievement"
    case badge = "badge"
    case milestone = "milestone"
    case chain = "chain"
    case seasonal = "seasonal"
    case rare = "rare"
}

enum NotificationPriority: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum AchievementInteraction: String, Codable {
    case viewed = "viewed"
    case shared = "shared"
    case liked = "liked"
    case commented = "commented"
    case compared = "compared"
    case favorited = "favorited"
}

enum AchievementSeason: String, Codable {
    case spring = "spring"
    case summer = "summer"
    case fall = "fall"
    case winter = "winter"
    case holiday = "holiday"
    case tournament = "tournament"
}

enum SharePlatform: String, Codable {
    case internal = "internal"
    case social = "social"
    case message = "message"
    case email = "email"
}

enum ActivityType: String, Codable {
    case unlocked = "unlocked"
    case shared = "shared"
    case compared = "compared"
    case celebrated = "celebrated"
}

enum DifficultyLevel: String, Codable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"
    case expert = "expert"
    case legendary = "legendary"
}

// MARK: - Complex Supporting Models

struct AchievementRequirements: Codable, Equatable {
    let primary: RequirementCriteria
    let secondary: [RequirementCriteria]
    let minimumLevel: Int?
    let timeWindow: TimeInterval?
    let courseRestrictions: [String]?
    let groupRequirements: GroupRequirements?
}

struct RequirementCriteria: Codable, Equatable {
    let type: RequirementType
    let value: Double
    let operator: ComparisonOperator
    let dataSource: String
    let validationRules: [ValidationRule]
}

struct AchievementRewards: Codable, Equatable {
    let experiencePoints: Int
    let badges: [String]
    let premiumFeatures: [PremiumFeature]
    let socialRecognition: SocialRecognition
    let customRewards: [CustomReward]
}

struct LocationContext: Codable, Equatable {
    let courseId: String?
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date
}

struct BadgeRequirements: Codable, Equatable {
    let tierRequirements: [AchievementTier: TierRequirement]
    let prerequisites: [String]
    let exclusivityRules: [ExclusivityRule]
}

struct BadgeTier: Codable, Equatable {
    let tier: AchievementTier
    let requirements: TierRequirement
    let rewards: TierRewards
    let imageUrl: String
}

struct BadgeRarity: Codable, Equatable {
    let level: AchievementRarity
    let unlockPercentage: Double
    let estimatedPlayers: Int
}

struct BadgeCelebration: Codable, Equatable {
    let tier: AchievementTier
    let hapticPattern: String
    let visualEffects: [VisualEffect]
    let duration: TimeInterval
}

struct ChainRewards: Codable, Equatable {
    let completionBonuses: [CompletionBonus]
    let progressRewards: [ProgressReward]
    let exclusiveUnlocks: [String]
}

struct MilestoneRewards: Codable, Equatable {
    let experienceBonus: Int
    let specialBadges: [String]
    let unlockableContent: [UnlockableContent]
    let celebrationPackage: CelebrationPackage
}

struct MilestoneRequirements: Codable, Equatable {
    let targetValue: Double
    let timeframe: TimeInterval?
    let conditions: [MilestoneCondition]
    let validationCriteria: [ValidationCriterion]
}

struct MilestoneReward: Codable, Equatable {
    let type: RewardType
    let value: String
    let description: String
    let isRare: Bool
}

// Additional supporting types would continue here...
// Due to length constraints, I'm providing the essential structure

// MARK: - Placeholder Supporting Types

enum RequirementType: String, Codable {
    case score, streak, count, percentage, time, social
}

enum ComparisonOperator: String, Codable {
    case equal, greaterThan, lessThan, greaterThanOrEqual, lessThanOrEqual
}

enum RewardType: String, Codable {
    case badge, experience, unlock, recognition
}

struct ValidationRule: Codable, Equatable {
    let rule: String
    let parameters: [String: AnyCodable]
}

struct GroupRequirements: Codable, Equatable {
    let minimumParticipants: Int
    let allowedGroups: [String]
}

struct PremiumFeature: Codable, Equatable {
    let featureId: String
    let duration: TimeInterval?
}

struct SocialRecognition: Codable, Equatable {
    let publicAnnouncement: Bool
    let leaderboardHighlight: Bool
    let friendNotification: Bool
}

struct CustomReward: Codable, Equatable {
    let id: String
    let type: String
    let value: String
}

struct TierRequirement: Codable, Equatable {
    let criteria: [RequirementCriteria]
    let minimumAchievements: Int
}

struct ExclusivityRule: Codable, Equatable {
    let rule: String
    let parameters: [String: AnyCodable]
}

struct TierRewards: Codable, Equatable {
    let experiencePoints: Int
    let specialFeatures: [String]
}

struct VisualEffect: Codable, Equatable {
    let type: String
    let duration: TimeInterval
}

struct CompletionBonus: Codable, Equatable {
    let type: String
    let value: Int
}

struct ProgressReward: Codable, Equatable {
    let percentage: Double
    let reward: String
}

struct UnlockableContent: Codable, Equatable {
    let contentId: String
    let type: String
}

struct CelebrationPackage: Codable, Equatable {
    let theme: String
    let effects: [VisualEffect]
    let duration: TimeInterval
}

struct MilestoneCondition: Codable, Equatable {
    let condition: String
    let value: Double
}

struct ValidationCriterion: Codable, Equatable {
    let criterion: String
    let required: Bool
}

struct SeasonalInfo: Codable, Equatable {
    let season: AchievementSeason
    let startDate: Date
    let endDate: Date
}

struct SeasonalBonus: Codable, Equatable {
    let multiplier: Double
    let bonusRewards: [String]
}

struct RequiredAction: Codable, Equatable {
    let action: String
    let target: Double
    let current: Double
}

struct ShareReaction: Codable, Equatable {
    let playerId: String
    let reaction: String
    let timestamp: Date
}

struct LeaderboardEntry: Codable, Equatable {
    let playerId: String
    let playerName: String
    let achievements: Int
    let position: Int
}

struct AchievementPopularity: Codable, Equatable {
    let achievementId: String
    let unlockCount: Int
    let popularityScore: Double
}

struct UnlockTrends: Codable, Equatable {
    let dailyUnlocks: [Date: Int]
    let trendDirection: String
    let growthRate: Double
}

struct JourneyEvent: Codable, Equatable {
    let timestamp: Date
    let type: String
    let description: String
}

struct JourneyMilestone: Codable, Equatable {
    let milestone: String
    let achievedAt: Date
    let significance: String
}

struct FutureAchievement: Codable, Equatable {
    let achievementId: String
    let estimatedDate: Date
    let probability: Double
}

struct PersonalBest: Codable, Equatable {
    let category: String
    let value: Double
    let achievedAt: Date
}

struct AchievementShareOptions: Codable, Equatable {
    let platforms: [SharePlatform]
    let includeMessage: Bool
    let includeImage: Bool
    let customMessage: String?
}

struct PerformanceStrength: Codable, Equatable {
    let area: String
    let rating: Double
    let trend: String
}

enum ChallengeType: String, Codable {
    case individual, group, tournament, social
}

struct ProcessingError: Codable, Equatable {
    let error: String
    let context: String
    let timestamp: Date
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable, Equatable {
    let value: Any
    
    init<T: Codable>(_ value: T) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unsupported type"))
        }
    }
    
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simplified equality check
        return String(describing: lhs.value) == String(describing: rhs.value)
    }
}