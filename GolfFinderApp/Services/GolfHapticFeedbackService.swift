import Foundation
import CoreHaptics
import UIKit

// MARK: - Golf Haptic Feedback Service Protocol

protocol HapticFeedbackServiceProtocol {
    // Golf-specific haptic feedback
    func provideTeeOffHaptic() async
    func provideScoreEntryHaptic(scoreType: ScoreType) async
    func provideLeaderboardUpdateHaptic(position: LeaderboardPosition) async
    func provideCourseDiscoveryHaptic() async
    func provideTeeTimeBookingHaptic() async
    
    // Distance and location feedback
    func provideDistanceHaptic(accuracy: DistanceAccuracy) async
    func provideHazardWarningHaptic() async
    func provideGreenApproachHaptic() async
    
    // Achievement and milestone feedback
    func providePersonalBestHaptic() async
    func provideHandicapImprovementHaptic() async
    func provideTournamentMilestoneHaptic(milestone: TournamentMilestone) async
    
    // Weather and conditions feedback
    func provideWeatherAlertHaptic(severity: WeatherSeverity) async
    func provideCourseConditionHaptic(condition: CourseConditionLevel) async
}

// MARK: - Golf Haptic Feedback Service Implementation

@MainActor
class GolfHapticFeedbackService: NSObject, HapticFeedbackServiceProtocol {
    
    // MARK: - Core Haptics Engine
    
    private var hapticEngine: CHHapticEngine?
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    // MARK: - Haptic Configuration
    
    private var isHapticsEnabled = true
    private var isAdvancedHapticsAvailable = false
    private let maxSimultaneousHaptics = 3
    private var activeHapticPlayers: Set<String> = []
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupHapticEngine()
        configureHapticFeedbackGenerators()
    }
    
    // MARK: - Golf-Specific Haptic Feedback
    
    func provideTeeOffHaptic() async {
        await playGolfHapticPattern(.teeOff)
        await triggerAppleWatchHaptic(.teeOff)
    }
    
    func provideScoreEntryHaptic(scoreType: ScoreType) async {
        let pattern: GolfHapticPattern
        
        switch scoreType {
        case .eagle, .albatross:
            pattern = .eagleAchievement
        case .birdie:
            pattern = .birdieSuccess
        case .par:
            pattern = .parConfirmation
        case .bogey:
            pattern = .bogeyMild
        case .doubleBogey, .tripleBogey, .worse:
            pattern = .troubleScore
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideLeaderboardUpdateHaptic(position: LeaderboardPosition) async {
        let pattern: GolfHapticPattern
        
        switch position {
        case .first:
            pattern = .leaderboardFirst
        case .topThree:
            pattern = .leaderboardTop
        case .improved:
            pattern = .leaderboardImprove
        case .declined:
            pattern = .leaderboardDecline
        }
        
        await playGolfHapticPattern(pattern)
    }
    
    func provideCourseDiscoveryHaptic() async {
        await playGolfHapticPattern(.courseDiscovery)
    }
    
    func provideTeeTimeBookingHaptic() async {
        await playGolfHapticPattern(.bookingConfirmation)
        await triggerAppleWatchHaptic(.bookingConfirmation)
    }
    
    // MARK: - Distance and Location Feedback
    
    func provideDistanceHaptic(accuracy: DistanceAccuracy) async {
        let pattern: GolfHapticPattern
        
        switch accuracy {
        case .precise:
            pattern = .distancePrecise
        case .approximate:
            pattern = .distanceApproximate
        case .estimated:
            pattern = .distanceEstimate
        }
        
        await playGolfHapticPattern(pattern)
    }
    
    func provideHazardWarningHaptic() async {
        await playGolfHapticPattern(.hazardWarning)
        await triggerAppleWatchHaptic(.hazardWarning)
    }
    
    func provideGreenApproachHaptic() async {
        await playGolfHapticPattern(.greenApproach)
    }
    
    // MARK: - Achievement and Milestone Feedback
    
    func providePersonalBestHaptic() async {
        await playGolfHapticPattern(.personalBest)
        await triggerAppleWatchHaptic(.personalBest)
    }
    
    func provideHandicapImprovementHaptic() async {
        await playGolfHapticPattern(.handicapImprovement)
        await triggerAppleWatchHaptic(.handicapImprovement)
    }
    
    func provideTournamentMilestoneHaptic(milestone: TournamentMilestone) async {
        let pattern: GolfHapticPattern
        
        switch milestone {
        case .tournamentStart:
            pattern = .tournamentStart
        case .halfwayLeader:
            pattern = .tournamentLeader
        case .finalRound:
            pattern = .tournamentFinal
        case .tournamentWin:
            pattern = .tournamentVictory
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    // MARK: - Weather and Conditions Feedback
    
    func provideWeatherAlertHaptic(severity: WeatherSeverity) async {
        let pattern: GolfHapticPattern
        
        switch severity {
        case .mild:
            pattern = .weatherMild
        case .moderate:
            pattern = .weatherModerate
        case .severe:
            pattern = .weatherSevere
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideCourseConditionHaptic(condition: CourseConditionLevel) async {
        let pattern: GolfHapticPattern
        
        switch condition {
        case .excellent:
            pattern = .conditionExcellent
        case .good:
            pattern = .conditionGood
        case .fair:
            pattern = .conditionFair
        case .poor:
            pattern = .conditionPoor
        }
        
        await playGolfHapticPattern(pattern)
    }
}

// MARK: - Private Implementation

private extension GolfHapticFeedbackService {
    
    func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("⚠️ Device does not support haptics")
            isAdvancedHapticsAvailable = false
            return
        }
        
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
            isAdvancedHapticsAvailable = true
            
            hapticEngine?.stoppedHandler = { [weak self] reason in
                print("🔄 Haptic engine stopped: \(reason)")
                Task { @MainActor in
                    try? await self?.hapticEngine?.start()
                }
            }
            
            hapticEngine?.resetHandler = { [weak self] in
                print("🔄 Haptic engine reset")
                Task { @MainActor in
                    try? await self?.hapticEngine?.start()
                }
            }
            
            print("✅ Golf Haptic Engine initialized successfully")
            
        } catch {
            print("❌ Failed to initialize haptic engine: \(error)")
            isAdvancedHapticsAvailable = false
        }
    }
    
    func configureHapticFeedbackGenerators() {
        // Prepare generators for optimal performance
        impactGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }
    
    func playGolfHapticPattern(_ pattern: GolfHapticPattern) async {
        guard isHapticsEnabled else { return }
        
        // Prevent too many simultaneous haptics
        guard activeHapticPlayers.count < maxSimultaneousHaptics else { return }
        
        let patternId = UUID().uuidString
        activeHapticPlayers.insert(patternId)
        
        defer {
            activeHapticPlayers.remove(patternId)
        }
        
        if isAdvancedHapticsAvailable, let hapticEngine = hapticEngine {
            await playAdvancedHapticPattern(pattern, engine: hapticEngine)
        } else {
            await playBasicHapticPattern(pattern)
        }
    }
    
    func playAdvancedHapticPattern(_ pattern: GolfHapticPattern, engine: CHHapticEngine) async {
        do {
            let hapticPattern = createCoreHapticPattern(for: pattern)
            let player = try engine.makePlayer(with: hapticPattern)
            try player.start(atTime: CHHapticTimeImmediate)
            
            // Add slight delay for pattern completion
            try await Task.sleep(nanoseconds: UInt64(pattern.duration * 1_000_000_000))
            
        } catch {
            print("❌ Failed to play advanced haptic pattern: \(error)")
            await playBasicHapticPattern(pattern)
        }
    }
    
    func playBasicHapticPattern(_ pattern: GolfHapticPattern) async {
        switch pattern.fallbackType {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .selection:
            selectionGenerator.selectionChanged()
        case .notification(let type):
            notificationGenerator.notificationOccurred(type)
        case .sequence(let patterns):
            for (index, subPattern) in patterns.enumerated() {
                if index > 0 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                }
                await playBasicHapticPattern(GolfHapticPattern.createBasicPattern(subPattern))
            }
        }
    }
    
    func createCoreHapticPattern(for pattern: GolfHapticPattern) -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        
        for (index, event) in pattern.events.enumerated() {
            let hapticEvent = CHHapticEvent(
                eventType: event.type == .impact ? .hapticTransient : .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness)
                ],
                relativeTime: event.time,
                duration: event.duration
            )
            events.append(hapticEvent)
        }
        
        do {
            return try CHHapticPattern(events: events, parameters: [])
        } catch {
            print("❌ Failed to create haptic pattern: \(error)")
            // Return a simple fallback pattern
            let simpleEvent = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0
            )
            return try! CHHapticPattern(events: [simpleEvent], parameters: [])
        }
    }
    
    func triggerAppleWatchHaptic(_ pattern: GolfHapticPattern) async {
        // Apple Watch integration would happen here
        // For now, we'll just log the intended watch haptic
        print("🍎⌚ Apple Watch Haptic: \(pattern.name)")
        
        // TODO: Implement WatchConnectivity integration
        // This would send haptic commands to the Apple Watch companion app
    }
}

// MARK: - Golf Haptic Pattern Definitions

struct GolfHapticPattern {
    let name: String
    let events: [HapticEvent]
    let duration: TimeInterval
    let fallbackType: BasicHapticType
    
    struct HapticEvent {
        let type: HapticEventType
        let time: TimeInterval
        let duration: TimeInterval
        let intensity: Float
        let sharpness: Float
        
        enum HapticEventType {
            case impact
            case continuous
        }
    }
    
    enum BasicHapticType {
        case light
        case medium
        case heavy
        case selection
        case notification(UINotificationFeedbackGenerator.FeedbackType)
        case sequence([BasicHapticType])
    }
    
    // MARK: - Golf-Specific Patterns
    
    static let teeOff = GolfHapticPattern(
        name: "Tee Off",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 0.8, sharpness: 0.7),
            HapticEvent(type: .continuous, time: 0.1, duration: 0.3, intensity: 0.4, sharpness: 0.3)
        ],
        duration: 0.4,
        fallbackType: .heavy
    )
    
    static let birdieSuccess = GolfHapticPattern(
        name: "Birdie Success",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 0.9, sharpness: 0.8),
            HapticEvent(type: .impact, time: 0.15, duration: 0.1, intensity: 0.7, sharpness: 0.6),
            HapticEvent(type: .impact, time: 0.3, duration: 0.1, intensity: 0.5, sharpness: 0.4)
        ],
        duration: 0.4,
        fallbackType: .notification(.success)
    )
    
    static let eagleAchievement = GolfHapticPattern(
        name: "Eagle Achievement",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 1.0, sharpness: 1.0),
            HapticEvent(type: .continuous, time: 0.1, duration: 0.2, intensity: 0.8, sharpness: 0.8),
            HapticEvent(type: .impact, time: 0.3, duration: 0.1, intensity: 1.0, sharpness: 1.0),
            HapticEvent(type: .continuous, time: 0.4, duration: 0.3, intensity: 0.6, sharpness: 0.4)
        ],
        duration: 0.7,
        fallbackType: .sequence([.heavy, .medium, .heavy])
    )
    
    static let leaderboardFirst = GolfHapticPattern(
        name: "Leaderboard First Place",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 1.0, sharpness: 0.9),
            HapticEvent(type: .continuous, time: 0.1, duration: 0.5, intensity: 0.7, sharpness: 0.5),
            HapticEvent(type: .impact, time: 0.6, duration: 0.1, intensity: 1.0, sharpness: 0.9)
        ],
        duration: 0.7,
        fallbackType: .sequence([.heavy, .heavy])
    )
    
    static let hazardWarning = GolfHapticPattern(
        name: "Hazard Warning",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.05, intensity: 0.9, sharpness: 1.0),
            HapticEvent(type: .impact, time: 0.1, duration: 0.05, intensity: 0.9, sharpness: 1.0),
            HapticEvent(type: .impact, time: 0.2, duration: 0.05, intensity: 0.9, sharpness: 1.0)
        ],
        duration: 0.25,
        fallbackType: .notification(.warning)
    )
    
    static let personalBest = GolfHapticPattern(
        name: "Personal Best",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 1.0, sharpness: 0.8),
            HapticEvent(type: .continuous, time: 0.15, duration: 0.4, intensity: 0.8, sharpness: 0.6),
            HapticEvent(type: .impact, time: 0.6, duration: 0.1, intensity: 1.0, sharpness: 0.8),
            HapticEvent(type: .continuous, time: 0.75, duration: 0.4, intensity: 0.6, sharpness: 0.4)
        ],
        duration: 1.2,
        fallbackType: .sequence([.heavy, .medium, .heavy, .light])
    )
    
    // Additional patterns...
    static let parConfirmation = createBasicPattern(.medium)
    static let bogeyMild = createBasicPattern(.light)
    static let troubleScore = createBasicPattern(.notification(.error))
    static let courseDiscovery = createBasicPattern(.selection)
    static let bookingConfirmation = createBasicPattern(.notification(.success))
    static let distancePrecise = createBasicPattern(.heavy)
    static let distanceApproximate = createBasicPattern(.medium)
    static let distanceEstimate = createBasicPattern(.light)
    static let greenApproach = createBasicPattern(.selection)
    static let handicapImprovement = createBasicPattern(.notification(.success))
    static let tournamentStart = createBasicPattern(.heavy)
    static let tournamentLeader = createBasicPattern(.sequence([.heavy, .medium]))
    static let tournamentFinal = createBasicPattern(.sequence([.heavy, .heavy, .medium]))
    static let tournamentVictory = createBasicPattern(.sequence([.heavy, .heavy, .heavy, .light]))
    static let leaderboardTop = createBasicPattern(.sequence([.heavy, .medium]))
    static let leaderboardImprove = createBasicPattern(.medium)
    static let leaderboardDecline = createBasicPattern(.light)
    static let weatherMild = createBasicPattern(.light)
    static let weatherModerate = createBasicPattern(.medium)
    static let weatherSevere = createBasicPattern(.notification(.warning))
    static let conditionExcellent = createBasicPattern(.selection)
    static let conditionGood = createBasicPattern(.light)
    static let conditionFair = createBasicPattern(.medium)
    static let conditionPoor = createBasicPattern(.heavy)
    
    static func createBasicPattern(_ type: BasicHapticType) -> GolfHapticPattern {
        return GolfHapticPattern(
            name: "Basic Pattern",
            events: [HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 0.7, sharpness: 0.5)],
            duration: 0.1,
            fallbackType: type
        )
    }
}

// MARK: - Supporting Enums

enum ScoreType {
    case albatross
    case eagle
    case birdie
    case par
    case bogey
    case doubleBogey
    case tripleBogey
    case worse
}

enum LeaderboardPosition {
    case first
    case topThree
    case improved
    case declined
}

enum DistanceAccuracy {
    case precise    // GPS/laser accurate
    case approximate // Good estimate
    case estimated  // Rough estimate
}

enum TournamentMilestone {
    case tournamentStart
    case halfwayLeader
    case finalRound
    case tournamentWin
}

enum WeatherSeverity {
    case mild      // Light rain, breeze
    case moderate  // Steady rain, wind
    case severe    // Heavy rain, storms
}

enum CourseConditionLevel {
    case excellent
    case good
    case fair
    case poor
}