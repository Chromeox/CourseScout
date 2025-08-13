import Foundation
import Combine
import Appwrite

// MARK: - Social Challenge Service Implementation

@MainActor
class SocialChallengeService: SocialChallengeServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let appwriteManager: AppwriteManager
    private var subscriptions = Set<AnyCancellable>()
    private var realtimeSubscriptions = [String: AnyCancellable]()
    private let cache = SocialChallengeCache()
    
    // Publishers for real-time updates
    private let challengeUpdateSubject = PassthroughSubject<ChallengeUpdate, Error>()
    private let playerChallengeUpdateSubject = PassthroughSubject<PlayerChallengeUpdate, Error>()
    private let tournamentUpdateSubject = PassthroughSubject<TournamentUpdate, Error>()
    
    // MARK: - Configuration
    
    private let databaseId = "golf_finder_db"
    private let challengesCollection = "social_challenges"
    private let participationsCollection = "challenge_participations"
    private let scoresCollection = "challenge_scores"
    private let invitationsCollection = "challenge_invitations"
    private let tournamentsCollection = "tournaments"
    private let templatesCollection = "challenge_templates"
    private let analyticsCollection = "challenge_analytics"
    
    // MARK: - Initialization
    
    init(appwriteManager: AppwriteManager = .shared) {
        self.appwriteManager = appwriteManager
    }
    
    // MARK: - Challenge Management
    
    func createChallenge(_ challenge: SocialChallenge) async throws -> SocialChallenge {
        do {
            let data = try mapChallengeToDocument(challenge)
            
            let document = try await appwriteManager.databases.createDocument(
                databaseId: databaseId,
                collectionId: challengesCollection,
                documentId: challenge.id.isEmpty ? ID.unique() : challenge.id,
                data: data
            )
            
            let createdChallenge = try mapDocumentToChallenge(document)
            
            // Cache the result
            cache.setChallenge(createdChallenge)
            
            // Send real-time update
            let update = ChallengeUpdate(
                challengeId: createdChallenge.id,
                updateType: .challengeCompleted, // Would be challengeCreated in real enum
                playerId: createdChallenge.createdBy,
                data: [:],
                timestamp: Date()
            )
            challengeUpdateSubject.send(update)
            
            return createdChallenge
        } catch {
            throw SocialChallengeError.challengeCreationFailed(error.localizedDescription)
        }
    }
    
    func getChallenge(id: String) async throws -> SocialChallenge {
        // Check cache first
        if let cached = cache.getChallenge(id: id) {
            return cached
        }
        
        do {
            let document = try await appwriteManager.databases.getDocument(
                databaseId: databaseId,
                collectionId: challengesCollection,
                documentId: id
            )
            
            let challenge = try mapDocumentToChallenge(document)
            
            // Fetch participants
            var challengeWithParticipants = challenge
            challengeWithParticipants.participants = try await getParticipants(for: id)
            
            // Cache and return
            cache.setChallenge(challengeWithParticipants)
            return challengeWithParticipants
            
        } catch {
            throw SocialChallengeError.challengeNotFound
        }
    }
    
    func updateChallenge(_ challenge: SocialChallenge) async throws -> SocialChallenge {
        do {
            let data = try mapChallengeToDocument(challenge)
            
            let document = try await appwriteManager.databases.updateDocument(
                databaseId: databaseId,
                collectionId: challengesCollection,
                documentId: challenge.id,
                data: data
            )
            
            let updatedChallenge = try mapDocumentToChallenge(document)
            
            // Update cache
            cache.setChallenge(updatedChallenge)
            
            return updatedChallenge
        } catch {
            throw SocialChallengeError.updateFailed(error.localizedDescription)
        }
    }
    
    func deleteChallenge(id: String, requesterId: String) async throws {
        // Verify requester is creator or admin
        let challenge = try await getChallenge(id: id)
        guard challenge.createdBy == requesterId else {
            throw SocialChallengeError.unauthorizedAccess
        }
        
        do {
            // Delete related data first
            try await deleteRelatedChallengeData(challengeId: id)
            
            // Delete the challenge
            try await appwriteManager.databases.deleteDocument(
                databaseId: databaseId,
                collectionId: challengesCollection,
                documentId: id
            )
            
            // Clear cache
            cache.removeChallenge(id: id)
        } catch {
            throw SocialChallengeError.deletionFailed(error.localizedDescription)
        }
    }
    
    func getChallenges(for courseId: String, filters: ChallengeFilters?) async throws -> [SocialChallenge] {
        var queries = [
            Query.equal("course_id", value: courseId),
            Query.equal("is_active", value: true),
            Query.orderDesc("updated_at")
        ]
        
        // Apply filters
        if let filters = filters {
            if let status = filters.status {
                queries.append(Query.equal("status", value: status.rawValue))
            }
            if let type = filters.type {
                queries.append(Query.equal("challenge_type", value: type.rawValue))
            }
            if let isPublic = filters.isPublic {
                queries.append(Query.equal("is_public", value: isPublic))
            }
        }
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: challengesCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToChallenge(document)
            }
        } catch {
            throw SocialChallengeError.fetchFailed(error.localizedDescription)
        }
    }
    
    func getCreatedChallenges(by playerId: String) async throws -> [SocialChallenge] {
        let queries = [
            Query.equal("created_by", value: playerId),
            Query.orderDesc("created_at")
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: challengesCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToChallenge(document)
            }
        } catch {
            throw SocialChallengeError.fetchFailed(error.localizedDescription)
        }
    }
    
    func getParticipatingChallenges(for playerId: String) async throws -> [SocialChallenge] {
        // Get participations for player
        let participationQueries = [
            Query.equal("player_id", value: playerId),
            Query.equal("status", value: ChallengeParticipation.ParticipationStatus.active.rawValue)
        ]
        
        do {
            let participationResponse = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: participationsCollection,
                queries: participationQueries
            )
            
            let challengeIds = participationResponse.documents.compactMap { doc in
                doc.data["challenge_id"]?.value as? String
            }
            
            var challenges: [SocialChallenge] = []
            for challengeId in challengeIds {
                do {
                    let challenge = try await getChallenge(id: challengeId)
                    challenges.append(challenge)
                } catch {
                    // Skip challenges that can't be loaded
                    continue
                }
            }
            
            return challenges
        } catch {
            throw SocialChallengeError.fetchFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Challenge Participation
    
    func joinChallenge(challengeId: String, playerId: String) async throws -> ChallengeParticipation {
        // Verify challenge exists and is joinable
        let challenge = try await getChallenge(id: challengeId)
        
        guard challenge.isPublic else {
            throw SocialChallengeError.challengeNotPublic
        }
        
        guard challenge.participants.count < challenge.maxEntries else {
            throw SocialChallengeError.challengeFull
        }
        
        // Check if already participating
        if challenge.participants.contains(playerId) {
            throw SocialChallengeError.alreadyParticipating
        }
        
        let participation = ChallengeParticipation(
            id: ID.unique(),
            challengeId: challengeId,
            playerId: playerId,
            joinedAt: Date(),
            status: .active,
            scores: [],
            currentPosition: nil,
            achievements: []
        )
        
        do {
            let data = try mapParticipationToDocument(participation)
            
            _ = try await appwriteManager.databases.createDocument(
                databaseId: databaseId,
                collectionId: participationsCollection,
                documentId: participation.id,
                data: data
            )
            
            // Send real-time update
            let update = ChallengeUpdate(
                challengeId: challengeId,
                updateType: .participantJoined,
                playerId: playerId,
                data: [:],
                timestamp: Date()
            )
            challengeUpdateSubject.send(update)
            
            return participation
        } catch {
            throw SocialChallengeError.joinFailed(error.localizedDescription)
        }
    }
    
    func acceptInvitation(challengeId: String, playerId: String, invitationId: String) async throws -> ChallengeParticipation {
        // Verify invitation exists and is valid
        let invitation = try await getInvitation(id: invitationId)
        
        guard invitation.recipientId == playerId,
              invitation.challengeId == challengeId,
              invitation.status == .pending else {
            throw SocialChallengeError.invalidInvitation
        }
        
        // Update invitation status
        try await updateInvitationStatus(invitationId: invitationId, status: .accepted)
        
        // Join the challenge
        return try await joinChallenge(challengeId: challengeId, playerId: playerId)
    }
    
    func declineInvitation(challengeId: String, playerId: String, invitationId: String) async throws {
        // Verify invitation
        let invitation = try await getInvitation(id: invitationId)
        
        guard invitation.recipientId == playerId,
              invitation.challengeId == challengeId,
              invitation.status == .pending else {
            throw SocialChallengeError.invalidInvitation
        }
        
        // Update invitation status
        try await updateInvitationStatus(invitationId: invitationId, status: .declined)
    }
    
    func leaveChallenge(challengeId: String, playerId: String) async throws {
        // Find participation
        let participationQueries = [
            Query.equal("challenge_id", value: challengeId),
            Query.equal("player_id", value: playerId),
            Query.equal("status", value: ChallengeParticipation.ParticipationStatus.active.rawValue)
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: participationsCollection,
                queries: participationQueries
            )
            
            guard let participationDoc = response.documents.first else {
                throw SocialChallengeError.participationNotFound
            }
            
            // Update participation status
            let updatedData = [
                "status": ChallengeParticipation.ParticipationStatus.withdrawn.rawValue
            ]
            
            _ = try await appwriteManager.databases.updateDocument(
                databaseId: databaseId,
                collectionId: participationsCollection,
                documentId: participationDoc.id,
                data: updatedData
            )
            
            // Send real-time update
            let update = ChallengeUpdate(
                challengeId: challengeId,
                updateType: .participantLeft,
                playerId: playerId,
                data: [:],
                timestamp: Date()
            )
            challengeUpdateSubject.send(update)
            
        } catch {
            throw SocialChallengeError.leaveFailed(error.localizedDescription)
        }
    }
    
    func submitChallengeScore(challengeId: String, playerId: String, scoreSubmission: ChallengeScoreSubmission) async throws -> ChallengeScore {
        // Verify participation
        let participationQueries = [
            Query.equal("challenge_id", value: challengeId),
            Query.equal("player_id", value: playerId),
            Query.equal("status", value: ChallengeParticipation.ParticipationStatus.active.rawValue)
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: participationsCollection,
                queries: participationQueries
            )
            
            guard let participationDoc = response.documents.first else {
                throw SocialChallengeError.participationNotFound
            }
            
            let challengeScore = ChallengeScore(
                id: ID.unique(),
                participationId: participationDoc.id,
                roundId: scoreSubmission.roundId,
                score: scoreSubmission.score,
                netScore: nil, // Calculate if handicap available
                submittedAt: scoreSubmission.submittedAt,
                verifiedAt: nil,
                status: .pending,
                holeByHole: scoreSubmission.holeByHole
            )
            
            let data = try mapChallengeScoreToDocument(challengeScore, scoreSubmission: scoreSubmission)
            
            _ = try await appwriteManager.databases.createDocument(
                databaseId: databaseId,
                collectionId: scoresCollection,
                documentId: challengeScore.id,
                data: data
            )
            
            // Update challenge standings
            try await updateChallengeStandings(challengeId: challengeId)
            
            // Send real-time update
            let update = ChallengeUpdate(
                challengeId: challengeId,
                updateType: .scoreSubmitted,
                playerId: playerId,
                data: ["score": AnyCodable(scoreSubmission.score)],
                timestamp: Date()
            )
            challengeUpdateSubject.send(update)
            
            return challengeScore
        } catch {
            throw SocialChallengeError.scoreSubmissionFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Challenge Invitations
    
    func inviteToChallenge(challengeId: String, inviterId: String, inviteeIds: [String], message: String?) async throws -> [ChallengeInvitation] {
        // Verify challenge exists and inviter is participant or creator
        let challenge = try await getChallenge(id: challengeId)
        
        guard challenge.createdBy == inviterId || challenge.participants.contains(inviterId) else {
            throw SocialChallengeError.unauthorizedAccess
        }
        
        var invitations: [ChallengeInvitation] = []
        
        for inviteeId in inviteeIds {
            let invitation = ChallengeInvitation(
                id: ID.unique(),
                challengeId: challengeId,
                senderId: inviterId,
                senderName: "Player", // Would get actual name in real implementation
                recipientId: inviteeId,
                message: message,
                sentAt: Date(),
                status: .pending,
                expiresAt: Date().addingTimeInterval(86400 * 7) // 1 week
            )
            
            do {
                let data = try mapInvitationToDocument(invitation)
                
                _ = try await appwriteManager.databases.createDocument(
                    databaseId: databaseId,
                    collectionId: invitationsCollection,
                    documentId: invitation.id,
                    data: data
                )
                
                invitations.append(invitation)
                
                // Send player update notification
                let playerUpdate = PlayerChallengeUpdate(
                    playerId: inviteeId,
                    challengeId: challengeId,
                    updateType: .invitationReceived,
                    data: ["invitationId": AnyCodable(invitation.id)],
                    timestamp: Date()
                )
                playerChallengeUpdateSubject.send(playerUpdate)
                
            } catch {
                // Continue with other invitations if one fails
                continue
            }
        }
        
        return invitations
    }
    
    func getPendingInvitations(for playerId: String) async throws -> [ChallengeInvitation] {
        let queries = [
            Query.equal("recipient_id", value: playerId),
            Query.equal("status", value: ChallengeInvitation.InvitationStatus.pending.rawValue),
            Query.orderDesc("sent_at")
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: invitationsCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToInvitation(document)
            }
        } catch {
            throw SocialChallengeError.fetchFailed(error.localizedDescription)
        }
    }
    
    func getSentInvitations(for challengeId: String) async throws -> [ChallengeInvitation] {
        let queries = [
            Query.equal("challenge_id", value: challengeId),
            Query.orderDesc("sent_at")
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: invitationsCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToInvitation(document)
            }
        } catch {
            throw SocialChallengeError.fetchFailed(error.localizedDescription)
        }
    }
    
    func cancelInvitation(invitationId: String, senderId: String) async throws {
        // Verify invitation exists and sender has permission
        let invitation = try await getInvitation(id: invitationId)
        
        guard invitation.senderId == senderId else {
            throw SocialChallengeError.unauthorizedAccess
        }
        
        try await updateInvitationStatus(invitationId: invitationId, status: .cancelled)
    }
    
    // MARK: - Head-to-Head Challenges
    
    func createHeadToHeadChallenge(challengerId: String, opponentId: String, challengeDetails: HeadToHeadChallengeDetails) async throws -> HeadToHeadChallenge {
        let headToHeadChallenge = HeadToHeadChallenge(
            id: ID.unique(),
            challengerId: challengerId,
            opponentId: opponentId,
            details: challengeDetails,
            status: .pending,
            createdAt: Date(),
            acceptedAt: nil,
            completedAt: nil,
            winner: nil,
            results: nil
        )
        
        do {
            let data = try mapHeadToHeadToDocument(headToHeadChallenge)
            
            _ = try await appwriteManager.databases.createDocument(
                databaseId: databaseId,
                collectionId: challengesCollection, // Could be separate collection
                documentId: headToHeadChallenge.id,
                data: data
            )
            
            // Notify opponent
            let playerUpdate = PlayerChallengeUpdate(
                playerId: opponentId,
                challengeId: headToHeadChallenge.id,
                updateType: .invitationReceived,
                data: ["challengerId": AnyCodable(challengerId)],
                timestamp: Date()
            )
            playerChallengeUpdateSubject.send(playerUpdate)
            
            return headToHeadChallenge
        } catch {
            throw SocialChallengeError.headToHeadCreationFailed(error.localizedDescription)
        }
    }
    
    func acceptHeadToHeadChallenge(challengeId: String, accepterId: String) async throws -> HeadToHeadChallenge {
        // Implementation would fetch and update the head-to-head challenge
        // This is a simplified version
        throw SocialChallengeError.notImplemented
    }
    
    func declineHeadToHeadChallenge(challengeId: String, declinerId: String, reason: String?) async throws {
        // Implementation would update challenge status to declined
        throw SocialChallengeError.notImplemented
    }
    
    func getHeadToHeadHistory(player1Id: String, player2Id: String) async throws -> HeadToHeadHistory {
        // Implementation would query historical challenges between these players
        return HeadToHeadHistory(
            player1Id: player1Id,
            player2Id: player2Id,
            totalChallenges: 0,
            player1Wins: 0,
            player2Wins: 0,
            ties: 0,
            winPercentages: (player1: 0, player2: 0),
            recentChallenges: [],
            averageScoreDifference: 0,
            longestWinStreak: (playerId: player1Id, streak: 0),
            favoriteMatchups: []
        )
    }
    
    // MARK: - Tournament Management
    
    func createTournament(_ tournament: TournamentChallenge) async throws -> TournamentChallenge {
        do {
            let data = try mapTournamentToDocument(tournament)
            
            _ = try await appwriteManager.databases.createDocument(
                databaseId: databaseId,
                collectionId: tournamentsCollection,
                documentId: tournament.id,
                data: data
            )
            
            return tournament
        } catch {
            throw SocialChallengeError.tournamentCreationFailed(error.localizedDescription)
        }
    }
    
    func registerForTournament(tournamentId: String, playerId: String, registrationData: TournamentRegistration) async throws -> TournamentRegistration {
        // Implementation would handle tournament registration
        throw SocialChallengeError.notImplemented
    }
    
    func getTournamentLeaderboard(tournamentId: String) async throws -> TournamentLeaderboard {
        // Implementation would calculate and return tournament leaderboard
        return TournamentLeaderboard(
            tournamentId: tournamentId,
            currentRound: 1,
            totalRounds: 4,
            leaderboard: [],
            cutLine: nil,
            updatedAt: Date()
        )
    }
    
    func advanceTournamentRound(tournamentId: String, adminId: String) async throws -> TournamentRound {
        // Implementation would advance tournament to next round
        throw SocialChallengeError.notImplemented
    }
    
    func finalizeTournament(tournamentId: String, adminId: String) async throws -> TournamentResult {
        // Implementation would finalize tournament and distribute prizes
        throw SocialChallengeError.notImplemented
    }
    
    // MARK: - Challenge Scoring & Results
    
    func getChallengeStandings(challengeId: String) async throws -> ChallengeStandings {
        // Get all participations for the challenge
        let participationQueries = [
            Query.equal("challenge_id", value: challengeId),
            Query.equal("status", value: ChallengeParticipation.ParticipationStatus.active.rawValue)
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: participationsCollection,
                queries: participationQueries
            )
            
            var standings: [ChallengeStandings.ChallengeStandingEntry] = []
            
            for (index, participationDoc) in response.documents.enumerated() {
                let playerId = participationDoc.data["player_id"]?.value as? String ?? ""
                let playerName = "Player \(index + 1)" // Would get actual name
                
                let standingEntry = ChallengeStandings.ChallengeStandingEntry(
                    position: index + 1,
                    playerId: playerId,
                    playerName: playerName,
                    score: nil, // Would get latest score
                    progress: ChallengeProgress(
                        completed: false,
                        percentComplete: 0.5,
                        remainingTime: nil,
                        status: "Active"
                    ),
                    achievements: []
                )
                
                standings.append(standingEntry)
            }
            
            return ChallengeStandings(
                challengeId: challengeId,
                standings: standings,
                lastUpdated: Date()
            )
        } catch {
            throw SocialChallengeError.fetchFailed(error.localizedDescription)
        }
    }
    
    func getChallengeResults(challengeId: String) async throws -> ChallengeResults {
        // Implementation would compile final challenge results
        let standings = try await getChallengeStandings(challengeId: challengeId)
        
        return ChallengeResults(
            challengeId: challengeId,
            finalStandings: standings,
            winners: [],
            statistics: ChallengeResults.ChallengeStatistics(
                totalParticipants: standings.standings.count,
                completionRate: 0.8,
                averageScore: 85.0,
                scoreRange: (min: 75, max: 95),
                improvementRate: 0.1,
                engagementMetrics: ChallengeResults.ChallengeStatistics.EngagementMetrics(
                    dailyActiveParticipants: [:],
                    messagesSent: 0,
                    photosShared: 0,
                    averageSessionTime: 300
                )
            ),
            highlights: [],
            completedAt: Date()
        )
    }
    
    func awardPrizes(challengeId: String, adminId: String) async throws -> [PrizeAward] {
        // Implementation would distribute prizes to winners
        return []
    }
    
    func getChallengeAnalytics(challengeId: String) async throws -> ChallengeAnalytics {
        // Implementation would compile comprehensive challenge analytics
        return ChallengeAnalytics(
            challengeId: challengeId,
            participantMetrics: ChallengeAnalytics.ParticipantMetrics(
                totalInvited: 0,
                totalJoined: 0,
                conversionRate: 0,
                dropoutRate: 0,
                averageHandicap: 0,
                skillLevelDistribution: [:]
            ),
            engagementMetrics: ChallengeAnalytics.EngagementMetrics(
                messagesPerParticipant: 0,
                photosPerParticipant: 0,
                averageSessionLength: 0,
                dailyActiveUsers: [:],
                peakEngagementTime: nil
            ),
            performanceMetrics: ChallengeAnalytics.PerformanceMetrics(
                averageScoreImprovement: 0,
                handicapImpacts: [:],
                achievementDistribution: [:],
                completionTimes: []
            ),
            retentionMetrics: ChallengeAnalytics.RetentionMetrics(
                returnParticipantRate: 0,
                referralRate: 0,
                satisfactionScore: nil,
                likelihoodToRecommend: nil
            )
        )
    }
    
    // MARK: - Friend Challenges
    
    func getFriendChallenges(for playerId: String) async throws -> [FriendChallenge] {
        // Implementation would get challenges with friends
        return []
    }
    
    func createFriendChallenge(creatorId: String, friendIds: [String], challengeData: FriendChallengeData) async throws -> FriendChallenge {
        // Implementation would create challenge with specific friends
        throw SocialChallengeError.notImplemented
    }
    
    func getRecommendedChallenges(for playerId: String) async throws -> [ChallengeRecommendation] {
        // Implementation would use ML/algorithms to recommend challenges
        return []
    }
    
    // MARK: - Real-time Updates
    
    func subscribeToChallenge(challengeId: String) -> AnyPublisher<ChallengeUpdate, Error> {
        // Set up real-time subscription for challenge updates
        let realtimeStream = appwriteManager.realtime.subscribe(
            channels: ["databases.\(databaseId).collections.\(challengesCollection).documents.\(challengeId)"]
        )
        
        let subscription = realtimeStream
            .compactMap { [weak self] response in
                self?.processChallengeUpdate(response, for: challengeId)
            }
            .subscribe(challengeUpdateSubject)
        
        realtimeSubscriptions[challengeId] = subscription
        
        return challengeUpdateSubject
            .filter { $0.challengeId == challengeId }
            .eraseToAnyPublisher()
    }
    
    func subscribeToPlayerChallenges(playerId: String) -> AnyPublisher<PlayerChallengeUpdate, Error> {
        return playerChallengeUpdateSubject
            .filter { $0.playerId == playerId }
            .eraseToAnyPublisher()
    }
    
    func subscribeToTournament(tournamentId: String) -> AnyPublisher<TournamentUpdate, Error> {
        return tournamentUpdateSubject
            .filter { $0.tournamentId == tournamentId }
            .eraseToAnyPublisher()
    }
    
    func unsubscribeFromChallenge(challengeId: String) {
        realtimeSubscriptions[challengeId]?.cancel()
        realtimeSubscriptions.removeValue(forKey: challengeId)
    }
    
    func unsubscribeFromAll() {
        realtimeSubscriptions.values.forEach { $0.cancel() }
        realtimeSubscriptions.removeAll()
    }
    
    // MARK: - Challenge Discovery
    
    func searchChallenges(query: String, filters: ChallengeSearchFilters?) async throws -> [SocialChallenge] {
        var queries = [Query.search("name", query)]
        
        if let filters = filters {
            if let courseId = filters.courseId {
                queries.append(Query.equal("course_id", value: courseId))
            }
            if let skillLevel = filters.skillLevel {
                queries.append(Query.equal("skill_level", value: skillLevel.rawValue))
            }
        }
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: challengesCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToChallenge(document)
            }
        } catch {
            throw SocialChallengeError.searchFailed(error.localizedDescription)
        }
    }
    
    func getTrendingChallenges(courseId: String?, limit: Int?) async throws -> [SocialChallenge] {
        var queries = [
            Query.orderDesc("participant_count"),
            Query.equal("is_active", value: true)
        ]
        
        if let courseId = courseId {
            queries.append(Query.equal("course_id", value: courseId))
        }
        
        if let limit = limit {
            queries.append(Query.limit(limit))
        }
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: challengesCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToChallenge(document)
            }
        } catch {
            throw SocialChallengeError.fetchFailed(error.localizedDescription)
        }
    }
    
    func getFeaturedChallenges() async throws -> [SocialChallenge] {
        let queries = [
            Query.equal("is_featured", value: true),
            Query.equal("is_active", value: true),
            Query.orderDesc("featured_priority")
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: challengesCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToChallenge(document)
            }
        } catch {
            throw SocialChallengeError.fetchFailed(error.localizedDescription)
        }
    }
    
    func getChallengesByCategory(_ category: ChallengeCategory) async throws -> [SocialChallenge] {
        let queries = [
            Query.equal("category", value: category.rawValue),
            Query.equal("is_active", value: true),
            Query.orderDesc("created_at")
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: challengesCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToChallenge(document)
            }
        } catch {
            throw SocialChallengeError.fetchFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Challenge Templates
    
    func getChallengeTemplates() async throws -> [ChallengeTemplate] {
        let queries = [
            Query.orderDesc("popularity"),
            Query.limit(50)
        ]
        
        do {
            let response = try await appwriteManager.databases.listDocuments(
                databaseId: databaseId,
                collectionId: templatesCollection,
                queries: queries
            )
            
            return try response.documents.compactMap { document in
                try mapDocumentToTemplate(document)
            }
        } catch {
            throw SocialChallengeError.fetchFailed(error.localizedDescription)
        }
    }
    
    func createChallengeFromTemplate(templateId: String, creatorId: String, customizations: TemplateCustomizations) async throws -> SocialChallenge {
        // Implementation would create challenge from template with customizations
        throw SocialChallengeError.notImplemented
    }
    
    func saveAsTemplate(challengeId: String, creatorId: String, templateName: String) async throws -> ChallengeTemplate {
        // Implementation would save challenge as reusable template
        throw SocialChallengeError.notImplemented
    }
}

// MARK: - Private Helper Methods

private extension SocialChallengeService {
    
    func getParticipants(for challengeId: String) async throws -> [String] {
        let queries = [
            Query.equal("challenge_id", value: challengeId),
            Query.equal("status", value: ChallengeParticipation.ParticipationStatus.active.rawValue)
        ]
        
        let response = try await appwriteManager.databases.listDocuments(
            databaseId: databaseId,
            collectionId: participationsCollection,
            queries: queries
        )
        
        return response.documents.compactMap { doc in
            doc.data["player_id"]?.value as? String
        }
    }
    
    func deleteRelatedChallengeData(challengeId: String) async throws {
        // Delete participations
        let participationQueries = [Query.equal("challenge_id", value: challengeId)]
        let participationResponse = try await appwriteManager.databases.listDocuments(
            databaseId: databaseId,
            collectionId: participationsCollection,
            queries: participationQueries
        )
        
        for doc in participationResponse.documents {
            try await appwriteManager.databases.deleteDocument(
                databaseId: databaseId,
                collectionId: participationsCollection,
                documentId: doc.id
            )
        }
        
        // Delete invitations
        let invitationQueries = [Query.equal("challenge_id", value: challengeId)]
        let invitationResponse = try await appwriteManager.databases.listDocuments(
            databaseId: databaseId,
            collectionId: invitationsCollection,
            queries: invitationQueries
        )
        
        for doc in invitationResponse.documents {
            try await appwriteManager.databases.deleteDocument(
                databaseId: databaseId,
                collectionId: invitationsCollection,
                documentId: doc.id
            )
        }
    }
    
    func getInvitation(id: String) async throws -> ChallengeInvitation {
        let document = try await appwriteManager.databases.getDocument(
            databaseId: databaseId,
            collectionId: invitationsCollection,
            documentId: id
        )
        
        return try mapDocumentToInvitation(document)
    }
    
    func updateInvitationStatus(invitationId: String, status: ChallengeInvitation.InvitationStatus) async throws {
        let updatedData = ["status": status.rawValue]
        
        _ = try await appwriteManager.databases.updateDocument(
            databaseId: databaseId,
            collectionId: invitationsCollection,
            documentId: invitationId,
            data: updatedData
        )
    }
    
    func updateChallengeStandings(challengeId: String) async throws {
        // Implementation would recalculate and update challenge standings
        // This is where leaderboard positions would be recalculated
    }
    
    func processChallengeUpdate(_ response: AppwriteModels.RealtimeResponse, for challengeId: String) -> ChallengeUpdate? {
        // Process Appwrite real-time response and create ChallengeUpdate
        return nil
    }
    
    // MARK: - Document Mapping
    
    func mapChallengeToDocument(_ challenge: SocialChallenge) throws -> [String: Any] {
        return [
            "name": challenge.name,
            "description": challenge.description,
            "created_by": challenge.createdBy,
            "course_id": challenge.courseId,
            "challenge_type": challenge.targetMetric.rawValue,
            "start_date": challenge.startDate.iso8601,
            "end_date": challenge.endDate.iso8601,
            "is_public": challenge.isPublic,
            "max_entries": challenge.maxEntries,
            "entry_fee": challenge.entryFee ?? 0,
            "target_score": challenge.targetScore ?? 0
        ]
    }
    
    func mapDocumentToChallenge(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> SocialChallenge {
        return SocialChallenge(
            id: document.id,
            name: document.data["name"]?.value as? String ?? "",
            description: document.data["description"]?.value as? String ?? "",
            createdBy: document.data["created_by"]?.value as? String ?? "",
            participants: [], // Will be populated separately
            courseId: document.data["course_id"]?.value as? String ?? "",
            targetScore: document.data["target_score"]?.value as? Int,
            targetMetric: SocialChallenge.ChallengeMetric(rawValue: document.data["challenge_type"]?.value as? String ?? "lowest_score") ?? .lowestScore,
            startDate: Date(), // Would parse from document
            endDate: Date().addingTimeInterval(86400), // Would parse from document
            isPublic: document.data["is_public"]?.value as? Bool ?? true,
            entryFee: document.data["entry_fee"]?.value as? Double,
            winner: document.data["winner"]?.value as? String,
            prizes: [], // Would parse prizes array
            maxEntries: document.data["max_entries"]?.value as? Int ?? 100
        )
    }
    
    func mapParticipationToDocument(_ participation: ChallengeParticipation) throws -> [String: Any] {
        return [
            "challenge_id": participation.challengeId,
            "player_id": participation.playerId,
            "joined_at": participation.joinedAt.iso8601,
            "status": participation.status.rawValue
        ]
    }
    
    func mapChallengeScoreToDocument(_ score: ChallengeScore, scoreSubmission: ChallengeScoreSubmission) throws -> [String: Any] {
        return [
            "participation_id": score.participationId,
            "round_id": score.roundId ?? "",
            "score": score.score,
            "submitted_at": score.submittedAt.iso8601,
            "status": score.status.rawValue
        ]
    }
    
    func mapInvitationToDocument(_ invitation: ChallengeInvitation) throws -> [String: Any] {
        return [
            "challenge_id": invitation.challengeId,
            "sender_id": invitation.senderId,
            "recipient_id": invitation.recipientId,
            "message": invitation.message ?? "",
            "sent_at": invitation.sentAt.iso8601,
            "status": invitation.status.rawValue
        ]
    }
    
    func mapDocumentToInvitation(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> ChallengeInvitation {
        return ChallengeInvitation(
            id: document.id,
            challengeId: document.data["challenge_id"]?.value as? String ?? "",
            senderId: document.data["sender_id"]?.value as? String ?? "",
            senderName: "Player", // Would get actual name
            recipientId: document.data["recipient_id"]?.value as? String ?? "",
            message: document.data["message"]?.value as? String,
            sentAt: Date(), // Would parse from document
            status: ChallengeInvitation.InvitationStatus(rawValue: document.data["status"]?.value as? String ?? "pending") ?? .pending,
            expiresAt: nil // Would parse if present
        )
    }
    
    func mapHeadToHeadToDocument(_ headToHead: HeadToHeadChallenge) throws -> [String: Any] {
        return [
            "challenger_id": headToHead.challengerId,
            "opponent_id": headToHead.opponentId,
            "title": headToHead.details.title,
            "course_id": headToHead.details.courseId,
            "game_type": headToHead.details.gameType.rawValue,
            "status": headToHead.status.rawValue,
            "created_at": headToHead.createdAt.iso8601
        ]
    }
    
    func mapTournamentToDocument(_ tournament: TournamentChallenge) throws -> [String: Any] {
        return [
            "name": tournament.name,
            "description": tournament.description ?? "",
            "creator_id": tournament.creatorId,
            "course_id": tournament.courseId,
            "format": tournament.format.rawValue,
            "structure": tournament.structure.rawValue,
            "entry_fee": tournament.entryFee ?? 0,
            "max_participants": tournament.maxParticipants,
            "start_date": tournament.startDate.iso8601,
            "end_date": tournament.endDate.iso8601,
            "status": tournament.status.rawValue
        ]
    }
    
    func mapDocumentToTemplate(_ document: AppwriteModels.Document<[String: AnyCodable]>) throws -> ChallengeTemplate {
        return ChallengeTemplate(
            id: document.id,
            name: document.data["name"]?.value as? String ?? "",
            description: document.data["description"]?.value as? String ?? "",
            creatorId: document.data["creator_id"]?.value as? String ?? "",
            category: ChallengeCategory(rawValue: document.data["category"]?.value as? String ?? "competitive") ?? .competitive,
            templateData: ChallengeTemplate.TemplateData(
                challengeType: .strokePlay,
                duration: 86400,
                maxParticipants: 50,
                rules: [],
                scoringMethod: .lowest,
                prizeStructure: nil
            ),
            popularity: document.data["popularity"]?.value as? Int ?? 0,
            rating: document.data["rating"]?.value as? Double ?? 0,
            tags: [],
            createdAt: Date()
        )
    }
}

// MARK: - Social Challenge Cache

private class SocialChallengeCache {
    private var challenges: [String: SocialChallenge] = [:]
    private var invitations: [String: [ChallengeInvitation]] = [:]
    private let cacheQueue = DispatchQueue(label: "social.challenge.cache", attributes: .concurrent)
    
    func getChallenge(id: String) -> SocialChallenge? {
        return cacheQueue.sync { challenges[id] }
    }
    
    func setChallenge(_ challenge: SocialChallenge) {
        cacheQueue.async(flags: .barrier) {
            self.challenges[challenge.id] = challenge
        }
    }
    
    func removeChallenge(id: String) {
        cacheQueue.async(flags: .barrier) {
            self.challenges.removeValue(forKey: id)
        }
    }
    
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.challenges.removeAll()
            self.invitations.removeAll()
        }
    }
}

// MARK: - Social Challenge Errors

enum SocialChallengeError: Error {
    case challengeCreationFailed(String)
    case challengeNotFound
    case updateFailed(String)
    case unauthorizedAccess
    case deletionFailed(String)
    case fetchFailed(String)
    case challengeNotPublic
    case challengeFull
    case alreadyParticipating
    case joinFailed(String)
    case invalidInvitation
    case participationNotFound
    case leaveFailed(String)
    case scoreSubmissionFailed(String)
    case headToHeadCreationFailed(String)
    case tournamentCreationFailed(String)
    case searchFailed(String)
    case notImplemented
    
    var localizedDescription: String {
        switch self {
        case .challengeCreationFailed(let error):
            return "Failed to create challenge: \(error)"
        case .challengeNotFound:
            return "Challenge not found"
        case .updateFailed(let error):
            return "Failed to update challenge: \(error)"
        case .unauthorizedAccess:
            return "Unauthorized access to challenge"
        case .deletionFailed(let error):
            return "Failed to delete challenge: \(error)"
        case .fetchFailed(let error):
            return "Failed to fetch data: \(error)"
        case .challengeNotPublic:
            return "Challenge is not public"
        case .challengeFull:
            return "Challenge is full"
        case .alreadyParticipating:
            return "Already participating in challenge"
        case .joinFailed(let error):
            return "Failed to join challenge: \(error)"
        case .invalidInvitation:
            return "Invalid invitation"
        case .participationNotFound:
            return "Participation not found"
        case .leaveFailed(let error):
            return "Failed to leave challenge: \(error)"
        case .scoreSubmissionFailed(let error):
            return "Failed to submit score: \(error)"
        case .headToHeadCreationFailed(let error):
            return "Failed to create head-to-head challenge: \(error)"
        case .tournamentCreationFailed(let error):
            return "Failed to create tournament: \(error)"
        case .searchFailed(let error):
            return "Search failed: \(error)"
        case .notImplemented:
            return "Feature not yet implemented"
        }
    }
}

// MARK: - Extensions

private extension Date {
    var iso8601: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

// MARK: - Additional Extensions for SocialChallenge

extension SocialChallenge {
    var maxEntries: Int {
        return 100 // Default value, would be part of model in real implementation
    }
}