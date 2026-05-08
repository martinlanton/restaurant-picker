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
    // A second Paris location only ~0.05 m away — should NOT trigger a new search.
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

    func testSelectRandomRestaurantFailsWhenPickEligibleListIsEmpty() {
        // Covers all filter types that can eliminate restaurants from the pick pool:
        // distance, cuisine include, cuisine exclude, and minimum rating.
        // In each sub-case selectRandomRestaurant() must set an error and leave
        // showSelectedRestaurant false — the sheet must never open on an empty pool.

        // Sub-case A: distance filter eliminates the only restaurant.
        let vmA = RestaurantViewModel(
            restaurants: [makeSample(name: "Far Ramen", cuisine: "Japanese", distance: 5000)]
        )
        vmA.filterRadius = 1000
        XCTAssertTrue(vmA.pickEligibleRestaurants.isEmpty, "Pre-condition A: distance filter must eliminate all")
        vmA.selectRandomRestaurant()
        XCTAssertNotNil(vmA.errorMessage, "A: error must be set when pick pool is empty")
        XCTAssertFalse(vmA.showSelectedRestaurant, "A: sheet must not open")
        XCTAssertNil(vmA.selectedRestaurant, "A: no restaurant must be selected")

        // Sub-case B: cuisine include filter eliminates the only restaurant.
        let vmB = RestaurantViewModel(
            restaurants: [makeSample(name: "Pizza Shop", cuisine: "Italian")]
        )
        vmB.selectedCuisines = ["Japanese"]
        XCTAssertTrue(vmB.pickEligibleRestaurants.isEmpty, "Pre-condition B: include filter must eliminate all")
        vmB.selectRandomRestaurant()
        XCTAssertNotNil(vmB.errorMessage, "B: error must be set when pick pool is empty")
        XCTAssertFalse(vmB.showSelectedRestaurant, "B: sheet must not open")

        // Sub-case C: cuisine exclude filter eliminates the only restaurant.
        let vmC = RestaurantViewModel(
            restaurants: [makeSample(name: "Sushi Bar", cuisine: "Japanese")]
        )
        vmC.excludedCuisines = ["Japanese"]
        XCTAssertTrue(vmC.pickEligibleRestaurants.isEmpty, "Pre-condition C: exclude filter must eliminate all")
        vmC.selectRandomRestaurant()
        XCTAssertNotNil(vmC.errorMessage, "C: error must be set when pick pool is empty")
        XCTAssertFalse(vmC.showSelectedRestaurant, "C: sheet must not open")
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
        vm.excludedCuisines = ["FastFood"]         // +1
        vm.minimumRating = 3                       // +1

        XCTAssertEqual(vm.activeCuisineFilterCount, 4)
    }

    func testAllFilterTypesActiveWithMultipleExcludes() {
        let vm = makeVM()
        vm.selectedCuisines = ["Japanese"]           // +1
        vm.excludedCuisines = ["FastFood", "Pizza"]  // +2
        vm.minimumRating = 4                         // +1

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

// MARK: - Search Text Display-Only Tests

/// Tests that `searchText` only affects what is *displayed* in `filteredRestaurants`
/// and never gates the "Pick a Restaurant!" action: `pickEligibleRestaurants` and
/// `selectRandomRestaurant()` must be unaffected by search text.
@MainActor
final class SearchTextDisplayOnlyTests: XCTestCase {
    private func makeSample(name: String, cuisine: String = "Test") -> Restaurant {
        Restaurant(
            id: UUID(),
            name: name,
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 300,
            category: cuisine,
            cuisineTags: [cuisine],
            phoneNumber: nil,
            url: nil
        )
    }

    func testSearchTextFiltersDisplayListButNotPickPool() {
        // Arrange — two restaurants; search matches only one.
        let vm = RestaurantViewModel(
            restaurants: [
                makeSample(name: "Thai Palace", cuisine: "Thai"),
                makeSample(name: "Ramen House", cuisine: "Japanese"),
            ]
        )
        vm.filterRadius = nil

        // Act — type a query that only matches "Ramen House".
        vm.searchText = "ramen"

        // Assert: display list is narrowed to 1…
        XCTAssertEqual(vm.filteredRestaurants.count, 1, "Display list must respect search text")
        XCTAssertEqual(vm.filteredRestaurants.first?.name, "Ramen House")

        // …but pick pool still contains both restaurants.
        XCTAssertEqual(
            vm.pickEligibleRestaurants.count, 2,
            "Search text must not reduce the pick-eligible pool"
        )
    }

    func testSelectRandomRestaurantIgnoresSearchText() {
        // One restaurant is visible in the pick pool even when search text hides it
        // from the display list; selectRandomRestaurant() must still succeed.
        let vm = RestaurantViewModel(
            restaurants: [makeSample(name: "Sushi Corner", cuisine: "Japanese")]
        )
        vm.filterRadius = nil
        vm.searchText = "pizza" // hides the only restaurant from filteredRestaurants

        XCTAssertTrue(vm.filteredRestaurants.isEmpty, "Pre-condition: search hides restaurant from display")
        XCTAssertFalse(vm.pickEligibleRestaurants.isEmpty, "Pre-condition: pick pool must still contain restaurant")

        vm.selectRandomRestaurant()

        XCTAssertNotNil(vm.selectedRestaurant, "Must pick the restaurant even though search text hides it")
        XCTAssertTrue(vm.showSelectedRestaurant, "Sheet must be shown")
        XCTAssertNil(vm.errorMessage)
    }
}

// MARK: - Pick Button Eligibility Tests

/// Tests that `pickEligibleRestaurants` correctly reflects which restaurants
/// are available to the "Pick a Restaurant!" button after applying
/// distance, cuisine, and rating filters (but ignoring search text).
@MainActor
final class PickButtonEligibilityTests: XCTestCase {
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

    func testPickPoolIsEmptyWhenDistanceFilterEliminatesAll() {
        let vm = RestaurantViewModel(
            restaurants: [makeSample(name: "Far Thai", cuisine: "Thai", distance: 5000)]
        )
        vm.filterRadius = 1000
        XCTAssertTrue(vm.pickEligibleRestaurants.isEmpty, "Distance filter must empty the pick pool")
    }

    func testPickPoolIsEmptyWhenCuisineIncludeEliminatesAll() {
        let vm = RestaurantViewModel(
            restaurants: [makeSample(name: "Pizza Place", cuisine: "Italian")]
        )
        vm.selectedCuisines = ["Japanese"]
        XCTAssertTrue(vm.pickEligibleRestaurants.isEmpty, "Include filter must empty the pick pool")
    }

    func testPickPoolIsEmptyWhenCuisineExcludeEliminatesAll() {
        let vm = RestaurantViewModel(
            restaurants: [makeSample(name: "Sushi Bar", cuisine: "Japanese")]
        )
        vm.excludedCuisines = ["Japanese"]
        XCTAssertTrue(vm.pickEligibleRestaurants.isEmpty, "Exclude filter must empty the pick pool")
    }

    func testPickPoolRemainsNonEmptyWhenOnlySearchTextFiltersAll() {
        // Even when search text hides every restaurant from the display list,
        // the pick pool must remain non-empty so the button stays enabled.
        let vm = RestaurantViewModel(
            restaurants: [makeSample(name: "Thai Corner", cuisine: "Thai")]
        )
        vm.filterRadius = nil
        vm.searchText = "zzznomatch"

        XCTAssertTrue(vm.filteredRestaurants.isEmpty, "Pre-condition: search must hide all from display")
        XCTAssertFalse(
            vm.pickEligibleRestaurants.isEmpty,
            "Pick pool must remain non-empty when only search text filters restaurants out"
        )
    }
}

// MARK: - Cuisine Mutual Exclusivity Tests

/// Tests that when a cuisine is in both `selectedCuisines` and `excludedCuisines`
/// the exclude filter takes priority, keeping the restaurant out of the pick pool.
///
/// The UI (`CuisineFilterView.toggle()`) prevents this state from occurring
/// in normal use, but the ViewModel must behave predictably if it arises.
@MainActor
final class CuisineMutualExclusivityTests: XCTestCase {
    private func makeSample(name: String, cuisine: String) -> Restaurant {
        Restaurant(
            id: UUID(),
            name: name,
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 300,
            category: cuisine,
            cuisineTags: [cuisine],
            phoneNumber: nil,
            url: nil
        )
    }

    func testExcludeWinsWhenCuisineIsInBothSets() {
        // If a cuisine ends up in both sets (e.g. via programmatic mutation),
        // the exclude filter must take priority and the restaurant must be hidden.
        let vm = RestaurantViewModel(
            restaurants: [makeSample(name: "Ramen Bar", cuisine: "Japanese")]
        )
        vm.selectedCuisines = ["Japanese"]
        vm.excludedCuisines = ["Japanese"]

        XCTAssertTrue(
            vm.pickEligibleRestaurants.isEmpty,
            "Exclude must take priority over include when a cuisine is in both sets"
        )
        XCTAssertTrue(
            vm.filteredRestaurants.isEmpty,
            "Display list must also be empty when exclude wins"
        )
    }
}

// MARK: - Clear Selection (Pick Again) Tests

/// Tests that `clearSelection()` — called by the "Pick Again" and "Done"
/// buttons in `SelectedRestaurantView` — fully resets the selection state.
@MainActor
final class ClearSelectionTests: XCTestCase {
    private func makeSample(name: String) -> Restaurant {
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

    func testClearSelectionResetsShowSelectedRestaurantAndSelectedRestaurant() {
        // Arrange — pick a restaurant so the sheet is shown.
        let vm = RestaurantViewModel(
            restaurants: [makeSample(name: "Thai Palace")]
        )
        vm.filterRadius = nil
        vm.selectRandomRestaurant()
        XCTAssertTrue(vm.showSelectedRestaurant, "Pre-condition: sheet must be visible")
        XCTAssertNotNil(vm.selectedRestaurant, "Pre-condition: a restaurant must be selected")

        // Act — simulate "Pick Again" / "Done"
        vm.clearSelection()

        // Assert
        XCTAssertFalse(vm.showSelectedRestaurant, "clearSelection must hide the sheet")
        XCTAssertNil(vm.selectedRestaurant, "clearSelection must clear the selected restaurant")
    }

    func testClearSelectionIsIdempotent() {
        // Calling clearSelection() when nothing is selected must not crash or change state.
        let vm = RestaurantViewModel(restaurants: [])
        XCTAssertFalse(vm.showSelectedRestaurant)
        XCTAssertNil(vm.selectedRestaurant)

        vm.clearSelection()

        XCTAssertFalse(vm.showSelectedRestaurant)
        XCTAssertNil(vm.selectedRestaurant)
    }
}

// MARK: - Rejected Restaurant Pick Pool Tests

/// Tests that rejected restaurants (rating == 0) are excluded from `pickEligibleRestaurants`
/// but remain visible in `filteredRestaurants` — keeping the "Pick a Restaurant!" button
/// greyed out when every restaurant has been rejected, while still showing them in the list.
@MainActor
final class RejectedRestaurantPickPoolTests: XCTestCase {
    private let sampleRestaurants = [
        Restaurant(
            id: UUID(), name: "Thai Place",
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 300, category: "Thai", cuisineTags: ["Thai"], phoneNumber: nil, url: nil
        ),
        Restaurant(
            id: UUID(), name: "Pizza Shop",
            coordinate: .init(latitude: 40.7200, longitude: -74.0100),
            distance: 500, category: "Italian", cuisineTags: ["Italian"], phoneNumber: nil, url: nil
        ),
        Restaurant(
            id: UUID(), name: "Sushi Bar",
            coordinate: .init(latitude: 40.7300, longitude: -74.0200),
            distance: 700, category: "Japanese", cuisineTags: ["Japanese"], phoneNumber: nil, url: nil
        ),
    ]

    private func makeTestDefaults() -> UserDefaults {
        let suite = "RejectedRestaurantPickPoolTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? UserDefaults.standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testAllRejectedEmptiesPickPool() {
        // Arrange
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let vm = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)

        for restaurant in sampleRestaurants {
            ratingStore.setRating(0, for: restaurant)
        }

        // Act — trigger applyFilter with no rating filter active
        vm.filterRadius = nil

        // Assert — pick pool empty so button greys out
        XCTAssertTrue(vm.pickEligibleRestaurants.isEmpty, "All-rejected list must produce an empty pick pool")
    }

    func testAllRejectedRestaurantsStillVisibleInDisplayList() {
        // Rejected restaurants must remain in filteredRestaurants so users can
        // review and change their ratings.
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let vm = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)

        for restaurant in sampleRestaurants {
            ratingStore.setRating(0, for: restaurant)
        }

        vm.filterRadius = nil

        XCTAssertEqual(
            vm.filteredRestaurants.count, sampleRestaurants.count,
            "Rejected restaurants must still appear in the display list"
        )
    }

    func testMixedRejectedAndRatedExcludesRejectedFromPickPool() {
        // Arrange — one rejected, one rated, one unrated
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let vm = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)

        ratingStore.setRating(0, for: sampleRestaurants[0]) // Thai — rejected
        ratingStore.setRating(4, for: sampleRestaurants[1]) // Pizza — 4 stars
        // Sushi — unrated (nil)

        vm.filterRadius = nil

        // Assert pick pool: Pizza + Sushi, not Thai
        XCTAssertEqual(vm.pickEligibleRestaurants.count, 2)
        let pickNames = Set(vm.pickEligibleRestaurants.map(\.name))
        XCTAssertFalse(pickNames.contains("Thai Place"), "Rejected restaurant must not be in pick pool")
        XCTAssertTrue(pickNames.contains("Pizza Shop"))
        XCTAssertTrue(pickNames.contains("Sushi Bar"))

        // Assert display list: all three visible
        XCTAssertEqual(vm.filteredRestaurants.count, 3)
    }

    func testRejectedRestaurantExcludedFromPickPoolPreventsPick() {
        // When only one restaurant exists and it is rejected, selectRandomRestaurant
        // must set an error and not show the selection sheet.
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let vm = RestaurantViewModel(restaurants: [sampleRestaurants[0]], ratingStore: ratingStore)
        ratingStore.setRating(0, for: sampleRestaurants[0])
        vm.filterRadius = nil

        vm.selectRandomRestaurant()

        XCTAssertNil(vm.selectedRestaurant)
        XCTAssertFalse(vm.showSelectedRestaurant, "Sheet must not open when pick pool is empty")
        XCTAssertNotNil(vm.errorMessage)
    }

    func testExplicitRatingFilterStillExcludesRejectedNormally() {
        // When minimumRating is set, passesRatingFilter already excludes rejected.
        // Verify the two exclusion paths don't conflict.
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let vm = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)

        ratingStore.setRating(0, for: sampleRestaurants[0]) // rejected
        ratingStore.setRating(4, for: sampleRestaurants[1])
        ratingStore.setRating(3, for: sampleRestaurants[2])

        vm.filterRadius = nil
        vm.minimumRating = 3

        // Rating filter path: rejected fails passesRatingFilter (0 < 3), so it's
        // excluded from baseFiltered and therefore from both lists.
        XCTAssertFalse(vm.filteredRestaurants.contains { $0.name == "Thai Place" })
        XCTAssertFalse(vm.pickEligibleRestaurants.contains { $0.name == "Thai Place" })
        XCTAssertEqual(vm.pickEligibleRestaurants.count, 2)
    }
}

// MARK: - Location Resolution Tests

/// Tests that `fetchNearbyRestaurants()` sets the correct user-visible error messages
/// for each location failure mode, and that `isLoading` always returns to `false`.
@MainActor
final class LocationResolutionTests: XCTestCase {
    func testDeniedLocationSetsDeniedErrorMessage() async {
        // Arrange
        let locationManager = MockLocationManager()
        locationManager.authorizationStatus = .denied
        let vm = RestaurantViewModel(
            locationManager: locationManager,
            searchService: MockRestaurantSearchService()
        )

        // Act — awaiting the call lets the function's internal guard run synchronously
        await vm.fetchNearbyRestaurants()

        // Assert
        XCTAssertEqual(
            vm.errorMessage,
            "Location access denied. Please enable location services in Settings."
        )
        XCTAssertFalse(vm.isLoading, "isLoading must be false after a failed fetch")
    }

    func testNotDeterminedLocationSetsNotAuthorizedMessage() async {
        // Arrange — mock never changes status after requestAuthorization(), so after
        // the 500 ms authorization wait the status is still notDetermined.
        let locationManager = MockLocationManager()
        locationManager.authorizationStatus = .notDetermined
        let vm = RestaurantViewModel(
            locationManager: locationManager,
            searchService: MockRestaurantSearchService()
        )

        // Act — waits ~500 ms internally for authorization to arrive
        await vm.fetchNearbyRestaurants()

        // Assert
        XCTAssertEqual(vm.errorMessage, "Location access not yet authorized.")
        XCTAssertFalse(vm.isLoading, "isLoading must be false after a failed fetch")
    }

    func testAuthorizedButNoGPSFixSetsUnableToLocateMessage() async {
        // Arrange — authorized but currentLocation stays nil (mock never calls back)
        let locationManager = MockLocationManager()
        locationManager.authorizationStatus = .authorizedWhenInUse
        locationManager.currentLocation = nil
        let vm = RestaurantViewModel(
            locationManager: locationManager,
            searchService: MockRestaurantSearchService()
        )

        // Act — waits ~2 s internally for a GPS fix
        await vm.fetchNearbyRestaurants()

        // Assert
        XCTAssertEqual(vm.errorMessage, "Unable to determine your location.")
        XCTAssertFalse(vm.isLoading, "isLoading must be false after a failed fetch")
    }
}

// MARK: - Cache Hit Loading State Tests

/// Tests that a cache hit in `fetchNearbyRestaurants()` immediately clears both
/// loading indicators without enqueueing a new search job.
@MainActor
final class CacheHitLoadingStateTests: XCTestCase {
    private let newYork = CLLocation(latitude: 40.7128, longitude: -74.0060)

    private func makeRestaurant(name: String) -> Restaurant {
        Restaurant(
            id: UUID(), name: name,
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 300, category: "Test", cuisineTags: ["Test"], phoneNumber: nil, url: nil
        )
    }

    func testCacheHitSetsLoadingStatesToFalseImmediately() async {
        // Arrange — seed the cache by completing a job.
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        let vm = RestaurantViewModel(
            locationManager: locationManager,
            searchService: MockRestaurantSearchService()
        )
        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.isLoading = true
        vm.handleOrchestratorUpdate(OrchestratorUpdate(
            jobID: jobID,
            location: newYork,
            snapshot: [makeRestaurant(name: "Thai Place")],
            isJobComplete: true
        ))
        XCTAssertEqual(vm.restaurants.count, 1, "Pre-condition: cache must be seeded")

        // Act — second fetch for the same location should hit the cache.
        await vm.fetchNearbyRestaurants()

        // Assert — no spinner: cache hit path clears both flags immediately.
        XCTAssertFalse(vm.isLoading, "isLoading must be false on a cache hit")
        XCTAssertFalse(vm.isLoadingMore, "isLoadingMore must be false on a cache hit")
        XCTAssertEqual(vm.restaurants.count, 1, "Cached restaurants must be preserved")
    }

    func testCacheHitPreservesJobIDUnchanged() async {
        // A cache hit must not enqueue a new orchestrator job — the jobID stays the same.
        let locationManager = MockLocationManager()
        locationManager.currentLocation = newYork
        let vm = RestaurantViewModel(
            locationManager: locationManager,
            searchService: MockRestaurantSearchService()
        )
        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.isLoading = true
        vm.handleOrchestratorUpdate(OrchestratorUpdate(
            jobID: jobID,
            location: newYork,
            snapshot: [makeRestaurant(name: "Thai Place")],
            isJobComplete: true
        ))

        await vm.fetchNearbyRestaurants()

        XCTAssertEqual(
            vm.currentSearchJobID, jobID,
            "Cache hit must not replace the current search job ID"
        )
    }
}
