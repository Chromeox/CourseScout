import Foundation
import WatchKit
import WatchConnectivity
import HealthKit
import CoreLocation
import os.log
import Combine

// MARK: - Enhanced Watch Sync Manager with Battery Optimization

@MainActor
final class EnhancedWatchSyncManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = EnhancedWatchSyncManager()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "EnhancedSync")
    private let session = WCSession.default
    private let batteryManager = OptimizedBatteryManager.shared
    
    // Published state
    @Published var syncState: SyncState = .idle
    @Published var connectionQuality: ConnectionQuality = .unknown
    @Published var lastSyncTime: Date?
    @Published var pendingSyncCount: Int = 0
    
    // Golf data
    @Published var activeRound: ActiveGolfRound?
    @Published var currentScorecard: SharedScorecard?
    @Published var currentCourse: SharedGolfCourse?
    @Published var currentHoleInfo: SharedHoleInfo?
    
    // Sync optimization
    private let intelligentScheduler = IntelligentSyncScheduler()
    private let dataCompressor = AdvancedDataCompressor()
    private let conflictResolver = SyncConflictResolver()
    private let cacheManager = WatchCacheService.shared
    
    // Priority queue management
    private let priorityQueue = SyncPriorityQueue()
    private var syncTimer: Timer?
    private var backgroundTask: WKBackgroundTask?
    
    // Performance tracking
    private var syncMetrics = SyncMetrics()
    private var lastSuccessfulSync: Date?
    private var consecutiveFailures = 0
    
    // Health data integration
    private let healthStore = HKHealthStore()
    private var healthDataCollector: HealthDataCollector?
    
    // Context awareness
    private var currentGolfContext: GolfContext = .idle
    private var locationManager: CLLocationManager?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        setupWatchConnectivity()
        setupHealthDataCollection()
        setupLocationServices()
        observeBatteryState()
    }
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            logger.warning("WatchConnectivity not supported")
            return
        }
        
        session.delegate = self
        session.activate()
        
        logger.info("EnhancedWatchSyncManager initialized")
    }
    
    // MARK: - Public Interface
    
    /// Start intelligent synchronization with battery optimization
    func startIntelligentSync() {
        intelligentScheduler.startScheduling { [weak self] schedule in
            Task {
                await self?.performScheduledSync(schedule)
            }
        }
        
        // Monitor battery state for adaptive sync
        batteryManager.startBatteryMonitoring()
        
        logger.info("Intelligent sync started")
    }
    
    /// Stop all synchronization
    func stopSync() {
        intelligentScheduler.stopScheduling()
        syncTimer?.invalidate()
        syncTimer = nil
        
        logger.info("Sync stopped")
    }
    
    // MARK: - Golf Round Management
    
    func startGolfRound(_ round: ActiveGolfRound) async {
        self.activeRound = round
        currentGolfContext = .activeRound
        
        // Configure sync for golf round
        await configureSyncForGolfRound(round)
        
        // Start health data collection
        await startHealthDataCollection(for: round)
        
        // Sync initial round data
        await syncRoundData(round, priority: .high)
        
        logger.info("Golf round started: \(round.courseName)")
    }
    
    func updateHoleProgress(hole: Int, score: Int) async {
        guard let round = activeRound else { return }
        
        // Update context
        currentGolfContext = determineGolfContext(hole: hole)
        
        // Update scorecard
        await updateScorecard(hole: hole, score: score)
        
        // Sync with adaptive priority
        let priority = determineSyncPriority(for: currentGolfContext)
        await syncScoreUpdate(hole: hole, score: score, priority: priority)
    }
    
    func endGolfRound() async {
        guard let round = activeRound else { return }
        
        // Final sync with all data
        await performFinalRoundSync(round)
        
        // Stop health data collection
        healthDataCollector?.stopCollection()
        
        // Reset context
        currentGolfContext = .idle
        activeRound = nil
        currentScorecard = nil
        
        logger.info("Golf round ended")
    }
    
    // MARK: - Intelligent Sync Scheduling
    
    private func performScheduledSync(_ schedule: SyncSchedule) async {
        // Check battery state first
        let batteryLevel = batteryManager.batteryLevel
        let powerMode = batteryManager.powerSavingMode
        
        // Adjust sync based on battery
        guard shouldPerformSync(batteryLevel: batteryLevel, powerMode: powerMode, schedule: schedule) else {
            logger.debug("Sync skipped due to battery constraints")
            return
        }
        
        syncState = .syncing
        
        do {
            // Perform context-aware sync
            await performContextAwareSync()
            
            lastSyncTime = Date()
            lastSuccessfulSync = Date()
            consecutiveFailures = 0
            syncState = .completed
            
            // Update metrics
            syncMetrics.recordSuccessfulSync()
            
        } catch {
            consecutiveFailures += 1
            syncState = .failed(error)
            
            // Update metrics
            syncMetrics.recordFailedSync(error: error)
            
            // Handle failure with backoff
            handleSyncFailure(error: error)
        }
    }
    
    private func performContextAwareSync() async {
        switch currentGolfContext {
        case .activeRound:
            await syncActiveRoundData()
        case .teeBox:
            await syncTeeBoxData()
        case .fairway:
            await syncFairwayData()
        case .puttingGreen:
            await syncPuttingData()
        case .walking:
            await syncWalkingData()
        case .rest:
            await syncMinimalData()
        case .idle:
            await syncCachedData()
        }
    }
    
    // MARK: - Battery-Conscious Data Transfer
    
    private func syncActiveRoundData() async {
        guard let round = activeRound else { return }
        
        // Compress data for transfer
        let compressedData = compressRoundData(round)
        
        // Send with appropriate method based on battery
        if batteryManager.powerSavingMode == .extreme {
            // Use application context for minimal battery impact
            updateApplicationContext(compressedData)
        } else if session.isReachable {
            // Use direct message for real-time sync
            await sendMessage(compressedData, priority: .normal)
        } else {
            // Queue for later delivery
            queueForLaterDelivery(compressedData)
        }
    }
    
    private func syncTeeBoxData() async {
        // High priority sync for tee box (accurate GPS, club selection)
        guard let holeInfo = currentHoleInfo else { return }
        
        let data: [String: Any] = [
            "type": "teeBox",
            "hole": holeInfo.holeNumber,
            "par": holeInfo.par,
            "distance": holeInfo.distance,
            "location": getCurrentLocation()
        ]
        
        await sendMessage(data, priority: .high)
    }
    
    private func syncFairwayData() async {
        // Balanced sync for fairway play
        let data: [String: Any] = [
            "type": "fairway",
            "location": getCurrentLocation(),
            "healthMetrics": await collectHealthMetrics()
        ]
        
        await sendMessage(data, priority: .normal)
    }
    
    private func syncPuttingData() async {
        // Minimal sync when putting (low movement, stable location)
        let data: [String: Any] = [
            "type": "putting",
            "hole": currentHoleInfo?.holeNumber ?? 0
        ]
        
        await sendMessage(data, priority: .low)
    }
    
    private func syncWalkingData() async {
        // Periodic sync while walking between holes
        let data: [String: Any] = [
            "type": "walking",
            "steps": await getStepCount(),
            "distance": await getDistanceWalked(),
            "calories": await getCaloriesBurned()
        ]
        
        await sendMessage(data, priority: .low)
    }
    
    private func syncMinimalData() async {
        // Minimal sync during rest periods
        let data: [String: Any] = [
            "type": "rest",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        updateApplicationContext(data)
    }
    
    private func syncCachedData() async {
        // Sync any cached data when idle
        if let cachedData = await cacheManager.getPendingSyncData() {
            await sendBatchedData(cachedData)
        }
    }
    
    // MARK: - Message Sending with Compression
    
    private func sendMessage(_ data: [String: Any], priority: MessagePriority) async {
        let message = SyncMessage(
            id: UUID().uuidString,
            type: .data,
            priority: priority,
            data: data,
            timestamp: Date()
        )
        
        // Add to priority queue
        priorityQueue.enqueue(message)
        
        // Process queue based on conditions
        await processMessageQueue()
    }
    
    private func processMessageQueue() async {
        guard session.isReachable else {
            logger.debug("Session not reachable, queuing messages")
            return
        }
        
        // Get batch based on battery state
        let batchSize = determineBatchSize()
        let messages = priorityQueue.dequeueBatch(maxCount: batchSize)
        
        for message in messages {
            await sendSingleMessage(message)
        }
    }
    
    private func sendSingleMessage(_ message: SyncMessage) async {
        do {
            // Compress if beneficial
            let payload = try await prepareMessagePayload(message)
            
            // Send with appropriate method
            if message.priority == .critical {
                // Send immediately with reply handler
                try await sendMessageWithReply(payload)
            } else {
                // Send without waiting for reply
                session.sendMessage(payload)
            }
            
            syncMetrics.recordMessageSent(size: payload.count)
            
        } catch {
            logger.error("Failed to send message: \(error)")
            
            // Re-queue if not expired
            if !message.isExpired {
                priorityQueue.enqueue(message)
            }
        }
    }
    
    // MARK: - Health Data Collection
    
    private func setupHealthDataCollection() {
        healthDataCollector = HealthDataCollector(healthStore: healthStore)
        
        healthDataCollector?.onMetricsUpdate = { [weak self] metrics in
            Task { @MainActor in
                await self?.handleHealthMetricsUpdate(metrics)
            }
        }
    }
    
    private func startHealthDataCollection(for round: ActiveGolfRound) async {
        // Request necessary permissions
        await requestHealthPermissions()
        
        // Start collecting golf-relevant metrics
        healthDataCollector?.startCollection(
            metrics: [.heartRate, .activeEnergyBurned, .distanceWalkingRunning, .stepCount],
            updateInterval: determineHealthUpdateInterval()
        )
    }
    
    private func handleHealthMetricsUpdate(_ metrics: HealthMetrics) async {
        // Process health metrics for golf insights
        if let round = activeRound {
            // Check for fatigue or stress indicators
            if metrics.heartRate > round.averageHeartRate * 1.3 {
                // Suggest rest
                await sendHealthAlert(type: .elevatedHeartRate)
            }
            
            // Update round statistics
            round.updateHealthStats(metrics)
            
            // Sync health data based on priority
            if shouldSyncHealthData(metrics) {
                await syncHealthMetrics(metrics)
            }
        }
    }
    
    // MARK: - Location Services
    
    private func setupLocationServices() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.requestWhenInUseAuthorization()
    }
    
    private func getCurrentLocation() -> [String: Any] {
        guard let location = locationManager?.location else {
            return [:]
        }
        
        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "altitude": location.altitude,
            "timestamp": location.timestamp.timeIntervalSince1970
        ]
    }
    
    // MARK: - Battery Optimization
    
    private func observeBatteryState() {
        batteryManager.$powerSavingMode
            .sink { [weak self] mode in
                self?.adjustSyncForPowerMode(mode)
            }
            .store(in: &cancellables)
        
        batteryManager.$batteryLevel
            .sink { [weak self] level in
                self?.adjustSyncForBatteryLevel(level)
            }
            .store(in: &cancellables)
    }
    
    private func adjustSyncForPowerMode(_ mode: PowerSavingMode) {
        switch mode {
        case .normal:
            intelligentScheduler.setSyncInterval(60) // 1 minute
        case .conservative:
            intelligentScheduler.setSyncInterval(120) // 2 minutes
        case .aggressive:
            intelligentScheduler.setSyncInterval(300) // 5 minutes
        case .extreme:
            intelligentScheduler.setSyncInterval(600) // 10 minutes
        }
    }
    
    private func adjustSyncForBatteryLevel(_ level: Float) {
        if level < 0.10 {
            // Critical battery - sync only essential data
            priorityQueue.setPriorityThreshold(.critical)
        } else if level < 0.20 {
            // Low battery - sync high priority only
            priorityQueue.setPriorityThreshold(.high)
        } else {
            // Normal battery - sync all priorities
            priorityQueue.setPriorityThreshold(.low)
        }
    }
    
    // MARK: - Helper Methods
    
    private func configureSyncForGolfRound(_ round: ActiveGolfRound) async {
        // Estimate round duration
        let estimatedDuration = round.totalHoles == 18 ? 4.5 * 3600 : 2.5 * 3600
        
        // Configure intelligent scheduler
        intelligentScheduler.configureForGolfRound(
            duration: estimatedDuration,
            batteryBudget: batteryManager.batteryLevel
        )
        
        // Pre-cache course data
        if let course = await fetchCourseData(courseId: round.courseId) {
            self.currentCourse = course
            await cacheManager.cacheCourse(course)
        }
    }
    
    private func determineGolfContext(hole: Int) -> GolfContext {
        // Determine context based on location and activity
        guard let location = locationManager?.location,
              let holeInfo = currentCourse?.holes.first(where: { $0.holeNumber == hole }) else {
            return .activeRound
        }
        
        let distanceToGreen = calculateDistance(from: location.coordinate, to: holeInfo.greenLocation)
        
        if distanceToGreen < 20 {
            return .puttingGreen
        } else if distanceToGreen > holeInfo.distance * 0.8 {
            return .teeBox
        } else {
            return .fairway
        }
    }
    
    private func determineSyncPriority(for context: GolfContext) -> MessagePriority {
        switch context {
        case .teeBox:
            return .high // Need accurate data for club selection
        case .fairway:
            return .normal
        case .puttingGreen:
            return .low // Minimal movement, less critical
        case .walking:
            return .low
        case .rest:
            return .low
        case .activeRound:
            return .normal
        case .idle:
            return .low
        }
    }
    
    private func shouldPerformSync(batteryLevel: Float, powerMode: PowerSavingMode, schedule: SyncSchedule) -> Bool {
        // Don't sync if battery is critical unless data is critical
        if batteryLevel < 0.05 && schedule.priority != .critical {
            return false
        }
        
        // Check if enough time has passed since last sync
        if let lastSync = lastSyncTime {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            let minInterval = getMinSyncInterval(for: powerMode)
            
            if timeSinceLastSync < minInterval && schedule.priority != .critical {
                return false
            }
        }
        
        return true
    }
    
    private func getMinSyncInterval(for powerMode: PowerSavingMode) -> TimeInterval {
        switch powerMode {
        case .normal:
            return 30 // 30 seconds
        case .conservative:
            return 60 // 1 minute
        case .aggressive:
            return 180 // 3 minutes
        case .extreme:
            return 300 // 5 minutes
        }
    }
    
    private func determineBatchSize() -> Int {
        switch batteryManager.powerSavingMode {
        case .normal:
            return 10
        case .conservative:
            return 5
        case .aggressive:
            return 3
        case .extreme:
            return 1
        }
    }
    
    private func determineHealthUpdateInterval() -> TimeInterval {
        switch batteryManager.powerSavingMode {
        case .normal:
            return 15 // 15 seconds
        case .conservative:
            return 30 // 30 seconds
        case .aggressive:
            return 60 // 1 minute
        case .extreme:
            return 120 // 2 minutes
        }
    }
    
    private func shouldSyncHealthData(_ metrics: HealthMetrics) -> Bool {
        // Sync if significant change or time threshold
        if let lastHeartRate = activeRound?.lastHeartRate {
            let change = abs(metrics.heartRate - lastHeartRate)
            if change > 10 {
                return true // Significant change
            }
        }
        
        // Check time since last health sync
        if let lastHealthSync = syncMetrics.lastHealthDataSync {
            let timeSince = Date().timeIntervalSince(lastHealthSync)
            return timeSince > determineHealthUpdateInterval()
        }
        
        return true
    }
    
    private func compressRoundData(_ round: ActiveGolfRound) -> [String: Any] {
        // Compress round data for efficient transfer
        let essential: [String: Any] = [
            "id": round.id,
            "hole": round.currentHole,
            "score": round.currentScore,
            "time": Date().timeIntervalSince1970
        ]
        
        return dataCompressor.compress(essential) ?? essential
    }
    
    private func handleSyncFailure(error: Error) {
        // Implement exponential backoff
        let backoffInterval = min(pow(2.0, Double(consecutiveFailures)) * 30, 600)
        
        intelligentScheduler.scheduleRetry(after: backoffInterval)
        
        logger.warning("Sync failed, retrying in \(backoffInterval) seconds")
    }
    
    private func queueForLaterDelivery(_ data: [String: Any]) {
        // Store in cache for later sync
        Task {
            await cacheManager.storePendingSync(data)
            pendingSyncCount = await cacheManager.getPendingSyncCount()
        }
    }
    
    private func updateApplicationContext(_ data: [String: Any]) {
        do {
            try session.updateApplicationContext(data)
        } catch {
            logger.error("Failed to update application context: \(error)")
        }
    }
    
    private func prepareMessagePayload(_ message: SyncMessage) async throws -> [String: Any] {
        var payload = message.data
        payload["messageId"] = message.id
        payload["timestamp"] = message.timestamp.timeIntervalSince1970
        payload["priority"] = message.priority.rawValue
        
        // Compress if beneficial
        if let compressed = dataCompressor.compressIfBeneficial(payload) {
            return ["compressed": true, "data": compressed]
        }
        
        return payload
    }
    
    private func sendMessageWithReply(_ payload: [String: Any]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(payload, replyHandler: { _ in
                continuation.resume()
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - WCSessionDelegate

extension EnhancedWatchSyncManager: WCSessionDelegate {
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("Session activation failed: \(error)")
        } else {
            logger.info("Session activated: \(activationState.rawValue)")
            
            // Start initial sync if reachable
            if session.isReachable {
                Task {
                    await performInitialSync()
                }
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        connectionQuality = session.isReachable ? .good : .poor
        
        if session.isReachable {
            // Process any queued messages
            Task {
                await processMessageQueue()
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleReceivedMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        let response = handleReceivedMessageWithReply(message)
        replyHandler(response)
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleApplicationContext(applicationContext)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        handleUserInfo(userInfo)
    }
}

// MARK: - CLLocationManagerDelegate

extension EnhancedWatchSyncManager: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Handle location updates with battery optimization
        guard let location = locations.last else { return }
        
        // Only sync if significant change or context requires it
        if shouldSyncLocation(location) {
            Task {
                await syncLocationUpdate(location)
            }
        }
    }
    
    private func shouldSyncLocation(_ location: CLLocation) -> Bool {
        // Sync based on context and movement
        switch currentGolfContext {
        case .teeBox, .fairway:
            return true // Always sync during active play
        case .puttingGreen:
            return false // No need for frequent updates
        case .walking:
            // Sync every 50 meters
            if let lastLocation = syncMetrics.lastLocationSync {
                return location.distance(from: lastLocation) > 50
            }
        default:
            return false
        }
        
        return true
    }
    
    private func syncLocationUpdate(_ location: CLLocation) async {
        let locationData: [String: Any] = [
            "type": "location",
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "timestamp": location.timestamp.timeIntervalSince1970
        ]
        
        await sendMessage(locationData, priority: .normal)
        syncMetrics.lastLocationSync = location
    }
}

// MARK: - Message Handling

private extension EnhancedWatchSyncManager {
    
    func handleReceivedMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "roundStart":
            if let roundData = message["round"] as? [String: Any] {
                handleRoundStart(roundData)
            }
            
        case "scoreUpdate":
            if let scoreData = message["score"] as? [String: Any] {
                handleScoreUpdate(scoreData)
            }
            
        case "courseData":
            if let courseData = message["course"] as? [String: Any] {
                handleCourseData(courseData)
            }
            
        case "syncRequest":
            Task {
                await handleSyncRequest(message["request"] as? String)
            }
            
        default:
            logger.debug("Received message type: \(type)")
        }
    }
    
    func handleReceivedMessageWithReply(_ message: [String: Any]) -> [String: Any] {
        guard let type = message["type"] as? String else {
            return ["success": false, "error": "Invalid message type"]
        }
        
        switch type {
        case "ping":
            return ["type": "pong", "timestamp": Date().timeIntervalSince1970]
            
        case "batteryStatus":
            return [
                "level": batteryManager.batteryLevel,
                "mode": batteryManager.powerSavingMode.rawValue,
                "estimated": batteryManager.estimatedRemainingTime
            ]
            
        case "syncStatus":
            return [
                "state": syncState.rawValue,
                "lastSync": lastSyncTime?.timeIntervalSince1970 ?? 0,
                "pending": pendingSyncCount
            ]
            
        default:
            return ["success": true]
        }
    }
    
    func handleApplicationContext(_ context: [String: Any]) {
        // Handle background updates
        logger.debug("Received application context")
        
        // Update cached data
        Task {
            await cacheManager.updateFromApplicationContext(context)
        }
    }
    
    func handleUserInfo(_ userInfo: [String: Any]) {
        // Handle guaranteed delivery messages
        logger.debug("Received user info")
    }
    
    func handleRoundStart(_ data: [String: Any]) {
        // Create round from received data
        if let round = ActiveGolfRound(from: data) {
            Task {
                await startGolfRound(round)
            }
        }
    }
    
    func handleScoreUpdate(_ data: [String: Any]) {
        // Update scorecard from received data
        if let hole = data["hole"] as? Int,
           let score = data["score"] as? Int {
            Task {
                await updateHoleProgress(hole: hole, score: score)
            }
        }
    }
    
    func handleCourseData(_ data: [String: Any]) {
        // Cache course data
        if let course = SharedGolfCourse(from: data) {
            self.currentCourse = course
            Task {
                await cacheManager.cacheCourse(course)
            }
        }
    }
    
    func handleSyncRequest(_ request: String?) async {
        guard let request = request else { return }
        
        switch request {
        case "full":
            await performInitialSync()
        case "health":
            if let metrics = await collectHealthMetrics() {
                await syncHealthMetrics(metrics)
            }
        case "location":
            if let location = locationManager?.location {
                await syncLocationUpdate(location)
            }
        default:
            break
        }
    }
    
    func performInitialSync() async {
        syncState = .syncing
        
        // Sync all essential data
        if let round = activeRound {
            await syncRoundData(round, priority: .high)
        }
        
        if let scorecard = currentScorecard {
            await syncScorecard(scorecard, priority: .normal)
        }
        
        // Sync cached data
        await syncCachedData()
        
        syncState = .completed
        lastSyncTime = Date()
    }
    
    func syncRoundData(_ round: ActiveGolfRound, priority: MessagePriority) async {
        let data = round.toDictionary()
        await sendMessage(["type": "round", "data": data], priority: priority)
    }
    
    func syncScorecard(_ scorecard: SharedScorecard, priority: MessagePriority) async {
        let data = scorecard.toDictionary()
        await sendMessage(["type": "scorecard", "data": data], priority: priority)
    }
    
    func syncScoreUpdate(hole: Int, score: Int, priority: MessagePriority) async {
        let data: [String: Any] = [
            "type": "scoreUpdate",
            "hole": hole,
            "score": score,
            "timestamp": Date().timeIntervalSince1970
        ]
        await sendMessage(data, priority: priority)
    }
    
    func updateScorecard(hole: Int, score: Int) async {
        if currentScorecard == nil {
            currentScorecard = SharedScorecard(roundId: activeRound?.id ?? "")
        }
        
        currentScorecard?.updateHole(hole, score: score)
        
        // Cache updated scorecard
        await cacheManager.cacheScorecard(currentScorecard!)
    }
    
    func performFinalRoundSync(_ round: ActiveGolfRound) async {
        // Sync all round data with high priority
        await syncRoundData(round, priority: .high)
        
        if let scorecard = currentScorecard {
            await syncScorecard(scorecard, priority: .high)
        }
        
        // Sync final health metrics
        if let metrics = await collectHealthMetrics() {
            await syncHealthMetrics(metrics, priority: .high)
        }
    }
    
    func collectHealthMetrics() async -> HealthMetrics? {
        return await healthDataCollector?.getCurrentMetrics()
    }
    
    func syncHealthMetrics(_ metrics: HealthMetrics, priority: MessagePriority = .normal) async {
        let data = metrics.toDictionary()
        await sendMessage(["type": "health", "data": data], priority: priority)
        syncMetrics.lastHealthDataSync = Date()
    }
    
    func sendHealthAlert(type: HealthAlertType) async {
        let alert: [String: Any] = [
            "type": "healthAlert",
            "alertType": type.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        await sendMessage(alert, priority: .high)
    }
    
    func requestHealthPermissions() async {
        let types: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: types)
        } catch {
            logger.error("Health permission request failed: \(error)")
        }
    }
    
    func fetchCourseData(courseId: String) async -> SharedGolfCourse? {
        // First check cache
        if let cached = await cacheManager.getCachedCourse(id: courseId) {
            return cached
        }
        
        // Request from iPhone
        let request: [String: Any] = [
            "type": "dataRequest",
            "requestType": "course",
            "courseId": courseId
        ]
        
        // Send request with reply handler
        return await withCheckedContinuation { continuation in
            session.sendMessage(request, replyHandler: { response in
                if let courseData = response["data"] as? [String: Any],
                   let course = SharedGolfCourse(from: courseData) {
                    continuation.resume(returning: course)
                } else {
                    continuation.resume(returning: nil)
                }
            }, errorHandler: { _ in
                continuation.resume(returning: nil)
            })
        }
    }
    
    func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }
    
    func sendBatchedData(_ data: [[String: Any]]) async {
        let batch: [String: Any] = [
            "type": "batch",
            "messages": data,
            "count": data.count
        ]
        
        await sendMessage(batch, priority: .low)
    }
    
    func getStepCount() async -> Int {
        return await healthDataCollector?.getTodayStepCount() ?? 0
    }
    
    func getDistanceWalked() async -> Double {
        return await healthDataCollector?.getTodayDistance() ?? 0
    }
    
    func getCaloriesBurned() async -> Double {
        return await healthDataCollector?.getTodayCalories() ?? 0
    }
}

// MARK: - Supporting Types

enum SyncState: String {
    case idle
    case syncing
    case completed
    case failed(Error)
    
    var rawValue: String {
        switch self {
        case .idle: return "idle"
        case .syncing: return "syncing"
        case .completed: return "completed"
        case .failed: return "failed"
        }
    }
}

enum ConnectionQuality {
    case unknown
    case excellent
    case good
    case poor
    case disconnected
}

enum GolfContext {
    case idle
    case activeRound
    case teeBox
    case fairway
    case puttingGreen
    case walking
    case rest
}

struct SyncMessage {
    let id: String
    let type: MessageType
    let priority: MessagePriority
    let data: [String: Any]
    let timestamp: Date
    
    var isExpired: Bool {
        return Date().timeIntervalSince(timestamp) > 300 // 5 minutes
    }
    
    enum MessageType {
        case data
        case health
        case location
        case score
        case alert
    }
}

struct SyncSchedule {
    let interval: TimeInterval
    let priority: MessagePriority
    let context: GolfContext
}

struct SyncMetrics {
    var totalSyncs: Int = 0
    var successfulSyncs: Int = 0
    var failedSyncs: Int = 0
    var totalDataTransferred: Int = 0
    var averageLatency: TimeInterval = 0
    var lastHealthDataSync: Date?
    var lastLocationSync: CLLocation?
    
    mutating func recordSuccessfulSync() {
        totalSyncs += 1
        successfulSyncs += 1
    }
    
    mutating func recordFailedSync(error: Error) {
        totalSyncs += 1
        failedSyncs += 1
    }
    
    mutating func recordMessageSent(size: Int) {
        totalDataTransferred += size
    }
}

struct HealthMetrics {
    let heartRate: Double
    let averageHeartRate: Double
    let caloriesBurned: Double
    let stepCount: Int
    let distanceWalked: Double
    
    func toDictionary() -> [String: Any] {
        return [
            "heartRate": heartRate,
            "averageHeartRate": averageHeartRate,
            "caloriesBurned": caloriesBurned,
            "stepCount": stepCount,
            "distanceWalked": distanceWalked
        ]
    }
}

enum HealthAlertType: String {
    case elevatedHeartRate
    case lowHeartRate
    case fatigue
    case dehydration
}

// MARK: - Helper Classes

class IntelligentSyncScheduler {
    private var timer: Timer?
    private var syncInterval: TimeInterval = 60
    private var onSchedule: ((SyncSchedule) -> Void)?
    
    func startScheduling(onSchedule: @escaping (SyncSchedule) -> Void) {
        self.onSchedule = onSchedule
        
        timer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { _ in
            let schedule = SyncSchedule(
                interval: self.syncInterval,
                priority: .normal,
                context: .idle
            )
            onSchedule(schedule)
        }
    }
    
    func stopScheduling() {
        timer?.invalidate()
        timer = nil
    }
    
    func setSyncInterval(_ interval: TimeInterval) {
        syncInterval = interval
        
        // Restart timer with new interval
        if timer != nil {
            stopScheduling()
            if let handler = onSchedule {
                startScheduling(onSchedule: handler)
            }
        }
    }
    
    func configureForGolfRound(duration: TimeInterval, batteryBudget: Float) {
        // Calculate optimal sync interval based on battery and duration
        let hoursRemaining = duration / 3600
        let batteryPerHour = batteryBudget / hoursRemaining
        
        if batteryPerHour < 0.15 {
            // Conservative sync for low battery
            syncInterval = 300 // 5 minutes
        } else if batteryPerHour < 0.25 {
            // Moderate sync
            syncInterval = 120 // 2 minutes
        } else {
            // Normal sync
            syncInterval = 60 // 1 minute
        }
    }
    
    func scheduleRetry(after interval: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            if let handler = self?.onSchedule {
                let schedule = SyncSchedule(
                    interval: interval,
                    priority: .high,
                    context: .idle
                )
                handler(schedule)
            }
        }
    }
}

class SyncPriorityQueue {
    private var queue = [SyncMessage]()
    private let lock = NSLock()
    private var priorityThreshold: MessagePriority = .low
    
    func enqueue(_ message: SyncMessage) {
        lock.lock()
        defer { lock.unlock() }
        
        // Only enqueue if meets priority threshold
        if message.priority >= priorityThreshold {
            queue.append(message)
            queue.sort { $0.priority.rawValue > $1.priority.rawValue }
        }
    }
    
    func dequeue() -> SyncMessage? {
        lock.lock()
        defer { lock.unlock() }
        
        return queue.isEmpty ? nil : queue.removeFirst()
    }
    
    func dequeueBatch(maxCount: Int) -> [SyncMessage] {
        lock.lock()
        defer { lock.unlock() }
        
        let count = min(maxCount, queue.count)
        guard count > 0 else { return [] }
        
        let batch = Array(queue.prefix(count))
        queue.removeFirst(count)
        return batch
    }
    
    func setPriorityThreshold(_ threshold: MessagePriority) {
        lock.lock()
        defer { lock.unlock() }
        
        priorityThreshold = threshold
        
        // Remove messages below threshold
        queue.removeAll { $0.priority < threshold }
    }
}

class AdvancedDataCompressor {
    func compress(_ data: [String: Any]) -> [String: Any]? {
        // Implement compression logic
        return data
    }
    
    func compressIfBeneficial(_ data: [String: Any]) -> Data? {
        // Only compress if it reduces size significantly
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else {
            return nil
        }
        
        if jsonData.count > 1024 { // Only compress if > 1KB
            return jsonData.compressed(using: .zlib)
        }
        
        return nil
    }
}

class SyncConflictResolver {
    func resolve(local: Any, remote: Any, type: String) -> Any {
        // Implement conflict resolution logic
        return local
    }
}

class HealthDataCollector {
    private let healthStore: HKHealthStore
    private var queries = [HKQuery]()
    var onMetricsUpdate: ((HealthMetrics) -> Void)?
    
    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }
    
    func startCollection(metrics: [HKQuantityTypeIdentifier], updateInterval: TimeInterval) {
        // Start health data collection queries
    }
    
    func stopCollection() {
        queries.forEach { healthStore.stop($0) }
        queries.removeAll()
    }
    
    func getCurrentMetrics() async -> HealthMetrics? {
        // Fetch current health metrics
        return nil
    }
    
    func getTodayStepCount() async -> Int? {
        // Fetch today's step count
        return nil
    }
    
    func getTodayDistance() async -> Double? {
        // Fetch today's walking distance
        return nil
    }
    
    func getTodayCalories() async -> Double? {
        // Fetch today's active calories
        return nil
    }
}

// MARK: - Extensions for Shared Types

extension ActiveGolfRound {
    var lastHeartRate: Double? { return nil }
    
    mutating func updateHealthStats(_ metrics: HealthMetrics) {
        // Update round with health metrics
    }
    
    init?(from dictionary: [String: Any]) {
        // Initialize from dictionary
        return nil
    }
}

extension SharedScorecard {
    init(roundId: String) {
        self.id = UUID().uuidString
        self.roundId = roundId
        self.holes = []
        self.totalScore = 0
        self.lastUpdated = Date()
    }
    
    mutating func updateHole(_ hole: Int, score: Int) {
        // Update hole score
    }
}

extension SharedGolfCourse {
    init?(from dictionary: [String: Any]) {
        // Initialize from dictionary
        return nil
    }
}

extension SharedHoleInfo {
    var greenLocation: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
}