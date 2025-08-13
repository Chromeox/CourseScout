import Foundation
import SwiftUI
import Combine
import os.log

// MARK: - Consent View Model

@MainActor
final class ConsentViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var showSuccess: Bool = false
    @Published var successMessage: String = ""
    
    // MARK: - Consent Items
    
    @Published var consentItems: [ConsentItem] = []
    @Published var consentResponses: [String: ConsentResponse] = [:]
    @Published var isProcessingConsent: Bool = false
    
    // MARK: - Required Consents
    
    @Published var requiredConsents: Set<String> = []
    @Published var optionalConsents: Set<String> = []
    @Published var allRequiredConsented: Bool = false
    
    // MARK: - GDPR Compliance
    
    @Published var gdprApplicable: Bool = false
    @Published var showGDPRDetails: Bool = false
    @Published var dataProcessingPurposes: [DataProcessingPurpose] = []
    @Published var dataRetentionPolicies: [DataRetentionPolicy] = []
    @Published var thirdPartySharing: [ThirdPartySharing] = []
    
    // MARK: - User Rights
    
    @Published var userRights: [UserRight] = []
    @Published var showRightsExplanation: Bool = false
    @Published var dataSubjectRequests: [DataSubjectRequest] = []
    
    // MARK: - Consent History
    
    @Published var consentHistory: [ConsentHistoryEntry] = []
    @Published var showConsentHistory: Bool = false
    @Published var canWithdrawConsent: Bool = true
    
    // MARK: - Marketing & Analytics
    
    @Published var marketingConsent: MarketingConsent?
    @Published var analyticsConsent: AnalyticsConsent?
    @Published var cookieConsent: CookieConsent?
    @Published var showMarketingDetails: Bool = false
    @Published var showAnalyticsDetails: Bool = false
    @Published var showCookieDetails: Bool = false
    
    // MARK: - Tenant-Specific Consent
    
    @Published var tenantConsentRequirements: TenantConsentRequirements?
    @Published var customConsentItems: [CustomConsentItem] = []
    @Published var brandedConsentFlow: BrandedConsentFlow?
    
    // MARK: - Geolocation & Jurisdiction
    
    @Published var userLocation: UserLocation?
    @Published var applicableLaws: [ApplicableLaw] = []
    @Published var jurisdictionSpecificConsents: [ConsentItem] = []
    
    // MARK: - Dependencies
    
    private let consentService: ConsentManagementServiceProtocol
    private let userProfileService: UserProfileServiceProtocol
    private let tenantConfigurationService: TenantConfigurationServiceProtocol
    private let geolocationService: GeolocationServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderApp", category: "ConsentViewModel")
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let consentVersion = "2024.1.0"
    private var currentUserId: String?
    private var currentTenantId: String?
    
    // MARK: - Computed Properties
    
    var allRequiredConsentsProvided: Bool {
        return requiredConsents.allSatisfy { consentId in
            consentResponses[consentId]?.granted == true
        }
    }
    
    var consentCompletionPercentage: Double {
        guard !consentItems.isEmpty else { return 0.0 }
        let totalItems = consentItems.count
        let completedItems = consentItems.filter { item in
            consentResponses[item.id] != nil
        }.count
        return Double(completedItems) / Double(totalItems)
    }
    
    var canProceed: Bool {
        return allRequiredConsentsProvided && !isLoading
    }
    
    var gdprConsentSummary: GDPRConsentSummary {
        let essential = consentResponses.values.filter { $0.category == .essential && $0.granted }.count
        let functional = consentResponses.values.filter { $0.category == .functional && $0.granted }.count
        let analytics = consentResponses.values.filter { $0.category == .analytics && $0.granted }.count
        let marketing = consentResponses.values.filter { $0.category == .marketing && $0.granted }.count
        
        return GDPRConsentSummary(
            essentialConsents: essential,
            functionalConsents: functional,
            analyticsConsents: analytics,
            marketingConsents: marketing,
            totalConsents: consentResponses.count,
            lastUpdated: Date()
        )
    }
    
    // MARK: - Initialization
    
    init(
        consentService: ConsentManagementServiceProtocol,
        userProfileService: UserProfileServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol,
        geolocationService: GeolocationServiceProtocol
    ) {
        self.consentService = consentService
        self.userProfileService = userProfileService
        self.tenantConfigurationService = tenantConfigurationService
        self.geolocationService = geolocationService
        
        setupObservers()
        logger.info("ConsentViewModel initialized")
    }
    
    // MARK: - Setup Methods
    
    private func setupObservers() {
        // Monitor consent responses changes
        $consentResponses
            .sink { [weak self] responses in
                self?.evaluateConsentStatus()
            }
            .store(in: &cancellables)
        
        // Monitor required consents changes
        $requiredConsents
            .sink { [weak self] _ in
                self?.evaluateConsentStatus()
            }
            .store(in: &cancellables)
    }
    
    private func evaluateConsentStatus() {
        allRequiredConsented = allRequiredConsentsProvided
    }
    
    // MARK: - Consent Loading
    
    func loadConsentRequirements(for userId: String, tenantId: String? = nil) {
        self.currentUserId = userId
        self.currentTenantId = tenantId
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showError = false
            }
            
            do {
                // Determine user location for jurisdiction-specific consents
                let location = try await geolocationService.getUserLocation()
                await MainActor.run {
                    self.userLocation = location
                    self.gdprApplicable = location.isEURegion || location.isUKRegion
                }
                
                // Load applicable laws and regulations
                let laws = try await consentService.getApplicableLaws(for: location)
                
                // Load base consent requirements
                let baseConsents = try await consentService.getBaseConsentRequirements(
                    version: consentVersion,
                    jurisdiction: location.jurisdiction
                )
                
                // Load tenant-specific consents if applicable
                var tenantConsents: [ConsentItem] = []
                var tenantRequirements: TenantConsentRequirements?
                var brandedFlow: BrandedConsentFlow?
                
                if let tenantId = tenantId {
                    tenantConsents = try await consentService.getTenantConsentRequirements(tenantId: tenantId)
                    tenantRequirements = try await tenantConfigurationService.getTenantConsentRequirements(tenantId: tenantId)
                    brandedFlow = try await tenantConfigurationService.getBrandedConsentFlow(tenantId: tenantId)
                }
                
                // Load user's existing consent history
                let history = try await consentService.getConsentHistory(userId: userId)
                
                await MainActor.run {
                    self.applicableLaws = laws
                    self.consentItems = baseConsents + tenantConsents
                    self.tenantConsentRequirements = tenantRequirements
                    self.brandedConsentFlow = brandedFlow
                    self.consentHistory = history
                    
                    // Categorize consents
                    self.categorizeConsents()
                    
                    // Load existing consent responses
                    self.loadExistingConsentResponses(from: history)
                    
                    self.isLoading = false
                }
                
                // Load detailed GDPR information if applicable
                if gdprApplicable {
                    await loadGDPRDetails()
                }
                
                logger.info("Loaded consent requirements for user: \(userId)")
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to load consent requirements: \(error.localizedDescription)"
                }
                
                logger.error("Failed to load consent requirements: \(error.localizedDescription)")
            }
        }
    }
    
    private func categorizeConsents() {
        requiredConsents = Set(consentItems.filter { $0.isRequired }.map { $0.id })
        optionalConsents = Set(consentItems.filter { !$0.isRequired }.map { $0.id })
    }
    
    private func loadExistingConsentResponses(from history: [ConsentHistoryEntry]) {
        // Load the most recent consent response for each item
        for item in consentItems {
            if let latestEntry = history
                .filter({ $0.consentId == item.id })
                .sorted(by: { $0.timestamp > $1.timestamp })
                .first {
                
                consentResponses[item.id] = ConsentResponse(
                    consentId: item.id,
                    granted: latestEntry.granted,
                    timestamp: latestEntry.timestamp,
                    version: latestEntry.version,
                    category: item.category,
                    ipAddress: latestEntry.ipAddress,
                    userAgent: latestEntry.userAgent
                )
            }
        }
    }
    
    private func loadGDPRDetails() async {
        do {
            let purposes = try await consentService.getDataProcessingPurposes()
            let policies = try await consentService.getDataRetentionPolicies()
            let sharing = try await consentService.getThirdPartySharing()
            let rights = try await consentService.getUserRights()
            
            await MainActor.run {
                self.dataProcessingPurposes = purposes
                self.dataRetentionPolicies = policies
                self.thirdPartySharing = sharing
                self.userRights = rights
            }
            
        } catch {
            logger.error("Failed to load GDPR details: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Consent Management
    
    func grantConsent(for consentId: String) {
        guard let item = consentItems.first(where: { $0.id == consentId }) else { return }
        
        let response = ConsentResponse(
            consentId: consentId,
            granted: true,
            timestamp: Date(),
            version: consentVersion,
            category: item.category,
            ipAddress: getCurrentIPAddress(),
            userAgent: getCurrentUserAgent()
        )
        
        consentResponses[consentId] = response
        
        logger.debug("Granted consent for: \(consentId)")
    }
    
    func revokeConsent(for consentId: String) {
        guard let item = consentItems.first(where: { $0.id == consentId }) else { return }
        
        // Check if consent can be revoked
        if item.isRequired {
            showError = true
            errorMessage = "This consent is required and cannot be revoked while using the service"
            return
        }
        
        let response = ConsentResponse(
            consentId: consentId,
            granted: false,
            timestamp: Date(),
            version: consentVersion,
            category: item.category,
            ipAddress: getCurrentIPAddress(),
            userAgent: getCurrentUserAgent()
        )
        
        consentResponses[consentId] = response
        
        logger.debug("Revoked consent for: \(consentId)")
    }
    
    func updateConsentResponse(for consentId: String, granted: Bool) {
        if granted {
            grantConsent(for: consentId)
        } else {
            revokeConsent(for: consentId)
        }
    }
    
    // MARK: - Consent Submission
    
    func submitConsentResponses() {
        guard let userId = currentUserId else {
            showError = true
            errorMessage = "User ID not available"
            return
        }
        
        guard allRequiredConsentsProvided else {
            showError = true
            errorMessage = "Please provide all required consents to continue"
            return
        }
        
        Task {
            await MainActor.run {
                self.isProcessingConsent = true
                self.showError = false
            }
            
            do {
                // Prepare consent submission
                let submission = ConsentSubmission(
                    userId: userId,
                    tenantId: currentTenantId,
                    responses: Array(consentResponses.values),
                    version: consentVersion,
                    submissionTimestamp: Date(),
                    ipAddress: getCurrentIPAddress(),
                    userAgent: getCurrentUserAgent(),
                    geolocation: userLocation
                )
                
                // Submit consents
                let result = try await consentService.submitConsentResponses(submission)
                
                // Update user profile with consent preferences
                if let preferences = buildUserPreferences() {
                    try await userProfileService.updateUserPreferences(
                        userId: userId,
                        preferences: preferences
                    )
                }
                
                await MainActor.run {
                    self.isProcessingConsent = false
                    self.showSuccess = true
                    self.successMessage = "Consent preferences saved successfully"
                }
                
                logger.info("Successfully submitted consent responses for user: \(userId)")
                
            } catch {
                await MainActor.run {
                    self.isProcessingConsent = false
                    self.showError = true
                    self.errorMessage = "Failed to save consent preferences: \(error.localizedDescription)"
                }
                
                logger.error("Failed to submit consent responses: \(error.localizedDescription)")
            }
        }
    }
    
    private func buildUserPreferences() -> UserPreferences? {
        let marketingOptOut = !(consentResponses.values.first { $0.category == .marketing }?.granted ?? false)
        let analyticsOptOut = !(consentResponses.values.first { $0.category == .analytics }?.granted ?? false)
        
        return UserPreferences(
            language: "en", // Would be determined from user context
            timezone: TimeZone.current.identifier,
            notifications: NotificationPreferences(
                emailNotifications: consentResponses.values.contains { $0.category == .notifications && $0.granted },
                pushNotifications: consentResponses.values.contains { $0.category == .notifications && $0.granted },
                smsNotifications: consentResponses.values.contains { $0.category == .notifications && $0.granted },
                securityAlerts: true // Always enabled for security
            ),
            privacy: PrivacySettings(
                profileVisibility: .restricted, // Conservative default
                dataProcessingConsent: consentResponses.values.contains { $0.category == .essential && $0.granted },
                analyticsOptOut: analyticsOptOut,
                marketingOptOut: marketingOptOut
            )
        )
    }
    
    // MARK: - Consent Withdrawal
    
    func withdrawAllConsent() {
        guard let userId = currentUserId else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                try await consentService.withdrawAllConsent(userId: userId)
                
                await MainActor.run {
                    // Update local state to reflect withdrawal
                    for (consentId, _) in self.consentResponses {
                        if !self.requiredConsents.contains(consentId) {
                            self.revokeConsent(for: consentId)
                        }
                    }
                    
                    self.isLoading = false
                    self.showSuccess = true
                    self.successMessage = "All optional consents have been withdrawn"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to withdraw consents: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Data Subject Requests
    
    func submitDataSubjectRequest(_ request: DataSubjectRequest) {
        guard let userId = currentUserId else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                try await consentService.submitDataSubjectRequest(
                    userId: userId,
                    request: request
                )
                
                await MainActor.run {
                    self.isLoading = false
                    self.showSuccess = true
                    self.successMessage = "Your request has been submitted and will be processed within 30 days"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to submit request: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Consent History
    
    func loadDetailedConsentHistory() {
        guard let userId = currentUserId else { return }
        
        Task {
            do {
                let detailedHistory = try await consentService.getDetailedConsentHistory(userId: userId)
                
                await MainActor.run {
                    self.consentHistory = detailedHistory
                    self.showConsentHistory = true
                }
                
            } catch {
                await MainActor.run {
                    self.showError = true
                    self.errorMessage = "Failed to load consent history: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Marketing Consent Details
    
    func loadMarketingConsentDetails() {
        Task {
            do {
                let details = try await consentService.getMarketingConsentDetails()
                
                await MainActor.run {
                    self.marketingConsent = details
                    self.showMarketingDetails = true
                }
                
            } catch {
                logger.error("Failed to load marketing consent details: \(error.localizedDescription)")
            }
        }
    }
    
    func loadAnalyticsConsentDetails() {
        Task {
            do {
                let details = try await consentService.getAnalyticsConsentDetails()
                
                await MainActor.run {
                    self.analyticsConsent = details
                    self.showAnalyticsDetails = true
                }
                
            } catch {
                logger.error("Failed to load analytics consent details: \(error.localizedDescription)")
            }
        }
    }
    
    func loadCookieConsentDetails() {
        Task {
            do {
                let details = try await consentService.getCookieConsentDetails()
                
                await MainActor.run {
                    self.cookieConsent = details
                    self.showCookieDetails = true
                }
                
            } catch {
                logger.error("Failed to load cookie consent details: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentIPAddress() -> String {
        // Implementation would get actual IP address
        return "127.0.0.1"
    }
    
    private func getCurrentUserAgent() -> String {
        return "GolfFinderApp/1.0 iOS/\(UIDevice.current.systemVersion)"
    }
    
    func getConsentItem(by id: String) -> ConsentItem? {
        return consentItems.first { $0.id == id }
    }
    
    func getConsentResponse(for id: String) -> ConsentResponse? {
        return consentResponses[id]
    }
    
    func isConsentGranted(for id: String) -> Bool {
        return consentResponses[id]?.granted ?? false
    }
    
    func isConsentRequired(for id: String) -> Bool {
        return requiredConsents.contains(id)
    }
    
    // MARK: - UI Actions
    
    func showGDPRInformation() {
        showGDPRDetails = true
    }
    
    func showUserRights() {
        showRightsExplanation = true
    }
    
    func dismissError() {
        showError = false
        errorMessage = ""
    }
    
    func dismissSuccess() {
        showSuccess = false
        successMessage = ""
    }
    
    func dismissGDPRDetails() {
        showGDPRDetails = false
    }
    
    func dismissRightsExplanation() {
        showRightsExplanation = false
    }
    
    func dismissConsentHistory() {
        showConsentHistory = false
    }
    
    func dismissMarketingDetails() {
        showMarketingDetails = false
    }
    
    func dismissAnalyticsDetails() {
        showAnalyticsDetails = false
    }
    
    func dismissCookieDetails() {
        showCookieDetails = false
    }
}

// MARK: - Supporting Types

struct ConsentItem {
    let id: String
    let title: String
    let description: String
    let detailedDescription: String?
    let purpose: String
    let legalBasis: LegalBasis
    let category: ConsentCategory
    let isRequired: Bool
    let canWithdraw: Bool
    let dataTypes: [DataType]
    let retentionPeriod: String?
    let thirdParties: [String]
    let version: String
    let lastUpdated: Date
    
    enum LegalBasis: String, CaseIterable {
        case consent = "consent"
        case contract = "contract"
        case legalObligation = "legal_obligation"
        case vitalInterests = "vital_interests"
        case publicTask = "public_task"
        case legitimateInterests = "legitimate_interests"
        
        var displayName: String {
            switch self {
            case .consent: return "Consent"
            case .contract: return "Contract Performance"
            case .legalObligation: return "Legal Obligation"
            case .vitalInterests: return "Vital Interests"
            case .publicTask: return "Public Task"
            case .legitimateInterests: return "Legitimate Interests"
            }
        }
    }
}

enum ConsentCategory: String, CaseIterable {
    case essential = "essential"
    case functional = "functional"
    case analytics = "analytics"
    case marketing = "marketing"
    case notifications = "notifications"
    case personalisation = "personalisation"
    case social = "social"
    
    var displayName: String {
        switch self {
        case .essential: return "Essential"
        case .functional: return "Functional"
        case .analytics: return "Analytics"
        case .marketing: return "Marketing"
        case .notifications: return "Notifications"
        case .personalisation: return "Personalisation"
        case .social: return "Social Media"
        }
    }
    
    var description: String {
        switch self {
        case .essential:
            return "Required for the basic functionality of the service"
        case .functional:
            return "Enhance your experience with additional features"
        case .analytics:
            return "Help us understand how you use our service"
        case .marketing:
            return "Allow us to send you promotional content"
        case .notifications:
            return "Send you important updates and alerts"
        case .personalisation:
            return "Customize content and recommendations for you"
        case .social:
            return "Enable social media sharing and integration"
        }
    }
}

enum DataType: String, CaseIterable {
    case personalIdentifiers = "personal_identifiers"
    case contactInformation = "contact_information"
    case demographicData = "demographic_data"
    case locationData = "location_data"
    case deviceInformation = "device_information"
    case usageData = "usage_data"
    case preferenceData = "preference_data"
    case transactionData = "transaction_data"
    case healthData = "health_data"
    case biometricData = "biometric_data"
    
    var displayName: String {
        switch self {
        case .personalIdentifiers: return "Personal Identifiers"
        case .contactInformation: return "Contact Information"
        case .demographicData: return "Demographic Data"
        case .locationData: return "Location Data"
        case .deviceInformation: return "Device Information"
        case .usageData: return "Usage Data"
        case .preferenceData: return "Preference Data"
        case .transactionData: return "Transaction Data"
        case .healthData: return "Health Data"
        case .biometricData: return "Biometric Data"
        }
    }
}

struct ConsentResponse {
    let consentId: String
    let granted: Bool
    let timestamp: Date
    let version: String
    let category: ConsentCategory
    let ipAddress: String
    let userAgent: String
}

struct ConsentSubmission {
    let userId: String
    let tenantId: String?
    let responses: [ConsentResponse]
    let version: String
    let submissionTimestamp: Date
    let ipAddress: String
    let userAgent: String
    let geolocation: UserLocation?
}

struct ConsentHistoryEntry {
    let id: String
    let consentId: String
    let granted: Bool
    let timestamp: Date
    let version: String
    let ipAddress: String
    let userAgent: String
    let method: String // "user_action", "automatic", "admin"
}

struct DataProcessingPurpose {
    let id: String
    let title: String
    let description: String
    let legalBasis: ConsentItem.LegalBasis
    let dataTypes: [DataType]
    let processingActivities: [String]
    let retentionPeriod: String
    let isActive: Bool
}

struct DataRetentionPolicy {
    let dataType: DataType
    let retentionPeriod: String
    let retentionReason: String
    let deletionProcess: String
    let exceptions: [String]
}

struct ThirdPartySharing {
    let partner: String
    let purpose: String
    let dataTypes: [DataType]
    let legalBasis: ConsentItem.LegalBasis
    let location: String
    let safeguards: [String]
    let optOut: Bool
}

struct UserRight {
    let type: RightType
    let title: String
    let description: String
    let howToExercise: String
    let processingTime: String
    let isAvailable: Bool
    
    enum RightType: String, CaseIterable {
        case access = "access"
        case rectification = "rectification"
        case erasure = "erasure"
        case portability = "portability"
        case restriction = "restriction"
        case objection = "objection"
        case withdraw = "withdraw"
        
        var displayName: String {
            switch self {
            case .access: return "Right of Access"
            case .rectification: return "Right to Rectification"
            case .erasure: return "Right to Erasure"
            case .portability: return "Right to Data Portability"
            case .restriction: return "Right to Restriction"
            case .objection: return "Right to Object"
            case .withdraw: return "Right to Withdraw Consent"
            }
        }
    }
}

struct DataSubjectRequest {
    let type: UserRight.RightType
    let description: String
    let specificData: String?
    let reason: String?
    let contactMethod: ContactMethod
    let urgency: Urgency
    
    enum ContactMethod: String, CaseIterable {
        case email = "email"
        case phone = "phone"
        case post = "post"
        case inApp = "in_app"
    }
    
    enum Urgency: String, CaseIterable {
        case low = "low"
        case normal = "normal"
        case high = "high"
        case urgent = "urgent"
    }
}

struct UserLocation {
    let country: String
    let region: String?
    let jurisdiction: String
    let isEURegion: Bool
    let isUKRegion: Bool
    let isCCPAApplicable: Bool
    let applicableRegulations: [String]
}

struct ApplicableLaw {
    let name: String
    let jurisdiction: String
    let description: String
    let requirements: [String]
    let userRights: [UserRight.RightType]
    let isActive: Bool
}

struct TenantConsentRequirements {
    let customConsents: [CustomConsentItem]
    let additionalLegalBases: [ConsentItem.LegalBasis]
    let customRetentionPolicies: [DataRetentionPolicy]
    let additionalUserRights: [UserRight]
    let brandingConfiguration: ConsentBrandingConfiguration
}

struct CustomConsentItem {
    let id: String
    let title: String
    let description: String
    let category: ConsentCategory
    let isRequired: Bool
    let legalBasis: ConsentItem.LegalBasis
    let customFields: [String: String]
}

struct BrandedConsentFlow {
    let logoURL: URL?
    let primaryColor: String
    let secondaryColor: String
    let customCSS: String?
    let welcomeText: String?
    let footerText: String?
    let customTermsURL: URL?
    let customPrivacyURL: URL?
}

struct ConsentBrandingConfiguration {
    let useCustomBranding: Bool
    let brandColors: [String: String]
    let customTexts: [String: String]
    let logoURL: URL?
    let customStyling: String?
}

struct GDPRConsentSummary {
    let essentialConsents: Int
    let functionalConsents: Int
    let analyticsConsents: Int
    let marketingConsents: Int
    let totalConsents: Int
    let lastUpdated: Date
}

struct MarketingConsent {
    let emailMarketing: Bool
    let smsMarketing: Bool
    let pushNotifications: Bool
    let personalizedOffers: Bool
    let thirdPartyMarketing: Bool
    let frequency: MarketingFrequency
    let categories: [MarketingCategory]
    
    enum MarketingFrequency: String, CaseIterable {
        case daily = "daily"
        case weekly = "weekly"
        case monthly = "monthly"
        case occasional = "occasional"
        
        var displayName: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .occasional: return "Occasional"
            }
        }
    }
    
    enum MarketingCategory: String, CaseIterable {
        case productUpdates = "product_updates"
        case specialOffers = "special_offers"
        case newsAndTips = "news_and_tips"
        case events = "events"
        case surveys = "surveys"
        
        var displayName: String {
            switch self {
            case .productUpdates: return "Product Updates"
            case .specialOffers: return "Special Offers"
            case .newsAndTips: return "News & Tips"
            case .events: return "Events"
            case .surveys: return "Surveys"
            }
        }
    }
}

struct AnalyticsConsent {
    let usageAnalytics: Bool
    let performanceAnalytics: Bool
    let errorReporting: Bool
    let userBehaviorTracking: Bool
    let crossDeviceTracking: Bool
    let thirdPartyAnalytics: [String]
    let dataRetentionPeriod: String
}

struct CookieConsent {
    let essentialCookies: Bool
    let functionalCookies: Bool
    let analyticsCookies: Bool
    let marketingCookies: Bool
    let thirdPartyCookies: [ThirdPartyCookie]
    let cookieLifetime: [String: String]
    
    struct ThirdPartyCookie {
        let provider: String
        let purpose: String
        let category: ConsentCategory
        let optOut: Bool
    }
}

// MARK: - Service Protocols

protocol ConsentManagementServiceProtocol {
    func getBaseConsentRequirements(version: String, jurisdiction: String) async throws -> [ConsentItem]
    func getTenantConsentRequirements(tenantId: String) async throws -> [ConsentItem]
    func getApplicableLaws(for location: UserLocation) async throws -> [ApplicableLaw]
    func getConsentHistory(userId: String) async throws -> [ConsentHistoryEntry]
    func getDetailedConsentHistory(userId: String) async throws -> [ConsentHistoryEntry]
    func submitConsentResponses(_ submission: ConsentSubmission) async throws -> ConsentSubmissionResult
    func withdrawAllConsent(userId: String) async throws
    func submitDataSubjectRequest(userId: String, request: DataSubjectRequest) async throws
    func getDataProcessingPurposes() async throws -> [DataProcessingPurpose]
    func getDataRetentionPolicies() async throws -> [DataRetentionPolicy]
    func getThirdPartySharing() async throws -> [ThirdPartySharing]
    func getUserRights() async throws -> [UserRight]
    func getMarketingConsentDetails() async throws -> MarketingConsent
    func getAnalyticsConsentDetails() async throws -> AnalyticsConsent
    func getCookieConsentDetails() async throws -> CookieConsent
}

protocol GeolocationServiceProtocol {
    func getUserLocation() async throws -> UserLocation
}

struct ConsentSubmissionResult {
    let success: Bool
    let submissionId: String
    let timestamp: Date
    let errors: [String]
}

// MARK: - Extensions

extension TenantConfigurationServiceProtocol {
    func getTenantConsentRequirements(tenantId: String) async throws -> TenantConsentRequirements {
        // Implementation would fetch tenant-specific consent requirements
        return TenantConsentRequirements(
            customConsents: [],
            additionalLegalBases: [],
            customRetentionPolicies: [],
            additionalUserRights: [],
            brandingConfiguration: ConsentBrandingConfiguration(
                useCustomBranding: false,
                brandColors: [:],
                customTexts: [:],
                logoURL: nil,
                customStyling: nil
            )
        )
    }
    
    func getBrandedConsentFlow(tenantId: String) async throws -> BrandedConsentFlow {
        // Implementation would fetch tenant branding for consent flow
        return BrandedConsentFlow(
            logoURL: nil,
            primaryColor: "#007AFF",
            secondaryColor: "#5856D6",
            customCSS: nil,
            welcomeText: nil,
            footerText: nil,
            customTermsURL: nil,
            customPrivacyURL: nil
        )
    }
}

// MARK: - Preview Support

extension ConsentViewModel {
    static var preview: ConsentViewModel {
        let mockConsent = MockConsentManagementService()
        let mockProfile = ServiceContainer.shared.resolve(UserProfileServiceProtocol.self)!
        let mockTenant = ServiceContainer.shared.resolve(TenantConfigurationServiceProtocol.self)!
        let mockGeo = MockGeolocationService()
        
        return ConsentViewModel(
            consentService: mockConsent,
            userProfileService: mockProfile,
            tenantConfigurationService: mockTenant,
            geolocationService: mockGeo
        )
    }
}

// MARK: - Mock Services

class MockConsentManagementService: ConsentManagementServiceProtocol {
    func getBaseConsentRequirements(version: String, jurisdiction: String) async throws -> [ConsentItem] {
        return [
            ConsentItem(
                id: "essential_cookies",
                title: "Essential Cookies",
                description: "Required for basic functionality",
                detailedDescription: "These cookies are necessary for the website to function properly.",
                purpose: "Enable core website functionality",
                legalBasis: .contract,
                category: .essential,
                isRequired: true,
                canWithdraw: false,
                dataTypes: [.deviceInformation, .usageData],
                retentionPeriod: "Session only",
                thirdParties: [],
                version: version,
                lastUpdated: Date()
            ),
            ConsentItem(
                id: "marketing_communications",
                title: "Marketing Communications",
                description: "Receive promotional emails and offers",
                detailedDescription: "We'll send you updates about new features, special offers, and relevant content.",
                purpose: "Send promotional content and offers",
                legalBasis: .consent,
                category: .marketing,
                isRequired: false,
                canWithdraw: true,
                dataTypes: [.contactInformation, .preferenceData],
                retentionPeriod: "Until withdrawn",
                thirdParties: ["Email Service Provider"],
                version: version,
                lastUpdated: Date()
            )
        ]
    }
    
    func getTenantConsentRequirements(tenantId: String) async throws -> [ConsentItem] {
        return []
    }
    
    func getApplicableLaws(for location: UserLocation) async throws -> [ApplicableLaw] {
        return [
            ApplicableLaw(
                name: "General Data Protection Regulation (GDPR)",
                jurisdiction: "European Union",
                description: "Comprehensive privacy regulation",
                requirements: ["Consent", "Data Protection Impact Assessment"],
                userRights: [.access, .rectification, .erasure, .portability],
                isActive: true
            )
        ]
    }
    
    func getConsentHistory(userId: String) async throws -> [ConsentHistoryEntry] {
        return []
    }
    
    func getDetailedConsentHistory(userId: String) async throws -> [ConsentHistoryEntry] {
        return []
    }
    
    func submitConsentResponses(_ submission: ConsentSubmission) async throws -> ConsentSubmissionResult {
        return ConsentSubmissionResult(
            success: true,
            submissionId: UUID().uuidString,
            timestamp: Date(),
            errors: []
        )
    }
    
    func withdrawAllConsent(userId: String) async throws {
        // Mock implementation
    }
    
    func submitDataSubjectRequest(userId: String, request: DataSubjectRequest) async throws {
        // Mock implementation
    }
    
    func getDataProcessingPurposes() async throws -> [DataProcessingPurpose] {
        return []
    }
    
    func getDataRetentionPolicies() async throws -> [DataRetentionPolicy] {
        return []
    }
    
    func getThirdPartySharing() async throws -> [ThirdPartySharing] {
        return []
    }
    
    func getUserRights() async throws -> [UserRight] {
        return []
    }
    
    func getMarketingConsentDetails() async throws -> MarketingConsent {
        return MarketingConsent(
            emailMarketing: false,
            smsMarketing: false,
            pushNotifications: false,
            personalizedOffers: false,
            thirdPartyMarketing: false,
            frequency: .monthly,
            categories: []
        )
    }
    
    func getAnalyticsConsentDetails() async throws -> AnalyticsConsent {
        return AnalyticsConsent(
            usageAnalytics: false,
            performanceAnalytics: false,
            errorReporting: false,
            userBehaviorTracking: false,
            crossDeviceTracking: false,
            thirdPartyAnalytics: [],
            dataRetentionPeriod: "24 months"
        )
    }
    
    func getCookieConsentDetails() async throws -> CookieConsent {
        return CookieConsent(
            essentialCookies: true,
            functionalCookies: false,
            analyticsCookies: false,
            marketingCookies: false,
            thirdPartyCookies: [],
            cookieLifetime: [:]
        )
    }
}

class MockGeolocationService: GeolocationServiceProtocol {
    func getUserLocation() async throws -> UserLocation {
        return UserLocation(
            country: "United States",
            region: "California",
            jurisdiction: "US-CA",
            isEURegion: false,
            isUKRegion: false,
            isCCPAApplicable: true,
            applicableRegulations: ["CCPA"]
        )
    }
}