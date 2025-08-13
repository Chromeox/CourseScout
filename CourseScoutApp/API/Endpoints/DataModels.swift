import Foundation
import CoreLocation
import CryptoKit

// MARK: - Golf Course Data Models

struct GolfCourse: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let address: Address
    let location: GolfCourseLocation
    let rating: Double
    let reviewCount: Int
    let holes: Int
    let par: Int
    let yardage: Int?
    let difficulty: CourseDifficulty
    let greenFees: GreenFees
    let amenities: [String]
    let photos: [String]
    let contact: ContactInfo
    let hours: [String: String]
    let isPublic: Bool
    let isFeatured: Bool
    let lastUpdated: Date
    
    // Computed properties
    var distanceFromUser: Double?
    
    // Equatable conformance
    static func == (lhs: GolfCourse, rhs: GolfCourse) -> Bool {
        return lhs.id == rhs.id
    }
}

struct Address: Codable {
    let street: String
    let city: String
    let state: String
    let zipCode: String
    let country: String
}

struct GolfCourseLocation: Codable {
    let latitude: Double
    let longitude: Double
    let city: String
    let state: String
    let country: String
}

enum CourseDifficulty: String, Codable, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case challenging = "challenging"
    case championship = "championship"
    
    var displayName: String {
        return rawValue.capitalized
    }
}

struct GreenFees: Codable {
    let weekday: Double
    let weekend: Double
    let twilight: Double?
    let senior: Double?
    let junior: Double?
}

struct ContactInfo: Codable {
    let phone: String?
    let email: String?
    let website: String?
}

// MARK: - Request Models

struct CourseDetailRequest: Codable {
    let includeReviews: Bool
    let includePhotos: Bool
    let includeAvailability: Bool
    let includeWeather: Bool
    
    init(includeReviews: Bool = false, includePhotos: Bool = false, includeAvailability: Bool = false, includeWeather: Bool = false) {
        self.includeReviews = includeReviews
        self.includePhotos = includePhotos
        self.includeAvailability = includeAvailability
        self.includeWeather = includeWeather
    }
}

struct CourseSearchRequest: Codable {
    let query: String?
    let location: CLLocation?
    let radius: Double?
    let minRating: Double?
    let maxRating: Double?
    let minPrice: Double?
    let maxPrice: Double?
    let priceType: PriceType?
    let amenities: [String]?
    let difficulty: CourseDifficulty?
    let isPublic: Bool?
    let holes: Int?
    let sortBy: SortOption?
    let limit: Int?
    let offset: Int?
    
    init(query: String? = nil, location: CLLocation? = nil, radius: Double? = nil,
         minRating: Double? = nil, maxRating: Double? = nil,
         minPrice: Double? = nil, maxPrice: Double? = nil, priceType: PriceType? = nil,
         amenities: [String]? = nil, difficulty: CourseDifficulty? = nil,
         isPublic: Bool? = nil, holes: Int? = nil, sortBy: SortOption? = nil,
         limit: Int? = nil, offset: Int? = nil) {
        self.query = query
        self.location = location
        self.radius = radius
        self.minRating = minRating
        self.maxRating = maxRating
        self.minPrice = minPrice
        self.maxPrice = maxPrice
        self.priceType = priceType
        self.amenities = amenities
        self.difficulty = difficulty
        self.isPublic = isPublic
        self.holes = holes
        self.sortBy = sortBy
        self.limit = limit
        self.offset = offset
    }
    
    var appliedFilters: [String: String] {
        var filters: [String: String] = [:]
        if let query = query { filters["query"] = query }
        if let minRating = minRating { filters["minRating"] = String(minRating) }
        if let maxPrice = maxPrice { filters["maxPrice"] = String(maxPrice) }
        if let difficulty = difficulty { filters["difficulty"] = difficulty.rawValue }
        if let isPublic = isPublic { filters["isPublic"] = String(isPublic) }
        return filters
    }
    
    var cacheKey: String {
        let components = [
            query,
            location?.coordinate.latitude.description,
            location?.coordinate.longitude.description,
            radius?.description,
            minRating?.description,
            maxPrice?.description,
            difficulty?.rawValue,
            isPublic?.description,
            sortBy?.rawValue,
            limit?.description,
            offset?.description
        ].compactMap { $0 }
        
        return components.joined(separator: "_").sha256
    }
}

enum PriceType: String, Codable {
    case weekday = "weekday"
    case weekend = "weekend"
    case twilight = "twilight"
    case senior = "senior"
    case junior = "junior"
}

enum SortOption: String, Codable {
    case name = "name"
    case rating = "rating"
    case price = "price"
    case distance = "distance"
}

struct NearbyCoursesRequest: Codable {
    let location: CLLocation
    let radius: Double // in meters
    let limit: Int?
    let offset: Int?
    let minRating: Double?
    
    init(location: CLLocation, radius: Double = 25000, limit: Int? = nil, offset: Int? = nil, minRating: Double? = nil) {
        self.location = location
        self.radius = radius
        self.limit = limit
        self.offset = offset
        self.minRating = minRating
    }
}

struct AmenityFilterRequest: Codable {
    let amenities: [String]
    let limit: Int?
    let offset: Int?
    
    init(amenities: [String], limit: Int? = nil, offset: Int? = nil) {
        self.amenities = amenities
        self.limit = limit
        self.offset = offset
    }
}

struct PriceRangeRequest: Codable {
    let minPrice: Double?
    let maxPrice: Double?
    let priceType: PriceType
    let limit: Int?
    let offset: Int?
    
    init(minPrice: Double? = nil, maxPrice: Double? = nil, priceType: PriceType = .weekday, limit: Int? = nil, offset: Int? = nil) {
        self.minPrice = minPrice
        self.maxPrice = maxPrice
        self.priceType = priceType
        self.limit = limit
        self.offset = offset
    }
}

struct AvailabilityRequest: Codable {
    let date: Date?
    let timeRange: TimeRange?
    let players: Int?
    
    init(date: Date? = nil, timeRange: TimeRange? = nil, players: Int? = nil) {
        self.date = date
        self.timeRange = timeRange
        self.players = players
    }
}

struct TimeRange: Codable {
    let start: Date
    let end: Date
}

struct ReviewsRequest: Codable {
    let limit: Int?
    let offset: Int?
    let minRating: Int?
    
    init(limit: Int? = nil, offset: Int? = nil, minRating: Int? = nil) {
        self.limit = limit
        self.offset = offset
        self.minRating = minRating
    }
}

struct PhotosRequest: Codable {
    let category: PhotoCategory?
    let limit: Int?
    let offset: Int?
    
    init(category: PhotoCategory? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.category = category
        self.limit = limit
        self.offset = offset
    }
}

enum PhotoCategory: String, Codable {
    case course = "course"
    case clubhouse = "clubhouse"
    case facilities = "facilities"
    case scenery = "scenery"
}

struct RecommendationRequest: Codable {
    let userId: String?
    let type: RecommendationType
    let location: CLLocation?
    let preferences: UserPreferences?
    let limit: Int?
    
    init(userId: String? = nil, type: RecommendationType, location: CLLocation? = nil, preferences: UserPreferences? = nil, limit: Int? = nil) {
        self.userId = userId
        self.type = type
        self.location = location
        self.preferences = preferences
        self.limit = limit
    }
}

enum RecommendationType: String, Codable {
    case personalized = "personalized"
    case similar = "similar"
    case trending = "trending"
    case nearby = "nearby"
}

struct UserPreferences: Codable {
    let preferredDifficulty: CourseDifficulty?
    let maxPrice: Double?
    let favoriteAmenities: [String]?
    let preferredTeeTime: String?
}

struct FeaturedCoursesRequest: Codable {
    let limit: Int?
    let category: FeaturedCategory?
    
    init(limit: Int? = nil, category: FeaturedCategory? = nil) {
        self.limit = limit
        self.category = category
    }
}

enum FeaturedCategory: String, Codable {
    case all = "all"
    case championship = "championship"
    case scenic = "scenic"
    case historic = "historic"
    case newOpening = "new_opening"
}

struct PopularCoursesRequest: Codable {
    let timeFrame: PopularityTimeFrame
    let limit: Int?
    let location: CLLocation?
    let radius: Double?
    
    init(timeFrame: PopularityTimeFrame = .lastMonth, limit: Int? = nil, location: CLLocation? = nil, radius: Double? = nil) {
        self.timeFrame = timeFrame
        self.limit = limit
        self.location = location
        self.radius = radius
    }
}

enum PopularityTimeFrame: String, Codable {
    case lastWeek = "last_week"
    case lastMonth = "last_month"
    case lastQuarter = "last_quarter"
    case lastYear = "last_year"
}

// MARK: - Response Models

struct CourseDetailResponse: Codable {
    let course: GolfCourse
    let reviews: CourseReviewsData?
    let photos: [CoursePhoto]?
    let availability: [TeeTimeSlot]?
    let weather: WeatherInfo?
    let nearbyAttractions: [NearbyAttraction]?
    let requestId: String
    let generatedAt: Date
}

struct CourseSearchResponse: Codable {
    let courses: [GolfCourse]
    let totalCount: Int
    let searchQuery: String?
    let appliedFilters: [String: String]
    let suggestedFilters: [String: [String]]
    let facets: SearchFacets
    let hasMore: Bool
    let requestId: String
    let generatedAt: Date
}

struct AvailabilityResponse: Codable {
    let courseId: String
    let availability: [TeeTimeSlot]?
    let requestId: String
    let generatedAt: Date
}

struct ReviewsResponse: Codable {
    let courseId: String
    let reviews: [CourseReview]
    let averageRating: Double
    let totalCount: Int
    let ratingDistribution: [Int: Int]
    let requestId: String
    let generatedAt: Date
}

struct PhotosResponse: Codable {
    let courseId: String
    let photos: [CoursePhoto]
    let requestId: String
    let generatedAt: Date
}

// MARK: - Supporting Data Models

struct CourseReviewsData {
    let reviews: [CourseReview]
    let averageRating: Double
    let totalCount: Int
    let ratingDistribution: [Int: Int]
}

struct CourseReview: Codable, Identifiable {
    let id: String
    let userId: String
    let username: String
    let rating: Int
    let title: String?
    let comment: String
    let playedDate: Date?
    let createdAt: Date
    let helpful: Int
    let verified: Bool
}

struct CoursePhoto: Codable, Identifiable {
    let id: String
    let url: String
    let thumbnailUrl: String?
    let caption: String?
    let category: PhotoCategory
    let uploadedAt: Date
    let photographer: String?
}

struct TeeTimeSlot: Codable, Identifiable {
    let id: String
    let time: Date
    let available: Bool
    let players: Int
    let price: Double
    let priceType: PriceType
    let restrictions: [String]?
}

struct WeatherInfo: Codable {
    let current: CurrentWeather
    let forecast: [DayForecast]
    let conditions: String
    let playabilityScore: Double // 0-10 scale
}

struct CurrentWeather: Codable {
    let temperature: Double
    let humidity: Double
    let windSpeed: Double
    let windDirection: String
    let precipitation: Double
    let visibility: Double
    let uvIndex: Int
}

struct DayForecast: Codable {
    let date: Date
    let high: Double
    let low: Double
    let conditions: String
    let precipitationChance: Double
    let windSpeed: Double
}

struct NearbyAttraction: Codable, Identifiable {
    let id: String
    let name: String
    let type: AttractionType
    let distance: Double
    let rating: Double?
    let priceLevel: Int?
    let address: String
}

enum AttractionType: String, Codable {
    case restaurant = "restaurant"
    case hotel = "hotel"
    case shopping = "shopping"
    case entertainment = "entertainment"
    case landmark = "landmark"
}

struct SearchFacets {
    let states: [String: Int]
    let difficulties: [String: Int]
    let courseTypes: [String: Int]
    let priceRanges: [String: Int]
}

// MARK: - Mock Service Models

class MockAPIGatewayService: APIGatewayServiceProtocol {
    func processRequest<T: Codable>(_ request: APIGatewayRequest, responseType: T.Type) async throws -> APIGatewayResponse<T> {
        // Mock implementation
        return APIGatewayResponse<T>(
            data: nil,
            statusCode: 200,
            headers: [:],
            requestId: UUID().uuidString,
            processingTimeMs: 50.0
        )
    }
    
    func validateAPIKey(_ apiKey: String) async throws -> APIKeyValidationResult {
        return APIKeyValidationResult(
            isValid: true,
            apiKey: apiKey,
            tier: .premium,
            userId: "mock_user",
            expiresAt: nil,
            remainingQuota: nil
        )
    }
    
    func checkRateLimit(for apiKey: String, endpoint: APIEndpoint) async throws -> RateLimitResult {
        return RateLimitResult(
            allowed: true,
            limit: 1000,
            remaining: 999,
            windowMs: 60000,
            resetTime: Date().addingTimeInterval(60)
        )
    }
    
    func logRequest(_ request: APIGatewayRequest, response: APIGatewayResponse<Any>) async {
        // Mock implementation
    }
    
    func addMiddleware(_ middleware: APIMiddleware) {
        // Mock implementation
    }
    
    func removeMiddleware(_ middlewareType: APIMiddleware.Type) {
        // Mock implementation
    }
    
    func registerEndpoint(_ endpoint: APIEndpoint) {
        // Mock implementation
    }
    
    func getEndpoint(path: String, version: APIVersion) -> APIEndpoint? {
        return nil
    }
    
    func listAvailableEndpoints(for tier: APITier) -> [APIEndpoint] {
        return []
    }
    
    func healthCheck() async -> APIHealthStatus {
        return APIHealthStatus(
            isHealthy: true,
            appwriteConnected: true,
            memoryUsagePercent: 25.0,
            averageResponseTimeMs: 50.0,
            activeConnections: 10,
            timestamp: Date()
        )
    }
    
    func getMetrics(for period: TimePeriod) async -> APIGatewayMetrics {
        return APIGatewayMetrics()
    }
}

// MARK: - Tier-Based Access Control Models

struct APITierAccessControl {
    let tier: APITier
    let features: [APIFeature]
    let limitations: APILimitations
    
    func hasAccess(to feature: APIFeature) -> Bool {
        return features.contains(feature)
    }
}

enum APIFeature: String, CaseIterable {
    // Free Tier Features
    case basicCourseData = "basic_course_data"
    case courseSearch = "course_search"
    case courseDetails = "course_details"
    
    // Premium Tier Features
    case weatherIntegration = "weather_integration"
    case courseAnalytics = "course_analytics"
    case availabilityData = "availability_data"
    case enhancedSearch = "enhanced_search"
    
    // Enterprise Tier Features
    case predictiveInsights = "predictive_insights"
    case demandForecasting = "demand_forecasting"
    case pricingOptimization = "pricing_optimization"
    case aiRecommendations = "ai_recommendations"
    
    // Business Tier Features
    case realtimeBooking = "realtime_booking"
    case bulkOperations = "bulk_operations"
    case webhookIntegration = "webhook_integration"
    case customIntegrations = "custom_integrations"
}

struct APILimitations {
    let dailyRequestLimit: Int
    let requestsPerMinute: Int
    let dataExportLimit: Int?
    let concurrentConnections: Int?
    let customFields: Bool
    let priority: APIResponsePriority
    
    static let freeTier = APILimitations(
        dailyRequestLimit: 1000,
        requestsPerMinute: 16,
        dataExportLimit: nil,
        concurrentConnections: 1,
        customFields: false,
        priority: .standard
    )
    
    static let premiumTier = APILimitations(
        dailyRequestLimit: 10000,
        requestsPerMinute: 167,
        dataExportLimit: 1000,
        concurrentConnections: 5,
        customFields: true,
        priority: .high
    )
    
    static let enterpriseTier = APILimitations(
        dailyRequestLimit: 100000,
        requestsPerMinute: 1667,
        dataExportLimit: 10000,
        concurrentConnections: 20,
        customFields: true,
        priority: .highest
    )
    
    static let businessTier = APILimitations(
        dailyRequestLimit: -1, // Unlimited
        requestsPerMinute: -1, // Unlimited
        dataExportLimit: nil, // Unlimited
        concurrentConnections: 100,
        customFields: true,
        priority: .realtime
    )
}

enum APIResponsePriority: String, CaseIterable {
    case standard = "standard"
    case high = "high"
    case highest = "highest"
    case realtime = "realtime"
}

enum TierUpgradeReason: String {
    case rateLimitExceeded = "rate_limit_exceeded"
    case featureNotAvailable = "feature_not_available"
    case dataLimitExceeded = "data_limit_exceeded"
    case concurrencyLimitExceeded = "concurrency_limit_exceeded"
}

struct TierUpgradeResponse: Codable {
    let currentTier: APITier
    let requiredTier: APITier
    let reason: TierUpgradeReason
    let upgradeUrl: String
    let benefits: [String]
    let pricing: PricingInfo?
    
    init(currentTier: APITier, requiredTier: APITier, reason: TierUpgradeReason) {
        self.currentTier = currentTier
        self.requiredTier = requiredTier
        self.reason = reason
        self.upgradeUrl = "https://api.golfscout.com/upgrade"
        self.benefits = Self.getBenefits(for: requiredTier)
        self.pricing = Self.getPricing(for: requiredTier)
    }
    
    private static func getBenefits(for tier: APITier) -> [String] {
        switch tier {
        case .free:
            return []
        case .premium:
            return [
                "10,000 requests per day",
                "Weather integration",
                "Course analytics",
                "Priority support"
            ]
        case .enterprise:
            return [
                "100,000 requests per day",
                "AI-powered predictions",
                "Demand forecasting",
                "Custom integrations"
            ]
        case .business:
            return [
                "Unlimited requests",
                "Real-time booking",
                "Bulk operations",
                "Dedicated support"
            ]
        }
    }
    
    private static func getPricing(for tier: APITier) -> PricingInfo? {
        switch tier {
        case .free:
            return nil
        case .premium:
            return PricingInfo(monthlyPrice: 99, yearlyPrice: 990, currency: "USD")
        case .enterprise:
            return PricingInfo(monthlyPrice: 499, yearlyPrice: 4990, currency: "USD")
        case .business:
            return PricingInfo(monthlyPrice: 1999, yearlyPrice: 19990, currency: "USD")
        }
    }
}

struct PricingInfo: Codable {
    let monthlyPrice: Int
    let yearlyPrice: Int
    let currency: String
}

// MARK: - Predictive Insights Models

struct PredictiveInsightsRequest: Codable {
    let courseId: String?
    let region: String?
    let predictionType: PredictionType
    let timeframe: PredictionTimeframe
    let factors: [PredictionFactor]
    let includeConfidence: Bool
    
    init(courseId: String? = nil, region: String? = nil, predictionType: PredictionType, timeframe: PredictionTimeframe = .nextMonth, factors: [PredictionFactor] = [], includeConfidence: Bool = true) {
        self.courseId = courseId
        self.region = region
        self.predictionType = predictionType
        self.timeframe = timeframe
        self.factors = factors
        self.includeConfidence = includeConfidence
    }
    
    var cacheKey: String {
        let components = [
            courseId ?? "all",
            region ?? "global",
            predictionType.rawValue,
            timeframe.rawValue,
            factors.map { $0.rawValue }.joined(separator: ","),
            String(includeConfidence)
        ]
        return components.joined(separator: "_").sha256
    }
}

enum PredictionType: String, Codable, CaseIterable {
    case optimalPricing = "optimal_pricing"
    case bookingDemand = "booking_demand"
    case weatherImpact = "weather_impact"
    case personalizedRecommendations = "personalized_recommendations"
    case revenueForecasting = "revenue_forecasting"
    case competitorAnalysis = "competitor_analysis"
}

enum PredictionTimeframe: String, Codable, CaseIterable {
    case nextWeek = "next_week"
    case nextMonth = "next_month"
    case nextQuarter = "next_quarter"
    case nextSeason = "next_season"
    case nextYear = "next_year"
}

enum PredictionFactor: String, Codable, CaseIterable {
    case weather = "weather"
    case seasonality = "seasonality"
    case competitors = "competitors"
    case events = "events"
    case economy = "economy"
    case holidays = "holidays"
    case userBehavior = "user_behavior"
}

struct PredictiveInsightsResponse: Codable {
    let predictionType: PredictionType
    let timeframe: PredictionTimeframe
    let courseId: String?
    let predictions: [Prediction]
    let insights: [PredictiveInsight]
    let confidence: ConfidenceMetrics?
    let recommendations: [ActionableRecommendation]
    let generatedAt: Date
    let requestId: String
}

struct Prediction: Codable, Identifiable {
    let id: String
    let type: PredictionType
    let value: PredictionValue
    let timeRange: DateRange
    let confidence: Double // 0.0 to 1.0
    let factors: [String: Double]
    let impact: PredictionImpact
}

enum PredictionValue: Codable {
    case pricing(PricingPrediction)
    case demand(DemandPrediction)
    case weather(WeatherImpactPrediction)
    case recommendations([CourseRecommendation])
    case revenue(RevenuePrediction)
    
    private enum CodingKeys: String, CodingKey {
        case type, data
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pricing(let prediction):
            try container.encode("pricing", forKey: .type)
            try container.encode(prediction, forKey: .data)
        case .demand(let prediction):
            try container.encode("demand", forKey: .type)
            try container.encode(prediction, forKey: .data)
        case .weather(let prediction):
            try container.encode("weather", forKey: .type)
            try container.encode(prediction, forKey: .data)
        case .recommendations(let predictions):
            try container.encode("recommendations", forKey: .type)
            try container.encode(predictions, forKey: .data)
        case .revenue(let prediction):
            try container.encode("revenue", forKey: .type)
            try container.encode(prediction, forKey: .data)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "pricing":
            let data = try container.decode(PricingPrediction.self, forKey: .data)
            self = .pricing(data)
        case "demand":
            let data = try container.decode(DemandPrediction.self, forKey: .data)
            self = .demand(data)
        case "weather":
            let data = try container.decode(WeatherImpactPrediction.self, forKey: .data)
            self = .weather(data)
        case "recommendations":
            let data = try container.decode([CourseRecommendation].self, forKey: .data)
            self = .recommendations(data)
        case "revenue":
            let data = try container.decode(RevenuePrediction.self, forKey: .data)
            self = .revenue(data)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid prediction type: \(type)")
        }
    }
}

struct PricingPrediction: Codable {
    let currentPrice: Double
    let recommendedPrice: Double
    let priceRange: ClosedRange<Double>
    let expectedRevenueLift: Double
    let demandElasticity: Double
    let competitorAnalysis: [CompetitorPricing]
}

struct DemandPrediction: Codable {
    let currentDemand: Int
    let predictedDemand: Int
    let demandTrend: DemandTrend
    let peakTimes: [TimeSlot]
    let seasonalFactors: [SeasonalFactor]
}

struct WeatherImpactPrediction: Codable {
    let currentScore: Double
    let predictedScore: Double
    let weatherFactors: [WeatherFactor]
    let alternativeRecommendations: [String]
}

struct CourseRecommendation: Codable, Identifiable {
    let id: String
    let courseId: String
    let courseName: String
    let score: Double
    let reasons: [RecommendationReason]
    let distance: Double?
    let priceComparison: PriceComparison?
}

struct RevenuePrediction: Codable {
    let currentRevenue: Double
    let predictedRevenue: Double
    let revenueGrowth: Double
    let revenueBySource: [String: Double]
    let optimizationOpportunities: [RevenueOpportunity]
}

struct PredictiveInsight: Codable, Identifiable {
    let id: String
    let type: InsightType
    let title: String
    let description: String
    let severity: InsightSeverity
    let actionable: Bool
    let recommendations: [String]
    let impact: ImpactEstimate
}

struct ConfidenceMetrics: Codable {
    let overall: Double
    let dataQuality: Double
    let modelAccuracy: Double
    let temporalReliability: Double
    let factors: [String: Double]
}

struct ActionableRecommendation: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let category: RecommendationCategory
    let priority: RecommendationPriority
    let expectedImpact: ImpactEstimate
    let implementationComplexity: ComplexityLevel
    let timeline: RecommendationTimeline
}

enum RecommendationCategory: String, Codable {
    case pricing = "pricing"
    case marketing = "marketing"
    case operations = "operations"
    case customer = "customer"
    case infrastructure = "infrastructure"
}

enum RecommendationPriority: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case urgent = "urgent"
}

enum ComplexityLevel: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case expert = "expert"
}

struct RecommendationTimeline: Codable {
    let immediate: [String]
    let shortTerm: [String] // 1-4 weeks
    let mediumTerm: [String] // 1-6 months
    let longTerm: [String] // 6+ months
}

// MARK: - Real-Time Booking Models

struct RealTimeBookingRequest: Codable {
    let courseId: String
    let playerId: String?
    let requestType: RealTimeRequestType
    let timeRange: TimeRange?
    let players: Int?
    let preferences: BookingPreferences?
    
    var cacheKey: String {
        let components = [
            courseId,
            playerId ?? "guest",
            requestType.rawValue,
            String(players ?? 1)
        ]
        return components.joined(separator: "_").sha256
    }
}

enum RealTimeRequestType: String, Codable {
    case streamUpdates = "stream_updates"
    case createBooking = "create_booking"
    case updateBooking = "update_booking"
    case cancelBooking = "cancel_booking"
    case bulkStatus = "bulk_status"
    case availability = "availability"
}

struct BookingPreferences: Codable {
    let preferredTimes: [String]
    let maxPrice: Double?
    let minDuration: Int? // minutes
    let equipmentNeeded: Bool
    let caddyRequired: Bool
    let mealPackage: Bool
}

struct RealTimeBookingResponse: Codable {
    let requestType: RealTimeRequestType
    let courseId: String
    let data: BookingResponseData
    let realTimeUrl: String?
    let websocketToken: String?
    let generatedAt: Date
    let requestId: String
}

enum BookingResponseData: Codable {
    case availability([TeeTimeSlot])
    case booking(Booking)
    case bookingUpdate(BookingUpdate)
    case bulkStatus([BookingStatus])
    case streamInfo(StreamInfo)
    
    private enum CodingKeys: String, CodingKey {
        case type, data
    }
}

struct Booking: Codable, Identifiable {
    let id: String
    let courseId: String
    let playerId: String
    let teeTime: Date
    let players: Int
    let status: BookingStatus
    let totalPrice: Double
    let confirmationCode: String
    let specialRequests: [String]?
    let createdAt: Date
    let updatedAt: Date
}

enum BookingStatus: String, Codable {
    case pending = "pending"
    case confirmed = "confirmed"
    case cancelled = "cancelled"
    case completed = "completed"
    case noShow = "no_show"
    case modified = "modified"
}

struct BookingUpdate: Codable {
    let bookingId: String
    let changeType: ChangeType
    let previousValue: String?
    let newValue: String?
    let timestamp: Date
    let reason: String?
}

enum ChangeType: String, Codable {
    case timeChange = "time_change"
    case playerCount = "player_count"
    case statusUpdate = "status_update"
    case priceUpdate = "price_update"
    case specialRequest = "special_request"
}

struct StreamInfo: Codable {
    let streamId: String
    let websocketUrl: String
    let authToken: String
    let expiresAt: Date
    let supportedEvents: [StreamEvent]
}

enum StreamEvent: String, Codable {
    case bookingCreated = "booking_created"
    case bookingUpdated = "booking_updated"
    case bookingCancelled = "booking_cancelled"
    case availabilityChanged = "availability_changed"
    case priceUpdated = "price_updated"
    case weatherAlert = "weather_alert"
}

// MARK: - Enhanced Analytics Models

struct AnalyticsPeriod: Codable {
    let startDate: Date
    let endDate: Date
    let granularity: DataGranularity
    
    var days: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }
}

struct CourseAnalyticsData: Codable {
    let courseId: String
    let period: AnalyticsPeriod
    let metrics: CourseMetricsData
    let trends: CourseTrendsData
    let insights: [AnalyticsInsight]
    let benchmarks: CourseBenchmarks
}

struct CourseMetricsData: Codable {
    let bookingMetrics: BookingMetrics
    let revenueMetrics: RevenueMetrics
    let customerMetrics: CustomerMetrics
    let operationalMetrics: OperationalMetrics
}

struct BookingMetrics: Codable {
    let totalBookings: Int
    let completedRounds: Int
    let noShowRate: Double
    let cancellationRate: Double
    let averageAdvanceBooking: Double // days
    let peakUtilization: Double
    let offPeakUtilization: Double
}

struct RevenueMetrics: Codable {
    let totalRevenue: Double
    let revenuePerRound: Double
    let revenueGrowth: Double
    let seasonalVariation: Double
    let pricingEfficiency: Double
}

struct CustomerMetrics: Codable {
    let uniqueCustomers: Int
    let repeatCustomerRate: Double
    let averageCustomerLifetime: Double
    let customerSatisfactionScore: Double
    let referralRate: Double
}

struct OperationalMetrics: Codable {
    let utilizationRate: Double
    let maintenanceHours: Int
    let staffEfficiency: Double
    let equipmentUtilization: Double
    let facilityRating: Double
}

struct CourseTrendsData: Codable {
    let bookingTrends: [TrendDataPoint]
    let revenueTrends: [TrendDataPoint]
    let seasonalPatterns: [SeasonalDataPoint]
    let forecastData: [ForecastDataPoint]
}

struct TrendDataPoint: Codable {
    let date: Date
    let value: Double
    let change: Double // percentage change from previous period
    let anomaly: Bool
}

struct SeasonalDataPoint: Codable {
    let period: String // e.g., "Q1", "Summer", "Weekend"
    let averageValue: Double
    let volatility: Double
    let trend: SeasonalTrend
}

enum SeasonalTrend: String, Codable {
    case increasing = "increasing"
    case stable = "stable"
    case decreasing = "decreasing"
    case volatile = "volatile"
}

struct ForecastDataPoint: Codable {
    let date: Date
    let predictedValue: Double
    let confidenceInterval: ConfidenceInterval
    let factors: [ForecastFactor]
}

struct ConfidenceInterval: Codable {
    let lower: Double
    let upper: Double
    let confidence: Double // e.g., 0.95 for 95% confidence
}

struct ForecastFactor: Codable {
    let name: String
    let impact: Double
    let confidence: Double
}

struct CourseBenchmarks: Codable {
    let industryAverages: IndustryBenchmarks
    let regionalAverages: RegionalBenchmarks
    let competitorComparison: CompetitorBenchmarks
    let performance: PerformanceRating
}

struct IndustryBenchmarks: Codable {
    let utilizationRate: Double
    let revenuePerRound: Double
    let customerSatisfaction: Double
    let seasonalVariation: Double
}

struct RegionalBenchmarks: Codable {
    let region: String
    let averagePrice: Double
    let bookingVolume: Int
    let competitorCount: Int
    let marketShare: Double
}

struct CompetitorBenchmarks: Codable {
    let competitors: [CompetitorMetrics]
    let marketPosition: MarketPosition
    let competitiveAdvantages: [String]
    let improvementAreas: [String]
}

struct CompetitorMetrics: Codable {
    let name: String
    let averagePrice: Double
    let utilizationRate: Double?
    let customerRating: Double?
    let distance: Double // km from current course
}

enum MarketPosition: String, Codable {
    case leader = "leader"
    case challenger = "challenger"
    case follower = "follower"
    case niche = "niche"
}

enum PerformanceRating: String, Codable {
    case excellent = "excellent"
    case good = "good"
    case average = "average"
    case belowAverage = "below_average"
    case poor = "poor"
}

// MARK: - Supporting Data Models

struct DateRange: Codable {
    let start: Date
    let end: Date
    
    var duration: TimeInterval {
        return end.timeIntervalSince(start)
    }
    
    var days: Int {
        return Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

enum DemandTrend: String, Codable {
    case increasing = "increasing"
    case stable = "stable"
    case decreasing = "decreasing"
    case seasonal = "seasonal"
    case volatile = "volatile"
}

struct TimeSlot: Codable {
    let startTime: Date
    let endTime: Date
    let utilization: Double
    let averagePrice: Double
}

struct SeasonalFactor: Codable {
    let factor: String
    let impact: Double // -1.0 to 1.0
    let confidence: Double
}

struct WeatherFactor: Codable {
    let condition: String
    let impact: Double
    let probability: Double
}

enum RecommendationReason: String, Codable {
    case similarPreferences = "similar_preferences"
    case proximityMatch = "proximity_match"
    case priceMatch = "price_match"
    case availabilityMatch = "availability_match"
    case ratingMatch = "rating_match"
    case seasonalTrend = "seasonal_trend"
}

struct PriceComparison: Codable {
    let currentCoursePrice: Double
    let recommendedCoursePrice: Double
    let savings: Double
    let priceRatio: Double
}

enum InsightSeverity: String, Codable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"
    case opportunity = "opportunity"
}

struct ImpactEstimate: Codable {
    let metric: String
    let currentValue: Double
    let projectedValue: Double
    let impact: Double // percentage change
    let confidence: Double
    let timeframe: String
}

struct CompetitorPricing: Codable {
    let competitorName: String
    let averagePrice: Double
    let priceRange: ClosedRange<Double>
    let pricingStrategy: PricingStrategy
    let marketShare: Double?
}

enum PricingStrategy: String, Codable {
    case premium = "premium"
    case competitive = "competitive"
    case discount = "discount"
    case dynamic = "dynamic"
    case value = "value"
}

struct RevenueOpportunity: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let category: RevenueCategory
    let potentialLift: Double
    let implementationCost: Double
    let timeToImplement: Int // days
    let riskLevel: RiskLevel
}

enum RevenueCategory: String, Codable {
    case pricing = "pricing"
    case upselling = "upselling"
    case retention = "retention"
    case acquisition = "acquisition"
    case operational = "operational"
}

enum RiskLevel: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case veryHigh = "very_high"
}

// MARK: - Error Response Models

struct APIErrorResponse: Codable {
    let error: APIErrorDetail
    let requestId: String
    let timestamp: Date
    let tier: APITier
    let upgradeInfo: TierUpgradeResponse?
}

struct APIErrorDetail: Codable {
    let code: String
    let message: String
    let details: String?
    let httpStatus: Int
    let retryAfter: TimeInterval?
}

// MARK: - Extensions

extension String {
    var sha256: String {
        let data = Data(self.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

extension CLLocation: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
}

extension ClosedRange: Codable where Bound: Codable {
    enum CodingKeys: String, CodingKey {
        case lowerBound
        case upperBound
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lowerBound, forKey: .lowerBound)
        try container.encode(upperBound, forKey: .upperBound)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lower = try container.decode(Bound.self, forKey: .lowerBound)
        let upper = try container.decode(Bound.self, forKey: .upperBound)
        self = lower...upper
    }
}

// MARK: - Tier Access Control Helper

struct TierAccessController {
    static func validateAccess(for tier: APITier, feature: APIFeature) throws {
        let allowedFeatures = getFeaturesForTier(tier)
        
        guard allowedFeatures.contains(feature) else {
            let requiredTier = getMinimumTierForFeature(feature)
            throw APIGatewayError.insufficientTier(required: requiredTier, current: tier)
        }
    }
    
    static func validateRequest(for tier: APITier, endpoint: String) throws -> Bool {
        let feature = getFeatureForEndpoint(endpoint)
        try validateAccess(for: tier, feature: feature)
        return true
    }
    
    private static func getFeaturesForTier(_ tier: APITier) -> [APIFeature] {
        switch tier {
        case .free:
            return [.basicCourseData, .courseSearch, .courseDetails]
        case .premium:
            return [.basicCourseData, .courseSearch, .courseDetails, .weatherIntegration, .courseAnalytics, .availabilityData, .enhancedSearch]
        case .enterprise:
            return APIFeature.allCases.filter { $0 != .realtimeBooking && $0 != .bulkOperations && $0 != .webhookIntegration && $0 != .customIntegrations }
        case .business:
            return APIFeature.allCases
        }
    }
    
    private static func getMinimumTierForFeature(_ feature: APIFeature) -> APITier {
        switch feature {
        case .basicCourseData, .courseSearch, .courseDetails:
            return .free
        case .weatherIntegration, .courseAnalytics, .availabilityData, .enhancedSearch:
            return .premium
        case .predictiveInsights, .demandForecasting, .pricingOptimization, .aiRecommendations:
            return .enterprise
        case .realtimeBooking, .bulkOperations, .webhookIntegration, .customIntegrations:
            return .business
        }
    }
    
    private static func getFeatureForEndpoint(_ endpoint: String) -> APIFeature {
        switch endpoint {
        case "/courses", "/courses/details":
            return .basicCourseData
        case "/courses/search":
            return .courseSearch
        case "/courses/analytics":
            return .courseAnalytics
        case "/courses/weather":
            return .weatherIntegration
        case "/predictions":
            return .predictiveInsights
        case "/booking/realtime":
            return .realtimeBooking
        default:
            return .basicCourseData
        }
    }
}