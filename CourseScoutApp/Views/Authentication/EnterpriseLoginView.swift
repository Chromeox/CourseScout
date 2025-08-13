import SwiftUI
import Combine

// MARK: - Enterprise Login View

struct EnterpriseLoginView: View {
    @StateObject private var viewModel: EnterpriseLoginViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol,
        securityService: SecurityServiceProtocol
    ) {
        self._viewModel = StateObject(wrappedValue: EnterpriseLoginViewModel(
            authenticationService: authenticationService,
            tenantConfigurationService: tenantConfigurationService,
            securityService: securityService
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // Enterprise header
                        enterpriseHeaderSection
                        
                        // Main content
                        mainContentSection
                            .padding(.horizontal, 24)
                        
                        Spacer(minLength: 40)
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .overlay(loadingOverlay)
        .sheet(isPresented: $viewModel.showProviderSelection) {
            providerSelectionSheet
        }
        .sheet(isPresented: $viewModel.showComplianceInfo) {
            complianceInfoSheet
        }
        .sheet(isPresented: $viewModel.showDeviceTrustInfo) {
            deviceTrustInfoSheet
        }
        .alert("Authentication Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
            
            if viewModel.canRetryAuthentication {
                Button("Retry") { viewModel.retryAuthentication() }
            }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Compliance Warning", isPresented: $viewModel.showComplianceWarning) {
            Button("Continue") { viewModel.acknowledgeComplianceWarning() }
            Button("Learn More") { viewModel.showComplianceInfo = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(viewModel.complianceWarningMessage)
        }
        .alert("Device Trust", isPresented: $viewModel.showDeviceTrustWarning) {
            Button("Continue Anyway") { viewModel.proceedWithUntrustedDevice() }
            Button("Learn More") { viewModel.showDeviceTrustInfo = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This device may not meet security requirements. Proceed with caution.")
        }
    }
    
    // MARK: - Enterprise Header Section
    
    private var enterpriseHeaderSection: some View {
        VStack(spacing: 24) {
            // Tenant branding
            if let tenant = viewModel.discoveredTenant {
                tenantBrandingHeader(tenant)
            } else {
                defaultEnterpriseHeader
            }
            
            // Security indicators
            securityIndicators
        }
        .padding(.top, 40)
        .padding(.bottom, 30)
        .background(enterpriseHeaderBackground)
    }
    
    private func tenantBrandingHeader(_ tenant: TenantInfo) -> some View {
        VStack(spacing: 16) {
            // Tenant logo
            if let logoURL = tenant.logoURL {
                AsyncImage(url: logoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "building.2")
                                .foregroundColor(.gray)
                        )
                }
                .frame(height: 80)
            }
            
            VStack(spacing: 8) {
                Text(tenant.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                if let domain = tenant.domain {
                    Text(domain)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Compliance badges
                if !tenant.complianceStandards.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(tenant.complianceStandards.prefix(3), id: \.self) { standard in
                            ComplianceBadge(standard: standard)
                        }
                    }
                }
            }
        }
    }
    
    private var defaultEnterpriseHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Enterprise Sign In")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
    }
    
    private var securityIndicators: some View {
        HStack(spacing: 16) {
            SecurityIndicator(
                icon: "shield.checkerboard",
                title: "Secure",
                isActive: viewModel.isSecureConnection
            )
            
            SecurityIndicator(
                icon: "checkmark.shield",
                title: "Verified",
                isActive: viewModel.isTenantVerified
            )
            
            SecurityIndicator(
                icon: "lock.shield",
                title: "Encrypted",
                isActive: true
            )
        }
    }
    
    private var enterpriseHeaderBackground: some View {
        LinearGradient(
            colors: [
                viewModel.tenantTheme?.backgroundColor ?? Color(.systemGray6),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(.all, edges: .top)
    }
    
    // MARK: - Main Content Section
    
    private var mainContentSection: some View {
        VStack(spacing: 24) {
            // Organization discovery
            organizationDiscoverySection
            
            // Authentication methods
            if viewModel.showAuthenticationMethods {
                authenticationMethodsSection
            }
            
            // Device trust status
            if viewModel.showDeviceTrustStatus {
                deviceTrustStatusSection
            }
            
            // Compliance information
            if viewModel.showComplianceRequirements {
                complianceRequirementsSection
            }
            
            // Footer links
            footerLinksSection
        }
    }
    
    // MARK: - Organization Discovery Section
    
    private var organizationDiscoverySection: some View {
        VStack(spacing: 16) {
            Text("Organization")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 8) {
                CustomTextField(
                    title: "Organization Domain",
                    text: $viewModel.organizationDomain,
                    placeholder: "company.com",
                    keyboardType: .URL,
                    autocapitalization: .none,
                    icon: "building.2"
                )
                
                if viewModel.isDomainDiscovering {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Discovering organization...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 8)
                }
                
                if let tenant = viewModel.discoveredTenant {
                    discoveredTenantInfo(tenant)
                } else if let error = viewModel.discoveryError {
                    discoveryErrorInfo(error)
                }
            }
        }
    }
    
    private func discoveredTenantInfo(_ tenant: TenantInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Organization found")
                    .font(.caption)
                    .foregroundColor(.green)
                    .fontWeight(.medium)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tenant.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let description = tenant.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Available SSO providers
                if !tenant.ssoProviders.isEmpty {
                    Text("Available sign-in methods: \(tenant.ssoProviders.map { $0.displayName }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func discoveryErrorInfo(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Organization not found")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
            }
            
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Authentication Methods Section
    
    private var authenticationMethodsSection: some View {
        VStack(spacing: 16) {
            Text("Sign In Method")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if viewModel.availableSSOProviders.count == 1,
               let provider = viewModel.availableSSOProviders.first {
                // Single SSO provider
                singleSSOProviderView(provider)
            } else if viewModel.availableSSOProviders.count > 1 {
                // Multiple SSO providers
                multipleSSOProvidersView
            } else {
                // No SSO providers available
                noSSOProvidersView
            }
        }
    }
    
    private func singleSSOProviderView(_ provider: SSOProvider) -> some View {
        Button(action: { viewModel.signInWithSSO(provider) }) {
            HStack(spacing: 12) {
                Image(systemName: provider.iconName)
                    .foregroundColor(provider.brandColor)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue with \(provider.displayName)")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Secure single sign-on")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if viewModel.isAuthenticating && viewModel.selectedProvider?.id == provider.id {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .disabled(viewModel.isAuthenticating)
    }
    
    private var multipleSSOProvidersView: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.availableSSOProviders, id: \.id) { provider in
                Button(action: { viewModel.signInWithSSO(provider) }) {
                    HStack(spacing: 12) {
                        Image(systemName: provider.iconName)
                            .foregroundColor(provider.brandColor)
                            .font(.title2)
                            .frame(width: 24)
                        
                        Text("Continue with \(provider.displayName)")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if viewModel.isAuthenticating && viewModel.selectedProvider?.id == provider.id {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }
                .disabled(viewModel.isAuthenticating)
            }
        }
    }
    
    private var noSSOProvidersView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.orange)
            
            Text("No authentication methods available")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Contact your IT administrator to set up single sign-on for your organization.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Contact Support") {
                viewModel.contactSupport()
            }
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Device Trust Status Section
    
    private var deviceTrustStatusSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Device Security")
                    .font(.headline)
                
                Spacer()
                
                Button("Details") {
                    viewModel.showDeviceTrustInfo = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            DeviceTrustStatusView(
                trustLevel: viewModel.deviceTrustLevel,
                securityChecks: viewModel.deviceSecurityChecks
            )
        }
    }
    
    // MARK: - Compliance Requirements Section
    
    private var complianceRequirementsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Compliance")
                    .font(.headline)
                
                Spacer()
                
                Button("Learn More") {
                    viewModel.showComplianceInfo = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if let tenant = viewModel.discoveredTenant {
                ComplianceRequirementsView(
                    standards: tenant.complianceStandards,
                    requirements: tenant.complianceRequirements
                )
            }
        }
    }
    
    // MARK: - Footer Links Section
    
    private var footerLinksSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                Button("Privacy Policy") {
                    viewModel.showPrivacyPolicy = true
                }
                
                Button("Terms of Service") {
                    viewModel.showTermsOfService = true
                }
                
                Button("Support") {
                    viewModel.contactSupport()
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            Button("Switch to Personal Account") {
                dismiss()
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding(.top, 24)
    }
    
    // MARK: - Overlays and Sheets
    
    private var loadingOverlay: some View {
        Group {
            if viewModel.isAuthenticating {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            
                            Text("Authenticating with \(viewModel.selectedProvider?.displayName ?? "SSO")...")
                                .foregroundColor(.white)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                        }
                        .padding(32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                        )
                    )
            }
        }
    }
    
    private var providerSelectionSheet: some View {
        NavigationView {
            List(viewModel.availableSSOProviders, id: \.id) { provider in
                Button(action: {
                    viewModel.signInWithSSO(provider)
                    viewModel.showProviderSelection = false
                }) {
                    HStack(spacing: 16) {
                        Image(systemName: provider.iconName)
                            .foregroundColor(provider.brandColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(provider.description ?? "Single sign-on")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Choose Sign-In Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        viewModel.showProviderSelection = false
                    }
                }
            }
        }
    }
    
    private var complianceInfoSheet: some View {
        NavigationView {
            ComplianceInfoView(
                tenant: viewModel.discoveredTenant,
                complianceManager: viewModel.complianceManager
            )
            .navigationTitle("Compliance Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.showComplianceInfo = false
                    }
                }
            }
        }
    }
    
    private var deviceTrustInfoSheet: some View {
        NavigationView {
            DeviceTrustInfoView(
                trustLevel: viewModel.deviceTrustLevel,
                securityChecks: viewModel.deviceSecurityChecks,
                recommendations: viewModel.securityRecommendations
            )
            .navigationTitle("Device Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.showDeviceTrustInfo = false
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ComplianceBadge: View {
    let standard: String
    
    var body: some View {
        Text(standard)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.2))
            .foregroundColor(.blue)
            .clipShape(Capsule())
    }
}

struct SecurityIndicator: View {
    let icon: String
    let title: String
    let isActive: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(isActive ? .green : .gray)
                .font(.caption)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(isActive ? .green : .gray)
        }
    }
}

struct DeviceTrustStatusView: View {
    let trustLevel: DeviceTrustLevel
    let securityChecks: [SecurityCheck]
    
    var body: some View {
        VStack(spacing: 12) {
            // Trust level indicator
            HStack {
                Circle()
                    .fill(trustLevel.color)
                    .frame(width: 12, height: 12)
                
                Text(trustLevel.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(trustLevel.color)
                
                Spacer()
                
                Text(trustLevel.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Security checks
            VStack(spacing: 8) {
                ForEach(securityChecks, id: \.id) { check in
                    HStack {
                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(check.passed ? .green : .red)
                            .font(.caption)
                        
                        Text(check.name)
                            .font(.caption)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if !check.passed {
                            Text("Failed")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct ComplianceRequirementsView: View {
    let standards: [String]
    let requirements: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !standards.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Standards")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    HStack {
                        ForEach(standards, id: \.self) { standard in
                            ComplianceBadge(standard: standard)
                        }
                    }
                }
            }
            
            if !requirements.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Requirements")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(requirements, id: \.self) { requirement in
                            Text("• \(requirement)")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Extensions

extension DeviceTrustLevel {
    var color: Color {
        switch self {
        case .trusted: return .green
        case .warning: return .orange
        case .untrusted: return .red
        case .unknown: return .gray
        }
    }
    
    var description: String {
        switch self {
        case .trusted: return "Trusted Device"
        case .warning: return "Device Warning"
        case .untrusted: return "Untrusted Device"
        case .unknown: return "Unknown Status"
        }
    }
    
    var statusText: String {
        switch self {
        case .trusted: return "All security checks passed"
        case .warning: return "Some security concerns detected"
        case .untrusted: return "Security requirements not met"
        case .unknown: return "Unable to verify device security"
        }
    }
}

// MARK: - Preview

struct EnterpriseLoginView_Previews: PreviewProvider {
    static var previews: some View {
        EnterpriseLoginView(
            authenticationService: MockAuthenticationService(),
            tenantConfigurationService: MockTenantConfigurationService(),
            securityService: MockSecurityService()
        )
    }
}