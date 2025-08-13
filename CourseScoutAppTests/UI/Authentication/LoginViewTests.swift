import XCTest
import SwiftUI
@testable import GolfFinderApp

// MARK: - Login View UI Tests

final class LoginViewTests: XCTestCase {
    
    // MARK: - Properties
    
    private var app: XCUIApplication!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        app = XCUIApplication()
        app.launchEnvironment["TESTING"] = "1"
        app.launchEnvironment["MOCK_AUTHENTICATION"] = "1"
        app.launch()
        
        // Ensure we start from a clean authentication state
        if app.buttons["Sign Out"].exists {
            app.buttons["Sign Out"].tap()
        }
    }
    
    override func tearDown() {
        app = nil
        super.tearDown()
    }
    
    // MARK: - Login View Layout Tests
    
    func testLoginViewLayout_AllElementsPresent() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        // Then - Verify all UI elements are present
        XCTAssertTrue(app.images["AppLogo"].exists, "App logo should be visible")
        XCTAssertTrue(app.staticTexts["Welcome to GolfFinder"].exists, "Welcome text should be visible")
        XCTAssertTrue(app.staticTexts["Sign in to access your golf courses"].exists, "Subtitle should be visible")
        
        // OAuth provider buttons
        XCTAssertTrue(app.buttons["Sign in with Google"].exists, "Google sign-in button should be visible")
        XCTAssertTrue(app.buttons["Sign in with Apple"].exists, "Apple sign-in button should be visible")
        XCTAssertTrue(app.buttons["Sign in with Facebook"].exists, "Facebook sign-in button should be visible")
        XCTAssertTrue(app.buttons["Sign in with Microsoft"].exists, "Microsoft sign-in button should be visible")
        
        // Enterprise options
        XCTAssertTrue(app.buttons["Enterprise Sign-In"].exists, "Enterprise sign-in button should be visible")
        
        // Footer links
        XCTAssertTrue(app.buttons["Privacy Policy"].exists, "Privacy Policy link should be visible")
        XCTAssertTrue(app.buttons["Terms of Service"].exists, "Terms of Service link should be visible")
        XCTAssertTrue(app.buttons["Create Account"].exists, "Create Account link should be visible")
    }
    
    func testLoginViewAccessibility_VoiceOverSupport() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        // Then - Verify accessibility elements
        let googleButton = app.buttons["Sign in with Google"]
        XCTAssertTrue(googleButton.exists)
        XCTAssertNotNil(googleButton.label)
        XCTAssertTrue(googleButton.isHittable)
        
        let appleButton = app.buttons["Sign in with Apple"]
        XCTAssertTrue(appleButton.exists)
        XCTAssertNotNil(appleButton.label)
        XCTAssertTrue(appleButton.isHittable)
        
        let enterpriseButton = app.buttons["Enterprise Sign-In"]
        XCTAssertTrue(enterpriseButton.exists)
        XCTAssertNotNil(enterpriseButton.label)
        XCTAssertTrue(enterpriseButton.isHittable)
        
        // Verify accessibility hints
        XCTAssertTrue(googleButton.label.contains("Google"))
        XCTAssertTrue(appleButton.label.contains("Apple"))
    }
    
    func testLoginViewResponsiveness_DifferentScreenSizes() {
        // Test on different device orientations and sizes
        let orientations: [UIDeviceOrientation] = [.portrait, .landscapeLeft]
        
        for orientation in orientations {
            // Rotate device
            XCUIDevice.shared.orientation = orientation
            
            // Give time for rotation animation
            Thread.sleep(forTimeInterval: 1.0)
            
            // Navigate to login view if needed
            if !app.otherElements["LoginView"].exists {
                navigateToLoginView()
            }
            
            // Verify elements are still visible and accessible
            XCTAssertTrue(app.buttons["Sign in with Google"].exists, "Google button should be visible in \(orientation)")
            XCTAssertTrue(app.buttons["Sign in with Apple"].exists, "Apple button should be visible in \(orientation)")
            XCTAssertTrue(app.buttons["Enterprise Sign-In"].exists, "Enterprise button should be visible in \(orientation)")
            
            // Verify buttons are tappable
            XCTAssertTrue(app.buttons["Sign in with Google"].isHittable, "Google button should be tappable in \(orientation)")
            XCTAssertTrue(app.buttons["Sign in with Apple"].isHittable, "Apple button should be tappable in \(orientation)")
        }
        
        // Reset to portrait
        XCUIDevice.shared.orientation = .portrait
    }
    
    // MARK: - OAuth Authentication Flow Tests
    
    func testGoogleSignIn_Flow() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        let googleButton = app.buttons["Sign in with Google"]
        XCTAssertTrue(googleButton.exists)
        
        // When - Tap Google sign-in button
        googleButton.tap()
        
        // Then - Verify Google OAuth flow starts
        // In test environment, this should show a mock success or redirect to main app
        let expectation = XCTestExpectation(description: "Google sign-in flow")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Check for either OAuth redirect or successful authentication
            if self.app.staticTexts["Authentication Successful"].exists ||
               self.app.otherElements["MainView"].exists ||
               self.app.staticTexts["Welcome"].exists {
                expectation.fulfill()
            } else {
                XCTFail("Google sign-in flow did not complete successfully")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testAppleSignIn_Flow() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        let appleButton = app.buttons["Sign in with Apple"]
        XCTAssertTrue(appleButton.exists)
        
        // When - Tap Apple sign-in button
        appleButton.tap()
        
        // Then - Verify Apple ID authentication flow
        let expectation = XCTestExpectation(description: "Apple sign-in flow")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // In test environment, check for mock Apple ID authentication
            if self.app.staticTexts["Authentication Successful"].exists ||
               self.app.otherElements["MainView"].exists ||
               self.app.alerts["Apple ID Authentication"].exists {
                expectation.fulfill()
            } else {
                XCTFail("Apple sign-in flow did not complete successfully")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testFacebookSignIn_Flow() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        let facebookButton = app.buttons["Sign in with Facebook"]
        XCTAssertTrue(facebookButton.exists)
        
        // When - Tap Facebook sign-in button
        facebookButton.tap()
        
        // Then - Verify Facebook OAuth flow
        let expectation = XCTestExpectation(description: "Facebook sign-in flow")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.app.staticTexts["Authentication Successful"].exists ||
               self.app.otherElements["MainView"].exists {
                expectation.fulfill()
            } else {
                XCTFail("Facebook sign-in flow did not complete successfully")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testMicrosoftSignIn_Flow() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        let microsoftButton = app.buttons["Sign in with Microsoft"]
        XCTAssertTrue(microsoftButton.exists)
        
        // When - Tap Microsoft sign-in button
        microsoftButton.tap()
        
        // Then - Verify Microsoft OAuth flow
        let expectation = XCTestExpectation(description: "Microsoft sign-in flow")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.app.staticTexts["Authentication Successful"].exists ||
               self.app.otherElements["MainView"].exists {
                expectation.fulfill()
            } else {
                XCTFail("Microsoft sign-in flow did not complete successfully")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Enterprise Authentication Tests
    
    func testEnterpriseSignIn_Flow() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        let enterpriseButton = app.buttons["Enterprise Sign-In"]
        XCTAssertTrue(enterpriseButton.exists)
        
        // When - Tap Enterprise sign-in button
        enterpriseButton.tap()
        
        // Then - Verify enterprise login view appears
        XCTAssertTrue(app.otherElements["EnterpriseLoginView"].waitForExistence(timeout: 3.0),
                     "Enterprise login view should appear")
        
        // Verify enterprise login elements
        XCTAssertTrue(app.textFields["Organization Domain"].exists, "Domain field should be present")
        XCTAssertTrue(app.buttons["Continue with Azure AD"].exists, "Azure AD button should be present")
        XCTAssertTrue(app.buttons["Continue with Google Workspace"].exists, "Google Workspace button should be present")
        XCTAssertTrue(app.buttons["Continue with Okta"].exists, "Okta button should be present")
        XCTAssertTrue(app.buttons["Continue with SAML"].exists, "SAML button should be present")
    }
    
    func testEnterpriseLogin_DomainValidation() {
        // Given - Navigate to enterprise login
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        app.buttons["Enterprise Sign-In"].tap()
        XCTAssertTrue(app.otherElements["EnterpriseLoginView"].waitForExistence(timeout: 3.0))
        
        let domainField = app.textFields["Organization Domain"]
        XCTAssertTrue(domainField.exists)
        
        // Test invalid domain
        domainField.tap()
        domainField.typeText("invalid-domain")
        
        app.buttons["Continue with Azure AD"].tap()
        
        // Should show validation error
        XCTAssertTrue(app.staticTexts["Please enter a valid domain"].waitForExistence(timeout: 2.0),
                     "Domain validation error should appear")
        
        // Test valid domain
        domainField.clearAndEnterText("example.com")
        app.buttons["Continue with Azure AD"].tap()
        
        // Should proceed to Azure AD authentication
        let expectation = XCTestExpectation(description: "Azure AD flow")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.app.staticTexts["Redirecting to Azure AD"].exists ||
               self.app.staticTexts["Authentication Successful"].exists {
                expectation.fulfill()
            } else {
                XCTFail("Azure AD authentication flow did not start")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testLoginView_NetworkErrorHandling() {
        // Given - Enable network error simulation
        app.launchEnvironment["SIMULATE_NETWORK_ERROR"] = "1"
        app.terminate()
        app.launch()
        
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        // When - Attempt to sign in with network error
        app.buttons["Sign in with Google"].tap()
        
        // Then - Verify error handling
        XCTAssertTrue(app.alerts["Network Error"].waitForExistence(timeout: 5.0),
                     "Network error alert should appear")
        
        XCTAssertTrue(app.staticTexts["Unable to connect. Please check your internet connection and try again."].exists,
                     "Error message should be informative")
        
        // Verify user can dismiss error and try again
        app.buttons["OK"].tap()
        XCTAssertFalse(app.alerts["Network Error"].exists, "Error alert should be dismissed")
        XCTAssertTrue(app.buttons["Sign in with Google"].exists, "Sign-in buttons should still be available")
    }
    
    func testLoginView_AuthenticationFailureHandling() {
        // Given - Enable authentication failure simulation
        app.launchEnvironment["SIMULATE_AUTH_FAILURE"] = "1"
        app.terminate()
        app.launch()
        
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        // When - Attempt to sign in with auth failure
        app.buttons["Sign in with Google"].tap()
        
        // Then - Verify error handling
        XCTAssertTrue(app.alerts["Authentication Failed"].waitForExistence(timeout: 5.0),
                     "Authentication failure alert should appear")
        
        XCTAssertTrue(app.staticTexts["Authentication was cancelled or failed. Please try again."].exists,
                     "Failure message should be informative")
        
        // Verify user can try again
        app.buttons["Try Again"].tap()
        XCTAssertTrue(app.buttons["Sign in with Google"].exists, "User should be able to retry")
    }
    
    // MARK: - Privacy and Terms Tests
    
    func testPrivacyPolicyLink() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        // When - Tap Privacy Policy link
        app.buttons["Privacy Policy"].tap()
        
        // Then - Verify privacy policy view opens
        XCTAssertTrue(app.otherElements["PrivacyPolicyView"].waitForExistence(timeout: 3.0),
                     "Privacy Policy view should open")
        
        // Verify privacy policy content
        XCTAssertTrue(app.staticTexts["Privacy Policy"].exists, "Privacy Policy title should be present")
        XCTAssertTrue(app.scrollViews.firstMatch.exists, "Privacy policy content should be scrollable")
        
        // Verify back navigation
        if app.buttons["Back"].exists {
            app.buttons["Back"].tap()
        } else if app.buttons["Done"].exists {
            app.buttons["Done"].tap()
        }
        
        XCTAssertTrue(app.otherElements["LoginView"].waitForExistence(timeout: 2.0),
                     "Should return to login view")
    }
    
    func testTermsOfServiceLink() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        // When - Tap Terms of Service link
        app.buttons["Terms of Service"].tap()
        
        // Then - Verify terms of service view opens
        XCTAssertTrue(app.otherElements["TermsOfServiceView"].waitForExistence(timeout: 3.0),
                     "Terms of Service view should open")
        
        // Verify terms content
        XCTAssertTrue(app.staticTexts["Terms of Service"].exists, "Terms of Service title should be present")
        XCTAssertTrue(app.scrollViews.firstMatch.exists, "Terms content should be scrollable")
        
        // Verify back navigation
        if app.buttons["Back"].exists {
            app.buttons["Back"].tap()
        } else if app.buttons["Done"].exists {
            app.buttons["Done"].tap()
        }
        
        XCTAssertTrue(app.otherElements["LoginView"].waitForExistence(timeout: 2.0),
                     "Should return to login view")
    }
    
    // MARK: - Create Account Flow Tests
    
    func testCreateAccountLink() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        // When - Tap Create Account link
        app.buttons["Create Account"].tap()
        
        // Then - Verify sign-up view opens
        XCTAssertTrue(app.otherElements["SignUpView"].waitForExistence(timeout: 3.0),
                     "Sign-up view should open")
        
        // Verify sign-up elements
        XCTAssertTrue(app.staticTexts["Create Account"].exists, "Sign-up title should be present")
        XCTAssertTrue(app.buttons["Sign up with Google"].exists, "Google sign-up should be available")
        XCTAssertTrue(app.buttons["Sign up with Apple"].exists, "Apple sign-up should be available")
        
        // Verify back navigation
        if app.buttons["Back to Sign In"].exists {
            app.buttons["Back to Sign In"].tap()
            XCTAssertTrue(app.otherElements["LoginView"].waitForExistence(timeout: 2.0),
                         "Should return to login view")
        }
    }
    
    // MARK: - Performance Tests
    
    func testLoginViewPerformance_LoadTime() {
        measure {
            app.terminate()
            app.launch()
            
            // Measure time to load login view
            _ = app.otherElements["LoginView"].waitForExistence(timeout: 5.0)
        }
    }
    
    func testLoginViewPerformance_ButtonResponseTime() {
        // Given - Navigate to login view
        if !app.otherElements["LoginView"].exists {
            navigateToLoginView()
        }
        
        measure {
            // Measure button tap response time
            let googleButton = app.buttons["Sign in with Google"]
            googleButton.tap()
            
            // Wait for some response (loading indicator, navigation, etc.)
            _ = app.activityIndicators.firstMatch.waitForExistence(timeout: 2.0) ||
                app.staticTexts["Signing in..."].waitForExistence(timeout: 2.0) ||
                app.otherElements["MainView"].waitForExistence(timeout: 2.0)
        }
    }
    
    // MARK: - Helper Methods
    
    private func navigateToLoginView() {
        // If already on login view, return
        if app.otherElements["LoginView"].exists {
            return
        }
        
        // Check if we need to sign out first
        if app.buttons["Sign Out"].exists {
            app.buttons["Sign Out"].tap()
        }
        
        // Check if we're on onboarding or need to navigate
        if app.buttons["Get Started"].exists {
            app.buttons["Get Started"].tap()
        }
        
        if app.buttons["Sign In"].exists {
            app.buttons["Sign In"].tap()
        }
        
        // Wait for login view to appear
        XCTAssertTrue(app.otherElements["LoginView"].waitForExistence(timeout: 3.0),
                     "Login view should be accessible")
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        tap()
        
        // Select all existing text
        press(forDuration: 1.0)
        
        if app.menuItems["Select All"].exists {
            app.menuItems["Select All"].tap()
        }
        
        // Type new text
        typeText(text)
    }
}