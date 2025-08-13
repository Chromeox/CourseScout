import Foundation
import Appwrite

// MARK: - Course Data API Protocol

protocol CourseDataAPIProtocol {
    // MARK: - Basic Course Operations
    func getCourses(request: CourseListRequest) async throws -> CourseListResponse
    func getCourseDetails(courseId: String, request: CourseDetailRequest?) async throws -> CourseDetailResponse
    func searchCourses(request: CourseSearchRequest) async throws -> CourseSearchResponse
    
    // MARK: - Course Filtering and Discovery
    func getCoursesNearby(request: NearbyCoursesRequest) async throws -> CourseListResponse
    func filterCoursesByAmenities(request: AmenityFilterRequest) async throws -> CourseListResponse
    func getCoursesByPriceRange(request: PriceRangeRequest) async throws -> CourseListResponse
    
    // MARK: - Course Metadata
    func getCourseAvailability(courseId: String, request: AvailabilityRequest) async throws -> AvailabilityResponse
    func getCourseReviews(courseId: String, request: ReviewsRequest?) async throws -> ReviewsResponse
    func getCoursePhotos(courseId: String, request: PhotosRequest?) async throws -> PhotosResponse
    
    // MARK: - Course Recommendations
    func getRecommendedCourses(request: RecommendationRequest) async throws -> CourseListResponse
    func getFeaturedCourses(request: FeaturedCoursesRequest?) async throws -> CourseListResponse
    func getPopularCourses(request: PopularCoursesRequest?) async throws -> CourseListResponse
}

// MARK: - Course Data API Implementation

@MainActor
class CourseDataAPI: CourseDataAPIProtocol, ObservableObject {
    // MARK: - Properties
    
    private let appwriteClient: Client
    private let databases: Databases
    private let golfCourseService: GolfCourseServiceProtocol
    private let locationService: LocationServiceProtocol
    
    @Published var isLoading: Bool = false
    @Published var lastRequest: Date?
    
    // MARK: - Performance Tracking
    
    private var requestMetrics: [String: RequestMetrics] = [:]
    private let metricsQueue = DispatchQueue(label: "CourseDataAPIMetrics", qos: .utility)
    
    // MARK: - Caching
    
    private let cache = NSCache<NSString, CachedResponse>()
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    init(appwriteClient: Client, golfCourseService: GolfCourseServiceProtocol, locationService: LocationServiceProtocol) {
        self.appwriteClient = appwriteClient
        self.databases = Databases(appwriteClient)
        self.golfCourseService = golfCourseService
        self.locationService = locationService
        
        setupCache()
    }
    
    // MARK: - Basic Course Operations
    
    func getCourses(request: CourseListRequest) async throws -> CourseListResponse {
        let startTime = Date()
        isLoading = true
        defer { isLoading = false }
        
        // Check cache first
        let cacheKey = "courses_\(request.cacheKey)"
        if let cachedResponse = getCachedResponse(key: cacheKey) as? CourseListResponse {
            await recordRequestMetric(endpoint: "/courses", duration: Date().timeIntervalSince(startTime), cached: true)
            return cachedResponse
        }
        
        do {
            // Build query parameters
            var query = Query.orderAsc("name")
            
            if let limit = request.limit {
                query = Query.limit(limit)
            }
            
            if let offset = request.offset {
                query = Query.offset(offset)
            }
            
            // Apply filters
            if let state = request.state {
                query = Query.equal("state", value: state)
            }
            
            if let minRating = request.minRating {
                query = Query.greaterThanEqual("rating", value: minRating)
            }
            
            let queries = [query]
            
            // Fetch courses from database
            let documents = try await databases.listDocuments(
                databaseId: Configuration.appwriteProjectId,
                collectionId: "golf_courses",
                queries: queries
            )
            
            // Convert to course models
            let courses = try documents.documents.compactMap { document in
                try parseGolfCourse(from: document)
            }
            
            // Apply additional processing
            let processedCourses = try await enrichCourseData(courses, request: request)
            
            let response = CourseListResponse(
                courses: processedCourses,
                totalCount: documents.total,
                hasMore: (request.offset ?? 0) + courses.count < documents.total,
                filters: request.appliedFilters,
                requestId: UUID().uuidString,
                generatedAt: Date()
            )
            
            // Cache the response
            setCachedResponse(key: cacheKey, response: response)
            
            await recordRequestMetric(endpoint: "/courses", duration: Date().timeIntervalSince(startTime), cached: false)
            lastRequest = Date()
            
            return response
            
        } catch {
            await recordRequestMetric(endpoint: "/courses", duration: Date().timeIntervalSince(startTime), cached: false, error: error)
            throw CourseDataAPIError.courseFetchFailed(error.localizedDescription)
        }
    }
    
    func getCourseDetails(courseId: String, request: CourseDetailRequest?) async throws -> CourseDetailResponse {
        let startTime = Date()
        isLoading = true
        defer { isLoading = false }
        
        // Check cache first
        let cacheKey = "course_details_\(courseId)"
        if let cachedResponse = getCachedResponse(key: cacheKey) as? CourseDetailResponse {
            await recordRequestMetric(endpoint: "/courses/\(courseId)", duration: Date().timeIntervalSince(startTime), cached: true)
            return cachedResponse
        }
        
        do {
            // Fetch course document
            let document = try await databases.getDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: "golf_courses",
                documentId: courseId
            )
            
            guard let course = try parseGolfCourse(from: document) else {
                throw CourseDataAPIError.courseNotFound(courseId)
            }
            
            // Fetch additional details based on request
            let includeReviews = request?.includeReviews ?? false
            let includePhotos = request?.includePhotos ?? false
            let includeAvailability = request?.includeAvailability ?? false
            let includeWeather = request?.includeWeather ?? false
            
            // Parallel fetch of additional data
            async let reviewsTask = includeReviews ? getCourseReviewsInternal(courseId: courseId) : nil
            async let photosTask = includePhotos ? getCoursePhotosInternal(courseId: courseId) : nil
            async let availabilityTask = includeAvailability ? getCourseAvailabilityInternal(courseId: courseId) : nil
            async let weatherTask = includeWeather ? getCourseWeatherInternal(course: course) : nil
            
            let reviews = try await reviewsTask
            let photos = try await photosTask
            let availability = try await availabilityTask
            let weather = try await weatherTask
            
            let response = CourseDetailResponse(
                course: course,
                reviews: reviews,
                photos: photos,
                availability: availability,
                weather: weather,
                nearbyAttractions: try await getNearbyAttractions(course: course),
                requestId: UUID().uuidString,
                generatedAt: Date()
            )
            
            // Cache the response
            setCachedResponse(key: cacheKey, response: response)
            
            await recordRequestMetric(endpoint: "/courses/\(courseId)", duration: Date().timeIntervalSince(startTime), cached: false)
            lastRequest = Date()
            
            return response
            
        } catch {
            await recordRequestMetric(endpoint: "/courses/\(courseId)", duration: Date().timeIntervalSince(startTime), cached: false, error: error)
            throw CourseDataAPIError.courseDetailsFailed(error.localizedDescription)
        }
    }
    
    func searchCourses(request: CourseSearchRequest) async throws -> CourseSearchResponse {
        let startTime = Date()
        isLoading = true
        defer { isLoading = false }
        
        // Check cache first
        let cacheKey = "search_\(request.cacheKey)"
        if let cachedResponse = getCachedResponse(key: cacheKey) as? CourseSearchResponse {
            await recordRequestMetric(endpoint: "/courses/search", duration: Date().timeIntervalSince(startTime), cached: true)
            return cachedResponse
        }
        
        do {
            var queries: [String] = []
            
            // Text search
            if let searchTerm = request.query, !searchTerm.isEmpty {
                queries.append(Query.search("name", value: searchTerm))
            }
            
            // Location-based search
            if let location = request.location {
                queries.append(contentsOf: buildLocationQueries(location: location, radius: request.radius))
            }
            
            // Filters
            if let minRating = request.minRating {
                queries.append(Query.greaterThanEqual("rating", value: minRating))
            }
            
            if let maxPrice = request.maxPrice {
                queries.append(Query.lessThanEqual("green_fee_weekday", value: maxPrice))
            }
            
            if let amenities = request.amenities, !amenities.isEmpty {
                queries.append(contentsOf: buildAmenitiesQueries(amenities))
            }
            
            // Apply pagination
            if let limit = request.limit {
                queries.append(Query.limit(limit))
            }
            
            if let offset = request.offset {
                queries.append(Query.offset(offset))
            }
            
            // Apply sorting
            switch request.sortBy {
            case .rating:
                queries.append(Query.orderDesc("rating"))
            case .price:
                queries.append(Query.orderAsc("green_fee_weekday"))
            case .distance:
                // Distance sorting handled post-fetch if location provided
                queries.append(Query.orderAsc("name"))
            case .name, .none:
                queries.append(Query.orderAsc("name"))
            }
            
            // Execute search
            let documents = try await databases.listDocuments(
                databaseId: Configuration.appwriteProjectId,
                collectionId: "golf_courses",
                queries: queries
            )
            
            // Convert and process results
            var courses = try documents.documents.compactMap { document in
                try parseGolfCourse(from: document)
            }
            
            // Apply post-processing filters
            courses = try await applyAdvancedFilters(courses: courses, request: request)
            
            // Sort by distance if location provided
            if let location = request.location, request.sortBy == .distance {
                courses = sortCoursesByDistance(courses: courses, to: location)
            }
            
            let response = CourseSearchResponse(
                courses: courses,
                totalCount: documents.total,
                searchQuery: request.query,
                appliedFilters: request.appliedFilters,
                suggestedFilters: generateSuggestedFilters(from: courses),
                facets: generateSearchFacets(from: courses),
                hasMore: (request.offset ?? 0) + courses.count < documents.total,
                requestId: UUID().uuidString,
                generatedAt: Date()
            )
            
            // Cache the response
            setCachedResponse(key: cacheKey, response: response)
            
            await recordRequestMetric(endpoint: "/courses/search", duration: Date().timeIntervalSince(startTime), cached: false)
            lastRequest = Date()
            
            return response
            
        } catch {
            await recordRequestMetric(endpoint: "/courses/search", duration: Date().timeIntervalSince(startTime), cached: false, error: error)
            throw CourseDataAPIError.searchFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Course Filtering and Discovery
    
    func getCoursesNearby(request: NearbyCoursesRequest) async throws -> CourseListResponse {
        let courseListRequest = CourseListRequest(
            location: request.location,
            radius: request.radius,
            limit: request.limit,
            offset: request.offset,
            minRating: request.minRating
        )
        
        return try await getCourses(request: courseListRequest)
    }
    
    func filterCoursesByAmenities(request: AmenityFilterRequest) async throws -> CourseListResponse {
        let searchRequest = CourseSearchRequest(
            amenities: request.amenities,
            limit: request.limit,
            offset: request.offset
        )
        
        let searchResponse = try await searchCourses(request: searchRequest)
        
        return CourseListResponse(
            courses: searchResponse.courses,
            totalCount: searchResponse.totalCount,
            hasMore: searchResponse.hasMore,
            filters: searchResponse.appliedFilters,
            requestId: searchResponse.requestId,
            generatedAt: searchResponse.generatedAt
        )
    }
    
    func getCoursesByPriceRange(request: PriceRangeRequest) async throws -> CourseListResponse {
        let searchRequest = CourseSearchRequest(
            minPrice: request.minPrice,
            maxPrice: request.maxPrice,
            priceType: request.priceType,
            limit: request.limit,
            offset: request.offset
        )
        
        let searchResponse = try await searchCourses(request: searchRequest)
        
        return CourseListResponse(
            courses: searchResponse.courses,
            totalCount: searchResponse.totalCount,
            hasMore: searchResponse.hasMore,
            filters: searchResponse.appliedFilters,
            requestId: searchResponse.requestId,
            generatedAt: searchResponse.generatedAt
        )
    }
    
    // MARK: - Course Metadata
    
    func getCourseAvailability(courseId: String, request: AvailabilityRequest) async throws -> AvailabilityResponse {
        // Integrate with booking system to get real availability
        let availability = try await getCourseAvailabilityInternal(courseId: courseId, request: request)
        
        return AvailabilityResponse(
            courseId: courseId,
            availability: availability,
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    func getCourseReviews(courseId: String, request: ReviewsRequest?) async throws -> ReviewsResponse {
        let reviews = try await getCourseReviewsInternal(courseId: courseId, request: request)
        
        return ReviewsResponse(
            courseId: courseId,
            reviews: reviews.reviews,
            averageRating: reviews.averageRating,
            totalCount: reviews.totalCount,
            ratingDistribution: reviews.ratingDistribution,
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    func getCoursePhotos(courseId: String, request: PhotosRequest?) async throws -> PhotosResponse {
        let photos = try await getCoursePhotosInternal(courseId: courseId, request: request)
        
        return PhotosResponse(
            courseId: courseId,
            photos: photos,
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    // MARK: - Course Recommendations
    
    func getRecommendedCourses(request: RecommendationRequest) async throws -> CourseListResponse {
        // Use ML/AI algorithms for personalized recommendations
        let recommendations = try await generatePersonalizedRecommendations(request: request)
        
        return CourseListResponse(
            courses: recommendations,
            totalCount: recommendations.count,
            hasMore: false,
            filters: ["recommendation_type": request.type.rawValue],
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    func getFeaturedCourses(request: FeaturedCoursesRequest?) async throws -> CourseListResponse {
        let queries = [
            Query.equal("is_featured", value: true),
            Query.orderDesc("featured_priority"),
            Query.limit(request?.limit ?? 10)
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "golf_courses",
            queries: queries
        )
        
        let courses = try documents.documents.compactMap { document in
            try parseGolfCourse(from: document)
        }
        
        return CourseListResponse(
            courses: courses,
            totalCount: documents.total,
            hasMore: false,
            filters: ["featured": "true"],
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    func getPopularCourses(request: PopularCoursesRequest?) async throws -> CourseListResponse {
        let timeFrame = request?.timeFrame ?? .lastMonth
        let startDate = getStartDate(for: timeFrame)
        
        // Get courses sorted by booking frequency or rating in the time frame
        let queries = [
            Query.greaterThanEqual("last_booking_date", value: startDate.timeIntervalSince1970),
            Query.orderDesc("booking_count"),
            Query.limit(request?.limit ?? 20)
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "golf_courses",
            queries: queries
        )
        
        let courses = try documents.documents.compactMap { document in
            try parseGolfCourse(from: document)
        }
        
        return CourseListResponse(
            courses: courses,
            totalCount: documents.total,
            hasMore: false,
            filters: ["popular": timeFrame.rawValue],
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    // MARK: - Helper Methods
    
    private func setupCache() {
        cache.countLimit = 200
        cache.totalCostLimit = 1024 * 1024 * 50 // 50MB
    }
    
    private func getCachedResponse(key: String) -> Any? {
        let cacheKey = NSString(string: key)
        guard let cached = cache.object(forKey: cacheKey) else {
            return nil
        }
        
        // Check if expired
        if Date().timeIntervalSince(cached.timestamp) > cacheTTL {
            cache.removeObject(forKey: cacheKey)
            return nil
        }
        
        return cached.response
    }
    
    private func setCachedResponse(key: String, response: Any) {
        let cacheKey = NSString(string: key)
        let cached = CachedResponse(response: response, timestamp: Date())
        cache.setObject(cached, forKey: cacheKey)
    }
    
    private func parseGolfCourse(from document: Document) throws -> GolfCourse? {
        let data = document.data
        
        guard let name = data["name"] as? String,
              let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double else {
            return nil
        }
        
        return GolfCourse(
            id: document.id,
            name: name,
            description: data["description"] as? String ?? "",
            address: parseAddress(from: data),
            location: GolfCourseLocation(
                latitude: latitude,
                longitude: longitude,
                city: data["city"] as? String ?? "",
                state: data["state"] as? String ?? "",
                country: data["country"] as? String ?? ""
            ),
            rating: data["rating"] as? Double ?? 0.0,
            reviewCount: data["review_count"] as? Int ?? 0,
            holes: data["holes"] as? Int ?? 18,
            par: data["par"] as? Int ?? 72,
            yardage: data["yardage"] as? Int,
            difficulty: parseDifficulty(from: data),
            greenFees: parseGreenFees(from: data),
            amenities: parseAmenities(from: data),
            photos: parsePhotos(from: data),
            contact: parseContact(from: data),
            hours: parseHours(from: data),
            isPublic: data["is_public"] as? Bool ?? true,
            isFeatured: data["is_featured"] as? Bool ?? false,
            lastUpdated: Date(timeIntervalSince1970: data["updated_at"] as? Double ?? 0)
        )
    }
    
    private func enrichCourseData(_ courses: [GolfCourse], request: CourseListRequest) async throws -> [GolfCourse] {
        // Add distance calculation if location provided
        guard let userLocation = request.location else {
            return courses
        }
        
        return courses.map { course in
            let distance = calculateDistance(
                from: userLocation,
                to: CLLocation(latitude: course.location.latitude, longitude: course.location.longitude)
            )
            
            var enrichedCourse = course
            enrichedCourse.distanceFromUser = distance
            return enrichedCourse
        }
    }
    
    private func buildLocationQueries(location: CLLocation, radius: Double?) -> [String] {
        let radiusInMeters = radius ?? 25000 // Default 25km
        
        // Approximate bounding box for initial filtering
        let latDelta = (radiusInMeters / 111000.0) // Approximate meters to degrees
        let lonDelta = latDelta / cos(location.coordinate.latitude * .pi / 180)
        
        return [
            Query.greaterThanEqual("latitude", value: location.coordinate.latitude - latDelta),
            Query.lessThanEqual("latitude", value: location.coordinate.latitude + latDelta),
            Query.greaterThanEqual("longitude", value: location.coordinate.longitude - lonDelta),
            Query.lessThanEqual("longitude", value: location.coordinate.longitude + lonDelta)
        ]
    }
    
    private func buildAmenitiesQueries(_ amenities: [String]) -> [String] {
        return amenities.map { amenity in
            Query.search("amenities", value: amenity)
        }
    }
    
    private func applyAdvancedFilters(courses: [GolfCourse], request: CourseSearchRequest) async throws -> [GolfCourse] {
        var filteredCourses = courses
        
        // Distance filtering (precise calculation)
        if let location = request.location, let radius = request.radius {
            filteredCourses = filteredCourses.filter { course in
                let courseLocation = CLLocation(latitude: course.location.latitude, longitude: course.location.longitude)
                return location.distance(from: courseLocation) <= radius
            }
        }
        
        // Advanced filters
        if let difficulty = request.difficulty {
            filteredCourses = filteredCourses.filter { $0.difficulty == difficulty }
        }
        
        if let isPublic = request.isPublic {
            filteredCourses = filteredCourses.filter { $0.isPublic == isPublic }
        }
        
        return filteredCourses
    }
    
    private func sortCoursesByDistance(courses: [GolfCourse], to location: CLLocation) -> [GolfCourse] {
        return courses.sorted { course1, course2 in
            let location1 = CLLocation(latitude: course1.location.latitude, longitude: course1.location.longitude)
            let location2 = CLLocation(latitude: course2.location.latitude, longitude: course2.location.longitude)
            
            return location.distance(from: location1) < location.distance(from: location2)
        }
    }
    
    private func calculateDistance(from: CLLocation, to: CLLocation) -> Double {
        return from.distance(from: to)
    }
    
    private func recordRequestMetric(endpoint: String, duration: TimeInterval, cached: Bool, error: Error? = nil) async {
        await metricsQueue.async {
            let metric = RequestMetrics(
                endpoint: endpoint,
                duration: duration,
                cached: cached,
                error: error?.localizedDescription,
                timestamp: Date()
            )
            
            if var existingMetrics = self.requestMetrics[endpoint] {
                existingMetrics.totalRequests += 1
                existingMetrics.totalDuration += duration
                existingMetrics.averageDuration = existingMetrics.totalDuration / Double(existingMetrics.totalRequests)
                
                if cached {
                    existingMetrics.cacheHits += 1
                }
                
                if error != nil {
                    existingMetrics.errorCount += 1
                }
                
                self.requestMetrics[endpoint] = existingMetrics
            } else {
                self.requestMetrics[endpoint] = RequestMetrics(
                    endpoint: endpoint,
                    duration: duration,
                    cached: cached,
                    totalRequests: 1,
                    totalDuration: duration,
                    averageDuration: duration,
                    cacheHits: cached ? 1 : 0,
                    errorCount: error != nil ? 1 : 0,
                    error: error?.localizedDescription,
                    timestamp: Date()
                )
            }
        }
    }
    
    // Additional helper methods for parsing and data processing...
    
    private func parseAddress(from data: [String: Any]) -> Address {
        return Address(
            street: data["street"] as? String ?? "",
            city: data["city"] as? String ?? "",
            state: data["state"] as? String ?? "",
            zipCode: data["zip_code"] as? String ?? "",
            country: data["country"] as? String ?? ""
        )
    }
    
    private func parseDifficulty(from data: [String: Any]) -> CourseDifficulty {
        let difficultyString = data["difficulty"] as? String ?? "intermediate"
        return CourseDifficulty(rawValue: difficultyString) ?? .intermediate
    }
    
    private func parseGreenFees(from data: [String: Any]) -> GreenFees {
        return GreenFees(
            weekday: data["green_fee_weekday"] as? Double ?? 0,
            weekend: data["green_fee_weekend"] as? Double ?? 0,
            twilight: data["green_fee_twilight"] as? Double,
            senior: data["green_fee_senior"] as? Double,
            junior: data["green_fee_junior"] as? Double
        )
    }
    
    private func parseAmenities(from data: [String: Any]) -> [String] {
        return data["amenities"] as? [String] ?? []
    }
    
    private func parsePhotos(from data: [String: Any]) -> [String] {
        return data["photos"] as? [String] ?? []
    }
    
    private func parseContact(from data: [String: Any]) -> ContactInfo {
        return ContactInfo(
            phone: data["phone"] as? String,
            email: data["email"] as? String,
            website: data["website"] as? String
        )
    }
    
    private func parseHours(from data: [String: Any]) -> [String: String] {
        return data["hours"] as? [String: String] ?? [:]
    }
    
    private func getCourseReviewsInternal(courseId: String, request: ReviewsRequest? = nil) async throws -> CourseReviewsData? {
        // Fetch reviews from reviews service or database
        // This is a simplified implementation
        return nil
    }
    
    private func getCoursePhotosInternal(courseId: String, request: PhotosRequest? = nil) async throws -> [CoursePhoto]? {
        // Fetch photos from media service or database
        // This is a simplified implementation
        return nil
    }
    
    private func getCourseAvailabilityInternal(courseId: String, request: AvailabilityRequest? = nil) async throws -> [TeeTimeSlot]? {
        // Fetch availability from booking service
        // This is a simplified implementation
        return nil
    }
    
    private func getCourseWeatherInternal(course: GolfCourse) async throws -> WeatherInfo? {
        // Fetch weather data for course location
        // This is a simplified implementation
        return nil
    }
    
    private func getNearbyAttractions(course: GolfCourse) async throws -> [NearbyAttraction]? {
        // Fetch nearby attractions, restaurants, hotels
        // This is a simplified implementation
        return nil
    }
    
    private func generatePersonalizedRecommendations(request: RecommendationRequest) async throws -> [GolfCourse] {
        // Use ML algorithms for personalized recommendations
        // This is a simplified implementation
        return []
    }
    
    private func generateSuggestedFilters(from courses: [GolfCourse]) -> [String: [String]] {
        // Analyze courses and suggest relevant filters
        var suggestions: [String: [String]] = [:]
        
        let uniqueStates = Set(courses.map { $0.location.state }).filter { !$0.isEmpty }
        if uniqueStates.count > 1 {
            suggestions["states"] = Array(uniqueStates).sorted()
        }
        
        let priceRanges = courses.map { $0.greenFees.weekday }
        let minPrice = priceRanges.min() ?? 0
        let maxPrice = priceRanges.max() ?? 0
        
        if maxPrice > minPrice {
            suggestions["price_ranges"] = [
                "$\(Int(minPrice))-$\(Int(minPrice + (maxPrice - minPrice) / 3))",
                "$\(Int(minPrice + (maxPrice - minPrice) / 3))-$\(Int(minPrice + 2 * (maxPrice - minPrice) / 3))",
                "$\(Int(minPrice + 2 * (maxPrice - minPrice) / 3))-$\(Int(maxPrice))"
            ]
        }
        
        return suggestions
    }
    
    private func generateSearchFacets(from courses: [GolfCourse]) -> SearchFacets {
        let stateCount = Dictionary(grouping: courses) { $0.location.state }
            .mapValues { $0.count }
            .filter { !$0.key.isEmpty }
        
        let difficultyCount = Dictionary(grouping: courses) { $0.difficulty.rawValue }
            .mapValues { $0.count }
        
        let publicPrivateCount = Dictionary(grouping: courses) { $0.isPublic ? "public" : "private" }
            .mapValues { $0.count }
        
        return SearchFacets(
            states: stateCount,
            difficulties: difficultyCount,
            courseTypes: publicPrivateCount,
            priceRanges: generatePriceRangeFacets(from: courses)
        )
    }
    
    private func generatePriceRangeFacets(from courses: [GolfCourse]) -> [String: Int] {
        let prices = courses.map { $0.greenFees.weekday }
        let ranges = [
            ("$0-$50", 0...50),
            ("$51-$100", 51...100),
            ("$101-$150", 101...150),
            ("$151+", 151...Double.greatestFiniteMagnitude)
        ]
        
        var facets: [String: Int] = [:]
        for (label, range) in ranges {
            facets[label] = prices.filter { range.contains($0) }.count
        }
        
        return facets
    }
    
    private func getStartDate(for timeFrame: PopularityTimeFrame) -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch timeFrame {
        case .lastWeek:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .lastQuarter:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .lastYear:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
    }
}

// MARK: - Data Models and Supporting Types

// Request/Response models and supporting types would be defined here...
// (These are referenced in the implementation above)

struct CourseListRequest {
    let location: CLLocation?
    let radius: Double?
    let limit: Int?
    let offset: Int?
    let state: String?
    let minRating: Double?
    let appliedFilters: [String: String]
    
    init(location: CLLocation? = nil, radius: Double? = nil, limit: Int? = nil, offset: Int? = nil, state: String? = nil, minRating: Double? = nil, appliedFilters: [String: String] = [:]) {
        self.location = location
        self.radius = radius
        self.limit = limit
        self.offset = offset
        self.state = state
        self.minRating = minRating
        self.appliedFilters = appliedFilters
    }
    
    var cacheKey: String {
        let components = [
            location?.coordinate.latitude.description,
            location?.coordinate.longitude.description,
            radius?.description,
            limit?.description,
            offset?.description,
            state,
            minRating?.description
        ].compactMap { $0 }
        
        return components.joined(separator: "_")
    }
}

struct CourseListResponse {
    let courses: [GolfCourse]
    let totalCount: Int
    let hasMore: Bool
    let filters: [String: String]
    let requestId: String
    let generatedAt: Date
}

// Additional model structs would be defined here for all request/response types...

struct CachedResponse {
    let response: Any
    let timestamp: Date
}

struct RequestMetrics {
    let endpoint: String
    var duration: TimeInterval
    let cached: Bool
    var totalRequests: Int = 0
    var totalDuration: TimeInterval = 0
    var averageDuration: TimeInterval = 0
    var cacheHits: Int = 0
    var errorCount: Int = 0
    let error: String?
    let timestamp: Date
}

// MARK: - Errors

enum CourseDataAPIError: Error, LocalizedError {
    case courseFetchFailed(String)
    case courseNotFound(String)
    case courseDetailsFailed(String)
    case searchFailed(String)
    case invalidRequest(String)
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .courseFetchFailed(let message):
            return "Failed to fetch courses: \(message)"
        case .courseNotFound(let courseId):
            return "Course not found: \(courseId)"
        case .courseDetailsFailed(let message):
            return "Failed to fetch course details: \(message)"
        case .searchFailed(let message):
            return "Course search failed: \(message)"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        }
    }
}

// Additional supporting models, enums, and types would be defined here...
// This includes all the referenced types like CourseDetailRequest, CourseSearchRequest, etc.

// MARK: - Mock Course Data API (for development/testing)

class MockCourseDataAPI: CourseDataAPIProtocol {
    private let mockCourses = [
        GolfCourse(
            id: "course_1",
            name: "Pine Valley Golf Club",
            description: "Championship golf course with beautiful views",
            address: Address(street: "123 Golf Dr", city: "Pine Valley", state: "NJ", zipCode: "08021", country: "USA"),
            location: GolfCourseLocation(latitude: 40.7128, longitude: -74.0060, city: "Pine Valley", state: "NJ", country: "USA"),
            rating: 4.5,
            reviewCount: 250,
            holes: 18,
            par: 72,
            yardage: 7200,
            difficulty: .challenging,
            greenFees: GreenFees(weekday: 150, weekend: 200, twilight: 120, senior: 120, junior: 80),
            amenities: ["pro_shop", "restaurant", "driving_range", "putting_green"],
            photos: ["https://example.com/photo1.jpg"],
            contact: ContactInfo(phone: "(555) 123-4567", email: "info@pinevalley.com", website: "https://pinevalley.com"),
            hours: ["monday": "6:00 AM - 8:00 PM", "tuesday": "6:00 AM - 8:00 PM"],
            isPublic: true,
            isFeatured: true,
            lastUpdated: Date()
        )
    ]
    
    func getCourses(request: CourseListRequest) async throws -> CourseListResponse {
        return CourseListResponse(
            courses: mockCourses,
            totalCount: mockCourses.count,
            hasMore: false,
            filters: request.appliedFilters,
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    func getCourseDetails(courseId: String, request: CourseDetailRequest?) async throws -> CourseDetailResponse {
        guard let course = mockCourses.first(where: { $0.id == courseId }) else {
            throw CourseDataAPIError.courseNotFound(courseId)
        }
        
        return CourseDetailResponse(
            course: course,
            reviews: nil,
            photos: nil,
            availability: nil,
            weather: nil,
            nearbyAttractions: nil,
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    func searchCourses(request: CourseSearchRequest) async throws -> CourseSearchResponse {
        var filteredCourses = mockCourses
        
        if let query = request.query, !query.isEmpty {
            filteredCourses = filteredCourses.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        
        return CourseSearchResponse(
            courses: filteredCourses,
            totalCount: filteredCourses.count,
            searchQuery: request.query,
            appliedFilters: request.appliedFilters,
            suggestedFilters: [:],
            facets: SearchFacets(states: [:], difficulties: [:], courseTypes: [:], priceRanges: [:]),
            hasMore: false,
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    // Implement remaining methods with mock data...
    
    func getCoursesNearby(request: NearbyCoursesRequest) async throws -> CourseListResponse {
        return try await getCourses(request: CourseListRequest())
    }
    
    func filterCoursesByAmenities(request: AmenityFilterRequest) async throws -> CourseListResponse {
        return try await getCourses(request: CourseListRequest())
    }
    
    func getCoursesByPriceRange(request: PriceRangeRequest) async throws -> CourseListResponse {
        return try await getCourses(request: CourseListRequest())
    }
    
    func getCourseAvailability(courseId: String, request: AvailabilityRequest) async throws -> AvailabilityResponse {
        return AvailabilityResponse(
            courseId: courseId,
            availability: [],
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    func getCourseReviews(courseId: String, request: ReviewsRequest?) async throws -> ReviewsResponse {
        return ReviewsResponse(
            courseId: courseId,
            reviews: [],
            averageRating: 4.5,
            totalCount: 0,
            ratingDistribution: [:],
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    func getCoursePhotos(courseId: String, request: PhotosRequest?) async throws -> PhotosResponse {
        return PhotosResponse(
            courseId: courseId,
            photos: [],
            requestId: UUID().uuidString,
            generatedAt: Date()
        )
    }
    
    func getRecommendedCourses(request: RecommendationRequest) async throws -> CourseListResponse {
        return try await getCourses(request: CourseListRequest())
    }
    
    func getFeaturedCourses(request: FeaturedCoursesRequest?) async throws -> CourseListResponse {
        return try await getCourses(request: CourseListRequest())
    }
    
    func getPopularCourses(request: PopularCoursesRequest?) async throws -> CourseListResponse {
        return try await getCourses(request: CourseListRequest())
    }
}