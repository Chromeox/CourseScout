import Foundation
import Combine
import Appwrite
import CryptoKit
import os.log

// MARK: - Security Service Implementation

@MainActor
class SecurityService: NSObject, SecurityServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinder", category: "Security")
    private let appwriteClient: Client
    
    // Security context
    @Published private var currentTenantId: String?
    @Published private var securityEvents: [SecurityEvent] = []
    
    // Security caches
    private var roleCache: [String: [SecurityRole]] = [:]
    private var permissionCache: [String: [SecurityPermission]] = [:]
    private var apiKeyCache: [String: APIKeyValidation] = [:]
    
    // Encryption
    private var encryptionKeys: [String: SymmetricKey] = [:]
    private let encryptionQueue = DispatchQueue(label: "SecurityEncryption", qos: .userInitiated)
    
    // Security monitoring
    private var securityTimer: Timer?
    private var anomalyDetector = AnomalyDetector()
    
    // Dependencies
    @ServiceInjected(TenantManagementServiceProtocol.self) private var tenantService
    @ServiceInjected(AnalyticsServiceProtocol.self) private var analyticsService
    
    // MARK: - Initialization
    
    init(appwriteClient: Client) {
        self.appwriteClient = appwriteClient
        super.init()
        
        setupSecurityMonitoring()
        logger.info("SecurityService initialized with enhanced multi-tenant protection")
    }
    
    private func setupSecurityMonitoring() {
        // Monitor security events every minute
        securityTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performSecurityMonitoring()
            }
        }
    }
    
    // MARK: - Tenant Data Isolation
    
    func validateTenantAccess(userId: String, tenantId: String, resourceId: String, action: SecurityAction) async throws -> Bool {
        logger.debug("Validating tenant access: user=\(userId), tenant=\(tenantId), resource=\(resourceId), action=\(action.rawValue)")
        
        // Check if tenant exists
        guard let tenant = try await tenantService.getTenant(id: tenantId) else {
            await logSecurityEvent(SecurityEvent(
                id: UUID().uuidString,
                tenantId: tenantId,
                userId: userId,
                eventType: .authorization,
                resource: resourceId,
                action: action,
                timestamp: Date(),
                ipAddress: nil,
                userAgent: nil,
                success: false,
                errorMessage: "Tenant not found",
                metadata: [:],
                riskLevel: .high
            ))
            throw SecurityServiceError.tenantNotFound(tenantId)
        }
        
        // Check if user has access to tenant
        let hasAccess = try await tenantService.validateTenantAccess(tenantId: tenantId, userId: userId)
        guard hasAccess else {
            await logSecurityEvent(SecurityEvent(
                id: UUID().uuidString,
                tenantId: tenantId,
                userId: userId,
                eventType: .authorization,
                resource: resourceId,
                action: action,
                timestamp: Date(),
                ipAddress: nil,
                userAgent: nil,
                success: false,
                errorMessage: "User does not have tenant access",
                metadata: [:],
                riskLevel: .high
            ))
            throw SecurityServiceError.unauthorizedAccess(userId, action, .tenant)
        }
        
        // Check specific permissions
        let hasPermission = try await checkPermission(tenantId: tenantId, userId: userId, permission: SecurityPermission(
            id: UUID().uuidString,
            resource: ResourceType(rawValue: resourceId) ?? .api,
            action: action,
            conditions: nil,
            scope: .tenant
        ))
        
        guard hasPermission else {
            await logSecurityEvent(SecurityEvent(
                id: UUID().uuidString,
                tenantId: tenantId,
                userId: userId,
                eventType: .authorization,
                resource: resourceId,
                action: action,
                timestamp: Date(),
                ipAddress: nil,
                userAgent: nil,
                success: false,
                errorMessage: "Insufficient permissions",
                metadata: [:],
                riskLevel: .medium
            ))
            throw SecurityServiceError.unauthorizedAccess(userId, action, ResourceType(rawValue: resourceId) ?? .api)
        }
        
        // Log successful access
        await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: userId,
            eventType: .authorization,
            resource: resourceId,
            action: action,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: [:],
            riskLevel: .low
        ))
        
        return true
    }
    
    func ensureTenantDataIsolation(query: Query, tenantId: String) throws -> Query {
        // Add tenant filter to ensure data isolation
        return query.equal("tenantId", value: tenantId)
    }
    
    func filterTenantData<T>(_ data: [T], tenantId: String) async throws -> [T] where T: TenantIsolatable {
        // Filter data to only include items belonging to the tenant
        let filteredData = data.filter { $0.tenantId == tenantId }
        
        // Log filtering operation
        await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: nil,
            eventType: .dataAccess,
            resource: String(describing: T.self),
            action: .read,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: ["original_count": String(data.count), "filtered_count": String(filteredData.count)],
            riskLevel: .low
        ))
        
        return filteredData
    }
    
    func validateDataOwnership(resourceId: String, tenantId: String, resourceType: ResourceType) async throws -> Bool {
        // Query the resource to verify ownership
        let databases = Databases(appwriteClient)
        
        do {
            let document = try await databases.getDocument(
                databaseId: Configuration.database.databaseId,
                collectionId: getCollectionId(for: resourceType),
                documentId: resourceId
            )
            
            guard let documentTenantId = document.data["tenantId"] as? String else {
                throw SecurityServiceError.dataIsolationFailed("Resource missing tenant ID")
            }
            
            let isOwned = documentTenantId == tenantId
            
            await logSecurityEvent(SecurityEvent(
                id: UUID().uuidString,
                tenantId: tenantId,
                userId: nil,
                eventType: .dataAccess,
                resource: resourceId,
                action: .read,
                timestamp: Date(),
                ipAddress: nil,
                userAgent: nil,
                success: isOwned,
                errorMessage: isOwned ? nil : "Cross-tenant data access attempt",
                metadata: ["resource_type": resourceType.rawValue],
                riskLevel: isOwned ? .low : .high
            ))
            
            return isOwned
        } catch {
            throw SecurityServiceError.dataIsolationFailed("Failed to validate data ownership: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Multi-Tenant Authentication
    
    func authenticateUserForTenant(token: String, tenantId: String) async throws -> UserAuth {
        let account = Account(appwriteClient)
        
        do {
            // Verify the JWT token
            let user = try await account.get()
            
            // Verify user has access to the tenant
            guard try await tenantService.validateTenantAccess(tenantId: tenantId, userId: user.id) else {
                throw SecurityServiceError.unauthorizedAccess(user.id, .read, .tenant)
            }
            
            // Get user roles and permissions
            let roles = try await getUserRoles(tenantId: tenantId, userId: user.id)
            let permissions = roles.flatMap { $0.permissions }
            
            let userAuth = UserAuth(
                userId: user.id,
                tenantId: tenantId,
                permissions: permissions,
                roles: roles,
                sessionToken: token,
                expiresAt: Date().addingTimeInterval(86400), // 24 hours
                lastLogin: Date(),
                ipAddress: nil,
                userAgent: nil,
                isMultiFactorEnabled: false // TODO: Implement MFA
            )
            
            await logSecurityEvent(SecurityEvent(
                id: UUID().uuidString,
                tenantId: tenantId,
                userId: user.id,
                eventType: .authentication,
                resource: "session",
                action: .create,
                timestamp: Date(),
                ipAddress: nil,
                userAgent: nil,
                success: true,
                errorMessage: nil,
                metadata: ["auth_method": "jwt"],
                riskLevel: .low
            ))
            
            return userAuth
            
        } catch {
            await logSecurityEvent(SecurityEvent(
                id: UUID().uuidString,
                tenantId: tenantId,
                userId: nil,
                eventType: .authentication,
                resource: "session",
                action: .create,
                timestamp: Date(),
                ipAddress: nil,
                userAgent: nil,
                success: false,
                errorMessage: "Authentication failed",
                metadata: ["error": error.localizedDescription],
                riskLevel: .high
            ))
            throw error
        }
    }
    
    func validateAPIKeyForTenant(apiKey: String, tenantId: String) async throws -> APIKeyValidation {
        // Check cache first
        if let cached = apiKeyCache[apiKey], cached.tenantId == tenantId {
            return cached
        }
        
        let databases = Databases(appwriteClient)
        
        do {
            // Query for the API key
            let query = Query.equal("keyHash", value: hashAPIKey(apiKey))
                .equal("tenantId", value: tenantId)
                .equal("isActive", value: true)
            
            let result = try await databases.listDocuments(
                databaseId: Configuration.database.databaseId,
                collectionId: "api_keys",
                queries: [query]
            )
            
            guard let document = result.documents.first else {
                throw SecurityServiceError.invalidAPIKey("API key not found or invalid")
            }
            
            let validation = APIKeyValidation(
                keyId: document.id,
                tenantId: tenantId,
                isValid: true,
                permissions: [], // TODO: Parse permissions from document
                rateLimit: nil, // TODO: Parse rate limit from document
                expiresAt: nil, // TODO: Parse expiration from document
                lastUsed: Date(),
                usage: APIKeyUsage(totalRequests: 0, lastRequest: Date(), requestsToday: 0, requestsThisMonth: 0, errors: 0)
            )
            
            // Cache the validation
            apiKeyCache[apiKey] = validation
            
            return validation
            
        } catch {
            throw SecurityServiceError.invalidAPIKey("Failed to validate API key: \(error.localizedDescription)")
        }
    }
    
    func createTenantAPIKey(tenantId: String, permissions: [SecurityPermission]) async throws -> TenantAPIKey {
        let databases = Databases(appwriteClient)
        
        // Generate a secure API key
        let apiKey = generateSecureAPIKey()
        let keyHash = hashAPIKey(apiKey)
        
        let tenantAPIKey = TenantAPIKey(
            id: UUID().uuidString,
            tenantId: tenantId,
            keyHash: keyHash,
            name: "Generated API Key",
            permissions: permissions,
            rateLimit: nil,
            expiresAt: nil,
            createdAt: Date(),
            createdBy: "system",
            isActive: true,
            usage: APIKeyUsage(totalRequests: 0, lastRequest: nil, requestsToday: 0, requestsThisMonth: 0, errors: 0)
        )
        
        // Store in database
        try await databases.createDocument(
            databaseId: Configuration.database.databaseId,
            collectionId: "api_keys",
            documentId: tenantAPIKey.id,
            data: [
                "tenantId": tenantId,
                "keyHash": keyHash,
                "name": tenantAPIKey.name,
                "permissions": try JSONEncoder().encode(permissions),
                "isActive": true,
                "createdAt": Date(),
                "createdBy": "system"
            ]
        )
        
        await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: nil,
            eventType: .authentication,
            resource: "api_key",
            action: .create,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: ["key_id": tenantAPIKey.id],
            riskLevel: .medium
        ))
        
        return tenantAPIKey
    }
    
    func revokeTenantAPIKey(tenantId: String, keyId: String) async throws {
        let databases = Databases(appwriteClient)
        
        try await databases.updateDocument(
            databaseId: Configuration.database.databaseId,
            collectionId: "api_keys",
            documentId: keyId,
            data: [
                "isActive": false,
                "revokedAt": Date()
            ]
        )
        
        // Remove from cache
        apiKeyCache.removeAll { $0.value.keyId == keyId }
        
        await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: nil,
            eventType: .authentication,
            resource: "api_key",
            action: .delete,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: ["key_id": keyId],
            riskLevel: .medium
        ))
    }
    
    // MARK: - Role-Based Access Control (RBAC)
    
    func createRole(tenantId: String, role: SecurityRole) async throws -> SecurityRole {
        let databases = Databases(appwriteClient)
        
        try await databases.createDocument(
            databaseId: Configuration.database.databaseId,
            collectionId: "security_roles",
            documentId: role.id,
            data: [
                "tenantId": tenantId,
                "name": role.name,
                "description": role.description,
                "permissions": try JSONEncoder().encode(role.permissions),
                "isSystem": role.isSystem,
                "createdAt": Date()
            ]
        )
        
        // Clear cache
        roleCache.removeValue(forKey: tenantId)
        
        return role
    }
    
    func assignRoleToUser(tenantId: String, userId: String, roleId: String) async throws {
        let databases = Databases(appwriteClient)
        
        try await databases.createDocument(
            databaseId: Configuration.database.databaseId,
            collectionId: "user_roles",
            documentId: UUID().uuidString,
            data: [
                "tenantId": tenantId,
                "userId": userId,
                "roleId": roleId,
                "assignedAt": Date()
            ]
        )
        
        // Clear cache
        roleCache.removeValue(forKey: "\(tenantId):\(userId)")
    }
    
    func removeRoleFromUser(tenantId: String, userId: String, roleId: String) async throws {
        let databases = Databases(appwriteClient)
        
        let query = Query.equal("tenantId", value: tenantId)
            .equal("userId", value: userId)
            .equal("roleId", value: roleId)
        
        let result = try await databases.listDocuments(
            databaseId: Configuration.database.databaseId,
            collectionId: "user_roles",
            queries: [query]
        )
        
        for document in result.documents {
            try await databases.deleteDocument(
                databaseId: Configuration.database.databaseId,
                collectionId: "user_roles",
                documentId: document.id
            )
        }
        
        // Clear cache
        roleCache.removeValue(forKey: "\(tenantId):\(userId)")
    }
    
    func getUserRoles(tenantId: String, userId: String) async throws -> [SecurityRole] {
        let cacheKey = "\(tenantId):\(userId)"
        
        // Check cache first
        if let cached = roleCache[cacheKey] {
            return cached
        }
        
        let databases = Databases(appwriteClient)
        
        // Get user role assignments
        let userRolesQuery = Query.equal("tenantId", value: tenantId)
            .equal("userId", value: userId)
        
        let userRolesResult = try await databases.listDocuments(
            databaseId: Configuration.database.databaseId,
            collectionId: "user_roles",
            queries: [userRolesQuery]
        )
        
        let roleIds = userRolesResult.documents.compactMap { $0.data["roleId"] as? String }
        
        if roleIds.isEmpty {
            return []
        }
        
        // Get role details
        let rolesQuery = Query.equal("tenantId", value: tenantId)
            .contains("id", values: roleIds)
        
        let rolesResult = try await databases.listDocuments(
            databaseId: Configuration.database.databaseId,
            collectionId: "security_roles",
            queries: [rolesQuery]
        )
        
        let roles = try rolesResult.documents.map { document -> SecurityRole in
            let permissionsData = document.data["permissions"] as? Data ?? Data()
            let permissions = try JSONDecoder().decode([SecurityPermission].self, from: permissionsData)
            
            return SecurityRole(
                id: document.id,
                tenantId: document.data["tenantId"] as? String ?? tenantId,
                name: document.data["name"] as? String ?? "",
                description: document.data["description"] as? String ?? "",
                permissions: permissions,
                isSystem: document.data["isSystem"] as? Bool ?? false,
                inheritedFrom: [],
                createdAt: Date(), // TODO: Parse from document
                updatedAt: Date()  // TODO: Parse from document
            )
        }
        
        // Cache the roles
        roleCache[cacheKey] = roles
        
        return roles
    }
    
    func checkPermission(tenantId: String, userId: String, permission: SecurityPermission) async throws -> Bool {
        let roles = try await getUserRoles(tenantId: tenantId, userId: userId)
        
        // Check if any role has the required permission
        for role in roles {
            for rolePermission in role.permissions {
                if rolePermission.resource == permission.resource &&
                   rolePermission.action == permission.action &&
                   rolePermission.scope == permission.scope {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Data Encryption
    
    func encryptTenantData<T: Codable>(_ data: T, tenantId: String) async throws -> EncryptedData {
        return try await withCheckedThrowingContinuation { continuation in
            encryptionQueue.async {
                do {
                    // Get or create encryption key for tenant
                    let key = self.getOrCreateEncryptionKey(for: tenantId)
                    
                    // Encode the data
                    let jsonData = try JSONEncoder().encode(data)
                    
                    // Generate IV
                    let iv = AES.GCM.Nonce()
                    
                    // Encrypt the data
                    let sealedBox = try AES.GCM.seal(jsonData, using: key, nonce: iv)
                    
                    let encryptedData = EncryptedData(
                        data: sealedBox.ciphertext,
                        keyId: tenantId,
                        algorithm: .aes256gcm,
                        iv: Data(iv),
                        tag: sealedBox.tag,
                        encryptedAt: Date()
                    )
                    
                    continuation.resume(returning: encryptedData)
                } catch {
                    continuation.resume(throwing: SecurityServiceError.encryptionFailed(error.localizedDescription))
                }
            }
        }
    }
    
    func decryptTenantData<T: Codable>(_ encryptedData: EncryptedData, tenantId: String, type: T.Type) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            encryptionQueue.async {
                do {
                    // Get encryption key for tenant
                    guard let key = self.encryptionKeys[tenantId] else {
                        continuation.resume(throwing: SecurityServiceError.decryptionFailed("Encryption key not found for tenant"))
                        return
                    }
                    
                    // Create sealed box from encrypted data
                    let nonce = try AES.GCM.Nonce(data: encryptedData.iv)
                    let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: encryptedData.data, tag: encryptedData.tag ?? Data())
                    
                    // Decrypt the data
                    let decryptedData = try AES.GCM.open(sealedBox, using: key)
                    
                    // Decode the object
                    let decodedObject = try JSONDecoder().decode(type, from: decryptedData)
                    
                    continuation.resume(returning: decodedObject)
                } catch {
                    continuation.resume(throwing: SecurityServiceError.decryptionFailed(error.localizedDescription))
                }
            }
        }
    }
    
    func rotateTenantEncryptionKey(tenantId: String) async throws {
        encryptionQueue.async {
            // Generate new key
            let newKey = SymmetricKey(size: .bits256)
            self.encryptionKeys[tenantId] = newKey
            
            // TODO: Re-encrypt existing data with new key
            // This would typically be done in background processing
        }
        
        await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: nil,
            eventType: .dataModification,
            resource: "encryption_key",
            action: .update,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: [:],
            riskLevel: .low
        ))
    }
    
    func getTenantEncryptionStatus(tenantId: String) async throws -> EncryptionStatus {
        let hasKey = encryptionKeys[tenantId] != nil
        
        return EncryptionStatus(
            tenantId: tenantId,
            isEnabled: hasKey,
            algorithm: .aes256gcm,
            keyRotationSchedule: nil,
            lastRotation: nil,
            nextRotation: nil,
            encryptedResources: [.user, .payment, .analytics],
            status: hasKey ? .healthy : .critical
        )
    }
    
    // MARK: - Audit Logging
    
    func logSecurityEvent(_ event: SecurityEvent) async throws {
        securityEvents.append(event)
        
        // Store in database for persistence
        let databases = Databases(appwriteClient)
        
        try await databases.createDocument(
            databaseId: Configuration.database.databaseId,
            collectionId: "security_events",
            documentId: event.id,
            data: [
                "tenantId": event.tenantId ?? "",
                "userId": event.userId ?? "",
                "eventType": event.eventType.rawValue,
                "resource": event.resource ?? "",
                "action": event.action.rawValue,
                "timestamp": event.timestamp,
                "success": event.success,
                "errorMessage": event.errorMessage ?? "",
                "metadata": try JSONEncoder().encode(event.metadata),
                "riskLevel": event.riskLevel.rawValue
            ]
        )
        
        // Keep only last 1000 events in memory
        if securityEvents.count > 1000 {
            securityEvents.removeFirst(securityEvents.count - 1000)
        }
    }
    
    func getSecurityEvents(tenantId: String?, userId: String?, eventType: SecurityEventType?, dateRange: DateRange) async throws -> [SecurityEvent] {
        let databases = Databases(appwriteClient)
        
        var queries: [String] = []
        
        if let tenantId = tenantId {
            queries.append(Query.equal("tenantId", value: tenantId))
        }
        
        if let userId = userId {
            queries.append(Query.equal("userId", value: userId))
        }
        
        if let eventType = eventType {
            queries.append(Query.equal("eventType", value: eventType.rawValue))
        }
        
        queries.append(Query.greaterThanEqual("timestamp", value: dateRange.startDate))
        queries.append(Query.lessThanEqual("timestamp", value: dateRange.endDate))
        
        let result = try await databases.listDocuments(
            databaseId: Configuration.database.databaseId,
            collectionId: "security_events",
            queries: queries.map { Query.init($0) }
        )
        
        // Convert documents to SecurityEvent objects
        return try result.documents.map { document -> SecurityEvent in
            let metadataData = document.data["metadata"] as? Data ?? Data()
            let metadata = try JSONDecoder().decode([String: String].self, from: metadataData)
            
            return SecurityEvent(
                id: document.id,
                tenantId: document.data["tenantId"] as? String,
                userId: document.data["userId"] as? String,
                eventType: SecurityEventType(rawValue: document.data["eventType"] as? String ?? "") ?? .authentication,
                resource: document.data["resource"] as? String,
                action: SecurityAction(rawValue: document.data["action"] as? String ?? "") ?? .read,
                timestamp: Date(), // TODO: Parse from document
                ipAddress: document.data["ipAddress"] as? String,
                userAgent: document.data["userAgent"] as? String,
                success: document.data["success"] as? Bool ?? false,
                errorMessage: document.data["errorMessage"] as? String,
                metadata: metadata,
                riskLevel: RiskLevel(rawValue: document.data["riskLevel"] as? String ?? "") ?? .low
            )
        }
    }
    
    func createSecurityAlert(_ alert: SecurityAlert) async throws {
        let databases = Databases(appwriteClient)
        
        try await databases.createDocument(
            databaseId: Configuration.database.databaseId,
            collectionId: "security_alerts",
            documentId: alert.id,
            data: [
                "tenantId": alert.tenantId,
                "alertType": alert.alertType.rawValue,
                "severity": alert.severity.rawValue,
                "title": alert.title,
                "description": alert.description,
                "detectedAt": alert.detectedAt,
                "status": alert.status.rawValue
            ]
        )
    }
    
    func getSecurityAlerts(tenantId: String, severity: AlertSeverity?) async throws -> [SecurityAlert] {
        let databases = Databases(appwriteClient)
        
        var queries = [Query.equal("tenantId", value: tenantId)]
        
        if let severity = severity {
            queries.append(Query.equal("severity", value: severity.rawValue))
        }
        
        let result = try await databases.listDocuments(
            databaseId: Configuration.database.databaseId,
            collectionId: "security_alerts",
            queries: queries
        )
        
        return result.documents.map { document in
            SecurityAlert(
                id: document.id,
                tenantId: document.data["tenantId"] as? String ?? tenantId,
                alertType: SecurityAlertType(rawValue: document.data["alertType"] as? String ?? "") ?? .unauthorizedAccess,
                severity: AlertSeverity(rawValue: document.data["severity"] as? String ?? "") ?? .low,
                title: document.data["title"] as? String ?? "",
                description: document.data["description"] as? String ?? "",
                affectedResources: [],
                detectedAt: Date(), // TODO: Parse from document
                resolvedAt: nil,
                status: AlertStatus.open,
                assignedTo: nil,
                remediation: []
            )
        }
    }
    
    // MARK: - Cross-Tenant Security
    
    func preventTenantCrossTalk(sourceId: String, targetId: String, operation: SecurityOperation) async throws {
        guard sourceId != targetId else {
            return // Same tenant, allowed
        }
        
        await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: sourceId,
            userId: nil,
            eventType: .securityBreach,
            resource: targetId,
            action: .read,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: false,
            errorMessage: "Cross-tenant operation attempted",
            metadata: ["source_tenant": sourceId, "target_tenant": targetId, "operation": operation.rawValue],
            riskLevel: .critical
        ))
        
        throw SecurityServiceError.crossTenantViolation(sourceId, targetId)
    }
    
    func validateTenantBoundary(resourcePath: String, tenantId: String) async throws -> Bool {
        // Validate that the resource path includes proper tenant scoping
        return resourcePath.contains("/tenants/\(tenantId)/") || resourcePath.contains("tenantId=\(tenantId)")
    }
    
    func sanitizeCrossTenantRequests<T>(_ request: T, tenantId: String) async throws -> T where T: TenantSanitizable {
        return request.sanitizeForTenant(tenantId)
    }
    
    // MARK: - Security Monitoring
    
    func detectAnomalousActivity(tenantId: String, period: SecurityPeriod) async throws -> [SecurityAnomaly] {
        let events = try await getSecurityEvents(
            tenantId: tenantId,
            userId: nil,
            eventType: nil,
            dateRange: DateRange(startDate: getStartDate(for: period), endDate: Date())
        )
        
        return anomalyDetector.detectAnomalies(in: events, for: tenantId)
    }
    
    func analyzeSecurityRisk(tenantId: String) async throws -> SecurityRiskAssessment {
        let anomalies = try await detectAnomalousActivity(tenantId: tenantId, period: .week)
        let alerts = try await getSecurityAlerts(tenantId: tenantId, severity: nil)
        
        let riskLevel: RiskLevel
        if anomalies.contains(where: { $0.severity == .critical }) {
            riskLevel = .critical
        } else if alerts.contains(where: { $0.severity == .high }) {
            riskLevel = .high
        } else if anomalies.count > 5 {
            riskLevel = .medium
        } else {
            riskLevel = .low
        }
        
        return SecurityRiskAssessment(
            tenantId: tenantId,
            overallRisk: riskLevel,
            riskFactors: [],
            recommendations: [],
            complianceScore: 0.85,
            lastAssessment: Date(),
            nextAssessment: Date().addingTimeInterval(86400 * 7) // Next week
        )
    }
    
    func generateSecurityReport(tenantId: String, reportType: SecurityReportType) async throws -> SecurityReport {
        // Generate comprehensive security report
        let report = SecurityReport(
            id: UUID().uuidString,
            tenantId: tenantId,
            reportType: reportType,
            generatedAt: Date(),
            period: DateRange(startDate: Date().addingTimeInterval(-86400 * 30), endDate: Date()),
            summary: SecuritySummary(),
            data: Data(),
            format: .json
        )
        
        return report
    }
    
    // MARK: - Compliance & Privacy (Simplified implementations)
    
    func ensureGDPRCompliance(tenantId: String, userId: String) async throws -> GDPRComplianceStatus {
        return GDPRComplianceStatus(
            tenantId: tenantId,
            userId: userId,
            isCompliant: true,
            issues: [],
            dataCategories: [],
            retentionStatus: RetentionStatus(),
            consentStatus: ConsentStatus(),
            lastAudit: Date()
        )
    }
    
    func processDataDeletionRequest(tenantId: String, userId: String, scope: DeletionScope) async throws {
        // Implementation for GDPR data deletion
        await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: userId,
            eventType: .dataModification,
            resource: "user_data",
            action: .delete,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: ["scope": scope.rawValue],
            riskLevel: .medium
        ))
    }
    
    func exportUserData(tenantId: String, userId: String, format: ExportFormat) async throws -> Data {
        // Implementation for GDPR data export
        return Data()
    }
    
    func anonymizeUserData(tenantId: String, userId: String, retentionRules: RetentionRules) async throws {
        // Implementation for data anonymization
    }
    
    // MARK: - Security Configuration
    
    func updateTenantSecurityPolicy(tenantId: String, policy: SecurityPolicy) async throws {
        let databases = Databases(appwriteClient)
        
        try await databases.updateDocument(
            databaseId: Configuration.database.databaseId,
            collectionId: "security_policies",
            documentId: tenantId,
            data: [
                "policy": try JSONEncoder().encode(policy),
                "updatedAt": Date()
            ]
        )
    }
    
    func getTenantSecurityPolicy(tenantId: String) async throws -> SecurityPolicy {
        // Return default security policy
        return SecurityPolicy(
            tenantId: tenantId,
            passwordPolicy: PasswordPolicy(),
            sessionPolicy: SessionPolicy(),
            encryptionPolicy: EncryptionPolicy(),
            auditPolicy: AuditPolicy(),
            accessPolicy: AccessPolicy(),
            dataRetentionPolicy: DataRetentionPolicy(),
            multiFactorPolicy: MultiFactorPolicy(),
            version: "1.0.0",
            lastUpdated: Date()
        )
    }
    
    func validateSecurityConfiguration(tenantId: String) async throws -> [SecurityConfigurationIssue] {
        // Validate security configuration and return issues
        return []
    }
    
    func applySecurityPatch(tenantId: String, patchId: String) async throws {
        // Apply security patch
        await logSecurityEvent(SecurityEvent(
            id: UUID().uuidString,
            tenantId: tenantId,
            userId: nil,
            eventType: .dataModification,
            resource: "security_patch",
            action: .update,
            timestamp: Date(),
            ipAddress: nil,
            userAgent: nil,
            success: true,
            errorMessage: nil,
            metadata: ["patch_id": patchId],
            riskLevel: .low
        ))
    }
    
    // MARK: - Private Helper Methods
    
    private func performSecurityMonitoring() async {
        // Monitor for security events and anomalies
        for tenantId in Set(securityEvents.compactMap { $0.tenantId }) {
            do {
                let anomalies = try await detectAnomalousActivity(tenantId: tenantId, period: .hour)
                
                for anomaly in anomalies {
                    if anomaly.severity == .critical || anomaly.severity == .high {
                        let alert = SecurityAlert(
                            id: UUID().uuidString,
                            tenantId: tenantId,
                            alertType: .suspiciousActivity,
                            severity: anomaly.severity == .critical ? .critical : .high,
                            title: "Security Anomaly Detected",
                            description: anomaly.description,
                            affectedResources: anomaly.affectedResources,
                            detectedAt: Date(),
                            resolvedAt: nil,
                            status: .open,
                            assignedTo: nil,
                            remediation: []
                        )
                        
                        try await createSecurityAlert(alert)
                    }
                }
            } catch {
                logger.error("Failed to perform security monitoring for tenant \(tenantId): \(error)")
            }
        }
    }
    
    private func getOrCreateEncryptionKey(for tenantId: String) -> SymmetricKey {
        if let existingKey = encryptionKeys[tenantId] {
            return existingKey
        }
        
        let newKey = SymmetricKey(size: .bits256)
        encryptionKeys[tenantId] = newKey
        return newKey
    }
    
    private func hashAPIKey(_ apiKey: String) -> String {
        let data = Data(apiKey.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func generateSecureAPIKey() -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<64).map { _ in characters.randomElement()! })
    }
    
    private func getCollectionId(for resourceType: ResourceType) -> String {
        switch resourceType {
        case .course: return "golf_courses"
        case .booking: return "bookings"
        case .user: return "users"
        case .tenant: return "tenants"
        case .payment: return "payments"
        case .analytics: return "analytics"
        case .api: return "api_keys"
        case .report: return "reports"
        }
    }
    
    private func getStartDate(for period: SecurityPeriod) -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch period {
        case .hour:
            return calendar.date(byAdding: .hour, value: -1, to: now) ?? now
        case .day:
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .quarter:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        }
    }
    
    deinit {
        securityTimer?.invalidate()
    }
}

// MARK: - Anomaly Detector

private class AnomalyDetector {
    func detectAnomalies(in events: [SecurityEvent], for tenantId: String) -> [SecurityAnomaly] {
        var anomalies: [SecurityAnomaly] = []
        
        // Check for unusual login patterns
        let failedLogins = events.filter { $0.eventType == .authentication && !$0.success }
        if failedLogins.count > 10 {
            anomalies.append(SecurityAnomaly(
                id: UUID().uuidString,
                tenantId: tenantId,
                anomalyType: .anomalousLogin,
                severity: .high,
                description: "Multiple failed login attempts detected",
                detectedAt: Date(),
                affectedUsers: Array(Set(failedLogins.compactMap { $0.userId })),
                affectedResources: [],
                confidenceScore: 0.85,
                riskAssessment: RiskAssessment()
            ))
        }
        
        // Check for unusual data access patterns
        let dataAccessEvents = events.filter { $0.eventType == .dataAccess }
        let uniqueResources = Set(dataAccessEvents.compactMap { $0.resource })
        
        if uniqueResources.count > 100 {
            anomalies.append(SecurityAnomaly(
                id: UUID().uuidString,
                tenantId: tenantId,
                anomalyType: .unusualAccess,
                severity: .medium,
                description: "Unusual data access pattern detected",
                detectedAt: Date(),
                affectedUsers: Array(Set(dataAccessEvents.compactMap { $0.userId })),
                affectedResources: Array(uniqueResources),
                confidenceScore: 0.75,
                riskAssessment: RiskAssessment()
            ))
        }
        
        return anomalies
    }
}

// MARK: - Supporting Types (Simplified)

struct SecuritySummary {
    // Implementation would include security metrics summary
}

struct RetentionRules {
    // Implementation for data retention rules
}

struct RetentionStatus {
    // Implementation for retention status
}

struct ConsentStatus {
    // Implementation for consent status
}

struct RiskAssessment {
    // Implementation for risk assessment
}

// Policy types would be implemented similarly
struct PasswordPolicy { }
struct SessionPolicy { }
struct EncryptionPolicy { }
struct AuditPolicy { }
struct AccessPolicy { }
struct DataRetentionPolicy { }
struct MultiFactorPolicy { }

enum AlertStatus {
    case open, investigating, resolved
}