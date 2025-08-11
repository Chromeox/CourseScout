import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - Watch Connectivity Integration Tests

@MainActor
final class WatchConnectivityIntegrationTests: XCTestCase {
    
    private var watchConnectivityManager: WatchConnectivityManagerProtocol!
    private var cancellables: Set<AnyCancellable> = []
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Use mock service for testing
        watchConnectivityManager = MockWatchConnectivityManager()
    }
    
    override func tearDown() async throws {
        watchConnectivityManager = nil
        cancellables.removeAll()
        try await super.tearDown()
    }
    
    // MARK: - Connection Tests
    
    func testWatchConnectivityInitialization() {
        // Given
        let manager = watchConnectivityManager!
        
        // Then
        XCTAssertTrue(manager.isWatchPaired)
        XCTAssertTrue(manager.isWatchAppInstalled)
        XCTAssertEqual(manager.connectionState, .connected)
    }
    
    func testStartConnectivity() {
        // Given
        let manager = watchConnectivityManager!
        
        // When
        manager.startConnectivity()
        
        // Then
        XCTAssertTrue(manager.isWatchReachable)
        XCTAssertEqual(manager.connectionState, .connected)
    }
    
    func testStopConnectivity() {
        // Given
        let manager = watchConnectivityManager!
        manager.startConnectivity()
        
        // When
        manager.stopConnectivity()
        
        // Then
        XCTAssertFalse(manager.isWatchReachable)
        XCTAssertEqual(manager.connectionState, .disconnected)
    }
    
    // MARK: - Golf Round Tests
    
    func testStartGolfRound() async {
        // Given
        let manager = watchConnectivityManager!
        let mockRound = createMockGolfRound()
        
        // When
        let success = await manager.startGolfRound(mockRound)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertEqual(manager.syncState, .completed)
        XCTAssertNotNil(manager.lastSyncTime)
    }
    
    func testUpdateScorecard() async {
        // Given
        let manager = watchConnectivityManager!
        let mockScorecard = createMockScorecard()
        
        // When
        await manager.updateScorecard(mockScorecard)
        
        // Then
        XCTAssertEqual(manager.syncState, .completed)
        XCTAssertNotNil(manager.lastSyncTime)
    }
    
    func testEndGolfRound() async {
        // Given
        let manager = watchConnectivityManager!
        let mockRound = createMockGolfRound()
        _ = await manager.startGolfRound(mockRound)
        
        // When
        let success = await manager.endGolfRound()
        
        // Then
        XCTAssertTrue(success)
        XCTAssertEqual(manager.syncState, .completed)
    }
    
    // MARK: - Message Sending Tests
    
    func testSendHighPriorityMessage() async {
        // Given
        let manager = watchConnectivityManager!
        let testData = ["test": "data"]
        
        // When
        let success = await manager.sendHighPriorityMessage(
            type: .ping,
            data: testData,
            requiresAck: true
        )
        
        // Then
        XCTAssertTrue(success)
    }
    
    func testSendNormalPriorityMessage() async {
        // Given
        let manager = watchConnectivityManager!
        let testData = ["test": "data"]
        
        // When
        await manager.sendNormalPriorityMessage(
            type: .healthUpdate,
            data: testData
        )
        
        // Then - Should complete without error
        XCTAssertEqual(manager.connectionState, .connected)
    }
    
    // MARK: - Battery Optimization Tests
    
    func testEnableBatteryOptimization() {
        // Given
        let manager = watchConnectivityManager!
        
        // When
        manager.enableBatteryOptimization(true)
        
        // Then - Should not throw error
        XCTAssertEqual(manager.connectionState, .connected)
    }
    
    func testDisableBatteryOptimization() {
        // Given
        let manager = watchConnectivityManager!
        manager.enableBatteryOptimization(true)
        
        // When
        manager.enableBatteryOptimization(false)
        
        // Then - Should not throw error
        XCTAssertEqual(manager.connectionState, .connected)
    }
    
    // MARK: - Health Data Tests
    
    func testSyncHealthMetrics() {
        // Given
        let manager = watchConnectivityManager!
        let mockMetrics = createMockHealthMetrics()
        
        // When
        manager.syncHealthMetrics(mockMetrics)
        
        // Then - Should not throw error
        XCTAssertEqual(manager.connectionState, .connected)
    }
    
    // MARK: - Haptic Feedback Tests
    
    func testSendHapticFeedback() {
        // Given
        let manager = watchConnectivityManager!
        let context = HapticContext(intensity: 1.0, pattern: "test")
        
        // When
        manager.sendHapticFeedback(.success, context: context)
        
        // Then - Should not throw error
        XCTAssertEqual(manager.connectionState, .connected)
    }
    
    func testCelebrateMilestone() {
        // Given
        let manager = watchConnectivityManager!
        let milestone = GolfMilestone.birdie
        
        // When
        manager.celebrateMilestone(milestone)
        
        // Then - Should not throw error
        XCTAssertEqual(manager.connectionState, .connected)
    }
    
    // MARK: - Delegate Tests
    
    func testDelegateManagement() {
        // Given
        let manager = watchConnectivityManager!
        let mockDelegate = MockWatchConnectivityDelegate()
        
        // When
        manager.addDelegate(mockDelegate)
        
        // Then - Should not throw error
        XCTAssertEqual(manager.connectionState, .connected)
        
        // When
        manager.removeDelegate(mockDelegate)
        
        // Then - Should not throw error
        XCTAssertEqual(manager.connectionState, .connected)
    }
    
    func testDelegateNotifications() async {
        // Given
        let manager = watchConnectivityManager!
        let mockDelegate = MockWatchConnectivityDelegate()
        manager.addDelegate(mockDelegate)
        
        let expectation = XCTestExpectation(description: "Delegate notification received")
        mockDelegate.onConnectionStateChange = { state in
            XCTAssertEqual(state, .connected)
            expectation.fulfill()
        }
        
        // When
        manager.startConnectivity()
        
        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    // MARK: - Battery Simulation Tests (Mock-specific)
    
    func testBatterySimulation() {
        // Given
        guard let mockManager = watchConnectivityManager as? MockWatchConnectivityManager else {
            XCTFail("Expected MockWatchConnectivityManager")
            return
        }
        
        let initialBatteryLevel = mockManager.batteryInfo?.level ?? 100.0
        
        // When
        mockManager.simulateLowBattery()
        
        // Then
        XCTAssertNotNil(mockManager.batteryInfo)
        XCTAssertLessThan(mockManager.batteryInfo!.level, initialBatteryLevel)
        XCTAssertTrue(mockManager.batteryInfo!.isLowPowerMode)
    }
    
    func testCriticalBatterySimulation() {
        // Given
        guard let mockManager = watchConnectivityManager as? MockWatchConnectivityManager else {
            XCTFail("Expected MockWatchConnectivityManager")
            return
        }
        
        // When
        mockManager.simulateCriticalBattery()
        
        // Then
        XCTAssertNotNil(mockManager.batteryInfo)
        XCTAssertLessThanOrEqual(mockManager.batteryInfo!.level, 10.0)
        XCTAssertTrue(mockManager.batteryInfo!.isLowPowerMode)
    }
    
    func testConnectionLossSimulation() {
        // Given
        guard let mockManager = watchConnectivityManager as? MockWatchConnectivityManager else {
            XCTFail("Expected MockWatchConnectivityManager")
            return
        }
        
        mockManager.startConnectivity()
        XCTAssertTrue(mockManager.isWatchReachable)
        
        // When
        mockManager.simulateConnectionLoss()
        
        // Then
        XCTAssertFalse(mockManager.isWatchReachable)
        XCTAssertEqual(mockManager.connectionState, .disconnected)
    }
    
    func testConnectionRestoreSimulation() {
        // Given
        guard let mockManager = watchConnectivityManager as? MockWatchConnectivityManager else {
            XCTFail("Expected MockWatchConnectivityManager")
            return
        }
        
        mockManager.simulateConnectionLoss()
        XCTAssertFalse(mockManager.isWatchReachable)
        
        // When
        mockManager.simulateConnectionRestore()
        
        // Then
        XCTAssertTrue(mockManager.isWatchReachable)
        XCTAssertEqual(mockManager.connectionState, .connected)
    }
    
    // MARK: - Performance Tests
    
    func testHighVolumeMessageSending() async {
        // Given
        let manager = watchConnectivityManager!
        let messageCount = 100
        
        // When
        let startTime = Date()
        
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<messageCount {
                group.addTask {
                    return await manager.sendHighPriorityMessage(
                        type: .ping,
                        data: ["index": i],
                        requiresAck: false
                    )
                }
            }
            
            // Wait for all tasks to complete
            var successCount = 0
            for await success in group {
                if success {
                    successCount += 1
                }
            }
            
            // Then
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            XCTAssertEqual(successCount, messageCount)
            XCTAssertLessThan(duration, 10.0) // Should complete within 10 seconds
        }
    }
    
    func testConcurrentOperations() async {
        // Given
        let manager = watchConnectivityManager!
        let mockRound = createMockGolfRound()
        let mockScorecard = createMockScorecard()
        let mockMetrics = createMockHealthMetrics()
        
        // When
        async let roundResult = manager.startGolfRound(mockRound)
        async let scorecardTask: Void = manager.updateScorecard(mockScorecard)
        let healthTask: Void = manager.syncHealthMetrics(mockMetrics)
        
        let results = await (roundResult, scorecardTask, healthTask)
        
        // Then
        XCTAssertTrue(results.0) // Round start should succeed
        // Other operations should complete without error
    }
    
    // MARK: - Helper Methods
    
    private func createMockGolfRound() -> ActiveGolfRound {
        return ActiveGolfRound(
            id: UUID().uuidString,
            courseId: "mock-course-1",
            courseName: "Mock Golf Course",
            startTime: Date(),
            currentHole: 1,
            totalHoles: 18,
            currentScore: 0
        )
    }
    
    private func createMockScorecard() -> SharedScorecard {
        return SharedScorecard(
            id: UUID().uuidString,
            roundId: "mock-round-1",
            holes: [],
            totalScore: 72,
            lastUpdated: Date(),
            modifiedHoles: [1, 2, 3]
        )
    }
    
    private func createMockHealthMetrics() -> WatchHealthMetrics {
        return WatchHealthMetrics(from: [
            "heartRate": 85.0,
            "averageHeartRate": 90.0,
            "caloriesBurned": 450.0,
            "stepCount": 8500,
            "distanceWalked": 6000.0,
            "currentHeartRate": 88.0,
            "heartRateZone": "moderate"
        ])
    }
}

// MARK: - Mock Delegate

class MockWatchConnectivityDelegate: WatchConnectivityDelegate {
    var onConnectionStateChange: ((WatchConnectionState) -> Void)?
    var onHealthMetrics: ((WatchHealthMetrics) -> Void)?
    var onScorecardUpdate: ((SharedScorecard) -> Void)?
    var onBatteryInfo: ((WatchBatteryInfo) -> Void)?
    
    func watchConnectivityManager(_ manager: WatchConnectivityManagerProtocol, didChangeConnectionState state: WatchConnectionState) {
        onConnectionStateChange?(state)
    }
    
    func watchConnectivityManager(_ manager: WatchConnectivityManagerProtocol, didReceiveHealthMetrics metrics: WatchHealthMetrics) {
        onHealthMetrics?(metrics)
    }
    
    func watchConnectivityManager(_ manager: WatchConnectivityManagerProtocol, didUpdateScorecard scorecard: SharedScorecard) {
        onScorecardUpdate?(scorecard)
    }
    
    func watchConnectivityManager(_ manager: WatchConnectivityManagerProtocol, didReceiveBatteryInfo info: WatchBatteryInfo) {
        onBatteryInfo?(info)
    }
}

// MARK: - Integration Test Scenarios

extension WatchConnectivityIntegrationTests {
    
    func testCompleteGolfRoundScenario() async {
        // Given
        let manager = watchConnectivityManager!
        let mockDelegate = MockWatchConnectivityDelegate()
        manager.addDelegate(mockDelegate)
        
        var receivedUpdates: [String] = []
        
        mockDelegate.onScorecardUpdate = { _ in
            receivedUpdates.append("scorecard")
        }
        
        mockDelegate.onHealthMetrics = { _ in
            receivedUpdates.append("health")
        }
        
        // When - Complete golf round scenario
        manager.startConnectivity()
        
        let mockRound = createMockGolfRound()
        let startSuccess = await manager.startGolfRound(mockRound)
        XCTAssertTrue(startSuccess)
        
        // Simulate playing holes
        for hole in 1...3 {
            let scorecard = createMockScorecard()
            await manager.updateScorecard(scorecard)
            
            let metrics = createMockHealthMetrics()
            manager.syncHealthMetrics(metrics)
            
            // Celebrate milestones
            if hole == 2 {
                manager.celebrateMilestone(.birdie)
            }
        }
        
        let endSuccess = await manager.endGolfRound()
        XCTAssertTrue(endSuccess)
        
        manager.stopConnectivity()
        
        // Then
        XCTAssertGreaterThan(receivedUpdates.count, 0)
        XCTAssertTrue(receivedUpdates.contains("scorecard"))
        XCTAssertTrue(receivedUpdates.contains("health"))
    }
    
    func testBatteryOptimizationScenario() async {
        // Given
        guard let mockManager = watchConnectivityManager as? MockWatchConnectivityManager else {
            XCTFail("Expected MockWatchConnectivityManager")
            return
        }
        
        let mockDelegate = MockWatchConnectivityDelegate()
        mockManager.addDelegate(mockDelegate)
        
        var batteryAlerts: [WatchBatteryInfo] = []
        
        mockDelegate.onBatteryInfo = { info in
            batteryAlerts.append(info)
        }
        
        // When - Simulate battery drain during round
        mockManager.startConnectivity()
        
        let mockRound = createMockGolfRound()
        _ = await mockManager.startGolfRound(mockRound)
        
        // Normal operation
        mockManager.enableBatteryOptimization(false)
        
        // Simulate low battery
        mockManager.simulateLowBattery()
        mockManager.enableBatteryOptimization(true)
        
        // Simulate critical battery
        mockManager.simulateCriticalBattery()
        
        // Then
        XCTAssertGreaterThan(batteryAlerts.count, 0)
        XCTAssertTrue(batteryAlerts.contains { $0.level < 20 })
        XCTAssertTrue(batteryAlerts.contains { $0.level < 10 })
    }
    
    func testConnectivityResilienceScenario() async {
        // Given
        guard let mockManager = watchConnectivityManager as? MockWatchConnectivityManager else {
            XCTFail("Expected MockWatchConnectivityManager")
            return
        }
        
        let mockDelegate = MockWatchConnectivityDelegate()
        mockManager.addDelegate(mockDelegate)
        
        var connectionChanges: [WatchConnectionState] = []
        
        mockDelegate.onConnectionStateChange = { state in
            connectionChanges.append(state)
        }
        
        // When - Test connectivity resilience
        mockManager.startConnectivity()
        
        let mockRound = createMockGolfRound()
        _ = await mockManager.startGolfRound(mockRound)
        
        // Simulate connection issues
        mockManager.simulateConnectionLoss()
        
        // Try to send data during disconnection
        let success1 = await mockManager.sendHighPriorityMessage(
            type: .scorecardUpdate,
            data: ["test": "data"],
            requiresAck: true
        )
        
        // Restore connection
        mockManager.simulateConnectionRestore()
        
        // Send data after restoration
        let success2 = await mockManager.sendHighPriorityMessage(
            type: .scorecardUpdate,
            data: ["test": "data"],
            requiresAck: true
        )
        
        // Then
        XCTAssertGreaterThan(connectionChanges.count, 0)
        XCTAssertTrue(connectionChanges.contains(.disconnected))
        XCTAssertTrue(connectionChanges.contains(.connected))
        XCTAssertTrue(success1) // Mock should handle gracefully
        XCTAssertTrue(success2)
    }
}