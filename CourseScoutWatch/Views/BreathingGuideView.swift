import SwiftUI
import WatchKit

// MARK: - Breathing Guide View

struct BreathingGuideView: View {
    // MARK: - Dependencies
    
    @WatchServiceInjected(WatchHapticFeedbackServiceProtocol.self) private var hapticService
    
    // MARK: - Parameters
    
    @Binding var phase: BreathingPhase
    @Binding var count: Int
    let onComplete: () -> Void
    
    // MARK: - State
    
    @State private var progress: Double = 0
    @State private var isActive = false
    @State private var timer: Timer?
    @State private var currentCycle = 0
    @State private var totalCycles = 5
    @State private var phaseTimer: Timer?
    @Environment(\.presentationMode) var presentationMode
    
    // MARK: - Constants
    
    private let inhaleTime: TimeInterval = 4.0
    private let holdTime: TimeInterval = 4.0
    private let exhaleTime: TimeInterval = 6.0
    private let restTime: TimeInterval = 2.0
    
    // MARK: - Computed Properties
    
    private var currentPhaseDuration: TimeInterval {
        switch phase {
        case .inhale: return inhaleTime
        case .hold: return holdTime
        case .exhale: return exhaleTime
        case .rest: return restTime
        }
    }
    
    private var phaseInstruction: String {
        switch phase {
        case .inhale: return "Breathe In"
        case .hold: return "Hold"
        case .exhale: return "Breathe Out"
        case .rest: return "Rest"
        }
    }
    
    private var phaseDescription: String {
        switch phase {
        case .inhale: return "Slowly inhale through your nose"
        case .hold: return "Hold your breath comfortably"
        case .exhale: return "Exhale slowly through your mouth"
        case .rest: return "Relax and prepare for the next breath"
        }
    }
    
    private var phaseColor: Color {
        switch phase {
        case .inhale: return .mint
        case .hold: return .blue
        case .exhale: return .orange
        case .rest: return .purple
        }
    }
    
    private var progressPercentage: Double {
        return Double(currentCycle) / Double(totalCycles)
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                // Header
                headerView
                
                // Main breathing animation
                breathingAnimationView(size: geometry.size)
                
                // Phase instruction
                phaseInstructionView
                
                // Progress indicator
                progressIndicatorView
                
                // Control buttons
                if !isActive {
                    controlButtonsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(phaseColor.opacity(0.1))
        }
        .navigationTitle("Breathing")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isActive)
        .onAppear {
            setupBreathingSession()
        }
        .onDisappear {
            stopBreathingSession()
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        VStack(spacing: 4) {
            Text("Mindful Breathing")
                .font(.headline)
                .fontWeight(.semibold)
            
            if isActive {
                Text("Cycle \(currentCycle + 1) of \(totalCycles)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("4-4-6 Breathing Technique")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func breathingAnimationView(size: CGSize) -> some View {
        ZStack {
            // Background circle
            Circle()
                .fill(phaseColor.opacity(0.2))
                .frame(width: 120, height: 120)
            
            // Animated breathing circle
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [phaseColor.opacity(0.8), phaseColor.opacity(0.3)]),
                        center: .center,
                        startRadius: 20,
                        endRadius: 60
                    )
                )
                .frame(width: 60, height: 60)
                .scaleEffect(breathingScale)
                .animation(breathingAnimation, value: progress)
                .overlay(
                    Circle()
                        .stroke(phaseColor, lineWidth: 2)
                        .scaleEffect(breathingScale)
                        .animation(breathingAnimation, value: progress)
                )
            
            // Progress indicator
            Circle()
                .trim(from: 0, to: progress)
                .stroke(phaseColor, lineWidth: 4)
                .frame(width: 130, height: 130)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
            
            // Phase icon
            Image(systemName: phaseIcon)
                .font(.title2)
                .foregroundColor(phaseColor)
                .scaleEffect(breathingScale * 0.8)
                .animation(breathingAnimation, value: progress)
        }
    }
    
    private var phaseInstructionView: some View {
        VStack(spacing: 8) {
            Text(phaseInstruction)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(phaseColor)
                .animation(.easeInOut(duration: 0.3), value: phase)
            
            Text(phaseDescription)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .animation(.easeInOut(duration: 0.3), value: phase)
            
            if isActive {
                Text(String(format: "%.0f", currentPhaseDuration - (progress * currentPhaseDuration)))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(phaseColor)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var progressIndicatorView: some View {
        VStack(spacing: 8) {
            // Cycle progress
            HStack {
                ForEach(0..<totalCycles, id: \.self) { cycle in
                    Circle()
                        .fill(cycle <= currentCycle ? phaseColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(cycle == currentCycle ? 1.2 : 1.0)
                        .animation(.spring(), value: currentCycle)
                }
            }
            
            // Overall progress
            ProgressView(value: progressPercentage)
                .progressViewStyle(LinearProgressViewStyle(tint: phaseColor))
                .scaleEffect(y: 2)
        }
        .padding(.horizontal, 20)
    }
    
    private var controlButtonsView: some View {
        VStack(spacing: 8) {
            // Start button
            Button(action: {
                startBreathingSession()
            }) {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.body)
                    Text("Start Session")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(phaseColor)
                .cornerRadius(25)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Customize duration
            HStack(spacing: 8) {
                Button("3 cycles") {
                    totalCycles = 3
                    hapticService.playTaptic(.light)
                }
                .font(.caption)
                .foregroundColor(totalCycles == 3 ? .white : phaseColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(totalCycles == 3 ? phaseColor : phaseColor.opacity(0.2))
                .cornerRadius(12)
                
                Button("5 cycles") {
                    totalCycles = 5
                    hapticService.playTaptic(.light)
                }
                .font(.caption)
                .foregroundColor(totalCycles == 5 ? .white : phaseColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(totalCycles == 5 ? phaseColor : phaseColor.opacity(0.2))
                .cornerRadius(12)
                
                Button("10 cycles") {
                    totalCycles = 10
                    hapticService.playTaptic(.light)
                }
                .font(.caption)
                .foregroundColor(totalCycles == 10 ? .white : phaseColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(totalCycles == 10 ? phaseColor : phaseColor.opacity(0.2))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Computed Properties for Animation
    
    private var breathingScale: CGFloat {
        switch phase {
        case .inhale: return 1.0 + (progress * 0.5) // Expand
        case .hold: return 1.5 // Stay expanded
        case .exhale: return 1.5 - (progress * 0.5) // Contract
        case .rest: return 1.0 // Normal size
        }
    }
    
    private var breathingAnimation: Animation {
        switch phase {
        case .inhale: return .easeIn(duration: inhaleTime)
        case .hold: return .linear(duration: holdTime)
        case .exhale: return .easeOut(duration: exhaleTime)
        case .rest: return .easeInOut(duration: restTime)
        }
    }
    
    private var phaseIcon: String {
        switch phase {
        case .inhale: return "arrow.up.circle.fill"
        case .hold: return "pause.circle.fill"
        case .exhale: return "arrow.down.circle.fill"
        case .rest: return "moon.circle.fill"
        }
    }
    
    // MARK: - Actions
    
    private func setupBreathingSession() {
        phase = .inhale
        progress = 0
        currentCycle = 0
    }
    
    private func startBreathingSession() {
        isActive = true
        currentCycle = 0
        startBreathingCycle()
        
        hapticService.playTaptic(.success)
    }
    
    private func startBreathingCycle() {
        phase = .inhale
        progress = 0
        startPhase()
    }
    
    private func startPhase() {
        // Provide haptic feedback for phase changes
        switch phase {
        case .inhale:
            hapticService.playBreathingInhale()
        case .hold:
            hapticService.playBreathingHold()
        case .exhale:
            hapticService.playBreathingExhale()
        case .rest:
            hapticService.playTaptic(.light)
        }
        
        // Start progress timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateProgress()
        }
        
        // Set phase completion timer
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: currentPhaseDuration, repeats: false) { _ in
            completePhase()
        }
    }
    
    private func updateProgress() {
        let increment = 0.1 / currentPhaseDuration
        progress = min(progress + increment, 1.0)
    }
    
    private func completePhase() {
        timer?.invalidate()
        progress = 0
        
        switch phase {
        case .inhale:
            phase = .hold
            startPhase()
        case .hold:
            phase = .exhale
            startPhase()
        case .exhale:
            phase = .rest
            startPhase()
        case .rest:
            completeCycle()
        }
    }
    
    private func completeCycle() {
        currentCycle += 1
        
        if currentCycle >= totalCycles {
            completeSession()
        } else {
            // Start next cycle
            startBreathingCycle()
        }
    }
    
    private func completeSession() {
        stopBreathingSession()
        
        // Completion haptics
        hapticService.playTaptic(.success)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            hapticService.playTaptic(.success)
        }
        
        // Call completion handler
        onComplete()
        
        // Dismiss after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func stopBreathingSession() {
        isActive = false
        timer?.invalidate()
        phaseTimer?.invalidate()
        timer = nil
        phaseTimer = nil
        progress = 0
    }
}

// MARK: - Haptic Feedback Extensions

extension WatchHapticFeedbackServiceProtocol {
    func playBreathingInhale() {
        // Gentle ascending haptic for inhale
        playTaptic(.light)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.playTaptic(.light)
        }
    }
    
    func playBreathingHold() {
        // Single medium tap for hold
        playTaptic(.medium)
    }
    
    func playBreathingExhale() {
        // Descending haptic pattern for exhale
        playTaptic(.medium)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.playTaptic(.light)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.playTaptic(.light)
        }
    }
    
    func playMilestoneHaptic() {
        // Special celebration pattern for milestones
        playTaptic(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.playTaptic(.success)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.playTaptic(.success)
        }
    }
}

// MARK: - Preview

struct BreathingGuideView_Previews: PreviewProvider {
    static var previews: some View {
        BreathingGuideView(
            phase: .constant(.inhale),
            count: .constant(0)
        ) {
            print("Breathing session completed")
        }
        .withWatchServiceContainer(
            WatchServiceContainer(environment: .test)
        )
    }
}