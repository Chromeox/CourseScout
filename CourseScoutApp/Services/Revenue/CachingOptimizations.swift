import Foundation
import Combine
import os.log

// MARK: - Advanced Caching Infrastructure

protocol CacheServiceProtocol: AnyObject {
    func get<T: Codable>(_ key: String, type: T.Type) async -> T?
    func set<T: Codable>(_ key: String, value: T, expiration: TimeInterval?) async
    func remove(_ key: String) async
    func clear() async
    func preload(_ keys: [String]) async
    func getMetrics() -> CacheMetrics
}

// Enhanced Cache Service with performance optimization
class EnhancedCacheService: CacheServiceProtocol {
    private let logger = Logger(subsystem: "GolfFinder", category: "EnhancedCacheService")
    
    // Multi-level cache: Memory -> Disk -> Network
    private var memoryCache: [String: CacheEntry] = [:]
    private let diskCache = NSCache<NSString, CacheEntry>()
    private let cacheQueue = DispatchQueue(label: "cache.queue", qos: .utility)
    private let maxMemoryItems = 1000
    private let defaultExpiration: TimeInterval = 300 // 5 minutes
    
    // Performance metrics
    private var cacheMetrics = CacheMetrics()
    private var lastCleanup = Date()
    private let cleanupInterval: TimeInterval = 300 // 5 minutes
    
    init() {
        diskCache.countLimit = 5000
        diskCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        
        // Setup automatic cleanup
        Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task { await self?.performCleanup() }
        }
        
        logger.info("EnhancedCacheService initialized")
    }
    
    func get<T: Codable>(_ key: String, type: T.Type) async -> T? {
        return await cacheQueue.sync {
            let startTime = Date()
            defer {
                let duration = Date().timeIntervalSince(startTime)
                cacheMetrics.recordGet(duration: duration)
            }
            
            // Check memory cache first
            if let entry = memoryCache[key], entry.isValid {
                cacheMetrics.recordHit(.memory)
                logger.debug("Cache hit (memory): \(key)")
                return entry.getValue(type: type)
            }
            
            // Check disk cache
            if let entry = diskCache.object(forKey: NSString(string: key)), entry.isValid {
                // Promote to memory cache
                memoryCache[key] = entry
                cacheMetrics.recordHit(.disk)
                logger.debug("Cache hit (disk): \(key)")
                return entry.getValue(type: type)
            }
            
            cacheMetrics.recordMiss()
            logger.debug("Cache miss: \(key)")
            return nil
        }
    }
    
    func set<T: Codable>(_ key: String, value: T, expiration: TimeInterval? = nil) async {
        await cacheQueue.sync {
            let entry = CacheEntry(
                value: value,
                expiration: expiration ?? defaultExpiration,
                accessCount: 0,
                lastAccessed: Date()
            )
            
            // Store in memory cache
            memoryCache[key] = entry
            
            // Store in disk cache
            diskCache.setObject(entry, forKey: NSString(string: key))
            
            // Manage memory cache size
            if memoryCache.count > maxMemoryItems {
                await evictLeastRecentlyUsed()
            }
            
            cacheMetrics.recordSet()
            logger.debug("Cached: \(key)")
        }
    }
    
    func remove(_ key: String) async {
        await cacheQueue.sync {
            memoryCache.removeValue(forKey: key)
            diskCache.removeObject(forKey: NSString(string: key))
            cacheMetrics.recordRemove()
            logger.debug("Removed from cache: \(key)")
        }
    }
    
    func clear() async {
        await cacheQueue.sync {
            memoryCache.removeAll()
            diskCache.removeAllObjects()
            cacheMetrics.recordClear()
            logger.info("Cache cleared")
        }
    }
    
    func preload(_ keys: [String]) async {
        logger.info("Preloading \(keys.count) cache keys")
        for key in keys {
            // In a real implementation, this would fetch from network/database
            // For now, we'll mark these keys as prioritized
            if let entry = memoryCache[key] {
                entry.accessCount += 10 // Boost priority
            }
        }
    }
    
    func getMetrics() -> CacheMetrics {
        return cacheMetrics
    }
    
    // MARK: - Private Methods
    
    private func evictLeastRecentlyUsed() async {
        let sortedEntries = memoryCache.sorted { 
            $0.value.lastAccessed < $1.value.lastAccessed 
        }
        
        let itemsToRemove = sortedEntries.prefix(100) // Remove oldest 100 items
        for (key, _) in itemsToRemove {
            memoryCache.removeValue(forKey: key)
        }
        
        logger.debug("Evicted \(itemsToRemove.count) items from memory cache")
    }
    
    private func performCleanup() async {
        guard Date().timeIntervalSince(lastCleanup) >= cleanupInterval else { return }
        
        await cacheQueue.sync {
            let expiredKeys = memoryCache.compactMapValues { entry in
                entry.isValid ? nil : entry
            }.keys
            
            for key in expiredKeys {
                memoryCache.removeValue(forKey: String(key))
                diskCache.removeObject(forKey: NSString(string: String(key)))
            }
            
            lastCleanup = Date()
            cacheMetrics.recordCleanup(expiredItems: expiredKeys.count)
            
            if !expiredKeys.isEmpty {
                logger.info("Cleanup removed \(expiredKeys.count) expired items")
            }
        }
    }
}

// MARK: - Cache Entry

private class CacheEntry: NSObject {
    private let data: Data
    private let expirationDate: Date
    private(set) var accessCount: Int
    private(set) var lastAccessed: Date
    
    init<T: Codable>(value: T, expiration: TimeInterval, accessCount: Int, lastAccessed: Date) {
        self.data = (try? JSONEncoder().encode(value)) ?? Data()
        self.expirationDate = Date().addingTimeInterval(expiration)
        self.accessCount = accessCount
        self.lastAccessed = lastAccessed
        super.init()
    }
    
    var isValid: Bool {
        return Date() < expirationDate
    }
    
    func getValue<T: Codable>(type: T.Type) -> T? {
        accessCount += 1
        lastAccessed = Date()
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Cache Metrics

struct CacheMetrics {
    private(set) var totalGets: Int = 0
    private(set) var totalSets: Int = 0
    private(set) var totalRemoves: Int = 0
    private(set) var totalClears: Int = 0
    private(set) var memoryHits: Int = 0
    private(set) var diskHits: Int = 0
    private(set) var misses: Int = 0
    private(set) var averageGetDuration: TimeInterval = 0
    private(set) var lastCleanupItemsRemoved: Int = 0
    
    var hitRate: Double {
        let totalHits = memoryHits + diskHits
        guard totalGets > 0 else { return 0 }
        return Double(totalHits) / Double(totalGets)
    }
    
    var memoryHitRate: Double {
        guard totalGets > 0 else { return 0 }
        return Double(memoryHits) / Double(totalGets)
    }
    
    mutating func recordGet(duration: TimeInterval) {
        totalGets += 1
        averageGetDuration = (averageGetDuration * Double(totalGets - 1) + duration) / Double(totalGets)
    }
    
    mutating func recordSet() {
        totalSets += 1
    }
    
    mutating func recordRemove() {
        totalRemoves += 1
    }
    
    mutating func recordClear() {
        totalClears += 1
    }
    
    mutating func recordHit(_ level: CacheLevel) {
        switch level {
        case .memory:
            memoryHits += 1
        case .disk:
            diskHits += 1
        }
    }
    
    mutating func recordMiss() {
        misses += 1
    }
    
    mutating func recordCleanup(expiredItems: Int) {
        lastCleanupItemsRemoved = expiredItems
    }
}

enum CacheLevel {
    case memory
    case disk
}

// MARK: - Cacheable Protocol

protocol Cacheable {
    var cacheKey: String { get }
    var cacheDuration: TimeInterval { get }
}

extension Cacheable {
    var cacheDuration: TimeInterval { return 300 } // Default 5 minutes
}

// MARK: - Cache-Aware Service Base Class

class CacheAwareService {
    protected let cache: CacheServiceProtocol
    private let logger: Logger
    
    init(cache: CacheServiceProtocol, category: String) {
        self.cache = cache
        self.logger = Logger(subsystem: "GolfFinder", category: category)
    }
    
    func getCachedOrFetch<T: Codable & Cacheable>(
        _ item: T.Type,
        key: String? = nil,
        fetcher: @escaping () async throws -> T
    ) async throws -> T {
        let cacheKey = key ?? "\(T.self)"
        
        // Try cache first
        if let cached = await cache.get(cacheKey, type: T.self) {
            logger.debug("Cache hit for \(cacheKey)")
            return cached
        }
        
        // Fetch fresh data
        logger.debug("Cache miss for \(cacheKey), fetching fresh data")
        let fresh = try await fetcher()
        
        // Cache the result
        await cache.set(cacheKey, value: fresh, expiration: fresh.cacheDuration)
        
        return fresh
    }
    
    func invalidateCache(key: String) async {
        await cache.remove(key)
        logger.debug("Invalidated cache for \(key)")
    }
}

// MARK: - Performance Optimizations

// Request Batching for efficient API usage
class RequestBatcher<Request, Response> {
    private let batchSize: Int
    private let flushInterval: TimeInterval
    private var pendingRequests: [(Request, CheckedContinuation<Response, Error>)] = []
    private let processor: ([Request]) async throws -> [Response]
    private var flushTimer: Timer?
    
    init(batchSize: Int = 10, flushInterval: TimeInterval = 0.1, processor: @escaping ([Request]) async throws -> [Response]) {
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.processor = processor
    }
    
    func add(_ request: Request) async throws -> Response {
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests.append((request, continuation))
            
            if pendingRequests.count >= batchSize {
                flushBatch()
            } else if flushTimer == nil {
                flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: false) { [weak self] _ in
                    self?.flushBatch()
                }
            }
        }
    }
    
    private func flushBatch() {
        guard !pendingRequests.isEmpty else { return }
        
        let currentBatch = pendingRequests
        pendingRequests.removeAll()
        flushTimer?.invalidate()
        flushTimer = nil
        
        Task {
            do {
                let requests = currentBatch.map { $0.0 }
                let responses = try await processor(requests)
                
                for (index, (_, continuation)) in currentBatch.enumerated() {
                    if index < responses.count {
                        continuation.resume(returning: responses[index])
                    } else {
                        continuation.resume(throwing: BatchError.insufficientResponses)
                    }
                }
            } catch {
                for (_, continuation) in currentBatch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum BatchError: Error, LocalizedError {
    case insufficientResponses
    
    var errorDescription: String? {
        switch self {
        case .insufficientResponses:
            return "Batch processor returned insufficient responses"
        }
    }
}

// MARK: - Circuit Breaker Pattern

class CircuitBreaker {
    private let failureThreshold: Int
    private let recoveryTimeout: TimeInterval
    private let halfOpenMaxCalls: Int
    
    private var state: CircuitBreakerState = .closed
    private var failureCount = 0
    private var lastFailureTime: Date?
    private var halfOpenCalls = 0
    
    init(failureThreshold: Int = 5, recoveryTimeout: TimeInterval = 60, halfOpenMaxCalls: Int = 3) {
        self.failureThreshold = failureThreshold
        self.recoveryTimeout = recoveryTimeout
        self.halfOpenMaxCalls = halfOpenMaxCalls
    }
    
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        switch state {
        case .open:
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) >= recoveryTimeout {
                state = .halfOpen
                halfOpenCalls = 0
            } else {
                throw CircuitBreakerError.circuitOpen
            }
            
        case .halfOpen:
            guard halfOpenCalls < halfOpenMaxCalls else {
                throw CircuitBreakerError.circuitOpen
            }
            halfOpenCalls += 1
            
        case .closed:
            break
        }
        
        do {
            let result = try await operation()
            onSuccess()
            return result
        } catch {
            onFailure()
            throw error
        }
    }
    
    private func onSuccess() {
        failureCount = 0
        if state == .halfOpen {
            state = .closed
        }
    }
    
    private func onFailure() {
        failureCount += 1
        lastFailureTime = Date()
        
        if failureCount >= failureThreshold {
            state = .open
        }
    }
}

enum CircuitBreakerState {
    case closed
    case open
    case halfOpen
}

enum CircuitBreakerError: Error, LocalizedError {
    case circuitOpen
    
    var errorDescription: String? {
        switch self {
        case .circuitOpen:
            return "Circuit breaker is open"
        }
    }
}

// MARK: - Retry with Exponential Backoff

struct RetryPolicy {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let backoffMultiplier: Double
    
    static let `default` = RetryPolicy(
        maxAttempts: 3,
        baseDelay: 1.0,
        maxDelay: 30.0,
        backoffMultiplier: 2.0
    )
    
    func execute<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                guard attempt < maxAttempts else { break }
                
                let delay = min(baseDelay * pow(backoffMultiplier, Double(attempt - 1)), maxDelay)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? RetryError.maxAttemptsExceeded
    }
}

enum RetryError: Error, LocalizedError {
    case maxAttemptsExceeded
    
    var errorDescription: String? {
        switch self {
        case .maxAttemptsExceeded:
            return "Maximum retry attempts exceeded"
        }
    }
}