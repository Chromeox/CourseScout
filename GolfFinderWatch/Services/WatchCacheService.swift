import Foundation
import os.log

// MARK: - Watch Cache Service Implementation

class WatchCacheService: WatchCacheServiceProtocol, WatchBatteryOptimizable, WatchBackgroundRefreshable, WatchMemoryCleanable {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "Cache")
    private let cacheQueue = DispatchQueue(label: "WatchCacheQueue", qos: .utility)
    private let fileManager = FileManager.default
    
    // Cache configuration
    private let maxCacheSize: Int64 = 50 * 1024 * 1024 // 50MB max for Watch
    private let maxCacheAge: TimeInterval = 24 * 60 * 60 // 24 hours
    private var isBatteryOptimized = false
    
    // Cache directories
    private lazy var cacheDirectory: URL = {
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appCacheDir = cacheDir.appendingPathComponent("GolfFinderWatch")
        
        try? fileManager.createDirectory(at: appCacheDir, withIntermediateDirectories: true)
        return appCacheDir
    }()
    
    private lazy var golfCacheDirectory: URL = {
        let golfDir = cacheDirectory.appendingPathComponent("Golf")
        try? fileManager.createDirectory(at: golfDir, withIntermediateDirectories: true)
        return golfDir
    }()
    
    // In-memory cache for frequently accessed items
    private var memoryCache: [String: CachedItem] = [:]
    private let memoryCacheLimit = 20 // Reduced for Watch constraints
    
    // Cache metadata
    private var cacheMetadata: [String: CacheMetadata] = [:]
    private let metadataKey = "CacheMetadata"
    
    // MARK: - Initialization
    
    init() {
        loadCacheMetadata()
        setupCacheCleanupTimer()
        logger.info("WatchCacheService initialized")
    }
    
    // MARK: - Generic Cache Operations
    
    func store<T: Codable>(_ object: T, forKey key: String) async {
        await cacheQueue.run { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try JSONEncoder().encode(object)
                let fileURL = self.cacheDirectory.appendingPathComponent("\(key).cache")
                
                try data.write(to: fileURL)
                
                // Update metadata
                let metadata = CacheMetadata(
                    key: key,
                    size: Int64(data.count),
                    createdAt: Date(),
                    lastAccessedAt: Date(),
                    accessCount: 1
                )
                self.cacheMetadata[key] = metadata
                
                // Store in memory cache if small enough
                if data.count < 10 * 1024 && !self.isBatteryOptimized { // 10KB limit
                    let cachedItem = CachedItem(data: data, lastAccessed: Date())
                    self.memoryCache[key] = cachedItem
                    self.trimMemoryCache()
                }
                
                await self.saveCacheMetadata()
                self.logger.debug("Cached object for key: \(key), size: \(data.count) bytes")
                
            } catch {
                self.logger.error("Failed to cache object for key \(key): \(error.localizedDescription)")
            }
        }
    }
    
    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) async -> T? {
        return await cacheQueue.run { [weak self] in
            guard let self = self else { return nil }
            
            // Check memory cache first
            if let cachedItem = self.memoryCache[key] {
                cachedItem.lastAccessed = Date()
                self.updateAccessMetadata(for: key)
                
                do {
                    let object = try JSONDecoder().decode(type, from: cachedItem.data)
                    self.logger.debug("Retrieved object from memory cache for key: \(key)")
                    return object
                } catch {
                    self.logger.warning("Failed to decode object from memory cache for key \(key): \(error.localizedDescription)")
                    self.memoryCache.removeValue(forKey: key)
                }
            }
            
            // Check disk cache
            let fileURL = self.cacheDirectory.appendingPathComponent("\(key).cache")
            
            guard self.fileManager.fileExists(atPath: fileURL.path) else {
                self.logger.debug("No cached object found for key: \(key)")
                return nil
            }
            
            do {
                let data = try Data(contentsOf: fileURL)
                let object = try JSONDecoder().decode(type, from: data)
                
                // Update metadata
                self.updateAccessMetadata(for: key)
                
                // Add to memory cache if appropriate
                if data.count < 10 * 1024 && !self.isBatteryOptimized {
                    let cachedItem = CachedItem(data: data, lastAccessed: Date())
                    self.memoryCache[key] = cachedItem
                    self.trimMemoryCache()
                }
                
                self.logger.debug("Retrieved object from disk cache for key: \(key)")
                return object
                
            } catch {
                self.logger.error("Failed to retrieve object for key \(key): \(error.localizedDescription)")
                // Remove corrupted cache file
                try? self.fileManager.removeItem(at: fileURL)
                self.cacheMetadata.removeValue(forKey: key)
                return nil
            }
        }
    }
    
    func remove(forKey key: String) async {
        await cacheQueue.run { [weak self] in
            guard let self = self else { return }
            
            // Remove from memory cache
            self.memoryCache.removeValue(forKey: key)
            
            // Remove from disk cache
            let fileURL = self.cacheDirectory.appendingPathComponent("\(key).cache")
            try? self.fileManager.removeItem(at: fileURL)
            
            // Remove metadata
            self.cacheMetadata.removeValue(forKey: key)
            
            Task {
                await self.saveCacheMetadata()
            }
            
            self.logger.debug("Removed cached object for key: \(key)")
        }
    }
    
    func clearCache() async {
        await cacheQueue.run { [weak self] in
            guard let self = self else { return }
            
            // Clear memory cache
            self.memoryCache.removeAll()
            
            // Clear disk cache
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)
                
                for url in contents where url.pathExtension == "cache" {
                    try self.fileManager.removeItem(at: url)
                }
                
                // Clear metadata
                self.cacheMetadata.removeAll()
                await self.saveCacheMetadata()
                
                self.logger.info("Cleared all cached data")
                
            } catch {
                self.logger.error("Failed to clear cache: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Golf-Specific Caching
    
    func cacheCourse(_ course: SharedGolfCourse) async {
        await store(course, forKey: "course_\(course.id)")
        
        // Also cache in golf-specific directory for organization
        await cacheQueue.run { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try JSONEncoder().encode(course)
                let courseURL = self.golfCacheDirectory.appendingPathComponent("\(course.id).course")
                try data.write(to: courseURL)
                
                self.logger.debug("Cached golf course: \(course.name)")
                
            } catch {
                self.logger.error("Failed to cache golf course \(course.id): \(error.localizedDescription)")
            }
        }
    }
    
    func getCachedCourse(id: String) async -> SharedGolfCourse? {
        // Try generic cache first
        if let course = await retrieve(SharedGolfCourse.self, forKey: "course_\(id)") {
            return course
        }
        
        // Try golf-specific cache
        return await cacheQueue.run { [weak self] in
            guard let self = self else { return nil }
            
            let courseURL = self.golfCacheDirectory.appendingPathComponent("\(id).course")
            
            guard self.fileManager.fileExists(atPath: courseURL.path) else {
                return nil
            }
            
            do {
                let data = try Data(contentsOf: courseURL)
                let course = try JSONDecoder().decode(SharedGolfCourse.self, from: data)
                
                self.logger.debug("Retrieved cached golf course: \(course.name)")
                return course
                
            } catch {
                self.logger.error("Failed to retrieve cached course \(id): \(error.localizedDescription)")
                try? self.fileManager.removeItem(at: courseURL)
                return nil
            }
        }
    }
    
    func cacheActiveRound(_ round: ActiveGolfRound) async {
        await store(round, forKey: "active_round")
        logger.debug("Cached active round: \(round.courseName)")
    }
    
    func getCachedActiveRound() async -> ActiveGolfRound? {
        return await retrieve(ActiveGolfRound.self, forKey: "active_round")
    }
    
    // MARK: - Cache Management
    
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
            
        } catch {
            logger.error("Failed to calculate cache size: \(error.localizedDescription)")
        }
        
        return totalSize
    }
    
    func performCacheCleanup() async {
        await cacheQueue.run { [weak self] in
            guard let self = self else { return }
            
            let currentSize = self.getCacheSize()
            self.logger.debug("Starting cache cleanup, current size: \(currentSize / 1024 / 1024)MB")
            
            if currentSize > self.maxCacheSize {
                await self.performSizeBasedCleanup()
            }
            
            await self.performAgeBasedCleanup()
            await self.cleanupCorruptedFiles()
            
            self.logger.info("Cache cleanup completed, new size: \(self.getCacheSize() / 1024 / 1024)MB")
        }
    }
    
    // MARK: - Battery Optimization
    
    func enableBatteryOptimization() {
        isBatteryOptimized = true
        
        // Reduce memory cache size
        let reducedLimit = memoryCacheLimit / 2
        while memoryCache.count > reducedLimit {
            removeOldestMemoryCacheItem()
        }
        
        logger.info("Enabled battery optimization for cache service")
    }
    
    func disableBatteryOptimization() {
        isBatteryOptimized = false
        logger.info("Disabled battery optimization for cache service")
    }
    
    // MARK: - Background Refresh
    
    func performBackgroundRefresh() async {
        logger.debug("Performing background cache refresh")
        
        // Clean up old cache items
        await performCacheCleanup()
        
        // Validate cache integrity
        await validateCacheIntegrity()
        
        // Preload critical data if not battery optimized
        if !isBatteryOptimized {
            await preloadCriticalData()
        }
        
        logger.debug("Background cache refresh completed")
    }
    
    // MARK: - Memory Cleanup
    
    func performMemoryCleanup() {
        cacheQueue.sync { [weak self] in
            guard let self = self else { return }
            
            // Clear memory cache
            self.memoryCache.removeAll()
            
            // Reduce metadata cache
            let currentTime = Date()
            self.cacheMetadata = self.cacheMetadata.filter { _, metadata in
                currentTime.timeIntervalSince(metadata.lastAccessedAt) < self.maxCacheAge / 2
            }
            
            self.logger.debug("Performed memory cleanup for cache service")
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func updateAccessMetadata(for key: String) {
        if var metadata = cacheMetadata[key] {
            metadata.lastAccessedAt = Date()
            metadata.accessCount += 1
            cacheMetadata[key] = metadata
        }
    }
    
    private func trimMemoryCache() {
        while memoryCache.count > memoryCacheLimit {
            removeOldestMemoryCacheItem()
        }
    }
    
    private func removeOldestMemoryCacheItem() {
        guard !memoryCache.isEmpty else { return }
        
        let oldestKey = memoryCache.min { $0.value.lastAccessed < $1.value.lastAccessed }?.key
        if let key = oldestKey {
            memoryCache.removeValue(forKey: key)
        }
    }
    
    private func setupCacheCleanupTimer() {
        // Clean up cache every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task {
                await self?.performCacheCleanup()
            }
        }
    }
    
    private func performSizeBasedCleanup() async {
        // Remove least recently accessed items until under size limit
        let sortedMetadata = cacheMetadata.sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
        
        var currentSize = getCacheSize()
        
        for (key, metadata) in sortedMetadata {
            if currentSize <= maxCacheSize { break }
            
            await remove(forKey: key)
            currentSize -= metadata.size
            
            logger.debug("Removed cache item for size cleanup: \(key)")
        }
    }
    
    private func performAgeBasedCleanup() async {
        let cutoffDate = Date().addingTimeInterval(-maxCacheAge)
        let expiredKeys = cacheMetadata.compactMap { key, metadata in
            metadata.createdAt < cutoffDate ? key : nil
        }
        
        for key in expiredKeys {
            await remove(forKey: key)
            logger.debug("Removed expired cache item: \(key)")
        }
    }
    
    private func cleanupCorruptedFiles() async {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            
            for url in contents where url.pathExtension == "cache" {
                let key = url.deletingPathExtension().lastPathComponent
                
                // Try to read the file to check if it's corrupted
                do {
                    let _ = try Data(contentsOf: url)
                } catch {
                    // File is corrupted, remove it
                    try fileManager.removeItem(at: url)
                    cacheMetadata.removeValue(forKey: key)
                    memoryCache.removeValue(forKey: key)
                    logger.warning("Removed corrupted cache file: \(key)")
                }
            }
            
        } catch {
            logger.error("Failed to clean up corrupted files: \(error.localizedDescription)")
        }
    }
    
    private func validateCacheIntegrity() async {
        var invalidKeys: [String] = []
        
        for (key, metadata) in cacheMetadata {
            let fileURL = cacheDirectory.appendingPathComponent("\(key).cache")
            
            if !fileManager.fileExists(atPath: fileURL.path) {
                invalidKeys.append(key)
                continue
            }
            
            do {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                
                if fileSize != metadata.size {
                    invalidKeys.append(key)
                }
            } catch {
                invalidKeys.append(key)
            }
        }
        
        // Remove invalid entries
        for key in invalidKeys {
            await remove(forKey: key)
            logger.warning("Removed invalid cache entry during integrity check: \(key)")
        }
    }
    
    private func preloadCriticalData() async {
        // Preload frequently accessed data into memory cache
        // This is a placeholder for golf-specific critical data preloading
        logger.debug("Preloading critical cache data")
    }
    
    // MARK: - Metadata Management
    
    private func loadCacheMetadata() {
        cacheQueue.sync { [weak self] in
            guard let self = self else { return }
            
            let metadataURL = self.cacheDirectory.appendingPathComponent("\(self.metadataKey).meta")
            
            guard self.fileManager.fileExists(atPath: metadataURL.path) else {
                self.logger.debug("No cache metadata found, starting fresh")
                return
            }
            
            do {
                let data = try Data(contentsOf: metadataURL)
                let metadata = try JSONDecoder().decode([String: CacheMetadata].self, from: data)
                self.cacheMetadata = metadata
                
                self.logger.debug("Loaded cache metadata for \(metadata.count) items")
                
            } catch {
                self.logger.error("Failed to load cache metadata: \(error.localizedDescription)")
                // Start fresh if metadata is corrupted
                self.cacheMetadata = [:]
            }
        }
    }
    
    private func saveCacheMetadata() async {
        await cacheQueue.run { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try JSONEncoder().encode(self.cacheMetadata)
                let metadataURL = self.cacheDirectory.appendingPathComponent("\(self.metadataKey).meta")
                try data.write(to: metadataURL)
                
            } catch {
                self.logger.error("Failed to save cache metadata: \(error.localizedDescription)")
            }
        }
    }
    
    deinit {
        logger.debug("WatchCacheService deinitialized")
    }
}

// MARK: - Supporting Types

private class CachedItem {
    let data: Data
    var lastAccessed: Date
    
    init(data: Data, lastAccessed: Date) {
        self.data = data
        self.lastAccessed = lastAccessed
    }
}

private struct CacheMetadata: Codable {
    let key: String
    let size: Int64
    let createdAt: Date
    var lastAccessedAt: Date
    var accessCount: Int
}

// MARK: - Mock Watch Cache Service

class MockWatchCacheService: WatchCacheServiceProtocol, WatchBatteryOptimizable, WatchBackgroundRefreshable, WatchMemoryCleanable {
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "MockCache")
    private var mockStorage: [String: Data] = [:]
    private var isBatteryOptimized = false
    
    init() {
        logger.info("MockWatchCacheService initialized")
    }
    
    func store<T: Codable>(_ object: T, forKey key: String) async {
        do {
            let data = try JSONEncoder().encode(object)
            mockStorage[key] = data
            logger.debug("Mock stored object for key: \(key)")
        } catch {
            logger.error("Mock failed to store object for key \(key): \(error.localizedDescription)")
        }
    }
    
    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) async -> T? {
        guard let data = mockStorage[key] else {
            logger.debug("Mock no object found for key: \(key)")
            return nil
        }
        
        do {
            let object = try JSONDecoder().decode(type, from: data)
            logger.debug("Mock retrieved object for key: \(key)")
            return object
        } catch {
            logger.error("Mock failed to decode object for key \(key): \(error.localizedDescription)")
            return nil
        }
    }
    
    func remove(forKey key: String) async {
        mockStorage.removeValue(forKey: key)
        logger.debug("Mock removed object for key: \(key)")
    }
    
    func clearCache() async {
        mockStorage.removeAll()
        logger.debug("Mock cleared all cache")
    }
    
    func getCacheSize() -> Int64 {
        let totalBytes = mockStorage.values.reduce(0) { $0 + $1.count }
        return Int64(totalBytes)
    }
    
    func performCacheCleanup() async {
        // Mock cleanup - remove half the items randomly
        let keysToRemove = Array(mockStorage.keys.prefix(mockStorage.count / 2))
        for key in keysToRemove {
            mockStorage.removeValue(forKey: key)
        }
        logger.debug("Mock performed cache cleanup")
    }
    
    func cacheCourse(_ course: SharedGolfCourse) async {
        await store(course, forKey: "course_\(course.id)")
    }
    
    func getCachedCourse(id: String) async -> SharedGolfCourse? {
        return await retrieve(SharedGolfCourse.self, forKey: "course_\(id)")
    }
    
    func cacheActiveRound(_ round: ActiveGolfRound) async {
        await store(round, forKey: "active_round")
    }
    
    func getCachedActiveRound() async -> ActiveGolfRound? {
        return await retrieve(ActiveGolfRound.self, forKey: "active_round")
    }
    
    func enableBatteryOptimization() {
        isBatteryOptimized = true
        logger.debug("Mock battery optimization enabled")
    }
    
    func disableBatteryOptimization() {
        isBatteryOptimized = false
        logger.debug("Mock battery optimization disabled")
    }
    
    func performBackgroundRefresh() async {
        logger.debug("Mock background refresh performed")
    }
    
    func performMemoryCleanup() {
        logger.debug("Mock memory cleanup performed")
    }
    
    // Mock control methods
    var itemCount: Int { mockStorage.count }
    var batteryOptimizationEnabled: Bool { isBatteryOptimized }
}