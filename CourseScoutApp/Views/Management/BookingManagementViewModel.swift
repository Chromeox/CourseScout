import Foundation
import Combine
import SwiftUI

// MARK: - Booking Management ViewModel

@MainActor
class BookingManagementViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var allBookings: [TeeTimeBooking] = []
    @Published var filteredBookings: [TeeTimeBooking] = []
    @Published var timeSlots: [TimeSlot] = []
    @Published var availableCourses: [GolfCourse] = []
    @Published var capacityData: [CapacityDataPoint] = []
    
    // MARK: - Real-time State
    @Published var isRealTimeConnected = false
    @Published var todaysBookingCount = 0
    @Published var courseUtilization: Double = 0
    @Published var todaysRevenue: Double = 0
    
    // MARK: - Drag and Drop State
    @Published var showingConflictAlert = false
    @Published var conflictMessage = ""
    private var pendingMove: (booking: TeeTimeBooking, slot: TimeSlot)?
    
    // MARK: - Loading States
    @Published var isLoading = false
    @Published var isRefreshing = false
    
    // MARK: - Private Properties
    private var bookingService: BookingServiceProtocol?
    private var golfCourseService: GolfCourseServiceProtocol?
    private var analyticsService: B2BAnalyticsServiceProtocol?
    private var currentTenantId: String?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Real-time Updates
    private var realTimeTimer: Timer?
    private let realTimeUpdateInterval: TimeInterval = 15.0
    
    // MARK: - Configuration
    
    func configure(for tenantId: String) {
        currentTenantId = tenantId
        bookingService = ServiceContainer.shared.resolve(BookingServiceProtocol.self)
        golfCourseService = ServiceContainer.shared.resolve(GolfCourseServiceProtocol.self)
        analyticsService = ServiceContainer.shared.resolve(B2BAnalyticsServiceProtocol.self)
        
        setupRealTimeUpdates()
        setupAnalyticsSubscriptions()
    }
    
    deinit {
        stopRealTimeUpdates()
    }
    
    // MARK: - Data Loading
    
    func loadBookings(tenantId: String, date: Date) async {
        guard !isLoading else { return }
        
        isLoading = true
        currentTenantId = tenantId
        
        do {
            async let bookingsTask = loadBookingsForDate(tenantId: tenantId, date: date)
            async let coursesTask = loadAvailableCourses(tenantId: tenantId)
            async let timeSlotsTask = generateTimeSlots(for: date)
            async let capacityTask = loadCapacityData(tenantId: tenantId, date: date)
            async let statsTask = loadDailyStats(tenantId: tenantId, date: date)
            
            let (bookings, courses, slots, capacity, stats) = try await (
                bookingsTask,
                coursesTask,
                timeSlotsTask,
                capacityTask,
                statsTask
            )
            
            allBookings = bookings
            filteredBookings = bookings
            availableCourses = courses
            timeSlots = slots
            capacityData = capacity
            
            updateDailyStats(stats)
            
        } catch {
            handleError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Private Data Loading Methods
    
    private func loadBookingsForDate(tenantId: String, date: Date) async throws -> [TeeTimeBooking] {
        guard let bookingService = bookingService else {
            throw BookingManagementError.serviceNotAvailable
        }
        
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        
        return try await bookingService.getBookings(
            startDate: startOfDay,
            endDate: endOfDay,
            tenantId: tenantId
        )
    }
    
    private func loadAvailableCourses(tenantId: String) async throws -> [GolfCourse] {
        guard let golfCourseService = golfCourseService else {
            throw BookingManagementError.serviceNotAvailable
        }
        
        return try await golfCourseService.getCourses(tenantId: tenantId)
    }
    
    private func generateTimeSlots(for date: Date) async -> [TimeSlot] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        var slots: [TimeSlot] = []
        
        // Generate slots from 6:00 AM to 6:00 PM (12 hours * 4 slots per hour)
        for hour in 6..<18 {
            for minute in stride(from: 0, to: 60, by: 15) {
                if let slotTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfDay) {
                    let slot = TimeSlot(
                        time: slotTime,
                        isAvailable: true,
                        capacity: 4 // 4 players per slot
                    )
                    slots.append(slot)
                }
            }
        }
        
        return slots
    }
    
    private func loadCapacityData(tenantId: String, date: Date) async throws -> [CapacityDataPoint] {
        // Generate capacity data based on bookings and time slots
        let hourlyCapacity = timeSlots.reduce(into: [Int: (booked: Int, total: Int)]()) { result, slot in
            let hour = Calendar.current.component(.hour, from: slot.time)
            let bookingsInSlot = allBookings.filter { booking in
                Calendar.current.component(.hour, from: booking.teeTime) == hour
            }.count
            
            if result[hour] == nil {
                result[hour] = (booked: 0, total: 0)
            }
            result[hour]?.booked += bookingsInSlot
            result[hour]?.total += slot.capacity
        }
        
        return hourlyCapacity.map { hour, data in
            CapacityDataPoint(
                hour: hour,
                bookedSlots: data.booked,
                totalSlots: data.total,
                utilizationRate: data.total > 0 ? Double(data.booked) / Double(data.total) : 0
            )
        }.sorted { $0.hour < $1.hour }
    }
    
    private func loadDailyStats(tenantId: String, date: Date) async throws -> DailyBookingStats {
        guard let analyticsService = analyticsService else {
            throw BookingManagementError.serviceNotAvailable
        }
        
        let realtimeStats = try await analyticsService.getRealTimeStats(for: tenantId)
        
        return DailyBookingStats(
            totalBookings: realtimeStats.currentBookings,
            totalRevenue: realtimeStats.todayRevenue,
            utilizationRate: realtimeStats.conversionRate
        )
    }
    
    // MARK: - Booking Operations
    
    func addBooking(_ booking: TeeTimeBooking) async {
        // Add booking to local state optimistically
        allBookings.append(booking)
        updateFilteredBookings()
        
        do {
            // Persist to backend
            guard let bookingService = bookingService,
                  let tenantId = currentTenantId else { return }
            
            let persistedBooking = try await bookingService.createBooking(booking, tenantId: tenantId)
            
            // Update local state with persisted version
            if let index = allBookings.firstIndex(where: { $0.id == booking.id }) {
                allBookings[index] = persistedBooking
            }
            
            updateDailyStatsFromBookings()
            
        } catch {
            // Revert optimistic update on failure
            allBookings.removeAll { $0.id == booking.id }
            updateFilteredBookings()
            handleError(error)
        }
    }
    
    func moveBooking(booking: TeeTimeBooking, toSlot: TimeSlot) async {
        // Check for conflicts
        let conflictingBookings = bookingsForSlot(toSlot)
        
        if conflictingBookings.count >= toSlot.capacity {
            pendingMove = (booking: booking, slot: toSlot)
            conflictMessage = "Time slot is at capacity (\(conflictingBookings.count)/\(toSlot.capacity)). Override?"
            showingConflictAlert = true
            return
        }
        
        await performBookingMove(booking: booking, toSlot: toSlot)
    }
    
    func resolveConflict() async {
        guard let pendingMove = pendingMove else { return }
        await performBookingMove(booking: pendingMove.booking, toSlot: pendingMove.slot)
        self.pendingMove = nil
        showingConflictAlert = false
    }
    
    func cancelDragOperation() {
        pendingMove = nil
        showingConflictAlert = false
    }
    
    private func performBookingMove(booking: TeeTimeBooking, toSlot: TimeSlot) async {
        // Create updated booking with new time
        var updatedBooking = booking
        updatedBooking.teeTime = toSlot.time
        
        // Optimistic update
        if let index = allBookings.firstIndex(where: { $0.id == booking.id }) {
            allBookings[index] = updatedBooking
            updateFilteredBookings()
        }
        
        do {
            guard let bookingService = bookingService,
                  let tenantId = currentTenantId else { return }
            
            let persistedBooking = try await bookingService.updateBooking(updatedBooking, tenantId: tenantId)
            
            // Update with persisted version
            if let index = allBookings.firstIndex(where: { $0.id == booking.id }) {
                allBookings[index] = persistedBooking
            }
            
        } catch {
            // Revert optimistic update on failure
            if let index = allBookings.firstIndex(where: { $0.id == booking.id }) {
                allBookings[index] = booking // Revert to original
                updateFilteredBookings()
            }
            handleError(error)
        }
    }
    
    // MARK: - Filtering and Search
    
    func filterBookings(searchText: String, options: BookingFilterOptions) {
        var filtered = allBookings
        
        // Apply search text filter
        if !searchText.isEmpty {
            filtered = filtered.filter { booking in
                booking.playerName.localizedCaseInsensitiveContains(searchText) ||
                booking.notes.localizedCaseInsensitiveContains(searchText) ||
                (booking.course?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Apply status filter
        if !options.status.isEmpty {
            filtered = filtered.filter { booking in
                options.status.contains(booking.status)
            }
        }
        
        // Apply course filter
        if !options.courses.isEmpty {
            filtered = filtered.filter { booking in
                guard let courseId = booking.course?.id else { return false }
                return options.courses.contains(courseId)
            }
        }
        
        // Apply time range filter
        if let timeRange = options.timeRange {
            filtered = filtered.filter { booking in
                timeRange.contains(booking.teeTime)
            }
        }
        
        filteredBookings = filtered.sorted { $0.teeTime < $1.teeTime }
    }
    
    func clearFilters() {
        filteredBookings = allBookings.sorted { $0.teeTime < $1.teeTime }
    }
    
    private func updateFilteredBookings() {
        filteredBookings = allBookings.sorted { $0.teeTime < $1.teeTime }
    }
    
    // MARK: - Utility Methods
    
    func bookingsForSlot(_ timeSlot: TimeSlot) -> [TeeTimeBooking] {
        let slotHour = Calendar.current.component(.hour, from: timeSlot.time)
        let slotMinute = Calendar.current.component(.minute, from: timeSlot.time)
        
        return allBookings.filter { booking in
            let bookingHour = Calendar.current.component(.hour, from: booking.teeTime)
            let bookingMinute = Calendar.current.component(.minute, from: booking.teeTime)
            return bookingHour == slotHour && bookingMinute == slotMinute
        }
    }
    
    private func updateDailyStats(_ stats: DailyBookingStats) {
        todaysBookingCount = stats.totalBookings
        todaysRevenue = stats.totalRevenue
        courseUtilization = stats.utilizationRate
    }
    
    private func updateDailyStatsFromBookings() {
        todaysBookingCount = allBookings.count
        
        // Calculate revenue based on booking fees (simplified)
        todaysRevenue = allBookings.reduce(0) { total, booking in
            total + (booking.fee ?? 0)
        }
        
        // Calculate utilization
        let totalSlots = timeSlots.reduce(0) { $0 + $1.capacity }
        courseUtilization = totalSlots > 0 ? Double(allBookings.count) / Double(totalSlots) : 0
    }
    
    // MARK: - Real-time Updates
    
    private func setupRealTimeUpdates() {
        realTimeTimer = Timer.scheduledTimer(withTimeInterval: realTimeUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshRealTimeData()
            }
        }
        isRealTimeConnected = true
    }
    
    private func stopRealTimeUpdates() {
        realTimeTimer?.invalidate()
        realTimeTimer = nil
        isRealTimeConnected = false
    }
    
    private func refreshRealTimeData() async {
        guard let tenantId = currentTenantId else { return }
        
        do {
            let realtimeStats = try await analyticsService?.getRealTimeStats(for: tenantId)
            if let stats = realtimeStats {
                let dailyStats = DailyBookingStats(
                    totalBookings: stats.currentBookings,
                    totalRevenue: stats.todayRevenue,
                    utilizationRate: stats.conversionRate
                )
                updateDailyStats(dailyStats)
            }
        } catch {
            print("Real-time update failed: \(error)")
            // Don't show errors for background updates
        }
    }
    
    // MARK: - Analytics Subscriptions
    
    private func setupAnalyticsSubscriptions() {
        guard let analyticsService = analyticsService else { return }
        
        // Subscribe to real-time booking updates
        // In a real implementation, this would be a WebSocket or similar
        Timer.publish(every: realTimeUpdateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshRealTimeData()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error) {
        print("Booking management error: \(error)")
        // In a real implementation, you would show user-friendly error messages
        // and implement retry logic
    }
    
    // MARK: - Public Helper Methods
    
    func refresh() async {
        guard let tenantId = currentTenantId else { return }
        isRefreshing = true
        await loadBookings(tenantId: tenantId, date: Date())
        isRefreshing = false
    }
    
    func exportBookings(format: ExportFormat) async -> URL? {
        // In a real implementation, this would generate export files
        return nil
    }
    
    func bulkUpdateBookings(_ bookingIds: Set<String>, status: TeeTimeBooking.BookingStatus) async {
        let bookingsToUpdate = allBookings.filter { bookingIds.contains($0.id) }
        
        for booking in bookingsToUpdate {
            var updatedBooking = booking
            updatedBooking.status = status
            
            do {
                if let bookingService = bookingService,
                   let tenantId = currentTenantId {
                    _ = try await bookingService.updateBooking(updatedBooking, tenantId: tenantId)
                    
                    // Update local state
                    if let index = allBookings.firstIndex(where: { $0.id == booking.id }) {
                        allBookings[index] = updatedBooking
                    }
                }
            } catch {
                handleError(error)
            }
        }
        
        updateFilteredBookings()
        updateDailyStatsFromBookings()
    }
}

// MARK: - Supporting Data Structures

struct DailyBookingStats {
    let totalBookings: Int
    let totalRevenue: Double
    let utilizationRate: Double
}

struct CapacityDataPoint: Identifiable {
    let id = UUID()
    let hour: Int
    let bookedSlots: Int
    let totalSlots: Int
    let utilizationRate: Double
    
    var hourDisplay: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        
        return "\(hour):00"
    }
}

// MARK: - Error Types

enum BookingManagementError: LocalizedError {
    case serviceNotAvailable
    case invalidTenantId
    case bookingConflict
    case moveOperationFailed(Error)
    case dataLoadingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .serviceNotAvailable:
            return "Booking service is not available"
        case .invalidTenantId:
            return "Invalid tenant ID"
        case .bookingConflict:
            return "Booking time slot conflict detected"
        case .moveOperationFailed(let error):
            return "Failed to move booking: \(error.localizedDescription)"
        case .dataLoadingFailed(let error):
            return "Failed to load booking data: \(error.localizedDescription)"
        }
    }
}

// MARK: - Mock Data Extensions

extension TeeTimeBooking {
    enum BookingStatus: String, CaseIterable, Codable {
        case confirmed = "confirmed"
        case checkedIn = "checked_in"
        case onCourse = "on_course"
        case completed = "completed"
        case cancelled = "cancelled"
        case noShow = "no_show"
    }
    
    static func mockBooking(
        playerName: String = "John Doe",
        teeTime: Date = Date(),
        status: BookingStatus = .confirmed,
        course: GolfCourse? = nil
    ) -> TeeTimeBooking {
        return TeeTimeBooking(
            id: UUID().uuidString,
            playerName: playerName,
            teeTime: teeTime,
            status: status,
            course: course,
            notes: "",
            fee: 75.0,
            slotIndex: 0
        )
    }
}

// MARK: - Service Protocol Extensions (Placeholder)

// These would be defined in the actual service protocols
extension BookingServiceProtocol {
    func getBookings(startDate: Date, endDate: Date, tenantId: String) async throws -> [TeeTimeBooking] {
        // Mock implementation - replace with actual service call
        return []
    }
    
    func createBooking(_ booking: TeeTimeBooking, tenantId: String) async throws -> TeeTimeBooking {
        // Mock implementation - replace with actual service call
        return booking
    }
    
    func updateBooking(_ booking: TeeTimeBooking, tenantId: String) async throws -> TeeTimeBooking {
        // Mock implementation - replace with actual service call
        return booking
    }
}

extension GolfCourseServiceProtocol {
    func getCourses(tenantId: String) async throws -> [GolfCourse] {
        // Mock implementation - replace with actual service call
        return []
    }
}