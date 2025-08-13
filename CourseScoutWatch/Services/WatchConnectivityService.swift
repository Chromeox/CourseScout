import Foundation
import WatchConnectivity
import os.log
import Combine

// MARK: - Optimized Watch Connectivity Service Protocol

protocol OptimizedWatchConnectivityServiceProtocol: AnyObject {
    // Session management
    var isSupported: Bool { get }
    var isReachable: Bool { get }
    var activationState: WCSessionActivationState { get }
    var connectionQuality: ConnectionQuality { get }
    
    // Optimized data transfer
    func sendMessage(_ message: [String: Any], priority: MessagePriority, replyHandler: (([String: Any]) -> Void)?, errorHandler: ((Error) -> Void)?)
    func sendMessageOptimized<T: Codable>(_ data: T, priority: MessagePriority) async throws
    func updateApplicationContext(_ context: [String: Any], compression: Bool) throws
    func transferUserInfo(_ userInfo: [String: Any], priority: TransferPriority) -> WCSessionUserInfoTransfer?
    func transferFileOptimized(at url: URL, metadata: [String: Any]?, compression: Bool) -> WCSessionFileTransfer?
    
    // Golf-specific optimized methods
    func sendScoreUpdate(_ scorecard: SharedScorecard, priority: MessagePriority) async throws
    func sendCourseData(_ course: SharedGolfCourse, useCache: Bool) async throws
    func sendActiveRoundUpdate(_ round: ActiveGolfRound) async throws
    func sendHealthMetricsUpdate(_ metrics: WatchHealthMetrics) async throws
    func requestCourseInformation(courseId: String, priority: MessagePriority) async throws -> SharedGolfCourse?
    func requestCurrentRound(priority: MessagePriority) async throws -> ActiveGolfRound?
    
    // Performance optimization
    func optimizeForBattery()
    func optimizeForPerformance()
    func clearMessageQueue()
    func getPerformanceMetrics() -> WatchConnectivityMetrics
    
    // Delegates
    func setDelegate(_ delegate: OptimizedWatchConnectivityDelegate)
    func removeDelegate(_ delegate: OptimizedWatchConnectivityDelegate)
}

// MARK: - Enhanced Delegate Protocol

protocol OptimizedWatchConnectivityDelegate: AnyObject {
    func didReceiveScoreUpdate(_ scorecard: SharedScorecard, metadata: MessageMetadata)
    func didReceiveCourseData(_ course: SharedGolfCourse, metadata: MessageMetadata)
    func didReceiveActiveRoundUpdate(_ round: ActiveGolfRound, metadata: MessageMetadata)
    func didReceiveHealthMetricsUpdate(_ metrics: WatchHealthMetrics, metadata: MessageMetadata)
    func didReceiveApplicationContext(_ context: [String: Any])
    func didReceiveMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?)
    func sessionActivationDidComplete(activationState: WCSessionActivationState, error: Error?)
    func sessionReachabilityDidChange(_ session: WCSession)
    func connectionQualityDidChange(_ quality: ConnectionQuality)
}

// Default implementations (optional methods)
extension OptimizedWatchConnectivityDelegate {
    func didReceiveScoreUpdate(_ scorecard: SharedScorecard, metadata: MessageMetadata) {}
    func didReceiveCourseData(_ course: SharedGolfCourse, metadata: MessageMetadata) {}
    func didReceiveActiveRoundUpdate(_ round: ActiveGolfRound, metadata: MessageMetadata) {}
    func didReceiveHealthMetricsUpdate(_ metrics: WatchHealthMetrics, metadata: MessageMetadata) {}
    func didReceiveApplicationContext(_ context: [String: Any]) {}
    func didReceiveMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {}
    func sessionActivationDidComplete(activationState: WCSessionActivationState, error: Error?) {}
    func sessionReachabilityDidChange(_ session: WCSession) {}
    func connectionQualityDidChange(_ quality: ConnectionQuality) {}
}

// MARK: - Watch Connectivity Delegate

protocol WatchConnectivityDelegate: AnyObject {
    func didReceiveScoreUpdate(_ scorecard: SharedScorecard)
    func didReceiveCourseData(_ course: SharedGolfCourse)
    func didReceiveActiveRoundUpdate(_ round: ActiveGolfRound)
    func didReceiveApplicationContext(_ context: [String: Any])
    func didReceiveMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?)
    func sessionActivationDidComplete(activationState: WCSessionActivationState, error: Error?)
    func sessionReachabilityDidChange(_ session: WCSession)
}

// Default implementations (optional methods)
extension WatchConnectivityDelegate {
    func didReceiveScoreUpdate(_ scorecard: SharedScorecard) {}
    func didReceiveCourseData(_ course: SharedGolfCourse) {}
    func didReceiveActiveRoundUpdate(_ round: ActiveGolfRound) {}
    func didReceiveApplicationContext(_ context: [String: Any]) {}
    func didReceiveMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {}
    func sessionActivationDidComplete(activationState: WCSessionActivationState, error: Error?) {}
    func sessionReachabilityDidChange(_ session: WCSession) {}
}

// MARK: - Watch Connectivity Service Implementation

class WatchConnectivityService: NSObject, WatchConnectivityServiceProtocol {
    // MARK: - Properties
    
    private let session: WCSession
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "WatchConnectivity")
    private let messageQueue = DispatchQueue(label: "GolfConnectivity", qos: .userInitiated)
    private let delegateQueue = DispatchQueue.main
    
    // Delegate management
    private var delegates: [WeakWatchConnectivityDelegate] = []
    
    // Message tracking
    private var pendingMessages: [String: PendingMessage] = [:]
    private var messageTimeouts: [String: Timer] = [:]
    
    // Application context backup
    private var lastApplicationContext: [String: Any] = [:]
    
    // MARK: - Initialization
    
    override init() {
        self.session = WCSession.default
        super.init()
        
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
            logger.info("WatchConnectivityService initialized and activated")
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
    
    // MARK: - Data Transfer Methods
    
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)? = nil,
        errorHandler: ((Error) -> Void)? = nil
    ) {
        guard isSupported && activationState == .activated else {
            let error = WatchConnectivityError.sessionNotActivated
            logger.error("Cannot send message: session not activated")
            errorHandler?(error)
            return
        }
        
        let messageId = UUID().uuidString
        let messageWithId = message.merging(["messageId": messageId]) { _, new in new }
        
        messageQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Store pending message
            let pendingMessage = PendingMessage(
                id: messageId,
                message: messageWithId,
                replyHandler: replyHandler,
                errorHandler: errorHandler,
                timestamp: Date()
            )
            self.pendingMessages[messageId] = pendingMessage
            
            // Set timeout
            let timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                self.handleMessageTimeout(messageId: messageId)
            }
            self.messageTimeouts[messageId] = timer
            
            // Send message
            if self.isReachable {
                self.session.sendMessage(messageWithId, replyHandler: { response in
                    self.handleMessageResponse(messageId: messageId, response: response)
                }, errorHandler: { error in
                    self.handleMessageError(messageId: messageId, error: error)
                })
                
                self.logger.debug("Sent message with ID: \(messageId)")
            } else {
                // Fallback to user info transfer for non-reachable counterpart
                let transfer = self.session.transferUserInfo(messageWithId)
                self.logger.debug("Sent user info transfer (not reachable): \(transfer.description)")
                
                // Clean up immediately since we won't get a response
                self.cleanupPendingMessage(messageId: messageId)
            }
        }
    }
    
    func updateApplicationContext(_ context: [String: Any]) throws {
        guard isSupported && activationState == .activated else {
            throw WatchConnectivityError.sessionNotActivated
        }
        
        // Avoid sending duplicate context
        if NSDictionary(dictionary: context).isEqual(to: lastApplicationContext) {
            logger.debug("Application context unchanged, skipping update")
            return
        }
        
        do {
            try session.updateApplicationContext(context)
            lastApplicationContext = context
            logger.debug("Updated application context successfully")
        } catch {
            logger.error("Failed to update application context: \(error.localizedDescription)")
            throw error
        }
    }
    
    func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer? {
        guard isSupported && activationState == .activated else {
            logger.error("Cannot transfer user info: session not activated")
            return nil
        }
        
        let transfer = session.transferUserInfo(userInfo)
        logger.debug("Started user info transfer: \(transfer.description)")
        return transfer
    }
    
    func transferFile(at url: URL, metadata: [String: Any]? = nil) -> WCSessionFileTransfer? {
        guard isSupported && activationState == .activated else {
            logger.error("Cannot transfer file: session not activated")
            return nil
        }
        
        let transfer = session.transferFile(url, metadata: metadata)
        logger.debug("Started file transfer: \(transfer.description)")
        return transfer
    }
    
    // MARK: - Golf-Specific Methods
    
    func sendScoreUpdate(_ scorecard: SharedScorecard) {
        logger.info("Sending score update for round: \(scorecard.id)")
        
        let message: [String: Any] = [
            "type": "scoreUpdate",
            "scorecard": try! JSONEncoder().encode(scorecard).base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        sendMessage(message, errorHandler: { error in
            self.logger.error("Failed to send score update: \(error.localizedDescription)")
        })
    }
    
    func sendCourseData(_ course: SharedGolfCourse) {
        logger.info("Sending course data: \(course.name)")
        
        let message: [String: Any] = [
            "type": "courseData",
            "course": try! JSONEncoder().encode(course).base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        sendMessage(message, errorHandler: { error in
            self.logger.error("Failed to send course data: \(error.localizedDescription)")
        })
    }
    
    func sendActiveRoundUpdate(_ round: ActiveGolfRound) {
        logger.info("Sending active round update: \(round.courseName), hole \(round.currentHole)")
        
        let message: [String: Any] = [
            "type": "activeRoundUpdate",
            "round": try! JSONEncoder().encode(round).base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Use application context for active round to ensure it persists
        do {
            try updateApplicationContext([
                "activeRound": try! JSONEncoder().encode(round).base64EncodedString(),
                "timestamp": Date().timeIntervalSince1970
            ])
        } catch {
            logger.error("Failed to update application context with active round: \(error.localizedDescription)")
        }
        
        // Also send as message for immediate update
        sendMessage(message, errorHandler: { error in
            self.logger.error("Failed to send active round update: \(error.localizedDescription)")
        })
    }
    
    func requestCourseInformation(courseId: String) {
        logger.info("Requesting course information: \(courseId)")
        
        let message: [String: Any] = [
            "type": "requestCourseInfo",
            "courseId": courseId,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        sendMessage(message, replyHandler: { response in
            self.logger.debug("Received course information response")
            self.processIncomingMessage(response)
        }, errorHandler: { error in
            self.logger.error("Failed to request course information: \(error.localizedDescription)")
        })
    }
    
    func requestCurrentRound() {
        logger.info("Requesting current round information")
        
        let message: [String: Any] = [
            "type": "requestCurrentRound",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        sendMessage(message, replyHandler: { response in
            self.logger.debug("Received current round response")
            self.processIncomingMessage(response)
        }, errorHandler: { error in
            self.logger.error("Failed to request current round: \(error.localizedDescription)")
        })
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: WatchConnectivityDelegate) {
        delegateQueue.async {
            // Remove any existing weak references to the same delegate
            self.delegates.removeAll { $0.delegate === delegate }
            
            // Add new weak reference
            self.delegates.append(WeakWatchConnectivityDelegate(delegate))
            
            // Clean up any nil references
            self.delegates.removeAll { $0.delegate == nil }
        }
        
        logger.debug("Added WatchConnectivity delegate")
    }
    
    func removeDelegate(_ delegate: WatchConnectivityDelegate) {
        delegateQueue.async {
            self.delegates.removeAll { $0.delegate === delegate }
        }
        
        logger.debug("Removed WatchConnectivity delegate")
    }
    
    // MARK: - Private Helper Methods
    
    private func handleMessageResponse(messageId: String, response: [String: Any]) {
        messageQueue.async {
            self.cleanupPendingMessage(messageId: messageId)
            
            if let pendingMessage = self.pendingMessages[messageId] {
                self.delegateQueue.async {
                    pendingMessage.replyHandler?(response)
                }
            }
            
            // Process the response content
            self.processIncomingMessage(response)
        }
    }
    
    private func handleMessageError(messageId: String, error: Error) {
        messageQueue.async {
            if let pendingMessage = self.pendingMessages[messageId] {
                self.delegateQueue.async {
                    pendingMessage.errorHandler?(error)
                }
            }
            
            self.cleanupPendingMessage(messageId: messageId)
            self.logger.error("Message error for ID \(messageId): \(error.localizedDescription)")
        }
    }
    
    private func handleMessageTimeout(messageId: String) {
        messageQueue.async {
            if let pendingMessage = self.pendingMessages[messageId] {
                let timeoutError = WatchConnectivityError.messageTimeout
                self.delegateQueue.async {
                    pendingMessage.errorHandler?(timeoutError)
                }
            }
            
            self.cleanupPendingMessage(messageId: messageId)
            self.logger.warning("Message timeout for ID: \(messageId)")
        }
    }
    
    private func cleanupPendingMessage(messageId: String) {
        pendingMessages.removeValue(forKey: messageId)
        messageTimeouts[messageId]?.invalidate()
        messageTimeouts.removeValue(forKey: messageId)
    }
    
    private func processIncomingMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else {
            logger.warning("Received message without type")
            return
        }
        
        switch type {
        case "scoreUpdate":
            handleIncomingScoreUpdate(message)
        case "courseData":
            handleIncomingCourseData(message)
        case "activeRoundUpdate":
            handleIncomingActiveRoundUpdate(message)
        default:
            logger.debug("Received unknown message type: \(type)")
        }
    }
    
    private func handleIncomingScoreUpdate(_ message: [String: Any]) {
        guard let scorecardData = message["scorecard"] as? String,
              let data = Data(base64Encoded: scorecardData),
              let scorecard = try? JSONDecoder().decode(SharedScorecard.self, from: data) else {
            logger.error("Failed to decode scorecard from message")
            return
        }
        
        delegateQueue.async {
            self.delegates.forEach { $0.delegate?.didReceiveScoreUpdate(scorecard) }
        }
    }
    
    private func handleIncomingCourseData(_ message: [String: Any]) {
        guard let courseData = message["course"] as? String,
              let data = Data(base64Encoded: courseData),
              let course = try? JSONDecoder().decode(SharedGolfCourse.self, from: data) else {
            logger.error("Failed to decode course from message")
            return
        }
        
        delegateQueue.async {
            self.delegates.forEach { $0.delegate?.didReceiveCourseData(course) }
        }
    }
    
    private func handleIncomingActiveRoundUpdate(_ message: [String: Any]) {
        guard let roundData = message["round"] as? String,
              let data = Data(base64Encoded: roundData),
              let round = try? JSONDecoder().decode(ActiveGolfRound.self, from: data) else {
            logger.error("Failed to decode active round from message")
            return
        }
        
        delegateQueue.async {
            self.delegates.forEach { $0.delegate?.didReceiveActiveRoundUpdate(round) }
        }
    }
    
    private func notifyDelegates<T>(_ action: (WatchConnectivityDelegate) -> T) {
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

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        logger.info("Session activation completed with state: \(activationState.rawValue)")
        
        notifyDelegates { delegate in
            delegate.sessionActivationDidComplete(activationState: activationState, error: error)
        }
        
        if let error = error {
            logger.error("Session activation error: \(error.localizedDescription)")
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        logger.info("Session reachability changed to: \(session.isReachable)")
        
        notifyDelegates { delegate in
            delegate.sessionReachabilityDidChange(session)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        logger.debug("Received message without reply handler")
        processIncomingMessage(message)
        
        notifyDelegates { delegate in
            delegate.didReceiveMessage(message, replyHandler: nil)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        logger.debug("Received message with reply handler")
        processIncomingMessage(message)
        
        notifyDelegates { delegate in
            delegate.didReceiveMessage(message, replyHandler: replyHandler)
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        logger.debug("Received application context update")
        
        // Handle active round from application context
        if let roundData = applicationContext["activeRound"] as? String,
           let data = Data(base64Encoded: roundData),
           let round = try? JSONDecoder().decode(ActiveGolfRound.self, from: data) {
            delegateQueue.async {
                self.delegates.forEach { $0.delegate?.didReceiveActiveRoundUpdate(round) }
            }
        }
        
        notifyDelegates { delegate in
            delegate.didReceiveApplicationContext(applicationContext)
        }
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        logger.debug("Received user info")
        processIncomingMessage(userInfo)
    }
    
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error = error {
            logger.error("User info transfer failed: \(error.localizedDescription)")
        } else {
            logger.debug("User info transfer completed successfully")
        }
    }
    
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        logger.debug("Received file: \(file.fileURL.lastPathComponent)")
    }
    
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error {
            logger.error("File transfer failed: \(error.localizedDescription)")
        } else {
            logger.debug("File transfer completed successfully")
        }
    }
}

// MARK: - Supporting Types

private struct PendingMessage {
    let id: String
    let message: [String: Any]
    let replyHandler: (([String: Any]) -> Void)?
    let errorHandler: ((Error) -> Void)?
    let timestamp: Date
}

private struct WeakWatchConnectivityDelegate {
    weak var delegate: WatchConnectivityDelegate?
    
    init(_ delegate: WatchConnectivityDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Watch Connectivity Errors

enum WatchConnectivityError: Error, LocalizedError {
    case sessionNotActivated
    case messageTimeout
    case invalidData
    case counterpartNotReachable
    
    var errorDescription: String? {
        switch self {
        case .sessionNotActivated:
            return "WCSession is not activated"
        case .messageTimeout:
            return "Message timed out"
        case .invalidData:
            return "Invalid data received"
        case .counterpartNotReachable:
            return "Counterpart device is not reachable"
        }
    }
}