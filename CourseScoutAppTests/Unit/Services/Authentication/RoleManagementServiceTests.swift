import XCTest
import Combine
@testable import GolfFinderApp

// MARK: - Role Management Service Tests

final class RoleManagementServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: RoleManagementService!
    private var mockAppwriteClient: MockAppwriteClient!
    private var mockSecurityService: MockSecurityService!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        mockAppwriteClient = MockAppwriteClient()
        mockSecurityService = MockSecurityService()
        cancellables = Set<AnyCancellable>()
        
        sut = RoleManagementService(
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
    
    // MARK: - Role Creation Tests
    
    func testCreateRole_Success() async throws {
        // Given
        let roleData = TestDataFactory.createRoleData()
        let expectedRole = TestDataFactory.createRole()
        mockAppwriteClient.mockRole = expectedRole
        
        // When
        let result = try await sut.createRole(roleData: roleData)
        
        // Then
        XCTAssertEqual(result.id, expectedRole.id)
        XCTAssertEqual(result.name, roleData.name)
        XCTAssertEqual(result.description, roleData.description)
        XCTAssertEqual(result.permissions.count, roleData.permissions.count)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testCreateRole_DuplicateName() async {
        // Given
        let roleData = TestDataFactory.createRoleData(name: "Admin")
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.roleAlreadyExists
        
        // When & Then
        do {
            _ = try await sut.createRole(roleData: roleData)
            XCTFail("Expected role creation to fail")
        } catch AuthenticationError.roleAlreadyExists {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateRole_InvalidPermissions() async {
        // Given
        let invalidRoleData = RoleCreationData(
            name: "Test Role",
            description: "Test role with invalid permissions",
            permissions: ["invalid_permission"], // Invalid permission
            tenantId: "test_tenant",
            isSystemRole: false,
            inheritedRoles: []
        )
        
        // When & Then
        do {
            _ = try await sut.createRole(roleData: invalidRoleData)
            XCTFail("Expected role creation to fail")
        } catch AuthenticationError.invalidPermission {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateRole_WithInheritance() async throws {
        // Given
        let parentRole = TestDataFactory.createRole(name: "Parent Role")
        let roleData = TestDataFactory.createRoleData(
            inheritedRoles: [parentRole.id]
        )
        let expectedRole = TestDataFactory.createRole()
        
        mockAppwriteClient.mockRole = expectedRole
        mockAppwriteClient.mockInheritedRoles = [parentRole]
        
        // When
        let result = try await sut.createRole(roleData: roleData)
        
        // Then
        XCTAssertEqual(result.inheritedRoles.count, 1)
        XCTAssertTrue(result.inheritedRoles.contains(parentRole.id))
    }
    
    // MARK: - Role Management Tests
    
    func testGetRole_Success() async throws {
        // Given
        let roleId = "test_role_id"
        let expectedRole = TestDataFactory.createRole(id: roleId)
        mockAppwriteClient.mockRole = expectedRole
        
        // When
        let result = try await sut.getRole(roleId: roleId)
        
        // Then
        XCTAssertEqual(result.id, roleId)
        XCTAssertEqual(mockAppwriteClient.getDocumentCallCount, 1)
    }
    
    func testGetRole_NotFound() async {
        // Given
        let roleId = "nonexistent_role_id"
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.roleNotFound
        
        // When & Then
        do {
            _ = try await sut.getRole(roleId: roleId)
            XCTFail("Expected get to fail")
        } catch AuthenticationError.roleNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testUpdateRole_Success() async throws {
        // Given
        let roleId = "test_role_id"
        let updates = TestDataFactory.createRoleUpdates()
        let expectedRole = TestDataFactory.createRole(id: roleId)
        mockAppwriteClient.mockRole = expectedRole
        
        // When
        let result = try await sut.updateRole(roleId: roleId, updates: updates)
        
        // Then
        XCTAssertEqual(result.id, roleId)
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testUpdateRole_SystemRoleProtection() async {
        // Given
        let systemRoleId = "system_admin_role"
        let updates = TestDataFactory.createRoleUpdates()
        let systemRole = TestDataFactory.createRole(id: systemRoleId, isSystemRole: true)
        mockAppwriteClient.mockRole = systemRole
        
        // When & Then
        do {
            _ = try await sut.updateRole(roleId: systemRoleId, updates: updates)
            XCTFail("Expected update to fail for system role")
        } catch AuthenticationError.systemRoleProtected {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testDeleteRole_Success() async throws {
        // Given
        let roleId = "test_role_id"
        let role = TestDataFactory.createRole(id: roleId, isSystemRole: false)
        mockAppwriteClient.mockRole = role
        mockAppwriteClient.mockRoleAssignments = [] // No assignments
        
        // When
        try await sut.deleteRole(roleId: roleId)
        
        // Then
        XCTAssertEqual(mockAppwriteClient.deleteDocumentCallCount, 1)
    }
    
    func testDeleteRole_SystemRoleProtection() async {
        // Given
        let systemRoleId = "system_admin_role"
        let systemRole = TestDataFactory.createRole(id: systemRoleId, isSystemRole: true)
        mockAppwriteClient.mockRole = systemRole
        
        // When & Then
        do {
            try await sut.deleteRole(roleId: systemRoleId)
            XCTFail("Expected deletion to fail for system role")
        } catch AuthenticationError.systemRoleProtected {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testDeleteRole_HasActiveAssignments() async {
        // Given
        let roleId = "test_role_id"
        let role = TestDataFactory.createRole(id: roleId)
        let assignments = [TestDataFactory.createRoleAssignment(roleId: roleId)]
        
        mockAppwriteClient.mockRole = role
        mockAppwriteClient.mockRoleAssignments = assignments
        
        // When & Then
        do {
            try await sut.deleteRole(roleId: roleId)
            XCTFail("Expected deletion to fail for role with assignments")
        } catch AuthenticationError.roleHasActiveAssignments {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Permission Management Tests
    
    func testAddPermissionToRole_Success() async throws {
        // Given
        let roleId = "test_role_id"
        let permission = Permission.readUsers
        let role = TestDataFactory.createRole(id: roleId)
        let updatedRole = TestDataFactory.createRole(id: roleId, permissions: role.permissions + [permission])
        
        mockAppwriteClient.mockRole = role
        mockAppwriteClient.mockUpdatedRole = updatedRole
        
        // When
        let result = try await sut.addPermissionToRole(roleId: roleId, permission: permission)
        
        // Then
        XCTAssertTrue(result.permissions.contains(permission))
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testAddPermissionToRole_AlreadyExists() async {
        // Given
        let roleId = "test_role_id"
        let permission = Permission.readUsers
        let role = TestDataFactory.createRole(id: roleId, permissions: [permission]) // Already has permission
        
        mockAppwriteClient.mockRole = role
        
        // When & Then
        do {
            _ = try await sut.addPermissionToRole(roleId: roleId, permission: permission)
            XCTFail("Expected addition to fail")
        } catch AuthenticationError.permissionAlreadyExists {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testRemovePermissionFromRole_Success() async throws {
        // Given
        let roleId = "test_role_id"
        let permission = Permission.readUsers
        let role = TestDataFactory.createRole(id: roleId, permissions: [permission, Permission.writeUsers])
        let updatedRole = TestDataFactory.createRole(id: roleId, permissions: [Permission.writeUsers])
        
        mockAppwriteClient.mockRole = role
        mockAppwriteClient.mockUpdatedRole = updatedRole
        
        // When
        let result = try await sut.removePermissionFromRole(roleId: roleId, permission: permission)
        
        // Then
        XCTAssertFalse(result.permissions.contains(permission))
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1)
    }
    
    func testRemovePermissionFromRole_NotFound() async {
        // Given
        let roleId = "test_role_id"
        let permission = Permission.readUsers
        let role = TestDataFactory.createRole(id: roleId, permissions: [Permission.writeUsers]) // Doesn't have permission
        
        mockAppwriteClient.mockRole = role
        
        // When & Then
        do {
            _ = try await sut.removePermissionFromRole(roleId: roleId, permission: permission)
            XCTFail("Expected removal to fail")
        } catch AuthenticationError.permissionNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testGetRolePermissions_Success() async throws {
        // Given
        let roleId = "test_role_id"
        let permissions = [Permission.readUsers, Permission.writeUsers, Permission.deleteUsers]
        let role = TestDataFactory.createRole(id: roleId, permissions: permissions)
        
        mockAppwriteClient.mockRole = role
        
        // When
        let result = try await sut.getRolePermissions(roleId: roleId)
        
        // Then
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.contains(.readUsers))
        XCTAssertTrue(result.contains(.writeUsers))
        XCTAssertTrue(result.contains(.deleteUsers))
    }
    
    func testGetEffectivePermissions_WithInheritance() async throws {
        // Given
        let roleId = "child_role_id"
        let parentRoleId = "parent_role_id"
        
        let parentRole = TestDataFactory.createRole(
            id: parentRoleId,
            permissions: [Permission.readUsers, Permission.writeUsers]
        )
        let childRole = TestDataFactory.createRole(
            id: roleId,
            permissions: [Permission.deleteUsers],
            inheritedRoles: [parentRoleId]
        )
        
        mockAppwriteClient.mockRole = childRole
        mockAppwriteClient.mockInheritedRoles = [parentRole]
        
        // When
        let result = try await sut.getEffectivePermissions(roleId: roleId)
        
        // Then
        XCTAssertEqual(result.count, 3) // Combined permissions
        XCTAssertTrue(result.contains(.readUsers)) // From parent
        XCTAssertTrue(result.contains(.writeUsers)) // From parent
        XCTAssertTrue(result.contains(.deleteUsers)) // Direct permission
    }
    
    // MARK: - User Role Assignment Tests
    
    func testAssignRoleToUser_Success() async throws {
        // Given
        let userId = "test_user_id"
        let roleId = "test_role_id"
        let tenantId = "test_tenant_id"
        let assignmentData = TestDataFactory.createRoleAssignmentData(
            userId: userId,
            roleId: roleId,
            tenantId: tenantId
        )
        let expectedAssignment = TestDataFactory.createRoleAssignment()
        
        mockAppwriteClient.mockRoleAssignment = expectedAssignment
        
        // When
        let result = try await sut.assignRoleToUser(assignmentData: assignmentData)
        
        // Then
        XCTAssertEqual(result.userId, userId)
        XCTAssertEqual(result.roleId, roleId)
        XCTAssertEqual(result.tenantId, tenantId)
        XCTAssertEqual(result.status, .active)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
    
    func testAssignRoleToUser_AlreadyAssigned() async {
        // Given
        let userId = "test_user_id"
        let roleId = "test_role_id"
        let tenantId = "test_tenant_id"
        let assignmentData = TestDataFactory.createRoleAssignmentData(
            userId: userId,
            roleId: roleId,
            tenantId: tenantId
        )
        
        // Mock existing assignment
        let existingAssignment = TestDataFactory.createRoleAssignment(
            userId: userId,
            roleId: roleId,
            tenantId: tenantId
        )
        mockAppwriteClient.mockExistingRoleAssignments = [existingAssignment]
        
        // When & Then
        do {
            _ = try await sut.assignRoleToUser(assignmentData: assignmentData)
            XCTFail("Expected assignment to fail")
        } catch AuthenticationError.roleAlreadyAssigned {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testAssignRoleToUser_InvalidRole() async {
        // Given
        let userId = "test_user_id"
        let invalidRoleId = "nonexistent_role_id"
        let tenantId = "test_tenant_id"
        let assignmentData = TestDataFactory.createRoleAssignmentData(
            userId: userId,
            roleId: invalidRoleId,
            tenantId: tenantId
        )
        
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.roleNotFound
        
        // When & Then
        do {
            _ = try await sut.assignRoleToUser(assignmentData: assignmentData)
            XCTFail("Expected assignment to fail")
        } catch AuthenticationError.roleNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testRemoveRoleFromUser_Success() async throws {
        // Given
        let userId = "test_user_id"
        let roleId = "test_role_id"
        let tenantId = "test_tenant_id"
        
        let existingAssignment = TestDataFactory.createRoleAssignment(
            userId: userId,
            roleId: roleId,
            tenantId: tenantId
        )
        mockAppwriteClient.mockRoleAssignment = existingAssignment
        
        // When
        try await sut.removeRoleFromUser(
            userId: userId,
            roleId: roleId,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertEqual(mockAppwriteClient.updateDocumentCallCount, 1) // Mark as inactive
    }
    
    func testRemoveRoleFromUser_NotAssigned() async {
        // Given
        let userId = "test_user_id"
        let roleId = "test_role_id"
        let tenantId = "test_tenant_id"
        
        mockAppwriteClient.shouldThrowError = true
        mockAppwriteClient.errorToThrow = AuthenticationError.roleNotAssigned
        
        // When & Then
        do {
            try await sut.removeRoleFromUser(
                userId: userId,
                roleId: roleId,
                tenantId: tenantId
            )
            XCTFail("Expected removal to fail")
        } catch AuthenticationError.roleNotAssigned {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testGetUserRoles_Success() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let userRoles = [
            TestDataFactory.createRole(name: "Admin"),
            TestDataFactory.createRole(name: "Editor"),
            TestDataFactory.createRole(name: "Viewer")
        ]
        
        mockAppwriteClient.mockUserRoles = userRoles
        
        // When
        let result = try await sut.getUserRoles(userId: userId, tenantId: tenantId)
        
        // Then
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.contains { $0.name == "Admin" })
        XCTAssertTrue(result.contains { $0.name == "Editor" })
        XCTAssertTrue(result.contains { $0.name == "Viewer" })
    }
    
    func testGetUserEffectivePermissions_Success() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        
        let userRoles = [
            TestDataFactory.createRole(permissions: [Permission.readUsers, Permission.writeUsers]),
            TestDataFactory.createRole(permissions: [Permission.deleteUsers, Permission.manageRoles])
        ]
        
        mockAppwriteClient.mockUserRoles = userRoles
        
        // When
        let result = try await sut.getUserEffectivePermissions(userId: userId, tenantId: tenantId)
        
        // Then
        XCTAssertEqual(result.count, 4) // Combined unique permissions
        XCTAssertTrue(result.contains(.readUsers))
        XCTAssertTrue(result.contains(.writeUsers))
        XCTAssertTrue(result.contains(.deleteUsers))
        XCTAssertTrue(result.contains(.manageRoles))
    }
    
    // MARK: - Permission Checking Tests
    
    func testCheckUserPermission_HasPermission() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let permission = Permission.readUsers
        
        let userRoles = [
            TestDataFactory.createRole(permissions: [permission, Permission.writeUsers])
        ]
        
        mockAppwriteClient.mockUserRoles = userRoles
        
        // When
        let result = try await sut.checkUserPermission(
            userId: userId,
            permission: permission,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertTrue(result)
    }
    
    func testCheckUserPermission_NoPermission() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let permission = Permission.deleteUsers
        
        let userRoles = [
            TestDataFactory.createRole(permissions: [Permission.readUsers, Permission.writeUsers])
        ]
        
        mockAppwriteClient.mockUserRoles = userRoles
        
        // When
        let result = try await sut.checkUserPermission(
            userId: userId,
            permission: permission,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertFalse(result)
    }
    
    func testCheckUserPermissions_AllRequired() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let requiredPermissions = [Permission.readUsers, Permission.writeUsers]
        
        let userRoles = [
            TestDataFactory.createRole(permissions: [Permission.readUsers, Permission.writeUsers, Permission.deleteUsers])
        ]
        
        mockAppwriteClient.mockUserRoles = userRoles
        
        // When
        let result = try await sut.checkUserPermissions(
            userId: userId,
            permissions: requiredPermissions,
            requireAll: true,
            tenantId: tenantId
        )
        
        // Then
        XCTAssertTrue(result)
    }
    
    func testCheckUserPermissions_AnyRequired() async throws {
        // Given
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let requiredPermissions = [Permission.deleteUsers, Permission.manageRoles] // User only has deleteUsers
        
        let userRoles = [
            TestDataFactory.createRole(permissions: [Permission.readUsers, Permission.deleteUsers])
        ]
        
        mockAppwriteClient.mockUserRoles = userRoles
        
        // When
        let result = try await sut.checkUserPermissions(
            userId: userId,
            permissions: requiredPermissions,
            requireAll: false, // Any permission is sufficient
            tenantId: tenantId
        )
        
        // Then
        XCTAssertTrue(result) // Has deleteUsers
    }
    
    // MARK: - Role Hierarchy Tests
    
    func testGetRoleHierarchy_Success() async throws {
        // Given
        let tenantId = "test_tenant_id"
        let hierarchy = TestDataFactory.createRoleHierarchy()
        mockAppwriteClient.mockRoleHierarchy = hierarchy
        
        // When
        let result = try await sut.getRoleHierarchy(tenantId: tenantId)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result.levels.count, 0)
    }
    
    func testValidateRoleHierarchy_Valid() async throws {
        // Given
        let parentRoleId = "parent_role"
        let childRoleId = "child_role"
        
        let parentRole = TestDataFactory.createRole(id: parentRoleId, level: 1)
        let childRole = TestDataFactory.createRole(id: childRoleId, level: 2)
        
        mockAppwriteClient.mockRoles = [parentRole, childRole]
        
        // When
        let result = try await sut.validateRoleHierarchy(
            parentRoleId: parentRoleId,
            childRoleId: childRoleId
        )
        
        // Then
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.violations.isEmpty)
    }
    
    func testValidateRoleHierarchy_CircularReference() async throws {
        // Given
        let roleAId = "role_a"
        let roleBId = "role_b"
        
        // Mock circular reference: A inherits from B, B inherits from A
        let roleA = TestDataFactory.createRole(id: roleAId, inheritedRoles: [roleBId])
        let roleB = TestDataFactory.createRole(id: roleBId, inheritedRoles: [roleAId])
        
        mockAppwriteClient.mockRoles = [roleA, roleB]
        mockSecurityService.mockCircularReference = true
        
        // When
        let result = try await sut.validateRoleHierarchy(
            parentRoleId: roleAId,
            childRoleId: roleBId
        )
        
        // Then
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.violations.contains(.circularReference))
    }
    
    // MARK: - Performance Tests
    
    func testRoleCreationPerformance() {
        let roleData = TestDataFactory.createRoleData()
        
        measure {
            let expectation = XCTestExpectation(description: "Role creation performance")
            
            Task {
                do {
                    _ = try await sut.createRole(roleData: roleData)
                } catch {
                    // Ignore errors for performance test
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testBulkPermissionCheckPerformance() {
        let userId = "test_user_id"
        let tenantId = "test_tenant_id"
        let permissions = Permission.allCases
        
        measure {
            let expectation = XCTestExpectation(description: "Bulk permission check performance")
            
            Task {
                for permission in permissions {
                    do {
                        _ = try await sut.checkUserPermission(
                            userId: userId,
                            permission: permission,
                            tenantId: tenantId
                        )
                    } catch {
                        // Ignore errors for performance test
                    }
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 2.0)
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentRoleOperations() async {
        // Given
        let taskCount = 10
        
        // When
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    do {
                        if i % 2 == 0 {
                            let roleData = TestDataFactory.createRoleData(name: "Role_\(i)")
                            _ = try await self.sut.createRole(roleData: roleData)
                        } else {
                            _ = try await self.sut.getRole(roleId: "role_\(i)")
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
    
    func testRoleWithMaximumPermissions() async throws {
        // Given
        let allPermissions = Permission.allCases
        let roleData = TestDataFactory.createRoleData(
            name: "Super Admin",
            permissions: allPermissions
        )
        let expectedRole = TestDataFactory.createRole(permissions: allPermissions)
        mockAppwriteClient.mockRole = expectedRole
        
        // When
        let result = try await sut.createRole(roleData: roleData)
        
        // Then
        XCTAssertEqual(result.permissions.count, allPermissions.count)
        XCTAssertTrue(allPermissions.allSatisfy { result.permissions.contains($0) })
    }
    
    func testRoleWithSpecialCharactersInName() async throws {
        // Given
        let specialName = "Rôle with éç special chars 特殊 🎮"
        let roleData = TestDataFactory.createRoleData(name: specialName)
        let expectedRole = TestDataFactory.createRole(name: specialName)
        mockAppwriteClient.mockRole = expectedRole
        
        // When
        let result = try await sut.createRole(roleData: roleData)
        
        // Then
        XCTAssertEqual(result.name, specialName)
        XCTAssertEqual(mockAppwriteClient.createDocumentCallCount, 1)
    }
}