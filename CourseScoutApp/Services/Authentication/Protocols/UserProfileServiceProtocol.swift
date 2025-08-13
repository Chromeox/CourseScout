import Foundation
import CoreLocation

// MARK: - User Profile Service Protocol

protocol UserProfileServiceProtocol {
    // MARK: - Profile Management
    func getUserProfile(_ userId: String) async throws -> GolfUserProfile
    func updateUserProfile(_ userId: String, profile: GolfUserProfileUpdate) async throws -> GolfUserProfile
    func createUserProfile(_ profile: GolfUserProfileCreate) async throws -> GolfUserProfile
    func deleteUserProfile(_ userId: String) async throws
    
    // MARK: - Golf-Specific Profile Data
    func updateHandicapIndex(_ userId: String, handicapIndex: Double) async throws
    func getHandicapHistory(_ userId: String, limit: Int) async throws -> [HandicapEntry]
    func updateGolfPreferences(_ userId: String, preferences: GolfPreferences) async throws
    func getGolfStatistics(_ userId: String, period: StatisticsPeriod) async throws -> GolfStatistics
    
    // MARK: - Multi-Tenant Membership
    func addTenantMembership(_ userId: String, tenantId: String, role: TenantRole) async throws -> TenantMembership
    func updateTenantMembership(_ membershipId: String, role: TenantRole, permissions: [Permission]) async throws
    func removeTenantMembership(_ userId: String, tenantId: String) async throws
    func getUserMemberships(_ userId: String) async throws -> [TenantMembership]
    func getTenantMembers(_ tenantId: String, role: TenantRole?) async throws -> [TenantMember]
    
    // MARK: - Privacy & Consent
    func updatePrivacySettings(_ userId: String, settings: PrivacySettings) async throws
    func recordConsentGiven(_ userId: String, consentType: ConsentType, version: String) async throws
    func getConsentHistory(_ userId: String) async throws -> [ConsentRecord]
    func exportUserData(_ userId: String) async throws -> UserDataExport
    func deleteUserData(_ userId: String, deletionType: DataDeletionType) async throws
    
    // MARK: - Social Features
    func addFriend(_ userId: String, friendId: String) async throws
    func removeFriend(_ userId: String, friendId: String) async throws
    func getFriends(_ userId: String, limit: Int?, offset: Int?) async throws -> [GolfFriend]
    func updateSocialVisibility(_ userId: String, visibility: SocialVisibility) async throws
    func blockUser(_ userId: String, blockedUserId: String) async throws
    func unblockUser(_ userId: String, blockedUserId: String) async throws
    
    // MARK: - Achievement System
    func getUserAchievements(_ userId: String) async throws -> [Achievement]
    func awardAchievement(_ userId: String, achievementId: String) async throws -> Achievement
    func getAchievementProgress(_ userId: String, achievementId: String) async throws -> AchievementProgress
    func getLeaderboardPosition(_ userId: String, leaderboardType: LeaderboardType) async throws -> LeaderboardPosition
    
    // MARK: - User Preferences & Settings
    func updateNotificationPreferences(_ userId: String, preferences: NotificationPreferences) async throws
    func updateGamePreferences(_ userId: String, preferences: GamePreferences) async throws
    func updateDisplayPreferences(_ userId: String, preferences: DisplayPreferences) async throws
    func getUserPreferences(_ userId: String) async throws -> UserPreferences
    
    // MARK: - Profile Validation & Verification
    func verifyGolfHandicap(_ userId: String, handicapIndex: Double, verificationData: HandicapVerification) async throws -> Bool
    func requestProfileVerification(_ userId: String, verificationType: VerificationType) async throws -> VerificationRequest
    func getVerificationStatus(_ userId: String) async throws -> VerificationStatus
    
    // MARK: - User Activity & Analytics
    func recordUserActivity(_ userId: String, activity: UserActivity) async throws
    func getUserActivitySummary(_ userId: String, period: ActivityPeriod) async throws -> ActivitySummary
    func getUserEngagementMetrics(_ userId: String) async throws -> EngagementMetrics
    
    // MARK: - Profile Search & Discovery
    func searchUsers(query: UserSearchQuery) async throws -> [GolfUserProfile]
    func getSuggestedFriends(_ userId: String, limit: Int) async throws -> [GolfUserProfile]
    func getNearbyGolfers(_ userId: String, location: CLLocation, radius: Double) async throws -> [NearbyGolfer]
}

// MARK: - Golf User Profile Models

struct GolfUserProfile {
    let id: String
    let email: String
    let username: String?
    let displayName: String
    let firstName: String?
    let lastName: String?
    let profileImageURL: URL?
    let coverImageURL: URL?
    let bio: String?
    
    // Golf-specific data
    let handicapIndex: Double?
    let handicapCertification: HandicapCertification?
    let golfPreferences: GolfPreferences
    let homeClub: GolfClub?
    let membershipType: MembershipType?
    let playingFrequency: PlayingFrequency
    
    // Personal information
    let dateOfBirth: Date?
    let location: UserLocation?
    let phoneNumber: String?
    let emergencyContact: EmergencyContact?
    
    // Platform metadata
    let createdAt: Date
    let lastActiveAt: Date
    let profileCompleteness: Double
    let verificationStatus: VerificationStatus
    let privacySettings: PrivacySettings
    let socialVisibility: SocialVisibility
    
    // Tenant memberships
    let tenantMemberships: [TenantMembership]
    let currentTenant: TenantInfo?
    
    // Statistics and achievements
    let golfStatistics: GolfStatistics?
    let achievements: [Achievement]
    let leaderboardPositions: [LeaderboardPosition]
}

struct GolfUserProfileUpdate {
    let displayName: String?
    let firstName: String?
    let lastName: String?
    let bio: String?
    let handicapIndex: Double?
    let golfPreferences: GolfPreferences?
    let homeClub: GolfClub?
    let membershipType: MembershipType?
    let playingFrequency: PlayingFrequency?
    let location: UserLocation?
    let phoneNumber: String?
    let emergencyContact: EmergencyContact?
    let privacySettings: PrivacySettings?
    let socialVisibility: SocialVisibility?
}

struct GolfUserProfileCreate {
    let email: String
    let displayName: String
    let firstName: String?
    let lastName: String?
    let handicapIndex: Double?
    let golfPreferences: GolfPreferences
    let privacySettings: PrivacySettings
    let tenantId: String?
    let invitationCode: String?
}

struct HandicapEntry {
    let id: String
    let userId: String
    let handicapIndex: Double
    let recordedAt: Date
    let source: HandicapSource
    let verificationLevel: VerificationLevel
    let notes: String?
}

struct HandicapCertification {
    let issuingAuthority: String
    let certificateNumber: String
    let issuedAt: Date
    let expiresAt: Date?
    let verificationLevel: VerificationLevel
}

struct GolfPreferences {
    let preferredTeeBox: TeeBox
    let playingStyle: PlayingStyle
    let courseTypes: [CourseType]
    let preferredRegions: [String]
    let maxTravelDistance: Double
    let budgetRange: PriceRange
    let preferredPlayTimes: [PlayTimePreference]
    let golfCartPreference: GolfCartPreference
    let weatherPreferences: WeatherPreferences
}

struct GolfStatistics {
    let totalRounds: Int
    let averageScore: Double
    let bestScore: Int?
    let handicapTrend: HandicapTrend
    let coursesPlayed: Int
    let favoriteCoursesCount: Int
    let averageRoundDuration: TimeInterval
    let monthlyRounds: [MonthlyStatistic]
    let scoringAnalysis: ScoringAnalysis
    let improvementMetrics: ImprovementMetrics
}

struct TenantMember {
    let userId: String
    let profile: GolfUserProfile
    let membership: TenantMembership
    let lastActiveAt: Date
    let contributionScore: Double
}

struct GolfFriend {
    let userId: String
    let profile: GolfUserProfile
    let friendshipType: FriendshipType
    let connectedAt: Date
    let mutualFriendsCount: Int
    let sharedRoundsCount: Int
    let lastInteractionAt: Date
}

struct Achievement {
    let id: String
    let type: AchievementType
    let title: String
    let description: String
    let iconURL: URL?
    let earnedAt: Date?
    let progress: AchievementProgress?
    let rarity: AchievementRarity
    let points: Int
}

struct AchievementProgress {
    let current: Double
    let target: Double
    let percentage: Double
    let isCompleted: Bool
    let lastUpdatedAt: Date
}

struct LeaderboardPosition {
    let leaderboardType: LeaderboardType
    let position: Int
    let totalParticipants: Int
    let score: Double
    let category: LeaderboardCategory?
    let period: LeaderboardPeriod
}

// MARK: - Privacy and Consent Models

struct ConsentRecord {
    let id: String
    let consentType: ConsentType
    let version: String
    let givenAt: Date
    let expiresAt: Date?
    let ipAddress: String
    let userAgent: String
}

struct UserDataExport {
    let userId: String
    let requestedAt: Date
    let exportURL: URL
    let expiresAt: Date
    let format: ExportFormat
    let includeAllData: Bool
}

// MARK: - Verification Models

struct HandicapVerification {
    let ghinNumber: String?
    let certificate: Data?
    let witnessSignature: String?
    let verifyingOfficialId: String?
}

struct VerificationRequest {
    let id: String
    let userId: String
    let verificationType: VerificationType
    let status: VerificationRequestStatus
    let submittedAt: Date
    let reviewedAt: Date?
    let reviewerId: String?
    let notes: String?
}

struct VerificationStatus {
    let isVerified: Bool
    let verificationLevel: VerificationLevel
    let verifiedAspects: [VerificationType]
    let lastVerifiedAt: Date?
    let trustScore: Double
}

// MARK: - Activity and Analytics Models

struct UserActivity {
    let type: ActivityType
    let metadata: [String: Any]
    let location: CLLocation?
    let sessionId: String?
    let timestamp: Date
}

struct ActivitySummary {
    let period: ActivityPeriod
    let totalActivities: Int
    let uniqueDaysActive: Int
    let averageSessionDuration: TimeInterval
    let mostCommonActivities: [ActivityType]
    let peakActivityTimes: [HourOfDay]
    let engagementScore: Double
}

struct EngagementMetrics {
    let dailyActiveUser: Bool
    let weeklyActiveUser: Bool
    let monthlyActiveUser: Bool
    let sessionsThisWeek: Int
    let averageSessionDuration: TimeInterval
    let retentionScore: Double
    let featureAdoptionRate: Double
}

// MARK: - Search and Discovery Models

struct UserSearchQuery {
    let searchTerm: String?
    let location: CLLocation?
    let maxDistance: Double?
    let handicapRange: HandicapRange?
    let playingFrequency: PlayingFrequency?
    let membershipTypes: [MembershipType]?
    let verifiedOnly: Bool
    let limit: Int
    let offset: Int
}

struct NearbyGolfer {
    let profile: GolfUserProfile
    let distance: Double
    let sharedInterests: [String]
    let compatibilityScore: Double
    let mutualConnections: Int
}

// MARK: - Supporting Models

struct GolfClub {
    let id: String
    let name: String
    let location: UserLocation
    let membershipType: MembershipType
    let logoURL: URL?
}

struct UserLocation {
    let address: String?
    let city: String?
    let state: String?
    let country: String
    let postalCode: String?
    let coordinates: CLLocationCoordinate2D?
    let timezone: String?
}

struct EmergencyContact {
    let name: String
    let phoneNumber: String
    let relationship: String
    let email: String?
}

struct GamePreferences {
    let scorecardFormat: ScorecardFormat
    let enableGPS: Bool
    let autoTrackStats: Bool
    let shareScores: Bool
    let enableTips: Bool
}

struct DisplayPreferences {
    let theme: AppTheme
    let units: MeasurementUnits
    let language: String
    let fontSize: FontSize
}

struct WeatherPreferences {
    let minTemperature: Double?
    let maxTemperature: Double?
    let acceptableConditions: [WeatherCondition]
    let windSpeedLimit: Double?
}

// MARK: - Enums

enum StatisticsPeriod: String, CaseIterable {
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"
    case allTime = "all_time"
}

enum ConsentType: String, CaseIterable {
    case dataProcessing = "data_processing"
    case marketing = "marketing"
    case analytics = "analytics"
    case locationTracking = "location_tracking"
    case socialFeatures = "social_features"
    case thirdPartySharing = "third_party_sharing"
}

enum DataDeletionType: String, CaseIterable {
    case full = "full"
    case partial = "partial"
    case anonymization = "anonymization"
}

enum SocialVisibility: String, CaseIterable {
    case public = "public"
    case friends = "friends"
    case private = "private"
}

enum VerificationType: String, CaseIterable {
    case identity = "identity"
    case handicap = "handicap"
    case membership = "membership"
    case email = "email"
    case phone = "phone"
}

enum VerificationLevel: String, CaseIterable {
    case unverified = "unverified"
    case basic = "basic"
    case enhanced = "enhanced"
    case premium = "premium"
}

enum VerificationRequestStatus: String, CaseIterable {
    case pending = "pending"
    case inReview = "in_review"
    case approved = "approved"
    case rejected = "rejected"
    case expired = "expired"
}

enum ActivityType: String, CaseIterable {
    case login = "login"
    case scoreEntry = "score_entry"
    case courseSearch = "course_search"
    case teeTimeBooking = "tee_time_booking"
    case socialInteraction = "social_interaction"
    case achievementUnlocked = "achievement_unlocked"
    case profileUpdate = "profile_update"
    case friendAdded = "friend_added"
}

enum ActivityPeriod: String, CaseIterable {
    case today = "today"
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"
}

enum MembershipType: String, CaseIterable {
    case full = "full"
    case associate = "associate"
    case junior = "junior"
    case senior = "senior"
    case corporate = "corporate"
    case guest = "guest"
    case trial = "trial"
}

enum PlayingFrequency: String, CaseIterable {
    case daily = "daily"
    case multiple_weekly = "multiple_weekly"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"
    case occasionally = "occasionally"
    case seasonal = "seasonal"
}

enum TeeBox: String, CaseIterable {
    case championship = "championship"
    case regular = "regular"
    case senior = "senior"
    case ladies = "ladies"
    case junior = "junior"
    
    var displayName: String {
        switch self {
        case .championship: return "Championship Tees"
        case .regular: return "Regular Tees"
        case .senior: return "Senior Tees"
        case .ladies: return "Ladies Tees"
        case .junior: return "Junior Tees"
        }
    }
}

enum PlayingStyle: String, CaseIterable {
    case competitive = "competitive"
    case casual = "casual"
    case social = "social"
    case practice = "practice"
    case instruction = "instruction"
}

enum CourseType: String, CaseIterable {
    case championship = "championship"
    case parkland = "parkland"
    case links = "links"
    case desert = "desert"
    case mountain = "mountain"
    case resort = "resort"
    case municipal = "municipal"
    case private = "private"
}

enum GolfCartPreference: String, CaseIterable {
    case required = "required"
    case preferred = "preferred"
    case walkOnly = "walk_only"
    case flexible = "flexible"
}

enum AchievementType: String, CaseIterable {
    case scoring = "scoring"
    case consistency = "consistency"
    case social = "social"
    case exploration = "exploration"
    case improvement = "improvement"
    case milestone = "milestone"
    case seasonal = "seasonal"
}

enum AchievementRarity: String, CaseIterable {
    case common = "common"
    case uncommon = "uncommon"
    case rare = "rare"
    case epic = "epic"
    case legendary = "legendary"
}

enum LeaderboardType: String, CaseIterable {
    case handicap = "handicap"
    case averageScore = "average_score"
    case roundsPlayed = "rounds_played"
    case improvement = "improvement"
    case consistency = "consistency"
    case social = "social"
}

enum LeaderboardCategory: String, CaseIterable {
    case overall = "overall"
    case ageGroup = "age_group"
    case handicapGroup = "handicap_group"
    case location = "location"
    case club = "club"
}

enum LeaderboardPeriod: String, CaseIterable {
    case weekly = "weekly"
    case monthly = "monthly"
    case quarterly = "quarterly"
    case yearly = "yearly"
    case allTime = "all_time"
}

enum FriendshipType: String, CaseIterable {
    case friend = "friend"
    case playingPartner = "playing_partner"
    case clubMate = "club_mate"
    case instructor = "instructor"
    case student = "student"
}

enum HandicapSource: String, CaseIterable {
    case usga = "usga"
    case randa = "randa"
    case selfReported = "self_reported"
    case calculated = "calculated"
    case imported = "imported"
}

enum ExportFormat: String, CaseIterable {
    case json = "json"
    case xml = "xml"
    case csv = "csv"
    case pdf = "pdf"
}

enum PriceRange: String, CaseIterable {
    case budget = "budget"          // $0-50
    case moderate = "moderate"      // $51-100
    case premium = "premium"        // $101-200
    case luxury = "luxury"          // $200+
    case flexible = "flexible"
}

enum PlayTimePreference: String, CaseIterable {
    case earlyMorning = "early_morning"    // 5:30-8:00 AM
    case morning = "morning"               // 8:00-11:00 AM
    case midday = "midday"                 // 11:00 AM-2:00 PM
    case afternoon = "afternoon"           // 2:00-5:00 PM
    case evening = "evening"               // 5:00+ PM
    case twilight = "twilight"             // Last 2 hours before sunset
}

enum WeatherCondition: String, CaseIterable {
    case sunny = "sunny"
    case partlyCloudy = "partly_cloudy"
    case cloudy = "cloudy"
    case lightRain = "light_rain"
    case moderateWind = "moderate_wind"
}

enum ScorecardFormat: String, CaseIterable {
    case traditional = "traditional"
    case strokesGained = "strokes_gained"
    case detailed = "detailed"
    case simple = "simple"
}

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case golfGreen = "golf_green"
}

enum MeasurementUnits: String, CaseIterable {
    case imperial = "imperial"
    case metric = "metric"
}

enum FontSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case extraLarge = "extra_large"
}

enum HourOfDay: Int, CaseIterable {
    case midnight = 0
    case one = 1, two = 2, three = 3, four = 4, five = 5
    case six = 6, seven = 7, eight = 8, nine = 9, ten = 10, eleven = 11
    case noon = 12
    case thirteen = 13, fourteen = 14, fifteen = 15, sixteen = 16, seventeen = 17
    case eighteen = 18, nineteen = 19, twenty = 20, twentyOne = 21, twentyTwo = 22, twentyThree = 23
}

// MARK: - Complex Data Structures

struct HandicapTrend {
    let direction: TrendDirection
    let changeOverPeriod: Double
    let consistencyScore: Double
    let improvementRate: Double
}

struct MonthlyStatistic {
    let month: Date
    let roundsPlayed: Int
    let averageScore: Double
    let handicapIndex: Double?
    let coursesPlayed: Int
}

struct ScoringAnalysis {
    let parBreakdown: [ParValue: ScoringStats]
    let strongestHoles: [HoleLength]
    let improvementAreas: [GameAspect]
    let consistencyMetrics: ConsistencyMetrics
}

struct ImprovementMetrics {
    let handicapImprovement: Double
    let scoreImprovement: Double
    let consistencyImprovement: Double
    let monthsToGoal: Int?
    let recommendedFocus: [GameAspect]
}

struct HandicapRange {
    let minimum: Double
    let maximum: Double
}

struct ConsistencyMetrics {
    let scoreVariability: Double
    let handicapStability: Double
    let performancePredictability: Double
}

struct ScoringStats {
    let average: Double
    let best: Int
    let worst: Int
    let frequency: Double
}

enum TrendDirection: String, CaseIterable {
    case improving = "improving"
    case stable = "stable"
    case declining = "declining"
}

enum ParValue: Int, CaseIterable {
    case three = 3
    case four = 4
    case five = 5
}

enum HoleLength: String, CaseIterable {
    case short = "short"
    case medium = "medium"
    case long = "long"
}

enum GameAspect: String, CaseIterable {
    case driving = "driving"
    case approach = "approach"
    case shortGame = "short_game"
    case putting = "putting"
    case courseManagement = "course_management"
    case mentalGame = "mental_game"
}