import SwiftUI
import Combine

struct ChallengeCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.serviceContainer) private var serviceContainer
    
    @State private var challengeName = ""
    @State private var challengeDescription = ""
    @State private var selectedCourse: Course?
    @State private var selectedMetric: SocialChallenge.ChallengeMetric = .lowestScore
    @State private var targetScore: Int = 72
    @State private var entryFee: Double = 0
    @State private var maxParticipants: Int = 50
    @State private var isPublic = true
    @State private var inviteOnly = false
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(86400 * 7) // Default 1 week
    @State private var selectedFriends: Set<String> = []
    @State private var hasPrizes = false
    @State private var prizeDescription = ""
    
    @State private var isCreating = false
    @State private var showingCourseSelection = false
    @State private var showingFriendSelection = false
    @State private var showingPreview = false
    @State private var creationProgress: Double = 0
    @State private var currentStep = 0
    
    private let creationSteps = [
        "Basic Details",
        "Challenge Rules",
        "Participants",
        "Prize & Fees",
        "Review & Create"
    ]
    
    private var hapticService: HapticFeedbackServiceProtocol {
        serviceContainer.hapticFeedbackService
    }
    
    private var isFormValid: Bool {
        !challengeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedCourse != nil &&
        endDate > startDate &&
        targetScore > 0 &&
        maxParticipants > 0
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color(.systemGroupedBackground)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Progress indicator
                        progressSection
                        
                        // Step content
                        stepContent
                    }
                    .padding()
                }
                
                // Creation overlay
                if isCreating {
                    creationOverlay
                }
            }
            .navigationTitle("Create Challenge")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        handleCancel()
                    }
                    .foregroundColor(.red)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if currentStep < creationSteps.count - 1 {
                        Button("Next") {
                            nextStep()
                        }
                        .fontWeight(.semibold)
                        .disabled(!canProceedToNextStep())
                    } else {
                        Button("Create") {
                            createChallenge()
                        }
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .disabled(!isFormValid || isCreating)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCourseSelection) {
            CourseSelectionView(selectedCourse: $selectedCourse)
        }
        .sheet(isPresented: $showingFriendSelection) {
            FriendSelectionView(selectedFriends: $selectedFriends)
        }
        .sheet(isPresented: $showingPreview) {
            ChallengePreviewView(
                challengeName: challengeName,
                description: challengeDescription,
                course: selectedCourse,
                metric: selectedMetric,
                targetScore: targetScore,
                entryFee: entryFee,
                startDate: startDate,
                endDate: endDate,
                isPublic: isPublic,
                selectedFriends: selectedFriends
            )
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 16) {
            // Progress bar
            HStack {
                ForEach(Array(creationSteps.enumerated()), id: \.offset) { index, step in
                    HStack {
                        Circle()
                            .fill(index <= currentStep ? .blue : Color(.tertiaryLabel))
                            .frame(width: 12, height: 12)
                        
                        if index < creationSteps.count - 1 {
                            Rectangle()
                                .fill(index < currentStep ? .blue : Color(.tertiaryLabel))
                                .frame(height: 2)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            
            // Current step
            Text(creationSteps[currentStep])
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("Step \(currentStep + 1) of \(creationSteps.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            basicDetailsStep
        case 1:
            challengeRulesStep
        case 2:
            participantsStep
        case 3:
            prizesStep
        case 4:
            reviewStep
        default:
            EmptyView()
        }
    }
    
    // MARK: - Basic Details Step
    
    private var basicDetailsStep: some View {
        VStack(spacing: 20) {
            FormCard {
                VStack(spacing: 16) {
                    // Challenge name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Challenge Name")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("Enter challenge name", text: $challengeName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description (Optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("Describe your challenge...", text: $challengeDescription, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(3...6)
                    }
                    
                    // Course selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Golf Course")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Button {
                            showingCourseSelection = true
                        } label: {
                            HStack {
                                if let course = selectedCourse {
                                    VStack(alignment: .leading) {
                                        Text(course.name)
                                            .foregroundColor(.primary)
                                        Text(course.location)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text("Select Course")
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Challenge Rules Step
    
    private var challengeRulesStep: some View {
        VStack(spacing: 20) {
            FormCard {
                VStack(spacing: 16) {
                    // Challenge metric
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Challenge Type")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(SocialChallenge.ChallengeMetric.allCases, id: \.self) { metric in
                                Text(metric.displayName).tag(metric)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    // Target score
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Score")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Stepper(
                                value: $targetScore,
                                in: 50...120,
                                step: 1
                            ) {
                                Text("\(targetScore)")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    
                    // Date range
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Challenge Duration")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        VStack(spacing: 12) {
                            DatePicker(
                                "Start Date",
                                selection: $startDate,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            
                            DatePicker(
                                "End Date",
                                selection: $endDate,
                                in: startDate.addingTimeInterval(3600)...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Participants Step
    
    private var participantsStep: some View {
        VStack(spacing: 20) {
            FormCard {
                VStack(spacing: 16) {
                    // Public/Private toggle
                    Toggle("Public Challenge", isOn: $isPublic)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if !isPublic {
                        Toggle("Invite Only", isOn: $inviteOnly)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    // Max participants
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Maximum Participants")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Stepper(
                            value: $maxParticipants,
                            in: 2...200,
                            step: 5
                        ) {
                            Text("\(maxParticipants) players")
                                .font(.body)
                        }
                    }
                    
                    // Friend selection
                    if !isPublic || inviteOnly {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Invite Friends")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Button {
                                showingFriendSelection = true
                            } label: {
                                HStack {
                                    Text("\(selectedFriends.count) friends selected")
                                        .foregroundColor(selectedFriends.isEmpty ? .secondary : .primary)
                                    
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.tertiarySystemGroupedBackground))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Prizes Step
    
    private var prizesStep: some View {
        VStack(spacing: 20) {
            FormCard {
                VStack(spacing: 16) {
                    // Entry fee
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Entry Fee (Optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text("$")
                            TextField("0", value: $entryFee, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                        }
                    }
                    
                    // Prizes toggle
                    Toggle("Add Prizes", isOn: $hasPrizes)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if hasPrizes {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prize Description")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            TextField("Describe the prizes...", text: $prizeDescription, axis: .vertical)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .lineLimit(2...4)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Review Step
    
    private var reviewStep: some View {
        VStack(spacing: 20) {
            // Preview card
            if let course = selectedCourse {
                ChallengePreviewCard(
                    name: challengeName,
                    description: challengeDescription,
                    course: course,
                    metric: selectedMetric,
                    targetScore: targetScore,
                    entryFee: entryFee,
                    startDate: startDate,
                    endDate: endDate,
                    maxParticipants: maxParticipants,
                    isPublic: isPublic,
                    friendCount: selectedFriends.count
                )
            }
            
            FormCard {
                VStack(spacing: 12) {
                    Text("Ready to Create?")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Review your challenge details above. Once created, some settings cannot be changed.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    // MARK: - Supporting Views
    
    private var creationOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.2)
                
                Text("Creating Challenge...")
                    .font(.headline)
                    .fontWeight(.medium)
                
                ProgressView(value: creationProgress)
                    .frame(width: 200)
            }
            .padding(30)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 20)
        }
    }
    
    // MARK: - Helper Views
    
    private struct FormCard<Content: View>: View {
        let content: Content
        
        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }
        
        var body: some View {
            VStack {
                content
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Actions
    
    private func handleCancel() {
        Task {
            await hapticService.provideFriendChallengeHaptic(challengeEvent: .declined)
        }
        dismiss()
    }
    
    private func nextStep() {
        Task {
            await hapticService.provideChallengeInvitationHaptic()
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = min(currentStep + 1, creationSteps.count - 1)
        }
    }
    
    private func canProceedToNextStep() -> Bool {
        switch currentStep {
        case 0:
            return !challengeName.isEmpty && selectedCourse != nil
        case 1:
            return endDate > startDate && targetScore > 0
        case 2:
            return maxParticipants > 1
        case 3:
            return true // Optional step
        default:
            return true
        }
    }
    
    private func createChallenge() {
        Task {
            await hapticService.provideFriendChallengeHaptic(challengeEvent: .accepted)
            
            withAnimation(.easeInOut(duration: 0.3)) {
                isCreating = true
                creationProgress = 0.0
            }
            
            // Simulate challenge creation with progress
            for i in 1...10 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    creationProgress = Double(i) / 10.0
                }
            }
            
            await hapticService.provideChallengeVictoryHaptic(competitionLevel: .competitive)
            
            dismiss()
        }
    }
}

// MARK: - Supporting Views

struct ChallengePreviewCard: View {
    let name: String
    let description: String
    let course: Course
    let metric: SocialChallenge.ChallengeMetric
    let targetScore: Int
    let entryFee: Double
    let startDate: Date
    let endDate: Date
    let maxParticipants: Int
    let isPublic: Bool
    let friendCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(name)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text(isPublic ? "PUBLIC" : "PRIVATE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPublic ? .blue : .orange)
                    .cornerRadius(6)
            }
            
            if !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                Label(course.name, systemImage: "flag.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Label("\(maxParticipants) max", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text(metric.displayName)
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Spacer()
                
                if entryFee > 0 {
                    Text("$\(Int(entryFee)) entry")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Extensions

private extension SocialChallenge.ChallengeMetric {
    var displayName: String {
        switch self {
        case .lowestScore:
            return "Lowest Score"
        case .mostImproved:
            return "Most Improved"
        case .longestDrive:
            return "Longest Drive"
        case .fewestPutts:
            return "Fewest Putts"
        }
    }
}

// MARK: - Mock Data Types

struct Course: Identifiable, Hashable {
    let id: String
    let name: String
    let location: String
}

// MARK: - Placeholder Views

struct CourseSelectionView: View {
    @Binding var selectedCourse: Course?
    @Environment(\.dismiss) private var dismiss
    
    let sampleCourses = [
        Course(id: "1", name: "Pebble Beach Golf Links", location: "Pebble Beach, CA"),
        Course(id: "2", name: "Augusta National", location: "Augusta, GA"),
        Course(id: "3", name: "St. Andrews Links", location: "St. Andrews, Scotland")
    ]
    
    var body: some View {
        NavigationStack {
            List(sampleCourses) { course in
                Button {
                    selectedCourse = course
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(course.name)
                            .foregroundColor(.primary)
                        Text(course.location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Select Course")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FriendSelectionView: View {
    @Binding var selectedFriends: Set<String>
    @Environment(\.dismiss) private var dismiss
    
    let sampleFriends = ["John", "Sarah", "Mike", "Emma", "David", "Lisa"]
    
    var body: some View {
        NavigationStack {
            List(sampleFriends, id: \.self) { friend in
                Button {
                    if selectedFriends.contains(friend) {
                        selectedFriends.remove(friend)
                    } else {
                        selectedFriends.insert(friend)
                    }
                } label: {
                    HStack {
                        Text(friend)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if selectedFriends.contains(friend) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Friends")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ChallengePreviewView: View {
    let challengeName: String
    let description: String
    let course: Course?
    let metric: SocialChallenge.ChallengeMetric
    let targetScore: Int
    let entryFee: Double
    let startDate: Date
    let endDate: Date
    let isPublic: Bool
    let selectedFriends: Set<String>
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Challenge Preview")
                    .font(.title)
                    .fontWeight(.bold)
                
                // Preview content here
            }
            .navigationTitle("Preview")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ChallengeCreationView()
}