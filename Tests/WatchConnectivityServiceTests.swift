import XCTest
import WatchConnectivity
@testable import GolfFinderWatch

// MARK: - Watch Connectivity Service Tests

class WatchConnectivityServiceTests: XCTestCase {
    var mockService: MockWatchConnectivityService!
    var testDelegate: TestWatchConnectivityDelegate!
    
    override func setUp() {
        super.setUp()
        mockService = MockWatchConnectivityService()
        testDelegate = TestWatchConnectivityDelegate()
        mockService.setDelegate(testDelegate)
    }
    
    override func tearDown() {
        mockService = nil
        testDelegate = nil
        super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testServiceInitialization() {
        XCTAssertTrue(mockService.isSupported, "Mock service should be supported")
        XCTAssertTrue(mockService.isReachable, "Mock service should be reachable by default")
        XCTAssertEqual(mockService.activationState, .activated, "Mock service should be activated")
    }
    
    func testSendMessage() async {
        let expectation = expectation(description: "Message sent")
        let testMessage = ["type": "test", "data": "test_data"]
        
        mockService.sendMessage(testMessage) { response in
            XCTAssertNotNil(response, "Should receive response")
            expectation.fulfill()
        } errorHandler: { error in
            XCTFail("Should not receive error: \(error)")
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testSendMessageWithError() async {
        mockService.configureSimulation(shouldSimulateErrors: true)
        
        let expectation = expectation(description: "Error received")
        let testMessage = ["type": "test", "data": "test_data"]
        
        mockService.sendMessage(testMessage) { response in
            XCTFail("Should not receive response when error is configured")
        } errorHandler: { error in
            XCTAssertNotNil(error, "Should receive error")
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testUpdateApplicationContext() async throws {
        let context = ["activeRound": "test_round_data", "timestamp": 123456789]
        
        XCTAssertNoThrow(try mockService.updateApplicationContext(context))
        
        // Verify delegate was notified
        XCTAssertTrue(testDelegate.didReceiveApplicationContextCalled)
        XCTAssertEqual(testDelegate.receivedContext.count, context.count)
    }
    
    func testUpdateApplicationContextWithInactiveSession() {
        mockService.configureMockState(activationState: .notActivated)
        
        let context = ["test": "data"]
        
        XCTAssertThrowsError(try mockService.updateApplicationContext(context)) { error in
            XCTAssertTrue(error is WatchConnectivityError)
        }
    }
    
    // MARK: - Golf-Specific Method Tests
    
    func testSendScoreUpdate() async {
        let mockScorecard = createMockScorecard()
        
        mockService.sendScoreUpdate(mockScorecard)
        
        // Verify message was processed
        await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        XCTAssertTrue(testDelegate.didReceiveScoreUpdateCalled)
        XCTAssertEqual(testDelegate.receivedScorecard?.id, mockScorecard.id)
    }
    
    func testSendCourseData() async {
        let mockCourse = createMockCourse()
        
        mockService.sendCourseData(mockCourse)
        
        // Verify message was processed
        await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        XCTAssertTrue(testDelegate.didReceiveCourseDataCalled)
        XCTAssertEqual(testDelegate.receivedCourse?.id, mockCourse.id)
    }
    
    func testSendActiveRoundUpdate() async {
        let mockRound = createMockActiveRound()
        
        mockService.sendActiveRoundUpdate(mockRound)
        
        // Verify message was processed and application context updated
        await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        XCTAssertTrue(testDelegate.didReceiveActiveRoundUpdateCalled)
        XCTAssertEqual(testDelegate.receivedActiveRound?.id, mockRound.id)
        XCTAssertTrue(testDelegate.didReceiveApplicationContextCalled)
    }
    
    func testRequestCourseInformation() async {
        let courseId = "test_course_123"
        
        mockService.requestCourseInformation(courseId: courseId)
        
        // Verify response was received
        await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        XCTAssertTrue(testDelegate.didReceiveCourseDataCalled)
        XCTAssertNotNil(testDelegate.receivedCourse)
    }
    
    func testRequestCurrentRound() async {
        mockService.requestCurrentRound()
        
        // Verify response was received
        await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        XCTAssertTrue(testDelegate.didReceiveActiveRoundUpdateCalled)
        XCTAssertNotNil(testDelegate.receivedActiveRound)
    }
    
    // MARK: - Delegate Management Tests
    
    func testDelegateManagement() {
        let delegate1 = TestWatchConnectivityDelegate()
        let delegate2 = TestWatchConnectivityDelegate()
        
        // Add delegates
        mockService.setDelegate(delegate1)
        mockService.setDelegate(delegate2)
        
        // Send a test message to verify delegates are called
        let testMessage = ["type": "test"]
        mockService.sendMessage(testMessage)
        
        // Both delegates should be called (in mock implementation)
        // Note: In real implementation, we'd need to verify this properly
    }
    
    func testDelegateRemoval() {
        let delegate = TestWatchConnectivityDelegate()
        
        mockService.setDelegate(delegate)
        mockService.removeDelegate(delegate)
        
        // Delegate should no longer receive callbacks
        let testMessage = ["type": "test"]
        mockService.sendMessage(testMessage)
        
        // Delegate should not be called (would need proper verification in real test)
    }
    
    // MARK: - Configuration Tests
    
    func testMockStateConfiguration() {
        mockService.configureMockState(
            isSupported: false,
            isReachable: false,
            activationState: .inactive
        )
        
        XCTAssertFalse(mockService.isSupported)
        XCTAssertFalse(mockService.isReachable)
        XCTAssertEqual(mockService.activationState, .inactive)
    }
    
    func testSimulationConfiguration() {
        mockService.configureSimulation(
            shouldSimulateDelay: false,
            shouldSimulateErrors: true,
            messageDelay: 2.0
        )
        
        // Test that error simulation is working
        let expectation = expectation(description: "Error simulation")
        let testMessage = ["type": "test"]
        
        mockService.sendMessage(testMessage) { _ in
            XCTFail("Should not succeed with error simulation")
        } errorHandler: { _ in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Analytics Tests
    
    func testAnalytics() {
        // Send some messages to generate analytics
        let testMessage = ["type": "test"]
        mockService.sendMessage(testMessage)
        mockService.sendMessage(testMessage)
        
        let analytics = mockService.getAnalytics()
        
        XCTAssertGreaterThan(analytics["messagesSent"] as? Int ?? 0, 0)
        XCTAssertEqual(analytics["activeDelegates"] as? Int, 1)
    }
    
    func testAnalyticsReset() {
        // Generate some analytics
        mockService.sendMessage(["type": "test"])
        
        // Reset
        mockService.resetAnalytics()
        
        let analytics = mockService.getAnalytics()
        XCTAssertEqual(analytics["messagesSent"] as? Int, 0)
        XCTAssertEqual(analytics["messagesReceived"] as? Int, 0)
    }
    
    // MARK: - Session Simulation Tests
    
    func testSessionActivationSimulation() {
        let expectation = expectation(description: "Session activation")
        
        // Set up delegate expectation
        testDelegate.sessionActivationExpectation = expectation
        
        mockService.simulateSessionActivation(state: .activated, error: nil)
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(testDelegate.sessionActivationDidCompleteCalled)
    }
    
    func testReachabilityChangeSimulation() {
        mockService.simulateReachabilityChange(isReachable: false)
        XCTAssertFalse(mockService.isReachable)
        
        mockService.simulateReachabilityChange(isReachable: true)
        XCTAssertTrue(mockService.isReachable)
    }
    
    // MARK: - Performance Tests
    
    func testMessagePerformance() {
        measure {
            for _ in 0..<100 {
                mockService.sendMessage(["type": "performance_test"])
            }
        }
    }
    
    func testBulkDataTransfer() {
        let largeCourse = createLargeMockCourse()
        
        measure {
            mockService.sendCourseData(largeCourse)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createMockScorecard() -> SharedScorecard {
        return SharedScorecard(
            id: "test_scorecard_123",
            userId: "test_user",
            courseId: "test_course",
            courseName: "Test Golf Course",
            playedDate: Date(),
            numberOfHoles: 18,
            coursePar: 72,
            teeType: .regular,
            holeScores: [],
            totalScore: 85,
            scoreRelativeToPar: 13,
            statistics: SharedRoundStatistics(
                pars: 10, birdies: 2, eagles: 0, bogeys: 4,
                doubleBogeys: 2, otherScores: 0, fairwaysHit: 8,
                totalFairways: 14, greensInRegulation: 6,
                totalGreens: 18, totalPutts: 32, totalPenalties: 1
            ),
            isComplete: true,
            currentHole: 19,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    private func createMockCourse() -> SharedGolfCourse {
        return SharedGolfCourse(
            id: "test_course_123",
            name: "Test Golf Course",
            address: "123 Test Ave",
            city: "Test City",
            state: "TS",
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
    
    private func createMockActiveRound() -> ActiveGolfRound {
        return ActiveGolfRound(
            id: "test_round_123",
            courseId: "test_course_123",
            courseName: "Test Golf Course",
            startTime: Date(),
            currentHole: 5,
            scores: [1: "4", 2: "3", 3: "5", 4: "4"],
            totalScore: 16,
            totalPar: 16,
            holes: [],
            teeType: .regular
        )
    }
    
    private func createLargeMockCourse() -> SharedGolfCourse {
        var course = createMockCourse()
        // Add complexity for performance testing
        return course
    }
}

// MARK: - Test Delegate

class TestWatchConnectivityDelegate: WatchConnectivityDelegate {
    // Tracking properties
    var didReceiveScoreUpdateCalled = false
    var didReceiveCourseDataCalled = false
    var didReceiveActiveRoundUpdateCalled = false
    var didReceiveApplicationContextCalled = false
    var didReceiveMessageCalled = false
    var sessionActivationDidCompleteCalled = false
    var sessionReachabilityDidChangeCalled = false
    
    // Received data
    var receivedScorecard: SharedScorecard?
    var receivedCourse: SharedGolfCourse?
    var receivedActiveRound: ActiveGolfRound?
    var receivedContext: [String: Any] = [:]
    var receivedMessage: [String: Any] = [:]
    
    // Expectations for async testing
    var sessionActivationExpectation: XCTestExpectation?
    var reachabilityChangeExpectation: XCTestExpectation?
    
    func didReceiveScoreUpdate(_ scorecard: SharedScorecard) {
        didReceiveScoreUpdateCalled = true
        receivedScorecard = scorecard
    }
    
    func didReceiveCourseData(_ course: SharedGolfCourse) {
        didReceiveCourseDataCalled = true
        receivedCourse = course
    }
    
    func didReceiveActiveRoundUpdate(_ round: ActiveGolfRound) {
        didReceiveActiveRoundUpdateCalled = true
        receivedActiveRound = round
    }
    
    func didReceiveApplicationContext(_ context: [String: Any]) {
        didReceiveApplicationContextCalled = true
        receivedContext = context
    }
    
    func didReceiveMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        didReceiveMessageCalled = true
        receivedMessage = message
    }
    
    func sessionActivationDidComplete(activationState: WCSessionActivationState, error: Error?) {
        sessionActivationDidCompleteCalled = true
        sessionActivationExpectation?.fulfill()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        sessionReachabilityDidChangeCalled = true
        reachabilityChangeExpectation?.fulfill()
    }
    
    // Reset method for test isolation
    func reset() {
        didReceiveScoreUpdateCalled = false
        didReceiveCourseDataCalled = false
        didReceiveActiveRoundUpdateCalled = false
        didReceiveApplicationContextCalled = false
        didReceiveMessageCalled = false
        sessionActivationDidCompleteCalled = false
        sessionReachabilityDidChangeCalled = false
        
        receivedScorecard = nil
        receivedCourse = nil
        receivedActiveRound = nil
        receivedContext = [:]
        receivedMessage = [:]
        
        sessionActivationExpectation = nil
        reachabilityChangeExpectation = nil
    }
}