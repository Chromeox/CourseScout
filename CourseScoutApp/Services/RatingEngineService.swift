import Foundation
import Combine
import Appwrite

// MARK: - Rating Engine Service Implementation

@MainActor
class RatingEngineService: RatingEngineServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let appwriteManager: AppwriteManager
    private var subscriptions = Set<AnyCancellable>()
    private let cache = RatingEngineCache()
    
    // Publishers for real-time updates
    private let liveRatingUpdateSubject = PassthroughSubject<LiveRatingUpdate, Error>()
    
    // MARK: - Configuration
    
    private let databaseId = "golf_finder_db"
    private let ratingsCollection = "player_ratings"
    private let handicapsCollection = "handicap_indices"
    private let performanceCollection = "performance_data"
    private let predictionsCollection = "predictions"
    
    // MARK: - USGA Constants
    
    private let maxHandicapIndex: Double = 54.0
    private let minScoresForHandicap = 3
    private let maxScoresForCalculation = 20
    private let handicapRevisionFrequency: TimeInterval = 86400 * 14 // 14 days
    
    // MARK: - Initialization
    
    init(appwriteManager: AppwriteManager = .shared) {
        self.appwriteManager = appwriteManager
    }
    
    // MARK: - USGA Handicap Integration
    
    func calculateHandicapIndex(playerId: String, recentScores: [ScorecardEntry]) async throws -> HandicapIndex {
        guard recentScores.count >= minScoresForHandicap else {
            throw RatingEngineError.insufficientScores
        }
        
        // Sort scores by date (newest first) and limit to 20
        let sortedScores = recentScores
            .sorted { $0.date > $1.date }
            .prefix(maxScoresForCalculation)
        
        // Calculate score differentials
        let scoreDifferentials = sortedScores.map { scorecard in
            calculateScoreDifferential(scorecard: scorecard)
        }
        
        // Calculate handicap index using USGA formula
        let handicapIndex = calculateUSGAHandicapIndex(from: scoreDifferentials)
        
        // Analyze trends
        let trends = analyzeHandicapTrends(scoreDifferentials: scoreDifferentials)
        
        let handicapIndexResult = HandicapIndex(
            playerId: playerId,
            index: handicapIndex,
            calculationDate: Date(),
            scoreDifferentials: scoreDifferentials,
            numberOfScores: scoreDifferentials.count,
            trends: trends,
            nextRevisionDate: Date().addingTimeInterval(handicapRevisionFrequency)
        )
        
        // Cache and store the result
        try await storeHandicapIndex(handicapIndexResult)
        cache.setHandicapIndex(handicapIndexResult, for: playerId)
        
        return handicapIndexResult
    }
    
    func getCourseHandicap(handicapIndex: Double, courseSlope: Int, courseRating: Double, par: Int) async throws -> Int {
        // USGA Course Handicap Formula: (Handicap Index × Slope Rating ÷ 113) + (Course Rating - Par)
        let baseHandicap = (handicapIndex * Double(courseSlope)) / 113.0
        let ratingAdjustment = courseRating - Double(par)
        let courseHandicap = baseHandicap + ratingAdjustment
        
        return Int(courseHandicap.rounded())
    }
    
    func updateHandicapWithNewRound(playerId: String, scorecard: ScorecardEntry) async throws -> HandicapUpdate {
        // Get current handicap
        guard let currentHandicap = try await getCurrentHandicap(playerId: playerId) else {
            throw RatingEngineError.noCurrentHandicap
        }
        
        // Get recent scores including the new one
        var recentScores = try await getRecentScores(playerId: playerId, limit: maxScoresForCalculation - 1)
        recentScores.insert(scorecard, at: 0)
        
        // Calculate new handicap
        let newHandicap = try await calculateHandicapIndex(playerId: playerId, recentScores: recentScores)
        
        let update = HandicapUpdate(
            previousIndex: currentHandicap.index,
            newIndex: newHandicap.index,
            change: newHandicap.index - currentHandicap.index,
            scoreContributed: true,
            revisionReason: .newScore,
            effectiveDate: Date()
        )
        
        return update
    }
    
    // MARK: - Advanced Rating Algorithms
    
    func calculateStrokesGained(scorecard: ScorecardEntry, courseData: GolfCourse) async throws -> StrokesGainedAnalysis {
        // Get baseline data for strokes gained calculation
        let benchmarkData = try await getBenchmarkData(courseId: scorecard.courseId)
        
        var holeAnalysis: [HoleStrokesGained] = []
        var totalDriving: Double = 0
        var totalApproach: Double = 0
        var totalShortGame: Double = 0
        var totalPutting: Double = 0
        
        for (index, score) in scorecard.holeScores.enumerated() {
            let holeNumber = index + 1
            let par = courseData.holes[index].par
            
            // Calculate strokes gained for each category per hole
            let holeAnalysisResult = calculateHoleStrokesGained(
                holeScore: score,
                holePar: par,
                holeData: courseData.holes[index],
                benchmark: benchmarkData
            )
            
            holeAnalysis.append(holeAnalysisResult)
            
            totalDriving += holeAnalysisResult.drivingGained ?? 0
            totalApproach += holeAnalysisResult.approachGained ?? 0
            totalShortGame += holeAnalysisResult.shortGameGained ?? 0
            totalPutting += holeAnalysisResult.puttingGained ?? 0
        }
        
        let totalStrokesGained = totalDriving + totalApproach + totalShortGame + totalPutting
        
        return StrokesGainedAnalysis(
            totalStrokesGained: totalStrokesGained,
            drivingStrokesGained: totalDriving,
            approachStrokesGained: totalApproach,
            shortGameStrokesGained: totalShortGame,
            puttingStrokesGained: totalPutting,
            holeByHoleAnalysis: holeAnalysis,
            comparisonBenchmark: benchmarkData
        )
    }
    
    func calculatePerformanceRating(playerId: String, dateRange: DateInterval) async throws -> PerformanceRating {
        let scorecards = try await getScorecards(playerId: playerId, dateRange: dateRange)
        
        guard !scorecards.isEmpty else {
            throw RatingEngineError.noDataForPeriod
        }
        
        // Calculate performance components
        let components = calculatePerformanceComponents(scorecards: scorecards)
        let historicalComparison = try await calculateHistoricalComparison(playerId: playerId, currentPeriod: dateRange)
        
        // Calculate overall rating (0-100 scale)
        let overallRating = calculateOverallRating(components: components)
        let consistencyRating = calculateConsistencyRating(scorecards: scorecards)
        let clutchRating = try await calculateClutchRating(playerId: playerId, dateRange: dateRange)
        let improvementRating = calculateImprovementRating(historicalComparison: historicalComparison)
        let competitiveRating = try await getCompetitiveRating(playerId: playerId)
        
        return PerformanceRating(
            playerId: playerId,
            overallRating: overallRating,
            consistencyRating: consistencyRating,
            clutchRating: clutchRating,
            improvementRating: improvementRating,
            competitiveRating: competitiveRating.rating,
            timeframe: dateRange,
            ratingComponents: components,
            historicalComparison: historicalComparison
        )
    }
    
    func calculateRelativePerformance(playerId: String, leaderboardId: String) async throws -> RelativePerformance {
        let leaderboard = try await getLeaderboard(leaderboardId: leaderboardId)
        let playerEntry = leaderboard.entries.first { $0.playerId == playerId }
        
        guard let playerEntry = playerEntry else {
            throw RatingEngineError.playerNotInLeaderboard
        }
        
        // Calculate field statistics
        let fieldScores = leaderboard.entries.map { Double($0.score) }
        let fieldAverage = fieldScores.reduce(0, +) / Double(fieldScores.count)
        let playerRelativeScore = Double(playerEntry.score) - fieldAverage
        
        // Calculate percentile rank
        let betterScores = fieldScores.filter { $0 < Double(playerEntry.score) }.count
        let percentileRank = (Double(betterScores) / Double(fieldScores.count)) * 100
        
        // Calculate expected vs actual finish
        let expectedFinish = calculateExpectedFinish(playerId: playerId, leaderboard: leaderboard)
        let outperformance = Double(expectedFinish - playerEntry.position)
        
        // Analyze contextual factors
        let contextualFactors = try await analyzeContextualFactors(
            playerId: playerId,
            leaderboardId: leaderboardId,
            performance: outperformance
        )
        
        return RelativePerformance(
            playerId: playerId,
            leaderboardId: leaderboardId,
            relativeToField: playerRelativeScore,
            percentileRank: percentileRank,
            expectedFinish: expectedFinish,
            actualFinish: playerEntry.position,
            outperformanceMetric: outperformance,
            contextualFactors: contextualFactors
        )
    }
    
    // MARK: - Competitive Rating System
    
    func calculateCompetitiveRating(playerId: String, recentTournaments: [TournamentResult]) async throws -> CompetitiveRating {
        guard !recentTournaments.isEmpty else {
            throw RatingEngineError.noTournamentHistory
        }
        
        // Initialize with base rating
        var rating = try await getBaseCompetitiveRating(playerId: playerId) ?? 1500.0 // ELO-style starting point
        
        // Calculate rating changes from recent tournaments
        for tournament in recentTournaments.sorted(by: { $0.date < $1.date }) {
            let ratingChange = calculateELORatingChange(
                currentRating: rating,
                finish: tournament.finish,
                fieldSize: tournament.fieldSize,
                fieldStrength: try await getFieldStrength(tournamentId: tournament.tournamentId)
            )
            rating += ratingChange
        }
        
        // Calculate confidence and volatility
        let confidence = calculateRatingConfidence(tournaments: recentTournaments)
        let volatility = calculateRatingVolatility(tournaments: recentTournaments)
        let momentum = calculateMomentum(tournaments: recentTournaments)
        let form = try await calculateFormRating(playerId: playerId, recentRounds: 10)
        
        let tournamentHistory = TournamentHistory(
            totalTournaments: recentTournaments.count,
            wins: recentTournaments.filter { $0.finish == 1 }.count,
            topFives: recentTournaments.filter { $0.finish <= 5 }.count,
            topTens: recentTournaments.filter { $0.finish <= 10 }.count,
            averageFinish: Double(recentTournaments.map { $0.finish }.reduce(0, +)) / Double(recentTournaments.count),
            bestFinish: recentTournaments.map { $0.finish }.min() ?? 0,
            recentForm: Array(recentTournaments.prefix(5))
        )
        
        return CompetitiveRating(
            playerId: playerId,
            rating: rating,
            confidence: confidence,
            volatility: volatility,
            momentum: momentum,
            recentForm: form,
            tournamentHistory: tournamentHistory,
            lastUpdated: Date()
        )
    }
    
    func adjustRatingForFieldStrength(baseRating: Double, fieldStrength: FieldStrength, conditions: PlayingConditions) async throws -> AdjustedRating {
        var adjustments: [AdjustmentFactor] = []
        var totalAdjustment = 0.0
        
        // Field strength adjustment
        let fieldAdjustment = calculateFieldStrengthAdjustment(fieldStrength: fieldStrength)
        adjustments.append(AdjustmentFactor(
            factor: "Field Strength",
            adjustment: fieldAdjustment,
            reasoning: "Adjusted for field strength tier: \(fieldStrength.strengthTier)"
        ))
        totalAdjustment += fieldAdjustment
        
        // Conditions adjustment
        let conditionsAdjustment = calculateConditionsAdjustment(conditions: conditions)
        adjustments.append(AdjustmentFactor(
            factor: "Playing Conditions",
            adjustment: conditionsAdjustment,
            reasoning: "Adjusted for weather and course conditions"
        ))
        totalAdjustment += conditionsAdjustment
        
        let finalRating = baseRating + totalAdjustment
        
        return AdjustedRating(
            baseRating: baseRating,
            fieldStrengthAdjustment: fieldAdjustment,
            conditionsAdjustment: conditionsAdjustment,
            finalRating: finalRating,
            adjustmentFactors: adjustments
        )
    }
    
    func calculateFormRating(playerId: String, recentRounds: Int) async throws -> FormRating {
        let scorecards = try await getRecentScores(playerId: playerId, limit: recentRounds)
        
        guard !scorecards.isEmpty else {
            throw RatingEngineError.noRecentScores
        }
        
        // Calculate current form (0-100 scale)
        let recentScores = scorecards.prefix(5).map { $0.scoreDifferential }
        let longerTermScores = scorecards.map { $0.scoreDifferential }
        
        let recentAverage = recentScores.reduce(0, +) / Double(recentScores.count)
        let longerTermAverage = longerTermScores.reduce(0, +) / Double(longerTermScores.count)
        
        let formImprovement = longerTermAverage - recentAverage // Positive is good (lower scores)
        let currentForm = min(100, max(0, 50 + (formImprovement * 10))) // Scale to 0-100
        
        // Calculate momentum
        let momentum = calculateMomentumFromScores(scores: recentScores)
        
        // Calculate consistency
        let consistency = calculateConsistency(scores: recentScores)
        
        // Find best recent performance
        let bestRecentPerformance = recentScores.min() ?? 0
        
        // Analyze streaks
        let streakAnalysis = analyzeStreaks(scores: Array(longerTermScores))
        
        // Calculate form trends
        let formTrend = calculateFormTrend(scores: longerTermScores)
        
        return FormRating(
            currentForm: currentForm,
            momentum: momentum,
            consistency: consistency,
            recentBestPerformance: bestRecentPerformance,
            streakAnalysis: streakAnalysis,
            formTrend: formTrend
        )
    }
    
    // MARK: - Predictive Analytics
    
    func predictScoreRange(playerId: String, courseId: String, conditions: PlayingConditions) async throws -> ScorePrediction {
        // Get player's historical performance on similar courses/conditions
        let historicalScores = try await getHistoricalScores(playerId: playerId, courseId: courseId)
        let playerStats = try await getPlayerStats(playerId: playerId)
        
        // Calculate baseline prediction
        let baselinePrediction = calculateBaselinePrediction(
            historicalScores: historicalScores,
            playerStats: playerStats
        )
        
        // Apply condition adjustments
        var predictionFactors: [PredictionFactor] = []
        var adjustedPrediction = baselinePrediction
        
        // Weather adjustment
        let weatherAdjustment = calculateWeatherImpact(conditions: conditions, playerProfile: playerStats)
        adjustedPrediction += weatherAdjustment
        predictionFactors.append(PredictionFactor(
            factor: "Weather Conditions",
            weight: 0.3,
            impact: weatherAdjustment
        ))
        
        // Form adjustment
        let formRating = try await calculateFormRating(playerId: playerId, recentRounds: 5)
        let formAdjustment = (formRating.currentForm - 50) * 0.1 // Convert to stroke adjustment
        adjustedPrediction -= formAdjustment // Better form = lower score
        predictionFactors.append(PredictionFactor(
            factor: "Current Form",
            weight: 0.4,
            impact: -formAdjustment
        ))
        
        // Course fit adjustment
        let courseFitAdjustment = try await calculateCourseFitAdjustment(playerId: playerId, courseId: courseId)
        adjustedPrediction += courseFitAdjustment
        predictionFactors.append(PredictionFactor(
            factor: "Course Fit",
            weight: 0.2,
            impact: courseFitAdjustment
        ))
        
        // Calculate confidence and range
        let standardDeviation = calculatePredictionStandardDeviation(historicalScores: historicalScores)
        let confidence = calculatePredictionConfidence(factors: predictionFactors, dataQuality: historicalScores.count)
        
        let mostLikelyScore = Int(adjustedPrediction.rounded())
        let rangeSize = max(2, Int((standardDeviation * 1.5).rounded()))
        let predictedRange = (mostLikelyScore - rangeSize)...(mostLikelyScore + rangeSize)
        
        return ScorePrediction(
            playerId: playerId,
            courseId: courseId,
            predictedRange: predictedRange,
            mostLikelyScore: mostLikelyScore,
            confidence: confidence,
            factorsConsidered: predictionFactors,
            historicalAccuracy: try await calculateHistoricalAccuracy(playerId: playerId)
        )
    }
    
    func calculateScoreProbabilities(playerId: String, courseId: String, targetScores: [Int]) async throws -> [ScoreProbability] {
        let scorePrediction = try await predictScoreRange(playerId: playerId, courseId: courseId, conditions: PlayingConditions(
            weather: WeatherConditions(windSpeed: 5, windDirection: 0, temperature: 20, humidity: 0.5, precipitation: 0, visibility: 10, difficultyImpact: 0),
            courseCondition: CourseCondition(fairwayCondition: .good, greenCondition: .good, roughCondition: .good, overallDifficulty: 0),
            pin: PinConditions(averageDifficulty: 5, frontPins: 6, middlePins: 6, backPins: 6, toughestHoles: []),
            expectedDifficulty: DifficultyAdjustment(strokesAdjustment: 0, factorsConsidered: [], confidenceLevel: 0.8)
        ))
        
        return targetScores.map { targetScore in
            let probability = calculateScoreProbability(
                targetScore: targetScore,
                prediction: scorePrediction
            )
            
            let currentBest = try? await getCurrentBestScore(playerId: playerId, courseId: courseId)
            let requiredImprovement = currentBest.map { Double(targetScore - $0) }
            
            return ScoreProbability(
                targetScore: targetScore,
                probability: probability,
                requiredImprovement: requiredImprovement,
                keyFactors: identifyKeyFactors(for: targetScore, prediction: scorePrediction)
            )
        }
    }
    
    func predictTournamentFinish(playerId: String, tournamentField: [String], courseId: String) async throws -> TournamentPrediction {
        // Get all player ratings and predictions
        var playerPredictions: [(playerId: String, prediction: ScorePrediction)] = []
        
        for fieldPlayerId in tournamentField {
            let prediction = try await predictScoreRange(
                playerId: fieldPlayerId,
                courseId: courseId,
                conditions: PlayingConditions(
                    weather: WeatherConditions(windSpeed: 5, windDirection: 0, temperature: 20, humidity: 0.5, precipitation: 0, visibility: 10, difficultyImpact: 0),
                    courseCondition: CourseCondition(fairwayCondition: .good, greenCondition: .good, roughCondition: .good, overallDifficulty: 0),
                    pin: PinConditions(averageDifficulty: 5, frontPins: 6, middlePins: 6, backPins: 6, toughestHoles: []),
                    expectedDifficulty: DifficultyAdjustment(strokesAdjustment: 0, factorsConsidered: [], confidenceLevel: 0.8)
                )
            )
            playerPredictions.append((fieldPlayerId, prediction))
        }
        
        // Sort by predicted score
        playerPredictions.sort { $0.prediction.mostLikelyScore < $1.prediction.mostLikelyScore }
        
        // Find player's predicted position
        guard let playerIndex = playerPredictions.firstIndex(where: { $0.playerId == playerId }) else {
            throw RatingEngineError.playerNotFound
        }
        
        let predictedFinish = playerIndex + 1
        
        // Calculate probabilities and ranges
        let playerPrediction = playerPredictions[playerIndex].prediction
        let finishRange = calculateFinishRange(playerPrediction: playerPrediction, field: playerPredictions)
        
        let topTenProbability = calculateTopTenProbability(prediction: playerPrediction, field: playerPredictions)
        let winProbability = calculateWinProbability(prediction: playerPrediction, field: playerPredictions)
        
        // Generate key matchups
        let keyMatchups = generateKeyMatchups(playerId: playerId, field: playerPredictions)
        
        return TournamentPrediction(
            playerId: playerId,
            predictedFinish: predictedFinish,
            finishRange: finishRange,
            topTenProbability: topTenProbability,
            winProbability: winProbability,
            cutProbability: nil, // Could implement cut logic for multi-round tournaments
            keyMatchups: keyMatchups
        )
    }
    
    // MARK: - Real-time Rating Updates
    
    func subscribeToLiveRatingUpdates(playerId: String) -> AnyPublisher<LiveRatingUpdate, Error> {
        return liveRatingUpdateSubject
            .filter { $0.playerId == playerId }
            .eraseToAnyPublisher()
    }
    
    func updateLiveRating(playerId: String, currentScore: Int, holesCompleted: Int) async throws -> LiveRatingUpdate {
        let currentRound = InProgressRound(
            playerId: playerId,
            courseId: "", // Would be provided in real implementation
            currentHole: holesCompleted + 1,
            holesCompleted: holesCompleted,
            currentScore: currentScore,
            holeScores: [], // Would be populated with actual scores
            conditions: PlayingConditions(
                weather: WeatherConditions(windSpeed: 0, windDirection: 0, temperature: 0, humidity: 0, precipitation: 0, visibility: 0, difficultyImpact: 0),
                courseCondition: CourseCondition(fairwayCondition: .good, greenCondition: .good, roughCondition: .good, overallDifficulty: 0),
                pin: PinConditions(averageDifficulty: 0, frontPins: 0, middlePins: 0, backPins: 0, toughestHoles: []),
                expectedDifficulty: DifficultyAdjustment(strokesAdjustment: 0, factorsConsidered: [], confidenceLevel: 0)
            ),
            timestamp: Date()
        )
        
        let projectedRating = try await projectFinalRating(playerId: playerId, currentRound: currentRound)
        let currentRating = try await getCurrentRating(playerId: playerId)
        
        let momentum = calculateLiveMomentum(
            currentScore: currentScore,
            holesCompleted: holesCompleted,
            playerAverage: currentRating
        )
        
        let update = LiveRatingUpdate(
            playerId: playerId,
            currentHole: holesCompleted + 1,
            currentScore: currentScore,
            projectedFinalScore: Int(projectedRating.projectedFinalRating),
            liveRating: projectedRating.currentRating,
            ratingChange: projectedRating.projectedFinalRating - currentRating,
            momentum: momentum,
            timestamp: Date()
        )
        
        liveRatingUpdateSubject.send(update)
        return update
    }
    
    func projectFinalRating(playerId: String, currentRound: InProgressRound) async throws -> ProjectedRating {
        let currentRating = try await getCurrentRating(playerId: playerId)
        let playerStats = try await getPlayerStats(playerId: playerId)
        
        // Project remaining holes performance
        let remainingHoles = 18 - currentRound.holesCompleted
        let currentPace = Double(currentRound.currentScore) / Double(currentRound.holesCompleted)
        
        let projectedScore = currentRound.currentScore + Int((Double(remainingHoles) * currentPace).rounded())
        
        // Calculate projected rating based on expected final score
        let projectedFinalRating = calculateRatingFromScore(
            score: projectedScore,
            playerBaseline: currentRating,
            courseData: nil // Would be provided in real implementation
        )
        
        let confidence = calculateProjectionConfidence(
            holesCompleted: currentRound.holesCompleted,
            consistency: playerStats.consistency
        )
        
        let projectionFactors = [
            ProjectedRating.ProjectionFactor(
                factor: "Current Pace",
                weight: 0.6,
                impact: projectedFinalRating - currentRating
            ),
            ProjectedRating.ProjectionFactor(
                factor: "Player Consistency",
                weight: 0.3,
                impact: (playerStats.consistency - 0.5) * 2
            ),
            ProjectedRating.ProjectionFactor(
                factor: "Course Conditions",
                weight: 0.1,
                impact: currentRound.conditions.expectedDifficulty.strokesAdjustment
            )
        ]
        
        return ProjectedRating(
            currentRating: currentRating,
            projectedFinalRating: projectedFinalRating,
            confidence: confidence,
            projectionFactors: projectionFactors
        )
    }
    
    // MARK: - Improvement Analysis
    
    func analyzeImprovementTrends(playerId: String, timeframe: ImprovementTimeframe) async throws -> ImprovementAnalysis {
        let dateRange = getDateRange(for: timeframe)
        let scorecards = try await getScorecards(playerId: playerId, dateRange: dateRange)
        
        guard !scorecards.isEmpty else {
            throw RatingEngineError.noDataForPeriod
        }
        
        // Calculate improvement by category
        let breakdown = calculateImprovementBreakdown(scorecards: scorecards)
        let overallImprovement = calculateOverallImprovement(scorecards: scorecards)
        
        // Identify milestones
        let milestones = identifyImprovementMilestones(scorecards: scorecards)
        
        // Project future improvement
        let projectedImprovement = projectFutureImprovement(
            currentTrend: overallImprovement,
            playerData: scorecards
        )
        
        return ImprovementAnalysis(
            playerId: playerId,
            timeframe: timeframe,
            overallImprovement: overallImprovement,
            categoryBreakdown: breakdown,
            milestones: milestones,
            projectedContinuation: projectedImprovement
        )
    }
    
    func analyzePlayerStrengthsWeaknesses(playerId: String, minimumRounds: Int) async throws -> PlayerAnalysis {
        let scorecards = try await getRecentScores(playerId: playerId, limit: minimumRounds)
        
        guard scorecards.count >= minimumRounds else {
            throw RatingEngineError.insufficientData
        }
        
        // Analyze each skill area
        let skillAreas = SkillArea.SkillCategory.allCases.map { category in
            analyzeSkillArea(category: category, scorecards: scorecards)
        }
        
        // Separate strengths and weaknesses
        let strengths = skillAreas.filter { $0.percentileRank >= 75 }.sorted { $0.rating > $1.rating }
        let weaknesses = skillAreas.filter { $0.percentileRank <= 25 }.sorted { $0.rating < $1.rating }
        
        // Calculate overall skill rating
        let overallSkillRating = skillAreas.map { $0.rating }.reduce(0, +) / Double(skillAreas.count)
        
        // Determine comparison group
        let averageScore = scorecards.map { $0.totalScore }.reduce(0, +) / scorecards.count
        let estimatedHandicap = (Double(averageScore) - 72) * 0.8 // Rough handicap estimation
        let comparisonGroup = determineComparisonGroup(estimatedHandicap: estimatedHandicap)
        
        // Assess development potential
        let developmentPotential = assessDevelopmentPotential(
            skillAreas: skillAreas,
            improvementTrend: try await analyzeImprovementTrends(playerId: playerId, timeframe: .last6Months)
        )
        
        return PlayerAnalysis(
            playerId: playerId,
            strengths: strengths,
            weaknesses: weaknesses,
            overallSkillRating: overallSkillRating,
            comparisonGroup: comparisonGroup,
            developmentPotential: developmentPotential
        )
    }
    
    func generateImprovementRecommendations(playerId: String) async throws -> [ImprovementRecommendation] {
        let playerAnalysis = try await analyzePlayerStrengthsWeaknesses(playerId: playerId, minimumRounds: 10)
        
        var recommendations: [ImprovementRecommendation] = []
        
        // Generate recommendations for weaknesses
        for weakness in playerAnalysis.weaknesses.prefix(3) { // Top 3 weaknesses
            let recommendation = generateRecommendationForWeakness(weakness: weakness, playerAnalysis: playerAnalysis)
            recommendations.append(recommendation)
        }
        
        // Generate recommendations for improvement areas
        let improvementAreas = playerAnalysis.strengths.filter { $0.percentileRank < 90 && $0.trend == .improving }
        for area in improvementAreas.prefix(2) {
            let recommendation = generateRecommendationForImprovement(area: area)
            recommendations.append(recommendation)
        }
        
        return recommendations.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    // MARK: - Leaderboard Integration
    
    func calculateDynamicLeaderboardPositions(leaderboardId: String) async throws -> [DynamicLeaderboardEntry] {
        let leaderboard = try await getLeaderboard(leaderboardId: leaderboardId)
        let fieldStrength = try await getLeaderboardFieldStrength(leaderboardId: leaderboardId)
        
        var dynamicEntries: [DynamicLeaderboardEntry] = []
        
        for entry in leaderboard.entries {
            let playerRating = try await getCurrentRating(playerId: entry.playerId)
            
            // Calculate adjustments
            let ratingAdjustment = calculateRatingAdjustment(
                playerRating: playerRating,
                fieldStrength: fieldStrength
            )
            
            let difficultyAdjustment = calculateDifficultyAdjustment(
                conditions: leaderboard.conditions ?? defaultConditions()
            )
            
            let qualityOfFieldAdjustment = calculateQualityOfFieldAdjustment(
                fieldStrength: fieldStrength
            )
            
            let adjustedScore = Double(entry.score) + ratingAdjustment + difficultyAdjustment + qualityOfFieldAdjustment
            let finalRating = playerRating + (adjustedScore - Double(entry.score))
            
            dynamicEntries.append(DynamicLeaderboardEntry(
                playerId: entry.playerId,
                adjustedScore: adjustedScore,
                adjustedPosition: 0, // Will be calculated after sorting
                ratingAdjustment: ratingAdjustment,
                difficultyAdjustment: difficultyAdjustment,
                qualityOfFieldAdjustment: qualityOfFieldAdjustment,
                finalRating: finalRating
            ))
        }
        
        // Sort by adjusted score and assign positions
        dynamicEntries.sort { $0.adjustedScore < $1.adjustedScore }
        for (index, _) in dynamicEntries.enumerated() {
            dynamicEntries[index] = DynamicLeaderboardEntry(
                playerId: dynamicEntries[index].playerId,
                adjustedScore: dynamicEntries[index].adjustedScore,
                adjustedPosition: index + 1,
                ratingAdjustment: dynamicEntries[index].ratingAdjustment,
                difficultyAdjustment: dynamicEntries[index].difficultyAdjustment,
                qualityOfFieldAdjustment: dynamicEntries[index].qualityOfFieldAdjustment,
                finalRating: dynamicEntries[index].finalRating
            )
        }
        
        return dynamicEntries
    }
    
    func updateRatingsFromLeaderboardResults(leaderboardId: String) async throws {
        let dynamicEntries = try await calculateDynamicLeaderboardPositions(leaderboardId: leaderboardId)
        
        for entry in dynamicEntries {
            try await updatePlayerRating(playerId: entry.playerId, newRating: entry.finalRating)
        }
    }
    
    func calculateRatingPointsChange(playerId: String, leaderboardResult: LeaderboardResult) async throws -> RatingPointsChange {
        let currentRating = try await getCurrentRating(playerId: playerId)
        let expectedFinish = calculateExpectedFinish(
            playerRating: currentRating,
            fieldStrength: leaderboardResult.fieldStrength
        )
        
        let performanceDifference = Double(expectedFinish - leaderboardResult.finalPosition)
        let basePointsChange = performanceDifference * 5.0 // 5 points per position
        
        // Apply modifiers
        let fieldSizeModifier = log(Double(leaderboardResult.fieldSize)) / log(100) // Larger fields = more points
        let strengthModifier = leaderboardResult.fieldStrength.averageRating / 1500 // Stronger fields = more points
        
        let finalPointsChange = basePointsChange * fieldSizeModifier * strengthModifier
        let newRating = currentRating + finalPointsChange
        
        let reasonBreakdown = [
            RatingPointsChange.RatingChangeReason(reason: "Finish Position", impact: performanceDifference, weight: 0.6),
            RatingPointsChange.RatingChangeReason(reason: "Field Size", impact: fieldSizeModifier - 1, weight: 0.2),
            RatingPointsChange.RatingChangeReason(reason: "Field Strength", impact: strengthModifier - 1, weight: 0.2)
        ]
        
        return RatingPointsChange(
            playerId: playerId,
            previousRating: currentRating,
            newRating: newRating,
            pointsChange: finalPointsChange,
            reasonBreakdown: reasonBreakdown
        )
    }
}

// MARK: - Private Helper Methods

private extension RatingEngineService {
    
    func calculateScoreDifferential(scorecard: ScorecardEntry) -> Double {
        return (Double(scorecard.totalScore) - scorecard.courseRating) * (113.0 / Double(scorecard.courseSlope))
    }
    
    func calculateUSGAHandicapIndex(from differentials: [Double]) -> Double {
        let sortedDifferentials = differentials.sorted()
        let numberOfScores = differentials.count
        
        // Determine how many differentials to use based on number of scores
        let numberOfDifferentialsToUse: Int
        switch numberOfScores {
        case 3...5: numberOfDifferentialsToUse = 1
        case 6...8: numberOfDifferentialsToUse = 2
        case 9...11: numberOfDifferentialsToUse = 3
        case 12...14: numberOfDifferentialsToUse = 4
        case 15...16: numberOfDifferentialsToUse = 5
        case 17: numberOfDifferentialsToUse = 6
        case 18: numberOfDifferentialsToUse = 7
        case 19: numberOfDifferentialsToUse = 8
        default: numberOfDifferentialsToUse = min(8, numberOfScores / 2)
        }
        
        let lowestDifferentials = Array(sortedDifferentials.prefix(numberOfDifferentialsToUse))
        let average = lowestDifferentials.reduce(0, +) / Double(numberOfDifferentialsToUse)
        
        return min(maxHandicapIndex, max(-5.0, average * 0.96)) // Apply 96% multiplier and cap
    }
    
    func analyzeHandicapTrends(scoreDifferentials: [Double]) -> HandicapTrend {
        guard scoreDifferentials.count >= 3 else {
            return HandicapTrend(direction: .stable, volatility: 0, consistency: 0.5, improvementRate: 0)
        }
        
        let recent = Array(scoreDifferentials.prefix(5))
        let older = Array(scoreDifferentials.dropFirst(5).prefix(5))
        
        let recentAverage = recent.reduce(0, +) / Double(recent.count)
        let olderAverage = older.isEmpty ? recentAverage : older.reduce(0, +) / Double(older.count)
        
        let improvement = olderAverage - recentAverage // Positive = improving (lower scores)
        
        let direction: HandicapTrend.TrendDirection
        if improvement > 0.5 {
            direction = .improving
        } else if improvement < -0.5 {
            direction = .deteriorating
        } else {
            direction = .stable
        }
        
        // Calculate volatility (standard deviation)
        let mean = scoreDifferentials.reduce(0, +) / Double(scoreDifferentials.count)
        let squaredDifferences = scoreDifferentials.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0, +) / Double(scoreDifferentials.count)
        let volatility = min(1.0, sqrt(variance) / 10.0) // Normalize to 0-1
        
        // Calculate consistency (inverse of volatility)
        let consistency = 1.0 - volatility
        
        // Estimate monthly improvement rate
        let improvementRate = improvement * 2 // Rough conversion to monthly rate
        
        return HandicapTrend(
            direction: direction,
            volatility: volatility,
            consistency: consistency,
            improvementRate: improvementRate
        )
    }
    
    // Additional helper methods would continue here...
    // Due to length constraints, I'm showing the key structural elements
    
    func storeHandicapIndex(_ handicapIndex: HandicapIndex) async throws {
        let data = try mapHandicapIndexToDocument(handicapIndex)
        
        _ = try await appwriteManager.databases.createDocument(
            databaseId: databaseId,
            collectionId: handicapsCollection,
            documentId: ID.unique(),
            data: data
        )
    }
    
    func mapHandicapIndexToDocument(_ handicapIndex: HandicapIndex) throws -> [String: Any] {
        return [
            "player_id": handicapIndex.playerId,
            "index": handicapIndex.index,
            "calculation_date": handicapIndex.calculationDate.iso8601,
            "score_differentials": handicapIndex.scoreDifferentials,
            "number_of_scores": handicapIndex.numberOfScores,
            "trend_direction": handicapIndex.trends.direction.rawValue,
            "volatility": handicapIndex.trends.volatility,
            "consistency": handicapIndex.trends.consistency,
            "improvement_rate": handicapIndex.trends.improvementRate,
            "next_revision_date": handicapIndex.nextRevisionDate.iso8601
        ]
    }
    
    // Placeholder implementations for complex calculations
    func getCurrentHandicap(playerId: String) async throws -> HandicapIndex? { return nil }
    func getRecentScores(playerId: String, limit: Int) async throws -> [ScorecardEntry] { return [] }
    func getBenchmarkData(courseId: String) async throws -> StrokesGainedBenchmark { 
        return StrokesGainedBenchmark(benchmarkType: .courseAverage, averageTotal: 0, averageDriving: 0, averageApproach: 0, averageShortGame: 0, averagePutting: 0)
    }
    func calculateHoleStrokesGained(holeScore: Int, holePar: Int, holeData: Any, benchmark: StrokesGainedBenchmark) -> HoleStrokesGained {
        return HoleStrokesGained(holeNumber: 1, totalGained: 0, drivingGained: 0, approachGained: 0, shortGameGained: 0, puttingGained: 0, significantFactor: nil)
    }
    func getScorecards(playerId: String, dateRange: DateInterval) async throws -> [ScorecardEntry] { return [] }
    func calculatePerformanceComponents(scorecards: [ScorecardEntry]) -> PerformanceComponents {
        return PerformanceComponents(scoringAverage: 0, strokesGainedAverage: 0, fairwayAccuracy: 0, greenInRegulationRate: 0, puttingAverage: 0, scramblePercentage: 0, sandSavePercentage: 0)
    }
    func calculateHistoricalComparison(playerId: String, currentPeriod: DateInterval) async throws -> HistoricalComparison {
        return HistoricalComparison(versusLastMonth: 0, versusLastYear: 0, versusCareerBest: 0, trendAnalysis: TrendAnalysis(shortTerm: .stable, mediumTerm: .stable, longTerm: .stable, volatilityIndex: 0, progressionRate: 0))
    }
    func calculateOverallRating(components: PerformanceComponents) -> Double { return 75.0 }
    func calculateConsistencyRating(scorecards: [ScorecardEntry]) -> Double { return 70.0 }
    func calculateClutchRating(playerId: String, dateRange: DateInterval) async throws -> Double { return 65.0 }
    func calculateImprovementRating(historicalComparison: HistoricalComparison) -> Double { return 80.0 }
    func getCompetitiveRating(playerId: String) async throws -> CompetitiveRating {
        return CompetitiveRating(playerId: playerId, rating: 1500, confidence: 0.7, volatility: 0.3, momentum: 0.1, recentForm: FormRating(currentForm: 75, momentum: MomentumIndicator(direction: .neutral, strength: 0.5, sustainabilityProbability: 0.6), consistency: 0.7, recentBestPerformance: -2.5, streakAnalysis: StreakAnalysis(currentStreak: .stable(rounds: 3), longestPositiveStreak: 5, streakProbability: StreakProbability(continueCurrentStreak: 0.4, breakOutPositively: 0.3, enterDecline: 0.3)), formTrend: FormTrend(shortTermTrend: 0.1, mediumTermTrend: 0.05, seasonalTrend: 0.2, peakPerformanceWindow: nil)), tournamentHistory: TournamentHistory(totalTournaments: 0, wins: 0, topFives: 0, topTens: 0, averageFinish: 0, bestFinish: 0, recentForm: []), lastUpdated: Date())
    }
    func getLeaderboard(leaderboardId: String) async throws -> Leaderboard {
        // Placeholder - would integrate with actual LeaderboardService
        return Leaderboard(id: leaderboardId, courseId: "", name: "", description: nil, type: .daily, period: .daily, maxEntries: 100, isActive: true, createdAt: Date(), updatedAt: Date(), expiresAt: nil, entryFee: nil, prizePool: nil, sponsorInfo: nil)
    }
    func calculateExpectedFinish(playerId: String, leaderboard: Leaderboard) -> Int { return 50 }
    func analyzeContextualFactors(playerId: String, leaderboardId: String, performance: Double) async throws -> [ContextualFactor] { return [] }
    func getCurrentRating(playerId: String) async throws -> Double { return 1500.0 }
    func getPlayerStats(playerId: String) async throws -> (consistency: Double) { return (consistency: 0.7) }
    func calculateLiveMomentum(currentScore: Int, holesCompleted: Int, playerAverage: Double) -> MomentumIndicator {
        return MomentumIndicator(direction: .neutral, strength: 0.5, sustainabilityProbability: 0.6)
    }
    func calculateRatingFromScore(score: Int, playerBaseline: Double, courseData: Any?) -> Double { return playerBaseline }
    func calculateProjectionConfidence(holesCompleted: Int, consistency: Double) -> Double { return Double(holesCompleted) / 18.0 * consistency }
    func getDateRange(for timeframe: ImprovementTimeframe) -> DateInterval {
        let now = Date()
        let start: Date
        switch timeframe {
        case .last3Months: start = now.addingTimeInterval(-86400 * 90)
        case .last6Months: start = now.addingTimeInterval(-86400 * 180)
        case .lastYear: start = now.addingTimeInterval(-86400 * 365)
        case .careerToDate: start = now.addingTimeInterval(-86400 * 365 * 10)
        }
        return DateInterval(start: start, end: now)
    }
    
    // Additional placeholder methods...
    func calculateImprovementBreakdown(scorecards: [ScorecardEntry]) -> ImprovementBreakdown {
        return ImprovementBreakdown(drivingImprovement: 0, approachImprovement: 0, shortGameImprovement: 0, puttingImprovement: 0, mentalGameImprovement: 0, courseManagementImprovement: 0)
    }
    func calculateOverallImprovement(scorecards: [ScorecardEntry]) -> Double { return 0 }
    func identifyImprovementMilestones(scorecards: [ScorecardEntry]) -> [ImprovementMilestone] { return [] }
    func projectFutureImprovement(currentTrend: Double, playerData: [ScorecardEntry]) -> ProjectedImprovement {
        return ProjectedImprovement(next3Months: 0, next6Months: 0, nextYear: 0, confidence: 0.5, requiredFocus: [])
    }
    func analyzeSkillArea(category: SkillArea.SkillCategory, scorecards: [ScorecardEntry]) -> SkillArea {
        return SkillArea(skill: category, rating: 75, percentileRank: 60, trend: .stable, improvement: 0, priority: .medium)
    }
    func determineComparisonGroup(estimatedHandicap: Double) -> ComparisonGroup {
        return ComparisonGroup(groupType: .handicapRange, averageHandicap: estimatedHandicap, playerRankInGroup: 1, totalInGroup: 100)
    }
    func assessDevelopmentPotential(skillAreas: [SkillArea], improvementTrend: ImprovementAnalysis) -> DevelopmentPotential {
        return DevelopmentPotential(overallPotential: .moderate, shortTermPotential: 2, longTermPotential: 5, limitingFactors: [], acceleratingFactors: [])
    }
    func generateRecommendationForWeakness(weakness: SkillArea, playerAnalysis: PlayerAnalysis) -> ImprovementRecommendation {
        return ImprovementRecommendation(id: UUID().uuidString, category: weakness.skill, title: "Improve \(weakness.skill)", description: "Focus on this area", priority: .high, estimatedImprovement: 2.0, timeframe: "3 months", difficulty: .moderate, resources: [])
    }
    func generateRecommendationForImprovement(area: SkillArea) -> ImprovementRecommendation {
        return ImprovementRecommendation(id: UUID().uuidString, category: area.skill, title: "Enhance \(area.skill)", description: "Build on strength", priority: .medium, estimatedImprovement: 1.0, timeframe: "2 months", difficulty: .easy, resources: [])
    }
    func getLeaderboardFieldStrength(leaderboardId: String) async throws -> FieldStrength {
        return FieldStrength(averageRating: 1500, ratingStandardDeviation: 200, numberOfPlayers: 50, strengthTier: .competitive, notableParticipants: [])
    }
    func defaultConditions() -> PlayingConditions {
        return PlayingConditions(weather: WeatherConditions(windSpeed: 5, windDirection: 0, temperature: 20, humidity: 0.5, precipitation: 0, visibility: 10, difficultyImpact: 0), courseCondition: CourseCondition(fairwayCondition: .good, greenCondition: .good, roughCondition: .good, overallDifficulty: 0), pin: PinConditions(averageDifficulty: 5, frontPins: 6, middlePins: 6, backPins: 6, toughestHoles: []), expectedDifficulty: DifficultyAdjustment(strokesAdjustment: 0, factorsConsidered: [], confidenceLevel: 0.8))
    }
    func calculateRatingAdjustment(playerRating: Double, fieldStrength: FieldStrength) -> Double { return 0 }
    func calculateDifficultyAdjustment(conditions: PlayingConditions) -> Double { return conditions.expectedDifficulty.strokesAdjustment }
    func calculateQualityOfFieldAdjustment(fieldStrength: FieldStrength) -> Double { return 0 }
    func updatePlayerRating(playerId: String, newRating: Double) async throws {}
    func calculateExpectedFinish(playerRating: Double, fieldStrength: FieldStrength) -> Int { return 25 }
    
    // Calculation methods for predictive analytics
    func getHistoricalScores(playerId: String, courseId: String) async throws -> [Double] { return [] }
    func calculateBaselinePrediction(historicalScores: [Double], playerStats: (consistency: Double)) -> Double { return 85.0 }
    func calculateWeatherImpact(conditions: PlayingConditions, playerProfile: (consistency: Double)) -> Double { return conditions.weather.difficultyImpact }
    func calculateCourseFitAdjustment(playerId: String, courseId: String) async throws -> Double { return 0 }
    func calculatePredictionStandardDeviation(historicalScores: [Double]) -> Double { return 3.0 }
    func calculatePredictionConfidence(factors: [PredictionFactor], dataQuality: Int) -> Double { return min(0.9, Double(dataQuality) / 20.0) }
    func calculateHistoricalAccuracy(playerId: String) async throws -> Double { return 0.75 }
    func calculateScoreProbability(targetScore: Int, prediction: ScorePrediction) -> Double {
        let distance = abs(targetScore - prediction.mostLikelyScore)
        return max(0.1, prediction.confidence * exp(-Double(distance) / 3.0))
    }
    func identifyKeyFactors(for targetScore: Int, prediction: ScorePrediction) -> [String] { return ["Current form", "Course conditions"] }
    func getCurrentBestScore(playerId: String, courseId: String) async throws -> Int { return 85 }
    func calculateFinishRange(playerPrediction: ScorePrediction, field: [(playerId: String, prediction: ScorePrediction)]) -> ClosedRange<Int> {
        let position = field.firstIndex { $0.prediction.mostLikelyScore >= playerPrediction.mostLikelyScore } ?? field.count
        let range = max(1, Int(Double(field.count) * 0.1))
        return max(1, position - range)...min(field.count, position + range)
    }
    func calculateTopTenProbability(prediction: ScorePrediction, field: [(playerId: String, prediction: ScorePrediction)]) -> Double {
        let betterPlayers = field.filter { $0.prediction.mostLikelyScore < prediction.mostLikelyScore }.count
        return max(0.1, min(0.9, Double(10 - betterPlayers) / 10.0))
    }
    func calculateWinProbability(prediction: ScorePrediction, field: [(playerId: String, prediction: ScorePrediction)]) -> Double {
        return 1.0 / Double(field.count) * prediction.confidence
    }
    func generateKeyMatchups(playerId: String, field: [(playerId: String, prediction: ScorePrediction)]) -> [PlayerMatchup] {
        return field.prefix(3).compactMap { player in
            guard player.playerId != playerId else { return nil }
            return PlayerMatchup(opponentId: player.playerId, opponentName: "Player", headToHeadAdvantage: 0.1, winProbability: 0.5)
        }
    }
    
    // Form and momentum calculations
    func calculateMomentumFromScores(scores: [Double]) -> MomentumIndicator {
        guard scores.count >= 3 else { return MomentumIndicator(direction: .neutral, strength: 0.5, sustainabilityProbability: 0.5) }
        
        let recent = Array(scores.prefix(3))
        let trend = (recent.last! - recent.first!) / 3.0
        
        let direction: MomentumIndicator.MomentumDirection
        if trend < -0.5 { direction = .positive }
        else if trend > 0.5 { direction = .negative }
        else { direction = .neutral }
        
        return MomentumIndicator(direction: direction, strength: min(1.0, abs(trend)), sustainabilityProbability: 0.6)
    }
    
    func calculateConsistency(scores: [Double]) -> Double {
        guard scores.count > 1 else { return 0.5 }
        
        let mean = scores.reduce(0, +) / Double(scores.count)
        let variance = scores.map { pow($0 - mean, 2) }.reduce(0, +) / Double(scores.count)
        let standardDeviation = sqrt(variance)
        
        return max(0, 1.0 - (standardDeviation / 5.0)) // Normalize to 0-1 scale
    }
    
    func analyzeStreaks(scores: [Double]) -> StreakAnalysis {
        guard !scores.isEmpty else {
            return StreakAnalysis(currentStreak: .stable(rounds: 0), longestPositiveStreak: 0, streakProbability: StreakProbability(continueCurrentStreak: 0.5, breakOutPositively: 0.3, enterDecline: 0.2))
        }
        
        // Simplified streak analysis
        let recentTrend = scores.count >= 3 ? scores[0] - scores[2] : 0
        let currentStreak: StreakAnalysis.StreakType
        
        if recentTrend < -1.0 {
            currentStreak = .improvement(rounds: min(scores.count, 3))
        } else if recentTrend > 1.0 {
            currentStreak = .decline(rounds: min(scores.count, 3))
        } else {
            currentStreak = .stable(rounds: min(scores.count, 3))
        }
        
        return StreakAnalysis(
            currentStreak: currentStreak,
            longestPositiveStreak: 5, // Would be calculated from full history
            streakProbability: StreakProbability(continueCurrentStreak: 0.4, breakOutPositively: 0.3, enterDecline: 0.3)
        )
    }
    
    func calculateFormTrend(scores: [Double]) -> FormTrend {
        let shortTerm = scores.count >= 3 ? (scores[2] - scores[0]) / 3.0 : 0
        let mediumTerm = scores.count >= 10 ? (scores[9] - scores[0]) / 10.0 : shortTerm
        let seasonalTrend = scores.count >= 20 ? (scores[19] - scores[0]) / 20.0 : mediumTerm
        
        return FormTrend(shortTermTrend: shortTerm, mediumTermTrend: mediumTerm, seasonalTrend: seasonalTrend, peakPerformanceWindow: nil)
    }
    
    // Rating calculation helpers
    func getBaseCompetitiveRating(playerId: String) async throws -> Double? { return 1500.0 }
    func getFieldStrength(tournamentId: String) async throws -> FieldStrength {
        return FieldStrength(averageRating: 1500, ratingStandardDeviation: 200, numberOfPlayers: 50, strengthTier: .competitive, notableParticipants: [])
    }
    func calculateELORatingChange(currentRating: Double, finish: Int, fieldSize: Int, fieldStrength: FieldStrength) -> Double {
        let expected = 1.0 / (1.0 + pow(10, (fieldStrength.averageRating - currentRating) / 400))
        let actual = Double(fieldSize - finish) / Double(fieldSize - 1)
        let kFactor = 32.0
        return kFactor * (actual - expected)
    }
    func calculateRatingConfidence(tournaments: [TournamentResult]) -> Double {
        return min(0.9, Double(tournaments.count) / 20.0)
    }
    func calculateRatingVolatility(tournaments: [TournamentResult]) -> Double {
        guard tournaments.count > 1 else { return 0.5 }
        
        let finishes = tournaments.map { Double($0.finish) }
        let mean = finishes.reduce(0, +) / Double(finishes.count)
        let variance = finishes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(finishes.count)
        
        return min(1.0, sqrt(variance) / 25.0) // Normalize volatility
    }
    func calculateMomentum(tournaments: [TournamentResult]) -> Double {
        guard tournaments.count >= 3 else { return 0 }
        
        let recentTournaments = tournaments.sorted { $0.date > $1.date }.prefix(3)
        let positions = recentTournaments.map { Double($0.finish) }
        let trend = (positions.first! - positions.last!) / 3.0
        
        return max(-1.0, min(1.0, trend / 10.0)) // Normalize to -1 to 1 range
    }
    
    func calculateFieldStrengthAdjustment(fieldStrength: FieldStrength) -> Double {
        // Adjust based on field strength tier
        switch fieldStrength.strengthTier {
        case .recreational: return -2.0
        case .competitive: return 0.0
        case .elite: return 2.0
        case .professional: return 4.0
        }
    }
    
    func calculateConditionsAdjustment(conditions: PlayingConditions) -> Double {
        return conditions.expectedDifficulty.strokesAdjustment
    }
}

// MARK: - Rating Engine Cache

private class RatingEngineCache {
    private var handicapIndices: [String: HandicapIndex] = [:]
    private var performanceRatings: [String: PerformanceRating] = [:]
    private var predictions: [String: ScorePrediction] = [:]
    private let cacheQueue = DispatchQueue(label: "rating.engine.cache", attributes: .concurrent)
    
    func getHandicapIndex(for playerId: String) -> HandicapIndex? {
        return cacheQueue.sync { handicapIndices[playerId] }
    }
    
    func setHandicapIndex(_ handicapIndex: HandicapIndex, for playerId: String) {
        cacheQueue.async(flags: .barrier) {
            self.handicapIndices[playerId] = handicapIndex
        }
    }
    
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.handicapIndices.removeAll()
            self.performanceRatings.removeAll()
            self.predictions.removeAll()
        }
    }
}

// MARK: - Rating Engine Errors

enum RatingEngineError: Error {
    case insufficientScores
    case noCurrentHandicap
    case noDataForPeriod
    case playerNotInLeaderboard
    case noTournamentHistory
    case playerNotFound
    case noRecentScores
    case insufficientData
    
    var localizedDescription: String {
        switch self {
        case .insufficientScores:
            return "Not enough scores to calculate handicap (minimum 3 required)"
        case .noCurrentHandicap:
            return "No current handicap found for player"
        case .noDataForPeriod:
            return "No performance data available for specified period"
        case .playerNotInLeaderboard:
            return "Player not found in leaderboard"
        case .noTournamentHistory:
            return "No tournament history found for player"
        case .playerNotFound:
            return "Player not found"
        case .noRecentScores:
            return "No recent scores available"
        case .insufficientData:
            return "Insufficient data for analysis"
        }
    }
}

// MARK: - Extensions

private extension Date {
    var iso8601: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

private extension Leaderboard {
    var conditions: PlayingConditions? {
        // This would be populated with actual conditions data
        return nil
    }
}

private extension GolfCourse {
    var holes: [GolfHole] {
        // This would return actual hole data
        return []
    }
}

private struct GolfHole {
    let par: Int
    let yardage: Int
    // Additional hole properties
}