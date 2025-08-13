import Foundation
import LocalAuthentication
import AuthenticationServices
import CryptoKit

// MARK: - Authentication Service Protocol

protocol AuthenticationServiceProtocol {
    // MARK: - OAuth 2.0 Authentication
    func signInWithGoogle() async throws -> AuthenticationResult
    func signInWithApple() async throws -> AuthenticationResult
    func signInWithFacebook() async throws -> AuthenticationResult
    func signInWithMicrosoft() async throws -> AuthenticationResult
    
    // MARK: - Enterprise Authentication
    func signInWithAzureAD(tenantId: String) async throws -> AuthenticationResult
    func signInWithGoogleWorkspace(domain: String) async throws -> AuthenticationResult
    func signInWithOkta(orgUrl: String) async throws -> AuthenticationResult
    func signInWithCustomOIDC(configuration: OIDCConfiguration) async throws -> AuthenticationResult
    
    // MARK: - JWT Token Management
    func validateToken(_ token: String) async throws -> TokenValidationResult
    func refreshToken(_ refreshToken: String) async throws -> AuthenticationResult
    func revokeToken(_ token: String) async throws
    func getStoredToken() async -> StoredToken?
    func clearStoredTokens() async throws
    
    // MARK: - Multi-Tenant Support
    func switchTenant(_ tenantId: String) async throws -> TenantSwitchResult
    func getCurrentTenant() async -> TenantInfo?
    func getUserTenants() async throws -> [TenantInfo]
    
    // MARK: - Session Management
    func getCurrentSession() async -> AuthenticationSession?
    func validateSession(_ sessionId: String) async throws -> SessionValidationResult
    func terminateSession(_ sessionId: String) async throws
    func terminateAllSessions() async throws
    
    // MARK: - User Authentication State
    var isAuthenticated: Bool { get }
    var currentUser: AuthenticatedUser? { get }
    var authenticationStateChanged: AsyncStream<AuthenticationState> { get }
    
    // MARK: - Security Features
    func enableMFA() async throws -> MFASetupResult
    func disableMFA() async throws
    func validateMFA(code: String, method: MFAMethod) async throws -> Bool
    func generateBackupCodes() async throws -> [String]
    
    // MARK: - Tenant Isolation & Security
    func validateTenantAccess(_ tenantId: String, userId: String) async throws -> Bool
    func auditAuthenticationAttempt(_ attempt: AuthenticationAttempt) async
}

// MARK: - Authentication Models

struct AuthenticationResult {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let user: AuthenticatedUser
    let tenant: TenantInfo?
    let expiresAt: Date
    let tokenType: String
    let scope: [String]
}

struct TokenValidationResult {
    let isValid: Bool
    let user: AuthenticatedUser?
    let tenant: TenantInfo?
    let expiresAt: Date?
    let remainingTime: TimeInterval
    let scopes: [String]
    let claims: [String: Any]
}

struct StoredToken {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresAt: Date
    let tokenType: String
    let tenant: TenantInfo?
}

struct AuthenticatedUser {
    let id: String
    let email: String?
    let name: String?
    let profileImageURL: URL?
    let provider: AuthenticationProvider
    let tenantMemberships: [TenantMembership]
    let lastLoginAt: Date
    let createdAt: Date
    let preferences: UserPreferences
}

struct TenantInfo {
    let id: String
    let name: String
    let domain: String?
    let logoURL: URL?
    let primaryColor: String?
    let isActive: Bool
    let subscription: TenantSubscription
    let settings: TenantSettings
}

struct TenantMembership {
    let tenantId: String
    let userId: String
    let role: TenantRole
    let permissions: [Permission]
    let joinedAt: Date
    let isActive: Bool
}

struct TenantSwitchResult {
    let newTenant: TenantInfo
    let newToken: String
    let user: AuthenticatedUser
    let expiresAt: Date
}

struct AuthenticationSession {
    let id: String
    let userId: String
    let tenantId: String?
    let deviceId: String
    let createdAt: Date
    let lastAccessedAt: Date
    let expiresAt: Date
    let ipAddress: String
    let userAgent: String
    let isActive: Bool
}

struct SessionValidationResult {
    let isValid: Bool
    let session: AuthenticationSession?
    let requiresReauth: Bool
    let suspiciousActivity: Bool
}

struct MFASetupResult {
    let secret: String
    let qrCodeURL: URL
    let backupCodes: [String]
    let method: MFAMethod
}

struct AuthenticationAttempt {
    let userId: String?
    let email: String?
    let provider: AuthenticationProvider
    let tenantId: String?
    let success: Bool
    let failureReason: AuthenticationFailureReason?
    let ipAddress: String
    let userAgent: String
    let deviceId: String
    let timestamp: Date
    let location: LocationInfo?
}

// MARK: - Configuration Models

struct OIDCConfiguration {
    let issuer: URL
    let clientId: String
    let clientSecret: String
    let redirectURI: String
    let scopes: [String]
    let additionalParameters: [String: String]
}

struct TenantSettings {
    let authenticationMethods: [AuthenticationProvider]
    let mfaRequired: Bool
    let sessionTimeout: TimeInterval
    let allowedDomains: [String]
    let ssoEnabled: Bool
    let loginBrandingEnabled: Bool
}

struct TenantSubscription {
    let plan: String
    let userLimit: Int
    let featuresEnabled: [String]
    let expiresAt: Date?
    let isTrialAccount: Bool
}

struct UserPreferences {
    let language: String
    let timezone: String
    let notifications: NotificationPreferences
    let privacy: PrivacySettings
}

struct LocationInfo {
    let city: String?
    let country: String?
    let coordinates: (latitude: Double, longitude: Double)?
}

// MARK: - Enums

enum AuthenticationProvider: String, CaseIterable {
    case google = "google"
    case apple = "apple"
    case facebook = "facebook"
    case microsoft = "microsoft"
    case azureAD = "azure_ad"
    case googleWorkspace = "google_workspace"
    case okta = "okta"
    case customOIDC = "custom_oidc"
    case email = "email"
    case phone = "phone"
    
    var displayName: String {
        switch self {
        case .google: return "Google"
        case .apple: return "Apple"
        case .facebook: return "Facebook"
        case .microsoft: return "Microsoft Personal"
        case .azureAD: return "Azure Active Directory"
        case .googleWorkspace: return "Google Workspace"
        case .okta: return "Okta"
        case .customOIDC: return "Single Sign-On"
        case .email: return "Email"
        case .phone: return "Phone"
        }
    }
    
    var isEnterprise: Bool {
        switch self {
        case .azureAD, .googleWorkspace, .okta, .customOIDC:
            return true
        default:
            return false
        }
    }
}

enum AuthenticationState {
    case unauthenticated
    case authenticating
    case authenticated(user: AuthenticatedUser, tenant: TenantInfo?)
    case expired
    case error(Error)
    case tenantSwitching
    case mfaRequired(challengeId: String)
}

enum TenantRole: String, CaseIterable {
    case owner = "owner"
    case admin = "admin"
    case manager = "manager"
    case member = "member"
    case guest = "guest"
    
    var permissions: [Permission] {
        switch self {
        case .owner:
            return Permission.allCases
        case .admin:
            return [.readUsers, .writeUsers, .readSettings, .writeSettings, .readAnalytics]
        case .manager:
            return [.readUsers, .writeUsers, .readAnalytics]
        case .member:
            return [.readUsers]
        case .guest:
            return []
        }
    }
}

enum Permission: String, CaseIterable {
    case readUsers = "read_users"
    case writeUsers = "write_users"
    case readSettings = "read_settings"
    case writeSettings = "write_settings"
    case readAnalytics = "read_analytics"
    case writeAnalytics = "write_analytics"
    case billing = "billing"
    case apiAccess = "api_access"
}

enum MFAMethod: String, CaseIterable {
    case totp = "totp"
    case sms = "sms"
    case email = "email"
    case backup = "backup"
    
    var displayName: String {
        switch self {
        case .totp: return "Authenticator App"
        case .sms: return "SMS"
        case .email: return "Email"
        case .backup: return "Backup Code"
        }
    }
}

enum AuthenticationFailureReason: String, CaseIterable {
    case invalidCredentials = "invalid_credentials"
    case accountLocked = "account_locked"
    case tenantNotFound = "tenant_not_found"
    case tenantInactive = "tenant_inactive"
    case mfaFailed = "mfa_failed"
    case tokenExpired = "token_expired"
    case insufficientPermissions = "insufficient_permissions"
    case suspiciousActivity = "suspicious_activity"
    case rateLimited = "rate_limited"
    case networkError = "network_error"
    case unknownError = "unknown_error"
}

// MARK: - Notification Models

struct NotificationPreferences {
    let emailNotifications: Bool
    let pushNotifications: Bool
    let smsNotifications: Bool
    let securityAlerts: Bool
}

struct PrivacySettings {
    let profileVisibility: ProfileVisibility
    let dataProcessingConsent: Bool
    let analyticsOptOut: Bool
    let marketingOptOut: Bool
}

enum ProfileVisibility: String, CaseIterable {
    case `public` = "public"
    case restricted = "restricted"
    case `private` = "private"
}

// MARK: - Error Types

enum AuthenticationError: LocalizedError, Equatable {
    case invalidCredentials
    case networkError(String)
    case tokenExpired
    case refreshTokenExpired
    case unsupportedProvider
    case tenantNotFound
    case tenantInactive
    case insufficientPermissions
    case mfaRequired
    case mfaFailed
    case biometricNotAvailable
    case biometricNotEnrolled
    case biometricFailed
    case userCancelled
    case configurationError(String)
    case rateLimited
    case suspiciousActivity
    case deviceNotTrusted
    case geofenceViolation
    case complianceViolation(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password"
        case .networkError(let message):
            return "Network error: \(message)"
        case .tokenExpired:
            return "Authentication token has expired"
        case .refreshTokenExpired:
            return "Session has expired. Please sign in again"
        case .unsupportedProvider:
            return "Authentication provider is not supported"
        case .tenantNotFound:
            return "Organization not found"
        case .tenantInactive:
            return "Organization is inactive"
        case .insufficientPermissions:
            return "You don't have permission to access this resource"
        case .mfaRequired:
            return "Multi-factor authentication is required"
        case .mfaFailed:
            return "Multi-factor authentication failed"
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device"
        case .biometricNotEnrolled:
            return "Biometric authentication is not set up on this device"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .userCancelled:
            return "Authentication was cancelled"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .rateLimited:
            return "Too many authentication attempts. Please try again later"
        case .suspiciousActivity:
            return "Suspicious activity detected. Please verify your identity"
        case .deviceNotTrusted:
            return "This device is not trusted for authentication"
        case .geofenceViolation:
            return "Authentication from this location is not allowed"
        case .complianceViolation(let message):
            return "Compliance violation: \(message)"
        }
    }
}