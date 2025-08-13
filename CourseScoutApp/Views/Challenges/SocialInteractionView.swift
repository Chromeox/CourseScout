import SwiftUI
import Combine

struct SocialInteractionView: View {
    let challenge: SocialChallenge
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.serviceContainer) private var serviceContainer
    
    @State private var selectedTab = 0
    @State private var inviteMessage = ""
    @State private var selectedFriends: Set<String> = []
    @State private var showingFriendPicker = false
    @State private var showingMessageComposer = false
    @State private var isInviting = false
    @State private var inviteAnimationOffset: CGFloat = 0
    @State private var celebrationVisible = false
    
    // Mock data
    @State private var recentActivity: [ChallengeActivity] = []
    @State private var challengeMessages: [ChallengeMessage] = []
    @State private var leaderboardEntries: [MockLeaderboardEntry] = []
    
    private var hapticService: HapticFeedbackServiceProtocol {
        serviceContainer.hapticFeedbackService
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with challenge info
                headerSection
                
                // Tab selector
                tabSelector
                
                // Tab content
                TabView(selection: $selectedTab) {
                    // Activity Tab
                    activityTab
                        .tag(0)
                    
                    // Leaderboard Tab
                    leaderboardTab
                        .tag(1)
                    
                    // Chat Tab
                    chatTab
                        .tag(2)
                    
                    // Invite Tab
                    inviteTab
                        .tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Challenge Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        handleClose()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            shareChallenge()
                        } label: {
                            Label("Share Challenge", systemImage: "square.and.arrow.up")
                        }
                        
                        Button {
                            reportChallenge()
                        } label: {
                            Label("Report Issue", systemImage: "flag")
                        }
                        
                        Button(role: .destructive) {
                            leaveChallenge()
                        } label: {
                            Label("Leave Challenge", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                loadData()
            }
            .overlay {
                if celebrationVisible {
                    celebrationOverlay
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Challenge name and status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(challenge.targetMetric.displayName)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                // Status badge
                statusBadge
            }
            
            // Quick stats
            HStack(spacing: 20) {
                StatBubble(
                    icon: "person.2.fill",
                    value: "\(challenge.participants.count)",
                    label: "Players",
                    color: .blue
                )
                
                StatBubble(
                    icon: "clock",
                    value: timeRemaining,
                    label: "Remaining",
                    color: .orange
                )
                
                if let entryFee = challenge.entryFee, entryFee > 0 {
                    StatBubble(
                        icon: "dollarsign.circle",
                        value: "$\(Int(entryFee))",
                        label: "Entry",
                        color: .green
                    )
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabItems.enumerated()), id: \.offset) { index, item in
                Button {
                    switchToTab(index)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .medium))
                        
                        Text(item.title)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(selectedTab == index ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selectedTab == index ?
                        Color.blue.opacity(0.1) : Color.clear
                    )
                    .overlay(
                        Rectangle()
                            .fill(Color.blue)
                            .frame(height: 2)
                            .opacity(selectedTab == index ? 1 : 0),
                        alignment: .bottom
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }
    
    // MARK: - Activity Tab
    
    private var activityTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(recentActivity) { activity in
                    ActivityCard(activity: activity)
                        .transition(.slide)
                }
                
                if recentActivity.isEmpty {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "No Recent Activity",
                        message: "Activity will appear here as players join and submit scores"
                    )
                    .padding(.top, 50)
                }
            }
            .padding()
        }
        .refreshable {
            await refreshActivity()
        }
    }
    
    // MARK: - Leaderboard Tab
    
    private var leaderboardTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(leaderboardEntries.enumerated()), id: \.offset) { index, entry in
                    LeaderboardEntryCard(
                        entry: entry,
                        position: index + 1,
                        isCurrentUser: entry.playerId == "current-user"
                    )
                    .transition(.slide)
                }
                
                if leaderboardEntries.isEmpty {
                    EmptyStateView(
                        icon: "list.number",
                        title: "No Scores Yet",
                        message: "The leaderboard will update as players submit their scores"
                    )
                    .padding(.top, 50)
                }
            }
            .padding()
        }
        .refreshable {
            await refreshLeaderboard()
        }
    }
    
    // MARK: - Chat Tab
    
    private var chatTab: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(challengeMessages) { message in
                        MessageBubble(message: message)
                    }
                    
                    if challengeMessages.isEmpty {
                        EmptyStateView(
                            icon: "bubble.left.and.bubble.right",
                            title: "Start the Conversation",
                            message: "Send a message to get the challenge discussion started!"
                        )
                        .padding(.top, 50)
                    }
                }
                .padding()
            }
            
            // Message input
            messageInputView
        }
    }
    
    // MARK: - Invite Tab
    
    private var inviteTab: some View {
        VStack(spacing: 20) {
            // Invite section
            VStack(alignment: .leading, spacing: 16) {
                Text("Invite Friends")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Challenge your friends to join the competition!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Quick invite buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(mockFriends, id: \.id) { friend in
                            FriendInviteButton(
                                friend: friend,
                                isSelected: selectedFriends.contains(friend.id)
                            ) {
                                toggleFriendSelection(friend.id)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Custom message
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invitation Message")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Add a personal message...", text: $inviteMessage, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(2...4)
                }
                
                // Send invites button
                Button {
                    sendInvitations()
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Send Invites (\(selectedFriends.count))")
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .scaleEffect(isInviting ? 0.98 : 1.0)
                    .offset(x: inviteAnimationOffset)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedFriends.isEmpty || isInviting)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isInviting)
            }
            .padding()
            
            Spacer()
        }
    }
    
    // MARK: - Supporting Views
    
    private var statusBadge: some View {
        Text(challenge.endDate > Date() ? "ACTIVE" : "ENDED")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(challenge.endDate > Date() ? .green : .gray)
            .cornerRadius(8)
    }
    
    private var timeRemaining: String {
        let timeInterval = challenge.endDate.timeIntervalSinceNow
        if timeInterval <= 0 {
            return "Ended"
        }
        
        let hours = Int(timeInterval) / 3600
        let days = hours / 24
        
        if days > 0 {
            return "\(days)d"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            let minutes = Int(timeInterval) / 60
            return "\(minutes)m"
        }
    }
    
    private var messageInputView: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $inviteMessage)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button {
                sendMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
            .disabled(inviteMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    private var celebrationOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
                
                Text("Invitations Sent!")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Your friends will receive notifications about the challenge")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(30)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
        }
        .transition(.scale.combined(with: .opacity))
        .onTapGesture {
            dismissCelebration()
        }
    }
    
    // MARK: - Data and Actions
    
    private let tabItems = [
        (title: "Activity", icon: "clock.arrow.circlepath"),
        (title: "Leaderboard", icon: "list.number"),
        (title: "Chat", icon: "bubble.left.and.bubble.right"),
        (title: "Invite", icon: "person.badge.plus")
    ]
    
    private let mockFriends = [
        MockFriend(id: "1", name: "John", avatar: "🏌️‍♂️"),
        MockFriend(id: "2", name: "Sarah", avatar: "⛳"),
        MockFriend(id: "3", name: "Mike", avatar: "🏌️‍♀️"),
        MockFriend(id: "4", name: "Emma", avatar: "🏌️‍♂️"),
        MockFriend(id: "5", name: "David", avatar: "⛳")
    ]
    
    private func loadData() {
        // Load mock data
        recentActivity = generateMockActivity()
        challengeMessages = generateMockMessages()
        leaderboardEntries = generateMockLeaderboard()
    }
    
    private func handleClose() {
        Task {
            await hapticService.provideChallengeInvitationHaptic()
        }
        dismiss()
    }
    
    private func switchToTab(_ index: Int) {
        Task {
            await hapticService.provideChallengeInvitationHaptic()
        }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = index
        }
    }
    
    private func toggleFriendSelection(_ friendId: String) {
        Task {
            await hapticService.provideChallengeInvitationHaptic()
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedFriends.contains(friendId) {
                selectedFriends.remove(friendId)
            } else {
                selectedFriends.insert(friendId)
            }
        }
    }
    
    private func sendInvitations() {
        guard !selectedFriends.isEmpty else { return }
        
        Task {
            await hapticService.provideFriendChallengeHaptic(challengeEvent: .invited)
            
            withAnimation(.easeInOut(duration: 0.3)) {
                isInviting = true
            }
            
            // Simulate sending
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isInviting = false
                celebrationVisible = true
            }
            
            await hapticService.provideChallengeVictoryHaptic(competitionLevel: .competitive)
            
            // Auto-dismiss celebration
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                dismissCelebration()
            }
        }
    }
    
    private func dismissCelebration() {
        withAnimation(.easeInOut(duration: 0.3)) {
            celebrationVisible = false
        }
        selectedFriends.removeAll()
        inviteMessage = ""
    }
    
    private func sendMessage() {
        guard !inviteMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        Task {
            await hapticService.provideChallengeInvitationHaptic()
        }
        
        // Add message to list
        let newMessage = ChallengeMessage(
            id: UUID().uuidString,
            senderId: "current-user",
            senderName: "You",
            content: inviteMessage.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: Date(),
            type: .text
        )
        
        challengeMessages.append(newMessage)
        inviteMessage = ""
    }
    
    private func shareChallenge() {
        Task {
            await hapticService.provideChallengeInvitationHaptic()
        }
        // Implement sharing logic
    }
    
    private func reportChallenge() {
        Task {
            await hapticService.provideFriendChallengeHaptic(challengeEvent: .declined)
        }
        // Implement reporting logic
    }
    
    private func leaveChallenge() {
        Task {
            await hapticService.provideFriendChallengeHaptic(challengeEvent: .lost)
        }
        dismiss()
    }
    
    private func refreshActivity() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        recentActivity = generateMockActivity()
    }
    
    private func refreshLeaderboard() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        leaderboardEntries = generateMockLeaderboard()
    }
    
    // MARK: - Mock Data Generators
    
    private func generateMockActivity() -> [ChallengeActivity] {
        return [
            ChallengeActivity(
                id: "1",
                type: .scoreSubmitted,
                playerId: "user1",
                playerName: "John",
                description: "submitted a score of 74",
                timestamp: Date().addingTimeInterval(-3600)
            ),
            ChallengeActivity(
                id: "2",
                type: .playerJoined,
                playerId: "user2",
                playerName: "Sarah",
                description: "joined the challenge",
                timestamp: Date().addingTimeInterval(-7200)
            ),
            ChallengeActivity(
                id: "3",
                type: .leaderChanged,
                playerId: "user3",
                playerName: "Mike",
                description: "took the lead with 71",
                timestamp: Date().addingTimeInterval(-10800)
            )
        ]
    }
    
    private func generateMockMessages() -> [ChallengeMessage] {
        return [
            ChallengeMessage(
                id: "1",
                senderId: "user1",
                senderName: "John",
                content: "Great round everyone! Looking forward to the competition 🏌️‍♂️",
                timestamp: Date().addingTimeInterval(-1800),
                type: .text
            ),
            ChallengeMessage(
                id: "2",
                senderId: "user2",
                senderName: "Sarah",
                content: "Just finished my round - course was in perfect condition today!",
                timestamp: Date().addingTimeInterval(-900),
                type: .text
            )
        ]
    }
    
    private func generateMockLeaderboard() -> [MockLeaderboardEntry] {
        return [
            MockLeaderboardEntry(playerId: "user3", playerName: "Mike", score: 71, change: .up),
            MockLeaderboardEntry(playerId: "user1", playerName: "John", score: 74, change: .same),
            MockLeaderboardEntry(playerId: "user2", playerName: "Sarah", score: 76, change: .down),
            MockLeaderboardEntry(playerId: "current-user", playerName: "You", score: 78, change: .up)
        ]
    }
}

// MARK: - Supporting Views and Models

struct StatBubble: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct ActivityCard: View {
    let activity: ChallengeActivity
    
    var body: some View {
        HStack(spacing: 12) {
            // Activity type icon
            Image(systemName: activity.type.icon)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(activity.type.color))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.playerName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(activity.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(activity.timestamp.formatted(.relative(presentation: .abbreviated)))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct LeaderboardEntryCard: View {
    let entry: MockLeaderboardEntry
    let position: Int
    let isCurrentUser: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Position
            Text("\(position)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(position <= 3 ? .yellow : .primary)
                .frame(width: 30)
            
            // Player info
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.playerName)
                    .font(.subheadline)
                    .fontWeight(isCurrentUser ? .bold : .medium)
                    .foregroundColor(isCurrentUser ? .blue : .primary)
                
                if isCurrentUser {
                    Text("Your Position")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            // Score
            Text("\(entry.score)")
                .font(.title3)
                .fontWeight(.bold)
            
            // Change indicator
            if entry.change != .same {
                Image(systemName: entry.change == .up ? "arrow.up" : "arrow.down")
                    .font(.caption)
                    .foregroundColor(entry.change == .up ? .green : .red)
            }
        }
        .padding()
        .background(
            Color(.secondarySystemGroupedBackground)
                .overlay(
                    isCurrentUser ?
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.5), lineWidth: 2) :
                    nil
                )
        )
        .cornerRadius(12)
    }
}

struct MessageBubble: View {
    let message: ChallengeMessage
    
    private var isCurrentUser: Bool {
        message.senderId == "current-user"
    }
    
    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(message.content)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        isCurrentUser ? Color.blue : Color(.secondarySystemGroupedBackground)
                    )
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .cornerRadius(16)
                
                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !isCurrentUser {
                Spacer()
            }
        }
    }
}

struct FriendInviteButton: View {
    let friend: MockFriend
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(friend.avatar)
                    .font(.title)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: isSelected ? 3 : 0)
                    )
                
                Text(friend.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .blue : .primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Data Models

struct ChallengeActivity: Identifiable {
    let id: String
    let type: ActivityType
    let playerId: String
    let playerName: String
    let description: String
    let timestamp: Date
    
    enum ActivityType {
        case scoreSubmitted
        case playerJoined
        case leaderChanged
        case messagePosted
        
        var icon: String {
            switch self {
            case .scoreSubmitted: return "target"
            case .playerJoined: return "person.badge.plus"
            case .leaderChanged: return "crown"
            case .messagePosted: return "bubble.left"
            }
        }
        
        var color: Color {
            switch self {
            case .scoreSubmitted: return .blue
            case .playerJoined: return .green
            case .leaderChanged: return .yellow
            case .messagePosted: return .purple
            }
        }
    }
}

struct ChallengeMessage: Identifiable {
    let id: String
    let senderId: String
    let senderName: String
    let content: String
    let timestamp: Date
    let type: MessageType
    
    enum MessageType {
        case text
        case image
        case system
    }
}

struct MockLeaderboardEntry {
    let playerId: String
    let playerName: String
    let score: Int
    let change: PositionChange
    
    enum PositionChange {
        case up, down, same
    }
}

struct MockFriend: Identifiable {
    let id: String
    let name: String
    let avatar: String
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
        name: "Weekend Warriors Championship",
        description: "Battle it out for the weekend crown",
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
    
    SocialInteractionView(challenge: sampleChallenge)
}