import SwiftUI
import WatchKit
import Combine

// MARK: - Watch Challenge Tracking View

struct WatchChallengeTrackingView: View {
    @StateObject private var gamificationService: WatchGamificationService
    @StateObject private var hapticService: WatchHapticFeedbackService
    @StateObject private var connectivityService: WatchConnectivityService
    @StateObject private var synchronizedHapticService: SocialChallengeSynchronizedHapticService
    
    @State private var activeChallenges: [LiveChallenge] = []
    @State private var selectedChallenge: LiveChallenge?
    @State private var currentChallengeIndex = 0
    @State private var showMilestoneAlert = false
    @State private var milestoneAlert: MilestoneAlert?
    @State private var lastUpdateTime: Date = Date()
    @State private var cancellables = Set<AnyCancellable>()
    
    // Animation states
    @State private var progressAnimationValue: Double = 0
    @State private var showCompletionCelebration = false
    @State private var pulseAnimation = false
    
    // Configuration
    private let refreshInterval: TimeInterval = 30.0
    private let maxVisibleChallenges = 3
    
    init(
        gamificationService: WatchGamificationService,
        hapticService: WatchHapticFeedbackService,
        connectivityService: WatchConnectivityService,
        synchronizedHapticService: SocialChallengeSynchronizedHapticService
    ) {
        self._gamificationService = StateObject(wrappedValue: gamificationService)
        self._hapticService = StateObject(wrappedValue: hapticService)
        self._connectivityService = StateObject(wrappedValue: connectivityService)
        self._synchronizedHapticService = StateObject(wrappedValue: synchronizedHapticService)
    }
    
    var body: some View {
        ZStack {
            // Dynamic background based on challenge activity
            challengeBackground
                .ignoresSafeArea()
            
            VStack(spacing: 6) {
                // Challenge selector header
                challengeHeaderView
                
                // Current challenge details
                if let challenge = selectedChallenge {
                    currentChallengeView(challenge)
                } else {
                    noChallengesView
                }
                
                // Challenge navigation
                if activeChallenges.count > 1 {
                    challengeNavigationView
                }
                
                // Last update info
                updateInfoView
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            // Milestone alert overlay
            if showMilestoneAlert, let alert = milestoneAlert {
                milestoneAlertOverlay(alert)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: showMilestoneAlert)
            }
            
            // Completion celebration overlay
            if showCompletionCelebration {
                completionCelebrationOverlay
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 1.0, dampingFraction: 0.6), value: showCompletionCelebration)
            }
        }
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupChallengeTracking()
        }
        .onDisappear {
            stopChallengeTracking()
        }
        .refreshable {
            await refreshChallengeData()
        }
        .digitalCrownRotation(
            .constant(Double(currentChallengeIndex)),
            from: 0,
            through: max(0, Double(activeChallenges.count - 1)),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        ) { crownValue in
            let newIndex = Int(crownValue.rounded())
            if newIndex != currentChallengeIndex && newIndex < activeChallenges.count {
                currentChallengeIndex = newIndex
                selectedChallenge = activeChallenges[newIndex]
                hapticService.playTaptic(.light)
            }
        }
    }
    
    // MARK: - View Components
    
    private var challengeBackground: LinearGradient {
        if let challenge = selectedChallenge, challenge.isActive {
            return LinearGradient(
                colors: [
                    challengeTypeColor(challenge.type).opacity(0.3),
                    challengeTypeColor(challenge.type).opacity(0.1),
                    Color.black.opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color.gray.opacity(0.2), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var challengeHeaderView: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Active Challenges")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if !activeChallenges.isEmpty {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(), value: pulseAnimation)
                }
                
                Spacer()
                
                Text("\(activeChallenges.count) Active")
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .fontWeight(.medium)
            }
            
            if activeChallenges.count > 1 {
                Text("Crown to navigate")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            pulseAnimation = !activeChallenges.isEmpty
        }
    }
    
    private func currentChallengeView(_ challenge: LiveChallenge) -> some View {
        VStack(spacing: 8) {
            // Challenge header
            challengeTitleCard(challenge)
            
            // Progress section
            challengeProgressSection(challenge)
            
            // Challenge details based on type
            switch challenge.type {
            case .headToHead:
                headToHeadChallengeView(challenge)
            case .tournament:
                tournamentChallengeView(challenge)
            case .achievement:
                achievementChallengeView(challenge)
            case .social:
                socialChallengeView(challenge)
            }
            
            // Challenge actions
            challengeActionsView(challenge)
        }
    }
    
    private func challengeTitleCard(_ challenge: LiveChallenge) -> some View {
        VStack(spacing: 4) {
            HStack {
                // Challenge type icon
                Image(systemName: challengeTypeIcon(challenge.type))
                    .foregroundColor(challengeTypeColor(challenge.type))
                    .font(.caption)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(challenge.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Status indicator
                challengeStatusBadge(challenge.status)
            }
            
            // Time remaining
            if let timeRemaining = challenge.timeRemaining, timeRemaining > 0 {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                    Text(timeRemainingString(timeRemaining))
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(challengeTypeColor(challenge.type).opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(challengeTypeColor(challenge.type).opacity(0.5), lineWidth: 1)
                )
        )
    }
    
    private func challengeProgressSection(_ challenge: LiveChallenge) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Progress")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(challenge.progress.percentComplete))%")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)
                    
                    Rectangle()
                        .fill(progressGradient(for: challenge))
                        .frame(width: geometry.size.width * (challenge.progress.percentComplete / 100), height: 6)
                        .animation(.easeInOut(duration: 1.0), value: challenge.progress.percentComplete)
                    
                    // Milestone markers
                    ForEach(challenge.milestones, id: \.threshold) { milestone in
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: 8)
                            .offset(x: geometry.size.width * (milestone.threshold / 100) - 1)
                    }
                }
                .cornerRadius(3)
            }
            .frame(height: 6)
            
            // Current milestone info
            if let currentMilestone = challenge.currentMilestone {
                Text(currentMilestone.description)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func headToHeadChallengeView(_ challenge: LiveChallenge) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("Head-to-Head")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            if let headToHeadData = challenge.headToHeadData {
                HStack {
                    // Player score
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You")
                            .font(.caption2)
                            .foregroundColor(.primary)
                        Text("\(headToHeadData.playerScore)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    // VS indicator
                    Text("vs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Opponent score
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(headToHeadData.opponentName)
                            .font(.caption2)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text("\(headToHeadData.opponentScore)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                }
                
                // Match status
                if !headToHeadData.matchStatus.isEmpty {
                    Text(headToHeadData.matchStatus)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(matchStatusColor(headToHeadData.matchStatus))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(matchStatusColor(headToHeadData.matchStatus).opacity(0.2))
                        )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private func tournamentChallengeView(_ challenge: LiveChallenge) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("Tournament")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let tournamentData = challenge.tournamentData {
                    Text("Round \(tournamentData.currentRound)/\(tournamentData.totalRounds)")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
            }
            
            if let tournamentData = challenge.tournamentData {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Position")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("#\(tournamentData.currentPosition)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(positionColor(tournamentData.currentPosition))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Players")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(tournamentData.totalPlayers)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                }
                
                if let nextRound = tournamentData.nextRound {
                    Text("Next: \(nextRound)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.2))
                        )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private func achievementChallengeView(_ challenge: LiveChallenge) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("Achievement")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let achievementData = challenge.achievementData {
                    Text(achievementData.tier.capitalized)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(tierColor(achievementData.tier))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(tierColor(achievementData.tier).opacity(0.2))
                        )
                }
            }
            
            if let achievementData = challenge.achievementData {
                VStack(spacing: 2) {
                    HStack {
                        Text("\(achievementData.currentValue)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        
                        Text("/ \(achievementData.targetValue)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(achievementData.unit)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if !achievementData.description.isEmpty {
                        Text(achievementData.description)
                            .font(.caption2)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private func socialChallengeView(_ challenge: LiveChallenge) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("Social Challenge")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let socialData = challenge.socialData {
                    Text("\(socialData.participantsCount) players")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
            }
            
            if let socialData = challenge.socialData {
                VStack(spacing: 3) {
                    // Friends participating
                    if !socialData.friendsParticipating.isEmpty {
                        HStack {
                            Text("Friends:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text(socialData.friendsParticipating.prefix(2).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if socialData.friendsParticipating.count > 2 {
                                Text("+\(socialData.friendsParticipating.count - 2)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    // Current standings
                    HStack {
                        Text("Your rank:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("#\(socialData.currentRank)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(positionColor(socialData.currentRank))
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private func challengeActionsView(_ challenge: LiveChallenge) -> some View {
        HStack(spacing: 8) {
            // Quick action based on challenge type
            Button(action: {
                performQuickAction(for: challenge)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: quickActionIcon(for: challenge))
                        .font(.caption)
                    Text(quickActionTitle(for: challenge))
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(challengeTypeColor(challenge.type))
                )
                .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // View details button
            Button(action: {
                viewChallengeDetails(challenge)
            }) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var challengeNavigationView: some View {
        HStack {
            ForEach(0..<min(activeChallenges.count, maxVisibleChallenges), id: \.self) { index in
                Button(action: {
                    currentChallengeIndex = index
                    selectedChallenge = activeChallenges[index]
                    hapticService.playTaptic(.light)
                }) {
                    Circle()
                        .fill(index == currentChallengeIndex ? challengeTypeColor(activeChallenges[index].type) : Color.gray)
                        .frame(width: 8, height: 8)
                        .scaleEffect(index == currentChallengeIndex ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: currentChallengeIndex)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if activeChallenges.count > maxVisibleChallenges {
                Text("+\(activeChallenges.count - maxVisibleChallenges)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var noChallengesView: some View {
        VStack(spacing: 8) {
            Image(systemName: "target")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("No Active Challenges")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Check your iPhone to join challenges")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var updateInfoView: some View {
        VStack(spacing: 2) {
            Text("Last Updated")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(timeAgoString(from: lastUpdateTime))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Overlay Views
    
    private func milestoneAlertOverlay(_ alert: MilestoneAlert) -> some View {
        VStack(spacing: 12) {
            // Milestone icon
            Image(systemName: alert.icon)
                .font(.largeTitle)
                .foregroundColor(alert.color)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true), value: pulseAnimation)
            
            // Milestone text
            VStack(spacing: 4) {
                Text(alert.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(alert.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Progress indicator
            Text("\(Int(alert.progressPercent))% Complete")
                .font(.caption2)
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(alert.color.opacity(0.2))
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(alert.color, lineWidth: 2)
                )
        )
        .onAppear {
            pulseAnimation = true
            
            // Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                showMilestoneAlert = false
                pulseAnimation = false
            }
        }
    }
    
    private var completionCelebrationOverlay: some View {
        VStack(spacing: 16) {
            // Celebration animation
            Image(systemName: "party.popper.fill")
                .font(.system(size: 40))
                .foregroundColor(.yellow)
                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulseAnimation)
            
            VStack(spacing: 8) {
                Text("Challenge Complete!")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
                
                if let challenge = selectedChallenge {
                    Text(challenge.title)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.yellow, lineWidth: 3)
                )
        )
        .onAppear {
            pulseAnimation = true
            
            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                showCompletionCelebration = false
                pulseAnimation = false
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func challengeTypeColor(_ type: ChallengeType) -> Color {
        switch type {
        case .headToHead:
            return .red
        case .tournament:
            return .blue
        case .achievement:
            return .purple
        case .social:
            return .green
        }
    }
    
    private func challengeTypeIcon(_ type: ChallengeType) -> String {
        switch type {
        case .headToHead:
            return "person.2"
        case .tournament:
            return "trophy"
        case .achievement:
            return "target"
        case .social:
            return "person.3"
        }
    }
    
    private func challengeStatusBadge(_ status: ChallengeStatus) -> some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(status.color)
            )
    }
    
    private func progressGradient(for challenge: LiveChallenge) -> LinearGradient {
        let progress = challenge.progress.percentComplete / 100
        
        if progress < 0.25 {
            return LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
        } else if progress < 0.5 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        } else if progress < 0.75 {
            return LinearGradient(colors: [.yellow, .green], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.green, .blue], startPoint: .leading, endPoint: .trailing)
        }
    }
    
    private func positionColor(_ position: Int) -> Color {
        switch position {
        case 1:
            return .yellow
        case 2, 3:
            return .orange
        case 4...10:
            return .green
        default:
            return .primary
        }
    }
    
    private func tierColor(_ tier: String) -> Color {
        switch tier.lowercased() {
        case "bronze":
            return .orange
        case "silver":
            return .gray
        case "gold":
            return .yellow
        case "platinum":
            return .cyan
        case "diamond":
            return .purple
        default:
            return .primary
        }
    }
    
    private func matchStatusColor(_ status: String) -> Color {
        if status.contains("up") {
            return .green
        } else if status.contains("down") {
            return .red
        } else {
            return .orange
        }
    }
    
    private func quickActionIcon(for challenge: LiveChallenge) -> String {
        switch challenge.type {
        case .headToHead:
            return "sportscourt"
        case .tournament:
            return "list.number"
        case .achievement:
            return "target"
        case .social:
            return "message"
        }
    }
    
    private func quickActionTitle(for challenge: LiveChallenge) -> String {
        switch challenge.type {
        case .headToHead:
            return "Score"
        case .tournament:
            return "Standings"
        case .achievement:
            return "Progress"
        case .social:
            return "Chat"
        }
    }
    
    private func timeRemainingString(_ timeRemaining: TimeInterval) -> String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else {
            return "\(minutes)m left"
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
    
    // MARK: - Challenge Management
    
    private func setupChallengeTracking() {
        logger.debug("Setting up challenge tracking")
        
        // Subscribe to challenge updates
        connectivityService.subscribeTo(.liveHeadToHeadUpdate) { [weak self] data in
            await self?.handleHeadToHeadUpdate(data)
        }
        
        connectivityService.subscribeTo(.challengeMilestoneProgress) { [weak self] data in
            await self?.handleMilestoneProgress(data)
        }
        
        connectivityService.subscribeTo(.challengeCompletionAlert) { [weak self] data in
            await self?.handleChallengeCompletion(data)
        }
        
        // Subscribe to gamification service updates
        gamificationService.subscribeToChallengeUpdates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] challengeUpdate in
                self?.handleChallengeUpdate(challengeUpdate)
            }
            .store(in: &cancellables)
        
        // Load initial challenges
        loadActiveChallenges()
        
        // Setup refresh timer
        Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshChallengeData()
            }
        }
    }
    
    private func stopChallengeTracking() {
        cancellables.removeAll()
        logger.debug("Stopped challenge tracking")
    }
    
    private func loadActiveChallenges() {
        activeChallenges = gamificationService.getActiveChallenges().compactMap { activeChallenge in
            LiveChallenge(from: activeChallenge)
        }
        
        if !activeChallenges.isEmpty {
            selectedChallenge = activeChallenges[0]
            currentChallengeIndex = 0
        }
    }
    
    @MainActor
    private func handleHeadToHeadUpdate(_ data: [String: Any]) async {
        guard let challengeId = data["challengeId"] as? String else { return }
        
        // Update the specific head-to-head challenge
        if let index = activeChallenges.firstIndex(where: { $0.id == challengeId }) {
            activeChallenges[index].updateHeadToHeadData(from: data)
            
            // Trigger haptic feedback for score changes
            if let matchStatus = data["matchStatus"] as? String {
                hapticService.playTaptic(matchStatus.contains("up") ? .success : .warning)
            }
        }
    }
    
    @MainActor
    private func handleMilestoneProgress(_ data: [String: Any]) async {
        guard let challengeId = data["challengeId"] as? String,
              let progress = data["progress"] as? Double,
              let target = data["target"] as? Double,
              let milestoneType = data["milestoneType"] as? String else { return }
        
        let progressPercent = (progress / target) * 100
        
        // Show milestone alert
        milestoneAlert = MilestoneAlert(
            title: "Milestone Reached!",
            description: milestoneType,
            progressPercent: progressPercent,
            icon: "flag.checkered",
            color: .orange
        )
        
        showMilestoneAlert = true
        
        // Play synchronized milestone haptic for challenges
        Task {
            await synchronizedHapticService.provideSynchronizedMilestoneReached(
                challengeId: challengeId,
                milestone: ChallengeMilestone(rawValue: milestoneType) ?? .halfwayPoint,
                playerName: "You",
                progressPercent: progressPercent
            )
        }
    }
    
    @MainActor
    private func handleChallengeCompletion(_ data: [String: Any]) async {
        guard let challengeId = data["challengeId"] as? String else { return }
        
        // Show completion celebration
        showCompletionCelebration = true
        
        // Play synchronized challenge completion haptic
        Task {
            await synchronizedHapticService.provideSynchronizedChallengeCompletion(
                challengeId: challengeId,
                winnerName: "You",
                completionTime: Date(),
                challengeType: activeChallenges.first { $0.id == challengeId }?.type ?? .achievement
            )
        }
        
        // Update challenge status
        if let index = activeChallenges.firstIndex(where: { $0.id == challengeId }) {
            activeChallenges[index].markAsCompleted()
        }
    }
    
    private func handleChallengeUpdate(_ challengeUpdate: ChallengeUpdate) {
        // Handle general challenge updates from the gamification service
        // Update UI based on challenge update type
    }
    
    private func refreshChallengeData() async {
        lastUpdateTime = Date()
        loadActiveChallenges()
    }
    
    private func performQuickAction(for challenge: LiveChallenge) {
        hapticService.playTaptic(.medium)
        
        switch challenge.type {
        case .headToHead:
            // Navigate to score entry or current match view
            break
        case .tournament:
            // Show tournament standings
            break
        case .achievement:
            // Show detailed progress
            break
        case .social:
            // Open challenge chat or social features
            break
        }
    }
    
    private func viewChallengeDetails(_ challenge: LiveChallenge) {
        hapticService.playTaptic(.light)
        // Navigate to detailed challenge view
    }
}

// MARK: - Supporting Data Models

struct LiveChallenge: Identifiable {
    let id: String
    let title: String
    let description: String
    let type: ChallengeType
    var status: ChallengeStatus
    var progress: ChallengeProgress
    let milestones: [ChallengeMilestone]
    var currentMilestone: ChallengeMilestone?
    var timeRemaining: TimeInterval?
    var isActive: Bool
    
    // Type-specific data
    var headToHeadData: HeadToHeadData?
    var tournamentData: TournamentData?
    var achievementData: AchievementData?
    var socialData: SocialData?
    
    init?(from activeChallenge: ActiveChallenge) {
        self.id = activeChallenge.challengeId
        self.title = activeChallenge.title
        self.description = "Challenge description" // Would be loaded from full challenge data
        self.type = activeChallenge.type
        self.status = .active
        self.progress = activeChallenge.progress
        self.milestones = [] // Would be loaded from challenge definition
        self.isActive = true
        
        // Initialize type-specific data based on challenge type
        switch activeChallenge.type {
        case .headToHead:
            self.headToHeadData = HeadToHeadData(
                playerScore: 0,
                opponentScore: 0,
                opponentName: "Opponent",
                matchStatus: "All Square",
                holesRemaining: 18
            )
        case .tournament:
            self.tournamentData = TournamentData(
                currentPosition: 1,
                totalPlayers: 64,
                currentRound: 1,
                totalRounds: 4,
                nextRound: nil
            )
        case .achievement:
            self.achievementData = AchievementData(
                tier: "Bronze",
                currentValue: 5,
                targetValue: 10,
                unit: "rounds",
                description: "Complete rounds to unlock"
            )
        case .social:
            self.socialData = SocialData(
                participantsCount: 8,
                friendsParticipating: [],
                currentRank: 3
            )
        }
    }
    
    mutating func updateHeadToHeadData(from data: [String: Any]) {
        guard let playerScore = data["playerScore"] as? Int,
              let opponentScore = data["opponentScore"] as? Int,
              let matchStatus = data["matchStatus"] as? String else { return }
        
        self.headToHeadData = HeadToHeadData(
            playerScore: playerScore,
            opponentScore: opponentScore,
            opponentName: headToHeadData?.opponentName ?? "Opponent",
            matchStatus: matchStatus,
            holesRemaining: data["holesRemaining"] as? Int ?? 0
        )
    }
    
    mutating func markAsCompleted() {
        self.status = .completed
        self.isActive = false
        self.progress = ChallengeProgress(
            completedSteps: progress.totalSteps,
            totalSteps: progress.totalSteps,
            percentComplete: 100.0,
            isCompleted: true,
            currentScore: progress.currentScore,
            targetScore: progress.targetScore
        )
    }
}

enum ChallengeStatus {
    case active
    case completed
    case paused
    case expired
    
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .completed: return "Complete"
        case .paused: return "Paused"
        case .expired: return "Expired"
        }
    }
    
    var color: Color {
        switch self {
        case .active: return .green
        case .completed: return .blue
        case .paused: return .orange
        case .expired: return .red
        }
    }
}

struct ChallengeMilestone {
    let threshold: Double // Percentage
    let title: String
    let description: String
    let icon: String
}

struct HeadToHeadData {
    let playerScore: Int
    let opponentScore: Int
    let opponentName: String
    let matchStatus: String
    let holesRemaining: Int
}

struct TournamentData {
    let currentPosition: Int
    let totalPlayers: Int
    let currentRound: Int
    let totalRounds: Int
    let nextRound: String?
}

struct AchievementData {
    let tier: String
    let currentValue: Int
    let targetValue: Int
    let unit: String
    let description: String
}

struct SocialData {
    let participantsCount: Int
    let friendsParticipating: [String]
    let currentRank: Int
}

struct MilestoneAlert {
    let title: String
    let description: String
    let progressPercent: Double
    let icon: String
    let color: Color
}

// MARK: - Preview Support

struct WatchChallengeTrackingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WatchChallengeTrackingView(
                gamificationService: MockWatchGamificationService() as! WatchGamificationService,
                hapticService: MockWatchHapticFeedbackService(),
                connectivityService: MockWatchConnectivityService() as! WatchConnectivityService
            )
        }
        .previewDevice("Apple Watch Series 9 - 45mm")
    }
}