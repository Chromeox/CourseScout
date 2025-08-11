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