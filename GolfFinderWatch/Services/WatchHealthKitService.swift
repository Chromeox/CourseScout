import Foundation
import HealthKit
import WorkoutKit
import WatchKit
import os.log
import Combine

// MARK: - Watch HealthKit Service Protocol

protocol WatchHealthKitServiceProtocol: AnyObject {
    // Authorization
    func requestAuthorization() async -> Bool
    var authorizationStatus: HKAuthorizationStatus { get }
    
    // Golf workout management
    func startGolfWorkout(course: SharedGolfCourse) async -> Bool
    func endGolfWorkout() async -> GolfWorkoutSummary?
    func pauseWorkout()
    func resumeWorkout()
    
    // Real-time health monitoring
    func startHealthMonitoring() async
    func stopHealthMonitoring()
    func getCurrentHeartRate() -> Double?
    func getCurrentStepCount() -> Int
    
    // Battery-optimized monitoring
    func setMonitoringMode(_ mode: HealthMonitoringMode)
    func optimizeForGolfRound()
    func optimizeForBattery()
    
    // Data collection
    func getWorkoutMetrics() -> WatchHealthMetrics
    func recordHoleMilestone(holeNumber: Int, strokeCount: Int)
    func recordShotDistance(distance: Double, club: String?)
    
    // Delegate
    func setDelegate(_ delegate: WatchHealthKitDelegate)
    func removeDelegate(_ delegate: WatchHealthKitDelegate)
}

// MARK: - Health Kit Delegate Protocol

protocol WatchHealthKitDelegate: AnyObject {
    func didUpdateHeartRate(_ heartRate: Double)
    func didUpdateStepCount(_ steps: Int)
    func didEnterHeartRateZone(_ zone: HeartRateZone)
    func didRecordWorkoutMilestone(_ milestone: WorkoutMilestone)
    func didDetectRestPeriod(duration: TimeInterval)
    func healthAuthorizationDidChange(_ status: HKAuthorizationStatus)
}

// Default implementations
extension WatchHealthKitDelegate {
    func didUpdateHeartRate(_ heartRate: Double) {}
    func didUpdateStepCount(_ steps: Int) {}
    func didEnterHeartRateZone(_ zone: HeartRateZone) {}
    func didRecordWorkoutMilestone(_ milestone: WorkoutMilestone) {}
    func didDetectRestPeriod(duration: TimeInterval) {}
    func healthAuthorizationDidChange(_ status: HKAuthorizationStatus) {}
}

// MARK: - Watch HealthKit Service Implementation

@MainActor
class WatchHealthKitService: NSObject, WatchHealthKitServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "HealthKit")
    
    // Workout management
    private var workoutManager: HKWorkoutSession?
    private var liveWorkoutBuilder: HKLiveWorkoutBuilder?
    private var workoutStartDate: Date?
    private var currentGolfWorkout: GolfWorkout?
    
    // Health monitoring
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var stepCountQuery: HKObserverQuery?
    private var activeEnergyQuery: HKAnchoredObjectQuery?
    private var distanceQuery: HKAnchoredObjectQuery?
    
    // Real-time data
    @Published private(set) var currentHeartRate: Double = 0
    @Published private(set) var currentSteps: Int = 0
    @Published private(set) var currentActiveEnergy: Double = 0
    @Published private(set) var currentDistance: Double = 0
    @Published private(set) var currentHeartRateZone: HeartRateZone = .resting
    
    // Monitoring configuration
    private var monitoringMode: HealthMonitoringMode = .normal
    private var isMonitoring = false
    private var isBatteryOptimized = false
    
    // Delegate management
    private var delegates: [WeakHealthKitDelegate] = []
    
    // Golf-specific tracking
    private var holeStartTimes: [Int: Date] = [:]
    private var shotDistances: [Double] = []
    private var heartRateZoneHistory: [HeartRateZone: TimeInterval] = [:]
    private var restPeriods: [(start: Date, duration: TimeInterval)] = []
    
    // Battery optimization
    private var lastHeartRateUpdate = Date()
    private var heartRateUpdateInterval: TimeInterval = 5.0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupHealthStore()
        logger.info("WatchHealthKitService initialized")
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit not available on this device")
            return false
        }
        
        let healthTypesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .vo2Max)!,
            HKWorkoutType.workoutType()
        ]
        
        let healthTypesToWrite: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKWorkoutType.workoutType()
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: healthTypesToWrite, read: healthTypesToRead)
            logger.info("HealthKit authorization requested successfully")
            
            // Notify delegates
            let status = authorizationStatus
            notifyDelegates { delegate in
                delegate.healthAuthorizationDidChange(status)
            }
            
            return status == .sharingAuthorized
        } catch {
            logger.error("HealthKit authorization failed: \(error.localizedDescription)")
            return false
        }
    }
    
    var authorizationStatus: HKAuthorizationStatus {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return .notDetermined
        }
        return healthStore.authorizationStatus(for: heartRateType)
    }
    
    // MARK: - Golf Workout Management
    
    func startGolfWorkout(course: SharedGolfCourse) async -> Bool {
        logger.info("Starting golf workout for course: \(course.name)")
        
        guard authorizationStatus == .sharingAuthorized else {
            logger.error("HealthKit not authorized")
            return false
        }
        
        // Create workout configuration
        let workoutConfiguration = HKWorkoutConfiguration()
        workoutConfiguration.activityType = .golf
        workoutConfiguration.locationType = .outdoor
        
        do {
            // Create workout session
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: workoutConfiguration)
            let builder = session.associatedWorkoutBuilder()
            
            // Configure data collection
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: workoutConfiguration)
            
            // Set delegates
            session.delegate = self
            builder.delegate = self
            
            // Start the session
            session.startActivity(with: Date())
            await builder.beginCollection(withStart: Date())
            
            // Store references
            workoutManager = session
            liveWorkoutBuilder = builder
            workoutStartDate = Date()
            
            // Create golf workout tracking
            currentGolfWorkout = GolfWorkout(
                id: UUID().uuidString,
                courseId: course.id,
                courseName: course.name,
                startTime: Date(),
                endTime: nil,
                workoutType: course.numberOfHoles == 18 ? .golf18Holes : .golf9Holes,
                statistics: WorkoutStatistics(
                    totalDistance: 0,
                    averageHeartRate: 0,
                    maxHeartRate: 0,
                    caloriesBurned: 0,
                    steps: 0,
                    holesCompleted: 0,
                    shotsTracked: 0,
                    averageShotDistance: nil
                )
            )
            
            // Start health monitoring
            await startHealthMonitoring()
            
            logger.info("Golf workout started successfully")
            return true
            
        } catch {
            logger.error("Failed to start golf workout: \(error.localizedDescription)")
            return false
        }
    }
    
    func endGolfWorkout() async -> GolfWorkoutSummary? {
        logger.info("Ending golf workout")
        
        guard let session = workoutManager,
              let builder = liveWorkoutBuilder,
              let startDate = workoutStartDate else {
            logger.error("No active workout to end")
            return nil
        }
        
        do {
            // End the session
            session.end()
            await builder.endCollection(withEnd: Date())
            
            // Stop health monitoring
            await stopHealthMonitoring()
            
            // Finalize the workout
            let workout = try await builder.finishWorkout()
            
            // Create workout summary
            let summary = createWorkoutSummary(workout: workout, startDate: startDate)
            
            // Clean up
            workoutManager = nil
            liveWorkoutBuilder = nil
            workoutStartDate = nil
            currentGolfWorkout = nil
            
            logger.info("Golf workout ended successfully")
            return summary
            
        } catch {
            logger.error("Failed to end golf workout: \(error.localizedDescription)")
            return nil
        }
    }
    
    func pauseWorkout() {
        guard let session = workoutManager else { return }
        session.pause()
        logger.info("Golf workout paused")
    }
    
    func resumeWorkout() {
        guard let session = workoutManager else { return }
        session.resume()
        logger.info("Golf workout resumed")
    }
    
    // MARK: - Health Monitoring
    
    func startHealthMonitoring() async {
        guard !isMonitoring else { return }
        
        logger.info("Starting health monitoring with mode: \(monitoringMode)")
        isMonitoring = true
        
        await startHeartRateMonitoring()
        await startStepCountMonitoring()
        await startActiveEnergyMonitoring()
        await startDistanceMonitoring()
    }
    
    func stopHealthMonitoring() async {
        guard isMonitoring else { return }
        
        logger.info("Stopping health monitoring")
        isMonitoring = false
        
        // Stop all queries
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        
        if let query = stepCountQuery {
            healthStore.stop(query)
            stepCountQuery = nil
        }
        
        if let query = activeEnergyQuery {
            healthStore.stop(query)
            activeEnergyQuery = nil
        }
        
        if let query = distanceQuery {
            healthStore.stop(query)
            distanceQuery = nil
        }
    }
    
    func getCurrentHeartRate() -> Double? {
        return currentHeartRate > 0 ? currentHeartRate : nil
    }
    
    func getCurrentStepCount() -> Int {
        return currentSteps
    }
    
    // MARK: - Battery Optimization
    
    func setMonitoringMode(_ mode: HealthMonitoringMode) {
        logger.info("Setting monitoring mode to: \(mode)")
        monitoringMode = mode
        
        // Adjust monitoring intervals based on mode
        switch mode {
        case .normal:
            heartRateUpdateInterval = 5.0
        case .batteryOptimized:
            heartRateUpdateInterval = 15.0
        case .golfOptimized:
            heartRateUpdateInterval = 10.0
        case .minimal:
            heartRateUpdateInterval = 30.0
        }
        
        // Restart monitoring if active
        if isMonitoring {
            Task {
                await stopHealthMonitoring()
                await startHealthMonitoring()
            }
        }
    }
    
    func optimizeForGolfRound() {
        logger.info("Optimizing for golf round")
        setMonitoringMode(.golfOptimized)
        isBatteryOptimized = false
    }
    
    func optimizeForBattery() {
        logger.info("Optimizing for battery")
        setMonitoringMode(.batteryOptimized)
        isBatteryOptimized = true
    }
    
    // MARK: - Data Collection
    
    func getWorkoutMetrics() -> WatchHealthMetrics {
        return WatchHealthMetrics(
            heartRate: getCurrentHeartRate(),
            steps: currentSteps,
            activeEnergyBurned: currentActiveEnergy,
            distanceWalkingRunning: currentDistance
        )
    }
    
    func recordHoleMilestone(holeNumber: Int, strokeCount: Int) {
        logger.info("Recording hole \(holeNumber) completed in \(strokeCount) strokes")
        
        // Record hole completion time
        holeStartTimes[holeNumber] = Date()
        
        // Update golf workout statistics
        if var golfWorkout = currentGolfWorkout {
            golfWorkout.statistics.holesCompleted += 1
            golfWorkout.statistics.shotsTracked += strokeCount
            currentGolfWorkout = golfWorkout
        }
        
        // Notify delegates
        let milestone = WorkoutMilestone(
            id: UUID().uuidString,
            workoutId: currentGolfWorkout?.id ?? "",
            type: .holeCompleted(holeNumber: holeNumber),
            timestamp: Date(),
            data: [
                "holeNumber": holeNumber,
                "strokes": strokeCount,
                "heartRate": currentHeartRate
            ]
        )
        
        notifyDelegates { delegate in
            delegate.didRecordWorkoutMilestone(milestone)
        }
    }
    
    func recordShotDistance(distance: Double, club: String?) {
        logger.debug("Recording shot distance: \(distance) yards with club: \(club ?? "unknown")")
        
        shotDistances.append(distance)
        
        // Update average shot distance
        if var golfWorkout = currentGolfWorkout {
            let averageDistance = shotDistances.reduce(0, +) / Double(shotDistances.count)
            golfWorkout.statistics.averageShotDistance = averageDistance
            currentGolfWorkout = golfWorkout
        }
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: WatchHealthKitDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        delegates.append(WeakHealthKitDelegate(delegate))
        delegates.removeAll { $0.delegate == nil }
        logger.debug("Added HealthKit delegate")
    }
    
    func removeDelegate(_ delegate: WatchHealthKitDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        logger.debug("Removed HealthKit delegate")
    }
}

// MARK: - Private Methods

private extension WatchHealthKitService {
    
    func setupHealthStore() {
        // Configure health store if needed
    }
    
    func startHeartRateMonitoring() async {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-60),
            end: nil,
            options: .strictEndDate
        )
        
        heartRateQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            
            guard let self = self, let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                // Throttle updates based on monitoring mode
                if Date().timeIntervalSince(self.lastHeartRateUpdate) < self.heartRateUpdateInterval {
                    return
                }
                
                if let mostRecentSample = samples.last {
                    let heartRate = mostRecentSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    self.currentHeartRate = heartRate
                    self.lastHeartRateUpdate = Date()
                    
                    // Determine heart rate zone
                    let zone = self.determineHeartRateZone(heartRate: heartRate)
                    if zone != self.currentHeartRateZone {
                        self.currentHeartRateZone = zone
                        self.notifyDelegates { delegate in
                            delegate.didEnterHeartRateZone(zone)
                        }
                    }
                    
                    // Notify delegates
                    self.notifyDelegates { delegate in
                        delegate.didUpdateHeartRate(heartRate)
                    }
                }
            }
        }
        
        heartRateQuery?.updateHandler = { [weak self] query, samples, deletedObjects, anchor, error in
            // Handle live updates
        }
        
        healthStore.execute(heartRateQuery!)
    }
    
    func startStepCountMonitoring() async {
        guard let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: Date()),
            end: nil,
            options: .strictEndDate
        )
        
        let query = HKStatisticsQuery(
            quantityType: stepCountType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] query, statistics, error in
            
            guard let self = self, let statistics = statistics else { return }
            
            Task { @MainActor in
                let steps = Int(statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                self.currentSteps = steps
                
                self.notifyDelegates { delegate in
                    delegate.didUpdateStepCount(steps)
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    func startActiveEnergyMonitoring() async {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: workoutStartDate ?? Date().addingTimeInterval(-3600),
            end: nil,
            options: .strictEndDate
        )
        
        activeEnergyQuery = HKAnchoredObjectQuery(
            type: energyType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            
            guard let self = self, let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                let totalEnergy = samples.reduce(0) { sum, sample in
                    sum + sample.quantity.doubleValue(for: .kilocalorie())
                }
                self.currentActiveEnergy = totalEnergy
            }
        }
        
        healthStore.execute(activeEnergyQuery!)
    }
    
    func startDistanceMonitoring() async {
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: workoutStartDate ?? Date().addingTimeInterval(-3600),
            end: nil,
            options: .strictEndDate
        )
        
        distanceQuery = HKAnchoredObjectQuery(
            type: distanceType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            
            guard let self = self, let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                let totalDistance = samples.reduce(0) { sum, sample in
                    sum + sample.quantity.doubleValue(for: .meter())
                }
                self.currentDistance = totalDistance
            }
        }
        
        healthStore.execute(distanceQuery!)
    }
    
    func determineHeartRateZone(heartRate: Double) -> HeartRateZone {
        // Simplified heart rate zones (should be personalized based on age/fitness)
        let maxHeartRate = 220.0 - 30.0 // Assume 30 years old for example
        let percentage = heartRate / maxHeartRate
        
        switch percentage {
        case 0..<0.5:
            return .resting
        case 0.5..<0.6:
            return .warmUp
        case 0.6..<0.7:
            return .fatBurn
        case 0.7..<0.8:
            return .aerobic
        case 0.8..<0.9:
            return .anaerobic
        default:
            return .maxEffort
        }
    }
    
    func createWorkoutSummary(workout: HKWorkout, startDate: Date) -> GolfWorkoutSummary {
        return GolfWorkoutSummary(
            workoutId: workout.uuid.uuidString,
            courseId: currentGolfWorkout?.courseId ?? "",
            courseName: currentGolfWorkout?.courseName ?? "",
            startTime: startDate,
            endTime: Date(),
            duration: workout.duration,
            totalDistance: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
            activeEnergyBurned: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
            averageHeartRate: currentGolfWorkout?.statistics.averageHeartRate ?? 0,
            maxHeartRate: currentGolfWorkout?.statistics.maxHeartRate ?? 0,
            holesCompleted: currentGolfWorkout?.statistics.holesCompleted ?? 0,
            totalShots: currentGolfWorkout?.statistics.shotsTracked ?? 0,
            averageShotDistance: currentGolfWorkout?.statistics.averageShotDistance
        )
    }
    
    func notifyDelegates<T>(_ action: (WatchHealthKitDelegate) -> T) {
        delegates.forEach { weakDelegate in
            if let delegate = weakDelegate.delegate {
                _ = action(delegate)
            }
        }
        
        // Clean up nil references
        delegates.removeAll { $0.delegate == nil }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchHealthKitService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        logger.info("Workout session state changed from \(fromState.rawValue) to \(toState.rawValue)")
    }
    
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        logger.error("Workout session failed with error: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchHealthKitService: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Handle collected data
    }
    
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events
    }
}

// MARK: - Supporting Types

enum HealthMonitoringMode: String, CaseIterable {
    case normal = "normal"
    case batteryOptimized = "battery_optimized"
    case golfOptimized = "golf_optimized"
    case minimal = "minimal"
}

enum HeartRateZone: String, CaseIterable {
    case resting = "resting"
    case warmUp = "warm_up"
    case fatBurn = "fat_burn"
    case aerobic = "aerobic"
    case anaerobic = "anaerobic"
    case maxEffort = "max_effort"
    
    var displayName: String {
        switch self {
        case .resting: return "Resting"
        case .warmUp: return "Warm-Up"
        case .fatBurn: return "Fat Burn"
        case .aerobic: return "Aerobic"
        case .anaerobic: return "Anaerobic"
        case .maxEffort: return "Max Effort"
        }
    }
    
    var color: String {
        switch self {
        case .resting: return "gray"
        case .warmUp: return "blue"
        case .fatBurn: return "green"
        case .aerobic: return "yellow"
        case .anaerobic: return "orange"
        case .maxEffort: return "red"
        }
    }
}

struct GolfWorkoutSummary {
    let workoutId: String
    let courseId: String
    let courseName: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let totalDistance: Double // meters
    let activeEnergyBurned: Double // kilocalories
    let averageHeartRate: Double
    let maxHeartRate: Double
    let holesCompleted: Int
    let totalShots: Int
    let averageShotDistance: Double?
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    var formattedDistance: String {
        let miles = totalDistance * 0.000621371
        return String(format: "%.1f mi", miles)
    }
    
    var formattedCalories: String {
        return String(format: "%.0f cal", activeEnergyBurned)
    }
}

private struct WeakHealthKitDelegate {
    weak var delegate: WatchHealthKitDelegate?
    
    init(_ delegate: WatchHealthKitDelegate) {
        self.delegate = delegate
    }
}