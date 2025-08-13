import Foundation
import XCTest
import Appwrite
@testable import GolfFinderSwiftUI

// MARK: - Test Data Factory

class TestDataFactory {
    
    // MARK: - Singleton Access
    
    static let shared = TestDataFactory()
    
    private init() {}
    
    // MARK: - Golf Course Test Data
    
    func createMockGolfCourse(
        id: String = UUID().uuidString,
        name: String = "Test Golf Course",
        latitude: Double = 37.7749,
        longitude: Double = -122.4194,
        rating: Double = 4.5,
        difficulty: String = "Intermediate",
        holes: Int = 18
    ) -> GolfCourse {
        return GolfCourse(
            id: id,
            name: name,
            address: "\(Int.random(in: 100...9999)) Golf Course Dr, Test City, TC 12345",
            latitude: latitude,
            longitude: longitude,
            phone: "+1-555-GOLF-\(String(format: "%03d", Int.random(in: 100...999)))",
            website: "https://test-golf-course.com",
            rating: rating,
            reviewCount: Int.random(in: 10...500),
            priceRange: ["$", "$$", "$$$", "$$$$"].randomElement() ?? "$$",
            difficulty: difficulty,
            holes: holes,
            yardage: Int.random(in: 5000...7200),
            par: holes == 18 ? 72 : 36,
            description: "A premier test golf course featuring challenging holes and beautiful scenery.",
            amenities: ["Pro Shop", "Restaurant", "Driving Range", "Putting Green"].shuffled().prefix(Int.random(in: 2...4)).map(String.init),
            images: [
                "https://example.com/course1.jpg",
                "https://example.com/course2.jpg",
                "https://example.com/course3.jpg"
            ].shuffled().prefix(Int.random(in: 1...3)).map(String.init),
            teeTimeSlots: createTeeTimeSlots()
        )
    }
    
    func createMockGolfCourses(count: Int) -> [GolfCourse] {
        return (0..<count).map { index in
            createMockGolfCourse(
                name: "Golf Course \(index + 1)",
                latitude: 37.7749 + Double.random(in: -0.1...0.1),
                longitude: -122.4194 + Double.random(in: -0.1...0.1)
            )
        }
    }
    
    private func createTeeTimeSlots() -> [TeeTime] {
        let today = Date()
        var teeTimeSlots: [TeeTime] = []
        
        for day in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: day, to: today) ?? today
            let startOfDay = Calendar.current.startOfDay(for: date)
            
            for hour in 6...18 {
                for minute in [0, 15, 30, 45] {
                    let teeTime = Calendar.current.date(byAdding: .hour, value: hour, to: startOfDay)!
                    let finalTime = Calendar.current.date(byAdding: .minute, value: minute, to: teeTime)!
                    
                    teeTimeSlots.append(TeeTime(
                        id: UUID().uuidString,
                        golfCourseId: "test-course-id",
                        dateTime: finalTime,
                        price: Decimal(Double.random(in: 50...200)),
                        playersCount: Int.random(in: 1...4),
                        maxPlayers: 4,
                        status: .available
                    ))
                }
            }
        }
        
        return teeTimeSlots
    }
    
    // MARK: - Scorecard Test Data
    
    func createMockScorecard(
        id: String = UUID().uuidString,
        userId: String = UUID().uuidString,
        golfCourseId: String = UUID().uuidString,
        date: Date = Date(),
        holes: Int = 18
    ) -> Scorecard {
        return Scorecard(
            id: id,
            userId: userId,
            golfCourseId: golfCourseId,
            courseName: "Test Golf Course",
            date: date,
            holes: createMockHoleScores(count: holes),
            totalScore: Int.random(in: 70...110),
            par: holes == 18 ? 72 : 36,
            handicap: Double.random(in: 0...36),
            weather: createMockWeatherConditions(),
            notes: "Great round with friends!"
        )
    }
    
    private func createMockHoleScores(count: Int) -> [HoleScore] {
        return (1...count).map { holeNumber in
            HoleScore(
                holeNumber: holeNumber,
                par: [3, 4, 5].randomElement() ?? 4,
                score: Int.random(in: 2...8),
                putts: Int.random(in: 1...4),
                fairwayHit: Bool.random(),
                greenInRegulation: Bool.random()
            )
        }
    }
    
    private func createMockWeatherConditions() -> WeatherConditions {
        return WeatherConditions(
            temperature: Double.random(in: 10...35),
            humidity: Double.random(in: 30...90),
            windSpeed: Double.random(in: 0...25),
            condition: ["Sunny", "Partly Cloudy", "Overcast", "Light Rain"].randomElement() ?? "Sunny"
        )
    }
    
    // MARK: - Leaderboard Test Data
    
    func createMockLeaderboardEntry(
        userId: String = UUID().uuidString,
        username: String = "TestPlayer",
        rank: Int = 1,
        score: Int = 72
    ) -> LeaderboardEntry {
        return LeaderboardEntry(
            userId: userId,
            username: username,
            displayName: "\(username) \(Int.random(in: 100...999))",
            avatarURL: "https://example.com/avatar.jpg",
            rank: rank,
            score: score,
            roundsPlayed: Int.random(in: 1...50),
            averageScore: Double(score) + Double.random(in: -5...5),
            bestScore: score - Int.random(in: 0...10),
            handicap: Double.random(in: 0...36)
        )
    }
    
    func createMockLeaderboard(
        id: String = UUID().uuidString,
        name: String = "Weekly Championship",
        entryCount: Int = 20
    ) -> Leaderboard {
        let entries = (1...entryCount).map { rank in
            createMockLeaderboardEntry(
                username: "Player\(rank)",
                rank: rank,
                score: 70 + rank + Int.random(in: -2...2)
            )
        }
        
        return Leaderboard(
            id: id,
            name: name,
            description: "Weekly tournament leaderboard",
            type: .weekly,
            startDate: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            endDate: Date(),
            entries: entries,
            totalPrize: Decimal(Double.random(in: 500...5000)),
            isActive: true
        )
    }
    
    // MARK: - Revenue Test Data
    
    func createMockAPIUsage(
        tenantId: String = UUID().uuidString,
        endpoint: String = "/courses",
        callCount: Int = 100
    ) -> APIUsage {
        return APIUsage(
            tenantId: tenantId,
            endpoint: endpoint,
            method: HTTPMethod.GET,
            callCount: callCount,
            totalDataTransfer: Int64(callCount * Int.random(in: 1024...8192)),
            averageResponseTime: Double.random(in: 50...300),
            errorCount: Int.random(in: 0...5),
            successRate: Double.random(in: 0.95...1.0),
            period: .daily,
            timestamp: Date()
        )
    }
    
    func createMockRevenueEvent(
        tenantId: String = UUID().uuidString,
        amount: Decimal = 10.00
    ) -> RevenueEvent {
        return RevenueEvent(
            id: UUID(),
            tenantId: tenantId,
            eventType: .subscription,
            amount: amount,
            currency: "USD",
            timestamp: Date(),
            subscriptionId: UUID().uuidString,
            customerId: tenantId,
            invoiceId: UUID().uuidString,
            metadata: [
                "plan": "business",
                "billing_cycle": "monthly"
            ],
            source: .stripe
        )
    }
    
    func createMockTenant(
        id: String = UUID().uuidString,
        name: String = "Test Golf Club"
    ) -> Tenant {
        return Tenant(
            id: id,
            name: name,
            domain: "\(name.lowercased().replacingOccurrences(of: " ", with: "-")).golf.app",
            subscriptionTier: .business,
            status: .active,
            brandingConfig: TenantBrandingConfig(
                primaryColor: "#1E40AF",
                secondaryColor: "#10B981",
                logoURL: "https://example.com/logo.png",
                faviconURL: "https://example.com/favicon.ico"
            ),
            apiLimits: APILimits(
                dailyRequests: 10000,
                monthlyRequests: 300000,
                concurrentConnections: 50
            ),
            createdAt: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
            updatedAt: Date()
        )
    }
    
    // MARK: - Authentication Test Data
    
    func createMockUser(
        id: String = UUID().uuidString,
        email: String = "test@example.com",
        username: String = "testuser"
    ) -> User {
        return User(
            id: id,
            email: email,
            username: username,
            displayName: "Test User",
            firstName: "Test",
            lastName: "User",
            avatarURL: "https://example.com/avatar.jpg",
            handicap: Double.random(in: 0...36),
            homeClub: "Test Golf Club",
            memberSince: Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date(),
            preferences: UserPreferences(
                units: .imperial,
                notifications: true,
                privacy: .public
            )
        )
    }
    
    // MARK: - API Gateway Test Data
    
    func createMockAPIGatewayRequest(
        path: String = "/courses",
        method: HTTPMethod = .GET,
        apiKey: String = "test-api-key-12345"
    ) -> APIGatewayRequest {
        return APIGatewayRequest(
            path: path,
            method: method,
            version: .v1,
            apiKey: apiKey,
            headers: [
                "Content-Type": "application/json",
                "User-Agent": "GolfFinderApp/1.0",
                "X-API-Key": apiKey
            ],
            body: nil,
            queryParameters: [:]
        )
    }
    
    func createMockAPIKeyValidationResult(
        isValid: Bool = true,
        tier: APITier = .business
    ) -> APIKeyValidationResult {
        return APIKeyValidationResult(
            isValid: isValid,
            apiKey: "test-api-key-12345",
            tier: tier,
            userId: UUID().uuidString,
            expiresAt: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
            remainingQuota: 10000
        )
    }
    
    // MARK: - Load Testing Data Generation
    
    func generateLoadTestingDataset(userCount: Int = 50000) -> LoadTestingDataset {
        let users = (0..<userCount).map { index in
            createMockUser(
                email: "loadtest\(index)@example.com",
                username: "loaduser\(index)"
            )
        }
        
        let courses = createMockGolfCourses(count: 1000)
        let apiKeys = (0..<1000).map { index in
            "load-test-api-key-\(String(format: "%06d", index))"
        }
        
        return LoadTestingDataset(
            users: users,
            golfCourses: courses,
            apiKeys: apiKeys,
            testScenarios: createLoadTestScenarios()
        )
    }
    
    // MARK: - Advanced Realistic Data Generation
    
    func createRealisticBookingFlow() -> BookingFlowTestData {
        let user = createMockUser()
        let course = createMockGolfCourse()
        let selectedTeeTime = course.teeTimeSlots.randomElement()!
        
        let booking = MockBooking(
            id: UUID().uuidString,
            userId: user.id,
            golfCourseId: course.id,
            teeTime: selectedTeeTime,
            playerCount: Int.random(in: 1...4),
            totalAmount: selectedTeeTime.price,
            paymentMethod: ["card", "apple_pay", "google_pay"].randomElement()!,
            specialRequests: Bool.random() ? "Golf cart requested" : nil,
            status: .confirmed,
            createdAt: Date(),
            confirmationNumber: "GF\(Int.random(in: 100000...999999))"
        )
        
        let paymentIntent = MockPaymentIntent(
            id: "pi_\(UUID().uuidString)",
            amount: Int(truncating: selectedTeeTime.price as NSDecimalNumber) * 100,
            currency: "usd",
            status: .succeeded,
            paymentMethodId: "pm_\(UUID().uuidString)"
        )
        
        return BookingFlowTestData(
            user: user,
            course: course,
            booking: booking,
            paymentIntent: paymentIntent,
            searchFilters: createMockSearchFilters()
        )
    }
    
    func createMockSearchFilters() -> SearchFilters {
        return SearchFilters(
            location: LocationFilter(
                latitude: 37.7749,
                longitude: -122.4194,
                radiusMiles: Double.random(in: 5...50)
            ),
            dateRange: DateRange(
                startDate: Date(),
                endDate: Calendar.current.date(byAdding: .day, value: Int.random(in: 1...14), to: Date()) ?? Date()
            ),
            priceRange: PriceRange(
                min: Decimal(Double.random(in: 25...75)),
                max: Decimal(Double.random(in: 100...300))
            ),
            difficulty: ["Beginner", "Intermediate", "Advanced"].randomElement(),
            amenities: ["Pro Shop", "Restaurant", "Driving Range", "Putting Green", "Golf Cart Rental"].shuffled().prefix(Int.random(in: 1...3)).map(String.init),
            timeSlots: TimeSlotPreference(
                preferredTimes: ["morning", "afternoon", "evening"].shuffled().prefix(Int.random(in: 1...2)).map(String.init)
            )
        )
    }
    
    func generateRealisticWeatherScenarios() -> [WeatherScenario] {
        return [
            WeatherScenario(
                name: "Perfect Golf Day",
                conditions: WeatherConditions(
                    temperature: 22.0,
                    humidity: 45.0,
                    windSpeed: 8.0,
                    condition: "Sunny"
                ),
                playabilityScore: 10.0,
                recommendedGear: ["sunscreen", "hat", "water"]
            ),
            WeatherScenario(
                name: "Challenging Windy Day",
                conditions: WeatherConditions(
                    temperature: 18.0,
                    humidity: 60.0,
                    windSpeed: 25.0,
                    condition: "Partly Cloudy"
                ),
                playabilityScore: 7.0,
                recommendedGear: ["windbreaker", "extra layers", "secured hat"]
            ),
            WeatherScenario(
                name: "Hot Summer Day",
                conditions: WeatherConditions(
                    temperature: 35.0,
                    humidity: 80.0,
                    windSpeed: 5.0,
                    condition: "Hot and Humid"
                ),
                playabilityScore: 6.0,
                recommendedGear: ["cooling towel", "electrolytes", "lightweight clothing"]
            ),
            WeatherScenario(
                name: "Light Rain Play",
                conditions: WeatherConditions(
                    temperature: 15.0,
                    humidity: 95.0,
                    windSpeed: 12.0,
                    condition: "Light Rain"
                ),
                playabilityScore: 4.0,
                recommendedGear: ["rain gear", "waterproof gloves", "umbrella"]
            )
        ]
    }
    
    func createMockScorecardWithStatistics() -> DetailedScorecard {
        let holes = createMockHoleScores(count: 18)
        let totalScore = holes.reduce(0) { $0 + $1.score }
        let totalPar = holes.reduce(0) { $0 + $1.par }
        
        let statistics = RoundStatistics(
            totalScore: totalScore,
            totalPar: totalPar,
            scoreToPar: totalScore - totalPar,
            totalPutts: holes.reduce(0) { $0 + $1.putts },
            fairwaysHit: holes.filter { $0.fairwayHit }.count,
            greensInRegulation: holes.filter { $0.greenInRegulation }.count,
            scrambling: calculateScrambling(holes: holes),
            averageDriveDistance: Double.random(in: 180...280),
            longestDrive: Double.random(in: 250...320),
            shortestPutt: Double.random(in: 0.5...3.0),
            longestPutt: Double.random(in: 8...30)
        )
        
        return DetailedScorecard(
            id: UUID().uuidString,
            userId: UUID().uuidString,
            golfCourseId: UUID().uuidString,
            courseName: "Championship Test Course",
            date: Date(),
            holes: holes,
            statistics: statistics,
            weather: createMockWeatherConditions(),
            playingPartners: createMockPlayingPartners(),
            notes: "Great round! Improved iron play significantly.",
            handicapIndex: Double.random(in: 5...25),
            courseHandicap: Int.random(in: 8...30),
            playingHandicap: Int.random(in: 8...30)
        )
    }
    
    private func calculateScrambling(holes: [HoleScore]) -> Double {
        let missedGIR = holes.filter { !$0.greenInRegulation }
        let scrambled = missedGIR.filter { $0.score <= $0.par }
        return missedGIR.isEmpty ? 0.0 : Double(scrambled.count) / Double(missedGIR.count)
    }
    
    private func createMockPlayingPartners() -> [PlayingPartner] {
        let partnerCount = Int.random(in: 1...3)
        return (0..<partnerCount).map { index in
            PlayingPartner(
                name: "Partner \(index + 1)",
                handicap: Double.random(in: 0...36),
                totalScore: Int.random(in: 70...110)
            )
        }
    }
    
    func createMockTournamentLeaderboard() -> TournamentLeaderboard {
        let entryCount = Int.random(in: 50...200)
        let entries = (1...entryCount).map { rank in
            createAdvancedLeaderboardEntry(rank: rank)
        }
        
        return TournamentLeaderboard(
            id: UUID().uuidString,
            name: "Monthly Club Championship",
            description: "Prestigious monthly tournament featuring the club's best players",
            type: .tournament,
            format: .strokePlay,
            startDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
            endDate: Date(),
            entries: entries,
            totalPrize: Decimal(2500.00),
            entryFee: Decimal(50.00),
            courseId: UUID().uuidString,
            courseName: "Tournament Golf Club",
            weather: createMockWeatherConditions(),
            isActive: false,
            isCompleted: true,
            cutline: entryCount > 100 ? 70 : nil,
            playoffResults: rank <= 3 ? createMockPlayoffResults() : nil
        )
    }
    
    private func createAdvancedLeaderboardEntry(rank: Int) -> AdvancedLeaderboardEntry {
        let baseScore = 68 + rank + Int.random(in: -2...3)
        return AdvancedLeaderboardEntry(
            userId: UUID().uuidString,
            username: "Player\(rank)",
            displayName: "Tournament Player \(rank)",
            avatarURL: "https://example.com/avatars/player\(rank).jpg",
            rank: rank,
            score: baseScore,
            scoreToPar: baseScore - 72,
            roundsPlayed: 4,
            rounds: createMockRoundScores(),
            averageScore: Double(baseScore) + Double.random(in: -1...1),
            bestScore: baseScore - Int.random(in: 0...5),
            handicap: Double.random(in: 0...25),
            nationality: ["USA", "CAN", "GBR", "AUS", "JPN", "DEU"].randomElement() ?? "USA",
            earnings: Decimal(Double.random(in: 100...1000)),
            holesCompleted: 72,
            currentStreak: StreakType.allCases.randomElement() ?? .none
        )
    }
    
    private func createMockRoundScores() -> [RoundScore] {
        return (1...4).map { round in
            let score = Int.random(in: 68...78)
            return RoundScore(
                round: round,
                score: score,
                scoreToPar: score - 72,
                date: Calendar.current.date(byAdding: .day, value: -round, to: Date()) ?? Date()
            )
        }
    }
    
    private func createMockPlayoffResults() -> PlayoffResult {
        return PlayoffResult(
            playoffType: .suddenDeath,
            holesPlayed: Int.random(in: 1...3),
            winner: "Player1",
            participants: ["Player1", "Player2", "Player3"].shuffled().prefix(Int.random(in: 2...3)).map(String.init)
        )
    }
    
    // MARK: - Performance Testing Data
    
    func generatePerformanceTestDataset() -> PerformanceTestDataset {
        return PerformanceTestDataset(
            massiveUserList: (0..<100000).map { createMockUser(username: "perfuser\($0)") },
            extensiveCourseList: createMockGolfCourses(count: 5000),
            highVolumeBookings: generateHighVolumeBookings(),
            concurrentSearchQueries: generateConcurrentSearchQueries(),
            largeLeaderboards: generateLargeLeaderboards(),
            memoryIntensiveContent: generateMemoryIntensiveContent()
        )
    }
    
    private func generateHighVolumeBookings() -> [MockBooking] {
        return (0..<50000).map { index in
            MockBooking(
                id: "booking-\(index)",
                userId: "user-\(index % 10000)",
                golfCourseId: "course-\(index % 1000)",
                teeTime: createMockTeeTime(),
                playerCount: Int.random(in: 1...4),
                totalAmount: Decimal(Double.random(in: 50...300)),
                paymentMethod: "card",
                specialRequests: nil,
                status: .confirmed,
                createdAt: Date(),
                confirmationNumber: "GF\(100000 + index)"
            )
        }
    }
    
    private func generateConcurrentSearchQueries() -> [SearchQuery] {
        return (0..<1000).map { index in
            SearchQuery(
                id: UUID().uuidString,
                query: "golf courses near \(index)",
                filters: createMockSearchFilters(),
                resultCount: Int.random(in: 0...100),
                executionTimeMs: Double.random(in: 50...500),
                timestamp: Date()
            )
        }
    }
    
    private func generateLargeLeaderboards() -> [Leaderboard] {
        return (0..<10).map { index in
            createMockLeaderboard(
                name: "Large Tournament \(index)",
                entryCount: 10000
            )
        }
    }
    
    private func generateMemoryIntensiveContent() -> [MemoryIntensiveItem] {
        return (0..<1000).map { index in
            MemoryIntensiveItem(
                id: UUID().uuidString,
                data: String(repeating: "A", count: 10000), // 10KB per item
                metadata: (0..<100).map { "key\($0)": "value\($0)" }.reduce(into: [:]) { $0[$1.key] = $1.value }
            )
        }
    }
    
    private func createLoadTestScenarios() -> [LoadTestScenario] {
        return [
            LoadTestScenario(
                name: "Course Discovery",
                description: "Users searching and browsing golf courses",
                userPercentage: 0.4,
                requestsPerUser: 10,
                duration: 300 // 5 minutes
            ),
            LoadTestScenario(
                name: "Booking Flow",
                description: "Users completing tee time bookings",
                userPercentage: 0.2,
                requestsPerUser: 15,
                duration: 600 // 10 minutes
            ),
            LoadTestScenario(
                name: "API Gateway Usage",
                description: "External developers using API endpoints",
                userPercentage: 0.3,
                requestsPerUser: 50,
                duration: 1800 // 30 minutes
            ),
            LoadTestScenario(
                name: "Real-time Features",
                description: "Live scoring and leaderboard updates",
                userPercentage: 0.1,
                requestsPerUser: 100,
                duration: 900 // 15 minutes
            )
        ]
    }
}

// MARK: - Supporting Data Models

struct LoadTestingDataset {
    let users: [User]
    let golfCourses: [GolfCourse]
    let apiKeys: [String]
    let testScenarios: [LoadTestScenario]
}

struct LoadTestScenario {
    let name: String
    let description: String
    let userPercentage: Double
    let requestsPerUser: Int
    let duration: TimeInterval
}

struct HoleScore {
    let holeNumber: Int
    let par: Int
    let score: Int
    let putts: Int
    let fairwayHit: Bool
    let greenInRegulation: Bool
}

struct WeatherConditions {
    let temperature: Double
    let humidity: Double
    let windSpeed: Double
    let condition: String
}

struct LeaderboardEntry {
    let userId: String
    let username: String
    let displayName: String
    let avatarURL: String
    let rank: Int
    let score: Int
    let roundsPlayed: Int
    let averageScore: Double
    let bestScore: Int
    let handicap: Double
}

struct UserPreferences {
    let units: MeasurementSystem
    let notifications: Bool
    let privacy: PrivacyLevel
}

enum MeasurementSystem {
    case imperial
    case metric
}

enum PrivacyLevel {
    case private
    case friends
    case public
}

struct APILimits {
    let dailyRequests: Int
    let monthlyRequests: Int
    let concurrentConnections: Int
}

struct TenantBrandingConfig {
    let primaryColor: String
    let secondaryColor: String
    let logoURL: String
    let faviconURL: String
}

// MARK: - Advanced Testing Data Models

struct BookingFlowTestData {
    let user: User
    let course: GolfCourse
    let booking: MockBooking
    let paymentIntent: MockPaymentIntent
    let searchFilters: SearchFilters
}

struct MockBooking {
    let id: String
    let userId: String
    let golfCourseId: String
    let teeTime: TeeTime
    let playerCount: Int
    let totalAmount: Decimal
    let paymentMethod: String
    let specialRequests: String?
    let status: BookingStatus
    let createdAt: Date
    let confirmationNumber: String
}

enum BookingStatus {
    case pending
    case confirmed
    case cancelled
    case completed
}

struct MockPaymentIntent {
    let id: String
    let amount: Int
    let currency: String
    let status: PaymentStatus
    let paymentMethodId: String
}

enum PaymentStatus {
    case requiresPaymentMethod
    case requiresConfirmation
    case processing
    case succeeded
    case failed
    case cancelled
}

struct SearchFilters {
    let location: LocationFilter
    let dateRange: DateRange
    let priceRange: PriceRange
    let difficulty: String?
    let amenities: [String]
    let timeSlots: TimeSlotPreference
}

struct LocationFilter {
    let latitude: Double
    let longitude: Double
    let radiusMiles: Double
}

struct DateRange {
    let startDate: Date
    let endDate: Date
}

struct PriceRange {
    let min: Decimal
    let max: Decimal
}

struct TimeSlotPreference {
    let preferredTimes: [String]
}

struct WeatherScenario {
    let name: String
    let conditions: WeatherConditions
    let playabilityScore: Double
    let recommendedGear: [String]
}

struct DetailedScorecard {
    let id: String
    let userId: String
    let golfCourseId: String
    let courseName: String
    let date: Date
    let holes: [HoleScore]
    let statistics: RoundStatistics
    let weather: WeatherConditions
    let playingPartners: [PlayingPartner]
    let notes: String
    let handicapIndex: Double
    let courseHandicap: Int
    let playingHandicap: Int
}

struct RoundStatistics {
    let totalScore: Int
    let totalPar: Int
    let scoreToPar: Int
    let totalPutts: Int
    let fairwaysHit: Int
    let greensInRegulation: Int
    let scrambling: Double
    let averageDriveDistance: Double
    let longestDrive: Double
    let shortestPutt: Double
    let longestPutt: Double
}

struct PlayingPartner {
    let name: String
    let handicap: Double
    let totalScore: Int
}

struct TournamentLeaderboard {
    let id: String
    let name: String
    let description: String
    let type: LeaderboardType
    let format: TournamentFormat
    let startDate: Date
    let endDate: Date
    let entries: [AdvancedLeaderboardEntry]
    let totalPrize: Decimal
    let entryFee: Decimal
    let courseId: String
    let courseName: String
    let weather: WeatherConditions
    let isActive: Bool
    let isCompleted: Bool
    let cutline: Int?
    let playoffResults: PlayoffResult?
}

enum TournamentFormat {
    case strokePlay
    case matchPlay
    case scramble
    case bestBall
}

struct AdvancedLeaderboardEntry {
    let userId: String
    let username: String
    let displayName: String
    let avatarURL: String
    let rank: Int
    let score: Int
    let scoreToPar: Int
    let roundsPlayed: Int
    let rounds: [RoundScore]
    let averageScore: Double
    let bestScore: Int
    let handicap: Double
    let nationality: String
    let earnings: Decimal
    let holesCompleted: Int
    let currentStreak: StreakType
}

struct RoundScore {
    let round: Int
    let score: Int
    let scoreToPar: Int
    let date: Date
}

struct PlayoffResult {
    let playoffType: PlayoffType
    let holesPlayed: Int
    let winner: String
    let participants: [String]
}

enum PlayoffType {
    case suddenDeath
    case aggregate
    case matchPlay
}

enum StreakType: CaseIterable {
    case none
    case birdieStreak
    case parStreak
    case underParStreak
    case cuts
}

struct PerformanceTestDataset {
    let massiveUserList: [User]
    let extensiveCourseList: [GolfCourse]
    let highVolumeBookings: [MockBooking]
    let concurrentSearchQueries: [SearchQuery]
    let largeLeaderboards: [Leaderboard]
    let memoryIntensiveContent: [MemoryIntensiveItem]
}

struct SearchQuery {
    let id: String
    let query: String
    let filters: SearchFilters
    let resultCount: Int
    let executionTimeMs: Double
    let timestamp: Date
}

struct MemoryIntensiveItem {
    let id: String
    let data: String
    let metadata: [String: String]
}

// MARK: - Test Environment Configuration

class TestEnvironmentManager {
    static let shared = TestEnvironmentManager()
    
    private init() {}
    
    func setupTestEnvironment() {
        // Configure ServiceContainer for testing
        ServiceContainer.shared.configure(for: .test)
        
        // Set up test database connection
        configureTestDatabase()
        
        // Initialize mock services
        initializeMockServices()
        
        // Set up test analytics (disabled in tests)
        disableAnalytics()
    }
    
    func teardownTestEnvironment() {
        // Clean up test data
        cleanupTestData()
        
        // Reset service container
        ServiceContainer.shared.configure(for: .development)
    }
    
    private func configureTestDatabase() {
        // Configure Appwrite test database
        // This would typically point to a test database instance
        print("Configuring test database environment")
    }
    
    private func initializeMockServices() {
        // Ensure all services are using mock implementations
        print("Initializing mock services for testing")
    }
    
    private func disableAnalytics() {
        // Disable analytics during testing
        print("Disabling analytics for test environment")
    }
    
    private func cleanupTestData() {
        // Clean up any test data created during tests
        print("Cleaning up test data")
    }
    
    private func createMockTeeTime() -> TeeTime {
        return TeeTime(
            id: UUID().uuidString,
            golfCourseId: "test-course-id",
            dateTime: Date(),
            price: Decimal(Double.random(in: 50...200)),
            playersCount: Int.random(in: 1...4),
            maxPlayers: 4,
            status: .available
        )
    }
}