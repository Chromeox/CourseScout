#!/usr/bin/env swift

import Foundation

// MARK: - Watch Architecture Validation Script

print("🔍 Starting Apple Watch App Architecture Validation")
print(String(repeating: "=", count: 60))

var validationErrors: [String] = []
var validationWarnings: [String] = []
var validationSuccess: [String] = []

// MARK: - File System Validation

func validateFileExists(_ path: String, description: String) -> Bool {
    let fileManager = FileManager.default
    let exists = fileManager.fileExists(atPath: path)
    
    if exists {
        validationSuccess.append("✅ \(description): \(path)")
        return true
    } else {
        validationErrors.append("❌ Missing \(description): \(path)")
        return false
    }
}

func validateDirectoryStructure() {
    print("\n📁 Validating Watch App Directory Structure")
    print(String(repeating: "-", count: 40))
    
    let watchStructure = [
        ("GolfFinderWatch/", "Watch App Root Directory"),
        ("GolfFinderWatch/Services/", "Watch Services Directory"),
        ("GolfFinderWatch/Views/", "Watch Views Directory"),
        ("Sources/SharedGolfModels/", "Shared Models Directory")
    ]
    
    for (path, description) in watchStructure {
        _ = validateFileExists(path, description: description)
    }
}

func validateCoreWatchFiles() {
    print("\n🏗️ Validating Core Watch App Files")
    print(String(repeating: "-", count: 40))
    
    let coreFiles = [
        // Watch Views
        ("GolfFinderWatch/Views/WatchNavigationView.swift", "Main Watch Navigation"),
        ("GolfFinderWatch/Views/CurrentHoleView.swift", "Current Hole View"),
        ("GolfFinderWatch/Views/QuickScoreView.swift", "Quick Score Entry"),
        ("GolfFinderWatch/Views/CraftTimerWatchView.swift", "Craft Timer View"),
        ("GolfFinderWatch/Views/BreathingGuideView.swift", "Breathing Guide"),
        ("GolfFinderWatch/Views/WatchComplicationsProvider.swift", "Watch Complications"),
        
        // Watch Services
        ("GolfFinderWatch/Services/WatchConnectivityService.swift", "Watch Connectivity Service"),
        ("GolfFinderWatch/Services/WatchLocationService.swift", "Watch Location Service"),
        ("GolfFinderWatch/Services/WatchNotificationService.swift", "Watch Notification Service"),
        ("GolfFinderWatch/Services/WatchBatteryOptimizationService.swift", "Battery Optimization Service"),
        ("GolfFinderWatch/Services/WatchServiceContainer.swift", "Watch Service Container"),
        
        // Shared Models
        ("Sources/SharedGolfModels/SharedGolfCourse.swift", "Shared Golf Course Model"),
        ("Sources/SharedGolfModels/SharedScorecard.swift", "Shared Scorecard Model")
    ]
    
    var foundFiles = 0
    for (path, description) in coreFiles {
        if validateFileExists(path, description: description) {
            foundFiles += 1
        }
    }
    
    print("\nFound \(foundFiles) out of \(coreFiles.count) core files")
}

// MARK: - Architecture Pattern Validation

func validateMVVMPatterns() {
    print("\n🏛️ Validating MVVM Architecture Patterns")
    print(String(repeating: "-", count: 40))
    
    let watchViewFiles = [
        "GolfFinderWatch/Views/WatchNavigationView.swift",
        "GolfFinderWatch/Views/CurrentHoleView.swift", 
        "GolfFinderWatch/Views/CraftTimerWatchView.swift"
    ]
    
    for viewFile in watchViewFiles {
        if FileManager.default.fileExists(atPath: viewFile) {
            validateMVVMInFile(viewFile)
        }
    }
}

func validateMVVMInFile(_ filePath: String) {
    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
        validationErrors.append("❌ Could not read file: \(filePath)")
        return
    }
    
    let fileName = URL(fileURLWithPath: filePath).lastPathComponent
    
    // Check for service injection
    if content.contains("@WatchServiceInjected") {
        validationSuccess.append("✅ Service injection found in \(fileName)")
    } else if content.contains("@ServiceInjected") {
        validationSuccess.append("✅ Service injection found in \(fileName)")
    } else {
        validationWarnings.append("⚠️  No service injection found in \(fileName)")
    }
    
    // Check for proper state management
    if content.contains("@State") && content.contains("@Published") {
        validationSuccess.append("✅ Proper state management in \(fileName)")
    } else if content.contains("@State") {
        validationSuccess.append("✅ Basic state management in \(fileName)")
    } else {
        validationWarnings.append("⚠️  Limited state management in \(fileName)")
    }
    
    // Check for separation of concerns
    if content.contains("private func") && content.contains("private var") {
        validationSuccess.append("✅ Good encapsulation in \(fileName)")
    }
}

// MARK: - Service Architecture Validation

func validateServiceArchitecture() {
    print("\n🔧 Validating Watch Service Architecture")
    print(String(repeating: "-", count: 40))
    
    let serviceFiles = [
        "GolfFinderWatch/Services/WatchConnectivityService.swift",
        "GolfFinderWatch/Services/WatchLocationService.swift",
        "GolfFinderWatch/Services/WatchNotificationService.swift",
        "GolfFinderWatch/Services/WatchBatteryOptimizationService.swift"
    ]
    
    var protocolCount = 0
    var implementationCount = 0
    var mockCount = 0
    
    for serviceFile in serviceFiles {
        if FileManager.default.fileExists(atPath: serviceFile) {
            if let content = try? String(contentsOfFile: serviceFile, encoding: .utf8) {
                let fileName = URL(fileURLWithPath: serviceFile).lastPathComponent
                
                // Check for protocol definition
                if content.contains("protocol") && content.contains("ServiceProtocol") {
                    protocolCount += 1
                    validationSuccess.append("✅ Protocol defined in \(fileName)")
                }
                
                // Check for implementation
                if content.contains("class") && content.contains("Service:") {
                    implementationCount += 1
                    validationSuccess.append("✅ Implementation found in \(fileName)")
                }
                
                // Check for mock implementation
                if content.contains("Mock") || content.contains("mock") {
                    mockCount += 1
                    validationSuccess.append("✅ Mock implementation in \(fileName)")
                }
                
                // Check for dependency injection compliance
                if content.contains("@MainActor") {
                    validationSuccess.append("✅ MainActor compliance in \(fileName)")
                }
                
                // Check for proper error handling
                if content.contains("throw") && content.contains("Error") {
                    validationSuccess.append("✅ Error handling in \(fileName)")
                }
            }
        }
    }
    
    print("Service Architecture Summary:")
    print("- Protocols: \(protocolCount)")
    print("- Implementations: \(implementationCount)")
    print("- Mock Services: \(mockCount)")
}

// MARK: - Connectivity Validation

func validateWatchConnectivity() {
    print("\n📡 Validating Watch Connectivity Architecture")
    print(String(repeating: "-", count: 40))
    
    let connectivityFile = "GolfFinderWatch/Services/WatchConnectivityService.swift"
    
    if let content = try? String(contentsOfFile: connectivityFile, encoding: .utf8) {
        // Check for Watch Connectivity framework
        if content.contains("import WatchConnectivity") {
            validationSuccess.append("✅ WatchConnectivity framework imported")
        } else {
            validationErrors.append("❌ Missing WatchConnectivity framework import")
        }
        
        // Check for session management
        if content.contains("WCSession") {
            validationSuccess.append("✅ WCSession integration found")
        } else {
            validationErrors.append("❌ Missing WCSession integration")
        }
        
        // Check for delegate implementation
        if content.contains("WCSessionDelegate") {
            validationSuccess.append("✅ WCSessionDelegate implementation")
        } else {
            validationWarnings.append("⚠️  Missing WCSessionDelegate implementation")
        }
        
        // Check for data synchronization methods
        let syncMethods = [
            "sendMessage",
            "updateApplicationContext", 
            "transferUserInfo",
            "sendScoreUpdate",
            "sendCourseData"
        ]
        
        for method in syncMethods {
            if content.contains(method) {
                validationSuccess.append("✅ Sync method: \(method)")
            } else {
                validationWarnings.append("⚠️  Missing sync method: \(method)")
            }
        }
    }
}

// MARK: - HealthKit Integration Validation

func validateHealthKitIntegration() {
    print("\n❤️ Validating HealthKit Integration")
    print(String(repeating: "-", count: 40))
    
    let healthServiceFile = "GolfFinderWatch/Services/WatchHealthKitService.swift"
    
    if FileManager.default.fileExists(atPath: healthServiceFile) {
        if let content = try? String(contentsOfFile: healthServiceFile) {
            // Check for HealthKit framework
            if content.contains("import HealthKit") {
                validationSuccess.append("✅ HealthKit framework imported")
            } else {
                validationErrors.append("❌ Missing HealthKit framework import")
            }
            
            // Check for workout integration
            if content.contains("HKWorkout") {
                validationSuccess.append("✅ Workout session integration")
            }
            
            // Check for heart rate monitoring
            if content.contains("heartRate") || content.contains("HKQuantityType") {
                validationSuccess.append("✅ Heart rate monitoring capability")
            }
            
            // Check for authorization handling
            if content.contains("requestAuthorization") {
                validationSuccess.append("✅ HealthKit authorization handling")
            }
        }
    } else {
        validationWarnings.append("⚠️  HealthKit service file not found")
    }
}

// MARK: - Notification System Validation

func validateNotificationSystem() {
    print("\n🔔 Validating Notification System")
    print(String(repeating: "-", count: 40))
    
    let notificationFile = "GolfFinderWatch/Services/WatchNotificationService.swift"
    
    if let content = try? String(contentsOfFile: notificationFile) {
        // Check for UserNotifications framework
        if content.contains("import UserNotifications") {
            validationSuccess.append("✅ UserNotifications framework imported")
        } else {
            validationErrors.append("❌ Missing UserNotifications framework")
        }
        
        // Check for notification types
        let notificationTypes = [
            "scheduleTeeTimeReminder",
            "scheduleHoleMilestoneNotification",
            "scheduleScoreNotification",
            "scheduleCraftTimerMilestone",
            "scheduleHeartRateZoneNotification"
        ]
        
        var foundTypes = 0
        for type in notificationTypes {
            if content.contains(type) {
                foundTypes += 1
                validationSuccess.append("✅ Notification type: \(type)")
            }
        }
        
        print("Found \(foundTypes) out of \(notificationTypes.count) notification types")
        
        // Check for notification categories
        if content.contains("UNNotificationCategory") {
            validationSuccess.append("✅ Notification categories configured")
        }
    }
}

// MARK: - Performance Optimization Validation

func validatePerformanceOptimization() {
    print("\n⚡ Validating Performance Optimization")
    print(String(repeating: "-", count: 40))
    
    let performanceFile = "GolfFinderWatch/Services/WatchBatteryOptimizationService.swift"
    
    if let content = try? String(contentsOfFile: performanceFile) {
        // Check for battery monitoring
        if content.contains("WKInterfaceDevice") && content.contains("batteryLevel") {
            validationSuccess.append("✅ Battery monitoring implemented")
        } else {
            validationWarnings.append("⚠️  Limited battery monitoring")
        }
        
        // Check for performance modes
        if content.contains("WatchPerformanceMode") {
            validationSuccess.append("✅ Performance modes defined")
        }
        
        // Check for optimization strategies
        let optimizations = [
            "enableBatteryOptimization",
            "optimizeForGolfRound",
            "optimizeForCraftTimer",
            "adaptPerformance"
        ]
        
        for optimization in optimizations {
            if content.contains(optimization) {
                validationSuccess.append("✅ Optimization: \(optimization)")
            }
        }
    }
}

// MARK: - Cross-Device Coordination Validation

func validateCrossDeviceCoordination() {
    print("\n📱⌚ Validating Cross-Device Coordination")
    print(String(repeating: "-", count: 40))
    
    // Check shared models
    let sharedModels = [
        "Sources/SharedGolfModels/SharedGolfCourse.swift",
        "Sources/SharedGolfModels/SharedScorecard.swift"
    ]
    
    for modelFile in sharedModels {
        if FileManager.default.fileExists(atPath: modelFile) {
            if let content = try? String(contentsOfFile: modelFile) {
                let fileName = URL(fileURLWithPath: modelFile).lastPathComponent
                
                // Check for Codable compliance
                if content.contains("Codable") {
                    validationSuccess.append("✅ Codable compliance: \(fileName)")
                } else {
                    validationErrors.append("❌ Missing Codable compliance: \(fileName)")
                }
                
                // Check for Identifiable compliance
                if content.contains("Identifiable") {
                    validationSuccess.append("✅ Identifiable compliance: \(fileName)")
                }
                
                // Check for coordinate handling
                if content.contains("CLLocationCoordinate2D") {
                    validationSuccess.append("✅ Location coordinate support: \(fileName)")
                }
            }
        }
    }
    
    // Check for synchronization capabilities
    let connectivityFile = "GolfFinderWatch/Services/WatchConnectivityService.swift"
    if let content = try? String(contentsOfFile: connectivityFile, encoding: .utf8) {
        let syncCapabilities = [
            "sendScoreUpdate",
            "sendCourseData",
            "sendActiveRoundUpdate",
            "sendHealthMetricsUpdate"
        ]
        
        for capability in syncCapabilities {
            if content.contains(capability) {
                validationSuccess.append("✅ Sync capability: \(capability)")
            } else {
                validationWarnings.append("⚠️  Missing sync capability: \(capability)")
            }
        }
    }
}

// MARK: - UI/UX Validation

func validateWatchUIUX() {
    print("\n🎨 Validating Watch UI/UX Implementation")
    print(String(repeating: "-", count: 40))
    
    let navigationFile = "GolfFinderWatch/Views/WatchNavigationView.swift"
    
    if let content = try? String(contentsOfFile: navigationFile) {
        // Check for TabView implementation
        if content.contains("TabView") {
            validationSuccess.append("✅ TabView navigation implemented")
        } else {
            validationWarnings.append("⚠️  No TabView navigation found")
        }
        
        // Check for haptic feedback integration
        if content.contains("HapticFeedback") || content.contains("hapticService") {
            validationSuccess.append("✅ Haptic feedback integration")
        } else {
            validationWarnings.append("⚠️  Missing haptic feedback")
        }
        
        // Check for Digital Crown support
        if content.contains("digitalCrownRotation") || content.contains("DigitalCrown") {
            validationSuccess.append("✅ Digital Crown support")
        } else {
            validationWarnings.append("⚠️  Limited Digital Crown support")
        }
    }
    
    // Check complications
    let complicationsFile = "GolfFinderWatch/Views/WatchComplicationsProvider.swift"
    if let content = try? String(contentsOfFile: complicationsFile) {
        if content.contains("CLKComplicationDataSource") {
            validationSuccess.append("✅ Watch complications implemented")
        } else {
            validationWarnings.append("⚠️  No complications found")
        }
    }
}

// MARK: - Testing Infrastructure Validation

func validateTestingInfrastructure() {
    print("\n🧪 Validating Testing Infrastructure")
    print(String(repeating: "-", count: 40))
    
    let testFiles = [
        "Tests/WatchConnectivityServiceTests.swift",
        "Tests/WatchServiceContainerTests.swift",
        "Tests/WatchConnectivityIntegrationTests.swift"
    ]
    
    var foundTests = 0
    for testFile in testFiles {
        if FileManager.default.fileExists(atPath: testFile) {
            foundTests += 1
            let fileName = URL(fileURLWithPath: testFile).lastPathComponent
            validationSuccess.append("✅ Test file: \(fileName)")
            
            if let content = try? String(contentsOfFile: testFile) {
                // Check for XCTest import
                if content.contains("import XCTest") {
                    validationSuccess.append("✅ XCTest framework in \(fileName)")
                }
                
                // Check for mock usage
                if content.contains("Mock") || content.contains("mock") {
                    validationSuccess.append("✅ Mock testing in \(fileName)")
                }
            }
        }
    }
    
    print("Found \(foundTests) test files")
    
    // Check for mock services in implementation
    let serviceFiles = [
        "GolfFinderWatch/Services/WatchConnectivityService.swift",
        "GolfFinderWatch/Services/WatchServiceContainer.swift"
    ]
    
    for serviceFile in serviceFiles {
        if let content = try? String(contentsOfFile: serviceFile) {
            if content.contains("Mock") && content.contains("class") {
                let fileName = URL(fileURLWithPath: serviceFile).lastPathComponent
                validationSuccess.append("✅ Mock service in \(fileName)")
            }
        }
    }
}

// MARK: - Memory and Performance Validation

func validateMemoryManagement() {
    print("\n🧠 Validating Memory Management")
    print(String(repeating: "-", count: 40))
    
    let watchFiles = [
        "GolfFinderWatch/Views/WatchNavigationView.swift",
        "GolfFinderWatch/Services/WatchConnectivityService.swift",
        "GolfFinderWatch/Services/WatchLocationService.swift"
    ]
    
    for file in watchFiles {
        if let content = try? String(contentsOfFile: file, encoding: .utf8) {
            let fileName = URL(fileURLWithPath: file).lastPathComponent
            
            // Check for proper memory management
            if content.contains("weak") {
                validationSuccess.append("✅ Weak references in \(fileName)")
            }
            
            if content.contains("@MainActor") {
                validationSuccess.append("✅ MainActor usage in \(fileName)")
            }
            
            if content.contains("deinit") {
                validationSuccess.append("✅ Cleanup implementation in \(fileName)")
            }
            
            // Check for timer cleanup
            if content.contains("Timer") && content.contains("invalidate") {
                validationSuccess.append("✅ Timer cleanup in \(fileName)")
            }
        }
    }
}

// MARK: - Integration Points Validation

func validateIntegrationPoints() {
    print("\n🔗 Validating Integration Points")
    print(String(repeating: "-", count: 40))
    
    // Check service container integration
    let serviceContainer = "GolfFinderWatch/Services/WatchServiceContainer.swift"
    if let content = try? String(contentsOfFile: serviceContainer) {
        let requiredServices = [
            "WatchConnectivityService",
            "WatchLocationService", 
            "WatchNotificationService",
            "WatchHealthKitService",
            "WatchHapticFeedbackService"
        ]
        
        for service in requiredServices {
            if content.contains(service) {
                validationSuccess.append("✅ Service registered: \(service)")
            } else {
                validationWarnings.append("⚠️  Service not registered: \(service)")
            }
        }
    }
    
    // Check for proper dependency injection
    let watchViews = [
        "GolfFinderWatch/Views/WatchNavigationView.swift",
        "GolfFinderWatch/Views/CurrentHoleView.swift"
    ]
    
    for viewFile in watchViews {
        if let content = try? String(contentsOfFile: viewFile) {
            let fileName = URL(fileURLWithPath: viewFile).lastPathComponent
            
            if content.contains("@WatchServiceInjected") || content.contains("@ServiceInjected") {
                validationSuccess.append("✅ Dependency injection in \(fileName)")
            } else {
                validationWarnings.append("⚠️  No dependency injection in \(fileName)")
            }
        }
    }
}

// MARK: - Main Execution

func main() {
    validateDirectoryStructure()
    validateCoreWatchFiles()
    validateMVVMPatterns()
    validateServiceArchitecture() 
    validateWatchConnectivity()
    validateHealthKitIntegration()
    validateNotificationSystem()
    validatePerformanceOptimization()
    validateCrossDeviceCoordination()
    validateWatchUIUX()
    validateTestingInfrastructure()
    validateMemoryManagement()
    validateIntegrationPoints()
    
    // Print Summary
    print("\n" + String(repeating: "=", count: 60))
    print("🏁 APPLE WATCH ARCHITECTURE VALIDATION SUMMARY")
    print(String(repeating: "=", count: 60))
    
    print("\n✅ SUCCESSES (\(validationSuccess.count)):")
    for success in validationSuccess.prefix(20) {
        print(success)
    }
    if validationSuccess.count > 20 {
        print("... and \(validationSuccess.count - 20) more successes")
    }
    
    if !validationWarnings.isEmpty {
        print("\n⚠️  WARNINGS (\(validationWarnings.count)):")
        for warning in validationWarnings {
            print(warning)
        }
    }
    
    if !validationErrors.isEmpty {
        print("\n❌ ERRORS (\(validationErrors.count)):")
        for error in validationErrors {
            print(error)
        }
    }
    
    // Overall Assessment
    let totalIssues = validationErrors.count
    let totalWarnings = validationWarnings.count
    let totalSuccess = validationSuccess.count
    
    let completionScore = Double(totalSuccess) / Double(totalSuccess + totalWarnings + totalIssues) * 100
    
    print("\n📊 ARCHITECTURE ASSESSMENT:")
    print("- Success Items: \(totalSuccess)")
    print("- Warning Items: \(totalWarnings)")
    print("- Error Items: \(totalIssues)")
    print("- Completion Score: \(String(format: "%.1f", completionScore))%")
    
    if totalIssues == 0 && totalWarnings <= 5 {
        print("\n🎉 EXCELLENT: Apple Watch architecture is production-ready!")
        print("   The Watch app demonstrates enterprise-grade architecture with")
        print("   comprehensive service integration and cross-device coordination.")
    } else if totalIssues <= 2 && totalWarnings <= 10 {
        print("\n✅ GOOD: Apple Watch architecture is well-structured with minor issues.")
        print("   Ready for alpha testing with some improvements recommended.")
    } else if totalIssues <= 5 {
        print("\n⚠️  NEEDS IMPROVEMENT: Several issues need to be addressed.")
        print("   Architecture foundation is solid but requires refinement.")
    } else {
        print("\n❌ SIGNIFICANT ISSUES: Major architecture problems detected.")
        print("   Substantial work needed before production deployment.")
    }
    
    print("\n🏆 WINDOW 2: APPLE WATCH INTEGRATION - VALIDATION COMPLETE")
    print(String(repeating: "=", count: 60))
}

// Execute validation
main()