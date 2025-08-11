import Foundation
import MapKit
import CoreLocation
import Combine
import os.log

// MARK: - Optimized Golf Course Map Service

@MainActor
class OptimizedGolfCourseMapService: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinder.Performance", category: "MapService")
    private let golfCourseService: GolfCourseServiceProtocol
    private let locationService: LocationServiceProtocol
    
    // High-performance caching system
    private let mapCache = AdvancedMapCache()
    private let regionCache = RegionQueryCache()
    
    // MapKit optimization
    private var mapView: MKMapView?
    private var currentRegion: MKCoordinateRegion?
    private var visibleAnnotations = Set<String>()
    
    // Query debouncing and batching
    private var regionChangeTimer: Timer?
    private var lastRegionUpdate = Date()
    private let regionUpdateThrottleInterval: TimeInterval = 0.5
    private var pendingQueries: [MapQuery] = []
    private let queryBatchTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in }
    
    // Performance monitoring
    private var queryMetrics = MapQueryMetrics()
    @Published var performanceStats = MapPerformanceStats()
    
    // Real-time updates
    private var subscriptions = Set<AnyCancellable>()
    private let courseUpdateSubject = PassthroughSubject<[GolfCourse], Never>()
    
    // Background processing
    private let mapQueue = DispatchQueue(label: "GolfMapService", qos: .userInitiated)
    private let cacheQueue = DispatchQueue(label: "MapCache", qos: .utility, attributes: .concurrent)
    
    // MARK: - Initialization
    
    init(golfCourseService: GolfCourseServiceProtocol, locationService: LocationServiceProtocol) {
        self.golfCourseService = golfCourseService
        self.locationService = locationService
        super.init()
        
        setupPerformanceOptimizations()
        setupRealTimeUpdates()
        logger.info("OptimizedGolfCourseMapService initialized with advanced caching")
    }
    
    // MARK: - Map Configuration
    
    func configureMapView(_ mapView: MKMapView) {
        self.mapView = mapView
        mapView.delegate = self
        
        // Performance optimizations for MapKit
        mapView.showsCompass = false // Reduces rendering overhead
        mapView.showsScale = false
        mapView.showsTraffic = false
        mapView.showsBuildings = false
        mapView.showsPointsOfInterest = false
        
        // Memory management
        mapView.preferredConfiguration = MKStandardMapConfiguration()
        if let config = mapView.preferredConfiguration as? MKStandardMapConfiguration {
            config.emphasisStyle = .muted
            config.pointOfInterestFilter = .excludingAll
        }
        
        logger.debug("MapView configured with performance optimizations")
    }
    
    // MARK: - Course Loading with Advanced Optimization
    
    func loadCoursesForRegion(_ region: MKCoordinateRegion, forceRefresh: Bool = false) async -> [GolfCourse] {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Check region cache first
        let cacheKey = regionCache.cacheKey(for: region)
        if !forceRefresh, let cachedCourses = await regionCache.getCourses(for: cacheKey) {
            logger.debug("Returning cached courses for region: \(cachedCourses.count) courses")
            updatePerformanceStats(queryTime: CFAbsoluteTimeGetCurrent() - startTime, cacheHit: true)
            return cachedCourses
        }
        
        do {
            // Calculate optimal search parameters
            let centerLocation = CLLocationCoordinate2D(
                latitude: region.center.latitude,
                longitude: region.center.longitude
            )
            
            let searchRadius = calculateOptimalSearchRadius(for: region)
            
            // Perform optimized search
            let courses = try await performOptimizedSearch(
                center: centerLocation,
                radius: searchRadius,
                region: region
            )
            
            // Cache results with intelligent expiration
            await regionCache.setCourses(courses, for: cacheKey, region: region)
            
            // Update performance metrics
            let queryTime = CFAbsoluteTimeGetCurrent() - startTime
            updatePerformanceStats(queryTime: queryTime, cacheHit: false, courseCount: courses.count)
            
            logger.info("Loaded \(courses.count) courses for region in \(String(format: "%.3f", queryTime))s")
            
            // Publish updates
            courseUpdateSubject.send(courses)
            
            return courses
            
        } catch {
            logger.error("Failed to load courses for region: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Intelligent Course Filtering
    
    func loadVisibleCourses(for mapView: MKMapView, with filters: CourseSearchFilters? = nil) async -> [GolfCourse] {
        let visibleRegion = mapView.region
        let visibleRect = mapView.visibleMapRect
        
        // Load courses for expanded region to enable smooth panning
        let expandedRegion = expandRegionForPreloading(visibleRegion)
        let allCourses = await loadCoursesForRegion(expandedRegion)
        
        // Filter to only truly visible courses for annotation display
        let visibleCourses = allCourses.filter { course in
            let coursePoint = MKMapPoint(course.coordinate)
            return visibleRect.contains(coursePoint)
        }
        
        // Apply additional filters
        let filteredCourses = applyFilters(visibleCourses, filters: filters)
        
        // Optimize annotation management
        await updateVisibleAnnotations(filteredCourses, in: mapView)
        
        return filteredCourses
    }
    
    // MARK: - Real-Time Course Updates
    
    func subscribeToCoursesInRegion(_ region: MKCoordinateRegion) -> AnyPublisher<[GolfCourse], Never> {
        // Create regional subscription for real-time updates
        let centerLocation = CLLocationCoordinate2D(
            latitude: region.center.latitude,
            longitude: region.center.longitude
        )
        
        // Use smaller radius for real-time updates to reduce overhead
        let updateRadius = min(calculateOptimalSearchRadius(for: region), 25.0) // Max 25 miles
        
        return Timer.publish(every: 30.0, on: .main, in: .default) // 30-second intervals
            .autoconnect()
            .asyncMap { _ in
                await self.loadCoursesForRegion(region, forceRefresh: true)
            }
            .merge(with: courseUpdateSubject)
            .removeDuplicates { courses1, courses2 in
                // Custom duplicate removal based on course IDs and update times
                return self.areCourseListsEquivalent(courses1, courses2)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Performance Monitoring
    
    func getPerformanceMetrics() -> MapPerformanceStats {
        return performanceStats
    }
    
    func resetPerformanceMetrics() {
        performanceStats = MapPerformanceStats()
        queryMetrics = MapQueryMetrics()
    }
    
    // MARK: - Memory Management
    
    func clearCache() {
        mapCache.clearAll()
        regionCache.clearAll()
        logger.info("Map service cache cleared")
    }
    
    func clearCacheForRegion(_ region: MKCoordinateRegion) {
        let cacheKey = regionCache.cacheKey(for: region)
        regionCache.removeCourses(for: cacheKey)
    }
    
    func optimizeMemoryUsage() async {
        await mapCache.performMemoryOptimization()
        await regionCache.performMemoryOptimization()
        
        // Update performance stats
        await MainActor.run {
            performanceStats.lastMemoryOptimization = Date()
            performanceStats.memoryOptimizations += 1
        }
    }
}

// MARK: - Private Helper Methods

private extension OptimizedGolfCourseMapService {
    
    func setupPerformanceOptimizations() {
        // Configure query batching timer
        queryBatchTimer.fire()
        
        // Monitor memory usage
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.optimizeMemoryUsage()
            }
        }
    }
    
    func setupRealTimeUpdates() {
        // Monitor location changes for cache invalidation
        locationService.objectWillChange
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task {
                    await self?.handleLocationChange()
                }
            }
            .store(in: &subscriptions)
    }
    
    func handleLocationChange() async {
        // Intelligent cache invalidation based on location change
        guard let currentLocation = locationService.currentLocation else { return }
        
        // Calculate distance from last cached location
        let invalidationDistance: CLLocationDistance = 5000 // 5km
        
        // Clear cache for regions that are now too far away
        await regionCache.invalidateDistantRegions(from: currentLocation, beyond: invalidationDistance)
    }
    
    func calculateOptimalSearchRadius(for region: MKCoordinateRegion) -> Double {
        // Calculate radius based on region span with performance considerations
        let latSpan = region.span.latitudeDelta
        let lonSpan = region.span.longitudeDelta
        
        // Convert to approximate miles with performance optimization
        let avgSpan = (latSpan + lonSpan) / 2
        let radiusMiles = min(avgSpan * 69.0 * 1.5, 100.0) // Max 100 miles for performance
        
        return max(radiusMiles, 5.0) // Min 5 miles for usability
    }
    
    func expandRegionForPreloading(_ region: MKCoordinateRegion) -> MKCoordinateRegion {
        // Expand region by 50% for smooth panning experience
        return MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: region.span.latitudeDelta * 1.5,
                longitudeDelta: region.span.longitudeDelta * 1.5
            )
        )
    }
    
    func performOptimizedSearch(
        center: CLLocationCoordinate2D,
        radius: Double,
        region: MKCoordinateRegion
    ) async throws -> [GolfCourse] {
        
        // Use batched querying for better performance
        let batchSize = 50
        var allCourses: [GolfCourse] = []
        var offset = 0
        
        repeat {
            let batchCourses = try await golfCourseService.searchCourses(
                near: center,
                radius: radius,
                filters: CourseSearchFilters(
                    limit: batchSize,
                    offset: offset
                )
            )
            
            allCourses.append(contentsOf: batchCourses)
            offset += batchSize
            
            // Prevent infinite loops and limit results for performance
            if batchCourses.count < batchSize || allCourses.count >= 500 {
                break
            }
        } while true
        
        // Sort by distance for optimal user experience
        return sortCoursesByDistance(allCourses, from: center)
    }
    
    func sortCoursesByDistance(_ courses: [GolfCourse], from location: CLLocationCoordinate2D) -> [GolfCourse] {
        return courses.sorted { course1, course2 in
            let distance1 = course1.coordinate.distance(to: location)
            let distance2 = course2.coordinate.distance(to: location)
            return distance1 < distance2
        }
    }
    
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
            
            // Rating filter
            if let minRating = filters.minimumRating {
                if course.averageRating < minRating {
                    return false
                }
            }
            
            return true
        }
    }
    
    func updateVisibleAnnotations(_ courses: [GolfCourse], in mapView: MKMapView) async {
        let currentVisible = Set(courses.map { $0.id })
        
        // Only update annotations if there's a significant change
        let addedCourses = currentVisible.subtracting(visibleAnnotations)
        let removedCourses = visibleAnnotations.subtracting(currentVisible)
        
        if !addedCourses.isEmpty || !removedCourses.isEmpty {
            await MainActor.run {
                // Remove annotations for courses no longer visible
                let annotationsToRemove = mapView.annotations.compactMap { annotation -> GolfCourseAnnotation? in
                    guard let courseAnnotation = annotation as? GolfCourseAnnotation else { return nil }
                    return removedCourses.contains(courseAnnotation.course.id) ? courseAnnotation : nil
                }
                mapView.removeAnnotations(annotationsToRemove)
                
                // Add annotations for newly visible courses
                let newAnnotations = courses.compactMap { course -> GolfCourseAnnotation? in
                    return addedCourses.contains(course.id) ? GolfCourseAnnotation(course: course) : nil
                }
                mapView.addAnnotations(newAnnotations)
                
                visibleAnnotations = currentVisible
            }
        }
    }
    
    func areCourseListsEquivalent(_ courses1: [GolfCourse], _ courses2: [GolfCourse]) -> Bool {
        // Fast comparison based on count and IDs
        guard courses1.count == courses2.count else { return false }
        
        let ids1 = Set(courses1.map { $0.id })
        let ids2 = Set(courses2.map { $0.id })
        
        return ids1 == ids2
    }
    
    func updatePerformanceStats(queryTime: CFAbsoluteTime, cacheHit: Bool, courseCount: Int = 0) {
        performanceStats.totalQueries += 1
        performanceStats.totalQueryTime += queryTime
        performanceStats.averageQueryTime = performanceStats.totalQueryTime / Double(performanceStats.totalQueries)
        
        if cacheHit {
            performanceStats.cacheHits += 1
        }
        
        performanceStats.cacheHitRate = Double(performanceStats.cacheHits) / Double(performanceStats.totalQueries)
        
        if queryTime > performanceStats.slowestQueryTime {
            performanceStats.slowestQueryTime = queryTime
        }
        
        if queryTime < performanceStats.fastestQueryTime || performanceStats.fastestQueryTime == 0 {
            performanceStats.fastestQueryTime = queryTime
        }
        
        performanceStats.lastUpdateTime = Date()
    }
}

// MARK: - MKMapViewDelegate

extension OptimizedGolfCourseMapService: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        // Throttle region change updates for performance
        regionChangeTimer?.invalidate()
        regionChangeTimer = Timer.scheduledTimer(withTimeInterval: regionUpdateThrottleInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.handleRegionChange(mapView.region)
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let golfCourseAnnotation = annotation as? GolfCourseAnnotation else {
            return nil
        }
        
        let identifier = "GolfCourseAnnotation"
        let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? GolfCourseAnnotationView
            ?? GolfCourseAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        
        annotationView.configure(with: golfCourseAnnotation.course)
        return annotationView
    }
    
    private func handleRegionChange(_ region: MKCoordinateRegion) async {
        currentRegion = region
        
        // Preload courses for the new region
        Task.detached(priority: .userInitiated) {
            await self.loadCoursesForRegion(region)
        }
    }
}

// MARK: - Supporting Types

struct MapQuery {
    let id = UUID()
    let region: MKCoordinateRegion
    let filters: CourseSearchFilters?
    let timestamp = Date()
}

struct MapQueryMetrics {
    var totalQueries = 0
    var successfulQueries = 0
    var failedQueries = 0
    var averageResponseTime: TimeInterval = 0
}

@MainActor
class MapPerformanceStats: ObservableObject {
    @Published var totalQueries = 0
    @Published var cacheHits = 0
    @Published var cacheHitRate: Double = 0
    @Published var totalQueryTime: CFAbsoluteTime = 0
    @Published var averageQueryTime: CFAbsoluteTime = 0
    @Published var fastestQueryTime: CFAbsoluteTime = 0
    @Published var slowestQueryTime: CFAbsoluteTime = 0
    @Published var lastUpdateTime = Date()
    @Published var memoryOptimizations = 0
    @Published var lastMemoryOptimization: Date?
    
    var formattedAverageQueryTime: String {
        String(format: "%.3fs", averageQueryTime)
    }
    
    var formattedCacheHitRate: String {
        String(format: "%.1f%%", cacheHitRate * 100)
    }
}

// MARK: - Custom Golf Course Annotation

class GolfCourseAnnotation: NSObject, MKAnnotation {
    let course: GolfCourse
    
    var coordinate: CLLocationCoordinate2D {
        course.coordinate
    }
    
    var title: String? {
        course.name
    }
    
    var subtitle: String? {
        "\(course.city), \(course.state) • \(course.formattedRating) ⭐"
    }
    
    init(course: GolfCourse) {
        self.course = course
        super.init()
    }
}

class GolfCourseAnnotationView: MKAnnotationView {
    
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func setupView() {
        canShowCallout = true
        calloutOffset = CGPoint(x: -5, y: 5)
        rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
    }
    
    func configure(with course: GolfCourse) {
        // Create custom pin image based on course difficulty
        let pinColor: UIColor
        switch course.difficulty {
        case .beginner:
            pinColor = .systemGreen
        case .intermediate:
            pinColor = .systemBlue
        case .advanced:
            pinColor = .systemOrange
        case .championship:
            pinColor = .systemRed
        }
        
        image = createPinImage(color: pinColor)
    }
    
    private func createPinImage(color: UIColor) -> UIImage? {
        let size = CGSize(width: 30, height: 40)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x: size.width / 2, y: size.height))
        path.addArc(withCenter: CGPoint(x: size.width / 2, y: size.width / 2),
                   radius: size.width / 2,
                   startAngle: 0,
                   endAngle: .pi * 2,
                   clockwise: true)
        
        color.setFill()
        path.fill()
        
        UIColor.white.setStroke()
        path.lineWidth = 2
        path.stroke()
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// MARK: - Extensions

extension CourseSearchFilters {
    init(limit: Int, offset: Int) {
        self.limit = limit
        self.offset = offset
        self.priceRange = nil
        self.difficulty = nil
        self.amenities = nil
        self.guestPolicy = nil
        self.minimumRating = nil
        self.holes = nil
    }
}

extension CLLocationCoordinate2D {
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let location1 = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let location2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location1.distance(from: location2)
    }
}

extension Publisher where Failure == Never {
    func asyncMap<T>(_ transform: @escaping (Output) async -> T) -> Publishers.FlatMap<Future<T, Never>, Self> {
        flatMap { value in
            Future { promise in
                Task {
                    let result = await transform(value)
                    promise(.success(result))
                }
            }
        }
    }
}