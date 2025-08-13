import Foundation
import Combine
import Appwrite
import os.log

// MARK: - Tenant Management Service Protocol

protocol TenantManagementServiceProtocol: AnyObject {
    // Tenant CRUD Operations
    var activeTenants: AnyPublisher<[Tenant], Never> { get }
    var tenantCount: AnyPublisher<Int, Never> { get }
    
    func createTenant(_ request: TenantCreateRequest) async throws -> Tenant
    func getTenant(id: String) async throws -> Tenant?
    func getTenant(domain: String) async throws -> Tenant?
    func updateTenant(id: String, updates: TenantUpdate) async throws -> Tenant
    func deleteTenant(id: String, transferDataTo: String?) async throws
    func suspendTenant(id: String, reason: SuspensionReason) async throws
    func reactivateTenant(id: String) async throws -> Tenant
    
    // Tenant Configuration
    func configureTenantBranding(tenantId: String, branding: TenantBranding) async throws
    func configureTenantSettings(tenantId: String, settings: TenantSettings) async throws
    func configureTenantLimits(tenantId: String, limits: TenantLimits) async throws
    func configureTenantFeatures(tenantId: String, features: [String]) async throws
    
    // Multi-tenancy & Isolation
    func validateTenantAccess(tenantId: String, userId: String) async throws -> Bool
    func getTenantContext() -> String? // Current tenant ID from context
    func setTenantContext(_ tenantId: String)
    func clearTenantContext()
    func ensureTenantIsolation(tenantId: String) async throws
    
    // Domain Management
    func addCustomDomain(tenantId: String, domain: String, sslCertificate: SSLCertificate?) async throws
    func removeCustomDomain(tenantId: String, domain: String) async throws
    func verifyDomain(tenantId: String, domain: String) async throws -> DomainVerification
    func getCustomDomains(tenantId: String) async throws -> [CustomDomain]
    
    // Tenant Analytics & Monitoring
    func getTenantMetrics(tenantId: String, period: RevenuePeriod) async throws -> TenantMetrics
    func getTenantUsage(tenantId: String, period: RevenuePeriod) async throws -> TenantUsage
    func getTenantHealthScore(tenantId: String) async throws -> TenantHealthScore
    func getAllTenantsHealth() async throws -> [TenantHealthScore]
    
    // Tenant Provisioning & Migration
    func provisionTenant(_ tenant: Tenant) async throws
    func migrateTenantData(from: String, to: String, options: MigrationOptions) async throws -> MigrationResult
    func exportTenantData(tenantId: String, format: ExportFormat) async throws -> Data
    func importTenantData(tenantId: String, data: Data, format: ExportFormat) async throws
    
    // Tenant Hierarchy & Relationships
    func createChildTenant(parentId: String, request: TenantCreateRequest) async throws -> Tenant
    func getChildTenants(parentId: String) async throws -> [Tenant]
    func transferTenant(tenantId: String, newParentId: String?) async throws
    
    // Delegate
    func setDelegate(_ delegate: TenantManagementDelegate)
    func removeDelegate(_ delegate: TenantManagementDelegate)
}

// MARK: - Tenant Management Delegate

protocol TenantManagementDelegate: AnyObject {
    func tenantDidCreate(_ tenant: Tenant)
    func tenantDidUpdate(_ tenant: Tenant)
    func tenantDidDelete(_ tenant: Tenant)
    func tenantDidSuspend(_ tenant: Tenant, reason: SuspensionReason)
    func tenantDidReactivate(_ tenant: Tenant)
    func tenantUsageDidExceedLimit(_ tenant: Tenant, limitType: LimitType, usage: Double, limit: Double)
    func tenantHealthScoreDidChange(_ tenant: Tenant, oldScore: Double, newScore: Double)
    func domainVerificationDidComplete(_ tenant: Tenant, domain: String, success: Bool)
}

// Default implementations
extension TenantManagementDelegate {
    func tenantDidCreate(_ tenant: Tenant) {}
    func tenantDidUpdate(_ tenant: Tenant) {}
    func tenantDidDelete(_ tenant: Tenant) {}
    func tenantDidSuspend(_ tenant: Tenant, reason: SuspensionReason) {}
    func tenantDidReactivate(_ tenant: Tenant) {}
    func tenantUsageDidExceedLimit(_ tenant: Tenant, limitType: LimitType, usage: Double, limit: Double) {}
    func tenantHealthScoreDidChange(_ tenant: Tenant, oldScore: Double, newScore: Double) {}
    func domainVerificationDidComplete(_ tenant: Tenant, domain: String, success: Bool) {}
}

// MARK: - Tenant Management Service Implementation

@MainActor
class TenantManagementService: NSObject, TenantManagementServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinder", category: "TenantManagement")
    
    // Published properties
    @Published private var tenants: [Tenant] = []
    @Published private var currentTenantId: String?
    
    // Combine publishers
    var activeTenants: AnyPublisher<[Tenant], Never> {
        $tenants
            .map { $0.filter { $0.status == .active } }
            .eraseToAnyPublisher()
    }
    
    var tenantCount: AnyPublisher<Int, Never> {
        activeTenants
            .map { $0.count }
            .eraseToAnyPublisher()
    }
    
    // Dependencies
    @ServiceInjected(SubscriptionServiceProtocol.self) private var subscriptionService
    @ServiceInjected(APIUsageTrackingServiceProtocol.self) private var usageService
    
    // Tenant context management
    private let tenantContextQueue = DispatchQueue(label: "tenant.context", qos: .userInitiated)
    private var tenantContextStack: [String] = []
    
    // Caching
    private var tenantCache: [String: Tenant] = [:]
    private var domainToTenantCache: [String: String] = [:]
    private let cacheExpiry: TimeInterval = 300 // 5 minutes
    
    // Delegate management
    private var delegates: [WeakTenantDelegate] = []
    
    // Health monitoring
    private var healthMonitoringTimer: Timer?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        loadTenants()
        setupHealthMonitoring()
        logger.info("TenantManagementService initialized")
    }
    
    private func loadTenants() {
        // In a real implementation, this would load from persistent storage
        tenants = [
            Tenant.sampleGolfCourse,
            Tenant.sampleEnterprise,
            Tenant.sampleStartup
        ]
        
        // Update caches
        updateTenantCaches()
    }
    
    private func updateTenantCaches() {
        tenantCache = Dictionary(uniqueKeysWithValues: tenants.map { ($0.id, $0) })
        
        // Update domain cache
        domainToTenantCache.removeAll()
        for tenant in tenants {
            if let primaryDomain = tenant.primaryDomain {
                domainToTenantCache[primaryDomain] = tenant.id
            }
            for domain in tenant.customDomains {
                domainToTenantCache[domain.domain] = tenant.id
            }
        }
    }
    
    private func setupHealthMonitoring() {
        healthMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performTenantHealthCheck()
            }
        }
    }
    
    // MARK: - Tenant CRUD Operations
    
    func createTenant(_ request: TenantCreateRequest) async throws -> Tenant {
        logger.info("Creating tenant: \(request.name)")
        
        // Validate request
        try validateTenantCreateRequest(request)
        
        // Check if domain is already taken
        if let domain = request.primaryDomain,
           try await getTenant(domain: domain) != nil {
            throw TenantError.domainAlreadyExists(domain)
        }
        
        // Create tenant
        let tenant = Tenant(
            id: UUID().uuidString,
            name: request.name,
            slug: request.slug,
            type: request.type,
            status: .active,
            primaryDomain: request.primaryDomain,
            customDomains: [],
            branding: request.branding ?? TenantBranding.default,
            settings: request.settings ?? TenantSettings.default,
            limits: request.limits ?? TenantLimits.default(for: request.type),
            features: request.features ?? [],
            parentTenantId: request.parentTenantId,
            createdAt: Date(),
            metadata: request.metadata ?? [:]
        )
        
        // Provision tenant resources
        try await provisionTenant(tenant)
        
        // Add to storage
        tenants.append(tenant)
        updateTenantCaches()
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.tenantDidCreate(tenant)
        }
        
        logger.info("Successfully created tenant: \(tenant.id)")
        return tenant
    }
    
    func getTenant(id: String) async throws -> Tenant? {
        // Check cache first
        if let cachedTenant = tenantCache[id] {
            return cachedTenant
        }
        
        return tenants.first { $0.id == id }
    }
    
    func getTenant(domain: String) async throws -> Tenant? {
        // Check domain cache first
        if let tenantId = domainToTenantCache[domain] {
            return try await getTenant(id: tenantId)
        }
        
        // Search through tenants
        return tenants.first { tenant in
            tenant.primaryDomain == domain ||
            tenant.customDomains.contains { $0.domain == domain }
        }
    }
    
    func updateTenant(id: String, updates: TenantUpdate) async throws -> Tenant {
        guard var tenant = try await getTenant(id: id) else {
            throw TenantError.tenantNotFound(id)
        }
        
        // Apply updates
        if let name = updates.name {
            tenant.name = name
        }
        
        if let status = updates.status {
            tenant.status = status
        }
        
        if let branding = updates.branding {
            tenant.branding = branding
        }
        
        if let settings = updates.settings {
            tenant.settings = settings
        }
        
        if let limits = updates.limits {
            tenant.limits = limits
        }
        
        if let features = updates.features {
            tenant.features = features
        }
        
        if let metadata = updates.metadata {
            tenant.metadata = tenant.metadata.merging(metadata) { _, new in new }
        }
        
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == id }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.tenantDidUpdate(tenant)
        }
        
        logger.info("Updated tenant: \(id)")
        return tenant
    }
    
    func deleteTenant(id: String, transferDataTo: String?) async throws {
        guard let tenant = try await getTenant(id: id) else {
            throw TenantError.tenantNotFound(id)
        }
        
        // Prevent deletion of tenants with active subscriptions
        if let subscription = try? await subscriptionService.getSubscription(id: tenant.subscriptionId ?? ""),
           subscription?.status == .active {
            throw TenantError.deletionNotAllowed("Tenant has active subscription")
        }
        
        // Transfer data if requested
        if let transferToId = transferDataTo {
            guard try await getTenant(id: transferToId) != nil else {
                throw TenantError.tenantNotFound(transferToId)
            }
            
            try await migrateTenantData(
                from: id,
                to: transferToId,
                options: MigrationOptions.dataTransfer
            )
        }
        
        // Remove from storage
        tenants.removeAll { $0.id == id }
        updateTenantCaches()
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.tenantDidDelete(tenant)
        }
        
        logger.info("Deleted tenant: \(id)")
    }
    
    func suspendTenant(id: String, reason: SuspensionReason) async throws {
        guard var tenant = try await getTenant(id: id) else {
            throw TenantError.tenantNotFound(id)
        }
        
        tenant.status = .suspended
        tenant.suspensionReason = reason
        tenant.suspendedAt = Date()
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == id }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.tenantDidSuspend(tenant, reason: reason)
        }
        
        logger.warning("Suspended tenant: \(id) - Reason: \(reason.rawValue)")
    }
    
    func reactivateTenant(id: String) async throws -> Tenant {
        guard var tenant = try await getTenant(id: id) else {
            throw TenantError.tenantNotFound(id)
        }
        
        guard tenant.status == .suspended else {
            throw TenantError.invalidStatus(tenant.status)
        }
        
        tenant.status = .active
        tenant.suspensionReason = nil
        tenant.suspendedAt = nil
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == id }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.tenantDidReactivate(tenant)
        }
        
        logger.info("Reactivated tenant: \(id)")
        return tenant
    }
    
    // MARK: - Tenant Configuration
    
    func configureTenantBranding(tenantId: String, branding: TenantBranding) async throws {
        guard var tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        tenant.branding = branding
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == tenantId }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        logger.info("Updated branding for tenant: \(tenantId)")
    }
    
    func configureTenantSettings(tenantId: String, settings: TenantSettings) async throws {
        guard var tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        tenant.settings = settings
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == tenantId }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        logger.info("Updated settings for tenant: \(tenantId)")
    }
    
    func configureTenantLimits(tenantId: String, limits: TenantLimits) async throws {
        guard var tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        tenant.limits = limits
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == tenantId }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        logger.info("Updated limits for tenant: \(tenantId)")
    }
    
    func configureTenantFeatures(tenantId: String, features: [String]) async throws {
        guard var tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        tenant.features = features
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == tenantId }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        logger.info("Updated features for tenant: \(tenantId)")
    }
    
    // MARK: - Multi-tenancy & Isolation
    
    func validateTenantAccess(tenantId: String, userId: String) async throws -> Bool {
        guard let tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        // Check if tenant is active
        guard tenant.status == .active else {
            throw TenantError.tenantNotActive(tenantId)
        }
        
        // In a real implementation, this would check user permissions
        // For now, we'll assume access is granted if tenant exists and is active
        return true
    }
    
    func getTenantContext() -> String? {
        return tenantContextQueue.sync {
            return tenantContextStack.last
        }
    }
    
    func setTenantContext(_ tenantId: String) {
        tenantContextQueue.sync {
            tenantContextStack.append(tenantId)
            currentTenantId = tenantId
        }
        logger.debug("Set tenant context: \(tenantId)")
    }
    
    func clearTenantContext() {
        tenantContextQueue.sync {
            _ = tenantContextStack.popLast()
            currentTenantId = tenantContextStack.last
        }
        logger.debug("Cleared tenant context")
    }
    
    func ensureTenantIsolation(tenantId: String) async throws {
        // Verify tenant exists and is accessible
        guard try await validateTenantAccess(tenantId: tenantId, userId: "system") else {
            throw TenantError.accessDenied(tenantId)
        }
        
        // Set tenant context for data isolation
        setTenantContext(tenantId)
        
        logger.debug("Ensured tenant isolation for: \(tenantId)")
    }
    
    // MARK: - Domain Management
    
    func addCustomDomain(tenantId: String, domain: String, sslCertificate: SSLCertificate?) async throws {
        guard var tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        // Check if domain is already in use
        if try await getTenant(domain: domain) != nil {
            throw TenantError.domainAlreadyExists(domain)
        }
        
        // Validate domain format
        guard isValidDomain(domain) else {
            throw TenantError.invalidDomain(domain)
        }
        
        let customDomain = CustomDomain(
            domain: domain,
            isVerified: false,
            verificationToken: UUID().uuidString,
            sslCertificate: sslCertificate,
            addedAt: Date()
        )
        
        tenant.customDomains.append(customDomain)
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == tenantId }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        logger.info("Added custom domain \(domain) to tenant: \(tenantId)")
    }
    
    func removeCustomDomain(tenantId: String, domain: String) async throws {
        guard var tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        tenant.customDomains.removeAll { $0.domain == domain }
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == tenantId }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        logger.info("Removed custom domain \(domain) from tenant: \(tenantId)")
    }
    
    func verifyDomain(tenantId: String, domain: String) async throws -> DomainVerification {
        guard var tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        guard let domainIndex = tenant.customDomains.firstIndex(where: { $0.domain == domain }) else {
            throw TenantError.domainNotFound(domain)
        }
        
        // Perform domain verification (simplified)
        let isVerified = await performDomainVerification(domain: domain, token: tenant.customDomains[domainIndex].verificationToken)
        
        // Update domain verification status
        tenant.customDomains[domainIndex].isVerified = isVerified
        tenant.customDomains[domainIndex].verifiedAt = isVerified ? Date() : nil
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == tenantId }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        let verification = DomainVerification(
            domain: domain,
            isVerified: isVerified,
            verifiedAt: tenant.customDomains[domainIndex].verifiedAt,
            dnsRecords: generateDNSRecords(for: domain),
            challenges: generateDomainChallenges(for: domain)
        )
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.domainVerificationDidComplete(tenant, domain: domain, success: isVerified)
        }
        
        logger.info("Domain verification for \(domain): \(isVerified ? "SUCCESS" : "FAILED")")
        return verification
    }
    
    func getCustomDomains(tenantId: String) async throws -> [CustomDomain] {
        guard let tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        return tenant.customDomains
    }
    
    // MARK: - Tenant Analytics & Monitoring
    
    func getTenantMetrics(tenantId: String, period: RevenuePeriod) async throws -> TenantMetrics {
        guard let tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        let usage = try await usageService.getCurrentUsage(tenantId: tenantId)
        
        return TenantMetrics(
            tenantId: tenantId,
            period: period,
            activeUsers: calculateActiveUsers(tenant: tenant, period: period),
            totalRevenue: calculateTenantRevenue(tenant: tenant, period: period),
            apiUsage: usage,
            storageUsage: calculateStorageUsage(tenant: tenant),
            bandwidth: calculateBandwidthUsage(tenant: tenant, period: period),
            errorRate: calculateErrorRate(tenant: tenant, period: period),
            uptime: calculateUptime(tenant: tenant, period: period),
            responseTime: calculateAverageResponseTime(tenant: tenant, period: period),
            customerSatisfaction: calculateCustomerSatisfaction(tenant: tenant, period: period)
        )
    }
    
    func getTenantUsage(tenantId: String, period: RevenuePeriod) async throws -> TenantUsage {
        guard let tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        let usage = try await usageService.getCurrentUsage(tenantId: tenantId)
        
        return TenantUsage(
            tenantId: tenantId,
            period: period,
            apiCalls: usage.apiCalls,
            storageUsed: usage.storageUsed,
            bandwidthUsed: usage.bandwidth,
            activeUsers: calculateActiveUsers(tenant: tenant, period: period),
            limits: tenant.limits,
            overages: calculateOverages(usage: usage, limits: tenant.limits),
            projectedUsage: calculateProjectedUsage(currentUsage: usage, period: period),
            generatedAt: Date()
        )
    }
    
    func getTenantHealthScore(tenantId: String) async throws -> TenantHealthScore {
        guard let tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        let metrics = try await getTenantMetrics(tenantId: tenantId, period: .monthly)
        let usage = try await getTenantUsage(tenantId: tenantId, period: .monthly)
        
        let healthScore = calculateHealthScore(tenant: tenant, metrics: metrics, usage: usage)
        
        return TenantHealthScore(
            tenantId: tenantId,
            score: healthScore.score,
            grade: healthScore.grade,
            factors: healthScore.factors,
            recommendations: healthScore.recommendations,
            trends: healthScore.trends,
            lastCalculated: Date(),
            nextCalculation: Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
        )
    }
    
    func getAllTenantsHealth() async throws -> [TenantHealthScore] {
        var healthScores: [TenantHealthScore] = []
        
        for tenant in tenants.filter({ $0.status == .active }) {
            if let healthScore = try? await getTenantHealthScore(tenantId: tenant.id) {
                healthScores.append(healthScore)
            }
        }
        
        return healthScores
    }
    
    // MARK: - Tenant Provisioning & Migration
    
    func provisionTenant(_ tenant: Tenant) async throws {
        logger.info("Provisioning tenant: \(tenant.id)")
        
        // Create tenant-specific database schema
        try await createTenantSchema(tenant)
        
        // Set up tenant-specific resources
        try await setupTenantResources(tenant)
        
        // Configure security policies
        try await configureTenantSecurity(tenant)
        
        // Initialize default data
        try await initializeTenantDefaults(tenant)
        
        logger.info("Successfully provisioned tenant: \(tenant.id)")
    }
    
    func migrateTenantData(from fromTenantId: String, to toTenantId: String, options: MigrationOptions) async throws -> MigrationResult {
        logger.info("Migrating tenant data from \(fromTenantId) to \(toTenantId)")
        
        guard let fromTenant = try await getTenant(id: fromTenantId) else {
            throw TenantError.tenantNotFound(fromTenantId)
        }
        
        guard let toTenant = try await getTenant(id: toTenantId) else {
            throw TenantError.tenantNotFound(toTenantId)
        }
        
        let migrationId = UUID().uuidString
        let startTime = Date()
        
        var migratedItems: [String] = []
        var errors: [String] = []
        
        // Migrate users
        if options.includeUsers {
            do {
                try await migrateUsers(from: fromTenant, to: toTenant)
                migratedItems.append("users")
            } catch {
                errors.append("Failed to migrate users: \(error.localizedDescription)")
            }
        }
        
        // Migrate courses
        if options.includeCourses {
            do {
                try await migrateCourses(from: fromTenant, to: toTenant)
                migratedItems.append("courses")
            } catch {
                errors.append("Failed to migrate courses: \(error.localizedDescription)")
            }
        }
        
        // Migrate bookings
        if options.includeBookings {
            do {
                try await migrateBookings(from: fromTenant, to: toTenant)
                migratedItems.append("bookings")
            } catch {
                errors.append("Failed to migrate bookings: \(error.localizedDescription)")
            }
        }
        
        // Migrate settings
        if options.includeSettings {
            do {
                try await migrateSettings(from: fromTenant, to: toTenant)
                migratedItems.append("settings")
            } catch {
                errors.append("Failed to migrate settings: \(error.localizedDescription)")
            }
        }
        
        let result = MigrationResult(
            migrationId: migrationId,
            fromTenantId: fromTenantId,
            toTenantId: toTenantId,
            status: errors.isEmpty ? .completed : .partiallyCompleted,
            startTime: startTime,
            endTime: Date(),
            migratedItems: migratedItems,
            errors: errors,
            statistics: MigrationStatistics(
                totalItems: migratedItems.count + errors.count,
                successfulItems: migratedItems.count,
                failedItems: errors.count
            )
        )
        
        logger.info("Migration completed: \(migrationId) - Status: \(result.status.rawValue)")
        return result
    }
    
    func exportTenantData(tenantId: String, format: ExportFormat) async throws -> Data {
        guard let tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        let exportData = TenantExportData(
            tenant: tenant,
            users: try await exportTenantUsers(tenant),
            courses: try await exportTenantCourses(tenant),
            bookings: try await exportTenantBookings(tenant),
            settings: tenant.settings,
            exportedAt: Date()
        )
        
        switch format {
        case .json:
            return try JSONEncoder().encode(exportData)
        case .csv:
            return try convertToCSV(exportData)
        case .excel:
            return try convertToExcel(exportData)
        case .xml:
            return try convertToXML(exportData)
        }
    }
    
    func importTenantData(tenantId: String, data: Data, format: ExportFormat) async throws {
        guard let tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        let importData: TenantExportData
        
        switch format {
        case .json:
            importData = try JSONDecoder().decode(TenantExportData.self, from: data)
        case .csv:
            importData = try parseCSV(data)
        case .excel:
            importData = try parseExcel(data)
        case .xml:
            importData = try parseXML(data)
        }
        
        // Import data sections
        try await importTenantUsers(tenant, users: importData.users)
        try await importTenantCourses(tenant, courses: importData.courses)
        try await importTenantBookings(tenant, bookings: importData.bookings)
        
        logger.info("Successfully imported data for tenant: \(tenantId)")
    }
    
    // MARK: - Tenant Hierarchy & Relationships
    
    func createChildTenant(parentId: String, request: TenantCreateRequest) async throws -> Tenant {
        guard let parentTenant = try await getTenant(id: parentId) else {
            throw TenantError.tenantNotFound(parentId)
        }
        
        // Verify parent can have child tenants
        guard parentTenant.limits.maxChildTenants > 0 else {
            throw TenantError.childTenantsNotAllowed(parentId)
        }
        
        // Check current child count
        let currentChildren = try await getChildTenants(parentId: parentId)
        guard currentChildren.count < parentTenant.limits.maxChildTenants else {
            throw TenantError.childTenantLimitReached(parentId)
        }
        
        // Create child tenant with parent reference
        var childRequest = request
        childRequest.parentTenantId = parentId
        
        // Inherit some settings from parent
        if childRequest.limits == nil {
            childRequest.limits = TenantLimits.childDefault(from: parentTenant.limits)
        }
        
        return try await createTenant(childRequest)
    }
    
    func getChildTenants(parentId: String) async throws -> [Tenant] {
        return tenants.filter { $0.parentTenantId == parentId }
    }
    
    func transferTenant(tenantId: String, newParentId: String?) async throws {
        guard var tenant = try await getTenant(id: tenantId) else {
            throw TenantError.tenantNotFound(tenantId)
        }
        
        // Validate new parent if provided
        if let newParentId = newParentId {
            guard let newParent = try await getTenant(id: newParentId) else {
                throw TenantError.tenantNotFound(newParentId)
            }
            
            // Check if new parent can accept children
            let currentChildren = try await getChildTenants(parentId: newParentId)
            guard currentChildren.count < newParent.limits.maxChildTenants else {
                throw TenantError.childTenantLimitReached(newParentId)
            }
        }
        
        tenant.parentTenantId = newParentId
        tenant.updatedAt = Date()
        
        // Update in storage
        if let index = tenants.firstIndex(where: { $0.id == tenantId }) {
            tenants[index] = tenant
        }
        updateTenantCaches()
        
        logger.info("Transferred tenant \(tenantId) to parent: \(newParentId ?? "none")")
    }
    
    // MARK: - Helper Methods
    
    private func validateTenantCreateRequest(_ request: TenantCreateRequest) throws {
        if request.name.isEmpty {
            throw TenantError.invalidRequest("Tenant name is required")
        }
        
        if request.slug.isEmpty {
            throw TenantError.invalidRequest("Tenant slug is required")
        }
        
        if !isValidSlug(request.slug) {
            throw TenantError.invalidRequest("Invalid tenant slug format")
        }
        
        // Check for duplicate slug
        if tenants.contains(where: { $0.slug == request.slug }) {
            throw TenantError.slugAlreadyExists(request.slug)
        }
    }
    
    private func isValidDomain(_ domain: String) -> Bool {
        // Basic domain validation
        let domainRegex = #"^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?(\.[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?)*$"#
        return domain.range(of: domainRegex, options: .regularExpression) != nil
    }
    
    private func isValidSlug(_ slug: String) -> Bool {
        let slugRegex = #"^[a-z0-9-]+$"#
        return slug.range(of: slugRegex, options: .regularExpression) != nil
    }
    
    private func performDomainVerification(domain: String, token: String) async -> Bool {
        // Simulate domain verification
        // In a real implementation, this would check DNS records or HTTP verification
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        return true // Simulate successful verification
    }
    
    private func generateDNSRecords(for domain: String) -> [DNSRecord] {
        return [
            DNSRecord(type: "CNAME", name: "@", value: "app.golffinder.com", ttl: 300),
            DNSRecord(type: "TXT", name: "_verification", value: UUID().uuidString, ttl: 300)
        ]
    }
    
    private func generateDomainChallenges(for domain: String) -> [DomainChallenge] {
        return [
            DomainChallenge(
                type: .dns,
                token: UUID().uuidString,
                instructions: "Add a TXT record with this token to verify domain ownership"
            ),
            DomainChallenge(
                type: .http,
                token: UUID().uuidString,
                instructions: "Place this token in a file at http://\(domain)/.well-known/golffinder-challenge"
            )
        ]
    }
    
    // Analytics calculations
    private func calculateActiveUsers(tenant: Tenant, period: RevenuePeriod) -> Int {
        // Placeholder implementation
        return Int.random(in: 10...100)
    }
    
    private func calculateTenantRevenue(tenant: Tenant, period: RevenuePeriod) -> Decimal {
        // Placeholder implementation
        return Decimal(Double.random(in: 1000...10000))
    }
    
    private func calculateStorageUsage(tenant: Tenant) -> Double {
        // Placeholder implementation
        return Double.random(in: 1...100)
    }
    
    private func calculateBandwidthUsage(tenant: Tenant, period: RevenuePeriod) -> Double {
        // Placeholder implementation
        return Double.random(in: 100...1000)
    }
    
    private func calculateErrorRate(tenant: Tenant, period: RevenuePeriod) -> Double {
        // Placeholder implementation
        return Double.random(in: 0.001...0.05)
    }
    
    private func calculateUptime(tenant: Tenant, period: RevenuePeriod) -> Double {
        // Placeholder implementation
        return Double.random(in: 0.95...0.999)
    }
    
    private func calculateAverageResponseTime(tenant: Tenant, period: RevenuePeriod) -> Double {
        // Placeholder implementation
        return Double.random(in: 50...200)
    }
    
    private func calculateCustomerSatisfaction(tenant: Tenant, period: RevenuePeriod) -> Double {
        // Placeholder implementation
        return Double.random(in: 4.0...5.0)
    }
    
    private func calculateOverages(usage: APIUsage, limits: TenantLimits) -> TenantOverages {
        return TenantOverages(
            apiCallsOverage: max(0, usage.apiCalls - limits.apiCallsPerMonth),
            storageOverage: max(0, usage.storageUsed - Double(limits.storageGB)),
            bandwidthOverage: max(0, usage.bandwidth - Double(limits.bandwidthGB)),
            usersOverage: max(0, 0 - limits.maxUsers) // Would need actual user count
        )
    }
    
    private func calculateProjectedUsage(currentUsage: APIUsage, period: RevenuePeriod) -> TenantUsageProjection {
        let growthFactor = 1.1 // 10% growth projection
        return TenantUsageProjection(
            projectedApiCalls: Int(Double(currentUsage.apiCalls) * growthFactor),
            projectedStorage: currentUsage.storageUsed * growthFactor,
            projectedBandwidth: currentUsage.bandwidth * growthFactor,
            projectedUsers: Int(Double(0) * growthFactor), // Would need actual user count
            confidence: 0.75
        )
    }
    
    private func calculateHealthScore(tenant: Tenant, metrics: TenantMetrics, usage: TenantUsage) -> (score: Double, grade: HealthGrade, factors: [HealthFactor], recommendations: [String], trends: [HealthTrend]) {
        var score = 100.0
        var factors: [HealthFactor] = []
        var recommendations: [String] = []
        
        // Factor in uptime
        let uptimeFactor = metrics.uptime * 40
        score += uptimeFactor - 40
        factors.append(HealthFactor(name: "Uptime", value: metrics.uptime, weight: 0.4, impact: uptimeFactor - 40))
        
        // Factor in error rate
        let errorFactor = (1.0 - metrics.errorRate) * 30
        score += errorFactor - 30
        factors.append(HealthFactor(name: "Error Rate", value: 1.0 - metrics.errorRate, weight: 0.3, impact: errorFactor - 30))
        
        // Factor in usage efficiency
        let usageEfficiency = 1.0 - (Double(usage.apiCalls) / Double(tenant.limits.apiCallsPerMonth))
        let usageFactor = usageEfficiency * 20
        score += usageFactor - 20
        factors.append(HealthFactor(name: "Usage Efficiency", value: usageEfficiency, weight: 0.2, impact: usageFactor - 20))
        
        // Factor in customer satisfaction
        let satisfactionFactor = (metrics.customerSatisfaction / 5.0) * 10
        score += satisfactionFactor - 10
        factors.append(HealthFactor(name: "Customer Satisfaction", value: metrics.customerSatisfaction / 5.0, weight: 0.1, impact: satisfactionFactor - 10))
        
        // Generate recommendations
        if metrics.uptime < 0.99 {
            recommendations.append("Improve system reliability to achieve 99%+ uptime")
        }
        if metrics.errorRate > 0.01 {
            recommendations.append("Reduce error rate to below 1%")
        }
        if Double(usage.apiCalls) / Double(tenant.limits.apiCallsPerMonth) > 0.8 {
            recommendations.append("Consider upgrading plan to avoid usage limits")
        }
        
        let grade: HealthGrade
        switch score {
        case 90...100: grade = .excellent
        case 80...89: grade = .good
        case 70...79: grade = .fair
        case 60...69: grade = .poor
        default: grade = .critical
        }
        
        let trends = [
            HealthTrend(metric: "uptime", direction: .stable, change: 0.001),
            HealthTrend(metric: "errors", direction: .improving, change: -0.002),
            HealthTrend(metric: "satisfaction", direction: .improving, change: 0.1)
        ]
        
        return (max(0, min(100, score)), grade, factors, recommendations, trends)
    }
    
    private func performTenantHealthCheck() async {
        logger.info("Performing tenant health check")
        
        for tenant in tenants.filter({ $0.status == .active }) {
            do {
                let healthScore = try await getTenantHealthScore(tenantId: tenant.id)
                
                // Alert on critical health scores
                if healthScore.grade == .critical {
                    logger.warning("Critical health score for tenant \(tenant.id): \(healthScore.score)")
                    // In a real implementation, this would trigger alerts
                }
                
                // Check for limit violations
                let usage = try await getTenantUsage(tenantId: tenant.id, period: .monthly)
                
                if usage.overages.apiCallsOverage > 0 {
                    notifyDelegates { delegate in
                        delegate.tenantUsageDidExceedLimit(
                            tenant,
                            limitType: .apiCalls,
                            usage: Double(usage.apiCalls),
                            limit: Double(tenant.limits.apiCallsPerMonth)
                        )
                    }
                }
                
            } catch {
                logger.error("Failed to check health for tenant \(tenant.id): \(error)")
            }
        }
    }
    
    // Migration helpers
    private func createTenantSchema(_ tenant: Tenant) async throws {
        // Placeholder for database schema creation
        logger.debug("Creating schema for tenant: \(tenant.id)")
    }
    
    private func setupTenantResources(_ tenant: Tenant) async throws {
        // Placeholder for resource provisioning
        logger.debug("Setting up resources for tenant: \(tenant.id)")
    }
    
    private func configureTenantSecurity(_ tenant: Tenant) async throws {
        // Placeholder for security configuration
        logger.debug("Configuring security for tenant: \(tenant.id)")
    }
    
    private func initializeTenantDefaults(_ tenant: Tenant) async throws {
        // Placeholder for default data initialization
        logger.debug("Initializing defaults for tenant: \(tenant.id)")
    }
    
    private func migrateUsers(from: Tenant, to: Tenant) async throws {
        // Placeholder for user migration
        logger.debug("Migrating users from \(from.id) to \(to.id)")
    }
    
    private func migrateCourses(from: Tenant, to: Tenant) async throws {
        // Placeholder for course migration
        logger.debug("Migrating courses from \(from.id) to \(to.id)")
    }
    
    private func migrateBookings(from: Tenant, to: Tenant) async throws {
        // Placeholder for booking migration
        logger.debug("Migrating bookings from \(from.id) to \(to.id)")
    }
    
    private func migrateSettings(from: Tenant, to: Tenant) async throws {
        // Placeholder for settings migration
        logger.debug("Migrating settings from \(from.id) to \(to.id)")
    }
    
    // Export/Import helpers
    private func exportTenantUsers(_ tenant: Tenant) async throws -> [TenantUser] {
        // Placeholder for user export
        return []
    }
    
    private func exportTenantCourses(_ tenant: Tenant) async throws -> [TenantCourse] {
        // Placeholder for course export
        return []
    }
    
    private func exportTenantBookings(_ tenant: Tenant) async throws -> [TenantBooking] {
        // Placeholder for booking export
        return []
    }
    
    private func importTenantUsers(_ tenant: Tenant, users: [TenantUser]) async throws {
        // Placeholder for user import
        logger.debug("Importing \(users.count) users for tenant: \(tenant.id)")
    }
    
    private func importTenantCourses(_ tenant: Tenant, courses: [TenantCourse]) async throws {
        // Placeholder for course import
        logger.debug("Importing \(courses.count) courses for tenant: \(tenant.id)")
    }
    
    private func importTenantBookings(_ tenant: Tenant, bookings: [TenantBooking]) async throws {
        // Placeholder for booking import
        logger.debug("Importing \(bookings.count) bookings for tenant: \(tenant.id)")
    }
    
    // Data format conversion helpers
    private func convertToCSV(_ data: TenantExportData) throws -> Data {
        // Simplified CSV conversion
        let csvString = "tenant_id,name,created_at\n\(data.tenant.id),\(data.tenant.name),\(data.exportedAt)"
        return csvString.data(using: .utf8) ?? Data()
    }
    
    private func convertToExcel(_ data: TenantExportData) throws -> Data {
        // Placeholder for Excel conversion
        return Data()
    }
    
    private func convertToXML(_ data: TenantExportData) throws -> Data {
        // Placeholder for XML conversion
        return Data()
    }
    
    private func parseCSV(_ data: Data) throws -> TenantExportData {
        // Placeholder for CSV parsing
        throw TenantError.importFailed("CSV parsing not implemented")
    }
    
    private func parseExcel(_ data: Data) throws -> TenantExportData {
        // Placeholder for Excel parsing
        throw TenantError.importFailed("Excel parsing not implemented")
    }
    
    private func parseXML(_ data: Data) throws -> TenantExportData {
        // Placeholder for XML parsing
        throw TenantError.importFailed("XML parsing not implemented")
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: TenantManagementDelegate) {
        delegates.removeAll { $0.delegate == nil }
        delegates.append(WeakTenantDelegate(delegate))
    }
    
    func removeDelegate(_ delegate: TenantManagementDelegate) {
        delegates.removeAll { $0.delegate === delegate }
    }
    
    private func notifyDelegates<T>(_ action: (TenantManagementDelegate) -> T) {
        delegates.forEach { weakDelegate in
            if let delegate = weakDelegate.delegate {
                _ = action(delegate)
            }
        }
        
        // Clean up nil references
        delegates.removeAll { $0.delegate == nil }
    }
}

// MARK: - Supporting Types

private struct WeakTenantDelegate {
    weak var delegate: TenantManagementDelegate?
    
    init(_ delegate: TenantManagementDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Mock Implementation

#if DEBUG
class MockTenantManagementService: TenantManagementServiceProtocol {
    @Published private var mockTenants: [Tenant] = [Tenant.sampleGolfCourse]
    
    var activeTenants: AnyPublisher<[Tenant], Never> {
        $mockTenants
            .map { $0.filter { $0.status == .active } }
            .eraseToAnyPublisher()
    }
    
    var tenantCount: AnyPublisher<Int, Never> {
        activeTenants.map { $0.count }.eraseToAnyPublisher()
    }
    
    func createTenant(_ request: TenantCreateRequest) async throws -> Tenant {
        let tenant = Tenant.sampleGolfCourse
        mockTenants.append(tenant)
        return tenant
    }
    
    func getTenant(id: String) async throws -> Tenant? {
        return mockTenants.first { $0.id == id }
    }
    
    func getTenant(domain: String) async throws -> Tenant? {
        return mockTenants.first { $0.primaryDomain == domain }
    }
    
    func updateTenant(id: String, updates: TenantUpdate) async throws -> Tenant {
        guard let index = mockTenants.firstIndex(where: { $0.id == id }) else {
            throw TenantError.tenantNotFound(id)
        }
        mockTenants[index].updatedAt = Date()
        return mockTenants[index]
    }
    
    func deleteTenant(id: String, transferDataTo: String?) async throws {}
    func suspendTenant(id: String, reason: SuspensionReason) async throws {}
    func reactivateTenant(id: String) async throws -> Tenant { return Tenant.sampleGolfCourse }
    func configureTenantBranding(tenantId: String, branding: TenantBranding) async throws {}
    func configureTenantSettings(tenantId: String, settings: TenantSettings) async throws {}
    func configureTenantLimits(tenantId: String, limits: TenantLimits) async throws {}
    func configureTenantFeatures(tenantId: String, features: [String]) async throws {}
    func validateTenantAccess(tenantId: String, userId: String) async throws -> Bool { return true }
    func getTenantContext() -> String? { return "mock-tenant" }
    func setTenantContext(_ tenantId: String) {}
    func clearTenantContext() {}
    func ensureTenantIsolation(tenantId: String) async throws {}
    func addCustomDomain(tenantId: String, domain: String, sslCertificate: SSLCertificate?) async throws {}
    func removeCustomDomain(tenantId: String, domain: String) async throws {}
    func verifyDomain(tenantId: String, domain: String) async throws -> DomainVerification { return DomainVerification.mock }
    func getCustomDomains(tenantId: String) async throws -> [CustomDomain] { return [] }
    func getTenantMetrics(tenantId: String, period: RevenuePeriod) async throws -> TenantMetrics { return TenantMetrics.mock }
    func getTenantUsage(tenantId: String, period: RevenuePeriod) async throws -> TenantUsage { return TenantUsage.mock }
    func getTenantHealthScore(tenantId: String) async throws -> TenantHealthScore { return TenantHealthScore.mock }
    func getAllTenantsHealth() async throws -> [TenantHealthScore] { return [TenantHealthScore.mock] }
    func provisionTenant(_ tenant: Tenant) async throws {}
    func migrateTenantData(from: String, to: String, options: MigrationOptions) async throws -> MigrationResult { return MigrationResult.mock }
    func exportTenantData(tenantId: String, format: ExportFormat) async throws -> Data { return Data() }
    func importTenantData(tenantId: String, data: Data, format: ExportFormat) async throws {}
    func createChildTenant(parentId: String, request: TenantCreateRequest) async throws -> Tenant { return Tenant.sampleGolfCourse }
    func getChildTenants(parentId: String) async throws -> [Tenant] { return [] }
    func transferTenant(tenantId: String, newParentId: String?) async throws {}
    func setDelegate(_ delegate: TenantManagementDelegate) {}
    func removeDelegate(_ delegate: TenantManagementDelegate) {}
}
#endif