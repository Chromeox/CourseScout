import Foundation
import WatchConnectivity
import os.log
import Combine
import CoreHaptics

// MARK: - Advanced Watch Connectivity Service Implementation

@MainActor
class OptimizedWatchConnectivityService: NSObject, OptimizedWatchConnectivityServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let session: WCSession
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "OptimizedWatchConnectivity")
    private let messageQueue = DispatchQueue(label: "GolfOptimizedConnectivity", qos: .userInitiated)
    private let delegateQueue = DispatchQueue.main
    
    // Enhanced delegate management
    private var delegates: [WeakOptimizedWatchConnectivityDelegate] = []
    
    // Advanced message management
    private var pendingMessages: [String: OptimizedPendingMessage] = [:]
    private var messageTimeouts: [String: Timer] = [:]
    private var priorityQueue = PriorityMessageQueue()
    private var compressionCache = CompressionCache()
    
    // Performance tracking
    @Published private var metrics = WatchConnectivityMetrics()
    @Published private(set) var connectionQuality: ConnectionQuality = .unknown
    private var batteryOptimized = false
    private var performanceOptimized = false
    
    // Application context backup
    private var lastApplicationContext: [String: Any] = [:]
    private var contextUpdateTimer: Timer?
    
    // Quality monitoring
    private var latencyHistory: [TimeInterval] = []
    private var errorCount = 0
    private var successCount = 0
    
    // Background task management
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    // MARK: - Initialization
    
    override init() {
        self.session = WCSession.default
        super.init()
        
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
            startConnectionMonitoring()
            logger.info("OptimizedWatchConnectivityService initialized and activated")
        } else {
            logger.warning("WatchConnectivity not supported on this device")
        }
    }
    
    // MARK: - Public Properties
    
    var isSupported: Bool {
        return WCSession.isSupported()
    }
    
    var isReachable: Bool {
        guard isSupported else { return false }
        return session.isReachable
    }
    
    var activationState: WCSessionActivationState {
        guard isSupported else { return .notActivated }
        return session.activationState
    }
    
    // MARK: - Optimized Data Transfer Methods
    
    func sendMessage(_ message: [String: Any], priority: MessagePriority = .normal, replyHandler: (([String: Any]) -> Void)? = nil, errorHandler: ((Error) -> Void)? = nil) {
        guard isSupported && activationState == .activated else {
            let error = WatchConnectivityError.sessionNotActivated
            logger.error("Cannot send message: session not activated")
            errorHandler?(error)
            return
        }
        
        let messageId = UUID().uuidString
        let optimizedMessage = optimizeMessage(message, priority: priority)
        
        Task {
            await enqueueMessage(
                id: messageId,
                message: optimizedMessage,
                priority: priority,
                replyHandler: replyHandler,
                errorHandler: errorHandler
            )
        }
    }
    
    func sendMessageOptimized<T: Codable>(_ data: T, priority: MessagePriority = .normal) async throws {
        let startTime = Date()
        
        do {
            let jsonData = try JSONEncoder().encode(data)
            let compressedData = compressionCache.compress(jsonData)
            let base64String = compressedData.base64EncodedString()
            
            let message: [String: Any] = [
                "type": String(describing: T.self),
                "data": base64String,
                "compressed": true,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            return try await withCheckedThrowingContinuation { continuation in
                sendMessage(message, priority: priority, replyHandler: { response in
                    let latency = Date().timeIntervalSince(startTime)
                    Task { @MainActor in
                        await self.updateMetrics(latency: latency, success: true)
                    }
                    continuation.resume()
                }, errorHandler: { error in
                    Task { @MainActor in
                        await self.updateMetrics(latency: nil, success: false)
                    }
                    continuation.resume(throwing: error)
                })
            }
        } catch {
            await updateMetrics(latency: nil, success: false)
            throw error
        }
    }
    
    func updateApplicationContext(_ context: [String: Any], compression: Bool = false) throws {
        guard isSupported && activationState == .activated else {
            throw WatchConnectivityError.sessionNotActivated
        }
        
        var finalContext = context
        
        // Apply compression if requested
        if compression {
            finalContext = compressionCache.compressContext(context)
        }
        
        // Avoid sending duplicate context
        if NSDictionary(dictionary: finalContext).isEqual(to: lastApplicationContext) {
            logger.debug("Application context unchanged, skipping update")
            return
        }
        
        do {
            try session.updateApplicationContext(finalContext)
            lastApplicationContext = finalContext
            logger.debug("Updated application context successfully with compression: \(compression)")
        } catch {
            logger.error("Failed to update application context: \(error.localizedDescription)")
            throw error
        }
    }
    
    func transferUserInfo(_ userInfo: [String: Any], priority: TransferPriority = .normal) -> WCSessionUserInfoTransfer? {
        guard isSupported && activationState == .activated else {
            logger.error("Cannot transfer user info: session not activated")
            return nil
        }
        
        let optimizedUserInfo = optimizeUserInfo(userInfo, priority: priority)
        let transfer = session.transferUserInfo(optimizedUserInfo)
        logger.debug("Started user info transfer with priority: \(priority)")
        return transfer
    }
    
    func transferFileOptimized(at url: URL, metadata: [String: Any]? = nil, compression: Bool = false) -> WCSessionFileTransfer? {
        guard isSupported && activationState == .activated else {
            logger.error("Cannot transfer file: session not activated")
            return nil
        }
        
        let finalURL: URL
        let finalMetadata = metadata ?? [:]
        
        if compression {
            // Compress file if requested
            do {
                finalURL = try compressionCache.compressFile(at: url)
                logger.debug("File compressed for transfer")
            } catch {
                logger.error("File compression failed: \(error.localizedDescription)")
                finalURL = url
            }
        } else {
            finalURL = url
        }
        
        let transfer = session.transferFile(finalURL, metadata: finalMetadata)
        logger.debug("Started file transfer with compression: \(compression)")
        return transfer
    }
    
    // MARK: - Golf-Specific Optimized Methods
    
    func sendScoreUpdate(_ scorecard: SharedScorecard, priority: MessagePriority = .high) async throws {
        logger.info("Sending optimized score update for round: \(scorecard.id)")
        
        let message: [String: Any] = [
            "type": "scoreUpdate",
            "priority": priority.rawValue,
            "scorecard": try JSONEncoder().encode(scorecard).base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970,
            "essential": scorecard.essentialData
        ]
        
        try await sendMessageOptimized(message, priority: priority)
    }
    
    func sendCourseData(_ course: SharedGolfCourse, useCache: Bool = true) async throws {
        logger.info("Sending optimized course data: \(course.name)")
        
        // Check cache first
        if useCache, let cachedData = compressionCache.getCachedCourseData(courseId: course.id) {
            logger.debug("Using cached course data")
            return
        }
        
        let message: [String: Any] = [
            "type": "courseData",
            "course": try JSONEncoder().encode(course).base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        try await sendMessageOptimized(message, priority: .normal)
        
        if useCache {
            compressionCache.cacheCourseData(course: course)
        }
    }
    
    func sendActiveRoundUpdate(_ round: ActiveGolfRound) async throws {
        logger.info("Sending optimized active round update: \(round.courseName), hole \(round.currentHole)")
        
        let roundData = try JSONEncoder().encode(round)
        let message: [String: Any] = [
            "type": "activeRoundUpdate",
            "round": roundData.base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970,
            "essential": [
                "currentHole": round.currentHole,
                "totalScore": round.totalScore,
                "scoreRelativeToPar": round.scoreRelativeToPar
            ]
        ]
        
        // Use application context for persistence
        try updateApplicationContext([
            "activeRound": roundData.base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ], compression: true)
        
        // Also send as high-priority message for immediate update
        try await sendMessageOptimized(message, priority: .high)
    }
    
    func sendHealthMetricsUpdate(_ metrics: WatchHealthMetrics) async throws {
        logger.info("Sending health metrics update")
        
        let message: [String: Any] = [
            "type": "healthMetricsUpdate",
            "metrics": try JSONEncoder().encode(metrics).base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        try await sendMessageOptimized(message, priority: .normal)
    }
    
    func requestCourseInformation(courseId: String, priority: MessagePriority = .normal) async throws -> SharedGolfCourse? {
        logger.info("Requesting course information: \(courseId)")
        
        let message: [String: Any] = [
            "type": "requestCourseInfo",
            "courseId": courseId,
            "priority": priority.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            sendMessage(message, priority: priority, replyHandler: { response in
                Task {
                    if let courseData = response["course"] as? String,
                       let data = Data(base64Encoded: courseData),
                       let course = try? JSONDecoder().decode(SharedGolfCourse.self, from: data) {
                        continuation.resume(returning: course)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }
    
    func requestCurrentRound(priority: MessagePriority = .normal) async throws -> ActiveGolfRound? {
        logger.info("Requesting current round information")
        
        let message: [String: Any] = [
            "type": "requestCurrentRound",
            "priority": priority.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            sendMessage(message, priority: priority, replyHandler: { response in
                Task {
                    if let roundData = response["round"] as? String,
                       let data = Data(base64Encoded: roundData),
                       let round = try? JSONDecoder().decode(ActiveGolfRound.self, from: data) {
                        continuation.resume(returning: round)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }
    
    // MARK: - Performance Optimization
    
    func optimizeForBattery() {
        logger.info("Optimizing for battery conservation")
        batteryOptimized = true
        
        // Reduce message queue processing frequency
        priorityQueue.setBatteryOptimized(true)
        
        // Use more compression
        compressionCache.setBatteryMode(true)
        
        // Reduce connection quality monitoring frequency
        connectionQuality = .batterySaver
    }
    
    func optimizeForPerformance() {
        logger.info("Optimizing for performance")
        performanceOptimized = true
        batteryOptimized = false
        
        // Increase message queue processing frequency
        priorityQueue.setBatteryOptimized(false)
        
        // Use optimal compression settings
        compressionCache.setBatteryMode(false)
        
        // Increase connection quality monitoring
        connectionQuality = .excellent
    }
    
    func clearMessageQueue() {
        priorityQueue.clear()
        pendingMessages.removeAll()
        messageTimeouts.values.forEach { $0.invalidate() }
        messageTimeouts.removeAll()
        logger.info("Message queue cleared")
    }
    
    func getPerformanceMetrics() -> WatchConnectivityMetrics {
        return metrics
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: OptimizedWatchConnectivityDelegate) {
        delegateQueue.async {
            // Remove any existing weak references to the same delegate
            self.delegates.removeAll { $0.delegate === delegate }
            
            // Add new weak reference
            self.delegates.append(WeakOptimizedWatchConnectivityDelegate(delegate))
            
            // Clean up any nil references
            self.delegates.removeAll { $0.delegate == nil }
        }
        
        logger.debug("Added OptimizedWatchConnectivity delegate")
    }
    
    func removeDelegate(_ delegate: OptimizedWatchConnectivityDelegate) {
        delegateQueue.async {
            self.delegates.removeAll { $0.delegate === delegate }
        }
        
        logger.debug("Removed OptimizedWatchConnectivity delegate")
    }
}

// MARK: - Private Helper Methods

private extension OptimizedWatchConnectivityService {
    
    func startConnectionMonitoring() {
        // Monitor connection quality
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateConnectionQuality()
            }
        }
    }
    
    func updateConnectionQuality() async {
        let previousQuality = connectionQuality
        
        if !isReachable {
            connectionQuality = .disconnected
        } else if errorCount > successCount {
            connectionQuality = .poor
        } else if latencyHistory.isEmpty {
            connectionQuality = .unknown
        } else {
            let averageLatency = latencyHistory.reduce(0, +) / Double(latencyHistory.count)
            
            switch averageLatency {
            case 0..<0.1:
                connectionQuality = .excellent
            case 0.1..<0.5:
                connectionQuality = .good
            case 0.5..<1.0:
                connectionQuality = .fair
            default:
                connectionQuality = .poor
            }
        }
        
        // Notify delegates if quality changed
        if connectionQuality != previousQuality {
            notifyDelegates { delegate in
                delegate.connectionQualityDidChange(connectionQuality)
            }
        }
    }
    
    func updateMetrics(latency: TimeInterval?, success: Bool) async {
        if success {
            successCount += 1
            if let latency = latency {
                latencyHistory.append(latency)
                if latencyHistory.count > 10 {
                    latencyHistory.removeFirst()
                }
            }
        } else {
            errorCount += 1
        }
        
        metrics.updateMetrics(
            messagesSent: successCount + errorCount,
            messagesSuccessful: successCount,
            averageLatency: latencyHistory.isEmpty ? 0 : latencyHistory.reduce(0, +) / Double(latencyHistory.count),
            connectionQuality: connectionQuality
        )
    }
    
    func optimizeMessage(_ message: [String: Any], priority: MessagePriority) -> [String: Any] {
        var optimizedMessage = message
        
        // Add priority information
        optimizedMessage["priority"] = priority.rawValue
        optimizedMessage["messageId"] = UUID().uuidString
        optimizedMessage["batteryOptimized"] = batteryOptimized
        
        // Apply compression for large messages
        if let jsonData = try? JSONSerialization.data(withJSONObject: message),
           jsonData.count > 1024 { // 1KB threshold
            let compressedData = compressionCache.compress(jsonData)
            optimizedMessage = [
                "compressed": true,
                "data": compressedData.base64EncodedString(),
                "originalSize": jsonData.count,
                "compressedSize": compressedData.count
            ]
        }
        
        return optimizedMessage
    }
    
    func optimizeUserInfo(_ userInfo: [String: Any], priority: TransferPriority) -> [String: Any] {
        var optimizedUserInfo = userInfo
        
        optimizedUserInfo["transferPriority"] = priority.rawValue
        optimizedUserInfo["timestamp"] = Date().timeIntervalSince1970
        
        return optimizedUserInfo
    }
    
    func enqueueMessage(
        id: String,
        message: [String: Any],
        priority: MessagePriority,
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((Error) -> Void)?
    ) async {
        let pendingMessage = OptimizedPendingMessage(
            id: id,
            message: message,
            priority: priority,
            replyHandler: replyHandler,
            errorHandler: errorHandler,
            timestamp: Date(),
            metadata: MessageMetadata(
                batteryLevel: await getCurrentBatteryLevel(),
                connectionQuality: connectionQuality,
                retryCount: 0
            )
        )
        
        pendingMessages[id] = pendingMessage
        
        // Set timeout based on priority
        let timeoutInterval = getTimeoutInterval(for: priority)
        let timer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { _ in
            Task {
                await self.handleMessageTimeout(messageId: id)
            }
        }
        messageTimeouts[id] = timer
        
        // Add to priority queue
        priorityQueue.enqueue(pendingMessage)
        
        // Process queue
        await processMessageQueue()
    }
    
    func processMessageQueue() async {
        guard isReachable else {
            logger.debug("Not reachable, deferring message processing")
            return
        }
        
        while let message = priorityQueue.dequeue() {
            await sendPendingMessage(message)
        }
    }
    
    func sendPendingMessage(_ pendingMessage: OptimizedPendingMessage) async {
        session.sendMessage(pendingMessage.message, replyHandler: { [weak self] response in
            Task {
                await self?.handleMessageResponse(messageId: pendingMessage.id, response: response)
            }
        }, errorHandler: { [weak self] error in
            Task {
                await self?.handleMessageError(messageId: pendingMessage.id, error: error)
            }
        })
        
        logger.debug("Sent priority message with ID: \(pendingMessage.id)")
    }
    
    func handleMessageResponse(messageId: String, response: [String: Any]) async {
        await cleanupPendingMessage(messageId: messageId)
        
        if let pendingMessage = pendingMessages[messageId] {
            delegateQueue.async {
                pendingMessage.replyHandler?(response)
            }
        }
        
        // Process the response content
        await processIncomingMessage(response)
        await updateMetrics(latency: Date().timeIntervalSince(pendingMessages[messageId]?.timestamp ?? Date()), success: true)
    }
    
    func handleMessageError(messageId: String, error: Error) async {
        if let pendingMessage = pendingMessages[messageId] {
            // Retry logic for high-priority messages
            if pendingMessage.priority == .critical && pendingMessage.metadata.retryCount < 3 {
                var retriedMessage = pendingMessage
                retriedMessage.metadata.retryCount += 1
                priorityQueue.enqueue(retriedMessage)
                logger.info("Retrying critical message: \(messageId), attempt \(retriedMessage.metadata.retryCount)")
                return
            }
            
            delegateQueue.async {
                pendingMessage.errorHandler?(error)
            }
        }
        
        await cleanupPendingMessage(messageId: messageId)
        await updateMetrics(latency: nil, success: false)
        logger.error("Message error for ID \(messageId): \(error.localizedDescription)")
    }
    
    func handleMessageTimeout(messageId: String) async {
        if let pendingMessage = pendingMessages[messageId] {
            let timeoutError = WatchConnectivityError.messageTimeout
            delegateQueue.async {
                pendingMessage.errorHandler?(timeoutError)
            }
        }
        
        await cleanupPendingMessage(messageId: messageId)
        await updateMetrics(latency: nil, success: false)
        logger.warning("Message timeout for ID: \(messageId)")
    }
    
    func cleanupPendingMessage(messageId: String) async {
        pendingMessages.removeValue(forKey: messageId)
        messageTimeouts[messageId]?.invalidate()
        messageTimeouts.removeValue(forKey: messageId)
    }
    
    func processIncomingMessage(_ message: [String: Any]) async {
        guard let type = message["type"] as? String else {
            logger.warning("Received message without type")
            return
        }
        
        let metadata = MessageMetadata(
            batteryLevel: await getCurrentBatteryLevel(),
            connectionQuality: connectionQuality,
            retryCount: 0
        )
        
        switch type {
        case "scoreUpdate":
            await handleIncomingScoreUpdate(message, metadata: metadata)
        case "courseData":
            await handleIncomingCourseData(message, metadata: metadata)
        case "activeRoundUpdate":
            await handleIncomingActiveRoundUpdate(message, metadata: metadata)
        case "healthMetricsUpdate":
            await handleIncomingHealthMetricsUpdate(message, metadata: metadata)
        default:
            logger.debug("Received unknown message type: \(type)")
        }
    }
    
    func handleIncomingScoreUpdate(_ message: [String: Any], metadata: MessageMetadata) async {
        guard let scorecardData = message["scorecard"] as? String,
              let data = Data(base64Encoded: scorecardData),
              let scorecard = try? JSONDecoder().decode(SharedScorecard.self, from: data) else {
            logger.error("Failed to decode scorecard from message")
            return
        }
        
        await MainActor.run {
            delegates.forEach { $0.delegate?.didReceiveScoreUpdate(scorecard, metadata: metadata) }
        }
    }
    
    func handleIncomingCourseData(_ message: [String: Any], metadata: MessageMetadata) async {
        guard let courseData = message["course"] as? String,
              let data = Data(base64Encoded: courseData),
              let course = try? JSONDecoder().decode(SharedGolfCourse.self, from: data) else {
            logger.error("Failed to decode course from message")
            return
        }
        
        await MainActor.run {
            delegates.forEach { $0.delegate?.didReceiveCourseData(course, metadata: metadata) }
        }
    }
    
    func handleIncomingActiveRoundUpdate(_ message: [String: Any], metadata: MessageMetadata) async {
        guard let roundData = message["round"] as? String,
              let data = Data(base64Encoded: roundData),
              let round = try? JSONDecoder().decode(ActiveGolfRound.self, from: data) else {
            logger.error("Failed to decode active round from message")
            return
        }
        
        await MainActor.run {
            delegates.forEach { $0.delegate?.didReceiveActiveRoundUpdate(round, metadata: metadata) }
        }
    }
    
    func handleIncomingHealthMetricsUpdate(_ message: [String: Any], metadata: MessageMetadata) async {
        guard let metricsData = message["metrics"] as? String,
              let data = Data(base64Encoded: metricsData),
              let healthMetrics = try? JSONDecoder().decode(WatchHealthMetrics.self, from: data) else {
            logger.error("Failed to decode health metrics from message")
            return
        }
        
        await MainActor.run {
            delegates.forEach { $0.delegate?.didReceiveHealthMetricsUpdate(healthMetrics, metadata: metadata) }
        }
    }
    
    func getCurrentBatteryLevel() async -> Double {
        return Double(WKInterfaceDevice.current().batteryLevel)
    }
    
    func getTimeoutInterval(for priority: MessagePriority) -> TimeInterval {
        switch priority {
        case .critical:
            return 5.0
        case .high:
            return 10.0
        case .normal:
            return 15.0
        case .low:
            return 30.0
        }
    }
    
    func notifyDelegates<T>(_ action: @escaping (OptimizedWatchConnectivityDelegate) -> T) {
        delegateQueue.async {
            self.delegates.forEach { weakDelegate in
                if let delegate = weakDelegate.delegate {
                    _ = action(delegate)
                }
            }
            
            // Clean up nil references
            self.delegates.removeAll { $0.delegate == nil }
        }
    }
}

// MARK: - WCSessionDelegate Implementation

extension OptimizedWatchConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        logger.info("Session activation completed with state: \(activationState.rawValue)")
        
        Task { @MainActor in
            notifyDelegates { delegate in
                delegate.sessionActivationDidComplete(activationState: activationState, error: error)
            }
        }
        
        if let error = error {
            logger.error("Session activation error: \(error.localizedDescription)")
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        logger.info("Session reachability changed to: \(session.isReachable)")
        
        Task { @MainActor in
            await updateConnectionQuality()
            notifyDelegates { delegate in
                delegate.sessionReachabilityDidChange(session)
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        logger.debug("Received message without reply handler")
        
        Task { @MainActor in
            await processIncomingMessage(message)
            notifyDelegates { delegate in
                delegate.didReceiveMessage(message, replyHandler: nil)
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        logger.debug("Received message with reply handler")
        
        Task { @MainActor in
            await processIncomingMessage(message)
            notifyDelegates { delegate in
                delegate.didReceiveMessage(message, replyHandler: replyHandler)
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        logger.debug("Received application context update")
        
        Task { @MainActor in
            // Handle active round from application context
            if let roundData = applicationContext["activeRound"] as? String,
               let data = Data(base64Encoded: roundData),
               let round = try? JSONDecoder().decode(ActiveGolfRound.self, from: data) {
                let metadata = MessageMetadata(
                    batteryLevel: await getCurrentBatteryLevel(),
                    connectionQuality: connectionQuality,
                    retryCount: 0
                )
                delegates.forEach { $0.delegate?.didReceiveActiveRoundUpdate(round, metadata: metadata) }
            }
            
            notifyDelegates { delegate in
                delegate.didReceiveApplicationContext(applicationContext)
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        logger.debug("Received user info")
        Task { @MainActor in
            await processIncomingMessage(userInfo)
        }
    }
    
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error = error {
            logger.error("User info transfer failed: \(error.localizedDescription)")
        } else {
            logger.debug("User info transfer completed successfully")
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        logger.debug("Received file: \(file.fileURL.lastPathComponent)")
    }
    
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error {
            logger.error("File transfer failed: \(error.localizedDescription)")
        } else {
            logger.debug("File transfer completed successfully")
        }
    }
}

// MARK: - Supporting Types

enum MessagePriority: String, CaseIterable, Codable {
    case critical = "critical"
    case high = "high"
    case normal = "normal"
    case low = "low"
    
    var numericValue: Int {
        switch self {
        case .critical: return 4
        case .high: return 3
        case .normal: return 2
        case .low: return 1
        }
    }
}

enum TransferPriority: String, CaseIterable, Codable {
    case high = "high"
    case normal = "normal"
    case low = "low"
}

enum ConnectionQuality: String, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case disconnected = "disconnected"
    case unknown = "unknown"
    case batterySaver = "battery_saver"
}

struct MessageMetadata {
    let batteryLevel: Double
    let connectionQuality: ConnectionQuality
    var retryCount: Int
    let timestamp: Date = Date()
}

struct OptimizedPendingMessage {
    let id: String
    let message: [String: Any]
    let priority: MessagePriority
    let replyHandler: (([String: Any]) -> Void)?
    let errorHandler: ((Error) -> Void)?
    let timestamp: Date
    var metadata: MessageMetadata
}

struct WatchConnectivityMetrics {
    private(set) var messagesSent: Int = 0
    private(set) var messagesSuccessful: Int = 0
    private(set) var averageLatency: TimeInterval = 0
    private(set) var lastConnectionQuality: ConnectionQuality = .unknown
    private(set) var lastUpdated: Date = Date()
    
    var successRate: Double {
        guard messagesSent > 0 else { return 0 }
        return Double(messagesSuccessful) / Double(messagesSent)
    }
    
    mutating func updateMetrics(messagesSent: Int, messagesSuccessful: Int, averageLatency: TimeInterval, connectionQuality: ConnectionQuality) {
        self.messagesSent = messagesSent
        self.messagesSuccessful = messagesSuccessful
        self.averageLatency = averageLatency
        self.lastConnectionQuality = connectionQuality
        self.lastUpdated = Date()
    }
}

struct WatchHealthMetrics: Codable {
    let heartRate: Double?
    let steps: Int
    let activeEnergyBurned: Double
    let distanceWalkingRunning: Double
    let timestamp: Date
    
    init(heartRate: Double? = nil, steps: Int = 0, activeEnergyBurned: Double = 0, distanceWalkingRunning: Double = 0) {
        self.heartRate = heartRate
        self.steps = steps
        self.activeEnergyBurned = activeEnergyBurned
        self.distanceWalkingRunning = distanceWalkingRunning
        self.timestamp = Date()
    }
}

private struct WeakOptimizedWatchConnectivityDelegate {
    weak var delegate: OptimizedWatchConnectivityDelegate?
    
    init(_ delegate: OptimizedWatchConnectivityDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Priority Queue Implementation

private class PriorityMessageQueue {
    private var messages: [OptimizedPendingMessage] = []
    private let queue = DispatchQueue(label: "PriorityMessageQueue", qos: .userInitiated)
    private var batteryOptimized = false
    
    func enqueue(_ message: OptimizedPendingMessage) {
        queue.async {
            self.messages.append(message)
            self.messages.sort { $0.priority.numericValue > $1.priority.numericValue }
        }
    }
    
    func dequeue() -> OptimizedPendingMessage? {
        return queue.sync {
            guard !messages.isEmpty else { return nil }
            
            // In battery mode, process only critical and high priority messages
            if batteryOptimized {
                if let index = messages.firstIndex(where: { $0.priority == .critical || $0.priority == .high }) {
                    return messages.remove(at: index)
                }
                return nil
            }
            
            return messages.removeFirst()
        }
    }
    
    func clear() {
        queue.async {
            self.messages.removeAll()
        }
    }
    
    func setBatteryOptimized(_ optimized: Bool) {
        queue.async {
            self.batteryOptimized = optimized
        }
    }
}

// MARK: - Compression Cache Implementation

private class CompressionCache {
    private var courseCache: [String: Data] = [:]
    private var compressionCache: [String: Data] = [:]
    private let cacheQueue = DispatchQueue(label: "CompressionCache", qos: .utility)
    private var batteryMode = false
    
    func compress(_ data: Data) -> Data {
        return cacheQueue.sync {
            if batteryMode && data.count < 512 {
                return data // Don't compress small data in battery mode
            }
            
            let cacheKey = data.sha256
            if let cached = compressionCache[cacheKey] {
                return cached
            }
            
            let compressed = data.compressed() ?? data
            compressionCache[cacheKey] = compressed
            
            // Limit cache size
            if compressionCache.count > 50 {
                compressionCache.removeValue(forKey: compressionCache.keys.first!)
            }
            
            return compressed
        }
    }
    
    func compressFile(at url: URL) throws -> URL {
        let data = try Data(contentsOf: url)
        let compressedData = compress(data)
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("compressed")
        
        try compressedData.write(to: tempURL)
        return tempURL
    }
    
    func compressContext(_ context: [String: Any]) -> [String: Any] {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: context),
              jsonData.count > 512 else {
            return context
        }
        
        let compressedData = compress(jsonData)
        return [
            "compressed": true,
            "data": compressedData.base64EncodedString(),
            "originalSize": jsonData.count
        ]
    }
    
    func cacheCourseData(course: SharedGolfCourse) {
        cacheQueue.async {
            if let data = try? JSONEncoder().encode(course) {
                self.courseCache[course.id] = data
            }
        }
    }
    
    func getCachedCourseData(courseId: String) -> Data? {
        return cacheQueue.sync {
            return courseCache[courseId]
        }
    }
    
    func setBatteryMode(_ enabled: Bool) {
        cacheQueue.async {
            self.batteryMode = enabled
        }
    }
}

// MARK: - Data Extensions

private extension Data {
    var sha256: String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func compressed() -> Data? {
        return self.withUnsafeBytes { bytes in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            defer { buffer.deallocate() }
            
            let compressedSize = compression_encode_buffer(
                buffer, count,
                bytes.bindMemory(to: UInt8.self).baseAddress!, count,
                nil, COMPRESSION_LZFSE
            )
            
            guard compressedSize > 0 else { return nil }
            return Data(bytes: buffer, count: compressedSize)
        }
    }
}

import CommonCrypto
import Compression

private struct SHA256 {
    static func hash(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}