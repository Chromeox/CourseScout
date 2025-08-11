import Foundation
import Appwrite
import SwiftUI

// MARK: - Appwrite Manager

@MainActor
class AppwriteManager: ObservableObject {
    // MARK: - Singleton Access
    
    static let shared = AppwriteManager()
    
    // MARK: - Appwrite Client
    
    let client: Client
    let account: Account
    let databases: Databases
    let storage: Storage
    let functions: Functions
    let realtime: Realtime
    
    // MARK: - Configuration
    
    private let endpoint: String
    private let projectId: String
    
    // MARK: - State Management
    
    @Published var isInitialized = false
    @Published var currentUser: AppwriteModels.User<AppwriteModels.Preferences>?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    // MARK: - Initialization
    
    private init() {
        self.endpoint = Configuration.appwriteEndpoint
        self.projectId = Configuration.appwriteProjectId
        
        // Initialize Appwrite client
        self.client = Client()
            .setEndpoint(endpoint)
            .setProject(projectId)
        
        // Initialize services
        self.account = Account(client)
        self.databases = Databases(client)
        self.storage = Storage(client)
        self.functions = Functions(client)
        self.realtime = Realtime(client)
        
        Task {
            await initializeConnection()
        }
    }
    
    // MARK: - Initialization Methods
    
    private func initializeConnection() async {
        do {
            connectionStatus = .connecting
            
            // Test connection with a simple health check
            _ = try await account.get()
            
            connectionStatus = .connected
            isInitialized = true
            
            print("✅ Appwrite connection initialized successfully")
            print("📍 Endpoint: \(endpoint)")
            print("🎯 Project: \(projectId)")
            
        } catch {
            connectionStatus = .error(error)
            print("❌ Appwrite initialization failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Connection Management
    
    func reconnect() async {
        await initializeConnection()
    }
    
    func checkConnection() async -> Bool {
        do {
            _ = try await account.get()
            connectionStatus = .connected
            return true
        } catch {
            connectionStatus = .error(error)
            return false
        }
    }
    
    // MARK: - User Session Management
    
    func getCurrentUser() async throws -> AppwriteModels.User<AppwriteModels.Preferences> {
        let user = try await account.get()
        await MainActor.run {
            self.currentUser = user
        }
        return user
    }
    
    func logout() async throws {
        try await account.deleteSession(sessionId: "current")
        await MainActor.run {
            self.currentUser = nil
        }
    }
    
    // MARK: - Database Collections
    
    struct DatabaseCollections {
        static let users = "users"
        static let golfCourses = "golf_courses"
        static let scorecards = "scorecards"
        static let leaderboards = "leaderboards"
        static let teetimes = "teetimes"
        static let reviews = "reviews"
        static let favorites = "favorites"
        static let handicaps = "handicaps"
        static let tournaments = "tournaments"
        static let bookings = "bookings"
    }
    
    // MARK: - Storage Buckets
    
    struct StorageBuckets {
        static let courseImages = "course-images"
        static let profilePictures = "profile-pictures"
        static let scorecardPhotos = "scorecard-photos"
        static let courseDocuments = "course-documents"
    }
    
    // MARK: - Real-time Subscriptions
    
    func subscribeToLeaderboards() -> AsyncThrowingStream<AppwriteModels.RealtimeResponse, Error> {
        return realtime.subscribe(channels: ["databases.\(projectId).collections.\(DatabaseCollections.leaderboards).documents"])
    }
    
    func subscribeToTeetimes() -> AsyncThrowingStream<AppwriteModels.RealtimeResponse, Error> {
        return realtime.subscribe(channels: ["databases.\(projectId).collections.\(DatabaseCollections.teetimes).documents"])
    }
    
    // MARK: - Error Handling
    
    func handleAppwriteError(_ error: Error) -> AppwriteError {
        if let appwriteError = error as? AppwriteError {
            return appwriteError
        }
        
        // Convert generic errors to Appwrite errors
        return AppwriteError.unknown(error.localizedDescription)
    }
}

// MARK: - Connection Status

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(Error)
    
    static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
    
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
    
    var errorMessage: String? {
        if case .error(let error) = self {
            return error.localizedDescription
        }
        return nil
    }
}

// MARK: - Appwrite Error Types

enum AppwriteError: Error, LocalizedError {
    case connectionFailed
    case authenticationRequired
    case permissionDenied
    case resourceNotFound
    case validationFailed(String)
    case serverError(Int)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to Appwrite server"
        case .authenticationRequired:
            return "Authentication required"
        case .permissionDenied:
            return "Permission denied"
        case .resourceNotFound:
            return "Resource not found"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .serverError(let code):
            return "Server error: \(code)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}