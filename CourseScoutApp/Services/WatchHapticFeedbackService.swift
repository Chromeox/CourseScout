import Foundation
import WatchConnectivity
import HealthKit

/// Apple Watch haptic feedback service with multi-tenant support
/// Coordinates haptic experiences between iPhone and Apple Watch
/// Integrates with health data for contextual golf course haptics
@MainActor
class WatchHapticFeedbackService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isWatchConnected: Bool = false
    @Published var isHealthDataAuthorized: Bool = false
    @Published var currentHeartRateZone: HeartRateZone = .resting
    @Published var workoutSessionActive: Bool = false
    
    // MARK: - Watch Connectivity
    
    private var session: WCSession?
    private var tenantConfiguration: TenantHapticConfiguration?
    private var tenantPreferences: TenantHapticPreferences = .default
    
    // MARK: - Multi-Tenant Watch Context
    
    @Published var currentTenantContext: WatchTenantContext = .defaultContext
    private var businessTypeHapticPatterns: [WatchBusinessType: [WatchInteractionType: WatchHapticPattern]] = [:]
    private var tenantBrandingPatterns: [String: BrandingHapticPattern] = [:]
    
    // MARK: - Health Integration
    
    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var workoutQuery: HKObserverQuery?
    
    // MARK: - Timer and Milestone Tracking
    
    private var timerStartTime: Date?
    private var milestoneTracker: TimerMilestoneTracker?
    private var lastHeartRateNotification: Date?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupWatchConnectivity()
        setupHealthKitIntegration()
        initializeBusinessTypeHapticPatterns()
    }
    
    // MARK: - Multi-Tenant Context Management
    
    func updateTenantContext(_ context: WatchTenantContext) async {
        currentTenantContext = context
        
        // Update tenant-specific haptic patterns
        await configureTenantHapticPatterns(for: context)
        
        // Send updated context to Apple Watch
        await sendTenantContextToWatch()
        
        print("✅ Updated Watch haptic context for tenant: \(context.tenantId ?? "default")")
    }
    
    private func configureTenantHapticPatterns(for context: WatchTenantContext) async {
        // Configure business type-specific haptic patterns
        let patterns = getBusinessTypeHapticPatterns(for: context.businessType)
        businessTypeHapticPatterns[context.businessType] = patterns
        
        // Configure tenant branding pattern if tenant ID exists
        if let tenantId = context.tenantId {
            let brandingPattern = createTenantBrandingPattern(for: context)
            tenantBrandingPatterns[tenantId] = brandingPattern
        }
    }
    
    private func sendTenantContextToWatch() async {
        guard let session = session, session.isReachable else { return }
        
        let contextData: [String: Any] = [
            "tenantId": currentTenantContext.tenantId as Any,
            "businessType": currentTenantContext.businessType.rawValue,
            "theme": [
                "primaryColor": currentTenantContext.theme.primaryColor,
                "secondaryColor": currentTenantContext.theme.secondaryColor
            ],
            "features": [
                "enableHaptics": currentTenantContext.features.enableHaptics,
                "enablePremiumAnalytics": currentTenantContext.features.enablePremiumAnalytics,
                "enableConcierge": currentTenantContext.features.enableConcierge
            ]
        ]
        
        session.sendMessage(["type": "tenant_context_update", "data": contextData], replyHandler: nil) { error in
            print("❌ Failed to send tenant context to Watch: \(error)")
        }
    }
    
    // MARK: - Public API
    
    func configureTenantHaptics(configuration: TenantHapticConfiguration) async {
        tenantConfiguration = configuration
        tenantPreferences = configuration.preferences
        
        // Send tenant configuration to Apple Watch
        await sendTenantConfigurationToWatch()
        
        print("✅ Configured Watch haptics for tenant: \(configuration.tenantId)")
    }
    
    func playTenantBrandingHaptic() async {
        guard let config = tenantConfiguration,
              tenantPreferences.brandingHapticEnabled,
              tenantPreferences.watchSyncEnabled else { return }
        
        await sendHapticToWatch(.notification, data: [
            "type": "branding",
            "tenantId": config.tenantId,
            "businessType": "\(config.businessType)",
            "pattern": config.brandingSignature.signatureName
        ])
    }
    
    func startGolfRoundTimer() async {
        timerStartTime = Date()
        milestoneTracker = TimerMilestoneTracker()
        workoutSessionActive = true
        
        await sendHapticToWatch(.start, data: [
            "type": "round_start",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        
        // Start monitoring heart rate zones during golf
        startHeartRateMonitoring()
    }
    
    func endGolfRoundTimer() async {
        guard let startTime = timerStartTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        workoutSessionActive = false
        timerStartTime = nil
        
        await sendHapticToWatch(.stop, data: [
            "type": "round_end",
            "duration": duration,
            "milestones": milestoneTracker?.completedMilestones ?? []
        ])
        
        stopHeartRateMonitoring()
        milestoneTracker = nil
    }
    
    func triggerTimerMilestone(_ milestone: TimerMilestone) async {
        guard workoutSessionActive else { return }
        
        milestoneTracker?.recordMilestone(milestone)
        
        let intensity = getMilestoneIntensity(milestone)
        await playMilestoneHaptic(milestone, intensity: intensity)
    }
    
    func triggerHeartRateZoneChange(from oldZone: HeartRateZone, to newZone: HeartRateZone) async {
        currentHeartRateZone = newZone
        
        // Prevent too frequent haptic notifications
        if let lastNotification = lastHeartRateNotification,
           Date().timeIntervalSince(lastNotification) < 30 {
            return
        }
        
        lastHeartRateNotification = Date()
        
        await sendHapticToWatch(.notification, data: [
            "type": "heart_rate_zone",
            "from": oldZone.rawValue,
            "to": newZone.rawValue,
            "intensity": newZone.hapticIntensity
        ])
    }
    
    func triggerBreathingReminder() async {
        guard tenantPreferences.isEnabled else { return }
        
        let breathingPattern = createBreathingReminderPattern()
        
        await sendHapticToWatch(.notification, data: [
            "type": "breathing_reminder",
            "pattern": breathingPattern,
            "duration": 4.0
        ])
    }
    
    func triggerWorkoutEvent(_ event: WorkoutEvent) async {
        guard workoutSessionActive else { return }
        
        let hapticType: WatchHapticType = switch event {
        case .sessionStart: .start
        case .sessionEnd: .stop
        case .goalReached: .success
        case .intervalComplete: .notification
        case .heartRateZoneChange: .notification
        }
        
        await sendHapticToWatch(hapticType, data: [
            "type": "workout_event",
            "event": "\(event)"
        ])
    }
    
    // MARK: - Golf-Specific Watch Haptics
    
    func triggerTeeTimeReminder(minutesUntil: Int) async {
        let urgency = getTeeTimeReminderUrgency(minutesUntil: minutesUntil)
        
        await sendHapticToWatch(.notification, data: [
            "type": "tee_time_reminder",
            "minutes_until": minutesUntil,
            "urgency": urgency
        ])
    }
    
    func triggerScoreEntry(score: Int, par: Int) async {
        let performance = getPerformanceType(score: score, par: par)
        let hapticType: WatchHapticType = switch performance {
        case .eagle, .birdie: .success
        case .par: .notification
        case .bogey: .retry
        case .doubleBogey, .worse: .failure
        }
        
        await sendHapticToWatch(hapticType, data: [
            "type": "score_entry",
            "score": score,
            "par": par,
            "performance": performance.rawValue
        ])
    }
    
    func triggerDistanceUpdate(toPin: Int) async {
        guard tenantPreferences.isEnabled else { return }
        
        // Subtle haptic for distance updates
        await sendHapticToWatch(.click, data: [
            "type": "distance_update",
            "distance": toPin
        ])
    }
    
    func triggerWeatherAlert(severity: WeatherSeverity) async {
        let hapticType: WatchHapticType = switch severity {
        case .watch: .notification
        case .warning: .retry
        case .severe: .failure
        }
        
        await sendHapticToWatch(hapticType, data: [
            "type": "weather_alert",
            "severity": severity.rawValue,
            "urgent": severity == .severe
        ])
    }
    
    // MARK: - Private Implementation
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            print("⚠️ Watch Connectivity not supported")
            return
        }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }
    
    private func setupHealthKitIntegration() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("⚠️ Health data not available")
            return
        }
        
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.workoutType()
        ]
        
        healthStore.requestAuthorization(toShare: [], read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isHealthDataAuthorized = success
                if let error = error {
                    print("❌ HealthKit authorization error: \(error)")
                }
            }
        }
    }
    
    private func sendTenantConfigurationToWatch() async {
        guard let config = tenantConfiguration else { return }
        
        let configData: [String: Any] = [
            "tenantId": config.tenantId,
            "businessType": "\(config.businessType)",
            "brandingSignature": config.brandingSignature.signatureName,
            "preferences": [
                "isEnabled": tenantPreferences.isEnabled,
                "globalIntensity": "\(tenantPreferences.globalIntensity)",
                "brandingHapticEnabled": tenantPreferences.brandingHapticEnabled,
                "watchSyncEnabled": tenantPreferences.watchSyncEnabled
            ]
        ]
        
        session?.sendMessage(["type": "tenant_config", "data": configData], replyHandler: nil) { error in
            print("❌ Failed to send tenant config to Watch: \(error)")
        }
    }
    
    private func sendHapticToWatch(_ type: WatchHapticType, data: [String: Any] = [:]) async {
        guard isWatchConnected, tenantPreferences.watchSyncEnabled else { return }
        
        var messageData = data
        messageData["hapticType"] = type.rawValue
        messageData["timestamp"] = Date().timeIntervalSince1970
        
        session?.sendMessage(["type": "haptic", "data": messageData], replyHandler: nil) { error in
            print("❌ Failed to send haptic to Watch: \(error)")
        }
    }
    
    private func startHeartRateMonitoring() {
        guard isHealthDataAuthorized else { return }
        
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        
        heartRateQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            guard let samples = samples as? [HKQuantitySample],
                  let latestSample = samples.last else { return }
            
            let heartRate = latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            
            DispatchQueue.main.async {
                self?.processHeartRateUpdate(heartRate)
            }
        }
        
        heartRateQuery?.updateHandler = { [weak self] _, samples, _, _, _ in
            guard let samples = samples as? [HKQuantitySample],
                  let latestSample = samples.last else { return }
            
            let heartRate = latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            
            DispatchQueue.main.async {
                self?.processHeartRateUpdate(heartRate)
            }
        }
        
        if let query = heartRateQuery {
            healthStore.execute(query)
        }
    }
    
    private func stopHeartRateMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }
    
    private func processHeartRateUpdate(_ heartRate: Double) {
        let newZone = HeartRateZone.zone(for: heartRate)
        
        if newZone != currentHeartRateZone {
            Task {
                await triggerHeartRateZoneChange(from: currentHeartRateZone, to: newZone)
            }
        }
    }
    
    private func getMilestoneIntensity(_ milestone: TimerMilestone) -> Float {
        guard let config = tenantConfiguration else { return 0.6 }
        
        let baseMilestoneIntensity: Float = switch milestone {
        case .started: 0.6
        case .quarterComplete: 0.7
        case .halfComplete: 0.8
        case .threeQuarterComplete: 0.9
        case .completed: 1.0
        case .paused: 0.4
        case .resumed: 0.5
        }
        
        return baseMilestoneIntensity * config.intensityProfile.brandingIntensity
    }
    
    private func playMilestoneHaptic(_ milestone: TimerMilestone, intensity: Float) async {
        let hapticType: WatchHapticType = switch milestone {
        case .started: .start
        case .quarterComplete, .halfComplete, .threeQuarterComplete: .notification
        case .completed: .success
        case .paused: .stop
        case .resumed: .start
        }
        
        await sendHapticToWatch(hapticType, data: [
            "type": "milestone",
            "milestone": "\(milestone)",
            "intensity": intensity
        ])
    }
    
    private func createBreathingReminderPattern() -> [String: Any] {
        // 4-7-8 breathing technique pattern
        return [
            "inhale": 4.0,
            "hold": 7.0,
            "exhale": 8.0,
            "intensity": 0.3
        ]
    }
    
    private func getTeeTimeReminderUrgency(minutesUntil: Int) -> String {
        switch minutesUntil {
        case 0...5: return "urgent"
        case 6...15: return "high"
        case 16...30: return "medium"
        default: return "low"
        }
    }
    
    private func getPerformanceType(score: Int, par: Int) -> GolfPerformance {
        let difference = score - par
        switch difference {
        case ...(-2): return .eagle
        case -1: return .birdie
        case 0: return .par
        case 1: return .bogey
        case 2: return .doubleBogey
        default: return .worse
        }
    }
    
    // MARK: - Multi-Tenant Haptic Patterns
    
    private func initializeBusinessTypeHapticPatterns() {
        // Golf Course - Basic patterns
        businessTypeHapticPatterns[.golfCourse] = [
            .buttonTap: WatchHapticPattern(type: .click, intensity: 0.6, duration: 0.1, businessTypeVariation: .golfCourse),
            .scoreInput: WatchHapticPattern(type: .notification(.success), intensity: 0.7, duration: 0.2, businessTypeVariation: .golfCourse),
            .navigation: WatchHapticPattern(type: .selection, intensity: 0.5, duration: 0.05, businessTypeVariation: .golfCourse),
            .notification: WatchHapticPattern(type: .notification(.warning), intensity: 0.8, duration: 0.3, businessTypeVariation: .golfCourse),
            .success: WatchHapticPattern(type: .notification(.success), intensity: 1.0, duration: 0.4, businessTypeVariation: .golfCourse),
            .error: WatchHapticPattern(type: .notification(.failure), intensity: 1.0, duration: 0.5, businessTypeVariation: .golfCourse),
            .milestone: WatchHapticPattern(type: .notification(.success), intensity: 1.0, duration: 0.6, businessTypeVariation: .golfCourse)
        ]
        
        // Golf Resort - Premium patterns
        businessTypeHapticPatterns[.golfResort] = [
            .buttonTap: WatchHapticPattern(type: .click, intensity: 0.7, duration: 0.12, businessTypeVariation: .golfResort),
            .scoreInput: WatchHapticPattern(type: .notification(.success), intensity: 0.8, duration: 0.25, businessTypeVariation: .golfResort),
            .navigation: WatchHapticPattern(type: .selection, intensity: 0.6, duration: 0.08, businessTypeVariation: .golfResort),
            .notification: WatchHapticPattern(type: .notification(.warning), intensity: 0.9, duration: 0.35, businessTypeVariation: .golfResort),
            .success: WatchHapticPattern(type: .start, intensity: 1.0, duration: 0.5, businessTypeVariation: .golfResort),
            .error: WatchHapticPattern(type: .notification(.failure), intensity: 1.0, duration: 0.6, businessTypeVariation: .golfResort),
            .milestone: WatchHapticPattern(type: .start, intensity: 1.0, duration: 0.7, businessTypeVariation: .golfResort)
        ]
        
        // Country Club - Elegant patterns
        businessTypeHapticPatterns[.countryClub] = [
            .buttonTap: WatchHapticPattern(type: .click, intensity: 0.8, duration: 0.15, businessTypeVariation: .countryClub),
            .scoreInput: WatchHapticPattern(type: .notification(.success), intensity: 0.85, duration: 0.3, businessTypeVariation: .countryClub),
            .navigation: WatchHapticPattern(type: .selection, intensity: 0.65, duration: 0.1, businessTypeVariation: .countryClub),
            .notification: WatchHapticPattern(type: .notification(.warning), intensity: 0.95, duration: 0.4, businessTypeVariation: .countryClub),
            .success: WatchHapticPattern(type: .start, intensity: 1.0, duration: 0.6, businessTypeVariation: .countryClub),
            .error: WatchHapticPattern(type: .notification(.failure), intensity: 1.0, duration: 0.7, businessTypeVariation: .countryClub),
            .milestone: WatchHapticPattern(type: .start, intensity: 1.0, duration: 0.8, businessTypeVariation: .countryClub)
        ]
        
        // Private Club - Elite patterns
        businessTypeHapticPatterns[.privateClub] = [
            .buttonTap: WatchHapticPattern(type: .click, intensity: 1.0, duration: 0.2, businessTypeVariation: .privateClub),
            .scoreInput: WatchHapticPattern(type: .notification(.success), intensity: 1.0, duration: 0.35, businessTypeVariation: .privateClub),
            .navigation: WatchHapticPattern(type: .selection, intensity: 0.8, duration: 0.12, businessTypeVariation: .privateClub),
            .notification: WatchHapticPattern(type: .notification(.warning), intensity: 1.0, duration: 0.5, businessTypeVariation: .privateClub),
            .success: WatchHapticPattern(type: .start, intensity: 1.0, duration: 0.8, businessTypeVariation: .privateClub),
            .error: WatchHapticPattern(type: .notification(.failure), intensity: 1.0, duration: 0.8, businessTypeVariation: .privateClub),
            .milestone: WatchHapticPattern(type: .start, intensity: 1.0, duration: 1.0, businessTypeVariation: .privateClub)
        ]
        
        // Public Course - Community patterns
        businessTypeHapticPatterns[.publicCourse] = [
            .buttonTap: WatchHapticPattern(type: .click, intensity: 0.5, duration: 0.08, businessTypeVariation: .publicCourse),
            .scoreInput: WatchHapticPattern(type: .notification(.success), intensity: 0.6, duration: 0.15, businessTypeVariation: .publicCourse),
            .navigation: WatchHapticPattern(type: .selection, intensity: 0.4, duration: 0.05, businessTypeVariation: .publicCourse),
            .notification: WatchHapticPattern(type: .notification(.warning), intensity: 0.7, duration: 0.25, businessTypeVariation: .publicCourse),
            .success: WatchHapticPattern(type: .notification(.success), intensity: 0.8, duration: 0.3, businessTypeVariation: .publicCourse),
            .error: WatchHapticPattern(type: .notification(.failure), intensity: 0.9, duration: 0.4, businessTypeVariation: .publicCourse),
            .milestone: WatchHapticPattern(type: .notification(.success), intensity: 0.9, duration: 0.5, businessTypeVariation: .publicCourse)
        ]
        
        // Golf Academy - Educational patterns
        businessTypeHapticPatterns[.golfAcademy] = [
            .buttonTap: WatchHapticPattern(type: .click, intensity: 0.65, duration: 0.1, businessTypeVariation: .golfAcademy),
            .scoreInput: WatchHapticPattern(type: .notification(.success), intensity: 0.75, duration: 0.2, businessTypeVariation: .golfAcademy),
            .navigation: WatchHapticPattern(type: .selection, intensity: 0.55, duration: 0.06, businessTypeVariation: .golfAcademy),
            .notification: WatchHapticPattern(type: .notification(.warning), intensity: 0.85, duration: 0.3, businessTypeVariation: .golfAcademy),
            .success: WatchHapticPattern(type: .notification(.success), intensity: 0.95, duration: 0.4, businessTypeVariation: .golfAcademy),
            .error: WatchHapticPattern(type: .notification(.failure), intensity: 0.95, duration: 0.5, businessTypeVariation: .golfAcademy),
            .milestone: WatchHapticPattern(type: .start, intensity: 0.95, duration: 0.6, businessTypeVariation: .golfAcademy)
        ]
    }
    
    private func getBusinessTypeHapticPatterns(for businessType: WatchBusinessType) -> [WatchInteractionType: WatchHapticPattern] {
        return businessTypeHapticPatterns[businessType] ?? businessTypeHapticPatterns[.golfCourse]!
    }
    
    private func createTenantBrandingPattern(for context: WatchTenantContext) -> BrandingHapticPattern {
        let intensity = context.businessType.hasEliteFeatures ? 1.0 : 0.8
        let duration = context.businessType.hasPremiumFeatures ? 0.6 : 0.4
        
        return BrandingHapticPattern(
            tenantId: context.tenantId ?? "default",
            businessType: context.businessType,
            primaryIntensity: intensity,
            duration: duration,
            pattern: createBrandingSignature(for: context.businessType)
        )
    }
    
    private func createBrandingSignature(for businessType: WatchBusinessType) -> [HapticPulse] {
        switch businessType {
        case .golfCourse:
            return [
                HapticPulse(intensity: 0.7, duration: 0.1),
                HapticPulse(intensity: 0.0, duration: 0.05),
                HapticPulse(intensity: 0.9, duration: 0.15)
            ]
        case .golfResort:
            return [
                HapticPulse(intensity: 0.8, duration: 0.12),
                HapticPulse(intensity: 0.0, duration: 0.08),
                HapticPulse(intensity: 1.0, duration: 0.2),
                HapticPulse(intensity: 0.0, duration: 0.05),
                HapticPulse(intensity: 0.6, duration: 0.1)
            ]
        case .countryClub:
            return [
                HapticPulse(intensity: 0.9, duration: 0.15),
                HapticPulse(intensity: 0.0, duration: 0.1),
                HapticPulse(intensity: 1.0, duration: 0.25),
                HapticPulse(intensity: 0.0, duration: 0.1),
                HapticPulse(intensity: 0.8, duration: 0.15)
            ]
        case .privateClub:
            return [
                HapticPulse(intensity: 1.0, duration: 0.2),
                HapticPulse(intensity: 0.0, duration: 0.15),
                HapticPulse(intensity: 1.0, duration: 0.3),
                HapticPulse(intensity: 0.0, duration: 0.1),
                HapticPulse(intensity: 1.0, duration: 0.2),
                HapticPulse(intensity: 0.0, duration: 0.05),
                HapticPulse(intensity: 0.8, duration: 0.1)
            ]
        case .publicCourse:
            return [
                HapticPulse(intensity: 0.6, duration: 0.08),
                HapticPulse(intensity: 0.0, duration: 0.04),
                HapticPulse(intensity: 0.8, duration: 0.12)
            ]
        case .golfAcademy:
            return [
                HapticPulse(intensity: 0.7, duration: 0.1),
                HapticPulse(intensity: 0.0, duration: 0.05),
                HapticPulse(intensity: 0.9, duration: 0.15),
                HapticPulse(intensity: 0.0, duration: 0.05),
                HapticPulse(intensity: 0.7, duration: 0.1),
                HapticPulse(intensity: 0.0, duration: 0.05),
                HapticPulse(intensity: 0.5, duration: 0.08)
            ]
        }
    }
    
    // MARK: - Tenant-Aware Haptic Triggers
    
    func triggerTenantAwareHaptic(for interaction: WatchInteractionType) async {
        guard currentTenantContext.features.enableHaptics else { return }
        
        let pattern = getBusinessTypeHapticPatterns(for: currentTenantContext.businessType)[interaction]
        guard let hapticPattern = pattern else { return }
        
        await sendTenantHapticToWatch(hapticPattern, interaction: interaction)
    }
    
    func triggerTenantBrandingHaptic() async {
        guard let tenantId = currentTenantContext.tenantId,
              let brandingPattern = tenantBrandingPatterns[tenantId],
              currentTenantContext.features.enableHaptics else { return }
        
        await sendBrandingHapticToWatch(brandingPattern)
    }
    
    private func sendTenantHapticToWatch(_ pattern: WatchHapticPattern, interaction: WatchInteractionType) async {
        guard let session = session, session.isReachable else { return }
        
        let hapticData: [String: Any] = [
            "type": "tenant_haptic",
            "interaction": interaction.rawValue,
            "businessType": currentTenantContext.businessType.rawValue,
            "pattern": [
                "hapticType": pattern.type.description,
                "intensity": pattern.intensity,
                "duration": pattern.duration
            ],
            "tenantId": currentTenantContext.tenantId as Any
        ]
        
        session.sendMessage(["type": "haptic", "data": hapticData], replyHandler: nil) { error in
            print("❌ Failed to send tenant haptic to Watch: \(error)")
        }
    }
    
    private func sendBrandingHapticToWatch(_ brandingPattern: BrandingHapticPattern) async {
        guard let session = session, session.isReachable else { return }
        
        let brandingData: [String: Any] = [
            "type": "branding_haptic",
            "tenantId": brandingPattern.tenantId,
            "businessType": brandingPattern.businessType.rawValue,
            "intensity": brandingPattern.primaryIntensity,
            "duration": brandingPattern.duration,
            "signature": brandingPattern.pattern.map { pulse in
                [
                    "intensity": pulse.intensity,
                    "duration": pulse.duration
                ]
            }
        ]
        
        session.sendMessage(["type": "haptic", "data": brandingData], replyHandler: nil) { error in
            print("❌ Failed to send branding haptic to Watch: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchHapticFeedbackService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = activationState == .activated
            
            if let error = error {
                print("❌ Watch connectivity activation failed: \(error)")
            } else {
                print("✅ Watch connectivity activated: \(activationState.rawValue)")
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
            print("⚠️ Watch session became inactive")
        }
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
            print("⚠️ Watch session deactivated")
        }
        
        // Reactivate session
        session.activate()
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Handle messages from Apple Watch
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "haptic_feedback_request":
            // Watch is requesting haptic feedback
            if let hapticType = message["hapticType"] as? String,
               let watchHapticType = WatchHapticType(rawValue: hapticType) {
                Task {
                    await sendHapticToWatch(watchHapticType)
                }
            }
        case "milestone_reached":
            // Watch detected a milestone
            if let milestoneString = message["milestone"] as? String,
               let milestone = TimerMilestone(rawValue: milestoneString) {
                Task {
                    await triggerTimerMilestone(milestone)
                }
            }
        default:
            print("Unknown message type from Watch: \(type)")
        }
    }
}

// MARK: - Supporting Types

enum HeartRateZone: String, CaseIterable {
    case resting = "resting"
    case warmUp = "warm_up"
    case aerobic = "aerobic"
    case anaerobic = "anaerobic"
    case maximum = "maximum"
    
    static func zone(for heartRate: Double) -> HeartRateZone {
        // Simplified heart rate zones (actual implementation would use user's age/fitness data)
        switch heartRate {
        case 0..<90: return .resting
        case 90..<120: return .warmUp
        case 120..<150: return .aerobic
        case 150..<180: return .anaerobic
        default: return .maximum
        }
    }
    
    var hapticIntensity: Float {
        switch self {
        case .resting: return 0.3
        case .warmUp: return 0.4
        case .aerobic: return 0.6
        case .anaerobic: return 0.8
        case .maximum: return 1.0
        }
    }
    
    var displayName: String {
        switch self {
        case .resting: return "Resting"
        case .warmUp: return "Warm Up"
        case .aerobic: return "Aerobic"
        case .anaerobic: return "Anaerobic"
        case .maximum: return "Maximum"
        }
    }
}

enum WeatherSeverity: String, CaseIterable {
    case watch = "watch"
    case warning = "warning"
    case severe = "severe"
}

enum GolfPerformance: String, CaseIterable {
    case eagle = "eagle"
    case birdie = "birdie"
    case par = "par"
    case bogey = "bogey"
    case doubleBogey = "double_bogey"
    case worse = "worse"
}

extension TimerMilestone {
    init?(rawValue: String) {
        switch rawValue {
        case "started": self = .started
        case "quarter_complete": self = .quarterComplete
        case "half_complete": self = .halfComplete
        case "three_quarter_complete": self = .threeQuarterComplete
        case "completed": self = .completed
        case "paused": self = .paused
        case "resumed": self = .resumed
        default: return nil
        }
    }
    
    var rawValue: String {
        switch self {
        case .started: return "started"
        case .quarterComplete: return "quarter_complete"
        case .halfComplete: return "half_complete"
        case .threeQuarterComplete: return "three_quarter_complete"
        case .completed: return "completed"
        case .paused: return "paused"
        case .resumed: return "resumed"
        }
    }
}

extension WatchHapticType {
    init?(rawValue: String) {
        switch rawValue {
        case "notification": self = .notification
        case "directionUp": self = .directionUp
        case "directionDown": self = .directionDown
        case "success": self = .success
        case "failure": self = .failure
        case "retry": self = .retry
        case "start": self = .start
        case "stop": self = .stop
        case "click": self = .click
        default: return nil
        }
    }
}

class TimerMilestoneTracker {
    private(set) var completedMilestones: [String] = []
    
    func recordMilestone(_ milestone: TimerMilestone) {
        completedMilestones.append(milestone.rawValue)
    }
    
    func reset() {
        completedMilestones.removeAll()
    }
}

// MARK: - Multi-Tenant Haptic Supporting Types

struct BrandingHapticPattern {
    let tenantId: String
    let businessType: WatchBusinessType
    let primaryIntensity: Double
    let duration: Double
    let pattern: [HapticPulse]
}

struct HapticPulse {
    let intensity: Double
    let duration: Double
}

// MARK: - Import WatchKit Types

import WatchKit

// Define missing WKHapticType for compatibility
#if !os(watchOS)
public enum WKHapticType: Int {
    case notification = 0
    case directionUp = 1
    case directionDown = 2
    case success = 3
    case failure = 4
    case retry = 5
    case start = 6
    case stop = 7
    case click = 8
    case selection = 9
    
    public enum NotificationType: Int {
        case success = 0
        case failure = 1
        case warning = 2
    }
    
    public static func notification(_ type: NotificationType) -> WKHapticType {
        switch type {
        case .success: return .success
        case .failure: return .failure
        case .warning: return .retry
        }
    }
}
#endif

// WatchHapticPattern already defined in WatchTenantThemeService
// WatchInteractionType already defined in WatchTenantThemeService
// WatchBusinessType already defined in WatchServiceContainer

// Additional haptic type extensions
extension WKHapticType {
    var description: String {
        switch self {
        case .notification: return "notification"
        case .directionUp: return "directionUp"
        case .directionDown: return "directionDown"
        case .success: return "success"
        case .failure: return "failure"
        case .retry: return "retry"
        case .start: return "start"
        case .stop: return "stop"
        case .click: return "click"
        case .selection: return "selection"
        @unknown default: return "unknown"
        }
    }
}

// Bridge to existing WatchHapticType
extension WatchHapticType {
    var wkHapticType: WKHapticType {
        switch self {
        case .notification: return .notification(.warning)
        case .directionUp: return .directionUp
        case .directionDown: return .directionDown
        case .success: return .success
        case .failure: return .failure
        case .retry: return .retry
        case .start: return .start
        case .stop: return .stop
        case .click: return .click
        }
    }
}