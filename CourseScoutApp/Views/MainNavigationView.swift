import SwiftUI
import Combine

// MARK: - Main Navigation View with Phase 4 Gamification Integration

struct MainNavigationView: View {
    // MARK: - Service Dependencies
    @ServiceInjected(AuthenticationServiceProtocol.self) private var authService
    @ServiceInjected(TenantConfigurationServiceProtocol.self) private var tenantService
    @ServiceInjected(RoleManagementServiceProtocol.self) private var roleService
    @ServiceInjected(HapticFeedbackServiceProtocol.self) private var hapticService
    @ServiceInjected(SocialChallengeSynchronizedHapticServiceProtocol.self) private var synchronizedHapticService
    @ServiceInjected(SecurePaymentServiceProtocol.self) private var paymentService
    @ServiceInjected(MultiTenantRevenueAttributionServiceProtocol.self) private var revenueAttributionService
    
    // MARK: - State Properties
    @State private var selectedTab: MainTab = .discover
    @State private var currentUser: UserProfile?
    @State private var userRole: UserRole = .golfer
    @State private var showingTournamentHosting = false
    @State private var showingChallengeCreation = false
    @State private var showingRevenueOptimization = false
    @State private var activeTournaments: [Tournament] = []
    @State private var activeChallenges: [SocialChallenge] = []
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Navigation State
    @State private var showingProfile = false
    @State private var showingSettings = false
    @State private var showingNotifications = false
    @State private var hasUnreadNotifications = false
    
    // Configuration based on tenant and user role
    private var availableTabs: [MainTab] {
        switch userRole {
        case .golfer:
            return [.discover, .challenges, .leaderboard, .profile]
        case .golfCourseAdmin:
            return [.discover, .challenges, .leaderboard, .tournament, .revenue, .profile]
        case .golfCourseManager:
            return [.discover, .challenges, .leaderboard, .management, .profile]
        case .systemAdmin:
            return MainTab.allCases
        }
    }
    
    var body: some View {
        ZStack {
            // Main tab content
            TabView(selection: $selectedTab) {
                ForEach(availableTabs, id: \.self) { tab in
                    tabContent(for: tab)
                        .tabItem {
                            Image(systemName: tab.icon)
                            Text(tab.title)
                        }
                        .tag(tab)
                }
            }
            .accentColor(.primary)
            
            // Floating action buttons for quick actions
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    gamificationFloatingActions
                }
                .padding(.trailing, 20)
                .padding(.bottom, 100) // Above tab bar
            }
            
            // Navigation overlays
            if showingTournamentHosting {
                tournamentHostingOverlay
            }
            
            if showingChallengeCreation {
                challengeCreationOverlay
            }
            
            if showingRevenueOptimization {
                revenueOptimizationOverlay
            }
        }
        .onAppear {
            setupNavigationHandlers()
            loadUserConfiguration()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showingSettings) {
            MainSettingsView()
        }
    }
    
    // MARK: - Tab Content Views
    
    @ViewBuilder
    private func tabContent(for tab: MainTab) -> some View {
        switch tab {
        case .discover:
            CourseDiscoveryView()
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        notificationButton
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        profileButton
                    }
                }
            
        case .challenges:
            NavigationView {
                SocialInteractionView()
                    .navigationTitle("Challenges")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Create Challenge") {
                                showChallengeCreation()
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            activeChallengesButton
                        }
                    }
            }
            
        case .leaderboard:
            NavigationView {
                LeaderboardView()
                    .navigationTitle("Leaderboard")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Live View") {
                                // Navigate to live leaderboard
                                hapticService.impact(.medium)
                            }
                        }
                    }
            }
            
        case .tournament:
            NavigationView {
                TournamentManagementView()
                    .navigationTitle("Tournament Management")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Host Tournament") {
                                showTournamentHosting()
                            }
                        }
                    }
            }
            
        case .revenue:
            NavigationView {
                RevenueOptimizationView()
                    .navigationTitle("Revenue")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Analytics") {
                                showRevenueOptimization()
                            }
                        }
                    }
            }
            
        case .management:
            NavigationView {
                CourseAdminDashboard()
                    .navigationTitle("Management")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Settings") {
                                showingSettings = true
                            }
                        }
                    }
            }
            
        case .profile:
            NavigationView {
                ProfileView()
                    .navigationTitle("Profile")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Settings") {
                                showingSettings = true
                            }
                        }
                    }
            }
        }
    }
    
    // MARK: - Floating Action Buttons
    
    private var gamificationFloatingActions: some View {
        VStack(spacing: 12) {
            // Tournament hosting (admin only)
            if userRole.canHostTournaments {
                FloatingActionButton(
                    icon: "trophy.fill",
                    color: .orange,
                    action: showTournamentHosting
                )
            }
            
            // Challenge creation
            FloatingActionButton(
                icon: "target",
                color: .green,
                action: showChallengeCreation
            )
            
            // Quick challenge
            FloatingActionButton(
                icon: "bolt.fill",
                color: .blue,
                action: createQuickChallenge
            )
        }
    }
    
    // MARK: - Overlay Views
    
    private var tournamentHostingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissTournamentHosting()
                }
            
            TournamentHostingView()
                .padding()
                .background(Color.systemBackground)
                .cornerRadius(16)
                .shadow(radius: 20)
                .padding()
                .transition(.scale.combined(with: .opacity))
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showingTournamentHosting)
    }
    
    private var challengeCreationOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissChallengeCreation()
                }
            
            ChallengeCreationView()
                .padding()
                .background(Color.systemBackground)
                .cornerRadius(16)
                .shadow(radius: 20)
                .padding()
                .transition(.scale.combined(with: .opacity))
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showingChallengeCreation)
    }
    
    private var revenueOptimizationOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissRevenueOptimization()
                }
            
            MonetizedChallengeView()
                .padding()
                .background(Color.systemBackground)
                .cornerRadius(16)
                .shadow(radius: 20)
                .padding()
                .transition(.scale.combined(with: .opacity))
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showingRevenueOptimization)
    }
    
    // MARK: - Toolbar Components
    
    private var notificationButton: some View {
        Button(action: {
            showingNotifications = true
            hapticService.impact(.light)
        }) {
            ZStack {
                Image(systemName: "bell")
                    .font(.title3)
                    .foregroundColor(.primary)
                
                if hasUnreadNotifications {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: 8, y: -8)
                }
            }
        }
    }
    
    private var profileButton: some View {
        Button(action: {
            showingProfile = true
            hapticService.impact(.light)
        }) {
            Image(systemName: "person.circle")
                .font(.title3)
                .foregroundColor(.primary)
        }
    }
    
    private var activeChallengesButton: some View {
        Button(action: {
            // Navigate to active challenges view
            hapticService.impact(.medium)
        }) {
            HStack(spacing: 4) {
                Text("\(activeChallenges.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Image(systemName: "target")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.2))
            .foregroundColor(.green)
            .clipShape(Capsule())
        }
    }
    
    // MARK: - Action Methods
    
    private func showTournamentHosting() {
        guard userRole.canHostTournaments else { return }
        
        Task {
            await synchronizedHapticService.provideSynchronizedActionFeedback(
                challengeId: "tournament_hosting",
                actionType: .open,
                playerName: currentUser?.name ?? "User"
            )
        }
        
        showingTournamentHosting = true
    }
    
    private func dismissTournamentHosting() {
        showingTournamentHosting = false
        hapticService.impact(.light)
    }
    
    private func showChallengeCreation() {
        Task {
            await synchronizedHapticService.provideSynchronizedActionFeedback(
                challengeId: "challenge_creation",
                actionType: .create,
                playerName: currentUser?.name ?? "User"
            )
        }
        
        showingChallengeCreation = true
    }
    
    private func dismissChallengeCreation() {
        showingChallengeCreation = false
        hapticService.impact(.light)
    }
    
    private func showRevenueOptimization() {
        guard userRole.canAccessRevenue else { return }
        
        Task {
            await synchronizedHapticService.provideSynchronizedActionFeedback(
                challengeId: "revenue_optimization",
                actionType: .open,
                playerName: currentUser?.name ?? "Admin"
            )
        }
        
        showingRevenueOptimization = true
    }
    
    private func dismissRevenueOptimization() {
        showingRevenueOptimization = false
        hapticService.impact(.light)
    }
    
    private func createQuickChallenge() {
        Task {
            await synchronizedHapticService.provideSynchronizedActionFeedback(
                challengeId: "quick_challenge",
                actionType: .create,
                playerName: currentUser?.name ?? "User"
            )
        }
        
        // Navigate to quick challenge creation
        hapticService.impact(.medium)
    }
    
    // MARK: - Setup Methods
    
    private func setupNavigationHandlers() {
        // Subscribe to authentication state changes
        authService.authenticationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleAuthenticationStateChange(state)
            }
            .store(in: &cancellables)
        
        // Subscribe to role changes
        roleService.currentRole
            .receive(on: DispatchQueue.main)
            .sink { [weak self] role in
                self?.userRole = role
            }
            .store(in: &cancellables)
        
        // Subscribe to tournament updates
        // This would be connected to tournament service when available
    }
    
    private func loadUserConfiguration() {
        Task {
            do {
                currentUser = try await authService.getCurrentUser()
                userRole = await roleService.getCurrentUserRole()
            } catch {
                print("Failed to load user configuration: \(error)")
            }
        }
    }
    
    private func handleAuthenticationStateChange(_ state: AuthenticationState) {
        switch state {
        case .authenticated(let user):
            currentUser = user
        case .unauthenticated:
            currentUser = nil
            selectedTab = .discover
        case .loading:
            break
        }
    }
}

// MARK: - Supporting Views

struct FloatingActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .clipShape(Circle())
                .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
                .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0) { _ in
            // On press
            isPressed = true
        } onPressingChanged: { pressing in
            // On release
            if !pressing {
                isPressed = false
            }
        } perform: {
            // On long press complete
        }
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

struct MainSettingsView: View {
    var body: some View {
        NavigationView {
            List {
                Section("Gamification") {
                    NavigationLink("Challenge Preferences", destination: EmptyView())
                    NavigationLink("Tournament Settings", destination: EmptyView())
                    NavigationLink("Haptic Feedback", destination: TenantHapticPreferencesView())
                }
                
                Section("Account") {
                    NavigationLink("Profile", destination: ProfileView())
                    NavigationLink("Privacy", destination: EmptyView())
                    NavigationLink("Notifications", destination: EmptyView())
                }
                
                Section("Revenue") {
                    NavigationLink("Revenue Attribution", destination: EmptyView())
                    NavigationLink("Payment Settings", destination: EmptyView())
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Tab Definition

enum MainTab: String, CaseIterable {
    case discover = "Discover"
    case challenges = "Challenges"
    case leaderboard = "Leaderboard"
    case tournament = "Tournaments"
    case revenue = "Revenue"
    case management = "Management"
    case profile = "Profile"
    
    var title: String {
        return rawValue
    }
    
    var icon: String {
        switch self {
        case .discover:
            return "map"
        case .challenges:
            return "target"
        case .leaderboard:
            return "list.number"
        case .tournament:
            return "trophy"
        case .revenue:
            return "dollarsign.circle"
        case .management:
            return "gear"
        case .profile:
            return "person.circle"
        }
    }
}

// MARK: - User Role Extensions

extension UserRole {
    var canHostTournaments: Bool {
        switch self {
        case .golfCourseAdmin, .systemAdmin:
            return true
        default:
            return false
        }
    }
    
    var canAccessRevenue: Bool {
        switch self {
        case .golfCourseAdmin, .systemAdmin:
            return true
        default:
            return false
        }
    }
}

// MARK: - Preview Support

struct MainNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        MainNavigationView()
            .previewDisplayName("Main Navigation")
    }
}