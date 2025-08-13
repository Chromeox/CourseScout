#!/usr/bin/env swift

import Foundation

// MARK: - Phase 4C Architecture Compliance Validation

struct ArchitectureValidationResult {
    let component: String
    let complianceScore: Int
    let issues: [String]
    let recommendations: [String]
    let isCompliant: Bool
    
    var status: String {
        return isCompliant ? "✅ COMPLIANT" : "❌ NON-COMPLIANT"
    }
}

class Phase4ArchitectureValidator {
    private var validationResults: [ArchitectureValidationResult] = []
    
    func validateArchitecture() {
        print("🔍 Phase 4C Architecture Compliance Validation")
        print("================================================\n")
        
        // Validate Phase 4A Components (Social Challenge UI)
        validateSocialChallengeArchitecture()
        
        // Validate Phase 4B Components (Revenue Features)
        validateRevenueArchitecture()
        
        // Validate Phase 4C Integration (ServiceContainer & Watch Coordination)
        validateIntegrationArchitecture()
        
        // Generate comprehensive report
        generateValidationReport()
    }
    
    // MARK: - Phase 4A Validation
    
    private func validateSocialChallengeArchitecture() {
        print("📱 Validating Phase 4A: Social Challenge UI Components")
        print("---------------------------------------------------")
        
        // Validate SocialChallengeCard
        validateComponent(
            name: "SocialChallengeCard",
            path: "GolfFinderApp/Views/Components/SocialChallengeCard.swift",
            expectedPatterns: [
                "@StateObject.*ViewModel",
                "@ServiceInjected",
                "struct.*View",
                "var body: some View"
            ]
        )
        
        // Validate ChallengeCreationView
        validateComponent(
            name: "ChallengeCreationView",
            path: "GolfFinderApp/Views/Challenges/ChallengeCreationView.swift",
            expectedPatterns: [
                "@StateObject.*ViewModel",
                "@ServiceInjected.*ServiceProtocol",
                "struct.*View",
                "private func.*Action"
            ]
        )
        
        // Validate SocialChallengeSynchronizedHapticService
        validateService(
            name: "SocialChallengeSynchronizedHapticService",
            path: "GolfFinderApp/Services/SocialChallengeSynchronizedHapticService.swift",
            protocolName: "SocialChallengeSynchronizedHapticServiceProtocol",
            expectedMethods: [
                "provideSynchronizedChallengeCompletion",
                "provideSynchronizedMilestoneReached",
                "provideSynchronizedPositionChange"
            ]
        )
        
        print()
    }
    
    // MARK: - Phase 4B Validation
    
    private func validateRevenueArchitecture() {
        print("💰 Validating Phase 4B: Revenue Features")
        print("---------------------------------------")
        
        // Validate SecurePaymentService
        validateService(
            name: "SecurePaymentService",
            path: "GolfFinderApp/Services/Revenue/SecurePaymentService.swift",
            protocolName: "SecurePaymentServiceProtocol",
            expectedMethods: [
                "processEntryFeePayment",
                "processBulkPayments",
                "validatePaymentSecurity",
                "detectFraudulentPayment"
            ]
        )
        
        // Validate MultiTenantRevenueAttributionService
        validateService(
            name: "MultiTenantRevenueAttributionService",
            path: "GolfFinderApp/Services/Revenue/MultiTenantRevenueAttributionService.swift",
            protocolName: "MultiTenantRevenueAttributionServiceProtocol",
            expectedMethods: [
                "attributeRevenue",
                "getRevenueAttribution",
                "calculateCommissions",
                "processRevenueSharing"
            ]
        )
        
        // Validate TournamentHostingView
        validateComponent(
            name: "TournamentHostingView",
            path: "GolfFinderApp/Views/Revenue/TournamentHostingView.swift",
            expectedPatterns: [
                "@StateObject.*TournamentHostingViewModel",
                "@ServiceInjected.*ServiceProtocol",
                "struct.*View",
                "private func.*"
            ]
        )
        
        // Validate MonetizedChallengeView
        validateComponent(
            name: "MonetizedChallengeView",
            path: "GolfFinderApp/Views/Revenue/MonetizedChallengeView.swift",
            expectedPatterns: [
                "@StateObject.*MonetizedChallengeViewModel",
                "@ServiceInjected.*ServiceProtocol",
                "struct.*View"
            ]
        )
        
        print()
    }
    
    // MARK: - Phase 4C Integration Validation
    
    private func validateIntegrationArchitecture() {
        print("🔧 Validating Phase 4C: Integration & Watch Coordination")
        print("-----------------------------------------------------")
        
        // Validate ServiceContainer Integration
        validateServiceContainerIntegration()
        
        // Validate Watch Views Integration
        validateWatchIntegration()
        
        // Validate Main Navigation Integration
        validateNavigationIntegration()
        
        print()
    }
    
    // MARK: - Specific Validation Methods
    
    private func validateServiceContainerIntegration() {
        let serviceContainerPath = "GolfFinderApp/Services/ServiceContainer.swift"
        var issues: [String] = []
        var recommendations: [String] = []
        
        guard let content = readFile(at: serviceContainerPath) else {
            issues.append("ServiceContainer.swift file not found")
            addValidationResult(name: "ServiceContainer Integration", score: 0, issues: issues, recommendations: recommendations)
            return
        }
        
        // Check for Phase 4 service registrations
        let requiredServices = [
            "SecurePaymentServiceProtocol",
            "MultiTenantRevenueAttributionServiceProtocol",
            "SocialChallengeSynchronizedHapticServiceProtocol"
        ]
        
        var registeredServices = 0
        for service in requiredServices {
            if content.contains("register(\\s*\(service)") {
                registeredServices += 1
                print("✅ \(service) properly registered")
            } else {
                issues.append("\(service) not registered in ServiceContainer")
                print("❌ \(service) missing from ServiceContainer")
            }
        }
        
        // Check for convenience methods
        let convenienceMethods = [
            "securePaymentService()",
            "multiTenantRevenueAttributionService()",
            "socialChallengeSynchronizedHapticService()"
        ]
        
        var convenienMethodsFound = 0
        for method in convenienceMethods {
            if content.contains(method) {
                convenienMethodsFound += 1
            } else {
                recommendations.append("Add convenience method: \(method)")
            }
        }
        
        // Check for preloading configuration
        if content.contains("\"SecurePaymentServiceProtocol\"") &&
           content.contains("\"MultiTenantRevenueAttributionServiceProtocol\"") &&
           content.contains("\"SocialChallengeSynchronizedHapticServiceProtocol\"") {
            print("✅ Phase 4 services added to preloading list")
        } else {
            issues.append("Phase 4 services not added to critical services preloading list")
        }
        
        let complianceScore = Int((Double(registeredServices + convenienMethodsFound) / Double(requiredServices.count + convenienceMethods.count)) * 100)
        
        addValidationResult(
            name: "ServiceContainer Integration",
            score: complianceScore,
            issues: issues,
            recommendations: recommendations
        )
    }
    
    private func validateWatchIntegration() {
        let watchTournamentPath = "GolfFinderWatch/Views/WatchTournamentMonitorView.swift"
        let watchChallengePath = "GolfFinderWatch/Views/WatchChallengeTrackingView.swift"
        
        var issues: [String] = []
        var recommendations: [String] = []
        var score = 0
        
        // Validate WatchTournamentMonitorView
        if let tournamentContent = readFile(at: watchTournamentPath) {
            if tournamentContent.contains("@StateObject private var synchronizedHapticService: SocialChallengeSynchronizedHapticService") {
                score += 25
                print("✅ WatchTournamentMonitorView: SynchronizedHapticService integrated")
            } else {
                issues.append("WatchTournamentMonitorView: SynchronizedHapticService not integrated")
            }
            
            if tournamentContent.contains("provideSynchronizedPositionChange") {
                score += 25
                print("✅ WatchTournamentMonitorView: Position change haptics integrated")
            } else {
                issues.append("WatchTournamentMonitorView: Synchronized position change haptics missing")
            }
        } else {
            issues.append("WatchTournamentMonitorView.swift not found")
        }
        
        // Validate WatchChallengeTrackingView
        if let challengeContent = readFile(at: watchChallengePath) {
            if challengeContent.contains("@StateObject private var synchronizedHapticService: SocialChallengeSynchronizedHapticService") {
                score += 25
                print("✅ WatchChallengeTrackingView: SynchronizedHapticService integrated")
            } else {
                issues.append("WatchChallengeTrackingView: SynchronizedHapticService not integrated")
            }
            
            if challengeContent.contains("provideSynchronizedChallengeCompletion") {
                score += 25
                print("✅ WatchChallengeTrackingView: Challenge completion haptics integrated")
            } else {
                issues.append("WatchChallengeTrackingView: Synchronized challenge completion haptics missing")
            }
        } else {
            issues.append("WatchChallengeTrackingView.swift not found")
        }
        
        addValidationResult(
            name: "Watch Integration",
            score: score,
            issues: issues,
            recommendations: recommendations
        )
    }
    
    private func validateNavigationIntegration() {
        let mainNavPath = "GolfFinderApp/Views/MainNavigationView.swift"
        
        var issues: [String] = []
        var recommendations: [String] = []
        var score = 0
        
        guard let content = readFile(at: mainNavPath) else {
            issues.append("MainNavigationView.swift not found")
            addValidationResult(name: "Navigation Integration", score: 0, issues: issues, recommendations: recommendations)
            return
        }
        
        // Check for Phase 4 service injections
        let requiredInjections = [
            "@ServiceInjected(SocialChallengeSynchronizedHapticServiceProtocol.self)",
            "@ServiceInjected(SecurePaymentServiceProtocol.self)",
            "@ServiceInjected(MultiTenantRevenueAttributionServiceProtocol.self)"
        ]
        
        var injectionsFound = 0
        for injection in requiredInjections {
            if content.contains(injection.replacingOccurrences(of: " ", with: "\\s*")) {
                injectionsFound += 1
                score += 20
            } else {
                issues.append("Missing service injection: \(injection)")
            }
        }
        
        // Check for tournament and challenge navigation
        if content.contains("showTournamentHosting") {
            score += 20
            print("✅ Tournament hosting navigation integrated")
        } else {
            issues.append("Tournament hosting navigation not integrated")
        }
        
        if content.contains("showChallengeCreation") {
            score += 20
            print("✅ Challenge creation navigation integrated")
        } else {
            issues.append("Challenge creation navigation not integrated")
        }
        
        addValidationResult(
            name: "Navigation Integration",
            score: score,
            issues: issues,
            recommendations: recommendations
        )
    }
    
    // MARK: - Component Validation
    
    private func validateComponent(name: String, path: String, expectedPatterns: [String]) {
        var issues: [String] = []
        var recommendations: [String] = []
        
        guard let content = readFile(at: path) else {
            issues.append("File not found at path: \(path)")
            addValidationResult(name: name, score: 0, issues: issues, recommendations: recommendations)
            return
        }
        
        var patternsFound = 0
        for pattern in expectedPatterns {
            if content.range(of: pattern, options: .regularExpression) != nil {
                patternsFound += 1
            } else {
                issues.append("Missing expected pattern: \(pattern)")
            }
        }
        
        // Check MVVM compliance
        if !content.contains("struct") || !content.contains("View") {
            issues.append("Not a proper SwiftUI View component")
        }
        
        if content.contains("@StateObject") && !content.contains("ViewModel") {
            recommendations.append("Consider using ViewModels for complex state management")
        }
        
        let complianceScore = Int((Double(patternsFound) / Double(expectedPatterns.count)) * 100)
        
        addValidationResult(
            name: name,
            score: complianceScore,
            issues: issues,
            recommendations: recommendations
        )
        
        print("  \(name): \(complianceScore)% compliant")
    }
    
    private func validateService(name: String, path: String, protocolName: String, expectedMethods: [String]) {
        var issues: [String] = []
        var recommendations: [String] = []
        
        guard let content = readFile(at: path) else {
            issues.append("File not found at path: \(path)")
            addValidationResult(name: name, score: 0, issues: issues, recommendations: recommendations)
            return
        }
        
        // Check protocol conformance
        if !content.contains(": \(protocolName)") {
            issues.append("Does not conform to \(protocolName)")
        }
        
        // Check dependency injection pattern
        if !content.contains("private let") && !content.contains("@ServiceInjected") {
            recommendations.append("Consider using dependency injection for dependencies")
        }
        
        // Check expected methods
        var methodsFound = 0
        for method in expectedMethods {
            if content.contains("func \(method)") {
                methodsFound += 1
            } else {
                issues.append("Missing expected method: \(method)")
            }
        }
        
        let complianceScore = Int((Double(methodsFound) / Double(expectedMethods.count)) * 100)
        
        addValidationResult(
            name: name,
            score: complianceScore,
            issues: issues,
            recommendations: recommendations
        )
        
        print("  \(name): \(complianceScore)% compliant")
    }
    
    // MARK: - Utility Methods
    
    private func readFile(at path: String) -> String? {
        let fullPath = FileManager.default.currentDirectoryPath + "/" + path
        return try? String(contentsOfFile: fullPath)
    }
    
    private func addValidationResult(name: String, score: Int, issues: [String], recommendations: [String]) {
        let result = ArchitectureValidationResult(
            component: name,
            complianceScore: score,
            issues: issues,
            recommendations: recommendations,
            isCompliant: score >= 80 // 80% threshold for compliance
        )
        validationResults.append(result)
    }
    
    // MARK: - Report Generation
    
    private func generateValidationReport() {
        print("\n🎯 Phase 4C Architecture Compliance Report")
        print("==========================================")
        
        let totalComponents = validationResults.count
        let compliantComponents = validationResults.filter { $0.isCompliant }.count
        let averageScore = validationResults.map { $0.complianceScore }.reduce(0, +) / max(totalComponents, 1)
        
        print("📊 Overall Statistics:")
        print("  Total Components: \(totalComponents)")
        print("  Compliant Components: \(compliantComponents)")
        print("  Compliance Rate: \(Int((Double(compliantComponents) / Double(totalComponents)) * 100))%")
        print("  Average Compliance Score: \(averageScore)%")
        print()
        
        print("📋 Detailed Results:")
        print("-------------------")
        
        for result in validationResults.sorted(by: { $0.complianceScore > $1.complianceScore }) {
            print("\(result.status) \(result.component) (\(result.complianceScore)%)")
            
            if !result.issues.isEmpty {
                print("  Issues:")
                for issue in result.issues {
                    print("    • \(issue)")
                }
            }
            
            if !result.recommendations.isEmpty {
                print("  Recommendations:")
                for recommendation in result.recommendations {
                    print("    → \(recommendation)")
                }
            }
            print()
        }
        
        // Architecture Integrity Assessment
        print("🏗️ Architecture Integrity Assessment:")
        print("------------------------------------")
        
        if averageScore >= 90 {
            print("✅ EXCELLENT: Phase 4 architecture meets enterprise standards")
        } else if averageScore >= 80 {
            print("✅ GOOD: Phase 4 architecture is production-ready with minor improvements needed")
        } else if averageScore >= 70 {
            print("⚠️ ACCEPTABLE: Phase 4 architecture needs improvements before production")
        } else {
            print("❌ NEEDS WORK: Phase 4 architecture requires significant improvements")
        }
        
        // Integration Status
        print("\n🔗 Integration Status:")
        print("--------------------")
        
        let serviceContainerResult = validationResults.first { $0.component == "ServiceContainer Integration" }
        let watchIntegrationResult = validationResults.first { $0.component == "Watch Integration" }
        let navigationResult = validationResults.first { $0.component == "Navigation Integration" }
        
        print("ServiceContainer: \(serviceContainerResult?.status ?? "❓ NOT VALIDATED")")
        print("Watch Coordination: \(watchIntegrationResult?.status ?? "❓ NOT VALIDATED")")
        print("Navigation: \(navigationResult?.status ?? "❓ NOT VALIDATED")")
        
        // Final Assessment
        print("\n🎯 Final Phase 4C Assessment:")
        print("-----------------------------")
        
        if compliantComponents >= Int(Double(totalComponents) * 0.8) && averageScore >= 80 {
            print("✅ PHASE 4C INTEGRATION SUCCESSFUL")
            print("The gamification system is ready for production deployment.")
        } else {
            print("⚠️ PHASE 4C NEEDS ATTENTION")
            print("Address the identified issues before proceeding to production.")
        }
    }
}

// MARK: - Main Execution

let validator = Phase4ArchitectureValidator()
validator.validateArchitecture()