import Foundation
import Appwrite
import SwiftUI

// MARK: - Developer Portal Integration Manager

@MainActor
class DeveloperPortalIntegration: ObservableObject {
    
    // MARK: - Properties
    
    private let serviceContainer: ServiceContainer
    
    @Published var isInitialized: Bool = false
    @Published var initializationError: Error?
    @Published var healthStatus: APIHealthStatus?
    
    // Service references
    private var developerAuthService: DeveloperAuthServiceProtocol?
    private var apiKeyManagementService: APIKeyManagementServiceProtocol?
    private var documentationService: DocumentationGeneratorServiceProtocol?
    private var sdkGeneratorService: SDKGeneratorServiceProtocol?
    private var apiGatewayService: APIGatewayServiceProtocol?
    
    // MARK: - Initialization
    
    init(serviceContainer: ServiceContainer = ServiceContainer.shared) {
        self.serviceContainer = serviceContainer
        Task {
            await initialize()
        }
    }
    
    private func initialize() async {
        do {
            // Initialize all developer portal services
            developerAuthService = serviceContainer.resolve(DeveloperAuthServiceProtocol.self)
            apiKeyManagementService = serviceContainer.resolve(APIKeyManagementServiceProtocol.self)
            documentationService = serviceContainer.resolve(DocumentationGeneratorServiceProtocol.self)
            sdkGeneratorService = serviceContainer.resolve(SDKGeneratorServiceProtocol.self)
            apiGatewayService = serviceContainer.resolve(APIGatewayServiceProtocol.self)
            
            // Validate services are working
            try await validateServices()
            
            // Perform health check
            healthStatus = await apiGatewayService?.healthCheck()
            
            isInitialized = true
            print("✅ Developer Portal Integration initialized successfully")
            
        } catch {
            initializationError = error
            isInitialized = false
            print("❌ Developer Portal Integration failed: \(error)")
        }
    }
    
    private func validateServices() async throws {
        // Validate that all required services are available
        guard let _ = developerAuthService else {
            throw DeveloperPortalError.serverError("DeveloperAuthService not available")
        }
        
        guard let _ = apiKeyManagementService else {
            throw DeveloperPortalError.serverError("APIKeyManagementService not available")
        }
        
        guard let _ = documentationService else {
            throw DeveloperPortalError.serverError("DocumentationGeneratorService not available")
        }
        
        guard let _ = sdkGeneratorService else {
            throw DeveloperPortalError.serverError("SDKGeneratorService not available")
        }
        
        guard let _ = apiGatewayService else {
            throw DeveloperPortalError.serverError("APIGatewayService not available")
        }
    }
    
    // MARK: - Complete Developer Workflow
    
    func completeDeveloperOnboarding(registration: DeveloperRegistration) async -> Result<DeveloperOnboardingResult, Error> {
        guard let authService = developerAuthService,
              let keyService = apiKeyManagementService,
              let docService = documentationService else {
            return .failure(DeveloperPortalError.serverError("Services not initialized"))
        }
        
        do {
            // Step 1: Register developer
            let developer = try await authService.registerDeveloper(registration)
            
            // Step 2: Create first API key
            let apiKey = try await keyService.generateAPIKey(
                for: developer.id,
                tier: developer.tier,
                name: "My First API Key",
                description: "Auto-generated key for getting started"
            )
            
            // Step 3: Generate initial documentation
            let documentation = try await docService.generateOpenAPISpec(
                version: .v2,
                tier: developer.tier
            )
            
            // Step 4: Create onboarding result
            let onboardingResult = DeveloperOnboardingResult(
                developer: developer,
                firstAPIKey: apiKey,
                documentation: documentation,
                nextSteps: generateNextSteps(for: developer.tier),
                estimatedCompletionTime: 300 // 5 minutes
            )
            
            return .success(onboardingResult)
            
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Developer Dashboard Data
    
    func getDeveloperDashboard(for developerId: String) async -> Result<DeveloperPortalDashboard, Error> {
        guard let authService = developerAuthService,
              let keyService = apiKeyManagementService else {
            return .failure(DeveloperPortalError.serverError("Services not initialized"))
        }
        
        do {
            // Get developer profile
            let profile = try await authService.getDeveloperProfile(developerId)
            
            // Create developer account from profile
            let developer = DeveloperAccount(
                id: profile.userId,
                email: profile.email,
                name: profile.name,
                company: profile.company,
                isEmailVerified: true,
                tier: profile.tier,
                createdAt: profile.createdAt,
                profile: profile
            )
            
            // Get API keys
            let apiKeys = try await keyService.listAPIKeys(for: developerId)
            
            // Generate usage analytics
            let analytics = generateMockUsageAnalytics(for: developerId, tier: profile.tier)
            
            // Generate notifications
            let notifications = generateNotifications(for: developer, apiKeys: apiKeys)
            
            // Generate billing info
            let billingInfo = generateBillingInfo(for: profile.tier)
            
            // Create dashboard
            let dashboard = DeveloperPortalDashboard(
                developer: developer,
                apiKeys: apiKeys,
                recentUsage: analytics,
                notifications: notifications,
                billingInfo: billingInfo,
                supportTickets: [],
                generatedAt: Date()
            )
            
            return .success(dashboard)
            
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - API Explorer Integration
    
    func getAPIExplorer(for tier: APITier) async -> Result<APIExplorerData, Error> {
        guard let docService = documentationService,
              let gatewayService = apiGatewayService else {
            return .failure(DeveloperPortalError.serverError("Services not initialized"))
        }
        
        do {
            // Get available endpoints for tier
            let endpoints = gatewayService.listAvailableEndpoints(for: tier)
            
            // Generate interactive playgrounds for each endpoint
            var playgrounds: [APIEndpoint: PlaygroundConfiguration] = [:]
            
            for endpoint in endpoints {
                let playground = try await docService.generateInteractivePlayground(
                    for: endpoint,
                    apiKey: "your_api_key_here"
                )
                playgrounds[endpoint] = playground
            }
            
            // Generate code examples
            let codeExamples = try await docService.generateCodeExamples(
                for: endpoints.first ?? createSampleEndpoint(),
                languages: [.curl, .swift, .javascript, .python]
            )
            
            let explorerData = APIExplorerData(
                availableEndpoints: endpoints,
                playgrounds: playgrounds,
                codeExamples: codeExamples,
                tier: tier
            )
            
            return .success(explorerData)
            
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - SDK Management
    
    func generateAllSDKs(for version: APIVersion, tier: APITier) async -> Result<SDKGenerationSummary, Error> {
        guard let sdkService = sdkGeneratorService,
              let gatewayService = apiGatewayService else {
            return .failure(DeveloperPortalError.serverError("Services not initialized"))
        }
        
        do {
            let endpoints = gatewayService.listAvailableEndpoints(for: tier)
            let languages: [ProgrammingLanguage] = [.swift, .javascript, .python, .go]
            
            var generatedSDKs: [ProgrammingLanguage: SDKGenerationResult] = [:]
            var errors: [ProgrammingLanguage: Error] = [:]
            
            // Generate SDKs for each language
            for language in languages {
                do {
                    let sdkResult: SDKGenerationResult
                    switch language {
                    case .swift:
                        sdkResult = try await sdkService.generateSwiftSDK(version: version, endpoints: endpoints)
                    case .javascript:
                        sdkResult = try await sdkService.generateJavaScriptSDK(version: version, endpoints: endpoints)
                    case .python:
                        sdkResult = try await sdkService.generatePythonSDK(version: version, endpoints: endpoints)
                    case .go:
                        sdkResult = try await sdkService.generateGoSDK(version: version, endpoints: endpoints)
                    default:
                        continue
                    }
                    generatedSDKs[language] = sdkResult
                } catch {
                    errors[language] = error
                }
            }
            
            let summary = SDKGenerationSummary(
                version: version,
                tier: tier,
                generatedSDKs: generatedSDKs,
                errors: errors,
                generatedAt: Date()
            )
            
            return .success(summary)
            
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Health and Monitoring
    
    func performComprehensiveHealthCheck() async -> Result<ComprehensiveHealthReport, Error> {
        guard let gatewayService = apiGatewayService else {
            return .failure(DeveloperPortalError.serverError("Services not initialized"))
        }
        
        do {
            // Gateway health check
            let gatewayHealth = await gatewayService.healthCheck()
            
            // Service availability checks
            let serviceHealth = checkServiceHealth()
            
            // Performance metrics
            let performanceMetrics = await getPerformanceMetrics()
            
            let report = ComprehensiveHealthReport(
                overall: gatewayHealth,
                services: serviceHealth,
                performance: performanceMetrics,
                generatedAt: Date()
            )
            
            return .success(report)
            
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateNextSteps(for tier: APITier) -> [OnboardingStep] {
        var steps: [OnboardingStep] = [
            OnboardingStep(
                title: "Verify your email",
                description: "Check your inbox and click the verification link",
                isCompleted: false,
                url: nil
            ),
            OnboardingStep(
                title: "Make your first API call",
                description: "Test your API key with a simple request",
                isCompleted: false,
                url: "/docs/quickstart"
            ),
            OnboardingStep(
                title: "Explore the documentation",
                description: "Learn about all available endpoints and features",
                isCompleted: false,
                url: "/docs"
            )
        ]
        
        if tier.priority >= APITier.premium.priority {
            steps.append(OnboardingStep(
                title: "Set up webhooks",
                description: "Configure webhooks for real-time notifications",
                isCompleted: false,
                url: "/docs/webhooks"
            ))
        }
        
        return steps
    }
    
    private func generateMockUsageAnalytics(for developerId: String, tier: APITier) -> DeveloperUsageAnalytics {
        let baseRequests = tier.dailyRequestLimit / 10 // 10% of daily limit
        
        return DeveloperUsageAnalytics(
            developerId: developerId,
            period: .currentMonth,
            totalRequests: baseRequests,
            requestsByEndpoint: [
                "/courses": baseRequests / 2,
                "/courses/search": baseRequests / 3,
                "/analytics": baseRequests / 6
            ],
            requestsByDay: [:], // Would be populated with real data
            averageResponseTime: Double.random(in: 50...200),
            errorCount: max(0, baseRequests / 100),
            costInCents: DeveloperPortalUtilities.calculateCostInCents(requests: baseRequests, tier: tier),
            quotaUsagePercent: Double.random(in: 0.1...0.8),
            topErrors: [:],
            generatedAt: Date()
        )
    }
    
    private func generateNotifications(for developer: DeveloperAccount, apiKeys: [APIKeyInfo]) -> [DeveloperNotification] {
        var notifications: [DeveloperNotification] = []
        
        // Welcome notification
        notifications.append(DeveloperNotification(
            id: UUID().uuidString,
            type: .welcome,
            title: "Welcome to GolfFinder API!",
            message: "Your developer account has been successfully created. Start building amazing golf applications!",
            actionUrl: "/docs/quickstart",
            actionText: "Get Started",
            isRead: false,
            createdAt: developer.createdAt,
            priority: .medium
        ))
        
        // Check for expiring keys
        for key in apiKeys {
            if let expiresAt = key.expiresAt,
               expiresAt.timeIntervalSinceNow < 86400 * 30 { // 30 days
                notifications.append(DeveloperNotification(
                    id: UUID().uuidString,
                    type: .keyExpiring,
                    title: "API Key Expiring Soon",
                    message: "Your API key '\(key.name)' will expire on \(DeveloperPortalUtilities.formatDate(expiresAt))",
                    actionUrl: "/keys/\(key.id)",
                    actionText: "Renew Key",
                    isRead: false,
                    createdAt: Date().addingTimeInterval(-86400),
                    priority: .high
                ))
            }
        }
        
        return notifications
    }
    
    private func generateBillingInfo(for tier: APITier) -> DeveloperBillingInfo {
        return DeveloperBillingInfo(
            currentTier: tier,
            billingCycle: .monthly,
            nextBillingDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
            currentUsageCosts: DeveloperPortalUtilities.calculateCostInCents(requests: 5000, tier: tier),
            projectedMonthlyCosts: DeveloperPortalUtilities.calculateCostInCents(requests: 15000, tier: tier),
            paymentMethod: nil,
            invoices: []
        )
    }
    
    private func createSampleEndpoint() -> APIEndpoint {
        return APIEndpoint(
            path: "/courses",
            method: .GET,
            version: .v2,
            requiredTier: .free,
            handler: { _ in return "" },
            description: "Get golf courses"
        )
    }
    
    private func checkServiceHealth() -> [String: Bool] {
        return [
            "developer_auth": developerAuthService != nil,
            "api_key_management": apiKeyManagementService != nil,
            "documentation_generator": documentationService != nil,
            "sdk_generator": sdkGeneratorService != nil,
            "api_gateway": apiGatewayService != nil
        ]
    }
    
    private func getPerformanceMetrics() async -> [String: Double] {
        // Would typically fetch real metrics
        return [
            "memory_usage_percent": Double.random(in: 20...60),
            "cpu_usage_percent": Double.random(in: 10...40),
            "avg_response_time_ms": Double.random(in: 50...200),
            "requests_per_second": Double.random(in: 100...500),
            "error_rate_percent": Double.random(in: 0.1...2.0)
        ]
    }
}

// MARK: - Integration Data Models

struct DeveloperOnboardingResult {
    let developer: DeveloperAccount
    let firstAPIKey: APIKeyInfo
    let documentation: OpenAPISpecification
    let nextSteps: [OnboardingStep]
    let estimatedCompletionTime: TimeInterval
}

struct OnboardingStep {
    let title: String
    let description: String
    let isCompleted: Bool
    let url: String?
}

struct APIExplorerData {
    let availableEndpoints: [APIEndpoint]
    let playgrounds: [APIEndpoint: PlaygroundConfiguration]
    let codeExamples: [CodeExample]
    let tier: APITier
}

struct SDKGenerationSummary {
    let version: APIVersion
    let tier: APITier
    let generatedSDKs: [ProgrammingLanguage: SDKGenerationResult]
    let errors: [ProgrammingLanguage: Error]
    let generatedAt: Date
    
    var successfulGenerations: Int {
        return generatedSDKs.count
    }
    
    var failedGenerations: Int {
        return errors.count
    }
    
    var successRate: Double {
        let total = successfulGenerations + failedGenerations
        guard total > 0 else { return 0.0 }
        return Double(successfulGenerations) / Double(total)
    }
}

struct ComprehensiveHealthReport {
    let overall: APIHealthStatus
    let services: [String: Bool]
    let performance: [String: Double]
    let generatedAt: Date
    
    var allServicesHealthy: Bool {
        return services.values.allSatisfy { $0 }
    }
    
    var healthScore: Double {
        let serviceScore = services.values.map { $0 ? 1.0 : 0.0 }.reduce(0, +) / Double(services.count)
        let performanceScore = overall.isHealthy ? 1.0 : 0.0
        return (serviceScore + performanceScore) / 2.0
    }
}

// MARK: - SwiftUI Integration Helpers

extension DeveloperPortalIntegration {
    
    var statusColor: Color {
        if isInitialized {
            return .green
        } else if initializationError != nil {
            return .red
        } else {
            return .orange
        }
    }
    
    var statusText: String {
        if isInitialized {
            return "Ready"
        } else if let error = initializationError {
            return "Error: \(error.localizedDescription)"
        } else {
            return "Initializing..."
        }
    }
    
    var healthStatusText: String {
        guard let health = healthStatus else { return "Unknown" }
        return health.isHealthy ? "Healthy" : "Unhealthy"
    }
}

// MARK: - View Modifier for Developer Portal Integration

struct DeveloperPortalEnvironment: ViewModifier {
    let integration: DeveloperPortalIntegration
    
    func body(content: Content) -> some View {
        content
            .environmentObject(integration)
            .onAppear {
                if !integration.isInitialized && integration.initializationError == nil {
                    Task {
                        await integration.initialize()
                    }
                }
            }
    }
}

extension View {
    func withDeveloperPortalIntegration(_ integration: DeveloperPortalIntegration = DeveloperPortalIntegration()) -> some View {
        modifier(DeveloperPortalEnvironment(integration: integration))
    }
}