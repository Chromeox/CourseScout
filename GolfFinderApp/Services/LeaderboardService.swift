import Foundation
import Combine
import Appwrite

// MARK: - Real-time Leaderboard Service Implementation

@MainActor
class LeaderboardService: LeaderboardServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let appwriteManager: AppwriteManager
    private var subscriptions = Set<AnyCancellable>()
    private var realtimeSubscriptions = [String: AnyCancellable]()
    private let cache = LeaderboardCache()
    
    // Publishers for real-time updates
    private let leaderboardUpdateSubject = PassthroughSubject<LeaderboardUpdate, Error>()
    private let leaderboardsSubject = PassthroughSubject<[Leaderboard], Error>()
    
    // MARK: - Configuration
    
    private let databaseId = "golf_finder_db"
    private let leaderboardsCollection = "leaderboards"
    private let entriesCollection = "leaderboard_entries"
    private let challengesCollection = "social_challenges"
    private let achievementsCollection = "achievements"
    
    // MARK: - Initialization
    
    init(appwriteManager: AppwriteManager = .shared) {
        self.appwriteManager = appwriteManager
    }
    
    // MARK: - Leaderboard Management
    
    func getLeaderboards(for courseId: String) async throws -> [Leaderboard] {
        // Check cache first
        if let cached = cache.getLeaderboards(for: courseId) {
            return cached
        }
        
        do {
            let queries = [
                Query.equal("course_id", value: courseId),
                Query.equal("is_active", value: true),
                Query.orderDesc("updated_at"),
                Query.limit(100)
            ]
            
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: leaderboardsCollection,
                queries: queries
            )
            
            let leaderboards = try response.documents.compactMap { document in
                try mapDocumentToLeaderboard(document)
            }
            
            // Cache the results
            cache.setLeaderboards(leaderboards, for: courseId)
            
            return leaderboards
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    func getLeaderboard(id: String) async throws -> Leaderboard {
        // Check cache first
        if let cached = cache.getLeaderboard(id: id) {
            return cached
        }
        
        do {
            let document = try await appwriteManager.databases.getDocument(
                databaseId: databaseId,
                collectionId: leaderboardsCollection,
                documentId: id
            )
            
            let leaderboard = try mapDocumentToLeaderboard(document)
            
            // Fetch entries for this leaderboard
            let entriesResponse = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: entriesCollection,
                queries: [
                    Query.equal("leaderboard_id", value: id),
                    Query.orderAsc("position"),
                    Query.limit(100)
                ]
            )
            
            var leaderboardWithEntries = leaderboard
            leaderboardWithEntries.entries = try entriesResponse.documents.compactMap { document in
                try mapDocumentToLeaderboardEntry(document)
            }
            
            // Cache the result
            cache.setLeaderboard(leaderboardWithEntries)
            
            return leaderboardWithEntries
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    func createLeaderboard(_ leaderboard: Leaderboard) async throws -> Leaderboard {
        do {
            let data = try mapLeaderboardToDocument(leaderboard)
            
            let document = try await appwriteManager.databases.createDocument(
                databaseId: databaseId,
                collectionId: leaderboardsCollection,
                documentId: leaderboard.id.isEmpty ? ID.unique() : leaderboard.id,
                data: data
            )
            
            let createdLeaderboard = try mapDocumentToLeaderboard(document)
            
            // Clear cache to force refresh
            cache.clearCache()
            
            return createdLeaderboard
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    func updateLeaderboard(_ leaderboard: Leaderboard) async throws -> Leaderboard {
        do {
            let data = try mapLeaderboardToDocument(leaderboard)
            
            let document = try await appwriteManager.databases.updateDocument(
                databaseId: databaseId,
                collectionId: leaderboardsCollection,
                documentId: leaderboard.id,
                data: data
            )
            
            let updatedLeaderboard = try mapDocumentToLeaderboard(document)
            
            // Update cache
            cache.setLeaderboard(updatedLeaderboard)
            
            return updatedLeaderboard
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    func deleteLeaderboard(id: String) async throws {
        do {
            // Delete all entries first
            let entriesResponse = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: entriesCollection,
                queries: [Query.equal("leaderboard_id", value: id)]
            )
            
            for entry in entriesResponse.documents {
                try await appwriteManager.databases.deleteDocument(
                    databaseId: databaseId,
                    collectionId: entriesCollection,
                    documentId: entry.id
                )
            }
            
            // Delete the leaderboard
            try await appwriteManager.databases.deleteDocument(
                databaseId: databaseId,
                collectionId: leaderboardsCollection,
                documentId: id
            )
            
            // Clear cache
            cache.removeLeaderboard(id: id)
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    // MARK: - Entry Management
    
    func submitEntry(_ entry: LeaderboardEntry) async throws -> LeaderboardEntry {
        do {
            let data = try mapLeaderboardEntryToDocument(entry)
            
            let document = try await appwriteManager.databases.createDocument(
                databaseId: databaseId,
                collectionId: entriesCollection,
                documentId: entry.id.isEmpty ? ID.unique() : entry.id,
                data: data
            )
            
            let createdEntry = try mapDocumentToLeaderboardEntry(document)
            
            // Recalculate positions for this leaderboard
            await recalculatePositions(for: entry.leaderboardId)
            
            // Clear relevant cache
            cache.removeLeaderboard(id: entry.leaderboardId)
            
            // Notify real-time subscribers
            let update = LeaderboardUpdate(
                leaderboardId: entry.leaderboardId,
                type: .entryAdded,
                entry: createdEntry,
                timestamp: Date()
            )
            leaderboardUpdateSubject.send(update)
            
            return createdEntry
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    func updateEntry(_ entry: LeaderboardEntry) async throws -> LeaderboardEntry {
        do {
            let data = try mapLeaderboardEntryToDocument(entry)
            
            let document = try await appwriteManager.databases.updateDocument(
                databaseId: databaseId,
                collectionId: entriesCollection,
                documentId: entry.id,
                data: data
            )
            
            let updatedEntry = try mapDocumentToLeaderboardEntry(document)
            
            // Recalculate positions
            await recalculatePositions(for: entry.leaderboardId)
            
            // Clear cache
            cache.removeLeaderboard(id: entry.leaderboardId)
            
            // Notify subscribers
            let update = LeaderboardUpdate(
                leaderboardId: entry.leaderboardId,
                type: .entryUpdated,
                entry: updatedEntry,
                timestamp: Date()
            )
            leaderboardUpdateSubject.send(update)
            
            return updatedEntry
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    func getEntries(for leaderboardId: String, limit: Int? = nil, offset: Int? = nil) async throws -> [LeaderboardEntry] {
        do {
            var queries = [
                Query.equal("leaderboard_id", value: leaderboardId),
                Query.orderAsc("position")
            ]
            
            if let limit = limit {
                queries.append(Query.limit(limit))
            }
            
            if let offset = offset {
                queries.append(Query.offset(offset))
            }
            
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: entriesCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToLeaderboardEntry(document)
            }
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    func getPlayerEntry(leaderboardId: String, playerId: String) async throws -> LeaderboardEntry? {
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: entriesCollection,
                queries: [
                    Query.equal("leaderboard_id", value: leaderboardId),
                    Query.equal("player_id", value: playerId)
                ]
            )
            
            return try response.documents.first.map { document in
                try mapDocumentToLeaderboardEntry(document)
            }
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    func removeEntry(leaderboardId: String, playerId: String) async throws {
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: entriesCollection,
                queries: [
                    Query.equal("leaderboard_id", value: leaderboardId),
                    Query.equal("player_id", value: playerId)
                ]
            )
            
            for entry in response.documents {
                try await appwriteManager.databases.deleteDocument(
                    databaseId: databaseId,
                    collectionId: entriesCollection,
                    documentId: entry.id
                )
            }
            
            // Recalculate positions
            await recalculatePositions(for: leaderboardId)
            
            // Clear cache
            cache.removeLeaderboard(id: leaderboardId)
            
            // Notify subscribers
            let update = LeaderboardUpdate(
                leaderboardId: leaderboardId,
                type: .entryRemoved,
                entry: nil,
                timestamp: Date()
            )
            leaderboardUpdateSubject.send(update)
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    // MARK: - Real-time Subscriptions
    
    func subscribeToLeaderboard(_ leaderboardId: String) -> AnyPublisher<LeaderboardUpdate, Error> {
        // Subscribe to Appwrite real-time updates
        let realtimeStream = appwriteManager.realtime.subscribe(
            channels: [
                "databases.\(databaseId).collections.\(entriesCollection).documents",
                "databases.\(databaseId).collections.\(leaderboardsCollection).documents"
            ]
        )
        
        let subscription = realtimeStream
            .compactMap { [weak self] response in
                self?.processRealtimeUpdate(response, for: leaderboardId)
            }
            .subscribe(leaderboardUpdateSubject)
        
        realtimeSubscriptions[leaderboardId] = subscription
        
        return leaderboardUpdateSubject
            .filter { $0.leaderboardId == leaderboardId }
            .eraseToAnyPublisher()
    }
    
    func subscribeToLeaderboards(courseId: String) -> AnyPublisher<[Leaderboard], Error> {
        // Set up real-time subscription for course leaderboards
        let realtimeStream = appwriteManager.realtime.subscribe(
            channels: ["databases.\(databaseId).collections.\(leaderboardsCollection).documents"]
        )
        
        let subscription = realtimeStream
            .compactMap { [weak self] response in
                self?.processLeaderboardsUpdate(response, for: courseId)
            }
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("❌ Leaderboards subscription error: \(error)")
                    }
                },
                receiveValue: { [weak self] leaderboards in
                    self?.leaderboardsSubject.send(leaderboards)
                }
            )
        
        realtimeSubscriptions[courseId] = subscription
        
        return leaderboardsSubject.eraseToAnyPublisher()
    }
    
    func unsubscribeFromLeaderboard(_ leaderboardId: String) {
        realtimeSubscriptions[leaderboardId]?.cancel()
        realtimeSubscriptions.removeValue(forKey: leaderboardId)
    }
    
    func unsubscribeFromAll() {
        realtimeSubscriptions.values.forEach { $0.cancel() }
        realtimeSubscriptions.removeAll()
    }
    
    // MARK: - Rankings & Statistics
    
    func getRankings(for leaderboardId: String) async throws -> [LeaderboardEntry] {
        return try await getEntries(for: leaderboardId)
    }
    
    func getPlayerPosition(leaderboardId: String, playerId: String) async throws -> Int? {
        guard let entry = try await getPlayerEntry(leaderboardId: leaderboardId, playerId: playerId) else {
            return nil
        }
        return entry.position
    }
    
    func getLeaderboardStats(for leaderboardId: String) async throws -> LeaderboardStats {
        // Implementation would calculate statistics from entries
        // This is a simplified version
        let entries = try await getEntries(for: leaderboardId)
        
        let scores = entries.map { $0.score }
        let totalRounds = entries.count
        let averageScore = scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(totalRounds)
        let bestScore = scores.min() ?? 0
        let worstScore = scores.max() ?? 0
        
        return LeaderboardStats(
            totalRounds: totalRounds,
            averageScore: averageScore,
            bestScore: bestScore,
            worstScore: worstScore,
            participationRate: 0.8, // This would be calculated based on course data
            competitiveBalance: calculateCompetitiveBalance(from: scores),
            scoreImprovement: 0.0, // Would be calculated from historical data
            popularityTrend: .stable,
            engagementMetrics: EngagementMetrics(
                viewCount: 0,
                shareCount: 0,
                commentCount: 0,
                participantRetention: 0.7,
                averageSessionTime: 300
            )
        )
    }
    
    func getTrendingLeaderboards(courseId: String) async throws -> [Leaderboard] {
        let queries = [
            Query.equal("course_id", value: courseId),
            Query.equal("is_active", value: true),
            Query.orderDesc("updated_at"),
            Query.limit(10)
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: leaderboardsCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToLeaderboard(document)
            }
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    // MARK: - Social Features (Simplified Implementation)
    
    func createChallenge(_ challenge: SocialChallenge) async throws -> SocialChallenge {
        // Implementation would create a challenge document
        return challenge
    }
    
    func joinChallenge(challengeId: String, playerId: String) async throws {
        // Implementation would update challenge participants
    }
    
    func getPlayerChallenges(playerId: String) async throws -> [SocialChallenge] {
        // Implementation would fetch challenges for player
        return []
    }
    
    func getPublicChallenges(courseId: String) async throws -> [SocialChallenge] {
        // Implementation would fetch public challenges
        return []
    }
    
    func inviteToChallenge(challengeId: String, playerIds: [String]) async throws {
        // Implementation would send invitations
    }
    
    // MARK: - Achievements (Simplified Implementation)
    
    func getPlayerAchievements(playerId: String) async throws -> [Achievement] {
        return []
    }
    
    func awardAchievement(_ achievement: Achievement, to playerId: String) async throws {
        // Implementation would award achievement
    }
    
    func getAvailableAchievements(courseId: String) async throws -> [Achievement] {
        return []
    }
    
    // MARK: - Search & Filtering
    
    func searchLeaderboards(query: String, courseId: String?) async throws -> [Leaderboard] {
        var queries = [Query.search("name", query)]
        
        if let courseId = courseId {
            queries.append(Query.equal("course_id", value: courseId))
        }
        
        queries.append(Query.equal("is_active", value: true))
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: leaderboardsCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToLeaderboard(document)
            }
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    func filterLeaderboards(
        courseId: String?,
        type: LeaderboardType?,
        period: LeaderboardPeriod?,
        isActive: Bool?
    ) async throws -> [Leaderboard] {
        var queries: [String] = []
        
        if let courseId = courseId {
            queries.append(Query.equal("course_id", value: courseId))
        }
        
        if let type = type {
            queries.append(Query.equal("type", value: type.rawValue))
        }
        
        if let period = period {
            queries.append(Query.equal("period", value: period.rawValue))
        }
        
        if let isActive = isActive {
            queries.append(Query.equal("is_active", value: isActive))
        }
        
        queries.append(Query.orderDesc("updated_at"))
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: leaderboardsCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToLeaderboard(document)
            }
        } catch {
            throw appwriteManager.handleAppwriteError(error)
        }
    }
    
    func getNearbyLeaderboards(
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> [Leaderboard] {
        // This would require geospatial queries - simplified for now
        return []
    }
    
    // MARK: - Performance Analytics (Simplified Implementation)
    
    func getPlayerPerformance(
        playerId: String,
        courseId: String?,
        dateRange: DateInterval?
    ) async throws -> PlayerPerformanceData {
        // Simplified implementation
        return PlayerPerformanceData(
            playerId: playerId,
            courseId: courseId,
            dateRange: dateRange ?? DateInterval(start: Date().addingTimeInterval(-86400 * 30), end: Date()),
            rounds: [],
            averageScore: 85.0,
            bestScore: 78,
            worstScore: 92,
            improvement: 2.5,
            consistency: 0.75,
            strengths: [],
            weaknesses: []
        )
    }
    
    func comparePlayerPerformance(
        playerId: String,
        compareWith: [String],
        courseId: String?
    ) async throws -> PerformanceComparison {
        // Simplified implementation
        let playerData = try await getPlayerPerformance(playerId: playerId, courseId: courseId, dateRange: nil)
        
        return PerformanceComparison(
            player: playerData,
            comparisons: [],
            rankings: ComparisonRankings(
                overall: 1,
                driving: 1,
                approach: 1,
                shortGame: 1,
                putting: 1,
                consistency: 1
            )
        )
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        cache.clearCache()
    }
    
    func refreshCache(for leaderboardId: String) async throws {
        cache.removeLeaderboard(id: leaderboardId)
        _ = try await getLeaderboard(id: leaderboardId)
    }
    
    func getCachedEntriesCount() -> Int {
        return cache.getCachedEntriesCount()
    }
}

// MARK: - Private Helper Methods

private extension LeaderboardService {
    
    func recalculatePositions(for leaderboardId: String) async {
        do {
            let entries = try await getEntries(for: leaderboardId)
            let sortedEntries = entries.sorted { $0.score < $1.score }
            
            for (index, entry) in sortedEntries.enumerated() {
                var updatedEntry = entry
                updatedEntry.previousPosition = entry.position
                updatedEntry.position = index + 1
                
                let data = try mapLeaderboardEntryToDocument(updatedEntry)
                
                try await appwriteManager.databases.updateDocument(
                    databaseId: databaseId,
                    collectionId: entriesCollection,
                    documentId: entry.id,
                    data: data
                )
            }
            
            // Notify position changes
            let update = LeaderboardUpdate(
                leaderboardId: leaderboardId,
                type: .positionsChanged,
                entry: nil,
                timestamp: Date()
            )
            leaderboardUpdateSubject.send(update)
            
        } catch {
            print("❌ Failed to recalculate positions: \(error)")
        }
    }
    
    func calculateCompetitiveBalance(from scores: [Int]) -> Double {
        guard scores.count > 1 else { return 0.0 }
        
        let sortedScores = scores.sorted()
        let range = Double(sortedScores.last! - sortedScores.first!)
        let median = Double(sortedScores[sortedScores.count / 2])
        
        return median > 0 ? (range / median) : 0.0
    }
    
    func processRealtimeUpdate(_ response: AppwriteModels.RealtimeResponse, for leaderboardId: String) -> LeaderboardUpdate? {
        // Process real-time updates and return appropriate LeaderboardUpdate
        // This would parse the Appwrite response and create updates
        return nil
    }
    
    func processLeaderboardsUpdate(_ response: AppwriteModels.RealtimeResponse, for courseId: String) -> [Leaderboard]? {
        // Process leaderboards list updates
        return nil
    }
}

// MARK: - Document Mapping Extensions

private extension LeaderboardService {
    
    func mapDocumentToLeaderboard(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> Leaderboard {
        // Simplified mapping - in real implementation, this would properly parse the document
        return Leaderboard(
            id: document.id,
            courseId: document.data["course_id"]?.value as? String ?? "",
            name: document.data["name"]?.value as? String ?? "",
            description: document.data["description"]?.value as? String,
            type: LeaderboardType(rawValue: document.data["type"]?.value as? String ?? "daily") ?? .daily,
            period: LeaderboardPeriod(rawValue: document.data["period"]?.value as? String ?? "daily") ?? .daily,
            maxEntries: document.data["max_entries"]?.value as? Int ?? 100,
            isActive: document.data["is_active"]?.value as? Bool ?? true,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            expiresAt: nil,
            entryFee: document.data["entry_fee"]?.value as? Double,
            prizePool: document.data["prize_pool"]?.value as? Double,
            sponsorInfo: nil
        )
    }
    
    func mapLeaderboardToDocument(_ leaderboard: Leaderboard) throws -> [String: Any] {
        var data: [String: Any] = [
            "course_id": leaderboard.courseId,
            "name": leaderboard.name,
            "type": leaderboard.type.rawValue,
            "period": leaderboard.period.rawValue,
            "max_entries": leaderboard.maxEntries,
            "is_active": leaderboard.isActive
        ]
        
        if let description = leaderboard.description {
            data["description"] = description
        }
        
        if let entryFee = leaderboard.entryFee {
            data["entry_fee"] = entryFee
        }
        
        if let prizePool = leaderboard.prizePool {
            data["prize_pool"] = prizePool
        }
        
        return data
    }
    
    func mapDocumentToLeaderboardEntry(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> LeaderboardEntry {
        // Simplified mapping
        return LeaderboardEntry(
            id: document.id,
            leaderboardId: document.data["leaderboard_id"]?.value as? String ?? "",
            playerId: document.data["player_id"]?.value as? String ?? "",
            playerName: document.data["player_name"]?.value as? String ?? "",
            playerAvatarUrl: document.data["player_avatar_url"]?.value as? String,
            score: document.data["score"]?.value as? Int ?? 0,
            handicap: document.data["handicap"]?.value as? Double,
            courseHandicap: document.data["course_handicap"]?.value as? Int,
            roundDate: Date(),
            roundId: document.data["round_id"]?.value as? String,
            holesPlayed: document.data["holes_played"]?.value as? Int ?? 18,
            strokesGained: document.data["strokes_gained"]?.value as? Double,
            fairwaysHit: document.data["fairways_hit"]?.value as? Int,
            greensInRegulation: document.data["gir"]?.value as? Int,
            scoreToPar: document.data["score_to_par"]?.value as? Int ?? 0,
            netScore: document.data["net_score"]?.value as? Int,
            bestHole: nil,
            achievements: [],
            updatedAt: document.updatedAt,
            isLive: document.data["is_live"]?.value as? Bool ?? false
        )
    }
    
    func mapLeaderboardEntryToDocument(_ entry: LeaderboardEntry) throws -> [String: Any] {
        return [
            "leaderboard_id": entry.leaderboardId,
            "player_id": entry.playerId,
            "player_name": entry.playerName,
            "score": entry.score,
            "score_to_par": entry.scoreToPar,
            "holes_played": entry.holesPlayed,
            "position": entry.position,
            "is_live": entry.isLive
        ]
    }
}

// MARK: - Leaderboard Cache

private class LeaderboardCache {
    private var leaderboards: [String: Leaderboard] = [:]
    private var courseLeaderboards: [String: [Leaderboard]] = [:]
    private let cacheQueue = DispatchQueue(label: "leaderboard.cache", attributes: .concurrent)
    
    func getLeaderboard(id: String) -> Leaderboard? {
        return cacheQueue.sync { leaderboards[id] }
    }
    
    func setLeaderboard(_ leaderboard: Leaderboard) {
        cacheQueue.async(flags: .barrier) {
            self.leaderboards[leaderboard.id] = leaderboard
        }
    }
    
    func getLeaderboards(for courseId: String) -> [Leaderboard]? {
        return cacheQueue.sync { courseLeaderboards[courseId] }
    }
    
    func setLeaderboards(_ leaderboards: [Leaderboard], for courseId: String) {
        cacheQueue.async(flags: .barrier) {
            self.courseLeaderboards[courseId] = leaderboards
            leaderboards.forEach { self.leaderboards[$0.id] = $0 }
        }
    }
    
    func removeLeaderboard(id: String) {
        cacheQueue.async(flags: .barrier) {
            self.leaderboards.removeValue(forKey: id)
            
            // Remove from course cache as well
            for (courseId, leaderboards) in self.courseLeaderboards {
                let filtered = leaderboards.filter { $0.id != id }
                if filtered.count != leaderboards.count {
                    self.courseLeaderboards[courseId] = filtered
                }
            }
        }
    }
    
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.leaderboards.removeAll()
            self.courseLeaderboards.removeAll()
        }
    }
    
    func getCachedEntriesCount() -> Int {
        return cacheQueue.sync {
            leaderboards.values.reduce(0) { total, leaderboard in
                total + leaderboard.entries.count
            }
        }
    }
}