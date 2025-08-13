import SwiftUI
import LocalAuthentication

// MARK: - Biometric Setup View

struct BiometricSetupView: View {
    @StateObject private var viewModel: BiometricSetupViewModel
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Initialization
    
    init(
        biometricService: BiometricAuthServiceProtocol,
        onCompletion: @escaping (Bool) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: BiometricSetupViewModel(
            biometricService: biometricService,
            onCompletion: onCompletion
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator
                
                // Content based on current step
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Navigation buttons
                navigationButtons
                    .padding()
            }
            .navigationTitle("Biometric Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.cancelSetup()
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Setup Complete", isPresented: $viewModel.showSuccess) {
            Button("Done") {
                viewModel.completeSetup()
                dismiss()
            }
        } message: {
            Text("Biometric authentication has been successfully configured!")
        }
        .task {
            await viewModel.initializeSetup()
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        VStack(spacing: 16) {
            HStack {
                ForEach(0..<viewModel.totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index <= viewModel.currentStepIndex ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                    
                    if index < viewModel.totalSteps - 1 {
                        Rectangle()
                            .fill(index < viewModel.currentStepIndex ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
            .padding(.horizontal)
            
            Text("Step \(viewModel.currentStepIndex + 1) of \(viewModel.totalSteps)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            welcomeStep
        case .deviceCheck:
            deviceCheckStep
        case .permissions:
            permissionsStep
        case .configuration:
            configurationStep
        case .testing:
            testingStep
        case .completion:
            completionStep
        }
    }
    
    // MARK: - Welcome Step
    
    private var welcomeStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                Image(systemName: viewModel.biometricType == .faceID ? "faceid" : "touchid")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 16) {
                    Text("Welcome")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Set up \(viewModel.biometricType.displayName) for secure and convenient access to your account.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(spacing: 16) {
                FeatureRow(
                    icon: "bolt.fill",
                    title: "Quick Access",
                    description: "Sign in instantly with your \(viewModel.biometricType.displayName.lowercased())"
                )
                
                FeatureRow(
                    icon: "shield.fill",
                    title: "Enhanced Security",
                    description: "Your biometric data stays secure on your device"
                )
                
                FeatureRow(
                    icon: "gear",
                    title: "Flexible Settings",
                    description: "Configure when to use biometric authentication"
                )
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Device Check Step
    
    private var deviceCheckStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                if viewModel.isCheckingDevice {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                } else {
                    Image(systemName: viewModel.deviceCheckPassed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(viewModel.deviceCheckPassed ? .green : .red)
                }
                
                VStack(spacing: 16) {
                    Text("Device Check")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if viewModel.isCheckingDevice {
                        Text("Checking your device capabilities...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else if viewModel.deviceCheckPassed {
                        Text("\(viewModel.biometricType.displayName) is available on this device")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            Text("Biometric authentication is not available")
                                .font(.body)
                                .foregroundColor(.red)
                            
                            if let reason = viewModel.deviceCheckError {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
            }
            
            if !viewModel.deviceCheckPassed && !viewModel.isCheckingDevice {
                VStack(spacing: 16) {
                    Text("What you can do:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        SolutionRow(
                            icon: "gear",
                            text: "Check your device settings to enable \(viewModel.biometricType.displayName)"
                        )
                        
                        if viewModel.biometricType == .faceID {
                            SolutionRow(
                                icon: "faceid",
                                text: "Go to Settings > Face ID & Passcode to set up Face ID"
                            )
                        } else {
                            SolutionRow(
                                icon: "touchid",
                                text: "Go to Settings > Touch ID & Passcode to set up Touch ID"
                            )
                        }
                        
                        SolutionRow(
                            icon: "lock",
                            text: "Ensure you have a passcode set on your device"
                        )
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Permissions Step
    
    private var permissionsStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                
                VStack(spacing: 16) {
                    Text("Permissions")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("We need your permission to use \(viewModel.biometricType.displayName) for authentication.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(spacing: 16) {
                PermissionInfoRow(
                    icon: "shield.checkerboard",
                    title: "Privacy Protected",
                    description: "Your biometric data never leaves your device"
                )
                
                PermissionInfoRow(
                    icon: "lock.shield",
                    title: "Secure Storage",
                    description: "Biometric templates are encrypted in secure hardware"
                )
                
                PermissionInfoRow(
                    icon: "hand.tap",
                    title: "Your Control",
                    description: "You can disable this feature at any time"
                )
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Configuration Step
    
    private var configurationStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 16) {
                    Text("Configuration")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Choose when you want to use \(viewModel.biometricType.displayName).")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(spacing: 20) {
                ConfigurationToggle(
                    title: "Enable for Login",
                    description: "Use \(viewModel.biometricType.displayName) to sign in to your account",
                    isOn: $viewModel.enabledForLogin
                )
                
                ConfigurationToggle(
                    title: "Enable for Transactions",
                    description: "Require \(viewModel.biometricType.displayName) for booking confirmations",
                    isOn: $viewModel.enabledForTransactions
                )
                
                ConfigurationToggle(
                    title: "Enable for Settings",
                    description: "Protect sensitive settings with \(viewModel.biometricType.displayName)",
                    isOn: $viewModel.enabledForSettings
                )
                
                Divider()
                
                ConfigurationToggle(
                    title: "Allow Passcode Fallback",
                    description: "Use device passcode if \(viewModel.biometricType.displayName) fails",
                    isOn: $viewModel.allowsPasscodeFallback
                )
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Testing Step
    
    private var testingStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                if viewModel.isTesting {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                } else if viewModel.testPassed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: viewModel.biometricType == .faceID ? "faceid" : "touchid")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                }
                
                VStack(spacing: 16) {
                    Text("Testing")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if viewModel.isTesting {
                        Text("Testing \(viewModel.biometricType.displayName) authentication...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else if viewModel.testPassed {
                        Text("Test Passed")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        
                        Text("\(viewModel.biometricType.displayName) is working correctly!")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Let's test \(viewModel.biometricType.displayName) to make sure everything works correctly.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if !viewModel.testPassed && !viewModel.isTesting {
                Button(action: viewModel.testBiometricAuthentication) {
                    HStack {
                        Image(systemName: viewModel.biometricType == .faceID ? "faceid" : "touchid")
                        Text("Test \(viewModel.biometricType.displayName)")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            
            if let error = viewModel.testError {
                VStack(spacing: 8) {
                    Text("Test Failed")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Try Again") {
                        viewModel.testBiometricAuthentication()
                    }
                    .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Completion Step
    
    private var completionStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                VStack(spacing: 16) {
                    Text("Setup Complete!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("\(viewModel.biometricType.displayName) authentication has been successfully configured.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(spacing: 16) {
                CompletionSummaryRow(
                    icon: "checkmark.circle.fill",
                    title: "Login Protection",
                    enabled: viewModel.enabledForLogin
                )
                
                CompletionSummaryRow(
                    icon: "checkmark.circle.fill",
                    title: "Transaction Security",
                    enabled: viewModel.enabledForTransactions
                )
                
                CompletionSummaryRow(
                    icon: "checkmark.circle.fill",
                    title: "Settings Protection",
                    enabled: viewModel.enabledForSettings
                )
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if viewModel.canGoBack {
                Button("Back") {
                    viewModel.goToPreviousStep()
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 1)
                )
            }
            
            Button(viewModel.nextButtonTitle) {
                viewModel.goToNextStep()
            }
            .disabled(!viewModel.canProceed)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.canProceed ? Color.blue : Color.gray)
            )
        }
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct SolutionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.caption)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

struct PermissionInfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct ConfigurationToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $isOn)
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

struct CompletionSummaryRow: View {
    let icon: String
    let title: String
    let enabled: Bool
    
    var body: some View {
        HStack {
            Image(systemName: enabled ? icon : "circle")
                .foregroundColor(enabled ? .green : .gray)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(enabled ? .primary : .secondary)
            
            Spacer()
            
            Text(enabled ? "Enabled" : "Disabled")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Extensions

extension LABiometryType {
    var displayName: String {
        switch self {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            if #available(iOS 17.0, *) {
                return "Optic ID"
            } else {
                return "Biometric ID"
            }
        case .none:
            return "Biometric Authentication"
        @unknown default:
            return "Biometric Authentication"
        }
    }
}

// MARK: - Preview

struct BiometricSetupView_Previews: PreviewProvider {
    static var previews: some View {
        BiometricSetupView(
            biometricService: MockBiometricAuthService(),
            onCompletion: { _ in }
        )
    }
}