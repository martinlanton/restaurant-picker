import Combine
import CoreLocation
@testable import RestaurantPicker
import XCTest

// MARK: - Refresh Cache Invalidation Tests

/// Tests that `refresh()` invalidates the current-location cache and that
/// caches for other locations are left untouched.
@MainActor
final class RefreshCacheTests: XCTestCase {
    private let newYork = CLLocation(latitude: 40.7128, longitude: -74.0060)

    private func makeRestaurant(name: String) -> Restaurant {
        Restaurant(
            id: UUID(),
            name: name,
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 300,
            category: "Test",
            cuisineTags: ["Test"],
            phoneNumber: nil,
            url: nil
        )
    }

    private struct RefreshTestContext {
        let vm: RestaurantViewModel
        let locationManager: MockLocationManager
        let searchService: MockRestaurantSearchService
    }

    private func makeViewModel(at location: CLLocation) -> RefreshTestContext {
        let locationManager = MockLocationManager()
        locationManager.currentLocation = location
        let searchService = MockRestaurantSearchService()
        let vm = RestaurantViewModel(locationManager: locationManager, searchService: searchService)
        return RefreshTestContext(vm: vm, locationManager: locationManager, searchService: searchService)
    }

    // MARK: - Tests

    func testRefreshClearsCurrentLocationCacheSoNextFetchEnqueuesNewJob() async {
        // Arrange — seed the ViewModel with a completed job so the cache is populated.
        let ctx = makeViewModel(at: newYork)
        let vm = ctx.vm
        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.isLoading = true
        let snapshot = [makeRestaurant(name: "Thai Place")]
        vm.handleOrchestratorUpdate(
            OrchestratorUpdate(
                jobID: jobID,
                location: newYork,
                snapshot: snapshot,
                isJobComplete: true
            )
        )
        XCTAssertEqual(vm.restaurants.count, 1, "Pre-condition: cache should be seeded")

        // Act — refresh clears the cache; the next fetch must enqueue a new job.
        let previousJobID = vm.currentSearchJobID
        await vm.refresh()

        // Assert — currentSearchJobID changed, confirming a new search was started.
        XCTAssertNotEqual(
            vm.currentSearchJobID, previousJobID,
            "refresh() must enqueue a new search job, not reuse the old one"
        )
    }

    func testRefreshDoesNotDoubleEnqueue() async {
        // After refresh(), the pending job should not be immediately replaced
        // by a second enqueue if nothing else triggered a fetch.
        let ctx = makeViewModel(at: newYork)
        let vm = ctx.vm
        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.isLoading = true
        vm.handleOrchestratorUpdate(
            OrchestratorUpdate(
                jobID: jobID,
                location: newYork,
                snapshot: [makeRestaurant(name: "Thai Place")],
                isJobComplete: true
            )
        )

        await vm.refresh()
        let jobIDAfterRefresh = vm.currentSearchJobID

        // A second observation of the same state should not produce a new job.
        let jobIDSecondObservation = vm.currentSearchJobID
        XCTAssertEqual(
            jobIDAfterRefresh, jobIDSecondObservation,
            "A second read of currentSearchJobID must not change it"
        )
    }
}

// MARK: - Location Override Triggering Search Tests

/// Tests that changing `overrideLocation` on the `LocationManaging` dependency
/// causes `RestaurantViewModel` to kick off a new search automatically.
@MainActor
final class LocationOverrideTests: XCTestCase {
    private let newYork = CLLocation(latitude: 40.7128, longitude: -74.0060)
    private let london = CLLocation(latitude: 51.5074, longitude: -0.1278)
    private let parisTiny = CLLocation(latitude: 48.8566, longitude: 2.3522)
    /// A second Paris location only ~0.05 m away — should NOT trigger a new search.
    private let parisTinyJitter = CLLocation(latitude: 48.85660045, longitude: 2.3522)

    func testSettingOverrideLocationTriggersNewSearch() async {
        // Arrange
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        let searchService = MockRestaurantSearchService()
        let vm = RestaurantViewModel(locationManager: locationManager, searchService: searchService)
        let originalJobID = vm.currentSearchJobID

        // Act — simulates user dropping a map pin
        locationManager.setOverrideLocation(london)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertNotEqual(
            vm.currentSearchJobID, originalJobID,
            "Setting an override location must trigger a new search"
        )
    }

    func testClearingOverrideLocationTriggersNewSearch() async {
        // Arrange — start with an override already set.
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        locationManager.setOverrideLocation(london)
        let searchService = MockRestaurantSearchService()
        let vm = RestaurantViewModel(locationManager: locationManager, searchService: searchService)

        // Let the initial override-triggered search settle.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let jobIDWithOverride = vm.currentSearchJobID

        // Act — simulates user removing the map pin
        locationManager.clearOverrideLocation()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertNotEqual(
            vm.currentSearchJobID, jobIDWithOverride,
            "Clearing the override location must trigger a new search using the GPS location"
        )
    }

    func testTinyJitterInOverrideLocationDoesNotTriggerNewSearch() async {
        // Arrange — VM created with no override so the CurrentValueSubject initial
        // emit (nil) is what dropFirst() drops. The first *real* setOverrideLocation
        // call is then seen by removeDuplicates as the "previous" value.
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        let searchService = MockRestaurantSearchService()
        let vm = RestaurantViewModel(locationManager: locationManager, searchService: searchService)

        // Set the first override → passes through removeDuplicates (no previous to compare).
        locationManager.setOverrideLocation(parisTiny)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let jobIDAfterFirstOverride = vm.currentSearchJobID

        // Act — update override to a location <1 m away (jitter).
        // removeDuplicates now compares parisTiny → parisTinyJitter: distance < 1 m → suppressed.
        locationManager.setOverrideLocation(parisTinyJitter)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Assert — job ID must not change.
        XCTAssertEqual(
            vm.currentSearchJobID, jobIDAfterFirstOverride,
            "A sub-metre location change must not trigger a redundant search"
        )
    }
}

// MARK: - selectRandomRestaurant Edge Cases Tests

/// Tests for `selectRandomRestaurant()` focusing on the filtered-list-empty branch
/// and the `showSelectedRestaurant` flag lifecycle.
@MainActor
final class SelectRandomRestaurantEdgeCaseTests: XCTestCase {
    private func makeSample(name: String, cuisine: String, distance: Double = 300) -> Restaurant {
        Restaurant(
            id: UUID(),
            name: name,
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: distance,
            category: cuisine,
            cuisineTags: [cuisine],
            phoneNumber: nil,
            url: nil
        )
    }

    func testSelectRandomRestaurantSetsErrorWhenFilteredListIsEmpty() {
        // Arrange — one restaurant at 5 km; distance filter set to 1 km.
        let vm = RestaurantViewModel(
            restaurants: [makeSample(name: "Far Ramen", cuisine: "Japanese", distance: 5000)]
        )
        vm.filterRadius = 1000 // filters out the only restaurant
        XCTAssertTrue(vm.filteredRestaurants.isEmpty, "Pre-condition: filtered list must be empty")

        // Act
        vm.selectRandomRestaurant()

        // Assert
        XCTAssertNotNil(vm.errorMessage, "An error message must be set when no restaurants are available")
        XCTAssertFalse(vm.showSelectedRestaurant, "Sheet must not be shown when selection fails")
        XCTAssertNil(vm.selectedRestaurant, "No restaurant should be selected")
    }

    func testSelectRandomRestaurantSetsShowSelectedRestaurantOnSuccess() {
        // Arrange
        let vm = RestaurantViewModel(
            restaurants: [makeSample(name: "Thai Place", cuisine: "Thai")]
        )
        vm.filterRadius = nil

        // Act
        vm.selectRandomRestaurant()

        // Assert
        XCTAssertTrue(vm.showSelectedRestaurant, "Sheet must be shown after a successful pick")
        XCTAssertNotNil(vm.selectedRestaurant)
        XCTAssertNil(vm.errorMessage)
    }

    func testSelectRandomRestaurantAfterCuisineFilterEliminatesAll() {
        // Arrange
        let vm = RestaurantViewModel(
            restaurants: [makeSample(name: "Pizza Shop", cuisine: "Italian")]
        )
        vm.selectedCuisines = ["Japanese"] // filters out the only restaurant
        XCTAssertTrue(vm.filteredRestaurants.isEmpty, "Pre-condition: cuisine filter must eliminate all restaurants")

        // Act
        vm.selectRandomRestaurant()

        // Assert
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.showSelectedRestaurant)
    }

    func testShowSelectedRestaurantRemainsAfterFilterChange() {
        // Arrange
        let vm = RestaurantViewModel(
            restaurants: [
                makeSample(name: "Near Thai", cuisine: "Thai", distance: 200),
                makeSample(name: "Far Thai", cuisine: "Thai", distance: 2000),
            ]
        )
        vm.selectRandomRestaurant()
        XCTAssertTrue(vm.showSelectedRestaurant, "Pre-condition: restaurant selected")

        // Act — changing a filter must not dismiss the sheet
        vm.filterRadius = 5000

        // Assert
        XCTAssertTrue(
            vm.showSelectedRestaurant,
            "Changing a filter must not dismiss the selected-restaurant sheet"
        )
    }
}

// MARK: - Cuisine-Specific Fetch Trigger Tests

/// Tests that selecting a cuisine causes `searchCuisines` to be called on the
/// search service for the matching cuisine labels.
@MainActor
final class CuisineSpecificFetchTests: XCTestCase {
    private let newYork = CLLocation(latitude: 40.7128, longitude: -74.0060)

    func testSelectingCuisineCallsSearchCuisines() async {
        // Arrange
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        let searchService = MockRestaurantSearchService()
        let vm = RestaurantViewModel(locationManager: locationManager, searchService: searchService)

        // Act
        vm.selectedCuisines = ["Japanese"]
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Assert
        let callCount = await searchService.searchCuisinesCallCount
        XCTAssertGreaterThanOrEqual(callCount, 1, "searchCuisines must be called when a cuisine is selected")
    }

    func testSelectingEmptyCuisineSetDoesNotCallSearchCuisines() async {
        // Arrange
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        let searchService = MockRestaurantSearchService()
        let vm = RestaurantViewModel(locationManager: locationManager, searchService: searchService)

        vm.selectedCuisines = ["Japanese"]
        try? await Task.sleep(nanoseconds: 50_000_000)
        let countAfterSelect = await searchService.searchCuisinesCallCount

        // Act — clearing must NOT trigger a cuisine search
        vm.selectedCuisines = []
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        let countAfterClear = await searchService.searchCuisinesCallCount
        XCTAssertEqual(countAfterSelect, countAfterClear, "Clearing cuisines must not trigger searchCuisines")
    }

    func testCuisineSearchResultsMergeIntoRestaurantList() async {
        // Arrange
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        let searchService = MockRestaurantSearchService()
        let ramen = Restaurant(
            id: UUID(),
            name: "Ramen Bar",
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 300,
            category: "Japanese",
            cuisineTags: ["Japanese"],
            phoneNumber: nil,
            url: nil
        )
        await searchService.setSearchCuisinesResult([ramen])
        let vm = RestaurantViewModel(locationManager: locationManager, searchService: searchService)

        // Act
        vm.selectedCuisines = ["Japanese"]
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Assert
        XCTAssertTrue(
            vm.restaurants.contains { $0.name == "Ramen Bar" },
            "Results from searchCuisines must be merged into the restaurant list"
        )
    }
}

// MARK: - Background Prefetch Scheduling Tests

/// Tests that `handleOrchestratorUpdate` with `isJobComplete: true` causes
/// background prefetch jobs to be scheduled for uncached, larger radii.
@MainActor
final class BackgroundPrefetchSchedulingTests: XCTestCase {
    private let newYork = CLLocation(latitude: 40.7128, longitude: -74.0060)

    private func makeRestaurant(name: String) -> Restaurant {
        Restaurant(
            id: UUID(),
            name: name,
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 300,
            category: "Test",
            cuisineTags: ["Test"],
            phoneNumber: nil,
            url: nil
        )
    }

    func testCompletingJobAt500mProducesCleanLoadingState() async {
        // Arrange
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        let searchService = MockRestaurantSearchService()
        let vm = RestaurantViewModel(locationManager: locationManager, searchService: searchService)
        vm.filterRadius = 500

        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.isLoading = true

        // Act
        vm.handleOrchestratorUpdate(
            OrchestratorUpdate(
                jobID: jobID,
                location: newYork,
                snapshot: [makeRestaurant(name: "Thai")],
                isJobComplete: true
            )
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Assert — loading flags cleared, no error
        XCTAssertFalse(vm.isLoadingMore, "isLoadingMore must be false after job completes")
        XCTAssertNil(vm.errorMessage)
    }

    func testCompletingJobWithMaxRadiusProducesCleanLoadingState() async {
        // filterRadius = 5000 m — no larger radius to prefetch
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        let searchService = MockRestaurantSearchService()
        let vm = RestaurantViewModel(locationManager: locationManager, searchService: searchService)
        vm.filterRadius = 5000

        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.isLoading = true

        vm.handleOrchestratorUpdate(
            OrchestratorUpdate(
                jobID: jobID,
                location: newYork,
                snapshot: [makeRestaurant(name: "Thai")],
                isJobComplete: true
            )
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isLoadingMore)
        XCTAssertNil(vm.errorMessage)
    }

    func testCompletingJobWithNilFilterRadiusProducesCleanLoadingState() async {
        // filterRadius == nil uses 500 m as base; radii 1000, 2000, 5000 are prefetched
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        let searchService = MockRestaurantSearchService()
        let vm = RestaurantViewModel(locationManager: locationManager, searchService: searchService)
        vm.filterRadius = nil

        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.isLoading = true

        vm.handleOrchestratorUpdate(
            OrchestratorUpdate(
                jobID: jobID,
                location: newYork,
                snapshot: [makeRestaurant(name: "Thai")],
                isJobComplete: true
            )
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }
}

// MARK: - ActiveFilterCount Exhaustive Tests

/// Tests that `activeCuisineFilterCount` correctly sums every combination of
/// active filter types and decrements by exactly 1 when each is removed.
@MainActor
final class ActiveFilterCountExhaustiveTests: XCTestCase {
    private func makeVM() -> RestaurantViewModel {
        RestaurantViewModel(restaurants: [])
    }

    // MARK: - All filter types active simultaneously

    func testAllFilterTypesActiveProduceCorrectSum() {
        let vm = makeVM()
        vm.selectedCuisines = ["Japanese", "Thai"] // +2
        vm.excludedCuisines = ["FastFood"] // +1
        vm.minimumRating = 3 // +1

        XCTAssertEqual(vm.activeCuisineFilterCount, 4)
    }

    func testAllFilterTypesActiveWithMultipleExcludes() {
        let vm = makeVM()
        vm.selectedCuisines = ["Japanese"] // +1
        vm.excludedCuisines = ["FastFood", "Pizza"] // +2
        vm.minimumRating = 4 // +1

        XCTAssertEqual(vm.activeCuisineFilterCount, 4)
    }

    // MARK: - Removing each filter type decrements count by exactly 1

    func testRemovingIncludeCuisineDecrementsCountByOne() {
        let vm = makeVM()
        vm.selectedCuisines = ["Japanese", "Thai"]
        vm.excludedCuisines = ["FastFood"]
        vm.minimumRating = 3
        let before = vm.activeCuisineFilterCount

        vm.selectedCuisines = ["Japanese"]

        XCTAssertEqual(vm.activeCuisineFilterCount, before - 1)
    }

    func testRemovingAllIncludeCuisinesDecrementsCountByCorrectAmount() {
        let vm = makeVM()
        vm.selectedCuisines = ["Japanese", "Thai"]
        vm.excludedCuisines = ["FastFood"]
        vm.minimumRating = 3
        let before = vm.activeCuisineFilterCount // 4

        vm.selectedCuisines = []

        XCTAssertEqual(vm.activeCuisineFilterCount, before - 2)
    }

    func testRemovingExcludeCuisineDecrementsCountByOne() {
        let vm = makeVM()
        vm.selectedCuisines = ["Japanese"]
        vm.excludedCuisines = ["FastFood", "Pizza"]
        vm.minimumRating = 3
        let before = vm.activeCuisineFilterCount

        vm.excludedCuisines = ["FastFood"]

        XCTAssertEqual(vm.activeCuisineFilterCount, before - 1)
    }

    func testRemovingRatingFilterDecrementsCountByOne() {
        let vm = makeVM()
        vm.selectedCuisines = ["Japanese"]
        vm.excludedCuisines = ["FastFood"]
        vm.minimumRating = 3
        let before = vm.activeCuisineFilterCount

        vm.minimumRating = nil

        XCTAssertEqual(vm.activeCuisineFilterCount, before - 1)
    }

    func testClearingAllFiltersProducesZeroCount() {
        let vm = makeVM()
        vm.selectedCuisines = ["Japanese", "Thai"]
        vm.excludedCuisines = ["FastFood"]
        vm.minimumRating = 5

        vm.selectedCuisines = []
        vm.excludedCuisines = []
        vm.minimumRating = nil

        XCTAssertEqual(vm.activeCuisineFilterCount, 0)
    }
}
