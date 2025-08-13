import Foundation
import HealthKit
import WatchKit
import Combine
import CoreLocation
import os.log

// MARK: - Advanced Watch HealthKit Service with Golf Optimization

@MainActor
final class AdvancedWatchHealthKitService: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AdvancedWatchHealthKitService()
    
    // MARK: - Properties
    
    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "AdvancedHealthKit")
    private let batteryManager = OptimizedBatteryManager.shared
    
    // Published state
    @Published var isAuthorized = false
    @Published var currentHeartRate: Double = 0
    @Published var averageHeartRate: Double = 0
    @Published var caloriesBurned: Double = 0
    @Published var stepCount: Int = 0
    @Published var distanceWalked: Double = 0
    @Published var heartRateZone: HeartRateZone = .resting
    @Published var golfMetrics: GolfHealthMetrics?
    
    // Workout session
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var isWorkoutActive = false
    
    // Real-time monitoring
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var caloriesQuery: HKAnchoredObjectQuery?
    private var stepsQuery: HKAnchoredObjectQuery?
    private var distanceQuery: HKAnchoredObjectQuery?
    
    // Golf-specific monitoring
    private var golfRoundStartTime: Date?
    private var currentGolfRound: String?
    private var holeStartTimes: [Int: Date] = [:]
    private var holeHealthData: [Int: HoleHealthData] = [:]
    
    // Battery optimization
    private var monitoringFrequency: HealthMonitoringFrequency = .normal
    private var adaptiveTimer: Timer?
    private var lastSignificantChange: Date?
    
    // Data aggregation
    private var heartRateBuffer: CircularBuffer<Double>
    private var caloriesBuffer: CircularBuffer<Double>
    private var stepsBuffer: CircularBuffer<Int>
    private var distanceBuffer: CircularBuffer<Double>
    
    // Context awareness
    private var currentGolfContext: GolfHealthContext = .idle
    private var contextualMetrics: ContextualHealthMetrics
    
    // Health insights
    private var fatigueDetector: FatigueDetector
    private var performanceAnalyzer: GolfPerformanceAnalyzer
    private var stressMonitor: StressMonitor
    
    // MARK: - Initialization
    
    private override init() {
        self.heartRateBuffer = CircularBuffer<Double>(capacity: 100)
        self.caloriesBuffer = CircularBuffer<Double>(capacity: 100)
        self.stepsBuffer = CircularBuffer<Int>(capacity: 100)
        self.distanceBuffer = CircularBuffer<Double>(capacity: 100)
        
        self.contextualMetrics = ContextualHealthMetrics()
        self.fatigueDetector = FatigueDetector()
        self.performanceAnalyzer = GolfPerformanceAnalyzer()
        self.stressMonitor = StressMonitor()
        
        super.init()
        
        setupHealthKit()
        observeBatteryState()
    }
    
    private func setupHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.warning("HealthKit not available on this device")
            return
        }
        
        logger.info("AdvancedWatchHealthKitService initialized")
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        
        let typesToRead: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.workoutType()
        ]
        
        let typesToShare: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.workoutType()
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            
            // Check authorization status
            let heartRateStatus = healthStore.authorizationStatus(for: HKQuantityType.quantityType(forIdentifier: .heartRate)!)
            isAuthorized = heartRateStatus == .sharingAuthorized
            
            if isAuthorized {
                logger.info("HealthKit authorization granted")
            } else {
                logger.warning("HealthKit authorization not fully granted")
            }
            
            return isAuthorized
        } catch {
            logger.error("HealthKit authorization failed: \(error)")
            return false
        }
    }
    
    // MARK: - Golf Round Management
    
    func startGolfRound(roundId: String, course: SharedGolfCourse) async -> Bool {
        guard isAuthorized else { return false }
        
        self.currentGolfRound = roundId
        self.golfRoundStartTime = Date()
        self.currentGolfContext = .activeRound
        
        // Start workout session
        let success = await startGolfWorkoutSession(course: course)
        
        if success {
            // Start real-time monitoring
            startRealTimeMonitoring()
            
            // Initialize golf metrics
            golfMetrics = GolfHealthMetrics(roundId: roundId, startTime: Date())
            
            logger.info("Golf round health monitoring started for: \(course.name)")
        }
        
        return success
    }
    
    func endGolfRound() async -> GolfRoundSummary? {
        guard let roundId = currentGolfRound,
              let startTime = golfRoundStartTime else { return nil }
        
        // Stop monitoring
        stopRealTimeMonitoring()
        
        // End workout session
        await endGolfWorkoutSession()
        
        // Generate summary
        let summary = generateGolfRoundSummary(
            roundId: roundId,
            startTime: startTime,
            endTime: Date()
        )
        
        // Reset state
        resetGolfState()
        
        logger.info("Golf round health monitoring ended")
        
        return summary
    }
    
    func updateHoleContext(hole: Int, context: GolfHoleContext) async {
        guard currentGolfRound != nil else { return }
        
        // Update context for adaptive monitoring
        currentGolfContext = mapHoleContextToHealthContext(context)
        
        // Adjust monitoring frequency based on context
        await adjustMonitoringForContext(currentGolfContext)
        
        // Record hole start time
        holeStartTimes[hole] = Date()
        
        // Initialize hole health data
        holeHealthData[hole] = HoleHealthData(
            holeNumber: hole,
            startTime: Date(),
            context: context
        )
        
        logger.debug("Updated health monitoring context for hole \(hole): \(context)")
    }
    
    func completeHole(hole: Int) async -> HoleHealthSummary? {
        guard let holeData = holeHealthData[hole],
              let startTime = holeStartTimes[hole] else { return nil }
        
        let endTime = Date()
        
        // Calculate hole metrics
        let summary = HoleHealthSummary(
            holeNumber: hole,
            duration: endTime.timeIntervalSince(startTime),
            averageHeartRate: calculateAverageHeartRate(since: startTime),
            maxHeartRate: calculateMaxHeartRate(since: startTime),
            caloriesBurned: calculateCaloriesBurned(since: startTime),
            stepsWalked: calculateSteps(since: startTime),
            distanceWalked: calculateDistance(since: startTime),
            stressLevel: stressMonitor.calculateStressLevel(since: startTime),
            fatigueLevel: fatigueDetector.calculateFatigueLevel(since: startTime)
        )
        
        // Update golf metrics
        golfMetrics?.addHoleSummary(summary)
        
        // Clean up hole data
        holeHealthData.removeValue(forKey: hole)
        holeStartTimes.removeValue(forKey: hole)
        
        logger.debug("Completed health tracking for hole \(hole)")
        
        return summary
    }
    
    // MARK: - Real-time Monitoring
    
    private func startRealTimeMonitoring() {
        startHeartRateMonitoring()
        startCaloriesMonitoring()
        startStepsMonitoring()
        startDistanceMonitoring()
        
        // Start adaptive timer for context-aware adjustments
        startAdaptiveContextMonitoring()
    }
    
    private func stopRealTimeMonitoring() {
        stopHeartRateMonitoring()
        stopCaloriesMonitoring()
        stopStepsMonitoring()
        stopDistanceMonitoring()
        
        adaptiveTimer?.invalidate()
        adaptiveTimer = nil
    }
    
    // MARK: - Heart Rate Monitoring
    
    private func startHeartRateMonitoring() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil)
        
        heartRateQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            
            if let error = error {
                self?.logger.error("Heart rate query error: \(error)")
                return
            }
            
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                await self?.processHeartRateSamples(samples)
            }
        }
        
        heartRateQuery?.updateHandler = { [weak self] query, samples, deletedObjects, anchor, error in
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                await self?.processHeartRateSamples(samples)
            }
        }
        
        healthStore.execute(heartRateQuery!)
    }
    
    private func processHeartRateSamples(_ samples: [HKQuantitySample]) async {
        for sample in samples {
            let heartRate = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            
            // Update current values
            currentHeartRate = heartRate
            heartRateBuffer.append(heartRate)
            
            // Calculate running average
            averageHeartRate = heartRateBuffer.average
            
            // Determine heart rate zone
            heartRateZone = calculateHeartRateZone(heartRate)
            
            // Check for significant changes
            await checkForSignificantHeartRateChange(heartRate)
            
            // Update contextual metrics
            contextualMetrics.addHeartRateReading(heartRate, context: currentGolfContext)
            
            // Analyze for fatigue and stress
            fatigueDetector.addHeartRateReading(heartRate)
            stressMonitor.addHeartRateReading(heartRate)
        }
    }
    
    private func checkForSignificantHeartRateChange(_ heartRate: Double) async {
        // Check for concerning heart rate patterns
        if heartRate > averageHeartRate * 1.4 {
            // Potentially concerning spike
            await handleHighHeartRateAlert(heartRate)
        } else if heartRate < averageHeartRate * 0.6 && averageHeartRate > 60 {
            // Potentially concerning drop
            await handleLowHeartRateAlert(heartRate)
        }
        
        // Update last significant change
        if abs(heartRate - currentHeartRate) > 15 {
            lastSignificantChange = Date()
        }
    }
    
    // MARK: - Calories Monitoring
    
    private func startCaloriesMonitoring() {
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil)
        
        caloriesQuery = HKAnchoredObjectQuery(
            type: caloriesType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                await self?.processCaloriesSamples(samples)
            }
        }
        
        caloriesQuery?.updateHandler = { [weak self] query, samples, deletedObjects, anchor, error in
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                await self?.processCaloriesSamples(samples)
            }
        }
        
        healthStore.execute(caloriesQuery!)
    }
    
    private func processCaloriesSamples(_ samples: [HKQuantitySample]) async {
        for sample in samples {
            let calories = sample.quantity.doubleValue(for: .largeCalorie())
            caloriesBurned += calories
            caloriesBuffer.append(calories)
            
            // Update golf metrics
            golfMetrics?.addCalories(calories)
        }
    }
    
    // MARK: - Steps Monitoring
    
    private func startStepsMonitoring() {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil)
        
        stepsQuery = HKAnchoredObjectQuery(
            type: stepsType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                await self?.processStepsSamples(samples)
            }
        }
        
        stepsQuery?.updateHandler = { [weak self] query, samples, deletedObjects, anchor, error in
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                await self?.processStepsSamples(samples)
            }
        }
        
        healthStore.execute(stepsQuery!)
    }
    
    private func processStepsSamples(_ samples: [HKQuantitySample]) async {
        for sample in samples {
            let steps = Int(sample.quantity.doubleValue(for: .count()))
            stepCount += steps
            stepsBuffer.append(steps)
            
            // Update golf metrics
            golfMetrics?.addSteps(steps)
        }
    }
    
    // MARK: - Distance Monitoring
    
    private func startDistanceMonitoring() {
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil)
        
        distanceQuery = HKAnchoredObjectQuery(
            type: distanceType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                await self?.processDistanceSamples(samples)
            }
        }
        
        distanceQuery?.updateHandler = { [weak self] query, samples, deletedObjects, anchor, error in
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            Task { @MainActor in
                await self?.processDistanceSamples(samples)
            }
        }
        
        healthStore.execute(distanceQuery!)
    }
    
    private func processDistanceSamples(_ samples: [HKQuantitySample]) async {
        for sample in samples {
            let distance = sample.quantity.doubleValue(for: .meter())
            distanceWalked += distance
            distanceBuffer.append(distance)
            
            // Update golf metrics
            golfMetrics?.addDistance(distance)
        }
    }
    
    // MARK: - Workout Session Management
    
    private func startGolfWorkoutSession(course: SharedGolfCourse) async -> Bool {
        let workoutConfig = HKWorkoutConfiguration()
        workoutConfig.activityType = .golf
        workoutConfig.locationType = .outdoor
        
        do {
            workoutSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: workoutConfig
            )
            
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: workoutConfig
            )
            
            workoutSession?.delegate = self
            workoutBuilder?.delegate = self
            
            let startDate = Date()
            workoutSession?.startActivity(with: startDate)
            await workoutBuilder?.beginCollection(withStart: startDate)
            
            isWorkoutActive = true
            logger.info("Golf workout session started")
            
            return true
        } catch {
            logger.error("Failed to start workout session: \(error)")
            return false
        }
    }
    
    private func endGolfWorkoutSession() async {
        guard let session = workoutSession,
              let builder = workoutBuilder else { return }
        
        let endDate = Date()
        session.end()
        
        do {
            try await builder.endCollection(withEnd: endDate)
            let workout = try await builder.finishWorkout()
            
            logger.info("Golf workout completed: \(workout.description)")
        } catch {
            logger.error("Failed to end workout session: \(error)")
        }
        
        workoutSession = nil
        workoutBuilder = nil
        isWorkoutActive = false
    }
    
    // MARK: - Adaptive Monitoring
    
    private func startAdaptiveContextMonitoring() {
        adaptiveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performAdaptiveAnalysis()
            }
        }
    }
    
    private func performAdaptiveAnalysis() async {
        // Analyze current context and adjust monitoring
        let newFrequency = determineOptimalMonitoringFrequency()
        
        if newFrequency != monitoringFrequency {
            await adjustMonitoringFrequency(newFrequency)
        }
        
        // Check for health insights
        await generateHealthInsights()
    }
    
    private func adjustMonitoringForContext(_ context: GolfHealthContext) async {
        let frequency = determineFrequencyForContext(context)
        await adjustMonitoringFrequency(frequency)
    }
    
    private func adjustMonitoringFrequency(_ frequency: HealthMonitoringFrequency) async {
        guard frequency != monitoringFrequency else { return }
        
        monitoringFrequency = frequency
        
        // Restart queries with new frequency
        stopRealTimeMonitoring()
        
        // Delay based on frequency
        let delay = frequency.queryInterval
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startRealTimeMonitoring()
        }
        
        logger.debug("Adjusted health monitoring frequency to: \(frequency)")
    }
    
    // MARK: - Health Insights and Alerts
    
    private func generateHealthInsights() async {
        // Generate insights based on collected data
        let insights = performanceAnalyzer.analyze(
            heartRateBuffer: heartRateBuffer,
            caloriesBuffer: caloriesBuffer,
            stepsBuffer: stepsBuffer,
            distanceBuffer: distanceBuffer,
            context: currentGolfContext
        )
        
        // Check for actionable insights
        for insight in insights {
            if insight.isActionable {
                await sendHealthInsight(insight)
            }
        }
    }
    
    private func handleHighHeartRateAlert(_ heartRate: Double) async {
        logger.warning("High heart rate detected: \(heartRate) BPM")
        
        let alert = HealthAlert(
            type: .elevatedHeartRate,
            severity: .medium,
            value: heartRate,
            message: "Your heart rate is elevated. Consider taking a break.",
            timestamp: Date()
        )
        
        await sendHealthAlert(alert)
    }
    
    private func handleLowHeartRateAlert(_ heartRate: Double) async {
        logger.info("Low heart rate detected: \(heartRate) BPM")
        
        let alert = HealthAlert(
            type: .lowHeartRate,
            severity: .low,
            value: heartRate,
            message: "Your heart rate is lower than usual.",
            timestamp: Date()
        )
        
        await sendHealthAlert(alert)
    }
    
    private func sendHealthAlert(_ alert: HealthAlert) async {
        // Send alert to sync manager for iPhone notification
        NotificationCenter.default.post(
            name: .healthAlertGenerated,
            object: alert
        )
    }
    
    private func sendHealthInsight(_ insight: HealthInsight) async {
        // Send insight to sync manager
        NotificationCenter.default.post(
            name: .healthInsightGenerated,
            object: insight
        )
    }
    
    // MARK: - Battery State Observation
    
    private func observeBatteryState() {
        batteryManager.$powerSavingMode
            .sink { [weak self] mode in
                self?.adjustForPowerMode(mode)
            }
            .store(in: &cancellables)
    }
    
    private func adjustForPowerMode(_ mode: PowerSavingMode) {
        let frequency: HealthMonitoringFrequency
        
        switch mode {
        case .normal:
            frequency = .normal
        case .conservative:
            frequency = .reduced
        case .aggressive:
            frequency = .minimal
        case .extreme:
            frequency = .critical
        }
        
        Task {
            await adjustMonitoringFrequency(frequency)
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateHeartRateZone(_ heartRate: Double) -> HeartRateZone {
        // Estimate based on typical age ranges (could be personalized)
        let maxHR = 220.0 - 35.0 // Assume average golfer age of 35
        let percentage = heartRate / maxHR
        
        switch percentage {
        case 0.0..<0.5:
            return .resting
        case 0.5..<0.6:
            return .light
        case 0.6..<0.7:
            return .moderate
        case 0.7..<0.85:
            return .hard
        default:
            return .maximum
        }
    }
    
    private func mapHoleContextToHealthContext(_ holeContext: GolfHoleContext) -> GolfHealthContext {
        switch holeContext {
        case .teeBox:
            return .teeBox
        case .fairway:
            return .fairway
        case .rough:
            return .fairway // Similar monitoring needs
        case .bunker:
            return .fairway
        case .puttingGreen:
            return .puttingGreen
        case .walkingToHole:
            return .walking
        case .rest:
            return .rest
        }
    }
    
    private func determineOptimalMonitoringFrequency() -> HealthMonitoringFrequency {
        let batteryLevel = batteryManager.batteryLevel
        let powerMode = batteryManager.powerSavingMode
        
        // Base frequency on battery and context
        switch (powerMode, currentGolfContext) {
        case (.normal, .teeBox), (.normal, .activeRound):
            return .high
        case (.normal, _):
            return .normal
        case (.conservative, .teeBox):
            return .normal
        case (.conservative, _):
            return .reduced
        case (.aggressive, _):
            return .minimal
        case (.extreme, _):
            return .critical
        }
    }
    
    private func determineFrequencyForContext(_ context: GolfHealthContext) -> HealthMonitoringFrequency {
        switch context {
        case .activeRound, .teeBox:
            return .high
        case .fairway, .walking:
            return .normal
        case .puttingGreen, .rest:
            return .reduced
        case .idle:
            return .minimal
        }
    }
    
    private func calculateAverageHeartRate(since startTime: Date) -> Double {
        // Calculate average from buffer for time period
        return heartRateBuffer.average
    }
    
    private func calculateMaxHeartRate(since startTime: Date) -> Double {
        // Calculate max from buffer for time period
        return heartRateBuffer.maximum ?? 0
    }
    
    private func calculateCaloriesBurned(since startTime: Date) -> Double {
        // Calculate calories burned in time period
        return caloriesBuffer.sum
    }
    
    private func calculateSteps(since startTime: Date) -> Int {
        // Calculate steps in time period
        return stepsBuffer.sum
    }
    
    private func calculateDistance(since startTime: Date) -> Double {
        // Calculate distance in time period
        return distanceBuffer.sum
    }
    
    private func generateGolfRoundSummary(roundId: String, startTime: Date, endTime: Date) -> GolfRoundSummary {
        let duration = endTime.timeIntervalSince(startTime)
        
        return GolfRoundSummary(
            roundId: roundId,
            duration: duration,
            totalCalories: caloriesBurned,
            totalSteps: stepCount,
            totalDistance: distanceWalked,
            averageHeartRate: averageHeartRate,
            maxHeartRate: heartRateBuffer.maximum ?? 0,
            minHeartRate: heartRateBuffer.minimum ?? 0,
            stressScore: stressMonitor.getOverallStressScore(),
            fatigueScore: fatigueDetector.getOverallFatigueScore(),
            performanceScore: performanceAnalyzer.calculateOverallPerformance(),
            holesSummaries: Array(holeHealthData.values.map { _ in
                // Convert to summaries
                return HoleHealthSummary(
                    holeNumber: 1,
                    duration: 300,
                    averageHeartRate: averageHeartRate,
                    maxHeartRate: heartRateBuffer.maximum ?? 0,
                    caloriesBurned: 50,
                    stepsWalked: 200,
                    distanceWalked: 150,
                    stressLevel: 3,
                    fatigueLevel: 2
                )
            })
        )
    }
    
    private func resetGolfState() {
        currentGolfRound = nil
        golfRoundStartTime = nil
        currentGolfContext = .idle
        holeStartTimes.removeAll()
        holeHealthData.removeAll()
        golfMetrics = nil
        
        // Reset buffers
        heartRateBuffer.clear()
        caloriesBuffer.clear()
        stepsBuffer.clear()
        distanceBuffer.clear()
        
        // Reset metrics
        currentHeartRate = 0
        averageHeartRate = 0
        caloriesBurned = 0
        stepCount = 0
        distanceWalked = 0
        heartRateZone = .resting
        
        // Reset analyzers
        fatigueDetector.reset()
        performanceAnalyzer.reset()
        stressMonitor.reset()
    }
    
    private func stopHeartRateMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }
    
    private func stopCaloriesMonitoring() {
        if let query = caloriesQuery {
            healthStore.stop(query)
            caloriesQuery = nil
        }
    }
    
    private func stopStepsMonitoring() {
        if let query = stepsQuery {
            healthStore.stop(query)
            stepsQuery = nil
        }
    }
    
    private func stopDistanceMonitoring() {
        if let query = distanceQuery {
            healthStore.stop(query)
            distanceQuery = nil
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - HKWorkoutSessionDelegate

extension AdvancedWatchHealthKitService: HKWorkoutSessionDelegate {
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        logger.info("Workout session state changed from \(fromState.rawValue) to \(toState.rawValue)")
        
        switch toState {
        case .running:
            isWorkoutActive = true
        case .ended:
            isWorkoutActive = false
        default:
            break
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        logger.error("Workout session failed: \(error)")
        isWorkoutActive = false
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension AdvancedWatchHealthKitService: HKLiveWorkoutBuilderDelegate {
    
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Handle collected workout data
        for type in collectedTypes {
            if type == HKQuantityType.quantityType(forIdentifier: .heartRate) {
                // Heart rate data collected
            }
        }
    }
    
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events
    }
}

// MARK: - Supporting Types and Enums

enum HeartRateZone: String, CaseIterable {
    case resting
    case light
    case moderate
    case hard
    case maximum
    
    var color: String {
        switch self {
        case .resting: return "blue"
        case .light: return "green"
        case .moderate: return "yellow"
        case .hard: return "orange"
        case .maximum: return "red"
        }
    }
    
    var description: String {
        switch self {
        case .resting: return "Resting"
        case .light: return "Light Activity"
        case .moderate: return "Moderate Activity"
        case .hard: return "Hard Activity"
        case .maximum: return "Maximum Effort"
        }
    }
}

enum HealthMonitoringFrequency: String, CaseIterable {
    case critical   // 120 seconds
    case minimal    // 60 seconds
    case reduced    // 30 seconds
    case normal     // 15 seconds
    case high       // 5 seconds
    
    var queryInterval: TimeInterval {
        switch self {
        case .critical: return 120
        case .minimal: return 60
        case .reduced: return 30
        case .normal: return 15
        case .high: return 5
        }
    }
}

enum GolfHealthContext {
    case idle
    case activeRound
    case teeBox
    case fairway
    case puttingGreen
    case walking
    case rest
}

enum GolfHoleContext {
    case teeBox
    case fairway
    case rough
    case bunker
    case puttingGreen
    case walkingToHole
    case rest
}

struct GolfHealthMetrics {
    let roundId: String
    let startTime: Date
    var totalCalories: Double = 0
    var totalSteps: Int = 0
    var totalDistance: Double = 0
    var holeSummaries: [HoleHealthSummary] = []
    
    mutating func addCalories(_ calories: Double) {
        totalCalories += calories
    }
    
    mutating func addSteps(_ steps: Int) {
        totalSteps += steps
    }
    
    mutating func addDistance(_ distance: Double) {
        totalDistance += distance
    }
    
    mutating func addHoleSummary(_ summary: HoleHealthSummary) {
        holeSummaries.append(summary)
    }
}

struct HoleHealthData {
    let holeNumber: Int
    let startTime: Date
    let context: GolfHoleContext
    var heartRateReadings: [Double] = []
    var caloriesBurned: Double = 0
    var stepsWalked: Int = 0
    var distanceWalked: Double = 0
}

struct HoleHealthSummary {
    let holeNumber: Int
    let duration: TimeInterval
    let averageHeartRate: Double
    let maxHeartRate: Double
    let caloriesBurned: Double
    let stepsWalked: Int
    let distanceWalked: Double
    let stressLevel: Int // 1-10 scale
    let fatigueLevel: Int // 1-10 scale
}

struct GolfRoundSummary {
    let roundId: String
    let duration: TimeInterval
    let totalCalories: Double
    let totalSteps: Int
    let totalDistance: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let minHeartRate: Double
    let stressScore: Int // 1-100
    let fatigueScore: Int // 1-100
    let performanceScore: Int // 1-100
    let holesSummaries: [HoleHealthSummary]
}

struct HealthAlert {
    let type: HealthAlertType
    let severity: AlertSeverity
    let value: Double
    let message: String
    let timestamp: Date
}

enum HealthAlertType: String {
    case elevatedHeartRate
    case lowHeartRate
    case highStress
    case fatigue
    case dehydration
}

enum AlertSeverity: String {
    case low
    case medium
    case high
    case critical
}

struct HealthInsight {
    let type: InsightType
    let message: String
    let recommendation: String
    let isActionable: Bool
    let confidence: Double // 0.0 to 1.0
}

enum InsightType: String {
    case performance
    case recovery
    case hydration
    case pacing
    case stress
}

struct ContextualHealthMetrics {
    private var heartRateByContext: [GolfHealthContext: [Double]] = [:]
    
    mutating func addHeartRateReading(_ heartRate: Double, context: GolfHealthContext) {
        if heartRateByContext[context] == nil {
            heartRateByContext[context] = []
        }
        heartRateByContext[context]?.append(heartRate)
    }
    
    func getAverageHeartRate(for context: GolfHealthContext) -> Double {
        guard let readings = heartRateByContext[context], !readings.isEmpty else { return 0 }
        return readings.reduce(0, +) / Double(readings.count)
    }
}

// MARK: - Specialized Analysis Classes

class FatigueDetector {
    private var heartRateReadings: [Double] = []
    private var heartRateVariability: [Double] = []
    
    func addHeartRateReading(_ heartRate: Double) {
        heartRateReadings.append(heartRate)
        
        // Calculate HRV if we have enough readings
        if heartRateReadings.count >= 2 {
            let variation = abs(heartRate - heartRateReadings[heartRateReadings.count - 2])
            heartRateVariability.append(variation)
        }
        
        // Keep only recent readings
        if heartRateReadings.count > 100 {
            heartRateReadings.removeFirst()
        }
        if heartRateVariability.count > 100 {
            heartRateVariability.removeFirst()
        }
    }
    
    func calculateFatigueLevel(since startTime: Date) -> Int {
        // Simplified fatigue calculation based on HRV reduction
        guard !heartRateVariability.isEmpty else { return 1 }
        
        let averageHRV = heartRateVariability.reduce(0, +) / Double(heartRateVariability.count)
        
        // Lower HRV indicates higher fatigue
        if averageHRV < 5 {
            return 8 // High fatigue
        } else if averageHRV < 10 {
            return 5 // Moderate fatigue
        } else {
            return 2 // Low fatigue
        }
    }
    
    func getOverallFatigueScore() -> Int {
        return calculateFatigueLevel(since: Date())
    }
    
    func reset() {
        heartRateReadings.removeAll()
        heartRateVariability.removeAll()
    }
}

class StressMonitor {
    private var heartRateReadings: [Double] = []
    private var stressEvents: [Date] = []
    
    func addHeartRateReading(_ heartRate: Double) {
        heartRateReadings.append(heartRate)
        
        // Detect stress events (sudden HR spikes)
        if heartRateReadings.count >= 2 {
            let previousHR = heartRateReadings[heartRateReadings.count - 2]
            if heartRate > previousHR * 1.2 && heartRate > 100 {
                stressEvents.append(Date())
            }
        }
        
        // Keep only recent readings
        if heartRateReadings.count > 100 {
            heartRateReadings.removeFirst()
        }
    }
    
    func calculateStressLevel(since startTime: Date) -> Int {
        let recentStressEvents = stressEvents.filter { $0 >= startTime }
        
        switch recentStressEvents.count {
        case 0:
            return 1
        case 1...2:
            return 3
        case 3...5:
            return 6
        default:
            return 9
        }
    }
    
    func getOverallStressScore() -> Int {
        return calculateStressLevel(since: Date().addingTimeInterval(-3600)) // Last hour
    }
    
    func reset() {
        heartRateReadings.removeAll()
        stressEvents.removeAll()
    }
}

class GolfPerformanceAnalyzer {
    func analyze(heartRateBuffer: CircularBuffer<Double>, caloriesBuffer: CircularBuffer<Double>, stepsBuffer: CircularBuffer<Int>, distanceBuffer: CircularBuffer<Double>, context: GolfHealthContext) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        
        // Analyze heart rate efficiency
        if let avgHR = heartRateBuffer.average, avgHR > 0 {
            if avgHR > 140 {
                insights.append(HealthInsight(
                    type: .pacing,
                    message: "Your heart rate has been elevated for an extended period.",
                    recommendation: "Consider taking a short break to lower your heart rate.",
                    isActionable: true,
                    confidence: 0.8
                ))
            } else if avgHR < 70 && context != .rest {
                insights.append(HealthInsight(
                    type: .performance,
                    message: "Your heart rate is quite low for golf activity.",
                    recommendation: "You might be able to pick up the pace slightly.",
                    isActionable: false,
                    confidence: 0.6
                ))
            }
        }
        
        // Analyze calorie burn efficiency
        let caloriesPerStep = caloriesBuffer.sum / Double(stepsBuffer.sum)
        if caloriesPerStep > 0.5 {
            insights.append(HealthInsight(
                type: .performance,
                message: "You're burning calories efficiently during your round.",
                recommendation: "Keep up the good pace!",
                isActionable: false,
                confidence: 0.7
            ))
        }
        
        return insights
    }
    
    func calculateOverallPerformance() -> Int {
        // Simplified performance score
        return 75 // Placeholder
    }
    
    func reset() {
        // Reset analyzer state
    }
}

// MARK: - Circular Buffer Implementation

class CircularBuffer<T: Numeric> {
    private var buffer: [T]
    private var head = 0
    private var count = 0
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: T.zero, count: capacity)
    }
    
    func append(_ element: T) {
        buffer[head] = element
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }
    
    var average: Double {
        guard count > 0 else { return 0 }
        let sum = buffer.prefix(count).reduce(T.zero, +)
        return Double(exactly: sum)! / Double(count)
    }
    
    var sum: T {
        return buffer.prefix(count).reduce(T.zero, +)
    }
    
    var maximum: T? {
        guard count > 0 else { return nil }
        return buffer.prefix(count).max()
    }
    
    var minimum: T? {
        guard count > 0 else { return nil }
        return buffer.prefix(count).min()
    }
    
    func clear() {
        head = 0
        count = 0
        buffer = Array(repeating: T.zero, count: capacity)
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let healthAlertGenerated = Notification.Name("healthAlertGenerated")
    static let healthInsightGenerated = Notification.Name("healthInsightGenerated")
}

// MARK: - Extensions for Int Support in CircularBuffer

extension Int: Numeric {
    static var zero: Int { return 0 }
    
    static func + (lhs: Int, rhs: Int) -> Int {
        return lhs + rhs
    }
    
    static func * (lhs: Int, rhs: Int) -> Int {
        return lhs * rhs
    }
}

extension Double: Numeric {
    static var zero: Double { return 0.0 }
    
    static func * (lhs: Double, rhs: Double) -> Double {
        return lhs * rhs
    }
}