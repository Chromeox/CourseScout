import Foundation
import HealthKit
import CoreLocation

// MARK: - Golf Health Metrics

struct GolfHealthMetrics: Codable, Equatable {
    let id: String
    let roundId: String
    let playerId: String
    let courseId: String
    let startDate: Date
    let endDate: Date
    
    // Heart rate data
    let heartRateData: HeartRateMetrics
    
    // Activity data
    let activityData: GolfActivityMetrics
    
    // Environmental data
    let environmentalData: EnvironmentalMetrics
    
    // Performance correlation
    let performanceCorrelation: PerformanceHealthCorrelation?
    
    // Computed properties
    var roundDuration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    var formattedDuration: String {
        let hours = Int(roundDuration) / 3600
        let minutes = (Int(roundDuration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    var averageHeartRate: Double {
        heartRateData.averageHeartRate
    }
    
    var caloriesBurned: Double {
        activityData.totalCalories
    }
    
    var totalDistance: Double {
        activityData.totalDistance
    }
}

// MARK: - Heart Rate Metrics

struct HeartRateMetrics: Codable, Equatable {
    let averageHeartRate: Double
    let maxHeartRate: Double
    let minHeartRate: Double
    let restingHeartRate: Double?
    
    // Heart rate zones
    let timeInZones: HeartRateZones
    
    // Variability
    let heartRateVariability: Double?
    
    // Recovery metrics
    let recoveryHeartRate: Double?
    let stressScore: Double?
    
    // Hole-by-hole data
    let holeHeartRates: [HoleHeartRate]
    
    var heartRateRange: Double {
        maxHeartRate - minHeartRate
    }
    
    var aerobicEfficiency: Double? {
        guard let resting = restingHeartRate else { return nil }
        return (maxHeartRate - resting) / (220 - Double(Calendar.current.component(.year, from: Date()) - 1990))
    }
}

struct HeartRateZones: Codable, Equatable {
    let zone1Duration: TimeInterval // Very light (50-60% max HR)
    let zone2Duration: TimeInterval // Light (60-70% max HR)
    let zone3Duration: TimeInterval // Moderate (70-80% max HR)
    let zone4Duration: TimeInterval // Hard (80-90% max HR)
    let zone5Duration: TimeInterval // Maximum (90-100% max HR)
    
    var totalActiveTime: TimeInterval {
        zone1Duration + zone2Duration + zone3Duration + zone4Duration + zone5Duration
    }
    
    var aerobicTime: TimeInterval {
        zone1Duration + zone2Duration + zone3Duration
    }
    
    var anaerobicTime: TimeInterval {
        zone4Duration + zone5Duration
    }
    
    func percentageInZone(_ zone: Int) -> Double {
        let zoneDuration: TimeInterval
        switch zone {
        case 1: zoneDuration = zone1Duration
        case 2: zoneDuration = zone2Duration
        case 3: zoneDuration = zone3Duration
        case 4: zoneDuration = zone4Duration
        case 5: zoneDuration = zone5Duration
        default: return 0
        }
        
        return totalActiveTime > 0 ? (zoneDuration / totalActiveTime) * 100 : 0
    }
}

struct HoleHeartRate: Codable, Equatable {
    let holeNumber: Int
    let averageHeartRate: Double
    let maxHeartRate: Double
    let minHeartRate: Double
    let duration: TimeInterval
    let stress: StressLevel
    
    enum StressLevel: String, CaseIterable, Codable {
        case low = "low"
        case moderate = "moderate"
        case high = "high"
        case extreme = "extreme"
        
        var color: String {
            switch self {
            case .low: return "green"
            case .moderate: return "yellow"
            case .high: return "orange"
            case .extreme: return "red"
            }
        }
        
        var description: String {
            switch self {
            case .low: return "Relaxed"
            case .moderate: return "Focused"
            case .high: return "Pressure"
            case .extreme: return "High Stress"
            }
        }
    }
}

// MARK: - Golf Activity Metrics

struct GolfActivityMetrics: Codable, Equatable {
    // Movement data
    let totalDistance: Double // meters
    let walkingDistance: Double
    let runningDistance: Double?
    let elevationGain: Double
    let elevationLoss: Double
    
    // Energy expenditure
    let totalCalories: Double
    let activeCalories: Double
    let restingCalories: Double
    
    // Step data
    let totalSteps: Int
    let averageStepLength: Double?
    let cadence: Double? // steps per minute
    
    // Golf-specific metrics
    let swingCount: Int?
    let averageSwingSpeed: Double? // mph
    let walkingPace: Double // minutes per mile
    
    // Time breakdown
    let activeTime: TimeInterval
    let restTime: TimeInterval
    let walkingTime: TimeInterval
    
    // Recovery metrics
    let recoveryTime: TimeInterval?
    let fatigueScore: Double? // 1-10 scale
    
    var averagePace: String {
        let paceMinutes = walkingPace
        let minutes = Int(paceMinutes)
        let seconds = Int((paceMinutes - Double(minutes)) * 60)
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
    
    var caloriesPerHour: Double {
        let hours = (activeTime + restTime) / 3600
        return hours > 0 ? totalCalories / hours : 0
    }
    
    var formattedDistance: String {
        let miles = totalDistance * 0.000621371
        return String(format: "%.1f mi", miles)
    }
}

// MARK: - Environmental Metrics

struct EnvironmentalMetrics: Codable, Equatable {
    let temperature: Double // Celsius
    let humidity: Double // percentage
    let windSpeed: Double // mph
    let windDirection: Double? // degrees
    let pressure: Double? // hPa
    let uvIndex: Double?
    let airQualityIndex: Int?
    
    // Comfort metrics
    let heatIndex: Double?
    let windChill: Double?
    let comfortLevel: ComfortLevel
    
    enum ComfortLevel: String, CaseIterable, Codable {
        case ideal = "ideal"
        case comfortable = "comfortable"
        case challenging = "challenging"
        case difficult = "difficult"
        case extreme = "extreme"
        
        var color: String {
            switch self {
            case .ideal: return "green"
            case .comfortable: return "blue"
            case .challenging: return "yellow"
            case .difficult: return "orange"
            case .extreme: return "red"
            }
        }
        
        var description: String {
            switch self {
            case .ideal: return "Perfect conditions"
            case .comfortable: return "Very playable"
            case .challenging: return "Some difficulty"
            case .difficult: return "Tough conditions"
            case .extreme: return "Extreme weather"
            }
        }
    }
    
    var temperatureFahrenheit: Double {
        (temperature * 9/5) + 32
    }
    
    var formattedTemperature: String {
        String(format: "%.0f°F", temperatureFahrenheit)
    }
    
    var formattedWindSpeed: String {
        String(format: "%.0f mph", windSpeed)
    }
}

// MARK: - Performance Health Correlation

struct PerformanceHealthCorrelation: Codable, Equatable {
    // Score correlations
    let heartRateScoreCorrelation: Double // -1 to 1
    let fatigueScoreCorrelation: Double
    let stressScoreCorrelation: Double
    
    // Pattern analysis
    let performancePatterns: [PerformancePattern]
    let recoveryNeeds: RecoveryRecommendations
    
    // Insights
    let insights: [HealthInsight]
    let warnings: [HealthWarning]
    
    struct PerformancePattern: Codable, Equatable {
        let pattern: PatternType
        let confidence: Double
        let description: String
        let recommendation: String
        
        enum PatternType: String, CaseIterable, Codable {
            case earlyFatigue = "early_fatigue"
            case stressPutting = "stress_putting"
            case heartRateSpikes = "heart_rate_spikes"
            case consistentPace = "consistent_pace"
            case goodRecovery = "good_recovery"
            case overexertion = "overexertion"
        }
    }
    
    struct RecoveryRecommendations: Codable, Equatable {
        let hydrationNeeds: HydrationLevel
        let restRecommendation: TimeInterval
        let nutritionTiming: NutritionTiming
        let nextRoundReadiness: ReadinessLevel
        
        enum HydrationLevel: String, CaseIterable, Codable {
            case low = "low"
            case moderate = "moderate"
            case high = "high"
            case critical = "critical"
        }
        
        enum NutritionTiming: String, CaseIterable, Codable {
            case immediate = "immediate"
            case within1Hour = "within_1_hour"
            case within2Hours = "within_2_hours"
            case notUrgent = "not_urgent"
        }
        
        enum ReadinessLevel: String, CaseIterable, Codable {
            case excellent = "excellent"
            case good = "good"
            case fair = "fair"
            case poor = "poor"
            case notReady = "not_ready"
            
            var color: String {
                switch self {
                case .excellent: return "green"
                case .good: return "blue"
                case .fair: return "yellow"
                case .poor: return "orange"
                case .notReady: return "red"
                }
            }
        }
    }
}

// MARK: - Health Insights and Warnings

struct HealthInsight: Identifiable, Codable, Equatable {
    let id: String
    let type: InsightType
    let title: String
    let description: String
    let actionable: Bool
    let priority: Priority
    let category: InsightCategory
    
    enum InsightType: String, CaseIterable, Codable {
        case performance = "performance"
        case fitness = "fitness"
        case recovery = "recovery"
        case nutrition = "nutrition"
        case hydration = "hydration"
        case technique = "technique"
    }
    
    enum Priority: String, CaseIterable, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }
    
    enum InsightCategory: String, CaseIterable, Codable {
        case positive = "positive"
        case neutral = "neutral"
        case caution = "caution"
        case improvement = "improvement"
    }
}

struct HealthWarning: Identifiable, Codable, Equatable {
    let id: String
    let type: WarningType
    let severity: Severity
    let title: String
    let description: String
    let recommendation: String
    let timeframe: Timeframe
    
    enum WarningType: String, CaseIterable, Codable {
        case overexertion = "overexertion"
        case dehydration = "dehydration"
        case heatStress = "heat_stress"
        case cardiacStrain = "cardiac_strain"
        case fatigue = "fatigue"
        case injury = "injury"
    }
    
    enum Severity: String, CaseIterable, Codable {
        case info = "info"
        case caution = "caution"
        case warning = "warning"
        case critical = "critical"
        case emergency = "emergency"
        
        var color: String {
            switch self {
            case .info: return "blue"
            case .caution: return "yellow"
            case .warning: return "orange"
            case .critical: return "red"
            case .emergency: return "purple"
            }
        }
    }
    
    enum Timeframe: String, CaseIterable, Codable {
        case immediate = "immediate"
        case today = "today"
        case thisWeek = "this_week"
        case ongoing = "ongoing"
    }
}

// MARK: - Workout Session

struct GolfWorkoutSession: Codable, Equatable {
    let id: String
    let roundId: String
    let workoutType: WorkoutType
    let startDate: Date
    let endDate: Date
    
    // HealthKit integration
    let healthKitWorkoutId: UUID?
    let healthKitSamples: [HealthKitSample]
    
    // Golf-specific data
    let courseData: CourseWorkoutData
    let performanceMetrics: WorkoutPerformanceMetrics
    
    enum WorkoutType: String, CaseIterable, Codable {
        case golfRound = "golf_round"
        case drivingRange = "driving_range"
        case shortGame = "short_game"
        case putting = "putting"
        case golfFitness = "golf_fitness"
    }
}

struct HealthKitSample: Codable, Equatable {
    let type: SampleType
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date
    let metadata: [String: String]?
    
    enum SampleType: String, CaseIterable, Codable {
        case heartRate = "heart_rate"
        case activeCalories = "active_calories"
        case distanceWalking = "distance_walking"
        case steps = "steps"
        case elevationAscended = "elevation_ascended"
        case workoutEvent = "workout_event"
    }
}

struct CourseWorkoutData: Codable, Equatable {
    let courseName: String
    let courseRating: Double
    let slope: Double
    let yardage: Int
    let elevationChange: Double
    let weatherConditions: EnvironmentalMetrics
    let difficultyFactor: Double // 1-5 scale
}

struct WorkoutPerformanceMetrics: Codable, Equatable {
    let efficiency: Double // calories per stroke
    let endurance: Double // performance over time
    let consistency: Double // heart rate stability
    let recovery: Double // between-hole recovery
    let adaptation: Double // weather/course adaptation
    
    var overallScore: Double {
        (efficiency + endurance + consistency + recovery + adaptation) / 5
    }
    
    var grade: PerformanceGrade {
        switch overallScore {
        case 0.9...:  return .excellent
        case 0.8..<0.9: return .good
        case 0.7..<0.8: return .fair
        case 0.6..<0.7: return .poor
        default: return .needsImprovement
        }
    }
    
    enum PerformanceGrade: String, CaseIterable, Codable {
        case excellent = "A"
        case good = "B"
        case fair = "C"
        case poor = "D"
        case needsImprovement = "F"
        
        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .fair: return "yellow"
            case .poor: return "orange"
            case .needsImprovement: return "red"
            }
        }
    }
}

// MARK: - Health Goals and Targets

struct GolfHealthGoals: Codable, Equatable {
    let id: String
    let playerId: String
    let goals: [HealthGoal]
    let targetPeriod: GoalPeriod
    let createdAt: Date
    let updatedAt: Date
    
    enum GoalPeriod: String, CaseIterable, Codable {
        case daily = "daily"
        case weekly = "weekly"
        case monthly = "monthly"
        case seasonal = "seasonal"
        case yearly = "yearly"
    }
}

struct HealthGoal: Identifiable, Codable, Equatable {
    let id: String
    let type: GoalType
    let target: Double
    let current: Double
    let unit: String
    let deadline: Date?
    let priority: GoalPriority
    
    var progress: Double {
        target > 0 ? min(current / target, 1.0) : 0
    }
    
    var isCompleted: Bool {
        current >= target
    }
    
    enum GoalType: String, CaseIterable, Codable {
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case caloriesBurned = "calories_burned"
        case distanceWalked = "distance_walked"
        case stepsPerRound = "steps_per_round"
        case recoveryTime = "recovery_time"
        case stressReduction = "stress_reduction"
        
        var displayName: String {
            switch self {
            case .averageHeartRate: return "Average Heart Rate"
            case .maxHeartRate: return "Max Heart Rate"
            case .caloriesBurned: return "Calories Burned"
            case .distanceWalked: return "Distance Walked"
            case .stepsPerRound: return "Steps Per Round"
            case .recoveryTime: return "Recovery Time"
            case .stressReduction: return "Stress Reduction"
            }
        }
        
        var icon: String {
            switch self {
            case .averageHeartRate: return "heart"
            case .maxHeartRate: return "heart.fill"
            case .caloriesBurned: return "flame"
            case .distanceWalked: return "figure.walk"
            case .stepsPerRound: return "shoeprints.fill"
            case .recoveryTime: return "timer"
            case .stressReduction: return "leaf"
            }
        }
    }
    
    enum GoalPriority: String, CaseIterable, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }
}