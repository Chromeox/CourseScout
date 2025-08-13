import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - Consent Management Service Tests

final class ConsentManagementServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: ConsentManagementService!
    private var mockAppwriteClient: MockAppwriteClient!
    private var mockSecurityService: MockSecurityService!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        mockAppwriteClient = MockAppwriteClient()
        mockSecurityService = MockSecurityService()
        cancellables = Set<AnyCancellable>()
        
        sut = ConsentManagementService(
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
    
    // MARK: - GDPR Consent Tests
    
    func testRecordGDPRConsent_Success() async throws {
        // Given
        let userId = "test_user_id"
        let consentData = TestDataFactory.createGDPRConsentData()
        let expectedConsent = TestDataFactory.createConsentRecord()
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordGDPRConsent(
            userId: userId,
            consentData: consentData
        )
        
        // Then
        XCTAssertEqual(result.userId, userId)
        XCTAssertEqual(result.consentType, .gdpr)
        XCTAssertEqual(result.status, .granted)
        XCTAssertNotNil(result.timestamp)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testRecordGDPRConsent_WithdrawConsent() async throws {
        // Given
        let userId = "test_user_id"
        let withdrawalData = TestDataFactory.createGDPRWithdrawalData()
        let expectedConsent = TestDataFactory.createConsentRecord(status: .withdrawn)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordGDPRConsent(
            userId: userId,
            consentData: withdrawalData
        )
        
        // Then
        XCTAssertEqual(result.status, .withdrawn)
        XCTAssertNotNil(result.withdrawalReason)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testRecordGDPRConsent_MinorAge() async {
        // Given
        let userId = "minor_user_id"
        let minorConsentData = TestDataFactory.createMinorConsentData()
        
        // When & Then
        do {
            _ = try await sut.recordGDPRConsent(
                userId: userId,
                consentData: minorConsentData
            )
            XCTFail("Expected consent recording to fail for minor")
        } catch AuthenticationError.minorConsentRequired {
            // Expected - require parental consent
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testRecordGDPRConsent_ParentalConsent() async throws {
        // Given
        let minorUserId = "minor_user_id"
        let parentalConsentData = TestDataFactory.createParentalConsentData()
        let expectedConsent = TestDataFactory.createConsentRecord(consentType: .parentalConsent)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordParentalConsent(
            minorUserId: minorUserId,
            parentalConsentData: parentalConsentData
        )
        
        // Then
        XCTAssertEqual(result.userId, minorUserId)
        XCTAssertEqual(result.consentType, .parentalConsent)
        XCTAssertEqual(result.status, .granted)
        XCTAssertNotNil(result.parentGuardianInfo)
    }
    
    // MARK: - Cookie Consent Tests
    
    func testRecordCookieConsent_Essential() async throws {
        // Given
        let userId = "test_user_id"
        let cookieConsent = TestDataFactory.createCookieConsentData(essential: true)
        let expectedConsent = TestDataFactory.createConsentRecord(consentType: .cookies)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordCookieConsent(
            userId: userId,
            cookieConsent: cookieConsent
        )
        
        // Then
        XCTAssertEqual(result.consentType, .cookies)
        XCTAssertTrue(result.cookieCategories.contains(.essential))
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testRecordCookieConsent_All() async throws {
        // Given
        let userId = "test_user_id"
        let cookieConsent = TestDataFactory.createCookieConsentData(
            essential: true,
            analytics: true,
            marketing: true,
            functional: true
        )
        let expectedConsent = TestDataFactory.createConsentRecord(consentType: .cookies)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordCookieConsent(
            userId: userId,
            cookieConsent: cookieConsent
        )
        
        // Then
        XCTAssertEqual(result.cookieCategories.count, 4)
        XCTAssertTrue(result.cookieCategories.contains(.essential))
        XCTAssertTrue(result.cookieCategories.contains(.analytics))
        XCTAssertTrue(result.cookieCategories.contains(.marketing))
        XCTAssertTrue(result.cookieCategories.contains(.functional))
    }
    
    func testRecordCookieConsent_Selective() async throws {
        // Given
        let userId = "test_user_id"
        let cookieConsent = TestDataFactory.createCookieConsentData(
            essential: true,
            analytics: true,
            marketing: false,
            functional: false
        )
        let expectedConsent = TestDataFactory.createConsentRecord(consentType: .cookies)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordCookieConsent(
            userId: userId,
            cookieConsent: cookieConsent
        )
        
        // Then
        XCTAssertEqual(result.cookieCategories.count, 2)
        XCTAssertTrue(result.cookieCategories.contains(.essential))
        XCTAssertTrue(result.cookieCategories.contains(.analytics))
        XCTAssertFalse(result.cookieCategories.contains(.marketing))
        XCTAssertFalse(result.cookieCategories.contains(.functional))
    }
    
    // MARK: - Marketing Consent Tests
    
    func testRecordMarketingConsent_Granted() async throws {
        // Given
        let userId = "test_user_id"
        let marketingConsent = TestDataFactory.createMarketingConsentData(granted: true)
        let expectedConsent = TestDataFactory.createConsentRecord(consentType: .marketing)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordMarketingConsent(
            userId: userId,
            marketingConsent: marketingConsent
        )
        
        // Then
        XCTAssertEqual(result.consentType, .marketing)
        XCTAssertEqual(result.status, .granted)
        XCTAssertTrue(result.marketingChannels.contains(.email))
    }
    
    func testRecordMarketingConsent_Denied() async throws {
        // Given
        let userId = "test_user_id"
        let marketingConsent = TestDataFactory.createMarketingConsentData(granted: false)
        let expectedConsent = TestDataFactory.createConsentRecord(consentType: .marketing, status: .denied)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordMarketingConsent(
            userId: userId,
            marketingConsent: marketingConsent
        )
        
        // Then
        XCTAssertEqual(result.status, .denied)
        XCTAssertTrue(result.marketingChannels.isEmpty)
    }
    
    func testRecordMarketingConsent_Selective() async throws {
        // Given
        let userId = "test_user_id"
        let marketingConsent = MarketingConsentData(
            emailMarketing: true,
            smsMarketing: false,
            pushNotifications: true,
            thirdPartySharing: false,
            purposes: [.productUpdates, .newsletters]
        )
        let expectedConsent = TestDataFactory.createConsentRecord(consentType: .marketing)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordMarketingConsent(
            userId: userId,
            marketingConsent: marketingConsent
        )
        
        // Then
        XCTAssertTrue(result.marketingChannels.contains(.email))
        XCTAssertTrue(result.marketingChannels.contains(.push))
        XCTAssertFalse(result.marketingChannels.contains(.sms))
        XCTAssertFalse(result.thirdPartySharing)
    }
    
    // MARK: - Data Processing Consent Tests
    
    func testRecordDataProcessingConsent_Success() async throws {
        // Given
        let userId = "test_user_id"
        let processingConsent = TestDataFactory.createDataProcessingConsentData()
        let expectedConsent = TestDataFactory.createConsentRecord(consentType: .dataProcessing)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordDataProcessingConsent(
            userId: userId,
            processingConsent: processingConsent
        )
        
        // Then
        XCTAssertEqual(result.consentType, .dataProcessing)
        XCTAssertEqual(result.status, .granted)
        XCTAssertFalse(result.processingPurposes.isEmpty)
    }
    
    func testRecordDataProcessingConsent_LimitedPurposes() async throws {
        // Given
        let userId = "test_user_id"
        let limitedProcessingConsent = DataProcessingConsentData(
            purposes: [.serviceProvision, .securityMonitoring],
            legalBasis: .legitimateInterest,
            dataCategories: [.profileData, .usageData],
            retentionPeriod: .oneYear,
            thirdPartySharing: false,
            crossBorderTransfer: false
        )
        let expectedConsent = TestDataFactory.createConsentRecord(consentType: .dataProcessing)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordDataProcessingConsent(
            userId: userId,
            processingConsent: limitedProcessingConsent
        )
        
        // Then
        XCTAssertEqual(result.processingPurposes.count, 2)
        XCTAssertTrue(result.processingPurposes.contains(.serviceProvision))
        XCTAssertTrue(result.processingPurposes.contains(.securityMonitoring))
        XCTAssertFalse(result.thirdPartySharing)
        XCTAssertFalse(result.crossBorderTransfer)
    }
    
    // MARK: - Consent Queries Tests
    
    func testGetUserConsent_Success() async throws {
        // Given
        let userId = "test_user_id"
        let consentType = ConsentType.gdpr
        let expectedConsent = TestDataFactory.createConsentRecord(consentType: consentType)
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.getUserConsent(
            userId: userId,
            consentType: consentType
        )
        
        // Then
        XCTAssertEqual(result?.userId, userId)
        XCTAssertEqual(result?.consentType, consentType)
        XCTAssertEqual(mockAppwriteClient.getDocumentCallCount, 1)
    }
    
    func testGetUserConsent_NotFound() async throws {
        // Given
        let userId = "test_user_id"
        let consentType = ConsentType.marketing
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.consentNotFound
        
        // When
        let result = try await sut.getUserConsent(
            userId: userId,
            consentType: consentType
        )
        
        // Then
        XCTAssertNil(result)
    }
    
    func testGetAllUserConsents_Success() async throws {
        // Given
        let userId = "test_user_id"
        let expectedConsents = [
            TestDataFactory.createConsentRecord(consentType: .gdpr),
            TestDataFactory.createConsentRecord(consentType: .cookies),
            TestDataFactory.createConsentRecord(consentType: .marketing)
        ]
        mockAppwriteClient.mockConsentRecords = expectedConsents
        
        // When
        let result = try await sut.getAllUserConsents(userId: userId)
        
        // Then
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.contains { $0.consentType == .gdpr })
        XCTAssertTrue(result.contains { $0.consentType == .cookies })
        XCTAssertTrue(result.contains { $0.consentType == .marketing })
    }
    
    func testGetConsentHistory_Success() async throws {
        // Given
        let userId = "test_user_id"
        let consentType = ConsentType.gdpr
        let expectedHistory = TestDataFactory.createConsentHistory(userId: userId, consentType: consentType)
        mockAppwriteClient.mockConsentHistory = expectedHistory
        
        // When
        let result = try await sut.getConsentHistory(
            userId: userId,
            consentType: consentType
        )
        
        // Then
        XCTAssertEqual(result.count, expectedHistory.count)
        XCTAssertTrue(result.allSatisfy { $0.userId == userId && $0.consentType == consentType })
    }
    
    // MARK: - Consent Validation Tests
    
    func testValidateConsent_Valid() async throws {
        // Given
        let userId = "test_user_id"
        let requiredConsents: [ConsentType] = [.gdpr, .cookies]
        let userConsents = [
            TestDataFactory.createConsentRecord(consentType: .gdpr, status: .granted),
            TestDataFactory.createConsentRecord(consentType: .cookies, status: .granted)
        ]
        mockAppwriteClient.mockConsentRecords = userConsents
        
        // When
        let result = try await sut.validateRequiredConsents(
            userId: userId,
            requiredConsents: requiredConsents
        )
        
        // Then
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.missingConsents.isEmpty)
        XCTAssertTrue(result.expiredConsents.isEmpty)
    }
    
    func testValidateConsent_MissingConsents() async throws {
        // Given
        let userId = "test_user_id"
        let requiredConsents: [ConsentType] = [.gdpr, .cookies, .marketing]
        let userConsents = [
            TestDataFactory.createConsentRecord(consentType: .gdpr, status: .granted)
            // Missing cookies and marketing consents
        ]
        mockAppwriteClient.mockConsentRecords = userConsents
        
        // When
        let result = try await sut.validateRequiredConsents(
            userId: userId,
            requiredConsents: requiredConsents
        )
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.missingConsents.count, 2)
        XCTAssertTrue(result.missingConsents.contains(.cookies))
        XCTAssertTrue(result.missingConsents.contains(.marketing))
    }
    
    func testValidateConsent_ExpiredConsents() async throws {
        // Given
        let userId = "test_user_id"
        let requiredConsents: [ConsentType] = [.gdpr, .cookies]
        let userConsents = [
            TestDataFactory.createConsentRecord(consentType: .gdpr, status: .granted),
            TestDataFactory.createExpiredConsentRecord(consentType: .cookies)
        ]
        mockAppwriteClient.mockConsentRecords = userConsents
        
        // When
        let result = try await sut.validateRequiredConsents(
            userId: userId,
            requiredConsents: requiredConsents
        )
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.expiredConsents.count, 1)
        XCTAssertTrue(result.expiredConsents.contains(.cookies))
    }
    
    func testValidateConsent_WithdrawnConsents() async throws {
        // Given
        let userId = "test_user_id"
        let requiredConsents: [ConsentType] = [.gdpr, .marketing]
        let userConsents = [
            TestDataFactory.createConsentRecord(consentType: .gdpr, status: .granted),
            TestDataFactory.createConsentRecord(consentType: .marketing, status: .withdrawn)
        ]
        mockAppwriteClient.mockConsentRecords = userConsents
        
        // When
        let result = try await sut.validateRequiredConsents(
            userId: userId,
            requiredConsents: requiredConsents
        )
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.withdrawnConsents.count, 1)
        XCTAssertTrue(result.withdrawnConsents.contains(.marketing))
    }
    
    // MARK: - Data Subject Rights Tests
    
    func testProcessDataExportRequest_Success() async throws {
        // Given
        let userId = "test_user_id"
        let exportRequest = TestDataFactory.createDataExportRequest(userId: userId)
        let expectedExport = TestDataFactory.createDataExportResult()
        mockAppwriteClient.mockDataExportResult = expectedExport
        
        // When
        let result = try await sut.processDataExportRequest(exportRequest)
        
        // Then
        XCTAssertEqual(result.userId, userId)
        XCTAssertEqual(result.status, .completed)
        XCTAssertNotNil(result.downloadUrl)
        XCTAssertGreaterThan(result.dataCategories.count, 0)
    }
    
    func testProcessDataDeletionRequest_Success() async throws {
        // Given
        let userId = "test_user_id"
        let deletionRequest = TestDataFactory.createDataDeletionRequest(userId: userId)
        let expectedDeletion = TestDataFactory.createDataDeletionResult()
        mockAppwriteClient.mockDataDeletionResult = expectedDeletion
        
        // When
        let result = try await sut.processDataDeletionRequest(deletionRequest)
        
        // Then
        XCTAssertEqual(result.userId, userId)
        XCTAssertEqual(result.status, .completed)
        XCTAssertGreaterThan(result.deletedDataCategories.count, 0)
    }
    
    func testProcessDataDeletionRequest_WithRetention() async throws {
        // Given
        let userId = "test_user_id"
        let deletionRequest = TestDataFactory.createDataDeletionRequest(
            userId: userId,
            respectRetentionPolicies: true
        )
        let expectedDeletion = TestDataFactory.createPartialDataDeletionResult()
        mockAppwriteClient.mockDataDeletionResult = expectedDeletion
        
        // When
        let result = try await sut.processDataDeletionRequest(deletionRequest)
        
        // Then
        XCTAssertEqual(result.status, .partialCompletion)
        XCTAssertGreaterThan(result.retainedDataCategories.count, 0)
        XCTAssertNotNil(result.retentionJustification)
    }
    
    func testProcessDataPortabilityRequest_Success() async throws {
        // Given
        let userId = "test_user_id"
        let portabilityRequest = TestDataFactory.createDataPortabilityRequest(userId: userId)
        let expectedPortability = TestDataFactory.createDataPortabilityResult()
        mockAppwriteClient.mockDataPortabilityResult = expectedPortability
        
        // When
        let result = try await sut.processDataPortabilityRequest(portabilityRequest)
        
        // Then
        XCTAssertEqual(result.userId, userId)
        XCTAssertEqual(result.format, .json)
        XCTAssertNotNil(result.downloadUrl)
        XCTAssertEqual(result.status, .completed)
    }
    
    // MARK: - Consent Renewal Tests
    
    func testCheckConsentRenewalRequired_Required() async throws {
        // Given
        let userId = "test_user_id"
        let oldConsent = TestDataFactory.createOldConsentRecord(userId: userId)
        mockAppwriteClient.mockConsentRecords = [oldConsent]
        
        // When
        let result = try await sut.checkConsentRenewalRequired(userId: userId)
        
        // Then
        XCTAssertTrue(result.renewalRequired)
        XCTAssertGreaterThan(result.expiredConsents.count, 0)
        XCTAssertNotNil(result.nextRenewalDate)
    }
    
    func testCheckConsentRenewalRequired_NotRequired() async throws {
        // Given
        let userId = "test_user_id"
        let recentConsent = TestDataFactory.createRecentConsentRecord(userId: userId)
        mockAppwriteClient.mockConsentRecords = [recentConsent]
        
        // When
        let result = try await sut.checkConsentRenewalRequired(userId: userId)
        
        // Then
        XCTAssertFalse(result.renewalRequired)
        XCTAssertTrue(result.expiredConsents.isEmpty)
    }
    
    func testRenewConsent_Success() async throws {
        // Given
        let userId = "test_user_id"
        let renewalData = TestDataFactory.createConsentRenewalData()
        let renewedConsent = TestDataFactory.createConsentRecord()
        mockAppwriteClient.mockConsentRecord = renewedConsent
        
        // When
        let result = try await sut.renewConsent(
            userId: userId,
            renewalData: renewalData
        )
        
        // Then
        XCTAssertEqual(result.userId, userId)
        XCTAssertEqual(result.status, .granted)
        XCTAssertGreaterThan(result.timestamp, Date().addingTimeInterval(-60))
    }
    
    // MARK: - Performance Tests
    
    func testConsentRecordingPerformance() {
        let userId = "test_user_id"
        let consentData = TestDataFactory.createGDPRConsentData()
        
        measure {
            let expectation = XCTestExpectation(description: "Consent recording performance")
            
            Task {
                do {
                    _ = try await sut.recordGDPRConsent(
                        userId: userId,
                        consentData: consentData
                    )
                } catch {
                    // Ignore errors for performance test
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testBulkConsentValidationPerformance() {
        let userIds = (1...100).map { "user_\($0)" }
        let requiredConsents: [ConsentType] = [.gdpr, .cookies, .marketing]
        
        measure {
            let expectation = XCTestExpectation(description: "Bulk validation performance")
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for userId in userIds {
                        group.addTask {
                            do {
                                _ = try await self.sut.validateRequiredConsents(
                                    userId: userId,
                                    requiredConsents: requiredConsents
                                )
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
    
    func testConcurrentConsentOperations() async {
        // Given
        let userId = "test_user_id"
        let taskCount = 10
        
        // When
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    do {
                        if i % 2 == 0 {
                            let consentData = TestDataFactory.createGDPRConsentData()
                            _ = try await self.sut.recordGDPRConsent(
                                userId: userId,
                                consentData: consentData
                            )
                        } else {
                            _ = try await self.sut.getUserConsent(
                                userId: userId,
                                consentType: .gdpr
                            )
                        }
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
    
    func testConsentWithExtremelyLongText() async throws {
        // Given
        let userId = "test_user_id"
        let longText = String(repeating: "A", count: 10000) // 10KB of text
        let consentData = GDPRConsentData(
            dataProcessingPurposes: [.serviceProvision],
            legalBasis: .consent,
            consentText: longText, // Extremely long consent text
            version: "1.0",
            language: "en",
            geoLocation: TestDataFactory.createLocationInfo()
        )
        
        let expectedConsent = TestDataFactory.createConsentRecord()
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordGDPRConsent(
            userId: userId,
            consentData: consentData
        )
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testConsentWithSpecialCharacters() async throws {
        // Given
        let userId = "test_user_éç_special"
        let consentData = GDPRConsentData(
            dataProcessingPurposes: [.serviceProvision],
            legalBasis: .consent,
            consentText: "Consent with éç special chars 特殊字符 🎮",
            version: "1.0",
            language: "en",
            geoLocation: TestDataFactory.createLocationInfo()
        )
        
        let expectedConsent = TestDataFactory.createConsentRecord()
        mockAppwriteClient.mockConsentRecord = expectedConsent
        
        // When
        let result = try await sut.recordGDPRConsent(
            userId: userId,
            consentData: consentData
        )
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result.userId, userId)
    }
}