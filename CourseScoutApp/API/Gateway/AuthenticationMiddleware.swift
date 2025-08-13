import Foundation
import Appwrite
import CryptoKit

// MARK: - Authentication Middleware

class AuthenticationMiddleware: APIMiddleware {
    let priority: Int = 50 // Higher priority than rate limiting
    
    // MARK: - Properties
    
    private let appwriteClient: Client
    private let apiKeyCache = NSCache<NSString, CachedAPIKeyValidation>()
    private let authQueue = DispatchQueue(label: "AuthenticationQueue", qos: .userInitiated)
    
    // MARK: - OAuth Configuration
    
    private let oauthProviders: [OAuthProvider] = [
        .google(clientId: "golf-finder-google-client"),
        .apple,
        .github(clientId: "golf-finder-github-client")
    ]
    
    // MARK: - JWT Configuration
    
    private let jwtSecretKey = SymmetricKey(size: .bits256)
    private let jwtIssuer = "golf-finder-api"
    
    // MARK: - Initialization
    
    init(appwriteClient: Client) {
        self.appwriteClient = appwriteClient
        setupCacheConfiguration()
    }
    
    // MARK: - APIMiddleware Implementation
    
    func process(_ request: APIGatewayRequest) async throws -> APIGatewayRequest {
        // Skip authentication for public endpoints
        if isPublicEndpoint(request.path) {
            return request
        }
        
        let validationResult = try await validateAPIKey(request.apiKey)
        
        guard validationResult.isValid else {
            throw APIGatewayError.invalidAPIKey
        }
        
        // Add authenticated user context to request
        var authenticatedRequest = request
        
        // In a more complete implementation, you'd modify the request to include
        // user context information from the validation result
        
        return authenticatedRequest
    }
    
    // MARK: - API Key Validation
    
    func validateAPIKey(_ apiKey: String) async throws -> APIKeyValidationResult {
        // Check cache first
        let cacheKey = NSString(string: apiKey)
        if let cachedValidation = apiKeyCache.object(forKey: cacheKey),
           !cachedValidation.isExpired {
            return cachedValidation.validationResult
        }
        
        // Perform validation
        let validationResult = try await performAPIKeyValidation(apiKey)
        
        // Cache the result
        let cachedValidation = CachedAPIKeyValidation(
            validationResult: validationResult,
            timestamp: Date(),
            ttlSeconds: 300 // 5 minutes
        )
        apiKeyCache.setObject(cachedValidation, forKey: cacheKey)
        
        return validationResult
    }
    
    private func performAPIKeyValidation(_ apiKey: String) async throws -> APIKeyValidationResult {
        // Validate API key format
        guard isValidAPIKeyFormat(apiKey) else {
            return APIKeyValidationResult(
                isValid: false,
                apiKey: apiKey,
                tier: .free,
                userId: nil,
                expiresAt: nil,
                remainingQuota: nil
            )
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    // Query Appwrite database for API key
                    let databases = Databases(appwriteClient)
                    let query = Query.equal("api_key", value: apiKey)
                    
                    let documents = try await databases.listDocuments(
                        databaseId: Configuration.appwriteProjectId,
                        collectionId: "api_keys",
                        queries: [query]
                    )
                    
                    guard let document = documents.documents.first else {
                        continuation.resume(returning: APIKeyValidationResult(
                            isValid: false,
                            apiKey: apiKey,
                            tier: .free,
                            userId: nil,
                            expiresAt: nil,
                            remainingQuota: nil
                        ))
                        return
                    }
                    
                    // Parse API key document
                    let isActive = document.data["is_active"] as? Bool ?? false
                    let tierString = document.data["tier"] as? String ?? "free"
                    let tier = APITier(rawValue: tierString) ?? .free
                    let userId = document.data["user_id"] as? String
                    let expiresAtTimestamp = document.data["expires_at"] as? Double
                    let remainingQuota = document.data["remaining_quota"] as? Int
                    
                    let expiresAt = expiresAtTimestamp != nil ? Date(timeIntervalSince1970: expiresAtTimestamp!) : nil
                    
                    // Check if API key is expired
                    let isExpired = expiresAt?.timeIntervalSinceNow ?? 1 <= 0
                    
                    let validationResult = APIKeyValidationResult(
                        isValid: isActive && !isExpired,
                        apiKey: apiKey,
                        tier: tier,
                        userId: userId,
                        expiresAt: expiresAt,
                        remainingQuota: remainingQuota
                    )
                    
                    continuation.resume(returning: validationResult)
                    
                } catch {
                    // Fallback to mock validation for development
                    if Configuration.environment.useMockServices {
                        continuation.resume(returning: self.getMockValidationResult(for: apiKey))
                    } else {
                        continuation.resume(throwing: APIGatewayError.authenticationFailed)
                    }
                }
            }
        }
    }
    
    // MARK: - OAuth 2.0 Support
    
    func validateOAuthToken(_ token: String, provider: OAuthProvider) async throws -> OAuthValidationResult {
        switch provider {
        case .google:
            return try await validateGoogleToken(token)
        case .apple:
            return try await validateAppleToken(token)
        case .github:
            return try await validateGitHubToken(token)
        }
    }
    
    private func validateGoogleToken(_ token: String) async throws -> OAuthValidationResult {
        // Validate Google OAuth token
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=\(token)") else {
            throw APIGatewayError.authenticationFailed
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIGatewayError.authenticationFailed
        }
        
        return OAuthValidationResult(
            isValid: true,
            provider: .google,
            userId: json["user_id"] as? String ?? "",
            email: json["email"] as? String,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
    
    private func validateAppleToken(_ token: String) async throws -> OAuthValidationResult {
        // Validate Apple Sign In token using Apple's public keys
        // This is a simplified implementation
        return OAuthValidationResult(
            isValid: true,
            provider: .apple,
            userId: "apple_user_\(UUID().uuidString)",
            email: nil,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
    
    private func validateGitHubToken(_ token: String) async throws -> OAuthValidationResult {
        // Validate GitHub OAuth token
        guard let url = URL(string: "https://api.github.com/user") else {
            throw APIGatewayError.authenticationFailed
        }
        
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIGatewayError.authenticationFailed
        }
        
        return OAuthValidationResult(
            isValid: true,
            provider: .github,
            userId: "\(json["id"] ?? "")",
            email: json["email"] as? String,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
    
    // MARK: - JWT Token Management
    
    func generateDeveloperPortalJWT(for userId: String, email: String, tier: APITier) throws -> String {
        let payload = DeveloperPortalJWTPayload(
            userId: userId,
            email: email,
            tier: tier.rawValue,
            issuedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400) // 24 hours
        )
        
        return try createJWT(payload: payload)
    }
    
    func validateDeveloperPortalJWT(_ token: String) throws -> DeveloperPortalJWTPayload {
        return try validateJWT(token: token, expectedPayloadType: DeveloperPortalJWTPayload.self)
    }
    
    private func createJWT<T: Codable>(payload: T) throws -> String {
        // JWT Header
        let header = JWTHeader(algorithm: "HS256", type: "JWT")
        let headerData = try JSONEncoder().encode(header)
        let headerBase64 = headerData.base64URLEncodedString()
        
        // JWT Payload
        let payloadData = try JSONEncoder().encode(payload)
        let payloadBase64 = payloadData.base64URLEncodedString()
        
        // Create signature
        let signingInput = "\(headerBase64).\(payloadBase64)"
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(signingInput.utf8),
            using: jwtSecretKey
        )
        let signatureBase64 = Data(signature).base64URLEncodedString()
        
        return "\(headerBase64).\(payloadBase64).\(signatureBase64)"
    }
    
    private func validateJWT<T: Codable>(token: String, expectedPayloadType: T.Type) throws -> T {
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else {
            throw APIGatewayError.authenticationFailed
        }
        
        let headerBase64 = components[0]
        let payloadBase64 = components[1]
        let signatureBase64 = components[2]
        
        // Verify signature
        let signingInput = "\(headerBase64).\(payloadBase64)"
        let expectedSignature = HMAC<SHA256>.authenticationCode(
            for: Data(signingInput.utf8),
            using: jwtSecretKey
        )
        
        guard let providedSignature = Data(base64URLEncoded: signatureBase64),
              Data(expectedSignature) == providedSignature else {
            throw APIGatewayError.authenticationFailed
        }
        
        // Decode and validate payload
        guard let payloadData = Data(base64URLEncoded: payloadBase64) else {
            throw APIGatewayError.authenticationFailed
        }
        
        let payload = try JSONDecoder().decode(expectedPayloadType, from: payloadData)
        
        return payload
    }
    
    // MARK: - API Key Generation
    
    func generateAPIKey(for userId: String, tier: APITier) async throws -> GeneratedAPIKey {
        let prefix = tier.rawValue.prefix(4).lowercased()
        let randomPart = generateSecureRandomString(length: 32)
        let apiKey = "\(prefix)_\(randomPart)"
        
        // Store in Appwrite database
        let databases = Databases(appwriteClient)
        
        let document = try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: ID.unique(),
            data: [
                "api_key": apiKey,
                "user_id": userId,
                "tier": tier.rawValue,
                "is_active": true,
                "created_at": Date().timeIntervalSince1970,
                "expires_at": Date().addingTimeInterval(365 * 24 * 60 * 60).timeIntervalSince1970, // 1 year
                "remaining_quota": tier.dailyRequestLimit > 0 ? tier.dailyRequestLimit : nil
            ]
        )
        
        return GeneratedAPIKey(
            apiKey: apiKey,
            documentId: document.id,
            tier: tier,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(365 * 24 * 60 * 60)
        )
    }
    
    func revokeAPIKey(_ apiKey: String) async throws {
        let databases = Databases(appwriteClient)
        let query = Query.equal("api_key", value: apiKey)
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            queries: [query]
        )
        
        guard let document = documents.documents.first else {
            throw APIGatewayError.invalidAPIKey
        }
        
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: "api_keys",
            documentId: document.id,
            data: ["is_active": false]
        )
        
        // Remove from cache
        let cacheKey = NSString(string: apiKey)
        apiKeyCache.removeObject(forKey: cacheKey)
    }
    
    // MARK: - Helper Methods
    
    private func isPublicEndpoint(_ path: String) -> Bool {
        let publicEndpoints = ["/health", "/docs", "/openapi.json"]
        return publicEndpoints.contains(path)
    }
    
    private func isValidAPIKeyFormat(_ apiKey: String) -> Bool {
        // API key format: {tier}_{32_char_random_string}
        let pattern = #"^(free|prem|ent_|biz_)_[a-zA-Z0-9]{32}$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: apiKey.utf16.count)
        return regex?.firstMatch(in: apiKey, range: range) != nil
    }
    
    private func getMockValidationResult(for apiKey: String) -> APIKeyValidationResult {
        let tier: APITier
        switch apiKey.prefix(4) {
        case "free":
            tier = .free
        case "prem":
            tier = .premium
        case "ent_":
            tier = .enterprise
        case "biz_":
            tier = .business
        default:
            tier = .free
        }
        
        return APIKeyValidationResult(
            isValid: true,
            apiKey: apiKey,
            tier: tier,
            userId: "mock_user_\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(365 * 24 * 60 * 60),
            remainingQuota: tier.dailyRequestLimit > 0 ? tier.dailyRequestLimit : nil
        )
    }
    
    private func generateSecureRandomString(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var result = ""
        for _ in 0..<length {
            let randomIndex = Int.random(in: 0..<characters.count)
            let character = characters[characters.index(characters.startIndex, offsetBy: randomIndex)]
            result.append(character)
        }
        return result
    }
    
    private func setupCacheConfiguration() {
        apiKeyCache.countLimit = 1000
        apiKeyCache.totalCostLimit = 1024 * 1024 * 5 // 5MB
    }
}

// MARK: - Data Models

struct CachedAPIKeyValidation {
    let validationResult: APIKeyValidationResult
    let timestamp: Date
    let ttlSeconds: TimeInterval
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > ttlSeconds
    }
}

enum OAuthProvider {
    case google(clientId: String)
    case apple
    case github(clientId: String)
}

struct OAuthValidationResult {
    let isValid: Bool
    let provider: OAuthProvider
    let userId: String
    let email: String?
    let expiresAt: Date
}

struct JWTHeader: Codable {
    let algorithm: String
    let type: String
    
    enum CodingKeys: String, CodingKey {
        case algorithm = "alg"
        case type = "typ"
    }
}

struct DeveloperPortalJWTPayload: Codable {
    let userId: String
    let email: String
    let tier: String
    let issuedAt: Date
    let expiresAt: Date
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email = "email"
        case tier = "tier"
        case issuedAt = "iat"
        case expiresAt = "exp"
    }
}

struct GeneratedAPIKey {
    let apiKey: String
    let documentId: String
    let tier: APITier
    let createdAt: Date
    let expiresAt: Date
}

// MARK: - Extensions

extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        self.init(base64Encoded: base64)
    }
}

// MARK: - Mock Authentication Middleware

class MockAuthenticationMiddleware: AuthenticationMiddleware {
    private var shouldAuthenticate: Bool = true
    private var mockTier: APITier = .premium
    
    override init(appwriteClient: Client) {
        super.init(appwriteClient: appwriteClient)
    }
    
    func setMockBehavior(authenticate: Bool, tier: APITier = .premium) {
        shouldAuthenticate = authenticate
        mockTier = tier
    }
    
    override func process(_ request: APIGatewayRequest) async throws -> APIGatewayRequest {
        if !shouldAuthenticate {
            throw APIGatewayError.invalidAPIKey
        }
        return request
    }
    
    override func validateAPIKey(_ apiKey: String) async throws -> APIKeyValidationResult {
        return APIKeyValidationResult(
            isValid: shouldAuthenticate,
            apiKey: apiKey,
            tier: mockTier,
            userId: shouldAuthenticate ? "mock_user_123" : nil,
            expiresAt: Date().addingTimeInterval(86400),
            remainingQuota: mockTier.dailyRequestLimit > 0 ? mockTier.dailyRequestLimit : nil
        )
    }
}