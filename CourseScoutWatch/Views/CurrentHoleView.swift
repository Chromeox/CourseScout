import SwiftUI
import CoreLocation

// MARK: - Current Hole View

struct CurrentHoleView: View {
    // MARK: - Dependencies
    
    @WatchServiceInjected(WatchGolfCourseServiceProtocol.self) private var courseService
    @WatchServiceInjected(WatchScorecardServiceProtocol.self) private var scorecardService
    @WatchServiceInjected(WatchGPSServiceProtocol.self) private var gpsService
    @WatchServiceInjected(WatchHapticFeedbackServiceProtocol.self) private var hapticService
    
    // MARK: - State
    
    @State private var currentRound: ActiveGolfRound?
    @State private var currentHole: SharedHoleInfo?
    @State private var distanceToPin: Int?
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var recommendedClub: String?
    @State private var isLoading = true
    @State private var showingScoreEntry = false
    
    // MARK: - Lifecycle
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    if isLoading {
                        loadingView
                    } else if let round = currentRound, let hole = currentHole {
                        holeHeaderView(round: round, hole: hole)
                        
                        if let distance = distanceToPin {
                            distanceView(distance: distance)
                        }
                        
                        if let club = recommendedClub {
                            clubRecommendationView(club: club)
                        }
                        
                        holeDetailsView(hole: hole)
                        
                        scoreActionButton(round: round, hole: hole)
                        
                        navigationButtons(round: round)
                    } else {
                        noRoundView
                    }
                }
                .padding(.horizontal, 8)
                .frame(minHeight: geometry.size.height)
            }
        }
        .navigationTitle("Current Hole")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingScoreEntry) {
            if let round = currentRound, let hole = currentHole {
                QuickScoreView(
                    round: round,
                    hole: hole,
                    onScoreRecorded: { score in
                        Task {
                            await recordScore(score, for: hole.holeNumber)
                        }
                    }
                )
            }
        }
        .task {
            await loadCurrentRound()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didUpdateLocation)) { notification in
            if let location = notification.object as? CLLocationCoordinate2D {
                userLocation = location
                Task {
                    await updateDistance()
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading round...")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func holeHeaderView(round: ActiveGolfRound, hole: SharedHoleInfo) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("HOLE")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(round.formattedScore)
                    .font(.caption2)
                    .foregroundColor(round.scoreRelativeToPar >= 0 ? .red : .green)
                    .fontWeight(.semibold)
            }
            
            HStack {
                Text("\(hole.holeNumber)")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PAR \(hole.par)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("\(hole.yardage) YDS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func distanceView(distance: Int) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                
                Text("DISTANCE TO PIN")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
            }
            
            Text("\(distance)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("yards")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGreen).opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGreen), lineWidth: 1)
        )
    }
    
    private func clubRecommendationView(club: String) -> some View {
        HStack {
            Image(systemName: "figure.golf")
                .foregroundColor(.blue)
                .font(.caption)
            
            Text("Recommended:")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(club)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBlue).opacity(0.1))
        .cornerRadius(8)
    }
    
    private func holeDetailsView(hole: SharedHoleInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HOLE DETAILS")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Handicap")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(hole.handicapIndex)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                if !hole.hazards.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Hazards")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(hole.hazards.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func scoreActionButton(round: ActiveGolfRound, hole: SharedHoleInfo) -> some View {
        Button(action: {
            hapticService.playTaptic(.light)
            showingScoreEntry = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                
                if let currentScore = round.scoreForHole(hole.holeNumber) {
                    Text("Score: \(currentScore)")
                        .fontWeight(.semibold)
                } else {
                    Text("Enter Score")
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(round.hasScoreForHole(hole.holeNumber) ? Color.orange : Color.blue)
            .cornerRadius(25)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func navigationButtons(round: ActiveGolfRound) -> some View {
        HStack(spacing: 8) {
            // Previous Hole
            Button(action: {
                hapticService.playTaptic(.light)
                Task {
                    await navigateToHole(round.currentHole - 1)
                }
            }) {
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                    Text("Prev")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(round.currentHole > 1 ? Color.gray : Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
            .disabled(round.currentHole <= 1)
            .buttonStyle(PlainButtonStyle())
            
            // Next Hole
            Button(action: {
                hapticService.playTaptic(.light)
                if round.hasScoreForHole(round.currentHole) {
                    Task {
                        await advanceToNextHole()
                    }
                } else {
                    // Show score entry if no score recorded
                    showingScoreEntry = true
                }
            }) {
                HStack {
                    Text("Next")
                        .font(.caption)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(round.currentHole < round.holes.count ? Color.green : Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
            .disabled(round.currentHole > round.holes.count)
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var noRoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "golf.course")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No Active Round")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Start a new round on your iPhone or Apple Watch to see hole information")
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
        
        do {
            currentRound = await scorecardService.getCurrentRound()
            
            if let round = currentRound {
                currentHole = round.currentHoleInfo
                await updateDistance()
                await updateClubRecommendation()
            }
        }
        
        isLoading = false
    }
    
    private func updateDistance() async {
        guard let location = userLocation,
              let hole = currentHole else { return }
        
        let distance = await courseService.getDistanceToPin(
            from: location,
            holeNumber: hole.holeNumber
        )
        
        await MainActor.run {
            distanceToPin = distance
        }
    }
    
    private func updateClubRecommendation() async {
        guard let distance = distanceToPin else { return }
        
        let club = await courseService.getRecommendedClub(for: distance, conditions: nil)
        
        await MainActor.run {
            recommendedClub = club
        }
    }
    
    private func recordScore(_ score: String, for holeNumber: Int) async {
        let success = await scorecardService.recordScore(score, forHole: holeNumber)
        
        if success {
            await MainActor.run {
                hapticService.playTaptic(.success)
            }
            
            // Reload current round to reflect changes
            await loadCurrentRound()
        } else {
            await MainActor.run {
                hapticService.playTaptic(.error)
            }
        }
    }
    
    private func advanceToNextHole() async {
        if let nextHole = await scorecardService.advanceToNextHole() {
            await MainActor.run {
                hapticService.playTaptic(.success)
            }
            
            // Reload to show new current hole
            await loadCurrentRound()
        }
    }
    
    private func navigateToHole(_ holeNumber: Int) async {
        guard let round = currentRound,
              holeNumber >= 1 && holeNumber <= round.holes.count else { return }
        
        // Update the current hole in the round
        currentRound?.currentHole = holeNumber
        currentHole = round.holes.first { $0.holeNumber == holeNumber }
        
        await updateDistance()
        await updateClubRecommendation()
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let didUpdateLocation = Notification.Name("didUpdateLocation")
}

// MARK: - Preview

struct CurrentHoleView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CurrentHoleView()
        }
        .withWatchServiceContainer(
            WatchServiceContainer(environment: .test)
        )
    }
}