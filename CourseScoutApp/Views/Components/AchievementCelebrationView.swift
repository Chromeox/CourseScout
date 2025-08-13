import SwiftUI
import Combine

struct AchievementCelebrationView: View {
    let achievement: Achievement
    let onDismiss: () -> Void
    
    @Environment(\.serviceContainer) private var serviceContainer
    @State private var animationPhase: CelebrationPhase = .entering
    @State private var backgroundScale: CGFloat = 0
    @State private var badgeScale: CGFloat = 0
    @State private var badgeRotation: Double = 0
    @State private var textOffset: CGFloat = 50
    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var sparkleParticles: [SparkleParticle] = []
    @State private var pulseOpacity: Double = 0.5
    @State private var titleTypewriterIndex = 0
    @State private var descriptionTypewriterIndex = 0
    @State private var hapticSequenceStep = 0
    @State private var showContinueButton = false
    
    private var hapticService: HapticFeedbackServiceProtocol {
        serviceContainer.hapticFeedbackService
    }
    
    private var tierGradient: LinearGradient {
        switch achievement.tier {
        case .bronze:
            return LinearGradient(colors: [.brown, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .silver:
            return LinearGradient(colors: [.gray, .white], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gold:
            return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .platinum:
            return LinearGradient(colors: [.white, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .diamond:
            return LinearGradient(colors: [.blue, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private var tierTitle: String {
        switch achievement.tier {
        case .bronze: return "Bronze Achievement!"
        case .silver: return "Silver Achievement!"
        case .gold: return "Gold Achievement!"
        case .platinum: return "Platinum Achievement!"
        case .diamond: return "Diamond Achievement!"
        }
    }
    
    var body: some View {
        ZStack {
            // Background overlay
            backgroundView
            
            // Main celebration content
            celebrationContent
            
            // Confetti layer
            confettiLayer
            
            // Sparkle layer
            sparkleLayer
            
            // Continue button
            if showContinueButton {
                continueButton
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startCelebrationSequence()
        }
    }
    
    // MARK: - Background View
    
    private var backgroundView: some View {
        ZStack {
            // Dark overlay
            Color.black.opacity(0.8)
            
            // Animated gradient background
            RadialGradient(
                colors: [
                    tierGradient.stops[0].color.opacity(0.3),
                    tierGradient.stops[1].color.opacity(0.1),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 300
            )
            .scaleEffect(backgroundScale)
            .opacity(pulseOpacity)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulseOpacity)
        }
    }
    
    // MARK: - Celebration Content
    
    private var celebrationContent: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Achievement badge
            achievementBadge
            
            // Title with typewriter effect
            VStack(spacing: 16) {
                Text(String(tierTitle.prefix(titleTypewriterIndex)))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(achievement.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(tierGradient.stops[0].color)
                    .multilineTextAlignment(.center)
                    .offset(y: textOffset)
            }
            
            // Description with typewriter effect
            if !achievement.description.isEmpty {
                Text(String(achievement.description.prefix(descriptionTypewriterIndex)))
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .offset(y: textOffset * 0.5)
            }
            
            // Achievement stats
            if animationPhase == .celebrating {
                achievementStats
            }
            
            Spacer()
        }
    }
    
    // MARK: - Achievement Badge
    
    private var achievementBadge: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [tierGradient.stops[0].color, tierGradient.stops[1].color, tierGradient.stops[0].color],
                        center: .center
                    ),
                    lineWidth: 8
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(badgeRotation))
                .opacity(0.7)
            
            // Main badge background
            Circle()
                .fill(tierGradient)
                .frame(width: 140, height: 140)
                .shadow(color: tierGradient.stops[0].color.opacity(0.5), radius: 20, x: 0, y: 10)
            
            // Inner content
            VStack(spacing: 8) {
                // Achievement icon
                Image(systemName: achievement.iconName)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                
                // Tier indicator
                Text(achievement.tier.rawValue.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.9))
            }
            
            // Sparkle overlay
            ForEach(0..<8, id: \.self) { index in
                sparklePoint(at: index)
            }
        }
        .scaleEffect(badgeScale)
        .rotation3DEffect(
            .degrees(animationPhase == .celebrating ? 15 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.8
        )
    }
    
    private func sparklePoint(at index: Int) -> some View {
        let angle = Double(index) * 45
        let radius: CGFloat = 90
        let x = cos(angle * .pi / 180) * radius
        let y = sin(angle * .pi / 180) * radius
        
        return Image(systemName: "sparkles")
            .font(.system(size: 12))
            .foregroundColor(.white)
            .offset(x: x, y: y)
            .opacity(pulseOpacity)
            .scaleEffect(pulseOpacity * 0.5 + 0.5)
    }
    
    // MARK: - Achievement Stats
    
    private var achievementStats: some View {
        VStack(spacing: 12) {
            if let earnedAt = achievement.earnedAt {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Earned \(earnedAt.formatted(.dateTime.day().month(.wide)))")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            
            if let progress = achievement.progress, progress < 100 {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Progress: \(Int(progress))%")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Confetti Layer
    
    private var confettiLayer: some View {
        ZStack {
            ForEach(confettiParticles, id: \.id) { particle in
                ConfettiParticleView(particle: particle)
            }
        }
    }
    
    // MARK: - Sparkle Layer
    
    private var sparkleLayer: some View {
        ZStack {
            ForEach(sparkleParticles, id: \.id) { particle in
                SparkleParticleView(particle: particle)
            }
        }
    }
    
    // MARK: - Continue Button
    
    private var continueButton: some View {
        VStack {
            Spacer()
            
            Button {
                dismissCelebration()
            } label: {
                HStack {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 15)
                .background(tierGradient.opacity(0.8))
                .cornerRadius(25)
                .shadow(color: tierGradient.stops[0].color.opacity(0.5), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(showContinueButton ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showContinueButton)
            
            Spacer()
                .frame(height: 50)
        }
    }
    
    // MARK: - Animation Sequence
    
    private func startCelebrationSequence() {
        // Phase 1: Initial haptic and entry
        Task {
            await hapticService.provideAchievementUnlockHaptic(tier: achievement.tier)
        }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            backgroundScale = 1
            animationPhase = .entering
        }
        
        // Phase 2: Badge entrance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                badgeScale = 1
            }
            
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                badgeRotation = 360
            }
            
            // Start confetti
            generateConfetti()
            
            // Additional haptic for badge appearance
            Task {
                await self.hapticService.provideMilestoneHaptic(milestone: .firstBirdie)
            }
        }
        
        // Phase 3: Text entrance with typewriter
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                textOffset = 0
            }
            
            startTypewriter()
        }
        
        // Phase 4: Celebration phase
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                animationPhase = .celebrating
            }
            
            generateSparkles()
            
            // Final celebration haptic sequence
            startHapticSequence()
        }
        
        // Phase 5: Show continue button
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showContinueButton = true
            }
        }
    }
    
    private func startTypewriter() {
        // Typewriter effect for title
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if titleTypewriterIndex < tierTitle.count {
                titleTypewriterIndex += 1
            } else {
                timer.invalidate()
                
                // Start description typewriter
                Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { descTimer in
                    if descriptionTypewriterIndex < achievement.description.count {
                        descriptionTypewriterIndex += 1
                    } else {
                        descTimer.invalidate()
                    }
                }
            }
        }
    }
    
    private func startHapticSequence() {
        let sequence: [AchievementTier] = [achievement.tier, achievement.tier, achievement.tier]
        
        func playNextHaptic() {
            guard hapticSequenceStep < sequence.count else { return }
            
            Task {
                await hapticService.provideAchievementUnlockHaptic(tier: sequence[hapticSequenceStep])
            }
            
            hapticSequenceStep += 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playNextHaptic()
            }
        }
        
        playNextHaptic()
    }
    
    private func generateConfetti() {
        let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]
        let shapes = ["circle", "triangle", "square"]
        
        for i in 0..<50 {
            let particle = ConfettiParticle(
                id: UUID().uuidString,
                color: colors.randomElement() ?? .blue,
                shape: shapes.randomElement() ?? "circle",
                startX: CGFloat.random(in: -100...100),
                startY: -100,
                endX: CGFloat.random(in: -200...200),
                endY: UIScreen.main.bounds.height + 100,
                rotation: Double.random(in: 0...360),
                size: CGFloat.random(in: 8...15),
                duration: Double.random(in: 2...4),
                delay: Double(i) * 0.02
            )
            confettiParticles.append(particle)
        }
        
        // Remove confetti after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            confettiParticles.removeAll()
        }
    }
    
    private func generateSparkles() {
        for i in 0..<30 {
            let particle = SparkleParticle(
                id: UUID().uuidString,
                startPosition: CGPoint(
                    x: CGFloat.random(in: -150...150),
                    y: CGFloat.random(in: -150...150)
                ),
                scale: CGFloat.random(in: 0.5...1.5),
                opacity: Double.random(in: 0.3...1.0),
                duration: Double.random(in: 1...3),
                delay: Double(i) * 0.1
            )
            sparkleParticles.append(particle)
        }
        
        // Remove sparkles after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            sparkleParticles.removeAll()
        }
    }
    
    private func dismissCelebration() {
        Task {
            await hapticService.provideChallengeInvitationHaptic()
        }
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            backgroundScale = 0
            badgeScale = 0
            textOffset = -50
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onDismiss()
        }
    }
}

// MARK: - Supporting Views and Types

enum CelebrationPhase {
    case entering
    case celebrating
    case dismissing
}

struct ConfettiParticle {
    let id: String
    let color: Color
    let shape: String
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let rotation: Double
    let size: CGFloat
    let duration: TimeInterval
    let delay: TimeInterval
}

struct SparkleParticle {
    let id: String
    let startPosition: CGPoint
    let scale: CGFloat
    let opacity: Double
    let duration: TimeInterval
    let delay: TimeInterval
}

struct ConfettiParticleView: View {
    let particle: ConfettiParticle
    @State private var position = CGPoint.zero
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        Group {
            switch particle.shape {
            case "circle":
                Circle()
            case "triangle":
                Triangle()
            case "square":
                Rectangle()
            default:
                Circle()
            }
        }
        .fill(particle.color)
        .frame(width: particle.size, height: particle.size)
        .position(position)
        .rotationEffect(.degrees(rotation))
        .opacity(opacity)
        .onAppear {
            position = CGPoint(x: particle.startX, y: particle.startY)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + particle.delay) {
                withAnimation(.easeOut(duration: particle.duration)) {
                    position = CGPoint(x: particle.endX, y: particle.endY)
                    rotation = particle.rotation
                    opacity = 0
                }
            }
        }
    }
}

struct SparkleParticleView: View {
    let particle: SparkleParticle
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var rotation: Double = 0
    
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 20))
            .foregroundColor(.white)
            .scaleEffect(scale)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .position(
                x: UIScreen.main.bounds.midX + particle.startPosition.x,
                y: UIScreen.main.bounds.midY + particle.startPosition.y
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + particle.delay) {
                    withAnimation(.easeInOut(duration: particle.duration).repeatCount(2, autoreverses: true)) {
                        scale = particle.scale
                        opacity = particle.opacity
                        rotation = 360
                    }
                }
            }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        
        return path
    }
}

// MARK: - Achievement Model Extension

struct Achievement {
    let id: String
    let name: String
    let description: String
    let iconName: String
    let tier: AchievementTier
    let category: String
    let earnedAt: Date?
    let progress: Double?
    let requirements: [String]
    let rewards: [String]
}

// MARK: - Preview

#Preview {
    let sampleAchievement = Achievement(
        id: "achievement-1",
        name: "Eagle Eye",
        description: "Score your first eagle - two strokes under par on a single hole!",
        iconName: "target",
        tier: .gold,
        category: "Scoring",
        earnedAt: Date(),
        progress: 100,
        requirements: ["Score an eagle on any hole"],
        rewards: ["50 XP", "Gold Badge"]
    )
    
    AchievementCelebrationView(achievement: sampleAchievement) {
        print("Achievement celebration dismissed")
    }
}