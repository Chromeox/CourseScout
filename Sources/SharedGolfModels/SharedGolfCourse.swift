import Foundation
import CoreLocation

// MARK: - Watch-Optimized Golf Course Model

struct SharedGolfCourse: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let address: String
    let city: String
    let state: String
    
    // Essential location data
    let latitude: Double
    let longitude: Double
    
    // Core course specifications
    let numberOfHoles: Int
    let par: Int
    let yardage: SharedCourseYardage
    
    // Watch-essential amenities (reduced set)
    let hasGPS: Bool
    let hasDrivingRange: Bool
    let hasRestaurant: Bool
    let cartRequired: Bool
    
    // Ratings
    let averageRating: Double
    let difficulty: SharedDifficultyLevel
    
    // Operating status
    let isOpen: Bool
    let isActive: Bool
    
    // Multi-tenant context
    let tenantId: String?
    let businessType: SharedBusinessType
    let databaseNamespace: String
    
    // Tenant-specific branding
    let tenantBranding: SharedTenantBranding?
    
    // Computed properties
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var shortAddress: String {
        "\(city), \(state)"
    }
    
    var formattedRating: String {
        String(format: "%.1f", averageRating)
    }
    
    var yardageRange: String {
        "\(yardage.forwardTees)-\(yardage.backTees)"
    }
    
    // Watch Connectivity optimized data
    var essentialData: [String: Any] {
        [
            "id": id,
            "name": name,
            "city": city,
            "state": state,
            "latitude": latitude,
            "longitude": longitude,
            "numberOfHoles": numberOfHoles,
            "par": par,
            "yardage": yardage.compactData,
            "rating": averageRating,
            "difficulty": difficulty.rawValue,
            "isOpen": isOpen
        ]
    }
}

// MARK: - Watch-Optimized Course Yardage

struct SharedCourseYardage: Codable, Equatable, Hashable {
    let backTees: Int           // Blue tees
    let regularTees: Int        // White tees
    let forwardTees: Int        // Red tees
    
    var compactData: [String: Int] {
        [
            "back": backTees,
            "regular": regularTees,
            "forward": forwardTees
        ]
    }
    
    var averageYardage: Int {
        (backTees + regularTees + forwardTees) / 3
    }
}

// MARK: - Watch-Optimized Difficulty Level

enum SharedDifficultyLevel: String, CaseIterable, Codable, Hashable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case championship = "championship"
    
    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .championship: return "Championship"
        }
    }
    
    var shortName: String {
        switch self {
        case .beginner: return "Easy"
        case .intermediate: return "Med"
        case .advanced: return "Hard"
        case .championship: return "Pro"
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

// MARK: - Watch Hole Information

struct SharedHoleInfo: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let holeNumber: Int
    let par: Int
    let yardage: Int
    let handicapIndex: Int
    
    // GPS coordinates for tee, pin, and hazards
    let teeCoordinate: CLLocationCoordinate2D
    let pinCoordinate: CLLocationCoordinate2D
    let hazards: [SharedHazard]
    
    var formattedInfo: String {
        "Hole \(holeNumber) • Par \(par) • \(yardage)y"
    }
    
    var shortInfo: String {
        "\(holeNumber) • \(par) • \(yardage)"
    }
    
    // Distance calculation helpers
    func distanceToPin(from location: CLLocationCoordinate2D) -> Int {
        let teeLocation = CLLocation(latitude: teeCoordinate.latitude, longitude: teeCoordinate.longitude)
        let pinLocation = CLLocation(latitude: pinCoordinate.latitude, longitude: pinCoordinate.longitude)
        let currentLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        let distanceToPin = currentLocation.distance(from: pinLocation)
        return Int(distanceToPin * 1.09361) // Convert meters to yards
    }
    
    func distanceFromTee(to location: CLLocationCoordinate2D) -> Int {
        let teeLocation = CLLocation(latitude: teeCoordinate.latitude, longitude: teeCoordinate.longitude)
        let currentLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        let distance = teeLocation.distance(from: currentLocation)
        return Int(distance * 1.09361) // Convert meters to yards
    }
}

// MARK: - Hazard Information

struct SharedHazard: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let type: HazardType
    let coordinate: CLLocationCoordinate2D
    let radius: Int // Yards
    
    enum HazardType: String, CaseIterable, Codable {
        case water = "water"
        case bunker = "bunker"
        case trees = "trees"
        case outOfBounds = "oob"
        
        var displayName: String {
            switch self {
            case .water: return "Water"
            case .bunker: return "Sand"
            case .trees: return "Trees"
            case .outOfBounds: return "OB"
            }
        }
        
        var symbol: String {
            switch self {
            case .water: return "💧"
            case .bunker: return "🏖️"
            case .trees: return "🌲"
            case .outOfBounds: return "⚠️"
            }
        }
    }
    
    func distanceTo(from location: CLLocationCoordinate2D) -> Int {
        let hazardLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let currentLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        let distance = currentLocation.distance(from: hazardLocation)
        return Int(distance * 1.09361) // Convert meters to yards
    }
}

// MARK: - Course Extension for Full Model Conversion

extension SharedGolfCourse {
    // Convert from full GolfCourse model (for Watch Connectivity)
    init(from fullCourse: GolfCourse, tenantId: String? = nil, businessType: SharedBusinessType = .golfCourse, tenantBranding: SharedTenantBranding? = nil) {
        self.id = fullCourse.id
        self.name = fullCourse.name
        self.address = fullCourse.address
        self.city = fullCourse.city
        self.state = fullCourse.state
        self.latitude = fullCourse.latitude
        self.longitude = fullCourse.longitude
        self.numberOfHoles = fullCourse.numberOfHoles
        self.par = fullCourse.par
        self.yardage = SharedCourseYardage(
            backTees: fullCourse.yardage.backTees,
            regularTees: fullCourse.yardage.regularTees,
            forwardTees: fullCourse.yardage.forwardTees
        )
        self.hasGPS = true // Assume modern courses have GPS
        self.hasDrivingRange = fullCourse.amenities.contains(.drivingRange)
        self.hasRestaurant = fullCourse.amenities.contains(.restaurant) || fullCourse.amenities.contains(.bar)
        self.cartRequired = fullCourse.cartPolicy == .required
        self.averageRating = fullCourse.averageRating
        self.difficulty = SharedDifficultyLevel(rawValue: fullCourse.difficulty.rawValue) ?? .intermediate
        self.isOpen = fullCourse.operatingHours.monday.isOpen // Simplified status
        self.isActive = fullCourse.isActive
        
        // Multi-tenant properties
        self.tenantId = tenantId
        self.businessType = businessType
        self.databaseNamespace = tenantId != nil ? "tenant_\(tenantId!)" : "default"
        self.tenantBranding = tenantBranding
    }
    
    // Default multi-tenant initializer
    init(id: String, name: String, address: String, city: String, state: String, latitude: Double, longitude: Double, numberOfHoles: Int, par: Int, yardage: SharedCourseYardage, hasGPS: Bool = true, hasDrivingRange: Bool = false, hasRestaurant: Bool = false, cartRequired: Bool = false, averageRating: Double = 0.0, difficulty: SharedDifficultyLevel = .intermediate, isOpen: Bool = true, isActive: Bool = true, tenantId: String? = nil, businessType: SharedBusinessType = .golfCourse, tenantBranding: SharedTenantBranding? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.city = city
        self.state = state
        self.latitude = latitude
        self.longitude = longitude
        self.numberOfHoles = numberOfHoles
        self.par = par
        self.yardage = yardage
        self.hasGPS = hasGPS
        self.hasDrivingRange = hasDrivingRange
        self.hasRestaurant = hasRestaurant
        self.cartRequired = cartRequired
        self.averageRating = averageRating
        self.difficulty = difficulty
        self.isOpen = isOpen
        self.isActive = isActive
        self.tenantId = tenantId
        self.businessType = businessType
        self.databaseNamespace = tenantId != nil ? "tenant_\(tenantId!)" : "default"
        self.tenantBranding = tenantBranding
    }
    
    // Tenant-aware computed properties
    var displayName: String {
        if let branding = tenantBranding {
            return "\(branding.brandName) - \(name)"
        }
        return name
    }
    
    var businessTypeDisplayInfo: (icon: String, name: String, color: String) {
        return (
            icon: businessType.iconName,
            name: businessType.shortName,
            color: tenantBranding?.primaryColor ?? "#2E7D32"
        )
    }
    
    var tenantAwareEssentialData: [String: Any] {
        var data = essentialData
        data["tenantId"] = tenantId
        data["businessType"] = businessType.rawValue
        data["databaseNamespace"] = databaseNamespace
        if let branding = tenantBranding {
            data["branding"] = [
                "brandName": branding.brandName,
                "primaryColor": branding.primaryColor,
                "logoURL": branding.logoURL as Any
            ]
        }
        return data
    }
}

// MARK: - CLLocationCoordinate2D Codable Extension

extension CLLocationCoordinate2D: Codable, Equatable, Hashable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}

// MARK: - Multi-Tenant Supporting Types

enum SharedBusinessType: String, CaseIterable, Codable, Hashable {
    case golfCourse = "golf_course"
    case golfResort = "golf_resort" 
    case countryClub = "country_club"
    case publicCourse = "public_course"
    case privateClub = "private_club"
    case golfAcademy = "golf_academy"
    
    var displayName: String {
        switch self {
        case .golfCourse: return "Golf Course"
        case .golfResort: return "Golf Resort"
        case .countryClub: return "Country Club"
        case .publicCourse: return "Public Course"
        case .privateClub: return "Private Club"
        case .golfAcademy: return "Golf Academy"
        }
    }
    
    var shortName: String {
        switch self {
        case .golfCourse: return "Course"
        case .golfResort: return "Resort"
        case .countryClub: return "Club"
        case .publicCourse: return "Public"
        case .privateClub: return "Private"
        case .golfAcademy: return "Academy"
        }
    }
    
    var iconName: String {
        switch self {
        case .golfCourse: return "sportscourt.fill"
        case .golfResort: return "building.2.crop.circle.fill"
        case .countryClub: return "crown.fill"
        case .publicCourse: return "person.3.fill"
        case .privateClub: return "lock.shield.fill"
        case .golfAcademy: return "graduationcap.fill"
        }
    }
    
    var hasBasicFeatures: Bool { true }
    var hasPremiumFeatures: Bool {
        switch self {
        case .golfResort, .countryClub, .privateClub:
            return true
        default:
            return false
        }
    }
    var hasEliteFeatures: Bool {
        switch self {
        case .privateClub:
            return true
        default:
            return false
        }
    }
}

struct SharedTenantBranding: Codable, Equatable, Hashable {
    let primaryColor: String
    let secondaryColor: String
    let logoURL: String?
    let faviconURL: String?
    let brandName: String
    let tagline: String?
    
    // Watch-specific branding
    let watchLogoURL: String?
    let complicationTintColor: String
    let notificationIcon: String?
    
    static let defaultBranding = SharedTenantBranding(
        primaryColor: "#2E7D32",
        secondaryColor: "#4CAF50",
        logoURL: nil,
        faviconURL: nil,
        brandName: "GolfFinder",
        tagline: "Your Golf Experience",
        watchLogoURL: nil,
        complicationTintColor: "#2E7D32",
        notificationIcon: nil
    )
    
    var watchThemeColors: (primary: String, secondary: String, accent: String) {
        // Generate accent color based on primary if not provided
        let accentColor = lightenColor(primaryColor, by: 0.3)
        return (primaryColor, secondaryColor, accentColor)
    }
    
    private func lightenColor(_ hexColor: String, by percentage: Double) -> String {
        // Simple color lightening algorithm
        // In production, you'd want a more sophisticated color manipulation
        return hexColor
    }
}