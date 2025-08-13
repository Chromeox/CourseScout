import Foundation

// MARK: - Watch-Optimized Scorecard Model

struct SharedScorecard: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let userId: String
    let courseId: String
    let courseName: String
    
    // Essential round information
    let playedDate: Date
    let numberOfHoles: Int
    let coursePar: Int
    let teeType: SharedTeeType
    
    // Hole-by-hole scores (simplified)
    let holeScores: [SharedHoleScore]
    
    // Round totals
    let totalScore: Int
    let scoreRelativeToPar: Int
    
    // Essential statistics
    let statistics: SharedRoundStatistics
    
    // Round status
    let isComplete: Bool
    let currentHole: Int // For active rounds
    
    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    
    // Multi-tenant context
    let tenantId: String?
    let businessType: SharedBusinessType
    let databaseNamespace: String
    
    // Computed properties
    var formattedScore: String {
        let relative = scoreRelativeToPar
        if relative == 0 {
            return "E"
        } else if relative > 0 {
            return "+\(relative)"
        } else {
            return "\(relative)"
        }
    }
    
    var shortFormattedScore: String {
        "\(formattedScore) (\(totalScore))"
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: playedDate)
    }
    
    var averageScore: Double {
        Double(totalScore) / Double(numberOfHoles)
    }
    
    var holesRemaining: Int {
        max(0, numberOfHoles - currentHole)
    }
    
    var progressPercentage: Double {
        guard numberOfHoles > 0 else { return 0.0 }
        return Double(currentHole) / Double(numberOfHoles)
    }
    
    var frontNineScore: Int? {
        guard numberOfHoles >= 9 else { return nil }
        return holeScores.prefix(9).compactMap { Int($0.score) }.reduce(0, +)
    }
    
    var backNineScore: Int? {
        guard numberOfHoles == 18, holeScores.count >= 18 else { return nil }
        return holeScores.suffix(9).compactMap { Int($0.score) }.reduce(0, +)
    }
    
    // Watch Connectivity optimized data
    var essentialData: [String: Any] {
        [
            "id": id,
            "courseId": courseId,
            "courseName": courseName,
            "totalScore": totalScore,
            "scoreRelativeToPar": scoreRelativeToPar,
            "currentHole": currentHole,
            "isComplete": isComplete,
            "holes": numberOfHoles,
            "par": coursePar,
            "birdies": statistics.birdies,
            "pars": statistics.pars,
            "bogeys": statistics.bogeys,
            "tenantId": tenantId as Any,
            "businessType": businessType.rawValue,
            "databaseNamespace": databaseNamespace
        ]
    }
}

// MARK: - Watch-Optimized Hole Score

struct SharedHoleScore: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let holeNumber: Int
    let par: Int
    let yardage: Int
    
    // Scoring (simplified for Watch)
    let score: String // "4", "X" for no score, etc.
    let putts: Int?
    let penalties: Int
    
    // Performance indicators
    let fairwayHit: Bool?
    let greenInRegulation: Bool?
    
    var scoreInt: Int? {
        Int(score)
    }
    
    var scoreRelativeToPar: Int? {
        guard let scoreValue = scoreInt else { return nil }
        return scoreValue - par
    }
    
    var scoreDescription: String {
        guard let relative = scoreRelativeToPar else { return score }
        
        switch relative {
        case -3: return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double"
        case 3: return "Triple"
        default: return relative > 0 ? "+\(relative)" : "\(relative)"
        }
    }
    
    var shortScoreDescription: String {
        guard let relative = scoreRelativeToPar else { return score }
        
        switch relative {
        case -3: return "🦅"
        case -2: return "🦅"
        case -1: return "🐦"
        case 0: return "➖"
        case 1: return "🟡"
        case 2: return "🔶"
        default: return "🔴"
        }
    }
    
    var isGoodScore: Bool {
        guard let relative = scoreRelativeToPar else { return false }
        return relative <= 0
    }
    
    var hasScore: Bool {
        return score != "X" && scoreInt != nil
    }
}

// MARK: - Watch-Optimized Round Statistics

struct SharedRoundStatistics: Codable, Equatable, Hashable {
    // Essential scoring stats
    let pars: Int
    let birdies: Int
    let eagles: Int
    let bogeys: Int
    let doubleBogeys: Int
    let otherScores: Int
    
    // Performance stats (simplified)
    let fairwaysHit: Int
    let totalFairways: Int
    let greensInRegulation: Int
    let totalGreens: Int
    let totalPutts: Int?
    let totalPenalties: Int
    
    // Computed properties
    var fairwayPercentage: Int {
        guard totalFairways > 0 else { return 0 }
        return Int((Double(fairwaysHit) / Double(totalFairways)) * 100)
    }
    
    var girPercentage: Int {
        guard totalGreens > 0 else { return 0 }
        return Int((Double(greensInRegulation) / Double(totalGreens)) * 100)
    }
    
    var averagePutts: Double? {
        guard let putts = totalPutts, totalGreens > 0 else { return nil }
        return Double(putts) / Double(totalGreens)
    }
    
    var goodScores: Int {
        return eagles + birdies + pars
    }
    
    var troubleScores: Int {
        return bogeys + doubleBogeys + otherScores
    }
    
    // Watch display summary
    var performanceSummary: String {
        var summary: [String] = []
        
        if birdies > 0 { summary.append("\(birdies) 🐦") }
        if eagles > 0 { summary.append("\(eagles) 🦅") }
        if totalPenalties > 0 { summary.append("\(totalPenalties) ⚠️") }
        
        return summary.isEmpty ? "Even par golf" : summary.joined(separator: " ")
    }
}

// MARK: - Shared Tee Type

enum SharedTeeType: String, CaseIterable, Codable, Hashable {
    case championship = "championship"
    case back = "back"
    case regular = "regular"
    case forward = "forward"
    case senior = "senior"
    case junior = "junior"
    
    var displayName: String {
        switch self {
        case .championship: return "Championship"
        case .back: return "Back"
        case .regular: return "Regular"
        case .forward: return "Forward"
        case .senior: return "Senior"
        case .junior: return "Junior"
        }
    }
    
    var shortName: String {
        switch self {
        case .championship: return "Champ"
        case .back: return "Back"
        case .regular: return "Regular"
        case .forward: return "Forward"
        case .senior: return "Senior"
        case .junior: return "Junior"
        }
    }
    
    var color: String {
        switch self {
        case .championship: return "black"
        case .back: return "blue"
        case .regular: return "white"
        case .forward: return "red"
        case .senior: return "silver"
        case .junior: return "green"
        }
    }
}

// MARK: - Active Round Model for Watch

struct ActiveGolfRound: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let courseId: String
    let courseName: String
    let startTime: Date
    
    // Current state
    var currentHole: Int
    var scores: [Int: String] // Hole number -> score
    var totalScore: Int
    var totalPar: Int
    
    // Course information
    let holes: [SharedHoleInfo]
    let teeType: SharedTeeType
    
    // Multi-tenant context
    let tenantId: String?
    let businessType: SharedBusinessType
    let databaseNamespace: String
    
    var scoreRelativeToPar: Int {
        totalScore - totalPar
    }
    
    var formattedScore: String {
        let relative = scoreRelativeToPar
        if relative == 0 {
            return "E"
        } else if relative > 0 {
            return "+\(relative)"
        } else {
            return "\(relative)"
        }
    }
    
    var currentHoleInfo: SharedHoleInfo? {
        holes.first { $0.holeNumber == currentHole }
    }
    
    var isComplete: Bool {
        currentHole > holes.count
    }
    
    var holesRemaining: Int {
        max(0, holes.count - currentHole + 1)
    }
    
    mutating func recordScore(_ score: String, forHole hole: Int) {
        scores[hole] = score
        
        // Recalculate totals
        totalScore = 0
        totalPar = 0
        
        for (holeNum, scoreStr) in scores {
            if let holeInfo = holes.first(where: { $0.holeNumber == holeNum }),
               let scoreValue = Int(scoreStr) {
                totalScore += scoreValue
                totalPar += holeInfo.par
            }
        }
    }
    
    mutating func advanceToNextHole() {
        currentHole = min(currentHole + 1, holes.count + 1)
    }
    
    func scoreForHole(_ holeNumber: Int) -> String? {
        return scores[holeNumber]
    }
    
    func hasScoreForHole(_ holeNumber: Int) -> Bool {
        return scores[holeNumber] != nil && scores[holeNumber] != "X"
    }
}

// MARK: - Scorecard Extension for Full Model Conversion

extension SharedScorecard {
    // Convert from full Scorecard model (for Watch Connectivity)
    init(from fullScorecard: Scorecard, tenantId: String? = nil, businessType: SharedBusinessType = .golfCourse) {
        self.id = fullScorecard.id
        self.userId = fullScorecard.userId
        self.courseId = fullScorecard.courseId
        self.courseName = fullScorecard.courseName
        self.playedDate = fullScorecard.playedDate
        self.numberOfHoles = fullScorecard.numberOfHoles
        self.coursePar = fullScorecard.coursePar
        self.teeType = SharedTeeType(rawValue: fullScorecard.teeType.rawValue) ?? .regular
        
        // Convert hole scores
        self.holeScores = fullScorecard.holeScores.map { holeScore in
            SharedHoleScore(
                id: holeScore.id,
                holeNumber: holeScore.holeNumber,
                par: holeScore.par,
                yardage: holeScore.yardage,
                score: holeScore.score,
                putts: holeScore.putts,
                penalties: holeScore.penalties,
                fairwayHit: holeScore.fairwayHit,
                greenInRegulation: holeScore.greenInRegulation
            )
        }
        
        self.totalScore = fullScorecard.totalScore
        self.scoreRelativeToPar = fullScorecard.scoreRelativeToPar
        
        // Convert statistics
        self.statistics = SharedRoundStatistics(
            pars: fullScorecard.statistics.pars,
            birdies: fullScorecard.statistics.birdies,
            eagles: fullScorecard.statistics.eagles,
            bogeys: fullScorecard.statistics.bogeys,
            doubleBogeys: fullScorecard.statistics.doubleBogeys,
            otherScores: fullScorecard.statistics.otherScores,
            fairwaysHit: fullScorecard.statistics.fairwaysHit,
            totalFairways: fullScorecard.statistics.totalFairways,
            greensInRegulation: fullScorecard.statistics.greensInRegulation,
            totalGreens: fullScorecard.statistics.totalGreens,
            totalPutts: fullScorecard.statistics.totalPutts,
            totalPenalties: fullScorecard.statistics.totalPenalties
        )
        
        self.isComplete = fullScorecard.isComplete
        self.currentHole = fullScorecard.holeScores.count + 1 // Next hole to play
        self.createdAt = fullScorecard.createdAt
        self.updatedAt = fullScorecard.updatedAt
        
        // Multi-tenant properties
        self.tenantId = tenantId
        self.businessType = businessType
        self.databaseNamespace = tenantId != nil ? "tenant_\(tenantId!)" : "default"
    }
    
    // Multi-tenant initializer
    init(id: String, userId: String, courseId: String, courseName: String, playedDate: Date, numberOfHoles: Int, coursePar: Int, teeType: SharedTeeType, holeScores: [SharedHoleScore], totalScore: Int, scoreRelativeToPar: Int, statistics: SharedRoundStatistics, isComplete: Bool, currentHole: Int, createdAt: Date, updatedAt: Date, tenantId: String? = nil, businessType: SharedBusinessType = .golfCourse) {
        self.id = id
        self.userId = userId
        self.courseId = courseId
        self.courseName = courseName
        self.playedDate = playedDate
        self.numberOfHoles = numberOfHoles
        self.coursePar = coursePar
        self.teeType = teeType
        self.holeScores = holeScores
        self.totalScore = totalScore
        self.scoreRelativeToPar = scoreRelativeToPar
        self.statistics = statistics
        self.isComplete = isComplete
        self.currentHole = currentHole
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tenantId = tenantId
        self.businessType = businessType
        self.databaseNamespace = tenantId != nil ? "tenant_\(tenantId!)" : "default"
    }
    
    // Create active round for Watch
    func toActiveRound(with holes: [SharedHoleInfo]) -> ActiveGolfRound {
        var scores: [Int: String] = [:]
        var totalCalculatedScore = 0
        var totalCalculatedPar = 0
        
        for holeScore in holeScores {
            scores[holeScore.holeNumber] = holeScore.score
            if let scoreValue = holeScore.scoreInt {
                totalCalculatedScore += scoreValue
                totalCalculatedPar += holeScore.par
            }
        }
        
        return ActiveGolfRound(
            id: id,
            courseId: courseId,
            courseName: courseName,
            startTime: createdAt,
            currentHole: currentHole,
            scores: scores,
            totalScore: totalCalculatedScore,
            totalPar: totalCalculatedPar,
            holes: holes,
            teeType: teeType,
            tenantId: tenantId,
            businessType: businessType,
            databaseNamespace: databaseNamespace
        )
    }
}