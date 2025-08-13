import Foundation
import Combine

// MARK: - Rating Engine Service Protocol

protocol RatingEngineServiceProtocol {
    // MARK: - USGA Handicap Integration
    
    /// Calculates USGA handicap index based on recent scores
    func calculateHandicapIndex(playerId: String, recentScores: [ScorecardEntry]) async throws -> HandicapIndex
    
    /// Gets course handicap for a specific course and tees
    func getCourseHandicap(handicapIndex: Double, courseSlope: Int, courseRating: Double, par: Int) async throws -> Int
    
    /// Updates handicap based on new round submission
    func updateHandicapWithNewRound(playerId: String, scorecard: ScorecardEntry) async throws -> HandicapUpdate
    
    // MARK: - Advanced Rating Algorithms
    
    /// Calculates strokes gained analysis for a round
    func calculateStrokesGained(scorecard: ScorecardEntry, courseData: GolfCourse) async throws -> StrokesGainedAnalysis
    
    /// Generates performance rating based on multiple factors
    func calculatePerformanceRating(playerId: String, dateRange: DateInterval) async throws -> PerformanceRating
    
    /// Compares player performance against field average
    func calculateRelativePerformance(playerId: String, leaderboardId: String) async throws -> RelativePerformance
    
    // MARK: - Competitive Rating System
    
    /// Calculates competitive rating for tournament play
    func calculateCompetitiveRating(playerId: String, recentTournaments: [TournamentResult]) async throws -> CompetitiveRating
    
    /// Adjusts rating based on field strength and conditions
    func adjustRatingForFieldStrength(baseRating: Double, fieldStrength: FieldStrength, conditions: PlayingConditions) async throws -> AdjustedRating
    
    /// Calculates momentum and form rating
    func calculateFormRating(playerId: String, recentRounds: Int) async throws -> FormRating
    
    // MARK: - Predictive Analytics
    
    /// Predicts likely score range for upcoming round
    func predictScoreRange(playerId: String, courseId: String, conditions: PlayingConditions) async throws -> ScorePrediction
    
    /// Calculates probability of achieving specific scores
    func calculateScoreProbabilities(playerId: String, courseId: String, targetScores: [Int]) async throws -> [ScoreProbability]
    
    /// Predicts tournament finish position
    func predictTournamentFinish(playerId: String, tournamentField: [String], courseId: String) async throws -> TournamentPrediction
    
    // MARK: - Improvement Analysis
    
    /// Tracks improvement trends over time
    func analyzeImprovementTrends(playerId: String, timeframe: ImprovementTimeframe) async throws -> ImprovementAnalysis
    
    /// Identifies strengths and weaknesses
    func analyzePlayerStrengthsWeaknesses(playerId: String, minimumRounds: Int) async throws -> PlayerAnalysis
    
    /// Recommends improvement focus areas
    func generateImprovementRecommendations(playerId: String) async throws -> [ImprovementRecommendation]
    
    // MARK: - Leaderboard Integration
    
    /// Calculates dynamic leaderboard positions with rating adjustments
    func calculateDynamicLeaderboardPositions(leaderboardId: String) async throws -> [DynamicLeaderboardEntry]
    
    /// Updates ratings based on leaderboard performance
    func updateRatingsFromLeaderboardResults(leaderboardId: String) async throws
    
    /// Calculates rating points earned/lost from competition
    func calculateRatingPointsChange(playerId: String, leaderboardResult: LeaderboardResult) async throws -> RatingPointsChange
    
    // MARK: - Real-time Rating Updates
    
    /// Provides real-time rating updates during active rounds
    func subscribeToLiveRatingUpdates(playerId: String) -> AnyPublisher<LiveRatingUpdate, Error>
    
    /// Updates rating in real-time as scores are entered
    func updateLiveRating(playerId: String, currentScore: Int, holesCompleted: Int) async throws -> LiveRatingUpdate
    
    /// Calculates projected final rating based on current performance
    func projectFinalRating(playerId: String, currentRound: InProgressRound) async throws -> ProjectedRating
}

// MARK: - Supporting Data Models

struct HandicapIndex: Codable {
    let playerId: String
    let index: Double
    let calculationDate: Date
    let scoreDifferentials: [Double]
    let numberOfScores: Int
    let trends: HandicapTrend
    let nextRevisionDate: Date
}

struct HandicapUpdate: Codable {
    let previousIndex: Double
    let newIndex: Double
    let change: Double
    let scoreContributed: Bool
    let revisionReason: RevisionReason
    let effectiveDate: Date
    
    enum RevisionReason: String, Codable {
        case newScore = "new_score"
        case periodicRevision = "periodic_revision"
        case exceptionalScore = "exceptional_score"
        case hardCapAdjustment = "hard_cap"
    }
}

struct HandicapTrend: Codable {
    let direction: TrendDirection
    let volatility: Double // 0-1 scale
    let consistency: Double // 0-1 scale
    let improvementRate: Double // strokes per month
    
    enum TrendDirection: String, Codable {
        case improving = "improving"
        case stable = "stable"
        case deteriorating = "deteriorating"
    }
}

struct StrokesGainedAnalysis: Codable {
    let totalStrokesGained: Double
    let drivingStrokesGained: Double
    let approachStrokesGained: Double
    let shortGameStrokesGained: Double
    let puttingStrokesGained: Double
    let holeByHoleAnalysis: [HoleStrokesGained]
    let comparisonBenchmark: StrokesGainedBenchmark
}

struct HoleStrokesGained: Codable {
    let holeNumber: Int
    let totalGained: Double
    let drivingGained: Double?
    let approachGained: Double?
    let shortGameGained: Double?
    let puttingGained: Double?
    let significantFactor: String?
}

struct StrokesGainedBenchmark: Codable {
    let benchmarkType: BenchmarkType
    let averageTotal: Double
    let averageDriving: Double
    let averageApproach: Double
    let averageShortGame: Double
    let averagePutting: Double
    
    enum BenchmarkType: String, Codable {
        case scratchGolfer = "scratch"
        case tourProfessional = "tour_pro"
        case similarHandicap = "similar_handicap"
        case courseAverage = "course_average"
    }
}

struct PerformanceRating: Codable {
    let playerId: String
    let overallRating: Double // 0-100 scale
    let consistencyRating: Double
    let clutchRating: Double
    let improvementRating: Double
    let competitiveRating: Double
    let timeframe: DateInterval
    let ratingComponents: PerformanceComponents
    let historicalComparison: HistoricalComparison
}

struct PerformanceComponents: Codable {
    let scoringAverage: Double
    let strokesGainedAverage: Double
    let fairwayAccuracy: Double
    let greenInRegulationRate: Double
    let puttingAverage: Double
    let scramblePercentage: Double
    let sandSavePercentage: Double
}

struct HistoricalComparison: Codable {
    let versusLastMonth: Double
    let versusLastYear: Double
    let versusCareerBest: Double
    let trendAnalysis: TrendAnalysis
}

struct TrendAnalysis: Codable {
    let shortTerm: TrendDirection // Last 5 rounds
    let mediumTerm: TrendDirection // Last 20 rounds
    let longTerm: TrendDirection // Last year
    let volatilityIndex: Double
    let progressionRate: Double
}

struct RelativePerformance: Codable {
    let playerId: String
    let leaderboardId: String
    let relativeToField: Double // Strokes better/worse than field average
    let percentileRank: Double // 0-100
    let expectedFinish: Int
    let actualFinish: Int?
    let outperformanceMetric: Double
    let contextualFactors: [ContextualFactor]
}

struct ContextualFactor: Codable {
    let factor: String
    let impact: Double // -5 to +5 strokes
    let confidence: Double // 0-1
}

struct CompetitiveRating: Codable {
    let playerId: String
    let rating: Double // ELO-style rating
    let confidence: Double
    let volatility: Double
    let momentum: Double
    let recentForm: FormRating
    let tournamentHistory: TournamentHistory
    let lastUpdated: Date
}

struct FieldStrength: Codable {
    let averageRating: Double
    let ratingStandardDeviation: Double
    let numberOfPlayers: Int
    let strengthTier: StrengthTier
    let notableParticipants: [String] // Player IDs
    
    enum StrengthTier: String, Codable {
        case recreational = "recreational"
        case competitive = "competitive"
        case elite = "elite"
        case professional = "professional"
    }
}

struct PlayingConditions: Codable {
    let weather: WeatherConditions
    let courseCondition: CourseCondition
    let pin: PinConditions
    let expectedDifficulty: DifficultyAdjustment
}

struct WeatherConditions: Codable {
    let windSpeed: Double
    let windDirection: Int
    let temperature: Double
    let humidity: Double
    let precipitation: Double
    let visibility: Double
    let difficultyImpact: Double // -3 to +3 strokes
}

struct CourseCondition: Codable {
    let fairwayCondition: CourseConditionLevel
    let greenCondition: CourseConditionLevel
    let roughCondition: CourseConditionLevel
    let overallDifficulty: Double
}

struct PinConditions: Codable {
    let averageDifficulty: Double // 1-10 scale
    let frontPins: Int
    let middlePins: Int
    let backPins: Int
    let toughestHoles: [Int]
}

struct DifficultyAdjustment: Codable {
    let strokesAdjustment: Double
    let factorsConsidered: [String]
    let confidenceLevel: Double
}

struct AdjustedRating: Codable {
    let baseRating: Double
    let fieldStrengthAdjustment: Double
    let conditionsAdjustment: Double
    let finalRating: Double
    let adjustmentFactors: [AdjustmentFactor]
}

struct AdjustmentFactor: Codable {
    let factor: String
    let adjustment: Double
    let reasoning: String
}

struct FormRating: Codable {
    let currentForm: Double // 0-100
    let momentum: MomentumIndicator
    let consistency: Double
    let recentBestPerformance: Double
    let streakAnalysis: StreakAnalysis
    let formTrend: FormTrend
}

struct MomentumIndicator: Codable {
    let direction: MomentumDirection
    let strength: Double // 0-1
    let sustainabilityProbability: Double
    
    enum MomentumDirection: String, Codable {
        case positive = "positive"
        case neutral = "neutral"
        case negative = "negative"
    }
}

struct StreakAnalysis: Codable {
    let currentStreak: StreakType
    let longestPositiveStreak: Int
    let streakProbability: StreakProbability
    
    enum StreakType: Codable {
        case improvement(rounds: Int)
        case decline(rounds: Int)
        case stable(rounds: Int)
    }
}

struct StreakProbability: Codable {
    let continueCurrentStreak: Double
    let breakOutPositively: Double
    let enterDecline: Double
}

struct FormTrend: Codable {
    let shortTermTrend: Double // Last 3 rounds
    let mediumTermTrend: Double // Last 10 rounds
    let seasonalTrend: Double // Current season
    let peakPerformanceWindow: DateInterval?
}

struct ScorePrediction: Codable {
    let playerId: String
    let courseId: String
    let predictedRange: ClosedRange<Int>
    let mostLikelyScore: Int
    let confidence: Double
    let factorsConsidered: [PredictionFactor]
    let historicalAccuracy: Double
}

struct PredictionFactor: Codable {
    let factor: String
    let weight: Double
    let impact: Double
}

struct ScoreProbability: Codable {
    let targetScore: Int
    let probability: Double // 0-1
    let requiredImprovement: Double?
    let keyFactors: [String]
}

struct TournamentPrediction: Codable {
    let playerId: String
    let predictedFinish: Int
    let finishRange: ClosedRange<Int>
    let topTenProbability: Double
    let winProbability: Double
    let cutProbability: Double?
    let keyMatchups: [PlayerMatchup]
}

struct PlayerMatchup: Codable {
    let opponentId: String
    let opponentName: String
    let headToHeadAdvantage: Double // -1 to 1
    let winProbability: Double
}

struct ImprovementAnalysis: Codable {
    let playerId: String
    let timeframe: ImprovementTimeframe
    let overallImprovement: Double // Strokes improved
    let categoryBreakdown: ImprovementBreakdown
    let milestones: [ImprovementMilestone]
    let projectedContinuation: ProjectedImprovement
}

enum ImprovementTimeframe: String, Codable, CaseIterable {
    case last3Months = "last_3_months"
    case last6Months = "last_6_months"
    case lastYear = "last_year"
    case careerToDate = "career"
}

struct ImprovementBreakdown: Codable {
    let drivingImprovement: Double
    let approachImprovement: Double
    let shortGameImprovement: Double
    let puttingImprovement: Double
    let mentalGameImprovement: Double
    let courseManagementImprovement: Double
}

struct ImprovementMilestone: Codable {
    let date: Date
    let milestone: String
    let improvement: Double
    let significance: MilestoneSignificance
    
    enum MilestoneSignificance: String, Codable {
        case minor = "minor"
        case significant = "significant"
        case major = "major"
        case breakthrough = "breakthrough"
    }
}

struct ProjectedImprovement: Codable {
    let next3Months: Double
    let next6Months: Double
    let nextYear: Double
    let confidence: Double
    let requiredFocus: [String]
}

struct PlayerAnalysis: Codable {
    let playerId: String
    let strengths: [SkillArea]
    let weaknesses: [SkillArea]
    let overallSkillRating: Double
    let comparisonGroup: ComparisonGroup
    let developmentPotential: DevelopmentPotential
}

struct SkillArea: Codable {
    let skill: SkillCategory
    let rating: Double // 0-100
    let percentileRank: Double
    let trend: TrendDirection
    let improvement: Double
    let priority: Priority
    
    enum SkillCategory: String, Codable, CaseIterable {
        case driving = "driving"
        case ironPlay = "iron_play"
        case wedgePlay = "wedge_play"
        case putting = "putting"
        case courseManagement = "course_management"
        case mentalGame = "mental_game"
        case physicalFitness = "fitness"
        case consistency = "consistency"
    }
    
    enum Priority: String, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }
}

struct ComparisonGroup: Codable {
    let groupType: GroupType
    let averageHandicap: Double
    let playerRankInGroup: Int
    let totalInGroup: Int
    
    enum GroupType: String, Codable {
        case handicapRange = "handicap_range"
        case ageGroup = "age_group"
        case regionalPlayers = "regional"
        case similarPlayers = "similar_skill"
    }
}

struct DevelopmentPotential: Codable {
    let overallPotential: PotentialLevel
    let shortTermPotential: Double // Next 6 months
    let longTermPotential: Double // Next 2 years
    let limitingFactors: [String]
    let acceleratingFactors: [String]
    
    enum PotentialLevel: String, Codable {
        case limited = "limited"
        case moderate = "moderate"
        case high = "high"
        case exceptional = "exceptional"
    }
}

struct ImprovementRecommendation: Codable {
    let id: String
    let category: SkillArea.SkillCategory
    let title: String
    let description: String
    let priority: ImprovementPriority
    let estimatedImprovement: Double // Strokes
    let timeframe: String
    let difficulty: DifficultyLevel
    let resources: [RecommendationResource]
    
    enum ImprovementPriority: String, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case immediate = "immediate"
    }
    
    enum DifficultyLevel: String, Codable {
        case easy = "easy"
        case moderate = "moderate"
        case challenging = "challenging"
        case advanced = "advanced"
    }
}

struct RecommendationResource: Codable {
    let type: ResourceType
    let title: String
    let url: String?
    let description: String
    
    enum ResourceType: String, Codable {
        case video = "video"
        case article = "article"
        case drill = "drill"
        case lesson = "lesson"
        case equipment = "equipment"
    }
}

struct DynamicLeaderboardEntry: Codable {
    let playerId: String
    let adjustedScore: Double
    let adjustedPosition: Int
    let ratingAdjustment: Double
    let difficultyAdjustment: Double
    let qualityOfFieldAdjustment: Double
    let finalRating: Double
}

struct LeaderboardResult: Codable {
    let leaderboardId: String
    let playerId: String
    let finalPosition: Int
    let score: Int
    let fieldSize: Int
    let fieldStrength: FieldStrength
    let conditions: PlayingConditions
}

struct RatingPointsChange: Codable {
    let playerId: String
    let previousRating: Double
    let newRating: Double
    let pointsChange: Double
    let reasonBreakdown: [RatingChangeReason]
    
    struct RatingChangeReason: Codable {
        let reason: String
        let impact: Double
        let weight: Double
    }
}

struct LiveRatingUpdate: Codable {
    let playerId: String
    let currentHole: Int
    let currentScore: Int
    let projectedFinalScore: Int
    let liveRating: Double
    let ratingChange: Double
    let momentum: MomentumIndicator
    let timestamp: Date
}

struct InProgressRound: Codable {
    let playerId: String
    let courseId: String
    let currentHole: Int
    let holesCompleted: Int
    let currentScore: Int
    let holeScores: [Int]
    let conditions: PlayingConditions
    let timestamp: Date
}

struct ProjectedRating: Codable {
    let currentRating: Double
    let projectedFinalRating: Double
    let confidence: Double
    let projectionFactors: [ProjectionFactor]
    
    struct ProjectionFactor: Codable {
        let factor: String
        let weight: Double
        let impact: Double
    }
}

struct TournamentHistory: Codable {
    let totalTournaments: Int
    let wins: Int
    let topFives: Int
    let topTens: Int
    let averageFinish: Double
    let bestFinish: Int
    let recentForm: [TournamentResult]
}

struct TournamentResult: Codable {
    let tournamentId: String
    let date: Date
    let finish: Int
    let fieldSize: Int
    let score: Int
    let strokesGained: Double?
    let ratingPointsEarned: Double
}

struct ScorecardEntry: Codable {
    let playerId: String
    let courseId: String
    let date: Date
    let totalScore: Int
    let coursePar: Int
    let courseRating: Double
    let courseSlope: Int
    let holeScores: [Int]
    let conditions: PlayingConditions
    let scoreDifferential: Double
}