import SwiftUI
import WatchKit

// MARK: - Quick Score View

struct QuickScoreView: View {
    // MARK: - Dependencies
    
    @WatchServiceInjected(WatchHapticFeedbackServiceProtocol.self) private var hapticService
    
    // MARK: - Parameters
    
    let round: ActiveGolfRound
    let hole: SharedHoleInfo
    let onScoreRecorded: (String) -> Void
    
    // MARK: - State
    
    @State private var selectedScore: Int
    @State private var showingCustomScore = false
    @State private var customScoreText = ""
    @Environment(\.presentationMode) var presentationMode
    
    // MARK: - Computed Properties
    
    private var currentScore: String? {
        round.scoreForHole(hole.holeNumber)
    }
    
    private var scoreRelativeToPar: Int {
        selectedScore - hole.par
    }
    
    private var scoreDescription: String {
        switch scoreRelativeToPar {
        case -3: return "Albatross 🦅"
        case -2: return "Eagle 🦅"
        case -1: return "Birdie 🐦"
        case 0: return "Par ➖"
        case 1: return "Bogey 🟡"
        case 2: return "Double 🔶"
        case 3: return "Triple 🔴"
        default: return scoreRelativeToPar > 0 ? "+\(scoreRelativeToPar) 🔴" : "\(scoreRelativeToPar) 💙"
        }
    }
    
    private var recommendedScores: [Int] {
        let par = hole.par
        return Array((par - 2)...(par + 4)).filter { $0 >= 1 && $0 <= 12 }
    }
    
    // MARK: - Initialization
    
    init(round: ActiveGolfRound, hole: SharedHoleInfo, onScoreRecorded: @escaping (String) -> Void) {
        self.round = round
        self.hole = hole
        self.onScoreRecorded = onScoreRecorded
        
        // Initialize with current score or par
        if let current = round.scoreForHole(hole.holeNumber), let score = Int(current) {
            _selectedScore = State(initialValue: score)
        } else {
            _selectedScore = State(initialValue: hole.par)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    holeHeaderView
                    
                    currentScoreIndicator
                    
                    digitalCrownScorePicker
                    
                    quickScoreButtons
                    
                    customScoreButton
                    
                    actionButtons
                }
                .padding(.horizontal, 8)
            }
            .navigationTitle("Score Entry")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        hapticService.playTaptic(.light)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                }
            }
        }
        .sheet(isPresented: $showingCustomScore) {
            CustomScoreEntryView(
                initialText: customScoreText,
                onSave: { score in
                    recordScore(score)
                },
                onCancel: {
                    showingCustomScore = false
                }
            )
        }
        .focusable(true)
        .digitalCrownRotation(
            $selectedScore,
            from: 1,
            through: 12,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }
    
    // MARK: - View Components
    
    private var holeHeaderView: some View {
        VStack(spacing: 4) {
            HStack {
                Text("HOLE \(hole.holeNumber)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                Spacer()
                Text("PAR \(hole.par)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
            }
            
            Text("\(hole.yardage) yards")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var currentScoreIndicator: some View {
        VStack(spacing: 8) {
            // Large score display
            Text("\(selectedScore)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .animation(.easeInOut(duration: 0.2), value: selectedScore)
            
            // Score description
            Text(scoreDescription)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(scoreRelativeToPar <= 0 ? .green : (scoreRelativeToPar <= 2 ? .orange : .red))
                .animation(.easeInOut(duration: 0.2), value: selectedScore)
            
            // Relative to par indicator
            HStack {
                if scoreRelativeToPar != 0 {
                    Text(scoreRelativeToPar > 0 ? "+\(scoreRelativeToPar)" : "\(scoreRelativeToPar)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(scoreRelativeToPar > 0 ? .red : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(scoreRelativeToPar > 0 ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                        )
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var digitalCrownScorePicker: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "digitalcrown.horizontal.press")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Turn Digital Crown")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
            
            // Score range indicator
            HStack {
                Text("1")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 2)
                    .overlay(
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: CGFloat(selectedScore - 1) * 10 - 55) // Approximate positioning
                    )
                
                Text("12")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 120)
        }
        .padding(.vertical, 8)
    }
    
    private var quickScoreButtons: some View {
        VStack(spacing: 8) {
            Text("Quick Select")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(recommendedScores, id: \.self) { score in
                    Button(action: {
                        hapticService.playTaptic(.light)
                        selectedScore = score
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
                        .foregroundColor(selectedScore == score ? .white : .primary)
                        .frame(minWidth: 44, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedScore == score ? Color.blue : Color(.systemGray5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedScore == score ? Color.blue : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var customScoreButton: some View {
        Button(action: {
            hapticService.playTaptic(.light)
            customScoreText = "\(selectedScore)"
            showingCustomScore = true
        }) {
            HStack {
                Image(systemName: "textformat.123")
                    .font(.caption)
                Text("Enter Custom Score")
                    .font(.caption)
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var actionButtons: some View {
        VStack(spacing: 8) {
            // Save Score Button
            Button(action: {
                recordScore("\(selectedScore)")
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                    
                    if currentScore != nil {
                        Text("Update Score")
                            .fontWeight(.semibold)
                    } else {
                        Text("Save Score")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.green)
                .cornerRadius(25)
            }
            .buttonStyle(PlainButtonStyle())
            
            // No Score Button (for penalty/water situations)
            if currentScore == nil {
                Button(action: {
                    recordScore("X")
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .font(.body)
                        Text("No Score (X)")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Actions
    
    private func recordScore(_ score: String) {
        hapticService.playTaptic(.success)
        onScoreRecorded(score)
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Custom Score Entry View

struct CustomScoreEntryView: View {
    let initialText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    @State private var scoreText: String
    @Environment(\.presentationMode) var presentationMode
    @WatchServiceInjected(WatchHapticFeedbackServiceProtocol.self) private var hapticService
    
    init(initialText: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        self.onCancel = onCancel
        _scoreText = State(initialValue: initialText)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Enter Score")
                    .font(.headline)
                    .padding(.top)
                
                TextField("Score", text: $scoreText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 8) {
                    Button("Save") {
                        if !scoreText.isEmpty {
                            hapticService.playTaptic(.success)
                            onSave(scoreText)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(scoreText.isEmpty ? Color.gray : Color.blue)
                    .cornerRadius(8)
                    .disabled(scoreText.isEmpty)
                    
                    Button("Cancel") {
                        hapticService.playTaptic(.light)
                        onCancel()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Preview

struct QuickScoreView_Previews: PreviewProvider {
    static var previews: some View {
        let mockRound = ActiveGolfRound(
            id: "mock-round",
            courseId: "mock-course",
            courseName: "Mock Golf Club",
            startTime: Date(),
            currentHole: 1,
            scores: [:],
            totalScore: 0,
            totalPar: 0,
            holes: [],
            teeType: .regular
        )
        
        let mockHole = SharedHoleInfo(
            id: "mock-hole",
            holeNumber: 1,
            par: 4,
            yardage: 350,
            handicapIndex: 1,
            teeCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            pinCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            hazards: []
        )
        
        QuickScoreView(round: mockRound, hole: mockHole) { score in
            print("Score recorded: \(score)")
        }
        .withWatchServiceContainer(
            WatchServiceContainer(environment: .test)
        )
    }
}