import CoreLocation
import MapKit
@testable import RestaurantPicker

/// A fully-controllable test double for `RestaurantSearching`.
///
/// All configurable return values are set via `await mock.set*(…)` before
/// the orchestrator is started so that there are no data races when the
/// orchestrator actor reads them during `async` calls.
actor MockRestaurantSearchService: RestaurantSearching {
    // MARK: - Configurable return values

    var focusedBatchResult: FocusedBatchResult =
        .init(results: [], saturatedQueries: [])

    var poiSearchResult: [(Restaurant, String)] = []

    var scatterNodeResult: ScatterNodeResult =
        .init(results: [], childNodes: [])

    var wideBatchResult: [(Restaurant, String)] = []

    var searchCuisinesResult: [Restaurant] = []

    // MARK: - Setters (called from test code outside the actor)

    func setPOISearchResult(_ result: [(Restaurant, String)]) {
        poiSearchResult = result
    }

    func setFocusedBatchResult(_ result: FocusedBatchResult) {
        focusedBatchResult = result
    }

    func setScatterNodeResult(_ result: ScatterNodeResult) {
        scatterNodeResult = result
    }

    func setWideBatchResult(_ result: [(Restaurant, String)]) {
        wideBatchResult = result
    }

    func setSearchCuisinesResult(_ result: [Restaurant]) {
        searchCuisinesResult = result
    }

    // MARK: - Call-count tracking

    private(set) var executeFocusedBatchCallCount = 0
    private(set) var executePOISearchCallCount = 0
    private(set) var executeScatterNodeCallCount = 0
    private(set) var executeWideBatchCallCount = 0
    private(set) var searchCuisinesCallCount = 0

    // MARK: - RestaurantSearching

    func executeFocusedBatch(
        queries: [(query: String, label: String)],
        region: MKCoordinateRegion,
        location: CLLocation,
        networkRadius: Double
    ) async -> FocusedBatchResult {
        executeFocusedBatchCallCount += 1
        return focusedBatchResult
    }

    func executePOISearch(
        region: MKCoordinateRegion,
        location: CLLocation,
        networkRadius: Double
    ) async -> [(Restaurant, String)] {
        executePOISearchCallCount += 1
        return poiSearchResult
    }

    func executeScatterNode(
        _ node: ScatterNode,
        userLocation: CLLocation,
        maxRadius: Double
    ) async -> ScatterNodeResult {
        executeScatterNodeCallCount += 1
        return scatterNodeResult
    }

    func executeWideBatch(
        queries: [(query: String, label: String)],
        region: MKCoordinateRegion,
        location: CLLocation,
        networkRadius: Double
    ) async -> [(Restaurant, String)] {
        executeWideBatchCallCount += 1
        return wideBatchResult
    }

    func searchCuisines(
        _ cuisineLabels: Set<String>,
        near location: CLLocation,
        radius: Double
    ) async -> [Restaurant] {
        searchCuisinesCallCount += 1
        return searchCuisinesResult
    }
}
