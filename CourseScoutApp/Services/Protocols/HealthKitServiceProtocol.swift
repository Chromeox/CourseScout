import Foundation
import HealthKit
import Combine

// MARK: - HealthKit Service Protocol

protocol HealthKitServiceProtocol {
    // MARK: - Authorization
    
    /// Requests HealthKit authorization for golf-specific data types
    func requestAuthorization() async throws -> Bool
    
    /// Checks if HealthKit is available and authorized for specific types
    func isAuthorized(for types: [HKObjectType]) -> Bool
    
    /// Gets current authorization status
    func getAuthorizationStatus() -> HealthKitAuthorizationStatus
    
    // MARK: - Workout Management
    
    /// Starts a golf workout session
    func startGolfWorkout(
        type: GolfWorkoutSession.WorkoutType,
        courseId: String,
        configuration: WorkoutConfiguration?
    ) async throws -> UUID
    
    /// Ends a golf workout session
    func endGolfWorkout(workoutId: UUID, endDate: Date?) async throws -> GolfWorkoutSession
    
    /// Pauses the current workout
    func pauseWorkout(workoutId: UUID) async throws
    
    /// Resumes a paused workout
    func resumeWorkout(workoutId: UUID) async throws
    
    /// Gets active workout sessions
    func getActiveWorkouts() async throws -> [GolfWorkoutSession]
    
    /// Cancels a workout session
    func cancelWorkout(workoutId: UUID) async throws
    
    // MARK: - Real-time Data Collection
    
    /// Starts real-time heart rate monitoring
    func startHeartRateMonitoring() -> AnyPublisher<Double, Error>
    
    /// Stops heart rate monitoring
    func stopHeartRateMonitoring()
    
    /// Gets real-time heart rate data stream
    func getHeartRateStream() -> AnyPublisher<HeartRateReading, Error>
    
    /// Starts step counting for the round
    func startStepCounting() -> AnyPublisher<Int, Error>
    
    /// Gets current step count
    func getCurrentStepCount() async throws -> Int
    
    // MARK: - Health Data Queries
    
    /// Gets heart rate data for a specific time period
    func getHeartRateData(
        startDate: Date,
        endDate: Date,
        resolution: HealthDataResolution
    ) async throws -> [HeartRateReading]
    
    /// Gets activity data for a golf round
    func getActivityData(
        startDate: Date,
        endDate: Date
    ) async throws -> GolfActivityMetrics
    
    /// Gets workout summary data
    func getWorkoutSummary(workoutId: UUID) async throws -> WorkoutSummaryData
    
    /// Gets historical golf workout data
    func getGolfWorkoutHistory(
        limit: Int?,
        startDate: Date?,
        endDate: Date?
    ) async throws -> [GolfWorkoutSession]
    
    // MARK: - Health Metrics Analysis
    
    /// Analyzes health data for a golf round
    func analyzeRoundHealthData(
        startDate: Date,
        endDate: Date,
        roundData: GolfRoundData
    ) async throws -> GolfHealthMetrics
    
    /// Gets heart rate zones for a workout
    func getHeartRateZones(
        workoutId: UUID,
        userAge: Int?,
        restingHeartRate: Double?
    ) async throws -> HeartRateZones
    
    /// Calculates performance correlations
    func calculatePerformanceCorrelation(
        healthMetrics: GolfHealthMetrics,
        scoreData: GolfScoreData
    ) async throws -> PerformanceHealthCorrelation
    
    // MARK: - Environmental Integration
    
    /// Records environmental conditions with health data
    func recordEnvironmentalConditions(
        workoutId: UUID,
        conditions: EnvironmentalMetrics
    ) async throws
    
    /// Gets weather impact on performance
    func getWeatherHealthImpact(
        conditions: EnvironmentalMetrics,
        healthData: GolfHealthMetrics
    ) async throws -> WeatherHealthImpact
    
    // MARK: - Recovery and Recommendations
    
    /// Gets recovery recommendations based on workout data
    func getRecoveryRecommendations(
        workoutData: GolfWorkoutSession,
        healthHistory: [GolfHealthMetrics]
    ) async throws -> RecoveryRecommendations
    
    /// Calculates readiness score for next round
    func calculateReadinessScore(
        recentWorkouts: [GolfWorkoutSession],
        sleepData: SleepData?,
        recoveryMetrics: RecoveryMetrics?
    ) async throws -> ReadinessScore
    
    /// Gets personalized health insights
    func getHealthInsights(
        playerId: String,
        timeframe: HealthInsightTimeframe
    ) async throws -> [HealthInsight]
    
    // MARK: - Goal Tracking
    
    /// Sets health goals for golf performance
    func setHealthGoals(_ goals: GolfHealthGoals) async throws
    
    /// Gets current health goals progress
    func getHealthGoalsProgress(playerId: String) async throws -> GolfHealthGoals
    
    /// Updates goal progress
    func updateGoalProgress(goalId: String, progress: Double) async throws
    
    /// Gets goal achievement notifications
    func getGoalAchievements(playerId: String) -> AnyPublisher<GoalAchievement, Never>
    
    // MARK: - Data Export and Sharing
    
    /// Exports health data for a time period
    func exportHealthData(
        startDate: Date,
        endDate: Date,
        format: HealthDataExportFormat
    ) async throws -> Data
    
    /// Shares workout data with other apps
    func shareWorkoutData(
        workoutId: UUID,
        recipients: [String]
    ) async throws
    
    /// Syncs data with external fitness platforms
    func syncWithExternalPlatforms(platforms: [FitnessPlatform]) async throws
    
    // MARK: - Background Processing
    
    /// Enables background health data collection
    func enableBackgroundUpdates(for types: [HKObjectType]) async throws
    
    /// Disables background updates
    func disableBackgroundUpdates()
    
    /// Processes background health data updates
    func processBackgroundHealthUpdate() async throws
    
    // MARK: - Notifications and Alerts
    
    /// Sets up health-based notifications
    func setupHealthNotifications(settings: HealthNotificationSettings) async throws
    
    /// Gets active health alerts
    func getActiveHealthAlerts() async throws -> [HealthAlert]
    
    /// Dismisses health alerts
    func dismissHealthAlert(alertId: String) async throws
    
    // MARK: - Privacy and Security
    
    /// Gets data privacy settings
    func getPrivacySettings() async throws -> HealthPrivacySettings
    
    /// Updates privacy preferences
    func updatePrivacySettings(_ settings: HealthPrivacySettings) async throws
    
    /// Deletes stored health data
    func deleteHealthData(before date: Date) async throws
}

// MARK: - Supporting Types

struct HealthKitAuthorizationStatus {
    let isAvailable: Bool
    let authorizedTypes: Set<HKObjectType>
    let deniedTypes: Set<HKObjectType>
    let notDeterminedTypes: Set<HKObjectType>
    
    var isFullyAuthorized: Bool {
        deniedTypes.isEmpty && notDeterminedTypes.isEmpty
    }
    
    var authorizationLevel: AuthorizationLevel {
        if isFullyAuthorized {
            return .full
        } else if !authorizedTypes.isEmpty {
            return .partial
        } else {
            return .none
        }
    }
    
    enum AuthorizationLevel {
        case none, partial, full
    }
}

struct WorkoutConfiguration {
    let enableHeartRateMonitoring: Bool
    let enableGPSTracking: Bool
    let enableStepCounting: Bool
    let heartRateAlertThreshold: Double?
    let targetHeartRateZone: HeartRateZone?
    let enableCoaching: Bool
    let dataResolution: HealthDataResolution
    
    enum HeartRateZone: Int, CaseIterable {
        case recovery = 1
        case aerobic = 2
        case threshold = 3
        case anaerobic = 4
        case neuromuscular = 5
        
        var name: String {
            switch self {
            case .recovery: return "Recovery"
            case .aerobic: return "Aerobic"
            case .threshold: return "Threshold"
            case .anaerobic: return "Anaerobic"
            case .neuromuscular: return "Neuromuscular"
            }
        }
    }
}

enum HealthDataResolution: String, CaseIterable {
    case high = "high"          // Every sample
    case medium = "medium"      // 1-minute averages
    case low = "low"           // 5-minute averages
    case summary = "summary"    // Workout summaries only
}

struct HeartRateReading {
    let timestamp: Date
    let heartRate: Double
    let confidence: Double
    let zone: WorkoutConfiguration.HeartRateZone?
    let context: HeartRateContext?
    
    enum HeartRateContext {
        case resting
        case walking
        case swinging
        case climbing
        case stressed
        case recovering
    }
}

struct WorkoutSummaryData {
    let workoutId: UUID
    let duration: TimeInterval
    let totalCalories: Double
    let activeCalories: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let distanceCovered: Double
    let stepCount: Int
    let elevationGain: Double
    let weatherConditions: EnvironmentalMetrics?
}

struct GolfRoundData {
    let roundId: String
    let courseId: String
    let startTime: Date
    let endTime: Date
    let holes: [HoleData]
    let totalScore: Int
    let totalPutts: Int
    let fairwaysHit: Int
    let greensInRegulation: Int
}

struct HoleData {
    let holeNumber: Int
    let par: Int
    let yardage: Int
    let score: Int
    let putts: Int
    let teeTime: Date?
    let holeOutTime: Date?
    let fairwayHit: Bool?
    let greenInRegulation: Bool?
}

struct GolfScoreData {
    let totalScore: Int
    let scoreToPar: Int
    let holeScores: [Int]
    let puttsPerHole: [Int]
    let fairwayAccuracy: Double
    let greensInRegulation: Double
    let upAndDownPercentage: Double
    let sandSavePercentage: Double
}

struct WeatherHealthImpact {
    let temperatureImpact: ImpactLevel
    let humidityImpact: ImpactLevel
    let windImpact: ImpactLevel
    let overallImpact: ImpactLevel
    let recommendations: [String]
    
    enum ImpactLevel: String, CaseIterable {
        case minimal = "minimal"
        case moderate = "moderate"
        case significant = "significant"
        case severe = "severe"
        
        var color: String {
            switch self {
            case .minimal: return "green"
            case .moderate: return "yellow"
            case .significant: return "orange"
            case .severe: return "red"
            }
        }
    }
}

struct ReadinessScore {
    let score: Double // 0-100
    let factors: [ReadinessFactor]
    let recommendation: ReadinessRecommendation
    let nextRecommendedRound: Date?
    
    var level: ReadinessLevel {
        switch score {
        case 85...100: return .excellent
        case 70..<85: return .good
        case 55..<70: return .fair
        case 40..<55: return .poor
        default: return .notReady
        }
    }
}

struct ReadinessFactor {
    let type: FactorType
    let impact: Double // -50 to +50
    let description: String
    
    enum FactorType: String, CaseIterable {
        case sleep = "sleep"
        case recovery = "recovery"
        case stress = "stress"
        case energy = "energy"
        case hydration = "hydration"
        case nutrition = "nutrition"
        case previousWorkout = "previous_workout"
        case weather = "weather"
    }
}

enum ReadinessRecommendation: String, CaseIterable {
    case playCompetitive = "play_competitive"
    case playCasual = "play_casual"
    case lightPractice = "light_practice"
    case rest = "rest"
    case recover = "recover"
    
    var title: String {
        switch self {
        case .playCompetitive: return "Ready to Compete"
        case .playCasual: return "Perfect for Casual Golf"
        case .lightPractice: return "Consider Light Practice"
        case .rest: return "Take a Rest Day"
        case .recover: return "Focus on Recovery"
        }
    }
}

enum ReadinessLevel: String, CaseIterable {
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

struct SleepData {
    let duration: TimeInterval
    let quality: SleepQuality
    let stages: SleepStages?
    let restfulness: Double // 0-100
    
    enum SleepQuality: String, CaseIterable {
        case poor = "poor"
        case fair = "fair"
        case good = "good"
        case excellent = "excellent"
    }
    
    struct SleepStages {
        let deep: TimeInterval
        let rem: TimeInterval
        let light: TimeInterval
        let awake: TimeInterval
    }
}

struct RecoveryMetrics {
    let heartRateVariability: Double?
    let restingHeartRate: Double?
    let bodyBattery: Double? // 0-100
    let stressLevel: Double? // 0-100
    let recoveryTime: TimeInterval?
}

enum HealthInsightTimeframe: String, CaseIterable {
    case today = "today"
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"
}

struct GoalAchievement {
    let goalId: String
    let goalType: HealthGoal.GoalType
    let achievedAt: Date
    let actualValue: Double
    let targetValue: Double
    let celebration: CelebrationType
    
    enum CelebrationType: String, CaseIterable {
        case milestone = "milestone"
        case personalBest = "personal_best"
        case streak = "streak"
        case target = "target"
    }
}

enum HealthDataExportFormat: String, CaseIterable {
    case json = "json"
    case csv = "csv"
    case pdf = "pdf"
    case healthkit = "healthkit"
}

enum FitnessPlatform: String, CaseIterable {
    case strava = "strava"
    case myFitnessPal = "myfitnesspal"
    case garmin = "garmin"
    case fitbit = "fitbit"
    case polar = "polar"
    case appleHealth = "apple_health"
}

struct HealthNotificationSettings {
    let heartRateAlerts: Bool
    let hydrationReminders: Bool
    let recoveryNotifications: Bool
    let goalProgress: Bool
    let workoutReminders: Bool
    let customThresholds: [NotificationThreshold]
}

struct NotificationThreshold {
    let type: ThresholdType
    let value: Double
    let enabled: Bool
    
    enum ThresholdType: String, CaseIterable {
        case maxHeartRate = "max_heart_rate"
        case minHeartRate = "min_heart_rate"
        case caloriesBurned = "calories_burned"
        case stepsAchieved = "steps_achieved"
        case hydrationReminder = "hydration_reminder"
    }
}

struct HealthAlert {
    let id: String
    let type: AlertType
    let severity: HealthWarning.Severity
    let title: String
    let message: String
    let timestamp: Date
    let actionRequired: Bool
    let dismissible: Bool
    
    enum AlertType: String, CaseIterable {
        case heartRateHigh = "heart_rate_high"
        case heartRateLow = "heart_rate_low"
        case dehydration = "dehydration"
        case overexertion = "overexertion"
        case goalAchieved = "goal_achieved"
        case recoveryNeeded = "recovery_needed"
    }
}

struct HealthPrivacySettings {
    let dataSharing: DataSharingLevel
    let analyticsOptIn: Bool
    let researchParticipation: Bool
    let dataRetentionPeriod: TimeInterval
    let anonymizeData: Bool
    let thirdPartySharing: [ThirdPartyPermission]
    
    enum DataSharingLevel: String, CaseIterable {
        case none = "none"
        case aggregated = "aggregated"
        case anonymized = "anonymized"
        case full = "full"
    }
    
    struct ThirdPartyPermission {
        let platform: FitnessPlatform
        let permissions: Set<HKObjectType>
        let enabled: Bool
    }
}