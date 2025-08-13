import SwiftUI
import WatchKit
import Combine

// MARK: - Watch Challenge Progress View

struct WatchChallengeProgressView: View {
    @StateObject private var gamificationService: WatchGamificationService
    @StateObject private var hapticService: WatchHapticFeedbackService
    @State private var activeChallenges: [ActiveChallenge] = []
    @State private var selectedChallenge: ActiveChallenge?
    @State private var showingChallengeDetail = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isRefreshing = false
    
    // Animation states
    @State private var progressAnimationValue: Double = 0
    @State private var pulsatingChallenge: String?
    
    init(gamificationService: WatchGamificationService, hapticService: WatchHapticFeedbackService) {
        self._gamificationService = StateObject(wrappedValue: gamificationService)
        self._hapticService = StateObject(wrappedValue: hapticService)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                if activeChallenges.isEmpty {
                    emptyChallengesView
                } else {
                    challengeListView
                }
            }
            .navigationTitle("Challenges")
            .onAppear {
                setupChallengeTracking()
            }
            .onDisappear {
                cancellables.removeAll()
            }
            .refreshable {
                await refreshChallenges()
            }
        }
        .fullScreenCover(isPresented: $showingChallengeDetail) {
            if let challenge = selectedChallenge {
                WatchChallengeDetailView(
                    challenge: challenge,
                    gamificationService: gamificationService,
                    hapticService: hapticService
                )
            }
        }
    }
    
    // MARK: - View Components
    
    private var emptyChallengesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.2.crossed")
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text("No Active Challenges")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text("Start a challenge to track your progress here")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var challengeListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(activeChallenges, id: \.challengeId) { challenge in
                    challengeCardView(challenge)
                        .onTapGesture {
                            selectedChallenge = challenge
                            showingChallengeDetail = true
                            hapticService.playTaptic(.light)
                        }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func challengeCardView(_ challenge: ActiveChallenge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Challenge header
            challengeHeaderView(challenge)
            
            // Progress indicator
            challengeProgressView(challenge)
            
            // Challenge details
            challengeDetailsView(challenge)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(challengeBackgroundColor(challenge))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(challengeBorderColor(challenge), lineWidth: 1)
                )
        )
        .scaleEffect(pulsatingChallenge == challenge.challengeId ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: pulsatingChallenge)
    }
    
    private func challengeHeaderView(_ challenge: ActiveChallenge) -> some View {
        HStack {
            // Challenge type icon
            Image(systemName: challengeTypeIcon(challenge.type))
                .foregroundColor(challengeTypeColor(challenge.type))
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text(challengeTypeText(challenge.type))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicator
            challengeStatusIndicator(challenge)
        }
    }
    
    private func challengeProgressView(_ challenge: ActiveChallenge) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Progress")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(challenge.progress.percentComplete * 100))%")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor(challenge.progress.percentComplete))
                        .frame(
                            width: geometry.size.width * progressAnimationValue,
                            height: 4
                        )
                        .animation(.easeInOut(duration: 0.8), value: progressAnimationValue)
                }
            }
            .frame(height: 4)
            .onAppear {
                progressAnimationValue = challenge.progress.percentComplete
            }
        }
    }
    
    private func challengeDetailsView(_ challenge: ActiveChallenge) -> some View {
        HStack {
            // Current score/status
            VStack(alignment: .leading, spacing: 2) {
                Text("Current")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if let currentScore = challenge.progress.currentScore {
                    Text("\(currentScore)")
                        .font(.caption)
                        .fontWeight(.semibold)
                } else {
                    Text("--")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Target score
            if let targetScore = challenge.progress.targetScore {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Target")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(targetScore)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            
            Spacer()
            
            // Time remaining or completion status
            VStack(alignment: .trailing, spacing: 2) {
                Text("Status")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(challengeStatusText(challenge))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(challengeStatusColor(challenge))
            }
        }
    }
    
    private func challengeStatusIndicator(_ challenge: ActiveChallenge) -> some View {
        Circle()
            .fill(challengeStatusColor(challenge))
            .frame(width: 8, height: 8)
    }
    
    // MARK: - Helper Methods
    
    private func challengeTypeIcon(_ type: ChallengeType) -> String {
        switch type {
        case .headToHead:
            return "person.2"
        case .tournament:
            return "trophy"
        case .achievement:
            return "star"
        case .social:
            return "person.3"
        }
    }
    
    private func challengeTypeColor(_ type: ChallengeType) -> Color {
        switch type {
        case .headToHead:
            return .orange
        case .tournament:
            return .yellow
        case .achievement:
            return .purple
        case .social:
            return .blue
        }
    }
    
    private func challengeTypeText(_ type: ChallengeType) -> String {
        switch type {
        case .headToHead:
            return "Head-to-Head"
        case .tournament:
            return "Tournament"
        case .achievement:
            return "Achievement"
        case .social:
            return "Social"
        }
    }
    
    private func challengeBackgroundColor(_ challenge: ActiveChallenge) -> Color {
        if challenge.progress.isCompleted {
            return Color.green.opacity(0.15)
        } else if challenge.progress.percentComplete > 0.75 {
            return Color.yellow.opacity(0.15)
        } else {
            return Color.gray.opacity(0.1)
        }
    }
    
    private func challengeBorderColor(_ challenge: ActiveChallenge) -> Color {
        if challenge.progress.isCompleted {
            return Color.green.opacity(0.5)
        } else if challenge.progress.percentComplete > 0.75 {
            return Color.yellow.opacity(0.5)
        } else {
            return Color.gray.opacity(0.3)
        }
    }
    
    private func progressColor(_ progress: Double) -> Color {
        if progress >= 1.0 {
            return .green
        } else if progress >= 0.75 {
            return .yellow
        } else if progress >= 0.5 {
            return .orange
        } else {
            return .blue
        }
    }
    
    private func challengeStatusText(_ challenge: ActiveChallenge) -> String {
        if challenge.progress.isCompleted {
            return "Complete"
        } else {
            let remainingSteps = challenge.progress.totalSteps - challenge.progress.completedSteps
            return "\(remainingSteps) left"
        }
    }
    
    private func challengeStatusColor(_ challenge: ActiveChallenge) -> Color {
        if challenge.progress.isCompleted {
            return .green
        } else if challenge.progress.percentComplete > 0.75 {
            return .yellow
        } else {
            return .orange
        }
    }
    
    // MARK: - Setup and Event Handling
    
    private func setupChallengeTracking() {
        // Subscribe to challenge updates
        gamificationService.subscribeToChallengeUpdates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] challengeUpdate in
                self?.handleChallengeUpdate(challengeUpdate)
            }
            .store(in: &cancellables)
        
        // Load current challenges
        activeChallenges = gamificationService.getActiveChallenges()
    }
    
    private func handleChallengeUpdate(_ update: ChallengeUpdate) {
        // Find and update the specific challenge
        if let index = activeChallenges.firstIndex(where: { $0.challengeId == update.challengeId }) {
            let challenge = activeChallenges[index]
            
            // Trigger visual feedback for updates
            withAnimation(.easeInOut(duration: 0.3)) {
                pulsatingChallenge = update.challengeId
            }
            
            // Reset pulsation after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                pulsatingChallenge = nil
            }
            
            // Trigger haptic feedback for significant progress
            if challenge.progress.percentComplete < 0.75 && challenge.progress.percentComplete >= 0.75 {
                hapticService.playTaptic(.success)
            } else if challenge.progress.isCompleted {
                hapticService.playSuccessSequence()
            }
        }
        
        // Refresh challenges from service
        activeChallenges = gamificationService.getActiveChallenges()
    }
    
    private func refreshChallenges() async {
        isRefreshing = true
        
        // Simulate refresh delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Update challenges
        activeChallenges = gamificationService.getActiveChallenges()
        
        isRefreshing = false
    }
}

// MARK: - Challenge Detail View

struct WatchChallengeDetailView: View {
    let challenge: ActiveChallenge
    @StateObject private var gamificationService: WatchGamificationService
    @StateObject private var hapticService: WatchHapticFeedbackService
    @Environment(\.dismiss) private var dismiss
    @State private var showingProgressAnimation = false
    
    init(
        challenge: ActiveChallenge,
        gamificationService: WatchGamificationService,
        hapticService: WatchHapticFeedbackService
    ) {
        self.challenge = challenge
        self._gamificationService = StateObject(wrappedValue: gamificationService)
        self._hapticService = StateObject(wrappedValue: hapticService)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Challenge header
                    challengeDetailHeaderView
                    
                    // Progress section
                    challengeProgressSection
                    
                    // Statistics section
                    challengeStatisticsSection
                    
                    // Actions section
                    challengeActionsSection
                }
                .padding()
            }
            .navigationTitle(challenge.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            showingProgressAnimation = true
        }
    }
    
    private var challengeDetailHeaderView: some View {
        VStack(spacing: 12) {
            // Challenge type icon
            Image(systemName: challengeTypeIcon(challenge.type))
                .font(.largeTitle)
                .foregroundColor(challengeTypeColor(challenge.type))
            
            // Challenge title and description
            Text(challenge.title)
                .font(.headline)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(challengeTypeText(challenge.type))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var challengeProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.headline)
                .fontWeight(.semibold)
            
            // Large progress ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: showingProgressAnimation ? challenge.progress.percentComplete : 0)
                    .stroke(
                        progressColor(challenge.progress.percentComplete),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: showingProgressAnimation)
                
                // Progress text
                VStack {
                    Text("\(Int(challenge.progress.percentComplete * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            .padding(.horizontal)
            
            // Progress details
            HStack {
                VStack(alignment: .leading) {
                    Text("Completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(challenge.progress.completedSteps)")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(challenge.progress.totalSteps - challenge.progress.completedSteps)")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var challengeStatisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                statisticRow("Started", value: formatDate(challenge.startDate))
                statisticRow("Last Update", value: formatDate(challenge.lastUpdated))
                
                if let currentScore = challenge.progress.currentScore,
                   let targetScore = challenge.progress.targetScore {
                    statisticRow("Current Score", value: "\(currentScore)")
                    statisticRow("Target Score", value: "\(targetScore)")
                    
                    let remaining = targetScore - currentScore
                    statisticRow("Score Needed", value: "\(remaining)")
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var challengeActionsSection: some View {
        VStack(spacing: 12) {
            if !challenge.progress.isCompleted {
                Button(action: simulateProgressUpdate) {
                    HStack {
                        Image(systemName: "arrow.up.circle")
                        Text("Simulate Update")
                    }
                    .foregroundColor(.blue)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            Button(action: {
                hapticService.playTaptic(.light)
            }) {
                HStack {
                    Image(systemName: "hand.tap")
                    Text("Test Haptic")
                }
                .foregroundColor(.orange)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    private func statisticRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    
    private func simulateProgressUpdate() {
        hapticService.playTaptic(.success)
        
        // Simulate progress update
        Task {
            let newProgress = ChallengeProgress(
                completedSteps: min(challenge.progress.totalSteps, challenge.progress.completedSteps + 1),
                totalSteps: challenge.progress.totalSteps,
                percentComplete: min(1.0, challenge.progress.percentComplete + 0.1),
                isCompleted: false,
                currentScore: (challenge.progress.currentScore ?? 0) + 1,
                targetScore: challenge.progress.targetScore
            )
            
            await gamificationService.updateChallengeProgress(
                challengeId: challenge.challengeId,
                progress: newProgress
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func challengeTypeIcon(_ type: ChallengeType) -> String {
        switch type {
        case .headToHead: return "person.2"
        case .tournament: return "trophy"
        case .achievement: return "star"
        case .social: return "person.3"
        }
    }
    
    private func challengeTypeColor(_ type: ChallengeType) -> Color {
        switch type {
        case .headToHead: return .orange
        case .tournament: return .yellow
        case .achievement: return .purple
        case .social: return .blue
        }
    }
    
    private func challengeTypeText(_ type: ChallengeType) -> String {
        switch type {
        case .headToHead: return "Head-to-Head Challenge"
        case .tournament: return "Tournament Challenge"
        case .achievement: return "Achievement Challenge"
        case .social: return "Social Challenge"
        }
    }
    
    private func progressColor(_ progress: Double) -> Color {
        if progress >= 1.0 { return .green }
        else if progress >= 0.75 { return .yellow }
        else if progress >= 0.5 { return .orange }
        else { return .blue }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Head-to-Head Challenge View

struct WatchHeadToHeadView: View {
    let challengeId: String
    @StateObject private var gamificationService: WatchGamificationService
    @StateObject private var hapticService: WatchHapticFeedbackService
    @State private var playerScore: Int = 0
    @State private var opponentScore: Int = 0
    @State private var matchStatus: String = "Active"
    
    init(challengeId: String, gamificationService: WatchGamificationService, hapticService: WatchHapticFeedbackService) {
        self.challengeId = challengeId
        self._gamificationService = StateObject(wrappedValue: gamificationService)
        self._hapticService = StateObject(wrappedValue: hapticService)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Match header
            Text("Head-to-Head")
                .font(.headline)
                .fontWeight(.bold)
            
            // Score display
            HStack(spacing: 20) {
                // Player score
                VStack {
                    Text("You")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(playerScore)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(scoreColor(playerScore, opponentScore))
                }
                
                Text("vs")
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                // Opponent score
                VStack {
                    Text("Opponent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(opponentScore)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(scoreColor(opponentScore, playerScore))
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Status
            Text(statusText())
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(statusColor())
            
            // Action buttons (for demo)
            HStack(spacing: 12) {
                Button("+1") {
                    playerScore += 1
                    hapticService.playTaptic(.success)
                }
                .buttonStyle(.borderedProminent)
                
                Button("Update") {
                    updateChallenge()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .navigationTitle("Challenge")
    }
    
    private func scoreColor(_ score: Int, _ opponentScore: Int) -> Color {
        if score > opponentScore {
            return .green
        } else if score < opponentScore {
            return .red
        } else {
            return .primary
        }
    }
    
    private func statusText() -> String {
        if playerScore > opponentScore {
            return "You're Leading!"
        } else if playerScore < opponentScore {
            return "Behind by \(opponentScore - playerScore)"
        } else {
            return "It's a Tie!"
        }
    }
    
    private func statusColor() -> Color {
        if playerScore > opponentScore {
            return .green
        } else if playerScore < opponentScore {
            return .red
        } else {
            return .orange
        }
    }
    
    private func updateChallenge() {
        let progress = ChallengeProgress(
            completedSteps: playerScore,
            totalSteps: 18, // 18 holes
            percentComplete: Double(playerScore) / 18.0,
            isCompleted: playerScore >= 18,
            currentScore: playerScore,
            targetScore: opponentScore - 1
        )
        
        Task {
            await gamificationService.updateChallengeProgress(
                challengeId: challengeId,
                progress: progress
            )
        }
        
        hapticService.playTaptic(.medium)
    }
}

// MARK: - Previews

struct WatchChallengeProgressView_Previews: PreviewProvider {
    static var previews: some View {
        WatchChallengeProgressView(
            gamificationService: MockWatchGamificationService() as! WatchGamificationService,
            hapticService: MockWatchHapticFeedbackService()
        )
        .previewDevice("Apple Watch Series 7 - 45mm")
    }
}