import Foundation
import CoreLocation
import Appwrite
import Combine

// MARK: - Scorecard Service Protocol

protocol ScorecardServiceProtocol: ObservableObject {
    // Current round management
    var currentScorecard: Scorecard? { get }
    var isRoundInProgress: Bool { get }
    
    // Scorecard CRUD operations
    func startNewRound(courseId: String, teeType: TeeType) async throws -> Scorecard
    func updateHoleScore(_ holeScore: HoleScore, for scorecardId: String) async throws
    func completeRound(_ scorecardId: String) async throws -> Scorecard
    func saveScorecard(_ scorecard: Scorecard) async throws
    func deleteScorecard(_ scorecardId: String) async throws
    
    // Scorecard retrieval
    func getScorecard(id: String) async throws -> Scorecard
    func getUserScorecards(userId: String, limit: Int) async throws -> [Scorecard]
    func getRecentRounds(userId: String, days: Int) async throws -> [Scorecard]
    
    // USGA handicap calculations
    func calculateHandicapIndex(for userId: String) async throws -> Double
    func calculateCourseHandicap(handicapIndex: Double, course: GolfCourse, teeType: TeeType) -> Int
    func calculatePlayingHandicap(courseHandicap: Int, course: GolfCourse) -> Int
    func calculateNetDoubleBogey(scorecard: Scorecard, handicapIndex: Double) -> Int
    
    // Statistics and analysis
    func calculateRoundStatistics(for scorecard: Scorecard) -> RoundStatistics
    func getUserStatistics(userId: String, timeframe: StatisticsTimeframe) async throws -> UserGolfStatistics
    func getHandicapTrend(userId: String, months: Int) async throws -> [HandicapEntry]
    
    // GPS shot tracking
    func startShotTracking(scorecardId: String, holeNumber: Int)
    func recordShot(scorecardId: String, holeNumber: Int, shot: Shot) async throws
    func stopShotTracking()
    func getShotTrackingData(scorecardId: String, holeNumber: Int) -> [Shot]
}

// MARK: - Additional Data Models

struct UserGolfStatistics: Codable {
    let userId: String
    let timeframe: StatisticsTimeframe
    let totalRounds: Int
    let averageScore: Double
    let bestScore: Int
    let worstScore: Int
    let currentHandicap: Double?
    
    // Performance metrics
    let averageFairwayHitPercentage: Double
    let averageGIRPercentage: Double
    let averagePuttsPerRound: Double
    let averagePenaltiesPerRound: Double
    
    // Scoring distribution
    let eagles: Int
    let birdies: Int
    let pars: Int
    let bogeys: Int
    let doubleBogeys: Int
    let otherScores: Int
    
    // Trends
    let scoreTrend: ScoreTrend
    let handicapTrend: HandicapTrend
    
    // Course performance
    let favoriteCourse: String?
    let bestCoursePerformance: (courseId: String, averageScore: Double)?
}

enum StatisticsTimeframe: String, CaseIterable, Codable {
    case lastMonth = "last_month"
    case lastThreeMonths = "last_3_months"
    case lastSixMonths = "last_6_months"
    case lastYear = "last_year"
    case allTime = "all_time"
    
    var days: Int {
        switch self {
        case .lastMonth: return 30
        case .lastThreeMonths: return 90
        case .lastSixMonths: return 180
        case .lastYear: return 365
        case .allTime: return 3650 // 10 years
        }
    }
}

enum ScoreTrend: String, CaseIterable, Codable {
    case improving = "improving"
    case stable = "stable"
    case declining = "declining"
    
    var description: String {
        switch self {
        case .improving: return "Your scores are improving!"
        case .stable: return "Your scores are consistent"
        case .declining: return "Focus on practice to improve"
        }
    }
}

enum HandicapTrend: String, CaseIterable, Codable {
    case improving = "improving"
    case stable = "stable"
    case declining = "declining"
    
    var description: String {
        switch self {
        case .improving: return "Handicap is improving"
        case .stable: return "Handicap is stable"
        case .declining: return "Handicap is increasing"
        }
    }
}

struct HandicapEntry: Identifiable, Codable {
    let id: String
    let userId: String
    let handicapIndex: Double
    let calculationDate: Date
    let roundsUsed: Int
    let scoringRecords: [ScoringRecord]
    
    struct ScoringRecord: Codable {
        let scorecardId: String
        let courseName: String
        let adjustedScore: Int
        let courseRating: Double
        let slopeRating: Int
        let handicapDifferential: Double
        let playedDate: Date
    }
}

// MARK: - Scorecard Service Implementation

@MainActor
class ScorecardService: ScorecardServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentScorecard: Scorecard?
    @Published var isRoundInProgress: Bool = false
    
    // MARK: - Private Properties
    
    private let client: Client
    private let databases: Databases
    
    // Database configuration
    private let databaseId = Configuration.appwrite.databaseId
    private let scorecardsCollectionId = "scorecards"
    private let handicapEntriesCollectionId = "handicap_entries"
    private let shotTrackingCollectionId = "shot_tracking"
    
    // GPS tracking
    private var locationService: LocationServiceProtocol?
    private var golfCourseService: GolfCourseServiceProtocol?
    private var currentShotTracking: (scorecardId: String, holeNumber: Int)?
    
    // Caching for performance
    private let statisticsCache = NSCache<NSString, NSData>()
    
    // MARK: - Initialization
    
    init(appwriteClient: Client) {
        self.client = appwriteClient
        self.databases = Databases(client)
        
        // Configure cache
        statisticsCache.countLimit = 50
        statisticsCache.totalCostLimit = 10 * 1024 * 1024 // 10MB
    }
    
    init(appwriteClient: Client, locationService: LocationServiceProtocol, golfCourseService: GolfCourseServiceProtocol) {
        self.client = appwriteClient
        self.databases = Databases(client)
        self.locationService = locationService
        self.golfCourseService = golfCourseService
        
        statisticsCache.countLimit = 50
        statisticsCache.totalCostLimit = 10 * 1024 * 1024 // 10MB
    }
    
    // MARK: - Round Management
    
    func startNewRound(courseId: String, teeType: TeeType) async throws -> Scorecard {
        // Get course details
        guard let golfCourseService = golfCourseService ?? ServiceContainer.shared.resolve(GolfCourseServiceProtocol.self) as? GolfCourseServiceProtocol else {
            throw ScorecardError.serviceNotAvailable
        }
        
        let course = try await golfCourseService.getCourseDetails(courseId: courseId)
        let courseLayout = try await golfCourseService.getCourseLayout(courseId: courseId)
        
        // Create hole scores for the course
        let holeScores = courseLayout.map { hole in
            HoleScore(
                id: UUID().uuidString,
                holeNumber: hole.holeNumber,
                par: hole.par,
                yardage: getYardageForTeeType(hole: hole, teeType: teeType),
                handicapIndex: hole.handicapIndex,
                score: "",
                adjustedScore: nil,
                netScore: nil,
                stablefordPoints: nil,
                shots: nil,
                putts: nil,
                penalties: 0,
                fairwayHit: nil,
                greenInRegulation: nil,
                pinPosition: nil,
                teeCondition: nil
            )
        }
        
        // Get course rating and slope for the tee type
        let (courseRating, slopeRating) = getCourseRatingForTeeType(course: course, teeType: teeType)
        
        // Create new scorecard
        let scorecard = Scorecard(
            id: UUID().uuidString,
            userId: getCurrentUserId(),
            courseId: courseId,
            courseName: course.name,
            teeTimeId: nil,
            playedDate: Date(),
            teeType: teeType,
            numberOfHoles: course.numberOfHoles,
            courseRating: courseRating,
            slopeRating: slopeRating,
            coursePar: course.par,
            holeScores: holeScores,
            totalScore: 0,
            totalPar: course.par,
            scoreRelativeToPar: 0,
            grossScore: 0,
            netScore: nil,
            adjustedGrossScore: nil,
            statistics: createEmptyRoundStatistics(),
            weather: nil,
            courseConditions: nil,
            isOfficial: true,
            isCompetitive: false,
            playingPartners: [],
            attestedBy: nil,
            notes: nil,
            isVerified: false,
            verificationMethod: .selfReported,
            gpsData: [],
            createdAt: Date(),
            updatedAt: Date(),
            submittedAt: nil
        )
        
        // Save to database
        try await saveScorecard(scorecard)
        
        // Set as current scorecard
        currentScorecard = scorecard
        isRoundInProgress = true
        
        return scorecard
    }
    
    func updateHoleScore(_ holeScore: HoleScore, for scorecardId: String) async throws {
        guard var scorecard = currentScorecard, scorecard.id == scorecardId else {
            // Load scorecard if not current
            var loadedScorecard = try await getScorecard(id: scorecardId)
            
            // Update the specific hole score
            if let index = loadedScorecard.holeScores.firstIndex(where: { $0.holeNumber == holeScore.holeNumber }) {
                loadedScorecard.holeScores[index] = holeScore
            }
            
            // Recalculate totals and statistics
            let updatedScorecard = recalculateScorecard(loadedScorecard)
            
            try await saveScorecard(updatedScorecard)
            return
        }
        
        // Update hole score in current scorecard
        if let index = scorecard.holeScores.firstIndex(where: { $0.holeNumber == holeScore.holeNumber }) {
            scorecard.holeScores[index] = holeScore
        }
        
        // Recalculate totals and statistics
        scorecard = recalculateScorecard(scorecard)
        
        // Save updated scorecard
        try await saveScorecard(scorecard)
        
        // Update current scorecard
        currentScorecard = scorecard
    }
    
    func completeRound(_ scorecardId: String) async throws -> Scorecard {
        var scorecard = try await getScorecard(id: scorecardId)
        
        // Validate that the round is complete
        guard scorecard.isComplete else {
            throw ScorecardError.incompleteRound
        }
        
        // Mark as completed
        scorecard.submittedAt = Date()
        scorecard.updatedAt = Date()
        scorecard.isVerified = true
        
        // Calculate adjusted gross score for handicap
        let handicapIndex = try await calculateHandicapIndex(for: scorecard.userId)
        let adjustedScore = calculateNetDoubleBogey(scorecard: scorecard, handicapIndex: handicapIndex)
        scorecard.adjustedGrossScore = adjustedScore
        
        // Recalculate final statistics
        scorecard = recalculateScorecard(scorecard)
        
        // Save final scorecard
        try await saveScorecard(scorecard)
        
        // Update handicap calculation
        try await updateHandicapCalculation(for: scorecard.userId, newScorecard: scorecard)
        
        // Clear current round
        if currentScorecard?.id == scorecardId {
            currentScorecard = nil
            isRoundInProgress = false
        }
        
        return scorecard
    }
    
    func saveScorecard(_ scorecard: Scorecard) async throws {
        let scorecardData = try encodeScorecardToDocumentData(scorecard)
        
        do {
            // Check if scorecard exists
            let existingDocument = try? await databases.getDocument(
                databaseId: databaseId,
                collectionId: scorecardsCollectionId,
                documentId: scorecard.id
            )
            
            if existingDocument != nil {
                // Update existing scorecard
                _ = try await databases.updateDocument(
                    databaseId: databaseId,
                    collectionId: scorecardsCollectionId,
                    documentId: scorecard.id,
                    data: scorecardData
                )
            } else {
                // Create new scorecard
                _ = try await databases.createDocument(
                    databaseId: databaseId,
                    collectionId: scorecardsCollectionId,
                    documentId: scorecard.id,
                    data: scorecardData
                )
            }
        } catch {
            print("Error saving scorecard: \(error)")
            throw ScorecardError.saveFailed(error.localizedDescription)
        }
    }
    
    func deleteScorecard(_ scorecardId: String) async throws {
        do {
            try await databases.deleteDocument(
                databaseId: databaseId,
                collectionId: scorecardsCollectionId,
                documentId: scorecardId
            )
            
            // Clear current scorecard if it was deleted
            if currentScorecard?.id == scorecardId {
                currentScorecard = nil
                isRoundInProgress = false
            }
        } catch {
            print("Error deleting scorecard: \(error)")
            throw ScorecardError.deleteFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Scorecard Retrieval
    
    func getScorecard(id: String) async throws -> Scorecard {
        do {
            let document = try await databases.getDocument(
                databaseId: databaseId,
                collectionId: scorecardsCollectionId,
                documentId: id
            )
            
            return try parseScorecardFromDocument(document)
            
        } catch {
            print("Error fetching scorecard: \(error)")
            throw ScorecardError.loadFailed(error.localizedDescription)
        }
    }
    
    func getUserScorecards(userId: String, limit: Int) async throws -> [Scorecard] {
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: scorecardsCollectionId,
                queries: [
                    "userId = '\(userId)'",
                    "limit = \(limit)"
                ]
            )
            
            return try response.documents.compactMap { doc in
                try parseScorecardFromDocument(doc)
            }.sorted { $0.playedDate > $1.playedDate }
            
        } catch {
            print("Error fetching user scorecards: \(error)")
            throw ScorecardError.loadFailed(error.localizedDescription)
        }
    }
    
    func getRecentRounds(userId: String, days: Int) async throws -> [Scorecard] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: scorecardsCollectionId,
                queries: [
                    "userId = '\(userId)'",
                    "playedDate >= '\(startDate.ISO8601String())'"
                ]
            )
            
            return try response.documents.compactMap { doc in
                try parseScorecardFromDocument(doc)
            }.sorted { $0.playedDate > $1.playedDate }
            
        } catch {
            print("Error fetching recent rounds: \(error)")
            throw ScorecardError.loadFailed(error.localizedDescription)
        }
    }
    
    // MARK: - USGA Handicap Calculations
    
    func calculateHandicapIndex(for userId: String) async throws -> Double {
        // Get recent scorecards (last 20 rounds or 365 days)
        let recentScorecards = try await getRecentRounds(userId: userId, days: 365)
            .filter { $0.qualifiesForHandicap }
            .prefix(20)
        
        guard recentScorecards.count >= 3 else {
            throw ScorecardError.insufficientData
        }
        
        // Calculate handicap differentials
        let handicapDifferentials = recentScorecards.compactMap { scorecard -> Double? in
            scorecard.handicapDifferential
        }
        
        guard handicapDifferentials.count >= 3 else {
            throw ScorecardError.insufficientData
        }
        
        // Sort differentials (best to worst)
        let sortedDifferentials = handicapDifferentials.sorted()
        
        // Determine how many differentials to use based on USGA rules
        let numberOfRounds = sortedDifferentials.count
        let numberOfDifferentialsToUse: Int
        
        switch numberOfRounds {
        case 3...4: numberOfDifferentialsToUse = 1
        case 5...6: numberOfDifferentialsToUse = 2
        case 7...8: numberOfDifferentialsToUse = 3
        case 9...10: numberOfDifferentialsToUse = 4
        case 11...12: numberOfDifferentialsToUse = 5
        case 13...14: numberOfDifferentialsToUse = 6
        case 15...16: numberOfDifferentialsToUse = 7
        case 17...18: numberOfDifferentialsToUse = 8
        case 19: numberOfDifferentialsToUse = 9
        default: numberOfDifferentialsToUse = 10 // 20+ rounds
        }
        
        // Take the lowest differentials
        let usedDifferentials = Array(sortedDifferentials.prefix(numberOfDifferentialsToUse))
        let averageDifferential = usedDifferentials.reduce(0, +) / Double(usedDifferentials.count)
        
        // Handicap Index = average of lowest differentials * 0.96
        let handicapIndex = averageDifferential * 0.96
        
        // Save handicap calculation
        try await saveHandicapEntry(userId: userId, handicapIndex: handicapIndex, scorecards: Array(recentScorecards))
        
        return max(0.0, min(54.0, handicapIndex)) // USGA limits: 0-54
    }
    
    func calculateCourseHandicap(handicapIndex: Double, course: GolfCourse, teeType: TeeType) -> Int {
        let (_, slopeRating) = getCourseRatingForTeeType(course: course, teeType: teeType)
        
        // Course Handicap = Handicap Index * Slope Rating / 113
        let courseHandicap = (handicapIndex * Double(slopeRating)) / 113.0
        
        return Int(round(courseHandicap))
    }
    
    func calculatePlayingHandicap(courseHandicap: Int, course: GolfCourse) -> Int {
        // Playing Handicap adjustments based on course conditions, competition format, etc.
        // For standard stroke play, Playing Handicap = Course Handicap
        return courseHandicap
    }
    
    func calculateNetDoubleBogey(scorecard: Scorecard, handicapIndex: Double) -> Int {
        let courseHandicap = calculateCourseHandicap(
            handicapIndex: handicapIndex,
            course: createCourseFromScorecard(scorecard),
            teeType: scorecard.teeType
        )
        
        var adjustedScore = 0
        
        for hole in scorecard.holeScores {
            // Determine strokes received on this hole
            let strokesReceived = strokesReceivedOnHole(
                holeHandicap: hole.handicapIndex,
                courseHandicap: courseHandicap,
                numberOfHoles: scorecard.numberOfHoles
            )
            
            // Net Double Bogey = Par + 2 + strokes received
            let netDoubleBogey = hole.par + 2 + strokesReceived
            
            // Use actual score or net double bogey, whichever is lower
            let actualScore = hole.scoreInt ?? netDoubleBogey
            adjustedScore += min(actualScore, netDoubleBogey)
        }
        
        return adjustedScore
    }
    
    // MARK: - Statistics and Analysis
    
    func calculateRoundStatistics(for scorecard: Scorecard) -> RoundStatistics {
        var pars = 0, birdies = 0, eagles = 0, bogeys = 0, doubleBogeys = 0, otherScores = 0
        var fairwaysHit = 0, totalFairways = 0, greensInRegulation = 0, totalGreens = 0
        var totalPenalties = 0, totalPutts = 0, puttCount = 0
        var longestDrive: Int?
        
        for hole in scorecard.holeScores {
            guard let score = hole.scoreInt else { continue }
            
            // Scoring distribution
            let relativeToPar = score - hole.par
            switch relativeToPar {
            case -2: eagles += 1
            case -1: birdies += 1
            case 0: pars += 1
            case 1: bogeys += 1
            case 2: doubleBogeys += 1
            default: otherScores += 1
            }
            
            // Fairway stats (par 4 and 5 holes only)
            if hole.par >= 4 {
                totalFairways += 1
                if hole.fairwayHit == true {
                    fairwaysHit += 1
                }
            }
            
            // Green in regulation stats
            totalGreens += 1
            if hole.greenInRegulation == true {
                greensInRegulation += 1
            }
            
            // Penalty stats
            totalPenalties += hole.penalties
            
            // Putting stats
            if let putts = hole.putts {
                totalPutts += putts
                puttCount += 1
            }
            
            // Distance tracking (would come from shot tracking)
            if let shots = hole.shots {
                for shot in shots {
                    if shot.club == .driver, let distance = shot.distance {
                        longestDrive = max(longestDrive ?? 0, distance)
                    }
                }
            }
        }
        
        let averagePuttsPerHole = puttCount > 0 ? Double(totalPutts) / Double(puttCount) : nil
        
        return RoundStatistics(
            pars: pars,
            birdies: birdies,
            eagles: eagles,
            bogeys: bogeys,
            doubleBogeys: doubleBogeys,
            otherScores: otherScores,
            fairwaysHit: fairwaysHit,
            totalFairways: totalFairways,
            greensInRegulation: greensInRegulation,
            totalGreens: totalGreens,
            totalPutts: puttCount > 0 ? totalPutts : nil,
            averagePuttsPerHole: averagePuttsPerHole,
            totalPenalties: totalPenalties,
            waterHazards: 0, // Would be tracked in shot data
            sandSaves: 0,    // Would be calculated from shot data
            upAndDowns: 0,   // Would be calculated from shot data
            longestDrive: longestDrive,
            averageDriveDistance: nil, // Would be calculated from shot data
            drivingAccuracy: nil       // Would be calculated from shot data
        )
    }
    
    func getUserStatistics(userId: String, timeframe: StatisticsTimeframe) async throws -> UserGolfStatistics {
        let cacheKey = "stats_\(userId)_\(timeframe.rawValue)" as NSString
        
        // Check cache first
        if let cachedData = statisticsCache.object(forKey: cacheKey) as? Data,
           let cachedStats = try? JSONDecoder().decode(UserGolfStatistics.self, from: cachedData) {
            return cachedStats
        }
        
        // Calculate fresh statistics
        let scorecards = try await getRecentRounds(userId: userId, days: timeframe.days)
        
        guard !scorecards.isEmpty else {
            throw ScorecardError.insufficientData
        }
        
        let totalRounds = scorecards.count
        let scores = scorecards.compactMap { $0.totalScore }
        let averageScore = Double(scores.reduce(0, +)) / Double(scores.count)
        let bestScore = scores.min() ?? 0
        let worstScore = scores.max() ?? 0
        
        // Calculate current handicap
        let currentHandicap = try? await calculateHandicapIndex(for: userId)
        
        // Performance metrics
        let fairwayStats = scorecards.map { $0.statistics.fairwayPercentage }
        let girStats = scorecards.map { $0.statistics.girPercentage }
        let puttStats = scorecards.compactMap { $0.statistics.averagePuttsPerHole }
        
        let avgFairwayHit = fairwayStats.isEmpty ? 0 : fairwayStats.reduce(0, +) / Double(fairwayStats.count)
        let avgGIR = girStats.isEmpty ? 0 : girStats.reduce(0, +) / Double(girStats.count)
        let avgPutts = puttStats.isEmpty ? 0 : puttStats.reduce(0, +) / Double(puttStats.count)
        let avgPenalties = Double(scorecards.map { $0.statistics.totalPenalties }.reduce(0, +)) / Double(totalRounds)
        
        // Scoring distribution
        let allStats = scorecards.map { $0.statistics }
        let eagles = allStats.map { $0.eagles }.reduce(0, +)
        let birdies = allStats.map { $0.birdies }.reduce(0, +)
        let pars = allStats.map { $0.pars }.reduce(0, +)
        let bogeys = allStats.map { $0.bogeys }.reduce(0, +)
        let doubleBogeys = allStats.map { $0.doubleBogeys }.reduce(0, +)
        let otherScores = allStats.map { $0.otherScores }.reduce(0, +)
        
        // Trends (simplified)
        let scoreTrend = calculateScoreTrend(scorecards: scorecards)
        let handicapTrend = calculateHandicapTrend(scorecards: scorecards)
        
        let statistics = UserGolfStatistics(
            userId: userId,
            timeframe: timeframe,
            totalRounds: totalRounds,
            averageScore: averageScore,
            bestScore: bestScore,
            worstScore: worstScore,
            currentHandicap: currentHandicap,
            averageFairwayHitPercentage: avgFairwayHit,
            averageGIRPercentage: avgGIR,
            averagePuttsPerRound: avgPutts,
            averagePenaltiesPerRound: avgPenalties,
            eagles: eagles,
            birdies: birdies,
            pars: pars,
            bogeys: bogeys,
            doubleBogeys: doubleBogeys,
            otherScores: otherScores,
            scoreTrend: scoreTrend,
            handicapTrend: handicapTrend,
            favoriteCourse: findFavoriteCourse(scorecards: scorecards),
            bestCoursePerformance: findBestCoursePerformance(scorecards: scorecards)
        )
        
        // Cache results
        if let data = try? JSONEncoder().encode(statistics) {
            statisticsCache.setObject(data as NSData, forKey: cacheKey)
        }
        
        return statistics
    }
    
    func getHandicapTrend(userId: String, months: Int) async throws -> [HandicapEntry] {
        let startDate = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: handicapEntriesCollectionId,
                queries: [
                    "userId = '\(userId)'",
                    "calculationDate >= '\(startDate.ISO8601String())'"
                ]
            )
            
            return try response.documents.compactMap { doc in
                try parseHandicapEntryFromDocument(doc)
            }.sorted { $0.calculationDate < $1.calculationDate }
            
        } catch {
            print("Error fetching handicap trend: \(error)")
            throw ScorecardError.loadFailed(error.localizedDescription)
        }
    }
    
    // MARK: - GPS Shot Tracking
    
    func startShotTracking(scorecardId: String, holeNumber: Int) {
        currentShotTracking = (scorecardId, holeNumber)
        locationService?.enableHighAccuracyMode()
    }
    
    func recordShot(scorecardId: String, holeNumber: Int, shot: Shot) async throws {
        guard currentShotTracking?.scorecardId == scorecardId,
              currentShotTracking?.holeNumber == holeNumber else {
            throw ScorecardError.shotTrackingNotActive
        }
        
        // Add GPS location if available
        var shotWithGPS = shot
        if let location = try? await locationService?.getCurrentLocation() {
            let gpsPoint = GPSTrackingPoint(
                latitude: location.latitude,
                longitude: location.longitude,
                altitude: nil,
                accuracy: locationService?.accuracy ?? 0,
                timestamp: Date(),
                holeNumber: holeNumber,
                shotNumber: shot.shotNumber
            )
            shotWithGPS.gpsLocation = gpsPoint
        }
        
        // Save shot to database
        let shotData = try encodeShotToDocumentData(shotWithGPS, scorecardId: scorecardId, holeNumber: holeNumber)
        
        do {
            _ = try await databases.createDocument(
                databaseId: databaseId,
                collectionId: shotTrackingCollectionId,
                documentId: UUID().uuidString,
                data: shotData
            )
        } catch {
            print("Error saving shot data: \(error)")
            throw ScorecardError.shotTrackingFailed(error.localizedDescription)
        }
    }
    
    func stopShotTracking() {
        currentShotTracking = nil
        locationService?.disableHighAccuracyMode()
    }
    
    func getShotTrackingData(scorecardId: String, holeNumber: Int) -> [Shot] {
        // This would load shot data from the database
        // For now, return empty array as this would require async loading
        return []
    }
}

// MARK: - Private Helper Methods

private extension ScorecardService {
    
    func getCurrentUserId() -> String {
        // This would get the current user ID from the authentication service
        return "current_user_id" // Placeholder
    }
    
    func getYardageForTeeType(hole: HoleInfo, teeType: TeeType) -> Int {
        switch teeType {
        case .championship:
            return hole.yardages["Championship"] ?? hole.yardages["Back"] ?? 400
        case .back:
            return hole.yardages["Back"] ?? 350
        case .regular:
            return hole.yardages["Regular"] ?? 300
        case .forward, .ladies:
            return hole.yardages["Forward"] ?? hole.yardages["Ladies"] ?? 250
        case .senior:
            return hole.yardages["Senior"] ?? hole.yardages["Regular"] ?? 280
        case .junior:
            return hole.yardages["Junior"] ?? hole.yardages["Forward"] ?? 200
        }
    }
    
    func getCourseRatingForTeeType(course: GolfCourse, teeType: TeeType) -> (Double, Int) {
        let rating: Double
        let slope: Int
        
        switch teeType {
        case .championship:
            rating = course.rating.championshipRating
            slope = Int(course.slope.championshipSlope)
        case .back:
            rating = course.rating.backRating
            slope = Int(course.slope.backSlope)
        case .regular:
            rating = course.rating.regularRating
            slope = Int(course.slope.regularSlope)
        case .forward, .ladies:
            rating = course.rating.forwardRating
            slope = Int(course.slope.forwardSlope)
        case .senior:
            rating = course.rating.seniorRating ?? course.rating.regularRating
            slope = Int(course.slope.seniorSlope ?? course.slope.regularSlope)
        case .junior:
            rating = course.rating.juniorRating ?? course.rating.forwardRating
            slope = Int(course.slope.juniorSlope ?? course.slope.forwardSlope)
        }
        
        return (rating, slope)
    }
    
    func createEmptyRoundStatistics() -> RoundStatistics {
        return RoundStatistics(
            pars: 0, birdies: 0, eagles: 0, bogeys: 0, doubleBogeys: 0, otherScores: 0,
            fairwaysHit: 0, totalFairways: 0, greensInRegulation: 0, totalGreens: 0,
            totalPutts: nil, averagePuttsPerHole: nil, totalPenalties: 0,
            waterHazards: 0, sandSaves: 0, upAndDowns: 0,
            longestDrive: nil, averageDriveDistance: nil, drivingAccuracy: nil
        )
    }
    
    func recalculateScorecard(_ scorecard: Scorecard) -> Scorecard {
        let completedHoles = scorecard.holeScores.filter { !$0.score.isEmpty }
        let scores = completedHoles.compactMap { $0.scoreInt }
        
        let totalScore = scores.reduce(0, +)
        let totalPar = completedHoles.reduce(0) { $0 + $1.par }
        let scoreRelativeToPar = totalScore - totalPar
        
        let statistics = calculateRoundStatistics(for: scorecard)
        
        var updatedScorecard = scorecard
        updatedScorecard.totalScore = totalScore
        updatedScorecard.totalPar = totalPar
        updatedScorecard.scoreRelativeToPar = scoreRelativeToPar
        updatedScorecard.grossScore = totalScore
        updatedScorecard.statistics = statistics
        updatedScorecard.updatedAt = Date()
        
        return updatedScorecard
    }
    
    func createCourseFromScorecard(_ scorecard: Scorecard) -> GolfCourse {
        // Create a minimal course object for handicap calculations
        // In a real implementation, this would fetch the full course details
        return GolfCourse(
            id: scorecard.courseId,
            name: scorecard.courseName,
            address: "", city: "", state: "", country: "", zipCode: "",
            latitude: 0, longitude: 0,
            description: nil, phoneNumber: nil, website: nil, email: nil,
            numberOfHoles: scorecard.numberOfHoles,
            par: scorecard.coursePar,
            yardage: CourseYardage(championshipTees: 7000, backTees: 6500, regularTees: 6000, forwardTees: 5500, seniorTees: nil, juniorTees: nil),
            slope: CourseSlope(championshipSlope: 125, backSlope: 120, regularSlope: 115, forwardSlope: 110, seniorSlope: nil, juniorSlope: nil),
            rating: CourseRating(championshipRating: scorecard.courseRating, backRating: scorecard.courseRating, regularRating: scorecard.courseRating, forwardRating: scorecard.courseRating, seniorRating: nil, juniorRating: nil),
            pricing: CoursePricing(weekdayRates: [50], weekendRates: [75], twilightRates: [35], seniorRates: nil, juniorRates: nil, cartFee: 25, cartIncluded: false, membershipRequired: false, guestPolicy: .open, seasonalMultiplier: 1.0, peakTimeMultiplier: 1.2, advanceBookingDiscount: nil),
            amenities: [], dressCode: .moderate, cartPolicy: .optional, images: [], virtualTour: nil,
            averageRating: 0, totalReviews: 0, difficulty: .intermediate,
            operatingHours: OperatingHours(monday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), tuesday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), wednesday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), thursday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), friday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), saturday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00"), sunday: OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00")),
            seasonalInfo: nil,
            bookingPolicy: BookingPolicy(advanceBookingDays: 7, cancellationPolicy: "", noShowPolicy: "", modificationPolicy: "", depositRequired: false, depositAmount: nil, refundableDeposit: true, groupBookingMinimum: nil, onlineBookingAvailable: true, phoneBookingRequired: false),
            createdAt: Date(), updatedAt: Date(), isActive: true, isFeatured: false
        )
    }
    
    func strokesReceivedOnHole(holeHandicap: Int, courseHandicap: Int, numberOfHoles: Int) -> Int {
        if courseHandicap <= 0 { return 0 }
        
        let strokesPerHole = courseHandicap / numberOfHoles
        let extraStrokes = courseHandicap % numberOfHoles
        
        let strokesReceived = strokesPerHole + (holeHandicap <= extraStrokes ? 1 : 0)
        return strokesReceived
    }
    
    func saveHandicapEntry(userId: String, handicapIndex: Double, scorecards: [Scorecard]) async throws {
        let scoringRecords = scorecards.prefix(20).map { scorecard in
            HandicapEntry.ScoringRecord(
                scorecardId: scorecard.id,
                courseName: scorecard.courseName,
                adjustedScore: scorecard.adjustedGrossScore ?? scorecard.totalScore,
                courseRating: scorecard.courseRating,
                slopeRating: scorecard.slopeRating,
                handicapDifferential: scorecard.handicapDifferential ?? 0,
                playedDate: scorecard.playedDate
            )
        }
        
        let handicapEntry = HandicapEntry(
            id: UUID().uuidString,
            userId: userId,
            handicapIndex: handicapIndex,
            calculationDate: Date(),
            roundsUsed: scoringRecords.count,
            scoringRecords: Array(scoringRecords)
        )
        
        let entryData = try encodeHandicapEntryToDocumentData(handicapEntry)
        
        do {
            _ = try await databases.createDocument(
                databaseId: databaseId,
                collectionId: handicapEntriesCollectionId,
                documentId: handicapEntry.id,
                data: entryData
            )
        } catch {
            print("Error saving handicap entry: \(error)")
            // Don't throw error for handicap entry saves
        }
    }
    
    func updateHandicapCalculation(for userId: String, newScorecard: Scorecard) async throws {
        // Recalculate handicap with the new scorecard
        _ = try await calculateHandicapIndex(for: userId)
    }
    
    func calculateScoreTrend(scorecards: [Scorecard]) -> ScoreTrend {
        guard scorecards.count >= 5 else { return .stable }
        
        let recent = Array(scorecards.prefix(5))
        let older = Array(scorecards.dropFirst(5).prefix(5))
        
        let recentAvg = Double(recent.map { $0.totalScore }.reduce(0, +)) / Double(recent.count)
        let olderAvg = Double(older.map { $0.totalScore }.reduce(0, +)) / Double(older.count)
        
        let difference = recentAvg - olderAvg
        
        if difference < -2 {
            return .improving
        } else if difference > 2 {
            return .declining
        } else {
            return .stable
        }
    }
    
    func calculateHandicapTrend(scorecards: [Scorecard]) -> HandicapTrend {
        // Simplified trend calculation
        // Would use actual handicap entries in real implementation
        return .stable
    }
    
    func findFavoriteCourse(scorecards: [Scorecard]) -> String? {
        let courseCounts = Dictionary(grouping: scorecards, by: { $0.courseId })
            .mapValues { $0.count }
        
        return courseCounts.max(by: { $0.value < $1.value })?.key
    }
    
    func findBestCoursePerformance(scorecards: [Scorecard]) -> (courseId: String, averageScore: Double)? {
        let courseGroups = Dictionary(grouping: scorecards, by: { $0.courseId })
        
        var bestPerformance: (courseId: String, averageScore: Double)?
        
        for (courseId, courseScorecards) in courseGroups {
            guard courseScorecards.count >= 3 else { continue } // Need minimum rounds for meaningful average
            
            let scores = courseScorecards.map { $0.totalScore }
            let averageScore = Double(scores.reduce(0, +)) / Double(scores.count)
            
            if bestPerformance == nil || averageScore < bestPerformance!.averageScore {
                bestPerformance = (courseId, averageScore)
            }
        }
        
        return bestPerformance
    }
    
    // MARK: - Document Parsing and Encoding Methods
    
    func encodeScorecardToDocumentData(_ scorecard: Scorecard) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        return [
            "userId": scorecard.userId,
            "courseId": scorecard.courseId,
            "courseName": scorecard.courseName,
            "teeTimeId": scorecard.teeTimeId ?? NSNull(),
            "playedDate": scorecard.playedDate.ISO8601String(),
            "teeType": scorecard.teeType.rawValue,
            "numberOfHoles": scorecard.numberOfHoles,
            "courseRating": scorecard.courseRating,
            "slopeRating": scorecard.slopeRating,
            "coursePar": scorecard.coursePar,
            "holeScores": try encoder.encode(scorecard.holeScores).base64EncodedString(),
            "totalScore": scorecard.totalScore,
            "totalPar": scorecard.totalPar,
            "scoreRelativeToPar": scorecard.scoreRelativeToPar,
            "grossScore": scorecard.grossScore,
            "netScore": scorecard.netScore ?? NSNull(),
            "adjustedGrossScore": scorecard.adjustedGrossScore ?? NSNull(),
            "statistics": try encoder.encode(scorecard.statistics).base64EncodedString(),
            "isOfficial": scorecard.isOfficial,
            "isCompetitive": scorecard.isCompetitive,
            "playingPartners": scorecard.playingPartners,
            "attestedBy": scorecard.attestedBy ?? NSNull(),
            "notes": scorecard.notes ?? NSNull(),
            "isVerified": scorecard.isVerified,
            "verificationMethod": scorecard.verificationMethod.rawValue,
            "gpsData": try encoder.encode(scorecard.gpsData ?? []).base64EncodedString(),
            "createdAt": scorecard.createdAt.ISO8601String(),
            "updatedAt": scorecard.updatedAt.ISO8601String(),
            "submittedAt": scorecard.submittedAt?.ISO8601String() ?? NSNull()
        ]
    }
    
    func parseScorecardFromDocument(_ document: Document) throws -> Scorecard {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let userId = document.data["userId"] as? String,
              let courseId = document.data["courseId"] as? String,
              let courseName = document.data["courseName"] as? String,
              let playedDateString = document.data["playedDate"] as? String,
              let playedDate = ISO8601DateFormatter().date(from: playedDateString),
              let teeTypeString = document.data["teeType"] as? String,
              let teeType = TeeType(rawValue: teeTypeString),
              let numberOfHoles = document.data["numberOfHoles"] as? Int,
              let courseRating = document.data["courseRating"] as? Double,
              let slopeRating = document.data["slopeRating"] as? Int,
              let coursePar = document.data["coursePar"] as? Int else {
            throw ScorecardError.parsingError
        }
        
        // Parse hole scores
        let holeScoresData = Data(base64Encoded: document.data["holeScores"] as? String ?? "") ?? Data()
        let holeScores = (try? decoder.decode([HoleScore].self, from: holeScoresData)) ?? []
        
        // Parse statistics
        let statisticsData = Data(base64Encoded: document.data["statistics"] as? String ?? "") ?? Data()
        let statistics = (try? decoder.decode(RoundStatistics.self, from: statisticsData)) ?? createEmptyRoundStatistics()
        
        // Parse GPS data
        let gpsData = Data(base64Encoded: document.data["gpsData"] as? String ?? "") ?? Data()
        let trackingPoints = (try? decoder.decode([GPSTrackingPoint].self, from: gpsData)) ?? []
        
        let verificationMethodString = document.data["verificationMethod"] as? String ?? "self_reported"
        let verificationMethod = VerificationMethod(rawValue: verificationMethodString) ?? .selfReported
        
        return Scorecard(
            id: document.id,
            userId: userId,
            courseId: courseId,
            courseName: courseName,
            teeTimeId: document.data["teeTimeId"] as? String,
            playedDate: playedDate,
            teeType: teeType,
            numberOfHoles: numberOfHoles,
            courseRating: courseRating,
            slopeRating: slopeRating,
            coursePar: coursePar,
            holeScores: holeScores,
            totalScore: document.data["totalScore"] as? Int ?? 0,
            totalPar: document.data["totalPar"] as? Int ?? coursePar,
            scoreRelativeToPar: document.data["scoreRelativeToPar"] as? Int ?? 0,
            grossScore: document.data["grossScore"] as? Int ?? 0,
            netScore: document.data["netScore"] as? Int,
            adjustedGrossScore: document.data["adjustedGrossScore"] as? Int,
            statistics: statistics,
            weather: nil, // Would parse if available
            courseConditions: nil, // Would parse if available
            isOfficial: document.data["isOfficial"] as? Bool ?? true,
            isCompetitive: document.data["isCompetitive"] as? Bool ?? false,
            playingPartners: document.data["playingPartners"] as? [String] ?? [],
            attestedBy: document.data["attestedBy"] as? String,
            notes: document.data["notes"] as? String,
            isVerified: document.data["isVerified"] as? Bool ?? false,
            verificationMethod: verificationMethod,
            gpsData: trackingPoints.isEmpty ? nil : trackingPoints,
            createdAt: parseDate(document.data["createdAt"]) ?? Date(),
            updatedAt: parseDate(document.data["updatedAt"]) ?? Date(),
            submittedAt: parseDate(document.data["submittedAt"])
        )
    }
    
    func encodeHandicapEntryToDocumentData(_ entry: HandicapEntry) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        return [
            "userId": entry.userId,
            "handicapIndex": entry.handicapIndex,
            "calculationDate": entry.calculationDate.ISO8601String(),
            "roundsUsed": entry.roundsUsed,
            "scoringRecords": try encoder.encode(entry.scoringRecords).base64EncodedString()
        ]
    }
    
    func parseHandicapEntryFromDocument(_ document: Document) throws -> HandicapEntry {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let userId = document.data["userId"] as? String,
              let handicapIndex = document.data["handicapIndex"] as? Double,
              let calculationDateString = document.data["calculationDate"] as? String,
              let calculationDate = ISO8601DateFormatter().date(from: calculationDateString),
              let roundsUsed = document.data["roundsUsed"] as? Int else {
            throw ScorecardError.parsingError
        }
        
        let scoringRecordsData = Data(base64Encoded: document.data["scoringRecords"] as? String ?? "") ?? Data()
        let scoringRecords = (try? decoder.decode([HandicapEntry.ScoringRecord].self, from: scoringRecordsData)) ?? []
        
        return HandicapEntry(
            id: document.id,
            userId: userId,
            handicapIndex: handicapIndex,
            calculationDate: calculationDate,
            roundsUsed: roundsUsed,
            scoringRecords: scoringRecords
        )
    }
    
    func encodeShotToDocumentData(_ shot: Shot, scorecardId: String, holeNumber: Int) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        return [
            "scorecardId": scorecardId,
            "holeNumber": holeNumber,
            "shotNumber": shot.shotNumber,
            "club": shot.club?.rawValue ?? NSNull(),
            "distance": shot.distance ?? NSNull(),
            "accuracy": shot.accuracy?.rawValue ?? NSNull(),
            "lie": shot.lie?.rawValue ?? NSNull(),
            "result": shot.result?.rawValue ?? NSNull(),
            "gpsLocation": shot.gpsLocation != nil ? try encoder.encode(shot.gpsLocation!).base64EncodedString() : NSNull(),
            "timestamp": Date().ISO8601String()
        ]
    }
    
    func parseDate(_ value: Any?) -> Date? {
        guard let dateString = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: dateString)
    }
}

// MARK: - Mock Scorecard Service

class MockScorecardService: ScorecardServiceProtocol, ObservableObject {
    @Published var currentScorecard: Scorecard?
    @Published var isRoundInProgress: Bool = false
    
    private var mockScorecards: [String: Scorecard] = [:]
    private var mockHandicapIndex: Double = 12.5
    
    func startNewRound(courseId: String, teeType: TeeType) async throws -> Scorecard {
        let scorecard = createMockScorecard(courseId: courseId, teeType: teeType)
        currentScorecard = scorecard
        isRoundInProgress = true
        mockScorecards[scorecard.id] = scorecard
        return scorecard
    }
    
    func updateHoleScore(_ holeScore: HoleScore, for scorecardId: String) async throws {
        guard var scorecard = mockScorecards[scorecardId] else { return }
        
        if let index = scorecard.holeScores.firstIndex(where: { $0.holeNumber == holeScore.holeNumber }) {
            scorecard.holeScores[index] = holeScore
        }
        
        mockScorecards[scorecardId] = scorecard
        if currentScorecard?.id == scorecardId {
            currentScorecard = scorecard
        }
    }
    
    func completeRound(_ scorecardId: String) async throws -> Scorecard {
        guard var scorecard = mockScorecards[scorecardId] else {
            throw ScorecardError.loadFailed("Scorecard not found")
        }
        
        scorecard.submittedAt = Date()
        scorecard.isVerified = true
        mockScorecards[scorecardId] = scorecard
        
        if currentScorecard?.id == scorecardId {
            currentScorecard = nil
            isRoundInProgress = false
        }
        
        return scorecard
    }
    
    func saveScorecard(_ scorecard: Scorecard) async throws {
        mockScorecards[scorecard.id] = scorecard
    }
    
    func deleteScorecard(_ scorecardId: String) async throws {
        mockScorecards.removeValue(forKey: scorecardId)
        if currentScorecard?.id == scorecardId {
            currentScorecard = nil
            isRoundInProgress = false
        }
    }
    
    func getScorecard(id: String) async throws -> Scorecard {
        guard let scorecard = mockScorecards[id] else {
            throw ScorecardError.loadFailed("Scorecard not found")
        }
        return scorecard
    }
    
    func getUserScorecards(userId: String, limit: Int) async throws -> [Scorecard] {
        return Array(mockScorecards.values.prefix(limit))
    }
    
    func getRecentRounds(userId: String, days: Int) async throws -> [Scorecard] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return mockScorecards.values.filter { $0.playedDate >= cutoffDate }
    }
    
    func calculateHandicapIndex(for userId: String) async throws -> Double {
        return mockHandicapIndex
    }
    
    func calculateCourseHandicap(handicapIndex: Double, course: GolfCourse, teeType: TeeType) -> Int {
        return Int(round((handicapIndex * 113.0) / 113.0)) // Simplified
    }
    
    func calculatePlayingHandicap(courseHandicap: Int, course: GolfCourse) -> Int {
        return courseHandicap
    }
    
    func calculateNetDoubleBogey(scorecard: Scorecard, handicapIndex: Double) -> Int {
        return scorecard.totalScore // Simplified
    }
    
    func calculateRoundStatistics(for scorecard: Scorecard) -> RoundStatistics {
        return RoundStatistics(
            pars: 10, birdies: 3, eagles: 0, bogeys: 4, doubleBogeys: 1, otherScores: 0,
            fairwaysHit: 8, totalFairways: 14, greensInRegulation: 9, totalGreens: 18,
            totalPutts: 32, averagePuttsPerHole: 1.8, totalPenalties: 1,
            waterHazards: 0, sandSaves: 2, upAndDowns: 3,
            longestDrive: 285, averageDriveDistance: 265, drivingAccuracy: 60.0
        )
    }
    
    func getUserStatistics(userId: String, timeframe: StatisticsTimeframe) async throws -> UserGolfStatistics {
        return UserGolfStatistics(
            userId: userId,
            timeframe: timeframe,
            totalRounds: 15,
            averageScore: 85.2,
            bestScore: 78,
            worstScore: 95,
            currentHandicap: mockHandicapIndex,
            averageFairwayHitPercentage: 62.5,
            averageGIRPercentage: 55.0,
            averagePuttsPerRound: 32.1,
            averagePenaltiesPerRound: 1.2,
            eagles: 2,
            birdies: 35,
            pars: 145,
            bogeys: 85,
            doubleBogeys: 25,
            otherScores: 8,
            scoreTrend: .improving,
            handicapTrend: .improving,
            favoriteCourse: "mock_course_1",
            bestCoursePerformance: ("mock_course_2", 82.5)
        )
    }
    
    func getHandicapTrend(userId: String, months: Int) async throws -> [HandicapEntry] {
        return []
    }
    
    func startShotTracking(scorecardId: String, holeNumber: Int) {
        // Mock implementation
    }
    
    func recordShot(scorecardId: String, holeNumber: Int, shot: Shot) async throws {
        // Mock implementation
    }
    
    func stopShotTracking() {
        // Mock implementation
    }
    
    func getShotTrackingData(scorecardId: String, holeNumber: Int) -> [Shot] {
        return []
    }
    
    private func createMockScorecard(courseId: String, teeType: TeeType) -> Scorecard {
        let holeScores = (1...18).map { holeNumber in
            HoleScore(
                id: UUID().uuidString,
                holeNumber: holeNumber,
                par: holeNumber <= 6 ? 4 : (holeNumber <= 12 ? 3 : (holeNumber <= 16 ? 5 : 4)),
                yardage: 350,
                handicapIndex: holeNumber,
                score: "",
                adjustedScore: nil,
                netScore: nil,
                stablefordPoints: nil,
                shots: nil,
                putts: nil,
                penalties: 0,
                fairwayHit: nil,
                greenInRegulation: nil,
                pinPosition: nil,
                teeCondition: nil
            )
        }
        
        return Scorecard(
            id: UUID().uuidString,
            userId: "mock_user",
            courseId: courseId,
            courseName: "Mock Golf Course",
            teeTimeId: nil,
            playedDate: Date(),
            teeType: teeType,
            numberOfHoles: 18,
            courseRating: 72.0,
            slopeRating: 113,
            coursePar: 72,
            holeScores: holeScores,
            totalScore: 0,
            totalPar: 72,
            scoreRelativeToPar: 0,
            grossScore: 0,
            netScore: nil,
            adjustedGrossScore: nil,
            statistics: RoundStatistics(pars: 0, birdies: 0, eagles: 0, bogeys: 0, doubleBogeys: 0, otherScores: 0, fairwaysHit: 0, totalFairways: 14, greensInRegulation: 0, totalGreens: 18, totalPutts: nil, averagePuttsPerHole: nil, totalPenalties: 0, waterHazards: 0, sandSaves: 0, upAndDowns: 0, longestDrive: nil, averageDriveDistance: nil, drivingAccuracy: nil),
            weather: nil,
            courseConditions: nil,
            isOfficial: true,
            isCompetitive: false,
            playingPartners: [],
            attestedBy: nil,
            notes: nil,
            isVerified: false,
            verificationMethod: .selfReported,
            gpsData: nil,
            createdAt: Date(),
            updatedAt: Date(),
            submittedAt: nil
        )
    }
}

// MARK: - Scorecard Error Types

enum ScorecardError: Error, LocalizedError {
    case serviceNotAvailable
    case parsingError
    case saveFailed(String)
    case loadFailed(String)
    case deleteFailed(String)
    case incompleteRound
    case insufficientData
    case shotTrackingNotActive
    case shotTrackingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .serviceNotAvailable:
            return "Required service not available"
        case .parsingError:
            return "Failed to parse scorecard data"
        case .saveFailed(let message):
            return "Failed to save scorecard: \(message)"
        case .loadFailed(let message):
            return "Failed to load scorecard: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete scorecard: \(message)"
        case .incompleteRound:
            return "Round must be complete before submission"
        case .insufficientData:
            return "Insufficient data for calculation"
        case .shotTrackingNotActive:
            return "Shot tracking is not active"
        case .shotTrackingFailed(let message):
            return "Shot tracking failed: \(message)"
        }
    }
}

extension Date {
    func ISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}