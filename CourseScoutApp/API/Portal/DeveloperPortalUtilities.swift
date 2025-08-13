import Foundation
import Appwrite
import CoreLocation
import CryptoKit

// MARK: - Developer Portal Utilities

struct DeveloperPortalUtilities {
    
    // MARK: - API Key Generation
    
    static func generateSecureAPIKey(tier: APITier) -> String {
        let prefix = tier.rawValue.prefix(4).lowercased()
        let randomPart = generateSecureRandomString(length: 32)
        return "\(prefix)_\(randomPart)"
    }
    
    static func generateSecureRandomString(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    static func hashAPIKey(_ apiKey: String) -> String {
        let data = Data(apiKey.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Email Validation
    
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
    
    // MARK: - Password Validation
    
    static func validatePasswordStrength(_ password: String) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        let minLength = 8
        
        if password.count < minLength {
            errors.append("Password must be at least \(minLength) characters long")
        }
        
        let hasUppercase = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLowercase = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumbers = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSpecialChars = password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")) != nil
        
        if !hasUppercase { errors.append("Password must contain at least one uppercase letter") }
        if !hasLowercase { errors.append("Password must contain at least one lowercase letter") }
        if !hasNumbers { errors.append("Password must contain at least one number") }
        if !hasSpecialChars { errors.append("Password must contain at least one special character") }
        
        return (isValid: errors.isEmpty, errors: errors)
    }
    
    // MARK: - URL Validation
    
    static func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    // MARK: - Version Validation
    
    static func isValidVersionFormat(_ version: String) -> Bool {
        let pattern = #"^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: version.utf16.count)
        return regex?.firstMatch(in: version, range: range) != nil
    }
    
    // MARK: - Rate Limiting Calculations
    
    static func calculateRateLimit(for tier: APITier) -> (requestsPerMinute: Int, burstLimit: Int) {
        let requestsPerMinute: Int
        let burstLimit: Int
        
        switch tier {
        case .free:
            requestsPerMinute = 16
            burstLimit = 10
        case .premium:
            requestsPerMinute = 167
            burstLimit = 50
        case .enterprise:
            requestsPerMinute = 1667
            burstLimit = 200
        case .business:
            requestsPerMinute = -1 // Unlimited
            burstLimit = 500
        }
        
        return (requestsPerMinute, burstLimit)
    }
    
    // MARK: - Usage Analytics
    
    static func calculateUsagePercentage(used: Int, total: Int) -> Double {
        guard total > 0 else { return 0.0 }
        return Double(used) / Double(total)
    }
    
    static func formatUsageString(used: Int, total: Int) -> String {
        if total == -1 {
            return "\(used) requests (Unlimited)"
        }
        let percentage = calculateUsagePercentage(used: used, total: total)
        return "\(used) / \(total) requests (\(String(format: "%.1f", percentage * 100))%)"
    }
    
    // MARK: - Cost Calculations
    
    static func calculateCostInCents(requests: Int, tier: APITier) -> Double {
        let costPerThousandRequests: Double
        
        switch tier {
        case .free:
            costPerThousandRequests = 0.0
        case .premium:
            costPerThousandRequests = 1.0 // $0.01 per 1000 requests
        case .enterprise:
            costPerThousandRequests = 0.5 // $0.005 per 1000 requests
        case .business:
            costPerThousandRequests = 0.2 // $0.002 per 1000 requests
        }
        
        return (Double(requests) / 1000.0) * costPerThousandRequests
    }
    
    // MARK: - Time Formatting
    
    static func formatTimeInterval(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "\(Int(interval))s"
    }
    
    static func formatDate(_ date: Date, style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    static func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - File Size Formatting
    
    static func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Response Time Formatting
    
    static func formatResponseTime(_ milliseconds: Double) -> String {
        if milliseconds < 1 {
            return String(format: "%.2f ms", milliseconds)
        } else if milliseconds < 1000 {
            return String(format: "%.0f ms", milliseconds)
        } else {
            return String(format: "%.2f s", milliseconds / 1000)
        }
    }
    
    // MARK: - Error Code Generation
    
    static func generateErrorCode(type: String, timestamp: Date = Date()) -> String {
        let timestampString = String(Int(timestamp.timeIntervalSince1970))
        let randomSuffix = String(Int.random(in: 100...999))
        return "\(type.uppercased())_\(timestampString)_\(randomSuffix)"
    }
    
    // MARK: - Request ID Generation
    
    static func generateRequestId() -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        return "req_\(timestamp)_\(random)"
    }
    
    // MARK: - Checksum Generation
    
    static func calculateChecksum(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    static func calculateChecksum(for string: String) -> String {
        let data = Data(string.utf8)
        return calculateChecksum(for: data)
    }
    
    // MARK: - JSON Utilities
    
    static func prettyPrintJSON(_ object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    static func parseJSON<T: Codable>(_ jsonString: String, as type: T.Type) -> T? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    
    // MARK: - Cache Key Generation
    
    static func generateCacheKey(components: [String]) -> String {
        let joined = components.joined(separator: "_")
        return calculateChecksum(for: joined)
    }
    
    // MARK: - Feature Flag Helpers
    
    static func isFeatureEnabled(_ feature: String, for tier: APITier) -> Bool {
        switch feature {
        case "advanced_analytics":
            return tier.priority >= APITier.premium.priority
        case "custom_webhooks":
            return tier.priority >= APITier.enterprise.priority
        case "priority_support":
            return tier.priority >= APITier.enterprise.priority
        case "dedicated_support":
            return tier == .business
        case "unlimited_requests":
            return tier == .business
        default:
            return true // Default features available to all tiers
        }
    }
    
    // MARK: - Health Check Utilities
    
    static func generateHealthCheckResponse(
        isHealthy: Bool,
        services: [String: Bool],
        metrics: [String: Double]
    ) -> APIHealthStatus {
        return APIHealthStatus(
            isHealthy: isHealthy,
            appwriteConnected: services["appwrite"] ?? false,
            memoryUsagePercent: metrics["memory_usage"] ?? 0.0,
            averageResponseTimeMs: metrics["avg_response_time"] ?? 0.0,
            activeConnections: Int(metrics["active_connections"] ?? 0),
            uptime: metrics["uptime"] ?? 0,
            timestamp: Date()
        )
    }
}

// MARK: - Developer Portal Extensions

extension APITier {
    
    var featureList: [String] {
        switch self {
        case .free:
            return [
                "Basic API access",
                "1,000 requests/day", 
                "Community support",
                "2 API keys",
                "Basic documentation"
            ]
        case .premium:
            return [
                "Advanced analytics",
                "10,000 requests/day",
                "Email support",
                "5 API keys",
                "Custom webhooks",
                "Priority rate limits",
                "Enhanced documentation"
            ]
        case .enterprise:
            return [
                "All premium features",
                "100,000 requests/day",
                "Priority support",
                "20 API keys",
                "SLA guarantee",
                "Custom integrations",
                "Advanced monitoring",
                "White-label options"
            ]
        case .business:
            return [
                "All enterprise features",
                "Unlimited requests",
                "Dedicated support",
                "50 API keys",
                "Custom solutions",
                "99.99% SLA",
                "On-premise deployment",
                "Custom training"
            ]
        }
    }
    
    var colorHex: String {
        switch self {
        case .free: return "#6B7280"      // Gray
        case .premium: return "#3B82F6"   // Blue
        case .enterprise: return "#8B5CF6" // Purple
        case .business: return "#F59E0B"   // Amber
        }
    }
}

extension APIVersion {
    
    var supportedFeatures: [String] {
        switch self {
        case .v1:
            return [
                "Basic course data",
                "Simple search",
                "Course details",
                "Reviews and ratings"
            ]
        case .v2:
            return [
                "Advanced analytics",
                "Predictive insights",
                "Real-time booking",
                "Enhanced search",
                "Machine learning recommendations",
                "Webhook support"
            ]
        }
    }
    
    var deprecationDate: Date? {
        switch self {
        case .v1:
            // v1 will be deprecated 1 year from now
            return Calendar.current.date(byAdding: .year, value: 1, to: Date())
        case .v2:
            return nil // Current version
        }
    }
}

extension HTTPMethod {
    
    var description: String {
        switch self {
        case .GET: return "Retrieve data"
        case .POST: return "Create new resource"
        case .PUT: return "Update existing resource"
        case .DELETE: return "Remove resource"
        case .PATCH: return "Partially update resource"
        case .HEAD: return "Get resource headers only"
        case .OPTIONS: return "Get allowed methods"
        }
    }
    
    var isIdempotent: Bool {
        switch self {
        case .GET, .PUT, .DELETE, .HEAD, .OPTIONS:
            return true
        case .POST, .PATCH:
            return false
        }
    }
}

extension UsagePeriod {
    
    var displayName: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .currentWeek: return "This Week"
        case .currentMonth: return "This Month"
        case .last30Days: return "Last 30 Days"
        }
    }
    
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            let start = calendar.startOfDay(for: yesterday)
            let end = calendar.startOfDay(for: now)
            return (start, end)
        case .currentWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            return (start, now)
        case .currentMonth:
            let start = calendar.dateInterval(of: .month, for: now)!.start
            return (start, now)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)!
            return (start, now)
        }
    }
}

// MARK: - Validation Helpers

struct DeveloperPortalValidator {
    
    static func validateDeveloperRegistration(_ registration: DeveloperRegistration) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Email validation
        if !DeveloperPortalUtilities.isValidEmail(registration.email) {
            errors.append("Invalid email address format")
        }
        
        // Password validation
        let passwordValidation = DeveloperPortalUtilities.validatePasswordStrength(registration.password)
        if !passwordValidation.isValid {
            errors.append(contentsOf: passwordValidation.errors)
        }
        
        // Name validation
        if registration.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name cannot be empty")
        }
        
        // Company validation (optional but recommended)
        if let company = registration.company, company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Company name appears to be empty")
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    static func validateAPIKeyRequest(_ request: APIKeyRequest) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Name validation
        if let name = request.name, name.count < 3 {
            errors.append("API key name must be at least 3 characters")
        }
        
        // Description validation
        if let description = request.description, description.isEmpty {
            warnings.append("Consider adding a description for better key management")
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
}

// MARK: - Mock Request Structure for Missing Models

struct APIKeyRequest: Codable {
    let name: String?
    let description: String?
    let tier: APITier
    let permissions: [String]?
    let expiresAt: Date?
    
    init(name: String? = nil, description: String? = nil, tier: APITier = .free, permissions: [String]? = nil, expiresAt: Date? = nil) {
        self.name = name
        self.description = description
        self.tier = tier
        self.permissions = permissions
        self.expiresAt = expiresAt
    }
}