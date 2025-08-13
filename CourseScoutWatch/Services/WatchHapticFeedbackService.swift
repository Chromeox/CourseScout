import Foundation
import WatchKit
import os.log

// MARK: - Watch Haptic Feedback Service Implementation

class WatchHapticFeedbackService: WatchHapticFeedbackServiceProtocol {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "HapticFeedback")
    private var isHapticEnabled: Bool = true
    
    // Haptic timing constants
    private let lightHapticDuration: TimeInterval = 0.1
    private let mediumHapticDuration: TimeInterval = 0.15
    private let heavyHapticDuration: TimeInterval = 0.2
    
    // MARK: - Initialization
    
    init() {
        loadHapticSettings()
        logger.info("WatchHapticFeedbackService initialized")
    }
    
    // MARK: - Public Properties
    
    var isHapticEnabled: Bool {
        get { return self.isHapticEnabled }
        set { 
            self.isHapticEnabled = newValue
            saveHapticSettings()
        }
    }
    
    // MARK: - Basic Haptic Feedback
    
    func playTaptic(_ type: WatchTapticType) {
        guard isHapticEnabled else {
            logger.debug("Haptic feedback disabled, skipping \(type)")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch type {
            case .light:
                self.playSystemHaptic(.click)
                
            case .medium:
                self.playSystemHaptic(.start)
                
            case .heavy:
                self.playSystemHaptic(.stop)
                
            case .success:
                self.playSuccessSequence()
                
            case .error:
                self.playErrorSequence()
                
            case .warning:
                self.playWarningHaptic()
                
            case .notification:
                self.playNotificationHaptic()
            }
            
            self.logger.debug("Played haptic feedback: \(type)")
        }
    }
    
    // MARK: - Custom Haptic Patterns
    
    func playCustomPattern(_ pattern: WatchHapticPattern) {
        guard isHapticEnabled else {
            logger.debug("Haptic feedback disabled, skipping custom pattern")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            for event in pattern.events {
                DispatchQueue.main.asyncAfter(deadline: .now() + event.time) {
                    self.playHapticWithIntensity(event.intensity, sharpness: event.sharpness)
                }
            }
            
            self.logger.debug("Playing custom haptic pattern with \(pattern.events.count) events")
        }
    }
    
    // MARK: - Golf-Specific Haptic Sequences
    
    func playSuccessSequence() {
        guard isHapticEnabled else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Success pattern: Light -> Medium -> Light
            self.playSystemHaptic(.click)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.playSystemHaptic(.start)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.playSystemHaptic(.click)
                }
            }
            
            self.logger.debug("Played success haptic sequence")
        }
    }
    
    func playErrorSequence() {
        guard isHapticEnabled else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Error pattern: Heavy -> pause -> Heavy
            self.playSystemHaptic(.stop)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.playSystemHaptic(.stop)
            }
            
            self.logger.debug("Played error haptic sequence")
        }
    }
    
    func playNavigationFeedback() {
        guard isHapticEnabled else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Navigation pattern: Light click
            self.playSystemHaptic(.click)
            
            self.logger.debug("Played navigation haptic feedback")
        }
    }
    
    func playScoreFeedback(relativeToPar: Int) {
        guard isHapticEnabled else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch relativeToPar {
            case ...(-2): // Eagle or better
                self.playEagleHaptic()
                
            case -1: // Birdie
                self.playBirdieHaptic()
                
            case 0: // Par
                self.playParHaptic()
                
            case 1: // Bogey
                self.playBogeyHaptic()
                
            case 2...: // Double bogey or worse
                self.playDoubleBogeyHaptic()
                
            default:
                self.playSystemHaptic(.click)
            }
            
            self.logger.debug("Played score haptic feedback for \(relativeToPar) relative to par")
        }
    }
    
    // MARK: - Settings Management
    
    func setHapticEnabled(_ enabled: Bool) {
        isHapticEnabled = enabled
        saveHapticSettings()
        logger.info("Haptic feedback \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Gamification Haptic Patterns
    
    /// Play haptic feedback for leaderboard position changes
    func playLeaderboardPositionHaptic(positionChange: Int) {
        guard isHapticEnabled else { return }
        
        if abs(positionChange) >= 10 {
            // Major position change - dramatic sequence
            playDramaticPositionSequence(isImprovement: positionChange > 0)
        } else if abs(positionChange) >= 5 {
            // Significant change
            if positionChange > 0 {
                playSuccessSequence()
            } else {
                playWarningHaptic()
            }
        } else if positionChange > 0 {
            // Minor improvement
            playTaptic(.success)
        } else if positionChange < 0 {
            // Minor decline
            playTaptic(.warning)
        }
    }
    
    /// Play haptic feedback for achievement unlocks with tier-appropriate celebration
    func playAchievementHaptic(tier: String) {
        guard isHapticEnabled else { return }
        
        switch tier.lowercased() {
        case "bronze":
            playBronzeAchievementSequence()
        case "silver":
            playSilverAchievementSequence()
        case "gold":
            playGoldAchievementSequence()
        case "platinum":
            playPlatinumAchievementSequence()
        case "diamond":
            playDiamondAchievementSequence()
        default:
            playSuccessSequence()
        }
    }
    
    /// Play haptic feedback for tournament milestones
    func playTournamentMilestoneHaptic(milestone: String) {
        guard isHapticEnabled else { return }
        
        switch milestone.lowercased() {
        case "first_place", "winner":
            playTournamentVictorySequence()
        case "top_three", "podium":
            playTopThreeSequence()
        case "top_ten":
            playTopTenSequence()
        case "qualifying", "advanced":
            playQualifyingSequence()
        default:
            playTournamentProgressSequence()
        }
    }
    
    /// Play haptic feedback for rating changes
    func playRatingChangeHaptic(ratingChange: Double) {
        guard isHapticEnabled else { return }
        
        let absChange = abs(ratingChange)
        
        if absChange >= 100 {
            // Major rating change
            if ratingChange > 0 {
                playMajorImprovementSequence()
            } else {
                playMajorDeclineSequence()
            }
        } else if absChange >= 50 {
            // Significant rating change
            if ratingChange > 0 {
                playSignificantImprovementSequence()
            } else {
                playSignificantDeclineSequence()
            }
        } else if ratingChange > 0 {
            // Minor improvement
            playTaptic(.success)
        } else if ratingChange < 0 {
            // Minor decline
            playTaptic(.light)
        }
    }
    
    /// Play haptic feedback for challenge progress updates
    func playChallengeProgressHaptic(progressPercent: Double, isCompleted: Bool) {
        guard isHapticEnabled else { return }
        
        if isCompleted {
            playChallengeCompletionSequence()
        } else if progressPercent >= 0.75 {
            // Near completion
            playNearCompletionSequence()
        } else if progressPercent >= 0.5 {
            // Halfway point
            playHalfwaySequence()
        } else if progressPercent >= 0.25 {
            // Quarter progress
            playQuarterProgressSequence()
        } else {
            // Minor progress
            playTaptic(.light)
        }
    }
    
    /// Play haptic feedback for handicap improvements
    func playHandicapImprovementHaptic(improvement: Double) {
        guard isHapticEnabled else { return }
        
        if improvement >= 2.0 {
            // Major handicap improvement
            playMajorHandicapImprovementSequence()
        } else if improvement >= 1.0 {
            // Significant improvement
            playSignificantHandicapImprovementSequence()
        } else if improvement >= 0.5 {
            // Minor improvement
            playTaptic(.success)
        }
    }
    
    /// Play synchronized celebration haptic with iPhone
    func playSynchronizedCelebrationHaptic(type: CelebrationType) {
        guard isHapticEnabled else { return }
        
        switch type {
        case .achievement(let tier):
            playAchievementHaptic(tier: tier)
        case .tournament(let milestone):
            playTournamentMilestoneHaptic(milestone: milestone)
        case .rating(let change):
            playRatingChangeHaptic(ratingChange: change)
        case .challenge(let isCompleted):
            playChallengeProgressHaptic(progressPercent: isCompleted ? 1.0 : 0.5, isCompleted: isCompleted)
        }
        
        logger.info("Synchronized celebration haptic played: \(type)")
    }
    
    // MARK: - Private Gamification Haptic Sequences
    
    private func playDramaticPositionSequence(isImprovement: Bool) {
        let pattern = WatchHapticPattern(
            events: [
                WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 0.0),
                WatchHapticEvent(intensity: 0.8, sharpness: 0.8, time: 0.15),
                WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 0.3),
                WatchHapticEvent(intensity: 0.6, sharpness: 0.6, time: 0.5),
                WatchHapticEvent(intensity: 0.4, sharpness: 0.4, time: 0.7)
            ],
            duration: 0.8
        )
        
        playCustomPattern(pattern)
        
        if isImprovement {
            logger.debug("Played dramatic improvement haptic sequence")
        } else {
            logger.debug("Played dramatic decline haptic sequence")
        }
    }
    
    private func playBronzeAchievementSequence() {
        playTaptic(.medium)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.playTaptic(.light)
        }
        logger.debug("Played bronze achievement haptic")
    }
    
    private func playSilverAchievementSequence() {
        playTaptic(.medium)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.playTaptic(.medium)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.playTaptic(.light)
        }
        logger.debug("Played silver achievement haptic")
    }
    
    private func playGoldAchievementSequence() {
        playSuccessSequence()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.playTaptic(.heavy)
        }
        logger.debug("Played gold achievement haptic")
    }
    
    private func playPlatinumAchievementSequence() {
        playSuccessSequence()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.playSuccessSequence()
        }
        logger.debug("Played platinum achievement haptic")
    }
    
    private func playDiamondAchievementSequence() {
        // Epic celebration sequence
        playSuccessSequence()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.playTaptic(.heavy)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.playSuccessSequence()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.playTaptic(.heavy)
        }
        logger.debug("Played diamond achievement haptic")
    }
    
    private func playTournamentVictorySequence() {
        let victoryPattern = WatchHapticPattern(
            events: [
                WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 0.0),
                WatchHapticEvent(intensity: 0.8, sharpness: 0.8, time: 0.15),
                WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 0.3),
                WatchHapticEvent(intensity: 0.9, sharpness: 0.9, time: 0.5),
                WatchHapticEvent(intensity: 0.7, sharpness: 0.7, time: 0.7),
                WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 1.0)
            ],
            duration: 1.2
        )
        
        playCustomPattern(victoryPattern)
        logger.debug("Played tournament victory haptic")
    }
    
    private func playTopThreeSequence() {
        playTaptic(.heavy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.playTaptic(.medium)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.playTaptic(.light)
        }
        logger.debug("Played top three haptic")
    }
    
    private func playTopTenSequence() {
        playTaptic(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.playTaptic(.medium)
        }
        logger.debug("Played top ten haptic")
    }
    
    private func playQualifyingSequence() {
        playTaptic(.medium)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.playTaptic(.light)
        }
        logger.debug("Played qualifying haptic")
    }
    
    private func playTournamentProgressSequence() {
        playTaptic(.light)
        logger.debug("Played tournament progress haptic")
    }
    
    private func playMajorImprovementSequence() {
        let improvementPattern = WatchHapticPattern(
            events: [
                WatchHapticEvent(intensity: 0.6, sharpness: 0.6, time: 0.0),
                WatchHapticEvent(intensity: 0.8, sharpness: 0.8, time: 0.15),
                WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 0.3),
                WatchHapticEvent(intensity: 0.7, sharpness: 0.7, time: 0.5)
            ],
            duration: 0.6
        )
        
        playCustomPattern(improvementPattern)
        logger.debug("Played major improvement haptic")
    }
    
    private func playMajorDeclineSequence() {
        let declinePattern = WatchHapticPattern(
            events: [
                WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 0.0),
                WatchHapticEvent(intensity: 0.7, sharpness: 0.7, time: 0.2),
                WatchHapticEvent(intensity: 0.4, sharpness: 0.4, time: 0.4)
            ],
            duration: 0.5
        )
        
        playCustomPattern(declinePattern)
        logger.debug("Played major decline haptic")
    }
    
    private func playSignificantImprovementSequence() {
        playTaptic(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.playTaptic(.medium)
        }
        logger.debug("Played significant improvement haptic")
    }
    
    private func playSignificantDeclineSequence() {
        playTaptic(.warning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.playTaptic(.light)
        }
        logger.debug("Played significant decline haptic")
    }
    
    private func playChallengeCompletionSequence() {
        let completionPattern = WatchHapticPattern(
            events: [
                WatchHapticEvent(intensity: 0.8, sharpness: 0.8, time: 0.0),
                WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 0.2),
                WatchHapticEvent(intensity: 0.9, sharpness: 0.9, time: 0.4),
                WatchHapticEvent(intensity: 0.6, sharpness: 0.6, time: 0.6)
            ],
            duration: 0.7
        )
        
        playCustomPattern(completionPattern)
        logger.debug("Played challenge completion haptic")
    }
    
    private func playNearCompletionSequence() {
        playTaptic(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.playTaptic(.medium)
        }
        logger.debug("Played near completion haptic")
    }
    
    private func playHalfwaySequence() {
        playTaptic(.medium)
        logger.debug("Played halfway haptic")
    }
    
    private func playQuarterProgressSequence() {
        playTaptic(.light)
        logger.debug("Played quarter progress haptic")
    }
    
    private func playMajorHandicapImprovementSequence() {
        let handicapPattern = WatchHapticPattern(
            events: [
                WatchHapticEvent(intensity: 0.9, sharpness: 0.9, time: 0.0),
                WatchHapticEvent(intensity: 1.0, sharpness: 1.0, time: 0.2),
                WatchHapticEvent(intensity: 0.8, sharpness: 0.8, time: 0.4),
                WatchHapticEvent(intensity: 0.5, sharpness: 0.5, time: 0.6)
            ],
            duration: 0.7
        )
        
        playCustomPattern(handicapPattern)
        logger.debug("Played major handicap improvement haptic")
    }
    
    private func playSignificantHandicapImprovementSequence() {
        playTaptic(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.playTaptic(.light)
        }
        logger.debug("Played significant handicap improvement haptic")
    }
    
    // MARK: - Private Helper Methods
    
    private func playSystemHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
    
    private func playHapticWithIntensity(_ intensity: Float, sharpness: Float) {
        // For Apple Watch, we'll map intensity/sharpness to available haptic types
        let clampedIntensity = max(0.0, min(1.0, intensity))
        
        if clampedIntensity < 0.3 {
            playSystemHaptic(.click)
        } else if clampedIntensity < 0.7 {
            playSystemHaptic(.start)
        } else {
            playSystemHaptic(.stop)
        }
    }
    
    private func playWarningHaptic() {
        // Warning pattern: Medium -> Light -> Medium
        playSystemHaptic(.start)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.playSystemHaptic(.click)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.playSystemHaptic(.start)
            }
        }
    }
    
    private func playNotificationHaptic() {
        // Notification pattern: Light -> pause -> Light -> Light
        playSystemHaptic(.click)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.playSystemHaptic(.click)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.playSystemHaptic(.click)
            }
        }
    }
    
    // MARK: - Golf Score Specific Haptics
    
    private func playEagleHaptic() {
        // Eagle: Celebration pattern - Multiple light taps
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) {
                self.playSystemHaptic(.click)
            }
        }
    }
    
    private func playBirdieHaptic() {
        // Birdie: Happy pattern - Light -> Medium -> Light
        playSystemHaptic(.click)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.playSystemHaptic(.start)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.playSystemHaptic(.click)
            }
        }
    }
    
    private func playParHaptic() {
        // Par: Neutral pattern - Single medium tap
        playSystemHaptic(.start)
    }
    
    private func playBogeyHaptic() {
        // Bogey: Mild disappointment - Medium -> Light
        playSystemHaptic(.start)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.playSystemHaptic(.click)
        }
    }
    
    private func playDoubleBogeyHaptic() {
        // Double bogey or worse: Heavy disappointment - Heavy -> pause -> Heavy
        playSystemHaptic(.stop)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.playSystemHaptic(.stop)
        }
    }
    
    // MARK: - Persistence
    
    private func loadHapticSettings() {
        isHapticEnabled = UserDefaults.standard.object(forKey: "WatchHapticEnabled") as? Bool ?? true
        logger.debug("Loaded haptic settings: enabled = \(isHapticEnabled)")
    }
    
    private func saveHapticSettings() {
        UserDefaults.standard.set(isHapticEnabled, forKey: "WatchHapticEnabled")
        logger.debug("Saved haptic settings: enabled = \(isHapticEnabled)")
    }
}

// MARK: - Mock Watch Haptic Feedback Service

class MockWatchHapticFeedbackService: WatchHapticFeedbackServiceProtocol {
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "MockHapticFeedback")
    private var _isHapticEnabled: Bool = true
    private var hapticCallCount: [WatchTapticType: Int] = [:]
    
    init() {
        logger.info("MockWatchHapticFeedbackService initialized")
    }
    
    var isHapticEnabled: Bool {
        get { _isHapticEnabled }
        set { _isHapticEnabled = newValue }
    }
    
    func playTaptic(_ type: WatchTapticType) {
        guard isHapticEnabled else { return }
        
        hapticCallCount[type] = (hapticCallCount[type] ?? 0) + 1
        logger.debug("Mock haptic played: \(type) (count: \(hapticCallCount[type] ?? 1))")
    }
    
    func playCustomPattern(_ pattern: WatchHapticPattern) {
        guard isHapticEnabled else { return }
        
        logger.debug("Mock custom haptic pattern played with \(pattern.events.count) events")
    }
    
    func playSuccessSequence() {
        guard isHapticEnabled else { return }
        
        hapticCallCount[.success] = (hapticCallCount[.success] ?? 0) + 1
        logger.debug("Mock success sequence played")
    }
    
    func playErrorSequence() {
        guard isHapticEnabled else { return }
        
        hapticCallCount[.error] = (hapticCallCount[.error] ?? 0) + 1
        logger.debug("Mock error sequence played")
    }
    
    func playNavigationFeedback() {
        guard isHapticEnabled else { return }
        
        hapticCallCount[.light] = (hapticCallCount[.light] ?? 0) + 1
        logger.debug("Mock navigation feedback played")
    }
    
    func playScoreFeedback(relativeToPar: Int) {
        guard isHapticEnabled else { return }
        
        logger.debug("Mock score feedback played for \(relativeToPar) relative to par")
    }
    
    func setHapticEnabled(_ enabled: Bool) {
        _isHapticEnabled = enabled
        logger.debug("Mock haptic enabled set to: \(enabled)")
    }
    
    // MARK: - Testing Helpers
    
    func getHapticCallCount(for type: WatchTapticType) -> Int {
        return hapticCallCount[type] ?? 0
    }
    
    func getTotalHapticCalls() -> Int {
        return hapticCallCount.values.reduce(0, +)
    }
    
    func resetCallCounts() {
        hapticCallCount.removeAll()
        logger.debug("Mock haptic call counts reset")
    }
}

// MARK: - Gamification Supporting Types

enum CelebrationType {
    case achievement(String)  // tier
    case tournament(String)   // milestone
    case rating(Double)       // change amount
    case challenge(Bool)      // is completed
}