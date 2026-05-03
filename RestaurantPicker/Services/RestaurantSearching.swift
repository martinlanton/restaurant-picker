import CoreLocation
import MapKit

// MARK: - RestaurantSearching

/// Defines the contract for executing MapKit restaurant search batches.
///
/// Conforming types run `MKLocalSearch` requests and return raw
/// `(Restaurant, label)` pairs; deduplication is handled by the orchestrator
/// via `RestaurantSearchService.deduplicateAndSort(_:)`.
///
/// All methods are `async` so that callers always `await` across the
/// isolation boundary regardless of whether the conforming type is an actor.
///
/// ## Adoption
/// ```swift
/// actor MockSearchService: RestaurantSearching {
///     func executeFocusedBatch(...) async -> FocusedBatchResult { ... }
///     // ...
/// }
/// ```
protocol RestaurantSearching: AnyObject {
    /// Executes one batch of cuisine queries concurrently against a focused region.
    ///
    /// - Parameters:
    ///   - queries: `(query, label)` pairs to run in this batch.
    ///   - region: The `MKCoordinateRegion` to search within.
    ///   - location: User location used for distance calculation.
    ///   - networkRadius: Results beyond this distance (m) are discarded.
    /// - Returns: Results and the subset of queries that hit the per-query cap.
    func executeFocusedBatch(
        queries: [(query: String, label: String)],
        region: MKCoordinateRegion,
        location: CLLocation,
        networkRadius: Double
    ) async -> FocusedBatchResult

    /// Executes a POI-category search covering the wide region.
    ///
    /// - Parameters:
    ///   - region: Wide `MKCoordinateRegion` (typically sized to `networkRadius`).
    ///   - location: User location used for distance calculation.
    ///   - networkRadius: Results beyond this distance (m) are discarded.
    /// - Returns: Restaurant/label pairs discovered via POI categories.
    func executePOISearch(
        region: MKCoordinateRegion,
        location: CLLocation,
        networkRadius: Double
    ) async -> [(Restaurant, String)]

    /// Executes one level of scatter for a saturated node.
    ///
    /// - Parameters:
    ///   - node: The scatter node to process (query, centre, radius, depth).
    ///   - userLocation: User's actual location for distance calculation.
    ///   - maxRadius: Results beyond this distance (m) are discarded.
    /// - Returns: Results and child nodes for any saturated sub-regions.
    func executeScatterNode(
        _ node: ScatterNode,
        userLocation: CLLocation,
        maxRadius: Double
    ) async -> ScatterNodeResult

    /// Executes one batch of cuisine queries concurrently against the wide region.
    ///
    /// - Parameters:
    ///   - queries: `(query, label)` pairs to run in this batch.
    ///   - region: Wide `MKCoordinateRegion`.
    ///   - location: User location used for distance calculation.
    ///   - networkRadius: Results beyond this distance (m) are discarded.
    /// - Returns: Restaurant/label pairs discovered by this batch.
    func executeWideBatch(
        queries: [(query: String, label: String)],
        region: MKCoordinateRegion,
        location: CLLocation,
        networkRadius: Double
    ) async -> [(Restaurant, String)]

    /// Searches for restaurants matching specific cuisine labels.
    ///
    /// - Parameters:
    ///   - cuisineLabels: Labels to search for (e.g. `["Yakiniku"]`).
    ///   - location: The centre point for the search.
    ///   - radius: Search radius in metres.
    /// - Returns: Discovered restaurants sorted by distance.
    func searchCuisines(
        _ cuisineLabels: Set<String>,
        near location: CLLocation,
        radius: Double
    ) async -> [Restaurant]
}
