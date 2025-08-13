import SwiftUI

struct CourseFilterSheet: View {
    @Binding var filters: CourseSearchFilters
    let onApply: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @ServiceInjected(HapticFeedbackServiceProtocol.self) private var hapticService
    
    @State private var tempFilters: CourseSearchFilters
    @State private var priceRange: ClosedRange<Double> = 0...200
    @State private var minimumRating: Double = 0.0
    
    init(filters: Binding<CourseSearchFilters>, onApply: @escaping () -> Void) {
        self._filters = filters
        self.onApply = onApply
        self._tempFilters = State(initialValue: filters.wrappedValue)
        
        // Initialize price range from filters
        if let filterPriceRange = filters.wrappedValue.priceRange {
            self._priceRange = State(initialValue: filterPriceRange)
        }
        
        // Initialize minimum rating from filters
        self._minimumRating = State(initialValue: filters.wrappedValue.minimumRating ?? 0.0)
    }
    
    var body: some View {
        NavigationView {
            Form {
                priceSection
                difficultySection
                amenitiesSection
                ratingSection
                courseTypeSection
                holesSection
                availabilitySection
            }
            .navigationTitle("Filter Golf Courses")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        resetFilters()
                        hapticService.impact(.light)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        applyFilters()
                        hapticService.selection()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Price Section
    
    private var priceSection: some View {
        Section("Price Range") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("$\(Int(priceRange.lowerBound))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("$\(Int(priceRange.upperBound))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                RangeSlider(range: $priceRange, bounds: 0...300)
                    .onChange(of: priceRange) { _ in
                        hapticService.impact(.light)
                    }
                
                Text("Per round, weekday rates")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Difficulty Section
    
    private var difficultySection: some View {
        Section("Difficulty Level") {
            ForEach(DifficultyLevel.allCases, id: \.self) { difficulty in
                HStack {
                    Button(action: {
                        toggleDifficulty(difficulty)
                        hapticService.impact(.light)
                    }) {
                        HStack {
                            Image(systemName: isDifficultySelected(difficulty) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isDifficultySelected(difficulty) ? .blue : .secondary)
                            
                            Text(difficulty.displayName)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Circle()
                                .fill(Color(difficulty.color))
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Amenities Section
    
    private var amenitiesSection: some View {
        Section("Required Amenities") {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(CourseAmenity.allCases, id: \.self) { amenity in
                    amenityButton(amenity)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func amenityButton(_ amenity: CourseAmenity) -> some View {
        Button(action: {
            toggleAmenity(amenity)
            hapticService.impact(.light)
        }) {
            HStack(spacing: 6) {
                Image(systemName: amenity.icon)
                    .font(.caption)
                Text(amenity.displayName)
                    .font(.caption)
            }
            .foregroundColor(isAmenitySelected(amenity) ? .white : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isAmenitySelected(amenity) ? Color.blue : Color.secondary.opacity(0.2))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Rating Section
    
    private var ratingSection: some View {
        Section("Minimum Rating") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ForEach(1...5, id: \.self) { star in
                        Button(action: {
                            minimumRating = Double(star)
                            hapticService.impact(.light)
                        }) {
                            Image(systemName: Double(star) <= minimumRating ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                                .font(.title3)
                        }
                    }
                    
                    Spacer()
                    
                    if minimumRating > 0 {
                        Button("Clear") {
                            minimumRating = 0
                            hapticService.impact(.light)
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                
                if minimumRating > 0 {
                    Text("Show courses with \(Int(minimumRating))+ stars")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No minimum rating requirement")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Course Type Section
    
    private var courseTypeSection: some View {
        Section("Course Type") {
            ForEach(CourseSearchFilters.CourseType.allCases, id: \.self) { courseType in
                HStack {
                    Button(action: {
                        toggleCourseType(courseType)
                        hapticService.impact(.light)
                    }) {
                        HStack {
                            Image(systemName: isCourseTypeSelected(courseType) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isCourseTypeSelected(courseType) ? .blue : .secondary)
                            
                            Text(courseType.displayName)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Holes Section
    
    private var holesSection: some View {
        Section("Number of Holes") {
            HStack {
                ForEach([9, 18], id: \.self) { holes in
                    Button(action: {
                        toggleHoles(holes)
                        hapticService.impact(.light)
                    }) {
                        HStack {
                            Image(systemName: isHolesSelected(holes) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isHolesSelected(holes) ? .blue : .secondary)
                            
                            Text("\(holes) holes")
                                .foregroundColor(.primary)
                        }
                    }
                    
                    if holes == 9 {
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - Availability Section
    
    private var availabilitySection: some View {
        Section("Availability") {
            Toggle("Has available tee times", isOn: Binding(
                get: { tempFilters.hasAvailableTimes ?? false },
                set: { value in
                    tempFilters.hasAvailableTimes = value ? true : nil
                    hapticService.impact(.light)
                }
            ))
            
            Toggle("Open today", isOn: Binding(
                get: { tempFilters.openToday ?? false },
                set: { value in
                    tempFilters.openToday = value ? true : nil
                    hapticService.impact(.light)
                }
            ))
        }
    }
    
    // MARK: - Helper Functions
    
    private func isDifficultySelected(_ difficulty: DifficultyLevel) -> Bool {
        tempFilters.difficulty?.contains(difficulty) ?? false
    }
    
    private func toggleDifficulty(_ difficulty: DifficultyLevel) {
        if tempFilters.difficulty == nil {
            tempFilters.difficulty = []
        }
        
        if tempFilters.difficulty!.contains(difficulty) {
            tempFilters.difficulty!.removeAll { $0 == difficulty }
            if tempFilters.difficulty!.isEmpty {
                tempFilters.difficulty = nil
            }
        } else {
            tempFilters.difficulty!.append(difficulty)
        }
    }
    
    private func isAmenitySelected(_ amenity: CourseAmenity) -> Bool {
        tempFilters.amenities?.contains(amenity) ?? false
    }
    
    private func toggleAmenity(_ amenity: CourseAmenity) {
        if tempFilters.amenities == nil {
            tempFilters.amenities = []
        }
        
        if tempFilters.amenities!.contains(amenity) {
            tempFilters.amenities!.removeAll { $0 == amenity }
            if tempFilters.amenities!.isEmpty {
                tempFilters.amenities = nil
            }
        } else {
            tempFilters.amenities!.append(amenity)
        }
    }
    
    private func isCourseTypeSelected(_ courseType: CourseSearchFilters.CourseType) -> Bool {
        tempFilters.courseType?.contains(courseType) ?? false
    }
    
    private func toggleCourseType(_ courseType: CourseSearchFilters.CourseType) {
        if tempFilters.courseType == nil {
            tempFilters.courseType = []
        }
        
        if tempFilters.courseType!.contains(courseType) {
            tempFilters.courseType!.removeAll { $0 == courseType }
            if tempFilters.courseType!.isEmpty {
                tempFilters.courseType = nil
            }
        } else {
            tempFilters.courseType!.append(courseType)
        }
    }
    
    private func isHolesSelected(_ holes: Int) -> Bool {
        tempFilters.holes?.contains(holes) ?? false
    }
    
    private func toggleHoles(_ holes: Int) {
        if tempFilters.holes == nil {
            tempFilters.holes = []
        }
        
        if tempFilters.holes!.contains(holes) {
            tempFilters.holes!.removeAll { $0 == holes }
            if tempFilters.holes!.isEmpty {
                tempFilters.holes = nil
            }
        } else {
            tempFilters.holes!.append(holes)
        }
    }
    
    private func resetFilters() {
        tempFilters = CourseSearchFilters()
        priceRange = 0...200
        minimumRating = 0.0
    }
    
    private func applyFilters() {
        // Apply price range if different from default
        if priceRange != 0...200 {
            tempFilters.priceRange = priceRange
        } else {
            tempFilters.priceRange = nil
        }
        
        // Apply minimum rating if set
        if minimumRating > 0 {
            tempFilters.minimumRating = minimumRating
        } else {
            tempFilters.minimumRating = nil
        }
        
        filters = tempFilters
        onApply()
    }
}

// MARK: - Range Slider Component

struct RangeSlider: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    
    private let height: CGFloat = 30
    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 20
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let trackWidth = width - thumbSize
            
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: trackHeight)
                    .cornerRadius(trackHeight / 2)
                    .offset(x: thumbSize / 2)
                
                // Active track
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: activeTrackWidth(in: trackWidth), height: trackHeight)
                    .cornerRadius(trackHeight / 2)
                    .offset(x: lowerThumbOffset(in: trackWidth) + thumbSize / 2)
                
                // Lower thumb
                Circle()
                    .fill(Color.blue)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: lowerThumbOffset(in: trackWidth))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newValue = valueFromOffset(value.location.x, in: trackWidth)
                                let clampedValue = max(bounds.lowerBound, min(range.upperBound, newValue))
                                range = clampedValue...range.upperBound
                            }
                    )
                
                // Upper thumb
                Circle()
                    .fill(Color.blue)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: upperThumbOffset(in: trackWidth))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newValue = valueFromOffset(value.location.x, in: trackWidth)
                                let clampedValue = max(range.lowerBound, min(bounds.upperBound, newValue))
                                range = range.lowerBound...clampedValue
                            }
                    )
            }
        }
        .frame(height: height)
    }
    
    private func lowerThumbOffset(in width: CGFloat) -> CGFloat {
        let ratio = (range.lowerBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        return ratio * width
    }
    
    private func upperThumbOffset(in width: CGFloat) -> CGFloat {
        let ratio = (range.upperBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        return ratio * width
    }
    
    private func activeTrackWidth(in totalWidth: CGFloat) -> CGFloat {
        let lowerRatio = (range.lowerBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        let upperRatio = (range.upperBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        return (upperRatio - lowerRatio) * totalWidth
    }
    
    private func valueFromOffset(_ offset: CGFloat, in width: CGFloat) -> Double {
        let ratio = offset / width
        return bounds.lowerBound + ratio * (bounds.upperBound - bounds.lowerBound)
    }
}

// MARK: - Preview

#Preview {
    CourseFilterSheet(filters: .constant(CourseSearchFilters())) {
        print("Filters applied")
    }
}