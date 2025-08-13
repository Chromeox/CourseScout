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
    
    // MARK: - Gamification System Haptics
    
    // Achievement System Haptics
    func provideAchievementUnlockHaptic(tier: AchievementTier) async
    func provideBadgeAcquisitionHaptic(badgeType: BadgeType) async
    func provideMilestoneHaptic(milestone: GameMilestone) async
    func provideStreakHaptic(streakType: StreakType) async
    
    // Social Challenge Haptics
    func provideChallengeInvitationHaptic() async
    func provideChallengeVictoryHaptic(competitionLevel: CompetitionLevel) async
    func provideTournamentProgressHaptic(progress: TournamentProgress) async
    func provideHeadToHeadUpdateHaptic(status: HeadToHeadStatus) async
    func provideFriendChallengeHaptic(challengeEvent: FriendChallengeEvent) async
    
    // Leaderboard Position Haptics
    func providePositionChangeHaptic(change: PositionChange) async
    func provideLeaderboardMilestoneHaptic(milestone: LeaderboardMilestone) async
    func provideLiveTournamentPositionHaptic(position: LiveTournamentPosition) async
    func provideRatingTierChangeHaptic(change: RatingTierChange) async
    
    // Rating Engine Haptics
    func providePersonalBestCelebrationHaptic(scoreType: PersonalBestType) async
    func provideHandicapMilestoneHaptic(improvement: HandicapImprovement) async
    func provideStrokesGainedHaptic(category: StrokesGainedCategory, achievement: StrokesGainedAchievement) async
    func providePredictivePerformanceHaptic(feedback: PerformanceFeedback) async
    
    // Apple Watch Coordination for Gamification
    func provideSynchronizedAchievementHaptic(tier: AchievementTier) async
    func provideSynchronizedTournamentHaptic(progress: TournamentProgress) async
    func provideSynchronizedChallengeHaptic(event: ChallengeEvent) async
    func provideSynchronizedLeaderboardHaptic(change: LeaderboardChange) async
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
    
    // MARK: - Gamification System Haptic Implementation
    
    // MARK: Achievement System Haptics
    
    func provideAchievementUnlockHaptic(tier: AchievementTier) async {
        let pattern: GolfHapticPattern
        
        switch tier {
        case .bronze:
            pattern = .achievementBronze
        case .silver:
            pattern = .achievementSilver
        case .gold:
            pattern = .achievementGold
        case .platinum:
            pattern = .achievementPlatinum
        case .diamond:
            pattern = .achievementDiamond
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideBadgeAcquisitionHaptic(badgeType: BadgeType) async {
        let pattern: GolfHapticPattern
        
        switch badgeType {
        case .scoring:
            pattern = .badgeScoring
        case .consistency:
            pattern = .badgeConsistency
        case .improvement:
            pattern = .badgeImprovement
        case .social:
            pattern = .badgeSocial
        case .tournament:
            pattern = .badgeTournament
        case .course:
            pattern = .badgeCourse
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideMilestoneHaptic(milestone: GameMilestone) async {
        let pattern: GolfHapticPattern
        
        switch milestone {
        case .firstRound:
            pattern = .milestoneFirstRound
        case .tenRounds:
            pattern = .milestoneTenRounds
        case .fiftyRounds:
            pattern = .milestoneFiftyRounds
        case .hundredRounds:
            pattern = .milestoneHundredRounds
        case .firstBirdie:
            pattern = .milestoneFirstBirdie
        case .firstEagle:
            pattern = .milestoneFirstEagle
        case .breakingPar:
            pattern = .milestoneBreakingPar
        case .handicapSingleDigit:
            pattern = .milestoneSingleDigitHandicap
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideStreakHaptic(streakType: StreakType) async {
        let pattern: GolfHapticPattern
        
        switch streakType {
        case .parStreak(let count):
            pattern = count >= 5 ? .streakParLong : .streakParShort
        case .birdieStreak(let count):
            pattern = count >= 3 ? .streakBirdieLong : .streakBirdieShort
        case .fairwayStreak(let count):
            pattern = count >= 10 ? .streakFairwayLong : .streakFairwayShort
        case .streakBroken:
            pattern = .streakBroken
        case .playingStreak(let days):
            pattern = days >= 7 ? .streakPlayingWeek : .streakPlayingDay
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    // MARK: Social Challenge Haptics
    
    func provideChallengeInvitationHaptic() async {
        await playGolfHapticPattern(.challengeInvitation)
        await triggerAppleWatchHaptic(.challengeInvitation)
    }
    
    func provideChallengeVictoryHaptic(competitionLevel: CompetitionLevel) async {
        let pattern: GolfHapticPattern
        
        switch competitionLevel {
        case .casual:
            pattern = .challengeVictoryCasual
        case .competitive:
            pattern = .challengeVictoryCompetitive
        case .professional:
            pattern = .challengeVictoryProfessional
        case .championship:
            pattern = .challengeVictoryChampionship
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideTournamentProgressHaptic(progress: TournamentProgress) async {
        let pattern: GolfHapticPattern
        
        switch progress {
        case .qualifying:
            pattern = .tournamentQualifying
        case .advancing:
            pattern = .tournamentAdvancing
        case .quarterFinal:
            pattern = .tournamentQuarterFinal
        case .semiFinal:
            pattern = .tournamentSemiFinal
        case .final:
            pattern = .tournamentFinalRound
        case .champion:
            pattern = .tournamentChampion
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideHeadToHeadUpdateHaptic(status: HeadToHeadStatus) async {
        let pattern: GolfHapticPattern
        
        switch status {
        case .takingLead:
            pattern = .headToHeadTakingLead
        case .tying:
            pattern = .headToHeadTying
        case .fallingBehind:
            pattern = .headToHeadFallingBehind
        case .closeGap:
            pattern = .headToHeadCloseGap
        case .extendingLead:
            pattern = .headToHeadExtendingLead
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideFriendChallengeHaptic(challengeEvent: FriendChallengeEvent) async {
        let pattern: GolfHapticPattern
        
        switch challengeEvent {
        case .invited:
            pattern = .friendChallengeInvited
        case .accepted:
            pattern = .friendChallengeAccepted
        case .completed:
            pattern = .friendChallengeCompleted
        case .won:
            pattern = .friendChallengeWon
        case .lost:
            pattern = .friendChallengeLost
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    // MARK: Leaderboard Position Haptics
    
    func providePositionChangeHaptic(change: PositionChange) async {
        let pattern: GolfHapticPattern
        
        switch change {
        case .majorImprovement(let positions):
            pattern = positions >= 10 ? .positionMajorImprovement : .positionImprovement
        case .minorImprovement:
            pattern = .positionMinorImprovement
        case .stable:
            pattern = .positionStable
        case .minorDecline:
            pattern = .positionMinorDecline
        case .majorDecline:
            pattern = .positionMajorDecline
        }
        
        await playGolfHapticPattern(pattern)
    }
    
    func provideLeaderboardMilestoneHaptic(milestone: LeaderboardMilestone) async {
        let pattern: GolfHapticPattern
        
        switch milestone {
        case .topTen:
            pattern = .leaderboardTopTen
        case .topFive:
            pattern = .leaderboardTopFive
        case .topThree:
            pattern = .leaderboardTopThree
        case .runner_up:
            pattern = .leaderboardRunnerUp
        case .first:
            pattern = .leaderboardFirstPlace
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideLiveTournamentPositionHaptic(position: LiveTournamentPosition) async {
        let pattern: GolfHapticPattern
        
        switch position {
        case .movingUp:
            pattern = .liveTournamentMovingUp
        case .movingDown:
            pattern = .liveTournamentMovingDown
        case .hotStreak:
            pattern = .liveTournamentHotStreak
        case .leaderboardCharge:
            pattern = .liveTournamentCharge
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideRatingTierChangeHaptic(change: RatingTierChange) async {
        let pattern: GolfHapticPattern
        
        switch change {
        case .tierUp(let newTier):
            switch newTier {
            case .beginner:
                pattern = .ratingTierBeginner
            case .recreational:
                pattern = .ratingTierRecreational
            case .intermediate:
                pattern = .ratingTierIntermediate
            case .advanced:
                pattern = .ratingTierAdvanced
            case .expert:
                pattern = .ratingTierExpert
            case .professional:
                pattern = .ratingTierProfessional
            }
        case .tierDown:
            pattern = .ratingTierDown
        case .nearPromotion:
            pattern = .ratingNearPromotion
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    // MARK: Rating Engine Haptics
    
    func providePersonalBestCelebrationHaptic(scoreType: PersonalBestType) async {
        let pattern: GolfHapticPattern
        
        switch scoreType {
        case .overallBest:
            pattern = .personalBestOverall
        case .courseBest:
            pattern = .personalBestCourse
        case .nineBest:
            pattern = .personalBestNine
        case .streakBest:
            pattern = .personalBestStreak
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideHandicapMilestoneHaptic(improvement: HandicapImprovement) async {
        let pattern: GolfHapticPattern
        
        switch improvement {
        case .firstHandicap:
            pattern = .handicapFirst
        case .majorImprovement(let strokes):
            pattern = strokes >= 5 ? .handicapMajorImprovement : .handicapImprovement
        case .singleDigit:
            pattern = .handicapSingleDigit
        case .scratch:
            pattern = .handicapScratch
        case .plus:
            pattern = .handicapPlus
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func provideStrokesGainedHaptic(category: StrokesGainedCategory, achievement: StrokesGainedAchievement) async {
        let pattern: GolfHapticPattern
        
        switch (category, achievement) {
        case (.driving, .milestone):
            pattern = .strokesGainedDriving
        case (.approach, .milestone):
            pattern = .strokesGainedApproach
        case (.shortGame, .milestone):
            pattern = .strokesGainedShortGame
        case (.putting, .milestone):
            pattern = .strokesGainedPutting
        case (_, .total):
            pattern = .strokesGainedTotal
        case (_, .improvement):
            pattern = .strokesGainedImprovement
        }
        
        await playGolfHapticPattern(pattern)
        await triggerAppleWatchHaptic(pattern)
    }
    
    func providePredictivePerformanceHaptic(feedback: PerformanceFeedback) async {
        let pattern: GolfHapticPattern
        
        switch feedback {
        case .onTrack:
            pattern = .performanceOnTrack
        case .exceedingExpectations:
            pattern = .performanceExceeding
        case .underPerforming:
            pattern = .performanceUnder
        case .strongFinish:
            pattern = .performanceStrongFinish
        case .comeback:
            pattern = .performanceComeback
        }
        
        await playGolfHapticPattern(pattern)
    }
    
    // MARK: Apple Watch Coordination for Gamification
    
    func provideSynchronizedAchievementHaptic(tier: AchievementTier) async {
        await provideAchievementUnlockHaptic(tier: tier)
        // Enhanced Apple Watch coordination with achievement celebration sequence
        await triggerSynchronizedWatchCelebration(type: .achievement(tier))
    }
    
    func provideSynchronizedTournamentHaptic(progress: TournamentProgress) async {
        await provideTournamentProgressHaptic(progress: progress)
        // Enhanced Apple Watch coordination with tournament progress
        await triggerSynchronizedWatchCelebration(type: .tournament(progress))
    }
    
    func provideSynchronizedChallengeHaptic(event: ChallengeEvent) async {
        let challengePattern: GolfHapticPattern
        
        switch event {
        case .victory(let level):
            challengePattern = level == .championship ? .challengeVictoryChampionship : .challengeVictoryCompetitive
        case .invitation:
            challengePattern = .challengeInvitation
        case .milestone:
            challengePattern = .challengeMilestone
        }
        
        await playGolfHapticPattern(challengePattern)
        await triggerSynchronizedWatchCelebration(type: .challenge(event))
    }
    
    func provideSynchronizedLeaderboardHaptic(change: LeaderboardChange) async {
        let leaderboardPattern: GolfHapticPattern
        
        switch change {
        case .toFirst:
            leaderboardPattern = .leaderboardFirstPlace
        case .majorMove:
            leaderboardPattern = .leaderboardMajorMove
        case .milestone(let milestone):
            switch milestone {
            case .topTen:
                leaderboardPattern = .leaderboardTopTen
            case .topFive:
                leaderboardPattern = .leaderboardTopFive
            default:
                leaderboardPattern = .leaderboardTopThree
            }
        }
        
        await playGolfHapticPattern(leaderboardPattern)
        await triggerSynchronizedWatchCelebration(type: .leaderboard(change))
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
    
    func triggerSynchronizedWatchCelebration(type: WatchCelebrationType) async {
        // Enhanced Apple Watch coordination for gamification celebrations
        print("🍎⌚ Synchronized Watch Celebration: \(type)")
        
        // TODO: Implement enhanced WatchConnectivity with celebration sequences
        // This would coordinate multi-stage haptic celebrations between devices
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
    
    // MARK: - Gamification Haptic Patterns
    
    // Achievement System Patterns
    static let achievementBronze = GolfHapticPattern(
        name: "Achievement Bronze",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 0.6, sharpness: 0.5),
            HapticEvent(type: .continuous, time: 0.1, duration: 0.2, intensity: 0.4, sharpness: 0.3)
        ],
        duration: 0.3,
        fallbackType: .notification(.success)
    )
    
    static let achievementSilver = GolfHapticPattern(
        name: "Achievement Silver",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 0.8, sharpness: 0.7),
            HapticEvent(type: .continuous, time: 0.1, duration: 0.3, intensity: 0.6, sharpness: 0.5),
            HapticEvent(type: .impact, time: 0.4, duration: 0.1, intensity: 0.6, sharpness: 0.5)
        ],
        duration: 0.5,
        fallbackType: .sequence([.heavy, .medium])
    )
    
    static let achievementGold = GolfHapticPattern(
        name: "Achievement Gold",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 1.0, sharpness: 0.9),
            HapticEvent(type: .continuous, time: 0.1, duration: 0.4, intensity: 0.8, sharpness: 0.7),
            HapticEvent(type: .impact, time: 0.5, duration: 0.1, intensity: 0.9, sharpness: 0.8),
            HapticEvent(type: .continuous, time: 0.6, duration: 0.3, intensity: 0.5, sharpness: 0.4)
        ],
        duration: 0.9,
        fallbackType: .sequence([.heavy, .heavy, .medium])
    )
    
    static let achievementPlatinum = GolfHapticPattern(
        name: "Achievement Platinum",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 1.0, sharpness: 1.0),
            HapticEvent(type: .continuous, time: 0.1, duration: 0.3, intensity: 0.9, sharpness: 0.8),
            HapticEvent(type: .impact, time: 0.4, duration: 0.1, intensity: 1.0, sharpness: 1.0),
            HapticEvent(type: .continuous, time: 0.5, duration: 0.3, intensity: 0.7, sharpness: 0.6),
            HapticEvent(type: .impact, time: 0.8, duration: 0.1, intensity: 0.8, sharpness: 0.7)
        ],
        duration: 1.0,
        fallbackType: .sequence([.heavy, .heavy, .heavy, .medium])
    )
    
    static let achievementDiamond = GolfHapticPattern(
        name: "Achievement Diamond",
        events: [
            HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 1.0, sharpness: 1.0),
            HapticEvent(type: .continuous, time: 0.1, duration: 0.2, intensity: 1.0, sharpness: 0.9),
            HapticEvent(type: .impact, time: 0.3, duration: 0.1, intensity: 1.0, sharpness: 1.0),
            HapticEvent(type: .continuous, time: 0.4, duration: 0.2, intensity: 0.8, sharpness: 0.7),
            HapticEvent(type: .impact, time: 0.6, duration: 0.1, intensity: 1.0, sharpness: 1.0),
            HapticEvent(type: .continuous, time: 0.7, duration: 0.4, intensity: 0.6, sharpness: 0.5)
        ],
        duration: 1.2,
        fallbackType: .sequence([.heavy, .heavy, .heavy, .heavy, .light])
    )
    
    // Badge Patterns
    static let badgeScoring = createAdvancedPattern("Badge Scoring", intensity: 0.8, duration: 0.4)
    static let badgeConsistency = createAdvancedPattern("Badge Consistency", intensity: 0.7, duration: 0.3)
    static let badgeImprovement = createAdvancedPattern("Badge Improvement", intensity: 0.9, duration: 0.5)
    static let badgeSocial = createAdvancedPattern("Badge Social", intensity: 0.6, duration: 0.3)
    static let badgeTournament = createAdvancedPattern("Badge Tournament", intensity: 1.0, duration: 0.6)
    static let badgeCourse = createAdvancedPattern("Badge Course", intensity: 0.7, duration: 0.4)
    
    // Milestone Patterns
    static let milestoneFirstRound = createCelebrationPattern("First Round", intensity: 0.8, stages: 2)
    static let milestoneTenRounds = createCelebrationPattern("Ten Rounds", intensity: 0.9, stages: 3)
    static let milestoneFiftyRounds = createCelebrationPattern("Fifty Rounds", intensity: 1.0, stages: 4)
    static let milestoneHundredRounds = createCelebrationPattern("Hundred Rounds", intensity: 1.0, stages: 5)
    static let milestoneFirstBirdie = createCelebrationPattern("First Birdie", intensity: 0.9, stages: 3)
    static let milestoneFirstEagle = createCelebrationPattern("First Eagle", intensity: 1.0, stages: 4)
    static let milestoneBreakingPar = createCelebrationPattern("Breaking Par", intensity: 1.0, stages: 4)
    static let milestoneSingleDigitHandicap = createCelebrationPattern("Single Digit Handicap", intensity: 1.0, stages: 5)
    
    // Streak Patterns
    static let streakParShort = createBasicPattern(.sequence([.medium, .light]))
    static let streakParLong = createBasicPattern(.sequence([.heavy, .medium, .light]))
    static let streakBirdieShort = createBasicPattern(.sequence([.heavy, .medium]))
    static let streakBirdieLong = createBasicPattern(.sequence([.heavy, .heavy, .medium]))
    static let streakFairwayShort = createBasicPattern(.medium)
    static let streakFairwayLong = createBasicPattern(.sequence([.medium, .medium]))
    static let streakBroken = createBasicPattern(.light)
    static let streakPlayingDay = createBasicPattern(.selection)
    static let streakPlayingWeek = createBasicPattern(.sequence([.heavy, .selection]))
    
    // Challenge Patterns
    static let challengeInvitation = createBasicPattern(.selection)
    static let challengeVictoryCasual = createBasicPattern(.notification(.success))
    static let challengeVictoryCompetitive = createBasicPattern(.sequence([.heavy, .medium]))
    static let challengeVictoryProfessional = createBasicPattern(.sequence([.heavy, .heavy, .medium]))
    static let challengeVictoryChampionship = createBasicPattern(.sequence([.heavy, .heavy, .heavy, .light]))
    static let challengeMilestone = createBasicPattern(.sequence([.heavy, .medium]))
    
    // Tournament Progress Patterns
    static let tournamentQualifying = createBasicPattern(.medium)
    static let tournamentAdvancing = createBasicPattern(.sequence([.heavy, .medium]))
    static let tournamentQuarterFinal = createBasicPattern(.sequence([.heavy, .heavy]))
    static let tournamentSemiFinal = createBasicPattern(.sequence([.heavy, .heavy, .medium]))
    static let tournamentFinalRound = createBasicPattern(.sequence([.heavy, .heavy, .heavy]))
    static let tournamentChampion = createBasicPattern(.sequence([.heavy, .heavy, .heavy, .heavy, .light]))
    
    // Head-to-Head Patterns
    static let headToHeadTakingLead = createBasicPattern(.sequence([.heavy, .medium]))
    static let headToHeadTying = createBasicPattern(.medium)
    static let headToHeadFallingBehind = createBasicPattern(.light)
    static let headToHeadCloseGap = createBasicPattern(.sequence([.medium, .heavy]))
    static let headToHeadExtendingLead = createBasicPattern(.sequence([.heavy, .light]))
    
    // Friend Challenge Patterns
    static let friendChallengeInvited = createBasicPattern(.selection)
    static let friendChallengeAccepted = createBasicPattern(.medium)
    static let friendChallengeCompleted = createBasicPattern(.sequence([.medium, .light]))
    static let friendChallengeWon = createBasicPattern(.notification(.success))
    static let friendChallengeLost = createBasicPattern(.light)
    
    // Position Change Patterns
    static let positionMajorImprovement = createBasicPattern(.sequence([.heavy, .heavy, .medium]))
    static let positionImprovement = createBasicPattern(.sequence([.heavy, .medium]))
    static let positionMinorImprovement = createBasicPattern(.medium)
    static let positionStable = createBasicPattern(.light)
    static let positionMinorDecline = createBasicPattern(.light)
    static let positionMajorDecline = createBasicPattern(.sequence([.light, .light]))
    
    // Leaderboard Milestone Patterns
    static let leaderboardTopTen = createBasicPattern(.sequence([.heavy, .medium]))
    static let leaderboardTopFive = createBasicPattern(.sequence([.heavy, .heavy, .medium]))
    static let leaderboardTopThree = createBasicPattern(.sequence([.heavy, .heavy, .heavy]))
    static let leaderboardRunnerUp = createBasicPattern(.sequence([.heavy, .heavy, .heavy, .medium]))
    static let leaderboardFirstPlace = createBasicPattern(.sequence([.heavy, .heavy, .heavy, .heavy, .light]))
    static let leaderboardMajorMove = createBasicPattern(.sequence([.heavy, .heavy]))
    
    // Live Tournament Position Patterns
    static let liveTournamentMovingUp = createBasicPattern(.sequence([.medium, .heavy]))
    static let liveTournamentMovingDown = createBasicPattern(.sequence([.heavy, .light]))
    static let liveTournamentHotStreak = createBasicPattern(.sequence([.heavy, .heavy, .medium]))
    static let liveTournamentCharge = createBasicPattern(.sequence([.heavy, .heavy, .heavy]))
    
    // Rating Tier Patterns
    static let ratingTierBeginner = createBasicPattern(.light)
    static let ratingTierRecreational = createBasicPattern(.medium)
    static let ratingTierIntermediate = createBasicPattern(.sequence([.medium, .heavy]))
    static let ratingTierAdvanced = createBasicPattern(.sequence([.heavy, .medium]))
    static let ratingTierExpert = createBasicPattern(.sequence([.heavy, .heavy]))
    static let ratingTierProfessional = createBasicPattern(.sequence([.heavy, .heavy, .heavy]))
    static let ratingTierDown = createBasicPattern(.light)
    static let ratingNearPromotion = createBasicPattern(.selection)
    
    // Personal Best Patterns
    static let personalBestOverall = createBasicPattern(.sequence([.heavy, .heavy, .heavy, .light]))
    static let personalBestCourse = createBasicPattern(.sequence([.heavy, .medium]))
    static let personalBestNine = createBasicPattern(.sequence([.heavy, .light]))
    static let personalBestStreak = createBasicPattern(.sequence([.medium, .medium]))
    
    // Handicap Patterns
    static let handicapFirst = createBasicPattern(.notification(.success))
    static let handicapImprovement = createBasicPattern(.sequence([.heavy, .medium]))
    static let handicapMajorImprovement = createBasicPattern(.sequence([.heavy, .heavy, .medium]))
    static let handicapSingleDigit = createBasicPattern(.sequence([.heavy, .heavy, .heavy]))
    static let handicapScratch = createBasicPattern(.sequence([.heavy, .heavy, .heavy, .heavy]))
    static let handicapPlus = createBasicPattern(.sequence([.heavy, .heavy, .heavy, .heavy, .light]))
    
    // Strokes Gained Patterns
    static let strokesGainedDriving = createBasicPattern(.sequence([.heavy, .medium]))
    static let strokesGainedApproach = createBasicPattern(.sequence([.medium, .heavy]))
    static let strokesGainedShortGame = createBasicPattern(.sequence([.light, .heavy]))
    static let strokesGainedPutting = createBasicPattern(.sequence([.medium, .light]))
    static let strokesGainedTotal = createBasicPattern(.sequence([.heavy, .heavy, .medium]))
    static let strokesGainedImprovement = createBasicPattern(.sequence([.medium, .heavy]))
    
    // Performance Feedback Patterns
    static let performanceOnTrack = createBasicPattern(.light)
    static let performanceExceeding = createBasicPattern(.sequence([.heavy, .medium]))
    static let performanceUnder = createBasicPattern(.light)
    static let performanceStrongFinish = createBasicPattern(.sequence([.medium, .heavy]))
    static let performanceComeback = createBasicPattern(.sequence([.light, .medium, .heavy]))
    
    static func createBasicPattern(_ type: BasicHapticType) -> GolfHapticPattern {
        return GolfHapticPattern(
            name: "Basic Pattern",
            events: [HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: 0.7, sharpness: 0.5)],
            duration: 0.1,
            fallbackType: type
        )
    }
    
    static func createAdvancedPattern(_ name: String, intensity: Float, duration: TimeInterval) -> GolfHapticPattern {
        return GolfHapticPattern(
            name: name,
            events: [
                HapticEvent(type: .impact, time: 0, duration: 0.1, intensity: intensity, sharpness: intensity * 0.8),
                HapticEvent(type: .continuous, time: 0.1, duration: duration - 0.1, intensity: intensity * 0.6, sharpness: intensity * 0.4)
            ],
            duration: duration,
            fallbackType: intensity > 0.8 ? .heavy : (intensity > 0.5 ? .medium : .light)
        )
    }
    
    static func createCelebrationPattern(_ name: String, intensity: Float, stages: Int) -> GolfHapticPattern {
        var events: [HapticEvent] = []
        let stageDuration: TimeInterval = 0.15
        let totalDuration = TimeInterval(stages) * stageDuration + 0.1
        
        for i in 0..<stages {
            let time = TimeInterval(i) * stageDuration
            let stageIntensity = intensity * (1.0 - Float(i) * 0.15) // Decreasing intensity
            events.append(HapticEvent(type: .impact, time: time, duration: 0.1, intensity: stageIntensity, sharpness: stageIntensity * 0.8))
        }
        
        let fallback: BasicHapticType
        switch stages {
        case 1...2:
            fallback = .sequence([.heavy, .medium])
        case 3:
            fallback = .sequence([.heavy, .medium, .light])
        case 4:
            fallback = .sequence([.heavy, .heavy, .medium, .light])
        default:
            fallback = .sequence([.heavy, .heavy, .heavy, .medium, .light])
        }
        
        return GolfHapticPattern(
            name: name,
            events: events,
            duration: totalDuration,
            fallbackType: fallback
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

// MARK: - Gamification System Enums

enum AchievementTier {
    case bronze
    case silver
    case gold
    case platinum
    case diamond
}

enum BadgeType {
    case scoring      // Score-related achievements
    case consistency  // Consistent play achievements
    case improvement  // Improvement-based achievements
    case social       // Social/multiplayer achievements
    case tournament   // Tournament participation achievements
    case course       // Course-specific achievements
}

enum GameMilestone {
    case firstRound
    case tenRounds
    case fiftyRounds
    case hundredRounds
    case firstBirdie
    case firstEagle
    case breakingPar
    case handicapSingleDigit
}

enum StreakType {
    case parStreak(Int)
    case birdieStreak(Int)
    case fairwayStreak(Int)
    case streakBroken
    case playingStreak(Int) // Days in a row
}

enum CompetitionLevel {
    case casual
    case competitive
    case professional
    case championship
}

enum TournamentProgress {
    case qualifying
    case advancing
    case quarterFinal
    case semiFinal
    case final
    case champion
}

enum HeadToHeadStatus {
    case takingLead
    case tying
    case fallingBehind
    case closeGap
    case extendingLead
}

enum FriendChallengeEvent {
    case invited
    case accepted
    case completed
    case won
    case lost
}

enum PositionChange {
    case majorImprovement(Int) // Number of positions gained
    case minorImprovement
    case stable
    case minorDecline
    case majorDecline
}

enum LeaderboardMilestone {
    case topTen
    case topFive
    case topThree
    case runner_up
    case first
}

enum LiveTournamentPosition {
    case movingUp
    case movingDown
    case hotStreak
    case leaderboardCharge
}

enum RatingTier {
    case beginner
    case recreational
    case intermediate
    case advanced
    case expert
    case professional
}

enum RatingTierChange {
    case tierUp(RatingTier)
    case tierDown
    case nearPromotion
}

enum PersonalBestType {
    case overallBest
    case courseBest
    case nineBest
    case streakBest
}

enum HandicapImprovement {
    case firstHandicap
    case majorImprovement(Int) // Number of strokes improved
    case singleDigit
    case scratch
    case plus
}

enum StrokesGainedCategory {
    case driving
    case approach
    case shortGame
    case putting
}

enum StrokesGainedAchievement {
    case milestone
    case total
    case improvement
}

enum PerformanceFeedback {
    case onTrack
    case exceedingExpectations
    case underPerforming
    case strongFinish
    case comeback
}

// MARK: - Apple Watch Coordination Enums

enum ChallengeEvent {
    case victory(CompetitionLevel)
    case invitation
    case milestone
}

enum LeaderboardChange {
    case toFirst
    case majorMove
    case milestone(LeaderboardMilestone)
}

enum WatchCelebrationType {
    case achievement(AchievementTier)
    case tournament(TournamentProgress)
    case challenge(ChallengeEvent)
    case leaderboard(LeaderboardChange)
}