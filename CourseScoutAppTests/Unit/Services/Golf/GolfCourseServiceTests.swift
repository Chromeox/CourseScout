import XCTest
import Appwrite
import Combine
@testable import GolfFinderSwiftUI

class GolfCourseServiceTests: XCTestCase {
    
    var sut: GolfCourseService!
    var mockAppwriteClient: Client!
    var testContainer: ServiceContainer!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        super.setUp()
        
        TestEnvironmentManager.shared.setupTestEnvironment()
        
        mockAppwriteClient = Client()
            .setEndpoint("https://test-appwrite.local/v1")
            .setProject("test-project-id")
            .setKey("test-api-key")
        
        testContainer = ServiceContainer(appwriteClient: mockAppwriteClient, environment: .test)
        sut = GolfCourseService(appwriteClient: mockAppwriteClient)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithError() throws {
        sut = nil
        mockAppwriteClient = nil
        testContainer = nil
        cancellables = nil
        
        TestEnvironmentManager.shared.teardownTestEnvironment()
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testGolfCourseService_WhenInitialized_ShouldBeReady() {
        // Given & When (setup in setUp)
        
        // Then
        XCTAssertNotNil(sut)
    }
    
    // MARK: - Course Search Tests
    
    func testSearchCourses_WithValidLocation_ShouldReturnCourses() async throws {
        // Given
        let latitude = 37.7749
        let longitude = -122.4194
        let radius = 10.0
        
        // When
        let courses = try await sut.searchCourses(
            latitude: latitude,
            longitude: longitude,
            radius: radius
        )
        
        // Then
        XCTAssertNotNil(courses)
        XCTAssertGreaterThan(courses.count, 0)
        
        // Verify courses are within radius
        for course in courses {
            let distance = calculateDistance(
                from: (latitude, longitude),
                to: (course.latitude, course.longitude)
            )
            XCTAssertLessThanOrEqual(distance, radius * 1.1, "Course should be within search radius (with 10% tolerance)")
        }
    }
    
    func testSearchCourses_WithZeroRadius_ShouldThrowError() async throws {
        // Given
        let latitude = 37.7749
        let longitude = -122.4194
        let radius = 0.0
        
        // When & Then
        do {
            _ = try await sut.searchCourses(latitude: latitude, longitude: longitude, radius: radius)
            XCTFail("Expected error for zero radius")
        } catch {
            // Expected error
            XCTAssertTrue(error is GolfCourseServiceError)
        }
    }
    
    func testSearchCourses_WithInvalidCoordinates_ShouldThrowError() async throws {
        // Given
        let invalidLatitude = 200.0 // Invalid latitude
        let validLongitude = -122.4194
        let radius = 10.0
        
        // When & Then
        do {
            _ = try await sut.searchCourses(latitude: invalidLatitude, longitude: validLongitude, radius: radius)
            XCTFail("Expected error for invalid coordinates")
        } catch {
            XCTAssertTrue(error is GolfCourseServiceError)
        }
    }
    
    // MARK: - Course Retrieval Tests
    
    func testGetCourseById_WithValidId_ShouldReturnCourse() async throws {
        // Given
        let mockCourse = TestDataFactory.shared.createMockGolfCourse()
        let courseId = mockCourse.id
        
        // When
        let retrievedCourse = try await sut.getCourseById(courseId)
        
        // Then
        XCTAssertNotNil(retrievedCourse)
        XCTAssertEqual(retrievedCourse.id, courseId)
        XCTAssertEqual(retrievedCourse.name, mockCourse.name)
        XCTAssertEqual(retrievedCourse.latitude, mockCourse.latitude, accuracy: 0.001)
        XCTAssertEqual(retrievedCourse.longitude, mockCourse.longitude, accuracy: 0.001)
    }
    
    func testGetCourseById_WithInvalidId_ShouldThrowError() async throws {
        // Given
        let invalidId = "invalid-course-id"
        
        // When & Then
        do {
            _ = try await sut.getCourseById(invalidId)
            XCTFail("Expected error for invalid course ID")
        } catch {
            XCTAssertTrue(error is GolfCourseServiceError)
        }
    }
    
    // MARK: - Course Filtering Tests
    
    func testFilterCourses_ByRating_ShouldReturnFilteredResults() async throws {
        // Given
        let courses = TestDataFactory.shared.createMockGolfCourses(count: 20)
        let minRating = 4.0
        
        // When
        let filteredCourses = sut.filterCourses(courses, by: .rating(minimum: minRating))
        
        // Then
        XCTAssertGreaterThan(filteredCourses.count, 0)
        for course in filteredCourses {
            XCTAssertGreaterThanOrEqual(course.rating, minRating)
        }
    }
    
    func testFilterCourses_ByPriceRange_ShouldReturnFilteredResults() async throws {
        // Given
        let courses = TestDataFactory.shared.createMockGolfCourses(count: 20)
        let priceRange = "$"
        
        // When
        let filteredCourses = sut.filterCourses(courses, by: .priceRange(priceRange))
        
        // Then
        XCTAssertGreaterThan(filteredCourses.count, 0)
        for course in filteredCourses {
            XCTAssertEqual(course.priceRange, priceRange)
        }
    }
    
    func testFilterCourses_ByDifficulty_ShouldReturnFilteredResults() async throws {
        // Given
        let courses = TestDataFactory.shared.createMockGolfCourses(count: 20)
        let difficulty = "Intermediate"
        
        // When
        let filteredCourses = sut.filterCourses(courses, by: .difficulty(difficulty))
        
        // Then
        XCTAssertGreaterThan(filteredCourses.count, 0)
        for course in filteredCourses {
            XCTAssertEqual(course.difficulty, difficulty)
        }
    }
    
    func testFilterCourses_ByAmenities_ShouldReturnFilteredResults() async throws {
        // Given
        let courses = TestDataFactory.shared.createMockGolfCourses(count: 20)
        let requiredAmenities = ["Pro Shop", "Restaurant"]
        
        // When
        let filteredCourses = sut.filterCourses(courses, by: .amenities(requiredAmenities))
        
        // Then
        XCTAssertGreaterThan(filteredCourses.count, 0)
        for course in filteredCourses {
            for amenity in requiredAmenities {
                XCTAssertTrue(course.amenities.contains(amenity), "Course should have required amenity: \(amenity)")
            }
        }
    }
    
    // MARK: - Course Sorting Tests
    
    func testSortCourses_ByDistance_ShouldReturnSortedResults() async throws {
        // Given
        let courses = TestDataFactory.shared.createMockGolfCourses(count: 10)
        let userLocation = (latitude: 37.7749, longitude: -122.4194)
        
        // When
        let sortedCourses = sut.sortCourses(courses, by: .distance(from: userLocation))
        
        // Then
        XCTAssertEqual(sortedCourses.count, courses.count)
        
        // Verify sorting order
        for i in 0..<sortedCourses.count - 1 {
            let distance1 = calculateDistance(
                from: userLocation,
                to: (sortedCourses[i].latitude, sortedCourses[i].longitude)
            )
            let distance2 = calculateDistance(
                from: userLocation,
                to: (sortedCourses[i + 1].latitude, sortedCourses[i + 1].longitude)
            )
            XCTAssertLessThanOrEqual(distance1, distance2, "Courses should be sorted by distance")
        }
    }
    
    func testSortCourses_ByRating_ShouldReturnSortedResults() async throws {
        // Given
        let courses = TestDataFactory.shared.createMockGolfCourses(count: 10)
        
        // When
        let sortedCourses = sut.sortCourses(courses, by: .rating)
        
        // Then
        XCTAssertEqual(sortedCourses.count, courses.count)
        
        // Verify sorting order (highest rating first)
        for i in 0..<sortedCourses.count - 1 {
            XCTAssertGreaterThanOrEqual(
                sortedCourses[i].rating,
                sortedCourses[i + 1].rating,
                "Courses should be sorted by rating (descending)"
            )
        }
    }
    
    func testSortCourses_ByPrice_ShouldReturnSortedResults() async throws {
        // Given
        let courses = TestDataFactory.shared.createMockGolfCourses(count: 10)
        
        // When
        let sortedCourses = sut.sortCourses(courses, by: .price)
        
        // Then
        XCTAssertEqual(sortedCourses.count, courses.count)
        
        // Verify sorting order (lowest price first)
        let priceOrder = ["$", "$$", "$$$", "$$$$"]
        for i in 0..<sortedCourses.count - 1 {
            let price1Index = priceOrder.firstIndex(of: sortedCourses[i].priceRange) ?? 0
            let price2Index = priceOrder.firstIndex(of: sortedCourses[i + 1].priceRange) ?? 0
            XCTAssertLessThanOrEqual(price1Index, price2Index, "Courses should be sorted by price")
        }
    }
    
    // MARK: - Tee Time Tests
    
    func testGetAvailableTeeTimes_WithValidCourseId_ShouldReturnTeeTimes() async throws {
        // Given
        let course = TestDataFactory.shared.createMockGolfCourse()
        let date = Date()
        
        // When
        let teeTimes = try await sut.getAvailableTeeTimes(courseId: course.id, date: date)
        
        // Then
        XCTAssertNotNil(teeTimes)
        XCTAssertGreaterThan(teeTimes.count, 0)
        
        for teeTime in teeTimes {
            XCTAssertEqual(teeTime.golfCourseId, course.id)
            XCTAssertEqual(Calendar.current.isDate(teeTime.dateTime, inSameDayAs: date), true)
            XCTAssertEqual(teeTime.status, .available)
        }
    }
    
    func testGetAvailableTeeTimes_WithPastDate_ShouldReturnEmpty() async throws {
        // Given
        let course = TestDataFactory.shared.createMockGolfCourse()
        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        
        // When
        let teeTimes = try await sut.getAvailableTeeTimes(courseId: course.id, date: pastDate)
        
        // Then
        XCTAssertEqual(teeTimes.count, 0, "No tee times should be available for past dates")
    }
    
    // MARK: - Performance Tests
    
    func testSearchCourses_Performance_ShouldCompleteUnder500ms() async throws {
        // Given
        let latitude = 37.7749
        let longitude = -122.4194
        let radius = 25.0
        
        // When
        let startTime = Date()
        let courses = try await sut.searchCourses(latitude: latitude, longitude: longitude, radius: radius)
        let executionTime = Date().timeIntervalSince(startTime) * 1000
        
        // Then
        XCTAssertLessThan(executionTime, 500.0, "Course search should complete within 500ms")
        XCTAssertGreaterThan(courses.count, 0)
    }
    
    func testConcurrentCourseRequests_ShouldHandleSimultaneousRequests() async throws {
        // Given
        let requestCount = 20
        let courseIds = (0..<requestCount).map { "test-course-\($0)" }
        
        // When
        let startTime = Date()
        let results = await withTaskGroup(of: (String, Result<GolfCourse, Error>).self) { group in
            for courseId in courseIds {
                group.addTask {
                    do {
                        let course = try await self.sut.getCourseById(courseId)
                        return (courseId, .success(course))
                    } catch {
                        return (courseId, .failure(error))
                    }
                }
            }
            
            var results: [(String, Result<GolfCourse, Error>)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        let totalTime = Date().timeIntervalSince(startTime) * 1000
        
        // Then
        XCTAssertEqual(results.count, requestCount)
        XCTAssertLessThan(totalTime, 2000.0, "20 concurrent course requests should complete within 2 seconds")
        
        let successCount = results.filter { 
            if case .success = $1 { return true }
            return false
        }.count
        
        XCTAssertGreaterThan(successCount, 0, "At least some concurrent requests should succeed")
    }
    
    // MARK: - Caching Tests
    
    func testGetCourseById_WithCaching_ShouldImprovePerformance() async throws {
        // Given
        let courseId = "test-course-123"
        
        // When - First request (should cache)
        let startTime1 = Date()
        _ = try await sut.getCourseById(courseId)
        let firstRequestTime = Date().timeIntervalSince(startTime1) * 1000
        
        // Second request (should use cache)
        let startTime2 = Date()
        _ = try await sut.getCourseById(courseId)
        let secondRequestTime = Date().timeIntervalSince(startTime2) * 1000
        
        // Then
        XCTAssertLessThan(secondRequestTime, firstRequestTime * 0.5, "Cached request should be at least 50% faster")
    }
    
    // MARK: - Error Handling Tests
    
    func testSearchCourses_WithNetworkError_ShouldThrowServiceError() async throws {
        // Given
        let invalidClient = Client().setEndpoint("https://invalid-endpoint.local")
        let invalidSut = GolfCourseService(appwriteClient: invalidClient)
        
        // When & Then
        do {
            _ = try await invalidSut.searchCourses(latitude: 37.7749, longitude: -122.4194, radius: 10.0)
            XCTFail("Expected network error")
        } catch {
            XCTAssertTrue(error is GolfCourseServiceError)
        }
    }
    
    // MARK: - Data Validation Tests
    
    func testValidateCourseData_WithValidCourse_ShouldPass() {
        // Given
        let course = TestDataFactory.shared.createMockGolfCourse()
        
        // When
        let isValid = sut.validateCourseData(course)
        
        // Then
        XCTAssertTrue(isValid)
    }
    
    func testValidateCourseData_WithInvalidCoordinates_ShouldFail() {
        // Given
        let invalidCourse = TestDataFactory.shared.createMockGolfCourse(
            latitude: 200.0, // Invalid latitude
            longitude: -122.4194
        )
        
        // When
        let isValid = sut.validateCourseData(invalidCourse)
        
        // Then
        XCTAssertFalse(isValid)
    }
    
    func testValidateCourseData_WithEmptyName_ShouldFail() {
        // Given
        let invalidCourse = TestDataFactory.shared.createMockGolfCourse(name: "")
        
        // When
        let isValid = sut.validateCourseData(invalidCourse)
        
        // Then
        XCTAssertFalse(isValid)
    }
    
    // MARK: - Memory Management Tests
    
    func testGolfCourseService_MemoryUsage_ShouldNotLeak() async throws {
        // Given
        let initialMemory = getCurrentMemoryUsage()
        
        // When - Process many course searches
        for _ in 0..<100 {
            try? await sut.searchCourses(
                latitude: Double.random(in: -90...90),
                longitude: Double.random(in: -180...180),
                radius: Double.random(in: 1...50)
            )
        }
        
        // Force garbage collection
        autoreleasepool {
            // Empty autoreleasepool to trigger cleanup
        }
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Then
        XCTAssertLessThan(memoryIncrease, 100_000_000, "Memory increase should be less than 100MB after 100 searches")
    }
    
    // MARK: - Helper Methods
    
    private func calculateDistance(
        from: (latitude: Double, longitude: Double),
        to: (latitude: Double, longitude: Double)
    ) -> Double {
        let earthRadius = 6371.0 // Earth's radius in kilometers
        
        let lat1Rad = from.latitude * .pi / 180
        let lat2Rad = to.latitude * .pi / 180
        let deltaLatRad = (to.latitude - from.latitude) * .pi / 180
        let deltaLonRad = (to.longitude - from.longitude) * .pi / 180
        
        let a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLonRad / 2) * sin(deltaLonRad / 2)
        
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }
    
    private func getCurrentMemoryUsage() -> Int64 {
        let info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        }
        
        return 0
    }
}

// MARK: - Service Extensions for Testing

extension GolfCourseService {
    
    func filterCourses(_ courses: [GolfCourse], by filter: CourseFilter) -> [GolfCourse] {
        switch filter {
        case .rating(let minimum):
            return courses.filter { $0.rating >= minimum }
        case .priceRange(let range):
            return courses.filter { $0.priceRange == range }
        case .difficulty(let difficulty):
            return courses.filter { $0.difficulty == difficulty }
        case .amenities(let requiredAmenities):
            return courses.filter { course in
                requiredAmenities.allSatisfy { course.amenities.contains($0) }
            }
        }
    }
    
    func sortCourses(_ courses: [GolfCourse], by sortOption: CourseSortOption) -> [GolfCourse] {
        switch sortOption {
        case .distance(let userLocation):
            return courses.sorted { course1, course2 in
                let distance1 = calculateDistanceForSorting(
                    from: userLocation,
                    to: (course1.latitude, course1.longitude)
                )
                let distance2 = calculateDistanceForSorting(
                    from: userLocation,
                    to: (course2.latitude, course2.longitude)
                )
                return distance1 < distance2
            }
        case .rating:
            return courses.sorted { $0.rating > $1.rating }
        case .price:
            let priceOrder = ["$": 0, "$$": 1, "$$$": 2, "$$$$": 3]
            return courses.sorted { course1, course2 in
                let price1 = priceOrder[course1.priceRange] ?? 0
                let price2 = priceOrder[course2.priceRange] ?? 0
                return price1 < price2
            }
        }
    }
    
    func validateCourseData(_ course: GolfCourse) -> Bool {
        // Validate coordinates
        guard course.latitude >= -90 && course.latitude <= 90 else { return false }
        guard course.longitude >= -180 && course.longitude <= 180 else { return false }
        
        // Validate name
        guard !course.name.isEmpty else { return false }
        
        // Validate rating
        guard course.rating >= 0 && course.rating <= 5 else { return false }
        
        // Validate holes
        guard course.holes > 0 && course.holes <= 18 else { return false }
        
        return true
    }
    
    private func calculateDistanceForSorting(
        from: (latitude: Double, longitude: Double),
        to: (latitude: Double, longitude: Double)
    ) -> Double {
        let earthRadius = 6371.0
        
        let lat1Rad = from.latitude * .pi / 180
        let lat2Rad = to.latitude * .pi / 180
        let deltaLatRad = (to.latitude - from.latitude) * .pi / 180
        let deltaLonRad = (to.longitude - from.longitude) * .pi / 180
        
        let a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLonRad / 2) * sin(deltaLonRad / 2)
        
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }
}

// MARK: - Test Enums

enum CourseFilter {
    case rating(minimum: Double)
    case priceRange(String)
    case difficulty(String)
    case amenities([String])
}

enum CourseSortOption {
    case distance(from: (latitude: Double, longitude: Double))
    case rating
    case price
}

// MARK: - Mock Service Error

enum GolfCourseServiceError: Error, LocalizedError {
    case invalidRadius
    case invalidCoordinates
    case courseNotFound
    case networkError
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .invalidRadius:
            return "Search radius must be greater than 0"
        case .invalidCoordinates:
            return "Invalid latitude or longitude coordinates"
        case .courseNotFound:
            return "Golf course not found"
        case .networkError:
            return "Network connection error"
        case .invalidData:
            return "Invalid course data"
        }
    }
}