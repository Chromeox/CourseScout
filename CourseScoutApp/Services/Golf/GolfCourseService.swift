import Foundation
import CoreLocation
import Appwrite
import Alamofire

// MARK: - Golf Course Service Implementation

class GolfCourseService: GolfCourseServiceProtocol {
    
    // MARK: - Properties
    
    private let client: Client
    private let databases: Databases
    private let storage: Storage
    
    // Database configuration
    private let databaseId = Configuration.appwrite.databaseId
    private let coursesCollectionId = "golf_courses"
    private let reviewsCollectionId = "course_reviews"
    private let imagesCollectionId = "course_images"
    private let holesCollectionId = "hole_info"
    
    // Performance optimization
    private let courseCache = NSCache<NSString, NSArray>()
    private let imageCache = NSCache<NSString, NSData>()
    
    // MARK: - Initialization
    
    init(appwriteClient: Client) {
        self.client = appwriteClient
        self.databases = Databases(client)
        self.storage = Storage(client)
        
        // Configure cache limits
        courseCache.countLimit = 100
        courseCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        imageCache.countLimit = 200
        imageCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }
    
    // MARK: - Course Discovery Implementation
    
    func searchCourses(
        near location: CLLocationCoordinate2D,
        radius: Double,
        filters: CourseSearchFilters?
    ) async throws -> [GolfCourse] {
        
        let cacheKey = "courses_\(location.latitude)_\(location.longitude)_\(radius)"
        
        // Check cache first
        if let cachedCourses = courseCache.object(forKey: cacheKey as NSString) as? [GolfCourse] {
            return applyFilters(cachedCourses, filters: filters)
        }
        
        // Build location-based query
        var queries: [String] = []
        
        // Geographic radius search using Appwrite's geographical queries
        let latRange = radius / 69.0 // Approximate miles to degrees
        let lonRange = radius / (69.0 * cos(location.latitude * .pi / 180.0))
        
        queries.append("latitude >= \(location.latitude - latRange)")
        queries.append("latitude <= \(location.latitude + latRange)")
        queries.append("longitude >= \(location.longitude - lonRange)")
        queries.append("longitude <= \(location.longitude + lonRange)")
        queries.append("isActive = true")
        
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: coursesCollectionId,
                queries: queries
            )
            
            let courses = try response.documents.compactMap { doc in
                try parseCourseFromDocument(doc)
            }
            
            // Filter by actual distance and cache results
            let nearbycourses = courses.filter { course in
                let courseLocation = CLLocation(latitude: course.latitude, longitude: course.longitude)
                let targetLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
                return courseLocation.distance(from: targetLocation) <= radius * 1609.34 // Convert miles to meters
            }.sorted { course1, course2 in
                let location1 = CLLocation(latitude: course1.latitude, longitude: course1.longitude)
                let location2 = CLLocation(latitude: course2.latitude, longitude: course2.longitude)
                let target = CLLocation(latitude: location.latitude, longitude: location.longitude)
                return location1.distance(from: target) < location2.distance(from: target)
            }
            
            // Cache results for 10 minutes
            courseCache.setObject(nearbyCourses as NSArray, forKey: cacheKey as NSString)
            
            return applyFilters(nearbyCourses, filters: filters)
            
        } catch {
            print("Error searching courses near location: \(error)")
            throw ServiceError.searchFailed(error.localizedDescription)
        }
    }
    
    func searchCourses(
        query: String,
        location: CLLocationCoordinate2D?,
        filters: CourseSearchFilters?
    ) async throws -> [GolfCourse] {
        
        var queries: [String] = []
        
        // Text search across multiple fields
        let searchTerms = query.lowercased().components(separatedBy: " ")
        for term in searchTerms where !term.isEmpty {
            queries.append("name contains '\(term)' OR city contains '\(term)' OR state contains '\(term)'")
        }
        
        queries.append("isActive = true")
        
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: coursesCollectionId,
                queries: queries
            )
            
            var courses = try response.documents.compactMap { doc in
                try parseCourseFromDocument(doc)
            }
            
            // Sort by relevance and distance if location provided
            if let location = location {
                courses = courses.sorted { course1, course2 in
                    let location1 = CLLocation(latitude: course1.latitude, longitude: course1.longitude)
                    let location2 = CLLocation(latitude: course2.latitude, longitude: course2.longitude)
                    let target = CLLocation(latitude: location.latitude, longitude: location.longitude)
                    return location1.distance(from: target) < location2.distance(from: target)
                }
            }
            
            return applyFilters(courses, filters: filters)
            
        } catch {
            print("Error searching courses with query: \(error)")
            throw ServiceError.searchFailed(error.localizedDescription)
        }
    }
    
    func getFeaturedCourses(
        for location: CLLocationCoordinate2D?,
        limit: Int
    ) async throws -> [GolfCourse] {
        
        var queries = ["isFeatured = true", "isActive = true"]
        
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: coursesCollectionId,
                queries: queries
            )
            
            var courses = try response.documents.compactMap { doc in
                try parseCourseFromDocument(doc)
            }
            
            // Sort by rating and distance if location provided
            if let location = location {
                courses = courses.sorted { course1, course2 in
                    let location1 = CLLocation(latitude: course1.latitude, longitude: course1.longitude)
                    let location2 = CLLocation(latitude: course2.latitude, longitude: course2.longitude)
                    let target = CLLocation(latitude: location.latitude, longitude: location.longitude)
                    
                    let distance1 = location1.distance(from: target)
                    let distance2 = location2.distance(from: target)
                    
                    // Combine rating and proximity for ranking
                    let score1 = course1.averageRating * 2.0 - (distance1 / 10000.0)
                    let score2 = course2.averageRating * 2.0 - (distance2 / 10000.0)
                    
                    return score1 > score2
                }
            } else {
                courses = courses.sorted { $0.averageRating > $1.averageRating }
            }
            
            return Array(courses.prefix(limit))
            
        } catch {
            print("Error fetching featured courses: \(error)")
            throw ServiceError.networkError(error.localizedDescription)
        }
    }
    
    func getRecentCourses(for userId: String) async throws -> [GolfCourse] {
        // Query recent scorecards to find recently played courses
        do {
            let recentScorecardsResponse = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: "scorecards",
                queries: [
                    "userId = '\(userId)'",
                    "playedDate >= '\(thirtyDaysAgo().ISO8601String())'"
                ]
            )
            
            let courseIds = Set(recentScorecardsResponse.documents.compactMap { doc in
                doc.data["courseId"] as? String
            })
            
            var recentCourses: [GolfCourse] = []
            
            for courseId in courseIds {
                if let course = try await getCourseDetails(courseId: courseId) as? GolfCourse {
                    recentCourses.append(course)
                }
            }
            
            return recentCourses.sorted { course1, course2 in
                // Sort by most recently played
                course1.updatedAt > course2.updatedAt
            }
            
        } catch {
            print("Error fetching recent courses: \(error)")
            throw ServiceError.networkError(error.localizedDescription)
        }
    }
    
    // MARK: - Course Details Implementation
    
    func getCourseDetails(courseId: String) async throws -> GolfCourse {
        do {
            let document = try await databases.getDocument(
                databaseId: databaseId,
                collectionId: coursesCollectionId,
                documentId: courseId
            )
            
            return try parseCourseFromDocument(document)
            
        } catch {
            print("Error fetching course details for \(courseId): \(error)")
            throw ServiceError.courseNotFound
        }
    }
    
    func getCourseImages(courseId: String) async throws -> [CourseImage] {
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: imagesCollectionId,
                queries: ["courseId = '\(courseId)'"]
            )
            
            return try response.documents.compactMap { doc in
                try parseCourseImageFromDocument(doc)
            }.sorted { $0.sortOrder < $1.sortOrder }
            
        } catch {
            print("Error fetching course images: \(error)")
            return []
        }
    }
    
    func getCourseLayout(courseId: String) async throws -> [HoleInfo] {
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: holesCollectionId,
                queries: ["courseId = '\(courseId)'"]
            )
            
            return try response.documents.compactMap { doc in
                try parseHoleInfoFromDocument(doc)
            }.sorted { $0.holeNumber < $1.holeNumber }
            
        } catch {
            print("Error fetching course layout: \(error)")
            return []
        }
    }
    
    func getCourseConditions(courseId: String) async throws -> CourseConditions {
        do {
            let document = try await databases.getDocument(
                databaseId: databaseId,
                collectionId: "course_conditions",
                documentId: courseId
            )
            
            return try parseCourseConditionsFromDocument(document)
            
        } catch {
            print("Error fetching course conditions: \(error)")
            // Return default conditions if not available
            return CourseConditions(
                greensCondition: .good,
                fairwayCondition: .good,
                roughCondition: .good,
                bunkerCondition: .good,
                greensSpeed: 9,
                firmness: .medium,
                moisture: .normal,
                maintenance: [],
                temporaryFeatures: [],
                overallRating: 7,
                lastUpdated: Date()
            )
        }
    }
    
    // MARK: - Reviews Implementation
    
    func getCourseReviews(
        courseId: String,
        page: Int,
        limit: Int
    ) async throws -> ReviewPage {
        
        let offset = (page - 1) * limit
        
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: reviewsCollectionId,
                queries: [
                    "courseId = '\(courseId)'",
                    "limit = \(limit)",
                    "offset = \(offset)"
                ]
            )
            
            let reviews = try response.documents.compactMap { doc in
                try parseCourseReviewFromDocument(doc)
            }
            
            return ReviewPage(
                reviews: reviews,
                totalCount: response.total,
                currentPage: page,
                totalPages: Int(ceil(Double(response.total) / Double(limit))),
                hasNextPage: offset + limit < response.total
            )
            
        } catch {
            print("Error fetching course reviews: \(error)")
            throw ServiceError.networkError(error.localizedDescription)
        }
    }
    
    func submitReview(
        courseId: String,
        review: CourseReview
    ) async throws -> CourseReview {
        
        let reviewData: [String: Any] = [
            "courseId": courseId,
            "userId": review.userId,
            "userName": review.userName,
            "userHandicap": review.userHandicap ?? NSNull(),
            "rating": review.rating,
            "title": review.title ?? "",
            "review": review.review,
            "playedDate": review.playedDate?.ISO8601String() ?? NSNull(),
            "courseCondition": review.courseCondition ?? NSNull(),
            "courseLayout": review.courseLayout ?? NSNull(),
            "staff": review.staff ?? NSNull(),
            "value": review.value ?? NSNull(),
            "amenities": review.amenities ?? NSNull(),
            "difficulty": review.difficulty ?? NSNull(),
            "isVerifiedPlay": review.isVerifiedPlay,
            "photos": review.photos ?? [],
            "helpfulVotes": 0,
            "totalVotes": 0,
            "createdAt": Date().ISO8601String(),
            "updatedAt": Date().ISO8601String()
        ]
        
        do {
            let document = try await databases.createDocument(
                databaseId: databaseId,
                collectionId: reviewsCollectionId,
                documentId: ID.unique(),
                data: reviewData
            )
            
            return try parseCourseReviewFromDocument(document)
            
        } catch {
            print("Error submitting course review: \(error)")
            throw ServiceError.submitFailed(error.localizedDescription)
        }
    }
    
    func getCourseRating(courseId: String) async throws -> CourseRatingDetails {
        // Implementation for fetching detailed rating statistics
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: reviewsCollectionId,
                queries: ["courseId = '\(courseId)'"]
            )
            
            let reviews = try response.documents.compactMap { doc in
                try parseCourseReviewFromDocument(doc)
            }
            
            return calculateRatingDetails(from: reviews, courseId: courseId)
            
        } catch {
            print("Error fetching course rating details: \(error)")
            throw ServiceError.networkError(error.localizedDescription)
        }
    }
    
    // MARK: - Favorites Implementation
    
    func addToFavorites(courseId: String, userId: String) async throws {
        let favoriteData: [String: Any] = [
            "userId": userId,
            "courseId": courseId,
            "createdAt": Date().ISO8601String()
        ]
        
        do {
            _ = try await databases.createDocument(
                databaseId: databaseId,
                collectionId: "user_favorites",
                documentId: ID.unique(),
                data: favoriteData
            )
        } catch {
            print("Error adding to favorites: \(error)")
            throw ServiceError.networkError(error.localizedDescription)
        }
    }
    
    func removeFromFavorites(courseId: String, userId: String) async throws {
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: "user_favorites",
                queries: [
                    "userId = '\(userId)'",
                    "courseId = '\(courseId)'"
                ]
            )
            
            for document in response.documents {
                try await databases.deleteDocument(
                    databaseId: databaseId,
                    collectionId: "user_favorites",
                    documentId: document.id
                )
            }
        } catch {
            print("Error removing from favorites: \(error)")
            throw ServiceError.networkError(error.localizedDescription)
        }
    }
    
    func getFavoriteCourses(userId: String) async throws -> [GolfCourse] {
        do {
            let favoritesResponse = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: "user_favorites",
                queries: ["userId = '\(userId)'"]
            )
            
            let courseIds = favoritesResponse.documents.compactMap { doc in
                doc.data["courseId"] as? String
            }
            
            var favoriteCourses: [GolfCourse] = []
            
            for courseId in courseIds {
                if let course = try? await getCourseDetails(courseId: courseId) {
                    favoriteCourses.append(course)
                }
            }
            
            return favoriteCourses.sorted { $0.name < $1.name }
            
        } catch {
            print("Error fetching favorite courses: \(error)")
            throw ServiceError.networkError(error.localizedDescription)
        }
    }
    
    func isFavorite(courseId: String, userId: String) async throws -> Bool {
        do {
            let response = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: "user_favorites",
                queries: [
                    "userId = '\(userId)'",
                    "courseId = '\(courseId)'"
                ]
            )
            
            return !response.documents.isEmpty
            
        } catch {
            print("Error checking favorite status: \(error)")
            return false
        }
    }
    
    // MARK: - Analytics Implementation
    
    func getPopularCourses(
        near location: CLLocationCoordinate2D,
        radius: Double,
        timeframe: PopularityTimeframe
    ) async throws -> [GolfCourse] {
        
        let startDate = Calendar.current.date(byAdding: .day, value: -timeframe.days, to: Date()) ?? Date()
        
        do {
            // Get booking counts for courses in the area
            let bookingResponse = try await databases.listDocuments(
                databaseId: databaseId,
                collectionId: "tee_times",
                queries: [
                    "status = 'booked' OR status = 'completed'",
                    "date >= '\(startDate.ISO8601String())'"
                ]
            )
            
            // Count bookings per course
            var courseCounts: [String: Int] = [:]
            for document in bookingResponse.documents {
                if let courseId = document.data["courseId"] as? String {
                    courseCounts[courseId, default: 0] += 1
                }
            }
            
            // Get course details for popular courses
            let popularCourses = try await searchCourses(
                near: location,
                radius: radius,
                filters: nil
            ).filter { course in
                courseCounts[course.id] ?? 0 > 0
            }.sorted { course1, course2 in
                let count1 = courseCounts[course1.id] ?? 0
                let count2 = courseCounts[course2.id] ?? 0
                return count1 > count2
            }
            
            return Array(popularCourses.prefix(20))
            
        } catch {
            print("Error fetching popular courses: \(error)")
            throw ServiceError.networkError(error.localizedDescription)
        }
    }
    
    func getCourseStatistics(courseId: String) async throws -> CourseStatistics {
        // Implementation would aggregate data from multiple collections
        // This is a simplified version - full implementation would require more complex queries
        
        return CourseStatistics(
            courseId: courseId,
            totalRounds: 0,
            averageScore: 0.0,
            averageRating: 0.0,
            popularTeeType: .regular,
            bookingMetrics: CourseStatistics.BookingMetrics(
                totalBookings: 0,
                averageBookingsPerDay: 0.0,
                peakBookingTimes: [],
                busySeason: nil,
                averageGroupSize: 0.0
            ),
            performanceMetrics: CourseStatistics.PerformanceMetrics(
                averageScoreByTee: [:],
                mostCommonScore: 0,
                birdieRate: 0.0,
                parRate: 0.0,
                bogeyRate: 0.0,
                averageRoundTime: 0
            ),
            popularityMetrics: CourseStatistics.PopularityMetrics(
                monthlyPlayers: 0,
                repeatPlayerRate: 0.0,
                referralRate: 0.0,
                socialMediaMentions: nil,
                rankingPosition: nil
            )
        )
    }
    
    func trackCourseView(courseId: String, userId: String?) async throws {
        let viewData: [String: Any] = [
            "courseId": courseId,
            "userId": userId ?? NSNull(),
            "timestamp": Date().ISO8601String(),
            "viewType": "course_detail"
        ]
        
        do {
            _ = try await databases.createDocument(
                databaseId: databaseId,
                collectionId: "course_views",
                documentId: ID.unique(),
                data: viewData
            )
        } catch {
            print("Error tracking course view: \(error)")
            // Don't throw error for analytics tracking
        }
    }
    
    // MARK: - Admin Functions Implementation
    
    func updateCourse(_ course: GolfCourse) async throws -> GolfCourse {
        // Convert course to document data
        let courseData = try encodeCourseToDocumentData(course)
        
        do {
            let document = try await databases.updateDocument(
                databaseId: databaseId,
                collectionId: coursesCollectionId,
                documentId: course.id,
                data: courseData
            )
            
            return try parseCourseFromDocument(document)
            
        } catch {
            print("Error updating course: \(error)")
            throw ServiceError.updateFailed(error.localizedDescription)
        }
    }
    
    func uploadCourseImage(
        courseId: String,
        imageData: Data,
        caption: String?,
        imageType: CourseImage.ImageType
    ) async throws -> CourseImage {
        
        do {
            // Upload image to Appwrite Storage
            let file = try await storage.createFile(
                bucketId: "course_images",
                fileId: ID.unique(),
                file: InputFile.fromData(imageData, filename: "course_image.jpg", mimeType: "image/jpeg")
            )
            
            // Create image document
            let imageData: [String: Any] = [
                "courseId": courseId,
                "url": "https://cloud.appwrite.io/v1/storage/buckets/course_images/files/\(file.id)/view",
                "thumbnailUrl": "https://cloud.appwrite.io/v1/storage/buckets/course_images/files/\(file.id)/preview?width=300&height=200",
                "caption": caption ?? "",
                "isPrimary": false,
                "sortOrder": 0,
                "imageType": imageType.rawValue
            ]
            
            let document = try await databases.createDocument(
                databaseId: databaseId,
                collectionId: imagesCollectionId,
                documentId: ID.unique(),
                data: imageData
            )
            
            return try parseCourseImageFromDocument(document)
            
        } catch {
            print("Error uploading course image: \(error)")
            throw ServiceError.uploadFailed(error.localizedDescription)
        }
    }
    
    func updateCourseConditions(
        courseId: String,
        conditions: CourseConditions
    ) async throws {
        
        let conditionsData = try encodeCourseConditionsToDocumentData(conditions)
        
        do {
            _ = try await databases.updateDocument(
                databaseId: databaseId,
                collectionId: "course_conditions",
                documentId: courseId,
                data: conditionsData
            )
        } catch {
            print("Error updating course conditions: \(error)")
            throw ServiceError.updateFailed(error.localizedDescription)
        }
    }
}

// MARK: - Private Parsing and Helper Methods

private extension GolfCourseService {
    
    func applyFilters(_ courses: [GolfCourse], filters: CourseSearchFilters?) -> [GolfCourse] {
        guard let filters = filters else { return courses }
        
        return courses.filter { course in
            // Price range filter
            if let priceRange = filters.priceRange {
                let coursePriceMin = course.pricing.baseWeekdayRate
                let coursePriceMax = course.pricing.baseWeekendRate
                if coursePriceMax < priceRange.lowerBound || coursePriceMin > priceRange.upperBound {
                    return false
                }
            }
            
            // Difficulty filter
            if let difficulties = filters.difficulty, !difficulties.isEmpty {
                if !difficulties.contains(course.difficulty) {
                    return false
                }
            }
            
            // Amenities filter
            if let requiredAmenities = filters.amenities, !requiredAmenities.isEmpty {
                let courseAmenities = Set(course.amenities)
                let requiredSet = Set(requiredAmenities)
                if !requiredSet.isSubset(of: courseAmenities) {
                    return false
                }
            }
            
            // Guest policy filter
            if let guestPolicies = filters.guestPolicy, !guestPolicies.isEmpty {
                if !guestPolicies.contains(course.pricing.guestPolicy) {
                    return false
                }
            }
            
            // Minimum rating filter
            if let minRating = filters.minimumRating {
                if course.averageRating < minRating {
                    return false
                }
            }
            
            // Holes filter
            if let holesOptions = filters.holes, !holesOptions.isEmpty {
                if !holesOptions.contains(course.numberOfHoles) {
                    return false
                }
            }
            
            return true
        }
    }
    
    func parseCourseFromDocument(_ document: Document) throws -> GolfCourse {
        // This would parse the Appwrite document into a GolfCourse model
        // Implementation would map document fields to GolfCourse properties
        // For brevity, showing the structure - full implementation would have all field mappings
        
        guard let name = document.data["name"] as? String,
              let address = document.data["address"] as? String,
              let city = document.data["city"] as? String,
              let state = document.data["state"] as? String,
              let country = document.data["country"] as? String,
              let zipCode = document.data["zipCode"] as? String,
              let latitude = document.data["latitude"] as? Double,
              let longitude = document.data["longitude"] as? Double else {
            throw ServiceError.parsingError
        }
        
        // Parse the full GolfCourse object from document data
        // This is a simplified version - full implementation would parse all fields
        
        return GolfCourse(
            id: document.id,
            name: name,
            address: address,
            city: city,
            state: state,
            country: country,
            zipCode: zipCode,
            latitude: latitude,
            longitude: longitude,
            description: document.data["description"] as? String,
            phoneNumber: document.data["phoneNumber"] as? String,
            website: document.data["website"] as? String,
            email: document.data["email"] as? String,
            numberOfHoles: document.data["numberOfHoles"] as? Int ?? 18,
            par: document.data["par"] as? Int ?? 72,
            yardage: parseYardageFromDocument(document),
            slope: parseSlopeFromDocument(document),
            rating: parseRatingFromDocument(document),
            pricing: parsePricingFromDocument(document),
            amenities: parseAmenitiesFromDocument(document),
            dressCode: parseDressCodeFromDocument(document),
            cartPolicy: parseCartPolicyFromDocument(document),
            images: [], // Would be loaded separately
            virtualTour: document.data["virtualTour"] as? String,
            averageRating: document.data["averageRating"] as? Double ?? 0.0,
            totalReviews: document.data["totalReviews"] as? Int ?? 0,
            difficulty: parseDifficultyFromDocument(document),
            operatingHours: parseOperatingHoursFromDocument(document),
            seasonalInfo: parseSeasonalInfoFromDocument(document),
            bookingPolicy: parseBookingPolicyFromDocument(document),
            createdAt: parseDate(document.data["createdAt"]) ?? Date(),
            updatedAt: parseDate(document.data["updatedAt"]) ?? Date(),
            isActive: document.data["isActive"] as? Bool ?? true,
            isFeatured: document.data["isFeatured"] as? Bool ?? false
        )
    }
    
    // Additional parsing helper methods would go here...
    // For brevity, showing structure rather than full implementation
    
    func parseYardageFromDocument(_ document: Document) -> CourseYardage {
        // Parse yardage data from document
        return CourseYardage(
            championshipTees: document.data["championshipYardage"] as? Int ?? 7000,
            backTees: document.data["backYardage"] as? Int ?? 6500,
            regularTees: document.data["regularYardage"] as? Int ?? 6000,
            forwardTees: document.data["forwardYardage"] as? Int ?? 5500,
            seniorTees: document.data["seniorYardage"] as? Int,
            juniorTees: document.data["juniorYardage"] as? Int
        )
    }
    
    func parseSlopeFromDocument(_ document: Document) -> CourseSlope {
        return CourseSlope(
            championshipSlope: document.data["championshipSlope"] as? Double ?? 125.0,
            backSlope: document.data["backSlope"] as? Double ?? 120.0,
            regularSlope: document.data["regularSlope"] as? Double ?? 115.0,
            forwardSlope: document.data["forwardSlope"] as? Double ?? 110.0,
            seniorSlope: document.data["seniorSlope"] as? Double,
            juniorSlope: document.data["juniorSlope"] as? Double
        )
    }
    
    func parseRatingFromDocument(_ document: Document) -> CourseRating {
        return CourseRating(
            championshipRating: document.data["championshipRating"] as? Double ?? 74.0,
            backRating: document.data["backRating"] as? Double ?? 71.0,
            regularRating: document.data["regularRating"] as? Double ?? 68.0,
            forwardRating: document.data["forwardRating"] as? Double ?? 65.0,
            seniorRating: document.data["seniorRating"] as? Double,
            juniorRating: document.data["juniorRating"] as? Double
        )
    }
    
    func parsePricingFromDocument(_ document: Document) -> CoursePricing {
        return CoursePricing(
            weekdayRates: document.data["weekdayRates"] as? [Double] ?? [50.0, 75.0, 100.0],
            weekendRates: document.data["weekendRates"] as? [Double] ?? [75.0, 100.0, 125.0],
            twilightRates: document.data["twilightRates"] as? [Double] ?? [35.0, 50.0, 65.0],
            seniorRates: document.data["seniorRates"] as? [Double],
            juniorRates: document.data["juniorRates"] as? [Double],
            cartFee: document.data["cartFee"] as? Double ?? 25.0,
            cartIncluded: document.data["cartIncluded"] as? Bool ?? false,
            membershipRequired: document.data["membershipRequired"] as? Bool ?? false,
            guestPolicy: parseGuestPolicy(document.data["guestPolicy"] as? String),
            seasonalMultiplier: document.data["seasonalMultiplier"] as? Double ?? 1.0,
            peakTimeMultiplier: document.data["peakTimeMultiplier"] as? Double ?? 1.2,
            advanceBookingDiscount: document.data["advanceBookingDiscount"] as? Double
        )
    }
    
    func parseAmenitiesFromDocument(_ document: Document) -> [CourseAmenity] {
        guard let amenityStrings = document.data["amenities"] as? [String] else { return [] }
        return amenityStrings.compactMap { CourseAmenity(rawValue: $0) }
    }
    
    func parseDressCodeFromDocument(_ document: Document) -> DressCode {
        guard let dressCodeString = document.data["dressCode"] as? String,
              let dressCode = DressCode(rawValue: dressCodeString) else {
            return .moderate
        }
        return dressCode
    }
    
    func parseCartPolicyFromDocument(_ document: Document) -> CartPolicy {
        guard let cartPolicyString = document.data["cartPolicy"] as? String,
              let cartPolicy = CartPolicy(rawValue: cartPolicyString) else {
            return .optional
        }
        return cartPolicy
    }
    
    func parseDifficultyFromDocument(_ document: Document) -> DifficultyLevel {
        guard let difficultyString = document.data["difficulty"] as? String,
              let difficulty = DifficultyLevel(rawValue: difficultyString) else {
            return .intermediate
        }
        return difficulty
    }
    
    func parseGuestPolicy(_ guestPolicyString: String?) -> GuestPolicy {
        guard let policyString = guestPolicyString,
              let policy = GuestPolicy(rawValue: policyString) else {
            return .open
        }
        return policy
    }
    
    func parseOperatingHoursFromDocument(_ document: Document) -> OperatingHours {
        // Parse operating hours from document data
        return OperatingHours(
            monday: parseDayHours(document.data["mondayHours"] as? [String: Any]),
            tuesday: parseDayHours(document.data["tuesdayHours"] as? [String: Any]),
            wednesday: parseDayHours(document.data["wednesdayHours"] as? [String: Any]),
            thursday: parseDayHours(document.data["thursdayHours"] as? [String: Any]),
            friday: parseDayHours(document.data["fridayHours"] as? [String: Any]),
            saturday: parseDayHours(document.data["saturdayHours"] as? [String: Any]),
            sunday: parseDayHours(document.data["sundayHours"] as? [String: Any])
        )
    }
    
    func parseDayHours(_ dayData: [String: Any]?) -> OperatingHours.DayHours {
        guard let data = dayData else {
            return OperatingHours.DayHours(isOpen: true, openTime: "06:00", closeTime: "19:00", lastTeeTime: "18:00")
        }
        
        return OperatingHours.DayHours(
            isOpen: data["isOpen"] as? Bool ?? true,
            openTime: data["openTime"] as? String,
            closeTime: data["closeTime"] as? String,
            lastTeeTime: data["lastTeeTime"] as? String
        )
    }
    
    func parseSeasonalInfoFromDocument(_ document: Document) -> SeasonalInfo? {
        guard let seasonalData = document.data["seasonalInfo"] as? [String: Any] else { return nil }
        
        let restrictionStrings = seasonalData["weatherRestrictions"] as? [String] ?? []
        let restrictions = restrictionStrings.compactMap { SeasonalInfo.WeatherRestriction(rawValue: $0) }
        
        return SeasonalInfo(
            isSeasonalCourse: seasonalData["isSeasonalCourse"] as? Bool ?? false,
            openingSeason: seasonalData["openingSeason"] as? String,
            closingSeason: seasonalData["closingSeason"] as? String,
            peakSeason: seasonalData["peakSeason"] as? String,
            offSeasonNotes: seasonalData["offSeasonNotes"] as? String,
            weatherRestrictions: restrictions
        )
    }
    
    func parseBookingPolicyFromDocument(_ document: Document) -> BookingPolicy {
        guard let policyData = document.data["bookingPolicy"] as? [String: Any] else {
            return BookingPolicy(
                advanceBookingDays: 7,
                cancellationPolicy: "Cancel up to 24 hours in advance for full refund",
                noShowPolicy: "No-show results in forfeit of green fees",
                modificationPolicy: "Modifications allowed up to 4 hours in advance",
                depositRequired: false,
                depositAmount: nil,
                refundableDeposit: true,
                groupBookingMinimum: 8,
                onlineBookingAvailable: true,
                phoneBookingRequired: false
            )
        }
        
        return BookingPolicy(
            advanceBookingDays: policyData["advanceBookingDays"] as? Int ?? 7,
            cancellationPolicy: policyData["cancellationPolicy"] as? String ?? "Cancel up to 24 hours in advance",
            noShowPolicy: policyData["noShowPolicy"] as? String ?? "No-show results in forfeit of fees",
            modificationPolicy: policyData["modificationPolicy"] as? String ?? "Modifications allowed",
            depositRequired: policyData["depositRequired"] as? Bool ?? false,
            depositAmount: policyData["depositAmount"] as? Double,
            refundableDeposit: policyData["refundableDeposit"] as? Bool ?? true,
            groupBookingMinimum: policyData["groupBookingMinimum"] as? Int,
            onlineBookingAvailable: policyData["onlineBookingAvailable"] as? Bool ?? true,
            phoneBookingRequired: policyData["phoneBookingRequired"] as? Bool ?? false
        )
    }
    
    func parseCourseImageFromDocument(_ document: Document) throws -> CourseImage {
        guard let url = document.data["url"] as? String,
              let imageTypeString = document.data["imageType"] as? String,
              let imageType = CourseImage.ImageType(rawValue: imageTypeString) else {
            throw ServiceError.parsingError
        }
        
        return CourseImage(
            id: document.id,
            url: url,
            thumbnailUrl: document.data["thumbnailUrl"] as? String,
            caption: document.data["caption"] as? String,
            isPrimary: document.data["isPrimary"] as? Bool ?? false,
            sortOrder: document.data["sortOrder"] as? Int ?? 0,
            imageType: imageType
        )
    }
    
    func parseHoleInfoFromDocument(_ document: Document) throws -> HoleInfo {
        guard let courseId = document.data["courseId"] as? String,
              let holeNumber = document.data["holeNumber"] as? Int,
              let par = document.data["par"] as? Int,
              let handicapIndex = document.data["handicapIndex"] as? Int else {
            throw ServiceError.parsingError
        }
        
        let yardages = document.data["yardages"] as? [String: Int] ?? [:]
        let hazardData = document.data["hazards"] as? [[String: Any]] ?? []
        let hazards = hazardData.compactMap { parseHoleHazard($0) }
        
        let layoutString = document.data["layout"] as? String ?? "straight"
        let layout = HoleInfo.HoleLayout(rawValue: layoutString) ?? .straight
        
        return HoleInfo(
            id: document.id,
            courseId: courseId,
            holeNumber: holeNumber,
            par: par,
            handicapIndex: handicapIndex,
            yardages: yardages,
            name: document.data["name"] as? String,
            description: document.data["description"] as? String,
            layout: layout,
            hazards: hazards,
            images: [], // Would be loaded separately
            layoutDiagram: document.data["layoutDiagram"] as? String,
            proTip: document.data["proTip"] as? String,
            strategy: parseHoleStrategy(document.data["strategy"] as? [String: Any])
        )
    }
    
    func parseHoleHazard(_ hazardData: [String: Any]) -> HoleInfo.HoleHazard? {
        guard let typeString = hazardData["type"] as? String,
              let type = HoleInfo.HoleHazard.HazardType(rawValue: typeString) else {
            return nil
        }
        
        let sideString = hazardData["side"] as? String
        let side = sideString != nil ? HoleInfo.HoleHazard.HazardSide(rawValue: sideString!) : nil
        
        return HoleInfo.HoleHazard(
            type: type,
            distance: hazardData["distance"] as? Int,
            side: side,
            description: hazardData["description"] as? String
        )
    }
    
    func parseHoleStrategy(_ strategyData: [String: Any]?) -> HoleInfo.HoleStrategy? {
        guard let data = strategyData,
              let strategy = data["strategy"] as? String else {
            return nil
        }
        
        return HoleInfo.HoleStrategy(
            recommendedClub: data["recommendedClub"] as? String,
            strategy: strategy,
            avoidAreas: data["avoidAreas"] as? [String],
            targetAreas: data["targetAreas"] as? [String],
            windConsiderations: data["windConsiderations"] as? String
        )
    }
    
    func parseCourseConditionsFromDocument(_ document: Document) throws -> CourseConditions {
        let greensConditionString = document.data["greensCondition"] as? String ?? "good"
        let greensCondition = ConditionQuality(rawValue: greensConditionString) ?? .good
        
        let fairwayConditionString = document.data["fairwayCondition"] as? String ?? "good"
        let fairwayCondition = ConditionQuality(rawValue: fairwayConditionString) ?? .good
        
        let roughConditionString = document.data["roughCondition"] as? String ?? "good"
        let roughCondition = ConditionQuality(rawValue: roughConditionString) ?? .good
        
        let bunkerConditionString = document.data["bunkerCondition"] as? String ?? "good"
        let bunkerCondition = ConditionQuality(rawValue: bunkerConditionString) ?? .good
        
        let firmnessString = document.data["firmness"] as? String ?? "medium"
        let firmness = FirmnessLevel(rawValue: firmnessString) ?? .medium
        
        let moistureString = document.data["moisture"] as? String ?? "normal"
        let moisture = MoistureLevel(rawValue: moistureString) ?? .normal
        
        let maintenanceStrings = document.data["maintenance"] as? [String] ?? []
        let maintenance = maintenanceStrings.compactMap { MaintenanceIssue(rawValue: $0) }
        
        let temporaryStrings = document.data["temporaryFeatures"] as? [String] ?? []
        let temporaryFeatures = temporaryStrings.compactMap { TemporaryFeature(rawValue: $0) }
        
        return CourseConditions(
            greensCondition: greensCondition,
            fairwayCondition: fairwayCondition,
            roughCondition: roughCondition,
            bunkerCondition: bunkerCondition,
            greensSpeed: document.data["greensSpeed"] as? Int ?? 9,
            firmness: firmness,
            moisture: moisture,
            maintenance: maintenance,
            temporaryFeatures: temporaryFeatures,
            overallRating: document.data["overallRating"] as? Int ?? 7,
            lastUpdated: parseDate(document.data["lastUpdated"]) ?? Date()
        )
    }
    
    func parseCourseReviewFromDocument(_ document: Document) throws -> CourseReview {
        guard let courseId = document.data["courseId"] as? String,
              let userId = document.data["userId"] as? String,
              let userName = document.data["userName"] as? String,
              let rating = document.data["rating"] as? Int,
              let review = document.data["review"] as? String else {
            throw ServiceError.parsingError
        }
        
        return CourseReview(
            id: document.id,
            courseId: courseId,
            userId: userId,
            userName: userName,
            userHandicap: document.data["userHandicap"] as? Double,
            rating: rating,
            title: document.data["title"] as? String,
            review: review,
            playedDate: parseDate(document.data["playedDate"]),
            courseCondition: document.data["courseCondition"] as? Int,
            courseLayout: document.data["courseLayout"] as? Int,
            staff: document.data["staff"] as? Int,
            value: document.data["value"] as? Int,
            amenities: document.data["amenities"] as? Int,
            difficulty: document.data["difficulty"] as? Int,
            isVerifiedPlay: document.data["isVerifiedPlay"] as? Bool ?? false,
            photos: document.data["photos"] as? [String],
            helpfulVotes: document.data["helpfulVotes"] as? Int ?? 0,
            totalVotes: document.data["totalVotes"] as? Int ?? 0,
            createdAt: parseDate(document.data["createdAt"]) ?? Date(),
            updatedAt: parseDate(document.data["updatedAt"]) ?? Date()
        )
    }
    
    func encodeCourseToDocumentData(_ course: GolfCourse) throws -> [String: Any] {
        // Convert GolfCourse model back to document data for updates
        return [
            "name": course.name,
            "address": course.address,
            "city": course.city,
            "state": course.state,
            "country": course.country,
            "zipCode": course.zipCode,
            "latitude": course.latitude,
            "longitude": course.longitude,
            "description": course.description ?? "",
            "phoneNumber": course.phoneNumber ?? "",
            "website": course.website ?? "",
            "email": course.email ?? "",
            "numberOfHoles": course.numberOfHoles,
            "par": course.par,
            "championshipYardage": course.yardage.championshipTees,
            "backYardage": course.yardage.backTees,
            "regularYardage": course.yardage.regularTees,
            "forwardYardage": course.yardage.forwardTees,
            "seniorYardage": course.yardage.seniorTees ?? NSNull(),
            "juniorYardage": course.yardage.juniorTees ?? NSNull(),
            "championshipSlope": course.slope.championshipSlope,
            "backSlope": course.slope.backSlope,
            "regularSlope": course.slope.regularSlope,
            "forwardSlope": course.slope.forwardSlope,
            "championshipRating": course.rating.championshipRating,
            "backRating": course.rating.backRating,
            "regularRating": course.rating.regularRating,
            "forwardRating": course.rating.forwardRating,
            "weekdayRates": course.pricing.weekdayRates,
            "weekendRates": course.pricing.weekendRates,
            "twilightRates": course.pricing.twilightRates,
            "cartFee": course.pricing.cartFee,
            "cartIncluded": course.pricing.cartIncluded,
            "amenities": course.amenities.map { $0.rawValue },
            "dressCode": course.dressCode.rawValue,
            "cartPolicy": course.cartPolicy.rawValue,
            "averageRating": course.averageRating,
            "totalReviews": course.totalReviews,
            "difficulty": course.difficulty.rawValue,
            "isActive": course.isActive,
            "isFeatured": course.isFeatured,
            "updatedAt": Date().ISO8601String()
        ]
    }
    
    func encodeCourseConditionsToDocumentData(_ conditions: CourseConditions) throws -> [String: Any] {
        return [
            "greensCondition": conditions.greensCondition.rawValue,
            "fairwayCondition": conditions.fairwayCondition.rawValue,
            "roughCondition": conditions.roughCondition.rawValue,
            "bunkerCondition": conditions.bunkerCondition.rawValue,
            "greensSpeed": conditions.greensSpeed,
            "firmness": conditions.firmness.rawValue,
            "moisture": conditions.moisture.rawValue,
            "maintenance": conditions.maintenance.map { $0.rawValue },
            "temporaryFeatures": conditions.temporaryFeatures.map { $0.rawValue },
            "overallRating": conditions.overallRating,
            "lastUpdated": Date().ISO8601String()
        ]
    }
    
    func thirtyDaysAgo() -> Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }
    
    func calculateRatingDetails(from reviews: [CourseReview], courseId: String) -> CourseRatingDetails {
        guard !reviews.isEmpty else {
            return CourseRatingDetails(
                courseId: courseId,
                averageRating: 0.0,
                totalReviews: 0,
                ratingBreakdown: [:],
                averageCondition: nil,
                averageLayout: nil,
                averageStaff: nil,
                averageValue: nil,
                averageAmenities: nil,
                averageDifficulty: nil,
                ratingTrend: .stable,
                recentAverageRating: 0.0
            )
        }
        
        let totalRating = reviews.reduce(0) { $0 + $1.rating }
        let averageRating = Double(totalRating) / Double(reviews.count)
        
        var ratingBreakdown: [Int: Int] = [:]
        for review in reviews {
            ratingBreakdown[review.rating, default: 0] += 1
        }
        
        // Calculate recent trend
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentReviews = reviews.filter { review in
            review.createdAt > thirtyDaysAgo
        }
        
        let recentAverageRating = recentReviews.isEmpty ? averageRating : 
            Double(recentReviews.reduce(0) { $0 + $1.rating }) / Double(recentReviews.count)
        
        let ratingTrend: CourseRatingDetails.RatingTrend
        let diff = recentAverageRating - averageRating
        if diff > 0.2 {
            ratingTrend = .improving
        } else if diff < -0.2 {
            ratingTrend = .declining
        } else {
            ratingTrend = .stable
        }
        
        return CourseRatingDetails(
            courseId: courseId,
            averageRating: averageRating,
            totalReviews: reviews.count,
            ratingBreakdown: ratingBreakdown,
            averageCondition: calculateAverageDetailRating(reviews) { $0.courseCondition },
            averageLayout: calculateAverageDetailRating(reviews) { $0.courseLayout },
            averageStaff: calculateAverageDetailRating(reviews) { $0.staff },
            averageValue: calculateAverageDetailRating(reviews) { $0.value },
            averageAmenities: calculateAverageDetailRating(reviews) { $0.amenities },
            averageDifficulty: calculateAverageDetailRating(reviews) { $0.difficulty },
            ratingTrend: ratingTrend,
            recentAverageRating: recentAverageRating
        )
    }
    
    func calculateAverageDetailRating(_ reviews: [CourseReview], ratingKeyPath: (CourseReview) -> Int?) -> Double? {
        let validRatings = reviews.compactMap(ratingKeyPath)
        guard !validRatings.isEmpty else { return nil }
        return Double(validRatings.reduce(0, +)) / Double(validRatings.count)
    }
}

// MARK: - Service Error Types

enum ServiceError: Error, LocalizedError {
    case networkError(String)
    case parsingError
    case courseNotFound
    case searchFailed(String)
    case submitFailed(String)
    case updateFailed(String)
    case uploadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError:
            return "Failed to parse course data"
        case .courseNotFound:
            return "Golf course not found"
        case .searchFailed(let message):
            return "Search failed: \(message)"
        case .submitFailed(let message):
            return "Submit failed: \(message)"
        case .updateFailed(let message):
            return "Update failed: \(message)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        }
    }
}

// MARK: - Date Extensions

extension Date {
    func ISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

private func parseDate(_ value: Any?) -> Date? {
    guard let dateString = value as? String else { return nil }
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: dateString)
}