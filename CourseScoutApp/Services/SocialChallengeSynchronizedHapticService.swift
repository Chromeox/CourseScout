import Foundation
import Combine
import WatchConnectivity

// MARK: - Social Challenge Synchronized Haptic Service Protocol

protocol SocialChallengeSynchronizedHapticServiceProtocol {
    // Challenge Invitation Haptics with Watch Coordination
    func provideSynchronizedChallengeInvitation(challengeId: String, challengeType: ChallengeType) async
    func provideSynchronizedInvitationAccepted(challengeId: String, participantName: String) async
    func provideSynchronizedInvitationDeclined(challengeId: String, participantName: String) async
    
    // Leaderboard Position Changes with Watch Coordination
    func provideSynchronizedPositionChange(
        challengeId: String,
        oldPosition: Int,
        newPosition: Int,
        playerName: String
    ) async
    func provideSynchronizedLeaderboardUpdate(challengeId: String, topPlayers: [String]) async
    
    // Achievement Unlocks with Watch Celebration
    func provideSynchronizedAchievementUnlock(
        achievement: SynchronizedAchievement,
        challengeContext: String?
    ) async
    
    // Real-time Challenge Events
    func provideSynchronizedScoreSubmission(
        challengeId: String,
        playerName: String,
        score: Int,
        improvement: Bool
    ) async
    func provideSynchronizedChallengeCompletion(
        challengeId: String,
        winners: [String],
        completionType: CompletionType
    ) async
    
    // Social Interaction Haptics
    func provideSynchronizedMessage(challengeId: String, senderName: String, messageType: MessageType) async
    func provideSynchronizedFriendJoined(challengeId: String, friendName: String) async
    
    // Tournament Milestone Haptics
    func provideSynchronizedTournamentMilestone(
        tournamentId: String,
        milestone: TournamentMilestone,
        playerAffected: String?
    ) async
    
    // Configuration and Status
    func setWatchHapticIntensity(_ intensity: WatchHapticIntensity)
    func enableWatchSynchronization(_ enabled: Bool)
    func getConnectionStatus() -> WatchConnectionStatus
}

// MARK: - Social Challenge Synchronized Haptic Service Implementation

@MainActor
class SocialChallengeSynchronizedHapticService: NSObject, SocialChallengeSynchronizedHapticServiceProtocol {
    
    // MARK: - Dependencies
    
    private let hapticService: HapticFeedbackServiceProtocol
    private let watchConnectivity: WCSession
    
    // MARK: - Configuration
    
    @Published private(set) var isWatchConnected = false
    @Published private(set) var watchHapticIntensity: WatchHapticIntensity = .medium
    @Published private(set) var isSynchronizationEnabled = true
    
    // MARK: - State Management
    
    private var activeChallengeSessions: Set<String> = []
    private var hapticSequenceQueue: [HapticSequenceItem] = []
    private var isProcessingSequence = false
    private let maxQueueSize = 10
    
    // MARK: - Initialization
    
    init(hapticService: HapticFeedbackServiceProtocol) {
        self.hapticService = hapticService
        self.watchConnectivity = WCSession.default
        
        super.init()
        
        setupWatchConnectivity()
    }
    
    // MARK: - Challenge Invitation Haptics
    
    func provideSynchronizedChallengeInvitation(challengeId: String, challengeType: ChallengeType) async {
        // iPhone haptic
        await hapticService.provideChallengeInvitationHaptic()
        
        // Watch coordination
        await sendWatchHaptic(.challengeInvitation(type: challengeType, intensity: watchHapticIntensity))
        
        // Add to active sessions
        activeChallengeSessions.insert(challengeId)
        
        // Send contextual data to watch
        sendWatchContext([
            "event": "challenge_invitation",
            "challengeId": challengeId,
            "challengeType": challengeType.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func provideSynchronizedInvitationAccepted(challengeId: String, participantName: String) async {
        // Sequential haptic pattern for acceptance
        await hapticService.provideFriendChallengeHaptic(challengeEvent: .accepted)
        
        // Watch celebration sequence
        await sendWatchHaptic(.invitationAccepted(participantName: participantName, intensity: watchHapticIntensity))
        
        // Delayed follow-up celebration on both devices
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task {
                await self.hapticService.provideChallengeVictoryHaptic(competitionLevel: .casual)
                await self.sendWatchHaptic(.celebration(type: .invitation, intensity: self.watchHapticIntensity))
            }
        }
        
        sendWatchContext([
            "event": "invitation_accepted",
            "challengeId": challengeId,
            "participantName": participantName,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func provideSynchronizedInvitationDeclined(challengeId: String, participantName: String) async {
        await hapticService.provideFriendChallengeHaptic(challengeEvent: .declined)
        
        await sendWatchHaptic(.invitationDeclined(participantName: participantName, intensity: watchHapticIntensity))
        
        sendWatchContext([
            "event": "invitation_declined",
            "challengeId": challengeId,
            "participantName": participantName,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Leaderboard Position Haptics
    
    func provideSynchronizedPositionChange(
        challengeId: String,
        oldPosition: Int,
        newPosition: Int,
        playerName: String
    ) async {
        let positionChange: PositionChange
        
        if newPosition < oldPosition {
            let improvement = oldPosition - newPosition
            positionChange = improvement >= 5 ? .majorImprovement(improvement) : .minorImprovement
        } else if newPosition > oldPosition {
            positionChange = .majorDecline
        } else {
            positionChange = .stable
        }
        
        // iPhone haptic based on change magnitude
        await hapticService.providePositionChangeHaptic(change: positionChange)
        
        // Watch coordination with contextual information
        await sendWatchHaptic(.positionChange(
            oldPosition: oldPosition,
            newPosition: newPosition,
            playerName: playerName,
            intensity: watchHapticIntensity
        ))
        
        // Special milestone haptic for significant improvements
        if case .majorImprovement(let positions) = positionChange, positions >= 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task {
                    await self.hapticService.provideLeaderboardMilestoneHaptic(milestone: .topTen)
                    await self.sendWatchHaptic(.milestone(type: .leaderboardBreakthrough, intensity: self.watchHapticIntensity))
                }
            }
        }
        
        sendWatchContext([
            "event": "position_change",
            "challengeId": challengeId,
            "oldPosition": oldPosition,
            "newPosition": newPosition,
            "playerName": playerName,
            "improvement": newPosition < oldPosition,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func provideSynchronizedLeaderboardUpdate(challengeId: String, topPlayers: [String]) async {
        await hapticService.provideLeaderboardUpdateHaptic(position: .improved)
        
        await sendWatchHaptic(.leaderboardUpdate(
            challengeId: challengeId,
            topPlayers: topPlayers,
            intensity: watchHapticIntensity
        ))
        
        sendWatchContext([
            "event": "leaderboard_update",
            "challengeId": challengeId,
            "topPlayers": topPlayers,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Achievement Haptics
    
    func provideSynchronizedAchievementUnlock(
        achievement: SynchronizedAchievement,
        challengeContext: String?
    ) async {
        // iPhone achievement haptic
        await hapticService.provideAchievementUnlockHaptic(tier: achievement.tier)
        
        // Watch achievement celebration sequence
        await sendWatchHaptic(.achievementUnlock(achievement: achievement, intensity: watchHapticIntensity))
        
        // Multi-stage celebration for high-tier achievements
        if achievement.tier == .platinum || achievement.tier == .diamond {
            await provideCelebrationSequence(for: achievement.tier)
        }
        
        sendWatchContext([
            "event": "achievement_unlock",
            "achievementId": achievement.id,
            "achievementName": achievement.name,
            "tier": achievement.tier.rawValue,
            "challengeContext": challengeContext,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Real-time Challenge Events
    
    func provideSynchronizedScoreSubmission(
        challengeId: String,
        playerName: String,
        score: Int,
        improvement: Bool
    ) async {
        let scoreType: ScoreType = improvement ? .birdie : .par
        await hapticService.provideScoreEntryHaptic(scoreType: scoreType)
        
        await sendWatchHaptic(.scoreSubmission(
            playerName: playerName,
            score: score,
            improvement: improvement,
            intensity: watchHapticIntensity
        ))
        
        sendWatchContext([
            "event": "score_submission",
            "challengeId": challengeId,
            "playerName": playerName,
            "score": score,
            "improvement": improvement,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func provideSynchronizedChallengeCompletion(
        challengeId: String,
        winners: [String],
        completionType: CompletionType
    ) async {
        // iPhone completion haptic
        let competitionLevel: CompetitionLevel = completionType == .tournament ? .championship : .competitive
        await hapticService.provideChallengeVictoryHaptic(competitionLevel: competitionLevel)
        
        // Watch completion celebration
        await sendWatchHaptic(.challengeCompletion(
            winners: winners,
            completionType: completionType,
            intensity: watchHapticIntensity
        ))
        
        // Extended celebration sequence for tournaments
        if completionType == .tournament {
            await provideTournamentCompletionSequence()
        }
        
        // Remove from active sessions
        activeChallengeSessions.remove(challengeId)
        
        sendWatchContext([
            "event": "challenge_completion",
            "challengeId": challengeId,
            "winners": winners,
            "completionType": completionType.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Social Interaction Haptics
    
    func provideSynchronizedMessage(challengeId: String, senderName: String, messageType: MessageType) async {
        await hapticService.provideChallengeInvitationHaptic()
        
        await sendWatchHaptic(.message(
            senderName: senderName,
            messageType: messageType,
            intensity: .light // Subtle for messages
        ))
        
        sendWatchContext([
            "event": "message_received",
            "challengeId": challengeId,
            "senderName": senderName,
            "messageType": messageType.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func provideSynchronizedFriendJoined(challengeId: String, friendName: String) async {
        await hapticService.provideFriendChallengeHaptic(challengeEvent: .accepted)
        
        await sendWatchHaptic(.friendJoined(
            friendName: friendName,
            challengeId: challengeId,
            intensity: watchHapticIntensity
        ))
        
        sendWatchContext([
            "event": "friend_joined",
            "challengeId": challengeId,
            "friendName": friendName,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Tournament Milestone Haptics
    
    func provideSynchronizedTournamentMilestone(
        tournamentId: String,
        milestone: TournamentMilestone,
        playerAffected: String?
    ) async {
        await hapticService.provideTournamentMilestoneHaptic(milestone: milestone)
        
        await sendWatchHaptic(.tournamentMilestone(
            milestone: milestone,
            playerAffected: playerAffected,
            intensity: watchHapticIntensity
        ))
        
        sendWatchContext([
            "event": "tournament_milestone",
            "tournamentId": tournamentId,
            "milestone": milestone.rawValue,
            "playerAffected": playerAffected,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Configuration Methods
    
    func setWatchHapticIntensity(_ intensity: WatchHapticIntensity) {
        watchHapticIntensity = intensity
        
        sendWatchContext([
            "configuration": "haptic_intensity",
            "intensity": intensity.rawValue
        ])
    }
    
    func enableWatchSynchronization(_ enabled: Bool) {
        isSynchronizationEnabled = enabled
        
        sendWatchContext([
            "configuration": "synchronization_enabled",
            "enabled": enabled
        ])
    }
    
    func getConnectionStatus() -> WatchConnectionStatus {
        if !WCSession.isSupported() {
            return .notSupported
        }
        
        if !watchConnectivity.isPaired {
            return .notPaired
        }
        
        if !watchConnectivity.isWatchAppInstalled {
            return .appNotInstalled
        }
        
        if !watchConnectivity.isReachable {
            return .notReachable
        }
        
        return .connected
    }
}

// MARK: - Private Implementation

private extension SocialChallengeSynchronizedHapticService {
    
    func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        
        watchConnectivity.delegate = self
        watchConnectivity.activate()
    }
    
    func sendWatchHaptic(_ haptic: WatchHapticCommand) async {
        guard isSynchronizationEnabled,
              isWatchConnected,
              watchConnectivity.isReachable else { return }
        
        let hapticData: [String: Any] = [
            "type": "haptic_command",
            "command": haptic.commandData,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        do {
            try watchConnectivity.updateApplicationContext(hapticData)
        } catch {
            print("❌ Failed to send watch haptic: \(error)")
        }
    }
    
    func sendWatchContext(_ context: [String: Any]) {
        guard isSynchronizationEnabled,
              isWatchConnected else { return }
        
        watchConnectivity.transferUserInfo(context)
    }
    
    func provideCelebrationSequence(for tier: AchievementTier) async {
        let sequenceCount = tier == .diamond ? 5 : 3
        
        for i in 0..<sequenceCount {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            
            await hapticService.provideAchievementUnlockHaptic(tier: tier)
            await sendWatchHaptic(.celebrationSequence(step: i + 1, totalSteps: sequenceCount, intensity: watchHapticIntensity))
        }
    }
    
    func provideTournamentCompletionSequence() async {
        // Tournament completion celebration sequence
        let celebrationSteps = [
            (TournamentMilestone.finalRound, 0.0),
            (TournamentMilestone.tournamentWin, 0.8),
            (TournamentMilestone.tournamentWin, 1.6),
            (TournamentMilestone.tournamentWin, 2.4)
        ]
        
        for (milestone, delay) in celebrationSteps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task {
                    await self.hapticService.provideTournamentMilestoneHaptic(milestone: milestone)
                    await self.sendWatchHaptic(.tournamentCelebration(milestone: milestone, intensity: self.watchHapticIntensity))
                }
            }
        }
    }
}

// MARK: - WCSessionDelegate Implementation

extension SocialChallengeSynchronizedHapticService: WCSessionDelegate {
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = activationState == .activated && session.isPaired && session.isReachable
        }
        
        if let error = error {
            print("❌ Watch connectivity activation failed: \(error)")
        } else {
            print("✅ Watch connectivity activated with state: \(activationState.rawValue)")
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
        }
        print("⚠️ Watch session became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
        }
        print("⚠️ Watch session deactivated")
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = session.isReachable
        }
        print("🔄 Watch reachability changed: \(session.isReachable)")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Handle messages from watch app
        if let event = message["event"] as? String {
            handleWatchEvent(event, data: message)
        }
    }
    
    private func handleWatchEvent(_ event: String, data: [String: Any]) {
        // Handle specific events from the watch app
        switch event {
        case "haptic_feedback_received":
            print("✅ Watch confirmed haptic feedback")
        case "challenge_interaction":
            // Handle challenge interactions from watch
            if let challengeId = data["challengeId"] as? String,
               let interaction = data["interaction"] as? String {
                handleWatchChallengeInteraction(challengeId: challengeId, interaction: interaction)
            }
        default:
            break
        }
    }
    
    private func handleWatchChallengeInteraction(challengeId: String, interaction: String) {
        // Process challenge interactions initiated from the watch
        Task {
            switch interaction {
            case "view_leaderboard":
                await hapticService.provideChallengeInvitationHaptic()
            case "send_encouragement":
                await hapticService.provideFriendChallengeHaptic(challengeEvent: .completed)
            default:
                break
            }
        }
    }
}

// MARK: - Supporting Types

enum ChallengeType: String, Codable {
    case strokePlay = "stroke_play"
    case tournament = "tournament"
    case skillsChallenge = "skills_challenge"
    case headToHead = "head_to_head"
}

enum CompletionType: String, Codable {
    case regular = "regular"
    case tournament = "tournament"
    case playoff = "playoff"
}

enum MessageType: String, Codable {
    case text = "text"
    case encouragement = "encouragement"
    case celebration = "celebration"
}

enum WatchHapticIntensity: String, Codable, CaseIterable {
    case light = "light"
    case medium = "medium"
    case strong = "strong"
    
    var hapticStrength: Float {
        switch self {
        case .light: return 0.3
        case .medium: return 0.6
        case .strong: return 0.9
        }
    }
}

enum WatchConnectionStatus {
    case connected
    case notSupported
    case notPaired
    case appNotInstalled
    case notReachable
    
    var displayName: String {
        switch self {
        case .connected: return "Connected"
        case .notSupported: return "Apple Watch Not Supported"
        case .notPaired: return "Apple Watch Not Paired"
        case .appNotInstalled: return "Watch App Not Installed"
        case .notReachable: return "Apple Watch Not Reachable"
        }
    }
}

struct SynchronizedAchievement {
    let id: String
    let name: String
    let tier: AchievementTier
    let iconName: String
    let category: String
}

enum WatchHapticCommand {
    case challengeInvitation(type: ChallengeType, intensity: WatchHapticIntensity)
    case invitationAccepted(participantName: String, intensity: WatchHapticIntensity)
    case invitationDeclined(participantName: String, intensity: WatchHapticIntensity)
    case positionChange(oldPosition: Int, newPosition: Int, playerName: String, intensity: WatchHapticIntensity)
    case leaderboardUpdate(challengeId: String, topPlayers: [String], intensity: WatchHapticIntensity)
    case achievementUnlock(achievement: SynchronizedAchievement, intensity: WatchHapticIntensity)
    case scoreSubmission(playerName: String, score: Int, improvement: Bool, intensity: WatchHapticIntensity)
    case challengeCompletion(winners: [String], completionType: CompletionType, intensity: WatchHapticIntensity)
    case message(senderName: String, messageType: MessageType, intensity: WatchHapticIntensity)
    case friendJoined(friendName: String, challengeId: String, intensity: WatchHapticIntensity)
    case tournamentMilestone(milestone: TournamentMilestone, playerAffected: String?, intensity: WatchHapticIntensity)
    case celebration(type: CelebrationType, intensity: WatchHapticIntensity)
    case milestone(type: MilestoneType, intensity: WatchHapticIntensity)
    case celebrationSequence(step: Int, totalSteps: Int, intensity: WatchHapticIntensity)
    case tournamentCelebration(milestone: TournamentMilestone, intensity: WatchHapticIntensity)
    
    var commandData: [String: Any] {
        switch self {
        case .challengeInvitation(let type, let intensity):
            return [
                "action": "challenge_invitation",
                "challengeType": type.rawValue,
                "intensity": intensity.rawValue
            ]
        case .invitationAccepted(let participantName, let intensity):
            return [
                "action": "invitation_accepted",
                "participantName": participantName,
                "intensity": intensity.rawValue
            ]
        case .invitationDeclined(let participantName, let intensity):
            return [
                "action": "invitation_declined",
                "participantName": participantName,
                "intensity": intensity.rawValue
            ]
        case .positionChange(let oldPosition, let newPosition, let playerName, let intensity):
            return [
                "action": "position_change",
                "oldPosition": oldPosition,
                "newPosition": newPosition,
                "playerName": playerName,
                "intensity": intensity.rawValue
            ]
        case .leaderboardUpdate(let challengeId, let topPlayers, let intensity):
            return [
                "action": "leaderboard_update",
                "challengeId": challengeId,
                "topPlayers": topPlayers,
                "intensity": intensity.rawValue
            ]
        case .achievementUnlock(let achievement, let intensity):
            return [
                "action": "achievement_unlock",
                "achievementId": achievement.id,
                "achievementName": achievement.name,
                "tier": achievement.tier.rawValue,
                "iconName": achievement.iconName,
                "intensity": intensity.rawValue
            ]
        case .scoreSubmission(let playerName, let score, let improvement, let intensity):
            return [
                "action": "score_submission",
                "playerName": playerName,
                "score": score,
                "improvement": improvement,
                "intensity": intensity.rawValue
            ]
        case .challengeCompletion(let winners, let completionType, let intensity):
            return [
                "action": "challenge_completion",
                "winners": winners,
                "completionType": completionType.rawValue,
                "intensity": intensity.rawValue
            ]
        case .message(let senderName, let messageType, let intensity):
            return [
                "action": "message",
                "senderName": senderName,
                "messageType": messageType.rawValue,
                "intensity": intensity.rawValue
            ]
        case .friendJoined(let friendName, let challengeId, let intensity):
            return [
                "action": "friend_joined",
                "friendName": friendName,
                "challengeId": challengeId,
                "intensity": intensity.rawValue
            ]
        case .tournamentMilestone(let milestone, let playerAffected, let intensity):
            return [
                "action": "tournament_milestone",
                "milestone": milestone.rawValue,
                "playerAffected": playerAffected,
                "intensity": intensity.rawValue
            ]
        case .celebration(let type, let intensity):
            return [
                "action": "celebration",
                "celebrationType": type.rawValue,
                "intensity": intensity.rawValue
            ]
        case .milestone(let type, let intensity):
            return [
                "action": "milestone",
                "milestoneType": type.rawValue,
                "intensity": intensity.rawValue
            ]
        case .celebrationSequence(let step, let totalSteps, let intensity):
            return [
                "action": "celebration_sequence",
                "step": step,
                "totalSteps": totalSteps,
                "intensity": intensity.rawValue
            ]
        case .tournamentCelebration(let milestone, let intensity):
            return [
                "action": "tournament_celebration",
                "milestone": milestone.rawValue,
                "intensity": intensity.rawValue
            ]
        }
    }
}

enum CelebrationType: String, Codable {
    case invitation = "invitation"
    case achievement = "achievement"
    case victory = "victory"
}

enum MilestoneType: String, Codable {
    case leaderboardBreakthrough = "leaderboard_breakthrough"
    case personalBest = "personal_best"
    case socialConnection = "social_connection"
}

struct HapticSequenceItem {
    let haptic: WatchHapticCommand
    let delay: TimeInterval
    let timestamp: Date
}

// MARK: - Mock Service for Preview/Testing

class MockSocialChallengeSynchronizedHapticService: SocialChallengeSynchronizedHapticServiceProtocol {
    
    func provideSynchronizedChallengeInvitation(challengeId: String, challengeType: ChallengeType) async {
        print("🔄 Mock: Challenge invitation sent - \(challengeType.rawValue)")
    }
    
    func provideSynchronizedInvitationAccepted(challengeId: String, participantName: String) async {
        print("✅ Mock: \(participantName) accepted invitation")
    }
    
    func provideSynchronizedInvitationDeclined(challengeId: String, participantName: String) async {
        print("❌ Mock: \(participantName) declined invitation")
    }
    
    func provideSynchronizedPositionChange(challengeId: String, oldPosition: Int, newPosition: Int, playerName: String) async {
        print("📊 Mock: \(playerName) moved from position \(oldPosition) to \(newPosition)")
    }
    
    func provideSynchronizedLeaderboardUpdate(challengeId: String, topPlayers: [String]) async {
        print("🏆 Mock: Leaderboard updated with top players: \(topPlayers.joined(separator: ", "))")
    }
    
    func provideSynchronizedAchievementUnlock(achievement: SynchronizedAchievement, challengeContext: String?) async {
        print("🎖️ Mock: Achievement unlocked - \(achievement.name) (\(achievement.tier.rawValue))")
    }
    
    func provideSynchronizedScoreSubmission(challengeId: String, playerName: String, score: Int, improvement: Bool) async {
        print("⛳ Mock: \(playerName) submitted score: \(score) \(improvement ? "(improved!)" : "")")
    }
    
    func provideSynchronizedChallengeCompletion(challengeId: String, winners: [String], completionType: CompletionType) async {
        print("🏁 Mock: Challenge completed - Winners: \(winners.joined(separator: ", "))")
    }
    
    func provideSynchronizedMessage(challengeId: String, senderName: String, messageType: MessageType) async {
        print("💬 Mock: Message from \(senderName) - \(messageType.rawValue)")
    }
    
    func provideSynchronizedFriendJoined(challengeId: String, friendName: String) async {
        print("👥 Mock: \(friendName) joined the challenge")
    }
    
    func provideSynchronizedTournamentMilestone(tournamentId: String, milestone: TournamentMilestone, playerAffected: String?) async {
        print("🏆 Mock: Tournament milestone - \(milestone.rawValue)")
    }
    
    func setWatchHapticIntensity(_ intensity: WatchHapticIntensity) {
        print("⚙️ Mock: Watch haptic intensity set to \(intensity.rawValue)")
    }
    
    func enableWatchSynchronization(_ enabled: Bool) {
        print("⚙️ Mock: Watch synchronization \(enabled ? "enabled" : "disabled")")
    }
    
    func getConnectionStatus() -> WatchConnectionStatus {
        return .connected
    }
}