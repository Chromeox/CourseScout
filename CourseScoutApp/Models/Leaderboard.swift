import Foundation
import CoreLocation

// MARK: - Leaderboard Models

struct Leaderboard: Identifiable, Codable, Equatable {
    let id: String
    let courseId: String
    let name: String
    let description: String?
    let type: LeaderboardType
    let period: LeaderboardPeriod
    let maxEntries: Int
    let isActive: Bool
    
    // Metadata
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date?
    
    // Competition settings
    let entryFee: Double?
    let prizePool: Double?
    let sponsorInfo: SponsorInfo?
    
    // Real-time tracking
    var entries: [LeaderboardEntry] = []
    var totalParticipants: Int { entries.count }
    
    // Computed properties
    var isExpired: Bool {
        guard let expiry = expiresAt else { return false }
        return Date() > expiry
    }
    
    var formattedPrizePool: String? {
        guard let prize = prizePool else { return nil }
        return "$\(Int(prize))"
    }
    
    var timeRemaining: String? {
        guard let expiry = expiresAt, expiry > Date() else { return nil }
        let interval = expiry.timeIntervalSince(Date())
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        
        if days > 0 {
            return "\(days)d \(hours)h remaining"
        } else if hours > 0 {
            return "\(hours)h remaining"
        } else {
            return "Ends soon"
        }
    }
}

struct LeaderboardEntry: Identifiable, Codable, Equatable {
    let id: String
    let leaderboardId: String
    let playerId: String
    let playerName: String
    let playerAvatarUrl: String?
    let score: Int
    let handicap: Double?
    let courseHandicap: Int?
    
    // Round details
    let roundDate: Date
    let roundId: String?
    let holesPlayed: Int
    let strokesGained: Double?
    let fairwaysHit: Int?
    let greensInRegulation: Int?
    
    // Position tracking
    var position: Int = 0
    var previousPosition: Int?
    var positionChange: PositionChange {
        guard let prev = previousPosition else { return .new }
        if position < prev { return .up }
        if position > prev { return .down }
        return .same
    }
    
    // Performance metrics
    let scoreToPar: Int
    let netScore: Int?
    let bestHole: HolePerformance?
    let achievements: [Achievement]
    
    // Real-time updates
    let updatedAt: Date
    let isLive: Bool
    
    var formattedScore: String {
        if scoreToPar == 0 {
            return "E"
        } else if scoreToPar > 0 {
            return "+\(scoreToPar)"
        } else {
            return "\(scoreToPar)"
        }
    }
    
    var positionDisplay: String {
        switch position {
        case 1: return "1st"
        case 2: return "2nd" 
        case 3: return "3rd"
        default: return "\(position)th"
        }
    }
}

struct HolePerformance: Codable, Equatable {
    let holeNumber: Int
    let par: Int
    let strokes: Int
    let scoreName: String // "Eagle", "Birdie", "Par", etc.
    let yardage: Int?
}

struct Achievement: Identifiable, Codable, Equatable {
    let id: String
    let type: AchievementType
    let name: String
    let description: String
    let iconName: String
    let earnedAt: Date
    let rarity: AchievementRarity
    
    enum AchievementType: String, CaseIterable, Codable {
        case eagle = "eagle"
        case holeinone = "hole_in_one"
        case underPar = "under_par"
        case consistentPlay = "consistent_play"
        case longDrive = "long_drive"
        case accurateApproach = "accurate_approach"
        case clutchPutt = "clutch_putt"
        case courseRecord = "course_record"
        case improvement = "improvement"
        case streakPlayer = "streak_player"
    }
    
    enum AchievementRarity: String, CaseIterable, Codable {
        case common = "common"
        case uncommon = "uncommon"
        case rare = "rare"
        case epic = "epic"
        case legendary = "legendary"
        
        var color: String {
            switch self {
            case .common: return "gray"
            case .uncommon: return "green"
            case .rare: return "blue"
            case .epic: return "purple"
            case .legendary: return "gold"
            }
        }
    }
}

enum PositionChange {
    case up, down, same, new
    
    var icon: String {
        switch self {
        case .up: return "arrow.up.circle.fill"
        case .down: return "arrow.down.circle.fill"
        case .same: return "minus.circle.fill"
        case .new: return "plus.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .up: return "green"
        case .down: return "red"
        case .same: return "gray"
        case .new: return "blue"
        }
    }
}

enum LeaderboardType: String, CaseIterable, Codable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case seasonal = "seasonal"
    case tournament = "tournament"
    case challenge = "challenge"
    case handicap = "handicap"
    case scratch = "scratch"
    case courseRecord = "course_record"
    case social = "social"
    
    var displayName: String {
        switch self {
        case .daily: return "Daily Leaders"
        case .weekly: return "Weekly Champions"
        case .monthly: return "Monthly Tournament"
        case .seasonal: return "Season Rankings"
        case .tournament: return "Tournament"
        case .challenge: return "Golf Challenge"
        case .handicap: return "Handicap Division"
        case .scratch: return "Scratch Players"
        case .courseRecord: return "Course Records"
        case .social: return "Friends Challenge"
        }
    }
    
    var icon: String {
        switch self {
        case .daily: return "sun.max"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .seasonal: return "leaf"
        case .tournament: return "trophy"
        case .challenge: return "target"
        case .handicap: return "equal"
        case .scratch: return "star"
        case .courseRecord: return "crown"
        case .social: return "person.2"
        }
    }
}

enum LeaderboardPeriod: String, CaseIterable, Codable {
    case realTime = "real_time"
    case hourly = "hourly"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case quarterly = "quarterly"
    case yearly = "yearly"
    case allTime = "all_time"
    
    var displayName: String {
        switch self {
        case .realTime: return "Live"
        case .hourly: return "This Hour"
        case .daily: return "Today"
        case .weekly: return "This Week"
        case .monthly: return "This Month"
        case .quarterly: return "This Quarter"
        case .yearly: return "This Year"
        case .allTime: return "All Time"
        }
    }
}

struct SponsorInfo: Codable, Equatable {
    let name: String
    let logoUrl: String?
    let website: String?
    let description: String?
    let sponsorshipLevel: SponsorshipLevel
    
    enum SponsorshipLevel: String, CaseIterable, Codable {
        case title = "title"
        case presenting = "presenting"
        case official = "official"
        case supporting = "supporting"
        
        var displayName: String {
            switch self {
            case .title: return "Title Sponsor"
            case .presenting: return "Presenting Sponsor"
            case .official: return "Official Sponsor"
            case .supporting: return "Supporting Sponsor"
            }
        }
    }
}

// MARK: - Leaderboard Statistics

struct LeaderboardStats: Codable, Equatable {
    let totalRounds: Int
    let averageScore: Double
    let bestScore: Int
    let worstScore: Int
    let participationRate: Double
    let competitiveBalance: Double // How close the competition is
    
    // Trending data
    let scoreImprovement: Double // Week-over-week improvement
    let popularityTrend: PopularityTrend
    let engagementMetrics: EngagementMetrics
    
    enum PopularityTrend: String, CaseIterable, Codable {
        case rising = "rising"
        case stable = "stable"
        case declining = "declining"
        
        var icon: String {
            switch self {
            case .rising: return "arrow.up.right"
            case .stable: return "arrow.right"
            case .declining: return "arrow.down.right"
            }
        }
        
        var color: String {
            switch self {
            case .rising: return "green"
            case .stable: return "blue"
            case .declining: return "red"
            }
        }
    }
}

struct EngagementMetrics: Codable, Equatable {
    let viewCount: Int
    let shareCount: Int
    let commentCount: Int
    let participantRetention: Double
    let averageSessionTime: TimeInterval
}

// MARK: - Social Features

struct SocialChallenge: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let createdBy: String
    let participants: [String] // Player IDs
    let courseId: String
    let targetScore: Int?
    let targetMetric: ChallengeMetric
    let startDate: Date
    let endDate: Date
    let isPublic: Bool
    let entryFee: Double?
    let winner: String?
    let prizes: [ChallengePrize]
    
    enum ChallengeMetric: String, CaseIterable, Codable {
        case lowestScore = "lowest_score"
        case mostImproved = "most_improved"
        case longestDrive = "longest_drive"
        case fewestPutts = "fewest_putts"
        case mostFairways = "most_fairways"
        case mostGIR = "most_gir"
        case bestFinish = "best_finish"
        
        var displayName: String {
            switch self {
            case .lowestScore: return "Lowest Score"
            case .mostImproved: return "Most Improved"
            case .longestDrive: return "Longest Drive"
            case .fewestPutts: return "Fewest Putts"
            case .mostFairways: return "Most Fairways Hit"
            case .mostGIR: return "Most Greens in Regulation"
            case .bestFinish: return "Best Finish"
            }
        }
    }
}

struct ChallengePrize: Identifiable, Codable, Equatable {
    let id: String
    let position: Int
    let type: PrizeType
    let value: Double?
    let description: String
    let sponsorName: String?
    
    enum PrizeType: String, CaseIterable, Codable {
        case cash = "cash"
        case gift = "gift"
        case discount = "discount"
        case trophy = "trophy"
        case badge = "badge"
        case experience = "experience"
        
        var icon: String {
            switch self {
            case .cash: return "dollarsign.circle"
            case .gift: return "gift"
            case .discount: return "percent"
            case .trophy: return "trophy"
            case .badge: return "star.circle"
            case .experience: return "location"
            }
        }
    }
}