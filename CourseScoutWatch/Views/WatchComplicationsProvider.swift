import ClockKit
import SwiftUI
import WidgetKit

// MARK: - Watch Complications Provider

@main
struct GolfFinderComplicationProvider: ComplicationDataSource {
    
    // MARK: - Dependencies
    
    private let scorecardService = WatchServiceContainer.shared.scorecardService()
    private let healthService = WatchServiceContainer.shared.healthKitService()
    private let connectivityService = WatchServiceContainer.shared.connectivityService()
    
    // MARK: - Timeline Provider Methods
    
    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            // Current Hole Complication
            CLKComplicationDescriptor(
                identifier: "current-hole",
                displayName: "Current Hole",
                supportedFamilies: [.modularSmall, .utilitarianSmall, .circularSmall, .graphicCorner, .graphicBezel, .graphicCircular]
            ),
            
            // Score Summary Complication  
            CLKComplicationDescriptor(
                identifier: "score-summary", 
                displayName: "Golf Score",
                supportedFamilies: [.modularLarge, .utilitarianLarge, .graphicRectangular, .graphicExtraLarge]
            ),
            
            // Health Metrics Complication
            CLKComplicationDescriptor(
                identifier: "health-metrics",
                displayName: "Golf Health",
                supportedFamilies: [.modularSmall, .utilitarianSmall, .circularSmall, .graphicCorner]
            ),
            
            // Timer Complication
            CLKComplicationDescriptor(
                identifier: "craft-timer",
                displayName: "Craft Timer", 
                supportedFamilies: [.modularSmall, .circularSmall, .graphicCorner, .graphicCircular]
            )
        ]
        
        handler(descriptors)
    }
    
    func getCurrentTimelineEntry(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
    ) {
        Task {
            let entry = await createTimelineEntry(for: complication, at: Date())
            handler(entry)
        }
    }
    
    func getTimelineEntries(
        for complication: CLKComplication,
        after date: Date,
        limit: Int,
        withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void
    ) {
        Task {
            var entries: [CLKComplicationTimelineEntry] = []
            let calendar = Calendar.current
            
            // Generate entries for the next few hours
            for i in 0..<min(limit, 24) {
                if let futureDate = calendar.date(byAdding: .hour, value: i, to: date),
                   let entry = await createTimelineEntry(for: complication, at: futureDate) {
                    entries.append(entry)
                }
            }
            
            handler(entries)
        }
    }
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        let template = createSampleTemplate(for: complication)
        handler(template)
    }
    
    // MARK: - Template Creation
    
    private func createTimelineEntry(for complication: CLKComplication, at date: Date) async -> CLKComplicationTimelineEntry? {
        guard let template = await createTemplate(for: complication, at: date) else { return nil }
        
        return CLKComplicationTimelineEntry(date: date, complicationTemplate: template)
    }
    
    private func createTemplate(for complication: CLKComplication, at date: Date) async -> CLKComplicationTemplate? {
        switch complication.identifier {
        case "current-hole":
            return await createCurrentHoleTemplate(for: complication.family, at: date)
        case "score-summary":
            return await createScoreSummaryTemplate(for: complication.family, at: date)
        case "health-metrics":
            return await createHealthMetricsTemplate(for: complication.family, at: date)
        case "craft-timer":
            return await createCraftTimerTemplate(for: complication.family, at: date)
        default:
            return nil
        }
    }
    
    // MARK: - Current Hole Templates
    
    private func createCurrentHoleTemplate(for family: CLKComplicationFamily, at date: Date) async -> CLKComplicationTemplate? {
        guard let activeRound = await scorecardService.getCurrentRound(),
              let currentHole = activeRound.currentHoleInfo else {
            return createNoActiveRoundTemplate(for: family)
        }
        
        let holeNumber = currentHole.holeNumber
        let par = currentHole.par
        let score = activeRound.scoreForHole(holeNumber)
        
        switch family {
        case .modularSmall, .utilitarianSmall:
            let template = CLKComplicationTemplateModularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: "H\(holeNumber)")
            return template
            
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: "\(holeNumber)")
            return template
            
        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerTextImage()
            template.textProvider = CLKSimpleTextProvider(text: "Hole \(holeNumber)")
            template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "golf.course.fill")!)
            return template
            
        case .graphicCircular:
            let template = CLKComplicationTemplateGraphicCircularView()
            template.contentView = CurrentHoleComplicationView(
                holeNumber: holeNumber,
                par: par,
                score: score
            )
            return template
            
        default:
            return nil
        }
    }
    
    // MARK: - Score Summary Templates
    
    private func createScoreSummaryTemplate(for family: CLKComplicationFamily, at date: Date) async -> CLKComplicationTemplate? {
        guard let activeRound = await scorecardService.getCurrentRound() else {
            return createNoActiveRoundTemplate(for: family)
        }
        
        let totalScore = activeRound.totalScore
        let relativeToPar = activeRound.scoreRelativeToPar
        let holesCompleted = activeRound.currentHole - 1
        
        switch family {
        case .modularLarge:
            let template = CLKComplicationTemplateModularLargeStandardBody()
            template.headerTextProvider = CLKSimpleTextProvider(text: "Golf Score")
            template.body1TextProvider = CLKSimpleTextProvider(text: "\(totalScore) (\(relativeToPar >= 0 ? "+" : "")\(relativeToPar))")
            template.body2TextProvider = CLKSimpleTextProvider(text: "\(holesCompleted) holes completed")
            return template
            
        case .utilitarianLarge:
            let template = CLKComplicationTemplateUtilitarianLargeFlat()
            template.textProvider = CLKSimpleTextProvider(text: "Score: \(totalScore) (\(relativeToPar >= 0 ? "+" : "")\(relativeToPar))")
            return template
            
        case .graphicRectangular:
            let template = CLKComplicationTemplateGraphicRectangularFullView()
            template.contentView = ScoreSummaryComplicationView(
                totalScore: totalScore,
                relativeToPar: relativeToPar,
                holesCompleted: holesCompleted,
                courseName: activeRound.courseName
            )
            return template
            
        default:
            return nil
        }
    }
    
    // MARK: - Health Metrics Templates
    
    private func createHealthMetricsTemplate(for family: CLKComplicationFamily, at date: Date) async -> CLKComplicationTemplate? {
        let healthMetrics = healthService.getWorkoutMetrics()
        let heartRate = Int(healthMetrics.heartRate)
        let calories = Int(healthMetrics.activeEnergyBurned)
        
        switch family {
        case .modularSmall, .utilitarianSmall:
            let template = CLKComplicationTemplateModularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: "\(heartRate)")
            return template
            
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: "♥\(heartRate)")
            return template
            
        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerTextImage()
            template.textProvider = CLKSimpleTextProvider(text: "\(heartRate) BPM")
            template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "heart.fill")!)
            return template
            
        default:
            return nil
        }
    }
    
    // MARK: - Craft Timer Templates
    
    private func createCraftTimerTemplate(for family: CLKComplicationFamily, at date: Date) async -> CLKComplicationTemplate? {
        // Check for active craft timer session
        let hasActiveSession = false // TODO: Implement active session check
        
        switch family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallSimpleImage()
            template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: hasActiveSession ? "timer.fill" : "timer")!)
            return template
            
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleImage()
            template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: hasActiveSession ? "timer.fill" : "timer")!)
            return template
            
        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerTextImage()
            template.textProvider = CLKSimpleTextProvider(text: hasActiveSession ? "Active" : "Timer")
            template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "timer.fill")!)
            return template
            
        case .graphicCircular:
            let template = CLKComplicationTemplateGraphicCircularView()
            template.contentView = CraftTimerComplicationView(isActive: hasActiveSession)
            return template
            
        default:
            return nil
        }
    }
    
    // MARK: - Sample Templates
    
    private func createSampleTemplate(for complication: CLKComplication) -> CLKComplicationTemplate? {
        switch complication.identifier {
        case "current-hole":
            return createSampleCurrentHoleTemplate(for: complication.family)
        case "score-summary":
            return createSampleScoreSummaryTemplate(for: complication.family)
        case "health-metrics":
            return createSampleHealthMetricsTemplate(for: complication.family)
        case "craft-timer":
            return createSampleCraftTimerTemplate(for: complication.family)
        default:
            return nil
        }
    }
    
    private func createSampleCurrentHoleTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        switch family {
        case .modularSmall, .utilitarianSmall:
            let template = CLKComplicationTemplateModularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: "H7")
            return template
            
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: "7")
            return template
            
        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerTextImage()
            template.textProvider = CLKSimpleTextProvider(text: "Hole 7")
            template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "golf.course.fill")!)
            return template
            
        case .graphicCircular:
            let template = CLKComplicationTemplateGraphicCircularView()
            template.contentView = CurrentHoleComplicationView(holeNumber: 7, par: 4, score: "5")
            return template
            
        default:
            return nil
        }
    }
    
    private func createSampleScoreSummaryTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        switch family {
        case .modularLarge:
            let template = CLKComplicationTemplateModularLargeStandardBody()
            template.headerTextProvider = CLKSimpleTextProvider(text: "Golf Score")
            template.body1TextProvider = CLKSimpleTextProvider(text: "38 (+2)")
            template.body2TextProvider = CLKSimpleTextProvider(text: "9 holes completed")
            return template
            
        case .graphicRectangular:
            let template = CLKComplicationTemplateGraphicRectangularFullView()
            template.contentView = ScoreSummaryComplicationView(
                totalScore: 38,
                relativeToPar: 2,
                holesCompleted: 9,
                courseName: "Pebble Beach"
            )
            return template
            
        default:
            return nil
        }
    }
    
    private func createSampleHealthMetricsTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        switch family {
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: "♥85")
            return template
            
        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerTextImage()
            template.textProvider = CLKSimpleTextProvider(text: "85 BPM")
            template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "heart.fill")!)
            return template
            
        default:
            return nil
        }
    }
    
    private func createSampleCraftTimerTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        switch family {
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleImage()
            template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: "timer")!)
            return template
            
        case .graphicCircular:
            let template = CLKComplicationTemplateGraphicCircularView()
            template.contentView = CraftTimerComplicationView(isActive: false)
            return template
            
        default:
            return nil
        }
    }
    
    // MARK: - No Active Round Template
    
    private func createNoActiveRoundTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        switch family {
        case .modularSmall, .utilitarianSmall:
            let template = CLKComplicationTemplateModularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: "Golf")
            return template
            
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleImage()
            template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: "golf.course")!)
            return template
            
        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerTextImage()
            template.textProvider = CLKSimpleTextProvider(text: "Golf")
            template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "golf.course")!)
            return template
            
        default:
            return nil
        }
    }
}

// MARK: - Complication Views

struct CurrentHoleComplicationView: View {
    let holeNumber: Int
    let par: Int
    let score: String?
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.3))
                .overlay(
                    Circle()
                        .stroke(Color.green, lineWidth: 2)
                )
            
            VStack(spacing: 2) {
                Text("\(holeNumber)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                
                if let score = score {
                    Text(score)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                } else {
                    Text("Par \(par)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct ScoreSummaryComplicationView: View {
    let totalScore: Int
    let relativeToPar: Int
    let holesCompleted: Int
    let courseName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(courseName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "golf.course.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }
            
            HStack(alignment: .bottom) {
                Text("\(totalScore)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("(\(relativeToPar >= 0 ? "+" : "")\(relativeToPar))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(relativeToPar >= 0 ? .red : .green)
                
                Spacer()
                
                Text("\(holesCompleted) holes")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 3)
                        .cornerRadius(1.5)
                    
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * (Double(holesCompleted) / 18.0), height: 3)
                        .cornerRadius(1.5)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

struct CraftTimerComplicationView: View {
    let isActive: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.3))
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.orange : Color.secondary, lineWidth: 2)
                )
            
            Image(systemName: isActive ? "timer.fill" : "timer")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isActive ? .orange : .secondary)
                .scaleEffect(isActive ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isActive)
        }
    }
}

// MARK: - Complication Updates

extension GolfFinderComplicationProvider {
    
    static func updateComplications() {
        let server = CLKComplicationServer.sharedInstance()
        
        for complication in server.activeComplications ?? [] {
            server.reloadTimeline(for: complication)
        }
    }
    
    static func updateComplication(withIdentifier identifier: String) {
        let server = CLKComplicationServer.sharedInstance()
        
        if let complication = server.activeComplications?.first(where: { $0.identifier == identifier }) {
            server.reloadTimeline(for: complication)
        }
    }
}