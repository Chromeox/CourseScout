import SwiftUI
import Combine

// MARK: - Role Management View

struct RoleManagementView: View {
    @StateObject private var viewModel: RoleManagementViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedFilter: UserFilter = .all
    @State private var showingUserDetail = false
    @State private var selectedUser: TenantUser?
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol,
        userManagementService: UserManagementServiceProtocol,
        auditService: AuditServiceProtocol
    ) {
        self._viewModel = StateObject(wrappedValue: RoleManagementViewModel(
            authenticationService: authenticationService,
            tenantConfigurationService: tenantConfigurationService,
            userManagementService: userManagementService,
            auditService: auditService
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and filter bar
                searchAndFilterBar
                
                // User list
                userListSection
            }
        }
        .navigationTitle("User Management")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Invite User") {
                        viewModel.showInviteUser = true
                    }
                    
                    Button("Bulk Actions") {
                        viewModel.showBulkActions = true
                    }
                    
                    Button("Export Users") {
                        viewModel.exportUsers()
                    }
                    
                    Button("Audit Log") {
                        viewModel.showAuditLog = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search users...")
        .refreshable {
            await viewModel.refreshUsers()
        }
        .sheet(isPresented: $viewModel.showInviteUser) {
            inviteUserSheet
        }
        .sheet(isPresented: $viewModel.showBulkActions) {
            bulkActionsSheet
        }
        .sheet(isPresented: $viewModel.showAuditLog) {
            auditLogSheet
        }
        .sheet(isPresented: $showingUserDetail) {
            if let user = selectedUser {
                userDetailSheet(user)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Success", isPresented: $viewModel.showSuccess) {
            Button("OK") { viewModel.dismissSuccess() }
        } message: {
            Text(viewModel.successMessage)
        }
        .task {
            await viewModel.loadUsers()
        }
    }
    
    // MARK: - Search and Filter Bar
    
    private var searchAndFilterBar: some View {
        VStack(spacing: 12) {
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(UserFilter.allCases, id: \.self) { filter in
                        FilterChip(
                            title: filter.displayName,
                            count: viewModel.getUserCount(for: filter),
                            isSelected: selectedFilter == filter
                        ) {
                            selectedFilter = filter
                            viewModel.applyFilter(filter)
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Statistics summary
            if viewModel.showStatistics {
                statisticsSummary
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    private var statisticsSummary: some View {
        HStack(spacing: 24) {
            StatisticItem(
                title: "Total Users",
                value: "\(viewModel.totalUsers)",
                color: .blue
            )
            
            StatisticItem(
                title: "Active",
                value: "\(viewModel.activeUsers)",
                color: .green
            )
            
            StatisticItem(
                title: "Pending",
                value: "\(viewModel.pendingUsers)",
                color: .orange
            )
            
            StatisticItem(
                title: "Suspended",
                value: "\(viewModel.suspendedUsers)",
                color: .red
            )
        }
        .padding(.horizontal)
    }
    
    // MARK: - User List Section
    
    private var userListSection: some View {
        List {
            ForEach(filteredUsers, id: \.id) { user in
                UserRowView(
                    user: user,
                    currentUserRole: viewModel.currentUserRole,
                    onTap: {
                        selectedUser = user
                        showingUserDetail = true
                    },
                    onRoleChange: { newRole in
                        viewModel.updateUserRole(user, role: newRole)
                    },
                    onStatusChange: { newStatus in
                        viewModel.updateUserStatus(user, status: newStatus)
                    },
                    onRemove: {
                        viewModel.removeUser(user)
                    }
                )
                .swipeActions(edge: .trailing) {
                    if viewModel.canRemoveUser(user) {
                        Button("Remove", role: .destructive) {
                            viewModel.removeUser(user)
                        }
                    }
                    
                    if viewModel.canSuspendUser(user) {
                        Button(user.status == .suspended ? "Unsuspend" : "Suspend") {
                            let newStatus: UserStatus = user.status == .suspended ? .active : .suspended
                            viewModel.updateUserStatus(user, status: newStatus)
                        }
                        .tint(.orange)
                    }
                }
                .swipeActions(edge: .leading) {
                    if viewModel.canEditUser(user) {
                        Button("Edit") {
                            selectedUser = user
                            showingUserDetail = true
                        }
                        .tint(.blue)
                    }
                    
                    Button("Audit") {
                        viewModel.showUserAuditLog(user)
                    }
                    .tint(.gray)
                }
            }
            
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            }
        }
        .listStyle(PlainListStyle())
    }
    
    private var filteredUsers: [TenantUser] {
        var users = viewModel.users
        
        // Apply search filter
        if !searchText.isEmpty {
            users = users.filter { user in
                user.firstName.localizedCaseInsensitiveContains(searchText) ||
                user.lastName.localizedCaseInsensitiveContains(searchText) ||
                user.email.localizedCaseInsensitiveContains(searchText) ||
                user.role.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply status filter
        switch selectedFilter {
        case .all:
            break
        case .active:
            users = users.filter { $0.status == .active }
        case .pending:
            users = users.filter { $0.status == .pending }
        case .suspended:
            users = users.filter { $0.status == .suspended }
        case .admins:
            users = users.filter { $0.role.isAdmin }
        case .managers:
            users = users.filter { $0.role == .manager }
        case .members:
            users = users.filter { $0.role == .member }
        }
        
        return users
    }
    
    // MARK: - Sheets
    
    private var inviteUserSheet: some View {
        NavigationView {
            InviteUserView(viewModel: viewModel)
                .navigationTitle("Invite User")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            viewModel.showInviteUser = false
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Send") {
                            viewModel.sendInvitation()
                        }
                        .disabled(!viewModel.isInvitationValid || viewModel.isLoading)
                    }
                }
        }
    }
    
    private var bulkActionsSheet: some View {
        NavigationView {
            BulkActionsView(viewModel: viewModel)
                .navigationTitle("Bulk Actions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            viewModel.showBulkActions = false
                        }
                    }
                }
        }
    }
    
    private var auditLogSheet: some View {
        NavigationView {
            AuditLogView(
                auditLogs: viewModel.auditLogs,
                onRefresh: { await viewModel.loadAuditLogs() }
            )
            .navigationTitle("Audit Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.showAuditLog = false
                    }
                }
            }
        }
    }
    
    private func userDetailSheet(_ user: TenantUser) -> some View {
        NavigationView {
            UserDetailView(
                user: user,
                viewModel: viewModel,
                onSave: { updatedUser in
                    viewModel.updateUser(updatedUser)
                    showingUserDetail = false
                }
            )
            .navigationTitle("User Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingUserDetail = false
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.gray.opacity(0.3))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray4))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

struct StatisticItem: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct UserRowView: View {
    let user: TenantUser
    let currentUserRole: UserRole?
    let onTap: () -> Void
    let onRoleChange: (UserRole) -> Void
    let onStatusChange: (UserStatus) -> Void
    let onRemove: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // User avatar
                AsyncImage(url: user.profileImageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Text(user.initials)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                // User info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(user.fullName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        if user.isCurrentUser {
                            Text("You")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(user.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        // Role badge
                        RoleBadge(role: user.role)
                        
                        // Status indicator
                        StatusIndicator(status: user.status)
                        
                        if let lastActive = user.lastActiveFormatted {
                            Text("Last active: \(lastActive)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Quick actions
                if canEditUser {
                    Menu {
                        if canChangeRole {
                            Menu("Change Role") {
                                ForEach(UserRole.allCases, id: \.self) { role in
                                    if role != user.role && canAssignRole(role) {
                                        Button(role.displayName) {
                                            onRoleChange(role)
                                        }
                                    }
                                }
                            }
                        }
                        
                        if canChangeStatus {
                            Menu("Change Status") {
                                ForEach(UserStatus.allCases, id: \.self) { status in
                                    if status != user.status {
                                        Button(status.displayName) {
                                            onStatusChange(status)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        if canRemoveUser {
                            Button("Remove User", role: .destructive) {
                                onRemove()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var canEditUser: Bool {
        guard let currentRole = currentUserRole else { return false }
        return currentRole.canManageUsers && (!user.isCurrentUser || currentRole.canManageSelf)
    }
    
    private var canChangeRole: Bool {
        guard let currentRole = currentUserRole else { return false }
        return currentRole.canAssignRoles && !user.isCurrentUser
    }
    
    private var canChangeStatus: Bool {
        guard let currentRole = currentUserRole else { return false }
        return currentRole.canSuspendUsers && !user.isCurrentUser
    }
    
    private var canRemoveUser: Bool {
        guard let currentRole = currentUserRole else { return false }
        return currentRole.canRemoveUsers && !user.isCurrentUser
    }
    
    private func canAssignRole(_ role: UserRole) -> Bool {
        guard let currentRole = currentUserRole else { return false }
        // Can only assign roles that are equal or lower than current user's role
        return role.priority >= currentRole.priority
    }
}

struct RoleBadge: View {
    let role: UserRole
    
    var body: some View {
        Text(role.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(role.color.opacity(0.2))
            .foregroundColor(role.color)
            .clipShape(Capsule())
    }
}

struct StatusIndicator: View {
    let status: UserStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            
            Text(status.displayName)
                .font(.caption2)
                .foregroundColor(status.color)
        }
    }
}

// MARK: - Invite User View

struct InviteUserView: View {
    @ObservedObject var viewModel: RoleManagementViewModel
    
    var body: some View {
        Form {
            Section("User Information") {
                TextField("Email Address", text: $viewModel.inviteEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                
                TextField("First Name", text: $viewModel.inviteFirstName)
                
                TextField("Last Name", text: $viewModel.inviteLastName)
                
                Picker("Role", selection: $viewModel.inviteRole) {
                    ForEach(viewModel.availableRoles, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
            }
            
            Section("Message") {
                TextField("Personal message (optional)", text: $viewModel.inviteMessage, axis: .vertical)
                    .lineLimit(3...6)
            }
            
            Section("Options") {
                Toggle("Send welcome email", isOn: $viewModel.sendWelcomeEmail)
                
                Toggle("Require password change on first login", isOn: $viewModel.requirePasswordChange)
            }
        }
    }
}

// MARK: - Bulk Actions View

struct BulkActionsView: View {
    @ObservedObject var viewModel: RoleManagementViewModel
    
    var body: some View {
        List {
            Section("Select Users") {
                Toggle("Select All", isOn: $viewModel.selectAllUsers)
                
                Text("\(viewModel.selectedUsers.count) users selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Actions") {
                Button("Change Role") {
                    viewModel.showBulkRoleChange = true
                }
                .disabled(viewModel.selectedUsers.isEmpty)
                
                Button("Suspend Users") {
                    viewModel.bulkSuspendUsers()
                }
                .disabled(viewModel.selectedUsers.isEmpty)
                .foregroundColor(.orange)
                
                Button("Remove Users") {
                    viewModel.bulkRemoveUsers()
                }
                .disabled(viewModel.selectedUsers.isEmpty)
                .foregroundColor(.red)
            }
            
            Section("Export") {
                Button("Export Selected Users") {
                    viewModel.exportSelectedUsers()
                }
                .disabled(viewModel.selectedUsers.isEmpty)
                
                Button("Export All Users") {
                    viewModel.exportAllUsers()
                }
            }
        }
    }
}

// MARK: - User Detail View

struct UserDetailView: View {
    @State private var user: TenantUser
    @ObservedObject var viewModel: RoleManagementViewModel
    let onSave: (TenantUser) -> Void
    
    init(user: TenantUser, viewModel: RoleManagementViewModel, onSave: @escaping (TenantUser) -> Void) {
        self._user = State(initialValue: user)
        self.viewModel = viewModel
        self.onSave = onSave
    }
    
    var body: some View {
        Form {
            Section("Personal Information") {
                TextField("First Name", text: $user.firstName)
                TextField("Last Name", text: $user.lastName)
                TextField("Email", text: $user.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            
            Section("Role & Permissions") {
                Picker("Role", selection: $user.role) {
                    ForEach(viewModel.availableRoles, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                
                Picker("Status", selection: $user.status) {
                    ForEach(UserStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
            }
            
            Section("Account Information") {
                HStack {
                    Text("Created")
                    Spacer()
                    Text(user.createdAt, style: .date)
                        .foregroundColor(.secondary)
                }
                
                if let lastActive = user.lastActiveAt {
                    HStack {
                        Text("Last Active")
                        Spacer()
                        Text(lastActive, style: .relative)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("Login Count")
                    Spacer()
                    Text("\(user.loginCount)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Actions") {
                Button("Send Password Reset") {
                    viewModel.sendPasswordReset(to: user)
                }
                
                Button("View Audit Log") {
                    viewModel.showUserAuditLog(user)
                }
                
                if !user.isCurrentUser {
                    Button("Remove User", role: .destructive) {
                        viewModel.removeUser(user)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    onSave(user)
                }
            }
        }
    }
}

// MARK: - Audit Log View

struct AuditLogView: View {
    let auditLogs: [AuditLogEntry]
    let onRefresh: () async -> Void
    
    var body: some View {
        List {
            ForEach(auditLogs, id: \.id) { entry in
                AuditLogEntryView(entry: entry)
            }
        }
        .refreshable {
            await onRefresh()
        }
    }
}

struct AuditLogEntryView: View {
    let entry: AuditLogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.action)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(entry.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let description = entry.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("By: \(entry.performedBy)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let ipAddress = entry.ipAddress {
                    Text("IP: \(ipAddress)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Extensions

extension UserFilter: CaseIterable {
    static var allCases: [UserFilter] = [.all, .active, .pending, .suspended, .admins, .managers, .members]
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .pending: return "Pending"
        case .suspended: return "Suspended"
        case .admins: return "Admins"
        case .managers: return "Managers"
        case .members: return "Members"
        }
    }
}

extension UserRole {
    var color: Color {
        switch self {
        case .owner: return .purple
        case .admin: return .red
        case .manager: return .blue
        case .member: return .green
        case .guest: return .gray
        }
    }
    
    var priority: Int {
        switch self {
        case .owner: return 5
        case .admin: return 4
        case .manager: return 3
        case .member: return 2
        case .guest: return 1
        }
    }
    
    var canManageUsers: Bool {
        switch self {
        case .owner, .admin: return true
        case .manager: return true
        case .member, .guest: return false
        }
    }
    
    var canAssignRoles: Bool {
        switch self {
        case .owner, .admin: return true
        case .manager, .member, .guest: return false
        }
    }
    
    var canSuspendUsers: Bool {
        switch self {
        case .owner, .admin: return true
        case .manager: return true
        case .member, .guest: return false
        }
    }
    
    var canRemoveUsers: Bool {
        switch self {
        case .owner, .admin: return true
        case .manager, .member, .guest: return false
        }
    }
    
    var canManageSelf: Bool {
        return true
    }
    
    var isAdmin: Bool {
        switch self {
        case .owner, .admin: return true
        case .manager, .member, .guest: return false
        }
    }
}

extension UserStatus {
    var color: Color {
        switch self {
        case .active: return .green
        case .pending: return .orange
        case .suspended: return .red
        case .inactive: return .gray
        }
    }
    
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .pending: return "Pending"
        case .suspended: return "Suspended"
        case .inactive: return "Inactive"
        }
    }
}

extension TenantUser {
    var fullName: String {
        return "\(firstName) \(lastName)"
    }
    
    var initials: String {
        let firstInitial = firstName.first?.uppercased() ?? ""
        let lastInitial = lastName.first?.uppercased() ?? ""
        return "\(firstInitial)\(lastInitial)"
    }
    
    var lastActiveFormatted: String? {
        guard let lastActiveAt = lastActiveAt else { return nil }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastActiveAt, relativeTo: Date())
    }
}

// MARK: - Preview

struct RoleManagementView_Previews: PreviewProvider {
    static var previews: some View {
        RoleManagementView(
            authenticationService: MockAuthenticationService(),
            tenantConfigurationService: MockTenantConfigurationService(),
            userManagementService: MockUserManagementService(),
            auditService: MockAuditService()
        )
    }
}

// MARK: - Mock Services

class MockUserManagementService: UserManagementServiceProtocol {
    func getUsers(tenantId: String) async throws -> [TenantUser] {
        return []
    }
    
    func inviteUser(_ invitation: UserInvitation) async throws {
    }
    
    func updateUser(_ user: TenantUser) async throws {
    }
    
    func removeUser(userId: String, tenantId: String) async throws {
    }
    
    func updateUserRole(userId: String, tenantId: String, role: UserRole) async throws {
    }
    
    func updateUserStatus(userId: String, tenantId: String, status: UserStatus) async throws {
    }
}

class MockAuditService: AuditServiceProtocol {
    func logEvent(_ event: AuditEvent) async throws {
    }
    
    func getAuditLogs(tenantId: String, userId: String?, limit: Int) async throws -> [AuditLogEntry] {
        return []
    }
    
    func exportAuditLogs(tenantId: String, dateRange: DateInterval) async throws -> URL {
        throw AuthenticationError.networkError("Mock")
    }
}