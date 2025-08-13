import Foundation
import Combine
import Appwrite
import os.log

// MARK: - Subscription Service Protocol

protocol SubscriptionServiceProtocol: AnyObject {
    // Subscription Management
    var activeSubscriptions: AnyPublisher<[Subscription], Never> { get }
    var subscriptionCount: AnyPublisher<Int, Never> { get }
    
    // Subscription Operations
    func createSubscription(_ subscription: SubscriptionRequest) async throws -> Subscription
    func getSubscription(id: String) async throws -> Subscription?
    func updateSubscription(id: String, updates: SubscriptionUpdate) async throws -> Subscription
    func cancelSubscription(id: String, reason: CancellationReason) async throws
    func pauseSubscription(id: String, pauseDuration: TimeInterval?) async throws
    func resumeSubscription(id: String) async throws -> Subscription
    
    // Subscription Lifecycle
    func renewSubscription(id: String) async throws -> Subscription
    func upgradeSubscription(id: String, to tier: SubscriptionTier) async throws -> Subscription
    func downgradeSubscription(id: String, to tier: SubscriptionTier, effectiveDate: Date?) async throws -> Subscription
    func transferSubscription(id: String, to tenantId: String) async throws -> Subscription
    
    // Tier Management
    func getAvailableTiers(for tenantType: TenantType) async throws -> [SubscriptionTier]
    func getTierDetails(tierId: String) async throws -> SubscriptionTier?
    func getRecommendedTier(for usage: UsageProfile) async throws -> SubscriptionTier?
    
    // Billing Operations
    func processSubscriptionBilling(subscriptionId: String) async throws -> BillingResult
    func calculateProration(from: SubscriptionTier, to: SubscriptionTier, remainingDays: Int) -> Decimal
    func getUpcomingBilling(for subscriptionId: String) async throws -> [UpcomingCharge]
    func applyDiscount(subscriptionId: String, discount: Discount) async throws
    func removeDiscount(subscriptionId: String, discountId: String) async throws
    
    // Analytics
    func getSubscriptionMetrics(period: RevenuePeriod) async throws -> SubscriptionMetrics
    func getChurnAnalysis() async throws -> ChurnAnalysis
    func getSubscriptionForecast(months: Int) async throws -> [SubscriptionForecast]
    
    // Notifications
    func setDelegate(_ delegate: SubscriptionServiceDelegate)
    func removeDelegate(_ delegate: SubscriptionServiceDelegate)
}

// MARK: - Subscription Service Delegate

protocol SubscriptionServiceDelegate: AnyObject {
    func subscriptionDidCreate(_ subscription: Subscription)
    func subscriptionDidUpdate(_ subscription: Subscription)
    func subscriptionDidCancel(_ subscription: Subscription, reason: CancellationReason)
    func subscriptionWillRenew(_ subscription: Subscription, renewalDate: Date)
    func subscriptionDidFail(_ subscription: Subscription, error: SubscriptionError)
    func subscriptionDidUpgrade(_ subscription: Subscription, from: SubscriptionTier, to: SubscriptionTier)
    func subscriptionDidDowngrade(_ subscription: Subscription, from: SubscriptionTier, to: SubscriptionTier)
}

// Default implementations
extension SubscriptionServiceDelegate {
    func subscriptionDidCreate(_ subscription: Subscription) {}
    func subscriptionDidUpdate(_ subscription: Subscription) {}
    func subscriptionDidCancel(_ subscription: Subscription, reason: CancellationReason) {}
    func subscriptionWillRenew(_ subscription: Subscription, renewalDate: Date) {}
    func subscriptionDidFail(_ subscription: Subscription, error: SubscriptionError) {}
    func subscriptionDidUpgrade(_ subscription: Subscription, from: SubscriptionTier, to: SubscriptionTier) {}
    func subscriptionDidDowngrade(_ subscription: Subscription, from: SubscriptionTier, to: SubscriptionTier) {}
}

// MARK: - Subscription Service Implementation

@MainActor
class SubscriptionService: NSObject, SubscriptionServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinder", category: "SubscriptionService")
    
    // Published properties
    @Published private var subscriptions: [Subscription] = []
    @Published private var subscriptionTiers: [SubscriptionTier] = []
    
    // Combine publishers
    var activeSubscriptions: AnyPublisher<[Subscription], Never> {
        $subscriptions
            .map { $0.filter { $0.status == .active } }
            .eraseToAnyPublisher()
    }
    
    var subscriptionCount: AnyPublisher<Int, Never> {
        activeSubscriptions
            .map { $0.count }
            .eraseToAnyPublisher()
    }
    
    // Dependencies
    private let appwriteClient: Client
    private let billingService: BillingServiceProtocol?
    private let tenantService: TenantManagementServiceProtocol?
    
    // Delegate management
    private var delegates: [WeakSubscriptionDelegate] = []
    
    // Caching
    private var subscriptionCache: [String: Subscription] = [:]
    private var tierCache: [String: SubscriptionTier] = [:]
    private let cacheExpiry: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    init(appwriteClient: Client, billingService: BillingServiceProtocol? = nil, tenantService: TenantManagementServiceProtocol? = nil) {
        self.appwriteClient = appwriteClient
        self.billingService = billingService
        self.tenantService = tenantService
        super.init()
        loadSubscriptionTiers()
        setupSubscriptionMonitoring()
        logger.info("SubscriptionService initialized")
    }
    
    override convenience init() {
        self.init(appwriteClient: ServiceContainer.shared.resolve(Client.self))
    }
    
    private func loadSubscriptionTiers() {
        subscriptionTiers = [
            SubscriptionTier.starter,
            SubscriptionTier.professional,
            SubscriptionTier.enterprise,
            SubscriptionTier.custom
        ]
        
        // Cache tiers
        tierCache = Dictionary(uniqueKeysWithValues: subscriptionTiers.map { ($0.id, $0) })
    }
    
    private func setupSubscriptionMonitoring() {
        // Set up periodic subscription status checks
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performSubscriptionHealthCheck()
            }
        }
    }
    
    // MARK: - Subscription Operations
    
    func createSubscription(_ request: SubscriptionRequest) async throws -> Subscription {
        logger.info("Creating subscription for tenant: \(request.tenantId)")
        
        // Validate request
        try validateSubscriptionRequest(request)
        
        // Check tenant limits
        try await validateTenantLimits(request.tenantId)
        
        // Get tier details
        guard let tier = try await getTierDetails(tierId: request.tierId) else {
            throw SubscriptionError.invalidTier(request.tierId)
        }
        
        // Calculate billing amounts
        let billingAmount = calculateBillingAmount(tier: tier, cycle: request.billingCycle)
        
        // Create subscription
        let subscription = Subscription(
            id: UUID().uuidString,
            tenantId: request.tenantId,
            customerId: request.customerId,
            tier: tier,
            billingCycle: request.billingCycle,
            status: .active,
            currentPeriodStart: Date(),
            currentPeriodEnd: calculatePeriodEnd(from: Date(), cycle: request.billingCycle),
            createdAt: Date(),
            billingAmount: billingAmount,
            currency: request.currency ?? "USD",
            paymentMethodId: request.paymentMethodId,
            metadata: request.metadata
        )
        
        // Process initial billing
        do {
            let billingResult = try await billingService.processPayment(
                amount: billingAmount,
                currency: subscription.currency,
                paymentMethodId: subscription.paymentMethodId,
                metadata: [
                    "subscription_id": subscription.id,
                    "tenant_id": subscription.tenantId,
                    "tier": tier.name
                ]
            )
            
            var updatedSubscription = subscription
            updatedSubscription.lastBillingDate = Date()
            updatedSubscription.nextBillingDate = subscription.currentPeriodEnd
            updatedSubscription.stripeSubscriptionId = billingResult.externalId
            
            // Store subscription
            subscriptions.append(updatedSubscription)
            subscriptionCache[updatedSubscription.id] = updatedSubscription
            
            // Notify delegates
            notifyDelegates { delegate in
                delegate.subscriptionDidCreate(updatedSubscription)
            }
            
            logger.info("Successfully created subscription: \(updatedSubscription.id)")
            return updatedSubscription
            
        } catch {
            logger.error("Failed to process initial billing for subscription: \(error.localizedDescription)")
            throw SubscriptionError.billingFailed(error)
        }
    }
    
    func getSubscription(id: String) async throws -> Subscription? {
        // Check cache first
        if let cachedSubscription = subscriptionCache[id] {
            return cachedSubscription
        }
        
        // Find in current subscriptions
        if let subscription = subscriptions.first(where: { $0.id == id }) {
            subscriptionCache[id] = subscription
            return subscription
        }
        
        return nil
    }
    
    func updateSubscription(id: String, updates: SubscriptionUpdate) async throws -> Subscription {
        guard let subscription = try await getSubscription(id: id) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        
        var updatedSubscription = subscription
        
        // Apply updates
        if let newPaymentMethodId = updates.paymentMethodId {
            updatedSubscription.paymentMethodId = newPaymentMethodId
        }
        
        if let newMetadata = updates.metadata {
            updatedSubscription.metadata = subscription.metadata.merging(newMetadata) { _, new in new }
        }
        
        if let newBillingCycle = updates.billingCycle {
            updatedSubscription.billingCycle = newBillingCycle
            updatedSubscription.nextBillingDate = calculatePeriodEnd(
                from: updatedSubscription.currentPeriodStart,
                cycle: newBillingCycle
            )
        }
        
        updatedSubscription.updatedAt = Date()
        
        // Update in storage
        if let index = subscriptions.firstIndex(where: { $0.id == id }) {
            subscriptions[index] = updatedSubscription
        }
        subscriptionCache[id] = updatedSubscription
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.subscriptionDidUpdate(updatedSubscription)
        }
        
        logger.info("Updated subscription: \(id)")
        return updatedSubscription
    }
    
    func cancelSubscription(id: String, reason: CancellationReason) async throws {
        guard let subscription = try await getSubscription(id: id) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        
        var cancelledSubscription = subscription
        cancelledSubscription.status = .cancelled
        cancelledSubscription.cancelledAt = Date()
        cancelledSubscription.cancellationReason = reason
        cancelledSubscription.updatedAt = Date()
        
        // Update in storage
        if let index = subscriptions.firstIndex(where: { $0.id == id }) {
            subscriptions[index] = cancelledSubscription
        }
        subscriptionCache[id] = cancelledSubscription
        
        // Cancel in billing system
        if let stripeId = subscription.stripeSubscriptionId {
            try await billingService.cancelSubscription(stripeId)
        }
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.subscriptionDidCancel(cancelledSubscription, reason: reason)
        }
        
        logger.info("Cancelled subscription: \(id) - Reason: \(reason.rawValue)")
    }
    
    func pauseSubscription(id: String, pauseDuration: TimeInterval?) async throws {
        guard let subscription = try await getSubscription(id: id) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        
        guard subscription.status == .active else {
            throw SubscriptionError.invalidStatus(subscription.status)
        }
        
        var pausedSubscription = subscription
        pausedSubscription.status = .paused
        pausedSubscription.pausedAt = Date()
        
        if let duration = pauseDuration {
            pausedSubscription.pausedUntil = Date().addingTimeInterval(duration)
        }
        
        pausedSubscription.updatedAt = Date()
        
        // Update in storage
        if let index = subscriptions.firstIndex(where: { $0.id == id }) {
            subscriptions[index] = pausedSubscription
        }
        subscriptionCache[id] = pausedSubscription
        
        logger.info("Paused subscription: \(id)")
    }
    
    func resumeSubscription(id: String) async throws -> Subscription {
        guard let subscription = try await getSubscription(id: id) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        
        guard subscription.status == .paused else {
            throw SubscriptionError.invalidStatus(subscription.status)
        }
        
        var resumedSubscription = subscription
        resumedSubscription.status = .active
        resumedSubscription.pausedAt = nil
        resumedSubscription.pausedUntil = nil
        resumedSubscription.updatedAt = Date()
        
        // Recalculate billing dates
        resumedSubscription.currentPeriodStart = Date()
        resumedSubscription.currentPeriodEnd = calculatePeriodEnd(
            from: Date(),
            cycle: subscription.billingCycle
        )
        resumedSubscription.nextBillingDate = resumedSubscription.currentPeriodEnd
        
        // Update in storage
        if let index = subscriptions.firstIndex(where: { $0.id == id }) {
            subscriptions[index] = resumedSubscription
        }
        subscriptionCache[id] = resumedSubscription
        
        logger.info("Resumed subscription: \(id)")
        return resumedSubscription
    }
    
    // MARK: - Subscription Lifecycle
    
    func renewSubscription(id: String) async throws -> Subscription {
        guard let subscription = try await getSubscription(id: id) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        
        guard subscription.status == .active else {
            throw SubscriptionError.invalidStatus(subscription.status)
        }
        
        // Process billing for renewal
        do {
            let billingResult = try await billingService.processPayment(
                amount: subscription.billingAmount,
                currency: subscription.currency,
                paymentMethodId: subscription.paymentMethodId,
                metadata: [
                    "subscription_id": subscription.id,
                    "type": "renewal"
                ]
            )
            
            var renewedSubscription = subscription
            renewedSubscription.currentPeriodStart = subscription.currentPeriodEnd
            renewedSubscription.currentPeriodEnd = calculatePeriodEnd(
                from: renewedSubscription.currentPeriodStart,
                cycle: subscription.billingCycle
            )
            renewedSubscription.lastBillingDate = Date()
            renewedSubscription.nextBillingDate = renewedSubscription.currentPeriodEnd
            renewedSubscription.updatedAt = Date()
            
            // Update in storage
            if let index = subscriptions.firstIndex(where: { $0.id == id }) {
                subscriptions[index] = renewedSubscription
            }
            subscriptionCache[id] = renewedSubscription
            
            logger.info("Successfully renewed subscription: \(id)")
            return renewedSubscription
            
        } catch {
            // Mark subscription as past due
            var overdueSubscription = subscription
            overdueSubscription.status = .pastDue
            overdueSubscription.updatedAt = Date()
            
            if let index = subscriptions.firstIndex(where: { $0.id == id }) {
                subscriptions[index] = overdueSubscription
            }
            subscriptionCache[id] = overdueSubscription
            
            notifyDelegates { delegate in
                delegate.subscriptionDidFail(overdueSubscription, error: .billingFailed(error))
            }
            
            throw SubscriptionError.renewalFailed(error)
        }
    }
    
    func upgradeSubscription(id: String, to tier: SubscriptionTier) async throws -> Subscription {
        guard let subscription = try await getSubscription(id: id) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        
        guard tier.price > subscription.tier.price else {
            throw SubscriptionError.invalidUpgrade(from: subscription.tier.name, to: tier.name)
        }
        
        let oldTier = subscription.tier
        let prorationAmount = calculateProration(
            from: subscription.tier,
            to: tier,
            remainingDays: daysRemainingInPeriod(subscription)
        )
        
        // Process prorated billing
        if prorationAmount > 0 {
            try await billingService.processPayment(
                amount: prorationAmount,
                currency: subscription.currency,
                paymentMethodId: subscription.paymentMethodId,
                metadata: [
                    "subscription_id": subscription.id,
                    "type": "upgrade_proration",
                    "from_tier": oldTier.name,
                    "to_tier": tier.name
                ]
            )
        }
        
        var upgradedSubscription = subscription
        upgradedSubscription.tier = tier
        upgradedSubscription.billingAmount = calculateBillingAmount(tier: tier, cycle: subscription.billingCycle)
        upgradedSubscription.updatedAt = Date()
        
        // Update in storage
        if let index = subscriptions.firstIndex(where: { $0.id == id }) {
            subscriptions[index] = upgradedSubscription
        }
        subscriptionCache[id] = upgradedSubscription
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.subscriptionDidUpgrade(upgradedSubscription, from: oldTier, to: tier)
        }
        
        logger.info("Upgraded subscription: \(id) from \(oldTier.name) to \(tier.name)")
        return upgradedSubscription
    }
    
    func downgradeSubscription(id: String, to tier: SubscriptionTier, effectiveDate: Date?) async throws -> Subscription {
        guard let subscription = try await getSubscription(id: id) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        
        guard tier.price < subscription.tier.price else {
            throw SubscriptionError.invalidDowngrade(from: subscription.tier.name, to: tier.name)
        }
        
        let oldTier = subscription.tier
        var downgradedSubscription = subscription
        
        if let effectiveDate = effectiveDate, effectiveDate > Date() {
            // Schedule downgrade for future date
            downgradedSubscription.pendingTierChange = PendingTierChange(
                newTier: tier,
                effectiveDate: effectiveDate,
                changeType: .downgrade
            )
        } else {
            // Immediate downgrade
            downgradedSubscription.tier = tier
            downgradedSubscription.billingAmount = calculateBillingAmount(tier: tier, cycle: subscription.billingCycle)
        }
        
        downgradedSubscription.updatedAt = Date()
        
        // Update in storage
        if let index = subscriptions.firstIndex(where: { $0.id == id }) {
            subscriptions[index] = downgradedSubscription
        }
        subscriptionCache[id] = downgradedSubscription
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.subscriptionDidDowngrade(downgradedSubscription, from: oldTier, to: tier)
        }
        
        logger.info("Scheduled downgrade for subscription: \(id) from \(oldTier.name) to \(tier.name)")
        return downgradedSubscription
    }
    
    func transferSubscription(id: String, to tenantId: String) async throws -> Subscription {
        guard let subscription = try await getSubscription(id: id) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        
        // Validate target tenant
        guard try await tenantService.getTenant(id: tenantId) != nil else {
            throw SubscriptionError.tenantNotFound(tenantId)
        }
        
        var transferredSubscription = subscription
        transferredSubscription.tenantId = tenantId
        transferredSubscription.updatedAt = Date()
        
        // Update in storage
        if let index = subscriptions.firstIndex(where: { $0.id == id }) {
            subscriptions[index] = transferredSubscription
        }
        subscriptionCache[id] = transferredSubscription
        
        logger.info("Transferred subscription: \(id) to tenant: \(tenantId)")
        return transferredSubscription
    }
    
    // MARK: - Tier Management
    
    func getAvailableTiers(for tenantType: TenantType) async throws -> [SubscriptionTier] {
        return subscriptionTiers.filter { tier in
            tier.availableForTenantTypes.contains(tenantType)
        }
    }
    
    func getTierDetails(tierId: String) async throws -> SubscriptionTier? {
        return tierCache[tierId]
    }
    
    func getRecommendedTier(for usage: UsageProfile) async throws -> SubscriptionTier? {
        // Analyze usage patterns and recommend appropriate tier
        for tier in subscriptionTiers.sorted(by: { $0.price < $1.price }) {
            if usage.apiCallsPerMonth <= tier.limits.apiCallsPerMonth &&
               usage.storageGB <= tier.limits.storageGB &&
               usage.usersCount <= tier.limits.maxUsers {
                return tier
            }
        }
        
        // If no standard tier fits, recommend custom
        return subscriptionTiers.first { $0.id == SubscriptionTier.custom.id }
    }
    
    // MARK: - Billing Operations
    
    func processSubscriptionBilling(subscriptionId: String) async throws -> BillingResult {
        guard let subscription = try await getSubscription(id: subscriptionId) else {
            throw SubscriptionError.subscriptionNotFound(subscriptionId)
        }
        
        return try await billingService.processPayment(
            amount: subscription.billingAmount,
            currency: subscription.currency,
            paymentMethodId: subscription.paymentMethodId,
            metadata: [
                "subscription_id": subscription.id,
                "tenant_id": subscription.tenantId
            ]
        )
    }
    
    func calculateProration(from: SubscriptionTier, to: SubscriptionTier, remainingDays: Int) -> Decimal {
        let fromDaily = from.price / 30
        let toDaily = to.price / 30
        let difference = toDaily - fromDaily
        
        return difference * Decimal(remainingDays)
    }
    
    func getUpcomingBilling(for subscriptionId: String) async throws -> [UpcomingCharge] {
        guard let subscription = try await getSubscription(id: subscriptionId) else {
            throw SubscriptionError.subscriptionNotFound(subscriptionId)
        }
        
        var upcomingCharges: [UpcomingCharge] = []
        
        // Regular subscription charge
        upcomingCharges.append(UpcomingCharge(
            id: UUID().uuidString,
            amount: subscription.billingAmount,
            currency: subscription.currency,
            description: "Subscription renewal - \(subscription.tier.name)",
            dueDate: subscription.nextBillingDate ?? subscription.currentPeriodEnd,
            type: .subscription
        ))
        
        // Usage-based charges
        if let usage = try? await usageService.getCurrentUsage(tenantId: subscription.tenantId) {
            let overage = calculateUsageOverage(subscription: subscription, usage: usage)
            if overage.amount > 0 {
                upcomingCharges.append(overage)
            }
        }
        
        return upcomingCharges
    }
    
    func applyDiscount(subscriptionId: String, discount: Discount) async throws {
        guard var subscription = try await getSubscription(id: subscriptionId) else {
            throw SubscriptionError.subscriptionNotFound(subscriptionId)
        }
        
        if subscription.discounts == nil {
            subscription.discounts = []
        }
        
        subscription.discounts?.append(discount)
        subscription.updatedAt = Date()
        
        // Recalculate billing amount with discount
        let discountedAmount = calculateDiscountedAmount(
            originalAmount: subscription.billingAmount,
            discounts: subscription.discounts ?? []
        )
        
        subscription.billingAmount = discountedAmount
        
        // Update in storage
        if let index = subscriptions.firstIndex(where: { $0.id == subscriptionId }) {
            subscriptions[index] = subscription
        }
        subscriptionCache[subscriptionId] = subscription
        
        logger.info("Applied discount to subscription: \(subscriptionId)")
    }
    
    func removeDiscount(subscriptionId: String, discountId: String) async throws {
        guard var subscription = try await getSubscription(id: subscriptionId) else {
            throw SubscriptionError.subscriptionNotFound(subscriptionId)
        }
        
        subscription.discounts?.removeAll { $0.id == discountId }
        subscription.updatedAt = Date()
        
        // Recalculate billing amount without discount
        let originalAmount = calculateBillingAmount(tier: subscription.tier, cycle: subscription.billingCycle)
        let discountedAmount = calculateDiscountedAmount(
            originalAmount: originalAmount,
            discounts: subscription.discounts ?? []
        )
        
        subscription.billingAmount = discountedAmount
        
        // Update in storage
        if let index = subscriptions.firstIndex(where: { $0.id == subscriptionId }) {
            subscriptions[index] = subscription
        }
        subscriptionCache[subscriptionId] = subscription
        
        logger.info("Removed discount from subscription: \(subscriptionId)")
    }
    
    // MARK: - Analytics
    
    func getSubscriptionMetrics(period: RevenuePeriod) async throws -> SubscriptionMetrics {
        let activeSubscriptions = subscriptions.filter { $0.status == .active }
        
        return SubscriptionMetrics(
            totalSubscriptions: subscriptions.count,
            activeSubscriptions: activeSubscriptions.count,
            newSubscriptions: getNewSubscriptionsCount(period: period),
            cancelledSubscriptions: getCancelledSubscriptionsCount(period: period),
            churnRate: calculateChurnRate(period: period),
            averageRevenuePerUser: calculateARPU(subscriptions: activeSubscriptions),
            lifetimeValue: calculateLTV(subscriptions: activeSubscriptions),
            subscriptionsByTier: getSubscriptionsByTier(),
            retentionRate: calculateRetentionRate(period: period),
            upgradeRate: calculateUpgradeRate(period: period),
            downgradeRate: calculateDowngradeRate(period: period)
        )
    }
    
    func getChurnAnalysis() async throws -> ChurnAnalysis {
        let cancelledSubscriptions = subscriptions.filter { $0.status == .cancelled }
        
        let churnReasons = Dictionary(grouping: cancelledSubscriptions, by: { $0.cancellationReason ?? .other })
            .mapValues { $0.count }
        
        let churnByTier = Dictionary(grouping: cancelledSubscriptions, by: { $0.tier.name })
            .mapValues { $0.count }
        
        return ChurnAnalysis(
            totalChurned: cancelledSubscriptions.count,
            churnRate: calculateChurnRate(period: .monthly),
            churnReasons: churnReasons,
            churnByTier: churnByTier,
            averageLifespan: calculateAverageLifespan(cancelledSubscriptions),
            predictedChurn: predictChurnRisk(),
            retentionStrategies: generateRetentionStrategies()
        )
    }
    
    func getSubscriptionForecast(months: Int) async throws -> [SubscriptionForecast] {
        var forecasts: [SubscriptionForecast] = []
        
        for month in 1...months {
            let forecastDate = Calendar.current.date(byAdding: .month, value: month, to: Date()) ?? Date()
            
            let forecast = SubscriptionForecast(
                month: forecastDate,
                predictedSubscriptions: predictSubscriptionCount(month: month),
                predictedRevenue: predictSubscriptionRevenue(month: month),
                predictedChurn: predictChurnCount(month: month),
                confidence: calculateForecastConfidence(month: month)
            )
            
            forecasts.append(forecast)
        }
        
        return forecasts
    }
    
    // MARK: - Helper Methods
    
    private func validateSubscriptionRequest(_ request: SubscriptionRequest) throws {
        if request.tenantId.isEmpty {
            throw SubscriptionError.invalidRequest("Tenant ID is required")
        }
        
        if request.tierId.isEmpty {
            throw SubscriptionError.invalidRequest("Tier ID is required")
        }
        
        if request.customerId.isEmpty {
            throw SubscriptionError.invalidRequest("Customer ID is required")
        }
        
        if request.paymentMethodId.isEmpty {
            throw SubscriptionError.invalidRequest("Payment method ID is required")
        }
    }
    
    private func validateTenantLimits(_ tenantId: String) async throws {
        // Check if tenant has reached subscription limits
        let tenantSubscriptions = subscriptions.filter { 
            $0.tenantId == tenantId && $0.status == .active 
        }
        
        if tenantSubscriptions.count >= 10 { // Max 10 active subscriptions per tenant
            throw SubscriptionError.subscriptionLimitReached(tenantId)
        }
    }
    
    private func calculateBillingAmount(tier: SubscriptionTier, cycle: BillingCycle) -> Decimal {
        switch cycle {
        case .monthly:
            return tier.price
        case .quarterly:
            return tier.price * 3 * Decimal(0.95) // 5% discount
        case .yearly:
            return tier.price * 12 * Decimal(0.85) // 15% discount
        }
    }
    
    private func calculatePeriodEnd(from start: Date, cycle: BillingCycle) -> Date {
        let calendar = Calendar.current
        
        switch cycle {
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: start) ?? start
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: start) ?? start
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: start) ?? start
        }
    }
    
    private func daysRemainingInPeriod(_ subscription: Subscription) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: Date(), to: subscription.currentPeriodEnd).day ?? 0
    }
    
    private func calculateUsageOverage(subscription: Subscription, usage: APIUsage) -> UpcomingCharge {
        let tier = subscription.tier
        var overageAmount: Decimal = 0
        
        // API calls overage
        if usage.apiCalls > tier.limits.apiCallsPerMonth {
            let overage = usage.apiCalls - tier.limits.apiCallsPerMonth
            overageAmount += Decimal(overage) * tier.overageRates.apiCallRate
        }
        
        // Storage overage
        if usage.storageUsed > tier.limits.storageGB {
            let overage = usage.storageUsed - tier.limits.storageGB
            overageAmount += Decimal(overage) * tier.overageRates.storageRate
        }
        
        return UpcomingCharge(
            id: UUID().uuidString,
            amount: overageAmount,
            currency: subscription.currency,
            description: "Usage overage",
            dueDate: subscription.nextBillingDate ?? subscription.currentPeriodEnd,
            type: .usage
        )
    }
    
    private func calculateDiscountedAmount(originalAmount: Decimal, discounts: [Discount]) -> Decimal {
        var discountedAmount = originalAmount
        
        for discount in discounts {
            switch discount.type {
            case .percentage:
                discountedAmount = discountedAmount * (1 - discount.value / 100)
            case .fixed:
                discountedAmount = max(0, discountedAmount - discount.value)
            }
        }
        
        return discountedAmount
    }
    
    // Analytics helper methods
    private func getNewSubscriptionsCount(period: RevenuePeriod) -> Int {
        let startDate = getStartDate(for: period)
        return subscriptions.filter { $0.createdAt >= startDate }.count
    }
    
    private func getCancelledSubscriptionsCount(period: RevenuePeriod) -> Int {
        let startDate = getStartDate(for: period)
        return subscriptions.filter { 
            $0.status == .cancelled && 
            $0.cancelledAt ?? Date.distantPast >= startDate 
        }.count
    }
    
    private func calculateChurnRate(period: RevenuePeriod) -> Double {
        let startDate = getStartDate(for: period)
        let totalAtStart = subscriptions.filter { $0.createdAt < startDate && $0.status != .cancelled }.count
        let churned = getCancelledSubscriptionsCount(period: period)
        
        guard totalAtStart > 0 else { return 0 }
        return Double(churned) / Double(totalAtStart)
    }
    
    private func calculateARPU(subscriptions: [Subscription]) -> Decimal {
        let totalRevenue = subscriptions.reduce(Decimal(0)) { $0 + $1.billingAmount }
        return subscriptions.isEmpty ? 0 : totalRevenue / Decimal(subscriptions.count)
    }
    
    private func calculateLTV(subscriptions: [Subscription]) -> Decimal {
        // Simplified LTV calculation
        let arpu = calculateARPU(subscriptions: subscriptions)
        let averageLifespan = Decimal(24) // 24 months average
        return arpu * averageLifespan
    }
    
    private func getSubscriptionsByTier() -> [String: Int] {
        return Dictionary(grouping: subscriptions.filter { $0.status == .active }, by: { $0.tier.name })
            .mapValues { $0.count }
    }
    
    private func calculateRetentionRate(period: RevenuePeriod) -> Double {
        // Implementation for retention rate calculation
        return 0.85 // Placeholder
    }
    
    private func calculateUpgradeRate(period: RevenuePeriod) -> Double {
        // Implementation for upgrade rate calculation
        return 0.15 // Placeholder
    }
    
    private func calculateDowngradeRate(period: RevenuePeriod) -> Double {
        // Implementation for downgrade rate calculation
        return 0.05 // Placeholder
    }
    
    private func getStartDate(for period: RevenuePeriod) -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch period {
        case .daily:
            return calendar.startOfDay(for: now)
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .monthly:
            return calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .quarterly:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .yearly:
            return calendar.dateInterval(of: .year, for: now)?.start ?? now
        case .custom:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        }
    }
    
    private func calculateAverageLifespan(_ subscriptions: [Subscription]) -> TimeInterval {
        let lifespans = subscriptions.compactMap { subscription in
            guard let cancelledAt = subscription.cancelledAt else { return nil }
            return cancelledAt.timeIntervalSince(subscription.createdAt)
        }
        
        guard !lifespans.isEmpty else { return 0 }
        return lifespans.reduce(0, +) / Double(lifespans.count)
    }
    
    private func predictChurnRisk() -> [String: Double] {
        // Simplified churn prediction
        return [
            "high_risk": 0.15,
            "medium_risk": 0.25,
            "low_risk": 0.60
        ]
    }
    
    private func generateRetentionStrategies() -> [String] {
        return [
            "Personalized onboarding program",
            "Proactive customer success outreach",
            "Usage-based recommendations",
            "Loyalty rewards program",
            "Feature adoption campaigns"
        ]
    }
    
    private func predictSubscriptionCount(month: Int) -> Int {
        // Simple growth prediction
        let currentCount = subscriptions.filter { $0.status == .active }.count
        let growthRate = 0.05 // 5% monthly growth
        return Int(Double(currentCount) * pow(1 + growthRate, Double(month)))
    }
    
    private func predictSubscriptionRevenue(month: Int) -> Decimal {
        let predictedCount = predictSubscriptionCount(month: month)
        let avgRevenue = calculateARPU(subscriptions: subscriptions.filter { $0.status == .active })
        return Decimal(predictedCount) * avgRevenue
    }
    
    private func predictChurnCount(month: Int) -> Int {
        let predictedCount = predictSubscriptionCount(month: month)
        let churnRate = calculateChurnRate(period: .monthly)
        return Int(Double(predictedCount) * churnRate)
    }
    
    private func calculateForecastConfidence(month: Int) -> Double {
        // Confidence decreases with time
        return max(0.5, 0.95 - (Double(month) * 0.05))
    }
    
    private func performSubscriptionHealthCheck() async {
        logger.info("Performing subscription health check")
        
        let now = Date()
        
        for subscription in subscriptions {
            // Check for overdue renewals
            if subscription.status == .active &&
               subscription.nextBillingDate ?? subscription.currentPeriodEnd < now {
                
                do {
                    _ = try await renewSubscription(id: subscription.id)
                } catch {
                    logger.error("Failed to renew subscription \(subscription.id): \(error)")
                }
            }
            
            // Check for pending tier changes
            if let pendingChange = subscription.pendingTierChange,
               pendingChange.effectiveDate <= now {
                
                // Apply pending tier change
                // Implementation would depend on change type
                logger.info("Applying pending tier change for subscription: \(subscription.id)")
            }
            
            // Resume paused subscriptions if applicable
            if subscription.status == .paused,
               let pausedUntil = subscription.pausedUntil,
               pausedUntil <= now {
                
                do {
                    _ = try await resumeSubscription(id: subscription.id)
                } catch {
                    logger.error("Failed to resume subscription \(subscription.id): \(error)")
                }
            }
        }
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: SubscriptionServiceDelegate) {
        delegates.removeAll { $0.delegate == nil }
        delegates.append(WeakSubscriptionDelegate(delegate))
    }
    
    func removeDelegate(_ delegate: SubscriptionServiceDelegate) {
        delegates.removeAll { $0.delegate === delegate }
    }
    
    private func notifyDelegates<T>(_ action: (SubscriptionServiceDelegate) -> T) {
        delegates.forEach { weakDelegate in
            if let delegate = weakDelegate.delegate {
                _ = action(delegate)
            }
        }
        
        // Clean up nil references
        delegates.removeAll { $0.delegate == nil }
    }
}

// MARK: - Supporting Types and Extensions

private struct WeakSubscriptionDelegate {
    weak var delegate: SubscriptionServiceDelegate?
    
    init(_ delegate: SubscriptionServiceDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Mock Implementation

#if DEBUG
class MockSubscriptionService: SubscriptionServiceProtocol {
    @Published private var mockSubscriptions: [Subscription] = []
    
    var activeSubscriptions: AnyPublisher<[Subscription], Never> {
        $mockSubscriptions
            .map { $0.filter { $0.status == .active } }
            .eraseToAnyPublisher()
    }
    
    var subscriptionCount: AnyPublisher<Int, Never> {
        activeSubscriptions
            .map { $0.count }
            .eraseToAnyPublisher()
    }
    
    func createSubscription(_ subscription: SubscriptionRequest) async throws -> Subscription {
        let newSubscription = Subscription.mock
        mockSubscriptions.append(newSubscription)
        return newSubscription
    }
    
    func getSubscription(id: String) async throws -> Subscription? {
        return mockSubscriptions.first { $0.id == id }
    }
    
    func updateSubscription(id: String, updates: SubscriptionUpdate) async throws -> Subscription {
        guard let index = mockSubscriptions.firstIndex(where: { $0.id == id }) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        mockSubscriptions[index].updatedAt = Date()
        return mockSubscriptions[index]
    }
    
    func cancelSubscription(id: String, reason: CancellationReason) async throws {
        if let index = mockSubscriptions.firstIndex(where: { $0.id == id }) {
            mockSubscriptions[index].status = .cancelled
            mockSubscriptions[index].cancelledAt = Date()
            mockSubscriptions[index].cancellationReason = reason
        }
    }
    
    func pauseSubscription(id: String, pauseDuration: TimeInterval?) async throws {
        if let index = mockSubscriptions.firstIndex(where: { $0.id == id }) {
            mockSubscriptions[index].status = .paused
            mockSubscriptions[index].pausedAt = Date()
        }
    }
    
    func resumeSubscription(id: String) async throws -> Subscription {
        guard let index = mockSubscriptions.firstIndex(where: { $0.id == id }) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        mockSubscriptions[index].status = .active
        mockSubscriptions[index].pausedAt = nil
        return mockSubscriptions[index]
    }
    
    func renewSubscription(id: String) async throws -> Subscription {
        guard let index = mockSubscriptions.firstIndex(where: { $0.id == id }) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        mockSubscriptions[index].lastBillingDate = Date()
        return mockSubscriptions[index]
    }
    
    func upgradeSubscription(id: String, to tier: SubscriptionTier) async throws -> Subscription {
        guard let index = mockSubscriptions.firstIndex(where: { $0.id == id }) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        mockSubscriptions[index].tier = tier
        return mockSubscriptions[index]
    }
    
    func downgradeSubscription(id: String, to tier: SubscriptionTier, effectiveDate: Date?) async throws -> Subscription {
        guard let index = mockSubscriptions.firstIndex(where: { $0.id == id }) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        mockSubscriptions[index].tier = tier
        return mockSubscriptions[index]
    }
    
    func transferSubscription(id: String, to tenantId: String) async throws -> Subscription {
        guard let index = mockSubscriptions.firstIndex(where: { $0.id == id }) else {
            throw SubscriptionError.subscriptionNotFound(id)
        }
        mockSubscriptions[index].tenantId = tenantId
        return mockSubscriptions[index]
    }
    
    func getAvailableTiers(for tenantType: TenantType) async throws -> [SubscriptionTier] {
        return [SubscriptionTier.starter, SubscriptionTier.professional, SubscriptionTier.enterprise]
    }
    
    func getTierDetails(tierId: String) async throws -> SubscriptionTier? {
        switch tierId {
        case "starter": return SubscriptionTier.starter
        case "professional": return SubscriptionTier.professional
        case "enterprise": return SubscriptionTier.enterprise
        default: return nil
        }
    }
    
    func getRecommendedTier(for usage: UsageProfile) async throws -> SubscriptionTier? {
        return SubscriptionTier.professional
    }
    
    func processSubscriptionBilling(subscriptionId: String) async throws -> BillingResult {
        return BillingResult.mock
    }
    
    func calculateProration(from: SubscriptionTier, to: SubscriptionTier, remainingDays: Int) -> Decimal {
        return Decimal(remainingDays) * (to.price - from.price) / 30
    }
    
    func getUpcomingBilling(for subscriptionId: String) async throws -> [UpcomingCharge] {
        return [UpcomingCharge.mock]
    }
    
    func applyDiscount(subscriptionId: String, discount: Discount) async throws {}
    
    func removeDiscount(subscriptionId: String, discountId: String) async throws {}
    
    func getSubscriptionMetrics(period: RevenuePeriod) async throws -> SubscriptionMetrics {
        return SubscriptionMetrics.mock
    }
    
    func getChurnAnalysis() async throws -> ChurnAnalysis {
        return ChurnAnalysis.mock
    }
    
    func getSubscriptionForecast(months: Int) async throws -> [SubscriptionForecast] {
        return [SubscriptionForecast.mock]
    }
    
    func setDelegate(_ delegate: SubscriptionServiceDelegate) {}
    func removeDelegate(_ delegate: SubscriptionServiceDelegate) {}
}
#endif