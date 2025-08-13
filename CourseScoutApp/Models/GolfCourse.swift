import Foundation
import CoreLocation
import MapKit

// MARK: - Golf Course Model

struct GolfCourse: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let address: String
    let city: String
    let state: String
    let country: String
    let zipCode: String
    
    // Location data
    let latitude: Double
    let longitude: Double
    
    // Course details
    let description: String?
    let phoneNumber: String?
    let website: String?
    let email: String?
    
    // Course specifications
    let numberOfHoles: Int
    let par: Int
    let yardage: CourseYardage
    let slope: CourseSlope
    let rating: CourseRating
    
    // Pricing
    let pricing: CoursePricing
    
    // Amenities and features
    let amenities: [CourseAmenity]
    let dressCode: DressCode
    let cartPolicy: CartPolicy
    
    // Media
    let images: [CourseImage]
    let virtualTour: String?
    
    // Ratings and reviews
    let averageRating: Double
    let totalReviews: Int
    let difficulty: DifficultyLevel
    
    // Operational details
    let operatingHours: OperatingHours
    let seasonalInfo: SeasonalInfo?
    let bookingPolicy: BookingPolicy
    
    // Metadata
    let createdAt: Date
    let updatedAt: Date
    let isActive: Bool
    let isFeatured: Bool
    
    // Computed properties
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var fullAddress: String {
        "\(address), \(city), \(state) \(zipCode)"
    }
    
    var priceRange: String {
        let min = pricing.weekdayRates.min() ?? 0
        let max = pricing.weekendRates.max() ?? 0
        return "$\(Int(min))-$\(Int(max))"
    }
    
    var formattedRating: String {
        String(format: "%.1f", averageRating)
    }
    
    var primaryImage: String? {
        images.first { $0.isPrimary }?.url ?? images.first?.url
    }
}

// MARK: - Course Yardage

struct CourseYardage: Codable, Equatable {
    let championshipTees: Int    // Black/Gold tees
    let backTees: Int           // Blue tees
    let regularTees: Int        // White tees
    let forwardTees: Int        // Red tees
    let seniorTees: Int?        // Silver tees
    let juniorTees: Int?        // Green tees
    
    var allYardages: [String: Int] {
        var yardages = [
            "Championship": championshipTees,
            "Back": backTees,
            "Regular": regularTees,
            "Forward": forwardTees
        ]
        
        if let senior = seniorTees {
            yardages["Senior"] = senior
        }
        
        if let junior = juniorTees {
            yardages["Junior"] = junior
        }
        
        return yardages
    }
}

// MARK: - Course Slope and Rating

struct CourseSlope: Codable, Equatable {
    let championshipSlope: Double
    let backSlope: Double
    let regularSlope: Double
    let forwardSlope: Double
    let seniorSlope: Double?
    let juniorSlope: Double?
}

struct CourseRating: Codable, Equatable {
    let championshipRating: Double
    let backRating: Double
    let regularRating: Double
    let forwardRating: Double
    let seniorRating: Double?
    let juniorRating: Double?
}

// MARK: - Course Pricing

struct CoursePricing: Codable, Equatable {
    let weekdayRates: [Double]      // 18-hole rates for different times
    let weekendRates: [Double]      // Weekend premium rates
    let twilightRates: [Double]     // Evening rates
    let seniorRates: [Double]?      // Senior discounts
    let juniorRates: [Double]?      // Junior rates
    let cartFee: Double
    let cartIncluded: Bool
    let membershipRequired: Bool
    let guestPolicy: GuestPolicy
    
    // Dynamic pricing
    let seasonalMultiplier: Double
    let peakTimeMultiplier: Double
    let advanceBookingDiscount: Double?
    
    var baseWeekdayRate: Double {
        weekdayRates.first ?? 0
    }
    
    var baseWeekendRate: Double {
        weekendRates.first ?? 0
    }
}

// MARK: - Course Amenities

enum CourseAmenity: String, CaseIterable, Codable {
    case drivingRange = "driving_range"
    case puttingGreen = "putting_green"
    case chippingArea = "chipping_area"
    case proShop = "pro_shop"
    case restaurant = "restaurant"
    case bar = "bar"
    case snackBar = "snack_bar"
    case lockerRoom = "locker_room"
    case clubRental = "club_rental"
    case cartRental = "cart_rental"
    case lessonsPro = "lessons_pro"
    case tournament = "tournament"
    case banquets = "banquets"
    case parking = "parking"
    case wifi = "wifi"
    case accessibility = "accessibility"
    case spa = "spa"
    case hotel = "hotel"
    case pool = "pool"
    case tennis = "tennis"
    
    var displayName: String {
        switch self {
        case .drivingRange: return "Driving Range"
        case .puttingGreen: return "Putting Green"
        case .chippingArea: return "Chipping Area"
        case .proShop: return "Pro Shop"
        case .restaurant: return "Restaurant"
        case .bar: return "Bar"
        case .snackBar: return "Snack Bar"
        case .lockerRoom: return "Locker Room"
        case .clubRental: return "Club Rental"
        case .cartRental: return "Cart Rental"
        case .lessonsPro: return "Golf Lessons"
        case .tournament: return "Tournament Host"
        case .banquets: return "Banquet Facilities"
        case .parking: return "Parking Available"
        case .wifi: return "WiFi"
        case .accessibility: return "Accessible"
        case .spa: return "Spa"
        case .hotel: return "Hotel"
        case .pool: return "Pool"
        case .tennis: return "Tennis"
        }
    }
    
    var icon: String {
        switch self {
        case .drivingRange: return "target"
        case .puttingGreen: return "circle.grid.cross"
        case .chippingArea: return "drop"
        case .proShop: return "bag"
        case .restaurant: return "fork.knife"
        case .bar: return "wineglass"
        case .snackBar: return "cup.and.saucer"
        case .lockerRoom: return "locker"
        case .clubRental: return "sportscourt"
        case .cartRental: return "car"
        case .lessonsPro: return "person.2"
        case .tournament: return "trophy"
        case .banquets: return "party.popper"
        case .parking: return "car.fill"
        case .wifi: return "wifi"
        case .accessibility: return "accessibility"
        case .spa: return "leaf"
        case .hotel: return "bed.double"
        case .pool: return "figure.pool.swim"
        case .tennis: return "tennis.racket"
        }
    }
}

// MARK: - Supporting Enums

enum DressCode: String, CaseIterable, Codable {
    case strict = "strict"
    case moderate = "moderate"
    case casual = "casual"
    case noRestrictions = "no_restrictions"
    
    var description: String {
        switch self {
        case .strict: return "Collared shirt, golf pants/shorts, golf shoes required"
        case .moderate: return "Collared shirt preferred, no denim, golf shoes recommended"
        case .casual: return "Appropriate athletic wear, no denim"
        case .noRestrictions: return "Come as you are"
        }
    }
}

enum CartPolicy: String, CaseIterable, Codable {
    case required = "required"
    case optional = "optional"
    case walking = "walking_only"
    case restricted = "cart_path_only"
    
    var description: String {
        switch self {
        case .required: return "Golf cart required"
        case .optional: return "Cart optional"
        case .walking: return "Walking only"
        case .restricted: return "Cart path only"
        }
    }
}

enum DifficultyLevel: String, CaseIterable, Codable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case championship = "championship"
    
    var displayName: String {
        switch self {
        case .beginner: return "Beginner Friendly"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .championship: return "Championship"
        }
    }
    
    var color: String {
        switch self {
        case .beginner: return "green"
        case .intermediate: return "blue"
        case .advanced: return "orange"
        case .championship: return "red"
        }
    }
}

enum GuestPolicy: String, CaseIterable, Codable {
    case open = "open_to_public"
    case restricted = "members_guests_only"
    case private = "private_members_only"
    case semiPrivate = "semi_private"
    
    var description: String {
        switch self {
        case .open: return "Open to Public"
        case .restricted: return "Members + Guests"
        case .private: return "Private Members Only"
        case .semiPrivate: return "Semi-Private"
        }
    }
}

// MARK: - Course Image

struct CourseImage: Identifiable, Codable, Equatable {
    let id: String
    let url: String
    let thumbnailUrl: String?
    let caption: String?
    let isPrimary: Bool
    let sortOrder: Int
    let imageType: ImageType
    
    enum ImageType: String, CaseIterable, Codable {
        case course = "course"
        case hole = "hole"
        case clubhouse = "clubhouse"
        case amenity = "amenity"
        case aerial = "aerial"
        case landscape = "landscape"
        
        var displayName: String {
            switch self {
            case .course: return "Course View"
            case .hole: return "Hole View"
            case .clubhouse: return "Clubhouse"
            case .amenity: return "Amenity"
            case .aerial: return "Aerial View"
            case .landscape: return "Landscape"
            }
        }
    }
}

// MARK: - Operating Hours

struct OperatingHours: Codable, Equatable {
    let monday: DayHours
    let tuesday: DayHours
    let wednesday: DayHours
    let thursday: DayHours
    let friday: DayHours
    let saturday: DayHours
    let sunday: DayHours
    
    struct DayHours: Codable, Equatable {
        let isOpen: Bool
        let openTime: String?    // "06:00"
        let closeTime: String?   // "19:00"
        let lastTeeTime: String? // "18:00"
        
        var formattedHours: String {
            guard isOpen, let open = openTime, let close = closeTime else {
                return "Closed"
            }
            return "\(formatTime(open)) - \(formatTime(close))"
        }
        
        private func formatTime(_ time: String) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            guard let date = formatter.date(from: time) else { return time }
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }
    }
    
    func hoursForDay(_ day: String) -> DayHours {
        switch day.lowercased() {
        case "monday": return monday
        case "tuesday": return tuesday
        case "wednesday": return wednesday
        case "thursday": return thursday
        case "friday": return friday
        case "saturday": return saturday
        case "sunday": return sunday
        default: return DayHours(isOpen: false, openTime: nil, closeTime: nil, lastTeeTime: nil)
        }
    }
}

// MARK: - Seasonal Information

struct SeasonalInfo: Codable, Equatable {
    let isSeasonalCourse: Bool
    let openingSeason: String?     // "March - November"
    let closingSeason: String?     // "December - February"
    let peakSeason: String?        // "June - August"
    let offSeasonNotes: String?
    let weatherRestrictions: [WeatherRestriction]
    
    enum WeatherRestriction: String, CaseIterable, Codable {
        case snow = "snow"
        case rain = "heavy_rain"
        case wind = "high_wind"
        case frost = "frost"
        case maintenance = "maintenance"
        
        var description: String {
            switch self {
            case .snow: return "Closed during snow"
            case .rain: return "May close for heavy rain"
            case .wind: return "May close for high winds"
            case .frost: return "Delayed opening for frost"
            case .maintenance: return "Periodic maintenance closures"
            }
        }
    }
}

// MARK: - Booking Policy

struct BookingPolicy: Codable, Equatable {
    let advanceBookingDays: Int        // How far in advance you can book
    let cancellationPolicy: String     // Cancellation terms
    let noShowPolicy: String          // No-show consequences  
    let modificationPolicy: String     // Change booking terms
    let depositRequired: Bool
    let depositAmount: Double?
    let refundableDeposit: Bool
    let groupBookingMinimum: Int?      // Minimum players for group booking
    let onlineBookingAvailable: Bool
    let phoneBookingRequired: Bool
    
    var formattedAdvanceBooking: String {
        if advanceBookingDays == 1 {
            return "1 day in advance"
        } else {
            return "\(advanceBookingDays) days in advance"
        }
    }
}

// MARK: - MKAnnotation Compliance

extension GolfCourse: MKAnnotation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var title: String? { name }
    var subtitle: String? { "\(city), \(state) • \(formattedRating) ⭐" }
}