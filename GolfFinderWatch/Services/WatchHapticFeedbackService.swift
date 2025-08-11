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