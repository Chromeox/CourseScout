import Foundation
import SwiftUI

// MARK: - B2B Analytics Data Models

// MARK: - Revenue Analytics

struct RevenueMetrics: Codable, Identifiable {
    let id: String
    let tenantId: String
    let period: AnalyticsPeriod
    let totalRevenue: Double
    let bookingRevenue: Double
    let membershipRevenue: Double
    let merchandiseRevenue: Double
    let foodBeverageRevenue: Double
    let otherRevenue: Double
    
    // Revenue trends
    let revenueGrowth: Double // Percentage change
    let averageRevenuePerUser: Double
    let averageRevenuePerBooking: Double
    let lifetimeValue: Double
    
    // Revenue breakdown by time
    let dailyRevenue: [DailyRevenue]
    let monthlyRevenue: [MonthlyRevenue]
    
    // Revenue forecasting
    let projectedRevenue: Double
    let projectedGrowth: Double
    
    let generatedAt: Date
    let dataAccuracy: Double // Confidence level 0.0-1.0
    
    var totalRevenueFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: totalRevenue)) ?? "$0"
    }
    
    var growthPercentageFormatted: String {
        let sign = revenueGrowth >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", revenueGrowth))%"
    }
    
    var growthTrendColor: Color {
        return revenueGrowth >= 0 ? .green : .red
    }
    
    var revenueBreakdown: [RevenueCategory] {
        [
            RevenueCategory(name: "Bookings", amount: bookingRevenue, color: .blue),
            RevenueCategory(name: "Memberships", amount: membershipRevenue, color: .green),
            RevenueCategory(name: "Merchandise", amount: merchandiseRevenue, color: .orange),
            RevenueCategory(name: "Food & Beverage", amount: foodBeverageRevenue, color: .purple),
            RevenueCategory(name: "Other", amount: otherRevenue, color: .gray)
        ]
    }
}

struct DailyRevenue: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let revenue: Double
    let bookings: Int
    let weather: String?
    let specialEvents: [String]
    
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

struct MonthlyRevenue: Codable, Identifiable {
    let id = UUID()
    let month: Date
    let revenue: Double
    let growth: Double
    let bookings: Int
    let averageBookingValue: Double
    
    var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: month)
    }
}

struct RevenueCategory: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
    let color: Color
    
    var percentage: Double = 0.0 // Will be calculated relative to total
    
    var amountFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }
}

// MARK: - Player Behavior Analytics

struct PlayerBehaviorMetrics: Codable, Identifiable {
    let id: String
    let tenantId: String
    let period: AnalyticsPeriod
    
    // User engagement
    let totalUsers: Int
    let activeUsers: Int
    let newUsers: Int
    let returningUsers: Int
    let churningUsers: Int
    let retentionRate: Double
    
    // Session analytics
    let averageSessionDuration: TimeInterval
    let averageSessionsPerUser: Double
    let bounceRate: Double
    
    // Booking behavior
    let bookingConversionRate: Double
    let averageBookingAdvance: TimeInterval // How far in advance users book
    let cancelationRate: Double
    let noShowRate: Double
    let rebookingRate: Double
    
    // Feature usage
    let featureUsage: [FeatureUsageMetric]
    let popularTimeSlots: [TimeSlotPopularity]
    let preferredCourseFeatures: [String: Int]
    
    // Demographic insights
    let ageGroups: [AgeGroupMetric]
    let genderDistribution: [GenderMetric]
    let locationDistribution: [LocationMetric]
    let deviceTypes: [DeviceMetric]
    
    // Satisfaction metrics
    let averageRating: Double
    let reviewCount: Int
    let netPromoterScore: Double
    
    let generatedAt: Date
    
    var engagementScore: Double {
        // Calculate engagement score based on multiple factors
        let sessionScore = min(averageSessionDuration / 1800, 1.0) * 0.3 // Max 30 minutes = 1.0
        let retentionScore = retentionRate * 0.4
        let conversionScore = bookingConversionRate * 0.3
        
        return (sessionScore + retentionScore + conversionScore) * 100
    }
    
    var userGrowthTrend: String {
        let growthRate = Double(newUsers) / max(Double(totalUsers - newUsers), 1.0)
        if growthRate > 0.1 {
            return "Strong Growth"
        } else if growthRate > 0.05 {
            return "Moderate Growth"
        } else if growthRate > 0 {
            return "Slow Growth"
        } else {
            return "Declining"
        }
    }
}

struct FeatureUsageMetric: Codable, Identifiable {
    let id = UUID()
    let featureName: String
    let usageCount: Int
    let uniqueUsers: Int
    let averageUsagePerUser: Double
    let adoptionRate: Double
    
    var popularityLevel: PopularityLevel {
        switch adoptionRate {
        case 0.8...1.0: return .veryHigh
        case 0.6..<0.8: return .high
        case 0.4..<0.6: return .medium
        case 0.2..<0.4: return .low
        default: return .veryLow
        }
    }
    
    enum PopularityLevel: String, CaseIterable {
        case veryHigh = "very_high"
        case high = "high"
        case medium = "medium"
        case low = "low"
        case veryLow = "very_low"
        
        var displayName: String {
            switch self {
            case .veryHigh: return "Very High"
            case .high: return "High"
            case .medium: return "Medium"
            case .low: return "Low"
            case .veryLow: return "Very Low"
            }
        }
        
        var color: Color {
            switch self {
            case .veryHigh: return .green
            case .high: return .blue
            case .medium: return .orange
            case .low: return .red
            case .veryLow: return .gray
            }
        }
    }
}

struct TimeSlotPopularity: Codable, Identifiable {
    let id = UUID()
    let timeSlot: String // "06:00", "07:00", etc.
    let dayOfWeek: Int // 1 = Sunday, 2 = Monday, etc.
    let bookingCount: Int
    let averageBookingValue: Double
    let popularityScore: Double
    
    var timeDisplay: String {
        let hour = Int(timeSlot.prefix(2)) ?? 0
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):00 \(period)"
    }
    
    var dayName: String {
        let days = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[dayOfWeek] ?? "Unknown"
    }
}

struct AgeGroupMetric: Codable, Identifiable {
    let id = UUID()
    let ageGroup: String // "18-25", "26-35", etc.
    let count: Int
    let percentage: Double
    let averageSpending: Double
    let retentionRate: Double
}

struct GenderMetric: Codable, Identifiable {
    let id = UUID()
    let gender: String
    let count: Int
    let percentage: Double
    let averageSpending: Double
}

struct LocationMetric: Codable, Identifiable {
    let id = UUID()
    let location: String
    let count: Int
    let percentage: Double
    let averageDistance: Double // Miles from course
}

struct DeviceMetric: Codable, Identifiable {
    let id = UUID()
    let deviceType: String // "iPhone", "iPad", "Apple Watch"
    let count: Int
    let percentage: Double
    let averageSessionDuration: TimeInterval
}

// MARK: - Predictive Analytics

struct PredictiveAnalytics: Codable, Identifiable {
    let id: String
    let tenantId: String
    let period: AnalyticsPeriod
    
    // Revenue predictions
    let revenueForecasts: [RevenueForecast]
    let seasonalTrends: [SeasonalTrend]
    
    // Demand forecasting
    let demandPredictions: [DemandPrediction]
    let optimalPricing: [PricingRecommendation]
    
    // User behavior predictions
    let churnPredictions: [ChurnPrediction]
    let lifetimeValuePredictions: [LTVPrediction]
    
    // Course optimization
    let capacityOptimization: [CapacityRecommendation]
    let staffingRecommendations: [StaffingRecommendation]
    
    // Weather impact analysis
    let weatherImpactPredictions: [WeatherImpactPrediction]
    
    let confidence: Double // Overall confidence in predictions
    let generatedAt: Date
    
    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.9...1.0: return .veryHigh
        case 0.8..<0.9: return .high
        case 0.7..<0.8: return .medium
        case 0.6..<0.7: return .low
        default: return .veryLow
        }
    }
    
    enum ConfidenceLevel: String, CaseIterable {
        case veryHigh = "very_high"
        case high = "high"
        case medium = "medium"
        case low = "low"
        case veryLow = "very_low"
        
        var displayName: String {
            switch self {
            case .veryHigh: return "Very High"
            case .high: return "High"
            case .medium: return "Medium"
            case .low: return "Low"
            case .veryLow: return "Very Low"
            }
        }
        
        var color: Color {
            switch self {
            case .veryHigh: return .green
            case .high: return .blue
            case .medium: return .orange
            case .low: return .red
            case .veryLow: return .gray
            }
        }
    }
}

struct RevenueForecast: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let predictedRevenue: Double
    let confidence: Double
    let factors: [String] // Contributing factors
}

struct SeasonalTrend: Codable, Identifiable {
    let id = UUID()
    let season: String // "Spring", "Summer", etc.
    let averageRevenue: Double
    let bookingPattern: String
    let recommendations: [String]
}

struct DemandPrediction: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let predictedDemand: Double // Normalized 0-1
    let timeSlot: String
    let factors: [String]
}

struct PricingRecommendation: Codable, Identifiable {
    let id = UUID()
    let timeSlot: String
    let currentPrice: Double
    let recommendedPrice: Double
    let expectedRevenueLift: Double
    let rationale: String
}

struct ChurnPrediction: Codable, Identifiable {
    let id = UUID()
    let userId: String
    let churnProbability: Double
    let riskLevel: RiskLevel
    let preventionStrategies: [String]
    
    enum RiskLevel: String, CaseIterable, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
        
        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
    }
}

struct LTVPrediction: Codable, Identifiable {
    let id = UUID()
    let userSegment: String
    let predictedLTV: Double
    let timeframe: String
    let growthOpportunities: [String]
}

struct CapacityRecommendation: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let timeSlot: String
    let currentCapacity: Int
    let recommendedCapacity: Int
    let utilizationRate: Double
    let revenueImpact: Double
}

struct StaffingRecommendation: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let timeSlot: String
    let currentStaff: Int
    let recommendedStaff: Int
    let department: String
    let costSavings: Double
}

struct WeatherImpactPrediction: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let weatherCondition: String
    let predictedBookingImpact: Double // Percentage change
    let revenueImpact: Double
    let recommendations: [String]
}

// MARK: - Supporting Enums and Types

enum AnalyticsPeriod: String, CaseIterable, Codable {
    case day = "day"
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .quarter: return "Quarterly"
        case .year: return "Yearly"
        case .custom: return "Custom"
        }
    }
    
    var dateFormat: String {
        switch self {
        case .day: return "MMM dd"
        case .week: return "MMM dd"
        case .month: return "MMM yyyy"
        case .quarter: return "Qnn yyyy"
        case .year: return "yyyy"
        case .custom: return "MMM dd"
        }
    }
}

// MARK: - Dashboard Summary

struct B2BAnalyticsSummary: Codable, Identifiable {
    let id: String
    let tenantId: String
    let period: AnalyticsPeriod
    
    // Key Performance Indicators
    let totalRevenue: Double
    let revenueGrowth: Double
    let totalBookings: Int
    let bookingGrowth: Double
    let activeUsers: Int
    let userGrowth: Double
    let averageRating: Double
    let retentionRate: Double
    
    // Alerts and notifications
    let criticalAlerts: [AnalyticsAlert]
    let opportunities: [BusinessOpportunity]
    let recommendations: [ActionableInsight]
    
    let lastUpdated: Date
    
    var overallHealthScore: Double {
        // Calculate overall business health score
        let revenueScore = min(max(revenueGrowth + 100, 0) / 200, 1.0) * 0.3
        let userScore = min(max(userGrowth + 100, 0) / 200, 1.0) * 0.25
        let retentionScore = retentionRate * 0.25
        let ratingScore = (averageRating / 5.0) * 0.2
        
        return (revenueScore + userScore + retentionScore + ratingScore) * 100
    }
    
    var healthStatus: HealthStatus {
        switch overallHealthScore {
        case 90...100: return .excellent
        case 80..<90: return .good
        case 70..<80: return .fair
        case 60..<70: return .poor
        default: return .critical
        }
    }
    
    enum HealthStatus: String, CaseIterable {
        case excellent = "excellent"
        case good = "good"
        case fair = "fair"
        case poor = "poor"
        case critical = "critical"
        
        var displayName: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Poor"
            case .critical: return "Critical"
            }
        }
        
        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .fair: return .yellow
            case .poor: return .orange
            case .critical: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .excellent: return "checkmark.circle.fill"
            case .good: return "checkmark.circle"
            case .fair: return "exclamationmark.triangle"
            case .poor: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.circle.fill"
            }
        }
    }
}

struct AnalyticsAlert: Codable, Identifiable {
    let id: String
    let severity: AlertSeverity
    let title: String
    let message: String
    let category: AlertCategory
    let actionRequired: Bool
    let createdAt: Date
    
    enum AlertSeverity: String, CaseIterable, Codable {
        case info = "info"
        case warning = "warning"
        case error = "error"
        case critical = "critical"
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .yellow
            case .error: return .orange
            case .critical: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "exclamationmark.circle"
            case .critical: return "exclamationmark.octagon"
            }
        }
    }
    
    enum AlertCategory: String, CaseIterable, Codable {
        case revenue = "revenue"
        case users = "users"
        case performance = "performance"
        case security = "security"
        case system = "system"
    }
}

struct BusinessOpportunity: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let potentialRevenue: Double
    let implementation: OpportunityImplementation
    let priority: OpportunityPriority
    let category: String
    let estimatedROI: Double
    
    enum OpportunityImplementation: String, CaseIterable, Codable {
        case immediate = "immediate"
        case short = "short_term"
        case medium = "medium_term"
        case long = "long_term"
        
        var displayName: String {
            switch self {
            case .immediate: return "Immediate"
            case .short: return "Short Term"
            case .medium: return "Medium Term"
            case .long: return "Long Term"
            }
        }
    }
    
    enum OpportunityPriority: String, CaseIterable, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
        
        var color: Color {
            switch self {
            case .low: return .gray
            case .medium: return .blue
            case .high: return .orange
            case .critical: return .red
            }
        }
    }
}

struct ActionableInsight: Codable, Identifiable {
    let id: String
    let insight: String
    let recommendation: String
    let expectedImpact: String
    let category: InsightCategory
    let dataConfidence: Double
    
    enum InsightCategory: String, CaseIterable, Codable {
        case pricing = "pricing"
        case scheduling = "scheduling"
        case marketing = "marketing"
        case operations = "operations"
        case customer = "customer_experience"
    }
}