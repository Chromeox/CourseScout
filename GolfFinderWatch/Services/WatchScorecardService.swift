import Foundation
import os.log

// MARK: - Watch Scorecard Service Protocol

protocol WatchScorecardServiceProtocol: AnyObject {
    // Active round management
    func startNewRound(courseId: String, teeType: SharedTeeType) async -> ActiveGolfRound?
    func getCurrentRound() async -> ActiveGolfRound?
    func endCurrentRound() async -> SharedScorecard?
    
    // Score entry
    func recordScore(_ score: String, forHole holeNumber: Int) async -> Bool
    func getScoreForHole(_ holeNumber: Int) async -> String?
    func advanceToNextHole() async -> Int?
    
    // Round statistics
    func getCurrentStatistics() async -> SharedRoundStatistics?
    func getScoreForFront9() async -> Int?
    func getScoreForBack9() async -> Int?
    func getTotalScore() async -> Int
    func getScoreRelativeToPar() async -> Int
    
    // Sync with iPhone
    func syncScoreWithiPhone() async -> Bool
    func requestRoundFromiPhone() async -> ActiveGolfRound?
    
    // Round history (limited cache)
    func getRecentRounds() async -> [SharedScorecard]
    func saveRoundToHistory(_ scorecard: SharedScorecard) async
    
    // Delegates
    func setDelegate(_ delegate: WatchScorecardDelegate)
    func removeDelegate(_ delegate: WatchScorecardDelegate)
}

// MARK: - Watch Scorecard Delegate

protocol WatchScorecardDelegate: AnyObject {
    func didStartNewRound(_ round: ActiveGolfRound)
    func didRecordScore(holeNumber: Int, score: String, relativeToPar: Int)
    func didAdvanceToHole(_ holeNumber: Int)
    func didCompleteRound(_ scorecard: SharedScorecard)
    func didSyncWithiPhone(_ round: ActiveGolfRound)
    func didFailToSyncWithiPhone(error: Error)
}

// Default implementations
extension WatchScorecardDelegate {
    func didStartNewRound(_ round: ActiveGolfRound) {}
    func didRecordScore(holeNumber: Int, score: String, relativeToPar: Int) {}
    func didAdvanceToHole(_ holeNumber: Int) {}
    func didCompleteRound(_ scorecard: SharedScorecard) {}
    func didSyncWithiPhone(_ round: ActiveGolfRound) {}
    func didFailToSyncWithiPhone(error: Error) {}
}

// MARK: - Watch Scorecard Service Implementation

class WatchScorecardService: NSObject, WatchScorecardServiceProtocol {
    // MARK: - Properties
    
    private let connectivityService: WatchConnectivityServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "Scorecard")
    
    // Active round management
    private var currentRound: ActiveGolfRound?
    private var roundHistory: [SharedScorecard] = []
    private let maxHistoryCount = 5 // Limit for Watch memory constraints
    
    // Sync management
    private var lastSyncTime: Date?
    private let syncInterval: TimeInterval = 30 // Sync every 30 seconds during active round
    private var syncTimer: Timer?
    
    // Delegates
    private var delegates: [WeakScorecardDelegate] = []
    
    // Auto-save
    private let autoSaveQueue = DispatchQueue(label: "WatchScorecardAutoSave", qos: .utility)
    
    // MARK: - Initialization
    
    init(connectivityService: WatchConnectivityServiceProtocol) {
        self.connectivityService = connectivityService
        super.init()
        
        connectivityService.setDelegate(self)
        loadCachedRound()
        logger.info("WatchScorecardService initialized")
    }
    
    // MARK: - Active Round Management
    
    func startNewRound(courseId: String, teeType: SharedTeeType) async -> ActiveGolfRound? {
        logger.info("Starting new round for course: \(courseId)")
        
        // End current round if exists
        if currentRound != nil {
            await endCurrentRound()
        }
        
        // Create new round
        let roundId = UUID().uuidString
        let newRound = ActiveGolfRound(
            id: roundId,
            courseId: courseId,
            courseName: "Loading...", // Will be updated when course data is received
            startTime: Date(),
            currentHole: 1,
            scores: [:],
            totalScore: 0,
            totalPar: 0,
            holes: [], // Will be populated when course data is received
            teeType: teeType
        )
        
        currentRound = newRound
        
        // Start auto-sync
        startSyncTimer()
        
        // Auto-save
        autoSaveCachedRound()
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.didStartNewRound(newRound)
        }
        
        // Sync with iPhone immediately
        await syncScoreWithiPhone()
        
        logger.info("Started new round: \(roundId)")
        return newRound
    }
    
    func getCurrentRound() async -> ActiveGolfRound? {
        if currentRound == nil {
            // Try to load from iPhone
            currentRound = await requestRoundFromiPhone()
        }
        
        return currentRound
    }
    
    func endCurrentRound() async -> SharedScorecard? {
        guard let round = currentRound else {
            logger.warning("No current round to end")
            return nil
        }
        
        logger.info("Ending current round: \(round.courseName)")
        
        // Stop auto-sync
        stopSyncTimer()
        
        // Create final scorecard
        let holeScores = round.scores.compactMap { (holeNumber, score) -> SharedHoleScore? in
            guard let holeInfo = round.holes.first(where: { $0.holeNumber == holeNumber }),
                  let scoreInt = Int(score) else {
                return nil
            }
            
            return SharedHoleScore(
                id: UUID().uuidString,
                holeNumber: holeNumber,
                par: holeInfo.par,
                yardage: holeInfo.yardage,
                score: score,
                putts: nil,
                penalties: 0,
                fairwayHit: nil,
                greenInRegulation: nil
            )
        }.sorted { $0.holeNumber < $1.holeNumber }
        
        // Calculate statistics
        let statistics = calculateStatistics(from: holeScores)
        
        let scorecard = SharedScorecard(
            id: round.id,
            userId: "watch-user", // Will be updated from iPhone
            courseId: round.courseId,
            courseName: round.courseName,
            playedDate: round.startTime,
            numberOfHoles: round.holes.count,
            coursePar: round.totalPar,
            teeType: round.teeType,
            holeScores: holeScores,
            totalScore: round.totalScore,
            scoreRelativeToPar: round.scoreRelativeToPar,
            statistics: statistics,
            isComplete: round.isComplete,
            currentHole: round.currentHole,
            createdAt: round.startTime,
            updatedAt: Date()
        )
        
        // Save to history
        await saveRoundToHistory(scorecard)
        
        // Clear current round
        currentRound = nil
        clearCachedRound()
        
        // Final sync with iPhone
        connectivityService.sendScoreUpdate(scorecard)
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.didCompleteRound(scorecard)
        }
        
        logger.info("Completed round with score: \(scorecard.formattedScore)")
        return scorecard
    }
    
    // MARK: - Score Entry
    
    func recordScore(_ score: String, forHole holeNumber: Int) async -> Bool {
        guard var round = currentRound else {
            logger.error("No active round to record score")
            return false
        }
        
        guard let holeInfo = round.holes.first(where: { $0.holeNumber == holeNumber }) else {
            logger.error("Hole \(holeNumber) not found in current round")
            return false
        }
        
        // Validate score
        guard validateScore(score) else {
            logger.error("Invalid score: \(score)")
            return false
        }
        
        // Record the score
        round.recordScore(score, forHole: holeNumber)
        currentRound = round
        
        // Auto-save
        autoSaveCachedRound()
        
        // Calculate relative to par for notification
        let relativeToPar = Int(score) != nil ? Int(score)! - holeInfo.par : 0
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.didRecordScore(holeNumber: holeNumber, score: score, relativeToPar: relativeToPar)
        }
        
        // Trigger sync
        await syncScoreWithiPhone()
        
        logger.debug("Recorded score \(score) for hole \(holeNumber) (par \(holeInfo.par))")
        return true
    }
    
    func getScoreForHole(_ holeNumber: Int) async -> String? {
        return currentRound?.scoreForHole(holeNumber)
    }
    
    func advanceToNextHole() async -> Int? {
        guard var round = currentRound else {
            logger.error("No active round to advance")
            return nil
        }
        
        let previousHole = round.currentHole
        round.advanceToNextHole()
        currentRound = round
        
        // Auto-save
        autoSaveCachedRound()
        
        // Notify delegates
        if round.currentHole != previousHole {
            notifyDelegates { delegate in
                delegate.didAdvanceToHole(round.currentHole)
            }
            
            // Sync with iPhone
            await syncScoreWithiPhone()
            
            logger.debug("Advanced to hole \(round.currentHole)")
            return round.currentHole
        }
        
        return nil
    }
    
    // MARK: - Round Statistics
    
    func getCurrentStatistics() async -> SharedRoundStatistics? {
        guard let round = currentRound, !round.scores.isEmpty else {
            return nil
        }
        
        let holeScores = round.scores.compactMap { (holeNumber, score) -> SharedHoleScore? in
            guard let holeInfo = round.holes.first(where: { $0.holeNumber == holeNumber }),
                  let scoreInt = Int(score) else {
                return nil
            }
            
            return SharedHoleScore(
                id: UUID().uuidString,
                holeNumber: holeNumber,
                par: holeInfo.par,
                yardage: holeInfo.yardage,
                score: score,
                putts: nil,
                penalties: 0,
                fairwayHit: nil,
                greenInRegulation: nil
            )
        }
        
        return calculateStatistics(from: holeScores)
    }
    
    func getScoreForFront9() async -> Int? {
        guard let round = currentRound else { return nil }
        
        let front9Scores = (1...9).compactMap { holeNumber in
            guard let scoreString = round.scores[holeNumber],
                  let score = Int(scoreString) else {
                return nil
            }
            return score
        }
        
        return front9Scores.isEmpty ? nil : front9Scores.reduce(0, +)
    }
    
    func getScoreForBack9() async -> Int? {
        guard let round = currentRound, round.holes.count >= 18 else { return nil }
        
        let back9Scores = (10...18).compactMap { holeNumber in
            guard let scoreString = round.scores[holeNumber],
                  let score = Int(scoreString) else {
                return nil
            }
            return score
        }
        
        return back9Scores.isEmpty ? nil : back9Scores.reduce(0, +)
    }
    
    func getTotalScore() async -> Int {
        return currentRound?.totalScore ?? 0
    }
    
    func getScoreRelativeToPar() async -> Int {
        return currentRound?.scoreRelativeToPar ?? 0
    }
    
    // MARK: - Sync with iPhone
    
    func syncScoreWithiPhone() async -> Bool {
        guard let round = currentRound else {
            logger.debug("No current round to sync")
            return false
        }
        
        // Check if enough time has passed since last sync
        let now = Date()
        if let lastSync = lastSyncTime, now.timeIntervalSince(lastSync) < 5.0 {
            logger.debug("Skipping sync - too frequent")
            return false
        }
        
        lastSyncTime = now
        
        return await withCheckedContinuation { continuation in
            connectivityService.sendActiveRoundUpdate(round)
            
            // Assume success for now - in real implementation, we'd wait for confirmation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.notifyDelegates { delegate in
                    delegate.didSyncWithiPhone(round)
                }
                continuation.resume(returning: true)
            }
        }
    }
    
    func requestRoundFromiPhone() async -> ActiveGolfRound? {
        logger.info("Requesting current round from iPhone")
        
        return await withCheckedContinuation { continuation in
            connectivityService.requestCurrentRound()
            
            // Set up timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                continuation.resume(returning: nil)
            }
            
            // The response will be handled in the WatchConnectivityDelegate
        }
    }
    
    // MARK: - Round History
    
    func getRecentRounds() async -> [SharedScorecard] {
        return Array(roundHistory.prefix(maxHistoryCount))
    }
    
    func saveRoundToHistory(_ scorecard: SharedScorecard) async {
        roundHistory.insert(scorecard, at: 0)
        
        // Limit history size for Watch memory constraints
        if roundHistory.count > maxHistoryCount {
            roundHistory = Array(roundHistory.prefix(maxHistoryCount))
        }
        
        // Persist to UserDefaults
        await saveHistoryToUserDefaults()
        
        logger.debug("Saved round to history: \(scorecard.courseName)")
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: WatchScorecardDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        delegates.append(WeakScorecardDelegate(delegate))
        delegates.removeAll { $0.delegate == nil }
        logger.debug("Added scorecard delegate")
    }
    
    func removeDelegate(_ delegate: WatchScorecardDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        logger.debug("Removed scorecard delegate")
    }
    
    // MARK: - Private Helper Methods
    
    private func validateScore(_ score: String) -> Bool {
        // Allow "X" for no score, or numeric values 1-15
        if score == "X" { return true }
        
        guard let scoreInt = Int(score), scoreInt >= 1 && scoreInt <= 15 else {
            return false
        }
        
        return true
    }
    
    private func calculateStatistics(from holeScores: [SharedHoleScore]) -> SharedRoundStatistics {
        var pars = 0, birdies = 0, eagles = 0, bogeys = 0, doubleBogeys = 0, otherScores = 0
        var fairwaysHit = 0, totalFairways = 0, greensInRegulation = 0, totalGreens = 0
        var totalPutts: Int? = nil, totalPenalties = 0
        
        for holeScore in holeScores {
            guard let scoreInt = holeScore.scoreInt else { continue }
            
            let relativeToPar = scoreInt - holeScore.par
            
            switch relativeToPar {
            case -2: eagles += 1
            case -1: birdies += 1
            case 0: pars += 1
            case 1: bogeys += 1
            case 2: doubleBogeys += 1
            default: otherScores += 1
            }
            
            // Track fairways and greens (simplified for Watch)
            if holeScore.par >= 4 { // Par 4 and 5 holes have fairways
                totalFairways += 1
                if holeScore.fairwayHit == true {
                    fairwaysHit += 1
                }
            }
            
            totalGreens += 1
            if holeScore.greenInRegulation == true {
                greensInRegulation += 1
            }
            
            if let putts = holeScore.putts {
                totalPutts = (totalPutts ?? 0) + putts
            }
            
            totalPenalties += holeScore.penalties
        }
        
        return SharedRoundStatistics(
            pars: pars,
            birdies: birdies,
            eagles: eagles,
            bogeys: bogeys,
            doubleBogeys: doubleBogeys,
            otherScores: otherScores,
            fairwaysHit: fairwaysHit,
            totalFairways: totalFairways,
            greensInRegulation: greensInRegulation,
            totalGreens: totalGreens,
            totalPutts: totalPutts,
            totalPenalties: totalPenalties
        )
    }
    
    // MARK: - Auto-Sync Timer
    
    private func startSyncTimer() {
        stopSyncTimer() // Stop existing timer
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.syncScoreWithiPhone()
            }
        }
        
        logger.debug("Started auto-sync timer")
    }
    
    private func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
        logger.debug("Stopped auto-sync timer")
    }
    
    // MARK: - Persistence
    
    private func autoSaveCachedRound() {
        autoSaveQueue.async { [weak self] in
            guard let self = self, let round = self.currentRound else { return }
            
            if let data = try? JSONEncoder().encode(round) {
                UserDefaults.standard.set(data, forKey: "CachedActiveRound")
                self.logger.debug("Auto-saved current round")
            }
        }
    }
    
    private func loadCachedRound() {
        autoSaveQueue.async { [weak self] in
            guard let data = UserDefaults.standard.data(forKey: "CachedActiveRound"),
                  let round = try? JSONDecoder().decode(ActiveGolfRound.self, from: data) else {
                return
            }
            
            DispatchQueue.main.async {
                self?.currentRound = round
                self?.startSyncTimer() // Resume auto-sync
                self?.logger.info("Loaded cached round: \(round.courseName)")
            }
        }
    }
    
    private func clearCachedRound() {
        UserDefaults.standard.removeObject(forKey: "CachedActiveRound")
        logger.debug("Cleared cached round")
    }
    
    private func saveHistoryToUserDefaults() async {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(roundHistory) {
            UserDefaults.standard.set(data, forKey: "ScorecardHistory")
        }
    }
    
    private func loadHistoryFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: "ScorecardHistory"),
              let history = try? JSONDecoder().decode([SharedScorecard].self, from: data) else {
            return
        }
        
        roundHistory = history
        logger.debug("Loaded \(roundHistory.count) rounds from history")
    }
    
    private func notifyDelegates<T>(_ action: (WatchScorecardDelegate) -> T) {
        DispatchQueue.main.async {
            self.delegates.forEach { weakDelegate in
                if let delegate = weakDelegate.delegate {
                    _ = action(delegate)
                }
            }
            
            // Clean up nil references
            self.delegates.removeAll { $0.delegate == nil }
        }
    }
    
    deinit {
        stopSyncTimer()
        logger.debug("WatchScorecardService deinitialized")
    }
}

// MARK: - WatchConnectivityDelegate Implementation

extension WatchScorecardService: WatchConnectivityDelegate {
    func didReceiveActiveRoundUpdate(_ round: ActiveGolfRound) {
        logger.info("Received active round update from iPhone: \(round.courseName), hole \(round.currentHole)")
        
        // Update current round if it matches
        if currentRound?.id == round.id || currentRound == nil {
            currentRound = round
            autoSaveCachedRound()
            
            if syncTimer == nil {
                startSyncTimer()
            }
            
            notifyDelegates { delegate in
                delegate.didSyncWithiPhone(round)
            }
        }
    }
    
    func didReceiveScoreUpdate(_ scorecard: SharedScorecard) {
        logger.info("Received scorecard update from iPhone: \(scorecard.courseName)")
        
        // If this matches our current round, update it
        if let currentId = currentRound?.id, currentId == scorecard.id {
            // Convert scorecard back to active round if not complete
            if !scorecard.isComplete {
                let holes = currentRound?.holes ?? [] // Keep existing hole data
                currentRound = scorecard.toActiveRound(with: holes)
                autoSaveCachedRound()
            } else {
                // Round is complete, end our current round
                Task {
                    await self.endCurrentRound()
                }
            }
        }
    }
}

// MARK: - Supporting Types

private struct WeakScorecardDelegate {
    weak var delegate: WatchScorecardDelegate?
    
    init(_ delegate: WatchScorecardDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Mock Watch Scorecard Service

class MockWatchScorecardService: WatchScorecardServiceProtocol {
    private let logger = Logger(subsystem: "GolfFinderWatch", category: "MockScorecard")
    private var delegates: [WeakScorecardDelegate] = []
    private var currentRound: ActiveGolfRound?
    private var roundHistory: [SharedScorecard] = []
    
    init() {
        setupMockRound()
        logger.info("MockWatchScorecardService initialized")
    }
    
    private func setupMockRound() {
        let holes = (1...18).map { holeNumber in
            SharedHoleInfo(
                id: "hole-\(holeNumber)",
                holeNumber: holeNumber,
                par: holeNumber <= 6 ? 4 : (holeNumber == 9 || holeNumber == 18 ? 5 : 3),
                yardage: Int.random(in: 150...450),
                handicapIndex: holeNumber,
                teeCoordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                pinCoordinate: CLLocationCoordinate2D(latitude: 37.7749 + 0.001, longitude: -122.4194 + 0.001),
                hazards: []
            )
        }
        
        currentRound = ActiveGolfRound(
            id: "mock-round-1",
            courseId: "mock-course-1",
            courseName: "Mock Golf Club",
            startTime: Date().addingTimeInterval(-3600),
            currentHole: 5,
            scores: [1: "4", 2: "3", 3: "5", 4: "4"],
            totalScore: 16,
            totalPar: 14,
            holes: holes,
            teeType: .regular
        )
    }
    
    // Mock implementations
    func startNewRound(courseId: String, teeType: SharedTeeType) async -> ActiveGolfRound? {
        setupMockRound()
        return currentRound
    }
    
    func getCurrentRound() async -> ActiveGolfRound? { return currentRound }
    func endCurrentRound() async -> SharedScorecard? { 
        currentRound = nil
        return nil 
    }
    
    func recordScore(_ score: String, forHole holeNumber: Int) async -> Bool {
        currentRound?.recordScore(score, forHole: holeNumber)
        return true
    }
    
    func getScoreForHole(_ holeNumber: Int) async -> String? {
        return currentRound?.scoreForHole(holeNumber)
    }
    
    func advanceToNextHole() async -> Int? {
        currentRound?.advanceToNextHole()
        return currentRound?.currentHole
    }
    
    func getCurrentStatistics() async -> SharedRoundStatistics? { return nil }
    func getScoreForFront9() async -> Int? { return 38 }
    func getScoreForBack9() async -> Int? { return 40 }
    func getTotalScore() async -> Int { return currentRound?.totalScore ?? 0 }
    func getScoreRelativeToPar() async -> Int { return currentRound?.scoreRelativeToPar ?? 0 }
    
    func syncScoreWithiPhone() async -> Bool { return true }
    func requestRoundFromiPhone() async -> ActiveGolfRound? { return currentRound }
    
    func getRecentRounds() async -> [SharedScorecard] { return roundHistory }
    func saveRoundToHistory(_ scorecard: SharedScorecard) async {
        roundHistory.insert(scorecard, at: 0)
    }
    
    func setDelegate(_ delegate: WatchScorecardDelegate) {
        delegates.removeAll { $0.delegate === delegate }
        delegates.append(WeakScorecardDelegate(delegate))
    }
    
    func removeDelegate(_ delegate: WatchScorecardDelegate) {
        delegates.removeAll { $0.delegate === delegate }
    }
}