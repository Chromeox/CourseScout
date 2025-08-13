import SwiftUI
import WatchKit

// MARK: - Main Watch Navigation

struct WatchNavigationView: View {
    // MARK: - Dependencies
    
    @WatchServiceInjected(WatchConnectivityServiceProtocol.self) private var connectivityService
    @WatchServiceInjected(WatchHapticFeedbackServiceProtocol.self) private var hapticService
    @WatchServiceInjected(WatchScorecardServiceProtocol.self) private var scorecardService
    
    // MARK: - State
    
    @State private var selectedTab: WatchTab = .current
    @State private var isConnected = false
    @State private var hasActiveRound = false
    @State private var showingConnectionAlert = false
    
    // MARK: - Tab Definition
    
    enum WatchTab: String, CaseIterable {
        case current = "Current"
        case scorecard = "Score"
        case timer = "Timer"
        case metrics = "Health"
        
        var icon: String {
            switch self {
            case .current: return "golf.course"
            case .scorecard: return "list.clipboard"
            case .timer: return "timer"
            case .metrics: return "heart"
            }
        }
        
        var selectedIcon: String {
            switch self {
            case .current: return "golf.course.fill"
            case .scorecard: return "list.clipboard.fill"
            case .timer: return "timer.fill"
            case .metrics: return "heart.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .current: return .green
            case .scorecard: return .blue
            case .timer: return .orange
            case .metrics: return .red
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Current Hole Tab
            CurrentHoleView()
                .tabItem {
                    Image(systemName: selectedTab == .current ? WatchTab.current.selectedIcon : WatchTab.current.icon)
                    Text(WatchTab.current.rawValue)
                }
                .tag(WatchTab.current)
            
            // Scorecard Tab
            WatchScorecardView()
                .tabItem {
                    Image(systemName: selectedTab == .scorecard ? WatchTab.scorecard.selectedIcon : WatchTab.scorecard.icon)
                    Text(WatchTab.scorecard.rawValue)
                }
                .tag(WatchTab.scorecard)
            
            // Timer Tab
            CraftTimerWatchView()
                .tabItem {
                    Image(systemName: selectedTab == .timer ? WatchTab.timer.selectedIcon : WatchTab.timer.icon)
                    Text(WatchTab.timer.rawValue)
                }
                .tag(WatchTab.timer)
            
            // Health Metrics Tab
            WatchHealthView()
                .tabItem {
                    Image(systemName: selectedTab == .metrics ? WatchTab.metrics.selectedIcon : WatchTab.metrics.icon)
                    Text(WatchTab.metrics.rawValue)
                }
                .tag(WatchTab.metrics)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
        .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
        .onChange(of: selectedTab) { newTab in
            hapticService.playTaptic(.light)
            trackTabSelection(newTab)
        }
        .onAppear {
            checkConnectivity()
            checkActiveRound()
        }
        .alert("iPhone Not Connected", isPresented: $showingConnectionAlert) {
            Button("Retry") {
                checkConnectivity()
            }
            Button("Continue Offline") {
                // Allow offline usage with limited functionality
            }
        } message: {
            Text("Some features require connection to your iPhone. Make sure both devices are nearby and Bluetooth is enabled.")
        }
        .overlay(alignment: .top) {
            if !isConnected {
                connectionStatusBar
            }
        }
    }
    
    // MARK: - Connection Status Bar
    
    private var connectionStatusBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "iphone.slash")
                .font(.caption2)
                .foregroundColor(.orange)
            
            Text("No iPhone")
                .font(.caption2)
                .foregroundColor(.orange)
            
            Spacer()
            
            Button(action: {
                checkConnectivity()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.2))
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .animation(.easeInOut, value: isConnected)
    }
    
    // MARK: - Helper Functions
    
    private func checkConnectivity() {
        isConnected = connectivityService.isReachable
        
        if !isConnected {
            // Try to establish connection
            Task {
                try? await connectivityService.requestConnectionStatus()
                await MainActor.run {
                    isConnected = connectivityService.isReachable
                }
            }
        }
    }
    
    private func checkActiveRound() {
        Task {
            let activeRound = await scorecardService.getCurrentRound()
            await MainActor.run {
                hasActiveRound = activeRound != nil
                
                // If no active round and not on scorecard tab, suggest starting a round
                if !hasActiveRound && selectedTab != .timer && selectedTab != .metrics {
                    selectedTab = .scorecard
                }
            }
        }
    }
    
    private func trackTabSelection(_ tab: WatchTab) {
        // Track tab usage for analytics
        let usage = WatchUsageMetric(
            feature: "navigation",
            action: "tab_selected",
            value: tab.rawValue,
            timestamp: Date()
        )
        
        Task {
            try? await connectivityService.recordUsageMetric(usage)
        }
    }
}

// MARK: - Watch Scorecard View

struct WatchScorecardView: View {
    @WatchServiceInjected(WatchScorecardServiceProtocol.self) private var scorecardService
    @WatchServiceInjected(WatchHapticFeedbackServiceProtocol.self) private var hapticService
    
    @State private var currentRound: ActiveGolfRound?
    @State private var displayMode: ScoreDisplayMode = .current
    @State private var isLoading = true
    
    enum ScoreDisplayMode: String, CaseIterable {
        case current = "Current"
        case summary = "Summary"
        case holes = "All Holes"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if let round = currentRound {
                    activeScorecardView(round: round)
                } else {
                    noActiveRoundView
                }
            }
            .navigationTitle("Scorecard")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadCurrentRound()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading scorecard...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func activeScorecardView(round: ActiveGolfRound) -> some View {
        VStack(spacing: 12) {
            // Course header
            courseHeaderView(round: round)
            
            // Display mode selector
            displayModeSelector
            
            // Content based on display mode
            ScrollView {
                VStack(spacing: 8) {
                    switch displayMode {
                    case .current:
                        currentHoleScoreView(round: round)
                    case .summary:
                        scoreSummaryView(round: round)
                    case .holes:
                        allHolesView(round: round)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    private func courseHeaderView(round: ActiveGolfRound) -> some View {
        VStack(spacing: 4) {
            Text(round.courseName)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)
            
            HStack {
                Text("Hole \(round.currentHole)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(round.formattedScore)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(round.scoreRelativeToPar >= 0 ? .red : .green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var displayModeSelector: some View {
        Picker("Display Mode", selection: $displayMode) {
            ForEach(ScoreDisplayMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal, 8)
        .onChange(of: displayMode) { _ in
            hapticService.playTaptic(.light)
        }
    }
    
    private func currentHoleScoreView(round: ActiveGolfRound) -> some View {
        VStack(spacing: 12) {
            if let currentHole = round.currentHoleInfo {
                // Current hole details
                currentHoleDetailView(hole: currentHole, round: round)
                
                // Quick score entry
                quickScoreEntryView(hole: currentHole, round: round)
            } else {
                Text("No current hole information")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func currentHoleDetailView(hole: SharedHoleInfo, round: ActiveGolfRound) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("HOLE \(hole.holeNumber)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Par \(hole.par)")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("YARDAGE")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(hole.yardage)")
                        .font(.headline)
                        .fontWeight(.bold)
                }
            }
            
            if let score = round.scoreForHole(hole.holeNumber) {
                HStack {
                    Text("Current Score:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(score)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private func quickScoreEntryView(hole: SharedHoleInfo, round: ActiveGolfRound) -> some View {
        VStack(spacing: 8) {
            Text("Quick Score")
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            
            let scores = Array((hole.par - 1)...(hole.par + 3))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(scores, id: \.self) { score in
                    Button(action: {
                        recordQuickScore(score, for: hole.holeNumber)
                    }) {
                        VStack(spacing: 2) {
                            Text("\(score)")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            let relativeToPar = score - hole.par
                            if relativeToPar != 0 {
                                Text(relativeToPar > 0 ? "+\(relativeToPar)" : "\(relativeToPar)")
                                    .font(.caption2)
                                    .opacity(0.8)
                            }
                        }
                        .foregroundColor(round.scoreForHole(hole.holeNumber) == "\(score)" ? .white : .primary)
                        .frame(minWidth: 40, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(round.scoreForHole(hole.holeNumber) == "\(score)" ? Color.blue : Color(.systemGray5))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private func scoreSummaryView(round: ActiveGolfRound) -> some View {
        VStack(spacing: 12) {
            // Overall score
            VStack(spacing: 4) {
                Text("TOTAL SCORE")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Text("\(round.totalScore)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                
                Text(round.formattedScore)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(round.scoreRelativeToPar >= 0 ? .red : .green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Statistics grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                statCard(title: "Holes", value: "\(round.currentHole - 1)", subtitle: "completed")
                statCard(title: "Par", value: "\(round.totalPar)", subtitle: "total")
                statCard(title: "Average", value: String(format: "%.1f", round.averageScore), subtitle: "per hole")
                statCard(title: "Best", value: "\(round.bestHoleScore)", subtitle: "hole score")
            }
        }
    }
    
    private func statCard(title: String, value: String, subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func allHolesView(round: ActiveGolfRound) -> some View {
        LazyVStack(spacing: 6) {
            ForEach(1...18, id: \.self) { holeNumber in
                if holeNumber <= round.holes.count {
                    holeRowView(holeNumber: holeNumber, round: round)
                }
            }
        }
    }
    
    private func holeRowView(holeNumber: Int, round: ActiveGolfRound) -> some View {
        let hole = round.holes.first { $0.holeNumber == holeNumber }
        let score = round.scoreForHole(holeNumber)
        let isCurrentHole = holeNumber == round.currentHole
        
        HStack {
            // Hole number
            Text("\(holeNumber)")
                .font(.caption)
                .fontWeight(isCurrentHole ? .bold : .medium)
                .foregroundColor(isCurrentHole ? .blue : .primary)
                .frame(width: 20)
            
            // Par
            Text("Par \(hole?.par ?? 4)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            
            Spacer()
            
            // Score
            if let score = score, let scoreValue = Int(score) {
                let par = hole?.par ?? 4
                let relative = scoreValue - par
                
                HStack(spacing: 4) {
                    Text(score)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if relative != 0 {
                        Text(relative > 0 ? "+\(relative)" : "\(relative)")
                            .font(.caption2)
                            .foregroundColor(relative > 0 ? .red : .green)
                    }
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isCurrentHole ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.separator.opacity(0.5)),
            alignment: .bottom
        )
    }
    
    private var noActiveRoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "golf.course")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No Active Round")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Start a new golf round on your iPhone to begin scoring")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Actions
    
    private func loadCurrentRound() async {
        isLoading = true
        currentRound = await scorecardService.getCurrentRound()
        isLoading = false
    }
    
    private func recordQuickScore(_ score: Int, for holeNumber: Int) {
        hapticService.playTaptic(.light)
        
        Task {
            let success = await scorecardService.recordScore("\(score)", forHole: holeNumber)
            
            if success {
                await MainActor.run {
                    hapticService.playTaptic(.success)
                }
                await loadCurrentRound()
            } else {
                await MainActor.run {
                    hapticService.playTaptic(.error)
                }
            }
        }
    }
}

// MARK: - Watch Health View

struct WatchHealthView: View {
    @WatchServiceInjected(WatchHealthKitServiceProtocol.self) private var healthService
    
    @State private var currentMetrics = WatchHealthMetrics.empty
    @State private var isMonitoring = false
    @State private var showingPermissionAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    if isMonitoring {
                        activeMetricsView
                    } else {
                        inactiveHealthView
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Health Access Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                // Open health app settings
                if let settingsURL = URL(string: "x-apple-health://") {
                    WKExtension.shared().openSystemURL(settingsURL)
                }
            }
            Button("Cancel") { }
        } message: {
            Text("Grant access to heart rate and activity data to track your golf performance.")
        }
        .onAppear {
            checkHealthPermissions()
        }
    }
    
    private var activeMetricsView: some View {
        VStack(spacing: 12) {
            // Current metrics
            healthMetricsGrid
            
            // Workout controls
            workoutControlsView
        }
    }
    
    private var healthMetricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            metricCard(
                title: "Heart Rate",
                value: "\(Int(currentMetrics.heartRate))",
                unit: "BPM",
                color: .red,
                icon: "heart.fill"
            )
            
            metricCard(
                title: "Calories",
                value: "\(Int(currentMetrics.activeEnergyBurned))",
                unit: "cal",
                color: .orange,
                icon: "flame.fill"
            )
            
            metricCard(
                title: "Steps",
                value: "\(currentMetrics.stepCount)",
                unit: "steps",
                color: .green,
                icon: "figure.walk"
            )
            
            metricCard(
                title: "Distance",
                value: String(format: "%.1f", currentMetrics.walkingDistance),
                unit: "miles",
                color: .blue,
                icon: "location.fill"
            )
        }
    }
    
    private func metricCard(title: String, value: String, unit: String, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                
                Text(title.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            HStack(alignment: .bottom, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var workoutControlsView: some View {
        VStack(spacing: 8) {
            Button(action: {
                toggleWorkoutMonitoring()
            }) {
                HStack {
                    Image(systemName: isMonitoring ? "pause.fill" : "play.fill")
                        .font(.body)
                    
                    Text(isMonitoring ? "Pause Workout" : "Start Workout")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isMonitoring ? Color.orange : Color.green)
                .cornerRadius(20)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var inactiveHealthView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("Health Monitoring")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Track heart rate, calories, and activity during your golf rounds")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Enable Health Tracking") {
                requestHealthPermissions()
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red)
            .cornerRadius(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Actions
    
    private func checkHealthPermissions() {
        let status = healthService.authorizationStatus
        isMonitoring = status == .sharingAuthorized
        
        if isMonitoring {
            loadCurrentMetrics()
        }
    }
    
    private func requestHealthPermissions() {
        Task {
            let authorized = await healthService.requestAuthorization()
            
            await MainActor.run {
                if authorized {
                    isMonitoring = true
                    loadCurrentMetrics()
                } else {
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    private func loadCurrentMetrics() {
        currentMetrics = healthService.getWorkoutMetrics()
    }
    
    private func toggleWorkoutMonitoring() {
        if isMonitoring {
            Task {
                await healthService.stopHealthMonitoring()
                await MainActor.run {
                    isMonitoring = false
                }
            }
        } else {
            Task {
                await healthService.startHealthMonitoring()
                await MainActor.run {
                    isMonitoring = true
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct WatchUsageMetric {
    let feature: String
    let action: String
    let value: String
    let timestamp: Date
}

// MARK: - Extensions

extension WatchConnectivityServiceProtocol {
    func recordUsageMetric(_ metric: WatchUsageMetric) async throws {
        let data: [String: Any] = [
            "type": "usage_metric",
            "feature": metric.feature,
            "action": metric.action,
            "value": metric.value,
            "timestamp": metric.timestamp.timeIntervalSince1970
        ]
        
        try await sendMessage(data, priority: .low)
    }
    
    func requestConnectionStatus() async throws {
        let message: [String: Any] = [
            "type": "connection_check",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        try await sendMessage(message, priority: .normal)
    }
}

extension ActiveGolfRound {
    var averageScore: Double {
        let completedScores = scores.values.compactMap { Double($0) }
        return completedScores.isEmpty ? 0 : completedScores.reduce(0, +) / Double(completedScores.count)
    }
    
    var bestHoleScore: Int {
        return scores.values.compactMap { Int($0) }.min() ?? 0
    }
}

// MARK: - Preview

struct WatchNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        WatchNavigationView()
            .withWatchServiceContainer(
                WatchServiceContainer(environment: .test)
            )
    }
}