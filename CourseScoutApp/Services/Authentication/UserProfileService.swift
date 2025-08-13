import Foundation
import Appwrite
import CoreLocation
import os.log

// MARK: - User Profile Service Implementation

@MainActor
final class UserProfileService: UserProfileServiceProtocol {
    
    // MARK: - Properties
    
    private let appwriteClient: Client
    private let databases: Databases
    private let storage: Storage
    private let logger = Logger(subsystem: "GolfFinderApp", category: "UserProfile")
    
    // Database Collections
    private let userProfilesCollection = "user_profiles"
    private let handicapHistoryCollection = "handicap_history"
    private let tenantMembershipsCollection = "tenant_memberships"
    private let consentRecordsCollection = "consent_records"
    private let userActivitiesCollection = "user_activities"
    private let achievementsCollection = "achievements"
    private let friendshipsCollection = "friendships"
    private let verificationRequestsCollection = "verification_requests"
    
    // MARK: - Initialization
    
    init(appwriteClient: Client) {
        self.appwriteClient = appwriteClient
        self.databases = Databases(appwriteClient)
        self.storage = Storage(appwriteClient)
        logger.info("UserProfileService initialized")
    }
    
    // MARK: - Profile Management
    
    func getUserProfile(_ userId: String) async throws -> GolfUserProfile {
        logger.debug("Fetching user profile: \(userId)")
        
        do {
            let document = try await databases.getDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: userProfilesCollection,
                documentId: userId
            )
            
            return try mapDocumentToGolfUserProfile(document)
            
        } catch {
            logger.error("Failed to fetch user profile \(userId): \(error.localizedDescription)")
            throw error
        }
    }
    
    func updateUserProfile(_ userId: String, profile: GolfUserProfileUpdate) async throws -> GolfUserProfile {
        logger.info("Updating user profile: \(userId)")
        
        var updateData: [String: Any] = [:]
        
        if let displayName = profile.displayName {
            updateData["display_name"] = displayName
        }
        if let firstName = profile.firstName {
            updateData["first_name"] = firstName
        }
        if let lastName = profile.lastName {
            updateData["last_name"] = lastName
        }
        if let bio = profile.bio {
            updateData["bio"] = bio
        }
        if let handicapIndex = profile.handicapIndex {
            updateData["handicap_index"] = handicapIndex
            
            // Record handicap history
            try await recordHandicapEntry(userId: userId, handicapIndex: handicapIndex, source: .selfReported)
        }
        if let golfPreferences = profile.golfPreferences {
            updateData["golf_preferences"] = try encodeGolfPreferences(golfPreferences)
        }
        if let homeClub = profile.homeClub {
            updateData["home_club"] = try encodeGolfClub(homeClub)
        }
        if let membershipType = profile.membershipType {
            updateData["membership_type"] = membershipType.rawValue
        }
        if let playingFrequency = profile.playingFrequency {
            updateData["playing_frequency"] = playingFrequency.rawValue
        }
        if let location = profile.location {
            updateData["location"] = try encodeUserLocation(location)
        }
        if let phoneNumber = profile.phoneNumber {
            updateData["phone_number"] = phoneNumber
        }
        if let emergencyContact = profile.emergencyContact {
            updateData["emergency_contact"] = try encodeEmergencyContact(emergencyContact)
        }
        if let privacySettings = profile.privacySettings {
            updateData["privacy_settings"] = try encodePrivacySettings(privacySettings)
        }
        if let socialVisibility = profile.socialVisibility {
            updateData["social_visibility"] = socialVisibility.rawValue
        }
        
        updateData["updated_at"] = Date().timeIntervalSince1970
        
        do {
            let updatedDocument = try await databases.updateDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: userProfilesCollection,
                documentId: userId,
                data: updateData
            )
            
            logger.info("Successfully updated user profile: \(userId)")
            return try mapDocumentToGolfUserProfile(updatedDocument)
            
        } catch {
            logger.error("Failed to update user profile \(userId): \(error.localizedDescription)")
            throw error
        }
    }
    
    func createUserProfile(_ profile: GolfUserProfileCreate) async throws -> GolfUserProfile {
        logger.info("Creating user profile for: \(profile.email)")
        
        let profileId = ID.unique()
        let now = Date().timeIntervalSince1970
        
        let profileData: [String: Any] = [
            "email": profile.email,
            "display_name": profile.displayName,
            "first_name": profile.firstName ?? "",
            "last_name": profile.lastName ?? "",
            "handicap_index": profile.handicapIndex ?? NSNull(),
            "golf_preferences": try encodeGolfPreferences(profile.golfPreferences),
            "privacy_settings": try encodePrivacySettings(profile.privacySettings),
            "tenant_id": profile.tenantId ?? "",
            "invitation_code": profile.invitationCode ?? "",
            "created_at": now,
            "updated_at": now,
            "last_active_at": now,
            "profile_completeness": calculateProfileCompleteness(profile),
            "verification_status": VerificationStatus(
                isVerified: false,
                verificationLevel: .unverified,
                verifiedAspects: [],
                lastVerifiedAt: nil,
                trustScore: 0.0
            ).rawValue,
            "social_visibility": SocialVisibility.friends.rawValue
        ]
        
        do {
            let document = try await databases.createDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: userProfilesCollection,
                documentId: profileId,
                data: profileData
            )
            
            // Handle invitation code if provided
            if let invitationCode = profile.invitationCode,
               let tenantId = profile.tenantId {
                try await processInvitationCode(
                    userId: profileId,
                    invitationCode: invitationCode,
                    tenantId: tenantId
                )
            }
            
            // Record initial handicap entry if provided
            if let handicapIndex = profile.handicapIndex {
                try await recordHandicapEntry(
                    userId: profileId,
                    handicapIndex: handicapIndex,
                    source: .selfReported
                )
            }
            
            logger.info("Successfully created user profile: \(profileId)")
            return try mapDocumentToGolfUserProfile(document)
            
        } catch {
            logger.error("Failed to create user profile: \(error.localizedDescription)")
            throw error
        }
    }
    
    func deleteUserProfile(_ userId: String) async throws {
        logger.warning("Deleting user profile: \(userId)")
        
        do {
            // Delete related data first
            await deleteUserRelatedData(userId: userId)
            
            // Delete main profile
            try await databases.deleteDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: userProfilesCollection,
                documentId: userId
            )
            
            logger.info("Successfully deleted user profile: \(userId)")
            
        } catch {
            logger.error("Failed to delete user profile \(userId): \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Golf-Specific Profile Data
    
    func updateHandicapIndex(_ userId: String, handicapIndex: Double) async throws {
        logger.info("Updating handicap index for user \(userId): \(handicapIndex)")
        
        // Validate handicap index
        guard handicapIndex >= -4.0 && handicapIndex <= 54.0 else {
            throw ValidationError.invalidHandicapIndex
        }
        
        // Update profile
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: userProfilesCollection,
            documentId: userId,
            data: [
                "handicap_index": handicapIndex,
                "updated_at": Date().timeIntervalSince1970
            ]
        )
        
        // Record handicap history
        try await recordHandicapEntry(
            userId: userId,
            handicapIndex: handicapIndex,
            source: .selfReported
        )
    }
    
    func getHandicapHistory(_ userId: String, limit: Int) async throws -> [HandicapEntry] {
        logger.debug("Fetching handicap history for user: \(userId)")
        
        let query = [
            Query.equal("user_id", value: userId),
            Query.orderDesc("recorded_at"),
            Query.limit(limit)
        ]
        
        do {
            let documents = try await databases.listDocuments(
                databaseId: Configuration.appwriteProjectId,
                collectionId: handicapHistoryCollection,
                queries: query
            )
            
            return try documents.documents.map(mapDocumentToHandicapEntry)
            
        } catch {
            logger.error("Failed to fetch handicap history for \(userId): \(error.localizedDescription)")
            throw error
        }
    }
    
    func updateGolfPreferences(_ userId: String, preferences: GolfPreferences) async throws {
        logger.info("Updating golf preferences for user: \(userId)")
        
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: userProfilesCollection,
            documentId: userId,
            data: [
                "golf_preferences": try encodeGolfPreferences(preferences),
                "updated_at": Date().timeIntervalSince1970
            ]
        )
    }
    
    func getGolfStatistics(_ userId: String, period: StatisticsPeriod) async throws -> GolfStatistics {
        logger.debug("Fetching golf statistics for user \(userId), period: \(period)")
        
        // This would typically aggregate data from scorecards, rounds, etc.
        // For now, return mock data structure
        return GolfStatistics(
            totalRounds: 0,
            averageScore: 0.0,
            bestScore: nil,
            handicapTrend: HandicapTrend(
                direction: .stable,
                changeOverPeriod: 0.0,
                consistencyScore: 0.0,
                improvementRate: 0.0
            ),
            coursesPlayed: 0,
            favoriteCoursesCount: 0,
            averageRoundDuration: 0,
            monthlyRounds: [],
            scoringAnalysis: ScoringAnalysis(
                parBreakdown: [:],
                strongestHoles: [],
                improvementAreas: [],
                consistencyMetrics: ConsistencyMetrics(
                    scoreVariability: 0.0,
                    handicapStability: 0.0,
                    performancePredictability: 0.0
                )
            ),
            improvementMetrics: ImprovementMetrics(
                handicapImprovement: 0.0,
                scoreImprovement: 0.0,
                consistencyImprovement: 0.0,
                monthsToGoal: nil,
                recommendedFocus: []
            )
        )
    }
    
    // MARK: - Multi-Tenant Membership
    
    func addTenantMembership(_ userId: String, tenantId: String, role: TenantRole) async throws -> TenantMembership {
        logger.info("Adding tenant membership: user \(userId), tenant \(tenantId), role \(role)")
        
        let membershipId = ID.unique()
        let now = Date().timeIntervalSince1970
        
        let membershipData: [String: Any] = [
            "user_id": userId,
            "tenant_id": tenantId,
            "role": role.rawValue,
            "permissions": role.permissions.map { $0.rawValue },
            "joined_at": now,
            "is_active": true,
            "created_at": now
        ]
        
        do {
            let document = try await databases.createDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: tenantMembershipsCollection,
                documentId: membershipId,
                data: membershipData
            )
            
            return try mapDocumentToTenantMembership(document)
            
        } catch {
            logger.error("Failed to add tenant membership: \(error.localizedDescription)")
            throw error
        }
    }
    
    func updateTenantMembership(_ membershipId: String, role: TenantRole, permissions: [Permission]) async throws {
        logger.info("Updating tenant membership: \(membershipId)")
        
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: tenantMembershipsCollection,
            documentId: membershipId,
            data: [
                "role": role.rawValue,
                "permissions": permissions.map { $0.rawValue },
                "updated_at": Date().timeIntervalSince1970
            ]
        )
    }
    
    func removeTenantMembership(_ userId: String, tenantId: String) async throws {
        logger.info("Removing tenant membership: user \(userId), tenant \(tenantId)")
        
        let query = [
            Query.equal("user_id", value: userId),
            Query.equal("tenant_id", value: tenantId)
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: tenantMembershipsCollection,
            queries: query
        )
        
        for document in documents.documents {
            try await databases.deleteDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: tenantMembershipsCollection,
                documentId: document.id
            )
        }
    }
    
    func getUserMemberships(_ userId: String) async throws -> [TenantMembership] {
        logger.debug("Fetching user memberships: \(userId)")
        
        let query = [
            Query.equal("user_id", value: userId),
            Query.equal("is_active", value: true)
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: tenantMembershipsCollection,
            queries: query
        )
        
        return try documents.documents.map(mapDocumentToTenantMembership)
    }
    
    func getTenantMembers(_ tenantId: String, role: TenantRole?) async throws -> [TenantMember] {
        logger.debug("Fetching tenant members: \(tenantId)")
        
        var query = [
            Query.equal("tenant_id", value: tenantId),
            Query.equal("is_active", value: true)
        ]
        
        if let role = role {
            query.append(Query.equal("role", value: role.rawValue))
        }
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: tenantMembershipsCollection,
            queries: query
        )
        
        var members: [TenantMember] = []
        
        for document in documents.documents {
            let membership = try mapDocumentToTenantMembership(document)
            if let profile = try? await getUserProfile(membership.userId) {
                members.append(TenantMember(
                    userId: membership.userId,
                    profile: profile,
                    membership: membership,
                    lastActiveAt: profile.lastActiveAt,
                    contributionScore: 0.0 // Would be calculated from user activities
                ))
            }
        }
        
        return members
    }
    
    // MARK: - Privacy & Consent
    
    func updatePrivacySettings(_ userId: String, settings: PrivacySettings) async throws {
        logger.info("Updating privacy settings for user: \(userId)")
        
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: userProfilesCollection,
            documentId: userId,
            data: [
                "privacy_settings": try encodePrivacySettings(settings),
                "updated_at": Date().timeIntervalSince1970
            ]
        )
    }
    
    func recordConsentGiven(_ userId: String, consentType: ConsentType, version: String) async throws {
        logger.info("Recording consent for user \(userId): \(consentType.rawValue) v\(version)")
        
        let consentData: [String: Any] = [
            "user_id": userId,
            "consent_type": consentType.rawValue,
            "version": version,
            "given_at": Date().timeIntervalSince1970,
            "expires_at": Date().addingTimeInterval(365 * 24 * 60 * 60).timeIntervalSince1970, // 1 year
            "ip_address": "127.0.0.1", // Would get actual IP
            "user_agent": "GolfFinderApp/1.0" // Would get actual user agent
        ]
        
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: consentRecordsCollection,
            documentId: ID.unique(),
            data: consentData
        )
    }
    
    func getConsentHistory(_ userId: String) async throws -> [ConsentRecord] {
        logger.debug("Fetching consent history for user: \(userId)")
        
        let query = [
            Query.equal("user_id", value: userId),
            Query.orderDesc("given_at")
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: consentRecordsCollection,
            queries: query
        )
        
        return try documents.documents.map(mapDocumentToConsentRecord)
    }
    
    func exportUserData(_ userId: String) async throws -> UserDataExport {
        logger.info("Exporting user data: \(userId)")
        
        // This would gather all user data and create an export file
        let exportId = UUID().uuidString
        let exportURL = URL(string: "https://example.com/exports/\(exportId)")!
        
        return UserDataExport(
            userId: userId,
            requestedAt: Date(),
            exportURL: exportURL,
            expiresAt: Date().addingTimeInterval(7 * 24 * 60 * 60), // 7 days
            format: .json,
            includeAllData: true
        )
    }
    
    func deleteUserData(_ userId: String, deletionType: DataDeletionType) async throws {
        logger.warning("Deleting user data: \(userId), type: \(deletionType)")
        
        switch deletionType {
        case .full:
            try await deleteUserProfile(userId)
        case .partial:
            // Delete specific data types while preserving core profile
            await deleteUserRelatedData(userId: userId, preserveProfile: true)
        case .anonymization:
            // Anonymize data instead of deleting
            try await anonymizeUserData(userId: userId)
        }
    }
    
    // MARK: - Social Features
    
    func addFriend(_ userId: String, friendId: String) async throws {
        logger.info("Adding friend relationship: \(userId) -> \(friendId)")
        
        let friendshipData: [String: Any] = [
            "user_id": userId,
            "friend_id": friendId,
            "friendship_type": FriendshipType.friend.rawValue,
            "connected_at": Date().timeIntervalSince1970,
            "is_active": true
        ]
        
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: friendshipsCollection,
            documentId: ID.unique(),
            data: friendshipData
        )
        
        // Create reciprocal friendship
        let reciprocalFriendshipData: [String: Any] = [
            "user_id": friendId,
            "friend_id": userId,
            "friendship_type": FriendshipType.friend.rawValue,
            "connected_at": Date().timeIntervalSince1970,
            "is_active": true
        ]
        
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: friendshipsCollection,
            documentId: ID.unique(),
            data: reciprocalFriendshipData
        )
    }
    
    func removeFriend(_ userId: String, friendId: String) async throws {
        logger.info("Removing friend relationship: \(userId) <-> \(friendId)")
        
        // Remove both directions of the friendship
        let queries = [
            [Query.equal("user_id", value: userId), Query.equal("friend_id", value: friendId)],
            [Query.equal("user_id", value: friendId), Query.equal("friend_id", value: userId)]
        ]
        
        for query in queries {
            let documents = try await databases.listDocuments(
                databaseId: Configuration.appwriteProjectId,
                collectionId: friendshipsCollection,
                queries: query
            )
            
            for document in documents.documents {
                try await databases.deleteDocument(
                    databaseId: Configuration.appwriteProjectId,
                    collectionId: friendshipsCollection,
                    documentId: document.id
                )
            }
        }
    }
    
    func getFriends(_ userId: String, limit: Int?, offset: Int?) async throws -> [GolfFriend] {
        logger.debug("Fetching friends for user: \(userId)")
        
        var query = [
            Query.equal("user_id", value: userId),
            Query.equal("is_active", value: true)
        ]
        
        if let limit = limit {
            query.append(Query.limit(limit))
        }
        
        if let offset = offset {
            query.append(Query.offset(offset))
        }
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: friendshipsCollection,
            queries: query
        )
        
        var friends: [GolfFriend] = []
        
        for document in documents.documents {
            guard let friendId = document.data["friend_id"] as? String,
                  let friendshipTypeRaw = document.data["friendship_type"] as? String,
                  let friendshipType = FriendshipType(rawValue: friendshipTypeRaw),
                  let connectedAt = document.data["connected_at"] as? Double else {
                continue
            }
            
            if let friendProfile = try? await getUserProfile(friendId) {
                friends.append(GolfFriend(
                    userId: friendId,
                    profile: friendProfile,
                    friendshipType: friendshipType,
                    connectedAt: Date(timeIntervalSince1970: connectedAt),
                    mutualFriendsCount: 0, // Would be calculated
                    sharedRoundsCount: 0, // Would be calculated
                    lastInteractionAt: Date()
                ))
            }
        }
        
        return friends
    }
    
    func updateSocialVisibility(_ userId: String, visibility: SocialVisibility) async throws {
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: userProfilesCollection,
            documentId: userId,
            data: [
                "social_visibility": visibility.rawValue,
                "updated_at": Date().timeIntervalSince1970
            ]
        )
    }
    
    func blockUser(_ userId: String, blockedUserId: String) async throws {
        // Implementation for blocking users
        logger.info("Blocking user: \(userId) blocks \(blockedUserId)")
        // Would create a blocked users record
    }
    
    func unblockUser(_ userId: String, blockedUserId: String) async throws {
        // Implementation for unblocking users
        logger.info("Unblocking user: \(userId) unblocks \(blockedUserId)")
        // Would remove blocked users record
    }
    
    // MARK: - Achievement System
    
    func getUserAchievements(_ userId: String) async throws -> [Achievement] {
        logger.debug("Fetching achievements for user: \(userId)")
        
        let query = [Query.equal("user_id", value: userId)]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: achievementsCollection,
            queries: query
        )
        
        return try documents.documents.map(mapDocumentToAchievement)
    }
    
    func awardAchievement(_ userId: String, achievementId: String) async throws -> Achievement {
        logger.info("Awarding achievement \(achievementId) to user \(userId)")
        
        let achievementData: [String: Any] = [
            "user_id": userId,
            "achievement_id": achievementId,
            "earned_at": Date().timeIntervalSince1970,
            "progress": 100.0
        ]
        
        let document = try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: achievementsCollection,
            documentId: ID.unique(),
            data: achievementData
        )
        
        return try mapDocumentToAchievement(document)
    }
    
    func getAchievementProgress(_ userId: String, achievementId: String) async throws -> AchievementProgress {
        // Implementation would track progress toward specific achievements
        return AchievementProgress(
            current: 0.0,
            target: 100.0,
            percentage: 0.0,
            isCompleted: false,
            lastUpdatedAt: Date()
        )
    }
    
    func getLeaderboardPosition(_ userId: String, leaderboardType: LeaderboardType) async throws -> LeaderboardPosition {
        // Implementation would calculate user's position on various leaderboards
        return LeaderboardPosition(
            leaderboardType: leaderboardType,
            position: 0,
            totalParticipants: 0,
            score: 0.0,
            category: nil,
            period: .monthly
        )
    }
    
    // MARK: - User Preferences & Settings
    
    func updateNotificationPreferences(_ userId: String, preferences: NotificationPreferences) async throws {
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: userProfilesCollection,
            documentId: userId,
            data: [
                "notification_preferences": try encodeNotificationPreferences(preferences),
                "updated_at": Date().timeIntervalSince1970
            ]
        )
    }
    
    func updateGamePreferences(_ userId: String, preferences: GamePreferences) async throws {
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: userProfilesCollection,
            documentId: userId,
            data: [
                "game_preferences": try encodeGamePreferences(preferences),
                "updated_at": Date().timeIntervalSince1970
            ]
        )
    }
    
    func updateDisplayPreferences(_ userId: String, preferences: DisplayPreferences) async throws {
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: userProfilesCollection,
            documentId: userId,
            data: [
                "display_preferences": try encodeDisplayPreferences(preferences),
                "updated_at": Date().timeIntervalSince1970
            ]
        )
    }
    
    func getUserPreferences(_ userId: String) async throws -> UserPreferences {
        let profile = try await getUserProfile(userId)
        return profile.preferences
    }
    
    // MARK: - Profile Validation & Verification
    
    func verifyGolfHandicap(_ userId: String, handicapIndex: Double, verificationData: HandicapVerification) async throws -> Bool {
        logger.info("Verifying golf handicap for user \(userId): \(handicapIndex)")
        
        // Implementation would validate handicap with external authorities
        // For now, return success if basic validation passes
        guard handicapIndex >= -4.0 && handicapIndex <= 54.0 else {
            return false
        }
        
        // Update handicap with verification
        try await updateHandicapIndex(userId, handicapIndex: handicapIndex)
        
        return true
    }
    
    func requestProfileVerification(_ userId: String, verificationType: VerificationType) async throws -> VerificationRequest {
        logger.info("Creating verification request for user \(userId): \(verificationType)")
        
        let requestData: [String: Any] = [
            "user_id": userId,
            "verification_type": verificationType.rawValue,
            "status": VerificationRequestStatus.pending.rawValue,
            "submitted_at": Date().timeIntervalSince1970
        ]
        
        let document = try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: verificationRequestsCollection,
            documentId: ID.unique(),
            data: requestData
        )
        
        return try mapDocumentToVerificationRequest(document)
    }
    
    func getVerificationStatus(_ userId: String) async throws -> VerificationStatus {
        // Implementation would check current verification status
        return VerificationStatus(
            isVerified: false,
            verificationLevel: .unverified,
            verifiedAspects: [],
            lastVerifiedAt: nil,
            trustScore: 0.0
        )
    }
    
    // MARK: - User Activity & Analytics
    
    func recordUserActivity(_ userId: String, activity: UserActivity) async throws {
        logger.debug("Recording user activity: \(userId), \(activity.type)")
        
        let activityData: [String: Any] = [
            "user_id": userId,
            "activity_type": activity.type.rawValue,
            "metadata": activity.metadata,
            "location_latitude": activity.location?.coordinate.latitude ?? NSNull(),
            "location_longitude": activity.location?.coordinate.longitude ?? NSNull(),
            "session_id": activity.sessionId ?? "",
            "timestamp": activity.timestamp.timeIntervalSince1970
        ]
        
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: userActivitiesCollection,
            documentId: ID.unique(),
            data: activityData
        )
    }
    
    func getUserActivitySummary(_ userId: String, period: ActivityPeriod) async throws -> ActivitySummary {
        logger.debug("Fetching activity summary for user \(userId), period: \(period)")
        
        // Implementation would aggregate activity data
        return ActivitySummary(
            period: period,
            totalActivities: 0,
            uniqueDaysActive: 0,
            averageSessionDuration: 0,
            mostCommonActivities: [],
            peakActivityTimes: [],
            engagementScore: 0.0
        )
    }
    
    func getUserEngagementMetrics(_ userId: String) async throws -> EngagementMetrics {
        // Implementation would calculate engagement metrics
        return EngagementMetrics(
            dailyActiveUser: false,
            weeklyActiveUser: false,
            monthlyActiveUser: false,
            sessionsThisWeek: 0,
            averageSessionDuration: 0,
            retentionScore: 0.0,
            featureAdoptionRate: 0.0
        )
    }
    
    // MARK: - Profile Search & Discovery
    
    func searchUsers(query: UserSearchQuery) async throws -> [GolfUserProfile] {
        logger.debug("Searching users with query: \(query.searchTerm ?? "no term")")
        
        var queries: [String] = []
        
        if let searchTerm = query.searchTerm, !searchTerm.isEmpty {
            queries.append(Query.search("display_name", searchTerm))
        }
        
        if let handicapRange = query.handicapRange {
            queries.append(Query.greaterThanEqual("handicap_index", value: handicapRange.minimum))
            queries.append(Query.lessThanEqual("handicap_index", value: handicapRange.maximum))
        }
        
        if let playingFrequency = query.playingFrequency {
            queries.append(Query.equal("playing_frequency", value: playingFrequency.rawValue))
        }
        
        if query.verifiedOnly {
            queries.append(Query.equal("verification_status.is_verified", value: true))
        }
        
        queries.append(Query.limit(query.limit))
        queries.append(Query.offset(query.offset))
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: userProfilesCollection,
            queries: queries
        )
        
        return try documents.documents.compactMap { document in
            try? mapDocumentToGolfUserProfile(document)
        }
    }
    
    func getSuggestedFriends(_ userId: String, limit: Int) async throws -> [GolfUserProfile] {
        // Implementation would suggest friends based on various factors
        // For now, return empty array
        return []
    }
    
    func getNearbyGolfers(_ userId: String, location: CLLocation, radius: Double) async throws -> [NearbyGolfer] {
        // Implementation would find nearby golfers using geolocation
        return []
    }
    
    // MARK: - Private Helper Methods
    
    private func mapDocumentToGolfUserProfile(_ document: Document) throws -> GolfUserProfile {
        // Implementation would map Appwrite document to GolfUserProfile
        // This is a complex mapping that would handle all the nested structures
        
        let id = document.id
        let email = document.data["email"] as? String ?? ""
        let displayName = document.data["display_name"] as? String ?? ""
        let firstName = document.data["first_name"] as? String
        let lastName = document.data["last_name"] as? String
        let createdAt = Date(timeIntervalSince1970: document.data["created_at"] as? Double ?? Date().timeIntervalSince1970)
        let lastActiveAt = Date(timeIntervalSince1970: document.data["last_active_at"] as? Double ?? Date().timeIntervalSince1970)
        
        // Create a minimal profile structure
        return GolfUserProfile(
            id: id,
            email: email,
            username: nil,
            displayName: displayName,
            firstName: firstName,
            lastName: lastName,
            profileImageURL: nil,
            coverImageURL: nil,
            bio: document.data["bio"] as? String,
            handicapIndex: document.data["handicap_index"] as? Double,
            handicapCertification: nil,
            golfPreferences: GolfPreferences(
                preferredTeeBox: .regular,
                playingStyle: .casual,
                courseTypes: [.parkland],
                preferredRegions: [],
                maxTravelDistance: 50.0,
                budgetRange: .moderate,
                preferredPlayTimes: [.morning],
                golfCartPreference: .flexible,
                weatherPreferences: WeatherPreferences(
                    minTemperature: nil,
                    maxTemperature: nil,
                    acceptableConditions: [.sunny, .partlyCloudy],
                    windSpeedLimit: nil
                )
            ),
            homeClub: nil,
            membershipType: nil,
            playingFrequency: .weekly,
            dateOfBirth: nil,
            location: nil,
            phoneNumber: document.data["phone_number"] as? String,
            emergencyContact: nil,
            createdAt: createdAt,
            lastActiveAt: lastActiveAt,
            profileCompleteness: document.data["profile_completeness"] as? Double ?? 0.0,
            verificationStatus: VerificationStatus(
                isVerified: false,
                verificationLevel: .unverified,
                verifiedAspects: [],
                lastVerifiedAt: nil,
                trustScore: 0.0
            ),
            privacySettings: PrivacySettings(
                profileVisibility: .public,
                dataProcessingConsent: true,
                analyticsOptOut: false,
                marketingOptOut: false
            ),
            socialVisibility: .friends,
            tenantMemberships: [],
            currentTenant: nil,
            golfStatistics: nil,
            achievements: [],
            leaderboardPositions: []
        )
    }
    
    private func recordHandicapEntry(userId: String, handicapIndex: Double, source: HandicapSource) async throws {
        let entryData: [String: Any] = [
            "user_id": userId,
            "handicap_index": handicapIndex,
            "recorded_at": Date().timeIntervalSince1970,
            "source": source.rawValue,
            "verification_level": VerificationLevel.basic.rawValue
        ]
        
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: handicapHistoryCollection,
            documentId: ID.unique(),
            data: entryData
        )
    }
    
    private func calculateProfileCompleteness(_ profile: GolfUserProfileCreate) -> Double {
        var score = 0.0
        let totalFields = 10.0
        
        if !profile.displayName.isEmpty { score += 1.0 }
        if profile.firstName?.isEmpty == false { score += 1.0 }
        if profile.lastName?.isEmpty == false { score += 1.0 }
        if profile.handicapIndex != nil { score += 1.0 }
        // Add more fields as needed
        
        return score / totalFields
    }
    
    private func processInvitationCode(userId: String, invitationCode: String, tenantId: String) async throws {
        // Implementation would process invitation codes
        logger.info("Processing invitation code for user \(userId)")
    }
    
    private func deleteUserRelatedData(userId: String, preserveProfile: Bool = false) async {
        // Delete related data across collections
        let collections = [
            handicapHistoryCollection,
            tenantMembershipsCollection,
            consentRecordsCollection,
            userActivitiesCollection,
            achievementsCollection,
            friendshipsCollection,
            verificationRequestsCollection
        ]
        
        for collection in collections {
            do {
                let query = [Query.equal("user_id", value: userId)]
                let documents = try await databases.listDocuments(
                    databaseId: Configuration.appwriteProjectId,
                    collectionId: collection,
                    queries: query
                )
                
                for document in documents.documents {
                    try await databases.deleteDocument(
                        databaseId: Configuration.appwriteProjectId,
                        collectionId: collection,
                        documentId: document.id
                    )
                }
            } catch {
                logger.error("Failed to delete from \(collection): \(error.localizedDescription)")
            }
        }
    }
    
    private func anonymizeUserData(userId: String) async throws {
        // Implementation would anonymize rather than delete user data
        let anonymousData: [String: Any] = [
            "display_name": "Anonymous User",
            "first_name": "",
            "last_name": "",
            "email": "anonymous@example.com",
            "phone_number": "",
            "bio": "",
            "updated_at": Date().timeIntervalSince1970
        ]
        
        try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: userProfilesCollection,
            documentId: userId,
            data: anonymousData
        )
    }
    
    // Additional mapping helper methods would be implemented here
    private func mapDocumentToHandicapEntry(_ document: Document) throws -> HandicapEntry {
        // Implementation would map document to HandicapEntry
        return HandicapEntry(
            id: document.id,
            userId: document.data["user_id"] as? String ?? "",
            handicapIndex: document.data["handicap_index"] as? Double ?? 0.0,
            recordedAt: Date(timeIntervalSince1970: document.data["recorded_at"] as? Double ?? 0),
            source: HandicapSource(rawValue: document.data["source"] as? String ?? "self_reported") ?? .selfReported,
            verificationLevel: VerificationLevel(rawValue: document.data["verification_level"] as? String ?? "basic") ?? .basic,
            notes: document.data["notes"] as? String
        )
    }
    
    private func mapDocumentToTenantMembership(_ document: Document) throws -> TenantMembership {
        return TenantMembership(
            tenantId: document.data["tenant_id"] as? String ?? "",
            userId: document.data["user_id"] as? String ?? "",
            role: TenantRole(rawValue: document.data["role"] as? String ?? "member") ?? .member,
            permissions: (document.data["permissions"] as? [String] ?? []).compactMap(Permission.init),
            joinedAt: Date(timeIntervalSince1970: document.data["joined_at"] as? Double ?? 0),
            isActive: document.data["is_active"] as? Bool ?? false
        )
    }
    
    private func mapDocumentToConsentRecord(_ document: Document) throws -> ConsentRecord {
        return ConsentRecord(
            id: document.id,
            consentType: ConsentType(rawValue: document.data["consent_type"] as? String ?? "data_processing") ?? .dataProcessing,
            version: document.data["version"] as? String ?? "1.0",
            givenAt: Date(timeIntervalSince1970: document.data["given_at"] as? Double ?? 0),
            expiresAt: document.data["expires_at"] as? Double != nil ? Date(timeIntervalSince1970: document.data["expires_at"] as! Double) : nil,
            ipAddress: document.data["ip_address"] as? String ?? "",
            userAgent: document.data["user_agent"] as? String ?? ""
        )
    }
    
    private func mapDocumentToAchievement(_ document: Document) throws -> Achievement {
        return Achievement(
            id: document.id,
            type: AchievementType(rawValue: document.data["type"] as? String ?? "scoring") ?? .scoring,
            title: document.data["title"] as? String ?? "",
            description: document.data["description"] as? String ?? "",
            iconURL: nil,
            earnedAt: document.data["earned_at"] as? Double != nil ? Date(timeIntervalSince1970: document.data["earned_at"] as! Double) : nil,
            progress: nil,
            rarity: AchievementRarity(rawValue: document.data["rarity"] as? String ?? "common") ?? .common,
            points: document.data["points"] as? Int ?? 0
        )
    }
    
    private func mapDocumentToVerificationRequest(_ document: Document) throws -> VerificationRequest {
        return VerificationRequest(
            id: document.id,
            userId: document.data["user_id"] as? String ?? "",
            verificationType: VerificationType(rawValue: document.data["verification_type"] as? String ?? "identity") ?? .identity,
            status: VerificationRequestStatus(rawValue: document.data["status"] as? String ?? "pending") ?? .pending,
            submittedAt: Date(timeIntervalSince1970: document.data["submitted_at"] as? Double ?? 0),
            reviewedAt: document.data["reviewed_at"] as? Double != nil ? Date(timeIntervalSince1970: document.data["reviewed_at"] as! Double) : nil,
            reviewerId: document.data["reviewer_id"] as? String,
            notes: document.data["notes"] as? String
        )
    }
    
    // Encoding helper methods for complex types
    private func encodeGolfPreferences(_ preferences: GolfPreferences) throws -> [String: Any] {
        return [
            "preferred_tee_box": preferences.preferredTeeBox.rawValue,
            "playing_style": preferences.playingStyle.rawValue,
            "course_types": preferences.courseTypes.map { $0.rawValue },
            "preferred_regions": preferences.preferredRegions,
            "max_travel_distance": preferences.maxTravelDistance,
            "budget_range": preferences.budgetRange.rawValue,
            "preferred_play_times": preferences.preferredPlayTimes.map { $0.rawValue },
            "golf_cart_preference": preferences.golfCartPreference.rawValue
        ]
    }
    
    private func encodeGolfClub(_ club: GolfClub) throws -> [String: Any] {
        return [
            "id": club.id,
            "name": club.name,
            "membership_type": club.membershipType.rawValue
        ]
    }
    
    private func encodeUserLocation(_ location: UserLocation) throws -> [String: Any] {
        return [
            "address": location.address ?? "",
            "city": location.city ?? "",
            "state": location.state ?? "",
            "country": location.country,
            "postal_code": location.postalCode ?? ""
        ]
    }
    
    private func encodeEmergencyContact(_ contact: EmergencyContact) throws -> [String: Any] {
        return [
            "name": contact.name,
            "phone_number": contact.phoneNumber,
            "relationship": contact.relationship,
            "email": contact.email ?? ""
        ]
    }
    
    private func encodePrivacySettings(_ settings: PrivacySettings) throws -> [String: Any] {
        return [
            "profile_visibility": settings.profileVisibility.rawValue,
            "data_processing_consent": settings.dataProcessingConsent,
            "analytics_opt_out": settings.analyticsOptOut,
            "marketing_opt_out": settings.marketingOptOut
        ]
    }
    
    private func encodeNotificationPreferences(_ preferences: NotificationPreferences) throws -> [String: Any] {
        return [
            "email_notifications": preferences.emailNotifications,
            "push_notifications": preferences.pushNotifications,
            "sms_notifications": preferences.smsNotifications,
            "security_alerts": preferences.securityAlerts
        ]
    }
    
    private func encodeGamePreferences(_ preferences: GamePreferences) throws -> [String: Any] {
        return [
            "scorecard_format": preferences.scorecardFormat.rawValue,
            "enable_gps": preferences.enableGPS,
            "auto_track_stats": preferences.autoTrackStats,
            "share_scores": preferences.shareScores,
            "enable_tips": preferences.enableTips
        ]
    }
    
    private func encodeDisplayPreferences(_ preferences: DisplayPreferences) throws -> [String: Any] {
        return [
            "theme": preferences.theme.rawValue,
            "units": preferences.units.rawValue,
            "language": preferences.language,
            "font_size": preferences.fontSize.rawValue
        ]
    }
}

// MARK: - Validation Errors

enum ValidationError: LocalizedError {
    case invalidHandicapIndex
    case invalidEmailFormat
    case invalidPhoneNumber
    case requiredFieldMissing(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidHandicapIndex:
            return "Handicap index must be between -4.0 and 54.0"
        case .invalidEmailFormat:
            return "Invalid email format"
        case .invalidPhoneNumber:
            return "Invalid phone number format"
        case .requiredFieldMissing(let field):
            return "Required field missing: \(field)"
        }
    }
}