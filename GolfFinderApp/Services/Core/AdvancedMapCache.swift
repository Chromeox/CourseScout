import Foundation
import MapKit
import CoreLocation
import os.log

// MARK: - Advanced Map Cache System

actor AdvancedMapCache {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinder.Performance", category: "MapCache")
    
    // Memory cache with LRU eviction
    private var courseCache: [String: CachedCourse] = [:]
    private var cacheAccessOrder: [String] = []
    
    // Configuration
    private let maxCacheSize: Int = 1000 // Max cached courses
    private let maxMemorySize: Int = 100 * 1024 * 1024 // 100MB
    private let defaultTTL: TimeInterval = 900 // 15 minutes
    private var currentMemoryUsage: Int = 0
    
    // Performance metrics
    private var hits: Int = 0
    private var misses: Int = 0
    private var evictions: Int = 0
    
    // MARK: - Cache Operations
    
    func getCourse(id: String) -> GolfCourse? {
        guard let cached = courseCache[id], !cached.isExpired else {
            misses += 1
            if courseCache[id] != nil {
                // Expired entry
                removeCourse(id: id)
            }
            return nil
        }
        
        // Update LRU order
        updateAccessOrder(id)
        hits += 1
        
        return cached.course
    }
    
    func setCourse(_ course: GolfCourse, ttl: TimeInterval? = nil) {
        let cacheKey = course.id
        let expirationTime = Date().addingTimeInterval(ttl ?? defaultTTL)
        let estimatedSize = estimateMemoryUsage(for: course)
        
        // Check if we need to evict entries
        if needsEviction(additionalSize: estimatedSize) {
            performEviction(targetSize: estimatedSize)
        }
        
        let cachedCourse = CachedCourse(
            course: course,
            timestamp: Date(),
            expirationTime: expirationTime,
            accessCount: 1,
            estimatedSize: estimatedSize
        )
        
        // Remove old entry if it exists
        if let oldCached = courseCache[cacheKey] {
            currentMemoryUsage -= oldCached.estimatedSize
        }
        
        // Add new entry
        courseCache[cacheKey] = cachedCourse
        currentMemoryUsage += estimatedSize
        updateAccessOrder(cacheKey)
        
        logger.debug("Cached course: \(course.name) (Size: \(estimatedSize) bytes)")
    }
    
    func removeCourse(id: String) {
        if let cached = courseCache.removeValue(forKey: id) {
            currentMemoryUsage -= cached.estimatedSize
            cacheAccessOrder.removeAll { $0 == id }
            logger.debug("Removed course from cache: \(id)")
        }
    }
    
    func clearAll() {
        let clearedCount = courseCache.count
        courseCache.removeAll()
        cacheAccessOrder.removeAll()
        currentMemoryUsage = 0
        
        logger.info("Cleared all cache entries: \(clearedCount) courses")
    }
    
    // MARK: - Memory Management
    
    func performMemoryOptimization() {
        let initialCount = courseCache.count
        let initialMemory = currentMemoryUsage
        
        // Remove expired entries
        removeExpiredEntries()
        
        // Perform aggressive cleanup if memory usage is still high
        let memoryThreshold = maxMemorySize / 2
        if currentMemoryUsage > memoryThreshold {
            performAggressiveCleanup()
        }
        
        let optimizedCount = courseCache.count
        let optimizedMemory = currentMemoryUsage
        
        logger.info("Memory optimization: \(initialCount) -> \(optimizedCount) courses, \(initialMemory) -> \(optimizedMemory) bytes")
    }
    
    func getCacheStats() -> CacheStats {
        let hitRate = hits + misses > 0 ? Double(hits) / Double(hits + misses) : 0
        
        return CacheStats(
            totalEntries: courseCache.count,
            memoryUsage: currentMemoryUsage,
            maxMemorySize: maxMemorySize,
            hits: hits,
            misses: misses,
            hitRate: hitRate,
            evictions: evictions,
            averageEntrySize: courseCache.isEmpty ? 0 : currentMemoryUsage / courseCache.count
        )
    }
    
    // MARK: - Private Methods
    
    private func updateAccessOrder(_ id: String) {
        // Move to end (most recently used)
        cacheAccessOrder.removeAll { $0 == id }
        cacheAccessOrder.append(id)
        
        // Update access count
        courseCache[id]?.accessCount += 1
    }
    
    private func needsEviction(additionalSize: Int) -> Bool {
        return courseCache.count >= maxCacheSize || 
               (currentMemoryUsage + additionalSize) > maxMemorySize
    }
    
    private func performEviction(targetSize: Int) {
        let requiredSpace = max(targetSize, maxMemorySize / 10) // At least 10% of max
        var freedSpace = 0
        var evictedCount = 0
        
        // First, remove expired entries
        removeExpiredEntries()
        
        // Then, use LRU eviction
        while freedSpace < requiredSpace && !cacheAccessOrder.isEmpty {
            let leastRecentlyUsedId = cacheAccessOrder.removeFirst()
            
            if let cached = courseCache.removeValue(forKey: leastRecentlyUsedId) {
                freedSpace += cached.estimatedSize
                currentMemoryUsage -= cached.estimatedSize
                evictedCount += 1
                evictions += 1
            }
        }
        
        if evictedCount > 0 {
            logger.debug("Evicted \(evictedCount) courses, freed \(freedSpace) bytes")
        }
    }
    
    private func removeExpiredEntries() {
        let expiredKeys = courseCache.compactMap { key, cached in
            cached.isExpired ? key : nil
        }
        
        for key in expiredKeys {
            removeCourse(id: key)
        }
        
        if !expiredKeys.isEmpty {
            logger.debug("Removed \(expiredKeys.count) expired entries")
        }
    }
    
    private func performAggressiveCleanup() {
        // Remove least accessed entries
        let sortedByAccess = courseCache.sorted { $0.value.accessCount < $1.value.accessCount }
        let toRemove = sortedByAccess.prefix(courseCache.count / 4) // Remove 25%
        
        for (key, _) in toRemove {
            removeCourse(id: key)
        }
        
        logger.debug("Aggressive cleanup: removed \(toRemove.count) low-access entries")
    }
    
    private func estimateMemoryUsage(for course: GolfCourse) -> Int {
        // Rough estimation of course memory footprint
        var size = 0
        
        // Basic properties
        size += course.name.utf8.count
        size += course.address.utf8.count
        size += course.city.utf8.count
        size += course.state.utf8.count
        size += course.country.utf8.count
        size += course.zipCode.utf8.count
        size += (course.description?.utf8.count ?? 0)
        
        // Images array
        size += course.images.count * 100 // Approximate per image
        
        // Amenities
        size += course.amenities.count * 20
        
        // Operating hours and other complex structures
        size += 500 // Approximate overhead for complex nested structures
        
        return max(size, 1024) // Minimum 1KB per course
    }
}

// MARK: - Regional Query Cache

actor RegionQueryCache {
    
    private let logger = Logger(subsystem: "GolfFinder.Performance", category: "RegionCache")
    
    // Regional cache
    private var regionCache: [String: RegionCacheEntry] = [:]
    
    // Configuration
    private let maxRegions: Int = 50
    private let defaultTTL: TimeInterval = 600 // 10 minutes
    
    func cacheKey(for region: MKCoordinateRegion) -> String {
        // Create normalized cache key
        let lat = String(format: "%.3f", region.center.latitude)
        let lon = String(format: "%.3f", region.center.longitude)
        let latSpan = String(format: "%.3f", region.span.latitudeDelta)
        let lonSpan = String(format: "%.3f", region.span.longitudeDelta)
        
        return "region_\(lat)_\(lon)_\(latSpan)_\(lonSpan)"
    }
    
    func getCourses(for cacheKey: String) async -> [GolfCourse]? {
        guard let entry = regionCache[cacheKey], !entry.isExpired else {
            if regionCache[cacheKey] != nil {
                regionCache.removeValue(forKey: cacheKey)
            }
            return nil
        }
        
        // Update access time
        regionCache[cacheKey]?.lastAccessed = Date()
        
        return entry.courses
    }
    
    func setCourses(_ courses: [GolfCourse], for cacheKey: String, region: MKCoordinateRegion) {
        // Evict old regions if necessary
        if regionCache.count >= maxRegions {
            evictOldestRegion()
        }
        
        let entry = RegionCacheEntry(
            courses: courses,
            region: region,
            timestamp: Date(),
            expirationTime: Date().addingTimeInterval(defaultTTL),
            lastAccessed: Date()
        )
        
        regionCache[cacheKey] = entry
        
        logger.debug("Cached \(courses.count) courses for region")
    }
    
    func removeCourses(for cacheKey: String) {
        regionCache.removeValue(forKey: cacheKey)
    }
    
    func clearAll() {
        let clearedCount = regionCache.count
        regionCache.removeAll()
        logger.info("Cleared all regional cache entries: \(clearedCount) regions")
    }
    
    func invalidateDistantRegions(from location: CLLocationCoordinate2D, beyond distance: CLLocationDistance) {
        let currentLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        var invalidatedCount = 0
        
        let keysToRemove = regionCache.compactMap { key, entry -> String? in
            let regionLocation = CLLocation(
                latitude: entry.region.center.latitude,
                longitude: entry.region.center.longitude
            )
            
            return currentLocation.distance(from: regionLocation) > distance ? key : nil
        }
        
        for key in keysToRemove {
            regionCache.removeValue(forKey: key)
            invalidatedCount += 1
        }
        
        if invalidatedCount > 0 {
            logger.debug("Invalidated \(invalidatedCount) distant regions")
        }
    }
    
    func performMemoryOptimization() {
        // Remove expired entries
        let expiredKeys = regionCache.compactMap { key, entry in
            entry.isExpired ? key : nil
        }
        
        for key in expiredKeys {
            regionCache.removeValue(forKey: key)
        }
        
        // Remove least recently accessed if over limit
        if regionCache.count > maxRegions {
            let sortedByAccess = regionCache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
            let toRemove = sortedByAccess.prefix(regionCache.count - maxRegions + 5)
            
            for (key, _) in toRemove {
                regionCache.removeValue(forKey: key)
            }
        }
        
        logger.debug("Regional cache optimization completed: \(regionCache.count) regions remaining")
    }
    
    private func evictOldestRegion() {
        guard let oldestKey = regionCache.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })?.key else {
            return
        }
        
        regionCache.removeValue(forKey: oldestKey)
    }
}

// MARK: - Cache Data Structures

private struct CachedCourse {
    let course: GolfCourse
    let timestamp: Date
    let expirationTime: Date
    var accessCount: Int
    let estimatedSize: Int
    
    var isExpired: Bool {
        Date() > expirationTime
    }
    
    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
}

private struct RegionCacheEntry {
    let courses: [GolfCourse]
    let region: MKCoordinateRegion
    let timestamp: Date
    let expirationTime: Date
    var lastAccessed: Date
    
    var isExpired: Bool {
        Date() > expirationTime
    }
    
    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
}

// MARK: - Cache Statistics

struct CacheStats {
    let totalEntries: Int
    let memoryUsage: Int
    let maxMemorySize: Int
    let hits: Int
    let misses: Int
    let hitRate: Double
    let evictions: Int
    let averageEntrySize: Int
    
    var formattedMemoryUsage: String {
        ByteCountFormatter().string(fromByteCount: Int64(memoryUsage))
    }
    
    var formattedMaxMemorySize: String {
        ByteCountFormatter().string(fromByteCount: Int64(maxMemorySize))
    }
    
    var memoryUtilization: Double {
        Double(memoryUsage) / Double(maxMemorySize)
    }
    
    var formattedHitRate: String {
        String(format: "%.1f%%", hitRate * 100)
    }
}