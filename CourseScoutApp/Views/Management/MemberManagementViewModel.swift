import Foundation
import Combine
import SwiftUI

// MARK: - Member Management ViewModel

@MainActor
class MemberManagementViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var allMembers: [Member] = []
    @Published var filteredMembers: [Member] = []
    @Published var memberSegments: [MemberSegment] = []
    @Published var memberGrowthData: [MemberGrowthDataPoint] = []
    @Published var recentActivities: [MemberActivity] = []
    
    // MARK: - Stats Properties
    @Published var totalMembersCount = 0
    @Published var activeMembersCount = 0
    @Published var newMembersThisMonth = 0
    @Published var retentionRate: Double = 0
    @Published var averageVisitsPerMonth: Double = 0
    @Published var averageSpending: Double = 0
    @Published var memberSatisfactionScore: Double = 0
    
    // MARK: - Trend Properties
    @Published var memberGrowthTrend: TrendDirection? = nil
    @Published var activityTrend: TrendDirection? = nil
    @Published var acquisitionTrend: TrendDirection? = nil
    @Published var retentionTrend: TrendDirection? = nil
    
    // MARK: - Loading States
    @Published var isLoading = false
    @Published var isRefreshing = false
    
    // MARK: - Private Properties
    private var userService: UserProfileServiceProtocol?
    private var analyticsService: B2BAnalyticsServiceProtocol?
    private var currentTenantId: String?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Real-time Updates
    private var realTimeTimer: Timer?
    private let realTimeUpdateInterval: TimeInterval = 60.0 // 1 minute
    
    // MARK: - Configuration
    
    func configure(for tenantId: String) {
        currentTenantId = tenantId
        userService = ServiceContainer.shared.resolve(UserProfileServiceProtocol.self)
        analyticsService = ServiceContainer.shared.resolve(B2BAnalyticsServiceProtocol.self)
        
        setupRealTimeUpdates()
        setupAnalyticsSubscriptions()
    }
    
    deinit {
        stopRealTimeUpdates()
    }
    
    // MARK: - Data Loading
    
    func loadMemberData(tenantId: String) async {
        guard !isLoading else { return }
        
        isLoading = true
        currentTenantId = tenantId
        
        do {
            async let membersTask = loadMembers(tenantId: tenantId)
            async let analyticsTask = loadMemberAnalytics(tenantId: tenantId)
            async let activitiesTask = loadRecentActivities(tenantId: tenantId)
            async let segmentsTask = loadMemberSegments(tenantId: tenantId)
            async let growthTask = loadMemberGrowthData(tenantId: tenantId)
            
            let (members, analytics, activities, segments, growthData) = try await (
                membersTask,
                analyticsTask,
                activitiesTask,
                segmentsTask,
                growthTask
            )
            
            allMembers = members
            filteredMembers = members
            recentActivities = activities
            memberSegments = segments
            memberGrowthData = growthData
            
            updateMemberStats(members: members, analytics: analytics)
            calculateTrends(analytics: analytics)
            
        } catch {
            handleError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Private Data Loading Methods
    
    private func loadMembers(tenantId: String) async throws -> [Member] {
        guard let userService = userService else {
            throw MemberManagementError.serviceNotAvailable
        }
        
        // In a real implementation, this would call the actual service
        return try await generateMockMembers(tenantId: tenantId)
    }
    
    private func loadMemberAnalytics(tenantId: String) async throws -> PlayerBehaviorMetrics {
        guard let analyticsService = analyticsService else {
            throw MemberManagementError.serviceNotAvailable
        }
        
        return try await analyticsService.loadPlayerBehaviorMetrics(for: tenantId, period: .month)
    }
    
    private func loadRecentActivities(tenantId: String) async throws -> [MemberActivity] {
        // Generate mock activities - in real implementation would fetch from analytics service
        return generateMockActivities()
    }
    
    private func loadMemberSegments(tenantId: String) async throws -> [MemberSegment] {
        guard let analyticsService = analyticsService else {
            throw MemberManagementError.serviceNotAvailable
        }
        
        let userSegments = try await analyticsService.getUserSegmentAnalysis(for: tenantId)
        
        return userSegments.map { segment in
            MemberSegment(
                name: segment.name,
                description: "Members with \(segment.characteristics.values.joined(separator: ", "))",
                memberCount: Double(segment.userCount),
                color: generateSegmentColor(for: segment.name),
                averageRevenue: segment.averageRevenue,
                growthTrend: segment.growthTrend
            )
        }
    }
    
    private func loadMemberGrowthData(tenantId: String) async throws -> [MemberGrowthDataPoint] {
        let calendar = Calendar.current
        let currentDate = Date()
        
        // Generate 12 months of growth data
        return (0..<12).compactMap { monthOffset in
            guard let date = calendar.date(byAdding: .month, value: -monthOffset, to: currentDate) else {
                return nil
            }
            
            // Simulate growth pattern
            let baseGrowth = 15
            let seasonalVariation = sin(Double(monthOffset) * .pi / 6) * 5
            let newMembers = Int(Double(baseGrowth) + seasonalVariation + Double.random(in: -3...3))
            
            return MemberGrowthDataPoint(
                month: date,
                newMembers: max(0, newMembers)
            )
        }.reversed()
    }
    
    // MARK: - Member Operations
    
    func addMember(_ member: Member) async {
        // Optimistic update
        allMembers.append(member)
        updateFilteredMembers()
        updateMemberCount()
        
        do {
            guard let userService = userService,
                  let tenantId = currentTenantId else { return }
            
            // In real implementation, would persist to backend
            let persistedMember = try await createMemberInBackend(member, tenantId: tenantId)
            
            // Update with persisted version
            if let index = allMembers.firstIndex(where: { $0.id == member.id }) {
                allMembers[index] = persistedMember
            }
            
        } catch {
            // Revert optimistic update on failure
            allMembers.removeAll { $0.id == member.id }
            updateFilteredMembers()
            updateMemberCount()
            handleError(error)
        }
    }
    
    func updateMember(_ member: Member) async {
        // Optimistic update
        if let index = allMembers.firstIndex(where: { $0.id == member.id }) {
            allMembers[index] = member
            updateFilteredMembers()
        }
        
        do {
            guard let userService = userService,
                  let tenantId = currentTenantId else { return }
            
            let updatedMember = try await updateMemberInBackend(member, tenantId: tenantId)
            
            // Update with backend version
            if let index = allMembers.firstIndex(where: { $0.id == member.id }) {
                allMembers[index] = updatedMember
                updateFilteredMembers()
            }
            
        } catch {
            // Could implement revert logic here
            handleError(error)
        }
    }
    
    func deleteMember(id: String) async {
        // Optimistic update
        let deletedMember = allMembers.first { $0.id == id }
        allMembers.removeAll { $0.id == id }
        updateFilteredMembers()
        updateMemberCount()
        
        do {
            guard let userService = userService,
                  let tenantId = currentTenantId else { return }
            
            try await deleteMemberInBackend(id: id, tenantId: tenantId)
            
        } catch {
            // Revert optimistic update on failure
            if let member = deletedMember {
                allMembers.append(member)
                updateFilteredMembers()
                updateMemberCount()
            }
            handleError(error)
        }
    }
    
    // MARK: - Filtering and Sorting
    
    func filterMembers(
        searchText: String,
        options: MemberFilterOptions,
        sortOption: MemberSortOption,
        ascending: Bool
    ) {
        var filtered = allMembers
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { member in
                member.name.localizedCaseInsensitiveContains(searchText) ||
                member.email.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply membership type filter
        if !options.membershipTypes.isEmpty {
            filtered = filtered.filter { member in
                options.membershipTypes.contains(member.membershipType)
            }
        }
        
        // Apply activity status filter
        if !options.activityStatus.isEmpty {
            filtered = filtered.filter { member in
                options.activityStatus.contains(member.activityStatus)
            }
        }
        
        // Apply join date range filter
        if let dateRange = options.joinDateRange {
            filtered = filtered.filter { member in
                dateRange.contains(member.joinDate)
            }
        }
        
        // Apply revenue range filter
        if let revenueRange = options.revenueRange {
            filtered = filtered.filter { member in
                revenueRange.contains(member.totalRevenue)
            }
        }
        
        // Apply sorting
        filtered = sortMembers(filtered, by: sortOption, ascending: ascending)
        
        filteredMembers = filtered
    }
    
    func clearFilters() {
        filteredMembers = allMembers.sorted { $0.name < $1.name }
    }
    
    private func sortMembers(_ members: [Member], by option: MemberSortOption, ascending: Bool) -> [Member] {
        let sorted = members.sorted { member1, member2 in
            switch option {
            case .name:
                return member1.name < member2.name
            case .joinDate:
                return member1.joinDate < member2.joinDate
            case .lastVisit:
                return member1.lastVisit < member2.lastVisit
            case .revenue:
                return member1.totalRevenue < member2.totalRevenue
            case .visits:
                return member1.totalVisits < member2.totalVisits
            }
        }
        
        return ascending ? sorted : sorted.reversed()
    }
    
    private func updateFilteredMembers() {
        filteredMembers = allMembers.sorted { $0.name < $1.name }
    }
    
    // MARK: - Stats Calculations
    
    private func updateMemberStats(members: [Member], analytics: PlayerBehaviorMetrics) {
        totalMembersCount = members.count
        activeMembersCount = members.filter { $0.activityStatus == .active }.count
        
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())
        
        newMembersThisMonth = members.filter { member in
            let joinMonth = calendar.component(.month, from: member.joinDate)
            let joinYear = calendar.component(.year, from: member.joinDate)
            return joinMonth == currentMonth && joinYear == currentYear
        }.count
        
        retentionRate = analytics.retentionRate
        averageVisitsPerMonth = calculateAverageVisitsPerMonth(members: members)
        averageSpending = members.isEmpty ? 0 : members.reduce(0) { $0 + $1.totalRevenue } / Double(members.count)
        memberSatisfactionScore = analytics.averageRating
    }
    
    private func calculateAverageVisitsPerMonth(members: [Member]) -> Double {
        guard !members.isEmpty else { return 0 }
        
        let totalVisits = members.reduce(0) { $0 + $1.totalVisits }
        let avgMembershipMonths = members.reduce(0.0) { total, member in
            let monthsSinceJoin = Calendar.current.dateComponents([.month], from: member.joinDate, to: Date()).month ?? 1
            return total + Double(max(1, monthsSinceJoin))
        } / Double(members.count)
        
        return Double(totalVisits) / avgMembershipMonths
    }
    
    private func calculateTrends(analytics: PlayerBehaviorMetrics) {
        // Calculate trends based on analytics data
        let memberGrowth = calculateMemberGrowthTrend()
        memberGrowthTrend = memberGrowth
        
        // Mock trend calculations - in real implementation would use historical data
        activityTrend = .up(8.5)
        acquisitionTrend = newMembersThisMonth > 15 ? .up(12.3) : .down(5.2)
        retentionTrend = retentionRate > 0.8 ? .up(3.1) : .down(2.4)
    }
    
    private func calculateMemberGrowthTrend() -> TrendDirection {
        guard memberGrowthData.count >= 2 else { return .neutral }
        
        let recent = memberGrowthData.suffix(2)
        let current = recent.last?.newMembers ?? 0
        let previous = recent.first?.newMembers ?? 1
        
        let change = Double(current - previous) / Double(max(previous, 1)) * 100
        
        if abs(change) < 1.0 {
            return .neutral
        } else if change > 0 {
            return .up(change)
        } else {
            return .down(abs(change))
        }
    }
    
    private func updateMemberCount() {
        totalMembersCount = allMembers.count
        activeMembersCount = allMembers.filter { $0.activityStatus == .active }.count
    }
    
    // MARK: - Real-time Updates
    
    private func setupRealTimeUpdates() {
        realTimeTimer = Timer.scheduledTimer(withTimeInterval: realTimeUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshRealTimeData()
            }
        }
    }
    
    private func stopRealTimeUpdates() {
        realTimeTimer?.invalidate()
        realTimeTimer = nil
    }
    
    private func refreshRealTimeData() async {
        guard let tenantId = currentTenantId else { return }
        
        // Refresh activities in background
        do {
            let activities = try await loadRecentActivities(tenantId: tenantId)
            recentActivities = activities
        } catch {
            print("Failed to refresh member activities: \(error)")
        }
    }
    
    // MARK: - Analytics Subscriptions
    
    private func setupAnalyticsSubscriptions() {
        guard let analyticsService = analyticsService else { return }
        
        // Subscribe to behavior analytics updates
        analyticsService.behaviorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] behavior in
                if let behavior = behavior {
                    self?.updateAnalyticsData(behavior)
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateAnalyticsData(_ behavior: PlayerBehaviorMetrics) {
        retentionRate = behavior.retentionRate
        memberSatisfactionScore = behavior.averageRating
        
        // Update trends based on new data
        calculateTrends(analytics: behavior)
    }
    
    // MARK: - Refresh Methods
    
    func refreshMembers() async {
        guard let tenantId = currentTenantId else { return }
        isRefreshing = true
        
        do {
            let members = try await loadMembers(tenantId: tenantId)
            allMembers = members
            updateFilteredMembers()
            updateMemberCount()
        } catch {
            handleError(error)
        }
        
        isRefreshing = false
    }
    
    func refreshAnalytics() async {
        guard let tenantId = currentTenantId else { return }
        
        do {
            let analytics = try await loadMemberAnalytics(tenantId: tenantId)
            updateMemberStats(members: allMembers, analytics: analytics)
            calculateTrends(analytics: analytics)
        } catch {
            handleError(error)
        }
    }
    
    func refreshSegments() async {
        guard let tenantId = currentTenantId else { return }
        
        do {
            let segments = try await loadMemberSegments(tenantId: tenantId)
            memberSegments = segments
        } catch {
            handleError(error)
        }
    }
    
    // MARK: - Mock Data Generation
    
    private func generateMockMembers(tenantId: String) async throws -> [Member] {
        let names = ["Alice Johnson", "Bob Smith", "Carol Williams", "David Brown", "Eva Davis", "Frank Miller", "Grace Wilson", "Henry Moore", "Iris Taylor", "Jack Anderson"]
        let domains = ["gmail.com", "yahoo.com", "outlook.com", "company.com"]
        let membershipTypes = Member.MembershipType.allCases
        let activityStatus = Member.ActivityStatus.allCases
        
        return (0..<50).map { index in
            let name = names[index % names.count] + " \(index + 1)"
            let email = name.lowercased().replacingOccurrences(of: " ", with: ".") + "@" + domains[index % domains.count]
            let joinDate = Calendar.current.date(byAdding: .day, value: -Int.random(in: 30...730), to: Date()) ?? Date()
            let lastVisit = Calendar.current.date(byAdding: .day, value: -Int.random(in: 1...30), to: Date()) ?? Date()
            
            return Member(
                id: UUID().uuidString,
                name: name,
                email: email,
                profileImageURL: nil,
                membershipType: membershipTypes[index % membershipTypes.count],
                activityStatus: activityStatus[index % activityStatus.count],
                joinDate: joinDate,
                lastVisit: lastVisit,
                totalVisits: Int.random(in: 1...50),
                totalRevenue: Double.random(in: 100...5000),
                preferences: MemberPreferences()
            )
        }
    }
    
    private func generateMockActivities() -> [MemberActivity] {
        let activities = [
            ("New member registration", "person.badge.plus", Color.green),
            ("Member renewed membership", "arrow.triangle.2.circlepath", Color.blue),
            ("Member completed round", "figure.golf", Color.purple),
            ("Member left review", "star.fill", Color.orange),
            ("Member updated profile", "person.crop.circle", Color.gray),
            ("Member booked lesson", "calendar.badge.plus", Color.cyan)
        ]
        
        return activities.enumerated().map { index, activity in
            let timestamp = Calendar.current.date(byAdding: .minute, value: -(index * 30), to: Date()) ?? Date()
            
            return MemberActivity(
                description: activity.0,
                timestamp: timestamp,
                icon: activity.1,
                color: activity.2,
                memberName: "Member \(index + 1)"
            )
        }
    }
    
    private func generateSegmentColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .yellow]
        let hash = name.hash
        return colors[abs(hash) % colors.count]
    }
    
    // MARK: - Backend Integration (Mock)
    
    private func createMemberInBackend(_ member: Member, tenantId: String) async throws -> Member {
        // Mock backend call - add 100ms delay to simulate network
        try await Task.sleep(nanoseconds: 100_000_000)
        return member
    }
    
    private func updateMemberInBackend(_ member: Member, tenantId: String) async throws -> Member {
        // Mock backend call
        try await Task.sleep(nanoseconds: 100_000_000)
        return member
    }
    
    private func deleteMemberInBackend(id: String, tenantId: String) async throws {
        // Mock backend call
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error) {
        print("Member management error: \(error)")
        // In a real implementation, you would show user-friendly error messages
        // and implement retry logic
    }
    
    // MARK: - Export Functionality
    
    func exportMembers(format: ExportFormat) async -> URL? {
        // In a real implementation, this would generate export files
        return nil
    }
    
    func bulkUpdateMembers(_ memberIds: Set<String>, updates: MemberBulkUpdate) async {
        let membersToUpdate = allMembers.filter { memberIds.contains($0.id) }
        
        for member in membersToUpdate {
            var updatedMember = member
            
            if let newMembershipType = updates.membershipType {
                updatedMember.membershipType = newMembershipType
            }
            
            if let newActivityStatus = updates.activityStatus {
                updatedMember.activityStatus = newActivityStatus
            }
            
            await updateMember(updatedMember)
        }
    }
}

// MARK: - Supporting Data Structures

struct MemberGrowthDataPoint: Identifiable {
    let id = UUID()
    let month: Date
    let newMembers: Int
}

struct MemberActivity: Identifiable {
    let id = UUID()
    let description: String
    let timestamp: Date
    let icon: String
    let color: Color
    let memberName: String
}

struct MemberSegment: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let memberCount: Double
    let color: Color
    let averageRevenue: Double
    let growthTrend: Double
}

struct Member: Identifiable, Codable {
    let id: String
    var name: String
    var email: String
    var profileImageURL: String?
    var membershipType: MembershipType
    var activityStatus: ActivityStatus
    let joinDate: Date
    var lastVisit: Date
    var totalVisits: Int
    var totalRevenue: Double
    var preferences: MemberPreferences
}

struct MemberPreferences: Codable {
    var preferredTeeTime: String = "morning"
    var notificationsEnabled: Bool = true
    var emailUpdates: Bool = true
    var smsUpdates: Bool = false
}

struct MemberBulkUpdate {
    let membershipType: Member.MembershipType?
    let activityStatus: Member.ActivityStatus?
}

// MARK: - Error Types

enum MemberManagementError: LocalizedError {
    case serviceNotAvailable
    case invalidMemberId
    case memberNotFound
    case updateFailed(Error)
    case deleteFailed(Error)
    case dataLoadingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .serviceNotAvailable:
            return "Member service is not available"
        case .invalidMemberId:
            return "Invalid member ID"
        case .memberNotFound:
            return "Member not found"
        case .updateFailed(let error):
            return "Failed to update member: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete member: \(error.localizedDescription)"
        case .dataLoadingFailed(let error):
            return "Failed to load member data: \(error.localizedDescription)"
        }
    }
}