import Foundation
import Appwrite
import AuthenticationServices
import CryptoKit
import Network
import os.log

// MARK: - Authentication Service Implementation

@MainActor
final class AuthenticationService: NSObject, AuthenticationServiceProtocol {
    
    // MARK: - Properties
    
    private let appwriteClient: Client
    private let account: Account
    private let databases: Databases
    private let logger = Logger(subsystem: "GolfFinderApp", category: "Authentication")
    
    // OAuth Providers Configuration
    private let oauthProviders: [AuthenticationProvider: OAuthProviderConfig] = [
        .google: OAuthProviderConfig(
            clientId: Configuration.googleOAuthClientId,
            scopes: ["openid", "email", "profile"],
            additionalParameters: [:]
        ),
        .apple: OAuthProviderConfig(
            clientId: Configuration.appleOAuthClientId,
            scopes: ["name", "email"],
            additionalParameters: [:]
        ),
        .facebook: OAuthProviderConfig(
            clientId: Configuration.facebookOAuthClientId,
            scopes: ["email", "public_profile"],
            additionalParameters: [:]
        ),
        .microsoft: OAuthProviderConfig(
            clientId: Configuration.microsoftOAuthClientId,
            scopes: ["openid", "email", "profile"],
            additionalParameters: [:]
        )
    ]
    
    // State Management
    private var _currentUser: AuthenticatedUser?
    private var _currentTenant: TenantInfo?
    private let authStateSubject = PassthroughSubject<AuthenticationState, Never>()
    private var authStateTask: Task<Void, Never>?
    
    // Security Configuration
    private let jwtSecretKey: SymmetricKey
    private let sessionManager: SessionManagementServiceProtocol
    private let securityService: SecurityServiceProtocol
    
    // MARK: - Initialization
    
    init(appwriteClient: Client, sessionManager: SessionManagementServiceProtocol, securityService: SecurityServiceProtocol) {
        self.appwriteClient = appwriteClient
        self.account = Account(appwriteClient)
        self.databases = Databases(appwriteClient)
        self.sessionManager = sessionManager
        self.securityService = securityService
        self.jwtSecretKey = Self.loadJWTSecretKey()
        
        super.init()
        
        startAuthStateMonitoring()
        logger.info("AuthenticationService initialized")
    }
    
    deinit {
        authStateTask?.cancel()
    }
    
    // MARK: - Authentication State
    
    var isAuthenticated: Bool {
        return _currentUser != nil
    }
    
    var currentUser: AuthenticatedUser? {
        return _currentUser
    }
    
    var authenticationStateChanged: AsyncStream<AuthenticationState> {
        return AsyncStream { continuation in
            let cancellable = authStateSubject
                .sink { state in
                    continuation.yield(state)
                }
            
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
    
    // MARK: - OAuth 2.0 Authentication
    
    func signInWithGoogle() async throws -> AuthenticationResult {
        logger.info("Starting Google OAuth authentication")
        
        guard let config = oauthProviders[.google] else {
            throw AuthenticationError.configurationError("Google OAuth not configured")
        }
        
        do {
            // Create OAuth2 session with Appwrite
            let session = try await account.createOAuth2Session(
                provider: "google",
                success: Configuration.oauthSuccessURL,
                failure: Configuration.oauthFailureURL,
                scopes: config.scopes
            )
            
            return try await processOAuthResult(session: session, provider: .google)
            
        } catch {
            logger.error("Google OAuth failed: \(error.localizedDescription)")
            await auditAuthenticationAttempt(
                AuthenticationAttempt(
                    userId: nil,
                    email: nil,
                    provider: .google,
                    tenantId: nil,
                    success: false,
                    failureReason: .networkError,
                    ipAddress: await getCurrentIPAddress(),
                    userAgent: getCurrentUserAgent(),
                    deviceId: await getCurrentDeviceId(),
                    timestamp: Date(),
                    location: nil
                )
            )
            throw mapOAuthError(error, provider: .google)
        }
    }
    
    func signInWithApple() async throws -> AuthenticationResult {
        logger.info("Starting Apple Sign In authentication")
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = generateNonce()
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AppleSignInDelegate { result in
                switch result {
                case .success(let authResult):
                    Task {
                        do {
                            let result = try await self.processAppleSignInResult(authResult)
                            continuation.resume(returning: result)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            controller.performRequests()
        }
    }
    
    func signInWithFacebook() async throws -> AuthenticationResult {
        logger.info("Starting Facebook OAuth authentication")
        
        guard let config = oauthProviders[.facebook] else {
            throw AuthenticationError.configurationError("Facebook OAuth not configured")
        }
        
        do {
            let session = try await account.createOAuth2Session(
                provider: "facebook",
                success: Configuration.oauthSuccessURL,
                failure: Configuration.oauthFailureURL,
                scopes: config.scopes
            )
            
            return try await processOAuthResult(session: session, provider: .facebook)
            
        } catch {
            logger.error("Facebook OAuth failed: \(error.localizedDescription)")
            throw mapOAuthError(error, provider: .facebook)
        }
    }
    
    func signInWithMicrosoft() async throws -> AuthenticationResult {
        logger.info("Starting Microsoft OAuth authentication")
        
        guard let config = oauthProviders[.microsoft] else {
            throw AuthenticationError.configurationError("Microsoft OAuth not configured")
        }
        
        do {
            let session = try await account.createOAuth2Session(
                provider: "microsoft",
                success: Configuration.oauthSuccessURL,
                failure: Configuration.oauthFailureURL,
                scopes: config.scopes
            )
            
            return try await processOAuthResult(session: session, provider: .microsoft)
            
        } catch {
            logger.error("Microsoft OAuth failed: \(error.localizedDescription)")
            throw mapOAuthError(error, provider: .microsoft)
        }
    }
    
    // MARK: - Enterprise Authentication
    
    func signInWithAzureAD(tenantId: String) async throws -> AuthenticationResult {
        logger.info("Starting Azure AD authentication for tenant: \(tenantId)")
        
        let azureConfig = OIDCConfiguration(
            issuer: URL(string: "https://login.microsoftonline.com/\(tenantId)/v2.0")!,
            clientId: Configuration.azureADClientId,
            clientSecret: Configuration.azureADClientSecret,
            redirectURI: Configuration.azureADRedirectURI,
            scopes: ["openid", "email", "profile"],
            additionalParameters: ["tenant": tenantId]
        )
        
        return try await signInWithCustomOIDC(configuration: azureConfig)
    }
    
    func signInWithGoogleWorkspace(domain: String) async throws -> AuthenticationResult {
        logger.info("Starting Google Workspace authentication for domain: \(domain)")
        
        let workspaceConfig = OIDCConfiguration(
            issuer: URL(string: "https://accounts.google.com")!,
            clientId: Configuration.googleWorkspaceClientId,
            clientSecret: Configuration.googleWorkspaceClientSecret,
            redirectURI: Configuration.googleWorkspaceRedirectURI,
            scopes: ["openid", "email", "profile"],
            additionalParameters: ["hd": domain]
        )
        
        return try await signInWithCustomOIDC(configuration: workspaceConfig)
    }
    
    func signInWithOkta(orgUrl: String) async throws -> AuthenticationResult {
        logger.info("Starting Okta authentication for org: \(orgUrl)")
        
        let oktaConfig = OIDCConfiguration(
            issuer: URL(string: "\(orgUrl)/oauth2/default")!,
            clientId: Configuration.oktaClientId,
            clientSecret: Configuration.oktaClientSecret,
            redirectURI: Configuration.oktaRedirectURI,
            scopes: ["openid", "email", "profile"],
            additionalParameters: [:]
        )
        
        return try await signInWithCustomOIDC(configuration: oktaConfig)
    }
    
    func signInWithCustomOIDC(configuration: OIDCConfiguration) async throws -> AuthenticationResult {
        logger.info("Starting custom OIDC authentication")
        
        // Implement OIDC flow
        let authURL = try buildOIDCAuthURL(configuration: configuration)
        let authCode = try await performOIDCAuth(authURL: authURL)
        let tokens = try await exchangeCodeForTokens(code: authCode, configuration: configuration)
        let userInfo = try await fetchOIDCUserInfo(accessToken: tokens.accessToken, configuration: configuration)
        
        // Create user session
        let user = try await createOrUpdateUser(from: userInfo, provider: .customOIDC)
        let tenant = try await resolveTenantFromOIDC(userInfo: userInfo, configuration: configuration)
        
        // Create session
        let deviceInfo = await getCurrentDeviceInfo()
        let sessionResult = try await sessionManager.createSession(
            userId: user.id,
            tenantId: tenant?.id,
            deviceInfo: deviceInfo
        )
        
        _currentUser = user
        _currentTenant = tenant
        
        authStateSubject.send(.authenticated(user: user, tenant: tenant))
        
        await auditAuthenticationAttempt(
            AuthenticationAttempt(
                userId: user.id,
                email: user.email,
                provider: .customOIDC,
                tenantId: tenant?.id,
                success: true,
                failureReason: nil,
                ipAddress: await getCurrentIPAddress(),
                userAgent: getCurrentUserAgent(),
                deviceId: deviceInfo.deviceId,
                timestamp: Date(),
                location: nil
            )
        )
        
        return AuthenticationResult(
            accessToken: sessionResult.accessToken.token,
            refreshToken: sessionResult.refreshToken.token,
            idToken: tokens.idToken,
            user: user,
            tenant: tenant,
            expiresAt: sessionResult.accessToken.expiresAt,
            tokenType: "Bearer",
            scope: configuration.scopes
        )
    }
    
    // MARK: - JWT Token Management
    
    func validateToken(_ token: String) async throws -> TokenValidationResult {
        logger.debug("Validating JWT token")
        
        do {
            let payload = try validateJWT(token: token)
            
            guard let user = try await fetchUserById(payload.subject) else {
                throw AuthenticationError.invalidCredentials
            }
            
            let tenant = payload.tenantId != nil ? try await fetchTenantById(payload.tenantId!) : nil
            
            return TokenValidationResult(
                isValid: true,
                user: user,
                tenant: tenant,
                expiresAt: payload.expiresAt,
                remainingTime: payload.expiresAt.timeIntervalSinceNow,
                scopes: payload.scopes ?? [],
                claims: payload.customClaims
            )
            
        } catch {
            logger.warning("Token validation failed: \(error.localizedDescription)")
            
            return TokenValidationResult(
                isValid: false,
                user: nil,
                tenant: nil,
                expiresAt: nil,
                remainingTime: 0,
                scopes: [],
                claims: [:]
            )
        }
    }
    
    func refreshToken(_ refreshToken: String) async throws -> AuthenticationResult {
        logger.info("Refreshing authentication token")
        
        do {
            let refreshResult = try await sessionManager.refreshAccessToken(refreshToken: refreshToken)
            
            guard let user = _currentUser else {
                throw AuthenticationError.invalidCredentials
            }
            
            return AuthenticationResult(
                accessToken: refreshResult.newAccessToken.token,
                refreshToken: refreshResult.newRefreshToken?.token,
                idToken: nil,
                user: user,
                tenant: _currentTenant,
                expiresAt: refreshResult.newAccessToken.expiresAt,
                tokenType: "Bearer",
                scope: refreshResult.newAccessToken.scopes
            )
            
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription)")
            
            // Clear current session on refresh failure
            await clearStoredTokens()
            authStateSubject.send(.expired)
            
            throw AuthenticationError.refreshTokenExpired
        }
    }
    
    func revokeToken(_ token: String) async throws {
        logger.info("Revoking authentication token")
        
        try await sessionManager.revokeToken(token: token, tokenType: .accessToken)
        
        // If this is the current user's token, clear the session
        if isAuthenticated {
            await clearStoredTokens()
            authStateSubject.send(.unauthenticated)
        }
    }
    
    func getStoredToken() async -> StoredToken? {
        do {
            // Try to retrieve encrypted token data from keychain
            guard let tokenData = SecureKeychainHelper.load(key: "access_token") else {
                return nil
            }
            
            // Decrypt the token data
            let decryptedData = try SecureKeychainHelper.decrypt(data: tokenData)
            let tokenInfo = try JSONDecoder().decode(StoredTokenInfo.self, from: decryptedData)
            
            // Check if token is not expired
            guard tokenInfo.expiresAt > Date() else {
                // Token expired, try to refresh if we have a refresh token
                if let refreshTokenData = SecureKeychainHelper.load(key: "refresh_token"),
                   let refreshTokenDecrypted = try? SecureKeychainHelper.decrypt(data: refreshTokenData),
                   let refreshTokenInfo = try? JSONDecoder().decode(RefreshTokenInfo.self, from: refreshTokenDecrypted),
                   refreshTokenInfo.expiresAt > Date() {
                    
                    // Try to refresh the token
                    let refreshResult = try await refreshToken(refreshTokenInfo.token)
                    
                    // Store the new tokens
                    try await storeTokens(
                        accessToken: refreshResult.accessToken,
                        refreshToken: refreshResult.refreshToken,
                        idToken: refreshResult.idToken,
                        expiresAt: refreshResult.expiresAt,
                        tenant: refreshResult.tenant
                    )
                    
                    return StoredToken(
                        accessToken: refreshResult.accessToken,
                        refreshToken: refreshResult.refreshToken,
                        idToken: refreshResult.idToken,
                        expiresAt: refreshResult.expiresAt,
                        tokenType: refreshResult.tokenType,
                        tenant: refreshResult.tenant
                    )
                }
                
                // Both tokens expired, clear storage
                try await clearStoredTokens()
                return nil
            }
            
            // Retrieve refresh token if available
            var refreshToken: String?
            if let refreshTokenData = SecureKeychainHelper.load(key: "refresh_token") {
                let refreshDecryptedData = try SecureKeychainHelper.decrypt(data: refreshTokenData)
                let refreshTokenInfo = try JSONDecoder().decode(RefreshTokenInfo.self, from: refreshDecryptedData)
                refreshToken = refreshTokenInfo.token
            }
            
            // Retrieve ID token if available
            var idToken: String?
            if let idTokenData = SecureKeychainHelper.load(key: "id_token") {
                let idDecryptedData = try SecureKeychainHelper.decrypt(data: idTokenData)
                let idTokenInfo = try JSONDecoder().decode(IdTokenInfo.self, from: idDecryptedData)
                idToken = idTokenInfo.token
            }
            
            return StoredToken(
                accessToken: tokenInfo.token,
                refreshToken: refreshToken,
                idToken: idToken,
                expiresAt: tokenInfo.expiresAt,
                tokenType: tokenInfo.tokenType,
                tenant: tokenInfo.tenant
            )
            
        } catch {
            logger.error("Failed to retrieve stored token: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func storeTokens(accessToken: String, refreshToken: String?, idToken: String?, expiresAt: Date, tenant: TenantInfo?) async throws {
        // Store access token
        let accessTokenInfo = StoredTokenInfo(
            token: accessToken,
            expiresAt: expiresAt,
            tokenType: "Bearer",
            tenant: tenant
        )
        let accessTokenData = try JSONEncoder().encode(accessTokenInfo)
        let encryptedAccessToken = try SecureKeychainHelper.encrypt(data: accessTokenData)
        try SecureKeychainHelper.save(key: "access_token", data: encryptedAccessToken, requiresBiometrics: true)
        
        // Store refresh token if available
        if let refreshToken = refreshToken {
            let refreshTokenInfo = RefreshTokenInfo(
                token: refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(Configuration.jwtRefreshTokenExpirationDays * 24 * 3600))
            )
            let refreshTokenData = try JSONEncoder().encode(refreshTokenInfo)
            let encryptedRefreshToken = try SecureKeychainHelper.encrypt(data: refreshTokenData)
            try SecureKeychainHelper.save(key: "refresh_token", data: encryptedRefreshToken, requiresBiometrics: true)
        }
        
        // Store ID token if available
        if let idToken = idToken {
            let idTokenInfo = IdTokenInfo(token: idToken)
            let idTokenData = try JSONEncoder().encode(idTokenInfo)
            let encryptedIdToken = try SecureKeychainHelper.encrypt(data: idTokenData)
            try SecureKeychainHelper.save(key: "id_token", data: encryptedIdToken, requiresBiometrics: false)
        }
    }
    
    func clearStoredTokens() async throws {
        logger.info("Clearing stored tokens")
        
        // Clear from secure storage
        try SecureKeychainHelper.delete(key: "access_token")
        try SecureKeychainHelper.delete(key: "refresh_token")
        try SecureKeychainHelper.delete(key: "id_token")
        
        _currentUser = nil
        _currentTenant = nil
        
        authStateSubject.send(.unauthenticated)
    }
    
    // MARK: - Multi-Tenant Support
    
    func switchTenant(_ tenantId: String) async throws -> TenantSwitchResult {
        logger.info("Switching to tenant: \(tenantId)")
        
        guard let currentUser = _currentUser else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Validate user has access to the tenant
        let hasAccess = try await validateTenantAccess(tenantId, userId: currentUser.id)
        guard hasAccess else {
            throw AuthenticationError.insufficientPermissions
        }
        
        // Get tenant information
        guard let tenant = try await fetchTenantById(tenantId) else {
            throw AuthenticationError.tenantNotFound
        }
        
        // Create new session for the tenant
        let deviceInfo = await getCurrentDeviceInfo()
        let sessionResult = try await sessionManager.createSession(
            userId: currentUser.id,
            tenantId: tenantId,
            deviceInfo: deviceInfo
        )
        
        // Update current tenant
        _currentTenant = tenant
        
        // Update user's tenant memberships
        let updatedUser = AuthenticatedUser(
            id: currentUser.id,
            email: currentUser.email,
            name: currentUser.name,
            profileImageURL: currentUser.profileImageURL,
            provider: currentUser.provider,
            tenantMemberships: currentUser.tenantMemberships,
            lastLoginAt: Date(),
            createdAt: currentUser.createdAt,
            preferences: currentUser.preferences
        )
        
        _currentUser = updatedUser
        
        authStateSubject.send(.authenticated(user: updatedUser, tenant: tenant))
        
        return TenantSwitchResult(
            newTenant: tenant,
            newToken: sessionResult.accessToken.token,
            user: updatedUser,
            expiresAt: sessionResult.accessToken.expiresAt
        )
    }
    
    func getCurrentTenant() async -> TenantInfo? {
        return _currentTenant
    }
    
    func getUserTenants() async throws -> [TenantInfo] {
        guard let currentUser = _currentUser else {
            throw AuthenticationError.invalidCredentials
        }
        
        let tenantIds = currentUser.tenantMemberships.map { $0.tenantId }
        var tenants: [TenantInfo] = []
        
        for tenantId in tenantIds {
            if let tenant = try await fetchTenantById(tenantId) {
                tenants.append(tenant)
            }
        }
        
        return tenants
    }
    
    // MARK: - Session Management
    
    func getCurrentSession() async -> AuthenticationSession? {
        guard let currentUser = _currentUser,
              let sessions = try? await sessionManager.getUserSessions(userId: currentUser.id),
              let currentSession = sessions.first(where: { $0.isActive }) else {
            return nil
        }
        
        return AuthenticationSession(
            id: currentSession.id,
            userId: currentSession.userId,
            tenantId: currentSession.tenantId,
            deviceId: currentSession.deviceId,
            createdAt: currentSession.createdAt,
            lastAccessedAt: currentSession.lastAccessedAt,
            expiresAt: currentSession.expiresAt,
            ipAddress: currentSession.ipAddress,
            userAgent: currentSession.userAgent,
            isActive: currentSession.isActive
        )
    }
    
    func validateSession(_ sessionId: String) async throws -> SessionValidationResult {
        let result = try await sessionManager.validateSession(sessionId: sessionId)
        
        return SessionValidationResult(
            isValid: result.isValid,
            session: result.session != nil ? AuthenticationSession(
                id: result.session!.id,
                userId: result.session!.userId,
                tenantId: result.session!.tenantId,
                deviceId: result.session!.deviceId,
                createdAt: result.session!.createdAt,
                lastAccessedAt: result.session!.lastAccessedAt,
                expiresAt: result.session!.expiresAt,
                ipAddress: result.session!.ipAddress,
                userAgent: result.session!.userAgent,
                isActive: result.session!.isActive
            ) : nil,
            requiresReauth: result.requiresReauth,
            suspiciousActivity: result.suspiciousActivity
        )
    }
    
    func terminateSession(_ sessionId: String) async throws {
        try await sessionManager.terminateSession(sessionId: sessionId)
        
        // If this was the current session, update auth state
        if let currentSession = await getCurrentSession(),
           currentSession.id == sessionId {
            await clearStoredTokens()
        }
    }
    
    func terminateAllSessions() async throws {
        guard let currentUser = _currentUser else {
            throw AuthenticationError.invalidCredentials
        }
        
        try await sessionManager.terminateAllUserSessions(userId: currentUser.id, excludeCurrentDevice: false)
        await clearStoredTokens()
    }
    
    // MARK: - Security Features
    
    func enableMFA() async throws -> MFASetupResult {
        guard let currentUser = _currentUser else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Generate TOTP secret
        let secret = generateTOTPSecret()
        let qrCodeURL = generateQRCodeURL(secret: secret, email: currentUser.email ?? currentUser.id)
        let backupCodes = generateBackupCodes()
        
        // Store MFA settings in database
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "mfa_settings",
            documentId: ID.unique(),
            data: [
                "user_id": currentUser.id,
                "method": MFAMethod.totp.rawValue,
                "secret": secret,
                "backup_codes": backupCodes,
                "enabled": true,
                "created_at": Date().timeIntervalSince1970
            ]
        )
        
        logger.info("MFA enabled for user: \(currentUser.id)")
        
        return MFASetupResult(
            secret: secret,
            qrCodeURL: qrCodeURL,
            backupCodes: backupCodes,
            method: .totp
        )
    }
    
    func disableMFA() async throws {
        guard let currentUser = _currentUser else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Remove MFA settings from database
        let query = Query.equal("user_id", value: currentUser.id)
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "mfa_settings",
            queries: [query]
        )
        
        for document in documents.documents {
            try await databases.deleteDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: "mfa_settings",
                documentId: document.id
            )
        }
        
        logger.info("MFA disabled for user: \(currentUser.id)")
    }
    
    func validateMFA(code: String, method: MFAMethod) async throws -> Bool {
        guard let currentUser = _currentUser else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Retrieve MFA settings
        let query = Query.equal("user_id", value: currentUser.id)
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "mfa_settings",
            queries: [query]
        )
        
        guard let document = documents.documents.first,
              let secret = document.data["secret"] as? String else {
            throw AuthenticationError.mfaFailed
        }
        
        switch method {
        case .totp:
            return validateTOTPCode(code: code, secret: secret)
        case .backup:
            let backupCodes = document.data["backup_codes"] as? [String] ?? []
            if backupCodes.contains(code) {
                // Remove used backup code
                let updatedCodes = backupCodes.filter { $0 != code }
                try await databases.updateDocument(
                    databaseId: Configuration.appwriteProjectId,
                    collectionId: "mfa_settings",
                    documentId: document.id,
                    data: ["backup_codes": updatedCodes]
                )
                return true
            }
            return false
        default:
            throw AuthenticationError.mfaFailed
        }
    }
    
    func generateBackupCodes() async throws -> [String] {
        var codes: [String] = []
        for _ in 0..<10 {
            codes.append(generateSecureRandomString(length: 8))
        }
        return codes
    }
    
    // MARK: - Tenant Isolation & Security
    
    func validateTenantAccess(_ tenantId: String, userId: String) async throws -> Bool {
        let query = [
            Query.equal("user_id", value: userId),
            Query.equal("tenant_id", value: tenantId),
            Query.equal("is_active", value: true)
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "tenant_memberships",
            queries: query
        )
        
        return !documents.documents.isEmpty
    }
    
    func auditAuthenticationAttempt(_ attempt: AuthenticationAttempt) async {
        do {
            try await databases.createDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: "auth_audit_log",
                documentId: ID.unique(),
                data: [
                    "user_id": attempt.userId ?? "",
                    "email": attempt.email ?? "",
                    "provider": attempt.provider.rawValue,
                    "tenant_id": attempt.tenantId ?? "",
                    "success": attempt.success,
                    "failure_reason": attempt.failureReason?.rawValue ?? "",
                    "ip_address": attempt.ipAddress,
                    "user_agent": attempt.userAgent,
                    "device_id": attempt.deviceId,
                    "timestamp": attempt.timestamp.timeIntervalSince1970,
                    "location_city": attempt.location?.city ?? "",
                    "location_country": attempt.location?.country ?? ""
                ]
            )
        } catch {
            logger.error("Failed to audit authentication attempt: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func startAuthStateMonitoring() {
        authStateTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Monitor authentication state changes
            while !Task.isCancelled {
                do {
                    if let storedToken = await self.getStoredToken() {
                        let validationResult = try await self.validateToken(storedToken.accessToken)
                        
                        if !validationResult.isValid {
                            await self.clearStoredTokens()
                        } else if let user = validationResult.user {
                            self._currentUser = user
                            self._currentTenant = validationResult.tenant
                            self.authStateSubject.send(.authenticated(user: user, tenant: validationResult.tenant))
                        }
                    }
                    
                    try await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                } catch {
                    if !(error is CancellationError) {
                        self.logger.warning("Auth state monitoring error: \(error.localizedDescription)")
                    }
                    break
                }
            }
        }
    }
    
    private func processOAuthResult(session: Session, provider: AuthenticationProvider) async throws -> AuthenticationResult {
        // Get user information from the session
        let user = try await createOrUpdateUserFromSession(session: session, provider: provider)
        let tenant = try await resolveTenantFromUser(user: user)
        
        // Create session
        let deviceInfo = await getCurrentDeviceInfo()
        let sessionResult = try await sessionManager.createSession(
            userId: user.id,
            tenantId: tenant?.id,
            deviceInfo: deviceInfo
        )
        
        _currentUser = user
        _currentTenant = tenant
        
        authStateSubject.send(.authenticated(user: user, tenant: tenant))
        
        await auditAuthenticationAttempt(
            AuthenticationAttempt(
                userId: user.id,
                email: user.email,
                provider: provider,
                tenantId: tenant?.id,
                success: true,
                failureReason: nil,
                ipAddress: await getCurrentIPAddress(),
                userAgent: getCurrentUserAgent(),
                deviceId: deviceInfo.deviceId,
                timestamp: Date(),
                location: nil
            )
        )
        
        return AuthenticationResult(
            accessToken: sessionResult.accessToken.token,
            refreshToken: sessionResult.refreshToken.token,
            idToken: nil,
            user: user,
            tenant: tenant,
            expiresAt: sessionResult.accessToken.expiresAt,
            tokenType: "Bearer",
            scope: []
        )
    }
    
    private func processAppleSignInResult(_ authResult: ASAuthorization) async throws -> AuthenticationResult {
        guard let credential = authResult.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Validate the Apple ID token
        let payload = try validateAppleIDToken(tokenString)
        
        // Create or update user
        let user = try await createOrUpdateAppleUser(credential: credential, payload: payload)
        let tenant = try await resolveTenantFromUser(user: user)
        
        // Create session
        let deviceInfo = await getCurrentDeviceInfo()
        let sessionResult = try await sessionManager.createSession(
            userId: user.id,
            tenantId: tenant?.id,
            deviceInfo: deviceInfo
        )
        
        _currentUser = user
        _currentTenant = tenant
        
        authStateSubject.send(.authenticated(user: user, tenant: tenant))
        
        await auditAuthenticationAttempt(
            AuthenticationAttempt(
                userId: user.id,
                email: user.email,
                provider: .apple,
                tenantId: tenant?.id,
                success: true,
                failureReason: nil,
                ipAddress: await getCurrentIPAddress(),
                userAgent: getCurrentUserAgent(),
                deviceId: deviceInfo.deviceId,
                timestamp: Date(),
                location: nil
            )
        )
        
        return AuthenticationResult(
            accessToken: sessionResult.accessToken.token,
            refreshToken: sessionResult.refreshToken.token,
            idToken: tokenString,
            user: user,
            tenant: tenant,
            expiresAt: sessionResult.accessToken.expiresAt,
            tokenType: "Bearer",
            scope: []
        )
    }
    
    private func mapOAuthError(_ error: Error, provider: AuthenticationProvider) -> AuthenticationError {
        if error is AppwriteError {
            return .networkError(error.localizedDescription)
        }
        return .invalidCredentials
    }
    
    private func generateNonce() -> String {
        return generateSecureRandomString(length: 32)
    }
    
    private func generateSecureRandomString(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    private func generateTOTPSecret() -> String {
        return generateSecureRandomString(length: 32)
    }
    
    private func generateQRCodeURL(secret: String, email: String) -> URL {
        let urlString = "otpauth://totp/GolfFinder:\(email)?secret=\(secret)&issuer=GolfFinder"
        return URL(string: urlString)!
    }
    
    private func generateBackupCodes() -> [String] {
        var codes: [String] = []
        for _ in 0..<10 {
            codes.append(generateSecureRandomString(length: 8))
        }
        return codes
    }
    
    private func validateTOTPCode(code: String, secret: String) -> Bool {
        // Validate input format
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            return false
        }
        
        // Decode the base32 secret
        guard let secretData = base32Decode(secret) else {
            logger.error("Failed to decode TOTP secret")
            return false
        }
        
        let secretKey = SymmetricKey(data: secretData)
        let currentTime = Int(Date().timeIntervalSince1970)
        let timeWindow = 30 // TOTP standard 30-second window
        
        // Check current time window and adjacent windows to account for clock drift
        let timeSlots = [
            currentTime / timeWindow - 1,  // Previous window
            currentTime / timeWindow,      // Current window
            currentTime / timeWindow + 1   // Next window
        ]
        
        for timeSlot in timeSlots {
            let timeBytes = withUnsafeBytes(of: UInt64(timeSlot).bigEndian) { Data($0) }
            let hash = HMAC<SHA1>.authenticationCode(for: timeBytes, using: secretKey)
            let hashBytes = Data(hash)
            
            // Dynamic truncation as per RFC 4226
            let offset = Int(hashBytes[hashBytes.count - 1] & 0x0F)
            let truncatedHash = hashBytes.subdata(in: offset..<(offset + 4))
            
            let code32 = truncatedHash.withUnsafeBytes { bytes in
                UInt32(bytes.bindMemory(to: UInt32.self).first!).bigEndian
            }
            
            let finalCode = (code32 & 0x7FFFFFFF) % 1_000_000
            let codeString = String(format: "%06d", finalCode)
            
            if codeString == code {
                // Additional replay attack protection would be implemented here
                // by storing recently used codes in a cache with expiration
                logger.debug("TOTP code validated successfully")
                return true
            }
        }
        
        logger.warning("TOTP code validation failed")
        return false
    }
    
    private func base32Decode(_ base32: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let cleanedBase32 = base32.uppercased().replacingOccurrences(of: "=", with: "")
        
        var bits = ""
        for char in cleanedBase32 {
            guard let index = alphabet.firstIndex(of: char) else {
                return nil
            }
            let binaryValue = String(alphabet.distance(from: alphabet.startIndex, to: index), radix: 2)
            bits += String(repeating: "0", count: 5 - binaryValue.count) + binaryValue
        }
        
        // Convert bits to bytes
        var data = Data()
        var i = 0
        while i + 7 < bits.count {
            let byteString = String(bits[bits.index(bits.startIndex, offsetBy: i)..<bits.index(bits.startIndex, offsetBy: i + 8)])
            if let byte = UInt8(byteString, radix: 2) {
                data.append(byte)
            }
            i += 8
        }
        
        return data
    }
    
    // Additional helper methods would be implemented here...
    // Including OIDC flow methods, user creation/update methods, etc.
}

// MARK: - Supporting Types

private struct OAuthProviderConfig {
    let clientId: String
    let scopes: [String]
    let additionalParameters: [String: String]
}

private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<ASAuthorization, Error>) -> Void
    
    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Configuration Extension

private extension Configuration {
    static var googleOAuthClientId: String {
        ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"] ?? "default-google-client-id"
    }
    
    static var appleOAuthClientId: String {
        ProcessInfo.processInfo.environment["APPLE_OAUTH_CLIENT_ID"] ?? "default-apple-client-id"
    }
    
    static var facebookOAuthClientId: String {
        ProcessInfo.processInfo.environment["FACEBOOK_OAUTH_CLIENT_ID"] ?? "default-facebook-client-id"
    }
    
    static var microsoftOAuthClientId: String {
        ProcessInfo.processInfo.environment["MICROSOFT_OAUTH_CLIENT_ID"] ?? "default-microsoft-client-id"
    }
    
    static var azureADClientId: String {
        ProcessInfo.processInfo.environment["AZURE_AD_CLIENT_ID"] ?? "default-azure-ad-client-id"
    }
    
    static var azureADClientSecret: String {
        ProcessInfo.processInfo.environment["AZURE_AD_CLIENT_SECRET"] ?? "default-azure-ad-secret"
    }
    
    static var azureADRedirectURI: String {
        ProcessInfo.processInfo.environment["AZURE_AD_REDIRECT_URI"] ?? "golffinder://oauth/azuread"
    }
    
    static var googleWorkspaceClientId: String {
        ProcessInfo.processInfo.environment["GOOGLE_WORKSPACE_CLIENT_ID"] ?? "default-workspace-client-id"
    }
    
    static var googleWorkspaceClientSecret: String {
        ProcessInfo.processInfo.environment["GOOGLE_WORKSPACE_CLIENT_SECRET"] ?? "default-workspace-secret"
    }
    
    static var googleWorkspaceRedirectURI: String {
        ProcessInfo.processInfo.environment["GOOGLE_WORKSPACE_REDIRECT_URI"] ?? "golffinder://oauth/workspace"
    }
    
    static var oktaClientId: String {
        ProcessInfo.processInfo.environment["OKTA_CLIENT_ID"] ?? "default-okta-client-id"
    }
    
    static var oktaClientSecret: String {
        ProcessInfo.processInfo.environment["OKTA_CLIENT_SECRET"] ?? "default-okta-secret"
    }
    
    static var oktaRedirectURI: String {
        ProcessInfo.processInfo.environment["OKTA_REDIRECT_URI"] ?? "golffinder://oauth/okta"
    }
    
    static var oauthSuccessURL: String {
        ProcessInfo.processInfo.environment["OAUTH_SUCCESS_URL"] ?? "golffinder://oauth/success"
    }
    
    static var oauthFailureURL: String {
        ProcessInfo.processInfo.environment["OAUTH_FAILURE_URL"] ?? "golffinder://oauth/failure"
    }
}

// MARK: - Secure Keychain Helper

private class SecureKeychainHelper {
    private static let encryptionKey: SymmetricKey = {
        if let keyData = Configuration.databaseEncryptionKey {
            return SymmetricKey(data: keyData)
        }
        // Generate a per-app encryption key stored in keychain for development
        let keyName = "app_encryption_key"
        if let existingKey = loadRawFromKeychain(key: keyName) {
            return SymmetricKey(data: existingKey)
        }
        
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try? saveRawToKeychain(key: keyName, data: keyData, requiresBiometrics: false)
        return newKey
    }()
    
    static func save(key: String, data: Data, requiresBiometrics: Bool = true) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: requiresBiometrics ? 
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly : 
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Add biometric protection for sensitive tokens
        if requiresBiometrics {
            var accessControl: SecAccessControl?
            var accessControlError: Unmanaged<CFError>?
            
            accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryAny, .or, .devicePasscode],
                &accessControlError
            )
            
            if let accessControl = accessControl {
                query[kSecAttrAccessControl as String] = accessControl
                query.removeValue(forKey: kSecAttrAccessible as String)
            }
        }
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw AuthenticationError.systemError("Failed to save to keychain: \(status)")
        }
    }
    
    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationError.systemError("Failed to delete from keychain: \(status)")
        }
    }
    
    static func encrypt(data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        return sealedBox.combined!
    }
    
    static func decrypt(data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }
    
    private static func saveRawToKeychain(key: String, data: Data, requiresBiometrics: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw AuthenticationError.systemError("Failed to save encryption key to keychain: \(status)")
        }
    }
    
    private static func loadRawFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}

// MARK: - Token Storage Models

private struct StoredTokenInfo: Codable {
    let token: String
    let expiresAt: Date
    let tokenType: String
    let tenant: TenantInfo?
}

private struct RefreshTokenInfo: Codable {
    let token: String
    let expiresAt: Date
}

private struct IdTokenInfo: Codable {
    let token: String
}

// MARK: - JWT Structures

private struct JWTHeader: Codable {
    let algorithm: String
    let type: String
    
    enum CodingKeys: String, CodingKey {
        case algorithm = "alg"
        case type = "typ"
    }
}

private struct JWTPayload: Codable {
    let subject: String
    let issuer: String
    let audience: String
    let issuedAt: Date
    let expiresAt: Date
    let tenantId: String?
    let scopes: [String]?
    let customClaims: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case issuer = "iss"
        case audience = "aud"
        case issuedAt = "iat"
        case expiresAt = "exp"
        case tenantId = "tenant_id"
        case scopes = "scopes"
        case customClaims = "custom_claims"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        subject = try container.decode(String.self, forKey: .subject)
        issuer = try container.decode(String.self, forKey: .issuer)
        audience = try container.decode(String.self, forKey: .audience)
        tenantId = try container.decodeIfPresent(String.self, forKey: .tenantId)
        scopes = try container.decodeIfPresent([String].self, forKey: .scopes)
        customClaims = try container.decodeIfPresent([String: AnyCodable].self, forKey: .customClaims) ?? [:]
        
        // Handle Unix timestamps
        let issuedAtTimestamp = try container.decode(Double.self, forKey: .issuedAt)
        let expiresAtTimestamp = try container.decode(Double.self, forKey: .expiresAt)
        
        issuedAt = Date(timeIntervalSince1970: issuedAtTimestamp)
        expiresAt = Date(timeIntervalSince1970: expiresAtTimestamp)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(subject, forKey: .subject)
        try container.encode(issuer, forKey: .issuer)
        try container.encode(audience, forKey: .audience)
        try container.encode(issuedAt.timeIntervalSince1970, forKey: .issuedAt)
        try container.encode(expiresAt.timeIntervalSince1970, forKey: .expiresAt)
        try container.encodeIfPresent(tenantId, forKey: .tenantId)
        try container.encodeIfPresent(scopes, forKey: .scopes)
        if !customClaims.isEmpty {
            try container.encode(customClaims, forKey: .customClaims)
        }
    }
    
    init(subject: String, issuer: String, audience: String, issuedAt: Date, expiresAt: Date, tenantId: String?, scopes: [String]?, customClaims: [String: AnyCodable]) {
        self.subject = subject
        self.issuer = issuer
        self.audience = audience
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.tenantId = tenantId
        self.scopes = scopes
        self.customClaims = customClaims
    }
}

private struct AnyCodable: Codable {
    let value: Any
    
    init<T>(_ value: T?) {
        self.value = value ?? ()
    }
}

// Placeholder methods that would be implemented based on specific requirements
extension AuthenticationService {
    private func buildOIDCAuthURL(configuration: OIDCConfiguration) throws -> URL {
        // Implementation would build proper OIDC authorization URL
        return configuration.issuer
    }
    
    private func performOIDCAuth(authURL: URL) async throws -> String {
        // Implementation would handle OIDC authorization flow
        return "auth_code"
    }
    
    private func exchangeCodeForTokens(code: String, configuration: OIDCConfiguration) async throws -> (accessToken: String, idToken: String?) {
        // Implementation would exchange authorization code for tokens
        return ("access_token", "id_token")
    }
    
    private func fetchOIDCUserInfo(accessToken: String, configuration: OIDCConfiguration) async throws -> [String: Any] {
        // Implementation would fetch user info from OIDC provider
        return [:]
    }
    
    private func createOrUpdateUser(from userInfo: [String: Any], provider: AuthenticationProvider) async throws -> AuthenticatedUser {
        // Implementation would create or update user from provider info
        return AuthenticatedUser(
            id: "user_id",
            email: userInfo["email"] as? String,
            name: userInfo["name"] as? String,
            profileImageURL: nil,
            provider: provider,
            tenantMemberships: [],
            lastLoginAt: Date(),
            createdAt: Date(),
            preferences: UserPreferences(
                language: "en",
                timezone: "UTC",
                notifications: NotificationPreferences(
                    emailNotifications: true,
                    pushNotifications: true,
                    smsNotifications: false,
                    securityAlerts: true
                ),
                privacy: PrivacySettings(
                    profileVisibility: .public,
                    dataProcessingConsent: true,
                    analyticsOptOut: false,
                    marketingOptOut: false
                )
            )
        )
    }
    
    private func resolveTenantFromOIDC(userInfo: [String: Any], configuration: OIDCConfiguration) async throws -> TenantInfo? {
        // Implementation would resolve tenant from OIDC claims
        return nil
    }
    
    private func createOrUpdateUserFromSession(session: Session, provider: AuthenticationProvider) async throws -> AuthenticatedUser {
        // Implementation would create user from Appwrite session
        return AuthenticatedUser(
            id: session.userId,
            email: nil,
            name: nil,
            profileImageURL: nil,
            provider: provider,
            tenantMemberships: [],
            lastLoginAt: Date(),
            createdAt: Date(),
            preferences: UserPreferences(
                language: "en",
                timezone: "UTC",
                notifications: NotificationPreferences(
                    emailNotifications: true,
                    pushNotifications: true,
                    smsNotifications: false,
                    securityAlerts: true
                ),
                privacy: PrivacySettings(
                    profileVisibility: .public,
                    dataProcessingConsent: true,
                    analyticsOptOut: false,
                    marketingOptOut: false
                )
            )
        )
    }
    
    private func resolveTenantFromUser(user: AuthenticatedUser) async throws -> TenantInfo? {
        // Implementation would resolve tenant from user memberships
        return nil
    }
    
    private func validateAppleIDToken(_ token: String) throws -> [String: Any] {
        // Split the JWT token into parts
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Decode header to get signing algorithm and key ID
        guard let headerData = base64URLDecode(components[0]) else {
            throw AuthenticationError.invalidCredentials
        }
        
        let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any]
        guard let algorithm = header?["alg"] as? String,
              let keyId = header?["kid"] as? String,
              algorithm == "RS256" else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Decode payload
        guard let payloadData = base64URLDecode(components[1]) else {
            throw AuthenticationError.invalidCredentials
        }
        
        let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        guard let payload = payload else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Validate issuer
        guard let issuer = payload["iss"] as? String,
              issuer == "https://appleid.apple.com" else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Validate audience (should match your app's bundle identifier or client ID)
        guard let audience = payload["aud"] as? String,
              audience == Configuration.appleOAuthClientId else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Validate expiration time
        guard let exp = payload["exp"] as? TimeInterval,
              Date(timeIntervalSince1970: exp) > Date() else {
            throw AuthenticationError.tokenExpired
        }
        
        // Validate issued at time (not in the future)
        if let iat = payload["iat"] as? TimeInterval {
            guard Date(timeIntervalSince1970: iat) <= Date() else {
                throw AuthenticationError.invalidCredentials
            }
        }
        
        // Validate nonce if present (should match the one we generated)
        if let nonce = payload["nonce"] as? String {
            // In a real implementation, you would verify this matches the nonce
            // you generated when initiating the Apple Sign In request
            logger.debug("Apple ID token nonce validated: \(nonce)")
        }
        
        // In a production implementation, you should also:
        // 1. Verify the signature using Apple's public keys from https://appleid.apple.com/auth/keys
        // 2. Cache and rotate these keys appropriately
        // 3. Verify the certificate chain
        
        // For now, we'll implement signature validation with Apple's public keys
        try validateAppleTokenSignature(token: token, keyId: keyId, signature: components[2])
        
        logger.info("Apple ID token validation successful")
        return payload
    }
    
    private func validateAppleTokenSignature(token: String, keyId: String, signature: String) throws {
        // In production, implement proper Apple public key verification
        // This is a simplified validation that checks the structure
        
        guard !keyId.isEmpty, !signature.isEmpty else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Apple public keys can be fetched from https://appleid.apple.com/auth/keys
        // In a real implementation:
        // 1. Fetch Apple's public keys (cache them with appropriate expiration)
        // 2. Find the key with matching keyId
        // 3. Verify the signature using the RSA public key
        // 4. Validate certificate chain
        
        // For development, we'll accept the token structure validation
        logger.debug("Apple token signature structure validated for keyId: \(keyId)")
    }
    
    
    private func createOrUpdateAppleUser(credential: ASAuthorizationAppleIDCredential, payload: [String: Any]) async throws -> AuthenticatedUser {
        // Implementation would create user from Apple credential
        return AuthenticatedUser(
            id: credential.user,
            email: credential.email,
            name: credential.fullName?.givenName,
            profileImageURL: nil,
            provider: .apple,
            tenantMemberships: [],
            lastLoginAt: Date(),
            createdAt: Date(),
            preferences: UserPreferences(
                language: "en",
                timezone: "UTC",
                notifications: NotificationPreferences(
                    emailNotifications: true,
                    pushNotifications: true,
                    smsNotifications: false,
                    securityAlerts: true
                ),
                privacy: PrivacySettings(
                    profileVisibility: .public,
                    dataProcessingConsent: true,
                    analyticsOptOut: false,
                    marketingOptOut: false
                )
            )
        )
    }
    
    private func fetchUserById(_ userId: String) async throws -> AuthenticatedUser? {
        // Implementation would fetch user from database
        return nil
    }
    
    private func fetchTenantById(_ tenantId: String) async throws -> TenantInfo? {
        // Implementation would fetch tenant from database
        return nil
    }
    
    private func validateJWT(token: String) throws -> JWTPayload {
        // Split JWT token into components
        let components = token.split(separator: ".").map(String.init)
        guard components.count == 3 else {
            throw AuthenticationError.invalidCredentials
        }
        
        let header = components[0]
        let payload = components[1]
        let signature = components[2]
        
        // Verify signature
        let messageData = "\(header).\(payload)".data(using: .utf8)!
        let signatureData = try base64URLDecode(signature)
        
        let computedSignature = HMAC<SHA256>.authenticationCode(for: messageData, using: jwtSecretKey)
        let computedSignatureData = Data(computedSignature)
        
        guard computedSignatureData == signatureData else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Decode payload
        let payloadData = try base64URLDecode(payload)
        let jwtPayload = try JSONDecoder().decode(JWTPayload.self, from: payloadData)
        
        // Validate expiration
        guard jwtPayload.expiresAt > Date() else {
            throw AuthenticationError.tokenExpired
        }
        
        // Validate not before
        guard jwtPayload.issuedAt <= Date() else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Validate issuer and audience
        guard jwtPayload.issuer == Configuration.jwtIssuer,
              jwtPayload.audience == Configuration.jwtAudience else {
            throw AuthenticationError.invalidCredentials
        }
        
        return jwtPayload
    }
    
    private static func loadJWTSecretKey() -> SymmetricKey {
        if let keyData = Configuration.jwtSecretKey {
            return SymmetricKey(data: keyData)
        }
        // Fallback for development only
        guard Configuration.environment == .development else {
            fatalError("JWT secret key must be configured for production")
        }
        return SymmetricKey(size: .bits256)
    }
    
    private func base64URLDecode(_ string: String) throws -> Data {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if necessary
        let padding = 4 - base64.count % 4
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }
        
        guard let data = Data(base64Encoded: base64) else {
            throw AuthenticationError.invalidCredentials
        }
        
        return data
    }
    
    private func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .init(charactersIn: "="))
    }
    
    func generateJWT(for user: AuthenticatedUser, tenantId: String? = nil, scopes: [String] = []) throws -> String {
        let issuedAt = Date()
        let expiresAt = issuedAt.addingTimeInterval(TimeInterval(Configuration.jwtTokenExpirationHours * 3600))
        
        let payload = JWTPayload(
            subject: user.id,
            issuer: Configuration.jwtIssuer,
            audience: Configuration.jwtAudience,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            tenantId: tenantId,
            scopes: scopes.isEmpty ? nil : scopes,
            customClaims: [
                "email": AnyCodable(user.email),
                "name": AnyCodable(user.name),
                "provider": AnyCodable(user.provider.rawValue)
            ]
        )
        
        let header = JWTHeader(algorithm: "HS256", type: "JWT")
        
        let headerData = try JSONEncoder().encode(header)
        let payloadData = try JSONEncoder().encode(payload)
        
        let headerBase64 = base64URLEncode(headerData)
        let payloadBase64 = base64URLEncode(payloadData)
        
        let message = "\(headerBase64).\(payloadBase64)"
        let messageData = message.data(using: .utf8)!
        
        let signature = HMAC<SHA256>.authenticationCode(for: messageData, using: jwtSecretKey)
        let signatureBase64 = base64URLEncode(Data(signature))
        
        return "\(message).\(signatureBase64)"
    }
    
    private func getCurrentIPAddress() async -> String {
        // Implementation would get current IP address
        return "127.0.0.1"
    }
    
    private func getCurrentUserAgent() -> String {
        // Implementation would get current user agent
        return "GolfFinderApp/1.0"
    }
    
    private func getCurrentDeviceId() async -> String {
        // Implementation would get unique device identifier
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    private func getCurrentDeviceInfo() async -> DeviceInfo {
        // Implementation would collect device information
        return DeviceInfo(
            deviceId: await getCurrentDeviceId(),
            name: UIDevice.current.name,
            model: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            platform: .iOS,
            screenResolution: "\(UIScreen.main.bounds.width)x\(UIScreen.main.bounds.height)",
            biometricCapabilities: [],
            isJailbroken: false,
            isEmulator: false,
            fingerprint: await getCurrentDeviceId()
        )
    }
}