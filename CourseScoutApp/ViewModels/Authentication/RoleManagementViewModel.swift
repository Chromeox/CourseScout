import Foundation
import SwiftUI
import Combine
import os.log

// MARK: - Role Management View Model

@MainActor
final class RoleManagementViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var showSuccess: Bool = false
    @Published var successMessage: String = ""
    
    // MARK: - Current User & Tenant
    
    @Published var currentUser: AuthenticatedUser?
    @Published var currentTenant: TenantInfo?
    @Published var userRoles: [TenantMembership] = []
    @Published var currentRole: TenantRole?
    @Published var permissions: [Permission] = []
    
    // MARK: - Role Management
    
    @Published var availableRoles: [TenantRole] = []
    @Published var roleDefinitions: [RoleDefinition] = []
    @Published var selectedRole: TenantRole?
    @Published var showRoleSelector: Bool = false
    @Published var pendingRoleChange: TenantRole?
    @Published var showRoleChangeConfirmation: Bool = false
    
    // MARK: - User Management (for admins)
    
    @Published var tenantUsers: [TenantUser] = []
    @Published var filteredUsers: [TenantUser] = []
    @Published var userSearchQuery: String = ""
    @Published var selectedUserFilter: UserFilter = .all
    @Published var sortOrder: UserSortOrder = .name
    @Published var showUserDetails: Bool = false
    @Published var selectedUser: TenantUser?
    
    // MARK: - Role Assignment
    
    @Published var isAssigningRole: Bool = false
    @Published var roleAssignmentTarget: TenantUser?
    @Published var showRoleAssignment: Bool = false
    @Published var bulkRoleAssignment: Bool = false
    @Published var selectedUsers: Set<String> = []
    @Published var bulkRole: TenantRole?
    
    // MARK: - Permission Management
    
    @Published var permissionGroups: [PermissionGroup] = []
    @Published var customPermissions: [CustomPermission] = []
    @Published var showPermissionEditor: Bool = false
    @Published var editingRole: RoleDefinition?
    @Published var tempPermissions: Set<Permission> = []
    
    // MARK: - Role Hierarchy
    
    @Published var roleHierarchy: RoleHierarchy?
    @Published var showRoleHierarchy: Bool = false
    @Published var canEscalateRoles: Bool = false
    @Published var maxAssignableRole: TenantRole?
    
    // MARK: - Access Control
    
    @Published var accessControlPolicies: [AccessControlPolicy] = []
    @Published var resourcePermissions: [ResourcePermission] = []
    @Published var showAccessControlMatrix: Bool = false
    @Published var conditionalAccess: [ConditionalAccessRule] = []
    
    // MARK: - Audit & Compliance
    
    @Published var roleChanges: [RoleChangeAudit] = []
    @Published var showAuditLog: Bool = false
    @Published var complianceStatus: ComplianceStatus?
    @Published var segregationOfDutiesViolations: [SODViolation] = []
    
    // MARK: - Invitations & Onboarding
    
    @Published var pendingInvitations: [RoleInvitation] = []
    @Published var showInviteUser: Bool = false
    @Published var inviteEmail: String = ""
    @Published var inviteRole: TenantRole?
    @Published var inviteMessage: String = ""
    @Published var inviteExpirationDays: Int = 7
    
    // MARK: - White Label Configuration
    
    @Published var tenantRoleConfiguration: TenantRoleConfiguration?
    @Published var customRoleNames: [TenantRole: String] = [:]
    @Published var brandedRoleInterface: BrandedRoleInterface?
    
    // MARK: - Dependencies
    
    private let authenticationService: AuthenticationServiceProtocol
    private let roleManagementService: RoleManagementServiceProtocol
    private let tenantConfigurationService: TenantConfigurationServiceProtocol
    private let auditService: AuditServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let logger = Logger(subsystem: "GolfFinderApp", category: "RoleManagementViewModel")
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var userSearchTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    
    var canManageUsers: Bool {
        return permissions.contains(.writeUsers) || currentRole == .owner || currentRole == .admin
    }
    
    var canManageRoles: Bool {
        return permissions.contains(.writeSettings) || currentRole == .owner
    }
    
    var canViewAuditLogs: Bool {
        return permissions.contains(.readAnalytics) || currentRole == .owner || currentRole == .admin
    }
    
    var canInviteUsers: Bool {
        return permissions.contains(.writeUsers) || currentRole == .owner || currentRole == .admin
    }
    
    var hasElevatedPermissions: Bool {
        return currentRole == .owner || currentRole == .admin || currentRole == .manager
    }
    
    var filteredAndSortedUsers: [TenantUser] {
        return filteredUsers.sorted { user1, user2 in
            switch sortOrder {
            case .name:
                return user1.displayName < user2.displayName
            case .role:
                return user1.role.rawValue < user2.role.rawValue
            case .lastActivity:
                return user1.lastActivityAt > user2.lastActivityAt
            case .joinDate:
                return user1.joinedAt < user2.joinedAt
            }
        }
    }
    
    var roleCapabilities: [RoleCapability] {
        guard let role = currentRole else { return [] }
        return getRoleCapabilities(for: role)
    }
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        roleManagementService: RoleManagementServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol,
        auditService: AuditServiceProtocol,
        notificationService: NotificationServiceProtocol
    ) {
        self.authenticationService = authenticationService
        self.roleManagementService = roleManagementService
        self.tenantConfigurationService = tenantConfigurationService
        self.auditService = auditService
        self.notificationService = notificationService
        
        setupObservers()
        loadCurrentUserAndTenant()
        logger.info("RoleManagementViewModel initialized")
    }
    
    deinit {
        userSearchTask?.cancel()
    }
    
    // MARK: - Setup Methods
    
    private func setupObservers() {
        // Monitor authentication state changes
        authenticationService.authenticationStateChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case .authenticated(let user, let tenant) = state {
                    self?.currentUser = user
                    self?.currentTenant = tenant
                    self?.loadUserRolesAndPermissions()
                }
            }
            .store(in: &cancellables)
        
        // Monitor user search query
        $userSearchQuery
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.filterUsers(query: query)
            }
            .store(in: &cancellables)
        
        // Monitor user filter changes
        $selectedUserFilter
            .sink { [weak self] filter in
                self?.applyUserFilter(filter)
            }
            .store(in: &cancellables)
    }
    
    private func loadCurrentUserAndTenant() {
        currentUser = authenticationService.currentUser
        
        Task {
            if let tenant = await authenticationService.getCurrentTenant() {
                await MainActor.run {
                    self.currentTenant = tenant
                }
            }
            
            await loadUserRolesAndPermissions()
        }
    }
    
    // MARK: - Role Loading
    
    func loadUserRolesAndPermissions() async {
        guard let user = currentUser,
              let tenant = currentTenant else { return }
        
        await MainActor.run {
            self.isLoading = true
        }
        
        do {
            // Load user's roles in the current tenant
            let memberships = try await roleManagementService.getUserTenantMemberships(
                userId: user.id,
                tenantId: tenant.id
            )
            
            // Get current role and permissions
            let currentMembership = memberships.first { $0.tenantId == tenant.id && $0.isActive }
            let userPermissions = currentMembership?.permissions ?? []
            
            // Load available roles for the tenant
            let availableRoles = try await roleManagementService.getAvailableRoles(tenantId: tenant.id)
            let roleDefinitions = try await roleManagementService.getRoleDefinitions(tenantId: tenant.id)
            
            // Load tenant role configuration
            let tenantConfig = try await tenantConfigurationService.getTenantRoleConfiguration(tenantId: tenant.id)
            let brandedInterface = try await tenantConfigurationService.getBrandedRoleInterface(tenantId: tenant.id)
            
            await MainActor.run {
                self.userRoles = memberships
                self.currentRole = currentMembership?.role
                self.permissions = userPermissions
                self.availableRoles = availableRoles
                self.roleDefinitions = roleDefinitions
                self.tenantRoleConfiguration = tenantConfig
                self.brandedRoleInterface = brandedInterface
                self.isLoading = false
                
                // Load additional data if user has appropriate permissions
                if self.canManageUsers {
                    Task {
                        await self.loadTenantUsers()
                    }
                }
                
                if self.canViewAuditLogs {
                    Task {
                        await self.loadRoleAuditHistory()
                    }
                }
            }
            
            logger.info("Loaded roles and permissions for user: \(user.id)")
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.showError = true
                self.errorMessage = "Failed to load roles: \(error.localizedDescription)"
            }
            
            logger.error("Failed to load user roles: \(error.localizedDescription)")
        }
    }
    
    func loadTenantUsers() async {
        guard let tenant = currentTenant,
              canManageUsers else { return }
        
        do {
            let users = try await roleManagementService.getTenantUsers(tenantId: tenant.id)
            let invitations = try await roleManagementService.getPendingInvitations(tenantId: tenant.id)
            
            await MainActor.run {
                self.tenantUsers = users
                self.filteredUsers = users
                self.pendingInvitations = invitations
            }
            
        } catch {
            await MainActor.run {
                self.showError = true
                self.errorMessage = "Failed to load users: \(error.localizedDescription)"
            }
        }
    }
    
    func loadRoleAuditHistory() async {
        guard let tenant = currentTenant,
              canViewAuditLogs else { return }
        
        do {
            let auditHistory = try await auditService.getRoleChangeHistory(
                tenantId: tenant.id,
                limit: 100
            )
            
            await MainActor.run {
                self.roleChanges = auditHistory
            }
            
        } catch {
            logger.error("Failed to load audit history: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Role Management
    
    func changeUserRole(to newRole: TenantRole) {
        selectedRole = newRole
        pendingRoleChange = newRole
        showRoleChangeConfirmation = true
    }
    
    func confirmRoleChange() {
        guard let user = currentUser,
              let tenant = currentTenant,
              let newRole = pendingRoleChange else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.showRoleChangeConfirmation = false
            }
            
            do {
                try await roleManagementService.changeUserRole(
                    userId: user.id,
                    tenantId: tenant.id,
                    newRole: newRole,
                    reason: "User requested role change"
                )
                
                // Reload roles and permissions
                await loadUserRolesAndPermissions()
                
                await MainActor.run {
                    self.isLoading = false
                    self.showSuccess = true
                    self.successMessage = "Role changed to \(newRole.displayName) successfully"
                    self.pendingRoleChange = nil
                }
                
                logger.info("Changed user role to: \(newRole.rawValue)")
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to change role: \(error.localizedDescription)"
                    self.pendingRoleChange = nil
                }
            }
        }
    }
    
    func assignRoleToUser(_ user: TenantUser, role: TenantRole) {
        guard let tenant = currentTenant,
              canManageUsers else { return }
        
        Task {
            await MainActor.run {
                self.isAssigningRole = true
            }
            
            do {
                try await roleManagementService.assignUserRole(
                    userId: user.userId,
                    tenantId: tenant.id,
                    role: role,
                    assignedBy: currentUser?.id ?? "",
                    reason: "Role assigned by admin"
                )
                
                await loadTenantUsers()
                
                await MainActor.run {
                    self.isAssigningRole = false
                    self.showSuccess = true
                    self.successMessage = "Role assigned to \(user.displayName) successfully"
                }
                
            } catch {
                await MainActor.run {
                    self.isAssigningRole = false
                    self.showError = true
                    self.errorMessage = "Failed to assign role: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func bulkAssignRole() {
        guard let tenant = currentTenant,
              let role = bulkRole,
              !selectedUsers.isEmpty,
              canManageUsers else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                try await roleManagementService.bulkAssignRole(
                    userIds: Array(selectedUsers),
                    tenantId: tenant.id,
                    role: role,
                    assignedBy: currentUser?.id ?? "",
                    reason: "Bulk role assignment"
                )
                
                await loadTenantUsers()
                
                await MainActor.run {
                    self.isLoading = false
                    self.selectedUsers = []
                    self.bulkRole = nil
                    self.bulkRoleAssignment = false
                    self.showSuccess = true
                    self.successMessage = "Bulk role assignment completed"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to assign roles: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - User Management
    
    private func filterUsers(query: String) {
        if query.isEmpty {
            filteredUsers = tenantUsers
        } else {
            filteredUsers = tenantUsers.filter { user in
                user.displayName.localizedCaseInsensitiveContains(query) ||
                user.email.localizedCaseInsensitiveContains(query) ||
                user.role.displayName.localizedCaseInsensitiveContains(query)
            }
        }
        
        applyUserFilter(selectedUserFilter)
    }
    
    private func applyUserFilter(_ filter: UserFilter) {
        switch filter {
        case .all:
            break
        case .active:
            filteredUsers = filteredUsers.filter { $0.isActive }
        case .inactive:
            filteredUsers = filteredUsers.filter { !$0.isActive }
        case .admins:
            filteredUsers = filteredUsers.filter { $0.role == .admin || $0.role == .owner }
        case .members:
            filteredUsers = filteredUsers.filter { $0.role == .member }
        case .pending:
            filteredUsers = filteredUsers.filter { $0.status == .pending }
        }
    }
    
    func removeUserFromTenant(_ user: TenantUser) {
        guard let tenant = currentTenant,
              canManageUsers,
              user.role != .owner else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                try await roleManagementService.removeUserFromTenant(
                    userId: user.userId,
                    tenantId: tenant.id,
                    removedBy: currentUser?.id ?? "",
                    reason: "Removed by admin"
                )
                
                await loadTenantUsers()
                
                await MainActor.run {
                    self.isLoading = false
                    self.showSuccess = true
                    self.successMessage = "\(user.displayName) removed from organization"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to remove user: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func suspendUser(_ user: TenantUser) {
        guard let tenant = currentTenant,
              canManageUsers else { return }
        
        Task {
            do {
                try await roleManagementService.suspendUser(
                    userId: user.userId,
                    tenantId: tenant.id,
                    suspendedBy: currentUser?.id ?? "",
                    reason: "Suspended by admin"
                )
                
                await loadTenantUsers()
                
                await MainActor.run {
                    self.showSuccess = true
                    self.successMessage = "\(user.displayName) has been suspended"
                }
                
            } catch {
                await MainActor.run {
                    self.showError = true
                    self.errorMessage = "Failed to suspend user: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func reactivateUser(_ user: TenantUser) {
        guard let tenant = currentTenant,
              canManageUsers else { return }
        
        Task {
            do {
                try await roleManagementService.reactivateUser(
                    userId: user.userId,
                    tenantId: tenant.id,
                    reactivatedBy: currentUser?.id ?? "",
                    reason: "Reactivated by admin"
                )
                
                await loadTenantUsers()
                
                await MainActor.run {
                    self.showSuccess = true
                    self.successMessage = "\(user.displayName) has been reactivated"
                }
                
            } catch {
                await MainActor.run {
                    self.showError = true
                    self.errorMessage = "Failed to reactivate user: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - User Invitations
    
    func inviteUser() {
        guard let tenant = currentTenant,
              let role = inviteRole,
              !inviteEmail.isEmpty,
              canInviteUsers else {
            showError = true
            errorMessage = "Please fill in all required fields"
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                let invitation = RoleInvitationRequest(
                    email: inviteEmail,
                    role: role,
                    tenantId: tenant.id,
                    invitedBy: currentUser?.id ?? "",
                    message: inviteMessage.isEmpty ? nil : inviteMessage,
                    expirationDays: inviteExpirationDays
                )
                
                try await roleManagementService.inviteUser(invitation)
                
                // Send notification email
                try await notificationService.sendInvitationEmail(
                    to: inviteEmail,
                    tenantName: tenant.name,
                    role: role,
                    inviterName: currentUser?.name ?? "Administrator",
                    customMessage: inviteMessage.isEmpty ? nil : inviteMessage
                )
                
                await loadTenantUsers()
                
                await MainActor.run {
                    self.isLoading = false
                    self.showInviteUser = false
                    self.inviteEmail = ""
                    self.inviteRole = nil
                    self.inviteMessage = ""
                    self.showSuccess = true
                    self.successMessage = "Invitation sent to \(inviteEmail)"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to send invitation: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func resendInvitation(_ invitation: RoleInvitation) {
        Task {
            do {
                try await roleManagementService.resendInvitation(invitationId: invitation.id)
                
                await MainActor.run {
                    self.showSuccess = true
                    self.successMessage = "Invitation resent to \(invitation.email)"
                }
                
            } catch {
                await MainActor.run {
                    self.showError = true
                    self.errorMessage = "Failed to resend invitation: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func cancelInvitation(_ invitation: RoleInvitation) {
        Task {
            do {
                try await roleManagementService.cancelInvitation(invitationId: invitation.id)
                
                await loadTenantUsers()
                
                await MainActor.run {
                    self.showSuccess = true
                    self.successMessage = "Invitation cancelled"
                }
                
            } catch {
                await MainActor.run {
                    self.showError = true
                    self.errorMessage = "Failed to cancel invitation: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Permission Management
    
    func loadPermissionGroups() async {
        guard let tenant = currentTenant else { return }
        
        do {
            let groups = try await roleManagementService.getPermissionGroups(tenantId: tenant.id)
            let customPerms = try await roleManagementService.getCustomPermissions(tenantId: tenant.id)
            
            await MainActor.run {
                self.permissionGroups = groups
                self.customPermissions = customPerms
            }
            
        } catch {
            logger.error("Failed to load permission groups: \(error.localizedDescription)")
        }
    }
    
    func editRolePermissions(_ role: RoleDefinition) {
        editingRole = role
        tempPermissions = Set(role.permissions)
        showPermissionEditor = true
    }
    
    func updateRolePermissions() {
        guard let role = editingRole,
              let tenant = currentTenant,
              canManageRoles else { return }
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            do {
                try await roleManagementService.updateRolePermissions(
                    roleId: role.id,
                    tenantId: tenant.id,
                    permissions: Array(tempPermissions),
                    updatedBy: currentUser?.id ?? ""
                )
                
                await loadUserRolesAndPermissions()
                
                await MainActor.run {
                    self.isLoading = false
                    self.showPermissionEditor = false
                    self.editingRole = nil
                    self.tempPermissions = []
                    self.showSuccess = true
                    self.successMessage = "Role permissions updated"
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showError = true
                    self.errorMessage = "Failed to update permissions: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getRoleCapabilities(for role: TenantRole) -> [RoleCapability] {
        switch role {
        case .owner:
            return [
                RoleCapability(name: "Full Access", description: "Complete control over the organization"),
                RoleCapability(name: "User Management", description: "Add, remove, and manage all users"),
                RoleCapability(name: "Role Management", description: "Create and modify roles and permissions"),
                RoleCapability(name: "Billing & Subscription", description: "Manage billing and subscription settings"),
                RoleCapability(name: "Security Settings", description: "Configure security policies and settings")
            ]
        case .admin:
            return [
                RoleCapability(name: "User Management", description: "Add, remove, and manage users"),
                RoleCapability(name: "Content Management", description: "Manage all content and data"),
                RoleCapability(name: "Analytics Access", description: "View detailed analytics and reports"),
                RoleCapability(name: "Settings Management", description: "Configure organization settings")
            ]
        case .manager:
            return [
                RoleCapability(name: "Team Management", description: "Manage team members and assignments"),
                RoleCapability(name: "Content Creation", description: "Create and edit content"),
                RoleCapability(name: "Basic Analytics", description: "View team and project analytics"),
                RoleCapability(name: "Resource Access", description: "Access to team resources")
            ]
        case .member:
            return [
                RoleCapability(name: "Content Access", description: "View and interact with content"),
                RoleCapability(name: "Basic Features", description: "Access to standard features"),
                RoleCapability(name: "Profile Management", description: "Manage own profile and preferences")
            ]
        case .guest:
            return [
                RoleCapability(name: "Limited Access", description: "Restricted access to basic features"),
                RoleCapability(name: "View Only", description: "View-only access to shared content")
            ]
        }
    }
    
    func getRoleDescription(for role: TenantRole) -> String {
        return tenantRoleConfiguration?.customDescriptions[role] ?? role.description
    }
    
    func getRoleDisplayName(for role: TenantRole) -> String {
        return customRoleNames[role] ?? role.displayName
    }
    
    // MARK: - UI Actions
    
    func showUserDetails(_ user: TenantUser) {
        selectedUser = user
        showUserDetails = true
    }
    
    func showRoleAssignmentSheet(for user: TenantUser) {
        roleAssignmentTarget = user
        showRoleAssignment = true
    }
    
    func showBulkRoleAssignment() {
        bulkRoleAssignment = true
    }
    
    func toggleUserSelection(_ userId: String) {
        if selectedUsers.contains(userId) {
            selectedUsers.remove(userId)
        } else {
            selectedUsers.insert(userId)
        }
    }
    
    func selectAllUsers() {
        selectedUsers = Set(filteredAndSortedUsers.map { $0.userId })
    }
    
    func deselectAllUsers() {
        selectedUsers.removeAll()
    }
    
    func showInviteUserSheet() {
        inviteEmail = ""
        inviteRole = .member
        inviteMessage = ""
        showInviteUser = true
    }
    
    func showAuditLogSheet() {
        showAuditLog = true
    }
    
    func showRoleHierarchySheet() {
        showRoleHierarchy = true
    }
    
    func showAccessControlMatrixSheet() {
        showAccessControlMatrix = true
    }
    
    func dismissError() {
        showError = false
        errorMessage = ""
    }
    
    func dismissSuccess() {
        showSuccess = false
        successMessage = ""
    }
    
    func cancelRoleChange() {
        showRoleChangeConfirmation = false
        pendingRoleChange = nil
    }
}

// MARK: - Supporting Types

struct TenantUser {
    let userId: String
    let email: String
    let displayName: String
    let role: TenantRole
    let permissions: [Permission]
    let isActive: Bool
    let status: UserStatus
    let joinedAt: Date
    let lastActivityAt: Date
    let profileImageURL: URL?
    let department: String?
    let title: String?
    
    enum UserStatus: String, CaseIterable {
        case active = "active"
        case inactive = "inactive"
        case pending = "pending"
        case suspended = "suspended"
        
        var displayName: String {
            switch self {
            case .active: return "Active"
            case .inactive: return "Inactive"
            case .pending: return "Pending"
            case .suspended: return "Suspended"
            }
        }
        
        var color: Color {
            switch self {
            case .active: return .green
            case .inactive: return .gray
            case .pending: return .orange
            case .suspended: return .red
            }
        }
    }
}

struct RoleDefinition {
    let id: String
    let role: TenantRole
    let displayName: String
    let description: String
    let permissions: [Permission]
    let isCustom: Bool
    let canBeModified: Bool
    let hierarchyLevel: Int
    let createdAt: Date
    let updatedAt: Date
}

struct RoleCapability {
    let name: String
    let description: String
}

struct PermissionGroup {
    let id: String
    let name: String
    let description: String
    let permissions: [Permission]
    let category: PermissionCategory
    
    enum PermissionCategory: String, CaseIterable {
        case user = "user"
        case content = "content"
        case settings = "settings"
        case analytics = "analytics"
        case billing = "billing"
        case security = "security"
        
        var displayName: String {
            switch self {
            case .user: return "User Management"
            case .content: return "Content Management"
            case .settings: return "Settings"
            case .analytics: return "Analytics"
            case .billing: return "Billing"
            case .security: return "Security"
            }
        }
    }
}

struct CustomPermission {
    let id: String
    let name: String
    let description: String
    let resource: String
    let actions: [String]
    let conditions: [AccessCondition]
    let isActive: Bool
}

struct AccessCondition {
    let field: String
    let operator: String
    let value: String
    let description: String
}

struct RoleHierarchy {
    let levels: [HierarchyLevel]
    let escalationRules: [EscalationRule]
    let restrictions: [HierarchyRestriction]
}

struct HierarchyLevel {
    let level: Int
    let roles: [TenantRole]
    let canManage: [TenantRole]
    let canAssign: [TenantRole]
}

struct EscalationRule {
    let fromRole: TenantRole
    let toRole: TenantRole
    let requiresApproval: Bool
    let approvers: [TenantRole]
    let conditions: [AccessCondition]
}

struct HierarchyRestriction {
    let role: TenantRole
    let restriction: RestrictionType
    let description: String
    
    enum RestrictionType {
        case cannotEscalate
        case cannotAssignHigher
        case requiresApproval
        case timeRestricted
    }
}

struct AccessControlPolicy {
    let id: String
    let name: String
    let description: String
    let resources: [String]
    let roles: [TenantRole]
    let permissions: [Permission]
    let conditions: [AccessCondition]
    let effect: PolicyEffect
    let isActive: Bool
    
    enum PolicyEffect: String {
        case allow = "allow"
        case deny = "deny"
    }
}

struct ResourcePermission {
    let resource: String
    let action: String
    let roles: [TenantRole]
    let conditions: [AccessCondition]
    let isAllowed: Bool
}

struct ConditionalAccessRule {
    let id: String
    let name: String
    let conditions: [AccessCondition]
    let action: ConditionalAction
    let isActive: Bool
    
    enum ConditionalAction {
        case allow
        case deny
        case requireMFA
        case requireApproval
        case restrictTime
    }
}

struct RoleChangeAudit {
    let id: String
    let userId: String
    let userEmail: String
    let previousRole: TenantRole?
    let newRole: TenantRole
    let changedBy: String
    let changedByEmail: String
    let reason: String?
    let timestamp: Date
    let ipAddress: String
    let userAgent: String
    let success: Bool
    let errorMessage: String?
}

struct ComplianceStatus {
    let isCompliant: Bool
    let violations: [ComplianceViolation]
    let lastAuditDate: Date
    let nextAuditDate: Date
    let score: Double
}

struct ComplianceViolation {
    let type: ViolationType
    let severity: Severity
    let description: String
    let remediation: String
    let dueDate: Date
    
    enum ViolationType {
        case segregationOfDuties
        case excessivePermissions
        case roleConflict
        case missingApproval
        case dataAccess
    }
    
    enum Severity {
        case low
        case medium
        case high
        case critical
    }
}

struct SODViolation {
    let userId: String
    let userEmail: String
    let conflictingRoles: [TenantRole]
    let conflictingPermissions: [Permission]
    let riskLevel: RiskLevel
    let description: String
    let detectedAt: Date
    
    enum RiskLevel {
        case low
        case medium
        case high
        case critical
    }
}

struct RoleInvitation {
    let id: String
    let email: String
    let role: TenantRole
    let tenantId: String
    let invitedBy: String
    let invitedByEmail: String
    let message: String?
    let status: InvitationStatus
    let sentAt: Date
    let expiresAt: Date
    let acceptedAt: Date?
    
    enum InvitationStatus: String, CaseIterable {
        case pending = "pending"
        case accepted = "accepted"
        case expired = "expired"
        case cancelled = "cancelled"
        
        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .accepted: return "Accepted"
            case .expired: return "Expired"
            case .cancelled: return "Cancelled"
            }
        }
        
        var color: Color {
            switch self {
            case .pending: return .orange
            case .accepted: return .green
            case .expired: return .gray
            case .cancelled: return .red
            }
        }
    }
}

struct RoleInvitationRequest {
    let email: String
    let role: TenantRole
    let tenantId: String
    let invitedBy: String
    let message: String?
    let expirationDays: Int
}

struct TenantRoleConfiguration {
    let customRoleNames: [TenantRole: String]
    let customDescriptions: [TenantRole: String]
    let hiddenRoles: Set<TenantRole>
    let roleHierarchy: RoleHierarchy?
    let customPermissions: [CustomPermission]
    let approvalWorkflows: [ApprovalWorkflow]
}

struct ApprovalWorkflow {
    let id: String
    let name: String
    let triggers: [WorkflowTrigger]
    let approvers: [TenantRole]
    let steps: [ApprovalStep]
    let isActive: Bool
}

struct WorkflowTrigger {
    let event: TriggerEvent
    let conditions: [AccessCondition]
    
    enum TriggerEvent {
        case roleChange
        case permissionGrant
        case userInvitation
        case accessRequest
    }
}

struct ApprovalStep {
    let stepNumber: Int
    let approverRoles: [TenantRole]
    let requiredApprovals: Int
    let timeout: TimeInterval
    let escalation: EscalationRule?
}

struct BrandedRoleInterface {
    let customRoleIcons: [TenantRole: String]
    let customColors: [TenantRole: String]
    let customLabels: [String: String]
    let hideSystemRoles: Bool
    let customOnboardingFlow: OnboardingFlow?
}

struct OnboardingFlow {
    let steps: [OnboardingStep]
    let customWelcomeMessage: String?
    let requiredTraining: [TrainingModule]
    let completionActions: [CompletionAction]
}

struct OnboardingStep {
    let id: String
    let title: String
    let description: String
    let content: OnboardingContent
    let isRequired: Bool
    let estimatedTime: TimeInterval
}

enum OnboardingContent {
    case text(String)
    case video(URL)
    case interactive(InteractiveContent)
    case quiz([QuizQuestion])
}

struct InteractiveContent {
    let type: String
    let data: [String: Any]
}

struct QuizQuestion {
    let question: String
    let options: [String]
    let correctAnswer: Int
    let explanation: String?
}

struct TrainingModule {
    let id: String
    let title: String
    let description: String
    let duration: TimeInterval
    let isRequired: Bool
    let completionCriteria: CompletionCriteria
}

struct CompletionCriteria {
    let minimumScore: Double?
    let timeSpent: TimeInterval?
    let interactions: [String]?
}

enum CompletionAction {
    case assignRole(TenantRole)
    case grantPermission(Permission)
    case sendNotification(String)
    case scheduleFollowUp(TimeInterval)
}

enum UserFilter: String, CaseIterable {
    case all = "all"
    case active = "active"
    case inactive = "inactive"
    case admins = "admins"
    case members = "members"
    case pending = "pending"
    
    var displayName: String {
        switch self {
        case .all: return "All Users"
        case .active: return "Active"
        case .inactive: return "Inactive"
        case .admins: return "Administrators"
        case .members: return "Members"
        case .pending: return "Pending"
        }
    }
}

enum UserSortOrder: String, CaseIterable {
    case name = "name"
    case role = "role"
    case lastActivity = "last_activity"
    case joinDate = "join_date"
    
    var displayName: String {
        switch self {
        case .name: return "Name"
        case .role: return "Role"
        case .lastActivity: return "Last Activity"
        case .joinDate: return "Join Date"
        }
    }
}

// MARK: - Service Protocols

protocol RoleManagementServiceProtocol {
    func getUserTenantMemberships(userId: String, tenantId: String) async throws -> [TenantMembership]
    func getAvailableRoles(tenantId: String) async throws -> [TenantRole]
    func getRoleDefinitions(tenantId: String) async throws -> [RoleDefinition]
    func getTenantUsers(tenantId: String) async throws -> [TenantUser]
    func getPendingInvitations(tenantId: String) async throws -> [RoleInvitation]
    func changeUserRole(userId: String, tenantId: String, newRole: TenantRole, reason: String) async throws
    func assignUserRole(userId: String, tenantId: String, role: TenantRole, assignedBy: String, reason: String) async throws
    func bulkAssignRole(userIds: [String], tenantId: String, role: TenantRole, assignedBy: String, reason: String) async throws
    func removeUserFromTenant(userId: String, tenantId: String, removedBy: String, reason: String) async throws
    func suspendUser(userId: String, tenantId: String, suspendedBy: String, reason: String) async throws
    func reactivateUser(userId: String, tenantId: String, reactivatedBy: String, reason: String) async throws
    func inviteUser(_ invitation: RoleInvitationRequest) async throws
    func resendInvitation(invitationId: String) async throws
    func cancelInvitation(invitationId: String) async throws
    func getPermissionGroups(tenantId: String) async throws -> [PermissionGroup]
    func getCustomPermissions(tenantId: String) async throws -> [CustomPermission]
    func updateRolePermissions(roleId: String, tenantId: String, permissions: [Permission], updatedBy: String) async throws
}

protocol AuditServiceProtocol {
    func getRoleChangeHistory(tenantId: String, limit: Int) async throws -> [RoleChangeAudit]
}

protocol NotificationServiceProtocol {
    func sendInvitationEmail(to email: String, tenantName: String, role: TenantRole, inviterName: String, customMessage: String?) async throws
}

// MARK: - Extensions

extension TenantRole {
    var description: String {
        switch self {
        case .owner:
            return "Full administrative control over the organization"
        case .admin:
            return "Administrative privileges with user and content management"
        case .manager:
            return "Team management and oversight capabilities"
        case .member:
            return "Standard user access with basic permissions"
        case .guest:
            return "Limited access for external users"
        }
    }
    
    var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .admin: return "Administrator"
        case .manager: return "Manager"
        case .member: return "Member"
        case .guest: return "Guest"
        }
    }
}

extension TenantConfigurationServiceProtocol {
    func getTenantRoleConfiguration(tenantId: String) async throws -> TenantRoleConfiguration {
        // Implementation would fetch tenant-specific role configuration
        return TenantRoleConfiguration(
            customRoleNames: [:],
            customDescriptions: [:],
            hiddenRoles: [],
            roleHierarchy: nil,
            customPermissions: [],
            approvalWorkflows: []
        )
    }
    
    func getBrandedRoleInterface(tenantId: String) async throws -> BrandedRoleInterface {
        // Implementation would fetch tenant branding for role interface
        return BrandedRoleInterface(
            customRoleIcons: [:],
            customColors: [:],
            customLabels: [:],
            hideSystemRoles: false,
            customOnboardingFlow: nil
        )
    }
}

// MARK: - Preview Support

extension RoleManagementViewModel {
    static var preview: RoleManagementViewModel {
        let mockAuth = ServiceContainer.shared.resolve(AuthenticationServiceProtocol.self)!
        let mockRole = MockRoleManagementService()
        let mockTenant = ServiceContainer.shared.resolve(TenantConfigurationServiceProtocol.self)!
        let mockAudit = MockAuditService()
        let mockNotification = MockNotificationService()
        
        return RoleManagementViewModel(
            authenticationService: mockAuth,
            roleManagementService: mockRole,
            tenantConfigurationService: mockTenant,
            auditService: mockAudit,
            notificationService: mockNotification
        )
    }
}

// MARK: - Mock Services

class MockRoleManagementService: RoleManagementServiceProtocol {
    func getUserTenantMemberships(userId: String, tenantId: String) async throws -> [TenantMembership] {
        return [
            TenantMembership(
                tenantId: tenantId,
                userId: userId,
                role: .admin,
                permissions: [.readUsers, .writeUsers, .readSettings],
                joinedAt: Date(),
                isActive: true
            )
        ]
    }
    
    func getAvailableRoles(tenantId: String) async throws -> [TenantRole] {
        return [.member, .manager, .admin]
    }
    
    func getRoleDefinitions(tenantId: String) async throws -> [RoleDefinition] {
        return []
    }
    
    func getTenantUsers(tenantId: String) async throws -> [TenantUser] {
        return []
    }
    
    func getPendingInvitations(tenantId: String) async throws -> [RoleInvitation] {
        return []
    }
    
    func changeUserRole(userId: String, tenantId: String, newRole: TenantRole, reason: String) async throws {
        // Mock implementation
    }
    
    func assignUserRole(userId: String, tenantId: String, role: TenantRole, assignedBy: String, reason: String) async throws {
        // Mock implementation
    }
    
    func bulkAssignRole(userIds: [String], tenantId: String, role: TenantRole, assignedBy: String, reason: String) async throws {
        // Mock implementation
    }
    
    func removeUserFromTenant(userId: String, tenantId: String, removedBy: String, reason: String) async throws {
        // Mock implementation
    }
    
    func suspendUser(userId: String, tenantId: String, suspendedBy: String, reason: String) async throws {
        // Mock implementation
    }
    
    func reactivateUser(userId: String, tenantId: String, reactivatedBy: String, reason: String) async throws {
        // Mock implementation
    }
    
    func inviteUser(_ invitation: RoleInvitationRequest) async throws {
        // Mock implementation
    }
    
    func resendInvitation(invitationId: String) async throws {
        // Mock implementation
    }
    
    func cancelInvitation(invitationId: String) async throws {
        // Mock implementation
    }
    
    func getPermissionGroups(tenantId: String) async throws -> [PermissionGroup] {
        return []
    }
    
    func getCustomPermissions(tenantId: String) async throws -> [CustomPermission] {
        return []
    }
    
    func updateRolePermissions(roleId: String, tenantId: String, permissions: [Permission], updatedBy: String) async throws {
        // Mock implementation
    }
}

class MockAuditService: AuditServiceProtocol {
    func getRoleChangeHistory(tenantId: String, limit: Int) async throws -> [RoleChangeAudit] {
        return []
    }
}

class MockNotificationService: NotificationServiceProtocol {
    func sendInvitationEmail(to email: String, tenantName: String, role: TenantRole, inviterName: String, customMessage: String?) async throws {
        // Mock implementation
    }
}