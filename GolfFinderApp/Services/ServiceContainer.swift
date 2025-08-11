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
        
        register(
            AuthenticationServiceProtocol.self,
            lifecycle: .singleton
        ) { container in
            if container.environment.useMockServices {
                return MockAuthenticationService()
            }
            return AuthenticationService(appwriteClient: container.appwriteClient)
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
                return MockHapticFeedbackService()
            }
            return GolfHapticFeedbackService()
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
            return SecurityService()
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
    
    func hapticFeedbackService() -> HapticFeedbackServiceProtocol {
        return resolve(HapticFeedbackServiceProtocol.self)
    }
    
    func analyticsService() -> AnalyticsServiceProtocol {
        return resolve(AnalyticsServiceProtocol.self)
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
            "AuthenticationServiceProtocol",
            "HapticFeedbackServiceProtocol",
            "AnalyticsServiceProtocol"
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