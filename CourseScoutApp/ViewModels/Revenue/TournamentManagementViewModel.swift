import Foundation
import Combine
import SwiftUI

// MARK: - Tournament Management View Model
/// Business logic for white label tournament management
/// Revenue target: $500-2000/month per golf course

@MainActor
class TournamentManagementViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let socialChallengeService: SocialChallengeServiceProtocol
    private let revenueService: RevenueServiceProtocol
    private let securityService: SecurityServiceProtocol
    private let tenantConfigurationService: TenantConfigurationServiceProtocol
    
    // MARK: - Published Properties
    
    @Published var tournaments: [ManagedTournament] = []
    @Published var isLoading: Bool = false
    @Published var selectedTournament: ManagedTournament?
    
    // UI State
    @Published var showCreateTournament: Bool = false
    @Published var showAnalyticsDashboard: Bool = false
    @Published var showParticipantManagement: Bool = false
    @Published var showRevenueDetails: Bool = false
    @Published var showAllCompleted: Bool = false
    
    // Revenue Metrics
    @Published var totalRevenue: Double = 0
    @Published var monthlyTarget: Double = 1500 // $1,500/month default target
    @Published var currency: String = "USD"
    @Published var revenueGrowth: Double = 0
    @Published var averageRevenuePerTournament: Double = 0
    @Published var targetProgress: Double = 0
    
    // Tournament Statistics
    @Published var totalParticipants: Int = 0
    @Published var completionRate: Double = 0
    @Published var averageEntryFee: Double = 0
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var currentTenantId: String = ""
    private var revenueUpdateTimer: Timer?
    
    // MARK: - Computed Properties
    
    var activeTournaments: [ManagedTournament] {
        tournaments.filter { $0.status == .active }
    }
    
    var upcomingTournaments: [ManagedTournament] {
        tournaments.filter { $0.status == .upcoming }
            .sorted { $0.startDate < $1.startDate }
    }
    
    var recentlyCompletedTournaments: [ManagedTournament] {
        tournaments.filter { $0.status == .completed }
            .sorted { $0.endDate > $1.endDate }
    }
    
    var activeTournamentCount: Int {
        activeTournaments.count
    }
    
    // MARK: - Initialization
    
    init(
        socialChallengeService: SocialChallengeServiceProtocol = ServiceContainer.shared.socialChallengeService,
        revenueService: RevenueServiceProtocol = ServiceContainer.shared.revenueService,
        securityService: SecurityServiceProtocol = ServiceContainer.shared.securityService,
        tenantConfigurationService: TenantConfigurationServiceProtocol = ServiceContainer.shared.tenantConfigurationService
    ) {
        self.socialChallengeService = socialChallengeService
        self.revenueService = revenueService
        self.securityService = securityService
        self.tenantConfigurationService = tenantConfigurationService
        
        setupRealtimeUpdates()
        startRevenueUpdateTimer()
    }
    
    deinit {
        revenueUpdateTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func loadInitialData() async {
        isLoading = true
        
        do {
            // Load tenant configuration
            await loadTenantConfiguration()
            
            // Load tournaments
            await loadTournaments()
            
            // Load revenue metrics
            await loadRevenueMetrics()
            
            // Calculate statistics
            calculateStatistics()
            
        } catch {
            print("Error loading tournament management data: \(error)")
        }
        
        isLoading = false
    }
    
    func refreshData() async {
        await loadTournaments()
        await loadRevenueMetrics()
        calculateStatistics()
    }
    
    func exportRevenueReport() async {
        do {
            let dateRange = DateRange(
                startDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
                endDate: Date()
            )
            
            let reportData = try await revenueService.exportRevenueData(
                dateRange: dateRange,
                format: .csv
            )
            
            // In a real implementation, this would save or share the report
            print("Revenue report exported: \(reportData.count) bytes")
            
        } catch {
            print("Failed to export revenue report: \(error)")
        }
    }
    
    func showParticipantManagement(for tournament: ManagedTournament) {
        selectedTournament = tournament
        showParticipantManagement = true
    }
    
    func showRevenueDetails(for tournament: ManagedTournament) {
        selectedTournament = tournament
        showRevenueDetails = true
    }
    
    func showResults(for tournament: ManagedTournament) {
        selectedTournament = tournament
        // In a real implementation, this would show tournament results
    }
    
    func editTournament(_ tournament: ManagedTournament) {
        selectedTournament = tournament
        // In a real implementation, this would show edit tournament sheet
    }
    
    func cancelTournament(_ tournament: ManagedTournament) {
        Task {
            await performCancelTournament(tournament)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadTenantConfiguration() async {
        do {
            let tenantConfig = try await tenantConfigurationService.getCurrentTenantConfiguration()
            
            await MainActor.run {
                self.currentTenantId = tenantConfig.tenantId
                self.currency = tenantConfig.defaultCurrency ?? "USD"
                
                // Load tenant-specific revenue targets
                if let revenueTargets = tenantConfig.revenueTargets {
                    self.monthlyTarget = revenueTargets["tournament_monthly"] ?? 1500
                }
            }
        } catch {
            print("Failed to load tenant configuration: \(error)")
        }
    }
    
    private func loadTournaments() async {
        do {
            // In a real implementation, this would load tournaments from the service
            // For now, we'll generate sample data
            let sampleTournaments = generateSampleTournaments()
            
            await MainActor.run {
                self.tournaments = sampleTournaments
            }
            
        } catch {
            print("Failed to load tournaments: \(error)")
        }
    }
    
    private func loadRevenueMetrics() async {
        do {
            let revenueMetrics = try await revenueService.getRevenueMetrics(for: .monthly)
            let tenantRevenue = try await revenueService.getRevenueByTenant(
                tenantId: currentTenantId,
                period: .monthly
            )
            
            await MainActor.run {
                self.totalRevenue = Double(tenantRevenue.totalRevenue)
                self.revenueGrowth = revenueMetrics.growthRate * 100
                self.targetProgress = (self.totalRevenue / self.monthlyTarget - 1) * 100
            }
            
        } catch {
            print("Failed to load revenue metrics: \(error)")
        }
    }
    
    private func calculateStatistics() {
        totalParticipants = tournaments.reduce(0) { $0 + $1.currentParticipants }
        
        let completedTournaments = tournaments.filter { $0.status == .completed }
        completionRate = completedTournaments.isEmpty ? 0 : 
            Double(completedTournaments.count) / Double(tournaments.count)
        
        averageEntryFee = tournaments.isEmpty ? 0 :
            tournaments.reduce(0) { $0 + $1.entryFee } / Double(tournaments.count)
        
        averageRevenuePerTournament = tournaments.isEmpty ? 0 :
            tournaments.reduce(0) { $0 + $1.revenueToDate } / Double(tournaments.count)
    }
    
    private func setupRealtimeUpdates() {
        // Subscribe to tournament updates
        socialChallengeService.subscribeToTournament(tournamentId: "all")
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("Tournament subscription error: \(error)")
                }
            }, receiveValue: { [weak self] update in
                Task { @MainActor in
                    await self?.handleTournamentUpdate(update)
                }
            })
            .store(in: &cancellables)
    }
    
    private func startRevenueUpdateTimer() {
        revenueUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadRevenueMetrics()
            }
        }
    }
    
    private func handleTournamentUpdate(_ update: TournamentUpdate) async {
        // Handle real-time tournament updates
        await refreshData()
    }
    
    private func performCancelTournament(_ tournament: ManagedTournament) async {
        do {
            // Validate cancellation permissions
            try await validateCancellationPermissions(for: tournament)
            
            // Process refunds if necessary
            try await processRefunds(for: tournament)
            
            // Update tournament status
            try await updateTournamentStatus(tournament.id, status: .cancelled)
            
            // Record revenue impact
            try await recordCancellationRevenue(for: tournament)
            
            // Refresh data
            await refreshData()
            
        } catch {
            print("Failed to cancel tournament: \(error)")
        }
    }
    
    private func validateCancellationPermissions(for tournament: ManagedTournament) async throws {
        let hasPermission = try await securityService.checkPermission(
            tenantId: currentTenantId,
            userId: getCurrentUserId(),
            permission: SecurityPermission(
                id: "tournament_cancel",
                resource: .course,
                action: .delete,
                conditions: nil,
                scope: .tenant
            )
        )
        
        guard hasPermission else {
            throw TournamentManagementError.insufficientPermissions
        }
    }
    
    private func processRefunds(for tournament: ManagedTournament) async throws {
        // Calculate refund amounts
        let refundAmount = tournament.entryFee * Double(tournament.currentParticipants)
        
        // Record refund revenue event
        let refundEvent = RevenueEvent(
            id: UUID(),
            tenantId: currentTenantId,
            eventType: .refund,
            amount: Decimal(-refundAmount),
            currency: tournament.currency,
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "tournament_id": tournament.id,
                "tournament_name": tournament.name,
                "participants_refunded": String(tournament.currentParticipants),
                "reason": "tournament_cancelled"
            ],
            source: .manual
        )
        
        try await revenueService.recordRevenueEvent(refundEvent)
    }
    
    private func updateTournamentStatus(_ tournamentId: String, status: TournamentStatus) async throws {
        // In a real implementation, this would update the tournament status
        // through the social challenge service
        
        // Update local state
        if let index = tournaments.firstIndex(where: { $0.id == tournamentId }) {
            var updatedTournament = tournaments[index]
            // Create new tournament with updated status
            tournaments[index] = ManagedTournament(
                id: updatedTournament.id,
                name: updatedTournament.name,
                format: updatedTournament.format,
                status: status,
                startDate: updatedTournament.startDate,
                endDate: updatedTournament.endDate,
                currentParticipants: updatedTournament.currentParticipants,
                maxParticipants: updatedTournament.maxParticipants,
                entryFee: updatedTournament.entryFee,
                currency: updatedTournament.currency,
                revenueToDate: updatedTournament.revenueToDate
            )
        }
    }
    
    private func recordCancellationRevenue(for tournament: ManagedTournament) async throws {
        let cancellationEvent = RevenueEvent(
            id: UUID(),
            tenantId: currentTenantId,
            eventType: .chargeback,
            amount: Decimal(-tournament.revenueToDate),
            currency: tournament.currency,
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "tournament_id": tournament.id,
                "event_type": "tournament_cancellation",
                "revenue_impact": String(-tournament.revenueToDate)
            ],
            source: .manual
        )
        
        try await revenueService.recordRevenueEvent(cancellationEvent)
    }
    
    private func getCurrentUserId() -> String {
        // In a real implementation, this would get the current authenticated user ID
        return "current_user_id"
    }
    
    // MARK: - Sample Data Generation
    
    private func generateSampleTournaments() -> [ManagedTournament] {
        let formats: [TournamentFormat] = [.strokePlay, .matchPlay, .scramble, .bestBall]
        let statuses: [TournamentStatus] = [.active, .upcoming, .completed]
        
        return (1...12).map { index in
            let status = statuses[index % statuses.count]
            let format = formats[index % formats.count]
            let entryFee = Double([25, 50, 75, 100][index % 4])
            let maxParticipants = [16, 32, 50, 64][index % 4]
            let currentParticipants = status == .upcoming ? Int.random(in: 5...maxParticipants/2) : maxParticipants
            
            let startDate: Date
            let endDate: Date
            
            switch status {
            case .upcoming:
                startDate = Date().addingTimeInterval(TimeInterval.random(in: 86400...86400*7)) // 1-7 days from now
                endDate = startDate.addingTimeInterval(TimeInterval.random(in: 3600...86400)) // 1 hour to 1 day duration
            case .active:
                startDate = Date().addingTimeInterval(-TimeInterval.random(in: 0...86400*2)) // Started 0-2 days ago
                endDate = startDate.addingTimeInterval(TimeInterval.random(in: 86400...86400*3)) // 1-3 days duration
            case .completed:
                endDate = Date().addingTimeInterval(-TimeInterval.random(in: 86400...86400*30)) // Ended 1-30 days ago
                startDate = endDate.addingTimeInterval(-TimeInterval.random(in: 3600...86400*2)) // 1 hour to 2 days duration
            case .cancelled:
                startDate = Date().addingTimeInterval(-TimeInterval.random(in: 86400...86400*7))
                endDate = startDate.addingTimeInterval(86400)
            }
            
            let revenueToDate = status == .completed ? 
                entryFee * Double(currentParticipants) * 0.1 : // 10% platform fee
                (status == .active ? entryFee * Double(currentParticipants) * 0.1 * 0.5 : 0) // 50% collected for active
            
            return ManagedTournament(
                id: "tournament_\(index)",
                name: "Tournament \(index)",
                format: format,
                status: status,
                startDate: startDate,
                endDate: endDate,
                currentParticipants: currentParticipants,
                maxParticipants: maxParticipants,
                entryFee: entryFee,
                currency: currency,
                revenueToDate: revenueToDate
            )
        }
    }
}

// MARK: - Tournament Management Errors

enum TournamentManagementError: Error, LocalizedError {
    case insufficientPermissions
    case tournamentNotFound
    case invalidCancellation
    case refundProcessingFailed
    case revenueTrackingFailed
    
    var errorDescription: String? {
        switch self {
        case .insufficientPermissions:
            return "Insufficient permissions for tournament management"
        case .tournamentNotFound:
            return "Tournament not found"
        case .invalidCancellation:
            return "Tournament cannot be cancelled at this time"
        case .refundProcessingFailed:
            return "Failed to process participant refunds"
        case .revenueTrackingFailed:
            return "Failed to update revenue tracking"
        }
    }
}

// MARK: - Supporting Types

struct TournamentAnalyticsDashboard: View {
    let tournaments: [ManagedTournament]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Analytics Dashboard")
                    .font(.largeTitle)
                    .padding()
                
                Text("Tournament analytics and revenue insights would be displayed here")
                    .foregroundColor(.secondary)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

extension TournamentFormat {
    var displayName: String {
        switch self {
        case .strokePlay: return "Stroke Play"
        case .matchPlay: return "Match Play"
        case .scramble: return "Scramble"
        case .bestBall: return "Best Ball"
        }
    }
}