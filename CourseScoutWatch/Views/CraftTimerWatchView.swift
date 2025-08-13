import SwiftUI
import WatchKit
import Combine

// MARK: - Craft Timer Watch View

struct CraftTimerWatchView: View {
    // MARK: - Dependencies
    
    @WatchServiceInjected(WatchHapticFeedbackServiceProtocol.self) private var hapticService
    @WatchServiceInjected(WatchHealthKitServiceProtocol.self) private var healthService
    @WatchServiceInjected(WatchConnectivityServiceProtocol.self) private var connectivityService
    
    // MARK: - State
    
    @State private var craftSession: CraftSession?
    @State private var isActive = false
    @State private var isPaused = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var heartRate: Double = 0
    @State private var caloriesBurned: Double = 0
    @State private var milestonesReached: [CraftMilestone] = []
    @State private var showingBreathingReminder = false
    @State private var currentZone: HeartRateZone = .resting
    
    // Breathing guidance
    @State private var showingBreathingGuide = false
    @State private var breathingPhase: BreathingPhase = .inhale
    @State private var breathingTimer: Timer?
    @State private var breathingCount = 0
    
    // MARK: - Computed Properties
    
    private var formattedTime: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = Int(elapsedTime) % 3600 / 60
        let seconds = Int(elapsedTime) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private var progressPercentage: Double {
        guard let session = craftSession, session.targetDuration > 0 else { return 0 }
        return min(elapsedTime / session.targetDuration, 1.0)
    }
    
    private var remainingTime: TimeInterval {
        guard let session = craftSession else { return 0 }
        return max(session.targetDuration - elapsedTime, 0)
    }
    
    private var nextMilestone: CraftMilestone? {
        guard let session = craftSession else { return nil }
        return session.milestones.first { milestone in
            milestone.timeThreshold > elapsedTime && !milestonesReached.contains(milestone)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    if let session = craftSession {
                        craftSessionView(session: session, size: geometry.size)
                    } else {
                        craftSelectionView
                    }
                }
                .padding(.horizontal, 4)
                .frame(minHeight: geometry.size.height)
            }
        }
        .navigationTitle("Craft Timer")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingBreathingGuide) {
            BreathingGuideView(
                phase: $breathingPhase,
                count: $breathingCount,
                onComplete: {
                    completeBreathingSession()
                }
            )
        }
        .alert("Breathing Reminder", isPresented: $showingBreathingReminder) {
            Button("Start Breathing") {
                showingBreathingGuide = true
            }
            Button("Later") { }
        } message: {
            Text("Take a moment for mindful breathing to enhance your golf focus and relaxation.")
        }
        .onAppear {
            requestHealthPermissions()
        }
        .onDisappear {
            pauseTimerIfActive()
        }
    }
    
    // MARK: - Craft Selection View
    
    private var craftSelectionView: some View {
        VStack(spacing: 16) {
            Text("Choose Your Practice")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(CraftType.allCases, id: \.self) { type in
                    craftTypeButton(type)
                }
            }
            
            // Quick start options
            VStack(spacing: 8) {
                Text("Quick Start")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    quickStartButton(duration: 10 * 60, title: "10m")
                    quickStartButton(duration: 20 * 60, title: "20m")
                    quickStartButton(duration: 30 * 60, title: "30m")
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func craftTypeButton(_ type: CraftType) -> some View {
        Button(action: {
            selectCraftType(type)
        }) {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.title3)
                    .foregroundColor(type.color)
                
                Text(type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(type.color.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(type.color, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func quickStartButton(duration: TimeInterval, title: String) -> some View {
        Button(action: {
            startQuickSession(duration: duration)
        }) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Active Session View
    
    private func craftSessionView(session: CraftSession, size: CGSize) -> some View {
        VStack(spacing: 12) {
            // Session header
            sessionHeaderView(session: session)
            
            // Main timer display
            timerDisplayView(session: session)
            
            // Progress indicator
            progressIndicatorView(session: session)
            
            // Health metrics
            if isActive {
                healthMetricsView
            }
            
            // Milestone progress
            if let milestone = nextMilestone {
                nextMilestoneView(milestone: milestone)
            }
            
            // Control buttons
            controlButtonsView(session: session)
            
            // Breathing reminder
            if shouldShowBreathingReminder {
                breathingReminderView
            }
        }
    }
    
    private func sessionHeaderView(session: CraftSession) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: session.type.icon)
                    .foregroundColor(session.type.color)
                    .font(.caption)
                
                Text(session.type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                if session.targetDuration > 0 {
                    Text("Target: \(formatDuration(session.targetDuration))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private func timerDisplayView(session: CraftSession) -> some View {
        VStack(spacing: 8) {
            // Main time display
            Text(formattedTime)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .animation(.easeInOut(duration: 0.1), value: elapsedTime)
            
            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(isActive ? (isPaused ? Color.orange : Color.green) : Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isActive && !isPaused ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isActive && !isPaused)
                
                Text(isActive ? (isPaused ? "PAUSED" : "ACTIVE") : "READY")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            // Remaining time for targeted sessions
            if session.targetDuration > 0 && isActive {
                Text("Remaining: \(formatDuration(remainingTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 16)
    }
    
    private func progressIndicatorView(session: CraftSession) -> some View {
        VStack(spacing: 8) {
            // Circular progress for targeted sessions
            if session.targetDuration > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: progressPercentage)
                        .stroke(session.type.color, lineWidth: 4)
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progressPercentage)
                    
                    Text("\(Int(progressPercentage * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(session.type.color)
                }
            } else {
                // Linear progress for open-ended sessions
                ProgressView(value: min(elapsedTime / (30 * 60), 1.0))
                    .progressViewStyle(LinearProgressViewStyle(tint: session.type.color))
                    .scaleEffect(y: 2)
            }
            
            // Milestone indicators
            if !session.milestones.isEmpty {
                milestoneProgressView(session: session)
            }
        }
    }
    
    private func milestoneProgressView(session: CraftSession) -> some View {
        HStack {
            ForEach(session.milestones.prefix(5)) { milestone in
                Circle()
                    .fill(milestonesReached.contains(milestone) ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(milestonesReached.contains(milestone) ? 1.2 : 1.0)
                    .animation(.spring(), value: milestonesReached.count)
                
                if milestone != session.milestones.last {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var healthMetricsView: some View {
        HStack {
            // Heart rate
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.caption2)
                    Text("HR")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text("\(Int(heartRate))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(currentZone.color)
            }
            
            Spacer()
            
            // Zone indicator
            VStack(spacing: 2) {
                Text("Zone")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(currentZone.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(currentZone.color)
            }
            
            Spacer()
            
            // Calories
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text("CAL")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text("\(Int(caloriesBurned))")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func nextMilestoneView(milestone: CraftMilestone) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundColor(.blue)
                    .font(.caption2)
                
                Text("Next Milestone")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("in \(formatDuration(milestone.timeThreshold - elapsedTime))")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            Text(milestone.message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue, lineWidth: 1)
        )
    }
    
    private func controlButtonsView(session: CraftSession) -> some View {
        VStack(spacing: 8) {
            // Primary action button
            Button(action: {
                if isActive {
                    if isPaused {
                        resumeTimer()
                    } else {
                        pauseTimer()
                    }
                } else {
                    startTimer()
                }
            }) {
                HStack {
                    Image(systemName: isActive ? (isPaused ? "play.fill" : "pause.fill") : "play.fill")
                        .font(.body)
                    
                    Text(isActive ? (isPaused ? "Resume" : "Pause") : "Start")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isActive ? (isPaused ? Color.green : Color.orange) : Color.green)
                .cornerRadius(25)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Secondary actions
            HStack(spacing: 8) {
                if isActive {
                    // Complete button
                    Button(action: {
                        completeSession()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .font(.caption)
                            Text("Complete")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Stop/Reset button
                Button(action: {
                    if isActive {
                        stopSession()
                    } else {
                        resetSession()
                    }
                }) {
                    HStack {
                        Image(systemName: isActive ? "stop.fill" : "arrow.clockwise")
                            .font(.caption)
                        Text(isActive ? "Stop" : "Reset")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var breathingReminderView: some View {
        Button(action: {
            showingBreathingGuide = true
        }) {
            HStack {
                Image(systemName: "wind")
                    .foregroundColor(.mint)
                    .font(.caption)
                
                Text("Mindful Breathing")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.mint)
                    .font(.caption2)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.mint.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.mint, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Properties
    
    private var shouldShowBreathingReminder: Bool {
        guard let session = craftSession else { return false }
        
        // Show breathing reminder for meditation/focus sessions
        let shouldShow = session.type == .meditation || session.type == .focus
        let timePassed = Int(elapsedTime) % (10 * 60) == 0 && elapsedTime > 0 // Every 10 minutes
        
        return shouldShow && timePassed && !showingBreathingGuide
    }
    
    // MARK: - Actions
    
    private func selectCraftType(_ type: CraftType) {
        hapticService.playTaptic(.light)
        
        let session = CraftSession(
            type: type,
            targetDuration: type.defaultDuration,
            milestones: type.defaultMilestones
        )
        
        craftSession = session
    }
    
    private func startQuickSession(duration: TimeInterval) {
        hapticService.playTaptic(.light)
        
        let session = CraftSession(
            type: .focus,
            targetDuration: duration,
            milestones: CraftType.focus.defaultMilestones.filter { $0.timeThreshold <= duration }
        )
        
        craftSession = session
    }
    
    private func startTimer() {
        guard let session = craftSession else { return }
        
        isActive = true
        isPaused = false
        
        // Start health monitoring
        startHealthMonitoring()
        
        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateTimer()
        }
        
        // Haptic feedback
        hapticService.playTaptic(.success)
        
        // Sync with iPhone
        syncSessionState()
    }
    
    private func pauseTimer() {
        isPaused = true
        timer?.invalidate()
        timer = nil
        
        hapticService.playTaptic(.light)
        syncSessionState()
    }
    
    private func resumeTimer() {
        isPaused = false
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateTimer()
        }
        
        hapticService.playTaptic(.success)
        syncSessionState()
    }
    
    private func stopSession() {
        isActive = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        
        // Stop health monitoring
        stopHealthMonitoring()
        
        hapticService.playTaptic(.warning)
        syncSessionState()
    }
    
    private func completeSession() {
        guard let session = craftSession else { return }
        
        // Mark as completed
        isActive = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        
        // Stop health monitoring
        stopHealthMonitoring()
        
        // Completion haptic feedback
        hapticService.playTaptic(.success)
        hapticService.playTaptic(.success) // Double tap for completion
        
        // Record session completion
        recordSessionCompletion(session)
        
        // Sync completion
        syncSessionState()
    }
    
    private func resetSession() {
        elapsedTime = 0
        milestonesReached = []
        caloriesBurned = 0
        
        hapticService.playTaptic(.light)
    }
    
    private func pauseTimerIfActive() {
        if isActive && !isPaused {
            pauseTimer()
        }
    }
    
    private func updateTimer() {
        elapsedTime += 1
        
        // Check for milestones
        checkMilestones()
        
        // Update health metrics
        updateHealthMetrics()
        
        // Check for completion
        if let session = craftSession, 
           session.targetDuration > 0 && 
           elapsedTime >= session.targetDuration {
            completeSession()
        }
        
        // Periodic sync (every 30 seconds)
        if Int(elapsedTime) % 30 == 0 {
            syncSessionState()
        }
    }
    
    private func checkMilestones() {
        guard let session = craftSession else { return }
        
        for milestone in session.milestones {
            if elapsedTime >= milestone.timeThreshold && !milestonesReached.contains(milestone) {
                milestonesReached.append(milestone)
                
                // Milestone haptic feedback
                hapticService.playMilestoneHaptic()
                
                // Show breathing reminder for specific milestones
                if milestone.includesBreathingReminder {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showingBreathingReminder = true
                    }
                }
            }
        }
    }
    
    // MARK: - Health Integration
    
    private func requestHealthPermissions() {
        Task {
            await healthService.requestAuthorization()
        }
    }
    
    private func startHealthMonitoring() {
        Task {
            await healthService.startWorkoutSession(type: .golf)
            
            // Start heart rate monitoring
            for await heartRateUpdate in await healthService.heartRateUpdates() {
                await MainActor.run {
                    heartRate = heartRateUpdate.value
                    currentZone = HeartRateZone.from(heartRate: heartRate, age: 35) // TODO: Use actual age
                }
            }
        }
    }
    
    private func stopHealthMonitoring() {
        Task {
            await healthService.endWorkoutSession()
        }
    }
    
    private func updateHealthMetrics() {
        Task {
            let calories = await healthService.getCurrentCaloriesBurned()
            await MainActor.run {
                caloriesBurned = calories
            }
        }
    }
    
    private func recordSessionCompletion(_ session: CraftSession) {
        let sessionData = CraftSessionResult(
            type: session.type,
            duration: elapsedTime,
            targetDuration: session.targetDuration,
            milestonesReached: milestonesReached.count,
            averageHeartRate: heartRate,
            caloriesBurned: caloriesBurned,
            completedAt: Date()
        )
        
        // Record locally and sync to iPhone
        Task {
            await healthService.recordCraftSession(sessionData)
        }
    }
    
    private func completeBreathingSession() {
        hapticService.playTaptic(.success)
        showingBreathingGuide = false
        showingBreathingReminder = false
    }
    
    // MARK: - Synchronization
    
    private func syncSessionState() {
        guard let session = craftSession else { return }
        
        let sessionState = WatchSessionState(
            session: session,
            isActive: isActive,
            isPaused: isPaused,
            elapsedTime: elapsedTime,
            heartRate: heartRate,
            caloriesBurned: caloriesBurned,
            milestonesReached: milestonesReached
        )
        
        Task {
            try? await connectivityService.sendTimerUpdate(sessionState)
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Supporting Types

struct CraftSession: Identifiable {
    let id = UUID()
    let type: CraftType
    let targetDuration: TimeInterval
    let milestones: [CraftMilestone]
}

enum CraftType: String, CaseIterable {
    case meditation = "meditation"
    case focus = "focus"
    case breathing = "breathing"
    case visualization = "visualization"
    
    var displayName: String {
        switch self {
        case .meditation: return "Meditation"
        case .focus: return "Focus"
        case .breathing: return "Breathing"
        case .visualization: return "Visualization"
        }
    }
    
    var icon: String {
        switch self {
        case .meditation: return "leaf.fill"
        case .focus: return "target"
        case .breathing: return "wind"
        case .visualization: return "eye.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .meditation: return .green
        case .focus: return .blue
        case .breathing: return .mint
        case .visualization: return .purple
        }
    }
    
    var defaultDuration: TimeInterval {
        switch self {
        case .meditation: return 20 * 60
        case .focus: return 25 * 60
        case .breathing: return 10 * 60
        case .visualization: return 15 * 60
        }
    }
    
    var defaultMilestones: [CraftMilestone] {
        switch self {
        case .meditation:
            return [
                CraftMilestone(timeThreshold: 5 * 60, message: "Finding your center", includesBreathingReminder: false),
                CraftMilestone(timeThreshold: 10 * 60, message: "Deepening awareness", includesBreathingReminder: true),
                CraftMilestone(timeThreshold: 15 * 60, message: "Sustained mindfulness", includesBreathingReminder: false),
                CraftMilestone(timeThreshold: 20 * 60, message: "Session complete", includesBreathingReminder: false)
            ]
        case .focus:
            return [
                CraftMilestone(timeThreshold: 5 * 60, message: "Getting in the zone", includesBreathingReminder: false),
                CraftMilestone(timeThreshold: 15 * 60, message: "Deep focus achieved", includesBreathingReminder: true),
                CraftMilestone(timeThreshold: 25 * 60, message: "Pomodoro complete", includesBreathingReminder: false)
            ]
        case .breathing:
            return [
                CraftMilestone(timeThreshold: 3 * 60, message: "Rhythm established", includesBreathingReminder: false),
                CraftMilestone(timeThreshold: 7 * 60, message: "Deep relaxation", includesBreathingReminder: false),
                CraftMilestone(timeThreshold: 10 * 60, message: "Breathing mastery", includesBreathingReminder: false)
            ]
        case .visualization:
            return [
                CraftMilestone(timeThreshold: 5 * 60, message: "Visualizing success", includesBreathingReminder: false),
                CraftMilestone(timeThreshold: 10 * 60, message: "Mental rehearsal", includesBreathingReminder: true),
                CraftMilestone(timeThreshold: 15 * 60, message: "Vision complete", includesBreathingReminder: false)
            ]
        }
    }
}

struct CraftMilestone: Identifiable, Equatable {
    let id = UUID()
    let timeThreshold: TimeInterval
    let message: String
    let includesBreathingReminder: Bool
    
    static func == (lhs: CraftMilestone, rhs: CraftMilestone) -> Bool {
        return lhs.id == rhs.id
    }
}

enum BreathingPhase {
    case inhale
    case hold
    case exhale
    case rest
}

enum HeartRateZone {
    case resting
    case warmup
    case aerobic
    case anaerobic
    case max
    
    var displayName: String {
        switch self {
        case .resting: return "Rest"
        case .warmup: return "Warm"
        case .aerobic: return "Aero"
        case .anaerobic: return "Anaero"
        case .max: return "Max"
        }
    }
    
    var color: Color {
        switch self {
        case .resting: return .gray
        case .warmup: return .blue
        case .aerobic: return .green
        case .anaerobic: return .orange
        case .max: return .red
        }
    }
    
    static func from(heartRate: Double, age: Int) -> HeartRateZone {
        let maxHR = Double(220 - age)
        let percentage = heartRate / maxHR
        
        switch percentage {
        case 0..<0.6: return .resting
        case 0.6..<0.7: return .warmup
        case 0.7..<0.8: return .aerobic
        case 0.8..<0.9: return .anaerobic
        default: return .max
        }
    }
}

struct CraftSessionResult {
    let type: CraftType
    let duration: TimeInterval
    let targetDuration: TimeInterval
    let milestonesReached: Int
    let averageHeartRate: Double
    let caloriesBurned: Double
    let completedAt: Date
}

struct WatchSessionState {
    let session: CraftSession
    let isActive: Bool
    let isPaused: Bool
    let elapsedTime: TimeInterval
    let heartRate: Double
    let caloriesBurned: Double
    let milestonesReached: [CraftMilestone]
}

// MARK: - Preview

struct CraftTimerWatchView_Previews: PreviewProvider {
    static var previews: some View {
        CraftTimerWatchView()
            .withWatchServiceContainer(
                WatchServiceContainer(environment: .test)
            )
    }
}