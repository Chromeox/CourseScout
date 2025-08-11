import Foundation
import WatchConnectivity
import os.log

// MARK: - Mock Watch Connectivity Service

class MockWatchConnectivityService: WatchConnectivityServiceProtocol {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "MockWatchConnectivity")
    private var delegates: [WeakWatchConnectivityDelegate] = []
    
    // Mock state
    private(set) var isSupported: Bool = true
    private(set) var isReachable: Bool = true
    private(set) var activationState: WCSessionActivationState = .activated
    
    // Mock data storage
    private var mockCourses: [String: SharedGolfCourse] = [:]
    private var mockScorecards: [String: SharedScorecard] = [:]
    private var mockActiveRounds: [String: ActiveGolfRound] = [:]
    private var applicationContext: [String: Any] = [:]
    
    // Message simulation
    private var shouldSimulateDelay: Bool = true
    private var shouldSimulateErrors: Bool = false
    private var messageDelay: TimeInterval = 0.5
    
    // Analytics
    private var messagesSent: Int = 0
    private var messagesReceived: Int = 0
    private var contextUpdates: Int = 0
    
    // MARK: - Initialization
    
    init() {
        setupMockData()
        logger.info("MockWatchConnectivityService initialized")
    }
    
    // MARK: - Configuration Methods (for testing)
    
    func configureMockState(
        isSupported: Bool = true,
        isReachable: Bool = true,
        activationState: WCSessionActivationState = .activated
    ) {
        self.isSupported = isSupported
        self.isReachable = isReachable
        self.activationState = activationState
        logger.debug("Mock state configured: supported=\(isSupported), reachable=\(isReachable), state=\(activationState.rawValue)")
    }
    
    func configureSimulation(
        shouldSimulateDelay: Bool = true,
        shouldSimulateErrors: Bool = false,
        messageDelay: TimeInterval = 0.5
    ) {
        self.shouldSimulateDelay = shouldSimulateDelay
        self.shouldSimulateErrors = shouldSimulateErrors
        self.messageDelay = messageDelay
        logger.debug("Simulation configured: delay=\(shouldSimulateDelay), errors=\(shouldSimulateErrors), delayTime=\(messageDelay)")
    }
    
    // MARK: - Data Transfer Methods
    
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)? = nil,
        errorHandler: ((Error) -> Void)? = nil
    ) {
        messagesSent += 1
        logger.debug("Sending mock message (total sent: \(messagesSent))")
        
        // Simulate errors if configured
        if shouldSimulateErrors && Int.random(in: 1...10) <= 2 { // 20% error rate
            let error = WatchConnectivityError.counterpartNotReachable
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                errorHandler?(error)
            }
            return
        }
        
        // Process message
        let delay = shouldSimulateDelay ? messageDelay : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.processMessage(message, replyHandler: replyHandler)
        }
    }
    
    func updateApplicationContext(_ context: [String: Any]) throws {
        if !isSupported || activationState != .activated {
            throw WatchConnectivityError.sessionNotActivated
        }
        
        applicationContext = context
        contextUpdates += 1
        logger.debug("Updated mock application context (total updates: \(contextUpdates))")
        
        // Notify delegates
        DispatchQueue.main.async {
            self.delegates.forEach { $0.delegate?.didReceiveApplicationContext(context) }
        }
    }
    
    func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer? {
        logger.debug("Mock user info transfer initiated")
        
        // Simulate the transfer
        DispatchQueue.main.asyncAfter(deadline: .now() + (shouldSimulateDelay ? messageDelay : 0)) {
            self.processMessage(userInfo, replyHandler: nil)
        }
        
        return nil // Return nil for mock, as we can't create a real transfer object
    }
    
    func transferFile(at url: URL, metadata: [String: Any]? = nil) -> WCSessionFileTransfer? {
        logger.debug("Mock file transfer initiated for: \(url.lastPathComponent)")
        return nil // Return nil for mock
    }
    
    // MARK: - Golf-Specific Methods
    
    func sendScoreUpdate(_ scorecard: SharedScorecard) {
        logger.info("Sending mock score update for round: \(scorecard.id)")
        
        // Store in mock data
        mockScorecards[scorecard.id] = scorecard
        
        let message: [String: Any] = [
            "type": "scoreUpdate",
            "scorecard": try! JSONEncoder().encode(scorecard).base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        sendMessage(message, errorHandler: { error in
            self.logger.error("Mock score update failed: \(error.localizedDescription)")
        })
    }
    
    func sendCourseData(_ course: SharedGolfCourse) {
        logger.info("Sending mock course data: \(course.name)")
        
        // Store in mock data
        mockCourses[course.id] = course
        
        let message: [String: Any] = [
            "type": "courseData",
            "course": try! JSONEncoder().encode(course).base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        sendMessage(message, errorHandler: { error in
            self.logger.error("Mock course data failed: \(error.localizedDescription)")
        })
    }
    
    func sendActiveRoundUpdate(_ round: ActiveGolfRound) {
        logger.info("Sending mock active round update: \(round.courseName), hole \(round.currentHole)")
        
        // Store in mock data
        mockActiveRounds[round.id] = round
        
        let message: [String: Any] = [
            "type": "activeRoundUpdate",
            "round": try! JSONEncoder().encode(round).base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Update application context
        do {
            try updateApplicationContext([
                "activeRound": try! JSONEncoder().encode(round).base64EncodedString(),
                "timestamp": Date().timeIntervalSince1970
            ])
        } catch {
            logger.error("Failed to update mock application context: \(error.localizedDescription)")
        }
        
        sendMessage(message, errorHandler: { error in
            self.logger.error("Mock active round update failed: \(error.localizedDescription)")
        })
    }
    
    func requestCourseInformation(courseId: String) {
        logger.info("Requesting mock course information: \(courseId)")
        
        let delay = shouldSimulateDelay ? messageDelay : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let course = self.mockCourses[courseId] {
                self.delegates.forEach { $0.delegate?.didReceiveCourseData(course) }
            } else {
                // Generate a mock course if none exists
                let mockCourse = self.generateMockCourse(id: courseId)
                self.mockCourses[courseId] = mockCourse
                self.delegates.forEach { $0.delegate?.didReceiveCourseData(mockCourse) }
            }
        }
    }
    
    func requestCurrentRound() {
        logger.info("Requesting mock current round information")
        
        let delay = shouldSimulateDelay ? messageDelay : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let round = self.mockActiveRounds.values.first {
                self.delegates.forEach { $0.delegate?.didReceiveActiveRoundUpdate(round) }
            } else {
                // Generate a mock active round
                let mockRound = self.generateMockActiveRound()
                self.mockActiveRounds[mockRound.id] = mockRound
                self.delegates.forEach { $0.delegate?.didReceiveActiveRoundUpdate(mockRound) }
            }
        }
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: WatchConnectivityDelegate) {
        // Remove any existing weak references to the same delegate
        delegates.removeAll { $0.delegate === delegate }
        
        // Add new weak reference
        delegates.append(WeakWatchConnectivityDelegate(delegate))
        
        // Clean up any nil references
        delegates.removeAll { $0.delegate == nil }
        
        logger.debug("Added mock WatchConnectivity delegate")
    }
    
    func removeDelegate(_ delegate: WatchConnectivityDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        logger.debug("Removed mock WatchConnectivity delegate")
    }
    
    // MARK: - Mock Data Setup
    
    private func setupMockData() {
        // Create mock course
        let mockCourse = generateMockCourse(id: "mock-course-1")
        mockCourses[mockCourse.id] = mockCourse
        
        // Create mock active round
        let mockRound = generateMockActiveRound()
        mockActiveRounds[mockRound.id] = mockRound
        
        logger.debug("Mock data setup complete")
    }
    
    private func generateMockCourse(id: String) -> SharedGolfCourse {
        return SharedGolfCourse(
            id: id,
            name: "Mock Golf Club",
            address: "123 Golf Course Dr",
            city: "Golf City",
            state: "CA",
            latitude: 37.7749,
            longitude: -122.4194,
            numberOfHoles: 18,
            par: 72,
            yardage: SharedCourseYardage(backTees: 6800, regularTees: 6200, forwardTees: 5400),
            hasGPS: true,
            hasDrivingRange: true,
            hasRestaurant: true,
            cartRequired: false,
            averageRating: 4.2,
            difficulty: .intermediate,
            isOpen: true,
            isActive: true
        )
    }
    
    private func generateMockActiveRound() -> ActiveGolfRound {
        let holes = (1...18).map { holeNumber in
            SharedHoleInfo(
                id: "hole-\(holeNumber)",
                holeNumber: holeNumber,
                par: holeNumber <= 4 || (holeNumber >= 10 && holeNumber <= 13) ? 4 : (holeNumber == 18 || holeNumber == 9 ? 5 : 3),
                yardage: Int.random(in: 150...450),
                handicapIndex: holeNumber,
                teeCoordinate: CLLocationCoordinate2D(latitude: 37.7749 + Double(holeNumber) * 0.001, longitude: -122.4194),
                pinCoordinate: CLLocationCoordinate2D(latitude: 37.7749 + Double(holeNumber) * 0.001 + 0.0005, longitude: -122.4194 + 0.0005),
                hazards: []
            )
        }
        
        return ActiveGolfRound(
            id: "mock-round-1",
            courseId: "mock-course-1",
            courseName: "Mock Golf Club",
            startTime: Date().addingTimeInterval(-3600), // Started 1 hour ago
            currentHole: 5,
            scores: [1: "4", 2: "3", 3: "5", 4: "4"],
            totalScore: 16,
            totalPar: 14,
            holes: holes,
            teeType: .regular
        )
    }
    
    // MARK: - Message Processing
    
    private func processMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        messagesReceived += 1
        logger.debug("Processing mock message (total received: \(messagesReceived))")
        
        guard let type = message["type"] as? String else {
            logger.warning("Received mock message without type")
            replyHandler?(["error": "No message type"])
            return
        }
        
        switch type {
        case "scoreUpdate":
            if let scorecardData = message["scorecard"] as? String,
               let data = Data(base64Encoded: scorecardData),
               let scorecard = try? JSONDecoder().decode(SharedScorecard.self, from: data) {
                delegates.forEach { $0.delegate?.didReceiveScoreUpdate(scorecard) }
                replyHandler?(["status": "success"])
            }
            
        case "courseData":
            if let courseData = message["course"] as? String,
               let data = Data(base64Encoded: courseData),
               let course = try? JSONDecoder().decode(SharedGolfCourse.self, from: data) {
                delegates.forEach { $0.delegate?.didReceiveCourseData(course) }
                replyHandler?(["status": "success"])
            }
            
        case "activeRoundUpdate":
            if let roundData = message["round"] as? String,
               let data = Data(base64Encoded: roundData),
               let round = try? JSONDecoder().decode(ActiveGolfRound.self, from: data) {
                delegates.forEach { $0.delegate?.didReceiveActiveRoundUpdate(round) }
                replyHandler?(["status": "success"])
            }
            
        case "requestCourseInfo":
            if let courseId = message["courseId"] as? String {
                requestCourseInformation(courseId: courseId)
                replyHandler?(["status": "success"])
            }
            
        case "requestCurrentRound":
            requestCurrentRound()
            replyHandler?(["status": "success"])
            
        default:
            logger.debug("Unknown mock message type: \(type)")
            replyHandler?(["error": "Unknown message type"])
        }
    }
    
    // MARK: - Analytics and Testing Helpers
    
    func getAnalytics() -> [String: Any] {
        return [
            "messagesSent": messagesSent,
            "messagesReceived": messagesReceived,
            "contextUpdates": contextUpdates,
            "activeDelegates": delegates.count,
            "mockCourses": mockCourses.count,
            "mockScorecards": mockScorecards.count,
            "mockActiveRounds": mockActiveRounds.count
        ]
    }
    
    func resetAnalytics() {
        messagesSent = 0
        messagesReceived = 0
        contextUpdates = 0
        logger.debug("Mock analytics reset")
    }
    
    func simulateSessionActivation(state: WCSessionActivationState = .activated, error: Error? = nil) {
        activationState = state
        delegates.forEach { $0.delegate?.sessionActivationDidComplete(activationState: state, error: error) }
        logger.debug("Simulated session activation with state: \(state.rawValue)")
    }
    
    func simulateReachabilityChange(isReachable: Bool) {
        self.isReachable = isReachable
        // Note: We can't create a real WCSession, so we'll notify with nil
        // In real implementation, delegates would need to check the service's isReachable property
        logger.debug("Simulated reachability change to: \(isReachable)")
    }
}

// MARK: - Supporting Types

private struct WeakWatchConnectivityDelegate {
    weak var delegate: WatchConnectivityDelegate?
    
    init(_ delegate: WatchConnectivityDelegate) {
        self.delegate = delegate
    }
}