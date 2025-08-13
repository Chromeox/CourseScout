import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - User Profile Service Tests

final class UserProfileServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: UserProfileService!
    private var mockAppwriteClient: MockAppwriteClient!
    private var mockSecurityService: MockSecurityService!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        mockAppwriteClient = MockAppwriteClient()
        mockSecurityService = MockSecurityService()
        cancellables = Set<AnyCancellable>()
        
        sut = UserProfileService(
            appwriteClient: mockAppwriteClient,
            securityService: mockSecurityService
        )
    }
    
    override func tearDown() {
        cancellables = nil
        sut = nil
        mockSecurityService = nil
        mockAppwriteClient = nil
        
        super.tearDown()
    }
    
    // MARK: - Profile Management Tests
    
    func testCreateUserProfile_Success() async throws {
        // Given
        let profileData = TestDataFactory.createUserProfileData()
        let expectedProfile = TestDataFactory.createUserProfile()
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When
        let result = try await sut.createUserProfile(profileData)
        
        // Then
        XCTAssertEqual(result.id, expectedProfile.id)
        XCTAssertEqual(result.email, expectedProfile.email)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testCreateUserProfile_DuplicateEmail() async {
        // Given
        let profileData = TestDataFactory.createUserProfileData(email: "duplicate@example.com")
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.emailAlreadyExists
        
        // When & Then
        do {
            _ = try await sut.createUserProfile(profileData)
            XCTFail("Expected creation to fail")
        } catch AuthenticationError.emailAlreadyExists {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testGetUserProfile_Success() async throws {
        // Given
        let userId = "test_user_id"
        let expectedProfile = TestDataFactory.createUserProfile(id: userId)
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When
        let result = try await sut.getUserProfile(userId: userId)
        
        // Then
        XCTAssertEqual(result.id, userId)
        XCTAssertEqual(mockAppwriteClient.getDocumentCallCount, 1)
    }
    
    func testGetUserProfile_NotFound() async {
        // Given
        let userId = "nonexistent_user_id"
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.userNotFound
        
        // When & Then
        do {
            _ = try await sut.getUserProfile(userId: userId)
            XCTFail("Expected get to fail")
        } catch AuthenticationError.userNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testUpdateUserProfile_Success() async throws {
        // Given
        let userId = "test_user_id"
        let updates = TestDataFactory.createUserProfileUpdates()
        let expectedProfile = TestDataFactory.createUserProfile(id: userId)
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When
        let result = try await sut.updateUserProfile(userId: userId, updates: updates)
        
        // Then
        XCTAssertEqual(result.id, userId)
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testUpdateUserProfile_ValidationError() async {
        // Given
        let userId = "test_user_id"
        let invalidUpdates = UserProfileUpdates(email: "invalid-email") // Invalid email format
        
        // When & Then
        do {
            _ = try await sut.updateUserProfile(userId: userId, updates: invalidUpdates)
            XCTFail("Expected validation to fail")
        } catch AuthenticationError.invalidInput {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testDeleteUserProfile_Success() async throws {
        // Given
        let userId = "test_user_id"
        
        // When
        try await sut.deleteUserProfile(userId: userId)
        
        // Then
        XCTAssertEqual(mockAppwriteClient.deleteDocumentCallCount, 1)
    }
    
    func testDeleteUserProfile_NotFound() async {
        // Given
        let userId = "nonexistent_user_id"
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.userNotFound
        
        // When & Then
        do {
            try await sut.deleteUserProfile(userId: userId)
            XCTFail("Expected deletion to fail")
        } catch AuthenticationError.userNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Profile Picture Tests
    
    func testUploadProfilePicture_Success() async throws {
        // Given
        let userId = "test_user_id"
        let imageData = TestDataFactory.createImageData()
        let expectedURL = URL(string: "https://storage.example.com/profile.jpg")!
        mockAppwriteClient.mockUploadURL = expectedURL
        
        // When
        let result = try await sut.uploadProfilePicture(userId: userId, imageData: imageData)
        
        // Then
        XCTAssertEqual(result, expectedURL)
        XCTAssertEqual(mockAppwriteClient.uploadFileCallCount, 1)
    }
    
    func testUploadProfilePicture_InvalidFormat() async {
        // Given
        let userId = "test_user_id"
        let invalidData = Data("invalid image data".utf8)
        
        // When & Then
        do {
            _ = try await sut.uploadProfilePicture(userId: userId, imageData: invalidData)
            XCTFail("Expected upload to fail")
        } catch AuthenticationError.invalidInput {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testUploadProfilePicture_FileTooLarge() async {
        // Given
        let userId = "test_user_id"
        let largeImageData = Data(count: 10 * 1024 * 1024) // 10MB
        
        // When & Then
        do {
            _ = try await sut.uploadProfilePicture(userId: userId, imageData: largeImageData)
            XCTFail("Expected upload to fail")
        } catch AuthenticationError.fileTooLarge {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testDeleteProfilePicture_Success() async throws {
        // Given
        let userId = "test_user_id"
        let pictureURL = URL(string: "https://storage.example.com/profile.jpg")!
        
        // When
        try await sut.deleteProfilePicture(userId: userId, pictureURL: pictureURL)
        
        // Then
        XCTAssertEqual(mockAppwriteClient.deleteFileCallCount, 1)
    }
    
    // MARK: - User Preferences Tests
    
    func testUpdateUserPreferences_Success() async throws {
        // Given
        let userId = "test_user_id"
        let preferences = TestDataFactory.createUserPreferences()
        let expectedProfile = TestDataFactory.createUserProfile(id: userId)
        expectedProfile.preferences = preferences
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When
        let result = try await sut.updateUserPreferences(userId: userId, preferences: preferences)
        
        // Then
        XCTAssertEqual(result.preferences.language, preferences.language)
        XCTAssertEqual(result.preferences.timezone, preferences.timezone)
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testUpdateUserPreferences_InvalidTimezone() async {
        // Given
        let userId = "test_user_id"
        let invalidPreferences = UserPreferences(
            language: "en",
            timezone: "Invalid/Timezone",
            notifications: TestDataFactory.createNotificationPreferences(),
            privacy: TestDataFactory.createPrivacySettings()
        )
        
        // When & Then
        do {
            _ = try await sut.updateUserPreferences(userId: userId, preferences: invalidPreferences)
            XCTFail("Expected validation to fail")
        } catch AuthenticationError.invalidInput {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testGetUserPreferences_Success() async throws {
        // Given
        let userId = "test_user_id"
        let expectedPreferences = TestDataFactory.createUserPreferences()
        let userProfile = TestDataFactory.createUserProfile(id: userId)
        userProfile.preferences = expectedPreferences
        mockAppwriteClient.mockUserProfile = userProfile
        
        // When
        let result = try await sut.getUserPreferences(userId: userId)
        
        // Then
        XCTAssertEqual(result.language, expectedPreferences.language)
        XCTAssertEqual(result.timezone, expectedPreferences.timezone)
    }
    
    // MARK: - Privacy Settings Tests
    
    func testUpdatePrivacySettings_Success() async throws {
        // Given
        let userId = "test_user_id"
        let privacySettings = TestDataFactory.createPrivacySettings()
        let expectedProfile = TestDataFactory.createUserProfile(id: userId)
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When
        let result = try await sut.updatePrivacySettings(userId: userId, settings: privacySettings)
        
        // Then
        XCTAssertEqual(result.preferences.privacy.profileVisibility, privacySettings.profileVisibility)
        XCTAssertEqual(result.preferences.privacy.dataProcessingConsent, privacySettings.dataProcessingConsent)
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testGetPrivacySettings_Success() async throws {
        // Given
        let userId = "test_user_id"
        let expectedSettings = TestDataFactory.createPrivacySettings()
        let userProfile = TestDataFactory.createUserProfile(id: userId)
        userProfile.preferences.privacy = expectedSettings
        mockAppwriteClient.mockUserProfile = userProfile
        
        // When
        let result = try await sut.getPrivacySettings(userId: userId)
        
        // Then
        XCTAssertEqual(result.profileVisibility, expectedSettings.profileVisibility)
        XCTAssertEqual(result.dataProcessingConsent, expectedSettings.dataProcessingConsent)
    }
    
    // MARK: - Multi-Tenant Profile Tests
    
    func testGetTenantSpecificProfile_Success() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let expectedProfile = TestDataFactory.createTenantUserProfile(userId: userId, tenantId: tenantId)
        mockAppwriteClient.mockTenantUserProfile = expectedProfile
        
        // When
        let result = try await sut.getTenantSpecificProfile(userId: userId, tenantId: tenantId)
        
        // Then
        XCTAssertEqual(result.userId, userId)
        XCTAssertEqual(result.tenantId, tenantId)
        XCTAssertEqual(mockAppwriteClient.getDocumentCallCount, 1)
    }
    
    func testUpdateTenantSpecificProfile_Success() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let updates = TestDataFactory.createTenantProfileUpdates()
        let expectedProfile = TestDataFactory.createTenantUserProfile(userId: userId, tenantId: tenantId)
        mockAppwriteClient.mockTenantUserProfile = expectedProfile
        
        // When
        let result = try await sut.updateTenantSpecificProfile(userId: userId, tenantId: tenantId, updates: updates)
        
        // Then
        XCTAssertEqual(result.userId, userId)
        XCTAssertEqual(result.tenantId, tenantId)
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    // MARK: - Security Tests
    
    func testProfileDataEncryption() async throws {
        // Given
        let userId = "test_user_id"
        let sensitiveData = TestDataFactory.createSensitiveProfileData()
        mockSecurityService.mockEncryptedData = "encrypted_data"
        
        // When
        try await sut.updateSensitiveProfileData(userId: userId, data: sensitiveData)
        
        // Then
        XCTAssertEqual(mockSecurityService.encryptDataCallCount, 1)
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testProfileDataDecryption() async throws {
        // Given
        let userId = "test_user_id"
        let encryptedProfile = TestDataFactory.createEncryptedUserProfile(id: userId)
        mockAppwriteClient.mockUserProfile = encryptedProfile
        mockSecurityService.mockDecryptedData = "decrypted_data"
        
        // When
        let result = try await sut.getUserProfileWithDecryption(userId: userId)
        
        // Then
        XCTAssertEqual(mockSecurityService.decryptDataCallCount, 1)
        XCTAssertNotNil(result)
    }
    
    // MARK: - Performance Tests
    
    func testProfileCreationPerformance() {
        let profileData = TestDataFactory.createUserProfileData()
        
        measure {
            let expectation = XCTestExpectation(description: "Profile creation performance")
            
            Task {
                do {
                    _ = try await sut.createUserProfile(profileData)
                } catch {
                    // Ignore errors for performance test
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testBulkProfileUpdatesPerformance() {
        let userIds = (1...100).map { "user_\($0)" }
        let updates = TestDataFactory.createUserProfileUpdates()
        
        measure {
            let expectation = XCTestExpectation(description: "Bulk updates performance")
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for userId in userIds {
                        group.addTask {
                            do {
                                _ = try await self.sut.updateUserProfile(userId: userId, updates: updates)
                            } catch {
                                // Ignore errors for performance test
                            }
                        }
                    }
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentProfileUpdates() async {
        // Given
        let userId = "test_user_id"
        let taskCount = 10
        let updates = TestDataFactory.createUserProfileUpdates()
        
        // When
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    do {
                        _ = try await self.sut.updateUserProfile(userId: userId, updates: updates)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            
            // Then
            XCTAssertEqual(results.count, taskCount)
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testProfileWithSpecialCharacters() async throws {
        // Given
        let profileData = UserProfileCreationData(
            email: "test+special@example.com",
            name: "User with émojis 🎮",
            phoneNumber: "+1-555-123-4567",
            dateOfBirth: Date(),
            preferences: TestDataFactory.createUserPreferences()
        )
        
        let expectedProfile = TestDataFactory.createUserProfile()
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When
        let result = try await sut.createUserProfile(profileData)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testProfileWithNilOptionalFields() async throws {
        // Given
        let profileData = UserProfileCreationData(
            email: "test@example.com",
            name: nil, // Optional field
            phoneNumber: nil, // Optional field
            dateOfBirth: nil, // Optional field
            preferences: TestDataFactory.createUserPreferences()
        )
        
        let expectedProfile = TestDataFactory.createUserProfile()
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When
        let result = try await sut.createUserProfile(profileData)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testProfileUpdateWithPartialData() async throws {
        // Given
        let userId = "test_user_id"
        let partialUpdates = UserProfileUpdates(
            email: nil, // Don't update email
            name: "New Name",
            phoneNumber: nil, // Don't update phone
            profileImageURL: nil // Don't update image
        )
        
        let expectedProfile = TestDataFactory.createUserProfile(id: userId)
        mockAppwriteClient.mockUserProfile = expectedProfile
        
        // When
        let result = try await sut.updateUserProfile(userId: userId, updates: partialUpdates)
        
        // Then
        XCTAssertEqual(result.id, userId)
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
}