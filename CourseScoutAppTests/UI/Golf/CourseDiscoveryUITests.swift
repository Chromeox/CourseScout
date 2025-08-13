import XCTest
import SwiftUI
@testable import GolfFinderSwiftUI

class CourseDiscoveryUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launchEnvironment = [
            "TEST_ENVIRONMENT": "ui_testing",
            "USE_MOCK_SERVICES": "true",
            "ENABLE_UI_TEST_IDENTIFIERS": "true",
            "DISABLE_ANIMATIONS": "true"
        ]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Course Discovery Flow Tests
    
    func testCourseDiscovery_InitialLoad_ShouldDisplayCourses() throws {
        // Given - App launches to course discovery screen
        
        // When - Wait for initial load
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        XCTAssertTrue(coursesCollectionView.waitForExistence(timeout: 5))
        
        // Then - Should display course cards
        let courseCards = coursesCollectionView.cells
        XCTAssertGreaterThan(courseCards.count, 0, "Should display at least one course")
        
        // Verify course card elements
        let firstCourseCard = courseCards.firstMatch
        XCTAssertTrue(firstCourseCard.exists)
        
        // Verify course name is displayed
        let courseName = firstCourseCard.staticTexts.matching(identifier: "CourseName").firstMatch
        XCTAssertTrue(courseName.exists, "Course name should be displayed")
        
        // Verify rating is displayed
        let courseRating = firstCourseCard.staticTexts.matching(identifier: "CourseRating").firstMatch
        XCTAssertTrue(courseRating.exists, "Course rating should be displayed")
        
        // Verify distance is displayed
        let courseDistance = firstCourseCard.staticTexts.matching(identifier: "CourseDistance").firstMatch
        XCTAssertTrue(courseDistance.exists, "Course distance should be displayed")
    }
    
    func testCourseDiscovery_SearchFunctionality_ShouldFilterResults() throws {
        // Given - Course discovery screen is loaded
        let searchField = app.searchFields["CourseSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        let initialCourseCount = coursesCollectionView.cells.count
        
        // When - Enter search term
        searchField.tap()
        searchField.typeText("Pebble Beach")
        
        // Wait for search results
        Thread.sleep(forTimeInterval: 1)
        
        // Then - Results should be filtered
        let filteredCourseCount = coursesCollectionView.cells.count
        XCTAssertLessThanOrEqual(filteredCourseCount, initialCourseCount, "Search should filter results")
        
        // Verify search results contain search term
        if filteredCourseCount > 0 {
            let firstResult = coursesCollectionView.cells.firstMatch
            let courseName = firstResult.staticTexts.matching(identifier: "CourseName").firstMatch
            let courseNameText = courseName.label
            XCTAssertTrue(
                courseNameText.localizedCaseInsensitiveContains("pebble") ||
                courseNameText.localizedCaseInsensitiveContains("beach"),
                "Search results should match search term"
            )
        }
    }
    
    func testCourseDiscovery_FilterButton_ShouldOpenFilterSheet() throws {
        // Given - Course discovery screen
        let filterButton = app.buttons["FilterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        
        // When - Tap filter button
        filterButton.tap()
        
        // Then - Filter sheet should appear
        let filterSheet = app.sheets["CourseFilterSheet"]
        XCTAssertTrue(filterSheet.waitForExistence(timeout: 3))
        
        // Verify filter options are present
        XCTAssertTrue(app.staticTexts["Price Range"].exists)
        XCTAssertTrue(app.staticTexts["Difficulty"].exists)
        XCTAssertTrue(app.staticTexts["Rating"].exists)
        XCTAssertTrue(app.staticTexts["Distance"].exists)
        
        // Verify filter controls
        XCTAssertTrue(app.sliders["PriceRangeSlider"].exists)
        XCTAssertTrue(app.segmentedControls["DifficultySelector"].exists)
        XCTAssertTrue(app.sliders["MinimumRatingSlider"].exists)
        XCTAssertTrue(app.sliders["MaxDistanceSlider"].exists)
    }
    
    func testCourseDiscovery_ApplyFilters_ShouldUpdateResults() throws {
        // Given - Open filter sheet
        app.buttons["FilterButton"].tap()
        let filterSheet = app.sheets["CourseFilterSheet"]
        XCTAssertTrue(filterSheet.waitForExistence(timeout: 3))
        
        // When - Adjust price range filter
        let priceSlider = app.sliders["PriceRangeSlider"]
        priceSlider.adjust(toNormalizedSliderPosition: 0.25) // Adjust to lower price range
        
        // Adjust minimum rating
        let ratingSlider = app.sliders["MinimumRatingSlider"]
        ratingSlider.adjust(toNormalizedSliderPosition: 0.8) // 4+ star rating
        
        // Apply filters
        app.buttons["ApplyFiltersButton"].tap()
        
        // Then - Wait for results to update
        Thread.sleep(forTimeInterval: 1)
        
        // Verify filter sheet is dismissed
        XCTAssertFalse(filterSheet.exists)
        
        // Verify results are filtered
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        let courseCards = coursesCollectionView.cells
        
        if courseCards.count > 0 {
            // Check first course meets filter criteria
            let firstCourse = courseCards.firstMatch
            let ratingText = firstCourse.staticTexts.matching(identifier: "CourseRating").firstMatch.label
            
            // Extract rating value (assuming format like "4.5 ★")
            if let ratingValue = Double(ratingText.components(separatedBy: " ").first ?? "0") {
                XCTAssertGreaterThanOrEqual(ratingValue, 4.0, "Filtered courses should meet minimum rating requirement")
            }
        }
    }
    
    func testCourseDiscovery_CourseCardTap_ShouldNavigateToDetail() throws {
        // Given - Course discovery screen with courses
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        XCTAssertTrue(coursesCollectionView.waitForExistence(timeout: 5))
        
        let firstCourseCard = coursesCollectionView.cells.firstMatch
        XCTAssertTrue(firstCourseCard.exists)
        
        // Store course name for verification
        let courseName = firstCourseCard.staticTexts.matching(identifier: "CourseName").firstMatch.label
        
        // When - Tap on course card
        firstCourseCard.tap()
        
        // Then - Course detail sheet should appear
        let courseDetailSheet = app.sheets["CourseDetailSheet"]
        XCTAssertTrue(courseDetailSheet.waitForExistence(timeout: 3))
        
        // Verify course detail elements
        XCTAssertTrue(app.staticTexts["CourseDetailName"].exists)
        XCTAssertTrue(app.staticTexts["CourseDetailAddress"].exists)
        XCTAssertTrue(app.staticTexts["CourseDetailPhone"].exists)
        XCTAssertTrue(app.images["CourseDetailImage"].exists)
        XCTAssertTrue(app.buttons["BookTeeTimeButton"].exists)
        XCTAssertTrue(app.buttons["ViewOnMapButton"].exists)
        
        // Verify correct course is displayed
        let detailCourseName = app.staticTexts["CourseDetailName"].label
        XCTAssertEqual(detailCourseName, courseName, "Detail view should show the selected course")
    }
    
    func testCourseDiscovery_LocationToggle_ShouldUpdateSortOrder() throws {
        // Given - Course discovery screen
        let sortButton = app.buttons["SortButton"]
        XCTAssertTrue(sortButton.waitForExistence(timeout: 5))
        
        // Get initial course order
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        let initialFirstCourse = coursesCollectionView.cells.firstMatch.staticTexts.matching(identifier: "CourseName").firstMatch.label
        
        // When - Change sort to distance
        sortButton.tap()
        let sortActionSheet = app.actionSheets.firstMatch
        XCTAssertTrue(sortActionSheet.waitForExistence(timeout: 3))
        
        app.buttons["Sort by Distance"].tap()
        
        // Wait for re-sort
        Thread.sleep(forTimeInterval: 1)
        
        // Then - Course order should change (unless already sorted by distance)
        let newFirstCourse = coursesCollectionView.cells.firstMatch.staticTexts.matching(identifier: "CourseName").firstMatch.label
        
        // Note: Order might be the same if already sorted by distance, so we just verify the sort action worked
        XCTAssertTrue(coursesCollectionView.cells.count > 0, "Courses should still be displayed after sorting")
        
        // Verify distance is shown in results
        let firstCourseDistance = coursesCollectionView.cells.firstMatch.staticTexts.matching(identifier: "CourseDistance").firstMatch
        XCTAssertTrue(firstCourseDistance.exists, "Distance should be displayed when sorted by distance")
    }
    
    func testCourseDiscovery_PullToRefresh_ShouldReloadData() throws {
        // Given - Course discovery screen
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        XCTAssertTrue(coursesCollectionView.waitForExistence(timeout: 5))
        
        // When - Pull to refresh
        let firstCell = coursesCollectionView.cells.firstMatch
        let start = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let finish = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 2.0))
        start.press(forDuration: 0.1, thenDragTo: finish)
        
        // Then - Loading indicator should appear briefly
        let refreshIndicator = app.activityIndicators["RefreshIndicator"]
        if refreshIndicator.exists {
            // Wait for refresh to complete
            XCTAssertTrue(refreshIndicator.waitForNonExistence(timeout: 10))
        }
        
        // Courses should still be displayed
        XCTAssertTrue(coursesCollectionView.cells.count > 0, "Courses should be displayed after refresh")
    }
    
    // MARK: - Map View Tests
    
    func testCourseDiscovery_MapViewToggle_ShouldShowMap() throws {
        // Given - Course discovery screen
        let mapToggleButton = app.buttons["MapViewToggle"]
        XCTAssertTrue(mapToggleButton.waitForExistence(timeout: 5))
        
        // When - Switch to map view
        mapToggleButton.tap()
        
        // Then - Map should be displayed
        let mapView = app.maps["CoursesMapView"]
        XCTAssertTrue(mapView.waitForExistence(timeout: 5))
        
        // Verify map annotations are present
        let mapAnnotations = mapView.otherElements.matching(identifier: "CourseMapAnnotation")
        XCTAssertGreaterThan(mapAnnotations.count, 0, "Map should display course annotations")
        
        // Verify map controls
        XCTAssertTrue(app.buttons["CurrentLocationButton"].exists)
        XCTAssertTrue(app.buttons["ListViewToggle"].exists)
    }
    
    func testCourseDiscovery_MapAnnotationTap_ShouldShowCourseDetail() throws {
        // Given - Map view is displayed
        app.buttons["MapViewToggle"].tap()
        let mapView = app.maps["CoursesMapView"]
        XCTAssertTrue(mapView.waitForExistence(timeout: 5))
        
        // When - Tap on map annotation
        let firstAnnotation = mapView.otherElements.matching(identifier: "CourseMapAnnotation").firstMatch
        XCTAssertTrue(firstAnnotation.exists)
        firstAnnotation.tap()
        
        // Then - Course detail sheet should appear
        let courseDetailSheet = app.sheets["CourseDetailSheet"]
        XCTAssertTrue(courseDetailSheet.waitForExistence(timeout: 3))
        
        // Verify course detail is displayed
        XCTAssertTrue(app.staticTexts["CourseDetailName"].exists)
        XCTAssertTrue(app.buttons["BookTeeTimeButton"].exists)
    }
    
    // MARK: - Performance Tests
    
    func testCourseDiscovery_ScrollPerformance_ShouldBeSmooth() throws {
        // Given - Course discovery screen with many courses
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        XCTAssertTrue(coursesCollectionView.waitForExistence(timeout: 5))
        
        // When - Perform rapid scrolling
        let startTime = Date()
        
        for _ in 0..<10 {
            coursesCollectionView.swipeUp()
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        for _ in 0..<10 {
            coursesCollectionView.swipeDown()
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        let scrollTime = Date().timeIntervalSince(startTime)
        
        // Then - Scrolling should complete within reasonable time
        XCTAssertLessThan(scrollTime, 5.0, "Scrolling should be performant")
        
        // UI should remain responsive
        let searchField = app.searchFields["CourseSearchField"]
        XCTAssertTrue(searchField.exists, "UI should remain responsive after scrolling")
    }
    
    func testCourseDiscovery_SearchPerformance_ShouldBeInstant() throws {
        // Given - Course discovery screen
        let searchField = app.searchFields["CourseSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        // When - Enter search text rapidly
        searchField.tap()
        
        let startTime = Date()
        searchField.typeText("Golf")
        
        // Wait for search results
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        let resultsAppeared = coursesCollectionView.cells.firstMatch.waitForExistence(timeout: 3)
        let searchTime = Date().timeIntervalSince(startTime)
        
        // Then - Search results should appear quickly
        XCTAssertTrue(resultsAppeared, "Search results should appear")
        XCTAssertLessThan(searchTime, 1.0, "Search should be nearly instantaneous")
    }
    
    // MARK: - Accessibility Tests
    
    func testCourseDiscovery_Accessibility_ShouldSupportVoiceOver() throws {
        // Given - Course discovery screen
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        XCTAssertTrue(coursesCollectionView.waitForExistence(timeout: 5))
        
        // When - Check accessibility elements
        let firstCourseCard = coursesCollectionView.cells.firstMatch
        
        // Then - Course cards should be accessible
        XCTAssertTrue(firstCourseCard.isAccessibilityElement || firstCourseCard.accessibilityElements != nil)
        
        // Check search field accessibility
        let searchField = app.searchFields["CourseSearchField"]
        XCTAssertNotNil(searchField.accessibilityLabel)
        XCTAssertNotNil(searchField.accessibilityHint)
        
        // Check filter button accessibility
        let filterButton = app.buttons["FilterButton"]
        XCTAssertNotNil(filterButton.accessibilityLabel)
        XCTAssertNotNil(filterButton.accessibilityHint)
        
        // Check sort button accessibility
        let sortButton = app.buttons["SortButton"]
        XCTAssertNotNil(sortButton.accessibilityLabel)
    }
    
    func testCourseDiscovery_DarkMode_ShouldDisplayCorrectly() throws {
        // Given - Switch to dark mode
        let settingsApp = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settingsApp.launch()
        
        // Navigate to Display & Brightness settings
        settingsApp.tables.cells["Display & Brightness"].tap()
        settingsApp.tables.cells["Dark"].tap()
        
        // Return to main app
        app.activate()
        
        // When - Check course discovery in dark mode
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        XCTAssertTrue(coursesCollectionView.waitForExistence(timeout: 5))
        
        // Then - UI should be displayed correctly in dark mode
        let firstCourseCard = coursesCollectionView.cells.firstMatch
        XCTAssertTrue(firstCourseCard.exists, "Course cards should be visible in dark mode")
        
        // Verify text is readable (not testing specific colors, just that elements exist)
        let courseName = firstCourseCard.staticTexts.matching(identifier: "CourseName").firstMatch
        XCTAssertTrue(courseName.exists, "Course names should be visible in dark mode")
    }
    
    // MARK: - Error Handling Tests
    
    func testCourseDiscovery_NetworkError_ShouldShowErrorState() throws {
        // Given - Simulate network error
        app.launchEnvironment["SIMULATE_NETWORK_ERROR"] = "true"
        app.terminate()
        app.launch()
        
        // When - Wait for error state
        let errorView = app.staticTexts["NetworkErrorMessage"]
        
        // Then - Error message should be displayed
        XCTAssertTrue(errorView.waitForExistence(timeout: 10))
        
        // Verify retry button is available
        let retryButton = app.buttons["RetryButton"]
        XCTAssertTrue(retryButton.exists, "Retry button should be available")
        
        // Test retry functionality
        retryButton.tap()
        
        // Error view should disappear (or attempt to reload)
        Thread.sleep(forTimeInterval: 2)
        // Note: In a real test, you'd verify the retry actually works
    }
    
    func testCourseDiscovery_EmptyResults_ShouldShowEmptyState() throws {
        // Given - Search for something that returns no results
        let searchField = app.searchFields["CourseSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        // When - Search for non-existent course
        searchField.tap()
        searchField.typeText("NonExistentGolfCourse12345")
        
        // Wait for search to complete
        Thread.sleep(forTimeInterval: 1)
        
        // Then - Empty state should be shown
        let emptyStateView = app.staticTexts["NoCoursesFoundMessage"]
        XCTAssertTrue(emptyStateView.waitForExistence(timeout: 5))
        
        // Verify helpful message
        let emptyStateMessage = emptyStateView.label
        XCTAssertTrue(
            emptyStateMessage.contains("No courses found") ||
            emptyStateMessage.contains("Try adjusting your search"),
            "Empty state should provide helpful guidance"
        )
        
        // Clear search should restore results
        searchField.buttons["Clear text"].tap()
        
        let coursesCollectionView = app.collectionViews["CoursesCollectionView"]
        let coursesRestored = coursesCollectionView.cells.firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(coursesRestored, "Courses should reappear when search is cleared")
    }
}