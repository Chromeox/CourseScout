import Foundation
import Combine

// MARK: - Social Challenge Service Protocol

protocol SocialChallengeServiceProtocol {
    // MARK: - Challenge Management
    
    /// Creates a new social challenge
    func createChallenge(_ challenge: SocialChallenge) async throws -> SocialChallenge
    
    /// Gets a specific challenge by ID
    func getChallenge(id: String) async throws -> SocialChallenge
    
    /// Updates an existing challenge
    func updateChallenge(_ challenge: SocialChallenge) async throws -> SocialChallenge
    
    /// Deletes a challenge (creator only)
    func deleteChallenge(id: String, requesterId: String) async throws
    
    /// Gets challenges for a specific course
    func getChallenges(for courseId: String, filters: ChallengeFilters?) async throws -> [SocialChallenge]
    
    /// Gets challenges created by a player
    func getCreatedChallenges(by playerId: String) async throws -> [SocialChallenge]
    
    /// Gets challenges a player is participating in
    func getParticipatingChallenges(for playerId: String) async throws -> [SocialChallenge]
    
    // MARK: - Challenge Participation
    
    /// Joins a public challenge
    func joinChallenge(challengeId: String, playerId: String) async throws -> ChallengeParticipation
    
    /// Accepts a challenge invitation
    func acceptInvitation(challengeId: String, playerId: String, invitationId: String) async throws -> ChallengeParticipation
    
    /// Declines a challenge invitation
    func declineInvitation(challengeId: String, playerId: String, invitationId: String) async throws
    
    /// Leaves a challenge (before completion)
    func leaveChallenge(challengeId: String, playerId: String) async throws
    
    /// Submits a score for a challenge
    func submitChallengeScore(challengeId: String, playerId: String, scoreSubmission: ChallengeScoreSubmission) async throws -> ChallengeScore
    
    // MARK: - Challenge Invitations
    
    /// Invites players to a challenge
    func inviteToChallenge(challengeId: String, inviterId: String, inviteeIds: [String], message: String?) async throws -> [ChallengeInvitation]
    
    /// Gets pending invitations for a player
    func getPendingInvitations(for playerId: String) async throws -> [ChallengeInvitation]
    
    /// Gets sent invitations for a challenge
    func getSentInvitations(for challengeId: String) async throws -> [ChallengeInvitation]
    
    /// Cancels a pending invitation
    func cancelInvitation(invitationId: String, senderId: String) async throws
    
    // MARK: - Head-to-Head Challenges
    
    /// Creates a direct head-to-head challenge between two players
    func createHeadToHeadChallenge(challengerId: String, opponentId: String, challengeDetails: HeadToHeadChallengeDetails) async throws -> HeadToHeadChallenge
    
    /// Accepts a head-to-head challenge
    func acceptHeadToHeadChallenge(challengeId: String, accepterId: String) async throws -> HeadToHeadChallenge
    
    /// Declines a head-to-head challenge
    func declineHeadToHeadChallenge(challengeId: String, declinerId: String, reason: String?) async throws
    
    /// Gets head-to-head history between players
    func getHeadToHeadHistory(player1Id: String, player2Id: String) async throws -> HeadToHeadHistory
    
    // MARK: - Tournament Management
    
    /// Creates a tournament-style challenge
    func createTournament(_ tournament: TournamentChallenge) async throws -> TournamentChallenge
    
    /// Registers for a tournament
    func registerForTournament(tournamentId: String, playerId: String, registrationData: TournamentRegistration) async throws -> TournamentRegistration
    
    /// Gets tournament leaderboard
    func getTournamentLeaderboard(tournamentId: String) async throws -> TournamentLeaderboard
    
    /// Advances tournament to next round (bracket tournaments)
    func advanceTournamentRound(tournamentId: String, adminId: String) async throws -> TournamentRound
    
    /// Finalizes tournament results
    func finalizeTournament(tournamentId: String, adminId: String) async throws -> TournamentResult
    
    // MARK: - Challenge Scoring & Results
    
    /// Gets current standings for a challenge
    func getChallengeStandings(challengeId: String) async throws -> ChallengeStandings
    
    /// Gets detailed results for a completed challenge
    func getChallengeResults(challengeId: String) async throws -> ChallengeResults
    
    /// Awards prizes for completed challenges
    func awardPrizes(challengeId: String, adminId: String) async throws -> [PrizeAward]
    
    /// Gets challenge statistics and analytics
    func getChallengeAnalytics(challengeId: String) async throws -> ChallengeAnalytics
    
    // MARK: - Friend Challenges
    
    /// Gets friend challenges (challenges with friends)
    func getFriendChallenges(for playerId: String) async throws -> [FriendChallenge]
    
    /// Creates a challenge with specific friends
    func createFriendChallenge(creatorId: String, friendIds: [String], challengeData: FriendChallengeData) async throws -> FriendChallenge
    
    /// Gets challenge recommendations based on friends and activity
    func getRecommendedChallenges(for playerId: String) async throws -> [ChallengeRecommendation]
    
    // MARK: - Real-time Updates
    
    /// Subscribes to real-time challenge updates
    func subscribeToChallenge(challengeId: String) -> AnyPublisher<ChallengeUpdate, Error>
    
    /// Subscribes to player's challenge activity
    func subscribeToPlayerChallenges(playerId: String) -> AnyPublisher<PlayerChallengeUpdate, Error>
    
    /// Subscribes to tournament updates
    func subscribeToTournament(tournamentId: String) -> AnyPublisher<TournamentUpdate, Error>
    
    /// Unsubscribes from challenge updates
    func unsubscribeFromChallenge(challengeId: String)
    
    /// Unsubscribes from all active subscriptions
    func unsubscribeFromAll()
    
    // MARK: - Challenge Discovery
    
    /// Searches for challenges
    func searchChallenges(query: String, filters: ChallengeSearchFilters?) async throws -> [SocialChallenge]
    
    /// Gets trending challenges
    func getTrendingChallenges(courseId: String?, limit: Int?) async throws -> [SocialChallenge]
    
    /// Gets featured challenges
    func getFeaturedChallenges() async throws -> [SocialChallenge]
    
    /// Gets challenges by category
    func getChallengesByCategory(_ category: ChallengeCategory) async throws -> [SocialChallenge]
    
    // MARK: - Challenge Templates
    
    /// Gets available challenge templates
    func getChallengeTemplates() async throws -> [ChallengeTemplate]
    
    /// Creates a challenge from template
    func createChallengeFromTemplate(templateId: String, creatorId: String, customizations: TemplateCustomizations) async throws -> SocialChallenge
    
    /// Saves a custom challenge as template
    func saveAsTemplate(challengeId: String, creatorId: String, templateName: String) async throws -> ChallengeTemplate
}

// MARK: - Supporting Data Models

struct ChallengeFilters: Codable {
    let status: ChallengeStatus?
    let type: ChallengeType?
    let skillLevel: SkillLevel?
    let entryFee: EntryFeeRange?
    let duration: DurationRange?
    let participantCount: ParticipantRange?
    let isPublic: Bool?
    let hasSpots: Bool?
    
    enum ChallengeStatus: String, Codable, CaseIterable {
        case open = "open"
        case inProgress = "in_progress"
        case completed = "completed"
        case cancelled = "cancelled"
    }
    
    enum ChallengeType: String, Codable, CaseIterable {
        case strokePlay = "stroke_play"
        case matchPlay = "match_play"
        case longestDrive = "longest_drive"
        case closestToPin = "closest_to_pin"
        case skillsChallenge = "skills_challenge"
        case tournament = "tournament"
        case headToHead = "head_to_head"
        case teamChallenge = "team_challenge"
    }
    
    enum SkillLevel: String, Codable, CaseIterable {
        case beginner = "beginner"
        case intermediate = "intermediate"
        case advanced = "advanced"
        case expert = "expert"
        case any = "any"
    }
    
    struct EntryFeeRange: Codable {
        let min: Double
        let max: Double
    }
    
    struct DurationRange: Codable {
        let min: TimeInterval
        let max: TimeInterval
    }
    
    struct ParticipantRange: Codable {
        let min: Int
        let max: Int
    }
}

struct ChallengeParticipation: Identifiable, Codable {
    let id: String
    let challengeId: String
    let playerId: String
    let joinedAt: Date
    let status: ParticipationStatus
    let scores: [ChallengeScore]
    let currentPosition: Int?
    let achievements: [ChallengeAchievement]
    
    enum ParticipationStatus: String, Codable {
        case active = "active"
        case completed = "completed"
        case withdrawn = "withdrawn"
        case disqualified = "disqualified"
    }
}

struct ChallengeScoreSubmission: Codable {
    let roundId: String?
    let courseId: String
    let score: Int
    let holesPlayed: Int
    let submittedAt: Date
    let verificationData: ScoreVerificationData?
    let holeByHole: [HoleScore]?
}

struct ScoreVerificationData: Codable {
    let gpsLocation: GPSLocation?
    let playingPartners: [PlayingPartner]?
    let photoEvidence: [String]? // Photo URLs
    let timestamp: Date
    let deviceId: String
    
    struct GPSLocation: Codable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
    }
    
    struct PlayingPartner: Codable {
        let playerId: String?
        let name: String
        let handicap: Double?
    }
}

struct HoleScore: Codable {
    let holeNumber: Int
    let score: Int
    let par: Int
    let putts: Int?
    let fairwayHit: Bool?
    let greenInRegulation: Bool?
    let penaltyStrokes: Int?
}

struct ChallengeScore: Identifiable, Codable {
    let id: String
    let participationId: String
    let roundId: String?
    let score: Int
    let netScore: Int?
    let submittedAt: Date
    let verifiedAt: Date?
    let status: ScoreStatus
    let holeByHole: [HoleScore]?
    
    enum ScoreStatus: String, Codable {
        case pending = "pending"
        case verified = "verified"
        case disputed = "disputed"
        case rejected = "rejected"
    }
}

struct ChallengeInvitation: Identifiable, Codable {
    let id: String
    let challengeId: String
    let senderId: String
    let senderName: String
    let recipientId: String
    let message: String?
    let sentAt: Date
    let status: InvitationStatus
    let expiresAt: Date?
    
    enum InvitationStatus: String, Codable {
        case pending = "pending"
        case accepted = "accepted"
        case declined = "declined"
        case expired = "expired"
        case cancelled = "cancelled"
    }
}

struct HeadToHeadChallenge: Identifiable, Codable {
    let id: String
    let challengerId: String
    let opponentId: String
    let details: HeadToHeadChallengeDetails
    let status: HeadToHeadStatus
    let createdAt: Date
    let acceptedAt: Date?
    let completedAt: Date?
    let winner: String?
    let results: HeadToHeadResults?
    
    enum HeadToHeadStatus: String, Codable {
        case pending = "pending"
        case accepted = "accepted"
        case declined = "declined"
        case inProgress = "in_progress"
        case completed = "completed"
        case expired = "expired"
    }
}

struct HeadToHeadChallengeDetails: Codable {
    let title: String
    let description: String?
    let courseId: String
    let gameType: HeadToHeadGameType
    let stakes: ChallengeStakes?
    let deadline: Date
    let rules: [ChallengeRule]
    
    enum HeadToHeadGameType: String, Codable {
        case strokePlay = "stroke_play"
        case matchPlay = "match_play"
        case longestDrive = "longest_drive"
        case closestToPin = "closest_to_pin"
        case bestBall = "best_ball"
    }
}

struct ChallengeStakes: Codable {
    let type: StakeType
    let amount: Double?
    let description: String
    
    enum StakeType: String, Codable {
        case braggingRights = "bragging_rights"
        case monetary = "monetary"
        case prize = "prize"
        case points = "points"
        case custom = "custom"
    }
}

struct ChallengeRule: Codable {
    let id: String
    let title: String
    let description: String
    let mandatory: Bool
}

struct HeadToHeadResults: Codable {
    let challengerScore: ChallengeScore
    let opponentScore: ChallengeScore
    let scoreDifference: Int
    let matchDetails: MatchDetails?
    
    struct MatchDetails: Codable {
        let holes: [MatchHole]
        let finalResult: String // "3&2", "1 up", etc.
        
        struct MatchHole: Codable {
            let holeNumber: Int
            let challengerScore: Int
            let opponentScore: Int
            let winner: String? // "challenger", "opponent", "tie"
            let matchStatus: String // "1 up", "AS", "2 down", etc.
        }
    }
}

struct HeadToHeadHistory: Codable {
    let player1Id: String
    let player2Id: String
    let totalChallenges: Int
    let player1Wins: Int
    let player2Wins: Int
    let ties: Int
    let winPercentages: (player1: Double, player2: Double)
    let recentChallenges: [HeadToHeadChallenge]
    let averageScoreDifference: Double
    let longestWinStreak: (playerId: String, streak: Int)
    let favoriteMatchups: [String] // Course names
}

struct TournamentChallenge: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let creatorId: String
    let courseId: String
    let format: TournamentFormat
    let structure: TournamentStructure
    let entryFee: Double?
    let prizePool: Double?
    let maxParticipants: Int
    let registrationDeadline: Date
    let startDate: Date
    let endDate: Date
    let status: TournamentStatus
    let rules: [ChallengeRule]
    let sponsors: [TournamentSponsor]?
    
    enum TournamentFormat: String, Codable {
        case strokePlay = "stroke_play"
        case matchPlay = "match_play"
        case scramble = "scramble"
        case bestBall = "best_ball"
        case stableford = "stableford"
    }
    
    enum TournamentStructure: String, Codable {
        case singleElimination = "single_elimination"
        case doubleElimination = "double_elimination"
        case roundRobin = "round_robin"
        case flightPlay = "flight_play"
        case medalPlay = "medal_play"
    }
    
    enum TournamentStatus: String, Codable {
        case draft = "draft"
        case open = "open"
        case closed = "closed"
        case inProgress = "in_progress"
        case completed = "completed"
        case cancelled = "cancelled"
    }
}

struct TournamentSponsor: Codable {
    let name: String
    let logoUrl: String?
    let website: String?
    let sponsorshipLevel: SponsorshipLevel
    let prizeContribution: Double?
    
    enum SponsorshipLevel: String, Codable {
        case title = "title"
        case presenting = "presenting"
        case major = "major"
        case supporting = "supporting"
    }
}

struct TournamentRegistration: Identifiable, Codable {
    let id: String
    let tournamentId: String
    let playerId: String
    let registeredAt: Date
    let handicap: Double?
    let flightAssignment: String?
    let paymentStatus: PaymentStatus
    let emergencyContact: EmergencyContact?
    
    enum PaymentStatus: String, Codable {
        case pending = "pending"
        case paid = "paid"
        case refunded = "refunded"
        case waived = "waived"
    }
    
    struct EmergencyContact: Codable {
        let name: String
        let phone: String
        let relationship: String
    }
}

struct TournamentLeaderboard: Codable {
    let tournamentId: String
    let currentRound: Int
    let totalRounds: Int
    let leaderboard: [TournamentLeaderboardEntry]
    let cutLine: Int?
    let updatedAt: Date
}

struct TournamentLeaderboardEntry: Codable {
    let position: Int
    let playerId: String
    let playerName: String
    let totalScore: Int
    let scoreToPar: Int
    let roundScores: [Int]
    let today: Int? // Today's score
    let earnings: Double?
}

struct TournamentRound: Codable {
    let roundNumber: Int
    let startDate: Date
    let endDate: Date
    let matchups: [TournamentMatchup]?
    let leaderboard: TournamentLeaderboard?
    
    struct TournamentMatchup: Codable {
        let id: String
        let player1Id: String
        let player2Id: String
        let teeTime: Date?
        let result: MatchResult?
        
        struct MatchResult: Codable {
            let winnerId: String?
            let scores: (player1: Int, player2: Int)?
            let matchResult: String? // For match play
        }
    }
}

struct TournamentResult: Codable {
    let tournamentId: String
    let winner: TournamentWinner
    let finalLeaderboard: TournamentLeaderboard
    let prizeDistribution: [PrizeDistribution]
    let statistics: TournamentStatistics
    let completedAt: Date
    
    struct TournamentWinner: Codable {
        let playerId: String
        let playerName: String
        let totalScore: Int
        let scoreToPar: Int
        let winningMargin: Int
        let playoff: Bool
    }
    
    struct PrizeDistribution: Codable {
        let position: Int
        let playerId: String
        let amount: Double
        let type: PrizeType
        
        enum PrizeType: String, Codable {
            case cash = "cash"
            case merchandise = "merchandise"
            case credit = "credit"
            case trophy = "trophy"
        }
    }
    
    struct TournamentStatistics: Codable {
        let totalParticipants: Int
        let completionRate: Double
        let averageScore: Double
        let lowestRound: Int
        let mostBirdies: Int
        let longestDrive: Double?
        let closestToPin: Double?
    }
}

struct ChallengeStandings: Codable {
    let challengeId: String
    let standings: [ChallengeStandingEntry]
    let lastUpdated: Date
    
    struct ChallengeStandingEntry: Codable {
        let position: Int
        let playerId: String
        let playerName: String
        let score: Int?
        let progress: ChallengeProgress
        let achievements: [ChallengeAchievement]
    }
}

struct ChallengeProgress: Codable {
    let completed: Bool
    let percentComplete: Double
    let remainingTime: TimeInterval?
    let status: String
}

struct ChallengeAchievement: Identifiable, Codable {
    let id: String
    let type: AchievementType
    let earnedAt: Date
    let description: String
    
    enum AchievementType: String, Codable {
        case firstPlace = "first_place"
        case personalBest = "personal_best"
        case comeback = "comeback"
        case consistency = "consistency"
        case participation = "participation"
        case sportsmanship = "sportsmanship"
    }
}

struct ChallengeResults: Codable {
    let challengeId: String
    let finalStandings: ChallengeStandings
    let winners: [ChallengeWinner]
    let statistics: ChallengeStatistics
    let highlights: [ChallengeHighlight]
    let completedAt: Date
    
    struct ChallengeWinner: Codable {
        let playerId: String
        let playerName: String
        let category: WinnerCategory
        let score: Int?
        let achievement: String
        
        enum WinnerCategory: String, Codable {
            case overall = "overall"
            case net = "net"
            case mostImproved = "most_improved"
            case closest = "closest"
            case longest = "longest"
        }
    }
    
    struct ChallengeStatistics: Codable {
        let totalParticipants: Int
        let completionRate: Double
        let averageScore: Double?
        let scoreRange: (min: Int, max: Int)?
        let improvementRate: Double
        let engagementMetrics: EngagementMetrics
        
        struct EngagementMetrics: Codable {
            let dailyActiveParticipants: [Date: Int]
            let messagesSent: Int
            let photosShared: Int
            let averageSessionTime: TimeInterval
        }
    }
    
    struct ChallengeHighlight: Codable {
        let type: HighlightType
        let playerId: String
        let description: String
        let value: String
        let timestamp: Date
        
        enum HighlightType: String, Codable {
            case scorePosted = "score_posted"
            case leaderChange = "leader_change"
            case achievement = "achievement"
            case comeback = "comeback"
            case milestone = "milestone"
        }
    }
}

struct PrizeAward: Codable {
    let recipientId: String
    let prize: ChallengePrize
    let awardedAt: Date
    let distributionStatus: DistributionStatus
    let distributionDate: Date?
    
    enum DistributionStatus: String, Codable {
        case pending = "pending"
        case distributed = "distributed"
        case failed = "failed"
        case refunded = "refunded"
    }
}

struct ChallengeAnalytics: Codable {
    let challengeId: String
    let participantMetrics: ParticipantMetrics
    let engagementMetrics: EngagementMetrics
    let performanceMetrics: PerformanceMetrics
    let retentionMetrics: RetentionMetrics
    
    struct ParticipantMetrics: Codable {
        let totalInvited: Int
        let totalJoined: Int
        let conversionRate: Double
        let dropoutRate: Double
        let averageHandicap: Double
        let skillLevelDistribution: [String: Int]
    }
    
    struct EngagementMetrics: Codable {
        let messagesPerParticipant: Double
        let photosPerParticipant: Double
        let averageSessionLength: TimeInterval
        let dailyActiveUsers: [Date: Int]
        let peakEngagementTime: Date?
    }
    
    struct PerformanceMetrics: Codable {
        let averageScoreImprovement: Double
        let handicapImpacts: [String: Double]
        let achievementDistribution: [String: Int]
        let completionTimes: [TimeInterval]
    }
    
    struct RetentionMetrics: Codable {
        let returnParticipantRate: Double
        let referralRate: Double
        let satisfactionScore: Double?
        let likelihoodToRecommend: Double?
    }
}

struct FriendChallenge: Identifiable, Codable {
    let id: String
    let creatorId: String
    let friendIds: [String]
    let challengeData: FriendChallengeData
    let status: ChallengeStatus
    let createdAt: Date
    let participants: [ChallengeParticipation]
    let currentLeader: String?
    
    enum ChallengeStatus: String, Codable {
        case active = "active"
        case completed = "completed"
        case cancelled = "cancelled"
    }
}

struct FriendChallengeData: Codable {
    let title: String
    let description: String?
    let challengeType: ChallengeFilters.ChallengeType
    let duration: TimeInterval
    let courseId: String?
    let target: ChallengeTarget
    let stakes: ChallengeStakes?
    
    struct ChallengeTarget: Codable {
        let type: TargetType
        let value: Double
        let unit: String
        
        enum TargetType: String, Codable {
            case score = "score"
            case improvement = "improvement"
            case distance = "distance"
            case accuracy = "accuracy"
            case consistency = "consistency"
        }
    }
}

struct ChallengeRecommendation: Identifiable, Codable {
    let id: String
    let challengeId: String
    let title: String
    let description: String
    let recommendationScore: Double
    let reasons: [RecommendationReason]
    let estimatedCompletionTime: TimeInterval
    let skillMatchScore: Double
    
    struct RecommendationReason: Codable {
        let reason: String
        let weight: Double
        let explanation: String
    }
}

struct ChallengeUpdate: Codable {
    let challengeId: String
    let updateType: UpdateType
    let playerId: String?
    let data: [String: AnyCodable]
    let timestamp: Date
    
    enum UpdateType: String, Codable {
        case scoreSubmitted = "score_submitted"
        case participantJoined = "participant_joined"
        case participantLeft = "participant_left"
        case leaderboardChanged = "leaderboard_changed"
        case challengeCompleted = "challenge_completed"
        case messagePosted = "message_posted"
        case achievementEarned = "achievement_earned"
    }
}

struct PlayerChallengeUpdate: Codable {
    let playerId: String
    let challengeId: String
    let updateType: PlayerUpdateType
    let data: [String: AnyCodable]
    let timestamp: Date
    
    enum PlayerUpdateType: String, Codable {
        case invitationReceived = "invitation_received"
        case challengeStarted = "challenge_started"
        case positionChanged = "position_changed"
        case achievementEarned = "achievement_earned"
        case challengeCompleted = "challenge_completed"
        case reminderDue = "reminder_due"
    }
}

struct TournamentUpdate: Codable {
    let tournamentId: String
    let updateType: TournamentUpdateType
    let data: [String: AnyCodable]
    let timestamp: Date
    
    enum TournamentUpdateType: String, Codable {
        case registrationOpened = "registration_opened"
        case registrationClosed = "registration_closed"
        case roundStarted = "round_started"
        case roundCompleted = "round_completed"
        case leaderboardUpdated = "leaderboard_updated"
        case cutMade = "cut_made"
        case tournamentCompleted = "tournament_completed"
        case payoutDistributed = "payout_distributed"
    }
}

struct ChallengeSearchFilters: Codable {
    let query: String?
    let courseId: String?
    let creatorId: String?
    let skillLevel: ChallengeFilters.SkillLevel?
    let type: ChallengeFilters.ChallengeType?
    let hasEntryFee: Bool?
    let maxEntryFee: Double?
    let startDate: DateRange?
    let participantCount: ChallengeFilters.ParticipantRange?
    let tags: [String]?
    
    struct DateRange: Codable {
        let start: Date
        let end: Date
    }
}

enum ChallengeCategory: String, Codable, CaseIterable {
    case competitive = "competitive"
    case social = "social"
    case skillBuilding = "skill_building"
    case fundraising = "fundraising"
    case corporate = "corporate"
    case beginner = "beginner"
    case seasonal = "seasonal"
    case local = "local"
}

struct ChallengeTemplate: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let creatorId: String
    let category: ChallengeCategory
    let templateData: TemplateData
    let popularity: Int
    let rating: Double
    let tags: [String]
    let createdAt: Date
    
    struct TemplateData: Codable {
        let challengeType: ChallengeFilters.ChallengeType
        let duration: TimeInterval
        let maxParticipants: Int
        let rules: [ChallengeRule]
        let scoringMethod: ScoringMethod
        let prizeStructure: PrizeStructure?
        
        enum ScoringMethod: String, Codable {
            case lowest = "lowest"
            case highest = "highest"
            case target = "target"
            case improvement = "improvement"
            case consistency = "consistency"
        }
        
        struct PrizeStructure: Codable {
            let distribution: [Int: Double] // Position -> Percentage
            let minimumPrizePool: Double?
        }
    }
}

struct TemplateCustomizations: Codable {
    let name: String?
    let description: String?
    let courseId: String?
    let startDate: Date?
    let endDate: Date?
    let maxParticipants: Int?
    let entryFee: Double?
    let customRules: [ChallengeRule]?
    let isPublic: Bool?
    let inviteOnly: Bool?
}