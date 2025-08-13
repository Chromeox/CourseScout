import SwiftUI
import Combine

struct SocialChallengeCard: View {
    let challenge: SocialChallenge
    let onTap: () -> Void
    
    @Environment(\.serviceContainer) private var serviceContainer
    @State private var isPressed = false
    @State private var isJoining = false
    @State private var hasJoined = false
    @State private var showingInviteView = false
    
    private var hapticService: HapticFeedbackServiceProtocol {
        serviceContainer.hapticFeedbackService
    }
    
    private var isActive: Bool {
        challenge.endDate > Date()
    }
    
    private var timeRemaining: String {
        let timeInterval = challenge.endDate.timeIntervalSinceNow
        if timeInterval <= 0 {
            return "Ended"
        }
        
        let hours = Int(timeInterval) / 3600
        let days = hours / 24
        
        if days > 0 {
            return "\(days)d remaining"
        } else if hours > 0 {
            return "\(hours)h remaining"
        } else {
            let minutes = Int(timeInterval) / 60
            return "\(minutes)m remaining"
        }
    }
    
    private var challengeIcon: String {
        switch challenge.targetMetric {
        case .lowestScore:
            return "target"
        case .mostImproved:
            return "chart.line.uptrend.xyaxis"
        case .longestDrive:
            return "arrow.up.right"
        case .fewestPutts:
            return "flag.fill"
        }
    }
    
    private var challengeColor: Color {
        switch challenge.targetMetric {
        case .lowestScore:
            return .blue
        case .mostImproved:
            return .green
        case .longestDrive:
            return .orange
        case .fewestPutts:
            return .purple
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header Section
            headerSection
            
            // Challenge Details
            detailsSection
            
            // Progress Section
            progressSection
            
            // Action Buttons
            actionSection
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(challengeColor.opacity(0.3), lineWidth: 1)
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            handleCardTap()
        }
        .onLongPressGesture(
            minimumDuration: 0.1,
            maximumDistance: 50,
            perform: {},
            onPressingChanged: { isPressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = isPressing
                }
                
                if isPressing {
                    Task {
                        await hapticService.provideChallengeInvitationHaptic()
                    }
                }
            }
        )
        .sheet(isPresented: $showingInviteView) {
            SocialInteractionView(challenge: challenge)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            // Challenge Icon and Type
            HStack(spacing: 8) {
                Image(systemName: challengeIcon)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(challengeColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    Text(challenge.targetMetric.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Status Badge
            VStack(alignment: .trailing, spacing: 4) {
                statusBadge
                
                if isActive {
                    Text(timeRemaining)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Details Section
    
    private var detailsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Label("\(challenge.participants.count) players", systemImage: "person.2.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let entryFee = challenge.entryFee, entryFee > 0 {
                    Label("$\(Int(entryFee))", systemImage: "dollarsign.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
            
            if !challenge.description.isEmpty {
                Text(challenge.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Current Leaders")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    showingInviteView = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.plus")
                        Text("Invite")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Top 3 participants preview
            topParticipantsView
        }
    }
    
    // MARK: - Action Section
    
    private var actionSection: some View {
        HStack(spacing: 12) {
            // View Details Button
            Button {
                onTap()
            } label: {
                HStack {
                    Image(systemName: "eye")
                    Text("View Details")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Join/Action Button
            actionButton
        }
    }
    
    // MARK: - Supporting Views
    
    private var statusBadge: some View {
        Group {
            if isActive {
                if hasJoined {
                    Text("JOINED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .cornerRadius(6)
                } else {
                    Text("ACTIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(challengeColor)
                        .cornerRadius(6)
                }
            } else {
                Text("ENDED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray)
                    .cornerRadius(6)
            }
        }
    }
    
    private var topParticipantsView: some View {
        LazyVStack(spacing: 4) {
            ForEach(Array(challenge.participants.prefix(3).enumerated()), id: \.offset) { index, participantId in
                HStack {
                    // Position indicator
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(index == 0 ? .yellow : .secondary)
                        .frame(width: 20)
                    
                    // Player avatar
                    Circle()
                        .fill(challengeColor.opacity(0.2))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(String(participantId.prefix(1).uppercased()))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(challengeColor)
                        )
                    
                    // Player name (simplified for demo)
                    Text("Player \(participantId.suffix(4))")
                        .font(.caption)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Score placeholder
                    if let targetScore = challenge.targetScore {
                        Text("\(targetScore - index)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    // Position change indicator
                    if index < 2 {
                        Image(systemName: index == 0 ? "arrow.up.circle.fill" : "minus.circle.fill")
                            .font(.caption2)
                            .foregroundColor(index == 0 ? .green : .orange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemGroupedBackground).opacity(0.5))
                .cornerRadius(8)
            }
        }
    }
    
    private var actionButton: some View {
        Button {
            handleActionButtonTap()
        } label: {
            HStack {
                if isJoining {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: hasJoined ? "checkmark.circle.fill" : "plus.circle.fill")
                }
                
                Text(hasJoined ? "Joined" : "Join Challenge")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Group {
                    if hasJoined {
                        Color.green
                    } else if isActive {
                        challengeColor
                    } else {
                        Color.gray
                    }
                }
            )
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isActive || isJoining || hasJoined)
    }
    
    // MARK: - Actions
    
    private func handleCardTap() {
        Task {
            await hapticService.provideChallengeInvitationHaptic()
        }
        onTap()
    }
    
    private func handleActionButtonTap() {
        guard isActive && !hasJoined && !isJoining else { return }
        
        Task {
            await hapticService.provideFriendChallengeHaptic(challengeEvent: .invited)
            
            withAnimation(.easeInOut(duration: 0.3)) {
                isJoining = true
            }
            
            // Simulate joining challenge
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                hasJoined = true
                isJoining = false
            }
            
            await hapticService.provideFriendChallengeHaptic(challengeEvent: .accepted)
        }
    }
}

// MARK: - Extensions

private extension SocialChallenge.ChallengeMetric {
    var displayName: String {
        switch self {
        case .lowestScore:
            return "Lowest Score"
        case .mostImproved:
            return "Most Improved"
        case .longestDrive:
            return "Longest Drive"
        case .fewestPutts:
            return "Fewest Putts"
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleChallenge = SocialChallenge(
        id: "challenge-1",
        name: "Weekend Warriors",
        description: "See who can post the lowest score this weekend at our home course!",
        createdBy: "user-1",
        participants: ["user-1", "user-2", "user-3", "user-4"],
        courseId: "course-1",
        targetScore: 72,
        targetMetric: .lowestScore,
        startDate: Date(),
        endDate: Date().addingTimeInterval(86400 * 2),
        isPublic: true,
        entryFee: 25.0,
        winner: nil,
        prizes: []
    )
    
    VStack(spacing: 16) {
        SocialChallengeCard(challenge: sampleChallenge) {
            print("Challenge tapped")
        }
        
        Spacer()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}