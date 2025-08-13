import SwiftUI
import Combine

// MARK: - Sign Up View

struct SignUpView: View {
    @StateObject private var viewModel: SignUpViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol,
        onboardingService: OnboardingServiceProtocol
    ) {
        self._viewModel = StateObject(wrappedValue: SignUpViewModel(
            authenticationService: authenticationService,
            tenantConfigurationService: tenantConfigurationService,
            onboardingService: onboardingService
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // Header with branding
                        headerSection
                        
                        // Sign up form
                        signUpFormSection
                            .padding(.horizontal, 24)
                        
                        Spacer(minLength: 40)
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .overlay(loadingOverlay)
        .sheet(isPresented: $viewModel.showTermsOfService) {
            termsOfServiceSheet
        }
        .sheet(isPresented: $viewModel.showPrivacyPolicy) {
            privacyPolicySheet
        }
        .sheet(isPresented: $viewModel.showConsentDetails) {
            consentDetailsSheet
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Success", isPresented: $viewModel.showSuccess) {
            Button("OK") { 
                viewModel.dismissSuccess()
                dismiss()
            }
        } message: {
            Text(viewModel.successMessage)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 24) {
            // App logo or tenant branding
            if let branding = viewModel.brandingConfiguration {
                brandedHeader(branding)
            } else {
                defaultHeader
            }
            
            // Welcome message
            welcomeMessage
        }
        .padding(.top, 40)
        .padding(.bottom, 30)
        .background(headerBackground)
    }
    
    private func brandedHeader(_ branding: BrandingConfiguration) -> some View {
        VStack(spacing: 16) {
            if let logoURL = branding.logoURL {
                AsyncImage(url: logoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
                .frame(height: 60)
            }
            
            Text(branding.appName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Color(hex: branding.primaryColor) ?? .primary)
        }
    }
    
    private var defaultHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: "golf.club.ball")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("GolfFinder")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
    }
    
    private var welcomeMessage: some View {
        VStack(spacing: 8) {
            Text("Create Account")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("Join the golf community")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    private var headerBackground: some View {
        LinearGradient(
            colors: [
                viewModel.tenantTheme?.backgroundColor ?? Color(.systemBackground),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(.all, edges: .top)
    }
    
    // MARK: - Sign Up Form Section
    
    private var signUpFormSection: some View {
        VStack(spacing: 24) {
            // Personal information
            personalInfoSection
            
            // Account credentials
            credentialsSection
            
            // Enterprise fields (if applicable)
            if viewModel.showEnterpriseFields {
                enterpriseSection
            }
            
            // Custom fields (tenant-specific)
            if !viewModel.customFields.isEmpty {
                customFieldsSection
            }
            
            // Terms and consent
            termsAndConsentSection
            
            // Action buttons
            actionButtons
            
            // Alternative sign-up options
            alternativeSignUpOptions
            
            // Footer links
            footerLinks
        }
    }
    
    private var personalInfoSection: some View {
        VStack(spacing: 16) {
            Text("Personal Information")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                CustomTextField(
                    title: "First Name",
                    text: $viewModel.firstName,
                    placeholder: "Enter first name",
                    icon: "person"
                )
                
                CustomTextField(
                    title: "Last Name",
                    text: $viewModel.lastName,
                    placeholder: "Enter last name",
                    icon: "person"
                )
            }
            
            CustomTextField(
                title: "Email",
                text: $viewModel.email,
                placeholder: "Enter your email address",
                keyboardType: .emailAddress,
                autocapitalization: .none,
                icon: "envelope"
            )
            .overlay(
                emailValidationIndicator,
                alignment: .trailing
            )
        }
    }
    
    private var emailValidationIndicator: some View {
        Group {
            if !viewModel.email.isEmpty {
                Image(systemName: viewModel.isEmailValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(viewModel.isEmailValid ? .green : .red)
                    .padding(.trailing, 16)
            }
        }
    }
    
    private var credentialsSection: some View {
        VStack(spacing: 16) {
            Text("Account Security")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            CustomSecureField(
                title: "Password",
                text: $viewModel.password,
                placeholder: "Create a strong password",
                icon: "lock"
            )
            
            // Password strength indicator
            if !viewModel.password.isEmpty {
                passwordStrengthIndicator
            }
            
            CustomSecureField(
                title: "Confirm Password",
                text: $viewModel.confirmPassword,
                placeholder: "Confirm your password",
                icon: "lock"
            )
            
            if !viewModel.confirmPassword.isEmpty && !viewModel.passwordsMatch {
                Text("Passwords do not match")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var passwordStrengthIndicator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Password Strength:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(viewModel.passwordStrength.description)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(viewModel.passwordStrength.color)
            }
            
            ProgressView(value: viewModel.passwordStrengthValue, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: viewModel.passwordStrength.color))
                .scaleEffect(x: 1, y: 0.5)
        }
    }
    
    private var enterpriseSection: some View {
        VStack(spacing: 16) {
            Text("Organization Information")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            CustomTextField(
                title: "Organization",
                text: $viewModel.organizationName,
                placeholder: "Your organization name",
                icon: "building.2"
            )
            
            if viewModel.showDepartmentField {
                CustomTextField(
                    title: "Department",
                    text: $viewModel.department,
                    placeholder: "Your department",
                    icon: "briefcase"
                )
            }
            
            if viewModel.showEmployeeIdField {
                CustomTextField(
                    title: "Employee ID",
                    text: $viewModel.employeeId,
                    placeholder: "Your employee ID",
                    icon: "number"
                )
            }
        }
    }
    
    private var customFieldsSection: some View {
        VStack(spacing: 16) {
            Text("Additional Information")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(viewModel.customFields, id: \.id) { field in
                customFieldView(field)
            }
        }
    }
    
    private func customFieldView(_ field: CustomSignUpField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.label)
                .font(.headline)
                .foregroundColor(.primary)
            
            switch field.type {
            case .text:
                TextField(field.placeholder ?? "", text: Binding(
                    get: { viewModel.customFieldValues[field.id] as? String ?? "" },
                    set: { viewModel.customFieldValues[field.id] = $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
            case .email:
                TextField(field.placeholder ?? "", text: Binding(
                    get: { viewModel.customFieldValues[field.id] as? String ?? "" },
                    set: { viewModel.customFieldValues[field.id] = $0 }
                ))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
            case .phone:
                TextField(field.placeholder ?? "", text: Binding(
                    get: { viewModel.customFieldValues[field.id] as? String ?? "" },
                    set: { viewModel.customFieldValues[field.id] = $0 }
                ))
                .keyboardType(.phonePad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
            case .select:
                Menu {
                    ForEach(field.options ?? [], id: \.self) { option in
                        Button(option) {
                            viewModel.customFieldValues[field.id] = option
                        }
                    }
                } label: {
                    HStack {
                        Text(viewModel.customFieldValues[field.id] as? String ?? field.placeholder ?? "Select option")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }
                
            case .checkbox:
                Toggle(isOn: Binding(
                    get: { viewModel.customFieldValues[field.id] as? Bool ?? false },
                    set: { viewModel.customFieldValues[field.id] = $0 }
                )) {
                    Text(field.placeholder ?? "")
                        .font(.body)
                }
            }
            
            if field.isRequired && viewModel.customFieldValues[field.id] == nil {
                Text("This field is required")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private var termsAndConsentSection: some View {
        VStack(spacing: 16) {
            ConsentCheckbox(
                isChecked: $viewModel.agreedToTerms,
                title: "I agree to the Terms of Service",
                action: { viewModel.showTermsOfService = true }
            )
            
            ConsentCheckbox(
                isChecked: $viewModel.agreedToPrivacy,
                title: "I agree to the Privacy Policy",
                action: { viewModel.showPrivacyPolicy = true }
            )
            
            if viewModel.requiresMarketingConsent {
                ConsentCheckbox(
                    isChecked: $viewModel.agreedToMarketing,
                    title: "I agree to receive marketing communications (optional)",
                    action: nil
                )
            }
            
            if viewModel.requiresDataProcessingConsent {
                ConsentCheckbox(
                    isChecked: $viewModel.agreedToDataProcessing,
                    title: "I consent to data processing as described in our Privacy Policy",
                    action: { viewModel.showConsentDetails = true }
                )
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary create account button
            Button(action: viewModel.createAccount) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    Text("Create Account")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(viewModel.tenantTheme?.primaryColor ?? Color.blue)
                )
            }
            .disabled(!viewModel.isFormValid || viewModel.isLoading)
            .opacity(viewModel.isFormValid ? 1.0 : 0.6)
            
            // Sign in button
            Button("Already have an account? Sign In") {
                dismiss()
            }
            .foregroundColor(viewModel.tenantTheme?.accentColor ?? .blue)
        }
    }
    
    private var alternativeSignUpOptions: some View {
        VStack(spacing: 16) {
            // Divider with "or" text
            HStack {
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 1)
                
                Text("or")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 1)
            }
            
            // OAuth provider buttons
            VStack(spacing: 12) {
                ForEach(viewModel.availableProviders, id: \.self) { provider in
                    OAuth2Button(
                        provider: provider,
                        action: { viewModel.signUpWithProvider(provider) },
                        isLoading: viewModel.isLoading && viewModel.selectedProvider == provider
                    )
                }
            }
        }
    }
    
    private var footerLinks: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button("Support") {
                    viewModel.showSupport = true
                }
                
                Button("Help") {
                    viewModel.showHelp = true
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.top, 24)
    }
    
    // MARK: - Sheets and Overlays
    
    private var loadingOverlay: some View {
        Group {
            if viewModel.isRegistering {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            
                            Text("Creating your account...")
                                .foregroundColor(.white)
                                .font(.headline)
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
    
    private var termsOfServiceSheet: some View {
        NavigationView {
            LegalDocumentView(
                title: "Terms of Service",
                content: viewModel.termsOfServiceContent
            )
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.showTermsOfService = false
                    }
                }
            }
        }
    }
    
    private var privacyPolicySheet: some View {
        NavigationView {
            LegalDocumentView(
                title: "Privacy Policy",
                content: viewModel.privacyPolicyContent
            )
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.showPrivacyPolicy = false
                    }
                }
            }
        }
    }
    
    private var consentDetailsSheet: some View {
        NavigationView {
            ConsentDetailsView(
                consentInfo: viewModel.dataProcessingConsent
            )
            .navigationTitle("Data Processing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.showConsentDetails = false
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ConsentCheckbox: View {
    @Binding var isChecked: Bool
    let title: String
    let action: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: {
                isChecked.toggle()
            }) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? .blue : .gray)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                if let action = action {
                    Button("Read details") {
                        action()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            
            Spacer()
        }
    }
}

struct LegalDocumentView: View {
    let title: String
    let content: String
    
    var body: some View {
        ScrollView {
            Text(content)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ConsentDetailsView: View {
    let consentInfo: DataProcessingConsent?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let consent = consentInfo {
                    Text("Purpose")
                        .font(.headline)
                    
                    Text(consent.purpose)
                        .font(.body)
                    
                    Text("Legal Basis")
                        .font(.headline)
                    
                    Text(consent.legalBasis)
                        .font(.body)
                    
                    if !consent.thirdParties.isEmpty {
                        Text("Third Parties")
                            .font(.headline)
                        
                        ForEach(consent.thirdParties, id: \.self) { party in
                            Text("• \(party)")
                                .font(.body)
                        }
                    }
                    
                    Text("Your Rights")
                        .font(.headline)
                    
                    Text(consent.userRights)
                        .font(.body)
                } else {
                    Text("No consent information available")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Extensions

extension PasswordStrength {
    var description: String {
        switch self {
        case .veryWeak: return "Very Weak"
        case .weak: return "Weak"
        case .medium: return "Medium"
        case .strong: return "Strong"
        case .veryStrong: return "Very Strong"
        }
    }
    
    var color: Color {
        switch self {
        case .veryWeak: return .red
        case .weak: return .orange
        case .medium: return .yellow
        case .strong: return .green
        case .veryStrong: return .blue
        }
    }
}

// MARK: - Preview

struct SignUpView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SignUpView(
                authenticationService: MockAuthenticationService(),
                tenantConfigurationService: MockTenantConfigurationService(),
                onboardingService: MockOnboardingService()
            )
            .preferredColorScheme(.light)
            
            SignUpView(
                authenticationService: MockAuthenticationService(),
                tenantConfigurationService: MockTenantConfigurationService(),
                onboardingService: MockOnboardingService()
            )
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Mock Services for Preview

class MockOnboardingService: OnboardingServiceProtocol {
    func getOnboardingSteps(for userType: UserType, tenantId: String?) async throws -> [OnboardingStep] {
        return []
    }
    
    func completeOnboardingStep(_ stepId: String, data: [String: Any]) async throws {
    }
    
    func getOnboardingProgress(userId: String) async throws -> OnboardingProgress {
        return OnboardingProgress(
            totalSteps: 0,
            completedSteps: 0,
            currentStep: nil,
            isComplete: true
        )
    }
}