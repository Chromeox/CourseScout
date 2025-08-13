import Foundation
import Combine
import CoreLocation
import SwiftUI

// MARK: - Branded Course Discovery View Model

@MainActor
class BrandedCourseDiscoveryViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var courses: [SharedGolfCourse] = []
    @Published private(set) var filteredCourses: [SharedGolfCourse] = []
    @Published private(set) var featuredCourses: [SharedGolfCourse] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var hasMoreCourses = true
    
    // MARK: - Private Properties
    private var searchQuery = ""
    private var currentFilter: CourseFilter = .all
    private var currentPage = 0
    private let pageSize = 20
    private var userLocation: CLLocation?
    
    // MARK: - Services
    @ServiceInjected(GolfCourseServiceProtocol.self)
    private var courseService: GolfCourseServiceProtocol
    
    @ServiceInjected(LocationServiceProtocol.self)
    private var locationService: LocationServiceProtocol
    
    @ServiceInjected(AnalyticsServiceProtocol.self)
    private var analyticsService: AnalyticsServiceProtocol
    
    @ServiceInjected(TenantConfigurationServiceProtocol.self)
    private var tenantService: TenantConfigurationServiceProtocol
    
    @ServiceInjected(CacheServiceProtocol.self)
    private var cacheService: CacheServiceProtocol
    
    // MARK: - Reactive Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Analytics Tracking
    private var viewStartTime = Date()
    private var coursesViewed: Set<String> = []
    private var searchQueries: [String] = []
    
    // MARK: - Initialization
    
    init() {
        setupLocationUpdates()
        setupTenantUpdates()
    }
    
    // MARK: - Course Loading
    
    func loadCourses() async {
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        currentPage = 0
        hasMoreCourses = true
        
        do {
            // Try cache first
            if let cachedCourses: [SharedGolfCourse] = try await cacheService.retrieve(key: getCacheKey()) {
                courses = cachedCourses
                await processLoadedCourses()
                
                // Load fresh data in background
                Task {
                    await loadFreshCourses()
                }
            } else {
                await loadFreshCourses()
            }
        } catch {
            await loadFreshCourses()
        }
        
        isLoading = false
    }
    
    private func loadFreshCourses() async {
        do {
            let tenantId = tenantService.currentTenant?.id
            let loadedCourses = try await courseService.searchCourses(
                query: "",
                location: userLocation?.coordinate,
                radius: 50000, // 50km
                limit: pageSize,
                offset: currentPage * pageSize
            )
            
            // Convert to SharedGolfCourse
            let sharedCourses = loadedCourses.map { SharedGolfCourse(from: $0) }
            courses = sharedCourses
            
            // Cache the results
            try await cacheService.store(key: getCacheKey(), value: sharedCourses, ttl: 300) // 5 minutes
            
            await processLoadedCourses()
            
            analyticsService.track("courses_loaded", parameters: [
                "count": courses.count,
                "page": currentPage,
                "tenant_id": tenantId ?? "none",
                "location_enabled": userLocation != nil
            ])
            
        } catch {
            self.error = error
            analyticsService.track("courses_load_error", parameters: [
                "error": error.localizedDescription,
                "page": currentPage
            ])
        }
    }
    
    func loadMoreCourses() async {
        guard !isLoading && hasMoreCourses else { return }
        
        isLoading = true
        currentPage += 1
        
        do {
            let tenantId = tenantService.currentTenant?.id
            let newCourses = try await courseService.searchCourses(
                query: searchQuery,
                location: userLocation?.coordinate,
                radius: 50000,
                limit: pageSize,
                offset: currentPage * pageSize
            )
            
            if newCourses.count < pageSize {
                hasMoreCourses = false
            }
            
            let sharedCourses = newCourses.map { SharedGolfCourse(from: $0) }
            courses.append(contentsOf: sharedCourses)
            
            await processLoadedCourses()
            
            analyticsService.track("more_courses_loaded", parameters: [
                "count": newCourses.count,
                "page": currentPage,
                "tenant_id": tenantId ?? "none"
            ])
            
        } catch {
            currentPage -= 1 // Revert page increment
            self.error = error
            analyticsService.track("more_courses_load_error", parameters: [
                "error": error.localizedDescription,
                "page": currentPage
            ])
        }
        
        isLoading = false
    }
    
    func refreshCourses() async {
        // Clear cache
        try? await cacheService.remove(key: getCacheKey())
        
        currentPage = 0
        hasMoreCourses = true
        await loadCourses()
        
        analyticsService.track("courses_refreshed", parameters: [
            "tenant_id": tenantService.currentTenant?.id ?? "none"
        ])
    }
    
    // MARK: - Search and Filtering
    
    func searchCourses(query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !searchQuery.isEmpty {
            searchQueries.append(searchQuery)
            analyticsService.track("course_search", parameters: [
                "query": searchQuery,
                "tenant_id": tenantService.currentTenant?.id ?? "none"
            ])
        }
        
        applyFiltersAndSearch()
    }
    
    func filterCourses(by filter: CourseFilter) {
        currentFilter = filter
        
        analyticsService.track("course_filter", parameters: [
            "filter": filter.rawValue,
            "tenant_id": tenantService.currentTenant?.id ?? "none"
        ])
        
        applyFiltersAndSearch()
    }
    
    private func applyFiltersAndSearch() {
        var filtered = courses
        
        // Apply search query
        if !searchQuery.isEmpty {
            filtered = filtered.filter { course in
                course.name.localizedCaseInsensitiveContains(searchQuery) ||
                course.city.localizedCaseInsensitiveContains(searchQuery) ||
                course.state.localizedCaseInsensitiveContains(searchQuery)
            }
        }
        
        // Apply filters
        switch currentFilter {
        case .all:
            break // No additional filtering
            
        case .nearby:
            if let userLocation = userLocation {
                filtered = filtered.sorted { course1, course2 in
                    let distance1 = userLocation.distance(from: CLLocation(
                        latitude: course1.latitude,
                        longitude: course1.longitude
                    ))
                    let distance2 = userLocation.distance(from: CLLocation(
                        latitude: course2.latitude,
                        longitude: course2.longitude
                    ))
                    return distance1 < distance2
                }
                // Take only first 10 nearest
                filtered = Array(filtered.prefix(10))
            }
            
        case .featured:
            filtered = filtered.filter { $0.averageRating >= 4.5 }
            
        case .highRated:
            filtered = filtered.filter { $0.averageRating >= 4.0 }
            
        case .hasGPS:
            filtered = filtered.filter { $0.hasGPS }
            
        case .hasRestaurant:
            filtered = filtered.filter { $0.hasRestaurant }
        }
        
        filteredCourses = filtered
    }
    
    // MARK: - Featured Courses
    
    private func updateFeaturedCourses() {
        featuredCourses = Array(courses.filter { $0.averageRating >= 4.5 }.prefix(5))
    }
    
    // MARK: - Analytics
    
    func trackCourseSelection(_ course: SharedGolfCourse) async {
        coursesViewed.insert(course.id)
        
        analyticsService.track("course_selected", parameters: [
            "course_id": course.id,
            "course_name": course.name,
            "rating": course.averageRating,
            "tenant_id": tenantService.currentTenant?.id ?? "none",
            "view_mode": "discovery",
            "search_query": searchQuery.isEmpty ? "none" : searchQuery,
            "filter": currentFilter.rawValue
        ])
    }
    
    func trackViewAppearance(brandName: String, theme: String, viewMode: String) async {
        viewStartTime = Date()
        
        analyticsService.track("branded_discovery_view_appeared", parameters: [
            "brand_name": brandName,
            "theme_primary_color": theme,
            "view_mode": viewMode,
            "tenant_id": tenantService.currentTenant?.id ?? "none",
            "courses_count": courses.count,
            "location_enabled": userLocation != nil
        ])
    }
    
    func trackViewDisappearance() async {
        let sessionDuration = Date().timeIntervalSince(viewStartTime)
        
        analyticsService.track("branded_discovery_session_ended", parameters: [
            "session_duration": sessionDuration,
            "courses_viewed": coursesViewed.count,
            "searches_performed": searchQueries.count,
            "unique_search_terms": Set(searchQueries).count,
            "tenant_id": tenantService.currentTenant?.id ?? "none"
        ])
    }
    
    // MARK: - Private Helper Methods
    
    private func processLoadedCourses() async {
        updateFeaturedCourses()
        applyFiltersAndSearch()
    }
    
    private func getCacheKey() -> String {
        let tenantId = tenantService.currentTenant?.id ?? "default"
        let locationKey = userLocation?.coordinate.description ?? "no_location"
        return "branded_courses_\(tenantId)_\(locationKey)"
    }
    
    private func setupLocationUpdates() {
        locationService.locationUpdates
            .sink { [weak self] location in
                self?.userLocation = location
                // Reapply nearby filter if active
                if self?.currentFilter == .nearby {
                    self?.applyFiltersAndSearch()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupTenantUpdates() {
        tenantService.currentTenantPublisher
            .sink { [weak self] tenant in
                // Reload courses when tenant changes
                Task {
                    await self?.loadCourses()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Utility Methods
    
    func getCourseDistance(_ course: SharedGolfCourse) -> String? {
        guard let userLocation = userLocation else { return nil }
        
        let courseLocation = CLLocation(latitude: course.latitude, longitude: course.longitude)
        let distance = userLocation.distance(from: courseLocation)
        
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: distance)
    }
    
    func getRecommendedCourses() -> [SharedGolfCourse] {
        return courses
            .filter { $0.averageRating >= 4.0 }
            .sorted { course1, course2 in
                // Sort by rating first, then by distance if available
                if course1.averageRating != course2.averageRating {
                    return course1.averageRating > course2.averageRating
                }
                
                guard let userLocation = userLocation else {
                    return course1.name < course2.name
                }
                
                let distance1 = userLocation.distance(from: CLLocation(
                    latitude: course1.latitude,
                    longitude: course1.longitude
                ))
                let distance2 = userLocation.distance(from: CLLocation(
                    latitude: course2.latitude,
                    longitude: course2.longitude
                ))
                
                return distance1 < distance2
            }
            .prefix(10)
            .map { $0 }
    }
    
    func getPopularSearches() -> [String] {
        let searchFrequency = searchQueries.reduce(into: [String: Int]()) { counts, search in
            counts[search, default: 0] += 1
        }
        
        return searchFrequency
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }
}

// MARK: - Error Types

enum BrandedDiscoveryError: LocalizedError {
    case noCoursesFound
    case locationUnavailable
    case tenantConfigurationMissing
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .noCoursesFound:
            return "No golf courses found in your area"
        case .locationUnavailable:
            return "Location services are not available"
        case .tenantConfigurationMissing:
            return "Tenant configuration is missing"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Extensions

extension SharedGolfCourse {
    var distanceDescription: String {
        // This would be set by the view model when user location is available
        return "Distance unavailable"
    }
    
    var featuresDescription: String {
        var features: [String] = []
        
        if hasGPS { features.append("GPS") }
        if hasDrivingRange { features.append("Range") }
        if hasRestaurant { features.append("Dining") }
        if cartRequired { features.append("Cart Req.") }
        
        return features.joined(separator: " • ")
    }
    
    var difficultyColor: Color {
        switch difficulty {
        case .beginner:
            return .green
        case .intermediate:
            return .blue
        case .advanced:
            return .orange
        case .championship:
            return .red
        }
    }
}