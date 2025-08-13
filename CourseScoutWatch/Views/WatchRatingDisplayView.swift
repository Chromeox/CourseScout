import SwiftUI
import WatchKit
import Combine

// MARK: - Watch Rating Display View

struct WatchRatingDisplayView: View {
    @StateObject private var gamificationService: WatchGamificationService
    @StateObject private var hapticService: WatchHapticFeedbackService
    @StateObject private var connectivityService: WatchConnectivityService
    
    @State private var currentRating: LivePlayerRating?
    @State private var ratingHistory: [RatingDataPoint] = []
    @State private var projectedRating: RatingProjection?
    @State private var showRatingChange = false
    @State private var ratingChangeValue: Double = 0
    @State private var showMilestone = false
    @State private var currentMilestone: RatingMilestone?
    @State private var lastUpdateTime: Date = Date()
    @State private var cancellables = Set<AnyCancellable>()
    
    // Animation states
    @State private var ratingBarProgress: Double = 0
    @State private var projectionLineAnimation: Double = 0
    @State private var pulseAnimation = false
    @State private var showConfidenceInterval = false
    @State private var sparkleAnimation = false
    
    // Configuration
    private let refreshInterval: TimeInterval = 10.0
    private let historyPoints = 20
    private let ratingAnimationDuration: TimeInterval = 1.5
    
    init(
        gamificationService: WatchGamificationService,
        hapticService: WatchHapticFeedbackService,
        connectivityService: WatchConnectivityService
    ) {
        self._gamificationService = StateObject(wrappedValue: gamificationService)
        self._hapticService = StateObject(wrappedValue: hapticService)
        self._connectivityService = StateObject(wrappedValue: connectivityService)
    }
    
    var body: some View {
        ZStack {
            // Dynamic rating background
            ratingBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 12) {
                    // Current rating header
                    currentRatingHeaderView
                    
                    // Rating progress visualization
                    ratingProgressView
                    
                    // Live projection section
                    if let projection = projectedRating {
                        ratingProjectionView(projection)
                    }
                    
                    // Rating trend chart
                    ratingTrendChartView
                    
                    // Rating insights
                    ratingInsightsView
                    
                    // Update info
                    updateInfoView
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            
            // Rating change overlay
            if showRatingChange {
                ratingChangeOverlay
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: showRatingChange)
            }
            
            // Milestone celebration overlay
            if showMilestone, let milestone = currentMilestone {
                milestoneOverlay(milestone)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 1.0, dampingFraction: 0.6), value: showMilestone)
            }
        }
        .navigationTitle("Rating")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupRatingTracking()
        }
        .onDisappear {
            stopRatingTracking()
        }
        .refreshable {
            await refreshRatingData()
        }
        .digitalCrownRotation(
            .constant(0),
            from: 0,
            through: 1,
            by: 0.1,
            sensitivity: .medium,
            isContinuous: false
        ) { crownValue in
            // Toggle between current and projected rating
            showConfidenceInterval = crownValue > 0.5
        }
    }
    
    // MARK: - View Components
    
    private var ratingBackground: LinearGradient {
        guard let rating = currentRating else {
            return LinearGradient(
                colors: [Color.gray.opacity(0.2), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        
        let ratingColor = getRatingColor(rating.currentRating)
        
        return LinearGradient(
            colors: [
                ratingColor.opacity(0.3),
                ratingColor.opacity(0.1),
                Color.black.opacity(0.8)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var currentRatingHeaderView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Current Rating")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let rating = currentRating {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(rating.isLive ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(), value: pulseAnimation)
                        
                        Text(rating.isLive ? "LIVE" : "CACHED")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(rating.isLive ? .green : .orange)
                    }
                }
            }
            
            if let rating = currentRating {
                HStack(alignment: .bottom, spacing: 8) {
                    // Main rating display
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(rating.currentRating))")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(getRatingColor(rating.currentRating))
                            .scaleEffect(sparkleAnimation ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 0.6), value: sparkleAnimation)
                        
                        Text(getRatingLabel(rating.currentRating))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Rating change indicator
                    if abs(rating.ratingChange) > 0.1 {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 2) {
                                Image(systemName: rating.ratingChange > 0 ? "arrow.up" : "arrow.down")
                                    .font(.caption)
                                    .foregroundColor(rating.ratingChange > 0 ? .green : .red)
                                
                                Text(String(format: "%.1f", abs(rating.ratingChange)))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(rating.ratingChange > 0 ? .green : .red)
                            }
                            
                            Text("this round")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                // Loading state
                VStack(spacing: 4) {
                    Text("--")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Text("Loading rating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private var ratingProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Rating Progress")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let rating = currentRating {
                    Text("Next: \(getNextMilestone(rating.currentRating))")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
            }
            
            // Rating progress bar with milestones
            if let rating = currentRating {
                ratingProgressBar(rating)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private func ratingProgressBar(_ rating: LivePlayerRating) -> some View {
        let milestones = getRatingMilestones()
        let currentMilestoneIndex = getCurrentMilestoneIndex(rating.currentRating, milestones: milestones)
        let nextMilestone = currentMilestoneIndex < milestones.count - 1 ? milestones[currentMilestoneIndex + 1] : milestones.last!
        let progress = (rating.currentRating - milestones[currentMilestoneIndex].rating) / 
                      (nextMilestone.rating - milestones[currentMilestoneIndex].rating)
        
        return VStack(spacing: 6) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                    
                    // Progress fill with gradient
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    getRatingColor(milestones[currentMilestoneIndex].rating),
                                    getRatingColor(nextMilestone.rating)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: ratingAnimationDuration), value: progress)
                    
                    // Milestone markers
                    ForEach(milestones, id: \.rating) { milestone in
                        let position = (milestone.rating - milestones[0].rating) / 
                                      (milestones.last!.rating - milestones[0].rating)
                        
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: 12)
                            .offset(x: geometry.size.width * position - 1)
                    }
                }
                .cornerRadius(4)
            }
            .frame(height: 8)
            
            // Progress text
            HStack {
                Text("\(Int(milestones[currentMilestoneIndex].rating))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(String(format: "%.1f", progress * 100))% to next")
                    .font(.caption2)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(Int(nextMilestone.rating))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func ratingProjectionView(_ projection: RatingProjection) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Live Projection")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("\(projection.holesRemaining) holes left")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                    if showConfidenceInterval {
                        Text("±\(String(format: "%.1f", projection.confidenceRange))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Projected rating display
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projected")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(projection.projectedRating))")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(getRatingColor(projection.projectedRating))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Change")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 2) {
                        Image(systemName: projection.projectedChange > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption)
                            .foregroundColor(projection.projectedChange > 0 ? .green : .red)
                        
                        Text(String(format: "%.1f", abs(projection.projectedChange)))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(projection.projectedChange > 0 ? .green : .red)
                    }
                }
            }
            
            // Confidence interval visualization
            if showConfidenceInterval {
                confidenceIntervalView(projection)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func confidenceIntervalView(_ projection: RatingProjection) -> some View {
        VStack(spacing: 4) {
            Text("Confidence Interval")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack {
                Text("\(Int(projection.lowerBound))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Most Likely: \(Int(projection.projectedRating))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(Int(projection.upperBound))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Confidence interval bar
            GeometryReader { geometry in
                ZStack {
                    // Full range background
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    
                    // Confidence range
                    let centerX = geometry.size.width / 2
                    let rangeWidth = geometry.size.width * 0.6
                    
                    Rectangle()
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: rangeWidth, height: 4)
                        .offset(x: centerX - rangeWidth / 2)
                    
                    // Most likely point
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .offset(x: centerX - 4)
                }
            }
            .frame(height: 8)
        }
    }
    
    private var ratingTrendChartView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Rating Trend")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !ratingHistory.isEmpty {
                    let trend = calculateTrend(ratingHistory)
                    HStack(spacing: 2) {
                        Image(systemName: trend > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                            .font(.caption2)
                            .foregroundColor(trend > 0 ? .green : .red)
                        
                        Text(trend > 0 ? "Improving" : "Declining")
                            .font(.caption2)
                            .foregroundColor(trend > 0 ? .green : .red)
                    }
                }
            }
            
            // Mini trend chart
            if !ratingHistory.isEmpty {
                trendChart
            } else {
                Text("No rating history available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 40)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private var trendChart: some View {
        GeometryReader { geometry in
            let maxRating = ratingHistory.map(\.rating).max() ?? 0
            let minRating = ratingHistory.map(\.rating).min() ?? 0
            let range = maxRating - minRating
            
            ZStack {
                // Chart line
                Path { path in
                    for (index, dataPoint) in ratingHistory.enumerated() {
                        let x = CGFloat(index) / CGFloat(ratingHistory.count - 1) * geometry.size.width
                        let y = geometry.size.height - CGFloat((dataPoint.rating - minRating) / range) * geometry.size.height
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.blue, lineWidth: 2)
                
                // Data points
                ForEach(Array(ratingHistory.enumerated()), id: \.offset) { index, dataPoint in
                    let x = CGFloat(index) / CGFloat(ratingHistory.count - 1) * geometry.size.width
                    let y = geometry.size.height - CGFloat((dataPoint.rating - minRating) / range) * geometry.size.height
                    
                    Circle()
                        .fill(getRatingColor(dataPoint.rating))
                        .frame(width: 4, height: 4)
                        .offset(x: x - 2, y: y - 2)
                }
                
                // Projection line if available
                if let projection = projectedRating, let lastPoint = ratingHistory.last {
                    let lastX = geometry.size.width
                    let lastY = geometry.size.height - CGFloat((lastPoint.rating - minRating) / range) * geometry.size.height
                    let projectedY = geometry.size.height - CGFloat((projection.projectedRating - minRating) / range) * geometry.size.height
                    
                    Path { path in
                        path.move(to: CGPoint(x: lastX, y: lastY))
                        path.addLine(to: CGPoint(x: lastX + 20, y: projectedY))
                    }
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [4, 2]))
                    .opacity(projectionLineAnimation)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: projectionLineAnimation)
                }
            }
        }
        .frame(height: 60)
        .onAppear {
            projectionLineAnimation = 1.0
        }
    }
    
    private var ratingInsightsView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Insights")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            VStack(spacing: 6) {
                if let rating = currentRating {
                    // Performance insight
                    insightRow(
                        icon: "target",
                        title: "Performance",
                        value: getPerformanceInsight(rating),
                        color: .blue
                    )
                    
                    // Consistency insight
                    insightRow(
                        icon: "chart.bar",
                        title: "Consistency",
                        value: getConsistencyInsight(rating),
                        color: .purple
                    )
                    
                    // Next milestone
                    insightRow(
                        icon: "flag",
                        title: "Next Goal",
                        value: "Reach \(getNextMilestone(rating.currentRating))",
                        color: .orange
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private func insightRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
    
    private var updateInfoView: some View {
        VStack(spacing: 2) {
            Text("Last Updated")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(timeAgoString(from: lastUpdateTime))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Overlay Views
    
    private var ratingChangeOverlay: some View {
        VStack(spacing: 16) {
            // Rating change animation
            VStack(spacing: 8) {
                Image(systemName: ratingChangeValue > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(ratingChangeValue > 0 ? .green : .red)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true), value: pulseAnimation)
                
                VStack(spacing: 4) {
                    Text("Rating \(ratingChangeValue > 0 ? "Increased" : "Decreased")")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("\(ratingChangeValue > 0 ? "+" : "")\(String(format: "%.1f", ratingChangeValue)) points")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ratingChangeValue > 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(ratingChangeValue > 0 ? Color.green : Color.red, lineWidth: 2)
                )
        )
        .onAppear {
            pulseAnimation = true
            
            // Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                showRatingChange = false
                pulseAnimation = false
            }
        }
    }
    
    private func milestoneOverlay(_ milestone: RatingMilestone) -> some View {
        VStack(spacing: 16) {
            // Milestone icon with sparkles
            ZStack {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.yellow)
                    .scaleEffect(sparkleAnimation ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: sparkleAnimation)
                
                // Sparkles around the icon
                ForEach(0..<8, id: \.self) { index in
                    Image(systemName: "sparkle")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .offset(
                            x: cos(Double(index) * .pi / 4) * 40,
                            y: sin(Double(index) * .pi / 4) * 40
                        )
                        .scaleEffect(sparkleAnimation ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                            value: sparkleAnimation
                        )
                }
            }
            
            VStack(spacing: 8) {
                Text("Milestone Reached!")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
                
                Text(milestone.title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("\(Int(milestone.rating)) Rating")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.yellow, lineWidth: 3)
                )
        )
        .onAppear {
            sparkleAnimation = true
            
            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                showMilestone = false
                sparkleAnimation = false
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getRatingColor(_ rating: Double) -> Color {
        switch rating {
        case 0..<600:
            return .red
        case 600..<1000:
            return .orange
        case 1000..<1400:
            return .yellow
        case 1400..<1800:
            return .green
        case 1800..<2200:
            return .blue
        case 2200...:
            return .purple
        default:
            return .primary
        }
    }
    
    private func getRatingLabel(_ rating: Double) -> String {
        switch rating {
        case 0..<600:
            return "Beginner"
        case 600..<1000:
            return "Novice"
        case 1000..<1400:
            return "Intermediate"
        case 1400..<1800:
            return "Advanced"
        case 1800..<2200:
            return "Expert"
        case 2200...:
            return "Master"
        default:
            return "Unrated"
        }
    }
    
    private func getRatingMilestones() -> [RatingMilestone] {
        return [
            RatingMilestone(rating: 0, title: "Starting Out", icon: "play.circle"),
            RatingMilestone(rating: 600, title: "Getting Started", icon: "leaf"),
            RatingMilestone(rating: 1000, title: "Building Skills", icon: "hammer"),
            RatingMilestone(rating: 1400, title: "Solid Player", icon: "shield"),
            RatingMilestone(rating: 1800, title: "Advanced Golfer", icon: "star"),
            RatingMilestone(rating: 2200, title: "Expert Level", icon: "crown"),
            RatingMilestone(rating: 2600, title: "Master Class", icon: "diamond")
        ]
    }
    
    private func getCurrentMilestoneIndex(_ rating: Double, milestones: [RatingMilestone]) -> Int {
        for (index, milestone) in milestones.enumerated() {
            if rating < milestone.rating {
                return max(0, index - 1)
            }
        }
        return milestones.count - 1
    }
    
    private func getNextMilestone(_ rating: Double) -> String {
        let milestones = getRatingMilestones()
        for milestone in milestones {
            if rating < milestone.rating {
                return "\(Int(milestone.rating))"
            }
        }
        return "\(Int(milestones.last?.rating ?? 3000))"
    }
    
    private func calculateTrend(_ history: [RatingDataPoint]) -> Double {
        guard history.count >= 2 else { return 0 }
        
        let recent = Array(history.suffix(5))
        let early = Array(recent.prefix(2))
        let late = Array(recent.suffix(2))
        
        let earlyAvg = early.map(\.rating).reduce(0, +) / Double(early.count)
        let lateAvg = late.map(\.rating).reduce(0, +) / Double(late.count)
        
        return lateAvg - earlyAvg
    }
    
    private func getPerformanceInsight(_ rating: LivePlayerRating) -> String {
        if rating.ratingChange > 50 {
            return "Excellent round!"
        } else if rating.ratingChange > 10 {
            return "Good improvement"
        } else if rating.ratingChange > -10 {
            return "Steady performance"
        } else {
            return "Room for improvement"
        }
    }
    
    private func getConsistencyInsight(_ rating: LivePlayerRating) -> String {
        // This would be calculated based on rating variance
        return "Good consistency"
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
    
    // MARK: - Rating Tracking
    
    private func setupRatingTracking() {
        logger.debug("Setting up rating tracking")
        
        // Subscribe to live rating updates
        connectivityService.subscribeTo(.liveRatingProjection) { [weak self] data in
            await self?.handleLiveRatingProjection(data)
        }
        
        connectivityService.subscribeTo(.ratingMilestoneReached) { [weak self] data in
            await self?.handleRatingMilestone(data)
        }
        
        // Subscribe to gamification service updates
        gamificationService.subscribeToRatingUpdates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playerRating in
                self?.handleRatingUpdate(playerRating)
            }
            .store(in: &cancellables)
        
        // Load initial data
        loadInitialRatingData()
        
        // Setup refresh timer
        Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshRatingData()
            }
        }
        
        pulseAnimation = true
    }
    
    private func stopRatingTracking() {
        cancellables.removeAll()
        pulseAnimation = false
        logger.debug("Stopped rating tracking")
    }
    
    private func loadInitialRatingData() {
        // Load cached rating data
        if let cachedRating = gamificationService.getCurrentRating() {
            currentRating = LivePlayerRating(from: cachedRating)
        }
        
        // Load rating history from cache
        loadRatingHistory()
    }
    
    private func loadRatingHistory() {
        // Load rating history from cache or service
        // This would typically come from the iPhone app
    }
    
    @MainActor
    private func handleLiveRatingProjection(_ data: [String: Any]) async {
        guard let projectedRating = data["projectedRating"] as? Double,
              let currentRating = data["currentRating"] as? Double,
              let holesRemaining = data["holesRemaining"] as? Int,
              let confidenceInterval = data["confidenceInterval"] as? [String: Double] else { return }
        
        let projection = RatingProjection(
            projectedRating: projectedRating,
            projectedChange: projectedRating - currentRating,
            holesRemaining: holesRemaining,
            lowerBound: confidenceInterval["lower"] ?? projectedRating - 50,
            upperBound: confidenceInterval["upper"] ?? projectedRating + 50,
            confidenceRange: (confidenceInterval["upper"] ?? projectedRating + 50) - (confidenceInterval["lower"] ?? projectedRating - 50)
        )
        
        self.projectedRating = projection
        
        logger.info("Received live rating projection: \(projectedRating)")
    }
    
    @MainActor
    private func handleRatingMilestone(_ data: [String: Any]) async {
        guard let newRating = data["newRating"] as? Double,
              let milestoneType = data["milestoneType"] as? String else { return }
        
        let milestone = RatingMilestone(
            rating: newRating,
            title: milestoneType,
            icon: "star.circle.fill"
        )
        
        currentMilestone = milestone
        showMilestone = true
        
        // Play milestone haptic
        hapticService.playRatingChangeHaptic(ratingChange: 100) // Significant milestone
        
        logger.info("Rating milestone reached: \(milestoneType) at \(newRating)")
    }
    
    private func handleRatingUpdate(_ playerRating: PlayerRating) {
        let oldRating = currentRating?.currentRating ?? 0
        
        currentRating = LivePlayerRating(from: playerRating)
        
        // Show rating change animation
        let change = playerRating.currentRating - oldRating
        if abs(change) > 5 { // Only show for significant changes
            ratingChangeValue = change
            showRatingChange = true
            
            // Trigger haptic feedback
            hapticService.playRatingChangeHaptic(ratingChange: change)
        }
        
        // Update history
        ratingHistory.append(RatingDataPoint(rating: playerRating.currentRating, timestamp: Date()))
        if ratingHistory.count > historyPoints {
            ratingHistory.removeFirst()
        }
        
        lastUpdateTime = Date()
    }
    
    private func refreshRatingData() async {
        lastUpdateTime = Date()
        // Request fresh rating data from iPhone
        await connectivityService.requestLiveUpdate(type: "player_rating")
    }
}

// MARK: - Supporting Data Models

struct LivePlayerRating {
    let playerId: String
    let currentRating: Double
    let ratingChange: Double
    let isLive: Bool
    let lastUpdated: Date
    
    init(from playerRating: PlayerRating) {
        self.playerId = "current_player"
        self.currentRating = playerRating.currentRating
        self.ratingChange = playerRating.ratingChange
        self.isLive = Date().timeIntervalSince(playerRating.lastUpdated) < 300 // Live if updated within 5 minutes
        self.lastUpdated = playerRating.lastUpdated
    }
}

struct RatingProjection {
    let projectedRating: Double
    let projectedChange: Double
    let holesRemaining: Int
    let lowerBound: Double
    let upperBound: Double
    let confidenceRange: Double
}

struct RatingMilestone {
    let rating: Double
    let title: String
    let icon: String
}

struct RatingDataPoint {
    let rating: Double
    let timestamp: Date
}

// MARK: - Preview Support

struct WatchRatingDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WatchRatingDisplayView(
                gamificationService: MockWatchGamificationService() as! WatchGamificationService,
                hapticService: MockWatchHapticFeedbackService(),
                connectivityService: MockWatchConnectivityService() as! WatchConnectivityService
            )
        }
        .previewDevice("Apple Watch Series 9 - 45mm")
    }
}