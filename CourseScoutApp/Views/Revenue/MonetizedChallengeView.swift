import SwiftUI
import Combine

// MARK: - Monetized Challenge View
/// Premium challenge creation with entry fees and advanced features
/// Revenue target: $10-50 entry fees per monetized challenge
/// Integrates with existing challenge system while adding monetization

struct MonetizedChallengeView: View {
    @StateObject private var viewModel = MonetizedChallengeViewModel()
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
                    Button("Create Challenge") {
                        Task {
                            await viewModel.createMonetizedChallenge()
                        }
                    }
                    .foregroundColor(.blue)
                    .disabled(!viewModel.canCreateChallenge)
                }
            }
            .alert("Challenge Creation", isPresented: $viewModel.showingAlert) {
                Button("OK") {
                    if viewModel.challengeCreated {
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
            Image(systemName: "star.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.yellow)
            
            Text("Create Premium Challenge")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Monetized challenges with entry fees and exclusive rewards")
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
            
            Text("Loading challenge setup...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        LazyVStack(spacing: 20) {
            challengeBasicsCard
            monetizationSettingsCard
            premiumFeaturesCard
            participantLimitsCard
            revenueProjectionCard
            securityComplianceCard
        }
    }
    
    // MARK: - Challenge Basics Card
    
    private var challengeBasicsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Challenge Details",
                    icon: "info.circle.fill",
                    iconColor: .blue
                )
                
                VStack(spacing: 12) {
                    CustomTextField(
                        title: "Challenge Name",
                        text: $viewModel.challengeName,
                        placeholder: "Enter challenge name",
                        icon: "star"
                    )
                    
                    CustomTextField(
                        title: "Description",
                        text: $viewModel.description,
                        placeholder: "Challenge description",
                        icon: "text.alignleft",
                        isMultiline: true
                    )
                    
                    Picker("Challenge Type", selection: $viewModel.selectedChallengeType) {
                        ForEach(PremiumChallengeType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    Picker("Skill Level", selection: $viewModel.skillLevel) {
                        ForEach(SkillLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    DurationPickerRow(
                        title: "Challenge Duration",
                        duration: $viewModel.duration,
                        icon: "clock"
                    )
                }
            }
        }
    }
    
    // MARK: - Monetization Settings Card
    
    private var monetizationSettingsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Monetization & Pricing",
                    icon: "dollarsign.circle.fill",
                    iconColor: .green
                )
                
                VStack(spacing: 12) {
                    EntryFeeInputRow(
                        title: "Entry Fee",
                        amount: $viewModel.entryFee,
                        currency: viewModel.currency
                    )
                    
                    Toggle("Premium Challenge", isOn: $viewModel.isPremiumChallenge)
                        .toggleStyle(SwitchToggleStyle(tint: .purple))
                    
                    if viewModel.isPremiumChallenge {
                        PremiumTierSelector(
                            selectedTier: $viewModel.premiumTier,
                            tiers: viewModel.availablePremiumTiers
                        )
                    }
                    
                    Toggle("Winner Takes All", isOn: $viewModel.winnerTakesAll)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                    
                    if !viewModel.winnerTakesAll {
                        PrizeDistributionView(
                            distribution: viewModel.prizeDistribution,
                            totalPrizePool: viewModel.calculatedPrizePool,
                            currency: viewModel.currency
                        )
                    }
                    
                    RevenueBreakdownRow(
                        label: "Platform Fee (15%)",
                        amount: viewModel.platformFee,
                        currency: viewModel.currency,
                        isDeduction: true
                    )
                    
                    RevenueBreakdownRow(
                        label: "Net Prize Pool",
                        amount: viewModel.netPrizePool,
                        currency: viewModel.currency,
                        isHighlighted: true
                    )
                }
            }
        }
    }
    
    // MARK: - Premium Features Card
    
    private var premiumFeaturesCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Premium Features",
                    icon: "crown.fill",
                    iconColor: .purple
                )
                
                VStack(spacing: 8) {
                    PremiumFeatureRow(
                        title: "Real-time Leaderboard",
                        description: "Live updates and push notifications",
                        isEnabled: $viewModel.realtimeLeaderboard,
                        isPremium: true
                    )
                    
                    PremiumFeatureRow(
                        title: "Advanced Analytics",
                        description: "Detailed performance insights",
                        isEnabled: $viewModel.advancedAnalytics,
                        isPremium: true
                    )
                    
                    PremiumFeatureRow(
                        title: "Video Highlights",
                        description: "Share and review round highlights",
                        isEnabled: $viewModel.videoHighlights,
                        isPremium: true
                    )
                    
                    PremiumFeatureRow(
                        title: "Professional Coaching Tips",
                        description: "AI-powered improvement suggestions",
                        isEnabled: $viewModel.coachingTips,
                        isPremium: true
                    )
                    
                    PremiumFeatureRow(
                        title: "Custom Badges & Achievements",
                        description: "Exclusive challenge rewards",
                        isEnabled: $viewModel.customBadges,
                        isPremium: false
                    )
                }
            }
        }
    }
    
    // MARK: - Participant Limits Card
    
    private var participantLimitsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Participant Settings",
                    icon: "person.3.fill",
                    iconColor: .blue
                )
                
                VStack(spacing: 12) {
                    ParticipantLimitSlider(
                        value: $viewModel.maxParticipants,
                        range: 4...100
                    )
                    
                    Text("Maximum Participants: \(viewModel.maxParticipants)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Toggle("Invitation Only", isOn: $viewModel.invitationOnly)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                    
                    Toggle("Require Handicap Verification", isOn: $viewModel.requireHandicap)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                    
                    if viewModel.isPremiumChallenge {
                        Toggle("Skill Level Matching", isOn: $viewModel.skillLevelMatching)
                            .toggleStyle(SwitchToggleStyle(tint: .purple))
                    }
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
                    icon: "chart.bar.fill",
                    iconColor: .green
                )
                
                VStack(spacing: 12) {
                    RevenueProjectionMetric(
                        title: "Total Entry Fees",
                        amount: viewModel.projectedEntryFees,
                        currency: viewModel.currency,
                        subtitle: "From \(viewModel.maxParticipants) participants"
                    )
                    
                    RevenueProjectionMetric(
                        title: "Platform Revenue",
                        amount: viewModel.projectedPlatformRevenue,
                        currency: viewModel.currency,
                        subtitle: "15% platform fee",
                        isHighlighted: true
                    )
                    
                    RevenueProjectionMetric(
                        title: "Prize Pool",
                        amount: viewModel.netPrizePool,
                        currency: viewModel.currency,
                        subtitle: "Distributed to winners"
                    )
                    
                    if viewModel.monthlyVolumeGoal > 0 {
                        RevenueProjectionMetric(
                            title: "Monthly Revenue Target",
                            amount: viewModel.monthlyRevenueProjection,
                            currency: viewModel.currency,
                            subtitle: "Goal: \(viewModel.monthlyVolumeGoal) challenges/month"
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Security Compliance Card
    
    private var securityComplianceCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Security & Compliance",
                    icon: "shield.checkerboard",
                    iconColor: .red
                )
                
                VStack(spacing: 8) {
                    SecurityComplianceRow(
                        title: "PCI DSS Payment Processing",
                        status: .compliant,
                        description: "Secure payment handling for entry fees"
                    )
                    
                    SecurityComplianceRow(
                        title: "Fair Play Monitoring",
                        status: .compliant,
                        description: "Anti-cheating and score verification"
                    )
                    
                    SecurityComplianceRow(
                        title: "Multi-Tenant Data Security",
                        status: .compliant,
                        description: "Isolated challenge data per tenant"
                    )
                    
                    SecurityComplianceRow(
                        title: "Age Verification",
                        status: viewModel.requireAgeVerification ? .compliant : .warning,
                        description: "Required for monetized challenges"
                    )
                }
                
                if viewModel.entryFee > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        Text("Monetized challenges require participant age verification and gambling regulations compliance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct PremiumTierSelector: View {
    @Binding var selectedTier: PremiumTier
    let tiers: [PremiumTier]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Premium Tier")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(tiers, id: \.self) { tier in
                    PremiumTierCard(
                        tier: tier,
                        isSelected: selectedTier == tier,
                        onSelect: { selectedTier = tier }
                    )
                }
            }
        }
    }
}

struct PremiumTierCard: View {
    let tier: PremiumTier
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            Text(tier.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text(tier.priceMultiplier, format: .percent)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.purple.opacity(0.2) : Color(.systemGray6))
        .foregroundColor(isSelected ? .purple : .primary)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            onSelect()
        }
    }
}

struct PremiumFeatureRow: View {
    let title: String
    let description: String
    @Binding var isEnabled: Bool
    let isPremium: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if isPremium {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.purple)
                            .font(.caption)
                    }
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isEnabled)
                .toggleStyle(SwitchToggleStyle(tint: isPremium ? .purple : .blue))
        }
        .padding(.vertical, 4)
    }
}

struct DurationPickerRow: View {
    let title: String
    @Binding var duration: ChallengeDuration
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Picker("Duration", selection: $duration) {
                ForEach(ChallengeDuration.allCases, id: \.self) { duration in
                    Text(duration.displayName).tag(duration)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct PrizeDistributionView: View {
    let distribution: [PrizeDistribution]
    let totalPrizePool: Double
    let currency: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prize Distribution")
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

// MARK: - Supporting Types

enum PremiumChallengeType: String, CaseIterable {
    case skillChallenge = "skill_challenge"
    case speedRound = "speed_round"
    case accuracyContest = "accuracy_contest"
    case enduranceChallenge = "endurance_challenge"
    case headToHead = "head_to_head"
    
    var displayName: String {
        switch self {
        case .skillChallenge: return "Skill Challenge"
        case .speedRound: return "Speed Round"
        case .accuracyContest: return "Accuracy Contest"
        case .enduranceChallenge: return "Endurance Challenge"
        case .headToHead: return "Head-to-Head"
        }
    }
}

enum SkillLevel: String, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case professional = "professional"
    
    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .professional: return "Professional"
        }
    }
}

enum ChallengeDuration: String, CaseIterable {
    case oneHour = "1h"
    case threeHours = "3h"
    case oneDay = "1d"
    case threeDays = "3d"
    case oneWeek = "1w"
    case twoWeeks = "2w"
    case oneMonth = "1m"
    
    var displayName: String {
        switch self {
        case .oneHour: return "1 Hour"
        case .threeHours: return "3 Hours"
        case .oneDay: return "1 Day"
        case .threeDays: return "3 Days"
        case .oneWeek: return "1 Week"
        case .twoWeeks: return "2 Weeks"
        case .oneMonth: return "1 Month"
        }
    }
    
    var timeInterval: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .threeHours: return 10800
        case .oneDay: return 86400
        case .threeDays: return 259200
        case .oneWeek: return 604800
        case .twoWeeks: return 1209600
        case .oneMonth: return 2592000
        }
    }
}

enum PremiumTier: String, CaseIterable {
    case standard = "standard"
    case premium = "premium"
    case elite = "elite"
    case championship = "championship"
    
    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .premium: return "Premium"
        case .elite: return "Elite"
        case .championship: return "Championship"
        }
    }
    
    var priceMultiplier: Double {
        switch self {
        case .standard: return 1.0
        case .premium: return 1.5
        case .elite: return 2.0
        case .championship: return 3.0
        }
    }
}

// MARK: - Preview

struct MonetizedChallengeView_Previews: PreviewProvider {
    static var previews: some View {
        MonetizedChallengeView()
    }
}