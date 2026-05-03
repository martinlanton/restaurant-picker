import CoreLocation
import MapKit

// MARK: - ScatterNode

/// A pending scatter-search node pairing a cuisine query with a geographic
/// sub-region to explore.
///
/// Produced by `executeScatterNode` when a child region is saturated.
/// Stored in `SearchJob.pendingScatterNodes` by the orchestrator.
struct ScatterNode {
    /// The MapKit natural-language query string (e.g. `"ramen restaurant"`).
    let query: String
    /// The human-readable cuisine label (e.g. `"Ramen"`).
    let label: String
    /// Geographic centre of the sub-region.
    let centre: CLLocationCoordinate2D
    /// Scatter radius in metres.
    let radius: Double
    /// Recursion depth (capped at `RestaurantSearchService.maxScatterDepth`).
    let depth: Int
}

// MARK: - FocusedBatchResult

/// Result of executing one focused-query batch via `executeFocusedBatch`.
struct FocusedBatchResult {
    /// Restaurant/label pairs returned by the batch.
    let results: [(Restaurant, String)]
    /// Queries whose raw result count hit `RestaurantSearchService.mkLocalSearchResultCap`,
    /// indicating the area is saturated and scatter should be enqueued.
    let saturatedQueries: [(query: String, label: String)]
}

// MARK: - ScatterNodeResult

/// Result of executing one scatter node via `executeScatterNode`.
struct ScatterNodeResult {
    /// Restaurant/label pairs returned by the cardinal + diagonal searches.
    let results: [(Restaurant, String)]
    /// Child nodes for saturated sub-regions that require further scatter.
    let childNodes: [ScatterNode]
}
