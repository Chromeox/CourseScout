import SwiftUI
import WatchKit
import Combine

// MARK: - Watch Tournament Monitor View

struct WatchTournamentMonitorView: View {
    let tournamentId: String
    @StateObject private var gamificationService: WatchGamificationService
    @StateObject private var hapticService: WatchHapticFeedbackService
    @StateObject private var connectivityService: WatchConnectivityService
    @StateObject private var synchronizedHapticService: SocialChallengeSynchronizedHapticService
    
    @State private var tournament: LiveTournament?
    @State private var currentView: TournamentViewMode = .overview
    @State private var playerPosition: LiveTournamentPosition?
    @State private var leaderboard: [TournamentLeaderEntry] = []
    @State private var nextOpponent: TournamentOpponent?
    @State private var upcomingMilestones: [TournamentMilestone] = []
    @State private var prizeInfo: TournamentPrizeInfo?
    @State private var lastUpdateTime: Date = Date()
    @State private var cancellables = Set<AnyCancellable>()
    
    // Animation states
    @State private var showPositionChange = false
    @State private var positionChangeAnimation = false
    @State private var showMilestoneAlert = false
    @State private var currentMilestoneAlert: TournamentMilestone?
    @State private var pulseAnimation = false
    @State private var bracketAnimationProgress: Double = 0
    
    // Configuration
    private let refreshInterval: TimeInterval = 20.0
    private let maxLeaderboardEntries = 8
    
    init(
        tournamentId: String,
        gamificationService: WatchGamificationService,
        hapticService: WatchHapticFeedbackService,
        connectivityService: WatchConnectivityService,
        synchronizedHapticService: SocialChallengeSynchronizedHapticService
    ) {
        self.tournamentId = tournamentId
        self._gamificationService = StateObject(wrappedValue: gamificationService)
        self._hapticService = StateObject(wrappedValue: hapticService)
        self._connectivityService = StateObject(wrappedValue: connectivityService)
        self._synchronizedHapticService = StateObject(wrappedValue: synchronizedHapticService)
    }
    
    var body: some View {
        ZStack {
            // Tournament background
            tournamentBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Tournament header
                tournamentHeaderView
                
                // View mode selector
                viewModeSelector
                
                // Main content based on current view
                mainContentView
                    .animation(.easeInOut(duration: 0.3), value: currentView)
                
                Spacer()
                
                // Update info
                updateInfoView
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            
            // Position change overlay
            if showPositionChange {
                positionChangeOverlay
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: showPositionChange)
            }
            
            // Milestone alert overlay
            if showMilestoneAlert, let milestone = currentMilestoneAlert {
                milestoneAlertOverlay(milestone)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 1.0, dampingFraction: 0.6), value: showMilestoneAlert)
            }
        }
        .navigationTitle(tournament?.name ?? "Tournament")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupTournamentMonitoring()
        }
        .onDisappear {
            stopTournamentMonitoring()
        }
        .refreshable {
            await refreshTournamentData()
        }
        .digitalCrownRotation(
            .constant(Double(currentView.rawValue)),
            from: 0,
            through: Double(TournamentViewMode.allCases.count - 1),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        ) { crownValue in
            let newMode = TournamentViewMode.allCases[Int(crownValue.rounded())]
            if newMode != currentView {
                currentView = newMode
                hapticService.playTaptic(.light)
            }
        }
    }
    
    // MARK: - View Components
    
    private var tournamentBackground: LinearGradient {
        guard let tournament = tournament else {
            return LinearGradient(
                colors: [Color.gray.opacity(0.2), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        
        let statusColor = tournamentStatusColor(tournament.status)
        
        return LinearGradient(
            colors: [
                statusColor.opacity(0.4),
                statusColor.opacity(0.2),
                Color.black.opacity(0.8)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var tournamentHeaderView: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let tournament = tournament {
                        Text(tournament.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            statusBadge(tournament.status)
                            
                            if tournament.isLive {
                                HStack(spacing: 2) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 4, height: 4)
                                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                        .animation(.easeInOut(duration: 1.0).repeatForever(), value: pulseAnimation)
                                    
                                    Text("LIVE")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Tournament info
                if let tournament = tournament {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Round \(tournament.currentRound)/\(tournament.totalRounds)")
                            .font(.caption2)
                            .foregroundColor(.primary)
                        
                        Text("\(tournament.totalParticipants) players")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Player position summary
            if let position = playerPosition {
                playerPositionSummary(position)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private func playerPositionSummary(_ position: LiveTournamentPosition) -> some View {
        HStack {
            // Current position
            HStack(spacing: 4) {
                Text("#\(position.currentPosition)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(positionColor(position.currentPosition))
                
                if position.positionChange != 0 {
                    HStack(spacing: 1) {
                        Image(systemName: position.positionChange > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                            .foregroundColor(position.positionChange > 0 ? .green : .red)
                        
                        Text("\(abs(position.positionChange))")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(position.positionChange > 0 ? .green : .red)
                    }
                    .scaleEffect(positionChangeAnimation ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.3).repeatCount(2, autoreverses: true), value: positionChangeAnimation)
                }
            }
            
            Spacer()
            
            // Score to par
            VStack(alignment: .trailing, spacing: 0) {
                Text(position.scoreToPar > 0 ? "+\(position.scoreToPar)" : "\(position.scoreToPar)")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(scoreToParColor(position.scoreToPar))
                
                Text("to par")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var viewModeSelector: some View {
        HStack(spacing: 4) {
            ForEach(TournamentViewMode.allCases, id: \.self) { mode in
                Button(action: {
                    currentView = mode
                    hapticService.playTaptic(.light)
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: mode.icon)
                            .font(.caption)
                            .foregroundColor(currentView == mode ? .white : .secondary)
                        
                        Text(mode.title)
                            .font(.caption2)
                            .foregroundColor(currentView == mode ? .white : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(currentView == mode ? Color.blue : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        switch currentView {
        case .overview:
            tournamentOverviewView
        case .leaderboard:
            tournamentLeaderboardView
        case .bracket:
            tournamentBracketView
        case .prizes:
            tournamentPrizesView
        }
    }
    
    private var tournamentOverviewView: some View {
        VStack(spacing: 8) {
            // Next opponent section
            if let opponent = nextOpponent {
                nextOpponentCard(opponent)
            }
            
            // Upcoming milestones
            if !upcomingMilestones.isEmpty {
                upcomingMilestonesCard
            }
            
            // Quick stats
            if let tournament = tournament {
                quickStatsCard(tournament)
            }
        }
    }
    
    private func nextOpponentCard(_ opponent: TournamentOpponent) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Next Opponent")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(timeUntilMatch(opponent.matchTime))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
            }
            
            HStack {
                // Opponent info
                VStack(alignment: .leading, spacing: 2) {
                    Text(opponent.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Rating: \(Int(opponent.rating))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Record: \(opponent.wins)-\(opponent.losses)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Head-to-head record
                VStack(alignment: .trailing, spacing: 2) {
                    Text("H2H")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let h2h = opponent.headToHeadRecord {
                        Text("\(h2h.wins)-\(h2h.losses)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(h2h.wins > h2h.losses ? .green : .red)
                    } else {
                        Text("First time")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var upcomingMilestonesCard: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Upcoming Milestones")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            VStack(spacing: 4) {
                ForEach(upcomingMilestones.prefix(3), id: \.id) { milestone in
                    milestoneRow(milestone)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func milestoneRow(_ milestone: TournamentMilestone) -> some View {
        HStack {
            Image(systemName: milestone.icon)
                .font(.caption)
                .foregroundColor(milestone.color)
                .frame(width: 16)
            
            Text(milestone.title)
                .font(.caption2)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(milestone.requirement)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func quickStatsCard(_ tournament: LiveTournament) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Tournament Stats")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            HStack {
                // Progress through tournament
                VStack(alignment: .leading, spacing: 2) {
                    Text("Progress")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(tournament.progressPercent))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                // Prize pool info
                if let prizeInfo = prizeInfo {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Prize Pool")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("$\(formatPrize(prizeInfo.totalPrizePool))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private var tournamentLeaderboardView: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Live Leaderboard")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let tournament = tournament, tournament.isLive {
                    Text("Updating...")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            LazyVStack(spacing: 2) {
                ForEach(Array(leaderboard.prefix(maxLeaderboardEntries).enumerated()), id: \.element.playerId) { index, entry in
                    leaderboardRow(entry: entry, isCurrentPlayer: entry.playerId == "current_player")
                        .animation(.easeInOut(delay: Double(index) * 0.05), value: leaderboard)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private func leaderboardRow(entry: TournamentLeaderEntry, isCurrentPlayer: Bool) -> some View {
        HStack(spacing: 6) {
            // Position
            Text("#\(entry.position)")
                .font(.caption2)
                .fontWeight(isCurrentPlayer ? .bold : .medium)
                .foregroundColor(isCurrentPlayer ? .yellow : positionColor(entry.position))
                .frame(width: 24, alignment: .leading)
            
            // Player name
            Text(isCurrentPlayer ? "You" : entry.playerName)
                .font(.caption2)
                .fontWeight(isCurrentPlayer ? .bold : .regular)
                .foregroundColor(isCurrentPlayer ? .yellow : .primary)
                .lineLimit(1)
            
            Spacer()
            
            // Score
            Text(entry.scoreToPar > 0 ? "+\(entry.scoreToPar)" : "\(entry.scoreToPar)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(scoreToParColor(entry.scoreToPar))
            
            // Today's round if available
            if let todayScore = entry.todayScore {
                Text("(\(todayScore))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrentPlayer ? Color.yellow.opacity(0.2) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isCurrentPlayer ? Color.yellow.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
    }
    
    private var tournamentBracketView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tournament Bracket")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let tournament = tournament {
                    Text("Round \(tournament.currentRound)")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
            }
            
            // Simplified bracket view for watch
            if let tournament = tournament {
                bracketVisualization(tournament)
            }
            
            // Current matchup details
            if let opponent = nextOpponent {
                currentMatchupCard(opponent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private func bracketVisualization(_ tournament: LiveTournament) -> some View {
        VStack(spacing: 4) {
            // Show player's path through bracket
            HStack {
                Text("Your Path")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            // Simplified bracket representation
            HStack {
                ForEach(1...tournament.totalRounds, id: \.self) { round in
                    VStack(spacing: 2) {
                        Circle()
                            .fill(round <= tournament.currentRound ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                        
                        Text("R\(round)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if round < tournament.totalRounds {
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 16, height: 1)
                    }
                }
            }
        }
    }
    
    private func currentMatchupCard(_ opponent: TournamentOpponent) -> some View {
        VStack(spacing: 4) {
            Text("Current Matchup")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack {
                Text("You")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.yellow)
                
                Text("vs")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(opponent.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let score = opponent.currentMatchScore {
                    Text(score)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.1))
        )
    }
    
    private var tournamentPrizesView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Prize Information")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            if let prizeInfo = prizeInfo {
                // Current projected payout
                if let projectedPayout = prizeInfo.projectedPayout {
                    projectedPayoutCard(projectedPayout)
                }
                
                // Prize distribution
                prizeDistributionCard(prizeInfo)
                
                // Payout requirements
                payoutRequirementsCard(prizeInfo)
            } else {
                Text("Prize information not available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private func projectedPayoutCard(_ payout: Double) -> some View {
        VStack(spacing: 4) {
            Text("Projected Payout")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text("$\(formatPrize(payout))")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.green)
            
            if let position = playerPosition {
                Text("Based on position #\(position.currentPosition)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.green.opacity(0.1))
        )
    }
    
    private func prizeDistributionCard(_ prizeInfo: TournamentPrizeInfo) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("Prize Distribution")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("$\(formatPrize(prizeInfo.totalPrizePool))")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 2) {
                ForEach(prizeInfo.distribution.prefix(5), id: \.position) { distribution in
                    HStack {
                        Text(positionOrdinal(distribution.position))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .leading)
                        
                        Spacer()
                        
                        Text("$\(formatPrize(distribution.amount))")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
                
                if prizeInfo.distribution.count > 5 {
                    Text("+ \(prizeInfo.distribution.count - 5) more positions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    private func payoutRequirementsCard(_ prizeInfo: TournamentPrizeInfo) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("Payout Requirements")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            VStack(spacing: 2) {
                requirementRow(
                    title: "Cut Line",
                    value: prizeInfo.cutLine != nil ? "Position \(prizeInfo.cutLine!)" : "No cut",
                    met: prizeInfo.cutLine == nil || (playerPosition?.currentPosition ?? 999) <= prizeInfo.cutLine!
                )
                
                requirementRow(
                    title: "Finish Tournament",
                    value: "Complete all rounds",
                    met: tournament?.status == .completed
                )
                
                if let minPosition = prizeInfo.minimumPayoutPosition {
                    requirementRow(
                        title: "Min Position",
                        value: "Top \(minPosition)",
                        met: (playerPosition?.currentPosition ?? 999) <= minPosition
                    )
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    private func requirementRow(title: String, value: String, met: Bool) -> some View {
        HStack {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundColor(met ? .green : .secondary)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
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
    
    private var positionChangeOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.up.down.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.blue)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true), value: pulseAnimation)
            
            if let position = playerPosition {
                VStack(spacing: 4) {
                    Text("Position Update")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Now #\(position.currentPosition)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(positionColor(position.currentPosition))
                    
                    if position.positionChange != 0 {
                        Text("\(position.positionChange > 0 ? "+" : "")\(position.positionChange) positions")
                            .font(.caption)
                            .foregroundColor(position.positionChange > 0 ? .green : .red)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue, lineWidth: 2)
                )
        )
        .onAppear {
            pulseAnimation = true
            
            // Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                showPositionChange = false
                pulseAnimation = false
            }
        }
    }
    
    private func milestoneAlertOverlay(_ milestone: TournamentMilestone) -> some View {
        VStack(spacing: 12) {
            Image(systemName: milestone.icon)
                .font(.largeTitle)
                .foregroundColor(milestone.color)
                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true), value: pulseAnimation)
            
            VStack(spacing: 4) {
                Text("Milestone Reached!")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(milestone.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(milestone.color, lineWidth: 2)
                )
        )
        .onAppear {
            pulseAnimation = true
            
            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                showMilestoneAlert = false
                pulseAnimation = false
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func statusBadge(_ status: TournamentStatus) -> some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tournamentStatusColor(status))
            )
    }
    
    private func tournamentStatusColor(_ status: TournamentStatus) -> Color {
        switch status {
        case .pending:
            return .orange
        case .active:
            return .green
        case .completed:
            return .blue
        case .cancelled:
            return .red
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
    
    private func scoreToParColor(_ scoreToPar: Int) -> Color {
        switch scoreToPar {
        case ..<0:
            return .green
        case 0:
            return .blue
        case 1...5:
            return .orange
        default:
            return .red
        }
    }
    
    private func timeUntilMatch(_ matchTime: Date) -> String {
        let interval = matchTime.timeIntervalSince(Date())
        
        if interval < 0 {
            return "Now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        }
    }
    
    private func formatPrize(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "%.1fK", amount / 1000)
        } else {
            return String(format: "%.0f", amount)
        }
    }
    
    private func positionOrdinal(_ position: Int) -> String {
        let suffix: String
        
        switch position % 10 {
        case 1 where position % 100 != 11:
            suffix = "st"
        case 2 where position % 100 != 12:
            suffix = "nd"
        case 3 where position % 100 != 13:
            suffix = "rd"
        default:
            suffix = "th"
        }
        
        return "\(position)\(suffix)"
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
    
    // MARK: - Tournament Monitoring
    
    private func setupTournamentMonitoring() {
        logger.debug("Setting up tournament monitoring for \(tournamentId)")
        
        // Subscribe to live tournament updates
        connectivityService.subscribeTo(.liveTournamentStandings) { [weak self] data in
            await self?.handleLiveTournamentUpdate(data)
        }
        
        connectivityService.subscribeTo(.tournamentBracketUpdate) { [weak self] data in
            await self?.handleBracketUpdate(data)
        }
        
        connectivityService.subscribeTo(.nextOpponentNotification) { [weak self] data in
            await self?.handleNextOpponentUpdate(data)
        }
        
        connectivityService.subscribeTo(.tournamentMilestone) { [weak self] data in
            await self?.handleTournamentMilestone(data)
        }
        
        connectivityService.subscribeTo(.tournamentPrizeUpdate) { [weak self] data in
            await self?.handlePrizeUpdate(data)
        }
        
        // Subscribe to gamification service updates
        gamificationService.subscribeToTournamentUpdates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tournamentUpdate in
                self?.handleTournamentUpdate(tournamentUpdate)
            }
            .store(in: &cancellables)
        
        // Load initial tournament data
        loadInitialTournamentData()
        
        // Setup refresh timer
        Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshTournamentData()
            }
        }
        
        // Enable tournament monitoring mode
        Task {
            await connectivityService.enableTournamentMonitoringMode(
                tournamentId: tournamentId,
                expectedDuration: 14400 // 4 hours
            )
        }
        
        pulseAnimation = true
    }
    
    private func stopTournamentMonitoring() {
        cancellables.removeAll()
        pulseAnimation = false
        
        Task {
            await connectivityService.disableTournamentMonitoringMode()
        }
        
        logger.debug("Stopped tournament monitoring")
    }
    
    private func loadInitialTournamentData() {
        // Load cached tournament data
        loadTournamentInfo()
        loadLeaderboard()
        loadPlayerPosition()
        loadPrizeInformation()
    }
    
    private func loadTournamentInfo() {
        // Load tournament information from cache or service
        // Implementation would depend on available data sources
    }
    
    private func loadLeaderboard() {
        // Load cached leaderboard data
        // Implementation would populate leaderboard array
    }
    
    private func loadPlayerPosition() {
        // Load player's current tournament position
        // Implementation would set playerPosition
    }
    
    private func loadPrizeInformation() {
        // Load prize pool and distribution information
        // Implementation would set prizeInfo
    }
    
    @MainActor
    private func handleLiveTournamentUpdate(_ data: [String: Any]) async {
        guard let tournamentIdData = data["tournamentId"] as? String,
              tournamentIdData == tournamentId else { return }
        
        // Update player position
        if let playerPosition = data["playerPosition"] as? Int,
           let positionChange = data["positionChange"] as? Int {
            
            let oldPosition = self.playerPosition?.currentPosition
            
            self.playerPosition = LiveTournamentPosition(
                playerId: "current_player",
                currentPosition: playerPosition,
                positionChange: positionChange,
                scoreToPar: data["scoreToPar"] as? Int ?? 0,
                totalScore: data["totalScore"] as? Int ?? 0,
                lastUpdated: Date()
            )
            
            // Show position change animation
            if let old = oldPosition, old != playerPosition {
                showPositionChange = true
                positionChangeAnimation = true
                
                // Trigger synchronized haptic feedback for position change
                Task {
                    await synchronizedHapticService.provideSynchronizedPositionChange(
                        challengeId: tournamentId,
                        oldPosition: old,
                        newPosition: playerPosition,
                        playerName: "You"
                    )
                }
                
                // Stop animation after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    positionChangeAnimation = false
                }
            }
        }
        
        // Update leaderboard
        if let standings = data["standings"] as? [[String: Any]] {
            leaderboard = standings.compactMap { standingData in
                TournamentLeaderEntry(from: standingData)
            }
        }
        
        lastUpdateTime = Date()
        
        logger.info("Live tournament update processed for \(tournamentId)")
    }
    
    @MainActor
    private func handleBracketUpdate(_ data: [String: Any]) async {
        guard let tournamentIdData = data["tournamentId"] as? String,
              tournamentIdData == tournamentId else { return }
        
        // Update bracket information
        if let bracketPosition = data["bracketPosition"] as? [String: Any] {
            // Update tournament bracket data
        }
        
        logger.info("Bracket update received for \(tournamentId)")
    }
    
    @MainActor
    private func handleNextOpponentUpdate(_ data: [String: Any]) async {
        guard let tournamentIdData = data["tournamentId"] as? String,
              tournamentIdData == tournamentId else { return }
        
        if let opponentInfo = data["opponentInfo"] as? [String: Any] {
            nextOpponent = TournamentOpponent(from: opponentInfo)
            
            // Trigger notification haptic
            hapticService.playTaptic(.notification)
        }
        
        logger.info("Next opponent update received for \(tournamentId)")
    }
    
    @MainActor
    private func handleTournamentMilestone(_ data: [String: Any]) async {
        guard let tournamentIdData = data["tournamentId"] as? String,
              tournamentIdData == tournamentId else { return }
        
        if let milestoneType = data["milestoneType"] as? String {
            let milestone = TournamentMilestone(
                id: UUID().uuidString,
                title: milestoneType,
                requirement: "Tournament milestone",
                icon: "flag.checkered",
                color: .orange
            )
            
            currentMilestoneAlert = milestone
            showMilestoneAlert = true
            
            // Play synchronized tournament milestone haptic
            Task {
                await synchronizedHapticService.provideSynchronizedTournamentMilestone(
                    tournamentId: tournamentId,
                    milestone: TournamentMilestone(rawValue: milestoneType) ?? .quarterfinal,
                    playerAffected: "You"
                )
            }
        }
        
        logger.info("Tournament milestone reached: \(data["milestoneType"] ?? "unknown")")
    }
    
    @MainActor
    private func handlePrizeUpdate(_ data: [String: Any]) async {
        guard let tournamentIdData = data["tournamentId"] as? String,
              tournamentIdData == tournamentId else { return }
        
        if let currentPrizePool = data["currentPrizePool"] as? Double {
            let projectedPayout = data["projectedPayout"] as? Double
            
            // Update prize information
            if prizeInfo == nil {
                prizeInfo = TournamentPrizeInfo(
                    totalPrizePool: currentPrizePool,
                    projectedPayout: projectedPayout,
                    distribution: [],
                    cutLine: nil,
                    minimumPayoutPosition: nil
                )
            } else {
                prizeInfo?.totalPrizePool = currentPrizePool
                prizeInfo?.projectedPayout = projectedPayout
            }
        }
        
        logger.info("Prize update received for \(tournamentId)")
    }
    
    private func handleTournamentUpdate(_ tournamentUpdate: TournamentStatus) {
        // Handle tournament status updates from gamification service
        // Update tournament info based on status change
    }
    
    private func refreshTournamentData() async {
        lastUpdateTime = Date()
        
        // Request fresh tournament data from iPhone
        await connectivityService.requestLiveUpdate(type: "tournament_status")
    }
}

// MARK: - Supporting Data Models

enum TournamentViewMode: Int, CaseIterable {
    case overview = 0
    case leaderboard = 1
    case bracket = 2
    case prizes = 3
    
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .leaderboard: return "Board"
        case .bracket: return "Bracket"
        case .prizes: return "Prizes"
        }
    }
    
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .leaderboard: return "list.number"
        case .bracket: return "tree"
        case .prizes: return "dollarsign.circle"
        }
    }
}

enum TournamentStatus {
    case pending
    case active
    case completed
    case cancelled
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .active: return "Active"
        case .completed: return "Complete"
        case .cancelled: return "Cancelled"
        }
    }
}

struct LiveTournament {
    let tournamentId: String
    let name: String
    let status: TournamentStatus
    let currentRound: Int
    let totalRounds: Int
    let totalParticipants: Int
    let isLive: Bool
    let progressPercent: Double
    
    init?(from data: [String: Any]) {
        guard let tournamentId = data["tournamentId"] as? String,
              let name = data["name"] as? String,
              let currentRound = data["currentRound"] as? Int,
              let totalRounds = data["totalRounds"] as? Int,
              let totalParticipants = data["totalParticipants"] as? Int else {
            return nil
        }
        
        self.tournamentId = tournamentId
        self.name = name
        self.currentRound = currentRound
        self.totalRounds = totalRounds
        self.totalParticipants = totalParticipants
        self.isLive = data["isLive"] as? Bool ?? false
        self.progressPercent = (Double(currentRound) / Double(totalRounds)) * 100
        
        // Parse status
        if let statusString = data["status"] as? String {
            switch statusString {
            case "pending": self.status = .pending
            case "active": self.status = .active
            case "completed": self.status = .completed
            case "cancelled": self.status = .cancelled
            default: self.status = .pending
            }
        } else {
            self.status = .pending
        }
    }
}

struct LiveTournamentPosition {
    let playerId: String
    let currentPosition: Int
    let positionChange: Int
    let scoreToPar: Int
    let totalScore: Int
    let lastUpdated: Date
}

struct TournamentLeaderEntry {
    let playerId: String
    let playerName: String
    let position: Int
    let scoreToPar: Int
    let totalScore: Int
    let todayScore: Int?
    
    init?(from data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let playerName = data["playerName"] as? String,
              let position = data["position"] as? Int,
              let scoreToPar = data["scoreToPar"] as? Int,
              let totalScore = data["totalScore"] as? Int else {
            return nil
        }
        
        self.playerId = playerId
        self.playerName = playerName
        self.position = position
        self.scoreToPar = scoreToPar
        self.totalScore = totalScore
        self.todayScore = data["todayScore"] as? Int
    }
}

struct TournamentOpponent {
    let playerId: String
    let name: String
    let rating: Double
    let wins: Int
    let losses: Int
    let headToHeadRecord: HeadToHeadRecord?
    let matchTime: Date
    let currentMatchScore: String?
    
    init?(from data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let name = data["name"] as? String,
              let rating = data["rating"] as? Double,
              let wins = data["wins"] as? Int,
              let losses = data["losses"] as? Int,
              let matchTimeInterval = data["matchTime"] as? TimeInterval else {
            return nil
        }
        
        self.playerId = playerId
        self.name = name
        self.rating = rating
        self.wins = wins
        self.losses = losses
        self.matchTime = Date(timeIntervalSince1970: matchTimeInterval)
        self.currentMatchScore = data["currentMatchScore"] as? String
        
        // Parse head-to-head record if available
        if let h2hData = data["headToHeadRecord"] as? [String: Any],
           let h2hWins = h2hData["wins"] as? Int,
           let h2hLosses = h2hData["losses"] as? Int {
            self.headToHeadRecord = HeadToHeadRecord(wins: h2hWins, losses: h2hLosses)
        } else {
            self.headToHeadRecord = nil
        }
    }
}

struct HeadToHeadRecord {
    let wins: Int
    let losses: Int
}

struct TournamentMilestone {
    let id: String
    let title: String
    let requirement: String
    let icon: String
    let color: Color
}

struct TournamentPrizeInfo {
    var totalPrizePool: Double
    var projectedPayout: Double?
    let distribution: [PrizeDistribution]
    let cutLine: Int?
    let minimumPayoutPosition: Int?
}

struct PrizeDistribution {
    let position: Int
    let amount: Double
}

// MARK: - Preview Support

struct WatchTournamentMonitorView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WatchTournamentMonitorView(
                tournamentId: "test_tournament",
                gamificationService: MockWatchGamificationService() as! WatchGamificationService,
                hapticService: MockWatchHapticFeedbackService(),
                connectivityService: MockWatchConnectivityService() as! WatchConnectivityService
            )
        }
        .previewDevice("Apple Watch Series 9 - 45mm")
    }
}