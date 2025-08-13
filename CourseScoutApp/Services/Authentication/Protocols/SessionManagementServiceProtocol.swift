import Foundation
import Network
import CryptoKit

// MARK: - Session Management Service Protocol

protocol SessionManagementServiceProtocol {
    // MARK: - Session Creation & Management
    func createSession(userId: String, tenantId: String?, deviceInfo: DeviceInfo) async throws -> SessionCreationResult
    func validateSession(sessionId: String) async throws -> SessionValidationResult
    func refreshSession(sessionId: String) async throws -> SessionRefreshResult
    func terminateSession(sessionId: String) async throws
    func terminateAllUserSessions(userId: String, excludeCurrentDevice: Bool) async throws
    func terminateAllTenantSessions(tenantId: String) async throws
    
    // MARK: - JWT Token Lifecycle
    func generateAccessToken(sessionId: String, scopes: [String]) async throws -> JWTToken
    func generateRefreshToken(sessionId: String) async throws -> JWTToken
    func validateAccessToken(_ token: String) async throws -> TokenValidationResult
    func refreshAccessToken(refreshToken: String) async throws -> TokenRefreshResult
    func revokeToken(token: String, tokenType: TokenType) async throws
    func rotateTokens(sessionId: String) async throws -> TokenRotationResult
    
    // MARK: - Multi-Device Session Management
    func getUserSessions(userId: String) async throws -> [UserSession]
    func getActiveDevices(userId: String) async throws -> [ActiveDevice]
    func trustDevice(userId: String, deviceInfo: DeviceInfo) async throws -> TrustedDevice
    func revokeDeviceTrust(userId: String, deviceId: String) async throws
    func notifyNewDeviceLogin(userId: String, deviceInfo: DeviceInfo, location: GeoLocation?) async throws
    
    // MARK: - Suspicious Activity Detection
    func detectSuspiciousActivity(sessionId: String, activity: SessionActivity) async throws -> SuspiciousActivityResult
    func reportSuspiciousSession(sessionId: String, reason: SuspicionReason) async throws
    func analyzeSessionPatterns(userId: String, period: TimeInterval) async throws -> SessionPatternAnalysis
    func enableAnomalyDetection(userId: String, enabled: Bool) async throws
    
    // MARK: - Geo-location Validation
    func updateSessionLocation(sessionId: String, location: GeoLocation) async throws
    func validateLocationAccess(userId: String, location: GeoLocation) async throws -> LocationValidationResult
    func addAllowedLocation(userId: String, location: GeoLocation, radius: Double) async throws
    func removeAllowedLocation(userId: String, locationId: String) async throws
    func getLocationHistory(userId: String, period: TimeInterval) async throws -> [LocationHistoryEntry]
    
    // MARK: - Session Security Policies
    func setSessionPolicy(tenantId: String?, policy: SessionPolicy) async throws
    func getSessionPolicy(tenantId: String?) async throws -> SessionPolicy
    func validateSessionCompliance(sessionId: String) async throws -> ComplianceResult
    func enforceSessionPolicy(sessionId: String) async throws -> PolicyEnforcementResult
    
    // MARK: - Concurrent Session Management
    func setConcurrentSessionLimit(userId: String, limit: Int) async throws
    func getConcurrentSessions(userId: String) async throws -> [ConcurrentSession]
    func terminateOldestSessions(userId: String, keepCount: Int) async throws
    func handleConcurrentSessionLimitExceeded(userId: String, newSession: SessionCreationRequest) async throws -> SessionLimitResult
    
    // MARK: - Session Analytics & Monitoring
    func getSessionMetrics(period: TimeInterval, tenantId: String?) async throws -> SessionMetrics
    func getUserSessionAnalytics(userId: String) async throws -> UserSessionAnalytics
    func generateSessionReport(filters: SessionReportFilters) async throws -> SessionReport
    func trackSessionEvent(sessionId: String, event: SessionEvent) async throws
    
    // MARK: - Emergency & Security Response
    func lockAllUserSessions(userId: String, reason: SecurityLockReason) async throws
    func unlockUserSessions(userId: String, authorizedBy: String) async throws
    func initiateEmergencyLogout(userId: String, reason: EmergencyReason) async throws
    func quarantineSession(sessionId: String, reason: QuarantineReason) async throws
    
    // MARK: - Session State Management
    var activeSessions: AsyncStream<[UserSession]> { get }
    var suspiciousActivities: AsyncStream<SuspiciousActivityAlert> { get }
    var sessionEvents: AsyncStream<SessionEvent> { get }
}

// MARK: - Session Models

struct SessionCreationResult {
    let session: UserSession
    let accessToken: JWTToken
    let refreshToken: JWTToken
    let deviceTrusted: Bool
    let locationValidated: Bool
    let securityWarnings: [SecurityWarning]
}

struct SessionValidationResult {
    let isValid: Bool
    let session: UserSession?
    let validationErrors: [ValidationError]
    let securityStatus: SessionSecurityStatus
    let remainingTime: TimeInterval
    let requiresReauth: Bool
    let suspiciousActivity: Bool
}

struct SessionRefreshResult {
    let session: UserSession
    let newAccessToken: JWTToken?
    let extendedUntil: Date
    let securityChecks: [SecurityCheck]
    let requiresAdditionalAuth: Bool
}

struct JWTToken {
    let token: String
    let tokenType: TokenType
    let issuedAt: Date
    let expiresAt: Date
    let scopes: [String]
    let issuer: String
    let audience: String
    let subject: String // userId
    let sessionId: String
    let deviceId: String
    let tenantId: String?
    let customClaims: [String: Any]
}

struct TokenValidationResult {
    let isValid: Bool
    let isExpired: Bool
    let userId: String?
    let sessionId: String?
    let scopes: [String]
    let remainingTime: TimeInterval
    let validationErrors: [TokenValidationError]
    let securityFlags: [SecurityFlag]
}

struct TokenRefreshResult {
    let newAccessToken: JWTToken
    let newRefreshToken: JWTToken?
    let sessionExtended: Bool
    let securityChecksPerformed: [SecurityCheck]
}

struct TokenRotationResult {
    let newAccessToken: JWTToken
    let newRefreshToken: JWTToken
    let oldTokensRevoked: Bool
    let rotationReason: TokenRotationReason
}

struct UserSession {
    let id: String
    let userId: String
    let tenantId: String?
    let deviceId: String
    let deviceInfo: DeviceInfo
    let createdAt: Date
    let lastAccessedAt: Date
    let expiresAt: Date
    let ipAddress: String
    let userAgent: String
    let location: GeoLocation?
    let isActive: Bool
    let isTrusted: Bool
    let securityLevel: SessionSecurityLevel
    let activities: [SessionActivity]
    let metadata: [String: Any]
}

struct ActiveDevice {
    let deviceId: String
    let deviceInfo: DeviceInfo
    let sessionId: String
    let lastActiveAt: Date
    let location: GeoLocation?
    let isTrusted: Bool
    let sessionsCount: Int
    let riskScore: Double
}

struct DeviceInfo {
    let deviceId: String
    let name: String
    let model: String
    let osVersion: String
    let appVersion: String
    let platform: Platform
    let screenResolution: String?
    let biometricCapabilities: [BiometricType]
    let isJailbroken: Bool
    let isEmulator: Bool
    let fingerprint: String
}

struct SessionActivity {
    let id: String
    let sessionId: String
    let activityType: ActivityType
    let timestamp: Date
    let location: GeoLocation?
    let metadata: [String: Any]
    let riskScore: Double
    let isAnomalous: Bool
}

struct SuspiciousActivityResult {
    let isSuspicious: Bool
    let riskScore: Double
    let suspicionReasons: [SuspicionReason]
    let recommendedActions: [SecurityAction]
    let alertGenerated: Bool
    let shouldTerminateSession: Bool
}

struct SessionPatternAnalysis {
    let userId: String
    let analyzedPeriod: TimeInterval
    let normalPatterns: [SessionPattern]
    let anomalies: [SessionAnomaly]
    let riskAssessment: RiskAssessment
    let recommendations: [SecurityRecommendation]
}

struct GeoLocation {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    let city: String?
    let region: String?
    let country: String
    let countryCode: String
    let ipAddress: String?
    let isVPN: Bool
    let isTor: Bool
}

struct LocationValidationResult {
    let isAllowed: Bool
    let isKnownLocation: Bool
    let riskScore: Double
    let distance: Double?  // Distance from nearest known location
    let validationReasons: [LocationValidationReason]
    let requiresApproval: Bool
}

struct LocationHistoryEntry {
    let location: GeoLocation
    let sessionId: String
    let timestamp: Date
    let duration: TimeInterval
    let activityCount: Int
    let isAnomalous: Bool
}

struct SessionPolicy {
    let maxConcurrentSessions: Int
    let sessionTimeout: TimeInterval
    let idleTimeout: TimeInterval
    let requireLocationValidation: Bool
    let allowedCountries: [String]?
    let blockedCountries: [String]?
    let requireDeviceTrust: Bool
    let enableAnomalyDetection: Bool
    let maxFailedValidations: Int
    let lockoutDuration: TimeInterval
    let requireMFAForSensitiveOps: Bool
    let allowVPNConnections: Bool
    let allowTorConnections: Bool
    let geofencingRules: [GeofenceRule]
}

struct ComplianceResult {
    let isCompliant: Bool
    let violations: [PolicyViolation]
    let riskScore: Double
    let recommendedActions: [ComplianceAction]
    let enforcementRequired: Bool
}

struct PolicyEnforcementResult {
    let actionsExecuted: [EnforcementAction]
    let sessionModified: Bool
    let sessionTerminated: Bool
    let userNotified: Bool
    let alertsGenerated: [SecurityAlert]
}

struct ConcurrentSession {
    let sessionId: String
    let deviceInfo: DeviceInfo
    let location: GeoLocation?
    let createdAt: Date
    let lastAccessedAt: Date
    let isCurrentSession: Bool
    let riskScore: Double
}

struct SessionLimitResult {
    let allowed: Bool
    let terminatedSessions: [String]
    let retainedSessions: [String]
    let reason: SessionLimitReason
    let userNotified: Bool
}

struct SessionMetrics {
    let totalSessions: Int
    let activeSessions: Int
    let averageSessionDuration: TimeInterval
    let suspiciousActivities: Int
    let terminatedSessions: Int
    let deviceTrustRate: Double
    let locationAnomalies: Int
    let policyViolations: Int
    let geographicDistribution: [String: Int]
    let deviceDistribution: [Platform: Int]
}

struct UserSessionAnalytics {
    let userId: String
    let totalSessions: Int
    let averageSessionDuration: TimeInterval
    let lastActivityAt: Date
    let riskProfile: RiskProfile
    let behaviorPatterns: [BehaviorPattern]
    let securityScore: Double
    let trustLevel: UserTrustLevel
}

struct SessionReport {
    let reportId: String
    let generatedAt: Date
    let period: ReportPeriod
    let filters: SessionReportFilters
    let totalSessions: Int
    let uniqueUsers: Int
    let securityEvents: [SecurityEventSummary]
    let geographicAnalysis: GeographicAnalysis
    let deviceAnalysis: DeviceAnalysis
    let riskAnalysis: RiskAnalysis
}

struct SessionEvent {
    let id: String
    let sessionId: String
    let eventType: SessionEventType
    let timestamp: Date
    let severity: EventSeverity
    let metadata: [String: Any]
    let location: GeoLocation?
    let userAgent: String?
}

// MARK: - Supporting Models

struct SecurityWarning {
    let type: WarningType
    let severity: WarningSeverity
    let message: String
    let recommendedAction: String?
}

struct ValidationError {
    let code: ValidationErrorCode
    let message: String
    let field: String?
}

struct SecurityCheck {
    let type: SecurityCheckType
    let passed: Bool
    let details: String?
    let timestamp: Date
}

struct SecurityFlag {
    let flag: SecurityFlagType
    let severity: FlagSeverity
    let description: String
}

struct SessionPattern {
    let patternType: PatternType
    let frequency: Double
    let confidence: Double
    let description: String
}

struct SessionAnomaly {
    let anomalyType: AnomalyType
    let severity: AnomalySeverity
    let description: String
    let timestamp: Date
    let riskScore: Double
}

struct RiskAssessment {
    let overallRisk: RiskLevel
    let riskFactors: [RiskFactor]
    let mitigatingFactors: [MitigatingFactor]
    let recommendedSecurityLevel: SessionSecurityLevel
}

struct SecurityRecommendation {
    let type: RecommendationType
    let priority: RecommendationPriority
    let description: String
    let implementation: String
}

struct GeofenceRule {
    let id: String
    let name: String
    let location: GeoLocation
    let radius: Double
    let action: GeofenceAction
    let isActive: Bool
}

struct EnforcementAction {
    let action: PolicyAction
    let target: String
    let executedAt: Date
    let success: Bool
    let details: String?
}

struct SecurityAlert {
    let id: String
    let alertType: SecurityAlertType
    let severity: AlertSeverity
    let message: String
    let timestamp: Date
    let acknowledged: Bool
}

struct RiskProfile {
    let overallRisk: RiskLevel
    let behaviorRisk: Double
    let locationRisk: Double
    let deviceRisk: Double
    let temporalRisk: Double
    let lastAssessedAt: Date
}

struct BehaviorPattern {
    let patternType: BehaviorPatternType
    let strength: Double
    let description: String
    let lastObservedAt: Date
}

struct SessionReportFilters {
    let startDate: Date
    let endDate: Date
    let userIds: [String]?
    let tenantIds: [String]?
    let deviceTypes: [Platform]?
    let countries: [String]?
    let includeAnonymous: Bool
    let minRiskScore: Double?
    let eventTypes: [SessionEventType]?
}

struct SecurityEventSummary {
    let eventType: SessionEventType
    let count: Int
    let severity: EventSeverity
    let trend: Trend
}

struct GeographicAnalysis {
    let topCountries: [CountryMetric]
    let suspiciousLocations: [SuspiciousLocation]
    let vpnUsage: VPNUsageMetrics
    let locationAnomalies: Int
}

struct DeviceAnalysis {
    let platformDistribution: [Platform: Int]
    let trustedDeviceRate: Double
    let jailbrokenDeviceDetections: Int
    let emulatorDetections: Int
    let deviceAnomalies: [DeviceAnomaly]
}

struct RiskAnalysis {
    let averageRiskScore: Double
    let highRiskSessions: Int
    let riskTrends: [RiskTrend]
    let topRiskFactors: [RiskFactorMetric]
}

// MARK: - Enums

enum TokenType: String, CaseIterable {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case idToken = "id_token"
}

enum TokenRotationReason: String, CaseIterable {
    case scheduled = "scheduled"
    case compromised = "compromised"
    case policyRequired = "policy_required"
    case userRequested = "user_requested"
    case anomalyDetected = "anomaly_detected"
}

enum Platform: String, CaseIterable {
    case iOS = "ios"
    case android = "android"
    case web = "web"
    case macOS = "macos"
    case windows = "windows"
    case watchOS = "watchOS"
    case tvOS = "tvOS"
}

enum SessionSecurityLevel: String, CaseIterable {
    case basic = "basic"
    case standard = "standard"
    case elevated = "elevated"
    case high = "high"
    case critical = "critical"
    
    var numericValue: Int {
        switch self {
        case .basic: return 1
        case .standard: return 2
        case .elevated: return 3
        case .high: return 4
        case .critical: return 5
        }
    }
}

enum SuspicionReason: String, CaseIterable {
    case unusualLocation = "unusual_location"
    case unusualTime = "unusual_time"
    case rapidLocationChange = "rapid_location_change"
    case multipleDevices = "multiple_devices"
    case suspiciousUserAgent = "suspicious_user_agent"
    case knownMaliciousIP = "known_malicious_ip"
    case vpnDetected = "vpn_detected"
    case torDetected = "tor_detected"
    case behaviorAnomaly = "behavior_anomaly"
    case deviceMismatch = "device_mismatch"
    case timePatternAnomaly = "time_pattern_anomaly"
    case geolocationSpoof = "geolocation_spoof"
}

enum LocationValidationReason: String, CaseIterable {
    case allowedCountry = "allowed_country"
    case blockedCountry = "blocked_country"
    case knownLocation = "known_location"
    case newLocation = "new_location"
    case vpnDetected = "vpn_detected"
    case torDetected = "tor_detected"
    case geofenceViolation = "geofence_violation"
    case travelSpeedViolation = "travel_speed_violation"
}

enum SecurityLockReason: String, CaseIterable {
    case suspiciousActivity = "suspicious_activity"
    case policyViolation = "policy_violation"
    case compromisedCredentials = "compromised_credentials"
    case adminLock = "admin_lock"
    case emergencyLock = "emergency_lock"
    case complianceViolation = "compliance_violation"
}

enum EmergencyReason: String, CaseIterable {
    case accountCompromised = "account_compromised"
    case securityBreach = "security_breach"
    case legalRequest = "legal_request"
    case userRequest = "user_request"
    case systemSecurity = "system_security"
}

enum QuarantineReason: String, CaseIterable {
    case malwareDetected = "malware_detected"
    case botActivity = "bot_activity"
    case massiveAnomalies = "massive_anomalies"
    case securityInvestigation = "security_investigation"
    case complianceHold = "compliance_hold"
}

enum SessionLimitReason: String, CaseIterable {
    case policyLimit = "policy_limit"
    case securityLimit = "security_limit"
    case resourceLimit = "resource_limit"
    case adminLimit = "admin_limit"
}

enum SessionEventType: String, CaseIterable {
    case sessionCreated = "session_created"
    case sessionRefreshed = "session_refreshed"
    case sessionTerminated = "session_terminated"
    case tokenRefreshed = "token_refreshed"
    case tokenRevoked = "token_revoked"
    case suspiciousActivity = "suspicious_activity"
    case locationChanged = "location_changed"
    case deviceTrusted = "device_trusted"
    case policyViolation = "policy_violation"
    case anomalyDetected = "anomaly_detected"
    case securityAlert = "security_alert"
}

enum EventSeverity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum UserTrustLevel: String, CaseIterable {
    case untrusted = "untrusted"
    case basic = "basic"
    case verified = "verified"
    case trusted = "trusted"
    case highlyTrusted = "highly_trusted"
}

enum ReportPeriod: String, CaseIterable {
    case hour = "hour"
    case day = "day"
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"
}

enum Trend: String, CaseIterable {
    case increasing = "increasing"
    case decreasing = "decreasing"
    case stable = "stable"
}

enum GeofenceAction: String, CaseIterable {
    case allow = "allow"
    case warn = "warn"
    case block = "block"
    case requireApproval = "require_approval"
}

enum PolicyAction: String, CaseIterable {
    case terminate = "terminate"
    case warn = "warn"
    case restrict = "restrict"
    case requireAuth = "require_auth"
    case log = "log"
}

enum SecurityAlertType: String, CaseIterable {
    case sessionAnomaly = "session_anomaly"
    case locationAnomaly = "location_anomaly"
    case deviceAnomaly = "device_anomaly"
    case policyViolation = "policy_violation"
    case securityBreach = "security_breach"
}

enum AlertSeverity: String, CaseIterable {
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
}

enum BehaviorPatternType: String, CaseIterable {
    case loginTiming = "login_timing"
    case activityPattern = "activity_pattern"
    case locationPattern = "location_pattern"
    case deviceUsage = "device_usage"
    case sessionDuration = "session_duration"
}

// MARK: - Additional Enums

enum WarningType: String, CaseIterable {
    case newDevice = "new_device"
    case newLocation = "new_location"
    case untrustedDevice = "untrusted_device"
    case vpnDetected = "vpn_detected"
    case anomalousActivity = "anomalous_activity"
}

enum WarningSeverity: String, CaseIterable {
    case info = "info"
    case warning = "warning"
    case high = "high"
}

enum ValidationErrorCode: String, CaseIterable {
    case sessionExpired = "session_expired"
    case invalidToken = "invalid_token"
    case insufficientPermissions = "insufficient_permissions"
    case deviceNotTrusted = "device_not_trusted"
    case locationNotAllowed = "location_not_allowed"
}

enum SecurityCheckType: String, CaseIterable {
    case deviceTrust = "device_trust"
    case locationValidation = "location_validation"
    case tokenIntegrity = "token_integrity"
    case anomalyDetection = "anomaly_detection"
    case policyCompliance = "policy_compliance"
}

enum SecurityFlagType: String, CaseIterable {
    case suspiciousIP = "suspicious_ip"
    case vpnUsage = "vpn_usage"
    case torUsage = "tor_usage"
    case jailbrokenDevice = "jailbroken_device"
    case emulatorDetected = "emulator_detected"
    case locationSpoof = "location_spoof"
}

enum FlagSeverity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
}

enum PatternType: String, CaseIterable {
    case temporal = "temporal"
    case geographic = "geographic"
    case behavioral = "behavioral"
    case device = "device"
}

enum AnomalyType: String, CaseIterable {
    case locationJump = "location_jump"
    case timeAnomaly = "time_anomaly"
    case deviceSwitch = "device_switch"
    case activityBurst = "activity_burst"
    case behaviorChange = "behavior_change"
}

enum AnomalySeverity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum RecommendationType: String, CaseIterable {
    case securityEnhancement = "security_enhancement"
    case policyUpdate = "policy_update"
    case userEducation = "user_education"
    case systemConfiguration = "system_configuration"
}

enum RecommendationPriority: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case urgent = "urgent"
}

enum MitigatingFactor: String, CaseIterable {
    case trustedDevice = "trusted_device"
    case knownLocation = "known_location"
    case consistentBehavior = "consistent_behavior"
    case strongAuthentication = "strong_authentication"
    case recentActivity = "recent_activity"
}

enum TokenValidationError: String, CaseIterable {
    case expired = "expired"
    case invalidSignature = "invalid_signature"
    case invalidIssuer = "invalid_issuer"
    case invalidAudience = "invalid_audience"
    case malformed = "malformed"
    case revoked = "revoked"
}

// MARK: - Complex Supporting Structures

struct SessionCreationRequest {
    let userId: String
    let tenantId: String?
    let deviceInfo: DeviceInfo
    let location: GeoLocation?
    let userAgent: String
    let ipAddress: String
}

struct SessionSecurityStatus {
    let level: SessionSecurityLevel
    let riskScore: Double
    let trustedDevice: Bool
    let knownLocation: Bool
    let anomaliesDetected: [AnomalyType]
    let lastSecurityCheck: Date
}

struct SuspiciousActivityAlert {
    let sessionId: String
    let userId: String
    let alertType: SuspiciousActivityType
    let severity: AlertSeverity
    let timestamp: Date
    let details: SuspiciousActivityDetails
    let actionTaken: SecurityAction?
}

struct SuspiciousActivityDetails {
    let riskScore: Double
    let indicators: [SuspicionReason]
    let context: [String: Any]
    let location: GeoLocation?
    let deviceInfo: DeviceInfo?
}

struct CountryMetric {
    let country: String
    let sessionCount: Int
    let uniqueUsers: Int
    let riskScore: Double
}

struct SuspiciousLocation {
    let location: GeoLocation
    let suspicionReasons: [SuspicionReason]
    let sessionCount: Int
    let riskScore: Double
}

struct VPNUsageMetrics {
    let totalSessions: Int
    let vpnSessions: Int
    let vpnPercentage: Double
    let torSessions: Int
    let torPercentage: Double
}

struct DeviceAnomaly {
    let deviceId: String
    let anomalyType: DeviceAnomalyType
    let severity: AnomalySeverity
    let description: String
}

struct RiskTrend {
    let period: Date
    let averageRisk: Double
    let trend: Trend
}

struct RiskFactorMetric {
    let factor: RiskFactor
    let frequency: Int
    let impact: Double
}

enum DeviceAnomalyType: String, CaseIterable {
    case jailbrokenDetection = "jailbroken_detection"
    case emulatorDetection = "emulator_detection"
    case tampering = "tampering"
    case cloning = "cloning"
    case spoofing = "spoofing"
}

enum SuspiciousActivityType: String, CaseIterable {
    case rapidLocationChange = "rapid_location_change"
    case simultaneousLogins = "simultaneous_logins"
    case unusualActivityPattern = "unusual_activity_pattern"
    case massRequests = "mass_requests"
    case botBehavior = "bot_behavior"
    case credentialStuffing = "credential_stuffing"
}

// MARK: - Error Types

enum SessionManagementError: LocalizedError, Equatable {
    case sessionNotFound
    case sessionExpired
    case sessionTerminated
    case invalidToken
    case tokenExpired
    case tokenRevoked
    case concurrentSessionLimitExceeded
    case deviceNotTrusted
    case locationNotAllowed
    case suspiciousActivity(SuspicionReason)
    case policyViolation([PolicyViolation])
    case geofenceViolation
    case emergencyLockActive
    case quarantineActive
    case networkError(String)
    case systemError(String)
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Session not found"
        case .sessionExpired:
            return "Session has expired"
        case .sessionTerminated:
            return "Session was terminated"
        case .invalidToken:
            return "Invalid authentication token"
        case .tokenExpired:
            return "Authentication token has expired"
        case .tokenRevoked:
            return "Authentication token has been revoked"
        case .concurrentSessionLimitExceeded:
            return "Too many active sessions. Please close other sessions and try again"
        case .deviceNotTrusted:
            return "This device is not trusted for authentication"
        case .locationNotAllowed:
            return "Authentication from this location is not allowed"
        case .suspiciousActivity(let reason):
            return "Suspicious activity detected: \(reason.rawValue)"
        case .policyViolation(let violations):
            return "Policy violation: \(violations.map(\.rawValue).joined(separator: ", "))"
        case .geofenceViolation:
            return "Access from this location is restricted"
        case .emergencyLockActive:
            return "Account is under emergency lock"
        case .quarantineActive:
            return "Session is quarantined for security review"
        case .networkError(let message):
            return "Network error: \(message)"
        case .systemError(let message):
            return "System error: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}