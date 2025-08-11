import Foundation
import Combine
import CoreLocation

// MARK: - Watch Connectivity Manager Protocol

protocol WatchConnectivityManagerProtocol: AnyObject {
    // Published state
    var isWatchPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var isWatchReachable: Bool { get }
    var connectionState: WatchConnectionState { get }
    var syncState: WatchSyncState { get }
    var lastSyncTime: Date? { get }
    var batteryInfo: WatchBatteryInfo? { get }
    
    // Golf round management
    func startGolfRound(_ round: ActiveGolfRound) async -> Bool
    func updateScorecard(_ scorecard: SharedScorecard) async
    func endGolfRound() async -> Bool
    
    // Message sending
    func sendHighPriorityMessage(type: MessageType, data: [String: Any], requiresAck: Bool) async -> Bool
    func sendNormalPriorityMessage(type: MessageType, data: [String: Any]) async
    
    // Battery optimization
    func enableBatteryOptimization(_ enabled: Bool)
    
    // Health data
    func syncHealthMetrics(_ metrics: WatchHealthMetrics)
    
    // Haptic feedback
    func sendHapticFeedback(_ type: WatchHapticType, context: HapticContext?)
    func celebrateMilestone(_ milestone: GolfMilestone)
    
    // Connectivity management
    func startConnectivity()
    func stopConnectivity()
    
    // Delegate management
    func addDelegate(_ delegate: WatchConnectivityDelegate)
    func removeDelegate(_ delegate: WatchConnectivityDelegate)
}

// MARK: - Watch Connectivity Delegate

protocol WatchConnectivityDelegate: AnyObject {
    func watchConnectivityManager(_ manager: WatchConnectivityManagerProtocol, didChangeConnectionState state: WatchConnectionState)
    func watchConnectivityManager(_ manager: WatchConnectivityManagerProtocol, didReceiveHealthMetrics metrics: WatchHealthMetrics)
    func watchConnectivityManager(_ manager: WatchConnectivityManagerProtocol, didUpdateScorecard scorecard: SharedScorecard)
    func watchConnectivityManager(_ manager: WatchConnectivityManagerProtocol, didReceiveBatteryInfo info: WatchBatteryInfo)
}

// MARK: - Mock Watch Connectivity Manager

@MainActor
class MockWatchConnectivityManager: ObservableObject, WatchConnectivityManagerProtocol {
    
    // MARK: - Published State
    
    @Published var isWatchPaired: Bool = true
    @Published var isWatchAppInstalled: Bool = true
    @Published var isWatchReachable: Bool = true
    @Published var connectionState: WatchConnectionState = .connected
    @Published var syncState: WatchSyncState = .idle
    @Published var lastSyncTime: Date? = Date()
    @Published var batteryInfo: WatchBatteryInfo? = WatchBatteryInfo(
        level: 85.0,
        state: .unplugged,
        isLowPowerMode: false,
        estimatedTimeRemaining: 8 * 3600 // 8 hours
    )
    
    // Private properties
    private var delegates = NSHashTable<AnyObject>.weakObjects()
    private var mockActiveRound: ActiveGolfRound?
    private var mockScorecard: SharedScorecard?
    
    // MARK: - Golf Round Management
    
    func startGolfRound(_ round: ActiveGolfRound) async -> Bool {
        print("🟢 Mock: Starting golf round - \(round.courseName)")
        
        mockActiveRound = round
        syncState = .syncing
        
        // Simulate sync delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        syncState = .completed
        lastSyncTime = Date()
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.watchConnectivityManager(self, didChangeConnectionState: .connected)
        }
        
        return true
    }
    
    func updateScorecard(_ scorecard: SharedScorecard) async {
        print("🟡 Mock: Updating scorecard - Total Score: \(scorecard.totalScore)")
        
        mockScorecard = scorecard
        syncState = .syncing
        
        // Simulate sync delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        syncState = .completed
        lastSyncTime = Date()
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.watchConnectivityManager(self, didUpdateScorecard: scorecard)
        }
    }
    
    func endGolfRound() async -> Bool {
        print("🔴 Mock: Ending golf round")
        
        syncState = .syncing
        
        // Simulate final sync
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        mockActiveRound = nil
        mockScorecard = nil
        syncState = .completed
        lastSyncTime = Date()
        
        return true
    }
    
    // MARK: - Message Sending
    
    func sendHighPriorityMessage(type: MessageType, data: [String: Any], requiresAck: Bool) async -> Bool {
        print("⚡ Mock: Sending high priority message - Type: \(type.rawValue)")
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        return true
    }
    
    func sendNormalPriorityMessage(type: MessageType, data: [String: Any]) async {
        print("📤 Mock: Sending normal priority message - Type: \(type.rawValue)")
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
    
    // MARK: - Battery Optimization
    
    func enableBatteryOptimization(_ enabled: Bool) {
        print("🔋 Mock: Battery optimization \(enabled ? "enabled" : "disabled")")
        
        // Simulate battery impact
        if enabled {
            // Reduce mock update frequency
        }
    }
    
    // MARK: - Health Data
    
    func syncHealthMetrics(_ metrics: WatchHealthMetrics) {
        print("❤️ Mock: Syncing health metrics - HR: \(metrics.currentHeartRate)")
        
        // Simulate processing health data
        let mockMetrics = WatchHealthMetrics(from: [
            "heartRate": metrics.heartRate,
            "averageHeartRate": metrics.averageHeartRate,
            "caloriesBurned": metrics.caloriesBurned,
            "stepCount": metrics.stepCount,
            "distanceWalked": metrics.distanceWalked,
            "currentHeartRate": metrics.currentHeartRate,
            "heartRateZone": metrics.heartRateZone.rawValue
        ])
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.watchConnectivityManager(self, didReceiveHealthMetrics: mockMetrics)
        }
    }
    
    // MARK: - Haptic Feedback
    
    func sendHapticFeedback(_ type: WatchHapticType, context: HapticContext? = nil) {
        print("📳 Mock: Sending haptic feedback - Type: \(type.rawValue)")
        
        // Simulate haptic feedback delivery
    }
    
    func celebrateMilestone(_ milestone: GolfMilestone) {
        print("🎉 Mock: Celebrating milestone - \(milestone.title)")
        
        // Send haptic and visual celebration
        sendHapticFeedback(.success, context: HapticContext(pattern: milestone.hapticPattern))
    }
    
    // MARK: - Connectivity Management
    
    func startConnectivity() {
        print("🚀 Mock: Starting watch connectivity")
        
        connectionState = .connected
        isWatchReachable = true
        
        // Start simulating periodic updates
        startMockUpdates()
    }
    
    func stopConnectivity() {
        print("🛑 Mock: Stopping watch connectivity")
        
        connectionState = .disconnected
        isWatchReachable = false
        
        // Stop mock updates
        stopMockUpdates()
    }
    
    // MARK: - Delegate Management
    
    func addDelegate(_ delegate: WatchConnectivityDelegate) {
        delegates.add(delegate)
        print("👥 Mock: Added watch connectivity delegate")
    }
    
    func removeDelegate(_ delegate: WatchConnectivityDelegate) {
        delegates.remove(delegate)
        print("👥 Mock: Removed watch connectivity delegate")
    }
    
    // MARK: - Mock Simulation
    
    private var mockTimer: Timer?
    
    private func startMockUpdates() {
        mockTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.simulateMockUpdates()
        }
    }
    
    private func stopMockUpdates() {
        mockTimer?.invalidate()
        mockTimer = nil
    }
    
    private func simulateMockUpdates() {
        // Simulate battery level changes
        if var battery = batteryInfo {
            battery = WatchBatteryInfo(
                level: max(20.0, battery.level - Float.random(in: 0...2)),
                state: battery.state,
                isLowPowerMode: battery.level < 20,
                estimatedTimeRemaining: battery.estimatedTimeRemaining
            )
            batteryInfo = battery
            
            // Notify delegates of battery changes
            notifyDelegates { delegate in
                delegate.watchConnectivityManager(self, didReceiveBatteryInfo: battery)
            }
        }
        
        // Simulate health metrics if round is active
        if mockActiveRound != nil {
            simulateHealthMetricsUpdate()
        }
        
        // Occasionally simulate connectivity changes
        if Bool.random() && Float.random(in: 0...1) < 0.1 { // 10% chance
            connectionState = isWatchReachable ? .paired : .connected
            isWatchReachable.toggle()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.connectionState = .connected
                self.isWatchReachable = true
            }
        }
    }
    
    private func simulateHealthMetricsUpdate() {
        let mockMetrics = WatchHealthMetrics(from: [
            "heartRate": Double.random(in: 70...140),
            "averageHeartRate": 95.0,
            "caloriesBurned": Double.random(in: 200...800),
            "stepCount": Int.random(in: 5000...15000),
            "distanceWalked": Double.random(in: 3000...8000),
            "currentHeartRate": Double.random(in: 80...120),
            "heartRateZone": "moderate"
        ])
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.watchConnectivityManager(self, didReceiveHealthMetrics: mockMetrics)
        }
    }
    
    private func notifyDelegates(block: (WatchConnectivityDelegate) -> Void) {
        delegates.allObjects.compactMap { $0 as? WatchConnectivityDelegate }.forEach(block)
    }
    
    // MARK: - Mock Configuration
    
    func simulateConnectionLoss() {
        connectionState = .disconnected
        isWatchReachable = false
        
        print("📡 Mock: Simulated connection loss")
    }
    
    func simulateConnectionRestore() {
        connectionState = .connected
        isWatchReachable = true
        
        print("📡 Mock: Simulated connection restore")
    }
    
    func simulateLowBattery() {
        batteryInfo = WatchBatteryInfo(
            level: 15.0,
            state: .unplugged,
            isLowPowerMode: true,
            estimatedTimeRemaining: 1.5 * 3600 // 1.5 hours
        )
        
        print("🔋 Mock: Simulated low battery")
    }
    
    func simulateCriticalBattery() {
        batteryInfo = WatchBatteryInfo(
            level: 5.0,
            state: .unplugged,
            isLowPowerMode: true,
            estimatedTimeRemaining: 0.5 * 3600 // 30 minutes
        )
        
        print("🔋 Mock: Simulated critical battery")
    }
    
    deinit {
        stopMockUpdates()
    }
}

// MARK: - Supporting Types (if not already defined)

extension WatchConnectionState {
    static func == (lhs: WatchConnectionState, rhs: WatchConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.paired, .paired),
             (.inactive, .inactive),
             (.connected, .connected):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}