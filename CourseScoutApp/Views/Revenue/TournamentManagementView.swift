import SwiftUI
import Combine

// MARK: - Tournament Management View
/// White label tournament management for golf courses
/// Revenue target: $500-2000/month per golf course for tournament management
/// Advanced features for managing ongoing tournaments with real-time revenue tracking

struct TournamentManagementView: View {
    @StateObject private var viewModel = TournamentManagementViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundGradient
                
                if viewModel.isLoading {
                    loadingView
                } else {
                    contentView
                }
            }
            .navigationTitle("Tournament Management")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Create New Tournament") {
                            viewModel.showCreateTournament = true
                        }
                        
                        Button("Export Revenue Report") {
                            Task {
                                await viewModel.exportRevenueReport()
                            }
                        }
                        
                        Button("Analytics Dashboard") {
                            viewModel.showAnalyticsDashboard = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                await viewModel.refreshData()
            }
        }
        .sheet(isPresented: $viewModel.showCreateTournament) {
            TournamentHostingView()
        }
        .sheet(isPresented: $viewModel.showAnalyticsDashboard) {
            TournamentAnalyticsDashboard(tournaments: viewModel.tournaments)
        }
        .task {
            await viewModel.loadInitialData()
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(.systemBackground),
                Color(.systemGray6).opacity(0.3)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading tournaments...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 16) {
                revenueOverviewCard
                tournamentStatsCard
                activeTournamentsSection
                upcomingTournamentsSection
                completedTournamentsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Revenue Overview Card
    
    private var revenueOverviewCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.green)
                        .font(.title2)
                    
                    Text("Revenue Overview")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text("This Month")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                
                HStack(spacing: 20) {
                    RevenueMetricView(
                        title: "Total Revenue",
                        amount: viewModel.totalRevenue,
                        currency: viewModel.currency,
                        changePercentage: viewModel.revenueGrowth,
                        isPositive: viewModel.revenueGrowth >= 0
                    )
                    
                    Divider()
                        .frame(height: 40)
                    
                    RevenueMetricView(
                        title: "Active Tournaments",
                        amount: Double(viewModel.activeTournamentCount),
                        currency: "",
                        changePercentage: nil,
                        isPositive: true,
                        isCount: true
                    )
                }
                
                HStack(spacing: 20) {
                    RevenueMetricView(
                        title: "Avg. Revenue/Tournament",
                        amount: viewModel.averageRevenuePerTournament,
                        currency: viewModel.currency,
                        changePercentage: nil,
                        isPositive: true
                    )
                    
                    Divider()
                        .frame(height: 40)
                    
                    RevenueMetricView(
                        title: "Monthly Target",
                        amount: viewModel.monthlyTarget,
                        currency: viewModel.currency,
                        changePercentage: viewModel.targetProgress,
                        isPositive: viewModel.targetProgress >= 0,
                        isTarget: true
                    )
                }
            }
        }
    }
    
    // MARK: - Tournament Stats Card
    
    private var tournamentStatsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    
                    Text("Tournament Statistics")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatisticView(
                        title: "Total Participants",
                        value: "\(viewModel.totalParticipants)",
                        icon: "person.3.fill",
                        color: .blue
                    )
                    
                    StatisticView(
                        title: "Completion Rate",
                        value: "\(Int(viewModel.completionRate * 100))%",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    
                    StatisticView(
                        title: "Avg. Entry Fee",
                        value: viewModel.averageEntryFee.formatted(.currency(code: viewModel.currency)),
                        icon: "dollarsign.circle.fill",
                        color: .purple
                    )
                }
            }
        }
    }
    
    // MARK: - Active Tournaments Section
    
    private var activeTournamentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Tournaments")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                if !viewModel.activeTournaments.isEmpty {
                    Text("\(viewModel.activeTournaments.count) active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if viewModel.activeTournaments.isEmpty {
                EmptyStateView(
                    icon: "trophy",
                    title: "No Active Tournaments",
                    subtitle: "Create a new tournament to start generating revenue"
                ) {
                    Button("Create Tournament") {
                        viewModel.showCreateTournament = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.activeTournaments) { tournament in
                        TournamentManagementCard(
                            tournament: tournament,
                            onViewDetails: { viewModel.selectedTournament = tournament },
                            onManageParticipants: { viewModel.showParticipantManagement(for: tournament) },
                            onViewRevenue: { viewModel.showRevenueDetails(for: tournament) }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Upcoming Tournaments Section
    
    private var upcomingTournamentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming Tournaments")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                if !viewModel.upcomingTournaments.isEmpty {
                    Text("\(viewModel.upcomingTournaments.count) scheduled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if viewModel.upcomingTournaments.isEmpty {
                Text("No upcoming tournaments scheduled")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.upcomingTournaments) { tournament in
                        UpcomingTournamentCard(
                            tournament: tournament,
                            onEdit: { viewModel.editTournament(tournament) },
                            onCancel: { viewModel.cancelTournament(tournament) }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Completed Tournaments Section
    
    private var completedTournamentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recently Completed")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("View All") {
                    viewModel.showAllCompleted = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if viewModel.recentlyCompletedTournaments.isEmpty {
                Text("No completed tournaments")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.recentlyCompletedTournaments.prefix(3)) { tournament in
                        CompletedTournamentCard(
                            tournament: tournament,
                            onViewResults: { viewModel.showResults(for: tournament) },
                            onViewRevenue: { viewModel.showRevenueDetails(for: tournament) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct RevenueMetricView: View {
    let title: String
    let amount: Double
    let currency: String
    let changePercentage: Double?
    let isPositive: Bool
    let isCount: Bool
    let isTarget: Bool
    
    init(title: String, amount: Double, currency: String, changePercentage: Double?, isPositive: Bool, isCount: Bool = false, isTarget: Bool = false) {
        self.title = title
        self.amount = amount
        self.currency = currency
        self.changePercentage = changePercentage
        self.isPositive = isPositive
        self.isCount = isCount
        self.isTarget = isTarget
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if isCount {
                Text("\(Int(amount))")
                    .font(.title3)
                    .fontWeight(.bold)
            } else {
                Text(amount, format: .currency(code: currency))
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            if let changePercentage = changePercentage {
                HStack(spacing: 2) {
                    Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                    
                    Text(String(format: "%.1f%%", abs(changePercentage)))
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(isPositive ? .green : .red)
            } else if isTarget {
                Text("Target")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatisticView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct TournamentManagementCard: View {
    let tournament: ManagedTournament
    let onViewDetails: () -> Void
    let onManageParticipants: () -> Void
    let onViewRevenue: () -> Void
    
    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tournament.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text(tournament.format.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    TournamentStatusBadge(status: tournament.status)
                }
                
                HStack(spacing: 16) {
                    Label("\(tournament.currentParticipants)/\(tournament.maxParticipants)", systemImage: "person.3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(tournament.revenueToDate.formatted(.currency(code: tournament.currency)), systemImage: "dollarsign.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    Text(tournament.timeRemaining)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                ProgressView(value: tournament.progressPercentage)
                    .accentColor(.blue)
                
                HStack(spacing: 12) {
                    Button("Details") {
                        onViewDetails()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Participants") {
                        onManageParticipants()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Revenue") {
                        onViewRevenue()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct UpcomingTournamentCard: View {
    let tournament: ManagedTournament
    let onEdit: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tournament.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Starts \(tournament.startDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Menu {
                        Button("Edit Tournament") {
                            onEdit()
                        }
                        
                        Button("Cancel Tournament", role: .destructive) {
                            onCancel()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                HStack(spacing: 16) {
                    Label("\(tournament.currentParticipants) registered", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Label(tournament.entryFee.formatted(.currency(code: tournament.currency)), systemImage: "tag")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }
}

struct CompletedTournamentCard: View {
    let tournament: ManagedTournament
    let onViewResults: () -> Void
    let onViewRevenue: () -> Void
    
    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tournament.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Completed \(tournament.endDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
                
                HStack(spacing: 16) {
                    Label("\(tournament.currentParticipants) participants", systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(tournament.revenueToDate.formatted(.currency(code: tournament.currency)), systemImage: "dollarsign.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }
                
                HStack(spacing: 12) {
                    Button("View Results") {
                        onViewResults()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Revenue Report") {
                        onViewRevenue()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct TournamentStatusBadge: View {
    let status: TournamentStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .cornerRadius(8)
    }
}

struct EmptyStateView<ActionView: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: ActionView
    
    init(icon: String, title: String, subtitle: String, @ViewBuilder action: () -> ActionView) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            action
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Supporting Types

enum TournamentStatus: String, CaseIterable {
    case upcoming = "upcoming"
    case active = "active"
    case completed = "completed"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .active: return "Active"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var color: Color {
        switch self {
        case .upcoming: return .blue
        case .active: return .green
        case .completed: return .gray
        case .cancelled: return .red
        }
    }
}

struct ManagedTournament: Identifiable {
    let id: String
    let name: String
    let format: TournamentFormat
    let status: TournamentStatus
    let startDate: Date
    let endDate: Date
    let currentParticipants: Int
    let maxParticipants: Int
    let entryFee: Double
    let currency: String
    let revenueToDate: Double
    
    var progressPercentage: Double {
        let now = Date()
        guard startDate < endDate else { return 0 }
        
        if now < startDate { return 0 }
        if now > endDate { return 1 }
        
        let totalDuration = endDate.timeIntervalSince(startDate)
        let elapsed = now.timeIntervalSince(startDate)
        return elapsed / totalDuration
    }
    
    var timeRemaining: String {
        let now = Date()
        
        if now < startDate {
            let interval = startDate.timeIntervalSince(now)
            return "Starts in \(formatTimeInterval(interval))"
        } else if now < endDate {
            let interval = endDate.timeIntervalSince(now)
            return "Ends in \(formatTimeInterval(interval))"
        } else {
            return "Completed"
        }
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else {
            return "\(hours)h"
        }
    }
}

// MARK: - Preview

struct TournamentManagementView_Previews: PreviewProvider {
    static var previews: some View {
        TournamentManagementView()
    }
}