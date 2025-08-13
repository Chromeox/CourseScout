import Foundation
import CoreLocation
import WeatherKit
import Combine

// MARK: - Weather Service Protocol

protocol WeatherServiceProtocol: ObservableObject {
    // Current weather
    func getCurrentWeather(for location: CLLocationCoordinate2D) async throws -> WeatherConditions
    func getWeatherForGolfCourse(_ course: GolfCourse) async throws -> WeatherConditions
    
    // Weather forecasts
    func getHourlyForecast(for location: CLLocationCoordinate2D, hours: Int) async throws -> [HourlyWeatherForecast]
    func getDailyForecast(for location: CLLocationCoordinate2D, days: Int) async throws -> [DailyWeatherForecast]
    
    // Golf-specific weather analysis
    func getGolfPlayabilityScore(for location: CLLocationCoordinate2D) async throws -> GolfPlayabilityScore
    func getOptimalTeeTimesForDay(location: CLLocationCoordinate2D, date: Date) async throws -> [OptimalTeeTime]
    func getWeatherAlerts(for location: CLLocationCoordinate2D) async throws -> [WeatherAlert]
    
    // Weather conditions monitoring
    func startWeatherMonitoring(for location: CLLocationCoordinate2D)
    func stopWeatherMonitoring()
    var isMonitoringWeather: Bool { get }
    
    // Cached weather data
    func getCachedWeather(for location: CLLocationCoordinate2D) -> WeatherConditions?
    func clearWeatherCache()
}

// MARK: - Additional Weather Data Models

struct HourlyWeatherForecast: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let temperature: Double
    let humidity: Double
    let windSpeed: Double
    let windDirection: String
    let precipitationChance: Double
    let precipitationAmount: Double
    let conditions: WeatherType
    let uvIndex: Int
    let visibility: Double
    
    var golfPlayabilityScore: Int {
        calculateGolfPlayability()
    }
    
    private func calculateGolfPlayability() -> Int {
        var score = 10
        
        // Temperature penalties
        if temperature < 40 || temperature > 95 {
            score -= 4
        } else if temperature < 50 || temperature > 85 {
            score -= 2
        }
        
        // Wind penalties
        if windSpeed > 25 {
            score -= 4
        } else if windSpeed > 15 {
            score -= 2
        }
        
        // Precipitation penalties
        if precipitationChance > 70 {
            score -= 5
        } else if precipitationChance > 40 {
            score -= 3
        } else if precipitationChance > 20 {
            score -= 1
        }
        
        // Weather condition penalties
        switch conditions {
        case .thunderstorm, .heavyRain:
            score -= 6
        case .lightRain, .drizzle:
            score -= 3
        case .fog:
            score -= 2
        case .snow:
            score = 0
        case .overcast:
            score -= 1
        case .sunny, .partlyCloudy:
            break
        }
        
        return max(0, min(10, score))
    }
}

struct DailyWeatherForecast: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let highTemperature: Double
    let lowTemperature: Double
    let humidity: Double
    let windSpeed: Double
    let windDirection: String
    let precipitationChance: Double
    let precipitationAmount: Double
    let conditions: WeatherType
    let uvIndex: Int
    let sunrise: Date
    let sunset: Date
    
    var optimalGolfHours: [Int] {
        // Return hours of day (0-23) that are optimal for golf
        var optimalHours: [Int] = []
        
        // Basic optimal hours: morning and late afternoon
        let baseHours = [7, 8, 9, 10, 16, 17, 18]
        
        for hour in baseHours {
            var score = 10
            
            // Adjust for weather conditions
            if precipitationChance > 50 {
                score -= 5
            }
            
            if windSpeed > 20 {
                score -= 3
            }
            
            // Add temperature considerations
            let estimatedTemp = lowTemperature + ((highTemperature - lowTemperature) * Double(hour - 6) / 12.0)
            if estimatedTemp < 45 || estimatedTemp > 90 {
                score -= 2
            }
            
            if score >= 6 {
                optimalHours.append(hour)
            }
        }
        
        return optimalHours.sorted()
    }
}

struct GolfPlayabilityScore: Codable {
    let location: CLLocationCoordinate2D
    let timestamp: Date
    let overallScore: Int // 0-10
    let conditions: WeatherConditions
    let factors: PlayabilityFactors
    let recommendation: GolfRecommendation
    
    struct PlayabilityFactors: Codable {
        let temperatureScore: Int
        let windScore: Int
        let precipitationScore: Int
        let visibilityScore: Int
        let uvScore: Int
        let overallConditionsScore: Int
    }
}

struct OptimalTeeTime: Identifiable, Codable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let playabilityScore: Int
    let temperature: Double
    let windSpeed: Double
    let precipitationChance: Double
    let conditions: WeatherType
    let recommendation: String
    
    var timeSlot: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
}

struct WeatherAlert: Identifiable, Codable {
    let id = UUID()
    let title: String
    let description: String
    let severity: AlertSeverity
    let startTime: Date
    let endTime: Date?
    let golfImpact: GolfImpact
    
    enum AlertSeverity: String, CaseIterable, Codable {
        case minor = "minor"
        case moderate = "moderate"
        case severe = "severe"
        case extreme = "extreme"
        
        var color: String {
            switch self {
            case .minor: return "yellow"
            case .moderate: return "orange"
            case .severe: return "red"
            case .extreme: return "purple"
            }
        }
    }
    
    enum GolfImpact: String, CaseIterable, Codable {
        case minimal = "minimal"
        case moderate = "moderate"
        case significant = "significant"
        case prohibitive = "prohibitive"
        
        var description: String {
            switch self {
            case .minimal: return "Minor impact on golf play"
            case .moderate: return "May affect playing conditions"
            case .significant: return "Significant impact on play"
            case .prohibitive: return "Golf play not recommended"
            }
        }
    }
}

enum GolfRecommendation: String, CaseIterable, Codable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case dangerous = "dangerous"
    
    var title: String {
        switch self {
        case .excellent: return "Perfect Golf Weather!"
        case .good: return "Great for Golf"
        case .fair: return "Fair Playing Conditions"
        case .poor: return "Challenging Conditions"
        case .dangerous: return "Unsafe for Golf"
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "Ideal conditions for a great round"
        case .good: return "Good weather for golf"
        case .fair: return "Playable with some challenges"
        case .poor: return "Consider postponing your round"
        case .dangerous: return "Do not play golf in these conditions"
        }
    }
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "yellow"
        case .poor: return "orange"
        case .dangerous: return "red"
        }
    }
}

// MARK: - Weather Service Implementation

@MainActor
class WeatherService: WeatherServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isMonitoringWeather: Bool = false
    
    // MARK: - Private Properties
    
    private let weatherService = Foundation.WeatherService.shared
    private var monitoringLocation: CLLocationCoordinate2D?
    private var weatherMonitoringTimer: Timer?
    
    // Caching
    private let weatherCache = NSCache<NSString, CachedWeatherData>()
    private let forecastCache = NSCache<NSString, CachedForecastData>()
    private let cacheValidityDuration: TimeInterval = 600 // 10 minutes
    
    // Performance optimization
    private let backgroundQueue = DispatchQueue(label: "WeatherServiceQueue", qos: .utility)
    
    // MARK: - Cache Data Structures
    
    private class CachedWeatherData: NSObject {
        let weather: WeatherConditions
        let timestamp: Date
        let location: CLLocationCoordinate2D
        
        init(weather: WeatherConditions, location: CLLocationCoordinate2D) {
            self.weather = weather
            self.timestamp = Date()
            self.location = location
        }
        
        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < 600 // 10 minutes
        }
    }
    
    private class CachedForecastData: NSObject {
        let hourlyForecast: [HourlyWeatherForecast]
        let dailyForecast: [DailyWeatherForecast]
        let timestamp: Date
        let location: CLLocationCoordinate2D
        
        init(hourly: [HourlyWeatherForecast], daily: [DailyWeatherForecast], location: CLLocationCoordinate2D) {
            self.hourlyForecast = hourly
            self.dailyForecast = daily
            self.timestamp = Date()
            self.location = location
        }
        
        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < 1800 // 30 minutes for forecasts
        }
    }
    
    // MARK: - Initialization
    
    init() {
        setupCache()
    }
    
    private func setupCache() {
        weatherCache.countLimit = 100
        weatherCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        
        forecastCache.countLimit = 50
        forecastCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }
    
    // MARK: - Current Weather Implementation
    
    func getCurrentWeather(for location: CLLocationCoordinate2D) async throws -> WeatherConditions {
        let cacheKey = "\(location.latitude)_\(location.longitude)" as NSString
        
        // Check cache first
        if let cachedData = weatherCache.object(forKey: cacheKey), cachedData.isValid {
            return cachedData.weather
        }
        
        do {
            let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let weather = try await weatherService.weather(for: clLocation)
            
            let weatherConditions = WeatherConditions(
                temperature: weather.currentWeather.temperature.value,
                humidity: weather.currentWeather.humidity * 100,
                windSpeed: weather.currentWeather.wind.speed.value * 2.237, // Convert m/s to mph
                windDirection: windDirectionToString(weather.currentWeather.wind.direction.value),
                precipitation: 0.0, // Current weather doesn't include precipitation amount
                conditions: mapWeatherCondition(weather.currentWeather.condition),
                visibility: weather.currentWeather.visibility?.value ?? 10.0,
                uvIndex: weather.currentWeather.uvIndex.value,
                sunrise: formatTimeFromDate(weather.dailyForecast.first?.sun.sunrise ?? Date()),
                sunset: formatTimeFromDate(weather.dailyForecast.first?.sun.sunset ?? Date())
            )
            
            // Cache the result
            let cachedData = CachedWeatherData(weather: weatherConditions, location: location)
            weatherCache.setObject(cachedData, forKey: cacheKey)
            
            return weatherConditions
            
        } catch {
            print("Error fetching weather data: \(error)")
            throw WeatherError.fetchFailed(error.localizedDescription)
        }
    }
    
    func getWeatherForGolfCourse(_ course: GolfCourse) async throws -> WeatherConditions {
        let location = CLLocationCoordinate2D(latitude: course.latitude, longitude: course.longitude)
        return try await getCurrentWeather(for: location)
    }
    
    // MARK: - Weather Forecasts Implementation
    
    func getHourlyForecast(for location: CLLocationCoordinate2D, hours: Int) async throws -> [HourlyWeatherForecast] {
        let cacheKey = "hourly_\(location.latitude)_\(location.longitude)_\(hours)" as NSString
        
        // Check cache first
        if let cachedData = forecastCache.object(forKey: cacheKey), cachedData.isValid {
            return Array(cachedData.hourlyForecast.prefix(hours))
        }
        
        do {
            let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let weather = try await weatherService.weather(for: clLocation)
            
            let hourlyForecasts = weather.hourlyForecast.prefix(hours).map { hourWeather in
                HourlyWeatherForecast(
                    date: hourWeather.date,
                    temperature: hourWeather.temperature.value,
                    humidity: hourWeather.humidity * 100,
                    windSpeed: hourWeather.wind.speed.value * 2.237, // m/s to mph
                    windDirection: windDirectionToString(hourWeather.wind.direction.value),
                    precipitationChance: hourWeather.precipitationChance * 100,
                    precipitationAmount: hourWeather.precipitationAmount.value * 0.0394, // mm to inches
                    conditions: mapWeatherCondition(hourWeather.condition),
                    uvIndex: hourWeather.uvIndex.value,
                    visibility: hourWeather.visibility?.value ?? 10.0
                )
            }
            
            let dailyForecasts = weather.dailyForecast.prefix(7).map { dayWeather in
                DailyWeatherForecast(
                    date: dayWeather.date,
                    highTemperature: dayWeather.highTemperature.value,
                    lowTemperature: dayWeather.lowTemperature.value,
                    humidity: (dayWeather.humidity ?? 0.5) * 100,
                    windSpeed: dayWeather.wind.speed.value * 2.237,
                    windDirection: windDirectionToString(dayWeather.wind.direction.value),
                    precipitationChance: dayWeather.precipitationChance * 100,
                    precipitationAmount: dayWeather.precipitationAmount.value * 0.0394,
                    conditions: mapWeatherCondition(dayWeather.condition),
                    uvIndex: dayWeather.uvIndex.value,
                    sunrise: dayWeather.sun.sunrise ?? Date(),
                    sunset: dayWeather.sun.sunset ?? Date()
                )
            }
            
            // Cache the results
            let cachedData = CachedForecastData(
                hourly: Array(hourlyForecasts),
                daily: Array(dailyForecasts),
                location: location
            )
            forecastCache.setObject(cachedData, forKey: cacheKey)
            
            return Array(hourlyForecasts)
            
        } catch {
            print("Error fetching hourly forecast: \(error)")
            throw WeatherError.forecastFailed(error.localizedDescription)
        }
    }
    
    func getDailyForecast(for location: CLLocationCoordinate2D, days: Int) async throws -> [DailyWeatherForecast] {
        let cacheKey = "daily_\(location.latitude)_\(location.longitude)_\(days)" as NSString
        
        // Check if we have cached forecast data
        if let cachedData = forecastCache.object(forKey: cacheKey), cachedData.isValid {
            return Array(cachedData.dailyForecast.prefix(days))
        }
        
        // If no cached data, fetch fresh data (this will also cache it)
        _ = try await getHourlyForecast(for: location, hours: 24) // This caches both hourly and daily
        
        // Now get from cache
        if let cachedData = forecastCache.object(forKey: cacheKey) {
            return Array(cachedData.dailyForecast.prefix(days))
        }
        
        throw WeatherError.forecastFailed("Failed to get daily forecast")
    }
    
    // MARK: - Golf-Specific Weather Analysis
    
    func getGolfPlayabilityScore(for location: CLLocationCoordinate2D) async throws -> GolfPlayabilityScore {
        let currentWeather = try await getCurrentWeather(for: location)
        
        let factors = GolfPlayabilityScore.PlayabilityFactors(
            temperatureScore: calculateTemperatureScore(currentWeather.temperature),
            windScore: calculateWindScore(currentWeather.windSpeed),
            precipitationScore: calculatePrecipitationScore(currentWeather.conditions),
            visibilityScore: calculateVisibilityScore(currentWeather.visibility),
            uvScore: calculateUVScore(currentWeather.uvIndex),
            overallConditionsScore: calculateOverallConditionsScore(currentWeather.conditions)
        )
        
        let overallScore = (factors.temperatureScore + factors.windScore + factors.precipitationScore + 
                           factors.visibilityScore + factors.uvScore + factors.overallConditionsScore) / 6
        
        let recommendation = determineGolfRecommendation(score: overallScore, weather: currentWeather)
        
        return GolfPlayabilityScore(
            location: location,
            timestamp: Date(),
            overallScore: overallScore,
            conditions: currentWeather,
            factors: factors,
            recommendation: recommendation
        )
    }
    
    func getOptimalTeeTimesForDay(location: CLLocationCoordinate2D, date: Date) async throws -> [OptimalTeeTime] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        
        let hourlyForecast = try await getHourlyForecast(for: location, hours: 24)
        
        var optimalTimes: [OptimalTeeTime] = []
        
        // Check each hour from 6 AM to 7 PM for optimal tee times
        for hour in 6...19 {
            guard let teeTime = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date),
                  let endTime = calendar.date(byAdding: .hour, value: 4, to: teeTime), // Assume 4-hour round
                  teeTime >= Date() else { continue } // Skip past times
            
            // Find the relevant hourly forecast
            let relevantForecasts = hourlyForecast.filter { forecast in
                forecast.date >= teeTime && forecast.date <= endTime
            }
            
            guard !relevantForecasts.isEmpty else { continue }
            
            // Calculate average conditions for the round
            let avgTemp = relevantForecasts.map { $0.temperature }.reduce(0, +) / Double(relevantForecasts.count)
            let maxWind = relevantForecasts.map { $0.windSpeed }.max() ?? 0
            let maxPrecipChance = relevantForecasts.map { $0.precipitationChance }.max() ?? 0
            
            // Get the most severe weather condition
            let worstCondition = relevantForecasts.min { forecast1, forecast2 in
                forecast1.golfPlayabilityScore < forecast2.golfPlayabilityScore
            }?.conditions ?? .sunny
            
            // Calculate playability score for this tee time
            let playabilityScore = calculateTeeTimePlayabilityScore(
                temperature: avgTemp,
                windSpeed: maxWind,
                precipitationChance: maxPrecipChance,
                conditions: worstCondition
            )
            
            let recommendation = generateTeeTimeRecommendation(
                score: playabilityScore,
                temperature: avgTemp,
                windSpeed: maxWind,
                precipitationChance: maxPrecipChance
            )
            
            let optimalTeeTime = OptimalTeeTime(
                startTime: teeTime,
                endTime: endTime,
                playabilityScore: playabilityScore,
                temperature: avgTemp,
                windSpeed: maxWind,
                precipitationChance: maxPrecipChance,
                conditions: worstCondition,
                recommendation: recommendation
            )
            
            optimalTimes.append(optimalTeeTime)
        }
        
        // Sort by playability score (best first)
        return optimalTimes.sorted { $0.playabilityScore > $1.playabilityScore }
    }
    
    func getWeatherAlerts(for location: CLLocationCoordinate2D) async throws -> [WeatherAlert] {
        do {
            let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let weather = try await weatherService.weather(for: clLocation)
            
            // Convert WeatherKit alerts to our weather alerts
            let weatherAlerts = weather.weatherAlerts?.compactMap { alert -> WeatherAlert? in
                let severity = mapAlertSeverity(alert.severity)
                let golfImpact = determineGolfImpact(for: alert, severity: severity)
                
                return WeatherAlert(
                    title: alert.summary,
                    description: alert.detailsURL?.absoluteString ?? alert.summary,
                    severity: severity,
                    startTime: alert.issuedDate,
                    endTime: alert.expireDate,
                    golfImpact: golfImpact
                )
            } ?? []
            
            return weatherAlerts
            
        } catch {
            print("Error fetching weather alerts: \(error)")
            return [] // Return empty array instead of throwing for alerts
        }
    }
    
    // MARK: - Weather Monitoring
    
    func startWeatherMonitoring(for location: CLLocationCoordinate2D) {
        monitoringLocation = location
        isMonitoringWeather = true
        
        // Start periodic weather updates
        weatherMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateMonitoredWeather()
            }
        }
        
        // Get initial weather update
        Task {
            await updateMonitoredWeather()
        }
    }
    
    func stopWeatherMonitoring() {
        monitoringLocation = nil
        isMonitoringWeather = false
        weatherMonitoringTimer?.invalidate()
        weatherMonitoringTimer = nil
    }
    
    private func updateMonitoredWeather() async {
        guard let location = monitoringLocation else { return }
        
        do {
            _ = try await getCurrentWeather(for: location)
            // Weather is automatically cached, so we don't need to store it separately
        } catch {
            print("Error updating monitored weather: \(error)")
        }
    }
    
    // MARK: - Cache Management
    
    func getCachedWeather(for location: CLLocationCoordinate2D) -> WeatherConditions? {
        let cacheKey = "\(location.latitude)_\(location.longitude)" as NSString
        
        if let cachedData = weatherCache.object(forKey: cacheKey), cachedData.isValid {
            return cachedData.weather
        }
        
        return nil
    }
    
    func clearWeatherCache() {
        weatherCache.removeAllObjects()
        forecastCache.removeAllObjects()
    }
}

// MARK: - Private Helper Methods

private extension WeatherService {
    
    func mapWeatherCondition(_ condition: WeatherCondition) -> WeatherType {
        switch condition {
        case .clear, .mostlyClear:
            return .sunny
        case .partlyCloudy, .mostlyCloudyDay, .mostlyCloudyNight:
            return .partlyCloudy
        case .cloudy, .overcast:
            return .overcast
        case .drizzle:
            return .drizzle
        case .rain, .isolatedThunderstorms, .scatteredThunderstorms:
            return .lightRain
        case .heavyRain, .thunderstorms:
            return .heavyRain
        case .fog, .haze:
            return .fog
        case .snow, .blizzard, .heavySnow, .flurries:
            return .snow
        default:
            return .partlyCloudy
        }
    }
    
    func windDirectionToString(_ degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", 
                         "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5) % 16
        return directions[index]
    }
    
    func formatTimeFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    func calculateTemperatureScore(_ temperature: Double) -> Int {
        if temperature >= 65 && temperature <= 80 {
            return 10 // Perfect golf temperature
        } else if temperature >= 55 && temperature <= 90 {
            return 8  // Good golf temperature
        } else if temperature >= 45 && temperature <= 95 {
            return 6  // Fair golf temperature
        } else if temperature >= 35 && temperature <= 100 {
            return 4  // Poor golf temperature
        } else {
            return 2  // Very poor golf temperature
        }
    }
    
    func calculateWindScore(_ windSpeed: Double) -> Int {
        if windSpeed <= 5 {
            return 10 // Calm conditions
        } else if windSpeed <= 10 {
            return 8  // Light breeze
        } else if windSpeed <= 15 {
            return 6  // Moderate wind
        } else if windSpeed <= 25 {
            return 4  // Strong wind
        } else {
            return 2  // Very strong wind
        }
    }
    
    func calculatePrecipitationScore(_ conditions: WeatherType) -> Int {
        switch conditions {
        case .sunny, .partlyCloudy:
            return 10
        case .overcast:
            return 8
        case .fog:
            return 6
        case .drizzle:
            return 4
        case .lightRain:
            return 2
        case .heavyRain, .thunderstorm, .snow:
            return 0
        }
    }
    
    func calculateVisibilityScore(_ visibility: Double) -> Int {
        if visibility >= 10 {
            return 10 // Excellent visibility
        } else if visibility >= 5 {
            return 8  // Good visibility
        } else if visibility >= 2 {
            return 6  // Fair visibility
        } else if visibility >= 1 {
            return 4  // Poor visibility
        } else {
            return 2  // Very poor visibility
        }
    }
    
    func calculateUVScore(_ uvIndex: Int) -> Int {
        if uvIndex <= 2 {
            return 10 // Low UV
        } else if uvIndex <= 5 {
            return 9  // Moderate UV
        } else if uvIndex <= 7 {
            return 7  // High UV
        } else if uvIndex <= 10 {
            return 5  // Very high UV
        } else {
            return 3  // Extreme UV
        }
    }
    
    func calculateOverallConditionsScore(_ conditions: WeatherType) -> Int {
        switch conditions {
        case .sunny:
            return 10
        case .partlyCloudy:
            return 9
        case .overcast:
            return 7
        case .fog:
            return 5
        case .drizzle:
            return 4
        case .lightRain:
            return 2
        case .heavyRain, .thunderstorm:
            return 0
        case .snow:
            return 0
        }
    }
    
    func determineGolfRecommendation(score: Int, weather: WeatherConditions) -> GolfRecommendation {
        switch score {
        case 9...10:
            return .excellent
        case 7...8:
            return .good
        case 5...6:
            return .fair
        case 3...4:
            return .poor
        default:
            return .dangerous
        }
    }
    
    func calculateTeeTimePlayabilityScore(temperature: Double, windSpeed: Double, precipitationChance: Double, conditions: WeatherType) -> Int {
        var score = 10
        
        // Temperature adjustments
        if temperature < 40 || temperature > 95 {
            score -= 4
        } else if temperature < 50 || temperature > 85 {
            score -= 2
        }
        
        // Wind adjustments
        if windSpeed > 25 {
            score -= 4
        } else if windSpeed > 15 {
            score -= 2
        }
        
        // Precipitation adjustments
        if precipitationChance > 70 {
            score -= 5
        } else if precipitationChance > 40 {
            score -= 3
        } else if precipitationChance > 20 {
            score -= 1
        }
        
        // Weather condition adjustments
        switch conditions {
        case .thunderstorm, .heavyRain, .snow:
            score -= 6
        case .lightRain, .drizzle:
            score -= 3
        case .fog:
            score -= 2
        case .overcast:
            score -= 1
        case .sunny, .partlyCloudy:
            break
        }
        
        return max(0, min(10, score))
    }
    
    func generateTeeTimeRecommendation(score: Int, temperature: Double, windSpeed: Double, precipitationChance: Double) -> String {
        switch score {
        case 9...10:
            return "Perfect conditions for golf!"
        case 7...8:
            return "Great weather for your round"
        case 5...6:
            if temperature < 50 {
                return "Bundle up - it'll be chilly"
            } else if windSpeed > 15 {
                return "Expect windy conditions"
            } else if precipitationChance > 20 {
                return "Keep an eye on the sky"
            } else {
                return "Decent conditions overall"
            }
        case 3...4:
            return "Consider rescheduling if possible"
        default:
            return "Not recommended for golf"
        }
    }
    
    func mapAlertSeverity(_ severity: WeatherSeverity) -> WeatherAlert.AlertSeverity {
        switch severity {
        case .minor:
            return .minor
        case .moderate:
            return .moderate
        case .severe:
            return .severe
        case .extreme:
            return .extreme
        @unknown default:
            return .moderate
        }
    }
    
    func determineGolfImpact(for alert: WeatherAlertSummary, severity: WeatherAlert.AlertSeverity) -> WeatherAlert.GolfImpact {
        let summary = alert.summary.lowercased()
        
        if summary.contains("tornado") || summary.contains("hurricane") || summary.contains("severe thunderstorm") {
            return .prohibitive
        } else if summary.contains("flood") || summary.contains("high wind") || summary.contains("storm") {
            return .significant
        } else if summary.contains("rain") || summary.contains("snow") || summary.contains("fog") {
            return .moderate
        } else {
            return .minimal
        }
    }
}

// MARK: - Mock Weather Service

class MockWeatherService: WeatherServiceProtocol, ObservableObject {
    
    @Published var isMonitoringWeather: Bool = false
    
    private var mockWeatherData: [String: WeatherConditions] = [:]
    private var monitoringTimer: Timer?
    
    init() {
        setupMockData()
    }
    
    func getCurrentWeather(for location: CLLocationCoordinate2D) async throws -> WeatherConditions {
        let key = "\(location.latitude)_\(location.longitude)"
        
        if let weather = mockWeatherData[key] {
            return weather
        }
        
        // Return default mock weather
        return WeatherConditions(
            temperature: 75.0,
            humidity: 45.0,
            windSpeed: 8.0,
            windDirection: "SW",
            precipitation: 0.0,
            conditions: .partlyCloudy,
            visibility: 10.0,
            uvIndex: 6,
            sunrise: "06:30",
            sunset: "19:45"
        )
    }
    
    func getWeatherForGolfCourse(_ course: GolfCourse) async throws -> WeatherConditions {
        let location = CLLocationCoordinate2D(latitude: course.latitude, longitude: course.longitude)
        return try await getCurrentWeather(for: location)
    }
    
    func getHourlyForecast(for location: CLLocationCoordinate2D, hours: Int) async throws -> [HourlyWeatherForecast] {
        var forecasts: [HourlyWeatherForecast] = []
        
        for i in 0..<hours {
            let date = Calendar.current.date(byAdding: .hour, value: i, to: Date()) ?? Date()
            let forecast = HourlyWeatherForecast(
                date: date,
                temperature: 75.0 + Double.random(in: -10...10),
                humidity: 45.0 + Double.random(in: -15...15),
                windSpeed: 8.0 + Double.random(in: -5...10),
                windDirection: ["N", "NE", "E", "SE", "S", "SW", "W", "NW"].randomElement() ?? "SW",
                precipitationChance: Double.random(in: 0...30),
                precipitationAmount: 0.0,
                conditions: [WeatherType.sunny, .partlyCloudy, .overcast].randomElement() ?? .partlyCloudy,
                uvIndex: Int.random(in: 3...8),
                visibility: 10.0
            )
            forecasts.append(forecast)
        }
        
        return forecasts
    }
    
    func getDailyForecast(for location: CLLocationCoordinate2D, days: Int) async throws -> [DailyWeatherForecast] {
        var forecasts: [DailyWeatherForecast] = []
        
        for i in 0..<days {
            let date = Calendar.current.date(byAdding: .day, value: i, to: Date()) ?? Date()
            let forecast = DailyWeatherForecast(
                date: date,
                highTemperature: 80.0 + Double.random(in: -10...15),
                lowTemperature: 60.0 + Double.random(in: -10...10),
                humidity: 50.0,
                windSpeed: 10.0,
                windDirection: "SW",
                precipitationChance: Double.random(in: 0...40),
                precipitationAmount: 0.0,
                conditions: [WeatherType.sunny, .partlyCloudy, .overcast].randomElement() ?? .sunny,
                uvIndex: Int.random(in: 4...9),
                sunrise: Date(),
                sunset: Date()
            )
            forecasts.append(forecast)
        }
        
        return forecasts
    }
    
    func getGolfPlayabilityScore(for location: CLLocationCoordinate2D) async throws -> GolfPlayabilityScore {
        let weather = try await getCurrentWeather(for: location)
        
        return GolfPlayabilityScore(
            location: location,
            timestamp: Date(),
            overallScore: 8,
            conditions: weather,
            factors: GolfPlayabilityScore.PlayabilityFactors(
                temperatureScore: 9,
                windScore: 8,
                precipitationScore: 10,
                visibilityScore: 10,
                uvScore: 7,
                overallConditionsScore: 8
            ),
            recommendation: .good
        )
    }
    
    func getOptimalTeeTimesForDay(location: CLLocationCoordinate2D, date: Date) async throws -> [OptimalTeeTime] {
        var teeTimes: [OptimalTeeTime] = []
        
        for hour in [8, 10, 14, 16] {
            let startTime = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
            let endTime = Calendar.current.date(byAdding: .hour, value: 4, to: startTime) ?? date
            
            let optimal = OptimalTeeTime(
                startTime: startTime,
                endTime: endTime,
                playabilityScore: Int.random(in: 6...10),
                temperature: 75.0 + Double.random(in: -5...5),
                windSpeed: 8.0 + Double.random(in: -3...7),
                precipitationChance: Double.random(in: 0...20),
                conditions: .partlyCloudy,
                recommendation: "Good conditions for golf"
            )
            
            teeTimes.append(optimal)
        }
        
        return teeTimes.sorted { $0.playabilityScore > $1.playabilityScore }
    }
    
    func getWeatherAlerts(for location: CLLocationCoordinate2D) async throws -> [WeatherAlert] {
        // Usually no alerts in mock data
        return []
    }
    
    func startWeatherMonitoring(for location: CLLocationCoordinate2D) {
        isMonitoringWeather = true
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            // Mock periodic updates
        }
    }
    
    func stopWeatherMonitoring() {
        isMonitoringWeather = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    func getCachedWeather(for location: CLLocationCoordinate2D) -> WeatherConditions? {
        let key = "\(location.latitude)_\(location.longitude)"
        return mockWeatherData[key]
    }
    
    func clearWeatherCache() {
        mockWeatherData.removeAll()
    }
    
    private func setupMockData() {
        // San Francisco
        mockWeatherData["37.7749_-122.4194"] = WeatherConditions(
            temperature: 68.0, humidity: 55.0, windSpeed: 12.0, windDirection: "W",
            precipitation: 0.0, conditions: .partlyCloudy, visibility: 10.0,
            uvIndex: 6, sunrise: "06:45", sunset: "19:30"
        )
        
        // Phoenix
        mockWeatherData["33.4484_-112.0740"] = WeatherConditions(
            temperature: 85.0, humidity: 25.0, windSpeed: 6.0, windDirection: "E",
            precipitation: 0.0, conditions: .sunny, visibility: 10.0,
            uvIndex: 9, sunrise: "06:00", sunset: "19:00"
        )
        
        // Miami
        mockWeatherData["25.7617_-80.1918"] = WeatherConditions(
            temperature: 82.0, humidity: 75.0, windSpeed: 15.0, windDirection: "SE",
            precipitation: 0.1, conditions: .partlyCloudy, visibility: 8.0,
            uvIndex: 8, sunrise: "06:30", sunset: "19:45"
        )
    }
}

// MARK: - Weather Error Types

enum WeatherError: Error, LocalizedError {
    case fetchFailed(String)
    case forecastFailed(String)
    case locationUnavailable
    case apiKeyMissing
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed(let message):
            return "Failed to fetch weather data: \(message)"
        case .forecastFailed(let message):
            return "Failed to get weather forecast: \(message)"
        case .locationUnavailable:
            return "Location not available for weather data"
        case .apiKeyMissing:
            return "Weather API key is missing"
        case .rateLimitExceeded:
            return "Weather API rate limit exceeded"
        }
    }
}

// MARK: - WeatherKit Extensions

extension WeatherConditions {
    
    /// Check if current weather conditions are suitable for golf
    var isSuitableForGolf: Bool {
        return playabilityScore >= 6
    }
    
    /// Get a short weather summary for golfers
    var golfSummary: String {
        let tempDesc = formattedTemperature
        let windDesc = windSpeed > 15 ? "Windy" : "Light winds"
        let condDesc = conditions.displayName
        
        return "\(tempDesc), \(condDesc), \(windDesc)"
    }
}

extension WeatherType {
    
    /// Golf-specific impact description
    var golfImpact: String {
        switch self {
        case .sunny:
            return "Perfect golf weather"
        case .partlyCloudy:
            return "Great for golf"
        case .overcast:
            return "Good golf conditions"
        case .lightRain:
            return "May affect play"
        case .heavyRain, .thunderstorm:
            return "Not suitable for golf"
        case .drizzle:
            return "Playable with rain gear"
        case .fog:
            return "Limited visibility"
        case .snow:
            return "Course likely closed"
        }
    }
}