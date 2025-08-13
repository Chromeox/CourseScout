import SwiftUI
import WatchKit
import Combine

// MARK: - Watch Achievement Notification View

struct WatchAchievementNotificationView: View {
    @StateObject private var gamificationService: WatchGamificationService
    @StateObject private var hapticService: WatchHapticFeedbackService
    @State private var recentAchievements: [Achievement] = []
    @State private var showingAchievement: Achievement?
    @State private var cancellables = Set<AnyCancellable>()
    
    // Animation states
    @State private var celebrationScale: CGFloat = 1.0
    @State private var celebrationOpacity: Double = 0.0
    @State private var celebrationRotation: Double = 0.0
    @State private var sparkleAnimations: [SparkleAnimation] = []
    
    init(gamificationService: WatchGamificationService, hapticService: WatchHapticFeedbackService) {
        self._gamificationService = StateObject(wrappedValue: gamificationService)
        self._hapticService = StateObject(wrappedValue: hapticService)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                if recentAchievements.isEmpty {
                    emptyAchievementsView
                } else {
                    achievementsListView
                }
                
                // Achievement celebration overlay
                if let achievement = showingAchievement {
                    achievementCelebrationOverlay(achievement)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                
                // Sparkle effects
                ForEach(sparkleAnimations, id: \.id) { sparkle in
                    sparkleView(sparkle)
                }
            }
            .navigationTitle("Achievements")
            .onAppear {
                setupAchievementTracking()
            }
            .onDisappear {
                cancellables.removeAll()
            }
        }
    }
    
    // MARK: - View Components
    
    private var emptyAchievementsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle")
                .font(.largeTitle)
                .foregroundColor(.yellow)
            
            Text("No Achievements Yet")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text("Keep playing to unlock achievements")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var achievementsListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(recentAchievements, id: \.achievementId) { achievement in
                    achievementCardView(achievement)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func achievementCardView(_ achievement: Achievement) -> some View {
        HStack(spacing: 12) {
            // Achievement tier icon
            achievementTierIcon(achievement.tier)
            
            // Achievement details
            VStack(alignment: .leading, spacing: 4) {
                Text(achievement.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text(achievement.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Text(timeAgoString(from: achievement.unlockedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(achievementBackgroundColor(achievement.tier))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(achievementBorderColor(achievement.tier), lineWidth: 1)
                )
        )
        .onTapGesture {
            triggerAchievementCelebration(achievement)
        }
    }
    
    private func achievementTierIcon(_ tier: String) -> some View {
        ZStack {
            Circle()
                .fill(achievementTierColor(tier))
                .frame(width: 40, height: 40)
            
            Image(systemName: achievementTierIconName(tier))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
    
    private func achievementCelebrationOverlay(_ achievement: Achievement) -> some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissCelebration()
                }
            
            VStack(spacing: 16) {
                // Celebration icon
                ZStack {
                    // Glowing background
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    achievementTierColor(achievement.tier).opacity(0.6),
                                    achievementTierColor(achievement.tier).opacity(0.3),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 5,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(celebrationScale)
                        .opacity(celebrationOpacity)
                    
                    // Main achievement icon
                    achievementTierIcon(achievement.tier)
                        .scaleEffect(2.0)
                        .rotationEffect(.degrees(celebrationRotation))
                        .scaleEffect(celebrationScale)
                }
                
                // Achievement title
                Text(achievement.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .opacity(celebrationOpacity)
                
                // Achievement tier
                Text("\(achievement.tier.capitalized) Achievement")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(achievementTierColor(achievement.tier))
                    .opacity(celebrationOpacity)
                
                // Achievement description
                Text(achievement.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(celebrationOpacity)
                
                // Dismiss button
                Button("Continue") {
                    dismissCelebration()
                }
                .buttonStyle(.borderedProminent)
                .tint(achievementTierColor(achievement.tier))
                .opacity(celebrationOpacity)
            }
            .padding()
            .scaleEffect(celebrationScale)
        }
    }
    
    private func sparkleView(_ sparkle: SparkleAnimation) -> some View {
        Image(systemName: "sparkle")
            .font(.caption)
            .foregroundColor(sparkle.color)
            .position(sparkle.position)
            .opacity(sparkle.opacity)
            .scaleEffect(sparkle.scale)
            .rotationEffect(.degrees(sparkle.rotation))
    }
    
    // MARK: - Helper Methods
    
    private func achievementTierColor(_ tier: String) -> Color {
        switch tier.lowercased() {
        case "bronze":
            return Color(red: 0.8, green: 0.5, blue: 0.2) // Bronze
        case "silver":
            return Color(red: 0.75, green: 0.75, blue: 0.75) // Silver
        case "gold":
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold
        case "platinum":
            return Color(red: 0.9, green: 0.9, blue: 0.95) // Platinum
        case "diamond":
            return Color(red: 0.7, green: 0.9, blue: 1.0) // Diamond blue
        default:
            return .gray
        }
    }
    
    private func achievementTierIconName(_ tier: String) -> String {
        switch tier.lowercased() {
        case "bronze":
            return "medal"
        case "silver":
            return "medal.fill"
        case "gold":
            return "crown"
        case "platinum":
            return "crown.fill"
        case "diamond":
            return "diamond"
        default:
            return "star"
        }
    }
    
    private func achievementBackgroundColor(_ tier: String) -> Color {
        achievementTierColor(tier).opacity(0.15)
    }
    
    private func achievementBorderColor(_ tier: String) -> Color {
        achievementTierColor(tier).opacity(0.5)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    // MARK: - Animation Methods
    
    private func triggerAchievementCelebration(_ achievement: Achievement) {
        showingAchievement = achievement
        
        // Reset animation states
        celebrationScale = 0.3
        celebrationOpacity = 0.0
        celebrationRotation = -180.0
        
        // Start celebration animation
        withAnimation(.easeOut(duration: 0.8)) {
            celebrationScale = 1.0
            celebrationOpacity = 1.0
            celebrationRotation = 0.0
        }
        
        // Create sparkle effects
        createSparkleEffects()
        
        // Trigger haptic celebration
        triggerCelebrationHaptics(for: achievement.tier)
        
        // Auto-dismiss after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if showingAchievement?.achievementId == achievement.achievementId {
                dismissCelebration()
            }
        }
    }
    
    private func dismissCelebration() {
        withAnimation(.easeIn(duration: 0.4)) {
            celebrationOpacity = 0.0
            celebrationScale = 0.8
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showingAchievement = nil
            sparkleAnimations.removeAll()
        }
    }
    
    private func createSparkleEffects() {
        let screenBounds = WKInterfaceDevice.current().screenBounds
        sparkleAnimations.removeAll()
        
        // Create multiple sparkles
        for i in 0..<12 {
            let sparkle = SparkleAnimation(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: 20...(screenBounds.width - 20)),
                    y: CGFloat.random(in: 50...(screenBounds.height - 50))
                ),
                color: [Color.yellow, Color.orange, Color.white, Color.cyan].randomElement() ?? .yellow,
                opacity: 1.0,
                scale: CGFloat.random(in: 0.5...1.5),
                rotation: Double.random(in: 0...360)
            )
            
            sparkleAnimations.append(sparkle)
            
            // Animate sparkle
            withAnimation(.easeInOut(duration: 1.5).delay(Double(i) * 0.1)) {
                sparkleAnimations[i].opacity = 0.0
                sparkleAnimations[i].scale *= 2.0
                sparkleAnimations[i].rotation += 180.0
            }
        }
        
        // Remove sparkles after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            sparkleAnimations.removeAll()
        }
    }
    
    private func triggerCelebrationHaptics(for tier: String) {
        switch tier.lowercased() {
        case "bronze":
            hapticService.playTaptic(.light)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                hapticService.playTaptic(.medium)
            }
            
        case "silver":
            hapticService.playTaptic(.medium)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                hapticService.playTaptic(.medium)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hapticService.playTaptic(.light)
            }
            
        case "gold":
            hapticService.playSuccessSequence()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                hapticService.playTaptic(.heavy)
            }
            
        case "platinum":
            hapticService.playSuccessSequence()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hapticService.playSuccessSequence()
            }
            
        case "diamond":
            // Epic celebration sequence
            hapticService.playSuccessSequence()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                hapticService.playTaptic(.heavy)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                hapticService.playSuccessSequence()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                hapticService.playTaptic(.heavy)
            }
            
        default:
            hapticService.playTaptic(.success)
        }
    }
    
    // MARK: - Setup and Event Handling
    
    private func setupAchievementTracking() {
        // Subscribe to achievement updates
        gamificationService.subscribeToAchievementUpdates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] achievement in
                self?.handleNewAchievement(achievement)
            }
            .store(in: &cancellables)
        
        // Load recent achievements
        recentAchievements = gamificationService.getRecentAchievements()
    }
    
    private func handleNewAchievement(_ achievement: Achievement) {
        // Add to recent achievements
        if !recentAchievements.contains(where: { $0.achievementId == achievement.achievementId }) {
            recentAchievements.insert(achievement, at: 0)
            
            // Limit the number of cached achievements
            if recentAchievements.count > 20 {
                recentAchievements = Array(recentAchievements.prefix(20))
            }
        }
        
        // Trigger celebration automatically for new achievements
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            triggerAchievementCelebration(achievement)
        }
    }
}

// MARK: - Achievement Quick View

struct WatchAchievementQuickView: View {
    let achievement: Achievement
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: {
            showingDetail = true
        }) {
            HStack {
                // Tier icon
                ZStack {
                    Circle()
                        .fill(achievementTierColor(achievement.tier))
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: achievementTierIconName(achievement.tier))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                // Title
                Text(achievement.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
                
                // Time
                Text(timeAgoString(from: achievement.unlockedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .fullScreenCover(isPresented: $showingDetail) {
            WatchAchievementDetailView(achievement: achievement)
        }
    }
    
    private func achievementTierColor(_ tier: String) -> Color {
        switch tier.lowercased() {
        case "bronze": return Color(red: 0.8, green: 0.5, blue: 0.2)
        case "silver": return Color(red: 0.75, green: 0.75, blue: 0.75)
        case "gold": return Color(red: 1.0, green: 0.84, blue: 0.0)
        case "platinum": return Color(red: 0.9, green: 0.9, blue: 0.95)
        case "diamond": return Color(red: 0.7, green: 0.9, blue: 1.0)
        default: return .gray
        }
    }
    
    private func achievementTierIconName(_ tier: String) -> String {
        switch tier.lowercased() {
        case "bronze": return "medal"
        case "silver": return "medal.fill"
        case "gold": return "crown"
        case "platinum": return "crown.fill"
        case "diamond": return "diamond"
        default: return "star"
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        else if interval < 3600 { return "\(Int(interval/60))m" }
        else { return "\(Int(interval/3600))h" }
    }
}

// MARK: - Achievement Detail View

struct WatchAchievementDetailView: View {
    let achievement: Achievement
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Large achievement icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    achievementTierColor(achievement.tier),
                                    achievementTierColor(achievement.tier).opacity(0.7),
                                    achievementTierColor(achievement.tier).opacity(0.3)
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 50
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: achievementTierIconName(achievement.tier))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                // Achievement details
                VStack(spacing: 12) {
                    Text(achievement.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("\(achievement.tier.capitalized) Achievement")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(achievementTierColor(achievement.tier))
                    
                    Text(achievement.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("Unlocked \(formatDate(achievement.unlockedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(achievementTierColor(achievement.tier))
            }
            .padding()
            .navigationTitle("Achievement")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func achievementTierColor(_ tier: String) -> Color {
        switch tier.lowercased() {
        case "bronze": return Color(red: 0.8, green: 0.5, blue: 0.2)
        case "silver": return Color(red: 0.75, green: 0.75, blue: 0.75)
        case "gold": return Color(red: 1.0, green: 0.84, blue: 0.0)
        case "platinum": return Color(red: 0.9, green: 0.9, blue: 0.95)
        case "diamond": return Color(red: 0.7, green: 0.9, blue: 1.0)
        default: return .gray
        }
    }
    
    private func achievementTierIconName(_ tier: String) -> String {
        switch tier.lowercased() {
        case "bronze": return "medal"
        case "silver": return "medal.fill"
        case "gold": return "crown"
        case "platinum": return "crown.fill"
        case "diamond": return "diamond"
        default: return "star"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Types

struct SparkleAnimation {
    let id: UUID
    var position: CGPoint
    let color: Color
    var opacity: Double
    var scale: CGFloat
    var rotation: Double
}

// MARK: - Previews

struct WatchAchievementNotificationView_Previews: PreviewProvider {
    static var previews: some View {
        WatchAchievementNotificationView(
            gamificationService: MockWatchGamificationService() as! WatchGamificationService,
            hapticService: MockWatchHapticFeedbackService()
        )
        .previewDevice("Apple Watch Series 7 - 45mm")
    }
}