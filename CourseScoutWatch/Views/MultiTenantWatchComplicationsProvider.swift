import ClockKit
import SwiftUI
import WatchKit

// MARK: - Multi-Tenant Watch Complications Provider

class MultiTenantWatchComplicationsProvider: NSObject, CLKComplicationDataSource {
    
    // MARK: - Properties
    
    private var tenantConfigService: WatchTenantConfigurationService
    private var themeService: WatchTenantThemeService
    private var connectivityService: MultiTenantWatchConnectivityService
    
    // MARK: - Initialization
    
    override init() {
        self.tenantConfigService = WatchServiceContainer.shared.watchTenantConfigurationService()
        self.themeService = WatchServiceContainer.shared.watchTenantThemeService()
        self.connectivityService = WatchServiceContainer.shared.multiTenantWatchConnectivityService()
        super.init()
    }
    
    // MARK: - Complication Configuration
    
    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let currentContext = tenantConfigService.currentTenantContext
        let capabilities = tenantConfigService.getBusinessTypeCapabilities()
        
        var descriptors: [CLKComplicationDescriptor] = []
        
        // Base complication - always available
        let baseDescriptor = CLKComplicationDescriptor(
            identifier: "golf_course_base",
            displayName: "\(currentContext.businessType.displayName) Status",
            supportedFamilies: CLKComplicationFamily.allCases
        )
        descriptors.append(baseDescriptor)
        
        // Premium features complications
        if capabilities.hasAdvancedAnalytics {
            let analyticsDescriptor = CLKComplicationDescriptor(
                identifier: "golf_analytics",
                displayName: "Golf Analytics",
                supportedFamilies: [.graphicRectangular, .graphicCircular, .modularLarge]
            )
            descriptors.append(analyticsDescriptor)
        }
        
        // Concierge services complication
        if capabilities.supportsConcierge {
            let conciergeDescriptor = CLKComplicationDescriptor(
                identifier: "concierge_services",
                displayName: "Concierge Services",
                supportedFamilies: [.circularSmall, .modularSmall, .graphicCorner]
            )
            descriptors.append(conciergeDescriptor)
        }
        
        // Member services complication (Private Clubs only)
        if capabilities.supportsMemberServices {
            let memberDescriptor = CLKComplicationDescriptor(
                identifier: "member_services",
                displayName: "Member Services",
                supportedFamilies: [.graphicRectangular, .modularLarge]
            )
            descriptors.append(memberDescriptor)
        }
        
        handler(descriptors)
    }
    
    // MARK: - Timeline Configuration
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        // Complications update throughout the day
        let endDate = Calendar.current.date(byAdding: .hour, value: 24, to: Date())
        handler(endDate)
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        // Hide sensitive data when privacy is enabled
        handler(.showOnLockScreen)
    }
    
    // MARK: - Timeline Population
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        
        guard let template = createTemplate(for: complication) else {
            handler(nil)
            return
        }
        
        let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
        handler(entry)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        
        var entries: [CLKComplicationTimelineEntry] = []
        let calendar = Calendar.current
        
        // Create entries for the next few hours
        for i in 0..<min(limit, 6) {
            guard let futureDate = calendar.date(byAdding: .hour, value: i + 1, to: date),
                  let template = createTemplate(for: complication, at: futureDate) else {
                continue
            }
            
            let entry = CLKComplicationTimelineEntry(date: futureDate, complicationTemplate: template)
            entries.append(entry)
        }
        
        handler(entries.isEmpty ? nil : entries)
    }
    
    // MARK: - Template Creation
    
    private func createTemplate(for complication: CLKComplication, at date: Date = Date()) -> CLKComplicationTemplate? {
        let context = tenantConfigService.currentTenantContext
        let colors = themeService.getComplicationColors()
        
        switch complication.identifier {
        case "golf_course_base":
            return createBaseTemplate(for: complication.family, context: context, colors: colors, date: date)
        case "golf_analytics":
            return createAnalyticsTemplate(for: complication.family, context: context, colors: colors, date: date)
        case "concierge_services":
            return createConciergeTemplate(for: complication.family, context: context, colors: colors, date: date)
        case "member_services":
            return createMemberTemplate(for: complication.family, context: context, colors: colors, date: date)
        default:
            return createBaseTemplate(for: complication.family, context: context, colors: colors, date: date)
        }
    }
    
    // MARK: - Base Template Creation
    
    private func createBaseTemplate(for family: CLKComplicationFamily, context: WatchTenantContext, colors: WatchComplicationColors, date: Date) -> CLKComplicationTemplate? {
        
        let businessIcon = Image(systemName: context.businessType.iconName)
        let tintColor = colors.tintColor
        
        switch family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallSimpleImage()
            template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: context.businessType.iconName)!)
            template.imageProvider.tintColor = UIColor(tintColor)
            return template
            
        case .modularLarge:
            let template = CLKComplicationTemplateModularLargeStandardBody()
            template.headerTextProvider = CLKSimpleTextProvider(text: context.businessType.shortName)
            template.body1TextProvider = CLKSimpleTextProvider(text: getCurrentStatus())
            template.body2TextProvider = CLKSimpleTextProvider(text: getWeatherInfo())
            template.headerTextProvider.tintColor = UIColor(tintColor)
            return template
            
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleImage()
            template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: context.businessType.iconName)!)
            template.imageProvider.tintColor = UIColor(tintColor)
            return template
            
        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerTextImage()
            template.textProvider = CLKSimpleTextProvider(text: context.businessType.shortName)
            template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: context.businessType.iconName)!)
            template.textProvider.tintColor = UIColor(tintColor)
            return template
            
        case .graphicCircular:
            return createGraphicCircularTemplate(context: context, colors: colors)
            
        case .graphicRectangular:
            return createGraphicRectangularTemplate(context: context, colors: colors)
            
        default:
            return nil
        }
    }
    
    // MARK: - Advanced Template Creation
    
    private func createAnalyticsTemplate(for family: CLKComplicationFamily, context: WatchTenantContext, colors: WatchComplicationColors, date: Date) -> CLKComplicationTemplate? {
        
        guard context.features.enablePremiumAnalytics else { return nil }
        
        switch family {
        case .graphicRectangular:
            let template = CLKComplicationTemplateGraphicRectangularStandardBody()
            template.headerTextProvider = CLKSimpleTextProvider(text: "Analytics")
            template.body1TextProvider = CLKSimpleTextProvider(text: "Rounds: 12")
            template.body2TextProvider = CLKSimpleTextProvider(text: "Avg: -2.5")
            template.headerTextProvider.tintColor = UIColor(colors.tintColor)
            return template
            
        case .graphicCircular:
            let template = CLKComplicationTemplateGraphicCircularStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "12")
            template.line2TextProvider = CLKSimpleTextProvider(text: "ROUNDS")
            return template
            
        case .modularLarge:
            let template = CLKComplicationTemplateModularLargeStandardBody()
            template.headerTextProvider = CLKSimpleTextProvider(text: "Golf Analytics")
            template.body1TextProvider = CLKSimpleTextProvider(text: "This Week: 3 rounds")
            template.body2TextProvider = CLKSimpleTextProvider(text: "Best: -4 (Eagle Ridge)")
            return template
            
        default:
            return createBaseTemplate(for: family, context: context, colors: colors, date: date)
        }
    }
    
    private func createConciergeTemplate(for family: CLKComplicationFamily, context: WatchTenantContext, colors: WatchComplicationColors, date: Date) -> CLKComplicationTemplate? {
        
        guard context.features.enableConcierge else { return nil }
        
        switch family {
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleImage()
            template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: "person.crop.circle.badge.checkmark")!)
            template.imageProvider.tintColor = UIColor(colors.tintColor)
            return template
            
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: "Service")
            template.textProvider.tintColor = UIColor(colors.tintColor)
            return template
            
        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerTextImage()
            template.textProvider = CLKSimpleTextProvider(text: "Concierge")
            template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "person.crop.circle.badge.checkmark")!)
            return template
            
        default:
            return createBaseTemplate(for: family, context: context, colors: colors, date: date)
        }
    }
    
    private func createMemberTemplate(for family: CLKComplicationFamily, context: WatchTenantContext, colors: WatchComplicationColors, date: Date) -> CLKComplicationTemplate? {
        
        guard context.features.enableMemberServices else { return nil }
        
        switch family {
        case .graphicRectangular:
            let template = CLKComplicationTemplateGraphicRectangularStandardBody()
            template.headerTextProvider = CLKSimpleTextProvider(text: "Member Portal")
            template.body1TextProvider = CLKSimpleTextProvider(text: "Events: 2 today")
            template.body2TextProvider = CLKSimpleTextProvider(text: "Dining: Available")
            template.headerTextProvider.tintColor = UIColor(colors.tintColor)
            return template
            
        case .modularLarge:
            let template = CLKComplicationTemplateModularLargeStandardBody()
            template.headerTextProvider = CLKSimpleTextProvider(text: "Member Services")
            template.body1TextProvider = CLKSimpleTextProvider(text: "Next Event: Gala Dinner")
            template.body2TextProvider = CLKSimpleTextProvider(text: "Saturday 7:00 PM")
            return template
            
        default:
            return createBaseTemplate(for: family, context: context, colors: colors, date: date)
        }
    }
    
    // MARK: - Graphic Template Helpers
    
    private func createGraphicCircularTemplate(context: WatchTenantContext, colors: WatchComplicationColors) -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateGraphicCircularImage()
        
        // Create a custom image with tenant branding
        let image = createBrandedCircularImage(context: context, colors: colors)
        template.imageProvider = CLKFullColorImageProvider(fullColorImage: image)
        
        return template
    }
    
    private func createGraphicRectangularTemplate(context: WatchTenantContext, colors: WatchComplicationColors) -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateGraphicRectangularStandardBody()
        
        template.headerTextProvider = CLKSimpleTextProvider(text: context.businessType.displayName)
        template.body1TextProvider = CLKSimpleTextProvider(text: getCurrentStatus())
        template.body2TextProvider = CLKSimpleTextProvider(text: "Tap for details")
        template.headerTextProvider.tintColor = UIColor(colors.tintColor)
        
        return template
    }
    
    // MARK: - Helper Methods
    
    private func createBrandedCircularImage(context: WatchTenantContext, colors: WatchComplicationColors) -> UIImage {
        let size = CGSize(width: 44, height: 44)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            
            // Background circle with tenant color
            UIColor(colors.backgroundColor).setFill()
            ctx.cgContext.fillEllipse(in: rect)
            
            // Border with tenant primary color
            UIColor(colors.tintColor).setStroke()
            ctx.cgContext.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            
            // Business type icon
            let iconSize: CGFloat = 24
            let iconRect = CGRect(
                x: (size.width - iconSize) / 2,
                y: (size.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            
            if let icon = UIImage(systemName: context.businessType.iconName) {
                UIColor(colors.textColor).setFill()
                icon.draw(in: iconRect)
            }
        }
    }
    
    private func getCurrentStatus() -> String {
        let context = tenantConfigService.currentTenantContext
        
        switch context.businessType {
        case .golfCourse, .publicCourse:
            return "Open"
        case .golfResort:
            return "Resort Open"
        case .countryClub, .privateClub:
            return "Members Only"
        case .golfAcademy:
            return "Lessons Available"
        }
    }
    
    private func getWeatherInfo() -> String {
        // In a real implementation, this would fetch actual weather data
        return "75°F Sunny"
    }
    
    // MARK: - Update Support
    
    func requestedUpdateDidBegin() {
        // Called when the system requests an update
        // Refresh tenant configuration if needed
        Task {
            try? await tenantConfigService.syncTenantConfiguration()
        }
    }
    
    func requestedUpdateBudgetExhausted() {
        // Called when update budget is exhausted
        // Reduce update frequency
    }
}

// MARK: - Complication Update Manager

class MultiTenantComplicationUpdateManager {
    
    private let complicationServer = CLKComplicationServer.sharedInstance()
    private let tenantConfigService: WatchTenantConfigurationService
    
    init(tenantConfigService: WatchTenantConfigurationService) {
        self.tenantConfigService = tenantConfigService
        observeTenantChanges()
    }
    
    private func observeTenantChanges() {
        tenantConfigService.tenantDidChange
            .sink { [weak self] _ in
                self?.updateComplications()
            }
            .store(in: &cancellables)
    }
    
    private func updateComplications() {
        guard let activeComplications = complicationServer.activeComplications else { return }
        
        for complication in activeComplications {
            complicationServer.reloadTimeline(for: complication)
        }
    }
    
    func forceUpdateComplications() {
        updateComplications()
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - SwiftUI Integration

struct TenantComplicationView: View {
    @EnvironmentObject private var tenantConfigService: WatchTenantConfigurationService
    @EnvironmentObject private var themeService: WatchTenantThemeService
    
    var body: some View {
        HStack {
            Image(systemName: tenantConfigService.currentTenantContext.businessType.iconName)
                .foregroundColor(themeService.getPrimaryColor())
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(tenantConfigService.currentTenantContext.businessType.shortName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(themeService.getTextColor())
                
                Text("Tap to open")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(themeService.getBackgroundColor().opacity(0.3))
        )
    }
}

// MARK: - Supporting Extensions

import Combine

extension CLKComplicationFamily: CaseIterable {
    public static var allCases: [CLKComplicationFamily] {
        return [
            .modularSmall,
            .modularLarge,
            .circularSmall,
            .extraLarge,
            .graphicCorner,
            .graphicBezel,
            .graphicCircular,
            .graphicRectangular
        ]
    }
}