import Foundation

// MARK: - Configuration Management

struct Configuration {
    // MARK: - Environment Detection
    
    static var environment: Environment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
    
    // MARK: - Appwrite Configuration
    
    static var appwriteEndpoint: String {
        ProcessInfo.processInfo.environment["APPWRITE_ENDPOINT"] ?? defaultAppwriteEndpoint
    }
    
    static var appwriteProjectId: String {
        ProcessInfo.processInfo.environment["APPWRITE_PROJECT_ID"] ?? defaultAppwriteProjectId
    }
    
    static var appwriteApiKey: String? {
        ProcessInfo.processInfo.environment["APPWRITE_API_KEY"]
    }
    
    // MARK: - Golf API Configuration
    
    static var golfApiBaseUrl: String {
        ProcessInfo.processInfo.environment["GOLF_API_BASE_URL"] ?? defaultGolfApiUrl
    }
    
    static var golfApiKey: String? {
        ProcessInfo.processInfo.environment["GOLF_API_KEY"]
    }
    
    // MARK: - Weather API Configuration
    
    static var weatherApiKey: String? {
        ProcessInfo.processInfo.environment["WEATHER_API_KEY"]
    }
    
    // MARK: - Payment Configuration
    
    static var stripePublishableKey: String {
        ProcessInfo.processInfo.environment["STRIPE_PUBLISHABLE_KEY"] ?? defaultStripeKey
    }
    
    // MARK: - Analytics Configuration
    
    static var firebaseConfigPath: String? {
        ProcessInfo.processInfo.environment["FIREBASE_CONFIG_PATH"]
    }
    
    // MARK: - JWT Security Configuration
    
    static var jwtSecretKey: Data? {
        guard let keyString = ProcessInfo.processInfo.environment["JWT_SECRET_KEY"] else {
            return nil
        }
        return Data(keyString.utf8)
    }
    
    static var jwtIssuer: String {
        ProcessInfo.processInfo.environment["JWT_ISSUER"] ?? "com.golffinder.app"
    }
    
    static var jwtAudience: String {
        ProcessInfo.processInfo.environment["JWT_AUDIENCE"] ?? "golffinder-api"
    }
    
    static var jwtTokenExpirationHours: Int {
        Int(ProcessInfo.processInfo.environment["JWT_TOKEN_EXPIRATION_HOURS"] ?? "24") ?? 24
    }
    
    static var jwtRefreshTokenExpirationDays: Int {
        Int(ProcessInfo.processInfo.environment["JWT_REFRESH_TOKEN_EXPIRATION_DAYS"] ?? "30") ?? 30
    }
    
    // MARK: - Enterprise Authentication Configuration
    
    static var enableEnterpriseSSO: Bool {
        ProcessInfo.processInfo.environment["ENABLE_ENTERPRISE_SSO"]?.lowercased() == "true"
    }
    
    static var samlMetadataURL: String? {
        ProcessInfo.processInfo.environment["SAML_METADATA_URL"]
    }
    
    static var samlEntityID: String? {
        ProcessInfo.processInfo.environment["SAML_ENTITY_ID"]
    }
    
    static var samlCertificate: String? {
        ProcessInfo.processInfo.environment["SAML_CERTIFICATE"]
    }
    
    static var samlPrivateKey: String? {
        ProcessInfo.processInfo.environment["SAML_PRIVATE_KEY"]
    }
    
    // MARK: - GDPR Compliance Configuration
    
    static var gdprDataRetentionDays: Int {
        Int(ProcessInfo.processInfo.environment["GDPR_DATA_RETENTION_DAYS"] ?? "2555") ?? 2555 // 7 years default
    }
    
    static var gdprConsentVersion: String {
        ProcessInfo.processInfo.environment["GDPR_CONSENT_VERSION"] ?? "1.0"
    }
    
    static var gdprPrivacyPolicyURL: String {
        ProcessInfo.processInfo.environment["GDPR_PRIVACY_POLICY_URL"] ?? "https://golffinder.app/privacy"
    }
    
    static var gdprTermsOfServiceURL: String {
        ProcessInfo.processInfo.environment["GDPR_TERMS_URL"] ?? "https://golffinder.app/terms"
    }
    
    static var enableDataSubjectRights: Bool {
        ProcessInfo.processInfo.environment["ENABLE_DATA_SUBJECT_RIGHTS"]?.lowercased() != "false"
    }
    
    static var dataProtectionOfficerEmail: String {
        ProcessInfo.processInfo.environment["DPO_EMAIL"] ?? "dpo@golffinder.app"
    }
    
    // MARK: - Role-Based Access Control Configuration
    
    static var enableRBAC: Bool {
        ProcessInfo.processInfo.environment["ENABLE_RBAC"]?.lowercased() != "false"
    }
    
    static var defaultUserRole: String {
        ProcessInfo.processInfo.environment["DEFAULT_USER_ROLE"] ?? "member"
    }
    
    static var roleHierarchyConfig: String? {
        ProcessInfo.processInfo.environment["ROLE_HIERARCHY_CONFIG"]
    }
    
    // MARK: - Database Encryption Configuration
    
    static var databaseEncryptionKey: Data? {
        guard let keyString = ProcessInfo.processInfo.environment["DATABASE_ENCRYPTION_KEY"] else {
            return nil
        }
        return Data(keyString.utf8)
    }
    
    static var enableFieldLevelEncryption: Bool {
        ProcessInfo.processInfo.environment["ENABLE_FIELD_ENCRYPTION"]?.lowercased() != "false"
    }
    
    // MARK: - Default Values (Development)
    
    private static let defaultAppwriteEndpoint = "https://cloud.appwrite.io/v1"
    private static let defaultAppwriteProjectId = "golf-finder-dev"
    private static let defaultGolfApiUrl = "https://api.golf-courses.com/v1"
    private static let defaultStripeKey = "pk_test_development_key"
    
    // MARK: - Validation
    
    static func validateConfiguration() throws {
        guard !appwriteEndpoint.isEmpty else {
            throw ConfigurationError.missingAppwriteEndpoint
        }
        
        guard !appwriteProjectId.isEmpty else {
            throw ConfigurationError.missingAppwriteProjectId
        }
        
        guard appwriteApiKey != nil else {
            throw ConfigurationError.missingAppwriteApiKey
        }
        
        // Validate security configuration for production
        if environment == .production {
            guard jwtSecretKey != nil else {
                throw ConfigurationError.missingJWTSecretKey
            }
            
            guard jwtSecretKey!.count >= 32 else {
                throw ConfigurationError.weakJWTSecretKey
            }
            
            if enableFieldLevelEncryption {
                guard databaseEncryptionKey != nil else {
                    throw ConfigurationError.missingDatabaseEncryptionKey
                }
                
                guard databaseEncryptionKey!.count >= 32 else {
                    throw ConfigurationError.weakDatabaseEncryptionKey
                }
            }
            
            if enableEnterpriseSSO {
                guard samlMetadataURL != nil || samlEntityID != nil else {
                    throw ConfigurationError.missingSAMLConfiguration
                }
            }
        }
        
        print("✅ Configuration validated for environment: \(environment)")
    }
    
    // MARK: - Environment Enum
    
    enum Environment: String, CaseIterable {
        case development = "development"
        case staging = "staging"
        case production = "production"
        
        var useMockServices: Bool {
            switch self {
            case .development:
                return true
            case .staging, .production:
                return false
            }
        }
        
        var enableDetailedLogging: Bool {
            switch self {
            case .development, .staging:
                return true
            case .production:
                return false
            }
        }
        
        var enablePerformanceMonitoring: Bool {
            return self == .production
        }
    }
    
    // MARK: - Configuration Errors
    
    enum ConfigurationError: Error, LocalizedError {
        case missingAppwriteEndpoint
        case missingAppwriteProjectId
        case missingAppwriteApiKey
        case missingGolfApiKey
        case missingWeatherApiKey
        case missingJWTSecretKey
        case weakJWTSecretKey
        case missingDatabaseEncryptionKey
        case weakDatabaseEncryptionKey
        case missingSAMLConfiguration
        
        var errorDescription: String? {
            switch self {
            case .missingAppwriteEndpoint:
                return "Appwrite endpoint is required"
            case .missingAppwriteProjectId:
                return "Appwrite project ID is required"
            case .missingAppwriteApiKey:
                return "Appwrite API key is required"
            case .missingGolfApiKey:
                return "Golf API key is required"
            case .missingWeatherApiKey:
                return "Weather API key is required"
            case .missingJWTSecretKey:
                return "JWT secret key is required for production environment"
            case .weakJWTSecretKey:
                return "JWT secret key must be at least 32 bytes long"
            case .missingDatabaseEncryptionKey:
                return "Database encryption key is required when field-level encryption is enabled"
            case .weakDatabaseEncryptionKey:
                return "Database encryption key must be at least 32 bytes long"
            case .missingSAMLConfiguration:
                return "SAML metadata URL or entity ID is required when enterprise SSO is enabled"
            }
        }
    }
}

// MARK: - Feature Flags

struct FeatureFlags {
    static let enableRealTimeLeaderboards = Configuration.environment != .development
    static let enablePremiumHaptics = true
    static let enableAdvancedAnalytics = Configuration.environment == .production
    static let enableSocialFeatures = true
    static let enableWeatherIntegration = true
    static let enableMapKitOptimizations = true
    static let enableImageCaching = true
    
    // Golf-specific features
    static let enableHandicapTracking = true
    static let enableTeeTimeOptimization = true
    static let enableCourseRecommendations = true
    static let enableScorecardIntegration = true
}