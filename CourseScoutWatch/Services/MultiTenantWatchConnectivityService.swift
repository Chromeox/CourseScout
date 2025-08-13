import Foundation
import WatchConnectivity
import Combine
import os.log

// MARK: - Multi-Tenant Watch Connectivity Service Protocol

protocol MultiTenantWatchConnectivityServiceProtocol: AnyObject {
    // Tenant context management
    var currentTenantContext: WatchTenantContext? { get }
    func switchTenantContext(_ context: WatchTenantContext) async
    
    // Multi-tenant message routing
    func sendTenantMessage(_ message: [String: Any], tenantId: String?, priority: MessagePriority) async throws
    func sendTenantScoreUpdate(_ scorecard: TenantAwareScorecard) async throws
    func sendTenantCourseRequest(_ courseId: String, tenantId: String) async throws -> SharedGolfCourse?
    func sendTenantBookingUpdate(_ booking: TenantAwareBooking) async throws
    
    // Tenant-specific application context
    func updateTenantApplicationContext(_ context: [String: Any], tenantId: String?) throws
    func getTenantApplicationContext(for tenantId: String?) -> [String: Any]?
    
    // Multi-tenant data isolation
    func isolateTenantData<T: Codable>(_ data: T, for tenantId: String?) -> TenantIsolatedData<T>
    func extractTenantData<T: Codable>(_ isolatedData: TenantIsolatedData<T>, expectedTenantId: String?) throws -> T
    
    // Tenant-aware delegates
    func addTenantDelegate(_ delegate: MultiTenantWatchConnectivityDelegate)
    func removeTenantDelegate(_ delegate: MultiTenantWatchConnectivityDelegate)
    
    // Publishers
    var tenantMessageReceived: AnyPublisher<TenantMessage, Never> { get }
    var tenantContextChanged: AnyPublisher<WatchTenantContext?, Never> { get }
}

// MARK: - Supporting Types

enum MessagePriority: Int, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    var timeout: TimeInterval {
        switch self {
        case .low: return 30.0
        case .normal: return 15.0
        case .high: return 10.0
        case .critical: return 5.0
        }
    }
}

struct TenantMessage {
    let messageId: String
    let tenantId: String?
    let messageType: String
    let payload: [String: Any]
    let timestamp: Date
    let priority: MessagePriority
}

struct TenantIsolatedData<T: Codable>: Codable {
    let tenantId: String?
    let databaseNamespace: String
    let data: T
    let isolationTimestamp: Date
    let businessType: WatchBusinessType
    
    init(data: T, tenantContext: WatchTenantContext?) {
        self.tenantId = tenantContext?.tenantId
        self.databaseNamespace = tenantContext?.databaseNamespace ?? "default"
        self.data = data
        self.isolationTimestamp = Date()
        self.businessType = tenantContext?.businessType ?? .golfCourse
    }
}

struct TenantAwareScorecard: Codable {
    let scorecard: SharedScorecard
    let tenantContext: WatchTenantContext?
    let courseId: String
    let playerId: String
    
    init(scorecard: SharedScorecard, tenantContext: WatchTenantContext?, courseId: String, playerId: String) {
        self.scorecard = scorecard
        self.tenantContext = tenantContext
        self.courseId = courseId
        self.playerId = playerId
    }
}

struct TenantAwareBooking: Codable {
    let bookingId: String
    let tenantContext: WatchTenantContext?
    let courseId: String
    let teeTime: Date
    let playerCount: Int
    let status: BookingStatus
    
    enum BookingStatus: String, Codable {
        case pending = "pending"
        case confirmed = "confirmed"
        case checkedIn = "checked_in"
        case active = "active"
        case completed = "completed"
        case cancelled = "cancelled"
    }
}

protocol MultiTenantWatchConnectivityDelegate: AnyObject {
    func didReceiveTenantMessage(_ message: TenantMessage)
    func didReceiveTenantScoreUpdate(_ scorecard: TenantAwareScorecard)
    func didReceiveTenantCourseData(_ course: SharedGolfCourse, tenantId: String?)
    func didReceiveTenantBookingUpdate(_ booking: TenantAwareBooking)
    func tenantContextDidChange(_ context: WatchTenantContext?)
}

// MARK: - Multi-Tenant Watch Connectivity Service Implementation

@MainActor
class MultiTenantWatchConnectivityService: MultiTenantWatchConnectivityServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var currentTenantContext: WatchTenantContext?
    
    // MARK: - Private Properties
    
    private let baseService: WatchConnectivityServiceProtocol
    private let tenantService: WatchTenantConfigurationServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "MultiTenantConnectivity")
    
    // MARK: - Publishers
    
    private let tenantMessageSubject = PassthroughSubject<TenantMessage, Never>()
    private let tenantContextSubject = CurrentValueSubject<WatchTenantContext?, Never>(nil)
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Delegate Management
    
    private var tenantDelegates: [WeakMultiTenantDelegate] = []
    
    // MARK: - Tenant Data Management
    
    private var tenantApplicationContexts: [String: [String: Any]] = [:]
    private var pendingTenantMessages: [String: TenantMessage] = [:]
    private var messageSequenceNumbers: [String: Int] = [:]
    
    // MARK: - Initialization
    
    init(baseService: WatchConnectivityServiceProtocol, tenantService: WatchTenantConfigurationServiceProtocol) {
        self.baseService = baseService
        self.tenantService = tenantService
        
        setupConnectivityDelegates()
        setupTenantObservation()
        
        logger.info("MultiTenantWatchConnectivityService initialized")
    }
    
    // MARK: - Publishers
    
    var tenantMessageReceived: AnyPublisher<TenantMessage, Never> {
        tenantMessageSubject.eraseToAnyPublisher()
    }
    
    var tenantContextChanged: AnyPublisher<WatchTenantContext?, Never> {
        tenantContextSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Tenant Context Management
    
    func switchTenantContext(_ context: WatchTenantContext) async {
        let previousTenantId = currentTenantContext?.tenantId
        logger.info("Switching tenant context from \(previousTenantId ?? "default") to \(context.tenantId ?? "default")")
        
        currentTenantContext = context
        tenantContextSubject.send(context)
        
        // Notify delegates
        notifyTenantDelegates { delegate in
            delegate.tenantContextDidChange(context)
        }
        
        // Clear pending messages for previous tenant
        if let previousId = previousTenantId {
            pendingTenantMessages = pendingTenantMessages.filter { $0.value.tenantId != previousId }
        }
        
        logger.debug("Tenant context switch completed")
    }
    
    // MARK: - Multi-Tenant Message Routing
    
    func sendTenantMessage(_ message: [String: Any], tenantId: String?, priority: MessagePriority = .normal) async throws {
        let messageId = UUID().uuidString
        let tenantMessage = TenantMessage(
            messageId: messageId,
            tenantId: tenantId,
            messageType: message["type"] as? String ?? "unknown",
            payload: message,
            timestamp: Date(),
            priority: priority
        )
        
        // Add tenant isolation headers
        var isolatedMessage = message
        isolatedMessage["tenantId"] = tenantId
        isolatedMessage["messageId"] = messageId
        isolatedMessage["priority"] = priority.rawValue
        isolatedMessage["databaseNamespace"] = getDatabaseNamespace(for: tenantId)
        isolatedMessage["businessType"] = getBusinessType(for: tenantId)?.rawValue
        isolatedMessage["sequenceNumber"] = getNextSequenceNumber(for: tenantId)
        
        // Store pending message
        pendingTenantMessages[messageId] = tenantMessage
        
        logger.debug("Sending tenant message: \(messageId) for tenant: \(tenantId ?? "default")")
        
        // Send via base service with timeout based on priority
        return try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                try await withCheckedThrowingContinuation { continuation in
                    self?.baseService.sendMessage(
                        isolatedMessage,
                        replyHandler: { [weak self] response in
                            self?.handleTenantMessageResponse(messageId: messageId, response: response)
                            continuation.resume()
                        },
                        errorHandler: { error in
                            continuation.resume(throwing: error)
                        }
                    )
                }
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(priority.timeout * 1_000_000_000))
                throw MultiTenantConnectivityError.messageTimeout(messageId: messageId)
            }
            
            try await group.next()
            group.cancelAll()
        }
    }
    
    func sendTenantScoreUpdate(_ scorecard: TenantAwareScorecard) async throws {
        logger.info("Sending tenant scorecard update for tenant: \(scorecard.tenantContext?.tenantId ?? "default")")
        
        let isolatedScorecard = isolateTenantData(scorecard, for: scorecard.tenantContext?.tenantId)
        let encodedData = try JSONEncoder().encode(isolatedScorecard)
        
        let message: [String: Any] = [
            "type": "tenantScoreUpdate",
            "scorecard": encodedData.base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        try await sendTenantMessage(message, tenantId: scorecard.tenantContext?.tenantId, priority: .high)
    }
    
    func sendTenantCourseRequest(_ courseId: String, tenantId: String) async throws -> SharedGolfCourse? {
        logger.info("Requesting course information: \(courseId) for tenant: \(tenantId)")
        
        let message: [String: Any] = [
            "type": "requestTenantCourseInfo",
            "courseId": courseId,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    try await sendTenantMessage(message, tenantId: tenantId, priority: .high)
                    // Response will be handled in delegate method
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func sendTenantBookingUpdate(_ booking: TenantAwareBooking) async throws {
        logger.info("Sending tenant booking update: \(booking.bookingId) for tenant: \(booking.tenantContext?.tenantId ?? "default")")
        
        let isolatedBooking = isolateTenantData(booking, for: booking.tenantContext?.tenantId)
        let encodedData = try JSONEncoder().encode(isolatedBooking)
        
        let message: [String: Any] = [
            "type": "tenantBookingUpdate",
            "booking": encodedData.base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        try await sendTenantMessage(message, tenantId: booking.tenantContext?.tenantId, priority: .normal)
    }
    
    // MARK: - Tenant Application Context
    
    func updateTenantApplicationContext(_ context: [String: Any], tenantId: String?) throws {
        let contextKey = tenantId ?? "default"
        
        // Add tenant isolation headers
        var isolatedContext = context
        isolatedContext["tenantId"] = tenantId
        isolatedContext["databaseNamespace"] = getDatabaseNamespace(for: tenantId)
        isolatedContext["contextTimestamp"] = Date().timeIntervalSince1970
        
        // Cache tenant-specific context
        tenantApplicationContexts[contextKey] = isolatedContext
        
        // Update base service context if this is the current tenant
        if tenantId == currentTenantContext?.tenantId || (tenantId == nil && currentTenantContext == nil) {
            try baseService.updateApplicationContext(isolatedContext)
        }
        
        logger.debug("Updated application context for tenant: \(contextKey)")
    }
    
    func getTenantApplicationContext(for tenantId: String?) -> [String: Any]? {
        let contextKey = tenantId ?? "default"
        return tenantApplicationContexts[contextKey]
    }
    
    // MARK: - Data Isolation
    
    func isolateTenantData<T: Codable>(_ data: T, for tenantId: String?) -> TenantIsolatedData<T> {
        let context = getTenantContext(for: tenantId)
        return TenantIsolatedData(data: data, tenantContext: context)
    }
    
    func extractTenantData<T: Codable>(_ isolatedData: TenantIsolatedData<T>, expectedTenantId: String?) throws -> T {
        // Validate tenant isolation
        guard isolatedData.tenantId == expectedTenantId else {
            throw MultiTenantConnectivityError.tenantMismatch(
                expected: expectedTenantId,
                actual: isolatedData.tenantId
            )
        }
        
        // Validate database namespace
        let expectedNamespace = getDatabaseNamespace(for: expectedTenantId)
        guard isolatedData.databaseNamespace == expectedNamespace else {
            throw MultiTenantConnectivityError.namespaceMismatch(
                expected: expectedNamespace,
                actual: isolatedData.databaseNamespace
            )
        }
        
        return isolatedData.data
    }
    
    // MARK: - Delegate Management
    
    func addTenantDelegate(_ delegate: MultiTenantWatchConnectivityDelegate) {
        tenantDelegates.removeAll { $0.delegate == nil || $0.delegate === delegate }
        tenantDelegates.append(WeakMultiTenantDelegate(delegate))
        logger.debug("Added multi-tenant connectivity delegate")
    }
    
    func removeTenantDelegate(_ delegate: MultiTenantWatchConnectivityDelegate) {
        tenantDelegates.removeAll { $0.delegate === delegate }
        logger.debug("Removed multi-tenant connectivity delegate")
    }
    
    // MARK: - Private Helper Methods
    
    private func setupConnectivityDelegates() {
        baseService.setDelegate(self)
    }
    
    private func setupTenantObservation() {
        tenantService.tenantDidChange
            .sink { [weak self] context in
                Task { @MainActor in
                    await self?.switchTenantContext(context)
                }
            }
            .store(in: &cancellables)
    }
    
    private func getTenantContext(for tenantId: String?) -> WatchTenantContext? {
        if let tenantId = tenantId {
            return tenantService.getCachedTenantContext(for: tenantId)
        }
        return currentTenantContext
    }
    
    private func getDatabaseNamespace(for tenantId: String?) -> String {
        return getTenantContext(for: tenantId)?.databaseNamespace ?? "default"
    }
    
    private func getBusinessType(for tenantId: String?) -> WatchBusinessType? {
        return getTenantContext(for: tenantId)?.businessType
    }
    
    private func getNextSequenceNumber(for tenantId: String?) -> Int {
        let key = tenantId ?? "default"
        let current = messageSequenceNumbers[key] ?? 0
        let next = current + 1
        messageSequenceNumbers[key] = next
        return next
    }
    
    private func handleTenantMessageResponse(messageId: String, response: [String: Any]) {
        guard let pendingMessage = pendingTenantMessages.removeValue(forKey: messageId) else {
            logger.warning("Received response for unknown message: \(messageId)")
            return
        }
        
        // Extract tenant information from response
        let responseTenantId = response["tenantId"] as? String
        
        // Validate tenant context
        guard responseTenantId == pendingMessage.tenantId else {
            logger.error("Tenant mismatch in response: expected \(pendingMessage.tenantId ?? "nil"), got \(responseTenantId ?? "nil")")
            return
        }
        
        processIncomingTenantMessage(response)
        logger.debug("Processed response for tenant message: \(messageId)")
    }
    
    private func processIncomingTenantMessage(_ message: [String: Any]) {
        guard let messageType = message["type"] as? String else {
            logger.warning("Received message without type")
            return
        }
        
        let tenantId = message["tenantId"] as? String
        let messageId = message["messageId"] as? String ?? UUID().uuidString
        let priorityRaw = message["priority"] as? Int ?? MessagePriority.normal.rawValue
        let priority = MessagePriority(rawValue: priorityRaw) ?? .normal
        
        let tenantMessage = TenantMessage(
            messageId: messageId,
            tenantId: tenantId,
            messageType: messageType,
            payload: message,
            timestamp: Date(),
            priority: priority
        )
        
        // Route based on message type
        switch messageType {
        case "tenantScoreUpdate":
            handleIncomingTenantScoreUpdate(tenantMessage)
        case "tenantCourseData":
            handleIncomingTenantCourseData(tenantMessage)
        case "tenantBookingUpdate":
            handleIncomingTenantBookingUpdate(tenantMessage)
        default:
            logger.debug("Received unknown tenant message type: \(messageType)")
            tenantMessageSubject.send(tenantMessage)
        }
        
        // Notify delegates
        notifyTenantDelegates { delegate in
            delegate.didReceiveTenantMessage(tenantMessage)
        }
    }
    
    private func handleIncomingTenantScoreUpdate(_ message: TenantMessage) {
        guard let scorecardData = message.payload["scorecard"] as? String,
              let data = Data(base64Encoded: scorecardData),
              let isolatedScorecard = try? JSONDecoder().decode(TenantIsolatedData<TenantAwareScorecard>.self, from: data) else {
            logger.error("Failed to decode tenant scorecard from message")
            return
        }
        
        do {
            let scorecard = try extractTenantData(isolatedScorecard, expectedTenantId: message.tenantId)
            notifyTenantDelegates { delegate in
                delegate.didReceiveTenantScoreUpdate(scorecard)
            }
        } catch {
            logger.error("Failed to extract tenant scorecard: \(error.localizedDescription)")
        }
    }
    
    private func handleIncomingTenantCourseData(_ message: TenantMessage) {
        guard let courseData = message.payload["course"] as? String,
              let data = Data(base64Encoded: courseData),
              let course = try? JSONDecoder().decode(SharedGolfCourse.self, from: data) else {
            logger.error("Failed to decode tenant course from message")
            return
        }
        
        notifyTenantDelegates { delegate in
            delegate.didReceiveTenantCourseData(course, tenantId: message.tenantId)
        }
    }
    
    private func handleIncomingTenantBookingUpdate(_ message: TenantMessage) {
        guard let bookingData = message.payload["booking"] as? String,
              let data = Data(base64Encoded: bookingData),
              let isolatedBooking = try? JSONDecoder().decode(TenantIsolatedData<TenantAwareBooking>.self, from: data) else {
            logger.error("Failed to decode tenant booking from message")
            return
        }
        
        do {
            let booking = try extractTenantData(isolatedBooking, expectedTenantId: message.tenantId)
            notifyTenantDelegates { delegate in
                delegate.didReceiveTenantBookingUpdate(booking)
            }
        } catch {
            logger.error("Failed to extract tenant booking: \(error.localizedDescription)")
        }
    }
    
    private func notifyTenantDelegates<T>(_ action: (MultiTenantWatchConnectivityDelegate) -> T) {
        DispatchQueue.main.async {
            self.tenantDelegates.forEach { weakDelegate in
                if let delegate = weakDelegate.delegate {
                    _ = action(delegate)
                }
            }
            
            // Clean up nil references
            self.tenantDelegates.removeAll { $0.delegate == nil }
        }
    }
}

// MARK: - WatchConnectivityDelegate Implementation

extension MultiTenantWatchConnectivityService: WatchConnectivityDelegate {
    func didReceiveMessage(_ message: [String : Any], replyHandler: (([String : Any]) -> Void)?) {
        processIncomingTenantMessage(message)
    }
    
    func didReceiveApplicationContext(_ context: [String : Any]) {
        // Extract tenant context if present
        let tenantId = context["tenantId"] as? String
        let contextKey = tenantId ?? "default"
        tenantApplicationContexts[contextKey] = context
        
        logger.debug("Received tenant application context for: \(contextKey)")
    }
    
    func sessionActivationDidComplete(activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("Multi-tenant connectivity session activation error: \(error.localizedDescription)")
        } else {
            logger.info("Multi-tenant connectivity session activated")
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        logger.info("Multi-tenant connectivity reachability changed: \(session.isReachable)")
    }
}

// MARK: - Supporting Types

private struct WeakMultiTenantDelegate {
    weak var delegate: MultiTenantWatchConnectivityDelegate?
    
    init(_ delegate: MultiTenantWatchConnectivityDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Mock Implementation

class MockMultiTenantWatchConnectivityService: MultiTenantWatchConnectivityServiceProtocol, ObservableObject {
    @Published private(set) var currentTenantContext: WatchTenantContext?
    
    private let tenantMessageSubject = PassthroughSubject<TenantMessage, Never>()
    private let tenantContextSubject = CurrentValueSubject<WatchTenantContext?, Never>(nil)
    
    var tenantMessageReceived: AnyPublisher<TenantMessage, Never> {
        tenantMessageSubject.eraseToAnyPublisher()
    }
    
    var tenantContextChanged: AnyPublisher<WatchTenantContext?, Never> {
        tenantContextSubject.eraseToAnyPublisher()
    }
    
    func switchTenantContext(_ context: WatchTenantContext) async {
        currentTenantContext = context
        tenantContextSubject.send(context)
    }
    
    func sendTenantMessage(_ message: [String: Any], tenantId: String?, priority: MessagePriority) async throws {
        // Mock implementation - no actual sending
    }
    
    func sendTenantScoreUpdate(_ scorecard: TenantAwareScorecard) async throws {
        // Mock implementation
    }
    
    func sendTenantCourseRequest(_ courseId: String, tenantId: String) async throws -> SharedGolfCourse? {
        return nil
    }
    
    func sendTenantBookingUpdate(_ booking: TenantAwareBooking) async throws {
        // Mock implementation
    }
    
    func updateTenantApplicationContext(_ context: [String: Any], tenantId: String?) throws {
        // Mock implementation
    }
    
    func getTenantApplicationContext(for tenantId: String?) -> [String: Any]? {
        return nil
    }
    
    func isolateTenantData<T: Codable>(_ data: T, for tenantId: String?) -> TenantIsolatedData<T> {
        return TenantIsolatedData(data: data, tenantContext: currentTenantContext)
    }
    
    func extractTenantData<T: Codable>(_ isolatedData: TenantIsolatedData<T>, expectedTenantId: String?) throws -> T {
        return isolatedData.data
    }
    
    func addTenantDelegate(_ delegate: MultiTenantWatchConnectivityDelegate) {
        // Mock implementation
    }
    
    func removeTenantDelegate(_ delegate: MultiTenantWatchConnectivityDelegate) {
        // Mock implementation
    }
}

// MARK: - Errors

enum MultiTenantConnectivityError: LocalizedError {
    case messageTimeout(messageId: String)
    case tenantMismatch(expected: String?, actual: String?)
    case namespaceMismatch(expected: String, actual: String)
    case invalidTenantData
    
    var errorDescription: String? {
        switch self {
        case .messageTimeout(let messageId):
            return "Message timeout: \(messageId)"
        case .tenantMismatch(let expected, let actual):
            return "Tenant mismatch: expected \(expected ?? "nil"), got \(actual ?? "nil")"
        case .namespaceMismatch(let expected, let actual):
            return "Database namespace mismatch: expected \(expected), got \(actual)"
        case .invalidTenantData:
            return "Invalid tenant data"
        }
    }
}