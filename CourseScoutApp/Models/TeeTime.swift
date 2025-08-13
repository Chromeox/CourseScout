import Foundation

// MARK: - Tee Time Model

struct TeeTime: Identifiable, Codable, Equatable {
    let id: String
    let courseId: String
    let courseName: String
    
    // Scheduling details
    let date: Date
    let time: String          // "08:30"
    let duration: Int         // Expected round duration in minutes
    
    // Booking details
    let maxPlayers: Int       // Usually 1-4
    let availableSpots: Int   // Current availability
    let bookedPlayers: Int    // Already booked
    
    // Pricing
    let basePrice: Double     // Per player
    let cartFee: Double       // Cart rental fee
    let cartIncluded: Bool    // Whether cart is included in base price
    let totalPrice: Double    // Total cost for all players
    
    // Tee and course configuration
    let teeType: TeeType      // Which tees (forward, regular, back, championship)
    let holes: Int            // 9 or 18 holes
    
    // Weather and conditions
    let weatherConditions: WeatherConditions?
    let courseConditions: CourseConditions
    
    // Booking status and policies
    let status: TeeTimeStatus
    let bookingDeadline: Date // Latest time to book/cancel
    let cancellationDeadline: Date
    
    // Group and tournament information
    let isGroupBooking: Bool
    let groupSize: Int?
    let tournamentId: String?
    let isCompetitive: Bool
    
    // Additional services
    let caddieAvailable: Bool
    let caddieRequired: Bool
    let caddiePrice: Double?
    let golfLessonAvailable: Bool
    let equipmentRental: [EquipmentRental]
    
    // Booking metadata
    let createdAt: Date
    let updatedAt: Date
    let bookedBy: String?     // User ID who booked
    let confirmationNumber: String?
    
    // Computed properties
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let date = formatter.date(from: time) else { return time }
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var fullDateTime: String {
        "\(formattedDate) at \(formattedTime)"
    }
    
    var isAvailable: Bool {
        availableSpots > 0 && status == .available
    }
    
    var pricePerPlayer: Double {
        let base = basePrice + (cartIncluded ? 0 : cartFee)
        let caddie = caddiePrice ?? 0
        return base + caddie
    }
    
    var estimatedEndTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let startTime = formatter.date(from: time) else { return time }
        
        let endTime = Calendar.current.date(byAdding: .minute, value: duration, to: startTime) ?? startTime
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: endTime)
    }
    
    var timeSlot: String {
        "\(formattedTime) - \(estimatedEndTime)"
    }
    
    var canBook: Bool {
        isAvailable && Date() < bookingDeadline
    }
    
    var canCancel: Bool {
        Date() < cancellationDeadline && (status == .booked || status == .confirmed)
    }
}

// MARK: - Tee Time Status

enum TeeTimeStatus: String, CaseIterable, Codable {
    case available = "available"
    case booked = "booked"
    case confirmed = "confirmed"
    case cancelled = "cancelled"
    case completed = "completed"
    case noShow = "no_show"
    case waitlisted = "waitlisted"
    case blocked = "blocked"        // Course blocked this time
    case maintenance = "maintenance" // Course maintenance
    
    var displayName: String {
        switch self {
        case .available: return "Available"
        case .booked: return "Booked"
        case .confirmed: return "Confirmed"
        case .cancelled: return "Cancelled"
        case .completed: return "Completed"
        case .noShow: return "No Show"
        case .waitlisted: return "Waitlisted"
        case .blocked: return "Blocked"
        case .maintenance: return "Maintenance"
        }
    }
    
    var color: String {
        switch self {
        case .available: return "green"
        case .booked, .confirmed: return "blue"
        case .cancelled: return "red"
        case .completed: return "gray"
        case .noShow: return "orange"
        case .waitlisted: return "yellow"
        case .blocked, .maintenance: return "red"
        }
    }
    
    var icon: String {
        switch self {
        case .available: return "checkmark.circle"
        case .booked: return "clock"
        case .confirmed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .completed: return "flag.checkered"
        case .noShow: return "exclamationmark.triangle"
        case .waitlisted: return "clock.badge.questionmark"
        case .blocked: return "lock"
        case .maintenance: return "wrench"
        }
    }
}

// MARK: - Tee Type

enum TeeType: String, CaseIterable, Codable {
    case forward = "forward"           // Red tees
    case regular = "regular"           // White tees  
    case back = "back"                // Blue tees
    case championship = "championship" // Black/Gold tees
    case senior = "senior"            // Silver tees
    case junior = "junior"            // Green tees
    case ladies = "ladies"            // Ladies tees
    
    var displayName: String {
        switch self {
        case .forward: return "Forward Tees"
        case .regular: return "Regular Tees"
        case .back: return "Back Tees"
        case .championship: return "Championship Tees"
        case .senior: return "Senior Tees"
        case .junior: return "Junior Tees"
        case .ladies: return "Ladies Tees"
        }
    }
    
    var color: String {
        switch self {
        case .forward: return "red"
        case .regular: return "white"
        case .back: return "blue"
        case .championship: return "black"
        case .senior: return "silver"
        case .junior: return "green"
        case .ladies: return "pink"
        }
    }
    
    var difficulty: String {
        switch self {
        case .forward, .ladies: return "Easiest"
        case .regular, .senior: return "Moderate"
        case .back: return "Challenging"
        case .championship: return "Most Difficult"
        case .junior: return "Youth"
        }
    }
    
    var recommendedFor: [String] {
        switch self {
        case .forward:
            return ["Beginners", "High handicap", "Shorter distance"]
        case .regular:
            return ["Most golfers", "Mid handicap", "Standard play"]
        case .back:
            return ["Low handicap", "Experienced golfers", "Longer distance"]
        case .championship:
            return ["Scratch golfers", "Tournaments", "Professional level"]
        case .senior:
            return ["Senior golfers", "Age 65+", "Shorter distance"]
        case .junior:
            return ["Youth golfers", "Age 12-17", "Learning game"]
        case .ladies:
            return ["Ladies golfers", "Traditional ladies tees", "Appropriate distance"]
        }
    }
}

// MARK: - Weather Conditions

struct WeatherConditions: Codable, Equatable {
    let temperature: Double          // Fahrenheit
    let humidity: Double            // Percentage
    let windSpeed: Double           // MPH
    let windDirection: String       // "N", "NE", "E", etc.
    let precipitation: Double       // Inches
    let conditions: WeatherType
    let visibility: Double          // Miles
    let uvIndex: Int               // 1-11
    let sunrise: String            // "06:30"
    let sunset: String             // "19:45"
    
    var formattedTemperature: String {
        "\(Int(temperature))°F"
    }
    
    var formattedWind: String {
        "\(Int(windSpeed)) mph \(windDirection)"
    }
    
    var playabilityScore: Int {
        var score = 10
        
        // Temperature adjustments
        if temperature < 40 || temperature > 95 {
            score -= 3
        } else if temperature < 50 || temperature > 85 {
            score -= 1
        }
        
        // Wind adjustments
        if windSpeed > 25 {
            score -= 3
        } else if windSpeed > 15 {
            score -= 1
        }
        
        // Weather condition adjustments
        switch conditions {
        case .thunderstorm, .heavyRain:
            score -= 5
        case .lightRain, .drizzle:
            score -= 2
        case .overcast, .fog:
            score -= 1
        case .sunny, .partlyCloudy:
            break // No penalty
        case .snow:
            score = 0 // Unplayable
        }
        
        return max(0, min(10, score))
    }
    
    var playabilityDescription: String {
        switch playabilityScore {
        case 8...10: return "Excellent conditions"
        case 6...7: return "Good conditions"
        case 4...5: return "Fair conditions"
        case 2...3: return "Poor conditions"
        case 0...1: return "Unplayable conditions"
        default: return "Unknown conditions"
        }
    }
}

enum WeatherType: String, CaseIterable, Codable {
    case sunny = "sunny"
    case partlyCloudy = "partly_cloudy"
    case overcast = "overcast"
    case lightRain = "light_rain"
    case heavyRain = "heavy_rain"
    case drizzle = "drizzle"
    case thunderstorm = "thunderstorm"
    case fog = "fog"
    case snow = "snow"
    
    var displayName: String {
        switch self {
        case .sunny: return "Sunny"
        case .partlyCloudy: return "Partly Cloudy"
        case .overcast: return "Overcast"
        case .lightRain: return "Light Rain"
        case .heavyRain: return "Heavy Rain"
        case .drizzle: return "Drizzle"
        case .thunderstorm: return "Thunderstorm"
        case .fog: return "Fog"
        case .snow: return "Snow"
        }
    }
    
    var icon: String {
        switch self {
        case .sunny: return "sun.max"
        case .partlyCloudy: return "cloud.sun"
        case .overcast: return "cloud"
        case .lightRain: return "cloud.rain"
        case .heavyRain: return "cloud.heavyrain"
        case .drizzle: return "cloud.drizzle"
        case .thunderstorm: return "cloud.bolt.rain"
        case .fog: return "cloud.fog"
        case .snow: return "cloud.snow"
        }
    }
}

// MARK: - Course Conditions

struct CourseConditions: Codable, Equatable {
    let greensCondition: ConditionQuality
    let fairwayCondition: ConditionQuality
    let roughCondition: ConditionQuality
    let bunkerCondition: ConditionQuality
    
    let greensSpeed: Int            // Stimpmeter reading (6-14)
    let firmness: FirmnessLevel     // Soft, Medium, Firm
    let moisture: MoistureLevel     // Dry, Normal, Wet
    
    let maintenance: [MaintenanceIssue]
    let temporaryFeatures: [TemporaryFeature]
    
    let overallRating: Int          // 1-10
    let lastUpdated: Date
    
    var conditionSummary: String {
        "Greens: \(greensCondition.displayName), Speed: \(greensSpeed)"
    }
}

enum ConditionQuality: String, CaseIterable, Codable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case closed = "closed"
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "yellow"
        case .poor: return "orange"
        case .closed: return "red"
        }
    }
}

enum FirmnessLevel: String, CaseIterable, Codable {
    case soft = "soft"
    case medium = "medium"
    case firm = "firm"
    case veryFirm = "very_firm"
    
    var displayName: String {
        switch self {
        case .soft: return "Soft"
        case .medium: return "Medium"
        case .firm: return "Firm"
        case .veryFirm: return "Very Firm"
        }
    }
}

enum MoistureLevel: String, CaseIterable, Codable {
    case dry = "dry"
    case normal = "normal"
    case wet = "wet"
    case saturated = "saturated"
    
    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Maintenance and Temporary Features

enum MaintenanceIssue: String, CaseIterable, Codable {
    case aerification = "aerification"
    case overseeding = "overseeding"
    case fertilizing = "fertilizing"
    case bunkerRenovation = "bunker_renovation"
    case treework = "tree_work"
    case irrigationRepair = "irrigation_repair"
    case temporaryGreens = "temporary_greens"
    case temporaryTees = "temporary_tees"
    
    var displayName: String {
        switch self {
        case .aerification: return "Aerification in progress"
        case .overseeding: return "Overseeding completed"
        case .fertilizing: return "Recent fertilization"
        case .bunkerRenovation: return "Bunker renovation"
        case .treework: return "Tree maintenance"
        case .irrigationRepair: return "Irrigation repairs"
        case .temporaryGreens: return "Temporary greens in use"
        case .temporaryTees: return "Temporary tees in use"
        }
    }
    
    var impactsPlay: Bool {
        switch self {
        case .temporaryGreens, .temporaryTees, .bunkerRenovation:
            return true
        default:
            return false
        }
    }
}

enum TemporaryFeature: String, CaseIterable, Codable {
    case dropZone = "drop_zone"
    case alternatePin = "alternate_pin"
    case groundUnderRepair = "ground_under_repair"
    case temporaryWater = "temporary_water"
    case winterRules = "winter_rules"
    
    var displayName: String {
        switch self {
        case .dropZone: return "Drop zone in effect"
        case .alternatePin: return "Alternate pin position"
        case .groundUnderRepair: return "Ground under repair areas"
        case .temporaryWater: return "Temporary water hazards"
        case .winterRules: return "Winter rules in effect"
        }
    }
}

// MARK: - Equipment Rental

struct EquipmentRental: Identifiable, Codable, Equatable {
    let id: String
    let equipmentType: EquipmentType
    let price: Double
    let isAvailable: Bool
    let description: String?
    
    enum EquipmentType: String, CaseIterable, Codable {
        case clubs = "golf_clubs"
        case cart = "golf_cart"
        case shoes = "golf_shoes"
        case umbrella = "umbrella"
        case towel = "towel"
        case gloves = "gloves"
        case rangefinder = "rangefinder"
        case pushCart = "push_cart"
        
        var displayName: String {
            switch self {
            case .clubs: return "Golf Clubs"
            case .cart: return "Golf Cart"
            case .shoes: return "Golf Shoes"
            case .umbrella: return "Umbrella"
            case .towel: return "Golf Towel"
            case .gloves: return "Golf Gloves"
            case .rangefinder: return "Rangefinder"
            case .pushCart: return "Push Cart"
            }
        }
        
        var icon: String {
            switch self {
            case .clubs: return "sportscourt"
            case .cart: return "car"
            case .shoes: return "shoes"
            case .umbrella: return "umbrella"
            case .towel: return "towel"
            case .gloves: return "hand.raised"
            case .rangefinder: return "binoculars"
            case .pushCart: return "cart"
            }
        }
    }
}