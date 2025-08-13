import SwiftUI
import Combine

struct FeaturedLeaderboardCard: View {
    let leaderboard: Leaderboard
    let onTap: () -> Void
    
    @Environment(\.serviceContainer) private var serviceContainer
    @State private var isPressed = false
    @State private var animationOffset: CGFloat = 0
    @State private var glowOpacity: Double = 0.5
    @State private var showingJoinAlert = false
    @State private var isJoining = false
    
    private var hapticService: HapticFeedbackServiceProtocol {
        serviceContainer.hapticFeedbackService
    }
    
    private var gradientColors: [Color] {
        switch leaderboard.type {
        case .strokePlay:
            return [.blue, .purple]
        case .tournament:
            return [.orange, .red]
        case .skillsChallenge:
            return [.green, .teal]
        case .headToHead:
            return [.pink, .purple]
        default:
            return [.indigo, .blue]
        }
    }
    
    private var typeIcon: String {
        switch leaderboard.type {
        case .strokePlay:
            return "flag.fill"
        case .tournament:
            return "trophy.fill"
        case .skillsChallenge:
            return "target"
        case .headToHead:
            return "person.2.fill"
        default:
            return "chart.bar.fill"
        }
    }
    
    private var isActive: Bool {
        !leaderboard.isExpired
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with live indicator
            headerSection
            
            // Main content
            contentSection
            
            // Footer with stats
            footerSection
            
            // Action button
            actionSection
        }
        .padding()
        .frame(width: 220, height: 180)
        .background(
            backgroundView
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .rotation3DEffect(
            .degrees(isPressed ? 2 : 0),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.8
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isPressed)
        .onTapGesture {
            handleCardTap()
        }
        .onLongPressGesture(
            minimumDuration: 0.1,
            maximumDistance: 50,
            perform: {},
            onPressingChanged: { isPressing in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isPressed = isPressing
                }
                
                if isPressing {
                    Task {
                        await hapticService.provideLeaderboardMilestoneHaptic(milestone: .topTen)
                    }
                }
            }
        )
        .onAppear {
            startAnimations()
        }
        .alert("Join Leaderboard", isPresented: $showingJoinAlert) {
            Button("Cancel") {}
            Button("Join") {
                handleJoinLeaderboard()
            }
        } message: {
            Text("Would you like to join this leaderboard competition?")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            // Type icon with animation
            Image(systemName: typeIcon)
                .foregroundColor(.white)
                .font(.title2)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.white.opacity(0.2))
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )
                )
                .rotationEffect(.degrees(animationOffset))
            
            Spacer()
            
            // Live indicator and time remaining
            VStack(alignment: .trailing, spacing: 2) {
                if isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .opacity(glowOpacity)
                        
                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                
                if let timeRemaining = leaderboard.timeRemaining {
                    Text(timeRemaining)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(leaderboard.name)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            if !leaderboard.description.isEmpty {
                Text(leaderboard.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
            }
        }
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        HStack(spacing: 12) {
            // Participants count
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
                
                Text("\(leaderboard.totalParticipants)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Prize pool or entry fee
            if let prize = leaderboard.formattedPrizePool {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    
                    Text(prize)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)
                }
            } else if let entryFee = leaderboard.entryFee, entryFee > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    
                    Text("$\(Int(entryFee))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    // MARK: - Action Section
    
    private var actionSection: some View {
        HStack {
            Button {
                onTap()
            } label: {
                HStack {
                    Image(systemName: "eye")
                    Text("View")
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.2))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            if isActive {
                Button {
                    showingJoinAlert = true
                } label: {
                    HStack {
                        if isJoining {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text("Join")
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(gradientColors[0])
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isJoining)
            }
        }
    }
    
    // MARK: - Background View
    
    private var backgroundView: some View {
        ZStack {
            // Main gradient background
            LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Animated overlay for premium effect
            LinearGradient(
                gradient: Gradient(colors: [
                    .white.opacity(0.1),
                    .clear,
                    .white.opacity(0.05)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .rotationEffect(.degrees(animationOffset * 0.5))
            
            // Border glow effect
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .white.opacity(0.4),
                            .clear,
                            .white.opacity(0.2)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .cornerRadius(16)
        .shadow(
            color: gradientColors[0].opacity(0.3),
            radius: 8,
            x: 0,
            y: 4
        )
    }
    
    // MARK: - Actions
    
    private func handleCardTap() {
        Task {
            await hapticService.providePositionChangeHaptic(change: .minorImprovement)
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            // Brief scale animation
        }
        
        onTap()
    }
    
    private func handleJoinLeaderboard() {
        Task {
            await hapticService.provideChallengeInvitationHaptic()
            
            withAnimation(.easeInOut(duration: 0.3)) {
                isJoining = true
            }
            
            // Simulate joining
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isJoining = false
            }
            
            await hapticService.provideChallengeVictoryHaptic(competitionLevel: .competitive)
        }
    }
    
    private func startAnimations() {
        // Rotation animation for icon
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            animationOffset = 360
        }
        
        // Glow animation for live indicator
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowOpacity = 1.0
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleLeaderboard = Leaderboard(
        id: "leaderboard-1",
        name: "Weekend Championship",
        description: "Compete with the best players this weekend",
        courseId: "course-1",
        type: .tournament,
        startDate: Date(),
        endDate: Date().addingTimeInterval(86400 * 2),
        maxParticipants: 50,
        entryFee: 25.0,
        prizePool: 1000.0,
        rules: [],
        isPublic: true,
        createdBy: "user-1",
        participants: Array(1...24).map { "user-\($0)" },
        currentLeaderboard: [],
        isActive: true,
        totalParticipants: 24
    )
    
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 16) {
            FeaturedLeaderboardCard(leaderboard: sampleLeaderboard) {
                print("Featured leaderboard tapped")
            }
            
            FeaturedLeaderboardCard(leaderboard: sampleLeaderboard) {
                print("Featured leaderboard tapped")
            }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}