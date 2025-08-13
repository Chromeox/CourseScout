import Foundation
import Combine
import SwiftUI

// MARK: - Monetized Challenge View Model
/// Business logic for premium challenge creation with entry fees
/// Revenue target: $10-50 entry fees per monetized challenge

@MainActor
class MonetizedChallengeViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let socialChallengeService: SocialChallengeServiceProtocol
    private let revenueService: RevenueServiceProtocol
    private let securityService: SecurityServiceProtocol
    private let tenantConfigurationService: TenantConfigurationServiceProtocol
    
    // MARK: - Published Properties
    
    // Challenge Basics
    @Published var challengeName: String = ""
    @Published var description: String = ""
    @Published var selectedChallengeType: PremiumChallengeType = .skillChallenge
    @Published var skillLevel: SkillLevel = .intermediate
    @Published var duration: ChallengeDuration = .oneWeek
    
    // Monetization Settings
    @Published var entryFee: Double = 25.0
    @Published var currency: String = "USD"
    @Published var isPremiumChallenge: Bool = true
    @Published var premiumTier: PremiumTier = .premium
    @Published var winnerTakesAll: Bool = false
    
    // Premium Features
    @Published var realtimeLeaderboard: Bool = true
    @Published var advancedAnalytics: Bool = true
    @Published var videoHighlights: Bool = false
    @Published var coachingTips: Bool = true
    @Published var customBadges: Bool = true
    
    // Participant Settings
    @Published var maxParticipants: Int = 20
    @Published var invitationOnly: Bool = false
    @Published var requireHandicap: Bool = true
    @Published var skillLevelMatching: Bool = false
    @Published var requireAgeVerification: Bool = true
    
    // UI State
    @Published var isLoading: Bool = false
    @Published var showingAlert: Bool = false
    @Published var alertMessage: String = ""
    @Published var challengeCreated: Bool = false
    
    // Revenue Settings
    @Published var monthlyVolumeGoal: Int = 10 // 10 challenges per month
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var currentTenantId: String = ""
    private let platformFeePercentage: Double = 0.15 // 15% platform fee for premium challenges
    
    // Prize distribution (configurable based on tier)
    var prizeDistribution: [PrizeDistribution] {
        switch premiumTier {
        case .standard:
            return [
                PrizeDistribution(position: "1st Place", percentage: 0.60),
                PrizeDistribution(position: "2nd Place", percentage: 0.25),
                PrizeDistribution(position: "3rd Place", percentage: 0.15)
            ]
        case .premium, .elite:
            return [
                PrizeDistribution(position: "1st Place", percentage: 0.50),
                PrizeDistribution(position: "2nd Place", percentage: 0.30),
                PrizeDistribution(position: "3rd Place", percentage: 0.20)
            ]
        case .championship:
            return [
                PrizeDistribution(position: "1st Place", percentage: 0.40),
                PrizeDistribution(position: "2nd Place", percentage: 0.25),
                PrizeDistribution(position: "3rd Place", percentage: 0.20),
                PrizeDistribution(position: "4th Place", percentage: 0.15)
            ]
        }
    }
    
    let availablePremiumTiers: [PremiumTier] = PremiumTier.allCases
    
    // MARK: - Computed Properties
    
    var canCreateChallenge: Bool {
        !challengeName.isEmpty &&
        entryFee > 0 &&
        maxParticipants >= 4 &&
        !isLoading &&
        (!isPremiumChallenge || premiumFeaturesValid)
    }
    
    private var premiumFeaturesValid: Bool {
        // At least one premium feature must be enabled for premium challenges
        realtimeLeaderboard || advancedAnalytics || videoHighlights || coachingTips
    }
    
    var adjustedEntryFee: Double {
        isPremiumChallenge ? entryFee * premiumTier.priceMultiplier : entryFee
    }
    
    var projectedEntryFees: Double {
        adjustedEntryFee * Double(maxParticipants)
    }
    
    var platformFee: Double {
        projectedEntryFees * platformFeePercentage
    }
    
    var projectedPlatformRevenue: Double {
        platformFee
    }
    
    var calculatedPrizePool: Double {
        projectedEntryFees - platformFee
    }
    
    var netPrizePool: Double {
        winnerTakesAll ? calculatedPrizePool : calculatedPrizePool
    }
    
    var monthlyRevenueProjection: Double {
        projectedPlatformRevenue * Double(monthlyVolumeGoal)
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
            
            // Validate monetization permissions
            await validateMonetizationPermissions()
            
            // Load premium feature availability
            await loadPremiumFeatureAvailability()
            
        } catch {
            showError("Failed to load challenge setup: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func createMonetizedChallenge() async {
        guard canCreateChallenge else {
            showError("Please complete all required fields and enable at least one premium feature")
            return
        }
        
        isLoading = true
        
        do {
            // Step 1: Validate security and compliance
            try await validateChallengeCreation()
            
            // Step 2: Create monetized challenge
            let challenge = try await createSecureMonetizedChallenge()
            
            // Step 3: Set up payment processing
            try await setupChallengePaymentProcessing(for: challenge)
            
            // Step 4: Enable premium features
            try await enablePremiumFeatures(for: challenge)
            
            // Step 5: Record revenue tracking
            try await recordChallengeRevenueProjection(for: challenge)
            
            // Step 6: Set up fraud monitoring
            try await setupFraudMonitoring(for: challenge)
            
            showSuccess("Premium challenge created successfully! Payment processing enabled.")
            challengeCreated = true
            
        } catch {
            showError("Failed to create challenge: \(error.localizedDescription)")
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
        
        // Auto-enable age verification for paid challenges
        $entryFee
            .sink { [weak self] fee in
                if fee > 0 {
                    self?.requireAgeVerification = true
                }
            }
            .store(in: &cancellables)
        
        // Validate premium tier changes
        $premiumTier
            .sink { [weak self] tier in
                self?.updatePremiumFeatures(for: tier)
            }
            .store(in: &cancellables)
    }
    
    private func loadTenantConfiguration() async {
        do {
            let tenantConfig = try await tenantConfigurationService.getCurrentTenantConfiguration()
            
            await MainActor.run {
                self.currentTenantId = tenantConfig.tenantId
                self.currency = tenantConfig.defaultCurrency ?? "USD"
                
                // Load monetization settings
                if let monetizationSettings = tenantConfig.monetizationSettings {
                    self.monthlyVolumeGoal = monetizationSettings["challenge_monthly_goal"] as? Int ?? 10
                }
            }
        } catch {
            print("Warning: Could not load tenant configuration: \(error)")
        }
    }
    
    private func validateMonetizationPermissions() async {
        do {
            let hasPermission = try await securityService.checkPermission(
                tenantId: currentTenantId,
                userId: getCurrentUserId(),
                permission: SecurityPermission(
                    id: "monetized_challenge_create",
                    resource: .course,
                    action: .create,
                    conditions: nil,
                    scope: .tenant
                )
            )
            
            if !hasPermission {
                await MainActor.run {
                    showError("Insufficient permissions to create monetized challenges")
                }
            }
        } catch {
            print("Permission validation error: \(error)")
        }
    }
    
    private func loadPremiumFeatureAvailability() async {
        // In a real implementation, this would check which premium features
        // are available for the current tenant's subscription tier
        
        // For now, assume all features are available
        await MainActor.run {
            self.realtimeLeaderboard = true
            self.advancedAnalytics = true
            self.coachingTips = true
        }
    }
    
    private func validateChallengeCreation() async throws {
        // Validate tenant access
        let accessValid = try await securityService.validateTenantAccess(
            userId: getCurrentUserId(),
            tenantId: currentTenantId,
            resourceId: "monetized_challenge",
            action: .create
        )
        
        guard accessValid else {
            throw MonetizedChallengeError.tenantAccessDenied
        }
        
        // Validate age verification requirements for paid challenges
        if entryFee > 0 && !requireAgeVerification {
            throw MonetizedChallengeError.ageVerificationRequired
        }
        
        // Validate gambling regulations compliance
        if entryFee > 50.0 {
            try await validateGamblingCompliance()
        }
    }
    
    private func validateGamblingCompliance() async throws {
        // Check gambling regulations compliance for high-value challenges
        let complianceStatus = try await securityService.ensureGDPRCompliance(
            tenantId: currentTenantId,
            userId: getCurrentUserId()
        )
        
        guard complianceStatus.isCompliant else {
            throw MonetizedChallengeError.complianceViolation
        }
    }
    
    private func createSecureMonetizedChallenge() async throws -> SocialChallenge {
        let endDate = Date().addingTimeInterval(duration.timeInterval)
        
        let challenge = SocialChallenge(
            id: UUID().uuidString,
            name: challengeName,
            description: description.isEmpty ? nil : description,
            createdBy: getCurrentUserId(),
            participants: [],
            courseId: getCurrentCourseId(),
            targetScore: nil, // Will be determined by challenge type
            targetMetric: mapToTargetMetric(selectedChallengeType),
            startDate: Date(),
            endDate: endDate,
            isPublic: !invitationOnly,
            entryFee: adjustedEntryFee,
            winner: nil,
            prizes: generatePrizeStructure(),
            maxEntries: maxParticipants
        )
        
        // Create challenge through social challenge service
        let createdChallenge = try await socialChallengeService.createChallenge(challenge)
        
        // Log security event
        let securityEvent = SecurityEvent(
            id: UUID().uuidString,
            tenantId: currentTenantId,
            userId: getCurrentUserId(),
            eventType: .dataModification,
            resource: "monetized_challenge:\(createdChallenge.id)",
            action: .create,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: [
                "challenge_name": challengeName,
                "entry_fee": String(adjustedEntryFee),
                "challenge_type": selectedChallengeType.rawValue,
                "is_premium": String(isPremiumChallenge),
                "premium_tier": premiumTier.rawValue
            ],
            riskLevel: entryFee > 50 ? .medium : .low
        )
        
        try await securityService.logSecurityEvent(securityEvent)
        
        return createdChallenge
    }
    
    private func setupChallengePaymentProcessing(for challenge: SocialChallenge) async throws {
        // Set up PCI compliant payment processing for entry fees
        let revenueEvent = RevenueEvent(
            id: UUID(),
            tenantId: currentTenantId,
            eventType: .oneTimePayment,
            amount: Decimal(adjustedEntryFee),
            currency: currency,
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "challenge_id": challenge.id,
                "challenge_name": challenge.name,
                "challenge_type": selectedChallengeType.rawValue,
                "payment_type": "challenge_entry_fee",
                "is_premium": String(isPremiumChallenge),
                "premium_tier": premiumTier.rawValue
            ],
            source: .stripe
        )
        
        try await revenueService.recordRevenueEvent(revenueEvent)
    }
    
    private func enablePremiumFeatures(for challenge: SocialChallenge) async throws {
        var premiumFeatures: [String] = []
        
        if realtimeLeaderboard {
            premiumFeatures.append("realtime_leaderboard")
        }
        
        if advancedAnalytics {
            premiumFeatures.append("advanced_analytics")
        }
        
        if videoHighlights {
            premiumFeatures.append("video_highlights")
        }
        
        if coachingTips {
            premiumFeatures.append("coaching_tips")
        }
        
        if customBadges {
            premiumFeatures.append("custom_badges")
        }
        
        // In a real implementation, this would enable the features through a feature flag service
        print("Enabled premium features for challenge \(challenge.id): \(premiumFeatures)")
    }
    
    private func recordChallengeRevenueProjection(for challenge: SocialChallenge) async throws {
        // Record revenue projection for analytics
        let projectionEvent = RevenueEvent(
            id: UUID(),
            tenantId: currentTenantId,
            eventType: .oneTimePayment,
            amount: Decimal(projectedPlatformRevenue),
            currency: currency,
            timestamp: Date(),
            subscriptionId: nil,
            customerId: nil,
            invoiceId: nil,
            metadata: [
                "challenge_id": challenge.id,
                "projection_type": "challenge_revenue",
                "max_participants": String(maxParticipants),
                "platform_fee_percentage": String(platformFeePercentage),
                "premium_tier": premiumTier.rawValue,
                "duration": duration.rawValue
            ],
            source: .manual
        )
        
        try await revenueService.recordRevenueEvent(projectionEvent)
    }
    
    private func setupFraudMonitoring(for challenge: SocialChallenge) async throws {
        let securityAlert = SecurityAlert(
            id: UUID().uuidString,
            tenantId: currentTenantId,
            alertType: .suspiciousActivity,
            severity: adjustedEntryFee > 50 ? .high : .medium,
            title: "Monetized Challenge Fraud Monitoring",
            description: "Fraud prevention monitoring enabled for premium challenge: \(challenge.name)",
            affectedResources: [challenge.id],
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
                ),
                RemediationStep(
                    id: UUID().uuidString,
                    description: "Verify participant age and identity for high-value challenges",
                    priority: 2,
                    estimatedTime: 0,
                    required: adjustedEntryFee > 50,
                    completed: false,
                    completedAt: nil
                )
            ]
        )
        
        try await securityService.createSecurityAlert(securityAlert)
    }
    
    // MARK: - Validation Methods
    
    private func validateEntryFee(_ fee: Double) {
        guard fee >= 0 else {
            showError("Entry fee cannot be negative")
            return
        }
        
        if fee > 0 && fee < 5.0 {
            showError("Minimum entry fee is $5.00 for monetized challenges")
        }
        
        if fee > 100.0 {
            showError("Entry fees over $100 require additional compliance verification")
        }
    }
    
    private func updatePremiumFeatures(for tier: PremiumTier) {
        switch tier {
        case .standard:
            realtimeLeaderboard = true
            advancedAnalytics = false
            videoHighlights = false
            coachingTips = false
        case .premium:
            realtimeLeaderboard = true
            advancedAnalytics = true
            videoHighlights = false
            coachingTips = true
        case .elite:
            realtimeLeaderboard = true
            advancedAnalytics = true
            videoHighlights = true
            coachingTips = true
        case .championship:
            realtimeLeaderboard = true
            advancedAnalytics = true
            videoHighlights = true
            coachingTips = true
            customBadges = true
        }
    }
    
    // MARK: - Helper Methods
    
    private func generatePrizeStructure() -> [String] {
        if winnerTakesAll {
            return ["Winner takes all: \(netPrizePool.formatted(.currency(code: currency)))"]
        } else {
            return prizeDistribution.map { distribution in
                let amount = netPrizePool * distribution.percentage
                return "\(distribution.position): \(amount.formatted(.currency(code: currency)))"
            }
        }
    }
    
    private func mapToTargetMetric(_ challengeType: PremiumChallengeType) -> SocialChallenge.ChallengeMetric {
        switch challengeType {
        case .skillChallenge, .accuracyContest:
            return .lowestScore
        case .speedRound:
            return .fastestTime
        case .enduranceChallenge:
            return .mostHoles
        case .headToHead:
            return .headToHead
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
        challengeCreated = false
    }
    
    private func showSuccess(_ message: String) {
        alertMessage = message
        showingAlert = true
        challengeCreated = true
    }
}

// MARK: - Monetized Challenge Errors

enum MonetizedChallengeError: Error, LocalizedError {
    case insufficientPermissions
    case tenantAccessDenied
    case ageVerificationRequired
    case complianceViolation
    case invalidEntryFee
    case premiumFeatureUnavailable
    case paymentSetupFailed
    case fraudPreventionSetupFailed
    
    var errorDescription: String? {
        switch self {
        case .insufficientPermissions:
            return "Insufficient permissions to create monetized challenges"
        case .tenantAccessDenied:
            return "Access denied for current tenant"
        case .ageVerificationRequired:
            return "Age verification is required for paid challenges"
        case .complianceViolation:
            return "Challenge violates gambling regulations"
        case .invalidEntryFee:
            return "Invalid entry fee amount"
        case .premiumFeatureUnavailable:
            return "Premium feature not available for current subscription"
        case .paymentSetupFailed:
            return "Failed to setup payment processing"
        case .fraudPreventionSetupFailed:
            return "Failed to setup fraud prevention monitoring"
        }
    }
}

// MARK: - Extensions

extension SocialChallenge.ChallengeMetric {
    static let fastestTime = SocialChallenge.ChallengeMetric.lowestScore // Placeholder
    static let mostHoles = SocialChallenge.ChallengeMetric.lowestScore // Placeholder
    static let headToHead = SocialChallenge.ChallengeMetric.lowestScore // Placeholder
}