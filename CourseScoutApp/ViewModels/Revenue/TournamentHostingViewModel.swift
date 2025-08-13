import Foundation
import Combine
import SwiftUI

// MARK: - Tournament Hosting View Model
/// Business logic for secure tournament hosting with PCI compliant payment processing
/// Integrates with existing multi-tenant revenue and security infrastructure

@MainActor
class TournamentHostingViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let socialChallengeService: SocialChallengeServiceProtocol
    private let revenueService: RevenueServiceProtocol
    private let securityService: SecurityServiceProtocol
    private let tenantConfigurationService: TenantConfigurationServiceProtocol
    
    // MARK: - Published Properties
    
    @Published var tournamentName: String = ""
    @Published var description: String = ""
    @Published var startDate: Date = Date().addingTimeInterval(86400) // Tomorrow
    @Published var endDate: Date = Date().addingTimeInterval(86400 * 7) // Next week
    @Published var selectedFormat: TournamentFormat = .strokePlay
    
    // Pricing & Revenue
    @Published var entryFee: Double = 50.0
    @Published var hasPrizePool: Bool = true
    @Published var maxParticipants: Int = 50
    @Published var currency: String = "USD"
    
    // Settings
    @Published var requireHandicapVerification: Bool = true
    @Published var isPublic: Bool = true
    @Published var fraudPreventionEnabled: Bool = true
    
    // UI State
    @Published var isLoading: Bool = false
    @Published var showingAlert: Bool = false
    @Published var alertMessage: String = ""
    @Published var tournamentCreated: Bool = false
    
    // Revenue Configuration
    @Published var monthlyTournamentGoal: Int = 4
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var currentTenantId: String = ""
    private let platformFeePercentage: Double = 0.10 // 10% platform fee
    
    // Prize pool distribution (configurable)
    let prizeDistribution: [PrizeDistribution] = [
        PrizeDistribution(position: "1st Place", percentage: 0.50),
        PrizeDistribution(position: "2nd Place", percentage: 0.30),
        PrizeDistribution(position: "3rd Place", percentage: 0.20)
    ]
    
    // MARK: - Computed Properties
    
    var canCreateTournament: Bool {
        !tournamentName.isEmpty &&
        startDate < endDate &&
        entryFee > 0 &&
        maxParticipants >= 8 &&
        !isLoading
    }
    
    var calculatedPrizePool: Double {
        guard hasPrizePool else { return 0 }
        let grossRevenue = entryFee * Double(maxParticipants)
        let platformFee = grossRevenue * platformFeePercentage
        return grossRevenue - platformFee
    }
    
    var platformFee: Double {
        entryFee * platformFeePercentage
    }
    
    var netRevenuePerEntry: Double {
        entryFee * platformFeePercentage
    }
    
    var projectedGrossRevenue: Double {
        entryFee * Double(maxParticipants)
    }
    
    var projectedNetRevenue: Double {
        netRevenuePerEntry * Double(maxParticipants)
    }
    
    var monthlyRevenueTarget: Double {
        projectedNetRevenue * Double(monthlyTournamentGoal)
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
        
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    func loadInitialData() async {
        isLoading = true
        
        do {
            // Load tenant configuration
            await loadTenantConfiguration()
            
            // Validate security compliance
            await validateSecurityCompliance()
            
            // Load revenue settings
            await loadRevenueSettings()
            
        } catch {
            showError("Failed to load tournament setup: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func createTournament() async {
        guard canCreateTournament else {
            showError("Please complete all required fields")
            return
        }
        
        isLoading = true
        
        do {
            // Step 1: Validate security and compliance
            try await validateTournamentSecurity()
            
            // Step 2: Create tournament with entry fees
            let tournament = try await createSecureTournament()
            
            // Step 3: Set up payment processing
            try await setupPaymentProcessing(for: tournament)
            
            // Step 4: Record revenue tracking
            try await recordRevenueProjection(for: tournament)
            
            // Step 5: Enable fraud prevention
            try await enableFraudPrevention(for: tournament)
            
            showSuccess("Tournament created successfully! Revenue tracking enabled.")
            tournamentCreated = true
            
        } catch {
            showError("Failed to create tournament: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Validate entry fee changes
        $entryFee
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newFee in
                self?.validateEntryFee(newFee)
            }
            .store(in: &cancellables)
        
        // Validate participant limits
        $maxParticipants
            .sink { [weak self] newLimit in
                self?.validateParticipantLimit(newLimit)
            }
            .store(in: &cancellables)
        
        // Validate date ranges
        Publishers.CombineLatest($startDate, $endDate)
            .sink { [weak self] startDate, endDate in
                self?.validateDateRange(startDate: startDate, endDate: endDate)
            }
            .store(in: &cancellables)
    }
    
    private func loadTenantConfiguration() async {
        do {
            // Get current tenant configuration
            let tenantConfig = try await tenantConfigurationService.getCurrentTenantConfiguration()
            
            await MainActor.run {
                self.currentTenantId = tenantConfig.tenantId
                self.currency = tenantConfig.defaultCurrency ?? "USD"
                self.fraudPreventionEnabled = tenantConfig.securitySettings?.fraudPreventionEnabled ?? true
            }
        } catch {
            print("Warning: Could not load tenant configuration: \(error)")
        }
    }
    
    private func validateSecurityCompliance() async {
        do {
            // Validate tenant security policy
            let securityPolicy = try await securityService.getTenantSecurityPolicy(tenantId: currentTenantId)
            
            // Check for any security configuration issues
            let issues = try await securityService.validateSecurityConfiguration(tenantId: currentTenantId)
            
            if !issues.isEmpty {
                let criticalIssues = issues.filter { $0.severity == .high || $0.severity == .critical }
                if !criticalIssues.isEmpty {
                    await MainActor.run {
                        showError("Critical security issues detected. Please contact administrator.")
                    }
                }
            }
        } catch {
            print("Security validation error: \(error)")
        }
    }
    
    private func loadRevenueSettings() async {
        do {
            // Load revenue metrics to inform tournament settings
            let revenueMetrics = try await revenueService.getRevenueMetrics(for: .monthly)
            
            await MainActor.run {
                // Adjust goals based on current performance
                if revenueMetrics.growthRate > 0.2 {
                    self.monthlyTournamentGoal = max(6, self.monthlyTournamentGoal)
                }
            }
        } catch {
            print("Revenue settings load error: \(error)")
        }
    }
    
    private func validateTournamentSecurity() async throws {
        // Validate user permissions for tournament creation
        let hasPermission = try await securityService.checkPermission(
            tenantId: currentTenantId,
            userId: getCurrentUserId(),
            permission: SecurityPermission(
                id: "tournament_create",
                resource: .course,
                action: .create,
                conditions: nil,
                scope: .tenant
            )
        )
        
        guard hasPermission else {
            throw TournamentHostingError.insufficientPermissions
        }
        
        // Validate tenant data isolation
        let accessValid = try await securityService.validateTenantAccess(
            userId: getCurrentUserId(),
            tenantId: currentTenantId,
            resourceId: "tournament_hosting",
            action: .create
        )
        
        guard accessValid else {
            throw TournamentHostingError.tenantAccessDenied
        }
    }
    
    private func createSecureTournament() async throws -> TournamentChallenge {
        let tournament = TournamentChallenge(
            id: UUID().uuidString,
            name: tournamentName,
            description: description.isEmpty ? nil : description,
            creatorId: getCurrentUserId(),
            courseId: getCurrentCourseId(),
            format: mapToTournamentFormat(selectedFormat),
            structure: .singleElimination, // Default structure
            entryFee: entryFee,
            prizePool: hasPrizePool ? calculatedPrizePool : nil,
            maxParticipants: maxParticipants,
            currentParticipants: 0,
            startDate: startDate,
            endDate: endDate,
            registrationDeadline: startDate.addingTimeInterval(-3600), // 1 hour before start
            status: .upcoming,
            rules: generateTournamentRules(),
            prizes: hasPrizePool ? generatePrizeStructure() : [],
            isPublic: isPublic,
            requiresHandicap: requireHandicapVerification,
            rounds: []
        )
        
        // Create tournament through social challenge service
        let createdTournament = try await socialChallengeService.createTournament(tournament)
        
        // Log security event
        let securityEvent = SecurityEvent(
            id: UUID().uuidString,
            tenantId: currentTenantId,
            userId: getCurrentUserId(),
            eventType: .dataModification,
            resource: "tournament:\(createdTournament.id)",
            action: .create,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: [
                "tournament_name": tournamentName,
                "entry_fee": String(entryFee),
                "max_participants": String(maxParticipants)
            ],
            riskLevel: .low
        )
        
        try await securityService.logSecurityEvent(securityEvent)
        
        return createdTournament
    }
    
    private func setupPaymentProcessing(for tournament: TournamentChallenge) async throws {
        // Set up PCI compliant payment processing through revenue service
        let revenueEvent = RevenueEvent(
            id: UUID(),
            tenantId: currentTenantId,
            eventType: .setupFee,
            amount: Decimal(entryFee),
            currency: currency,
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "tournament_id": tournament.id,
                "tournament_name": tournament.name,
                "payment_type": "tournament_entry_fee"
            ],
            source: .stripe
        )
        
        try await revenueService.recordRevenueEvent(revenueEvent)
    }
    
    private func recordRevenueProjection(for tournament: TournamentChallenge) async throws {
        // Record revenue projection for analytics
        let projectionEvent = RevenueEvent(
            id: UUID(),
            tenantId: currentTenantId,
            eventType: .oneTimePayment,
            amount: Decimal(projectedNetRevenue),
            currency: currency,
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "tournament_id": tournament.id,
                "projection_type": "tournament_revenue",
                "max_participants": String(maxParticipants),
                "platform_fee_percentage": String(platformFeePercentage)
            ],
            source: .manual
        )
        
        try await revenueService.recordRevenueEvent(projectionEvent)
    }
    
    private func enableFraudPrevention(for tournament: TournamentChallenge) async throws {
        guard fraudPreventionEnabled else { return }
        
        // Set up fraud monitoring for tournament
        let securityAlert = SecurityAlert(
            id: UUID().uuidString,
            tenantId: currentTenantId,
            alertType: .suspiciousActivity,
            severity: .medium,
            title: "Tournament Fraud Monitoring Enabled",
            description: "Fraud prevention monitoring enabled for tournament: \(tournament.name)",
            affectedResources: [tournament.id],
            detectedAt: Date(),
            resolvedAt: nil,
            status: .active,
            assignedTo: nil,
            remediation: [
                RemediationStep(
                    id: UUID().uuidString,
                    description: "Monitor entry fee payments for suspicious patterns",
                    priority: 1,
                    estimatedTime: 0,
                    required: true,
                    completed: false,
                    completedAt: nil
                )
            ]
        )
        
        try await securityService.createSecurityAlert(securityAlert)
    }
    
    // MARK: - Validation Methods
    
    private func validateEntryFee(_ fee: Double) {
        guard fee > 0 else { return }
        
        // Validate minimum entry fee for PCI compliance
        if fee < 1.0 {
            showError("Minimum entry fee is $1.00 for payment processing compliance")
        }
        
        // Validate maximum entry fee for fraud prevention
        if fee > 1000.0 {
            showError("Entry fees over $1,000 require additional verification")
        }
    }
    
    private func validateParticipantLimit(_ limit: Int) {
        guard limit >= 8 else {
            showError("Minimum tournament size is 8 participants")
            return
        }
        
        if limit > 200 {
            showError("Large tournaments (200+ participants) require additional setup")
        }
    }
    
    private func validateDateRange(startDate: Date, endDate: Date) {
        guard startDate < endDate else {
            showError("End date must be after start date")
            return
        }
        
        let minimumDuration: TimeInterval = 3600 // 1 hour
        guard endDate.timeIntervalSince(startDate) >= minimumDuration else {
            showError("Tournament must be at least 1 hour long")
            return
        }
        
        let maxDuration: TimeInterval = 86400 * 30 // 30 days
        guard endDate.timeIntervalSince(startDate) <= maxDuration else {
            showError("Tournament duration cannot exceed 30 days")
            return
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateTournamentRules() -> [String] {
        var rules = [
            "Standard USGA rules apply",
            "Entry fee must be paid before tournament start",
            "Players must maintain GHIN handicap"
        ]
        
        if requireHandicapVerification {
            rules.append("Valid handicap certificate required for registration")
        }
        
        if hasPrizePool {
            rules.append("Prize distribution based on final leaderboard standings")
        }
        
        return rules
    }
    
    private func generatePrizeStructure() -> [TournamentPrize] {
        return prizeDistribution.enumerated().map { index, distribution in
            TournamentPrize(
                position: index + 1,
                amount: calculatedPrizePool * distribution.percentage,
                currency: currency,
                description: distribution.position
            )
        }
    }
    
    private func mapToTournamentFormat(_ format: TournamentFormat) -> TournamentChallenge.TournamentFormat {
        switch format {
        case .strokePlay: return .strokePlay
        case .matchPlay: return .matchPlay
        case .scramble: return .scramble
        case .bestBall: return .bestBall
        }
    }
    
    private func getCurrentUserId() -> String {
        // In a real implementation, this would get the current authenticated user ID
        return "current_user_id"
    }
    
    private func getCurrentCourseId() -> String {
        // In a real implementation, this would get the current course context
        return "current_course_id"
    }
    
    private func showError(_ message: String) {
        alertMessage = message
        showingAlert = true
        tournamentCreated = false
    }
    
    private func showSuccess(_ message: String) {
        alertMessage = message
        showingAlert = true
        tournamentCreated = true
    }
}

// MARK: - Tournament Hosting Errors

enum TournamentHostingError: Error, LocalizedError {
    case insufficientPermissions
    case tenantAccessDenied
    case invalidEntryFee
    case invalidDateRange
    case paymentSetupFailed
    case securityValidationFailed
    case fraudPreventionSetupFailed
    
    var errorDescription: String? {
        switch self {
        case .insufficientPermissions:
            return "Insufficient permissions to create tournaments"
        case .tenantAccessDenied:
            return "Access denied for current tenant"
        case .invalidEntryFee:
            return "Invalid entry fee amount"
        case .invalidDateRange:
            return "Invalid tournament date range"
        case .paymentSetupFailed:
            return "Failed to setup payment processing"
        case .securityValidationFailed:
            return "Security validation failed"
        case .fraudPreventionSetupFailed:
            return "Failed to setup fraud prevention"
        }
    }
}

// MARK: - Supporting Models

struct TournamentPrize {
    let position: Int
    let amount: Double
    let currency: String
    let description: String
}

// MARK: - Service Container Extension

extension ServiceContainer {
    var revenueService: RevenueServiceProtocol {
        // In a real implementation, this would return the actual revenue service
        fatalError("RevenueService not implemented in ServiceContainer")
    }
    
    var securityService: SecurityServiceProtocol {
        // In a real implementation, this would return the actual security service
        fatalError("SecurityService not implemented in ServiceContainer")
    }
    
    var tenantConfigurationService: TenantConfigurationServiceProtocol {
        // In a real implementation, this would return the actual tenant configuration service
        fatalError("TenantConfigurationService not implemented in ServiceContainer")
    }
}