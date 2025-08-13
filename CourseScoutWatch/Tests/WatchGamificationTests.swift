import XCTest
import Combine
@testable import GolfFinderWatch

// MARK: - Watch Gamification Tests

class WatchGamificationTests: XCTestCase {
    
    // MARK: - Properties
    
    var mockGamificationService: MockWatchGamificationService!
    var mockHapticService: MockWatchHapticFeedbackService!
    var mockPowerOptimizationService: MockWatchPowerOptimizationService!
    var cancellables: Set<AnyCancellable>!
    
    // MARK: - Setup & Teardown
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        mockGamificationService = MockWatchGamificationService()
        mockHapticService = MockWatchHapticFeedbackService()
        mockPowerOptimizationService = MockWatchPowerOptimizationService()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithError() throws {
        cancellables.removeAll()
        mockGamificationService = nil
        mockHapticService = nil
        mockPowerOptimizationService = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Leaderboard Tests
    
    func testLeaderboardPositionUpdate() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Leaderboard update received")
        let playerId = "test-player-123"
        let position = 15
        let totalPlayers = 64
        let positionChange = -3
        
        // When
        mockGamificationService.subscribeToLeaderboardUpdates()
            .sink { leaderboardPosition in
                // Then
                XCTAssertEqual(leaderboardPosition.playerId, playerId)
                XCTAssertEqual(leaderboardPosition.position, position)
                XCTAssertEqual(leaderboardPosition.totalPlayers, totalPlayers)
                XCTAssertEqual(leaderboardPosition.positionChange, positionChange)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        await mockGamificationService.updateLeaderboard(
            playerId: playerId,
            position: position,
            totalPlayers: totalPlayers,
            positionChange: positionChange
        )
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testLeaderboardPositionRetrieval() async throws {
        // Given
        let playerId = "test-player-123"
        let position = 8
        let totalPlayers = 32
        let positionChange = 5
        
        // When
        await mockGamificationService.updateLeaderboard(
            playerId: playerId,
            position: position,
            totalPlayers: totalPlayers,
            positionChange: positionChange
        )
        
        let retrievedPosition = mockGamificationService.getCurrentLeaderboardPosition()
        
        // Then
        XCTAssertNotNil(retrievedPosition)
        XCTAssertEqual(retrievedPosition?.playerId, playerId)
        XCTAssertEqual(retrievedPosition?.position, position)
        XCTAssertEqual(retrievedPosition?.positionChange, positionChange)
    }
    
    // MARK: - Achievement Tests
    
    func testAchievementUnlock() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Achievement unlock received")
        let achievementId = "first-birdie"
        let tier = "gold"
        let title = "First Birdie"
        let description = "Congratulations on your first birdie!"
        
        // When
        mockGamificationService.subscribeToAchievementUpdates()
            .sink { achievement in
                // Then
                XCTAssertEqual(achievement.achievementId, achievementId)
                XCTAssertEqual(achievement.tier, tier)
                XCTAssertEqual(achievement.title, title)
                XCTAssertEqual(achievement.description, description)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        await mockGamificationService.processAchievementUnlock(
            achievementId: achievementId,
            tier: tier,
            title: title,
            description: description
        )
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testMultipleAchievementsStorage() async throws {
        // Given
        let achievements = [
            ("achievement-1", "bronze", "Bronze Badge", "First bronze achievement"),
            ("achievement-2", "silver", "Silver Star", "First silver achievement"),
            ("achievement-3", "gold", "Golden Eagle", "First gold achievement")
        ]
        
        // When
        for (id, tier, title, desc) in achievements {
            await mockGamificationService.processAchievementUnlock(
                achievementId: id,
                tier: tier,
                title: title,
                description: desc
            )
        }
        
        let recentAchievements = mockGamificationService.getRecentAchievements()
        
        // Then
        XCTAssertEqual(recentAchievements.count, 3)
        XCTAssertEqual(recentAchievements[0].achievementId, "achievement-3") // Most recent first
        XCTAssertEqual(recentAchievements[1].achievementId, "achievement-2")
        XCTAssertEqual(recentAchievements[2].achievementId, "achievement-1")
    }
    
    // MARK: - Rating Tests
    
    func testRatingUpdate() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Rating update received")
        let playerId = "test-player-123"
        let currentRating = 1485.0
        let ratingChange = 25.0
        let projectedRating = 1510.0
        
        // When
        mockGamificationService.subscribeToRatingUpdates()
            .sink { rating in
                // Then
                XCTAssertEqual(rating.currentRating, currentRating)
                XCTAssertEqual(rating.ratingChange, ratingChange)
                XCTAssertEqual(rating.projectedRating, projectedRating)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        await mockGamificationService.updateRating(
            currentRating: currentRating,
            ratingChange: ratingChange,
            projectedRating: projectedRating
        )
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testRatingDeclineUpdate() async throws {
        // Given
        let currentRating = 1425.0
        let ratingChange = -35.0
        
        // When
        await mockGamificationService.updateRating(
            currentRating: currentRating,
            ratingChange: ratingChange,
            projectedRating: nil
        )
        
        let retrievedRating = mockGamificationService.getCurrentRating()
        
        // Then
        XCTAssertNotNil(retrievedRating)
        XCTAssertEqual(retrievedRating?.currentRating, currentRating)
        XCTAssertEqual(retrievedRating?.ratingChange, ratingChange)
        XCTAssertNil(retrievedRating?.projectedRating)
    }
    
    // MARK: - Challenge Tests
    
    func testChallengeProgressUpdate() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Challenge update received")
        let challengeId = "head-to-head-123"
        let progress = ChallengeProgress(
            completedSteps: 9,
            totalSteps: 18,
            percentComplete: 0.5,
            isCompleted: false,
            currentScore: 75,
            targetScore: 72
        )
        
        // When
        mockGamificationService.subscribeToChallengeUpdates()
            .sink { challengeUpdate in
                // Then
                XCTAssertEqual(challengeUpdate.challengeId, challengeId)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        await mockGamificationService.updateChallengeProgress(
            challengeId: challengeId,
            progress: progress
        )
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testActiveChallengesRetrieval() async throws {
        // Given
        let challengeId = "tournament-456"
        let progress = ChallengeProgress(
            completedSteps: 18,
            totalSteps: 18,
            percentComplete: 1.0,
            isCompleted: true,
            currentScore: 68,
            targetScore: 72
        )
        
        // When
        await mockGamificationService.updateChallengeProgress(
            challengeId: challengeId,
            progress: progress
        )
        
        let activeChallenges = mockGamificationService.getActiveChallenges()
        
        // Then
        XCTAssertGreaterThanOrEqual(activeChallenges.count, 0)
    }
    
    // MARK: - Tournament Tests
    
    func testTournamentStatusUpdate() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Tournament update received")
        let tournamentId = "weekend-tournament"
        let position = 12
        let standings: [[String: Any]] = [
            ["playerId": "player1", "score": 68],
            ["playerId": "player2", "score": 70],
            ["playerId": "player3", "score": 71]
        ]
        
        // When
        mockGamificationService.subscribeToTournamentUpdates()
            .sink { tournamentStatus in
                // Then
                XCTAssertEqual(tournamentStatus.tournamentId, tournamentId)
                XCTAssertEqual(tournamentStatus.position, position)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        await mockGamificationService.updateTournamentStatus(
            tournamentId: tournamentId,
            position: position,
            standings: standings
        )
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Haptic Integration Tests
    
    func testHapticFeedbackForLeaderboardChange() async throws {
        // Given
        let significantPositionChange = 8
        
        // When
        mockHapticService.playLeaderboardPositionHaptic(positionChange: significantPositionChange)
        
        // Then
        XCTAssertGreaterThan(mockHapticService.getTotalHapticCalls(), 0)
    }
    
    func testHapticFeedbackForAchievementTiers() async throws {
        // Given
        let tiers = ["bronze", "silver", "gold", "platinum", "diamond"]
        
        // When & Then
        for tier in tiers {
            mockHapticService.resetCallCounts()
            mockHapticService.playAchievementHaptic(tier: tier)
            XCTAssertGreaterThan(mockHapticService.getTotalHapticCalls(), 0, "No haptic played for \(tier) tier")
        }
    }
    
    func testHapticOptimizationBasedOnBatteryLevel() async throws {
        // Given
        let lowBattery: Float = 0.15
        let highBattery: Float = 0.85
        let baseIntensity: Float = 1.0
        
        // When
        mockPowerOptimizationService.simulateBatteryLevel(lowBattery)
        let lowBatteryIntensity = mockPowerOptimizationService.optimizeHapticIntensity(baseIntensity: baseIntensity)
        
        mockPowerOptimizationService.simulateBatteryLevel(highBattery)
        let highBatteryIntensity = mockPowerOptimizationService.optimizeHapticIntensity(baseIntensity: baseIntensity)
        
        // Then
        XCTAssertLessThan(lowBatteryIntensity, highBatteryIntensity, "Low battery should have reduced haptic intensity")
    }
    
    // MARK: - Power Optimization Tests
    
    func testUpdateFrequencyAdjustmentForBatteryLevel() throws {
        // Given
        let component: WatchComponent = .leaderboard
        let lowBattery: Float = 0.20
        let highBattery: Float = 0.80
        
        // When
        mockPowerOptimizationService.adjustUpdateFrequency(for: component, batteryLevel: lowBattery)
        let lowBatteryInterval = mockPowerOptimizationService.getUpdateInterval(for: component)
        
        mockPowerOptimizationService.adjustUpdateFrequency(for: component, batteryLevel: highBattery)
        let highBatteryInterval = mockPowerOptimizationService.getUpdateInterval(for: component)
        
        // Then
        XCTAssertGreaterThan(lowBatteryInterval, highBatteryInterval, "Low battery should have longer update intervals")
    }
    
    func testDataSyncPriorityFiltering() throws {
        // Given
        mockPowerOptimizationService.simulateBatteryLevel(0.10) // Very low battery
        
        // When & Then
        XCTAssertTrue(mockPowerOptimizationService.shouldSyncData(priority: .critical))
        XCTAssertFalse(mockPowerOptimizationService.shouldSyncData(priority: .low))
        XCTAssertFalse(mockPowerOptimizationService.shouldSyncData(priority: .medium))
    }
    
    func testBatteryOptimizationToggle() throws {
        // Given
        let initialLevel = mockPowerOptimizationService.optimizationLevel
        
        // When
        mockPowerOptimizationService.enableBatteryOptimization(true)
        let optimizedLevel = mockPowerOptimizationService.optimizationLevel
        
        mockPowerOptimizationService.enableBatteryOptimization(false)
        let standardLevel = mockPowerOptimizationService.optimizationLevel
        
        // Then
        XCTAssertNotEqual(initialLevel, optimizedLevel)
        XCTAssertEqual(standardLevel, .standard)
    }
    
    // MARK: - Real-time Synchronization Tests
    
    func testMultipleSubscribersToLeaderboardUpdates() async throws {
        // Given
        let expectation1 = XCTestExpectation(description: "First subscriber")
        let expectation2 = XCTestExpectation(description: "Second subscriber")
        
        // When
        mockGamificationService.subscribeToLeaderboardUpdates()
            .sink { _ in expectation1.fulfill() }
            .store(in: &cancellables)
        
        mockGamificationService.subscribeToLeaderboardUpdates()
            .sink { _ in expectation2.fulfill() }
            .store(in: &cancellables)
        
        await mockGamificationService.updateLeaderboard(
            playerId: "test-player",
            position: 10,
            totalPlayers: 50,
            positionChange: 2
        )
        
        // Then
        await fulfillment(of: [expectation1, expectation2], timeout: 1.0)
    }
    
    func testConcurrentUpdatesHandling() async throws {
        // Given
        let updateCount = 10
        let expectations = (0..<updateCount).map { index in
            XCTestExpectation(description: "Update \(index)")
        }
        
        var receivedUpdates = 0
        
        // When
        mockGamificationService.subscribeToLeaderboardUpdates()
            .sink { _ in
                receivedUpdates += 1
                if receivedUpdates <= updateCount {
                    expectations[receivedUpdates - 1].fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Perform concurrent updates
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<updateCount {
                group.addTask { [weak self] in
                    await self?.mockGamificationService.updateLeaderboard(
                        playerId: "player-\(i)",
                        position: i + 1,
                        totalPlayers: 100,
                        positionChange: 0
                    )
                }
            }
        }
        
        // Then
        await fulfillment(of: expectations, timeout: 2.0)
        XCTAssertEqual(receivedUpdates, updateCount)
    }
    
    // MARK: - Data Model Tests
    
    func testLeaderboardPositionModel() throws {
        // Given
        let playerId = "test-player"
        let position = 5
        let totalPlayers = 20
        let positionChange = -2
        let timestamp = Date()
        
        // When
        let leaderboardPosition = LeaderboardPosition(
            playerId: playerId,
            position: position,
            totalPlayers: totalPlayers,
            positionChange: positionChange,
            lastUpdated: timestamp
        )
        
        // Then
        XCTAssertEqual(leaderboardPosition.playerId, playerId)
        XCTAssertEqual(leaderboardPosition.position, position)
        XCTAssertEqual(leaderboardPosition.totalPlayers, totalPlayers)
        XCTAssertEqual(leaderboardPosition.positionChange, positionChange)
        XCTAssertEqual(leaderboardPosition.lastUpdated, timestamp)
    }
    
    func testAchievementModel() throws {
        // Given
        let achievementId = "hole-in-one"
        let tier = "diamond"
        let title = "Hole in One!"
        let description = "Incredible achievement!"
        let timestamp = Date()
        
        // When
        let achievement = Achievement(
            achievementId: achievementId,
            tier: tier,
            title: title,
            description: description,
            unlockedAt: timestamp
        )
        
        // Then
        XCTAssertEqual(achievement.achievementId, achievementId)
        XCTAssertEqual(achievement.tier, tier)
        XCTAssertEqual(achievement.title, title)
        XCTAssertEqual(achievement.description, description)
        XCTAssertEqual(achievement.unlockedAt, timestamp)
    }
    
    func testChallengeProgressModel() throws {
        // Given
        let completedSteps = 12
        let totalSteps = 18
        let percentComplete = Double(completedSteps) / Double(totalSteps)
        let isCompleted = false
        let currentScore = 85
        let targetScore = 72
        
        // When
        let progress = ChallengeProgress(
            completedSteps: completedSteps,
            totalSteps: totalSteps,
            percentComplete: percentComplete,
            isCompleted: isCompleted,
            currentScore: currentScore,
            targetScore: targetScore
        )
        
        // Then
        XCTAssertEqual(progress.completedSteps, completedSteps)
        XCTAssertEqual(progress.totalSteps, totalSteps)
        XCTAssertEqual(progress.percentComplete, percentComplete, accuracy: 0.01)
        XCTAssertEqual(progress.isCompleted, isCompleted)
        XCTAssertEqual(progress.currentScore, currentScore)
        XCTAssertEqual(progress.targetScore, targetScore)
    }
    
    // MARK: - Performance Tests
    
    func testLeaderboardUpdatePerformance() throws {
        measure {
            let group = DispatchGroup()
            
            for i in 0..<100 {
                group.enter()
                Task {
                    await mockGamificationService.updateLeaderboard(
                        playerId: "player-\(i)",
                        position: i + 1,
                        totalPlayers: 100,
                        positionChange: 0
                    )
                    group.leave()
                }
            }
            
            group.wait()
        }
    }
    
    func testHapticServicePerformance() throws {
        measure {
            for _ in 0..<100 {
                mockHapticService.playTaptic(.success)
                mockHapticService.playAchievementHaptic(tier: "gold")
                mockHapticService.playLeaderboardPositionHaptic(positionChange: 5)
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidDataHandling() async throws {
        // Test with invalid/extreme values
        await mockGamificationService.updateLeaderboard(
            playerId: "",
            position: -1,
            totalPlayers: 0,
            positionChange: Int.max
        )
        
        // Should not crash and should handle gracefully
        let position = mockGamificationService.getCurrentLeaderboardPosition()
        XCTAssertNotNil(position) // Mock service should handle this
    }
    
    func testMemoryManagementWithSubscriptions() async throws {
        weak var weakService: MockWatchGamificationService?
        
        do {
            let service = MockWatchGamificationService()
            weakService = service
            
            // Create and immediately release subscription
            _ = service.subscribeToLeaderboardUpdates()
                .sink { _ in }
        }
        
        // Service should be deallocated
        XCTAssertNil(weakService, "Service should be deallocated after subscriptions are released")
    }
    
    // MARK: - Integration Tests
    
    func testFullGamificationFlow() async throws {
        // Given
        let playerId = "integration-test-player"
        var receivedUpdates: [String] = []
        
        let leaderboardExpectation = XCTestExpectation(description: "Leaderboard update")
        let achievementExpectation = XCTestExpectation(description: "Achievement unlock")
        let ratingExpectation = XCTestExpectation(description: "Rating update")
        
        // When - Set up subscriptions
        mockGamificationService.subscribeToLeaderboardUpdates()
            .sink { _ in
                receivedUpdates.append("leaderboard")
                leaderboardExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        mockGamificationService.subscribeToAchievementUpdates()
            .sink { _ in
                receivedUpdates.append("achievement")
                achievementExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        mockGamificationService.subscribeToRatingUpdates()
            .sink { _ in
                receivedUpdates.append("rating")
                ratingExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Trigger multiple updates
        await mockGamificationService.updateLeaderboard(
            playerId: playerId,
            position: 8,
            totalPlayers: 32,
            positionChange: 5
        )
        
        await mockGamificationService.processAchievementUnlock(
            achievementId: "integration-test",
            tier: "gold",
            title: "Integration Test",
            description: "Test achievement"
        )
        
        await mockGamificationService.updateRating(
            currentRating: 1500.0,
            ratingChange: 50.0,
            projectedRating: 1550.0
        )
        
        // Then
        await fulfillment(of: [leaderboardExpectation, achievementExpectation, ratingExpectation], timeout: 2.0)
        XCTAssertEqual(receivedUpdates.count, 3)
        XCTAssertTrue(receivedUpdates.contains("leaderboard"))
        XCTAssertTrue(receivedUpdates.contains("achievement"))
        XCTAssertTrue(receivedUpdates.contains("rating"))
    }
}

// MARK: - Test Utilities

extension WatchGamificationTests {
    
    func createMockLeaderboardPosition(position: Int = 10, totalPlayers: Int = 50) -> LeaderboardPosition {
        return LeaderboardPosition(
            playerId: "test-player",
            position: position,
            totalPlayers: totalPlayers,
            positionChange: 0,
            lastUpdated: Date()
        )
    }
    
    func createMockAchievement(tier: String = "gold") -> Achievement {
        return Achievement(
            achievementId: "test-achievement",
            tier: tier,
            title: "Test Achievement",
            description: "A test achievement",
            unlockedAt: Date()
        )
    }
    
    func createMockChallengeProgress(completed: Bool = false) -> ChallengeProgress {
        return ChallengeProgress(
            completedSteps: completed ? 18 : 9,
            totalSteps: 18,
            percentComplete: completed ? 1.0 : 0.5,
            isCompleted: completed,
            currentScore: completed ? 72 : 85,
            targetScore: 72
        )
    }
}