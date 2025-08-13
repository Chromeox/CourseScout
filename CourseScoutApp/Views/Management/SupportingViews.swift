import SwiftUI
import Combine

// MARK: - Export Options Sheet

struct ExportOptionsSheet: View {
    let tenantId: String
    let timeframe: TimeFrameOption
    let analyticsService: B2BAnalyticsServiceProtocol
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .pdf
    @State private var selectedReportType: ReportType = .executive
    @State private var includeCharts = true
    @State private var includeTables = true
    @State private var isExporting = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Export Format") {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Report Type") {
                    Picker("Type", selection: $selectedReportType) {
                        ForEach(ReportType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                
                Section("Include") {
                    Toggle("Charts and Graphs", isOn: $includeCharts)
                    Toggle("Data Tables", isOn: $includeTables)
                }
                
                Section {
                    Button {
                        Task { await exportData() }
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isExporting ? "Exporting..." : "Export Data")
                        }
                    }
                    .disabled(isExporting)
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func exportData() async {
        isExporting = true
        
        do {
            let _ = try await analyticsService.exportAnalytics(
                for: tenantId,
                format: selectedFormat,
                period: timeframe.analyticsPeriod
            )
            
            // Show success and dismiss
            dismiss()
        } catch {
            print("Export failed: \(error)")
        }
        
        isExporting = false
    }
}

// MARK: - Alert Detail Sheet

struct AlertDetailSheet: View {
    let alert: AnalyticsAlert
    let analyticsService: B2BAnalyticsServiceProtocol
    
    @Environment(\.dismiss) private var dismiss
    @State private var isAcknowledging = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Alert Header
                    HStack {
                        Image(systemName: alert.severity.icon)
                            .font(.title2)
                            .foregroundColor(alert.severity.color)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(alert.category.rawValue.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Alert Message
                    Text(alert.message)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    // Alert Details
                    if alert.actionRequired {
                        Text("Action Required")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.red)
                    }
                    
                    Text("Created: \(alert.createdAt, formatter: DateFormatter.full)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Actions
                    Button {
                        Task { await acknowledgeAlert() }
                    } label: {
                        HStack {
                            if isAcknowledging {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isAcknowledging ? "Acknowledging..." : "Acknowledge")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAcknowledging)
                }
                .padding()
            }
            .navigationTitle("Alert Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func acknowledgeAlert() async {
        isAcknowledging = true
        
        do {
            try await analyticsService.acknowledgeAlert(alertId: alert.id)
            dismiss()
        } catch {
            print("Failed to acknowledge alert: \(error)")
        }
        
        isAcknowledging = false
    }
}

// MARK: - New Booking Sheet

struct NewBookingSheet: View {
    let selectedDate: Date
    let onBookingCreated: (TeeTimeBooking) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var playerName = ""
    @State private var selectedTime = Date()
    @State private var selectedCourse: GolfCourse? = nil
    @State private var notes = ""
    @State private var fee: Double = 75.0
    
    var body: some View {
        NavigationView {
            Form {
                Section("Player Information") {
                    TextField("Player Name", text: $playerName)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
                
                Section("Booking Details") {
                    DatePicker("Tee Time", selection: $selectedTime, displayedComponents: [.date, .hourAndMinute])
                    
                    HStack {
                        Text("Fee")
                        Spacer()
                        TextField("Fee", value: $fee, format: .currency(code: "USD"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }
                
                Section {
                    Button("Create Booking") {
                        createBooking()
                    }
                    .disabled(playerName.isEmpty)
                }
            }
            .navigationTitle("New Booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func createBooking() {
        let booking = TeeTimeBooking(
            id: UUID().uuidString,
            playerName: playerName,
            teeTime: selectedTime,
            status: .confirmed,
            course: selectedCourse,
            notes: notes,
            fee: fee,
            slotIndex: 0
        )
        
        onBookingCreated(booking)
        dismiss()
    }
}

// MARK: - Booking Filters Sheet

struct BookingFiltersSheet: View {
    @Binding var options: BookingFilterOptions
    let onApply: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var tempOptions: BookingFilterOptions
    
    init(options: Binding<BookingFilterOptions>, onApply: @escaping () -> Void) {
        self._options = options
        self.onApply = onApply
        self._tempOptions = State(initialValue: options.wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Booking Status") {
                    ForEach(TeeTimeBooking.BookingStatus.allCases, id: \.self) { status in
                        Toggle(status.displayName, isOn: Binding(
                            get: { tempOptions.status.contains(status) },
                            set: { isOn in
                                if isOn {
                                    tempOptions.status.insert(status)
                                } else {
                                    tempOptions.status.remove(status)
                                }
                            }
                        ))
                    }
                }
                
                Section("Time Range") {
                    // Time range picker would go here
                    Text("Time range filtering coming soon")
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button("Apply Filters") {
                        options = tempOptions
                        onApply()
                        dismiss()
                    }
                    
                    Button("Clear All") {
                        tempOptions = BookingFilterOptions()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Filter Bookings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Timeline Booking View

struct TimelineBookingView: View {
    let bookings: [TeeTimeBooking]
    let selectedDate: Date
    let tenantTheme: WhiteLabelTheme
    let onBookingTap: (TeeTimeBooking) -> Void
    
    private var hourlyBookings: [(hour: Int, bookings: [TeeTimeBooking])] {
        let grouped = Dictionary(grouping: bookings) { booking in
            Calendar.current.component(.hour, from: booking.teeTime)
        }
        
        return grouped.map { hour, bookings in
            (hour: hour, bookings: bookings.sorted { $0.teeTime < $1.teeTime })
        }.sorted { $0.hour < $1.hour }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(hourlyBookings, id: \.hour) { hourGroup in
                HStack(alignment: .top, spacing: 12) {
                    // Hour Label
                    Text(formatHour(hourGroup.hour))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    
                    // Timeline Line
                    VStack {
                        Circle()
                            .fill(tenantTheme.primarySwiftUIColor)
                            .frame(width: 8, height: 8)
                        
                        Rectangle()
                            .fill(tenantTheme.primarySwiftUIColor.opacity(0.3))
                            .frame(width: 2)
                    }
                    
                    // Bookings for this hour
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(hourGroup.bookings, id: \.id) { booking in
                            Button {
                                onBookingTap(booking)
                            } label: {
                                TimelineBookingCard(booking: booking, tenantTheme: tenantTheme)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
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

struct TimelineBookingCard: View {
    let booking: TeeTimeBooking
    let tenantTheme: WhiteLabelTheme
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(booking.playerName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                
                Text(booking.teeTime.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack {
                Image(systemName: booking.status.icon)
                    .font(.caption)
                Text(booking.status.displayName)
                    .font(.caption)
            }
            .foregroundColor(booking.status.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(booking.status.backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(booking.status.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Capacity Overview View

struct CapacityOverviewView: View {
    let capacityData: [CapacityDataPoint]
    let selectedDate: Date
    let tenantTheme: WhiteLabelTheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Course Capacity Overview")
                .font(.headline)
                .foregroundColor(.primary)
            
            if capacityData.isEmpty {
                EmptyStateView(
                    title: "No Capacity Data",
                    subtitle: "Capacity information will appear here",
                    systemImage: "chart.bar"
                )
                .frame(height: 200)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(capacityData, id: \.id) { dataPoint in
                        CapacityCard(dataPoint: dataPoint, tenantTheme: tenantTheme)
                    }
                }
            }
        }
    }
}

struct CapacityCard: View {
    let dataPoint: CapacityDataPoint
    let tenantTheme: WhiteLabelTheme
    
    private var utilizationColor: Color {
        let rate = dataPoint.utilizationRate
        if rate >= 0.9 { return .red }
        else if rate >= 0.7 { return .orange }
        else if rate >= 0.5 { return .green }
        else { return .blue }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dataPoint.hourDisplay)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(Int(dataPoint.utilizationRate * 100))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(utilizationColor)
            }
            
            HStack {
                Text("\(dataPoint.bookedSlots)/\(dataPoint.totalSlots)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("slots")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: dataPoint.utilizationRate)
                .tint(utilizationColor)
                .scaleEffect(y: 2)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(utilizationColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Add Member Sheet

struct AddMemberSheet: View {
    let onMemberCreated: (Member) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var membershipType: Member.MembershipType = .basic
    @State private var isCreating = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Member Information") {
                    TextField("Full Name", text: $name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                
                Section("Membership") {
                    Picker("Type", selection: $membershipType) {
                        ForEach(Member.MembershipType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                
                Section {
                    Button {
                        createMember()
                    } label: {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isCreating ? "Creating..." : "Add Member")
                        }
                    }
                    .disabled(name.isEmpty || email.isEmpty || isCreating)
                }
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func createMember() {
        isCreating = true
        
        let member = Member(
            id: UUID().uuidString,
            name: name,
            email: email,
            profileImageURL: nil,
            membershipType: membershipType,
            activityStatus: .active,
            joinDate: Date(),
            lastVisit: Date(),
            totalVisits: 0,
            totalRevenue: 0,
            preferences: MemberPreferences()
        )
        
        onMemberCreated(member)
        dismiss()
    }
}

// MARK: - Member Detail Sheet

struct MemberDetailSheet: View {
    let member: Member
    let viewModel: MemberManagementViewModel
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Member Header
                    HStack {
                        AsyncImage(url: URL(string: member.profileImageURL ?? "")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(.gray.opacity(0.3))
                                .overlay(
                                    Text(member.initials)
                                        .font(.title.weight(.medium))
                                        .foregroundColor(.gray)
                                )
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.name)
                                .font(.title2.weight(.bold))
                                .foregroundColor(.primary)
                            
                            Text(member.email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(member.membershipType.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(member.membershipType.color.opacity(0.2))
                                    )
                                    .foregroundColor(member.membershipType.color)
                                
                                Text(member.activityStatus.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(member.activityStatus.color.opacity(0.2))
                                    )
                                    .foregroundColor(member.activityStatus.color)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // Member Stats
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        MemberStatItem(
                            title: "Total Visits",
                            value: "\(member.totalVisits)",
                            icon: "figure.golf",
                            color: .blue
                        )
                        
                        MemberStatItem(
                            title: "Total Revenue",
                            value: member.totalRevenue.formatted(.currency(code: "USD")),
                            icon: "dollarsign.circle",
                            color: .green
                        )
                        
                        MemberStatItem(
                            title: "Member Since",
                            value: member.joinDate.formatted(date: .abbreviated, time: .omitted),
                            icon: "calendar",
                            color: .orange
                        )
                        
                        MemberStatItem(
                            title: "Last Visit",
                            value: member.lastVisit.formatted(date: .abbreviated, time: .omitted),
                            icon: "clock",
                            color: .purple
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Member Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        // Handle edit member
                    }
                }
            }
        }
    }
}

struct MemberStatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Spacer()
            }
            
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Member Export Sheet

struct MemberExportSheet: View {
    let members: [Member]
    let tenantId: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .csv
    @State private var includeStats = true
    @State private var includePreferences = false
    @State private var isExporting = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Export Format") {
                    Picker("Format", selection: $selectedFormat) {
                        Text("CSV").tag(ExportFormat.csv)
                        Text("Excel").tag(ExportFormat.excel)
                        Text("PDF").tag(ExportFormat.pdf)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Include Data") {
                    Toggle("Member Statistics", isOn: $includeStats)
                    Toggle("Preferences", isOn: $includePreferences)
                }
                
                Section("Summary") {
                    HStack {
                        Text("Total Members")
                        Spacer()
                        Text("\(members.count)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button {
                        exportMembers()
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isExporting ? "Exporting..." : "Export Members")
                        }
                    }
                    .disabled(isExporting)
                }
            }
            .navigationTitle("Export Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func exportMembers() {
        isExporting = true
        
        // Simulate export process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isExporting = false
            dismiss()
        }
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Data Models for Supporting Views

extension TeeTimeBooking {
    init(id: String, playerName: String, teeTime: Date, status: BookingStatus, course: GolfCourse?, notes: String, fee: Double?, slotIndex: Int) {
        self.id = id
        self.playerName = playerName
        self.teeTime = teeTime
        self.status = status
        self.course = course
        self.notes = notes
        self.fee = fee
        self.slotIndex = slotIndex
    }
}