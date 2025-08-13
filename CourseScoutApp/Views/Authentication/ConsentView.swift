import SwiftUI
import Combine

// MARK: - Consent View

struct ConsentView: View {
    @StateObject private var viewModel: ConsentViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Initialization
    
    init(
        authenticationService: AuthenticationServiceProtocol,
        tenantConfigurationService: TenantConfigurationServiceProtocol,
        consentManager: ConsentManagerProtocol
    ) {
        self._viewModel = StateObject(wrappedValue: ConsentViewModel(
            authenticationService: authenticationService,
            tenantConfigurationService: tenantConfigurationService,
            consentManager: consentManager
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header section
                    headerSection
                    
                    // Consent categories
                    consentCategoriesSection
                    
                    // Data subject rights
                    dataSubjectRightsSection
                    
                    // Jurisdiction-specific requirements
                    if !viewModel.jurisdictionRequirements.isEmpty {
                        jurisdictionRequirementsSection
                    }
                    
                    // Action buttons
                    actionButtonsSection
                }
                .padding()
            }
        }
        .navigationTitle("Privacy Consent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    viewModel.cancelConsent()
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    viewModel.saveConsent()
                }
                .disabled(!viewModel.hasRequiredConsents || viewModel.isLoading)
            }
        }
        .sheet(isPresented: $viewModel.showPrivacyPolicy) {
            privacyPolicySheet
        }
        .sheet(isPresented: $viewModel.showDataProcessingDetails) {
            dataProcessingDetailsSheet
        }
        .sheet(isPresented: $viewModel.showThirdPartyDetails) {
            thirdPartyDetailsSheet
        }
        .sheet(isPresented: $viewModel.showDataSubjectRights) {
            dataSubjectRightsSheet
        }
        .alert("Consent Required", isPresented: $viewModel.showConsentError) {
            Button("OK") { viewModel.dismissConsentError() }
        } message: {
            Text(viewModel.consentErrorMessage)
        }
        .alert("Success", isPresented: $viewModel.showSuccess) {
            Button("Continue") {
                viewModel.dismissSuccess()
                dismiss()
            }
        } message: {
            Text("Your privacy preferences have been saved.")
        }
        .task {
            await viewModel.loadConsentRequirements()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Privacy icon
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            VStack(spacing: 8) {
                Text("Your Privacy Matters")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("We respect your privacy and want to be transparent about how we collect, use, and share your data.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Tenant-specific message
            if let tenant = viewModel.currentTenant {
                tenantPrivacyMessage(tenant)
            }
        }
    }
    
    private func tenantPrivacyMessage(_ tenant: TenantInfo) -> some View {
        VStack(spacing: 8) {
            HStack {
                if let logoURL = tenant.logoURL {
                    AsyncImage(url: logoURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 24, height: 24)
                }
                
                Text(tenant.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            if let privacyMessage = tenant.privacyMessage {
                Text(privacyMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - Consent Categories Section
    
    private var consentCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Consent Categories")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                ForEach(viewModel.consentCategories, id: \.id) { category in
                    ConsentCategoryCard(
                        category: category,
                        isConsented: Binding(
                            get: { viewModel.consentStates[category.id] ?? false },
                            set: { viewModel.updateConsent(for: category.id, granted: $0) }
                        ),
                        onLearnMore: {
                            viewModel.selectedCategory = category
                            if category.type == .dataProcessing {
                                viewModel.showDataProcessingDetails = true
                            } else if category.type == .thirdParty {
                                viewModel.showThirdPartyDetails = true
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Data Subject Rights Section
    
    private var dataSubjectRightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Rights")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                ForEach(viewModel.dataSubjectRights, id: \.type) { right in
                    DataSubjectRightCard(right: right) {
                        viewModel.selectedRight = right
                        viewModel.showDataSubjectRights = true
                    }
                }
            }
            
            Button("Learn More About Your Rights") {
                viewModel.showDataSubjectRights = true
            }
            .font(.subheadline)
            .foregroundColor(.blue)
        }
    }
    
    // MARK: - Jurisdiction Requirements Section
    
    private var jurisdictionRequirementsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Regional Requirements")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                ForEach(viewModel.jurisdictionRequirements, id: \.jurisdiction) { requirement in
                    JurisdictionRequirementCard(requirement: requirement)
                }
            }
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Accept all button
            Button(action: viewModel.acceptAllConsents) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    Text("Accept All")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(viewModel.isLoading)
            
            // Accept selected button
            Button(action: viewModel.acceptSelectedConsents) {
                Text("Accept Selected")
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 1)
                    )
            }
            .disabled(!viewModel.hasRequiredConsents || viewModel.isLoading)
            
            // Reject all button (if allowed)
            if viewModel.allowRejectAll {
                Button(action: viewModel.rejectAllConsents) {
                    Text("Reject All")
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red, lineWidth: 1)
                        )
                }
                .disabled(viewModel.isLoading)
            }
            
            // View privacy policy link
            Button("View Privacy Policy") {
                viewModel.showPrivacyPolicy = true
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Sheets
    
    private var privacyPolicySheet: some View {
        NavigationView {
            PrivacyPolicyView(
                privacyPolicy: viewModel.privacyPolicy,
                tenant: viewModel.currentTenant
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
    
    private var dataProcessingDetailsSheet: some View {
        NavigationView {
            DataProcessingDetailsView(
                category: viewModel.selectedCategory,
                processingDetails: viewModel.dataProcessingDetails
            )
            .navigationTitle("Data Processing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.showDataProcessingDetails = false
                    }
                }
            }
        }
    }
    
    private var thirdPartyDetailsSheet: some View {
        NavigationView {
            ThirdPartyDetailsView(
                category: viewModel.selectedCategory,
                thirdParties: viewModel.thirdPartyServices
            )
            .navigationTitle("Third Party Services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.showThirdPartyDetails = false
                    }
                }
            }
        }
    }
    
    private var dataSubjectRightsSheet: some View {
        NavigationView {
            DataSubjectRightsView(
                rights: viewModel.dataSubjectRights,
                selectedRight: viewModel.selectedRight,
                onExerciseRight: { right in
                    viewModel.exerciseDataSubjectRight(right)
                }
            )
            .navigationTitle("Your Rights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.showDataSubjectRights = false
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ConsentCategoryCard: View {
    let category: ConsentCategory
    @Binding var isConsented: Bool
    let onLearnMore: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(category.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if category.isRequired {
                            Text("Required")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(category.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Toggle("", isOn: $isConsented)
                    .disabled(category.isRequired && isConsented)
            }
            
            if !category.purposes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used for:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(category.purposes, id: \.self) { purpose in
                        Text("• \(purpose)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack {
                if !category.legalBasis.isEmpty {
                    Text("Legal basis: \(category.legalBasis)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Learn More") {
                    onLearnMore()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isConsented ? Color.blue : Color(.systemGray4), lineWidth: 1)
        )
    }
}

struct DataSubjectRightCard: View {
    let right: DataSubjectRight
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: right.iconName)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(right.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(right.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct JurisdictionRequirementCard: View {
    let requirement: JurisdictionRequirement
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(requirement.jurisdiction)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(requirement.regulation)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            
            Text(requirement.description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !requirement.specificRequirements.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(requirement.specificRequirements, id: \.self) { req in
                        Text("• \(req)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
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
}

// MARK: - Detail Views

struct PrivacyPolicyView: View {
    let privacyPolicy: PrivacyPolicy?
    let tenant: TenantInfo?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let policy = privacyPolicy {
                    Text(policy.content)
                        .font(.body)
                    
                    if let lastUpdated = policy.lastUpdated {
                        Text("Last updated: \(lastUpdated, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Privacy policy not available")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

struct DataProcessingDetailsView: View {
    let category: ConsentCategory?
    let processingDetails: DataProcessingDetails?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let category = category {
                    Text(category.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(category.description)
                        .font(.body)
                }
                
                if let details = processingDetails {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Data Collected")
                        ForEach(details.dataTypes, id: \.self) { dataType in
                            Text("• \(dataType)")
                                .font(.body)
                        }
                        
                        SectionHeader(title: "Processing Purpose")
                        Text(details.purpose)
                            .font(.body)
                        
                        SectionHeader(title: "Legal Basis")
                        Text(details.legalBasis)
                            .font(.body)
                        
                        SectionHeader(title: "Retention Period")
                        Text(details.retentionPeriod)
                            .font(.body)
                        
                        if !details.recipients.isEmpty {
                            SectionHeader(title: "Data Recipients")
                            ForEach(details.recipients, id: \.self) { recipient in
                                Text("• \(recipient)")
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct ThirdPartyDetailsView: View {
    let category: ConsentCategory?
    let thirdParties: [ThirdPartyService]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let category = category {
                    Text(category.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(category.description)
                        .font(.body)
                }
                
                ForEach(thirdParties, id: \.id) { service in
                    ThirdPartyServiceCard(service: service)
                }
            }
            .padding()
        }
    }
}

struct ThirdPartyServiceCard: View {
    let service: ThirdPartyService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(service.name)
                .font(.headline)
            
            Text(service.purpose)
                .font(.body)
                .foregroundColor(.secondary)
            
            if let privacyPolicyURL = service.privacyPolicyURL {
                Link("View Privacy Policy", destination: privacyPolicyURL)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct DataSubjectRightsView: View {
    let rights: [DataSubjectRight]
    let selectedRight: DataSubjectRight?
    let onExerciseRight: (DataSubjectRight) -> Void
    
    var body: some View {
        List {
            ForEach(rights, id: \.type) { right in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(right.description)
                            .font(.body)
                        
                        if let details = right.details {
                            Text(details)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Button("Exercise This Right") {
                            onExerciseRight(right)
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(right.title)
                        .font(.headline)
                }
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
            .padding(.top, 8)
    }
}

// MARK: - Extensions

extension DataSubjectRight {
    var iconName: String {
        switch type {
        case .access: return "eye"
        case .rectification: return "pencil"
        case .erasure: return "trash"
        case .portability: return "arrow.down.doc"
        case .restriction: return "hand.raised"
        case .objection: return "exclamationmark.triangle"
        case .withdrawal: return "hand.wave"
        }
    }
}

// MARK: - Preview

struct ConsentView_Previews: PreviewProvider {
    static var previews: some View {
        ConsentView(
            authenticationService: MockAuthenticationService(),
            tenantConfigurationService: MockTenantConfigurationService(),
            consentManager: MockConsentManager()
        )
    }
}

class MockConsentManager: ConsentManagerProtocol {
    func getConsentRequirements(for tenantId: String?, jurisdiction: String?) async throws -> ConsentRequirements {
        return ConsentRequirements(
            categories: [],
            dataSubjectRights: [],
            jurisdictionRequirements: []
        )
    }
    
    func saveConsent(_ consent: UserConsent) async throws {
    }
    
    func getConsent(userId: String) async throws -> UserConsent? {
        return nil
    }
    
    func updateConsent(userId: String, categoryId: String, granted: Bool) async throws {
    }
    
    func exerciseDataSubjectRight(_ request: DataSubjectRightRequest) async throws {
    }
}