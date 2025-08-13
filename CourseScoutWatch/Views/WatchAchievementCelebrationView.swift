import SwiftUI
import WatchKit
import Combine

// MARK: - Watch Achievement Celebration View

struct WatchAchievementCelebrationView: View {
    let achievement: Achievement
    let celebrationType: CelebrationType
    @StateObject private var hapticService: WatchHapticFeedbackService
    @StateObject private var connectivityService: WatchConnectivityService
    
    @State private var showCelebration = false
    @State private var celebrationPhase: CelebrationPhase = .entrance
    @State private var confettiOffset: CGFloat = -200
    @State private var badgeScale: CGFloat = 0.1
    @State private var badgeRotation: Double = 0
    @State private var showDetails = false
    @State private var pulseAnimation = false
    @State private var shimmerOffset: CGFloat = -200
    @State private var socialShareCompleted = false
    
    // Animation configuration
    private let celebrationDuration: TimeInterval = 5.0
    private let badgeAnimationDuration: TimeInterval = 1.2
    private let confettiAnimationDuration: TimeInterval = 2.0
    private let socialShareDelay: TimeInterval = 3.0
    
    init(
        achievement: Achievement,
        celebrationType: CelebrationType = .achievement("gold"),
        hapticService: WatchHapticFeedbackService,
        connectivityService: WatchConnectivityService
    ) {
        self.achievement = achievement
        self.celebrationType = celebrationType
        self._hapticService = StateObject(wrappedValue: hapticService)
        self._connectivityService = StateObject(wrappedValue: connectivityService)
    }
    
    var body: some View {
        ZStack {
            // Dynamic celebration background
            celebrationBackground
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.0), value: celebrationPhase)
            
            // Confetti layer
            if celebrationPhase != .entrance {
                confettiLayer
                    .animation(.easeOut(duration: confettiAnimationDuration), value: confettiOffset)
            }
            
            // Main achievement celebration content
            VStack(spacing: 0) {
                if celebrationPhase == .entrance || celebrationPhase == .celebration {
                    achievementBadgeView
                        .scaleEffect(badgeScale)
                        .rotationEffect(.degrees(badgeRotation))
                        .animation(.spring(response: badgeAnimationDuration, dampingFraction: 0.6), value: badgeScale)
                        .animation(.easeInOut(duration: 0.8), value: badgeRotation)
                }
                
                if celebrationPhase != .entrance {
                    Spacer().frame(height: 16)
                    
                    achievementDetailsView
                        .opacity(showDetails ? 1 : 0)
                        .animation(.easeIn(duration: 0.8).delay(0.5), value: showDetails)
                }
                
                if celebrationPhase == .sharing {
                    Spacer().frame(height: 20)
                    
                    socialSharingView
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: celebrationPhase)
                }
            }
            .padding()
            
            // Shimmer effect overlay
            if celebrationPhase == .celebration {
                shimmerOverlay
                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: shimmerOffset)
            }
            
            // Tier-specific celebration elements
            tierSpecificElements
        }
        .onAppear {
            startCelebrationSequence()
        }
        .gesture(
            TapGesture()
                .onEnded { _ in
                    advanceCelebrationPhase()
                }
        )
    }
    
    // MARK: - View Components
    
    private var celebrationBackground: some View {
        let colors = tierColors(for: achievement.tier)
        
        return ZStack {
            // Base gradient
            RadialGradient(
                gradient: Gradient(colors: [
                    colors.primary.opacity(0.8),
                    colors.secondary.opacity(0.6),
                    Color.black.opacity(0.9)
                ]),
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            
            // Animated overlay for celebration phase
            if celebrationPhase == .celebration {
                RadialGradient(
                    gradient: Gradient(colors: [
                        colors.accent.opacity(0.4),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 50,
                    endRadius: 150
                )
                .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: pulseAnimation)
            }
        }
    }
    
    private var confettiLayer: some View {
        ZStack {
            ForEach(0..<20, id: \.self) { index in
                confettiParticle(index: index)
            }
        }
    }
    
    private func confettiParticle(index: Int) -> some View {
        let colors = tierColors(for: achievement.tier)
        let particleColor = [colors.primary, colors.secondary, colors.accent].randomElement() ?? colors.primary
        
        return RoundedRectangle(cornerRadius: 2)
            .fill(particleColor)
            .frame(width: 8, height: 4)
            .offset(
                x: CGFloat.random(in: -100...100),
                y: confettiOffset + CGFloat(index * 10)
            )
            .rotationEffect(.degrees(Double.random(in: 0...360)))
            .scaleEffect(CGFloat.random(in: 0.5...1.0))
    }
    
    private var achievementBadgeView: some View {
        ZStack {
            // Badge background with tier styling
            badgeBackground
            
            // Badge icon
            Image(systemName: achievementIcon)
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)
            
            // Tier indicator
            VStack {
                Spacer()
                tierBadge
                    .offset(y: 10)
            }
        }
        .frame(width: 100, height: 100)
    }
    
    private var badgeBackground: some View {
        let colors = tierColors(for: achievement.tier)
        
        return ZStack {
            // Outer glow ring
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            colors.primary.opacity(0.8),
                            colors.primary.opacity(0.3),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 45,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
            
            // Main badge circle
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            colors.primary,
                            colors.secondary
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(colors.accent, lineWidth: 3)
                )
            
            // Inner highlight
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.3),
                            Color.clear
                        ]),
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 10,
                        endRadius: 40
                    )
                )
        }
    }
    
    private var tierBadge: some View {
        Text(achievement.tier.uppercased())
            .font(.caption2)
            .fontWeight(.heavy)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tierColors(for: achievement.tier).accent)
                    .overlay(
                        Capsule()
                            .stroke(Color.white, lineWidth: 1)
                    )
            )
    }
    
    private var achievementDetailsView: some View {
        VStack(spacing: 8) {
            // Achievement title
            Text(achievement.title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            // Achievement description
            Text(achievement.description)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            
            // Unlock timestamp
            Text("Unlocked \(formatUnlockTime(achievement.unlockedAt))")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
            
            // Achievement rarity indicator
            if let rarity = achievementRarity(for: achievement.tier) {
                rarityIndicator(rarity)
            }
        }
    }
    
    private func rarityIndicator(_ rarity: AchievementRarity) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<rarity.stars, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
            
            Text(rarity.label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.3))
        )
    }
    
    private var socialSharingView: some View {
        VStack(spacing: 12) {
            Text("Share Your Achievement!")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                // Share to friends
                shareButton(
                    icon: "person.2.fill",
                    title: "Friends",
                    action: shareWithFriends
                )
                
                // Share to social media
                shareButton(
                    icon: "globe",
                    title: "Social",
                    action: shareToSocial
                )
                
                // Save to photos
                shareButton(
                    icon: "camera.fill",
                    title: "Save",
                    action: saveScreenshot
                )
            }
            
            if socialShareCompleted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Shared!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: socialShareCompleted)
            }
        }
    }
    
    private func shareButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(tierColors(for: achievement.tier).primary)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private var shimmerOverlay: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.clear,
                Color.white.opacity(0.3),
                Color.clear
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 100, height: 300)
        .offset(x: shimmerOffset)
        .mask(
            Rectangle()
                .frame(width: WKInterfaceDevice.current().screenBounds.width)
        )
    }
    
    private var tierSpecificElements: some View {
        Group {
            switch achievement.tier.lowercased() {
            case "diamond":
                diamondSparkles
            case "platinum":
                platinumRings
            case "gold":
                goldParticles
            default:
                EmptyView()
            }
        }
    }
    
    private var diamondSparkles: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Image(systemName: "sparkle")
                    .font(.caption)
                    .foregroundColor(.cyan)
                    .offset(
                        x: cos(Double(index) * .pi / 4) * 80,
                        y: sin(Double(index) * .pi / 4) * 80
                    )
                    .scaleEffect(pulseAnimation ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: pulseAnimation
                    )
            }
        }
    }
    
    private var platinumRings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.gray.opacity(0.6), lineWidth: 2)
                    .frame(width: CGFloat(60 + index * 30))
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.0)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: pulseAnimation
                    )
            }
        }
    }
    
    private var goldParticles: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(Color.yellow.opacity(0.8))
                    .frame(width: 4, height: 4)
                    .offset(
                        x: cos(Double(index) * .pi / 6) * 90,
                        y: sin(Double(index) * .pi / 6) * 90
                    )
                    .scaleEffect(pulseAnimation ? 1.5 : 0.5)
                    .animation(
                        .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.08),
                        value: pulseAnimation
                    )
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var achievementIcon: String {
        switch achievement.tier.lowercased() {
        case "diamond":
            return "diamond.fill"
        case "platinum":
            return "crown.fill"
        case "gold":
            return "star.fill"
        case "silver":
            return "medal.fill"
        case "bronze":
            return "rosette"
        default:
            return "trophy.fill"
        }
    }
    
    // MARK: - Helper Methods
    
    private func tierColors(for tier: String) -> TierColors {
        switch tier.lowercased() {
        case "diamond":
            return TierColors(
                primary: .cyan,
                secondary: .blue,
                accent: .white
            )
        case "platinum":
            return TierColors(
                primary: .gray,
                secondary: .white,
                accent: .silver
            )
        case "gold":
            return TierColors(
                primary: .yellow,
                secondary: .orange,
                accent: .white
            )
        case "silver":
            return TierColors(
                primary: .gray,
                secondary: .secondary,
                accent: .white
            )
        case "bronze":
            return TierColors(
                primary: .orange,
                secondary: .brown,
                accent: .white
            )
        default:
            return TierColors(
                primary: .blue,
                secondary: .purple,
                accent: .white
            )
        }
    }
    
    private func achievementRarity(for tier: String) -> AchievementRarity? {
        switch tier.lowercased() {
        case "diamond":
            return AchievementRarity(stars: 5, label: "Legendary")
        case "platinum":
            return AchievementRarity(stars: 4, label: "Epic")
        case "gold":
            return AchievementRarity(stars: 3, label: "Rare")
        case "silver":
            return AchievementRarity(stars: 2, label: "Uncommon")
        case "bronze":
            return AchievementRarity(stars: 1, label: "Common")
        default:
            return nil
        }
    }
    
    private func formatUnlockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
    
    // MARK: - Animation Control
    
    private func startCelebrationSequence() {
        // Phase 1: Entrance animation
        celebrationPhase = .entrance
        
        // Trigger coordinated iPhone haptic
        Task {
            await hapticService.playSynchronizedCelebrationHaptic(type: celebrationType)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            badgeScale = 1.0
            badgeRotation = 360
        }
        
        // Phase 2: Main celebration
        DispatchQueue.main.asyncAfter(deadline: .now() + badgeAnimationDuration) {
            celebrationPhase = .celebration
            showDetails = true
            pulseAnimation = true
            startConfetti()
            startShimmer()
        }
        
        // Phase 3: Social sharing
        DispatchQueue.main.asyncAfter(deadline: .now() + socialShareDelay) {
            celebrationPhase = .sharing
        }
        
        // Auto-dismiss after full celebration
        DispatchQueue.main.asyncAfter(deadline: .now() + celebrationDuration) {
            dismissCelebration()
        }
    }
    
    private func startConfetti() {
        confettiOffset = -200
        
        withAnimation(.easeOut(duration: confettiAnimationDuration)) {
            confettiOffset = 400
        }
    }
    
    private func startShimmer() {
        shimmerOffset = -200
        
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 200
        }
    }
    
    private func advanceCelebrationPhase() {
        hapticService.playTaptic(.light)
        
        switch celebrationPhase {
        case .entrance:
            celebrationPhase = .celebration
            showDetails = true
            pulseAnimation = true
            startConfetti()
            startShimmer()
        case .celebration:
            celebrationPhase = .sharing
        case .sharing:
            dismissCelebration()
        }
    }
    
    private func dismissCelebration() {
        // Notify that celebration is complete
        // This would typically close the celebration view
    }
    
    // MARK: - Social Sharing Actions
    
    private func shareWithFriends() {
        hapticService.playTaptic(.success)
        
        Task {
            await connectivityService.shareAchievement(
                achievementId: achievement.achievementId,
                shareType: .friends
            )
            
            await MainActor.run {
                socialShareCompleted = true
            }
        }
    }
    
    private func shareToSocial() {
        hapticService.playTaptic(.success)
        
        Task {
            await connectivityService.shareAchievement(
                achievementId: achievement.achievementId,
                shareType: .social
            )
            
            await MainActor.run {
                socialShareCompleted = true
            }
        }
    }
    
    private func saveScreenshot() {
        hapticService.playTaptic(.success)
        
        Task {
            await connectivityService.saveAchievementScreenshot(achievementId: achievement.achievementId)
            
            await MainActor.run {
                socialShareCompleted = true
            }
        }
    }
}

// MARK: - Supporting Types

enum CelebrationPhase {
    case entrance
    case celebration
    case sharing
}

struct TierColors {
    let primary: Color
    let secondary: Color
    let accent: Color
}

extension Color {
    static let silver = Color(red: 0.75, green: 0.75, blue: 0.75)
    static let brown = Color(red: 0.65, green: 0.16, blue: 0.16)
}

struct AchievementRarity {
    let stars: Int
    let label: String
}

// MARK: - Watch Connectivity Extensions

extension WatchConnectivityService {
    func shareAchievement(achievementId: String, shareType: AchievementShareType) async {
        // Implementation for sharing achievement data to iPhone
    }
    
    func saveAchievementScreenshot(achievementId: String) async {
        // Implementation for saving achievement screenshot
    }
}

enum AchievementShareType {
    case friends
    case social
    case screenshot
}

// MARK: - Achievement Celebration Coordinator

@MainActor
class AchievementCelebrationCoordinator: ObservableObject {
    @Published var showCelebration = false
    @Published var currentAchievement: Achievement?
    @Published var celebrationType: CelebrationType = .achievement("gold")
    
    private var celebrationQueue: [Achievement] = []
    private var isDisplayingCelebration = false
    
    func queueCelebration(achievement: Achievement, type: CelebrationType) {
        celebrationQueue.append(achievement)
        
        if !isDisplayingCelebration {
            displayNextCelebration()
        }
    }
    
    private func displayNextCelebration() {
        guard !celebrationQueue.isEmpty else {
            isDisplayingCelebration = false
            return
        }
        
        isDisplayingCelebration = true
        currentAchievement = celebrationQueue.removeFirst()
        showCelebration = true
        
        // Auto-dismiss after celebration duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            self.dismissCelebration()
        }
    }
    
    func dismissCelebration() {
        showCelebration = false
        currentAchievement = nil
        
        // Display next celebration if any
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.displayNextCelebration()
        }
    }
}

// MARK: - Preview Support

struct WatchAchievementCelebrationView_Previews: PreviewProvider {
    static var previews: some View {
        WatchAchievementCelebrationView(
            achievement: Achievement(
                achievementId: "test_achievement",
                tier: "gold",
                title: "Birdie Master",
                description: "Score 10 birdies in a single round",
                unlockedAt: Date()
            ),
            celebrationType: .achievement("gold"),
            hapticService: MockWatchHapticFeedbackService(),
            connectivityService: MockWatchConnectivityService() as! WatchConnectivityService
        )
        .previewDevice("Apple Watch Series 9 - 45mm")
    }
}