import SwiftUI
import CoreLocation

struct ScorecardView: View {
    
    // MARK: - Input Parameters
    
    let golfCourse: GolfCourse
    let userId: String
    
    // MARK: - Service Dependencies
    
    @ServiceInjected(ScorecardServiceProtocol.self) private var scorecardService
    @ServiceInjected(LocationServiceProtocol.self) private var locationService
    @ServiceInjected(HapticFeedbackServiceProtocol.self) private var hapticService
    @ServiceInjected(WeatherServiceProtocol.self) private var weatherService
    
    // MARK: - State Properties
    
    @State private var activeScorecard: Scorecard?
    @State private var currentHole: Int = 1
    @State private var currentStrokes: Int = 0
    @State private var isRoundInProgress: Bool = false
    @State private var showRoundSummary: Bool = false
    @State private var showStartRoundConfirmation: Bool = false
    @State private var showEndRoundConfirmation: Bool = false
    
    // Scoring state
    @State private var holeScores: [Int: HoleScore] = [:]
    @State private var totalScore: Int = 0
    @State private var currentHandicap: Double = 0.0
    @State private var scoreToPar: Int = 0
    
    // GPS and weather
    @State private var isTrackingShots: Bool = false
    @State private var currentWeather: WeatherConditions?
    @State private var shotHistory: [ShotData] = []
    @State private var currentLocation: CLLocationCoordinate2D?
    
    // UI state
    @State private var selectedTeeType: String = "Regular"
    @State private var showHoleDetail: Bool = false
    @State private var showShotTracker: Bool = false
    @State private var showStatistics: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                if isRoundInProgress {
                    activeScorecardView
                } else {
                    preRoundSetupView
                }
                
                // Loading overlay
                if isLoading {
                    loadingOverlay
                }
            }
            .navigationTitle("Golf Scorecard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if isRoundInProgress {
                        roundActionButtons
                    } else {
                        setupActionButtons
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if isRoundInProgress {
                        courseInfoButton
                    }
                }
            }
            .sheet(isPresented: $showHoleDetail) {
                if let hole = getCurrentHoleInfo() {
                    HoleDetailView(hole: hole, course: golfCourse)
                }
            }
            .sheet(isPresented: $showShotTracker) {
                ShotTrackerView(
                    currentHole: currentHole,
                    course: golfCourse,
                    onShotRecorded: { shot in
                        recordShot(shot)
                    }
                )
            }
            .sheet(isPresented: $showRoundSummary) {
                if let scorecard = activeScorecard {
                    RoundSummaryView(scorecard: scorecard, course: golfCourse)
                }
            }
            .sheet(isPresented: $showStatistics) {
                PlayerStatisticsView(userId: userId)
            }
            .alert("Start New Round?", isPresented: $showStartRoundConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Start Round") {
                    startNewRound()
                }
            } message: {
                Text("Begin tracking your round at \(golfCourse.name)?")
            }
            .alert("End Round?", isPresented: $showEndRoundConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("End Round", role: .destructive) {
                    endCurrentRound()
                }
            } message: {
                Text("Your round will be saved and cannot be continued.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .onAppear {
                setupInitialState()
                loadCurrentHandicap()
                loadWeatherConditions()
            }
        }
    }
    
    // MARK: - Pre-Round Setup View
    
    private var preRoundSetupView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Course header
                courseHeaderSection
                
                // Tee selection
                teeSelectionSection
                
                // Player information
                playerInfoSection
                
                // Weather conditions
                if let weather = currentWeather {
                    weatherSection(weather)
                }
                
                // Start round button
                startRoundButton
                
                Spacer()
            }
            .padding()
        }
    }
    
    private var courseHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(golfCourse.name)
                .font(.title)
                .fontWeight(.bold)
            
            Text("\(golfCourse.city), \(golfCourse.state)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                courseInfoCard("Par", value: "\(golfCourse.par)")
                courseInfoCard("Holes", value: "\(golfCourse.numberOfHoles)")
                courseInfoCard("Difficulty", value: golfCourse.difficulty.displayName)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func courseInfoCard(_ title: String, value: String) -> some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var teeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Tees")
                .font(.headline)
            
            HStack {
                ForEach(getAvailableTees(), id: \.self) { teeType in
                    teeSelectionButton(teeType)
                }
            }
            
            if let yardage = getYardageForTee(selectedTeeType) {
                Text("\(yardage) yards")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func teeSelectionButton(_ teeType: String) -> some View {
        Button(action: {
            selectedTeeType = teeType
            hapticService.impact(.light)
        }) {
            Text(teeType)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(selectedTeeType == teeType ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedTeeType == teeType ? Color.blue : Color.secondary.opacity(0.2))
                .cornerRadius(8)
        }
    }
    
    private var playerInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Information")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Current Handicap")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f", currentHandicap))
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Today's Target")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(golfCourse.par + Int(currentHandicap))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var startRoundButton: some View {
        Button(action: {
            showStartRoundConfirmation = true
            hapticService.impact(.medium)
        }) {
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                Text("Start Round")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Active Scorecard View
    
    private var activeScorecardView: some View {
        VStack(spacing: 0) {
            // Current hole header
            currentHoleHeader
            
            // Scorecard content
            TabView(selection: $currentHole) {
                ForEach(1...golfCourse.numberOfHoles, id: \.self) { holeNumber in
                    holeDetailCard(holeNumber)
                        .tag(holeNumber)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .onChange(of: currentHole) { _ in
                hapticService.impact(.light)
            }
            
            // Navigation and scoring controls
            scoringControls
        }
    }
    
    private var currentHoleHeader: some View {
        VStack(spacing: 8) {
            // Hole navigation
            HStack {
                Button(action: {
                    if currentHole > 1 {
                        currentHole -= 1
                        hapticService.impact(.light)
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(currentHole > 1 ? .primary : .secondary)
                }
                .disabled(currentHole <= 1)
                
                Spacer()
                
                VStack {
                    Text("Hole \(currentHole)")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    if let holeInfo = getCurrentHoleInfo() {
                        Text("Par \(holeInfo.par) • \(getYardageForCurrentHole()) yards")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    if currentHole < golfCourse.numberOfHoles {
                        currentHole += 1
                        hapticService.impact(.light)
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(currentHole < golfCourse.numberOfHoles ? .primary : .secondary)
                }
                .disabled(currentHole >= golfCourse.numberOfHoles)
            }
            
            // Current score summary
            HStack {
                scoreDisplayCard("Score", value: "\(totalScore)")
                scoreDisplayCard("To Par", value: scoreToPar >= 0 ? "+\(scoreToPar)" : "\(scoreToPar)")
                scoreDisplayCard("Through", value: "\(getCompletedHoles())")
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.separator),
            alignment: .bottom
        )
    }
    
    private func scoreDisplayCard(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(title == "To Par" ? (scoreToPar < 0 ? .green : scoreToPar > 0 ? .red : .primary) : .primary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func holeDetailCard(_ holeNumber: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hole information
                if let holeInfo = getHoleInfo(for: holeNumber) {
                    holeInfoSection(holeInfo)
                }
                
                // Current hole score
                currentHoleScoreSection(holeNumber)
                
                // Shot tracking section
                shotTrackingSection(holeNumber)
                
                // Hole statistics (if available)
                if let holeStats = getHoleStatistics(holeNumber) {
                    holeStatisticsSection(holeStats)
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func holeInfoSection(_ hole: HoleInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hole \(hole.holeNumber)")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                difficultyIndicator(hole.difficulty ?? .intermediate)
            }
            
            HStack {
                infoChip("Par \(hole.par)")
                infoChip("\(getYardageForCurrentHole()) yds")
                if let handicap = hole.handicap {
                    infoChip("HCP \(handicap)")
                }
            }
            
            if let description = hole.description {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            if let proTip = hole.proTip {
                HStack {
                    Image(systemName: "lightbulb")
                        .foregroundColor(.yellow)
                    Text(proTip)
                        .font(.caption)
                        .italic()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
    }
    
    private func difficultyIndicator(_ difficulty: DifficultyLevel) -> some View {
        HStack {
            ForEach(1...4, id: \.self) { level in
                Circle()
                    .fill(level <= difficulty.rawValue ? Color(difficulty.color) : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    private func currentHoleScoreSection(_ holeNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score")
                .font(.headline)
            
            let currentScore = holeScores[holeNumber]?.strokes ?? 0
            let par = getHoleInfo(for: holeNumber)?.par ?? 4
            
            HStack {
                // Score picker
                HStack {
                    Button(action: {
                        if currentScore > 0 {
                            updateHoleScore(holeNumber, strokes: currentScore - 1)
                            hapticService.impact(.light)
                        }
                    }) {
                        Image(systemName: "minus.circle")
                            .font(.title2)
                            .foregroundColor(currentScore > 0 ? .red : .secondary)
                    }
                    .disabled(currentScore <= 0)
                    
                    Text("\(currentScore)")
                        .font(.title)
                        .fontWeight(.bold)
                        .frame(minWidth: 60)
                    
                    Button(action: {
                        if currentScore < 12 {
                            updateHoleScore(holeNumber, strokes: currentScore + 1)
                            hapticService.impact(.light)
                        }
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundColor(currentScore < 12 ? .green : .secondary)
                    }
                    .disabled(currentScore >= 12)
                }
                
                Spacer()
                
                // Score relative to par
                VStack(alignment: .trailing) {
                    if currentScore > 0 {
                        let scoreToPar = currentScore - par
                        Text(scoreToParText(scoreToPar))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(scoreToParColor(scoreToPar))
                        Text("to par")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Quick score buttons
            HStack {
                ForEach([par - 2, par - 1, par, par + 1, par + 2], id: \.self) { score in
                    if score > 0 && score <= 12 {
                        quickScoreButton(score, par: par, holeNumber: holeNumber)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func quickScoreButton(_ score: Int, par: Int, holeNumber: Int) -> some View {
        let isSelected = (holeScores[holeNumber]?.strokes ?? 0) == score
        let scoreToPar = score - par
        
        return Button(action: {
            updateHoleScore(holeNumber, strokes: score)
            hapticService.selection()
        }) {
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.headline)
                    .fontWeight(.bold)
                Text(getScoreName(scoreToPar))
                    .font(.caption)
            }
            .foregroundColor(isSelected ? .white : scoreToParColor(scoreToPar))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? scoreToParColor(scoreToPar) : scoreToParColor(scoreToPar).opacity(0.2))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func shotTrackingSection(_ holeNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shot Tracking")
                    .font(.headline)
                
                Spacer()
                
                Toggle("GPS Tracking", isOn: $isTrackingShots)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .scaleEffect(0.8)
                    .onChange(of: isTrackingShots) { enabled in
                        if enabled {
                            enableShotTracking()
                        } else {
                            disableShotTracking()
                        }
                    }
            }
            
            if isTrackingShots {
                let holeShots = shotHistory.filter { $0.holeNumber == holeNumber }
                
                if holeShots.isEmpty {
                    HStack {
                        Image(systemName: "location.circle")
                            .foregroundColor(.blue)
                        Text("GPS ready - shots will be tracked automatically")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(holeShots.enumerated()), id: \.offset) { index, shot in
                            shotHistoryRow(shot, shotNumber: index + 1)
                        }
                    }
                }
                
                Button(action: {
                    showShotTracker = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Shot")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func shotHistoryRow(_ shot: ShotData, shotNumber: Int) -> some View {
        HStack {
            Text("#\(shotNumber)")
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 25)
            
            VStack(alignment: .leading) {
                Text(shot.clubUsed ?? "Unknown Club")
                    .font(.caption)
                    .fontWeight(.medium)
                
                if let distance = shot.distanceToPin {
                    Text("\(Int(distance))y to pin")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(shot.result.displayName)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(shot.result.color).opacity(0.2))
                .foregroundColor(Color(shot.result.color))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }
    
    private func holeStatisticsSection(_ stats: HoleStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Statistics")
                .font(.headline)
            
            HStack {
                statItem("Avg Score", value: String(format: "%.1f", stats.averageScore))
                Spacer()
                statItem("Best", value: "\(stats.bestScore)")
                Spacer()
                statItem("Played", value: "\(stats.timesPlayed)")
            }
            
            if stats.averageScore < Double(getHoleInfo(for: currentHole)?.par ?? 4) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("One of your stronger holes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func statItem(_ title: String, value: String) -> some View {
        VStack {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Scoring Controls
    
    private var scoringControls: some View {
        VStack(spacing: 12) {
            // Stroke counter for current hole
            HStack {
                Button(action: {
                    if currentStrokes > 0 {
                        currentStrokes -= 1
                        hapticService.impact(.light)
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title)
                        .foregroundColor(.red)
                }
                .disabled(currentStrokes <= 0)
                
                VStack {
                    Text("Strokes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(currentStrokes)")
                        .font(.title)
                        .fontWeight(.bold)
                }
                .frame(minWidth: 100)
                
                Button(action: {
                    if currentStrokes < 12 {
                        currentStrokes += 1
                        hapticService.impact(.light)
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundColor(.green)
                }
                .disabled(currentStrokes >= 12)
            }
            
            // Action buttons
            HStack(spacing: 16) {
                Button(action: {
                    saveCurrentHole()
                }) {
                    Text("Save Hole")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .disabled(currentStrokes == 0)
                
                Button(action: {
                    moveToNextHole()
                }) {
                    Text(currentHole < golfCourse.numberOfHoles ? "Next Hole" : "Finish Round")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(8)
                }
                .disabled(currentStrokes == 0 || !isHoleSaved(currentHole))
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.separator),
            alignment: .top
        )
    }
    
    // MARK: - Toolbar Buttons
    
    private var setupActionButtons: some View {
        HStack {
            Button(action: {
                showStatistics = true
                hapticService.impact(.light)
            }) {
                Image(systemName: "chart.bar")
            }
        }
    }
    
    private var roundActionButtons: some View {
        HStack {
            Button(action: {
                showHoleDetail = true
                hapticService.impact(.light)
            }) {
                Image(systemName: "info.circle")
            }
            
            Button(action: {
                showEndRoundConfirmation = true
                hapticService.impact(.medium)
            }) {
                Image(systemName: "stop.circle")
                    .foregroundColor(.red)
            }
        }
    }
    
    private var courseInfoButton: some View {
        Button(action: {
            showRoundSummary = true
            hapticService.impact(.light)
        }) {
            Image(systemName: "doc.text")
        }
    }
    
    // MARK: - Weather Section
    
    private func weatherSection(_ weather: WeatherConditions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weather Conditions")
                .font(.headline)
            
            HStack {
                Image(systemName: weather.conditions.icon)
                    .font(.title2)
                    .foregroundColor(weatherIconColor(weather.conditions))
                
                VStack(alignment: .leading) {
                    Text(weather.conditions.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(weather.formattedTemperature)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(weather.playabilityDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(playabilityColor(weather.playabilityScore))
                    Text("Golf Score: \(weather.playabilityScore)/10")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Processing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding()
            .background(Material.regular)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Helper Functions
    
    private func setupInitialState() {
        // Check if there's an active round for this course
        Task {
            do {
                let activeRounds = try await scorecardService.getActiveScorecards(for: userId)
                if let existingRound = activeRounds.first(where: { $0.courseId == golfCourse.id }) {
                    await MainActor.run {
                        activeScorecard = existingRound
                        isRoundInProgress = true
                        loadExistingScores()
                    }
                }
            } catch {
                print("Error checking for active rounds: \(error)")
            }
        }
    }
    
    private func loadCurrentHandicap() {
        Task {
            do {
                let handicap = try await scorecardService.calculateHandicapIndex(for: userId)
                await MainActor.run {
                    currentHandicap = handicap
                }
            } catch {
                print("Error loading handicap: \(error)")
                await MainActor.run {
                    currentHandicap = 18.0 // Default handicap
                }
            }
        }
    }
    
    private func loadWeatherConditions() {
        Task {
            do {
                let weather = try await weatherService.getWeatherForGolfCourse(golfCourse)
                await MainActor.run {
                    currentWeather = weather
                }
            } catch {
                print("Error loading weather: \(error)")
            }
        }
    }
    
    private func startNewRound() {
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            do {
                let scorecard = try await scorecardService.startNewRound(
                    userId: userId,
                    courseId: golfCourse.id,
                    teeType: selectedTeeType,
                    weather: currentWeather
                )
                
                await MainActor.run {
                    activeScorecard = scorecard
                    isRoundInProgress = true
                    currentHole = 1
                    currentStrokes = 0
                    holeScores.removeAll()
                    shotHistory.removeAll()
                    totalScore = 0
                    scoreToPar = 0
                    isLoading = false
                    hapticService.notification(.success)
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                    isLoading = false
                    hapticService.notification(.error)
                }
            }
        }
    }
    
    private func endCurrentRound() {
        guard let scorecard = activeScorecard else { return }
        
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            do {
                let finalScorecard = try await scorecardService.finishRound(scorecardId: scorecard.id)
                
                await MainActor.run {
                    activeScorecard = finalScorecard
                    isRoundInProgress = false
                    showRoundSummary = true
                    isLoading = false
                    hapticService.notification(.success)
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                    isLoading = false
                    hapticService.notification(.error)
                }
            }
        }
    }
    
    private func updateHoleScore(_ holeNumber: Int, strokes: Int) {
        let holeScore = HoleScore(
            holeNumber: holeNumber,
            par: getHoleInfo(for: holeNumber)?.par ?? 4,
            strokes: strokes,
            putts: nil, // Could be enhanced to track putts separately
            fairwayHit: nil,
            greenInRegulation: nil,
            shots: shotHistory.filter { $0.holeNumber == holeNumber }
        )
        
        holeScores[holeNumber] = holeScore
        currentStrokes = strokes
        recalculateScores()
    }
    
    private func saveCurrentHole() {
        guard currentStrokes > 0, let scorecard = activeScorecard else { return }
        
        updateHoleScore(currentHole, strokes: currentStrokes)
        
        Task {
            do {
                try await scorecardService.updateHoleScore(
                    scorecardId: scorecard.id,
                    holeScore: holeScores[currentHole]!
                )
                
                await MainActor.run {
                    hapticService.notification(.success)
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                    hapticService.notification(.error)
                }
            }
        }
    }
    
    private func moveToNextHole() {
        if !isHoleSaved(currentHole) {
            saveCurrentHole()
        }
        
        if currentHole < golfCourse.numberOfHoles {
            currentHole += 1
            currentStrokes = holeScores[currentHole]?.strokes ?? 0
            hapticService.impact(.medium)
        } else {
            // Round is complete
            endCurrentRound()
        }
    }
    
    private func loadExistingScores() {
        guard let scorecard = activeScorecard else { return }
        
        // Load scores from existing scorecard
        for hole in scorecard.holeScores {
            holeScores[hole.holeNumber] = hole
        }
        
        recalculateScores()
        
        // Set current hole to first unfinished hole
        currentHole = holeScores.keys.max() ?? 1
        if currentHole < golfCourse.numberOfHoles && holeScores[currentHole] != nil {
            currentHole += 1
        }
        
        currentStrokes = holeScores[currentHole]?.strokes ?? 0
    }
    
    private func recalculateScores() {
        totalScore = holeScores.values.reduce(0) { $0 + $1.strokes }
        
        let completedHoles = holeScores.count
        let expectedPar = completedHoles * 4 // Simplified - could use actual par per hole
        scoreToPar = totalScore - expectedPar
    }
    
    private func enableShotTracking() {
        locationService.enableHighAccuracyMode()
        currentLocation = locationService.currentLocation
        hapticService.impact(.light)
    }
    
    private func disableShotTracking() {
        locationService.disableHighAccuracyMode()
        hapticService.impact(.light)
    }
    
    private func recordShot(_ shot: ShotData) {
        shotHistory.append(shot)
        
        guard let scorecard = activeScorecard else { return }
        
        Task {
            do {
                try await scorecardService.recordShot(scorecardId: scorecard.id, shot: shot)
            } catch {
                print("Error recording shot: \(error)")
            }
        }
    }
    
    // MARK: - Data Helper Functions
    
    private func getCurrentHoleInfo() -> HoleInfo? {
        return getHoleInfo(for: currentHole)
    }
    
    private func getHoleInfo(for holeNumber: Int) -> HoleInfo? {
        // This would typically come from the golf course service
        // For now, return a mock hole info
        return HoleInfo(
            holeNumber: holeNumber,
            par: holeNumber <= 6 ? (holeNumber % 3 == 0 ? 5 : 4) : (holeNumber % 4 == 0 ? 3 : 4),
            yardages: [selectedTeeType: 150 + (holeNumber * 25)],
            description: "A challenging hole requiring precision and strategy.",
            proTip: "Play conservatively and aim for the center of the green.",
            difficulty: DifficultyLevel.allCases[holeNumber % DifficultyLevel.allCases.count],
            handicap: holeNumber
        )
    }
    
    private func getAvailableTees() -> [String] {
        let yardage = golfCourse.yardage
        var tees: [String] = []
        
        if yardage.championshipTees > 0 { tees.append("Championship") }
        if yardage.backTees > 0 { tees.append("Back") }
        tees.append("Regular")
        if yardage.forwardTees > 0 { tees.append("Forward") }
        if let _ = yardage.seniorTees { tees.append("Senior") }
        
        return tees
    }
    
    private func getYardageForTee(_ teeType: String) -> Int? {
        let yardage = golfCourse.yardage
        switch teeType {
        case "Championship": return yardage.championshipTees
        case "Back": return yardage.backTees
        case "Regular": return yardage.regularTees
        case "Forward": return yardage.forwardTees
        case "Senior": return yardage.seniorTees
        default: return yardage.regularTees
        }
    }
    
    private func getYardageForCurrentHole() -> Int {
        return getYardageForTee(selectedTeeType).map { $0 / golfCourse.numberOfHoles } ?? 180
    }
    
    private func getCompletedHoles() -> Int {
        return holeScores.count
    }
    
    private func isHoleSaved(_ holeNumber: Int) -> Bool {
        return holeScores[holeNumber] != nil
    }
    
    private func getHoleStatistics(_ holeNumber: Int) -> HoleStatistics? {
        // This would come from the scorecard service
        // Return mock data for now
        return HoleStatistics(
            holeNumber: holeNumber,
            timesPlayed: 12,
            averageScore: 4.2,
            bestScore: 3,
            worstScore: 7,
            parOrBetter: 6,
            birdieDelta: 2
        )
    }
    
    // MARK: - Style Helper Functions
    
    private func scoreToParText(_ scoreToPar: Int) -> String {
        switch scoreToPar {
        case -3: return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double"
        case 3: return "Triple"
        default: return scoreToPar > 0 ? "+\(scoreToPar)" : "\(scoreToPar)"
        }
    }
    
    private func scoreToParColor(_ scoreToPar: Int) -> Color {
        switch scoreToPar {
        case ...(-2): return .purple
        case -1: return .green
        case 0: return .blue
        case 1: return .orange
        default: return .red
        }
    }
    
    private func getScoreName(_ scoreToPar: Int) -> String {
        switch scoreToPar {
        case -3: return "Alba"
        case -2: return "Eagle"
        case -1: return "Bird"
        case 0: return "Par"
        case 1: return "Bog"
        case 2: return "Dbl"
        default: return "+\(scoreToPar)"
        }
    }
    
    private func weatherIconColor(_ conditions: WeatherConditions.WeatherType) -> Color {
        switch conditions {
        case .sunny: return .yellow
        case .partlyCloudy: return .blue
        case .overcast: return .gray
        case .lightRain, .drizzle: return .blue
        case .heavyRain, .thunderstorm: return .purple
        case .fog: return .secondary
        case .snow: return .white
        }
    }
    
    private func playabilityColor(_ score: Int) -> Color {
        switch score {
        case 8...10: return .green
        case 6...7: return .blue
        case 4...5: return .orange
        default: return .red
        }
    }
}

// MARK: - Supporting Views

struct HoleDetailView: View {
    let hole: HoleInfo
    let course: GolfCourse
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Hole header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hole \(hole.holeNumber)")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        HStack {
                            Text("Par \(hole.par)")
                                .font(.headline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                            
                            if let handicap = hole.handicap {
                                Text("Handicap \(handicap)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Yardages
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Yardages")
                            .font(.headline)
                        
                        ForEach(Array(hole.yardages.keys.sorted()), id: \.self) { teeType in
                            HStack {
                                Text(teeType)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(hole.yardages[teeType] ?? 0) yards")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Description and tips
                    if let description = hole.description {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            Text(description)
                                .font(.body)
                        }
                    }
                    
                    if let proTip = hole.proTip {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pro Tip")
                                .font(.headline)
                            HStack {
                                Image(systemName: "lightbulb")
                                    .foregroundColor(.yellow)
                                Text(proTip)
                                    .font(.body)
                                    .italic()
                            }
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle(course.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ShotTrackerView: View {
    let currentHole: Int
    let course: GolfCourse
    let onShotRecorded: (ShotData) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClub: String = "7 Iron"
    @State private var shotResult: ShotData.ShotResult = .fairway
    @State private var distanceToPin: Int = 150
    @State private var notes: String = ""
    
    let clubs = ["Driver", "3 Wood", "5 Wood", "3 Iron", "4 Iron", "5 Iron", "6 Iron", "7 Iron", "8 Iron", "9 Iron", "PW", "SW", "LW", "Putter"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Shot Details") {
                    Picker("Club", selection: $selectedClub) {
                        ForEach(clubs, id: \.self) { club in
                            Text(club).tag(club)
                        }
                    }
                    
                    HStack {
                        Text("Distance to Pin")
                        Spacer()
                        Text("\(distanceToPin) yards")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { Double(distanceToPin) },
                        set: { distanceToPin = Int($0) }
                    ), in: 0...500, step: 5)
                }
                
                Section("Result") {
                    Picker("Shot Result", selection: $shotResult) {
                        ForEach(ShotData.ShotResult.allCases, id: \.self) { result in
                            Text(result.displayName).tag(result)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Record Shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        recordShot()
                    }
                }
            }
        }
    }
    
    private func recordShot() {
        let shot = ShotData(
            holeNumber: currentHole,
            shotNumber: 1, // This would be calculated based on existing shots
            timestamp: Date(),
            location: CLLocationCoordinate2D(latitude: 0, longitude: 0), // Would use actual GPS
            clubUsed: selectedClub,
            distanceToPin: Double(distanceToPin),
            result: shotResult,
            notes: notes.isEmpty ? nil : notes
        )
        
        onShotRecorded(shot)
        dismiss()
    }
}

struct RoundSummaryView: View {
    let scorecard: Scorecard
    let course: GolfCourse
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Round header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(course.name)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Played \(scorecard.playedDate, format: .dateTime.weekday().month().day())")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Score summary
                    HStack {
                        scoreSummaryCard("Total Score", value: "\(scorecard.totalScore)")
                        scoreSummaryCard("To Par", value: scorecard.totalScore >= course.par ? "+\(scorecard.totalScore - course.par)" : "\(scorecard.totalScore - course.par)")
                        scoreSummaryCard("Handicap", value: String(format: "%.1f", scorecard.playingHandicap))
                    }
                    
                    // Hole-by-hole scores
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(scorecard.holeScores.sorted(by: { $0.holeNumber < $1.holeNumber })) { hole in
                            holeScoreCell(hole)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Round Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func scoreSummaryCard(_ title: String, value: String) -> some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(title == "To Par" ? (scorecard.totalScore >= course.par ? .red : .green) : .primary)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private func holeScoreCell(_ hole: HoleScore) -> some View {
        VStack(spacing: 2) {
            Text("\(hole.holeNumber)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(hole.strokes)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(scoreColor(hole.strokes - hole.par))
        }
        .frame(width: 40, height: 40)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(6)
    }
    
    private func scoreColor(_ scoreToPar: Int) -> Color {
        switch scoreToPar {
        case ...(-2): return .purple
        case -1: return .green
        case 0: return .blue
        case 1: return .orange
        default: return .red
        }
    }
}

struct PlayerStatisticsView: View {
    let userId: String
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your Golf Statistics")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    // This would be populated with actual statistics
                    Text("Statistics will be loaded here")
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Data Models

struct HoleStatistics {
    let holeNumber: Int
    let timesPlayed: Int
    let averageScore: Double
    let bestScore: Int
    let worstScore: Int
    let parOrBetter: Int
    let birdieDelta: Int
}

// MARK: - Preview

#Preview {
    ScorecardView(
        golfCourse: GolfCourse(
            id: "1",
            name: "Pebble Beach Golf Links",
            address: "1700 17 Mile Dr",
            city: "Pebble Beach",
            state: "CA",
            country: "US",
            zipCode: "93953",
            latitude: 36.5621,
            longitude: -121.9490,
            description: "One of the most beautiful and challenging golf courses in the world.",
            phoneNumber: "(831) 624-3811",
            website: "https://www.pebblebeach.com",
            email: nil,
            numberOfHoles: 18,
            par: 72,
            yardage: CourseYardage(championshipTees: 6828, backTees: 6536, regularTees: 6023, forwardTees: 5197, seniorTees: nil, juniorTees: nil),
            slope: CourseSlope(championshipSlope: 145, backSlope: 142, regularSlope: 130, forwardSlope: 122, seniorSlope: nil, juniorSlope: nil),
            rating: CourseRating(championshipRating: 75.5, backRating: 73.2, regularRating: 69.7, forwardRating: 64.8, seniorRating: nil, juniorRating: nil),
            pricing: CoursePricing(weekdayRates: [595], weekendRates: [595], twilightRates: [395], seniorRates: nil, juniorRates: nil, cartFee: 50, cartIncluded: true, membershipRequired: false, guestPolicy: .open, seasonalMultiplier: 1.0, peakTimeMultiplier: 1.0, advanceBookingDiscount: nil),
            amenities: [.drivingRange, .puttingGreen, .proShop, .restaurant, .bar],
            dressCode: .strict,
            cartPolicy: .required,
            images: [],
            virtualTour: nil,
            averageRating: 4.8,
            totalReviews: 1247,
            difficulty: .championship,
            operatingHours: OperatingHours(monday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), tuesday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), wednesday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), thursday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), friday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), saturday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00"), sunday: OperatingHours.DayHours(isOpen: true, openTime: "07:00", closeTime: "17:00", lastTeeTime: "16:00")),
            seasonalInfo: nil,
            bookingPolicy: BookingPolicy(advanceBookingDays: 30, cancellationPolicy: "24-hour cancellation policy", noShowPolicy: "No-shows will be charged full amount", modificationPolicy: "Changes allowed up to 24 hours", depositRequired: true, depositAmount: 100, refundableDeposit: false, groupBookingMinimum: 8, onlineBookingAvailable: true, phoneBookingRequired: false),
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true,
            isFeatured: true
        ),
        userId: "test_user"
    )
    .withServiceContainer()
}