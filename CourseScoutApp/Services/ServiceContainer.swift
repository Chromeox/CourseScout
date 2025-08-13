import Foundation
import Appwrite
import SwiftUI
import WatchConnectivity

// MARK: - Service Lifecycle

enum ServiceLifecycle {
    case singleton // Single instance throughout app lifecycle
    case scoped // New instance per container scope
    case transient // New instance every time
}

// MARK: - Environment Configuration

enum ServiceEnvironment {
    case development
    case test
    case production

    var useMockServices: Bool {
        switch self {
        case .test:
            return true
        case .development:
            return Configuration.environment.useMockServices
        case .production:
            return false
        }
    }
}

// MARK: - Service Container

@MainActor
class ServiceContainer: ObservableObject {
    // MARK: - Singleton Access

    static let shared = ServiceContainer()

    // MARK: - Configuration

    @Published var environment: ServiceEnvironment = .development
    private let appwriteClient: Client
    
    // MARK: - Service Storage

    private var singletonServices: [String: Any] = [:]
    private var serviceRegistrations: [String: ServiceRegistration] = [:]
    
    // MARK: - Performance Optimization
    private var serviceAccessMetrics: [String: ServiceAccessMetrics] = [:]
    private let serviceCreationQueue = DispatchQueue(label: "GolfServiceCreation", qos: .userInitiated)
    private var preloadedServices: Set<String> = []

    // MARK: - Initialization

    private init() {
        appwriteClient = AppwriteManager.shared.client
        registerDefaultServices()
    }

    // For testing purposes - allows custom Appwrite Client injection
    init(appwriteClient: Client, environment: ServiceEnvironment = .test) {
        self.appwriteClient = appwriteClient
        self.environment = environment
        registerDefaultServices()
    }

    // MARK: - Service Registration

    private func registerDefaultServices() {
        // MARK: - Core Infrastructure Services
        
        register(
            Client.self,
            lifecycle: .singleton
        ) { container in
            return container.appwriteClient
        }
        
        // MARK: - Core Golf Services
        
        register(
            GolfCourseServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockGolfCourseService()
            }
            return GolfCourseService(appwriteClient: container.appwriteClient)
        }
        
        register(
            TeeTimeServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockTeeTimeService()
            }
            return TeeTimeService(appwriteClient: container.appwriteClient)
        }
        
        register(
            ScorecardServiceProtocol.self,
            lifecycle: .scoped
        ) { container in
            if container.environment.useMockServices {
                return MockScorecardService()
            }
            return ScorecardService(appwriteClient: container.appwriteClient)
        }
        
        register(
            HandicapServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockHandicapService()
            }
            return HandicapService(appwriteClient: container.appwriteClient)
        }
        
        register(
            LeaderboardServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockLeaderboardService()
            }
            return LeaderboardService(appwriteClient: container.appwriteClient)
        }
        
        register(
            TournamentServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockTournamentService()
            }
            return TournamentService(appwriteClient: container.appwriteClient)
        }

        // MARK: - Location and Weather Services
        
        register(
            LocationServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockLocationService()
            }
            return LocationService()
        }
        
        register(
            WeatherServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWeatherService()
            }
            return WeatherService()
        }
        
        register(
            MapServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockMapService()
            }
            return MapService()
        }

        // MARK: - User and Authentication Services
        
        // Core Authentication Services
        register(
            SessionManagementServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockSessionManagementService()
            }
            return SessionManagementService(appwriteClient: container.appwriteClient)
        }
        
        register(
            BiometricAuthServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockBiometricAuthService()
            }
            let securityService = container.resolve(SecurityServiceProtocol.self)
            return BiometricAuthService(securityService: securityService)
        }
        
        register(
            AuthenticationServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockAuthenticationService()
            }
            let sessionManager = container.resolve(SessionManagementServiceProtocol.self)
            let securityService = container.resolve(SecurityServiceProtocol.self)
            return AuthenticationService(
                appwriteClient: container.appwriteClient,
                sessionManager: sessionManager,
                securityService: securityService
            )
        }
        
        register(
            UserProfileServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockUserProfileService()
            }
            return UserProfileService(appwriteClient: container.appwriteClient)
        }
        
        register(
            BookingServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockBookingService()
            }
            return BookingService(appwriteClient: container.appwriteClient)
        }

        // MARK: - Payment and Premium Services
        
        register(
            PaymentServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockPaymentService()
            }
            let securityService = container.resolve(SecurityServiceProtocol.self)
            return PaymentService(appwriteClient: container.appwriteClient, securityService: securityService)
        }
        
        register(
            SubscriptionServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockSubscriptionService()
            }
            return SubscriptionService(appwriteClient: container.appwriteClient)
        }

        // MARK: - Social and Community Services
        
        register(
            ReviewServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockReviewService()
            }
            return ReviewService(appwriteClient: container.appwriteClient)
        }
        
        register(
            SocialServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockSocialService()
            }
            return SocialService(appwriteClient: container.appwriteClient)
        }
        
        register(
            FavoritesServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockFavoritesService()
            }
            return FavoritesService(appwriteClient: container.appwriteClient)
        }

        // MARK: - UX and Notification Services
        
        register(
            HapticFeedbackServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockTenantHapticFeedbackService()
            }
            return HapticFeedbackService()
        }
        
        register(
            WatchHapticFeedbackService.self,
            lifecycle: .singleton
        ) { container in
            return WatchHapticFeedbackService()
        }
        
        register(
            TenantConfigurationServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockTenantConfigurationService()
            }
            return TenantConfigurationService(appwriteClient: container.appwriteClient)
        }
        
        register(
            NotificationServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockNotificationService()
            }
            return NotificationService()
        }

        // MARK: - Analytics and Performance Services
        
        register(
            AnalyticsServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockAnalyticsService()
            }
            return AnalyticsService()
        }
        
        register(
            PerformanceMonitoringServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockPerformanceMonitoringService()
            }
            return PerformanceMonitoringService()
        }
        
        register(
            CrashReportingServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockCrashReportingService()
            }
            return CrashReportingService()
        }

        // MARK: - Security and Cache Services
        
        register(
            SecurityServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockSecurityService()
            }
            return SecurityService(appwriteClient: container.appwriteClient)
        }
        
        register(
            CacheServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockCacheService()
            }
            return CacheService()
        }
        
        register(
            ImageCacheServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockImageCacheService()
            }
            return ImageCacheService()
        }
        
        // MARK: - Watch Connectivity Services
        
        register(
            WatchConnectivityManagerProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockWatchConnectivityManager()
            }
            return WatchConnectivityManager.shared
        }

        // MARK: - API Gateway Services
        
        register(
            APIGatewayServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockAPIGatewayService()
            }
            return APIGatewayService(appwriteClient: container.appwriteClient)
        }
        
        register(
            DeveloperAuthServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockDeveloperAuthService()
            }
            return DeveloperAuthService(appwriteClient: container.appwriteClient)
        }
        
        register(
            APIKeyManagementServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockAPIKeyManagementService()
            }
            let authService = container.resolve(AuthenticationMiddleware.self)
            return APIKeyManagementService(appwriteClient: container.appwriteClient, authService: authService)
        }
        
        register(
            DocumentationGeneratorServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockDocumentationGeneratorService()
            }
            return DocumentationGeneratorService(appwriteClient: container.appwriteClient)
        }
        
        register(
            SDKGeneratorServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockSDKGeneratorService()
            }
            return SDKGeneratorService(appwriteClient: container.appwriteClient)
        }
        
        register(
            CourseDataAPIProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockCourseDataAPI()
            }
            let golfCourseService = container.resolve(GolfCourseServiceProtocol.self)
            let locationService = container.resolve(LocationServiceProtocol.self)
            return CourseDataAPI(appwriteClient: container.appwriteClient, golfCourseService: golfCourseService, locationService: locationService)
        }
        
        // MARK: - API Middleware Services
        
        register(
            AuthenticationMiddleware.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockAuthenticationMiddleware(appwriteClient: container.appwriteClient)
            }
            return AuthenticationMiddleware(appwriteClient: container.appwriteClient)
        }
        
        register(
            RateLimitingMiddleware.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockRateLimitingMiddleware()
            }
            return RateLimitingMiddleware()
        }
        
        register(
            UsageTrackingMiddleware.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockUsageTrackingMiddleware()
            }
            return UsageTrackingMiddleware(appwriteClient: container.appwriteClient)
        }
        
        // MARK: - Revenue Infrastructure Services
        
        register(
            RevenueServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockRevenueService()
            }
            let analyticsService = container.resolve(AnalyticsServiceProtocol.self)
            return RevenueService(appwriteClient: container.appwriteClient, analyticsService: analyticsService)
        }
        
        register(
            TenantManagementServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockTenantManagementService()
            }
            let securityService = container.resolve(SecurityServiceProtocol.self)
            let analyticsService = container.resolve(AnalyticsServiceProtocol.self)
            return TenantManagementService(
                appwriteClient: container.appwriteClient,
                securityService: securityService,
                analyticsService: analyticsService
            )
        }
        
        register(
            APIUsageTrackingServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockAPIUsageTrackingService()
            }
            let analyticsService = container.resolve(AnalyticsServiceProtocol.self)
            return APIUsageTrackingService(appwriteClient: container.appwriteClient, analyticsService: analyticsService)
        }
        
        register(
            BillingServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockBillingService()
            }
            let securityService = container.resolve(SecurityServiceProtocol.self)
            let analyticsService = container.resolve(AnalyticsServiceProtocol.self)
            let paymentService = container.resolve(PaymentServiceProtocol.self)
            return BillingService(
                appwriteClient: container.appwriteClient,
                securityService: securityService,
                analyticsService: analyticsService,
                paymentService: paymentService
            )
        }
        
        // Revenue Service Protocol already registered above in subscription section
        // But we'll update the existing registration to include dependencies
        
        // Update existing SubscriptionServiceProtocol registration
        serviceRegistrations["SubscriptionServiceProtocol"] = ServiceRegistration(
            lifecycle: .singleton,
            factory: { container in
                if container.environment.useMockServices {
                    return MockSubscriptionService()
                }
                let billingService = container.resolve(BillingServiceProtocol.self)
                let tenantService = container.resolve(TenantManagementServiceProtocol.self)
                return SubscriptionService(
                    appwriteClient: container.appwriteClient,
                    billingService: billingService,
                    tenantService: tenantService
                )
            }
        )
        
        // MARK: - Gamification System Services
        
        register(
            RatingEngineServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockRatingEngineService()
            }
            return RatingEngineService(appwriteClient: container.appwriteClient)
        }
        
        register(
            SocialChallengeServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockSocialChallengeService()
            }
            return SocialChallengeService(appwriteManager: AppwriteManager.shared)
        }
        
        register(
            AchievementServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockAchievementService()
            }
            
            // Create achievement service with dependencies
            let achievementService = AchievementService(appwriteManager: AppwriteManager.shared)
            
            // Configure dependencies
            achievementService.configure(
                ratingEngineService: container.resolve(RatingEngineServiceProtocol.self),
                socialChallengeService: container.resolve(SocialChallengeServiceProtocol.self),
                leaderboardService: container.resolve(LeaderboardServiceProtocol.self),
                hapticFeedbackService: container.resolve(HapticFeedbackServiceProtocol.self)
            )
            
            return achievementService
        }

        // MARK: - Enterprise Authentication Services
        
        register(
            EnterpriseAuthServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockEnterpriseAuthService()
            }
            return EnterpriseAuthService(appwriteClient: container.appwriteClient)
        }
        
        register(
            ConsentManagementServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockConsentManagementService()
            }
            return ConsentManagementService(appwriteClient: container.appwriteClient)
        }
        
        register(
            RoleManagementServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockRoleManagementService()
            }
            return RoleManagementService(appwriteClient: container.appwriteClient)
        }
        
        // MARK: - Phase 4 Gamification System Services
        
        register(
            SecurePaymentServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockSecurePaymentService()
            }
            let securityService = container.resolve(SecurityServiceProtocol.self)
            let revenueService = container.resolve(RevenueServiceProtocol.self)
            let tenantConfigurationService = container.resolve(TenantConfigurationServiceProtocol.self)
            return SecurePaymentService(
                securityService: securityService,
                revenueService: revenueService,
                tenantConfigurationService: tenantConfigurationService
            )
        }
        
        register(
            MultiTenantRevenueAttributionServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockMultiTenantRevenueAttributionService()
            }
            let revenueService = container.resolve(RevenueServiceProtocol.self)
            let securityService = container.resolve(SecurityServiceProtocol.self)
            let tenantConfigurationService = container.resolve(TenantConfigurationServiceProtocol.self)
            return MultiTenantRevenueAttributionService(
                revenueService: revenueService,
                securityService: securityService,
                tenantConfigurationService: tenantConfigurationService
            )
        }
        
        register(
            SocialChallengeSynchronizedHapticServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockSocialChallengeSynchronizedHapticService()
            }
            let hapticService = container.resolve(HapticFeedbackServiceProtocol.self)
            return SocialChallengeSynchronizedHapticService(hapticService: hapticService)
        }
    }

    // MARK: - Generic Service Registration

    func register<T>(
        _ protocolType: T.Type,
        lifecycle: ServiceLifecycle,
        factory: @escaping (ServiceContainer) -> T
    ) {
        let key = String(describing: protocolType)
        serviceRegistrations[key] = ServiceRegistration(
            lifecycle: lifecycle,
            factory: { container in
                factory(container)
            }
        )
    }

    // MARK: - Service Resolution

    func resolve<T>(_ protocolType: T.Type) -> T {
        let key = String(describing: protocolType)
        let startTime = DispatchTime.now()

        guard let registration = serviceRegistrations[key] else {
            fatalError("Service not registered: \(key)")
        }

        let service: T
        
        switch registration.lifecycle {
        case .singleton:
            if let existingService = singletonServices[key] as? T {
                recordServiceAccess(key: key, creationTime: 0, fromCache: true)
                return existingService
            }

            service = registration.factory(self) as! T
            singletonServices[key] = service

        case .scoped:
            service = registration.factory(self) as! T

        case .transient:
            service = registration.factory(self) as! T
        }
        
        let creationTime = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        recordServiceAccess(key: key, creationTime: creationTime, fromCache: false)
        
        return service
    }

    // MARK: - Convenience Methods for Golf Services

    func golfCourseService() -> GolfCourseServiceProtocol {
        return resolve(GolfCourseServiceProtocol.self)
    }
    
    func teeTimeService() -> TeeTimeServiceProtocol {
        return resolve(TeeTimeServiceProtocol.self)
    }
    
    func scorecardService() -> ScorecardServiceProtocol {
        return resolve(ScorecardServiceProtocol.self)
    }
    
    func handicapService() -> HandicapServiceProtocol {
        return resolve(HandicapServiceProtocol.self)
    }
    
    func leaderboardService() -> LeaderboardServiceProtocol {
        return resolve(LeaderboardServiceProtocol.self)
    }
    
    func locationService() -> LocationServiceProtocol {
        return resolve(LocationServiceProtocol.self)
    }
    
    func weatherService() -> WeatherServiceProtocol {
        return resolve(WeatherServiceProtocol.self)
    }
    
    func authenticationService() -> AuthenticationServiceProtocol {
        return resolve(AuthenticationServiceProtocol.self)
    }
    
    func userProfileService() -> UserProfileServiceProtocol {
        return resolve(UserProfileServiceProtocol.self)
    }
    
    func sessionManagementService() -> SessionManagementServiceProtocol {
        return resolve(SessionManagementServiceProtocol.self)
    }
    
    func biometricAuthService() -> BiometricAuthServiceProtocol {
        return resolve(BiometricAuthServiceProtocol.self)
    }
    
    func hapticFeedbackService() -> HapticFeedbackServiceProtocol {
        return resolve(HapticFeedbackServiceProtocol.self)
    }
    
    func analyticsService() -> AnalyticsServiceProtocol {
        return resolve(AnalyticsServiceProtocol.self)
    }
    
    func watchHapticFeedbackService() -> WatchHapticFeedbackService {
        return resolve(WatchHapticFeedbackService.self)
    }
    
    func tenantConfigurationService() -> TenantConfigurationServiceProtocol {
        return resolve(TenantConfigurationServiceProtocol.self)
    }
    
    // MARK: - Gamification System Convenience Methods
    
    func ratingEngineService() -> RatingEngineServiceProtocol {
        return resolve(RatingEngineServiceProtocol.self)
    }
    
    func socialChallengeService() -> SocialChallengeServiceProtocol {
        return resolve(SocialChallengeServiceProtocol.self)
    }
    
    func achievementService() -> AchievementServiceProtocol {
        return resolve(AchievementServiceProtocol.self)
    }
    
    // MARK: - API Gateway Convenience Methods
    
    func apiGatewayService() -> APIGatewayServiceProtocol {
        return resolve(APIGatewayServiceProtocol.self)
    }
    
    func developerAuthService() -> DeveloperAuthServiceProtocol {
        return resolve(DeveloperAuthServiceProtocol.self)
    }
    
    func apiKeyManagementService() -> APIKeyManagementServiceProtocol {
        return resolve(APIKeyManagementServiceProtocol.self)
    }
    
    func documentationGeneratorService() -> DocumentationGeneratorServiceProtocol {
        return resolve(DocumentationGeneratorServiceProtocol.self)
    }
    
    func sdkGeneratorService() -> SDKGeneratorServiceProtocol {
        return resolve(SDKGeneratorServiceProtocol.self)
    }
    
    func courseDataAPI() -> CourseDataAPIProtocol {
        return resolve(CourseDataAPIProtocol.self)
    }
    
    // MARK: - Revenue Infrastructure Convenience Methods
    
    func revenueService() -> RevenueServiceProtocol {
        return resolve(RevenueServiceProtocol.self)
    }
    
    func tenantManagementService() -> TenantManagementServiceProtocol {
        return resolve(TenantManagementServiceProtocol.self)
    }
    
    func apiUsageTrackingService() -> APIUsageTrackingServiceProtocol {
        return resolve(APIUsageTrackingServiceProtocol.self)
    }
    
    func billingService() -> BillingServiceProtocol {
        return resolve(BillingServiceProtocol.self)
    }
    
    func subscriptionService() -> SubscriptionServiceProtocol {
        return resolve(SubscriptionServiceProtocol.self)
    }
    
    // MARK: - Enterprise Authentication Convenience Methods
    
    func enterpriseAuthService() -> EnterpriseAuthServiceProtocol {
        return resolve(EnterpriseAuthServiceProtocol.self)
    }
    
    func consentManagementService() -> ConsentManagementServiceProtocol {
        return resolve(ConsentManagementServiceProtocol.self)
    }
    
    func roleManagementService() -> RoleManagementServiceProtocol {
        return resolve(RoleManagementServiceProtocol.self)
    }
    
    // MARK: - Phase 4 Gamification System Convenience Methods
    
    func securePaymentService() -> SecurePaymentServiceProtocol {
        return resolve(SecurePaymentServiceProtocol.self)
    }
    
    func multiTenantRevenueAttributionService() -> MultiTenantRevenueAttributionServiceProtocol {
        return resolve(MultiTenantRevenueAttributionServiceProtocol.self)
    }
    
    func socialChallengeSynchronizedHapticService() -> SocialChallengeSynchronizedHapticServiceProtocol {
        return resolve(SocialChallengeSynchronizedHapticServiceProtocol.self)
    }

    // MARK: - Environment Configuration

    func configure(for environment: ServiceEnvironment) {
        self.environment = environment
        singletonServices.removeAll()
        print("ServiceContainer configured for environment: \(environment)")
    }

    // MARK: - Performance Monitoring
    
    private func recordServiceAccess(key: String, creationTime: Double, fromCache: Bool) {
        if var metrics = serviceAccessMetrics[key] {
            metrics.accessCount += 1
            metrics.totalCreationTime += creationTime
            metrics.averageCreationTime = metrics.totalCreationTime / Double(metrics.accessCount)
            metrics.cacheHitRate = fromCache ? 
                (metrics.cacheHitRate * Double(metrics.accessCount - 1) + 1.0) / Double(metrics.accessCount) :
                (metrics.cacheHitRate * Double(metrics.accessCount - 1)) / Double(metrics.accessCount)
            metrics.lastAccessTime = Date()
            serviceAccessMetrics[key] = metrics
        } else {
            serviceAccessMetrics[key] = ServiceAccessMetrics(
                serviceName: key,
                accessCount: 1,
                totalCreationTime: creationTime,
                averageCreationTime: creationTime,
                cacheHitRate: fromCache ? 1.0 : 0.0,
                lastAccessTime: Date()
            )
        }
    }
    
    func getServiceMetrics() -> [ServiceAccessMetrics] {
        return Array(serviceAccessMetrics.values).sorted { $0.accessCount > $1.accessCount }
    }
    
    // MARK: - Service Preloading for Critical Golf Services
    
    func preloadCriticalGolfServices() async {
        let criticalServices = [
            "GolfCourseServiceProtocol",
            "LocationServiceProtocol",
            "WeatherServiceProtocol",
            "SessionManagementServiceProtocol",
            "BiometricAuthServiceProtocol",
            "AuthenticationServiceProtocol",
            "UserProfileServiceProtocol",
            "HapticFeedbackServiceProtocol",
            "WatchHapticFeedbackService",
            "TenantConfigurationServiceProtocol",
            "AnalyticsServiceProtocol",
            "RevenueServiceProtocol",
            "TenantManagementServiceProtocol",
            "APIUsageTrackingServiceProtocol",
            "EnterpriseAuthServiceProtocol",
            "ConsentManagementServiceProtocol",
            "RoleManagementServiceProtocol",
            "SecurityServiceProtocol",
            "RatingEngineServiceProtocol",
            "SocialChallengeServiceProtocol",
            "AchievementServiceProtocol",
            "LeaderboardServiceProtocol",
            "SecurePaymentServiceProtocol",
            "MultiTenantRevenueAttributionServiceProtocol",
            "SocialChallengeSynchronizedHapticServiceProtocol"
        ]
        
        await withTaskGroup(of: Void.self) { group in
            for serviceKey in criticalServices {
                group.addTask { [weak self] in
                    await self?.preloadService(serviceKey)
                }
            }
        }
    }
    
    private func preloadService(_ serviceKey: String) async {
        guard !preloadedServices.contains(serviceKey),
              let registration = serviceRegistrations[serviceKey],
              registration.lifecycle == .singleton else {
            return
        }
        
        let service = registration.factory(self)
        singletonServices[serviceKey] = service
        preloadedServices.insert(serviceKey)
        
        recordServiceAccess(key: serviceKey, creationTime: 0, fromCache: false)
        print("Preloaded golf service: \(serviceKey)")
    }
}

// MARK: - Service Registration Helper

private struct ServiceRegistration {
    let lifecycle: ServiceLifecycle
    let factory: (ServiceContainer) -> Any
}

// MARK: - SwiftUI Environment Integration

private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue: ServiceContainer = .shared
}

extension EnvironmentValues {
    var serviceContainer: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}

// MARK: - SwiftUI Property Wrapper

@propertyWrapper
struct ServiceInjected<T> {
    private let serviceType: T.Type

    init(_ serviceType: T.Type) {
        self.serviceType = serviceType
    }

    var wrappedValue: T {
        ServiceContainer.shared.resolve(serviceType)
    }
}

// MARK: - View Modifier for Service Container

struct ServiceContainerModifier: ViewModifier {
    let container: ServiceContainer

    func body(content: Content) -> some View {
        content
            .environmentObject(container)
            .environment(\.serviceContainer, container)
    }
}

extension View {
    func withServiceContainer(_ container: ServiceContainer = ServiceContainer.shared) -> some View {
        modifier(ServiceContainerModifier(container: container))
    }
}

// MARK: - Performance Monitoring Data Structures

struct ServiceAccessMetrics {
    let serviceName: String
    var accessCount: Int
    var totalCreationTime: Double
    var averageCreationTime: Double
    var cacheHitRate: Double
    var lastAccessTime: Date
    
    var formattedAverageCreationTime: String {
        String(format: "%.2f ms", averageCreationTime)
    }
    
    var formattedCacheHitRate: String {
        String(format: "%.1f%%", cacheHitRate * 100)
    }
}