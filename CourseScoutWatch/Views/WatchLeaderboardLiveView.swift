import SwiftUI
import WatchKit
import Combine

// MARK: - Watch Leaderboard Live View

struct WatchLeaderboardLiveView: View {
    @StateObject private var gamificationService: WatchGamificationService
    @StateObject private var hapticService: WatchHapticFeedbackService
    @StateObject private var connectivityService: WatchConnectivityService
    
    @State private var currentPosition: LiveLeaderboardPosition?
    @State private var liveStandings: [LiveStandingEntry] = []
    @State private var tournamentInfo: LiveTournamentInfo?
    @State private var isLiveMode = false
    @State private var lastUpdateTime: Date = Date()
    @State private var nextUpdateIn: TimeInterval = 0
    @State private var cancellables = Set<AnyCancellable>()
    
    // Animation states
    @State private var isAnimatingPositionChange = false
    @State private var showPositionChangeIndicator = false
    @State private var positionChangeValue = 0
    @State private var showLiveBadge = false
    @State private var pulseAnimation = false
    
    // Configuration
    private let maxDisplayedStandings = 8
    private let refreshInterval: TimeInterval = 15.0 // 15 seconds for live mode
    private let animationDuration: TimeInterval = 1.2
    
    init(
        gamificationService: WatchGamificationService,
        hapticService: WatchHapticFeedbackService,
        connectivityService: WatchConnectivityService
    ) {
        self._gamificationService = StateObject(wrappedValue: gamificationService)
        self._hapticService = StateObject(wrappedValue: hapticService)
        self._connectivityService = StateObject(wrappedValue: connectivityService)
    }
    
    var body: some View {
        ZStack {
            // Dynamic background based on tournament status
            dynamicBackground
                .ignoresSafeArea()
            
            VStack(spacing: 6) {
                // Live header with tournament info
                liveHeaderView
                
                // Current position with enhanced indicators
                enhancedPositionView
                
                // Live standings with real-time updates
                liveStandingsView
                
                // Next update countdown
                updateCountdownView
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            // Position change overlay with enhanced animation
            if showPositionChangeIndicator {
                positionChangeOverlay
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showPositionChangeIndicator)
            }
        }
        .navigationTitle("Live Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupLiveTracking()
        }
        .onDisappear {
            stopLiveTracking()
        }
        .refreshable {
            await refreshLiveData()
        }
        .digitalCrownRotation(
            .constant(0),
            from: 0,
            through: 1,
            by: 0.1,
            sensitivity: .medium,
            isContinuous: false
        ) { crownValue in
            // Scroll through standings with Digital Crown
            scrollToStanding(at: Int(crownValue * Double(liveStandings.count)))
        }
    }
    
    // MARK: - View Components
    
    private var dynamicBackground: LinearGradient {
        if isLiveMode {
            return LinearGradient(
                colors: [
                    Color.green.opacity(0.3),
                    Color.blue.opacity(0.4),
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
    
    private var liveHeaderView: some View {
        VStack(spacing: 2) {
            HStack {
                // Live indicator
                if isLiveMode {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(), value: pulseAnimation)
                        
                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                } else {
                    Text("LEADERBOARD")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Tournament info
                if let tournament = tournamentInfo {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(tournament.name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text("R\(tournament.currentRound)/\(tournament.totalRounds)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            pulseAnimation = isLiveMode
        }
        .onChange(of: isLiveMode) { newValue in
            pulseAnimation = newValue
        }
    }
    
    private var enhancedPositionView: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Position")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        if let position = currentPosition {
                            Text("#\(position.position)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(positionColor(for: position))
                                .scaleEffect(isAnimatingPositionChange ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.3), value: isAnimatingPositionChange)
                            
                            // Position change indicator
                            if position.positionChange != 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: position.positionChange > 0 ? "arrow.up" : "arrow.down")
                                        .font(.caption)
                                        .foregroundColor(position.positionChange > 0 ? .green : .red)
                                    
                                    Text("\(abs(position.positionChange))")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(position.positionChange > 0 ? .green : .red)
                                }
                                .scaleEffect(isAnimatingPositionChange ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.3).repeatCount(2, autoreverses: true), value: isAnimatingPositionChange)
                            }
                        } else {
                            Text("--")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total Players")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(currentPosition?.totalPlayers ?? 0)")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    // Percentile indicator
                    if let position = currentPosition {
                        let percentile = Double(position.position) / Double(position.totalPlayers) * 100
                        Text("\(Int(percentile))th %")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Enhanced performance indicator
            if let position = currentPosition {
                performanceIndicatorBar(for: position)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(positionBorderColor, lineWidth: 1)
                )
        )
    }
    
    private func performanceIndicatorBar(for position: LiveLeaderboardPosition) -> some View {
        let percentile = Double(position.position) / Double(position.totalPlayers)
        let progress = 1.0 - percentile // Invert so better positions show more progress
        
        return VStack(spacing: 2) {
            HStack {
                Text("Performance")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(performanceLabel(for: percentile))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(performanceColor(for: percentile))
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(performanceColor(for: percentile))
                        .frame(width: geometry.size.width * progress, height: 4)
                        .animation(.easeInOut(duration: 0.8), value: progress)
                }
                .cornerRadius(2)
            }
            .frame(height: 4)
        }
    }
    
    private var liveStandingsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Live Standings")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isLiveMode && nextUpdateIn > 0 {
                    Text("Next: \(Int(nextUpdateIn))s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 4)
            
            LazyVStack(spacing: 1) {
                ForEach(Array(liveStandings.enumerated()), id: \.element.playerId) { index, standing in
                    liveStandingRow(standing: standing, isCurrentPlayer: standing.isCurrentPlayer)
                        .animation(.easeInOut(delay: Double(index) * 0.05), value: liveStandings)
                }
            }
        }
    }
    
    private func liveStandingRow(standing: LiveStandingEntry, isCurrentPlayer: Bool) -> some View {
        HStack(spacing: 8) {
            // Position with trend indicator
            HStack(spacing: 2) {
                Text("#\(standing.position)")
                    .font(.caption2)
                    .fontWeight(isCurrentPlayer ? .bold : .regular)
                    .foregroundColor(isCurrentPlayer ? .yellow : .primary)
                    .frame(width: 25, alignment: .leading)
                
                // Position trend
                if let trend = standing.positionTrend {
                    Image(systemName: trendIcon(for: trend))
                        .font(.system(size: 6))
                        .foregroundColor(trendColor(for: trend))
                }
            }
            
            // Player name
            Text(standing.playerName)
                .font(.caption2)
                .fontWeight(isCurrentPlayer ? .bold : .regular)
                .foregroundColor(isCurrentPlayer ? .yellow : .primary)
                .lineLimit(1)
            
            Spacer()
            
            // Score with live indicator
            HStack(spacing: 2) {
                Text(standing.scoreDisplay)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                // Live scoring indicator
                if standing.isLiveScoring {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .padding(.horizontal, 8)
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
    
    private var updateCountdownView: some View {
        VStack(spacing: 2) {
            if isLiveMode {
                Text("Live Updates")
                    .font(.caption2)
                    .foregroundColor(.green)
                
                if nextUpdateIn > 0 {
                    Text("Next in \(Int(nextUpdateIn))s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Updating...")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            } else {
                Text("Last Updated")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(timeAgoString(from: lastUpdateTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var positionChangeOverlay: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: positionChangeValue > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundColor(positionChangeValue > 0 ? .green : .red)
                        .font(.title)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(positionChangeValue > 0 ? "Moved Up!" : "Position Changed")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(positionChangeValue > 0 ? .green : .red)
                        
                        Text("\(abs(positionChangeValue)) position\(abs(positionChangeValue) == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Enhanced position change details
                if let position = currentPosition {
                    HStack {
                        Text("Now #\(position.position)")
                            .font(.caption)
                            .foregroundColor(.primary)
                        
                        Text("of \(position.totalPlayers)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(positionChangeValue > 0 ? Color.green : Color.red, lineWidth: 2)
                    )
            )
            
            Spacer()
        }
    }
    
    // MARK: - Helper Methods
    
    private func positionColor(for position: LiveLeaderboardPosition) -> Color {
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
    
    private var positionBorderColor: Color {
        guard let position = currentPosition else { return .clear }
        
        if position.position == 1 {
            return .yellow
        } else if position.position <= 3 {
            return .orange
        } else if Double(position.position) / Double(position.totalPlayers) <= 0.1 {
            return .green
        } else {
            return .clear
        }
    }
    
    private func performanceLabel(for percentile: Double) -> String {
        if percentile <= 0.05 {
            return "Elite"
        } else if percentile <= 0.1 {
            return "Excellent"
        } else if percentile <= 0.25 {
            return "Great"
        } else if percentile <= 0.5 {
            return "Good"
        } else if percentile <= 0.75 {
            return "Fair"
        } else {
            return "Needs Work"
        }
    }
    
    private func performanceColor(for percentile: Double) -> Color {
        if percentile <= 0.1 {
            return .green
        } else if percentile <= 0.25 {
            return .blue
        } else if percentile <= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func trendIcon(for trend: PositionTrend) -> String {
        switch trend {
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .stable:
            return "minus"
        }
    }
    
    private func trendColor(for trend: PositionTrend) -> Color {
        switch trend {
        case .up:
            return .green
        case .down:
            return .red
        case .stable:
            return .secondary
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
    
    private func scrollToStanding(at index: Int) {
        // Implementation for Digital Crown scrolling through standings
        // Would scroll to show specific standing entry
    }
    
    // MARK: - Live Data Management
    
    private func setupLiveTracking() {
        logger.debug("Setting up live leaderboard tracking")
        
        // Subscribe to live tournament updates
        connectivityService.subscribeTo(.liveTournamentStandings) { [weak self] data in
            await self?.handleLiveTournamentUpdate(data)
        }
        
        // Subscribe to gamification updates
        gamificationService.subscribeToTournamentUpdates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tournamentUpdate in
                self?.handleTournamentUpdate(tournamentUpdate)
            }
            .store(in: &cancellables)
        
        // Setup periodic refresh timer
        Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshLiveData()
            }
        }
        
        // Load initial data
        loadInitialData()
    }
    
    private func stopLiveTracking() {
        cancellables.removeAll()
        isLiveMode = false
        logger.debug("Stopped live leaderboard tracking")
    }
    
    private func loadInitialData() {
        // Load cached tournament data
        if let cachedPosition = gamificationService.getCurrentLeaderboardPosition() {
            currentPosition = LiveLeaderboardPosition(from: cachedPosition)
        }
        
        // Load cached tournament info if available
        loadTournamentInfo()
    }
    
    private func loadTournamentInfo() {
        // Load tournament information from cache or service
        // Implementation would depend on available tournament data
    }
    
    @MainActor
    private func handleLiveTournamentUpdate(_ data: [String: Any]) async {
        guard let tournamentId = data["tournamentId"] as? String,
              let playerPosition = data["playerPosition"] as? Int,
              let positionChange = data["positionChange"] as? Int,
              let standings = data["standings"] as? [[String: Any]] else { return }
        
        // Update position with animation
        let oldPosition = currentPosition?.position
        currentPosition = LiveLeaderboardPosition(
            playerId: "current_player",
            position: playerPosition,
            totalPlayers: standings.count,
            positionChange: positionChange,
            lastUpdated: Date()
        )
        
        // Update standings
        liveStandings = standings.compactMap { standingData in
            LiveStandingEntry(from: standingData)
        }
        
        // Handle position change animation
        if let old = oldPosition, old != playerPosition {
            let change = old - playerPosition // Positive means moved up
            positionChangeValue = change
            
            // Show position change indicator
            showPositionChangeIndicator = true
            
            // Trigger haptic feedback
            await triggerPositionChangeHaptic(change: change)
            
            // Animate position change
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                isAnimatingPositionChange = true
            }
            
            // Hide indicator after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showPositionChangeIndicator = false
                }
            }
            
            // Stop animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isAnimatingPositionChange = false
            }
        }
        
        // Update timing info
        if let nextUpdate = data["nextUpdateIn"] as? TimeInterval {
            nextUpdateIn = nextUpdate
            startUpdateCountdown()
        }
        
        lastUpdateTime = Date()
        isLiveMode = true
        
        logger.info("Live tournament update processed: position \(playerPosition)")
    }
    
    private func handleTournamentUpdate(_ tournamentUpdate: TournamentStatus) {
        // Handle tournament status updates from gamification service
        // Update tournament info and refresh display
    }
    
    private func startUpdateCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if self.nextUpdateIn > 0 {
                self.nextUpdateIn -= 1
            } else {
                timer.invalidate()
            }
        }
    }
    
    private func refreshLiveData() async {
        // Request fresh data from iPhone
        await connectivityService.requestLiveUpdate(type: "tournament_leaderboard")
        lastUpdateTime = Date()
    }
    
    private func triggerPositionChangeHaptic(change: Int) async {
        if abs(change) >= 5 {
            // Major position change
            hapticService.playLeaderboardPositionHaptic(positionChange: change)
        } else if change > 0 {
            // Minor improvement
            hapticService.playTaptic(.success)
        } else if change < 0 {
            // Minor decline
            hapticService.playTaptic(.warning)
        }
    }
}

// MARK: - Supporting Data Models

struct LiveLeaderboardPosition: Identifiable {
    let id = UUID()
    let playerId: String
    let position: Int
    let totalPlayers: Int
    let positionChange: Int
    let lastUpdated: Date
    
    init(playerId: String, position: Int, totalPlayers: Int, positionChange: Int, lastUpdated: Date) {
        self.playerId = playerId
        self.position = position
        self.totalPlayers = totalPlayers
        self.positionChange = positionChange
        self.lastUpdated = lastUpdated
    }
    
    init(from leaderboardPosition: LeaderboardPosition) {
        self.playerId = leaderboardPosition.playerId
        self.position = leaderboardPosition.position
        self.totalPlayers = leaderboardPosition.totalPlayers
        self.positionChange = leaderboardPosition.positionChange
        self.lastUpdated = leaderboardPosition.lastUpdated
    }
}

struct LiveStandingEntry: Identifiable {
    let id = UUID()
    let playerId: String
    let playerName: String
    let position: Int
    let scoreDisplay: String
    let isCurrentPlayer: Bool
    let isLiveScoring: Bool
    let positionTrend: PositionTrend?
    
    init?(from data: [String: Any]) {
        guard let playerId = data["playerId"] as? String,
              let playerName = data["playerName"] as? String,
              let position = data["position"] as? Int,
              let scoreDisplay = data["scoreDisplay"] as? String else {
            return nil
        }
        
        self.playerId = playerId
        self.playerName = playerName
        self.position = position
        self.scoreDisplay = scoreDisplay
        self.isCurrentPlayer = data["isCurrentPlayer"] as? Bool ?? false
        self.isLiveScoring = data["isLiveScoring"] as? Bool ?? false
        
        if let trendString = data["positionTrend"] as? String {
            self.positionTrend = PositionTrend(rawValue: trendString)
        } else {
            self.positionTrend = nil
        }
    }
}

struct LiveTournamentInfo {
    let tournamentId: String
    let name: String
    let currentRound: Int
    let totalRounds: Int
    let status: String
}

enum PositionTrend: String {
    case up = "up"
    case down = "down"
    case stable = "stable"
}

// MARK: - Preview Support

struct WatchLeaderboardLiveView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WatchLeaderboardLiveView(
                gamificationService: MockWatchGamificationService() as! WatchGamificationService,
                hapticService: MockWatchHapticFeedbackService(),
                connectivityService: MockWatchConnectivityService() as! WatchConnectivityService
            )
        }
        .previewDevice("Apple Watch Series 9 - 45mm")
    }
}

// MARK: - Mock Connectivity Service Extension

extension WatchConnectivityService {
    func subscribeTo(_ messageType: MessageType, handler: @escaping ([String: Any]) async -> Void) {
        // Implementation for subscribing to specific message types
    }
    
    func requestLiveUpdate(type: String) async {
        // Implementation for requesting live updates from iPhone
    }
}