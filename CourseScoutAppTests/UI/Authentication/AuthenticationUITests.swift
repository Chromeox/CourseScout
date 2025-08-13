import XCTest
@testable import GolfFinderApp

// MARK: - Authentication UI Tests

final class AuthenticationUITests: XCTestCase {
    
    // MARK: - Properties
    
    private var app: XCUIApplication!
    private var testDataFactory: TestDataFactory!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        continueAfterFailure = false
        
        app = XCUIApplication()
        testDataFactory = TestDataFactory()
        
        // Configure test environment
        app.launchEnvironment["IS_UI_TESTING"] = "1"
        app.launchEnvironment["ANIMATION_SPEED"] = "0"
        app.launchEnvironment["MOCK_AUTHENTICATION"] = "1"
        
        app.launch()
    }
    
    override func tearDown() {
        app = nil
        testDataFactory = nil
        
        super.tearDown()
    }
    
    // MARK: - Login Flow Tests
    
    func testLoginView_InitialState() {
        // Given
        navigateToLoginView()
        
        // Then
        XCTAssertTrue(app.staticTexts["Welcome Back"].exists)
        XCTAssertTrue(app.staticTexts["Sign in to your account"].exists)
        XCTAssertTrue(app.buttons["Personal"].exists)
        XCTAssertTrue(app.buttons["Enterprise"].exists)
        XCTAssertTrue(app.textFields["Email"].exists)
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.buttons["Sign In"].exists)
    }
    
    func testLoginView_PersonalModeFields() {
        // Given
        navigateToLoginView()
        
        // When
        app.buttons["Personal"].tap()
        
        // Then
        XCTAssertTrue(app.textFields["Email"].exists)
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.toggles["Remember me"].exists)
        XCTAssertTrue(app.buttons["Forgot Password?"].exists)
        XCTAssertFalse(app.textFields["Organization Domain"].exists)
    }
    
    func testLoginView_EnterpriseModeFields() {
        // Given
        navigateToLoginView()
        
        // When
        app.buttons["Enterprise"].tap()
        
        // Then
        XCTAssertTrue(app.textFields["Organization Domain"].exists)
        XCTAssertFalse(app.textFields["Email"].exists)
        XCTAssertFalse(app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.buttons["Continue with SSO"].exists)
    }
    
    func testLoginView_EmailValidation() {
        // Given
        navigateToLoginView()
        
        // When
        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("invalid-email")
        
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("password123")
        
        app.buttons["Sign In"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Please enter a valid email address"].waitForExistence(timeout: 2))
    }
    
    func testLoginView_PasswordRequirement() {
        // Given
        navigateToLoginView()
        
        // When
        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("test@example.com")
        
        app.buttons["Sign In"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Please fill in all required fields"].waitForExistence(timeout: 2))
    }
    
    func testLoginView_SuccessfulLogin() {
        // Given
        navigateToLoginView()
        
        // When
        performValidLogin()
        
        // Then
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 5))
    }
    
    func testLoginView_FailedLogin() {
        // Given
        navigateToLoginView()
        app.launchEnvironment["MOCK_LOGIN_FAILURE"] = "1"
        
        // When
        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("wrong@example.com")
        
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("wrongpassword")
        
        app.buttons["Sign In"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Invalid username or password"].waitForExistence(timeout: 3))
    }
    
    // MARK: - OAuth Authentication Tests
    
    func testLoginView_GoogleSignIn() {
        // Given
        navigateToLoginView()
        
        // When
        app.buttons["Continue with Google"].tap()
        
        // Then
        // OAuth would open external web view - test that we initiate the process
        XCTAssertTrue(app.staticTexts["Authenticating..."].waitForExistence(timeout: 2))
    }
    
    func testLoginView_AppleSignIn() {
        // Given
        navigateToLoginView()
        
        // When
        app.buttons["Continue with Apple"].tap()
        
        // Then
        // Apple Sign In would show system dialog - test that we initiate the process
        XCTAssertTrue(app.staticTexts["Authenticating..."].waitForExistence(timeout: 2))
    }
    
    func testLoginView_FacebookSignIn() {
        // Given
        navigateToLoginView()
        
        // When
        app.buttons["Continue with Facebook"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Authenticating..."].waitForExistence(timeout: 2))
    }
    
    func testLoginView_MicrosoftSignIn() {
        // Given
        navigateToLoginView()
        
        // When
        app.buttons["Continue with Microsoft"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Authenticating..."].waitForExistence(timeout: 2))
    }
    
    // MARK: - Enterprise Authentication Tests
    
    func testLoginView_EnterpriseOrganizationDiscovery() {
        // Given
        navigateToLoginView()
        
        // When
        app.buttons["Enterprise"].tap()
        
        let domainField = app.textFields["Organization Domain"]
        domainField.tap()
        domainField.typeText("example.com")
        
        // Then
        XCTAssertTrue(app.staticTexts["Discovering organization..."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Found: Example Corporation"].waitForExistence(timeout: 5))
    }
    
    func testLoginView_EnterpriseOrganizationNotFound() {
        // Given
        navigateToLoginView()
        app.launchEnvironment["MOCK_TENANT_NOT_FOUND"] = "1"
        
        // When
        app.buttons["Enterprise"].tap()
        
        let domainField = app.textFields["Organization Domain"]
        domainField.tap()
        domainField.typeText("notfound.com")
        
        // Then
        XCTAssertTrue(app.staticTexts["Organization not found for this domain"].waitForExistence(timeout: 5))
    }
    
    func testLoginView_EnterpriseSSOFlow() {
        // Given
        navigateToLoginView()
        
        // When
        app.buttons["Enterprise"].tap()
        
        let domainField = app.textFields["Organization Domain"]
        domainField.tap()
        domainField.typeText("example.com")
        
        // Wait for organization discovery
        XCTAssertTrue(app.staticTexts["Found: Example Corporation"].waitForExistence(timeout: 5))
        
        app.buttons["Continue with SSO"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Authenticating..."].waitForExistence(timeout: 2))
    }
    
    // MARK: - Biometric Authentication Tests
    
    func testLoginView_BiometricAuthentication() {
        // Given
        navigateToLoginView()
        app.launchEnvironment["MOCK_BIOMETRIC_AVAILABLE"] = "1"
        
        // When
        performValidLogin() // First login to enable biometric option
        
        // Sign out and return to login
        app.buttons["Sign Out"].tap()
        
        // Then
        XCTAssertTrue(app.buttons["Sign in with Face ID"].waitForExistence(timeout: 3))
        
        // When
        app.buttons["Sign in with Face ID"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 5))
    }
    
    func testLoginView_BiometricNotAvailable() {
        // Given
        navigateToLoginView()
        app.launchEnvironment["MOCK_BIOMETRIC_AVAILABLE"] = "0"
        
        // When
        performValidLogin()
        
        // Then
        XCTAssertFalse(app.buttons["Sign in with Face ID"].exists)
        XCTAssertFalse(app.buttons["Sign in with Touch ID"].exists)
    }
    
    // MARK: - Multi-Factor Authentication Tests
    
    func testLoginView_MFAPrompt() {
        // Given
        navigateToLoginView()
        app.launchEnvironment["MOCK_MFA_REQUIRED"] = "1"
        
        // When
        performValidLogin()
        
        // Then
        XCTAssertTrue(app.staticTexts["Two-Factor Authentication"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Enter the 6-digit code from your Authenticator App"].exists)
        XCTAssertTrue(app.textFields["000000"].exists)
        XCTAssertTrue(app.buttons["Verify"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }
    
    func testLoginView_MFAValidCode() {
        // Given
        navigateToLoginView()
        app.launchEnvironment["MOCK_MFA_REQUIRED"] = "1"
        
        // When
        performValidLogin()
        
        // Wait for MFA prompt
        XCTAssertTrue(app.staticTexts["Two-Factor Authentication"].waitForExistence(timeout: 3))
        
        let codeField = app.textFields["000000"]
        codeField.tap()
        codeField.typeText("123456")
        
        app.buttons["Verify"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 5))
    }
    
    func testLoginView_MFAInvalidCode() {
        // Given
        navigateToLoginView()
        app.launchEnvironment["MOCK_MFA_REQUIRED"] = "1"
        app.launchEnvironment["MOCK_MFA_INVALID"] = "1"
        
        // When
        performValidLogin()
        
        // Wait for MFA prompt
        XCTAssertTrue(app.staticTexts["Two-Factor Authentication"].waitForExistence(timeout: 3))
        
        let codeField = app.textFields["000000"]
        codeField.tap()
        codeField.typeText("000000")
        
        app.buttons["Verify"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Invalid verification code"].waitForExistence(timeout: 3))
    }
    
    // MARK: - Sign Up Flow Tests
    
    func testSignUpView_Navigation() {
        // Given
        navigateToLoginView()
        
        // When
        app.buttons["Don't have an account? Sign Up"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Create Account"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["First Name"].exists)
        XCTAssertTrue(app.textFields["Last Name"].exists)
        XCTAssertTrue(app.textFields["Email"].exists)
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.secureTextFields["Confirm Password"].exists)
    }
    
    func testSignUpView_PasswordStrength() {
        // Given
        navigateToSignUpView()
        
        // When
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("weak")
        
        // Then
        XCTAssertTrue(app.staticTexts["Weak"].waitForExistence(timeout: 2))
        
        // When
        passwordField.clearText()
        passwordField.typeText("StrongPassword123!")
        
        // Then
        XCTAssertTrue(app.staticTexts["Strong"].waitForExistence(timeout: 2))
    }
    
    func testSignUpView_PasswordMismatch() {
        // Given
        navigateToSignUpView()
        
        // When
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("password123")
        
        let confirmPasswordField = app.secureTextFields["Confirm Password"]
        confirmPasswordField.tap()
        confirmPasswordField.typeText("different123")
        
        app.buttons["Create Account"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Passwords do not match"].waitForExistence(timeout: 2))
    }
    
    func testSignUpView_SuccessfulRegistration() {
        // Given
        navigateToSignUpView()
        
        // When
        fillSignUpForm()
        app.buttons["Create Account"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Account created successfully!"].waitForExistence(timeout: 5))
    }
    
    // MARK: - Profile Management Tests
    
    func testProfileView_Navigation() {
        // Given
        authenticateAndNavigateToProfile()
        
        // Then
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Edit Profile"].exists)
        XCTAssertTrue(app.buttons["Security Settings"].exists)
        XCTAssertTrue(app.buttons["Privacy Settings"].exists)
    }
    
    func testProfileView_EditProfile() {
        // Given
        authenticateAndNavigateToProfile()
        
        // When
        app.buttons["Edit Profile"].tap()
        
        // Then
        XCTAssertTrue(app.textFields["First Name"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["Last Name"].exists)
        XCTAssertTrue(app.textFields["Email"].exists)
        XCTAssertTrue(app.buttons["Save Changes"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }
    
    func testProfileView_SecuritySettings() {
        // Given
        authenticateAndNavigateToProfile()
        
        // When
        app.buttons["Security Settings"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Security"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.toggles["Two-Factor Authentication"].exists)
        XCTAssertTrue(app.toggles["Biometric Authentication"].exists)
        XCTAssertTrue(app.buttons["Change Password"].exists)
    }
    
    // MARK: - Biometric Setup Tests
    
    func testBiometricSetup_Navigation() {
        // Given
        authenticateAndNavigateToProfile()
        
        // When
        app.buttons["Security Settings"].tap()
        app.buttons["Setup Biometric Authentication"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Biometric Authentication Setup"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Welcome"].exists)
        XCTAssertTrue(app.buttons["Get Started"].exists)
    }
    
    func testBiometricSetup_AvailabilityCheck() {
        // Given
        navigateToBiometricSetup()
        app.launchEnvironment["MOCK_BIOMETRIC_AVAILABLE"] = "1"
        
        // When
        app.buttons["Get Started"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Device Check"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Face ID is available on this device"].exists)
        XCTAssertTrue(app.buttons["Continue"].exists)
    }
    
    func testBiometricSetup_NotAvailable() {
        // Given
        navigateToBiometricSetup()
        app.launchEnvironment["MOCK_BIOMETRIC_AVAILABLE"] = "0"
        
        // When
        app.buttons["Get Started"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Device Check"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Biometric authentication is not available on this device"].exists)
    }
    
    func testBiometricSetup_ConfigurationStep() {
        // Given
        navigateToBiometricSetup()
        app.launchEnvironment["MOCK_BIOMETRIC_AVAILABLE"] = "1"
        
        // When
        app.buttons["Get Started"].tap()
        
        // Wait for availability check
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 3))
        app.buttons["Continue"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Configuration"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.toggles["Enable for Login"].exists)
        XCTAssertTrue(app.toggles["Enable for Transactions"].exists)
        XCTAssertTrue(app.toggles["Enable for Settings"].exists)
    }
    
    func testBiometricSetup_TestingStep() {
        // Given
        completeBiometricSetupToTesting()
        
        // When
        app.buttons["Test Biometric Authentication"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Test Passed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Complete Setup"].exists)
    }
    
    func testBiometricSetup_Completion() {
        // Given
        completeBiometricSetupToTesting()
        
        // When
        app.buttons["Test Biometric Authentication"].tap()
        
        // Wait for test completion
        XCTAssertTrue(app.staticTexts["Test Passed"].waitForExistence(timeout: 5))
        
        app.buttons["Complete Setup"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Setup Complete!"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Biometric authentication setup complete!"].exists)
    }
    
    // MARK: - Error Handling Tests
    
    func testLoginView_NetworkError() {
        // Given
        navigateToLoginView()
        app.launchEnvironment["MOCK_NETWORK_ERROR"] = "1"
        
        // When
        performValidLogin()
        
        // Then
        XCTAssertTrue(app.staticTexts["Network error"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["OK"].exists)
    }
    
    func testLoginView_ServerError() {
        // Given
        navigateToLoginView()
        app.launchEnvironment["MOCK_SERVER_ERROR"] = "1"
        
        // When
        performValidLogin()
        
        // Then
        XCTAssertTrue(app.staticTexts["Service temporarily unavailable"].waitForExistence(timeout: 3))
    }
    
    func testBiometricSetup_PermissionDenied() {
        // Given
        navigateToBiometricSetup()
        app.launchEnvironment["MOCK_BIOMETRIC_PERMISSION_DENIED"] = "1"
        
        // When
        app.buttons["Get Started"].tap()
        
        // Wait for permissions step
        XCTAssertTrue(app.staticTexts["Permissions"].waitForExistence(timeout: 3))
        app.buttons["Grant Permission"].tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["Permission is required to use biometric authentication"].waitForExistence(timeout: 3))
    }
    
    // MARK: - Accessibility Tests
    
    func testLoginView_AccessibilityLabels() {
        // Given
        navigateToLoginView()
        
        // Then
        XCTAssertTrue(app.textFields["Email"].isAccessibilityElement)
        XCTAssertEqual(app.textFields["Email"].accessibilityLabel, "Email")
        
        XCTAssertTrue(app.secureTextFields["Password"].isAccessibilityElement)
        XCTAssertEqual(app.secureTextFields["Password"].accessibilityLabel, "Password")
        
        XCTAssertTrue(app.buttons["Sign In"].isAccessibilityElement)
        XCTAssertEqual(app.buttons["Sign In"].accessibilityLabel, "Sign In")
    }
    
    func testBiometricSetup_AccessibilityNavigation() {
        // Given
        navigateToBiometricSetup()
        
        // Then
        XCTAssertTrue(app.buttons["Get Started"].isAccessibilityElement)
        XCTAssertNotNil(app.buttons["Get Started"].accessibilityHint)
        
        // When
        app.buttons["Get Started"].tap()
        
        // Then
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Continue"].isAccessibilityElement)
    }
    
    // MARK: - Performance Tests
    
    func testLoginView_LaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchEnvironment["IS_UI_TESTING"] = "1"
            app.launch()
            
            XCTAssertTrue(app.staticTexts["Welcome Back"].waitForExistence(timeout: 10))
        }
    }
    
    func testLoginView_AuthenticationPerformance() {
        // Given
        navigateToLoginView()
        
        // When & Then
        measure {
            performValidLogin()
            XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 5))
            
            // Sign out for next iteration
            app.buttons["Sign Out"].tap()
            XCTAssertTrue(app.staticTexts["Welcome Back"].waitForExistence(timeout: 3))
        }
    }
    
    // MARK: - Helper Methods
    
    private func navigateToLoginView() {
        // Assuming the app starts with login view or we navigate to it
        if !app.staticTexts["Welcome Back"].exists {
            // Navigate to login if not already there
            app.buttons["Sign In"].tap()
        }
    }
    
    private func navigateToSignUpView() {
        navigateToLoginView()
        app.buttons["Don't have an account? Sign Up"].tap()
    }
    
    private func navigateToBiometricSetup() {
        authenticateAndNavigateToProfile()
        app.buttons["Security Settings"].tap()
        app.buttons["Setup Biometric Authentication"].tap()
    }
    
    private func authenticateAndNavigateToProfile() {
        navigateToLoginView()
        performValidLogin()
        
        // Navigate to profile
        app.buttons["Profile"].tap()
    }
    
    private func performValidLogin() {
        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("test@example.com")
        
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("password123")
        
        app.buttons["Sign In"].tap()
    }
    
    private func fillSignUpForm() {
        app.textFields["First Name"].tap()
        app.textFields["First Name"].typeText("John")
        
        app.textFields["Last Name"].tap()
        app.textFields["Last Name"].typeText("Doe")
        
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("john.doe@example.com")
        
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("StrongPassword123!")
        
        app.secureTextFields["Confirm Password"].tap()
        app.secureTextFields["Confirm Password"].typeText("StrongPassword123!")
        
        app.toggles["I agree to the Terms of Service"].tap()
        app.toggles["I agree to the Privacy Policy"].tap()
    }
    
    private func completeBiometricSetupToTesting() {
        navigateToBiometricSetup()
        app.launchEnvironment["MOCK_BIOMETRIC_AVAILABLE"] = "1"
        
        // Get Started
        app.buttons["Get Started"].tap()
        
        // Device Check
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 3))
        app.buttons["Continue"].tap()
        
        // Permissions
        XCTAssertTrue(app.buttons["Grant Permission"].waitForExistence(timeout: 3))
        app.buttons["Grant Permission"].tap()
        
        // Configuration
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 3))
        app.buttons["Continue"].tap()
        
        // Testing step
        XCTAssertTrue(app.staticTexts["Testing"].waitForExistence(timeout: 3))
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String else {
            return
        }
        
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        typeText(deleteString)
    }
    
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}