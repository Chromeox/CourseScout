import Foundation
import UIKit
import SwiftUI
import Kingfisher
import Combine
import os.log

// MARK: - Optimized Image Cache Service

@MainActor
class OptimizedImageCacheService: ImageCacheServiceProtocol, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = OptimizedImageCacheService()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinder.Performance", category: "ImageCache")
    
    // Kingfisher optimized configuration
    private let imageCache: ImageCache
    private let imageDownloader: ImageDownloader
    
    // Advanced caching layers
    private let preloadCache = PreloadImageCache()
    private let thumbnailCache = ThumbnailCache()
    private let priorityQueue = ImageLoadPriorityQueue()
    
    // Performance monitoring
    @Published var cacheStatistics = ImageCacheStatistics()
    private var performanceMetrics = ImagePerformanceMetrics()
    
    // Memory management
    private var subscriptions = Set<AnyCancellable>()
    private let memoryPressureHandler = ImageMemoryPressureHandler()
    
    // Configuration
    private let maxCacheSize: UInt = 500 * 1024 * 1024 // 500MB
    private let maxMemoryCacheSize: UInt = 100 * 1024 * 1024 // 100MB
    private let maxCachePeriod: TimeInterval = 7 * 24 * 3600 // 7 days
    private let thumbnailSize = CGSize(width: 300, height: 200)
    
    // MARK: - Initialization
    
    private init() {
        // Configure Kingfisher for optimal performance
        self.imageCache = ImageCache.default
        self.imageDownloader = ImageDownloader.default
        
        setupKingfisherOptimizations()
        setupMemoryManagement()
        setupPerformanceMonitoring()
        
        logger.info("OptimizedImageCacheService initialized with advanced caching")
    }
    
    // MARK: - Image Loading Interface
    
    func loadImage(from url: String, priority: ImageLoadPriority = .normal) async -> UIImage? {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let imageURL = URL(string: url) else {
            logger.error("Invalid image URL: \(url)")
            return nil
        }
        
        // Check thumbnail cache first for thumbnails
        if priority == .thumbnail, let thumbnail = await thumbnailCache.getThumbnail(for: url) {
            recordCacheHit(url: url, loadTime: CFAbsoluteTimeGetCurrent() - startTime, source: .thumbnailCache)
            return thumbnail
        }
        
        // Add to priority queue
        priorityQueue.addRequest(url: url, priority: priority)
        
        do {
            let image = try await withCheckedThrowingContinuation { continuation in
                let options: KingfisherOptionsInfo = buildKingfisherOptions(for: priority)
                
                KingfisherManager.shared.retrieveImage(
                    with: imageURL,
                    options: options
                ) { result in
                    switch result {
                    case .success(let imageResult):
                        continuation.resume(returning: imageResult.image)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            recordCacheHit(url: url, loadTime: loadTime, source: imageCache.imageCachedType(forKey: url).cacheType)
            
            // Cache thumbnail if needed
            if priority == .thumbnail {
                await thumbnailCache.storeThumbnail(image, for: url)
            }
            
            return image
            
        } catch {
            logger.error("Failed to load image from \(url): \(error.localizedDescription)")
            recordCacheMiss(url: url, loadTime: CFAbsoluteTimeGetCurrent() - startTime)
            return nil
        }
    }
    
    func preloadImages(_ urls: [String], priority: ImageLoadPriority = .low) async {
        logger.info("Preloading \(urls.count) images with priority: \(priority)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Use TaskGroup for concurrent preloading with controlled concurrency
        await withTaskGroup(of: Void.self) { group in
            let maxConcurrentPreloads = min(urls.count, 3) // Limit concurrent preloads
            
            for (index, url) in urls.enumerated() {
                if index < maxConcurrentPreloads {
                    group.addTask {
                        await self.preloadSingleImage(url: url, priority: priority)
                    }
                }
            }
            
            // Add remaining tasks as others complete
            var nextIndex = maxConcurrentPreloads
            while nextIndex < urls.count {
                await group.next()
                
                if nextIndex < urls.count {
                    let url = urls[nextIndex]
                    group.addTask {
                        await self.preloadSingleImage(url: url, priority: priority)
                    }
                    nextIndex += 1
                }
            }
        }
        
        let preloadTime = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("Preloading completed in \(String(format: "%.3f", preloadTime))s")
        
        performanceMetrics.recordPreloadBatch(urls: urls, duration: preloadTime)
    }
    
    func generateThumbnail(from url: String, size: CGSize = CGSize(width: 300, height: 200)) async -> UIImage? {
        // Check thumbnail cache first
        if let cachedThumbnail = await thumbnailCache.getThumbnail(for: url, size: size) {
            return cachedThumbnail
        }
        
        // Load full image and generate thumbnail
        guard let fullImage = await loadImage(from: url, priority: .normal) else {
            return nil
        }
        
        let thumbnail = await generateThumbnailFromImage(fullImage, targetSize: size)
        
        // Cache the generated thumbnail
        if let thumbnail = thumbnail {
            await thumbnailCache.storeThumbnail(thumbnail, for: url, size: size)
        }
        
        return thumbnail
    }
    
    // MARK: - Course-Specific Optimizations
    
    func preloadCourseImages(_ course: GolfCourse) async {
        let imageURLs = course.images.map { $0.url }
        
        // Prioritize primary image
        if let primaryImageUrl = course.primaryImage {
            await preloadSingleImage(url: primaryImageUrl, priority: .high)
        }
        
        // Preload other images with lower priority
        let otherImages = imageURLs.filter { $0 != course.primaryImage }
        await preloadImages(otherImages, priority: .low)
        
        logger.debug("Preloaded images for course: \(course.name)")
    }
    
    func preloadCourseThumbnails(_ courses: [GolfCourse]) async {
        let thumbnailURLs = courses.compactMap { $0.primaryImage }
        
        await withTaskGroup(of: Void.self) { group in
            for url in thumbnailURLs {
                group.addTask {
                    _ = await self.generateThumbnail(from: url, size: self.thumbnailSize)
                }
            }
        }
        
        logger.info("Preloaded thumbnails for \(courses.count) courses")
    }
    
    func optimizeForMapView(_ courses: [GolfCourse]) async {
        // Preload only thumbnails for map annotations to save memory
        let priorityCourses = Array(courses.prefix(20)) // Limit to visible courses
        await preloadCourseThumbnails(priorityCourses)
    }
    
    // MARK: - Cache Management
    
    func clearCache(olderThan timeInterval: TimeInterval) async {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        
        await imageCache.clearExpiredDiskCache()
        await thumbnailCache.clearExpiredCache(olderThan: cutoffDate)
        
        updateCacheStatistics()
        logger.info("Cleared cache older than \(timeInterval / 3600) hours")
    }
    
    func clearAllCache() async {
        await imageCache.clearCache()
        await thumbnailCache.clearAll()
        await preloadCache.clearAll()
        
        updateCacheStatistics()
        logger.info("Cleared all image cache")
    }
    
    func optimizeCache() async {
        logger.info("Starting cache optimization")
        
        // Clear expired entries
        await imageCache.cleanExpiredDiskCache()
        await thumbnailCache.performMaintenance()
        
        // Check memory pressure and adjust if needed
        await memoryPressureHandler.optimizeForCurrentPressure()
        
        updateCacheStatistics()
        
        logger.info("Cache optimization completed")
    }
    
    func getCacheSize() async -> UInt64 {
        let diskCacheSize = await imageCache.diskStorageSize
        let thumbnailCacheSize = await thumbnailCache.getCacheSize()
        
        return diskCacheSize + thumbnailCacheSize
    }
    
    // MARK: - Performance Monitoring
    
    func getPerformanceMetrics() -> ImagePerformanceMetrics {
        return performanceMetrics
    }
    
    func resetPerformanceMetrics() {
        performanceMetrics = ImagePerformanceMetrics()
    }
    
    private func updateCacheStatistics() {
        Task {
            let diskSize = await imageCache.diskStorageSize
            let memorySize = await imageCache.memoryStorageSize
            let thumbnailSize = await thumbnailCache.getCacheSize()
            
            cacheStatistics = ImageCacheStatistics(
                diskCacheSize: diskSize,
                memoryCacheSize: memorySize,
                thumbnailCacheSize: thumbnailSize,
                totalCacheSize: diskSize + thumbnailSize,
                hitRate: performanceMetrics.cacheHitRate,
                averageLoadTime: performanceMetrics.averageLoadTime
            )
        }
    }
}

// MARK: - Private Helper Methods

private extension OptimizedImageCacheService {
    
    func setupKingfisherOptimizations() {
        // Configure disk cache
        imageCache.diskStorage.config.sizeLimit = maxCacheSize
        imageCache.diskStorage.config.expiration = .days(7)
        imageCache.diskStorage.config.cleanExpiredTimeout = 300 // 5 minutes
        
        // Configure memory cache
        imageCache.memoryStorage.config.totalCostLimit = Int(maxMemoryCacheSize)
        imageCache.memoryStorage.config.countLimit = 100
        imageCache.memoryStorage.config.expiration = .seconds(3600) // 1 hour
        
        // Configure downloader
        imageDownloader.downloadTimeout = 30.0
        imageDownloader.sessionConfiguration.httpMaximumConnectionsPerHost = 4
        imageDownloader.sessionConfiguration.urlCredentialStorage = nil
        imageDownloader.sessionConfiguration.urlCache = nil // Rely on Kingfisher's cache
        
        // Enable progressive JPEG support for faster loading
        imageDownloader.sessionConfiguration.httpAdditionalHeaders = [
            "Accept": "image/webp,image/jpeg,image/png,image/*,*/*;q=0.8"
        ]
        
        logger.debug("Kingfisher optimizations configured")
    }
    
    func setupMemoryManagement() {
        // Monitor memory pressure
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.handleMemoryWarning()
                }
            }
            .store(in: &subscriptions)
        
        // Monitor app lifecycle
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.handleAppBackground()
                }
            }
            .store(in: &subscriptions)
    }
    
    func setupPerformanceMonitoring() {
        // Update statistics periodically
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.updateCacheStatistics()
        }
    }
    
    func buildKingfisherOptions(for priority: ImageLoadPriority) -> KingfisherOptionsInfo {
        var options: KingfisherOptionsInfo = [
            .cacheSerializer(FormatIndicatedCacheSerializer.png),
            .scaleFactor(UIScreen.main.scale)
        ]
        
        switch priority {
        case .high:
            options.append(.downloadPriority(1.0))
            options.append(.cacheMemoryOnly)
        case .normal:
            options.append(.downloadPriority(0.5))
        case .low:
            options.append(.downloadPriority(0.1))
            options.append(.backgroundDecode)
        case .thumbnail:
            options.append(.downloadPriority(0.7))
            options.append(.processor(DownsamplingImageProcessor(size: thumbnailSize)))
            options.append(.backgroundDecode)
        }
        
        return options
    }
    
    func preloadSingleImage(url: String, priority: ImageLoadPriority) async {
        guard let imageURL = URL(string: url) else { return }
        
        let options = buildKingfisherOptions(for: priority)
        let prefetcher = ImagePrefetcher(urls: [imageURL], options: options)
        
        await withCheckedContinuation { continuation in
            prefetcher.start {
                continuation.resume()
            }
        }
    }
    
    func generateThumbnailFromImage(_ image: UIImage, targetSize: CGSize) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let thumbnail = image.resized(to: targetSize)
                continuation.resume(returning: thumbnail)
            }
        }
    }
    
    func recordCacheHit(url: String, loadTime: CFAbsoluteTime, source: ImageCacheType) {
        performanceMetrics.recordCacheHit(url: url, loadTime: loadTime, source: source)
        priorityQueue.removeRequest(url: url)
    }
    
    func recordCacheMiss(url: String, loadTime: CFAbsoluteTime) {
        performanceMetrics.recordCacheMiss(url: url, loadTime: loadTime)
        priorityQueue.removeRequest(url: url)
    }
    
    func handleMemoryWarning() async {
        logger.warning("Received memory warning, clearing memory cache")
        
        // Clear memory cache but preserve disk cache
        imageCache.clearMemoryCache()
        await thumbnailCache.clearMemoryCache()
        
        // Update statistics
        updateCacheStatistics()
    }
    
    func handleAppBackground() async {
        // Optimize for background state
        imageCache.clearMemoryCache()
        await optimizeCache()
    }
}

// MARK: - Advanced Caching Components

private actor PreloadImageCache {
    private var preloadedImages: [String: PreloadedImage] = [:]
    private let maxPreloadedImages = 50
    
    struct PreloadedImage {
        let image: UIImage
        let timestamp: Date
        let priority: ImageLoadPriority
    }
    
    func store(_ image: UIImage, for url: String, priority: ImageLoadPriority) {
        if preloadedImages.count >= maxPreloadedImages {
            // Remove oldest image
            if let oldestKey = preloadedImages.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                preloadedImages.removeValue(forKey: oldestKey)
            }
        }
        
        preloadedImages[url] = PreloadedImage(image: image, timestamp: Date(), priority: priority)
    }
    
    func get(for url: String) -> UIImage? {
        return preloadedImages[url]?.image
    }
    
    func clearAll() {
        preloadedImages.removeAll()
    }
}

private actor ThumbnailCache {
    private var thumbnails: [String: CachedThumbnail] = [:]
    private let maxThumbnails = 200
    private let maxAge: TimeInterval = 86400 // 24 hours
    
    private struct CachedThumbnail {
        let image: UIImage
        let timestamp: Date
        let size: CGSize
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 86400 // 24 hours
        }
    }
    
    func getThumbnail(for url: String, size: CGSize = CGSize(width: 300, height: 200)) -> UIImage? {
        guard let cached = thumbnails[cacheKey(url: url, size: size)],
              !cached.isExpired else {
            return nil
        }
        return cached.image
    }
    
    func storeThumbnail(_ image: UIImage, for url: String, size: CGSize = CGSize(width: 300, height: 200)) {
        if thumbnails.count >= maxThumbnails {
            // Remove expired thumbnails first
            removeExpiredThumbnails()
            
            // If still over limit, remove oldest
            if thumbnails.count >= maxThumbnails {
                if let oldestKey = thumbnails.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                    thumbnails.removeValue(forKey: oldestKey)
                }
            }
        }
        
        let key = cacheKey(url: url, size: size)
        thumbnails[key] = CachedThumbnail(image: image, timestamp: Date(), size: size)
    }
    
    func clearExpiredCache(olderThan date: Date) {
        thumbnails = thumbnails.filter { $0.value.timestamp > date }
    }
    
    func clearMemoryCache() {
        thumbnails.removeAll()
    }
    
    func clearAll() {
        thumbnails.removeAll()
    }
    
    func getCacheSize() -> UInt64 {
        return UInt64(thumbnails.count * 50000) // Approximate size
    }
    
    func performMaintenance() {
        removeExpiredThumbnails()
    }
    
    private func removeExpiredThumbnails() {
        thumbnails = thumbnails.filter { !$0.value.isExpired }
    }
    
    private func cacheKey(url: String, size: CGSize) -> String {
        return "\(url)_\(Int(size.width))x\(Int(size.height))"
    }
}

private class ImageLoadPriorityQueue {
    private var requests: [String: ImageLoadRequest] = [:]
    private let queue = DispatchQueue(label: "ImagePriorityQueue", attributes: .concurrent)
    
    private struct ImageLoadRequest {
        let url: String
        let priority: ImageLoadPriority
        let timestamp: Date
    }
    
    func addRequest(url: String, priority: ImageLoadPriority) {
        queue.async(flags: .barrier) {
            self.requests[url] = ImageLoadRequest(url: url, priority: priority, timestamp: Date())
        }
    }
    
    func removeRequest(url: String) {
        queue.async(flags: .barrier) {
            self.requests.removeValue(forKey: url)
        }
    }
    
    func getPendingRequests() -> [ImageLoadRequest] {
        return queue.sync {
            return Array(requests.values).sorted { $0.priority.rawValue > $1.priority.rawValue }
        }
    }
}

private class ImageMemoryPressureHandler {
    private let logger = Logger(subsystem: "GolfFinder.Performance", category: "ImageMemoryPressure")
    
    func optimizeForCurrentPressure() async {
        let memoryUsage = getCurrentMemoryUsage()
        
        if memoryUsage > 0.8 { // 80% memory usage
            await performAggressiveOptimization()
        } else if memoryUsage > 0.6 { // 60% memory usage
            await performModerateOptimization()
        }
    }
    
    private func getCurrentMemoryUsage() -> Double {
        // Get current memory usage percentage
        let info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: UnsafeMutablePointer<mach_task_basic_info>.allocate(capacity: 1).pointee) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = UInt64(info.resident_size)
        
        return Double(usedMemory) / Double(physicalMemory)
    }
    
    private func performModerateOptimization() async {
        logger.info("Performing moderate memory optimization")
        ImageCache.default.clearMemoryCache()
    }
    
    private func performAggressiveOptimization() async {
        logger.warning("Performing aggressive memory optimization")
        ImageCache.default.clearMemoryCache()
        await ImageCache.default.clearExpiredDiskCache()
    }
}

// MARK: - Supporting Types

enum ImageLoadPriority: Int, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case thumbnail = 3
}

enum ImageCacheType {
    case memory
    case disk
    case thumbnailCache
    case network
    
    var cacheType: ImageCacheType {
        return self
    }
}

struct ImageCacheStatistics {
    let diskCacheSize: UInt64
    let memoryCacheSize: UInt64
    let thumbnailCacheSize: UInt64
    let totalCacheSize: UInt64
    let hitRate: Double
    let averageLoadTime: Double
    
    init() {
        self.diskCacheSize = 0
        self.memoryCacheSize = 0
        self.thumbnailCacheSize = 0
        self.totalCacheSize = 0
        self.hitRate = 0
        self.averageLoadTime = 0
    }
    
    init(diskCacheSize: UInt64, memoryCacheSize: UInt64, thumbnailCacheSize: UInt64, 
         totalCacheSize: UInt64, hitRate: Double, averageLoadTime: Double) {
        self.diskCacheSize = diskCacheSize
        self.memoryCacheSize = memoryCacheSize
        self.thumbnailCacheSize = thumbnailCacheSize
        self.totalCacheSize = totalCacheSize
        self.hitRate = hitRate
        self.averageLoadTime = averageLoadTime
    }
    
    var formattedDiskCacheSize: String {
        ByteCountFormatter().string(fromByteCount: Int64(diskCacheSize))
    }
    
    var formattedMemoryCacheSize: String {
        ByteCountFormatter().string(fromByteCount: Int64(memoryCacheSize))
    }
    
    var formattedTotalCacheSize: String {
        ByteCountFormatter().string(fromByteCount: Int64(totalCacheSize))
    }
    
    var formattedHitRate: String {
        String(format: "%.1f%%", hitRate * 100)
    }
    
    var formattedAverageLoadTime: String {
        String(format: "%.3fs", averageLoadTime)
    }
}

struct ImagePerformanceMetrics {
    private var totalRequests = 0
    private var cacheHits = 0
    private var totalLoadTime: CFAbsoluteTime = 0
    private var preloadBatches: [PreloadBatch] = []
    
    private struct PreloadBatch {
        let urlCount: Int
        let duration: CFAbsoluteTime
        let timestamp: Date
    }
    
    var cacheHitRate: Double {
        return totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0
    }
    
    var averageLoadTime: Double {
        return totalRequests > 0 ? totalLoadTime / Double(totalRequests) : 0
    }
    
    mutating func recordCacheHit(url: String, loadTime: CFAbsoluteTime, source: ImageCacheType) {
        totalRequests += 1
        cacheHits += 1
        totalLoadTime += loadTime
    }
    
    mutating func recordCacheMiss(url: String, loadTime: CFAbsoluteTime) {
        totalRequests += 1
        totalLoadTime += loadTime
    }
    
    mutating func recordPreloadBatch(urls: [String], duration: CFAbsoluteTime) {
        preloadBatches.append(PreloadBatch(
            urlCount: urls.count,
            duration: duration,
            timestamp: Date()
        ))
        
        // Keep only recent batches
        if preloadBatches.count > 10 {
            preloadBatches.removeFirst(preloadBatches.count - 10)
        }
    }
}

// MARK: - UIImage Extensions

extension UIImage {
    func resized(to targetSize: CGSize) -> UIImage {
        let size = self.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        
        let ratio = min(widthRatio, heightRatio)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        let rect = CGRect(origin: .zero, size: newSize)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        self.draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}

// MARK: - Extension for cache type detection

extension ImageCachedType {
    var cacheType: ImageCacheType {
        switch self {
        case .none:
            return .network
        case .memory:
            return .memory
        case .disk:
            return .disk
        }
    }
}