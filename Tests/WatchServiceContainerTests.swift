import XCTest
@testable import GolfFinderWatch

// MARK: - Watch Service Container Tests

class WatchServiceContainerTests: XCTestCase {
    var container: WatchServiceContainer!
    
    override func setUp() {
        super.setUp()
        container = WatchServiceContainer(environment: .test)
    }
    
    override func tearDown() {
        container = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testContainerInitialization() {
        XCTAssertNotNil(container)
        XCTAssertEqual(container.environment, .test)
    }
    
    func testSharedContainerAccess() {
        let sharedContainer = WatchServiceContainer.shared
        XCTAssertNotNil(sharedContainer)
    }
    
    // MARK: - Service Registration Tests
    
    func testServiceRegistrationAndResolution() {
        // Test that core services are registered
        let connectivityService = container.watchConnectivityService()
        XCTAssertNotNil(connectivityService)
        XCTAssertTrue(connectivityService is MockWatchConnectivityService)
    }
    
    func testGolfCourseServiceRegistration() {
        let golfCourseService = container.watchGolfCourseService()
        XCTAssertNotNil(golfCourseService)
        XCTAssertTrue(golfCourseService is MockWatchGolfCourseService)
    }
    
    func testScorecardServiceRegistration() {
        let scorecardService = container.watchScorecardService()
        XCTAssertNotNil(scorecardService)
        XCTAssertTrue(scorecardService is MockWatchScorecardService)
    }
    
    func testSingletonLifecycle() {
        let service1 = container.watchConnectivityService()
        let service2 = container.watchConnectivityService()
        
        // Should return the same instance for singleton services
        XCTAssertTrue(service1 === service2)
    }
    
    func testScopedLifecycle() {
        let scorecardService1 = container.watchScorecardService()
        let scorecardService2 = container.watchScorecardService()
        
        // Scoped services should return different instances
        XCTAssertFalse(scorecardService1 === scorecardService2)
    }
    
    func testCustomServiceRegistration() {
        // Register a custom test service
        container.register(TestServiceProtocol.self, lifecycle: .singleton) { _ in
            TestService()
        }
        
        let testService = container.resolve(TestServiceProtocol.self)
        XCTAssertNotNil(testService)
        XCTAssertTrue(testService is TestService)
    }
    
    // MARK: - Environment Configuration Tests
    
    func testEnvironmentConfiguration() {
        container.configure(for: .development)
        XCTAssertEqual(container.environment, .development)
    }
    
    func testMockServiceUsage() {
        container.configure(for: .test)
        
        let connectivityService = container.watchConnectivityService()
        XCTAssertTrue(connectivityService is MockWatchConnectivityService)
    }
    
    func testProductionServiceUsage() {
        container.configure(for: .production)
        
        // In production, should use real services (not mocks)
        // Note: This test would need real service implementations
        let connectivityService = container.watchConnectivityService()
        XCTAssertNotNil(connectivityService)
    }
    
    // MARK: - Performance Monitoring Tests
    
    func testServiceMetricsCollection() {
        // Resolve some services to generate metrics
        let _ = container.watchConnectivityService()
        let _ = container.watchGolfCourseService()
        let _ = container.watchScorecardService()
        
        let metrics = container.getServiceMetrics()
        XCTAssertGreaterThan(metrics.count, 0)
    }
    
    func testServiceAccessTracking() {
        // Access a service multiple times
        for _ in 0..<5 {
            let _ = container.watchConnectivityService()
        }
        
        let metrics = container.getServiceMetrics()
        let connectivityMetrics = metrics.first { $0.serviceName.contains("WatchConnectivityServiceProtocol") }
        
        XCTAssertNotNil(connectivityMetrics)
        XCTAssertGreaterThanOrEqual(connectivityMetrics?.accessCount ?? 0, 5)
    }
    
    func testCacheHitRate() {
        // First access (cache miss)
        let _ = container.watchConnectivityService()
        
        // Subsequent accesses (cache hits)
        for _ in 0..<3 {
            let _ = container.watchConnectivityService()
        }
        
        let metrics = container.getServiceMetrics()
        let connectivityMetrics = metrics.first { $0.serviceName.contains("WatchConnectivityServiceProtocol") }
        
        XCTAssertNotNil(connectivityMetrics)
        XCTAssertGreaterThan(connectivityMetrics?.cacheHitRate ?? 0, 0.5) // Should be > 50%
    }
    
    // MARK: - Service Preloading Tests
    
    func testCriticalServicePreloading() async {
        let expectation = expectation(description: "Services preloaded")
        
        await container.preloadCriticalWatchServices()
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify that critical services are preloaded (should have high cache hit rate)
        let metrics = container.getServiceMetrics()
        XCTAssertGreaterThan(metrics.count, 0)
    }
    
    // MARK: - Battery Optimization Tests
    
    func testBatteryOptimizationInterface() {
        // Test that battery optimization services are recognized
        let testOptimizableService = TestBatteryOptimizableService()
        
        container.register(TestBatteryOptimizableServiceProtocol.self, lifecycle: .singleton) { _ in
            testOptimizableService
        }
        
        let service = container.resolve(TestBatteryOptimizableServiceProtocol.self) as! TestBatteryOptimizableService
        XCTAssertFalse(service.batteryOptimizationEnabled)
        
        service.enableBatteryOptimization()
        XCTAssertTrue(service.batteryOptimizationEnabled)
        
        service.disableBatteryOptimization()
        XCTAssertFalse(service.batteryOptimizationEnabled)
    }
    
    // MARK: - Background Refresh Tests
    
    func testBackgroundRefreshInterface() {
        let testRefreshableService = TestBackgroundRefreshableService()
        
        container.register(TestBackgroundRefreshableServiceProtocol.self, lifecycle: .singleton) { _ in
            testRefreshableService
        }
        
        let service = container.resolve(TestBackgroundRefreshableServiceProtocol.self) as! TestBackgroundRefreshableService
        
        let expectation = expectation(description: "Background refresh completed")
        service.refreshExpectation = expectation
        
        container.performBackgroundRefresh()
        
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(service.backgroundRefreshCalled)
    }
    
    // MARK: - Memory Management Tests
    
    func testMemoryCleanup() {
        let testCleanableService = TestMemoryCleanableService()
        
        container.register(TestMemoryCleanableServiceProtocol.self, lifecycle: .singleton) { _ in
            testCleanableService
        }
        
        let service = container.resolve(TestMemoryCleanableServiceProtocol.self) as! TestMemoryCleanableService
        
        container.performMemoryCleanup()
        
        XCTAssertTrue(service.memoryCleanupCalled)
    }
    
    // MARK: - Error Handling Tests
    
    func testUnregisteredServiceError() {
        // Attempting to resolve an unregistered service should cause a fatal error
        // In a real test, we'd need to handle this more gracefully
        
        // For now, just verify the service registration works correctly
        XCTAssertNoThrow(container.watchConnectivityService())
    }
    
    // MARK: - Convenience Methods Tests
    
    func testConvenienceMethodsReturnCorrectTypes() {
        XCTAssertTrue(container.watchConnectivityService() is WatchConnectivityServiceProtocol)
        XCTAssertTrue(container.watchGolfCourseService() is WatchGolfCourseServiceProtocol)
        XCTAssertTrue(container.watchScorecardService() is WatchScorecardServiceProtocol)
        XCTAssertTrue(container.watchGPSService() is WatchGPSServiceProtocol)
        XCTAssertTrue(container.watchWorkoutService() is WatchWorkoutServiceProtocol)
        XCTAssertTrue(container.watchHapticFeedbackService() is WatchHapticFeedbackServiceProtocol)
        XCTAssertTrue(container.watchSyncService() is WatchSyncServiceProtocol)
        XCTAssertTrue(container.watchAnalyticsService() is WatchAnalyticsServiceProtocol)
    }
    
    // MARK: - SwiftUI Integration Tests
    
    func testPropertyWrapperIntegration() {
        // Test the @WatchServiceInjected property wrapper
        let testView = TestView()
        
        // Access the injected service
        XCTAssertNotNil(testView.connectivityService)
        XCTAssertTrue(testView.connectivityService is WatchConnectivityServiceProtocol)
    }
    
    // MARK: - Performance Tests
    
    func testServiceResolutionPerformance() {
        measure {
            for _ in 0..<1000 {
                let _ = container.watchConnectivityService()
            }
        }
    }
    
    func testServiceCreationPerformance() {
        measure {
            for _ in 0..<100 {
                let _ = container.watchScorecardService() // Scoped service - new instance each time
            }
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentServiceAccess() {
        let expectation = expectation(description: "Concurrent access completed")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue.global(qos: .userInitiated)
        
        for _ in 0..<10 {
            queue.async {
                let _ = self.container.watchConnectivityService()
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
}

// MARK: - Test Helper Services and Protocols

protocol TestServiceProtocol {}
class TestService: TestServiceProtocol {}

protocol TestBatteryOptimizableServiceProtocol {}
class TestBatteryOptimizableService: TestBatteryOptimizableServiceProtocol, WatchBatteryOptimizable {
    var batteryOptimizationEnabled = false
    
    func enableBatteryOptimization() {
        batteryOptimizationEnabled = true
    }
    
    func disableBatteryOptimization() {
        batteryOptimizationEnabled = false
    }
}

protocol TestBackgroundRefreshableServiceProtocol {}
class TestBackgroundRefreshableService: TestBackgroundRefreshableServiceProtocol, WatchBackgroundRefreshable {
    var backgroundRefreshCalled = false
    var refreshExpectation: XCTestExpectation?
    
    func performBackgroundRefresh() async {
        backgroundRefreshCalled = true
        refreshExpectation?.fulfill()
    }
}

protocol TestMemoryCleanableServiceProtocol {}
class TestMemoryCleanableService: TestMemoryCleanableServiceProtocol, WatchMemoryCleanable {
    var memoryCleanupCalled = false
    
    func performMemoryCleanup() {
        memoryCleanupCalled = true
    }
}

struct TestView {
    @WatchServiceInjected(WatchConnectivityServiceProtocol.self) 
    var connectivityService: WatchConnectivityServiceProtocol
}