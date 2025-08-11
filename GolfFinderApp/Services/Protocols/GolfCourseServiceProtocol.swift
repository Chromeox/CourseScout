import Foundation
import CoreLocation

// MARK: - Golf Course Service Protocol

protocol GolfCourseServiceProtocol {
    // MARK: - Course Discovery
    
    /// Fetch golf courses near a location
    func searchCourses(
        near location: CLLocationCoordinate2D,
        radius: Double,
        filters: CourseSearchFilters?
    ) async throws -> [GolfCourse]
    
    /// Search courses by name or location text
    func searchCourses(
        query: String,
        location: CLLocationCoordinate2D?,
        filters: CourseSearchFilters?
    ) async throws -> [GolfCourse]
    
    /// Get featured/recommended courses
    func getFeaturedCourses(
        for location: CLLocationCoordinate2D?,
        limit: Int
    ) async throws -> [GolfCourse]
    
    /// Get recently played courses for a user
    func getRecentCourses(for userId: String) async throws -> [GolfCourse]
    
    // MARK: - Course Details
    
    /// Fetch detailed information about a specific course
    func getCourseDetails(courseId: String) async throws -> GolfCourse
    
    /// Get course images and media
    func getCourseImages(courseId: String) async throws -> [CourseImage]
    
    /// Get course hole information and layout
    func getCourseLayout(courseId: String) async throws -> [HoleInfo]
    
    /// Get real-time course conditions
    func getCourseConditions(courseId: String) async throws -> CourseConditions
    
    // MARK: - Course Ratings and Reviews
    
    /// Get reviews for a specific course
    func getCourseReviews(
        courseId: String,
        page: Int,
        limit: Int
    ) async throws -> ReviewPage
    
    /// Submit a review for a course
    func submitReview(
        courseId: String,
        review: CourseReview
    ) async throws -> CourseReview
    
    /// Get course rating breakdown
    func getCourseRating(courseId: String) async throws -> CourseRatingDetails
    
    // MARK: - Favorites and Saved Courses
    
    /// Add course to user's favorites
    func addToFavorites(courseId: String, userId: String) async throws
    
    /// Remove course from user's favorites
    func removeFromFavorites(courseId: String, userId: String) async throws
    
    /// Get user's favorite courses
    func getFavoriteCourses(userId: String) async throws -> [GolfCourse]
    
    /// Check if course is in user's favorites
    func isFavorite(courseId: String, userId: String) async throws -> Bool
    
    // MARK: - Course Analytics
    
    /// Get popular courses in an area
    func getPopularCourses(
        near location: CLLocationCoordinate2D,
        radius: Double,
        timeframe: PopularityTimeframe
    ) async throws -> [GolfCourse]
    
    /// Get course play statistics
    func getCourseStatistics(courseId: String) async throws -> CourseStatistics
    
    /// Track course view/visit
    func trackCourseView(courseId: String, userId: String?) async throws
    
    // MARK: - Course Management (Admin)
    
    /// Update course information
    func updateCourse(_ course: GolfCourse) async throws -> GolfCourse
    
    /// Upload course images
    func uploadCourseImage(
        courseId: String,
        imageData: Data,
        caption: String?,
        imageType: CourseImage.ImageType
    ) async throws -> CourseImage
    
    /// Update course conditions
    func updateCourseConditions(
        courseId: String,
        conditions: CourseConditions
    ) async throws
}

// MARK: - Search Filters

struct CourseSearchFilters: Codable {
    let priceRange: ClosedRange<Double>?
    let difficulty: [DifficultyLevel]?
    let amenities: [CourseAmenity]?
    let guestPolicy: [GuestPolicy]?
    let dressCode: [DressCode]?
    let minimumRating: Double?
    let hasAvailableTimes: Bool?
    let openToday: Bool?
    let courseType: [CourseType]?
    let holes: [Int]?                    // 9, 18, or both
    
    enum CourseType: String, CaseIterable, Codable {
        case public = "public"
        case private = "private"
        case semiPrivate = "semi_private"
        case resort = "resort"
        case municipal = "municipal"
        
        var displayName: String {
            switch self {
            case .public: return "Public"
            case .private: return "Private"
            case .semiPrivate: return "Semi-Private"
            case .resort: return "Resort"
            case .municipal: return "Municipal"
            }
        }
    }
    
    init(
        priceRange: ClosedRange<Double>? = nil,
        difficulty: [DifficultyLevel]? = nil,
        amenities: [CourseAmenity]? = nil,
        guestPolicy: [GuestPolicy]? = nil,
        dressCode: [DressCode]? = nil,
        minimumRating: Double? = nil,
        hasAvailableTimes: Bool? = nil,
        openToday: Bool? = nil,
        courseType: [CourseType]? = nil,
        holes: [Int]? = nil
    ) {
        self.priceRange = priceRange
        self.difficulty = difficulty
        self.amenities = amenities
        self.guestPolicy = guestPolicy
        self.dressCode = dressCode
        self.minimumRating = minimumRating
        self.hasAvailableTimes = hasAvailableTimes
        self.openToday = openToday
        self.courseType = courseType
        self.holes = holes
    }
}

// MARK: - Course Review

struct CourseReview: Identifiable, Codable {
    let id: String
    let courseId: String
    let userId: String
    let userName: String
    let userHandicap: Double?
    
    // Review content
    let rating: Int                  // 1-5 stars
    let title: String?
    let review: String
    let playedDate: Date?
    
    // Detailed ratings
    let courseCondition: Int?        // 1-5
    let courseLayout: Int?           // 1-5
    let staff: Int?                  // 1-5
    let value: Int?                  // 1-5
    let amenities: Int?              // 1-5
    let difficulty: Int?             // 1-5
    
    // Review metadata
    let isVerifiedPlay: Bool         // User actually played the course
    let photos: [String]?            // Photo URLs
    let helpfulVotes: Int
    let totalVotes: Int
    
    let createdAt: Date
    let updatedAt: Date
    
    var helpfulPercentage: Double {
        guard totalVotes > 0 else { return 0.0 }
        return Double(helpfulVotes) / Double(totalVotes) * 100
    }
    
    var averageDetailedRating: Double? {
        let ratings = [courseCondition, courseLayout, staff, value, amenities, difficulty].compactMap { $0 }
        guard !ratings.isEmpty else { return nil }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }
}

struct ReviewPage: Codable {
    let reviews: [CourseReview]
    let totalCount: Int
    let currentPage: Int
    let totalPages: Int
    let hasNextPage: Bool
}

// MARK: - Course Rating Details

struct CourseRatingDetails: Codable {
    let courseId: String
    let averageRating: Double
    let totalReviews: Int
    let ratingBreakdown: [Int: Int]    // Rating (1-5) -> Count
    
    // Detailed rating averages
    let averageCondition: Double?
    let averageLayout: Double?
    let averageStaff: Double?
    let averageValue: Double?
    let averageAmenities: Double?
    let averageDifficulty: Double?
    
    // Recent trends
    let ratingTrend: RatingTrend       // Improving, declining, stable
    let recentAverageRating: Double    // Last 30 days
    
    enum RatingTrend: String, CaseIterable, Codable {
        case improving = "improving"
        case declining = "declining"
        case stable = "stable"
        
        var displayName: String {
            rawValue.capitalized
        }
        
        var icon: String {
            switch self {
            case .improving: return "arrow.up.circle.fill"
            case .declining: return "arrow.down.circle.fill"
            case .stable: return "minus.circle.fill"
            }
        }
        
        var color: String {
            switch self {
            case .improving: return "green"
            case .declining: return "red"
            case .stable: return "gray"
            }
        }
    }
    
    var ratingDistribution: [(rating: Int, percentage: Double)] {
        let total = Double(totalReviews)
        guard total > 0 else { return [] }
        
        return (1...5).map { rating in
            let count = Double(ratingBreakdown[rating] ?? 0)
            return (rating: rating, percentage: (count / total) * 100)
        }.reversed()
    }
}

// MARK: - Hole Information

struct HoleInfo: Identifiable, Codable {
    let id: String
    let courseId: String
    let holeNumber: Int
    let par: Int
    let handicapIndex: Int
    
    // Yardages for different tees
    let yardages: [String: Int]      // "Championship": 425, "Regular": 385, etc.
    
    // Hole description and layout
    let name: String?                // "Devil's Triangle"
    let description: String?
    let layout: HoleLayout
    let hazards: [HoleHazard]
    
    // Hole images and diagrams
    let images: [HoleImage]
    let layoutDiagram: String?       // URL to hole layout diagram
    
    // Playing tips and strategy
    let proTip: String?
    let strategy: HoleStrategy?
    
    enum HoleLayout: String, CaseIterable, Codable {
        case straight = "straight"
        case doglegLeft = "dogleg_left"
        case doglegRight = "dogleg_right"
        case doubleDogleg = "double_dogleg"
        case island = "island"
        case links = "links"
        
        var displayName: String {
            switch self {
            case .straight: return "Straight"
            case .doglegLeft: return "Dogleg Left"
            case .doglegRight: return "Dogleg Right"
            case .doubleDogleg: return "Double Dogleg"
            case .island: return "Island"
            case .links: return "Links Style"
            }
        }
    }
    
    struct HoleHazard: Codable {
        let type: HazardType
        let distance: Int?           // Distance from tee
        let side: HazardSide?        // Left, right, center
        let description: String?
        
        enum HazardType: String, CaseIterable, Codable {
            case water = "water"
            case bunker = "bunker"
            case trees = "trees"
            case outOfBounds = "out_of_bounds"
            case rough = "rough"
            case slope = "slope"
            
            var displayName: String {
                switch self {
                case .water: return "Water Hazard"
                case .bunker: return "Bunker"
                case .trees: return "Trees"
                case .outOfBounds: return "Out of Bounds"
                case .rough: return "Rough"
                case .slope: return "Slope"
                }
            }
            
            var icon: String {
                switch self {
                case .water: return "drop.fill"
                case .bunker: return "circle.fill"
                case .trees: return "tree.fill"
                case .outOfBounds: return "xmark.octagon"
                case .rough: return "grass"
                case .slope: return "triangle.fill"
                }
            }
        }
        
        enum HazardSide: String, CaseIterable, Codable {
            case left = "left"
            case right = "right"
            case center = "center"
            case leftAndRight = "left_and_right"
            
            var displayName: String {
                switch self {
                case .left: return "Left"
                case .right: return "Right"
                case .center: return "Center"
                case .leftAndRight: return "Left & Right"
                }
            }
        }
    }
    
    struct HoleImage: Identifiable, Codable {
        let id: String
        let url: String
        let caption: String?
        let viewType: ViewType
        
        enum ViewType: String, CaseIterable, Codable {
            case tee = "tee"
            case fairway = "fairway"
            case approach = "approach"
            case green = "green"
            case aerial = "aerial"
            
            var displayName: String {
                switch self {
                case .tee: return "Tee Box View"
                case .fairway: return "Fairway View"
                case .approach: return "Approach View"
                case .green: return "Green View"
                case .aerial: return "Aerial View"
                }
            }
        }
    }
    
    struct HoleStrategy: Codable {
        let recommendedClub: String?
        let strategy: String
        let avoidAreas: [String]?
        let targetAreas: [String]?
        let windConsiderations: String?
    }
}

// MARK: - Course Statistics

struct CourseStatistics: Codable {
    let courseId: String
    let totalRounds: Int
    let averageScore: Double
    let averageRating: Double
    let popularTeeType: TeeType
    
    // Booking statistics
    let bookingMetrics: BookingMetrics
    
    // Performance statistics
    let performanceMetrics: PerformanceMetrics
    
    // Popularity metrics
    let popularityMetrics: PopularityMetrics
    
    struct BookingMetrics: Codable {
        let totalBookings: Int
        let averageBookingsPerDay: Double
        let peakBookingTimes: [String]   // ["08:00", "14:00"]
        let busySeason: String?          // "June - August"
        let averageGroupSize: Double
    }
    
    struct PerformanceMetrics: Codable {
        let averageScoreByTee: [TeeType: Double]
        let mostCommonScore: Int
        let birdieRate: Double           // Percentage
        let parRate: Double
        let bogeyRate: Double
        let averageRoundTime: Int        // Minutes
    }
    
    struct PopularityMetrics: Codable {
        let monthlyPlayers: Int
        let repeatPlayerRate: Double     // Percentage of players who return
        let referralRate: Double
        let socialMediaMentions: Int?
        let rankingPosition: Int?        // Local/regional ranking
    }
}

// MARK: - Popularity Timeframe

enum PopularityTimeframe: String, CaseIterable, Codable {
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"
    
    var displayName: String {
        switch self {
        case .week: return "This Week"
        case .month: return "This Month"
        case .quarter: return "This Quarter"
        case .year: return "This Year"
        }
    }
    
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        }
    }
}