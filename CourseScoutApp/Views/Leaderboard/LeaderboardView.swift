import SwiftUI
import Combine

struct LeaderboardView: View {
    @StateObject private var viewModel: LeaderboardViewModel
    @State private var selectedLeaderboard: Leaderboard?
    @State private var showingCreateLeaderboard = false
    @State private var refreshing = false
    
    let courseId: String
    
    init(courseId: String) {
        self.courseId = courseId
        self._viewModel = StateObject(wrappedValue: LeaderboardViewModel(courseId: courseId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemBackground), Color(.systemGroupedBackground)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Header with real-time indicators
                        headerSection
                        
                        // Featured leaderboards
                        if !viewModel.featuredLeaderboards.isEmpty {
                            featuredSection
                        }
                        
                        // Main leaderboards list
                        leaderboardsSection
                        
                        // Social challenges
                        if !viewModel.socialChallenges.isEmpty {
                            socialChallengesSection
                        }
                    }
                    .padding(.horizontal)
                }
                .refreshable {
                    await refreshData()
                }
                
                // Loading overlay
                if viewModel.isLoading && viewModel.leaderboards.isEmpty {
                    ProgressView("Loading leaderboards...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.8))
                }
            }
            .navigationTitle("Leaderboards")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreateLeaderboard = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await refreshData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees(refreshing ? 360 : 0))
                            .animation(.linear(duration: 1).repeatCount(refreshing ? .max : 0, autoreverses: false), value: refreshing)
                    }
                }
            }
            .sheet(isPresented: $showingCreateLeaderboard) {
                CreateLeaderboardView(courseId: courseId) { newLeaderboard in
                    Task {
                        await viewModel.createLeaderboard(newLeaderboard)
                    }
                }
            }
            .sheet(item: $selectedLeaderboard) { leaderboard in
                LeaderboardDetailView(leaderboard: leaderboard)
            }
        }
        .task {
            await viewModel.loadLeaderboards()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Live Competitions")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Circle()
                            .fill(viewModel.isConnected ? .green : .red)
                            .frame(width: 8, height: 8)
                        
                        Text(viewModel.isConnected ? "Live Updates" : "Offline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Statistics
                VStack(alignment: .trailing) {
                    Text("\(viewModel.activeLeaderboards.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    Text("Active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Quick stats
            HStack(spacing: 20) {
                StatView(title: "Players", value: "\(viewModel.totalPlayers)", color: .green)
                StatView(title: "Today", value: "\(viewModel.todaysRounds)", color: .orange)
                StatView(title: "Live", value: "\(viewModel.liveRounds)", color: .red)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - Featured Section
    
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Featured Competitions")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(viewModel.featuredLeaderboards) { leaderboard in
                        FeaturedLeaderboardCard(leaderboard: leaderboard) {
                            selectedLeaderboard = leaderboard
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Leaderboards Section
    
    private var leaderboardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("All Competitions")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Menu {
                    Button("All Types") { viewModel.filterType = nil }
                    Divider()
                    ForEach(LeaderboardType.allCases, id: \.self) { type in
                        Button(type.displayName) {
                            viewModel.filterType = type
                        }
                    }
                } label: {
                    HStack {
                        Text(viewModel.filterType?.displayName ?? "All Types")
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 4)
            
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredLeaderboards) { leaderboard in
                    LeaderboardCard(
                        leaderboard: leaderboard,
                        topEntries: viewModel.getTopEntries(for: leaderboard.id)
                    ) {
                        selectedLeaderboard = leaderboard
                    }
                    .transition(.slide)
                }
            }
        }
    }
    
    // MARK: - Social Challenges Section
    
    private var socialChallengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Friend Challenges")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal, 4)
            
            LazyVStack(spacing: 8) {
                ForEach(viewModel.socialChallenges) { challenge in
                    SocialChallengeCard(challenge: challenge) {
                        // Handle challenge tap
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func refreshData() async {
        refreshing = true
        await viewModel.refreshAll()
        refreshing = false
    }
}

// MARK: - Supporting Views

struct StatView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct FeaturedLeaderboardCard: View {
    let leaderboard: Leaderboard
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: leaderboard.type.icon)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                
                Spacer()
                
                if let timeRemaining = leaderboard.timeRemaining {
                    Text(timeRemaining)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Text(leaderboard.name)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)
            
            HStack {
                Text("\(leaderboard.totalParticipants) players")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                if let prize = leaderboard.formattedPrizePool {
                    Text(prize)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.yellow)
                }
            }
        }
        .padding()
        .frame(width: 200, height: 120)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.blue, .purple]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .onTapGesture(perform: onTap)
    }
}

struct LeaderboardCard: View {
    let leaderboard: Leaderboard
    let topEntries: [LeaderboardEntry]
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(leaderboard.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Image(systemName: leaderboard.type.icon)
                            .foregroundColor(.blue)
                        
                        Text(leaderboard.type.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !leaderboard.isExpired {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(leaderboard.totalParticipants)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    Text("Players")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Top 3 preview
            if !topEntries.isEmpty {
                VStack(spacing: 6) {
                    ForEach(topEntries.prefix(3)) { entry in
                        HStack {
                            Text("#\(entry.position)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(entry.position == 1 ? .yellow : .secondary)
                                .frame(width: 30, alignment: .leading)
                            
                            Text(entry.playerName)
                                .font(.subheadline)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(entry.formattedScore)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(entry.scoreToPar <= 0 ? .green : .primary)
                            
                            if entry.positionChange != .same {
                                Image(systemName: entry.positionChange.icon)
                                    .font(.caption2)
                                    .foregroundColor(Color(entry.positionChange.color))
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(8)
            }
            
            // Footer
            HStack {
                if let timeRemaining = leaderboard.timeRemaining {
                    Label(timeRemaining, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                if let prize = leaderboard.formattedPrizePool {
                    Label(prize, systemImage: "trophy")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
                
                Button {
                    onTap()
                } label: {
                    Text("View All")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
}

struct SocialChallengeCard: View {
    let challenge: SocialChallenge
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(challenge.participants.count) participants")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                onTap()
            } label: {
                Text("Join")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LeaderboardView(courseId: "sample-course-id")
    }
}