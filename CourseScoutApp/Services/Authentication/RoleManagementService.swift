import Foundation
import Appwrite
import os.log

// MARK: - Role Management Service Protocol

protocol RoleManagementServiceProtocol {
    // MARK: - Role Hierarchy Management
    func createRole(_ role: GolfRole) async throws -> String
    func updateRole(_ roleId: String, updates: GolfRoleUpdate) async throws -> GolfRole
    func deleteRole(_ roleId: String) async throws
    func getRole(_ roleId: String) async throws -> GolfRole?
    func getAllRoles() async throws -> [GolfRole]
    
    // MARK: - User Role Assignment
    func assignRole(userId: String, roleId: String, scope: RoleScope?) async throws
    func removeRole(userId: String, roleId: String, scope: RoleScope?) async throws
    func getUserRoles(_ userId: String) async throws -> [UserRoleAssignment]
    func updateUserRole(_ assignmentId: String, updates: RoleAssignmentUpdate) async throws
    
    // MARK: - Permission System
    func createPermission(_ permission: GolfPermission) async throws -> String
    func assignPermissionToRole(roleId: String, permissionId: String) async throws
    func removePermissionFromRole(roleId: String, permissionId: String) async throws
    func getUserPermissions(_ userId: String, scope: RoleScope?) async throws -> [GolfPermission]
    func checkPermission(userId: String, permission: String, scope: RoleScope?) async throws -> Bool
    
    // MARK: - Golf Course Role Hierarchy
    func createCourseRole(_ courseId: String, role: CourseRole) async throws -> String
    func assignCourseRole(userId: String, courseId: String, roleId: String) async throws
    func getCourseStaff(_ courseId: String) async throws -> [CourseStaffMember]
    func updateStaffRole(_ staffId: String, newRoleId: String) async throws
    
    // MARK: - Dynamic Permissions Based on Handicap/Achievements
    func evaluateHandicapBasedPermissions(_ userId: String) async throws -> [GolfPermission]
    func updateAchievementPermissions(userId: String, newAchievements: [GolfAchievement]) async throws
    func getSkillBasedPermissions(_ handicap: Double, achievements: [GolfAchievement]) async -> [GolfPermission]
    
    // MARK: - Multi-Tenant Support
    func createTenantRole(_ tenantId: String, role: TenantRole) async throws -> String
    func assignTenantRole(userId: String, tenantId: String, roleId: String) async throws
    func getTenantRoles(_ tenantId: String) async throws -> [TenantRole]
    func validateTenantAccess(userId: String, tenantId: String, requiredPermission: String) async throws -> Bool
    
    // MARK: - Role Validation & Security
    func validateRoleAssignment(_ assignment: RoleAssignmentRequest) async throws -> RoleValidationResult
    func auditRoleChange(_ change: RoleChangeAudit) async throws
    func getAccessControlMatrix(_ userId: String) async throws -> AccessControlMatrix
}

// MARK: - Role Management Service Implementation

@MainActor
final class RoleManagementService: RoleManagementServiceProtocol {
    
    // MARK: - Properties
    
    private let appwriteClient: Client
    private let databases: Databases
    private let logger = Logger(subsystem: "GolfFinderApp", category: "RoleManagement")
    private let encryptionService: RoleEncryptionService
    private let permissionEvaluator: PermissionEvaluator
    
    // MARK: - Database Collections
    
    private let rolesCollection = "golf_roles"
    private let permissionsCollection = "golf_permissions"
    private let roleAssignmentsCollection = "role_assignments"
    private let courseRolesCollection = "course_roles"
    private let tenantRolesCollection = "tenant_roles"
    private let roleAuditLogCollection = "role_audit_log"
    private let achievementPermissionsCollection = "achievement_permissions"
    
    // MARK: - Role Hierarchy Definitions
    
    private let defaultRoleHierarchy: [String: [String]] = [
        "super_admin": [],
        "chain_admin": ["super_admin"],
        "course_manager": ["chain_admin"],
        "golf_pro": ["course_manager"],
        "staff": ["golf_pro"],
        "premium_member": ["staff"],
        "member": ["premium_member"],
        "guest": ["member"]
    ]
    
    // MARK: - Initialization
    
    init(appwriteClient: Client) {
        self.appwriteClient = appwriteClient
        self.databases = Databases(appwriteClient)
        self.encryptionService = RoleEncryptionService()
        self.permissionEvaluator = PermissionEvaluator()
        
        logger.info("RoleManagementService initialized")
    }
    
    // MARK: - Role Hierarchy Management
    
    func createRole(_ role: GolfRole) async throws -> String {
        logger.info("Creating role: \(role.name)")
        
        // Validate role creation
        try await validateRoleCreation(role)
        
        let roleId = ID.unique()
        
        // Store role in database
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: rolesCollection,
            documentId: roleId,
            data: [
                "name": role.name,
                "display_name": role.displayName,
                "description": role.description,
                "level": role.level,
                "parent_roles": role.parentRoles,
                "permissions": role.permissions.map { $0.rawValue },
                "scope_type": role.scopeType.rawValue,
                "is_active": role.isActive,
                "created_at": Date().timeIntervalSince1970,
                "created_by": role.createdBy ?? ""
            ]
        )
        
        // Audit role creation
        await auditRoleChange(
            RoleChangeAudit(
                userId: role.createdBy ?? "system",
                action: .roleCreated,
                roleId: roleId,
                roleName: role.name,
                details: ["level": role.level],
                timestamp: Date()
            )
        )
        
        logger.info("Role created successfully: \(roleId)")
        return roleId
    }
    
    func updateRole(_ roleId: String, updates: GolfRoleUpdate) async throws -> GolfRole {
        logger.info("Updating role: \(roleId)")
        
        // Retrieve existing role
        let document = try await databases.getDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: rolesCollection,
            documentId: roleId
        )
        
        let existingRole = try parseGolfRole(from: document.data)
        
        // Apply updates
        var updateData: [String: Any] = ["updated_at": Date().timeIntervalSince1970]
        
        if let displayName = updates.displayName {
            updateData["display_name"] = displayName
        }
        
        if let description = updates.description {
            updateData["description"] = description
        }
        
        if let permissions = updates.permissions {
            updateData["permissions"] = permissions.map { $0.rawValue }
        }
        
        if let isActive = updates.isActive {
            updateData["is_active"] = isActive
        }
        
        // Update role
        _ = try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: rolesCollection,
            documentId: roleId,
            data: updateData
        )
        
        // Audit role update
        await auditRoleChange(
            RoleChangeAudit(
                userId: updates.updatedBy ?? "system",
                action: .roleUpdated,
                roleId: roleId,
                roleName: existingRole.name,
                details: updateData,
                timestamp: Date()
            )
        )
        
        // Return updated role
        let updatedDocument = try await databases.getDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: rolesCollection,
            documentId: roleId
        )
        
        return try parseGolfRole(from: updatedDocument.data)
    }
    
    func deleteRole(_ roleId: String) async throws {
        logger.info("Deleting role: \(roleId)")
        
        // Check if role is in use
        let usageCount = try await getRoleUsageCount(roleId)
        guard usageCount == 0 else {
            throw RoleManagementError.roleInUse
        }
        
        // Get role info for audit
        let document = try await databases.getDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: rolesCollection,
            documentId: roleId
        )
        let role = try parseGolfRole(from: document.data)
        
        // Delete role
        try await databases.deleteDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: rolesCollection,
            documentId: roleId
        )
        
        // Audit role deletion
        await auditRoleChange(
            RoleChangeAudit(
                userId: "system",
                action: .roleDeleted,
                roleId: roleId,
                roleName: role.name,
                details: [:],
                timestamp: Date()
            )
        )
        
        logger.info("Role deleted successfully: \(roleId)")
    }
    
    func getRole(_ roleId: String) async throws -> GolfRole? {
        do {
            let document = try await databases.getDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: rolesCollection,
                documentId: roleId
            )
            return try parseGolfRole(from: document.data)
        } catch {
            return nil
        }
    }
    
    func getAllRoles() async throws -> [GolfRole] {
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: rolesCollection,
            queries: [Query.orderAsc("level")]
        )
        
        return try documents.documents.compactMap { document in
            try parseGolfRole(from: document.data)
        }
    }
    
    // MARK: - User Role Assignment
    
    func assignRole(userId: String, roleId: String, scope: RoleScope?) async throws {
        logger.info("Assigning role \(roleId) to user \(userId)")
        
        // Validate role assignment
        let validationResult = try await validateRoleAssignment(
            RoleAssignmentRequest(
                userId: userId,
                roleId: roleId,
                scope: scope,
                assignedBy: "system"
            )
        )
        
        guard validationResult.isValid else {
            throw RoleManagementError.invalidRoleAssignment(validationResult.reason ?? "Unknown error")
        }
        
        // Check if assignment already exists
        if try await roleAssignmentExists(userId: userId, roleId: roleId, scope: scope) {
            throw RoleManagementError.roleAlreadyAssigned
        }
        
        let assignmentId = ID.unique()
        
        // Create role assignment
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: roleAssignmentsCollection,
            documentId: assignmentId,
            data: [
                "user_id": userId,
                "role_id": roleId,
                "scope_type": scope?.type.rawValue ?? "",
                "scope_id": scope?.id ?? "",
                "assigned_at": Date().timeIntervalSince1970,
                "assigned_by": "system",
                "is_active": true
            ]
        )
        
        // Audit role assignment
        await auditRoleChange(
            RoleChangeAudit(
                userId: userId,
                action: .roleAssigned,
                roleId: roleId,
                roleName: (try? await getRole(roleId))?.name ?? "Unknown",
                details: ["scope": scope?.description ?? "global"],
                timestamp: Date()
            )
        )
        
        logger.info("Role assigned successfully: \(assignmentId)")
    }
    
    func removeRole(userId: String, roleId: String, scope: RoleScope?) async throws {
        logger.info("Removing role \(roleId) from user \(userId)")
        
        // Find role assignment
        let query = [
            Query.equal("user_id", value: userId),
            Query.equal("role_id", value: roleId),
            Query.equal("scope_type", value: scope?.type.rawValue ?? ""),
            Query.equal("scope_id", value: scope?.id ?? "")
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: roleAssignmentsCollection,
            queries: query
        )
        
        guard let assignment = documents.documents.first else {
            throw RoleManagementError.roleAssignmentNotFound
        }
        
        // Remove role assignment
        try await databases.deleteDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: roleAssignmentsCollection,
            documentId: assignment.id
        )
        
        // Audit role removal
        await auditRoleChange(
            RoleChangeAudit(
                userId: userId,
                action: .roleRemoved,
                roleId: roleId,
                roleName: (try? await getRole(roleId))?.name ?? "Unknown",
                details: ["scope": scope?.description ?? "global"],
                timestamp: Date()
            )
        )
        
        logger.info("Role removed successfully from user: \(userId)")
    }
    
    func getUserRoles(_ userId: String) async throws -> [UserRoleAssignment] {
        let query = [
            Query.equal("user_id", value: userId),
            Query.equal("is_active", value: true)
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: roleAssignmentsCollection,
            queries: query
        )
        
        var assignments: [UserRoleAssignment] = []
        
        for document in documents.documents {
            if let assignment = try? parseRoleAssignment(from: document.data),
               let role = try? await getRole(assignment.roleId) {
                assignments.append(UserRoleAssignment(
                    id: document.id,
                    userId: assignment.userId,
                    role: role,
                    scope: assignment.scope,
                    assignedAt: assignment.assignedAt,
                    assignedBy: assignment.assignedBy
                ))
            }
        }
        
        return assignments
    }
    
    func updateUserRole(_ assignmentId: String, updates: RoleAssignmentUpdate) async throws {
        var updateData: [String: Any] = ["updated_at": Date().timeIntervalSince1970]
        
        if let isActive = updates.isActive {
            updateData["is_active"] = isActive
        }
        
        _ = try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: roleAssignmentsCollection,
            documentId: assignmentId,
            data: updateData
        )
    }
    
    // MARK: - Permission System
    
    func createPermission(_ permission: GolfPermission) async throws -> String {
        let permissionId = ID.unique()
        
        // Store permission
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: permissionsCollection,
            documentId: permissionId,
            data: [
                "name": permission.name,
                "display_name": permission.displayName,
                "description": permission.description,
                "category": permission.category.rawValue,
                "resource_type": permission.resourceType,
                "action": permission.action,
                "is_active": true,
                "created_at": Date().timeIntervalSince1970
            ]
        )
        
        return permissionId
    }
    
    func assignPermissionToRole(roleId: String, permissionId: String) async throws {
        // Implementation for assigning permission to role
    }
    
    func removePermissionFromRole(roleId: String, permissionId: String) async throws {
        // Implementation for removing permission from role
    }
    
    func getUserPermissions(_ userId: String, scope: RoleScope?) async throws -> [GolfPermission] {
        // Get user roles
        let userRoles = try await getUserRoles(userId)
        
        // Collect all permissions from roles
        var permissions = Set<GolfPermission>()
        
        for roleAssignment in userRoles {
            // Filter by scope if specified
            if let scope = scope, !roleAssignment.scope?.matches(scope) ?? false {
                continue
            }
            
            permissions.formUnion(roleAssignment.role.permissions)
        }
        
        // Add handicap-based permissions
        let handicapPermissions = try await evaluateHandicapBasedPermissions(userId)
        permissions.formUnion(handicapPermissions)
        
        return Array(permissions)
    }
    
    func checkPermission(userId: String, permission: String, scope: RoleScope?) async throws -> Bool {
        let userPermissions = try await getUserPermissions(userId, scope: scope)
        return userPermissions.contains { $0.name == permission }
    }
    
    // MARK: - Golf Course Role Hierarchy
    
    func createCourseRole(_ courseId: String, role: CourseRole) async throws -> String {
        let roleId = ID.unique()
        
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: courseRolesCollection,
            documentId: roleId,
            data: [
                "course_id": courseId,
                "name": role.name,
                "display_name": role.displayName,
                "description": role.description,
                "permissions": role.permissions.map { $0.rawValue },
                "salary_range": role.salaryRange ?? [],
                "requirements": role.requirements,
                "is_active": true,
                "created_at": Date().timeIntervalSince1970
            ]
        )
        
        return roleId
    }
    
    func assignCourseRole(userId: String, courseId: String, roleId: String) async throws {
        try await assignRole(
            userId: userId,
            roleId: roleId,
            scope: RoleScope(type: .course, id: courseId, description: "Course \(courseId)")
        )
    }
    
    func getCourseStaff(_ courseId: String) async throws -> [CourseStaffMember] {
        let query = [
            Query.equal("scope_type", value: ScopeType.course.rawValue),
            Query.equal("scope_id", value: courseId),
            Query.equal("is_active", value: true)
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: roleAssignmentsCollection,
            queries: query
        )
        
        var staff: [CourseStaffMember] = []
        
        for document in documents.documents {
            if let assignment = try? parseRoleAssignment(from: document.data),
               let role = try? await getRole(assignment.roleId) {
                staff.append(CourseStaffMember(
                    userId: assignment.userId,
                    role: role,
                    assignedAt: assignment.assignedAt,
                    isActive: true
                ))
            }
        }
        
        return staff
    }
    
    func updateStaffRole(_ staffId: String, newRoleId: String) async throws {
        _ = try await databases.updateDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: roleAssignmentsCollection,
            documentId: staffId,
            data: [
                "role_id": newRoleId,
                "updated_at": Date().timeIntervalSince1970
            ]
        )
    }
    
    // MARK: - Dynamic Permissions Based on Handicap/Achievements
    
    func evaluateHandicapBasedPermissions(_ userId: String) async throws -> [GolfPermission] {
        // Get user's handicap and achievements
        let userProfile = try await getUserGolfProfile(userId)
        
        return getSkillBasedPermissions(
            userProfile.handicap ?? 36.0,
            achievements: userProfile.achievements
        )
    }
    
    func updateAchievementPermissions(userId: String, newAchievements: [GolfAchievement]) async throws {
        // Update user's achievement-based permissions
        let additionalPermissions = getAchievementPermissions(newAchievements)
        
        // Store achievement permissions
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: achievementPermissionsCollection,
            documentId: ID.unique(),
            data: [
                "user_id": userId,
                "achievements": newAchievements.map { $0.rawValue },
                "granted_permissions": additionalPermissions.map { $0.rawValue },
                "updated_at": Date().timeIntervalSince1970
            ]
        )
    }
    
    func getSkillBasedPermissions(_ handicap: Double, achievements: [GolfAchievement]) async -> [GolfPermission] {
        var permissions: [GolfPermission] = []
        
        // Handicap-based permissions
        if handicap <= 5.0 {
            permissions.append(contentsOf: [
                .competitiveTournaments,
                .proShopDiscount,
                .instructorRecommendations
            ])
        } else if handicap <= 15.0 {
            permissions.append(contentsOf: [
                .clubTournaments,
                .memberEvents
            ])
        }
        
        // Achievement-based permissions
        permissions.append(contentsOf: getAchievementPermissions(achievements))
        
        return permissions
    }
    
    // MARK: - Multi-Tenant Support
    
    func createTenantRole(_ tenantId: String, role: TenantRole) async throws -> String {
        let roleId = ID.unique()
        
        try await databases.createDocument(
            databaseId: Configuration.appwriteProjectId,
            collectionId: tenantRolesCollection,
            documentId: roleId,
            data: [
                "tenant_id": tenantId,
                "name": role.name,
                "display_name": role.displayName,
                "description": role.description,
                "permissions": role.permissions.map { $0.rawValue },
                "inheritance_rules": role.inheritanceRules,
                "is_active": true,
                "created_at": Date().timeIntervalSince1970
            ]
        )
        
        return roleId
    }
    
    func assignTenantRole(userId: String, tenantId: String, roleId: String) async throws {
        try await assignRole(
            userId: userId,
            roleId: roleId,
            scope: RoleScope(type: .tenant, id: tenantId, description: "Tenant \(tenantId)")
        )
    }
    
    func getTenantRoles(_ tenantId: String) async throws -> [TenantRole] {
        let query = [Query.equal("tenant_id", value: tenantId)]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: tenantRolesCollection,
            queries: query
        )
        
        return try documents.documents.compactMap { document in
            try parseTenantRole(from: document.data)
        }
    }
    
    func validateTenantAccess(userId: String, tenantId: String, requiredPermission: String) async throws -> Bool {
        let tenantScope = RoleScope(type: .tenant, id: tenantId, description: "Tenant \(tenantId)")
        return try await checkPermission(userId: userId, permission: requiredPermission, scope: tenantScope)
    }
    
    // MARK: - Role Validation & Security
    
    func validateRoleAssignment(_ assignment: RoleAssignmentRequest) async throws -> RoleValidationResult {
        // Check if role exists
        guard let role = try await getRole(assignment.roleId) else {
            return RoleValidationResult(
                isValid: false,
                reason: "Role does not exist"
            )
        }
        
        // Check if user exists (simplified check)
        if assignment.userId.isEmpty {
            return RoleValidationResult(
                isValid: false,
                reason: "Invalid user ID"
            )
        }
        
        // Check role hierarchy constraints
        if let scope = assignment.scope,
           !isValidRoleForScope(role: role, scope: scope) {
            return RoleValidationResult(
                isValid: false,
                reason: "Role not valid for specified scope"
            )
        }
        
        return RoleValidationResult(isValid: true, reason: nil)
    }
    
    func auditRoleChange(_ change: RoleChangeAudit) async {
        do {
            try await databases.createDocument(
                databaseId: Configuration.appwriteProjectId,
                collectionId: roleAuditLogCollection,
                documentId: ID.unique(),
                data: [
                    "user_id": change.userId,
                    "action": change.action.rawValue,
                    "role_id": change.roleId,
                    "role_name": change.roleName,
                    "details": change.details,
                    "timestamp": change.timestamp.timeIntervalSince1970,
                    "ip_address": await getCurrentIPAddress(),
                    "user_agent": getCurrentUserAgent()
                ]
            )
        } catch {
            logger.error("Failed to audit role change: \(error.localizedDescription)")
        }
    }
    
    func getAccessControlMatrix(_ userId: String) async throws -> AccessControlMatrix {
        let userRoles = try await getUserRoles(userId)
        let permissions = try await getUserPermissions(userId, scope: nil)
        
        return AccessControlMatrix(
            userId: userId,
            roles: userRoles.map { $0.role },
            permissions: permissions,
            scopes: userRoles.compactMap { $0.scope }
        )
    }
    
    // MARK: - Helper Methods
    
    private func validateRoleCreation(_ role: GolfRole) async throws {
        // Check for duplicate role names
        let existingRoles = try await getAllRoles()
        if existingRoles.contains(where: { $0.name == role.name }) {
            throw RoleManagementError.roleNameAlreadyExists
        }
        
        // Validate role hierarchy
        for parentRole in role.parentRoles {
            guard existingRoles.contains(where: { $0.name == parentRole }) else {
                throw RoleManagementError.invalidParentRole(parentRole)
            }
        }
    }
    
    private func getRoleUsageCount(_ roleId: String) async throws -> Int {
        let query = [Query.equal("role_id", value: roleId)]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: roleAssignmentsCollection,
            queries: query
        )
        
        return documents.total
    }
    
    private func roleAssignmentExists(userId: String, roleId: String, scope: RoleScope?) async throws -> Bool {
        let query = [
            Query.equal("user_id", value: userId),
            Query.equal("role_id", value: roleId),
            Query.equal("scope_type", value: scope?.type.rawValue ?? ""),
            Query.equal("scope_id", value: scope?.id ?? ""),
            Query.equal("is_active", value: true)
        ]
        
        let documents = try await databases.listDocuments(
            databaseId: Configuration.appwriteProjectId,
            collectionId: roleAssignmentsCollection,
            queries: query
        )
        
        return !documents.documents.isEmpty
    }
    
    private func isValidRoleForScope(role: GolfRole, scope: RoleScope) -> Bool {
        // Implement scope validation logic
        return role.scopeType == .global || role.scopeType == scope.type
    }
    
    private func getAchievementPermissions(_ achievements: [GolfAchievement]) -> [GolfPermission] {
        var permissions: [GolfPermission] = []
        
        for achievement in achievements {
            switch achievement {
            case .holeInOne:
                permissions.append(.specialEvents)
            case .courseRecord:
                permissions.append(.competitiveTournaments)
            case .clubChampion:
                permissions.append(.championshipEvents)
            case .longestDrive:
                permissions.append(.drivingRange)
            }
        }
        
        return permissions
    }
    
    private func getUserGolfProfile(_ userId: String) async throws -> UserGolfProfile {
        // Retrieve user's golf profile with handicap and achievements
        return UserGolfProfile(
            userId: userId,
            handicap: nil,
            achievements: []
        )
    }
    
    private func parseGolfRole(from data: [String: Any]) throws -> GolfRole {
        guard let name = data["name"] as? String,
              let displayName = data["display_name"] as? String,
              let description = data["description"] as? String,
              let level = data["level"] as? Int else {
            throw RoleManagementError.invalidRoleData
        }
        
        let parentRoles = data["parent_roles"] as? [String] ?? []
        let permissionsRaw = data["permissions"] as? [String] ?? []
        let permissions = permissionsRaw.compactMap { GolfPermission(rawValue: $0) }
        let scopeType = ScopeType(rawValue: data["scope_type"] as? String ?? "global") ?? .global
        let isActive = data["is_active"] as? Bool ?? true
        
        return GolfRole(
            name: name,
            displayName: displayName,
            description: description,
            level: level,
            parentRoles: parentRoles,
            permissions: permissions,
            scopeType: scopeType,
            isActive: isActive,
            createdBy: data["created_by"] as? String
        )
    }
    
    private func parseRoleAssignment(from data: [String: Any]) throws -> RoleAssignment {
        guard let userId = data["user_id"] as? String,
              let roleId = data["role_id"] as? String,
              let assignedAtTimestamp = data["assigned_at"] as? TimeInterval else {
            throw RoleManagementError.invalidAssignmentData
        }
        
        let scopeType = data["scope_type"] as? String
        let scopeId = data["scope_id"] as? String
        let scope = (scopeType.map { ScopeType(rawValue: $0) } ?? nil).flatMap { type in
            scopeId.map { RoleScope(type: type, id: $0, description: "") }
        }
        
        return RoleAssignment(
            userId: userId,
            roleId: roleId,
            scope: scope,
            assignedAt: Date(timeIntervalSince1970: assignedAtTimestamp),
            assignedBy: data["assigned_by"] as? String ?? "system"
        )
    }
    
    private func parseTenantRole(from data: [String: Any]) throws -> TenantRole {
        guard let name = data["name"] as? String,
              let displayName = data["display_name"] as? String else {
            throw RoleManagementError.invalidRoleData
        }
        
        return TenantRole(
            name: name,
            displayName: displayName,
            description: data["description"] as? String ?? "",
            permissions: [],
            inheritanceRules: data["inheritance_rules"] as? [String: Any] ?? [:]
        )
    }
    
    private func getCurrentIPAddress() async -> String {
        return "127.0.0.1"
    }
    
    private func getCurrentUserAgent() -> String {
        return "GolfFinderApp/1.0"
    }
}

// MARK: - Supporting Services

private class RoleEncryptionService {
    // Encryption service for sensitive role data
}

private class PermissionEvaluator {
    // Service for evaluating complex permission logic
}

// MARK: - Data Models

struct GolfRole {
    let name: String
    let displayName: String
    let description: String
    let level: Int
    let parentRoles: [String]
    let permissions: [GolfPermission]
    let scopeType: ScopeType
    let isActive: Bool
    let createdBy: String?
}

struct GolfRoleUpdate {
    let displayName: String?
    let description: String?
    let permissions: [GolfPermission]?
    let isActive: Bool?
    let updatedBy: String?
}

struct UserRoleAssignment {
    let id: String
    let userId: String
    let role: GolfRole
    let scope: RoleScope?
    let assignedAt: Date
    let assignedBy: String
}

struct RoleAssignment {
    let userId: String
    let roleId: String
    let scope: RoleScope?
    let assignedAt: Date
    let assignedBy: String
}

struct RoleAssignmentRequest {
    let userId: String
    let roleId: String
    let scope: RoleScope?
    let assignedBy: String
}

struct RoleAssignmentUpdate {
    let isActive: Bool?
}

struct RoleScope {
    let type: ScopeType
    let id: String
    let description: String
    
    func matches(_ other: RoleScope) -> Bool {
        return type == other.type && id == other.id
    }
}

struct CourseRole {
    let name: String
    let displayName: String
    let description: String
    let permissions: [GolfPermission]
    let salaryRange: [Double]?
    let requirements: [String]
}

struct CourseStaffMember {
    let userId: String
    let role: GolfRole
    let assignedAt: Date
    let isActive: Bool
}

struct TenantRole {
    let name: String
    let displayName: String
    let description: String
    let permissions: [GolfPermission]
    let inheritanceRules: [String: Any]
}

struct RoleValidationResult {
    let isValid: Bool
    let reason: String?
}

struct RoleChangeAudit {
    let userId: String
    let action: RoleAction
    let roleId: String
    let roleName: String
    let details: [String: Any]
    let timestamp: Date
}

struct AccessControlMatrix {
    let userId: String
    let roles: [GolfRole]
    let permissions: [GolfPermission]
    let scopes: [RoleScope]
}

struct UserGolfProfile {
    let userId: String
    let handicap: Double?
    let achievements: [GolfAchievement]
}

// MARK: - Enums

enum ScopeType: String, CaseIterable {
    case global = "global"
    case tenant = "tenant"
    case course = "course"
    case tournament = "tournament"
    case group = "group"
}

enum RoleAction: String, CaseIterable {
    case roleCreated = "role_created"
    case roleUpdated = "role_updated"
    case roleDeleted = "role_deleted"
    case roleAssigned = "role_assigned"
    case roleRemoved = "role_removed"
}

enum GolfPermission: String, CaseIterable {
    // Basic permissions
    case viewCourses = "view_courses"
    case bookTeeTime = "book_tee_time"
    case submitScores = "submit_scores"
    case viewLeaderboard = "view_leaderboard"
    
    // Member permissions
    case memberEvents = "member_events"
    case clubTournaments = "club_tournaments"
    case proShopDiscount = "pro_shop_discount"
    
    // Advanced permissions
    case competitiveTournaments = "competitive_tournaments"
    case instructorRecommendations = "instructor_recommendations"
    case specialEvents = "special_events"
    case championshipEvents = "championship_events"
    case drivingRange = "driving_range"
    
    // Staff permissions
    case manageCourse = "manage_course"
    case manageBookings = "manage_bookings"
    case viewReports = "view_reports"
    case manageMembers = "manage_members"
    
    // Admin permissions
    case systemAdmin = "system_admin"
    case chainAdmin = "chain_admin"
    
    var displayName: String {
        switch self {
        case .viewCourses: return "View Courses"
        case .bookTeeTime: return "Book Tee Time"
        case .submitScores: return "Submit Scores"
        case .viewLeaderboard: return "View Leaderboard"
        case .memberEvents: return "Member Events"
        case .clubTournaments: return "Club Tournaments"
        case .proShopDiscount: return "Pro Shop Discount"
        case .competitiveTournaments: return "Competitive Tournaments"
        case .instructorRecommendations: return "Instructor Recommendations"
        case .specialEvents: return "Special Events"
        case .championshipEvents: return "Championship Events"
        case .drivingRange: return "Driving Range"
        case .manageCourse: return "Manage Course"
        case .manageBookings: return "Manage Bookings"
        case .viewReports: return "View Reports"
        case .manageMembers: return "Manage Members"
        case .systemAdmin: return "System Admin"
        case .chainAdmin: return "Chain Admin"
        }
    }
    
    var description: String {
        return displayName
    }
    
    var category: PermissionCategory {
        switch self {
        case .viewCourses, .viewLeaderboard:
            return .read
        case .bookTeeTime, .submitScores:
            return .write
        case .manageCourse, .manageBookings, .manageMembers:
            return .manage
        case .systemAdmin, .chainAdmin:
            return .admin
        default:
            return .member
        }
    }
    
    var resourceType: String {
        switch self {
        case .viewCourses, .manageCourse:
            return "course"
        case .bookTeeTime, .manageBookings:
            return "booking"
        case .submitScores, .viewLeaderboard:
            return "score"
        case .manageMembers:
            return "member"
        default:
            return "system"
        }
    }
    
    var action: String {
        switch self {
        case .viewCourses, .viewLeaderboard, .viewReports:
            return "read"
        case .bookTeeTime, .submitScores:
            return "create"
        case .manageCourse, .manageBookings, .manageMembers:
            return "manage"
        default:
            return "access"
        }
    }
}

enum PermissionCategory: String, CaseIterable {
    case read = "read"
    case write = "write"
    case manage = "manage"
    case admin = "admin"
    case member = "member"
}

enum GolfAchievement: String, CaseIterable {
    case holeInOne = "hole_in_one"
    case courseRecord = "course_record"
    case clubChampion = "club_champion"
    case longestDrive = "longest_drive"
}

enum RoleManagementError: Error, LocalizedError {
    case roleNameAlreadyExists
    case invalidParentRole(String)
    case roleInUse
    case invalidRoleAssignment(String)
    case roleAlreadyAssigned
    case roleAssignmentNotFound
    case invalidRoleData
    case invalidAssignmentData
    
    var errorDescription: String? {
        switch self {
        case .roleNameAlreadyExists:
            return "Role name already exists"
        case .invalidParentRole(let role):
            return "Invalid parent role: \(role)"
        case .roleInUse:
            return "Cannot delete role that is currently in use"
        case .invalidRoleAssignment(let reason):
            return "Invalid role assignment: \(reason)"
        case .roleAlreadyAssigned:
            return "Role already assigned to user"
        case .roleAssignmentNotFound:
            return "Role assignment not found"
        case .invalidRoleData:
            return "Invalid role data"
        case .invalidAssignmentData:
            return "Invalid assignment data"
        }
    }
}