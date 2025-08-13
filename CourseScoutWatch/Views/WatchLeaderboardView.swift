import SwiftUI
import WatchKit
import Combine

// MARK: - Watch Leaderboard View

struct WatchLeaderboardView: View {
    @StateObject private var gamificationService: WatchGamificationService
    @StateObject private var hapticService: WatchHapticFeedbackService
    @State private var currentPosition: LeaderboardPosition?
    @State private var isAnimatingPositionChange = false
    @State private var showPositionChangeIndicator = false
    @State private var positionChangeValue = 0
    @State private var lastUpdateTime: Date = Date()
    @State private var cancellables = Set<AnyCancellable>()
    
    // Configuration
    private let refreshInterval: TimeInterval = 5.0
    private let animationDuration: TimeInterval = 0.8
    private let maxDisplayedRanks = 5
    
    init(gamificationService: WatchGamificationService, hapticService: WatchHapticFeedbackService) {
        self._gamificationService = StateObject(wrappedValue: gamificationService)
        self._hapticService = StateObject(wrappedValue: hapticService)
    }
    
    var body: some View {
        ZStack {
            // Background gradient based on performance
            backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 8) {
                // Header with current position
                headerView
                
                // Position indicator with animation
                positionIndicatorView
                
                // Tournament standings (condensed view)
                standingsView
                
                // Last update time
                footerView
            }
            .padding()
            
            // Position change overlay
            if showPositionChangeIndicator {
                positionChangeOverlay
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: showPositionChangeIndicator)
            }
        }
        .navigationTitle("Leaderboard")
        .onAppear {
            setupLeaderboardTracking()
        }
        .onDisappear {
            cancellables.removeAll()
        }
        .refreshable {
            await refreshLeaderboardData()
        }
    }
    
    // MARK: - View Components
    
    private var backgroundGradient: LinearGradient {
        guard let position = currentPosition else {
            return LinearGradient(
                colors: [Color.gray.opacity(0.3), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        
        let percentile = Double(position.position) / Double(position.totalPlayers)
        
        if percentile <= 0.1 {
            // Top 10% - Gold gradient
            return LinearGradient(
                colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.5), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if percentile <= 0.25 {
            // Top 25% - Silver gradient
            return LinearGradient(
                colors: [Color.gray.opacity(0.4), Color.white.opacity(0.2), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if percentile <= 0.5 {
            // Top 50% - Blue gradient
            return LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            // Lower half - Neutral gradient
            return LinearGradient(
                colors: [Color.gray.opacity(0.2), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Live Position")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let position = currentPosition {
                    Text("#\(position.position)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(positionColor(for: position))
                } else {
                    Text("--")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("Total")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(currentPosition?.totalPlayers ?? 0)")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
        }
    }
    
    private var positionIndicatorView: some View {
        HStack {
            // Position change arrow
            Group {
                if let position = currentPosition, position.positionChange != 0 {
                    Image(systemName: position.positionChange > 0 ? "arrow.up" : "arrow.down")
                        .foregroundColor(position.positionChange > 0 ? .green : .red)
                        .font(.caption)
                        .scaleEffect(isAnimatingPositionChange ? 1.3 : 1.0)
                        .animation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true), value: isAnimatingPositionChange)
                    
                    Text("\(abs(position.positionChange))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(position.positionChange > 0 ? .green : .red)
                } else {
                    Image(systemName: "minus")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text("No change")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Performance indicator
            if let position = currentPosition {
                let percentile = Double(position.position) / Double(position.totalPlayers)
                performanceIndicator(percentile: percentile)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func performanceIndicator(percentile: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                Circle()
                    .fill(circleColor(for: index, percentile: percentile))
                    .frame(width: 6, height: 6)
            }
        }
    }
    
    private func circleColor(for index: Int, percentile: Double) -> Color {
        let threshold = Double(index) / 5.0
        
        if percentile <= threshold {
            if percentile <= 0.1 {
                return .yellow // Top 10%
            } else if percentile <= 0.25 {
                return .green // Top 25%
            } else if percentile <= 0.5 {
                return .blue // Top 50%
            } else {
                return .orange // Lower half
            }
        } else {
            return .gray.opacity(0.3)
        }
    }
    
    private var standingsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Around You")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVStack(spacing: 2) {
                // Show positions around current player
                if let position = currentPosition {
                    let startPos = max(1, position.position - 2)
                    let endPos = min(position.totalPlayers, position.position + 2)
                    
                    ForEach(startPos...endPos, id: \.self) { pos in
                        standingRow(position: pos, isCurrentPlayer: pos == position.position)
                    }
                } else {
                    standingRow(position: 1, isCurrentPlayer: false)
                    standingRow(position: 2, isCurrentPlayer: false)
                    standingRow(position: 3, isCurrentPlayer: false)
                }
            }
        }
    }
    
    private func standingRow(position: Int, isCurrentPlayer: Bool) -> some View {
        HStack {
            Text("#\(position)")
                .font(.caption2)
                .fontWeight(isCurrentPlayer ? .bold : .regular)
                .foregroundColor(isCurrentPlayer ? .yellow : .primary)
                .frame(width: 30, alignment: .leading)
            
            Text(isCurrentPlayer ? "You" : "Player \(position)")
                .font(.caption2)
                .fontWeight(isCurrentPlayer ? .bold : .regular)
                .foregroundColor(isCurrentPlayer ? .yellow : .primary)
            
            Spacer()
            
            // Mock score - would be real data in implementation
            Text("-\(position)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrentPlayer ? Color.yellow.opacity(0.2) : Color.clear)
        )
    }
    
    private var footerView: some View {
        VStack(spacing: 2) {
            Text("Last Updated")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(timeAgoString(from: lastUpdateTime))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var positionChangeOverlay: some View {
        VStack {
            Spacer()
            
            HStack {
                Image(systemName: positionChangeValue > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(positionChangeValue > 0 ? .green : .red)
                    .font(.title2)
                
                Text(positionChangeValue > 0 ? "+\(positionChangeValue)" : "\(positionChangeValue)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(positionChangeValue > 0 ? .green : .red)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
            
            Spacer()
        }
    }
    
    // MARK: - Helper Methods
    
    private func positionColor(for position: LeaderboardPosition) -> Color {
        let percentile = Double(position.position) / Double(position.totalPlayers)
        
        if position.position == 1 {
            return .yellow
        } else if position.position <= 3 {
            return .orange
        } else if percentile <= 0.1 {
            return .green
        } else if percentile <= 0.25 {
            return .blue
        } else if percentile <= 0.5 {
            return .cyan
        } else {
            return .primary
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
    
    // MARK: - Setup and Event Handling
    
    private func setupLeaderboardTracking() {
        // Subscribe to leaderboard updates
        gamificationService.subscribeToLeaderboardUpdates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosition in
                self?.handleLeaderboardUpdate(newPosition)
            }
            .store(in: &cancellables)
        
        // Load current position
        currentPosition = gamificationService.getCurrentLeaderboardPosition()
        
        // Setup periodic refresh
        Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task {
                await refreshLeaderboardData()
            }
        }
    }
    
    private func handleLeaderboardUpdate(_ newPosition: LeaderboardPosition) {
        let oldPosition = currentPosition
        
        // Check for position change
        if let old = oldPosition, old.position != newPosition.position {
            let change = old.position - newPosition.position // Positive means moved up
            positionChangeValue = change
            
            // Show position change indicator
            showPositionChangeIndicator = true
            
            // Trigger haptic feedback
            triggerHapticForPositionChange(change)
            
            // Animate position change
            withAnimation(.easeInOut(duration: animationDuration)) {
                isAnimatingPositionChange = true
            }
            
            // Hide indicator after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showPositionChangeIndicator = false
                }
            }
            
            // Stop animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isAnimatingPositionChange = false
            }
        }
        
        // Update position
        withAnimation(.easeInOut(duration: 0.5)) {
            currentPosition = newPosition
            lastUpdateTime = Date()
        }
    }
    
    private func triggerHapticForPositionChange(_ change: Int) {
        if abs(change) >= 5 {
            // Significant change
            hapticService.playSuccessSequence()
        } else if change > 0 {
            // Moved up
            hapticService.playTaptic(.success)
        } else if change < 0 {
            // Moved down
            hapticService.playTaptic(.warning)
        }
    }
    
    private func refreshLeaderboardData() async {
        // Simulate data refresh - would call real API in implementation
        lastUpdateTime = Date()
        
        // Add some variability for demo purposes
        if let current = currentPosition {
            let randomChange = Int.random(in: -2...2)
            let newPos = max(1, min(current.totalPlayers, current.position + randomChange))
            
            await gamificationService.updateLeaderboard(
                playerId: current.playerId,
                position: newPos,
                totalPlayers: current.totalPlayers,
                positionChange: current.position - newPos
            )
        }
    }
}

// MARK: - Leaderboard Preview View

struct WatchLeaderboardPreviewView: View {
    @StateObject private var mockGamificationService = MockWatchGamificationService()
    @StateObject private var mockHapticService = MockWatchHapticFeedbackService()
    
    var body: some View {
        NavigationView {
            WatchLeaderboardView(
                gamificationService: mockGamificationService as! WatchGamificationService,
                hapticService: mockHapticService
            )
            .onAppear {
                // Setup mock data
                Task {
                    await mockGamificationService.updateLeaderboard(
                        playerId: "player123",
                        position: 15,
                        totalPlayers: 64,
                        positionChange: 3
                    )
                }
            }
        }
    }
}

// MARK: - Tournament Leaderboard Detail View

struct WatchTournamentLeaderboardView: View {
    let tournamentId: String
    @StateObject private var gamificationService: WatchGamificationService
    @State private var tournamentStatus: TournamentStatus?
    @State private var cancellables = Set<AnyCancellable>()
    
    init(tournamentId: String, gamificationService: WatchGamificationService) {
        self.tournamentId = tournamentId
        self._gamificationService = StateObject(wrappedValue: gamificationService)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Tournament header
            tournamentHeaderView
            
            // Player position
            playerPositionView
            
            // Top leaders
            topLeadersView
            
            Spacer()
        }
        .padding()
        .navigationTitle("Tournament")
        .onAppear {
            setupTournamentTracking()
        }
        .onDisappear {
            cancellables.removeAll()
        }
    }
    
    private var tournamentHeaderView: some View {
        VStack {
            Text("Live Tournament")
                .font(.headline)
                .fontWeight(.bold)
            
            if let status = tournamentStatus {
                Text("\(status.totalParticipants) Players")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var playerPositionView: some View {
        VStack {
            if let status = tournamentStatus {
                Text("Your Position")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("#\(status.position)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(positionColor(status.position))
                    
                    Text("of \(status.totalParticipants)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                // Percentile indicator
                let percentile = Double(status.position) / Double(status.totalParticipants) * 100
                Text("\(Int(percentile))th percentile")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
    
    private var topLeadersView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Leaders")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 2) {
                ForEach(1...3, id: \.self) { position in
                    leaderRow(position: position)
                }
            }
        }
    }
    
    private func leaderRow(position: Int) -> some View {
        HStack {
            // Position indicator
            Text("#\(position)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(positionColor(position))
                .frame(width: 25, alignment: .leading)
            
            // Player name
            Text("Leader \(position)")
                .font(.caption2)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Score
            Text("-\(position + 10)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
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
    
    private func setupTournamentTracking() {
        gamificationService.subscribeToTournamentUpdates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status.tournamentId == self?.tournamentId {
                    self?.tournamentStatus = status
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Previews

struct WatchLeaderboardView_Previews: PreviewProvider {
    static var previews: some View {
        WatchLeaderboardPreviewView()
            .previewDevice("Apple Watch Series 7 - 45mm")
    }
}