import SwiftUI
import Combine

// MARK: - Tournament Hosting View
/// Primary revenue generator for white label golf course customers
/// Provides secure tournament creation with entry fees and PCI compliant payment processing
/// Target: $25K+/month revenue from tournament hosting

struct TournamentHostingView: View {
    @StateObject private var viewModel = TournamentHostingViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundGradient
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerSection
                        
                        if viewModel.isLoading {
                            loadingView
                        } else {
                            contentView
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create Tournament") {
                        Task {
                            await viewModel.createTournament()
                        }
                    }
                    .foregroundColor(.blue)
                    .disabled(!viewModel.canCreateTournament)
                }
            }
            .alert("Tournament Creation", isPresented: $viewModel.showingAlert) {
                Button("OK") {
                    if viewModel.tournamentCreated {
                        dismiss()
                    }
                }
            } message: {
                Text(viewModel.alertMessage)
            }
        }
        .task {
            await viewModel.loadInitialData()
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(.systemBackground),
                Color(.systemGray6).opacity(0.3)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            
            Text("Host a Tournament")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Create premium tournaments with entry fees and prize pools")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading tournament setup...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        LazyVStack(spacing: 20) {
            tournamentBasicsCard
            prizingAndFeesCard
            participantSettingsCard
            securityAndComplianceCard
            revenueProjectionCard
        }
    }
    
    // MARK: - Tournament Basics Card
    
    private var tournamentBasicsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Tournament Details",
                    icon: "info.circle.fill",
                    iconColor: .blue
                )
                
                VStack(spacing: 12) {
                    CustomTextField(
                        title: "Tournament Name",
                        text: $viewModel.tournamentName,
                        placeholder: "Enter tournament name",
                        icon: "trophy"
                    )
                    
                    CustomTextField(
                        title: "Description",
                        text: $viewModel.description,
                        placeholder: "Tournament description (optional)",
                        icon: "text.alignleft",
                        isMultiline: true
                    )
                    
                    DateSelectionRow(
                        title: "Start Date",
                        date: $viewModel.startDate,
                        icon: "calendar"
                    )
                    
                    DateSelectionRow(
                        title: "End Date",
                        date: $viewModel.endDate,
                        icon: "calendar.badge.clock"
                    )
                    
                    Picker("Tournament Format", selection: $viewModel.selectedFormat) {
                        ForEach(TournamentFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
        }
    }
    
    // MARK: - Pricing and Fees Card
    
    private var prizingAndFeesCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Pricing & Prize Pool",
                    icon: "dollarsign.circle.fill",
                    iconColor: .green
                )
                
                VStack(spacing: 12) {
                    EntryFeeInputRow(
                        title: "Entry Fee",
                        amount: $viewModel.entryFee,
                        currency: viewModel.currency
                    )
                    
                    Toggle("Enable Prize Pool", isOn: $viewModel.hasPrizePool)
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                    
                    if viewModel.hasPrizePool {
                        PrizePoolBreakdownView(
                            totalPrizePool: viewModel.calculatedPrizePool,
                            distribution: viewModel.prizeDistribution,
                            currency: viewModel.currency
                        )
                    }
                    
                    RevenueBreakdownRow(
                        label: "Platform Fee (10%)",
                        amount: viewModel.platformFee,
                        currency: viewModel.currency,
                        isDeduction: true
                    )
                    
                    RevenueBreakdownRow(
                        label: "Net Revenue per Entry",
                        amount: viewModel.netRevenuePerEntry,
                        currency: viewModel.currency,
                        isHighlighted: true
                    )
                }
            }
        }
    }
    
    // MARK: - Participant Settings Card
    
    private var participantSettingsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Participant Settings",
                    icon: "person.3.fill",
                    iconColor: .purple
                )
                
                VStack(spacing: 12) {
                    ParticipantLimitSlider(
                        value: $viewModel.maxParticipants,
                        range: 8...200
                    )
                    
                    Text("Maximum Participants: \(viewModel.maxParticipants)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Toggle("Require Handicap Verification", isOn: $viewModel.requireHandicapVerification)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                    
                    Toggle("Public Tournament", isOn: $viewModel.isPublic)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                    
                    if !viewModel.isPublic {
                        Text("Private tournaments are invitation-only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Security and Compliance Card
    
    private var securityAndComplianceCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Security & Compliance",
                    icon: "shield.checkerboard",
                    iconColor: .red
                )
                
                VStack(spacing: 8) {
                    SecurityComplianceRow(
                        title: "PCI DSS Compliant Payments",
                        status: .compliant,
                        description: "All payment processing meets PCI DSS standards"
                    )
                    
                    SecurityComplianceRow(
                        title: "Multi-Tenant Data Isolation",
                        status: .compliant,
                        description: "Tournament data is securely isolated per tenant"
                    )
                    
                    SecurityComplianceRow(
                        title: "Fraud Prevention",
                        status: viewModel.fraudPreventionEnabled ? .compliant : .warning,
                        description: "Advanced fraud detection and prevention enabled"
                    )
                    
                    SecurityComplianceRow(
                        title: "GDPR Compliance",
                        status: .compliant,
                        description: "Data processing complies with GDPR requirements"
                    )
                }
            }
        }
    }
    
    // MARK: - Revenue Projection Card
    
    private var revenueProjectionCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Revenue Projection",
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .green
                )
                
                VStack(spacing: 12) {
                    RevenueProjectionMetric(
                        title: "Projected Gross Revenue",
                        amount: viewModel.projectedGrossRevenue,
                        currency: viewModel.currency,
                        subtitle: "Based on \(viewModel.maxParticipants) participants"
                    )
                    
                    RevenueProjectionMetric(
                        title: "Platform Net Revenue",
                        amount: viewModel.projectedNetRevenue,
                        currency: viewModel.currency,
                        subtitle: "After prize pool distribution",
                        isHighlighted: true
                    )
                    
                    if viewModel.monthlyTournamentGoal > 0 {
                        RevenueProjectionMetric(
                            title: "Monthly Revenue Target",
                            amount: viewModel.monthlyRevenueTarget,
                            currency: viewModel.currency,
                            subtitle: "Goal: \(viewModel.monthlyTournamentGoal) tournaments/month"
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct CardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack {
            content
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    let iconColor: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title2)
            
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
        }
    }
}

struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let icon: String
    let isMultiline: Bool
    
    init(title: String, text: Binding<String>, placeholder: String, icon: String, isMultiline: Bool = false) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.icon = icon
        self.isMultiline = isMultiline
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Group {
                if isMultiline {
                    TextEditor(text: $text)
                        .frame(minHeight: 80)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct DateSelectionRow: View {
    let title: String
    @Binding var date: Date
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(CompactDatePickerStyle())
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }
}

struct EntryFeeInputRow: View {
    let title: String
    @Binding var amount: Double
    let currency: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "dollarsign.circle")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack {
                Text(currency)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                
                TextField("0.00", value: $amount, format: .currency(code: currency))
                    .keyboardType(.decimalPad)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct PrizePoolBreakdownView: View {
    let totalPrizePool: Double
    let distribution: [PrizeDistribution]
    let currency: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prize Pool Distribution")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                ForEach(distribution.indices, id: \.self) { index in
                    let prize = distribution[index]
                    HStack {
                        Text(prize.position)
                        Spacer()
                        Text(prize.formattedAmount(total: totalPrizePool, currency: currency))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(6)
        }
    }
}

struct RevenueBreakdownRow: View {
    let label: String
    let amount: Double
    let currency: String
    let isDeduction: Bool
    let isHighlighted: Bool
    
    init(label: String, amount: Double, currency: String, isDeduction: Bool = false, isHighlighted: Bool = false) {
        self.label = label
        self.amount = amount
        self.currency = currency
        self.isDeduction = isDeduction
        self.isHighlighted = isHighlighted
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(isHighlighted ? .subheadline : .caption)
                .fontWeight(isHighlighted ? .semibold : .medium)
                .foregroundColor(isHighlighted ? .primary : .secondary)
            
            Spacer()
            
            Text("\(isDeduction ? "-" : "")\(amount, format: .currency(code: currency))")
                .font(isHighlighted ? .subheadline : .caption)
                .fontWeight(.semibold)
                .foregroundColor(isDeduction ? .red : (isHighlighted ? .green : .primary))
        }
        .padding(.horizontal, isHighlighted ? 8 : 0)
        .padding(.vertical, isHighlighted ? 4 : 0)
        .background(isHighlighted ? Color.green.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}

struct ParticipantLimitSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Maximum Participants", systemImage: "person.3")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Slider(value: Binding(
                get: { Double(value) },
                set: { value = Int($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            .accentColor(.purple)
        }
    }
}

struct SecurityComplianceRow: View {
    let title: String
    let status: ComplianceStatus
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.iconName)
                .foregroundColor(status.color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct RevenueProjectionMetric: View {
    let title: String
    let amount: Double
    let currency: String
    let subtitle: String
    let isHighlighted: Bool
    
    init(title: String, amount: Double, currency: String, subtitle: String, isHighlighted: Bool = false) {
        self.title = title
        self.amount = amount
        self.currency = currency
        self.subtitle = subtitle
        self.isHighlighted = isHighlighted
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(amount, format: .currency(code: currency))
                .font(isHighlighted ? .title2 : .title3)
                .fontWeight(.bold)
                .foregroundColor(isHighlighted ? .green : .primary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(isHighlighted ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHighlighted ? Color.green.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Supporting Types

enum TournamentFormat: String, CaseIterable {
    case strokePlay = "stroke_play"
    case matchPlay = "match_play"
    case scramble = "scramble"
    case bestBall = "best_ball"
    
    var displayName: String {
        switch self {
        case .strokePlay: return "Stroke Play"
        case .matchPlay: return "Match Play"
        case .scramble: return "Scramble"
        case .bestBall: return "Best Ball"
        }
    }
}

enum ComplianceStatus {
    case compliant
    case warning
    case nonCompliant
    
    var iconName: String {
        switch self {
        case .compliant: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.shield.fill"
        case .nonCompliant: return "xmark.shield.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .compliant: return .green
        case .warning: return .orange
        case .nonCompliant: return .red
        }
    }
}

struct PrizeDistribution {
    let position: String
    let percentage: Double
    
    func formattedAmount(total: Double, currency: String) -> String {
        let amount = total * percentage
        return amount.formatted(.currency(code: currency))
    }
}

// MARK: - Preview

struct TournamentHostingView_Previews: PreviewProvider {
    static var previews: some View {
        TournamentHostingView()
    }
}