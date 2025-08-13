import Foundation
import Combine

// MARK: - Leaderboard Service Protocol

protocol LeaderboardServiceProtocol {
    // MARK: - Leaderboard Management
    
    /// Fetches leaderboards for a specific course
    func getLeaderboards(for courseId: String) async throws -> [Leaderboard]
    
    /// Fetches a specific leaderboard by ID
    func getLeaderboard(id: String) async throws -> Leaderboard
    
    /// Creates a new leaderboard
    func createLeaderboard(_ leaderboard: Leaderboard) async throws -> Leaderboard
    
    /// Updates an existing leaderboard
    func updateLeaderboard(_ leaderboard: Leaderboard) async throws -> Leaderboard
    
    /// Deletes a leaderboard
    func deleteLeaderboard(id: String) async throws
    
    // MARK: - Entry Management
    
    /// Submits a new leaderboard entry
    func submitEntry(_ entry: LeaderboardEntry) async throws -> LeaderboardEntry
    
    /// Updates an existing entry
    func updateEntry(_ entry: LeaderboardEntry) async throws -> LeaderboardEntry
    
    /// Gets entries for a specific leaderboard
    func getEntries(for leaderboardId: String, limit: Int?, offset: Int?) async throws -> [LeaderboardEntry]
    
    /// Gets a player's entry for a specific leaderboard
    func getPlayerEntry(leaderboardId: String, playerId: String) async throws -> LeaderboardEntry?
    
    /// Removes a player's entry from a leaderboard
    func removeEntry(leaderboardId: String, playerId: String) async throws
    
    // MARK: - Real-time Subscriptions
    
    /// Subscribes to real-time updates for a leaderboard
    func subscribeToLeaderboard(_ leaderboardId: String) -> AnyPublisher<LeaderboardUpdate, Error>
    
    /// Subscribes to all leaderboards for a course
    func subscribeToLeaderboards(courseId: String) -> AnyPublisher<[Leaderboard], Error>
    
    /// Unsubscribes from leaderboard updates
    func unsubscribeFromLeaderboard(_ leaderboardId: String)
    
    /// Unsubscribes from all active subscriptions
    func unsubscribeFromAll()
    
    // MARK: - Rankings & Statistics
    
    /// Gets current rankings for a leaderboard
    func getRankings(for leaderboardId: String) async throws -> [LeaderboardEntry]
    
    /// Gets player's current position in a leaderboard
    func getPlayerPosition(leaderboardId: String, playerId: String) async throws -> Int?
    
    /// Gets leaderboard statistics
    func getLeaderboardStats(for leaderboardId: String) async throws -> LeaderboardStats
    
    /// Gets trending leaderboards for a course
    func getTrendingLeaderboards(courseId: String) async throws -> [Leaderboard]
    
    // MARK: - Social Features
    
    /// Creates a social challenge
    func createChallenge(_ challenge: SocialChallenge) async throws -> SocialChallenge
    
    /// Joins a social challenge
    func joinChallenge(challengeId: String, playerId: String) async throws
    
    /// Gets challenges for a player
    func getPlayerChallenges(playerId: String) async throws -> [SocialChallenge]
    
    /// Gets public challenges for a course
    func getPublicChallenges(courseId: String) async throws -> [SocialChallenge]
    
    /// Invites friends to a challenge
    func inviteToChallenge(challengeId: String, playerIds: [String]) async throws
    
    // MARK: - Achievements
    
    /// Gets achievements for a player
    func getPlayerAchievements(playerId: String) async throws -> [Achievement]
    
    /// Awards an achievement to a player
    func awardAchievement(_ achievement: Achievement, to playerId: String) async throws
    
    /// Gets available achievements for a course
    func getAvailableAchievements(courseId: String) async throws -> [Achievement]
    
    // MARK: - Search & Filtering
    
    /// Searches leaderboards by name or description
    func searchLeaderboards(query: String, courseId: String?) async throws -> [Leaderboard]
    
    /// Filters leaderboards by type and period
    func filterLeaderboards(
        courseId: String?,
        type: LeaderboardType?,
        period: LeaderboardPeriod?,
        isActive: Bool?
    ) async throws -> [Leaderboard]
    
    /// Gets nearby leaderboards based on location
    func getNearbyLeaderboards(
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> [Leaderboard]
    
    // MARK: - Performance Analytics
    
    /// Gets player performance over time
    func getPlayerPerformance(
        playerId: String,
        courseId: String?,
        dateRange: DateInterval?
    ) async throws -> PlayerPerformanceData
    
    /// Compares player performance with others
    func comparePlayerPerformance(
        playerId: String,
        compareWith: [String],
        courseId: String?
    ) async throws -> PerformanceComparison
    
    // MARK: - Cache Management
    
    /// Clears cached leaderboard data
    func clearCache()
    
    /// Refreshes cached data for a specific leaderboard
    func refreshCache(for leaderboardId: String) async throws
    
    /// Gets cached entries count
    func getCachedEntriesCount() -> Int
}

// MARK: - Supporting Types

struct LeaderboardUpdate {
    let leaderboardId: String
    let type: UpdateType
    let entry: LeaderboardEntry?
    let timestamp: Date
    
    enum UpdateType {
        case entryAdded
        case entryUpdated
        case entryRemoved
        case positionsChanged
        case leaderboardUpdated
    }
}

struct PlayerPerformanceData {
    let playerId: String
    let courseId: String?
    let dateRange: DateInterval
    let rounds: [RoundPerformance]
    let averageScore: Double
    let bestScore: Int
    let worstScore: Int
    let improvement: Double
    let consistency: Double
    let strengths: [PerformanceArea]
    let weaknesses: [PerformanceArea]
}

struct RoundPerformance {
    let roundId: String
    let date: Date
    let score: Int
    let scoreToPar: Int
    let fairwaysHit: Int?
    let greensInRegulation: Int?
    let putts: Int?
    let penalties: Int?
    let highlights: [String]
}

struct PerformanceArea {
    let category: PerformanceCategory
    let score: Double
    let percentile: Double
    let improvement: Double?
    
    enum PerformanceCategory: String, CaseIterable {
        case driving = "driving"
        case approach = "approach"
        case shortGame = "short_game"
        case putting = "putting"
        case courseManagement = "course_management"
        case consistency = "consistency"
    }
}

struct PerformanceComparison {
    let player: PlayerPerformanceData
    let comparisons: [ComparisonData]
    let rankings: ComparisonRankings
}

struct ComparisonData {
    let playerId: String
    let playerName: String
    let performance: PlayerPerformanceData
    let difference: Double
    let betterAreas: [PerformanceArea]
    let worseAreas: [PerformanceArea]
}

struct ComparisonRankings {
    let overall: Int
    let driving: Int
    let approach: Int
    let shortGame: Int
    let putting: Int
    let consistency: Int
}