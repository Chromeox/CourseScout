import Foundation

// MARK: - Scorecard Model

struct Scorecard: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let courseId: String
    let courseName: String
    let teeTimeId: String?
    
    // Round information
    let playedDate: Date
    let teeType: TeeType
    let numberOfHoles: Int          // 9 or 18
    let courseRating: Double
    let slopeRating: Int
    let coursePar: Int
    
    // Hole-by-hole scores
    let holeScores: [HoleScore]
    
    // Round totals and statistics
    let totalScore: Int
    let totalPar: Int
    let scoreRelativeToPar: Int     // +/- par
    let grossScore: Int
    let netScore: Int?              // With handicap applied
    let adjustedGrossScore: Int?    // For handicap calculation
    
    // Performance statistics
    let statistics: RoundStatistics
    
    // Playing conditions
    let weather: WeatherConditions?
    let courseConditions: CourseConditions?
    
    // Round metadata
    let isOfficial: Bool            // Counts toward handicap
    let isCompetitive: Bool         // Tournament or competitive round
    let playingPartners: [String]   // User IDs of playing partners
    let attestedBy: String?         // Who verified the scorecard
    let notes: String?
    
    // Verification and integrity
    let isVerified: Bool
    let verificationMethod: VerificationMethod
    let gpsData: [GPSTrackingPoint]?
    
    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    let submittedAt: Date?
    
    // Computed properties
    var formattedScore: String {
        let relative = scoreRelativeToPar
        if relative == 0 {
            return "E (\(totalScore))"
        } else if relative > 0 {
            return "+\(relative) (\(totalScore))"
        } else {
            return "\(relative) (\(totalScore))"
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: playedDate)
    }
    
    var averageScore: Double {
        Double(totalScore) / Double(numberOfHoles)
    }
    
    var isComplete: Bool {
        holeScores.count == numberOfHoles && holeScores.allSatisfy { !$0.score.isEmpty }
    }
    
    var handicapDifferential: Double? {
        guard let adjusted = adjustedGrossScore else { return nil }
        return Double(adjusted - Int(courseRating)) * 113.0 / Double(slopeRating)
    }
    
    var qualityOfRound: RoundQuality {
        let percentage = Double(totalScore - coursePar) / Double(coursePar)
        
        if percentage <= -0.1 { return .excellent }
        else if percentage <= 0 { return .good }
        else if percentage <= 0.15 { return .fair }
        else if percentage <= 0.3 { return .challenging }
        else { return .difficult }
    }
}

// MARK: - Hole Score

struct HoleScore: Identifiable, Codable, Equatable {
    let id: String
    let holeNumber: Int
    let par: Int
    let yardage: Int
    let handicapIndex: Int          // Hole difficulty ranking (1-18)
    
    // Scoring
    let score: String               // "4", "X" for no score, etc.
    let adjustedScore: Int?         // ESC adjusted score
    let netScore: Int?              // With handicap strokes
    let stablefordPoints: Int?      // Points in Stableford format
    
    // Shot tracking (optional advanced feature)
    let shots: [Shot]?
    let putts: Int?
    let penalties: Int
    let fairwayHit: Bool?           // For par 4/5 holes
    let greenInRegulation: Bool?
    
    // Hole conditions
    let pinPosition: PinPosition?
    let teeCondition: TeeCondition?
    
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
        case 2: return "Double Bogey"
        case 3: return "Triple Bogey"
        default: return relative > 0 ? "+\(relative)" : "\(relative)"
        }
    }
    
    var isGoodScore: Bool {
        guard let relative = scoreRelativeToPar else { return false }
        return relative <= 0
    }
}

// MARK: - Shot Tracking

struct Shot: Identifiable, Codable, Equatable {
    let id: String
    let shotNumber: Int
    let club: GolfClub?
    let distance: Int?              // Yards
    let accuracy: ShotAccuracy?
    let lie: LieCondition?
    let result: ShotResult?
    let gpsLocation: GPSTrackingPoint?
    
    enum GolfClub: String, CaseIterable, Codable {
        case driver = "driver"
        case fairwayWood = "fairway_wood"
        case hybrid = "hybrid"
        case longIron = "long_iron"      // 3-4 iron
        case midIron = "mid_iron"        // 5-7 iron
        case shortIron = "short_iron"    // 8-9 iron
        case wedge = "wedge"             // PW, SW, LW
        case putter = "putter"
        
        var displayName: String {
            switch self {
            case .driver: return "Driver"
            case .fairwayWood: return "Fairway Wood"
            case .hybrid: return "Hybrid"
            case .longIron: return "Long Iron"
            case .midIron: return "Mid Iron"
            case .shortIron: return "Short Iron"
            case .wedge: return "Wedge"
            case .putter: return "Putter"
            }
        }
    }
    
    enum ShotAccuracy: String, CaseIterable, Codable {
        case straight = "straight"
        case slightLeft = "slight_left"
        case slightRight = "slight_right"
        case left = "left"
        case right = "right"
        case wayLeft = "way_left"
        case wayRight = "way_right"
        
        var displayName: String {
            switch self {
            case .straight: return "Straight"
            case .slightLeft: return "Slight Left"
            case .slightRight: return "Slight Right"
            case .left: return "Left"
            case .right: return "Right"
            case .wayLeft: return "Way Left"
            case .wayRight: return "Way Right"
            }
        }
    }
    
    enum LieCondition: String, CaseIterable, Codable {
        case tee = "tee"
        case fairway = "fairway"
        case rough = "rough"
        case bunker = "bunker"
        case hazard = "hazard"
        case green = "green"
        case cart = "cart_path"
        case trees = "trees"
        
        var displayName: String {
            switch self {
            case .tee: return "Tee"
            case .fairway: return "Fairway"
            case .rough: return "Rough"
            case .bunker: return "Bunker"
            case .hazard: return "Hazard"
            case .green: return "Green"
            case .cart: return "Cart Path"
            case .trees: return "Trees"
            }
        }
    }
    
    enum ShotResult: String, CaseIterable, Codable {
        case excellent = "excellent"
        case good = "good"
        case fair = "fair"
        case poor = "poor"
        case penalty = "penalty"
        
        var displayName: String {
            rawValue.capitalized
        }
    }
}

// MARK: - Round Statistics

struct RoundStatistics: Codable, Equatable {
    // Scoring stats
    let pars: Int
    let birdies: Int
    let eagles: Int
    let bogeys: Int
    let doubleBogeys: Int
    let otherScores: Int
    
    // Performance stats
    let fairwaysHit: Int
    let totalFairways: Int
    let greensInRegulation: Int
    let totalGreens: Int
    let totalPutts: Int?
    let averagePuttsPerHole: Double?
    
    // Penalty and trouble stats
    let totalPenalties: Int
    let waterHazards: Int
    let sandSaves: Int
    let upAndDowns: Int
    
    // Distance and accuracy
    let longestDrive: Int?          // Yards
    let averageDriveDistance: Int?
    let drivingAccuracy: Double?    // Percentage
    
    // Computed properties
    var fairwayPercentage: Double {
        guard totalFairways > 0 else { return 0.0 }
        return Double(fairwaysHit) / Double(totalFairways) * 100
    }
    
    var girPercentage: Double {
        guard totalGreens > 0 else { return 0.0 }
        return Double(greensInRegulation) / Double(totalGreens) * 100
    }
    
    var scramblePercentage: Double {
        let missedGreens = totalGreens - greensInRegulation
        guard missedGreens > 0 else { return 0.0 }
        return Double(upAndDowns) / Double(missedGreens) * 100
    }
}

// MARK: - Supporting Enums

enum VerificationMethod: String, CaseIterable, Codable {
    case selfReported = "self_reported"
    case peerVerified = "peer_verified"
    case gpsTracked = "gps_tracked"
    case scorecardPhoto = "scorecard_photo"
    case tournamentOfficial = "tournament_official"
    
    var displayName: String {
        switch self {
        case .selfReported: return "Self Reported"
        case .peerVerified: return "Peer Verified"
        case .gpsTracked: return "GPS Tracked"
        case .scorecardPhoto: return "Scorecard Photo"
        case .tournamentOfficial: return "Tournament Official"
        }
    }
    
    var reliability: Int {
        switch self {
        case .selfReported: return 1
        case .peerVerified: return 2
        case .scorecardPhoto: return 3
        case .gpsTracked: return 4
        case .tournamentOfficial: return 5
        }
    }
}

enum PinPosition: String, CaseIterable, Codable {
    case front = "front"
    case middle = "middle"
    case back = "back"
    case left = "left"
    case right = "right"
    case frontLeft = "front_left"
    case frontRight = "front_right"
    case backLeft = "back_left"
    case backRight = "back_right"
    
    var displayName: String {
        switch self {
        case .front: return "Front"
        case .middle: return "Middle"
        case .back: return "Back"
        case .left: return "Left"
        case .right: return "Right"
        case .frontLeft: return "Front Left"
        case .frontRight: return "Front Right"
        case .backLeft: return "Back Left"
        case .backRight: return "Back Right"
        }
    }
}

enum TeeCondition: String, CaseIterable, Codable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case temporary = "temporary"
    
    var displayName: String {
        rawValue.capitalized
    }
}

enum RoundQuality: String, CaseIterable, Codable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case challenging = "challenging"
    case difficult = "difficult"
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "yellow"
        case .challenging: return "orange"
        case .difficult: return "red"
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "Outstanding round!"
        case .good: return "Solid performance"
        case .fair: return "Average round"
        case .challenging: return "Tough day out there"
        case .difficult: return "Keep practicing!"
        }
    }
}

// MARK: - GPS Tracking

struct GPSTrackingPoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let accuracy: Double            // Accuracy in meters
    let timestamp: Date
    let holeNumber: Int?
    let shotNumber: Int?
    
    var formattedAccuracy: String {
        "\(Int(accuracy))m accuracy"
    }
}

// MARK: - Scorecard Extensions

extension Scorecard {
    // Generate a summary for sharing
    var sharingSummary: String {
        """
        \(courseName) - \(formattedDate)
        Score: \(formattedScore)
        \(statistics.birdies) birdies, \(statistics.pars) pars
        Fairways: \(statistics.fairwaysHit)/\(statistics.totalFairways) (\(Int(statistics.fairwayPercentage))%)
        GIR: \(statistics.greensInRegulation)/\(statistics.totalGreens) (\(Int(statistics.girPercentage))%)
        """
    }
    
    // Check if round qualifies for handicap
    var qualifiesForHandicap: Bool {
        return isOfficial && 
               isComplete && 
               numberOfHoles >= 9 &&
               isVerified &&
               verificationMethod.reliability >= 2
    }
    
    // Calculate net double bogey for handicap
    func netDoubleBogeyScore(handicapIndex: Double) -> Int {
        let coursePar = holeScores.reduce(0) { $0 + $1.par }
        let courseHandicap = Int((handicapIndex * Double(slopeRating)) / 113.0)
        
        var adjustedScore = 0
        
        for hole in holeScores {
            let holeHandicap = courseHandicap / numberOfHoles + 
                              (courseHandicap % numberOfHoles >= hole.handicapIndex ? 1 : 0)
            let maxScore = hole.par + 2 + holeHandicap
            
            if let score = hole.scoreInt {
                adjustedScore += min(score, maxScore)
            } else {
                adjustedScore += maxScore // Assume max if no score recorded
            }
        }
        
        return adjustedScore
    }
}