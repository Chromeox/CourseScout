import Foundation
import Combine
import SwiftUI

@MainActor
class LeaderboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var leaderboards: [Leaderboard] = []
    @Published var featuredLeaderboards: [Leaderboard] = []
    @Published var socialChallenges: [SocialChallenge] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isConnected = false
    @Published var filterType: LeaderboardType?
    
    // MARK: - Computed Properties
    
    var activeLeaderboards: [Leaderboard] {
        leaderboards.filter { $0.isActive && !$0.isExpired }
    }
    
    var filteredLeaderboards: [Leaderboard] {
        let active = activeLeaderboards
        
        if let filterType = filterType {
            return active.filter { $0.type == filterType }
        }
        
        return active
    }
    
    var totalPlayers: Int {
        activeLeaderboards.reduce(0) { total, leaderboard in
            total + leaderboard.totalParticipants
        }
    }
    
    var todaysRounds: Int {
        // This would be calculated from actual data
        activeLeaderboards.reduce(0) { total, leaderboard in
            total + leaderboard.entries.filter { Calendar.current.isDateInToday($0.roundDate) }.count
        }
    }
    
    var liveRounds: Int {
        activeLeaderboards.reduce(0) { total, leaderboard in
            total + leaderboard.entries.filter { $0.isLive }.count
        }
    }
    
    // MARK: - Private Properties
    
    private let courseId: String
    private let leaderboardService: LeaderboardServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var realtimeSubscriptions = Set<AnyCancellable>()
    private let cache = LeaderboardViewModelCache()
    
    // Entry cache for performance
    private var entriesCache: [String: [LeaderboardEntry]] = [:]
    
    // MARK: - Initialization
    
    init(courseId: String, leaderboardService: LeaderboardServiceProtocol? = nil) {
        self.courseId = courseId
        self.leaderboardService = leaderboardService ?? ServiceContainer.shared.leaderboardService
        
        setupRealtimeSubscriptions()
    }
    
    deinit {
        leaderboardService.unsubscribeFromAll()
    }
    
    // MARK: - Public Methods
    
    func loadLeaderboards() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Load from cache first if available
            if let cached = cache.getCachedLeaderboards(for: courseId) {
                leaderboards = cached
                updateFeaturedLeaderboards()
            }
            
            // Load fresh data
            let freshLeaderboards = try await leaderboardService.getLeaderboards(for: courseId)
            leaderboards = freshLeaderboards
            
            // Cache the results
            cache.setCachedLeaderboards(freshLeaderboards, for: courseId)
            
            updateFeaturedLeaderboards()
            
            // Load entries for visible leaderboards
            await loadEntriesForVisibleLeaderboards()
            
            // Load social challenges
            await loadSocialChallenges()
            
        } catch {
            errorMessage = "Failed to load leaderboards: \(error.localizedDescription)"
            print("❌ Failed to load leaderboards: \(error)")
        }
        
        isLoading = false
    }
    
    func refreshAll() async {
        cache.clearCache()
        entriesCache.removeAll()
        await loadLeaderboards()
    }
    
    func createLeaderboard(_ leaderboard: Leaderboard) async {
        do {
            let createdLeaderboard = try await leaderboardService.createLeaderboard(leaderboard)
            leaderboards.append(createdLeaderboard)
            updateFeaturedLeaderboards()
            cache.clearCache() // Clear cache to force refresh
        } catch {
            errorMessage = "Failed to create leaderboard: \(error.localizedDescription)"
            print("❌ Failed to create leaderboard: \(error)")
        }
    }
    
    func joinLeaderboard(_ leaderboard: Leaderboard, with entry: LeaderboardEntry) async {
        do {
            let submittedEntry = try await leaderboardService.submitEntry(entry)
            
            // Update local state
            if let index = leaderboards.firstIndex(where: { $0.id == leaderboard.id }) {
                leaderboards[index].entries.append(submittedEntry)
                
                // Update entries cache
                var entries = entriesCache[leaderboard.id] ?? []
                entries.append(submittedEntry)
                entriesCache[leaderboard.id] = entries.sorted { $0.position < $1.position }
            }
            
        } catch {
            errorMessage = "Failed to join leaderboard: \(error.localizedDescription)"
            print("❌ Failed to join leaderboard: \(error)")
        }
    }
    
    func getTopEntries(for leaderboardId: String) -> [LeaderboardEntry] {
        if let cached = entriesCache[leaderboardId] {
            return Array(cached.prefix(5))
        }
        
        // Get from leaderboard entries if available
        if let leaderboard = leaderboards.first(where: { $0.id == leaderboardId }) {
            let topEntries = Array(leaderboard.entries.prefix(5))
            entriesCache[leaderboardId] = leaderboard.entries
            return topEntries
        }
        
        return []
    }
    
    func searchLeaderboards(query: String) async {
        guard !query.isEmpty else {
            await loadLeaderboards()
            return
        }
        
        do {
            let searchResults = try await leaderboardService.searchLeaderboards(
                query: query,
                courseId: courseId
            )
            leaderboards = searchResults
            updateFeaturedLeaderboards()
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }
    
    func filterLeaderboards(by type: LeaderboardType?) {
        filterType = type
    }
    
    func getLeaderboardStats(for leaderboardId: String) async -> LeaderboardStats? {
        do {
            return try await leaderboardService.getLeaderboardStats(for: leaderboardId)
        } catch {
            print("❌ Failed to get stats for leaderboard \(leaderboardId): \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func setupRealtimeSubscriptions() {
        // Subscribe to leaderboards updates for this course
        leaderboardService.subscribeToLeaderboards(courseId: courseId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Real-time connection failed: \(error.localizedDescription)"
                        self?.isConnected = false
                    }
                },
                receiveValue: { [weak self] updatedLeaderboards in
                    self?.handleLeaderboardsUpdate(updatedLeaderboards)
                    self?.isConnected = true
                }
            )
            .store(in: &realtimeSubscriptions)
        
        // Subscribe to individual leaderboard updates
        for leaderboard in leaderboards {
            subscribeToLeaderboardUpdates(leaderboard.id)
        }
    }
    
    private func subscribeToLeaderboardUpdates(_ leaderboardId: String) {
        leaderboardService.subscribeToLeaderboard(leaderboardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("❌ Leaderboard subscription error: \(error)")
                    }
                },
                receiveValue: { [weak self] update in
                    self?.handleLeaderboardUpdate(update)
                }
            )
            .store(in: &realtimeSubscriptions)
    }
    
    private func handleLeaderboardsUpdate(_ updatedLeaderboards: [Leaderboard]) {
        leaderboards = updatedLeaderboards
        updateFeaturedLeaderboards()
        
        // Subscribe to new leaderboards
        for leaderboard in updatedLeaderboards {
            if !realtimeSubscriptions.contains(where: { _ in true }) { // Simplified check
                subscribeToLeaderboardUpdates(leaderboard.id)
            }
        }
    }
    
    private func handleLeaderboardUpdate(_ update: LeaderboardUpdate) {
        switch update.type {
        case .entryAdded, .entryUpdated:
            if let entry = update.entry {
                updateEntryInCache(entry, for: update.leaderboardId)
            }
            
        case .entryRemoved:
            removeEntryFromCache(for: update.leaderboardId, playerId: update.entry?.playerId)
            
        case .positionsChanged:
            // Reload entries for this leaderboard
            Task {
                await loadEntries(for: update.leaderboardId)
            }
            
        case .leaderboardUpdated:
            // Refresh the specific leaderboard
            Task {
                await refreshLeaderboard(update.leaderboardId)
            }
        }
    }
    
    private func updateEntryInCache(_ entry: LeaderboardEntry, for leaderboardId: String) {
        var entries = entriesCache[leaderboardId] ?? []
        
        if let existingIndex = entries.firstIndex(where: { $0.playerId == entry.playerId }) {
            entries[existingIndex] = entry
        } else {
            entries.append(entry)
        }
        
        entriesCache[leaderboardId] = entries.sorted { $0.position < $1.position }
        
        // Update leaderboard entries as well
        if let leaderboardIndex = leaderboards.firstIndex(where: { $0.id == leaderboardId }) {
            leaderboards[leaderboardIndex].entries = entries
        }
    }
    
    private func removeEntryFromCache(for leaderboardId: String, playerId: String?) {
        guard let playerId = playerId else { return }
        
        var entries = entriesCache[leaderboardId] ?? []
        entries.removeAll { $0.playerId == playerId }
        entriesCache[leaderboardId] = entries
        
        // Update leaderboard entries
        if let leaderboardIndex = leaderboards.firstIndex(where: { $0.id == leaderboardId }) {
            leaderboards[leaderboardIndex].entries = entries
        }
    }
    
    private func updateFeaturedLeaderboards() {
        featuredLeaderboards = leaderboards
            .filter { $0.isActive && !$0.isExpired }
            .filter { $0.type == .tournament || $0.prizePool != nil || $0.isFeatured }
            .sorted { leaderboard1, leaderboard2 in
                // Prioritize by prize pool, then by participants
                if let prize1 = leaderboard1.prizePool, let prize2 = leaderboard2.prizePool {
                    return prize1 > prize2
                }
                if leaderboard1.prizePool != nil { return true }
                if leaderboard2.prizePool != nil { return false }
                return leaderboard1.totalParticipants > leaderboard2.totalParticipants
            }
            .prefix(5)
            .map { $0 }
    }
    
    private func loadEntriesForVisibleLeaderboards() async {
        let visibleLeaderboards = Array(leaderboards.prefix(10)) // Load entries for first 10 leaderboards
        
        await withTaskGroup(of: Void.self) { group in
            for leaderboard in visibleLeaderboards {
                group.addTask {
                    await self.loadEntries(for: leaderboard.id)
                }
            }
        }
    }
    
    private func loadEntries(for leaderboardId: String) async {
        do {
            let entries = try await leaderboardService.getEntries(
                for: leaderboardId,
                limit: 20,
                offset: nil
            )
            
            await MainActor.run {
                self.entriesCache[leaderboardId] = entries
                
                // Update the leaderboard's entries
                if let index = self.leaderboards.firstIndex(where: { $0.id == leaderboardId }) {
                    self.leaderboards[index].entries = entries
                }
            }
        } catch {
            print("❌ Failed to load entries for leaderboard \(leaderboardId): \(error)")
        }
    }
    
    private func refreshLeaderboard(_ leaderboardId: String) async {
        do {
            let refreshedLeaderboard = try await leaderboardService.getLeaderboard(id: leaderboardId)
            
            if let index = leaderboards.firstIndex(where: { $0.id == leaderboardId }) {
                leaderboards[index] = refreshedLeaderboard
                entriesCache[leaderboardId] = refreshedLeaderboard.entries
            }
        } catch {
            print("❌ Failed to refresh leaderboard \(leaderboardId): \(error)")
        }
    }
    
    private func loadSocialChallenges() async {
        do {
            socialChallenges = try await leaderboardService.getPublicChallenges(courseId: courseId)
        } catch {
            print("❌ Failed to load social challenges: \(error)")
        }
    }
}

// MARK: - Cache Helper

private class LeaderboardViewModelCache {
    private var leaderboardsCache: [String: [Leaderboard]] = [:]
    private let cacheQueue = DispatchQueue(label: "leaderboard.viewmodel.cache", attributes: .concurrent)
    private let cacheExpiry: TimeInterval = 300 // 5 minutes
    private var cacheTimestamps: [String: Date] = [:]
    
    func getCachedLeaderboards(for courseId: String) -> [Leaderboard]? {
        return cacheQueue.sync {
            guard let timestamp = cacheTimestamps[courseId],
                  Date().timeIntervalSince(timestamp) < cacheExpiry else {
                return nil
            }
            return leaderboardsCache[courseId]
        }
    }
    
    func setCachedLeaderboards(_ leaderboards: [Leaderboard], for courseId: String) {
        cacheQueue.async(flags: .barrier) {
            self.leaderboardsCache[courseId] = leaderboards
            self.cacheTimestamps[courseId] = Date()
        }
    }
    
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.leaderboardsCache.removeAll()
            self.cacheTimestamps.removeAll()
        }
    }
}

// MARK: - Mock Data for Development

extension LeaderboardViewModel {
    static func createSampleLeaderboards() -> [Leaderboard] {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        
        return [
            Leaderboard(
                id: "weekend-championship",
                courseId: "pebble-beach",
                name: "Weekend Championship",
                description: "Compete against the best players this weekend",
                type: .tournament,
                period: .weekly,
                maxEntries: 100,
                isActive: true,
                createdAt: now,
                updatedAt: now,
                expiresAt: tomorrow,
                entryFee: 25.0,
                prizePool: 1000.0,
                sponsorInfo: nil
            ),
            Leaderboard(
                id: "daily-low-score",
                courseId: "pebble-beach",
                name: "Daily Low Score",
                description: "Best score of the day wins",
                type: .daily,
                period: .daily,
                maxEntries: 50,
                isActive: true,
                createdAt: now,
                updatedAt: now,
                expiresAt: Calendar.current.date(byAdding: .hour, value: 6, to: now),
                entryFee: nil,
                prizePool: nil,
                sponsorInfo: nil
            )
        ]
    }
}