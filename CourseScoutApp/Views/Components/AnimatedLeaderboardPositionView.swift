import SwiftUI
import Combine

struct AnimatedLeaderboardPositionView: View {
    let entry: LeaderboardEntry
    let newPosition: Int
    let previousPosition: Int?
    
    @Environment(\.serviceContainer) private var serviceContainer
    @State private var animationPhase: AnimationPhase = .initial
    @State private var positionOffset: CGFloat = 0
    @State private var scaleEffect: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    @State private var celebrationVisible = false
    @State private var particles: [ParticleEffect] = []
    
    private var hapticService: HapticFeedbackServiceProtocol {
        serviceContainer.hapticFeedbackService
    }
    
    private var positionChange: PositionChangeType {
        guard let previous = previousPosition else { return .none }
        
        if newPosition < previous {
            let change = previous - newPosition
            return change >= 5 ? .majorImprovement : .improvement
        } else if newPosition > previous {
            return .decline
        } else {
            return .none
        }
    }
    
    private var changeColor: Color {
        switch positionChange {
        case .majorImprovement:
            return .green
        case .improvement:
            return .blue
        case .decline:
            return .red
        case .none:
            return .clear
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Animated position indicator
            positionIndicator
            
            // Player info with animations
            playerInfo
            
            Spacer()
            
            // Score with change animation
            scoreSection
            
            // Position change indicator
            positionChangeIndicator
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(changeColor.opacity(glowOpacity), lineWidth: 2)
                )
        )
        .scaleEffect(scaleEffect)
        .offset(y: positionOffset)
        .overlay {
            if celebrationVisible {
                celebrationOverlay
            }
        }
        .overlay {
            ForEach(particles, id: \.id) { particle in
                ParticleView(particle: particle)
            }
        }
        .onAppear {
            startPositionAnimation()
        }
        .onChange(of: newPosition) { oldValue, newValue in
            animatePositionChange(from: oldValue, to: newValue)
        }
    }
    
    // MARK: - Position Indicator
    
    private var positionIndicator: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(positionBackgroundGradient)
                .frame(width: 40, height: 40)
            
            // Position number
            Text("\(newPosition)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Crown for first place
            if newPosition == 1 {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
                    .offset(y: -15)
                    .rotationEffect(.degrees(animationPhase == .celebrating ? 10 : 0))
                    .animation(.easeInOut(duration: 0.5).repeatCount(3), value: animationPhase)
            }
        }
        .shadow(color: changeColor.opacity(0.3), radius: glowOpacity * 10, x: 0, y: 0)
        .animation(.easeInOut(duration: 0.3), value: glowOpacity)
    }
    
    private var positionBackgroundGradient: LinearGradient {
        switch newPosition {
        case 1:
            return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 2:
            return LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 3:
            return LinearGradient(colors: [.brown, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    // MARK: - Player Info
    
    private var playerInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.playerName)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if animationPhase == .celebrating && newPosition == 1 {
                Text("🏆 LEADER!")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
                    .scaleEffect(scaleEffect)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6).repeatCount(2), value: scaleEffect)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Round \(entry.currentRound ?? 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Score Section
    
    private var scoreSection: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(entry.totalScore)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            HStack(spacing: 2) {
                Text(entry.scoreToPar > 0 ? "+\(entry.scoreToPar)" : "\(entry.scoreToPar)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(entry.scoreToPar <= 0 ? .green : .red)
                
                Text("par")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Position Change Indicator
    
    private var positionChangeIndicator: some View {
        Group {
            if positionChange != .none {
                VStack(spacing: 2) {
                    Image(systemName: positionChange.icon)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(changeColor)
                        .scaleEffect(animationPhase == .highlighting ? 1.5 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: animationPhase)
                    
                    if let previous = previousPosition {
                        Text("\(abs(previous - newPosition))")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(changeColor)
                    }
                }
            }
        }
    }
    
    // MARK: - Celebration Overlay
    
    private var celebrationOverlay: some View {
        ZStack {
            // Glow effect
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [changeColor, changeColor.opacity(0.3), changeColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .opacity(celebrationVisible ? 1 : 0)
                .scaleEffect(celebrationVisible ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatCount(3), value: celebrationVisible)
            
            // Achievement text for major improvements
            if positionChange == .majorImprovement {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Great Move!")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(changeColor)
                            .cornerRadius(6)
                            .opacity(celebrationVisible ? 1 : 0)
                            .scaleEffect(celebrationVisible ? 1 : 0.5)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.2), value: celebrationVisible)
                    }
                }
            }
        }
    }
    
    // MARK: - Particle View
    
    private struct ParticleView: View {
        let particle: ParticleEffect
        @State private var offset: CGSize = .zero
        @State private var opacity: Double = 1.0
        @State private var scale: CGFloat = 1.0
        
        var body: some View {
            Image(systemName: particle.symbol)
                .font(.system(size: particle.size))
                .foregroundColor(particle.color)
                .offset(offset)
                .opacity(opacity)
                .scaleEffect(scale)
                .onAppear {
                    withAnimation(.easeOut(duration: particle.duration)) {
                        offset = particle.targetOffset
                        opacity = 0
                        scale = particle.targetScale
                    }
                }
        }
    }
    
    // MARK: - Animation Logic
    
    private func startPositionAnimation() {
        // Initial entry animation
        positionOffset = 20
        scaleEffect = 0.8
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            positionOffset = 0
            scaleEffect = 1.0
        }
    }
    
    private func animatePositionChange(from oldPosition: Int, to newPosition: Int) {
        guard oldPosition != newPosition else { return }
        
        // Trigger haptic feedback based on change type
        Task {
            switch positionChange {
            case .majorImprovement:
                await hapticService.providePositionChangeHaptic(change: .majorImprovement(oldPosition - newPosition))
                await hapticService.provideLeaderboardMilestoneHaptic(milestone: getMilestone(for: newPosition))
            case .improvement:
                await hapticService.providePositionChangeHaptic(change: .minorImprovement)
            case .decline:
                await hapticService.providePositionChangeHaptic(change: .minorDecline)
            case .none:
                break
            }
        }
        
        // Phase 1: Highlight change
        withAnimation(.easeInOut(duration: 0.2)) {
            animationPhase = .highlighting
            glowOpacity = 1.0
        }
        
        // Phase 2: Position change animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                if newPosition < oldPosition {
                    // Moving up
                    positionOffset = -30
                } else {
                    // Moving down
                    positionOffset = 30
                }
                scaleEffect = 1.1
            }
        }
        
        // Phase 3: Settle into new position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                positionOffset = 0
                scaleEffect = 1.0
                animationPhase = .settling
            }
        }
        
        // Phase 4: Celebration for significant improvements
        if positionChange == .majorImprovement || newPosition == 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                triggerCelebration()
            }
        }
        
        // Phase 5: Return to normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                glowOpacity = 0.0
                celebrationVisible = false
                animationPhase = .initial
            }
        }
    }
    
    private func triggerCelebration() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            animationPhase = .celebrating
            celebrationVisible = true
        }
        
        // Generate celebration particles
        generateCelebrationParticles()
        
        // Additional haptic for celebration
        Task {
            if newPosition == 1 {
                await hapticService.provideChallengeVictoryHaptic(competitionLevel: .competitive)
            } else {
                await hapticService.provideAchievementUnlockHaptic(tier: .silver)
            }
        }
    }
    
    private func generateCelebrationParticles() {
        let symbols = ["star.fill", "sparkles", "crown.fill", "trophy.fill"]
        let colors: [Color] = [.yellow, .orange, .blue, .green]
        
        for i in 0..<8 {
            let particle = ParticleEffect(
                id: UUID().uuidString,
                symbol: symbols.randomElement() ?? "star.fill",
                color: colors.randomElement() ?? .yellow,
                size: CGFloat.random(in: 12...20),
                startPosition: CGPoint.zero,
                targetOffset: CGSize(
                    width: CGFloat.random(in: -50...50),
                    height: CGFloat.random(in: -80...(-20))
                ),
                targetScale: CGFloat.random(in: 0.3...0.7),
                duration: Double.random(in: 1.0...2.0)
            )
            particles.append(particle)
        }
        
        // Remove particles after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            particles.removeAll()
        }
    }
    
    private func getMilestone(for position: Int) -> LeaderboardMilestone {
        switch position {
        case 1:
            return .first
        case 2:
            return .runner_up
        case 3:
            return .topThree
        case 4...5:
            return .topFive
        case 6...10:
            return .topTen
        default:
            return .topTen
        }
    }
}

// MARK: - Supporting Types

enum AnimationPhase {
    case initial
    case highlighting
    case settling
    case celebrating
}

enum PositionChangeType {
    case majorImprovement
    case improvement
    case decline
    case none
    
    var icon: String {
        switch self {
        case .majorImprovement:
            return "arrow.up.circle.fill"
        case .improvement:
            return "arrow.up"
        case .decline:
            return "arrow.down"
        case .none:
            return ""
        }
    }
}

struct ParticleEffect {
    let id: String
    let symbol: String
    let color: Color
    let size: CGFloat
    let startPosition: CGPoint
    let targetOffset: CGSize
    let targetScale: CGFloat
    let duration: TimeInterval
}

// MARK: - Preview

#Preview {
    let sampleEntry = LeaderboardEntry(
        id: "entry-1",
        leaderboardId: "board-1",
        playerId: "player-1",
        playerName: "John Smith",
        totalScore: 74,
        scoreToPar: 2,
        position: 1,
        positionChange: .up,
        lastUpdated: Date(),
        roundScores: [74],
        currentRound: 1,
        holesPlayed: 18,
        isActive: true
    )
    
    VStack(spacing: 16) {
        AnimatedLeaderboardPositionView(
            entry: sampleEntry,
            newPosition: 1,
            previousPosition: 3
        )
        
        AnimatedLeaderboardPositionView(
            entry: sampleEntry,
            newPosition: 2,
            previousPosition: 2
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}