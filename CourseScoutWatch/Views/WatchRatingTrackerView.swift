import SwiftUI
import WatchKit
import Combine

// MARK: - Watch Rating Tracker View

struct WatchRatingTrackerView: View {
    @StateObject private var gamificationService: WatchGamificationService
    @StateObject private var hapticService: WatchHapticFeedbackService
    @State private var currentRating: PlayerRating?
    @State private var ratingHistory: [RatingHistoryPoint] = []
    @State private var showingRatingChange = false
    @State private var ratingChangeValue: Double = 0
    @State private var cancellables = Set<AnyCancellable>()
    
    // Animation states
    @State private var ratingAnimationValue: Double = 0
    @State private var projectedRatingOpacity: Double = 0
    @State private var improvementGlow: Bool = false
    
    // Configuration
    private let ratingHistoryLimit = 10
    private let significantChangeThreshold: Double = 25.0
    
    init(gamificationService: WatchGamificationService, hapticService: WatchHapticFeedbackService) {
        self._gamificationService = StateObject(wrappedValue: gamificationService)
        self._hapticService = StateObject(wrappedValue: hapticService)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Current rating display
                    currentRatingView
                    
                    // Rating change indicator
                    if showingRatingChange {
                        ratingChangeIndicatorView
                            .transition(.opacity.combined(with: .scale))
                    }
                    
                    // Rating progress visualization
                    ratingProgressView
                    
                    // Rating tier information
                    ratingTierView
                    
                    // Handicap information
                    handicapView
                    
                    // Recent changes history
                    ratingHistoryView
                }
                .padding()
            }
            .navigationTitle("Rating")
            .onAppear {
                setupRatingTracking()
            }
            .onDisappear {
                cancellables.removeAll()
            }
            .refreshable {
                await refreshRatingData()
            }
        }
    }
    
    // MARK: - View Components
    
    private var currentRatingView: some View {
        VStack(spacing: 12) {
            // Main rating display
            VStack(spacing: 4) {
                Text("Current Rating")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(Int(currentRating?.currentRating ?? 0))")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(ratingColor(currentRating?.currentRating ?? 0))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.8), value: ratingAnimationValue)
                    
                    Text("pts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .offset(y: -4)
                }
            }
            
            // Projected rating (if available and different)
            if let rating = currentRating,
               let projected = rating.projectedRating,
               abs(projected - rating.currentRating) > 5 {
                
                HStack {
                    Text("Projected:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(projected)) pts")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(ratingColor(projected))
                        .opacity(projectedRatingOpacity)
                        .animation(.easeInOut(duration: 0.5), value: projectedRatingOpacity)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            improvementGlow ? ratingColor(currentRating?.currentRating ?? 0) : Color.clear,
                            lineWidth: improvementGlow ? 2 : 0
                        )
                        .opacity(improvementGlow ? 0.6 : 0)
                        .animation(.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true), value: improvementGlow)
                )
        )
    }
    
    private var ratingChangeIndicatorView: some View {
        HStack(spacing: 8) {
            // Change direction icon
            Image(systemName: ratingChangeValue >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(ratingChangeValue >= 0 ? .green : .red)
                .font(.title3)
            
            // Change amount
            Text("\(ratingChangeValue >= 0 ? "+" : "")\(Int(ratingChangeValue))")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(ratingChangeValue >= 0 ? .green : .red)
            
            Text("rating change")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill((ratingChangeValue >= 0 ? Color.green : Color.red).opacity(0.15))
        )
    }
    
    private var ratingProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress to Next Tier")
                .font(.caption)
                .foregroundColor(.secondary)
            
            let currentTier = getRatingTier(currentRating?.currentRating ?? 0)
            let nextTier = getNextRatingTier(currentTier)
            let progressToNext = getRatingProgress(currentRating?.currentRating ?? 0)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [ratingTierColor(currentTier), ratingTierColor(nextTier)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * progressToNext,
                            height: 8
                        )
                        .animation(.easeInOut(duration: 1.0), value: progressToNext)
                }
            }
            .frame(height: 8)
            
            // Tier labels
            HStack {
                Text(currentTier.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(ratingTierColor(currentTier))
                
                Spacer()
                
                Text("\(Int(progressToNext * 100))%")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(nextTier.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(ratingTierColor(nextTier))
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var ratingTierView: some View {
        let tier = getRatingTier(currentRating?.currentRating ?? 0)
        
        VStack(spacing: 8) {
            HStack {
                // Tier icon
                Image(systemName: tier.iconName)
                    .font(.title2)
                    .foregroundColor(ratingTierColor(tier))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(tier.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Tier benefits
            if !tier.benefits.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tier Benefits:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    ForEach(tier.benefits.prefix(2), id: \.self) { benefit in
                        HStack {
                            Text("•")
                                .foregroundColor(ratingTierColor(tier))
                            Text(benefit)
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ratingTierColor(tier).opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(ratingTierColor(tier), lineWidth: 1)
                        .opacity(0.3)
                )
        )
    }
    
    private var handicapView: some View {
        VStack(spacing: 12) {
            Text("Handicap Information")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                // Current handicap
                VStack {
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(estimatedHandicap(from: currentRating?.currentRating ?? 0), specifier: "%.1f")")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                // Handicap change
                if let rating = currentRating, rating.ratingChange != 0 {
                    VStack {
                        Text("Change")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        let handicapChange = estimatedHandicapChange(from: rating.ratingChange)
                        Text("\(handicapChange >= 0 ? "+" : "")\(handicapChange, specifier: "%.1f")")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(handicapChange <= 0 ? .green : .red) // Lower handicap is better
                    }
                }
            }
            
            Text("Estimated based on rating")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var ratingHistoryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Changes")
                .font(.headline)
                .fontWeight(.semibold)
            
            if ratingHistory.isEmpty {
                Text("No recent changes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(ratingHistory.prefix(5), id: \.timestamp) { point in
                        historyRowView(point)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func historyRowView(_ point: RatingHistoryPoint) -> some View {
        HStack {
            // Date
            Text(formatHistoryDate(point.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            
            // Change indicator
            HStack(spacing: 4) {
                Image(systemName: point.change >= 0 ? "arrow.up" : "arrow.down")
                    .font(.caption2)
                    .foregroundColor(point.change >= 0 ? .green : .red)
                
                Text("\(point.change >= 0 ? "+" : "")\(Int(point.change))")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(point.change >= 0 ? .green : .red)
            }
            .frame(width: 45, alignment: .leading)
            
            Spacer()
            
            // Final rating
            Text("\(Int(point.newRating))")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
    
    // MARK: - Helper Methods
    
    private func ratingColor(_ rating: Double) -> Color {
        let tier = getRatingTier(rating)
        return ratingTierColor(tier)
    }
    
    private func ratingTierColor(_ tier: RatingTier) -> Color {
        switch tier {
        case .beginner:
            return .gray
        case .recreational:
            return .blue
        case .intermediate:
            return .green
        case .advanced:
            return .orange
        case .expert:
            return .red
        case .professional:
            return .purple
        }
    }
    
    private func getRatingTier(_ rating: Double) -> RatingTier {
        switch rating {
        case 0..<600:
            return .beginner
        case 600..<1200:
            return .recreational
        case 1200..<1800:
            return .intermediate
        case 1800..<2400:
            return .advanced
        case 2400..<3000:
            return .expert
        default:
            return .professional
        }
    }
    
    private func getNextRatingTier(_ current: RatingTier) -> RatingTier {
        switch current {
        case .beginner:
            return .recreational
        case .recreational:
            return .intermediate
        case .intermediate:
            return .advanced
        case .advanced:
            return .expert
        case .expert:
            return .professional
        case .professional:
            return .professional
        }
    }
    
    private func getRatingProgress(_ rating: Double) -> Double {
        let tier = getRatingTier(rating)
        let tierRanges: [RatingTier: (min: Double, max: Double)] = [
            .beginner: (0, 600),
            .recreational: (600, 1200),
            .intermediate: (1200, 1800),
            .advanced: (1800, 2400),
            .expert: (2400, 3000),
            .professional: (3000, 4000)
        ]
        
        guard let range = tierRanges[tier] else { return 0 }
        
        let progress = (rating - range.min) / (range.max - range.min)
        return min(max(progress, 0), 1)
    }
    
    private func estimatedHandicap(from rating: Double) -> Double {
        // Rough estimation: higher rating = lower handicap
        // This is a simplified model
        let maxHandicap: Double = 36
        let normalizedRating = min(max(rating, 0), 3000) / 3000
        return maxHandicap * (1 - normalizedRating)
    }
    
    private func estimatedHandicapChange(from ratingChange: Double) -> Double {
        // Approximate handicap change based on rating change
        return -(ratingChange / 100) // Negative because higher rating = lower handicap
    }
    
    private func formatHistoryDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
    
    // MARK: - Animation and Effects
    
    private func triggerRatingChangeEffects(change: Double) {
        ratingChangeValue = change
        showingRatingChange = true
        
        // Update animation value
        withAnimation(.easeInOut(duration: 0.8)) {
            ratingAnimationValue = currentRating?.currentRating ?? 0
            projectedRatingOpacity = 1.0
        }
        
        // Trigger improvement glow for positive changes
        if change > 0 {
            improvementGlow = true
            
            // Reset glow after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                improvementGlow = false
            }
        }
        
        // Hide change indicator after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showingRatingChange = false
            }
        }
        
        // Trigger haptic feedback
        if abs(change) >= significantChangeThreshold {
            hapticService.playSuccessSequence()
        } else if change > 0 {
            hapticService.playTaptic(.success)
        } else if change < 0 {
            hapticService.playTaptic(.warning)
        }
    }
    
    // MARK: - Setup and Event Handling
    
    private func setupRatingTracking() {
        // Subscribe to rating updates
        gamificationService.subscribeToRatingUpdates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rating in
                self?.handleRatingUpdate(rating)
            }
            .store(in: &cancellables)
        
        // Load current rating
        currentRating = gamificationService.getCurrentRating()
        
        // Initialize animation value
        ratingAnimationValue = currentRating?.currentRating ?? 0
        projectedRatingOpacity = currentRating?.projectedRating != nil ? 1.0 : 0.0
        
        // Load rating history (would be from cache or service)
        loadRatingHistory()
    }
    
    private func handleRatingUpdate(_ rating: PlayerRating) {
        let previousRating = currentRating
        currentRating = rating
        
        // Add to history
        if let previous = previousRating, previous.currentRating != rating.currentRating {
            let historyPoint = RatingHistoryPoint(
                timestamp: rating.lastUpdated,
                newRating: rating.currentRating,
                change: rating.ratingChange
            )
            
            ratingHistory.insert(historyPoint, at: 0)
            
            // Limit history size
            if ratingHistory.count > ratingHistoryLimit {
                ratingHistory = Array(ratingHistory.prefix(ratingHistoryLimit))
            }
        }
        
        // Trigger visual effects for changes
        if abs(rating.ratingChange) > 0 {
            triggerRatingChangeEffects(change: rating.ratingChange)
        }
    }
    
    private func loadRatingHistory() {
        // Mock rating history - would load from service/cache in real implementation
        let now = Date()
        ratingHistory = [
            RatingHistoryPoint(timestamp: now.addingTimeInterval(-86400), newRating: 1245, change: 15),
            RatingHistoryPoint(timestamp: now.addingTimeInterval(-172800), newRating: 1230, change: -8),
            RatingHistoryPoint(timestamp: now.addingTimeInterval(-259200), newRating: 1238, change: 22),
            RatingHistoryPoint(timestamp: now.addingTimeInterval(-345600), newRating: 1216, change: -12),
            RatingHistoryPoint(timestamp: now.addingTimeInterval(-432000), newRating: 1228, change: 18)
        ]
    }
    
    private func refreshRatingData() async {
        // Simulate refresh delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Would refresh data from service in real implementation
        currentRating = gamificationService.getCurrentRating()
    }
}

// MARK: - Rating Tier Definition

enum RatingTier {
    case beginner
    case recreational
    case intermediate
    case advanced
    case expert
    case professional
    
    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .recreational: return "Recreational"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .expert: return "Expert"
        case .professional: return "Professional"
        }
    }
    
    var description: String {
        switch self {
        case .beginner: return "Learning the basics"
        case .recreational: return "Casual player"
        case .intermediate: return "Regular golfer"
        case .advanced: return "Skilled player"
        case .expert: return "Highly skilled"
        case .professional: return "Tournament level"
        }
    }
    
    var iconName: String {
        switch self {
        case .beginner: return "figure.golf"
        case .recreational: return "sportscourt"
        case .intermediate: return "target"
        case .advanced: return "medal"
        case .expert: return "crown"
        case .professional: return "trophy.fill"
        }
    }
    
    var benefits: [String] {
        switch self {
        case .beginner:
            return ["Basic tracking", "Learning resources"]
        case .recreational:
            return ["Course recommendations", "Basic analytics"]
        case .intermediate:
            return ["Advanced analytics", "Challenge access"]
        case .advanced:
            return ["Tournament entry", "Pro tips"]
        case .expert:
            return ["Expert challenges", "Coaching access"]
        case .professional:
            return ["Pro tournaments", "Sponsorship opportunities"]
        }
    }
}

// MARK: - Supporting Types

struct RatingHistoryPoint {
    let timestamp: Date
    let newRating: Double
    let change: Double
}

// MARK: - Compact Rating Widget

struct WatchRatingWidget: View {
    let rating: PlayerRating?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Rating")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let rating = rating, rating.ratingChange != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: rating.ratingChange >= 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                        
                        Text("\(Int(abs(rating.ratingChange)))")
                            .font(.caption2)
                    }
                    .foregroundColor(rating.ratingChange >= 0 ? .green : .red)
                }
            }
            
            Text("\(Int(rating?.currentRating ?? 0))")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(ratingColor(rating?.currentRating ?? 0))
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func ratingColor(_ rating: Double) -> Color {
        switch rating {
        case 0..<600: return .gray
        case 600..<1200: return .blue
        case 1200..<1800: return .green
        case 1800..<2400: return .orange
        case 2400..<3000: return .red
        default: return .purple
        }
    }
}

// MARK: - Previews

struct WatchRatingTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        WatchRatingTrackerView(
            gamificationService: MockWatchGamificationService() as! WatchGamificationService,
            hapticService: MockWatchHapticFeedbackService()
        )
        .previewDevice("Apple Watch Series 7 - 45mm")
    }
}