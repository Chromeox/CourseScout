import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Booking Management View

struct BookingManagementView: View {
    
    // MARK: - Dependencies
    @TenantInjected private var tenantService: TenantConfigurationServiceProtocol
    @TenantInjected private var analyticsService: B2BAnalyticsServiceProtocol
    @ServiceInjected(BookingServiceProtocol.self) private var bookingService
    @ServiceInjected(HapticFeedbackServiceProtocol.self) private var hapticService
    
    // MARK: - State Management
    @StateObject private var viewModel = BookingManagementViewModel()
    @State private var selectedDate = Date()
    @State private var selectedView: BookingViewType = .schedule
    @State private var showingNewBookingSheet = false
    @State private var showingFilters = false
    @State private var showingBulkActions = false
    @State private var selectedBookings: Set<String> = []
    
    // MARK: - Search and Filter State
    @State private var searchText = ""
    @State private var filterOptions = BookingFilterOptions()
    
    // MARK: - Drag and Drop State
    @State private var draggedBooking: TeeTimeBooking?
    @State private var dropTargetSlot: TimeSlot?
    
    // MARK: - Current Tenant Context
    @State private var currentTenant: TenantConfiguration?
    private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // MARK: - Top Controls
                topControlsSection
                
                // MARK: - Date Picker and View Selector
                dateAndViewSection
                
                // MARK: - Search and Filter Bar
                searchAndFilterSection
                
                // MARK: - Main Content
                mainContentSection
                
                // MARK: - Bottom Action Bar
                if !selectedBookings.isEmpty {
                    bottomActionBar
                }
            }
            .navigationTitle("Booking Management")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Bulk Actions Toggle
                    Button {
                        showingBulkActions.toggle()
                        hapticService.selectionChanged()
                    } label: {
                        Image(systemName: showingBulkActions ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundColor(tenantTheme.primarySwiftUIColor)
                    }
                    
                    // Add New Booking
                    Button {
                        showingNewBookingSheet = true
                        hapticService.buttonPressed()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(tenantTheme.primarySwiftUIColor)
                    }
                }
            }
        }
        .onAppear {
            setupTenantContext()
            Task { await loadBookingData() }
        }
        .sheet(isPresented: $showingNewBookingSheet) {
            NewBookingSheet(
                selectedDate: selectedDate,
                onBookingCreated: { booking in
                    Task { await viewModel.addBooking(booking) }
                }
            )
        }
        .sheet(isPresented: $showingFilters) {
            BookingFiltersSheet(
                options: $filterOptions,
                onApply: {
                    Task { await applyFilters() }
                }
            )
        }
        .alert("Booking Conflict", isPresented: $viewModel.showingConflictAlert) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDragOperation()
            }
            Button("Override") {
                Task { await viewModel.resolveConflict() }
            }
        } message: {
            Text(viewModel.conflictMessage)
        }
    }
    
    // MARK: - Top Controls Section
    
    private var topControlsSection: some View {
        HStack {
            // Real-time Status Indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isRealTimeConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.5), value: viewModel.isRealTimeConnected)
                
                Text(viewModel.isRealTimeConnected ? "Live Updates" : "Offline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Stats Summary
            HStack(spacing: 16) {
                StatBadge(
                    title: "Today's Bookings",
                    value: "\(viewModel.todaysBookingCount)",
                    color: tenantTheme.primarySwiftUIColor
                )
                
                StatBadge(
                    title: "Utilization",
                    value: "\(Int(viewModel.courseUtilization * 100))%",
                    color: .blue
                )
                
                StatBadge(
                    title: "Revenue",
                    value: viewModel.todaysRevenue.formatted(.currency(code: "USD")),
                    color: .green
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
    
    // MARK: - Date and View Section
    
    private var dateAndViewSection: some View {
        VStack(spacing: 12) {
            // Date Navigation
            HStack {
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    Task { await loadBookingData() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(tenantTheme.primarySwiftUIColor)
                }
                
                Spacer()
                
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .onChange(of: selectedDate) { _, _ in
                    Task { await loadBookingData() }
                }
                
                Spacer()
                
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    Task { await loadBookingData() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(tenantTheme.primarySwiftUIColor)
                }
            }
            
            // View Type Selector
            Picker("View Type", selection: $selectedView) {
                ForEach(BookingViewType.allCases, id: \.self) { viewType in
                    Text(viewType.displayName).tag(viewType)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedView) { _, _ in
                hapticService.selectionChanged()
            }
        }
        .padding()
    }
    
    // MARK: - Search and Filter Section
    
    private var searchAndFilterSection: some View {
        HStack {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search bookings...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, _ in
                        viewModel.filterBookings(searchText: searchText, options: filterOptions)
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        viewModel.clearFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
            )
            
            // Filter Button
            Button {
                showingFilters = true
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    if filterOptions.hasActiveFilters {
                        Text("\(filterOptions.activeFilterCount)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Circle().fill(Color.red))
                            .foregroundColor(.white)
                    }
                }
                .foregroundColor(tenantTheme.primarySwiftUIColor)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Main Content Section
    
    private var mainContentSection: some View {
        ScrollView {
            switch selectedView {
            case .schedule:
                scheduleView
            case .list:
                listView
            case .timeline:
                timelineView
            case .capacity:
                capacityView
            }
        }
        .refreshable {
            await loadBookingData()
        }
    }
    
    // MARK: - Schedule View
    
    private var scheduleView: some View {
        LazyVStack(spacing: 0) {
            // Time Header
            scheduleTimeHeader
            
            // Booking Slots
            ForEach(viewModel.timeSlots, id: \.id) { timeSlot in
                ScheduleSlotRow(
                    timeSlot: timeSlot,
                    bookings: viewModel.bookingsForSlot(timeSlot),
                    isSelected: { bookingId in
                        selectedBookings.contains(bookingId)
                    },
                    onBookingTap: { booking in
                        handleBookingTap(booking)
                    },
                    onBookingDrag: { booking in
                        draggedBooking = booking
                        hapticService.impactFeedback(.medium)
                    },
                    onSlotDrop: { slot in
                        handleSlotDrop(slot)
                    },
                    showBulkSelection: showingBulkActions,
                    tenantTheme: tenantTheme
                )
                .background(
                    dropTargetSlot?.id == timeSlot.id ? 
                    tenantTheme.primarySwiftUIColor.opacity(0.1) : 
                    Color.clear
                )
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Schedule Time Header
    
    private var scheduleTimeHeader: some View {
        HStack {
            // Time Column Header
            Text("Time")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            // Course Headers
            ForEach(viewModel.availableCourses, id: \.id) { course in
                Text(course.name)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    // MARK: - List View
    
    private var listView: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.filteredBookings, id: \.id) { booking in
                BookingListCard(
                    booking: booking,
                    isSelected: selectedBookings.contains(booking.id),
                    showBulkSelection: showingBulkActions,
                    tenantTheme: tenantTheme,
                    onTap: { handleBookingTap(booking) },
                    onToggleSelection: {
                        toggleBookingSelection(booking.id)
                    }
                )
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Timeline View
    
    private var timelineView: some View {
        TimelineBookingView(
            bookings: viewModel.filteredBookings,
            selectedDate: selectedDate,
            tenantTheme: tenantTheme,
            onBookingTap: { booking in
                handleBookingTap(booking)
            }
        )
        .padding(.horizontal)
    }
    
    // MARK: - Capacity View
    
    private var capacityView: some View {
        CapacityOverviewView(
            capacityData: viewModel.capacityData,
            selectedDate: selectedDate,
            tenantTheme: tenantTheme
        )
        .padding(.horizontal)
    }
    
    // MARK: - Bottom Action Bar
    
    private var bottomActionBar: some View {
        HStack {
            Text("\(selectedBookings.count) selected")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 16) {
                // Reschedule Button
                Button {
                    // Handle bulk reschedule
                } label: {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                        Text("Reschedule")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(tenantTheme.primarySwiftUIColor)
                }
                
                // Cancel Button
                Button {
                    // Handle bulk cancel
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Cancel")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.red)
                }
                
                // Export Button
                Button {
                    // Handle export
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: -2)
        )
    }
    
    // MARK: - Helper Views
    
    private var tenantTheme: WhiteLabelTheme {
        currentTenant?.theme ?? .golfCourseDefault
    }
    
    // MARK: - Methods
    
    private func setupTenantContext() {
        tenantService.currentTenantPublisher
            .receive(on: DispatchQueue.main)
            .sink { tenant in
                currentTenant = tenant
                if let tenant = tenant {
                    viewModel.configure(for: tenant.id)
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadBookingData() async {
        guard let tenantId = currentTenant?.id else { return }
        await viewModel.loadBookings(tenantId: tenantId, date: selectedDate)
    }
    
    private func handleBookingTap(_ booking: TeeTimeBooking) {
        if showingBulkActions {
            toggleBookingSelection(booking.id)
        } else {
            // Navigate to booking detail
        }
    }
    
    private func toggleBookingSelection(_ bookingId: String) {
        if selectedBookings.contains(bookingId) {
            selectedBookings.remove(bookingId)
        } else {
            selectedBookings.insert(bookingId)
        }
        hapticService.selectionChanged()
    }
    
    private func handleSlotDrop(_ slot: TimeSlot) {
        guard let draggedBooking = draggedBooking else { return }
        
        dropTargetSlot = slot
        
        Task {
            await viewModel.moveBooking(
                booking: draggedBooking,
                toSlot: slot
            )
            
            self.draggedBooking = nil
            self.dropTargetSlot = nil
        }
    }
    
    private func applyFilters() async {
        viewModel.filterBookings(searchText: searchText, options: filterOptions)
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ScheduleSlotRow: View {
    let timeSlot: TimeSlot
    let bookings: [TeeTimeBooking]
    let isSelected: (String) -> Bool
    let onBookingTap: (TeeTimeBooking) -> Void
    let onBookingDrag: (TeeTimeBooking) -> Void
    let onSlotDrop: (TimeSlot) -> Void
    let showBulkSelection: Bool
    let tenantTheme: WhiteLabelTheme
    
    var body: some View {
        HStack {
            // Time Label
            Text(timeSlot.time.formatted(date: .omitted, time: .shortened))
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            // Booking Slots
            ForEach(0..<4) { slotIndex in
                if let booking = bookings.first(where: { $0.slotIndex == slotIndex }) {
                    BookingSlotCard(
                        booking: booking,
                        isSelected: isSelected(booking.id),
                        showBulkSelection: showBulkSelection,
                        tenantTheme: tenantTheme,
                        onTap: { onBookingTap(booking) }
                    )
                    .draggable(booking) {
                        BookingDragPreview(booking: booking)
                    }
                    .onDrag {
                        onBookingDrag(booking)
                        return NSItemProvider(object: booking.id as NSString)
                    }
                } else {
                    EmptyBookingSlot(
                        timeSlot: timeSlot,
                        slotIndex: slotIndex
                    )
                    .dropDestination(for: TeeTimeBooking.self) { _, _ in
                        onSlotDrop(timeSlot)
                        return true
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct BookingSlotCard: View {
    let booking: TeeTimeBooking
    let isSelected: Bool
    let showBulkSelection: Bool
    let tenantTheme: WhiteLabelTheme
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if showBulkSelection {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? tenantTheme.primarySwiftUIColor : .secondary)
                        .font(.caption)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(booking.playerName)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack {
                        Image(systemName: booking.status.icon)
                            .font(.caption2)
                        Text(booking.status.displayName)
                            .font(.caption2)
                    }
                    .foregroundColor(booking.status.color)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(booking.status.backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isSelected ? tenantTheme.primarySwiftUIColor : booking.status.color.opacity(0.3),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EmptyBookingSlot: View {
    let timeSlot: TimeSlot
    let slotIndex: Int
    
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(.systemGray6))
            .frame(height: 40)
            .overlay(
                Text("Available")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            )
    }
}

struct BookingDragPreview: View {
    let booking: TeeTimeBooking
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(booking.playerName)
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
            
            Text(booking.teeTime.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(radius: 4)
        )
    }
}

struct BookingListCard: View {
    let booking: TeeTimeBooking
    let isSelected: Bool
    let showBulkSelection: Bool
    let tenantTheme: WhiteLabelTheme
    let onTap: () -> Void
    let onToggleSelection: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                if showBulkSelection {
                    Button(action: onToggleSelection) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? tenantTheme.primarySwiftUIColor : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(booking.playerName)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(booking.teeTime.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        HStack {
                            Image(systemName: booking.status.icon)
                                .font(.caption)
                            Text(booking.status.displayName)
                                .font(.caption)
                        }
                        .foregroundColor(booking.status.color)
                        
                        Spacer()
                        
                        if let course = booking.course {
                            Text(course.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !booking.notes.isEmpty {
                        Text(booking.notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? tenantTheme.primarySwiftUIColor : Color(.systemGray5),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Enums and Supporting Types

enum BookingViewType: String, CaseIterable {
    case schedule = "schedule"
    case list = "list"
    case timeline = "timeline"
    case capacity = "capacity"
    
    var displayName: String {
        switch self {
        case .schedule: return "Schedule"
        case .list: return "List"
        case .timeline: return "Timeline"
        case .capacity: return "Capacity"
        }
    }
}

struct BookingFilterOptions {
    var status: Set<TeeTimeBooking.BookingStatus> = []
    var courses: Set<String> = []
    var players: Set<String> = []
    var timeRange: ClosedRange<Date>?
    var includeNotes: Bool = false
    
    var hasActiveFilters: Bool {
        !status.isEmpty || !courses.isEmpty || !players.isEmpty || timeRange != nil
    }
    
    var activeFilterCount: Int {
        var count = 0
        if !status.isEmpty { count += 1 }
        if !courses.isEmpty { count += 1 }
        if !players.isEmpty { count += 1 }
        if timeRange != nil { count += 1 }
        return count
    }
}

struct TimeSlot: Identifiable {
    let id = UUID()
    let time: Date
    let isAvailable: Bool
    let capacity: Int
}

// MARK: - Extensions

extension TeeTimeBooking.BookingStatus {
    var icon: String {
        switch self {
        case .confirmed: return "checkmark.circle"
        case .checkedIn: return "person.crop.circle.badge.checkmark"
        case .onCourse: return "figure.golf"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .noShow: return "exclamationmark.triangle"
        }
    }
    
    var displayName: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .checkedIn: return "Checked In"
        case .onCourse: return "On Course"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .noShow: return "No Show"
        }
    }
    
    var color: Color {
        switch self {
        case .confirmed: return .blue
        case .checkedIn: return .green
        case .onCourse: return .purple
        case .completed: return .gray
        case .cancelled: return .red
        case .noShow: return .orange
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .confirmed: return .blue.opacity(0.1)
        case .checkedIn: return .green.opacity(0.1)
        case .onCourse: return .purple.opacity(0.1)
        case .completed: return .gray.opacity(0.1)
        case .cancelled: return .red.opacity(0.1)
        case .noShow: return .orange.opacity(0.1)
        }
    }
}

// MARK: - Data Transfer Support

extension TeeTimeBooking: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .booking)
    }
}

extension UTType {
    static let booking = UTType(exportedAs: "com.golfinder.booking")
}