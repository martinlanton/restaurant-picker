import CoreLocation
import Foundation
import MapKit

/// Service for searching restaurants using Apple MapKit.
///
/// This service exposes atomic batch-execution primitives that are driven by
/// `SearchOrchestrator`. Each primitive runs one `withTaskGroup` batch of
/// `MKLocalSearch` requests and returns immediately — allowing the orchestrator
/// to interleave work across multiple locations without cancelling in-flight
/// requests.
///
/// ## Primitives
/// - `executeFocusedBatch` — runs a slice of cuisine queries against a focused region.
/// - `executePOISearch` — runs a single POI-category search over the wide region.
/// - `executeScatterNode` — runs one level of cardinal + diagonal scatter for a
///   saturated node, returning child nodes for further scatter.
/// - `executeWideBatch` — runs a slice of cuisine queries against the wide region.
///
/// ## Usage
/// ```swift
/// let service = RestaurantSearchService()
/// let result = await service.executeFocusedBatch(
///     queries: RestaurantSearchService.cuisineQueries,
///     region: focusedRegion,
///     location: userLocation,
///     networkRadius: 10_000
/// )
/// ```
actor RestaurantSearchService: RestaurantSearching {
    // MARK: - Errors

    /// Errors that can occur during restaurant search.
    enum SearchError: LocalizedError {
        case searchFailed(underlying: Error)
        case noResults

        var errorDescription: String? {
            switch self {
            case let .searchFailed(error):
                "Search failed: \(error.localizedDescription)"
            case .noResults:
                "No restaurants found in this area."
            }
        }
    }

    // MARK: - Search Queries

    /// Cuisine-specific queries used to discover more restaurants.
    ///
    /// `MKLocalSearch` returns a maximum of ~25 results per query.
    /// By searching for many cuisine types in parallel, we can discover
    /// hundreds of unique restaurants in the same area.
    static let cuisineQueries: [(query: String, label: String)] = [
        // MARK: Priority 1 — Universal high-yield (first batch)

        // These queries return results almost anywhere in the world.
        ("restaurant", "Restaurant"),
        ("cafe restaurant", "Café"),
        ("bakery", "Bakery"),
        ("pizza restaurant", "Pizza"),
        ("burger restaurant", "Burger"),
        ("sushi restaurant", "Sushi"),
        ("ramen restaurant", "Ramen"),
        ("chinese restaurant", "Chinese"),
        ("italian restaurant", "Italian"),
        ("thai restaurant", "Thai"),
        ("indian restaurant", "Indian"),
        ("mexican restaurant", "Mexican"),
        ("japanese restaurant", "Japanese"),
        ("korean restaurant", "Korean"),
        ("seafood restaurant", "Seafood"),

        // MARK: Priority 2 — Common global cuisines

        ("french restaurant", "French"),
        ("american restaurant", "American"),
        ("vietnamese restaurant", "Vietnamese"),
        ("greek restaurant", "Greek"),
        ("mediterranean restaurant", "Mediterranean"),
        ("bbq restaurant", "BBQ"),
        ("steakhouse", "Steakhouse"),
        ("curry restaurant", "Curry"),
        ("noodle restaurant", "Noodle"),
        ("sandwich shop", "Sandwich"),
        ("fried chicken restaurant", "Fried Chicken"),
        ("vegetarian restaurant", "Vegetarian"),
        ("vegan restaurant", "Vegan"),
        ("breakfast restaurant", "Breakfast"),
        ("brunch restaurant", "Brunch"),
        ("ice cream shop", "Ice Cream"),
        ("dessert restaurant", "Dessert"),
        ("kebab restaurant", "Kebab"),
        ("middle eastern restaurant", "Middle Eastern"),
        ("spanish restaurant", "Spanish"),
        ("family restaurant", "Family Restaurant"),
        ("food court", "Food Court"),

        // MARK: Priority 3 — Regional favourites

        ("pasta restaurant", "Pasta"),
        ("dim sum restaurant", "Dim Sum"),
        ("pho restaurant", "Pho"),
        ("lebanese restaurant", "Lebanese"),
        ("turkish restaurant", "Turkish"),
        ("tapas restaurant", "Tapas"),
        ("german restaurant", "German"),
        ("british restaurant", "British"),
        ("pub", "Pub"),
        ("deli", "Deli"),
        ("diner", "Diner"),
        ("yakiniku restaurant", "Yakiniku"),
        ("izakaya", "Izakaya"),
        ("udon restaurant", "Udon"),
        ("tonkatsu restaurant", "Tonkatsu"),
        ("tempura restaurant", "Tempura"),
        ("korean bbq restaurant", "Korean BBQ"),
        ("shawarma restaurant", "Shawarma"),
        ("falafel restaurant", "Falafel"),
        ("halal restaurant", "Halal"),
        ("fish and chips restaurant", "Fish & Chips"),
        ("tacos restaurant", "Tacos"),
        ("tex-mex restaurant", "Tex-Mex"),
        ("wings restaurant", "Wings"),
        ("hot dog restaurant", "Hot Dog"),
        ("donut shop", "Donuts"),
        ("smoothie juice bar", "Juice Bar"),

        // MARK: Priority 4 — Specific regional cuisines

        ("yakitori restaurant", "Yakitori"),
        ("shabu-shabu restaurant", "Shabu-Shabu"),
        ("soba restaurant", "Soba"),
        ("teppanyaki restaurant", "Teppanyaki"),
        ("okonomiyaki restaurant", "Okonomiyaki"),
        ("takoyaki restaurant", "Takoyaki"),
        ("gyudon restaurant", "Gyudon"),
        ("donburi restaurant", "Donburi"),
        ("cantonese restaurant", "Cantonese"),
        ("szechuan restaurant", "Szechuan"),
        ("hotpot restaurant", "Hotpot"),
        ("dumpling restaurant", "Dumpling"),
        ("korean fried chicken restaurant", "Korean Fried Chicken"),
        ("banh mi restaurant", "Bánh Mì"),
        ("biryani restaurant", "Biryani"),
        ("filipino restaurant", "Filipino"),
        ("indonesian restaurant", "Indonesian"),
        ("malaysian restaurant", "Malaysian"),
        ("singaporean restaurant", "Singaporean"),
        ("taiwanese restaurant", "Taiwanese"),
        ("boba tea", "Boba Tea"),
        ("persian restaurant", "Persian"),
        ("israeli restaurant", "Israeli"),
        ("egyptian restaurant", "Egyptian"),
        ("moroccan restaurant", "Moroccan"),
        ("ethiopian restaurant", "Ethiopian"),
        ("south african restaurant", "South African"),
        ("african restaurant", "African"),
        ("irish restaurant", "Irish"),
        ("portuguese restaurant", "Portuguese"),
        ("brazilian restaurant", "Brazilian"),
        ("peruvian restaurant", "Peruvian"),
        ("caribbean restaurant", "Caribbean"),
        ("hawaiian restaurant", "Hawaiian"),
        ("poke restaurant", "Poke"),
        ("cajun restaurant", "Cajun"),
        ("creole restaurant", "Creole"),
        ("soul food restaurant", "Soul Food"),
        ("wine bar", "Wine Bar"),
        ("gastropub", "Gastropub"),
        ("creperie", "Crêperie"),

        // MARK: Priority 5 — Niche / location-specific

        ("washoku restaurant", "Washoku"),
        ("kaiseki restaurant", "Kaiseki"),
        ("kushikatsu restaurant", "Kushikatsu"),
        ("yoshoku restaurant", "Yoshoku"),
        ("nepali restaurant", "Nepali"),
        ("pakistani restaurant", "Pakistani"),
        ("sri lankan restaurant", "Sri Lankan"),
        ("tibetan restaurant", "Tibetan"),
        ("afghan restaurant", "Afghan"),
        ("scandinavian restaurant", "Scandinavian"),
        ("polish restaurant", "Polish"),
        ("hungarian restaurant", "Hungarian"),
        ("austrian restaurant", "Austrian"),
        ("swiss restaurant", "Swiss"),
        ("fondue restaurant", "Fondue"),
        ("belgian restaurant", "Belgian"),
        ("dutch restaurant", "Dutch"),
        ("georgian restaurant", "Georgian"),
        ("russian restaurant", "Russian"),
        ("colombian restaurant", "Colombian"),
        ("argentinian restaurant", "Argentinian"),
        ("venezuelan restaurant", "Venezuelan"),
        ("cuban restaurant", "Cuban"),
        ("kosher restaurant", "Kosher"),
        ("organic restaurant", "Organic"),
        ("waffles restaurant", "Waffles"),
        ("pancake restaurant", "Pancakes"),
    ]

    // MARK: - Generic Categories

    /// Labels that are too generic to be useful as cuisine types.
    ///
    /// These originate from `MKPointOfInterestCategory` (e.g. `.restaurant`)
    /// and from the catch-all `"restaurant"` query. They are stripped from
    /// `cuisineTags` and `category` during deduplication so that only
    /// meaningful cuisine types survive.
    ///
    /// Note: "Café" and "Bakery" are **not** generic — they are valid
    /// cuisine types that users can filter on.
    static let genericCategories: Set<String> = [
        "Restaurant", "Family Restaurant", "Food Court",
        "Food Market", "Brewery", "Winery", "Nightlife",
    ]

    // MARK: - Constants

    /// Apple's undocumented per-query result cap for `MKLocalSearch`.
    ///
    /// When a query returns exactly this many items, the category is likely
    /// saturated and additional results exist beyond what was returned.
    /// Used by `executeScatterNode` to decide which child nodes to enqueue.
    static let mkLocalSearchResultCap = 25

    /// Maximum recursion depth for adaptive scatter searches.
    ///
    /// At depth 3 the worst-case additional queries per cuisine label is ~29.
    /// Radii at each depth: R → R/2 → R/4 → R/8.
    static let maxScatterDepth = 3

    /// Maximum coordinate delta (in degrees latitude or longitude) used to
    /// determine whether two results represent the same physical restaurant.
    ///
    /// 0.0005° ≈ 55 m at the equator — tight enough to avoid merging nearby
    /// branches of the same chain while still combining duplicate POI entries.
    ///
    /// Used in `deduplicate(_:)` and referenced by `RestaurantViewModel` for
    /// the same purpose, ensuring a single source of truth for this threshold.
    static let coordinateProximityThreshold: Double = 0.0005

    /// Number of cuisine queries executed per batch.
    static let cuisineQueryBatchSize = 15

    /// Pause inserted between consecutive cuisine-search batches (50 ms).
    private static let cuisineSearchBatchDelayNanoseconds: UInt64 = 50_000_000

    // MARK: - Internal Types (now top-level — see RestaurantSearchTypes.swift)

    // MARK: - Private Types

    /// Cardinal direction used for scatter search offsets.
    private enum Cardinal: CaseIterable {
        case north, south, east, west
    }

    /// Diagonal direction inferred from two adjacent saturated cardinals.
    private enum Diagonal {
        case northEast, northWest, southEast, southWest
    }

    // MARK: - Coordinate Helpers

    /// Offsets a coordinate by `metres` in a cardinal direction.
    ///
    /// Uses approximate conversions:
    /// - 1° latitude ≈ 111,320 m
    /// - 1° longitude ≈ 111,320 m × cos(latitude)
    private static func offset(
        _ coord: CLLocationCoordinate2D,
        direction: Cardinal,
        metres: Double
    ) -> CLLocationCoordinate2D {
        let (latDelta, lngDelta) = coordinateDeltas(metres: metres, latitude: coord.latitude)
        switch direction {
        case .north: return CLLocationCoordinate2D(latitude: coord.latitude + latDelta, longitude: coord.longitude)
        case .south: return CLLocationCoordinate2D(latitude: coord.latitude - latDelta, longitude: coord.longitude)
        case .east: return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude + lngDelta)
        case .west: return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude - lngDelta)
        }
    }

    /// Offsets a coordinate by `metres` in a diagonal direction.
    private static func offset(
        _ coord: CLLocationCoordinate2D,
        diagonal: Diagonal,
        metres: Double
    ) -> CLLocationCoordinate2D {
        let (latDelta, lngDelta) = coordinateDeltas(metres: metres / sqrt(2.0), latitude: coord.latitude)
        switch diagonal {
        case .northEast: return CLLocationCoordinate2D(
                latitude: coord.latitude + latDelta,
                longitude: coord.longitude + lngDelta
            )
        case .northWest: return CLLocationCoordinate2D(
                latitude: coord.latitude + latDelta,
                longitude: coord.longitude - lngDelta
            )
        case .southEast: return CLLocationCoordinate2D(
                latitude: coord.latitude - latDelta,
                longitude: coord.longitude + lngDelta
            )
        case .southWest: return CLLocationCoordinate2D(
                latitude: coord.latitude - latDelta,
                longitude: coord.longitude - lngDelta
            )
        }
    }

    /// Returns the latitude and longitude deltas (in degrees) for a given
    /// distance in metres at the specified latitude.
    ///
    /// - Parameters:
    ///   - metres: Distance to convert.
    ///   - latitude: Latitude at which to compute the longitude scaling.
    /// - Returns: A `(latDelta, lngDelta)` tuple in degrees.
    private static func coordinateDeltas(metres: Double, latitude: Double) -> (Double, Double) {
        let latDelta = metres / 111_320.0
        let lngDelta = metres / (111_320.0 * cos(latitude * .pi / 180.0))
        return (latDelta, lngDelta)
    }

    /// Returns the diagonal direction between two orthogonally adjacent cardinals, if any.
    private static func diagonal(between a: Cardinal, and b: Cardinal) -> Diagonal? {
        switch (a, b) {
        case (.north, .east), (.east, .north): .northEast
        case (.north, .west), (.west, .north): .northWest
        case (.south, .east), (.east, .south): .southEast
        case (.south, .west), (.west, .south): .southWest
        default: nil
        }
    }

    // MARK: - Batch Execution Primitives

    /// Executes one batch of cuisine queries concurrently against a focused region.
    ///
    /// Runs all queries in `queries` in parallel via a `withTaskGroup`.
    /// Returns the combined results and the subset of queries whose raw
    /// result count hit `mkLocalSearchResultCap` (saturated — scatter needed).
    ///
    /// - Parameters:
    ///   - queries: The `(query, label)` pairs to execute in this batch.
    ///   - region: The `MKCoordinateRegion` to search within.
    ///   - location: The user's location used for distance calculation.
    ///   - networkRadius: Maximum distance in meters — results beyond this are discarded.
    /// - Returns: A `FocusedBatchResult` with results and saturated queries.
    func executeFocusedBatch(
        queries: [(query: String, label: String)],
        region: MKCoordinateRegion,
        location: CLLocation,
        networkRadius: Double
    ) async -> FocusedBatchResult {
        let batchResults: [(query: String, label: String, result: SearchResult)] =
            await withTaskGroup(of: (String, String, SearchResult).self) { group in
                for cuisine in queries {
                    group.addTask { [self] in
                        let r = await performSearch(
                            query: cuisine.query,
                            label: cuisine.label,
                            region: region,
                            location: location,
                            radius: networkRadius
                        )
                        return (cuisine.query, cuisine.label, r)
                    }
                }
                var collected: [(String, String, SearchResult)] = []
                for await item in group {
                    collected.append(item)
                }
                return collected
            }

        let results = batchResults.flatMap(\.result.results)
        let saturated = batchResults
            .filter { $0.result.rawCount >= Self.mkLocalSearchResultCap }
            .map { (query: $0.query, label: $0.label) }

        return FocusedBatchResult(results: results, saturatedQueries: saturated)
    }

    /// Executes a POI-category search covering the wide region.
    ///
    /// Uses `MKLocalPointsOfInterestRequest` with `.restaurant`, `.cafe`,
    /// and `.bakery` filters. Each result's label is derived from its
    /// actual POI category so cafés and bakeries get proper tags.
    ///
    /// - Parameters:
    ///   - region: The `MKCoordinateRegion` to search within (typically the wide region).
    ///   - location: The user's location used for distance calculation.
    ///   - networkRadius: Maximum distance in meters — results beyond this are discarded.
    /// - Returns: Restaurant/label pairs discovered by the POI search.
    func executePOISearch(
        region: MKCoordinateRegion,
        location: CLLocation,
        networkRadius: Double
    ) async -> [(Restaurant, String)] {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: [.restaurant, .cafe, .bakery]
        )
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.compactMap { item in
                guard let name = item.name else { return nil }
                let distance = location.distance(from: item.placemark.coordinate.asLocation)
                guard distance <= networkRadius else { return nil }
                let label = Self.poiCategoryLabel(for: item.pointOfInterestCategory)
                let displayCat = Self.displayName(for: item.pointOfInterestCategory)
                let restaurant = Restaurant(
                    id: UUID(),
                    name: name,
                    coordinate: item.placemark.coordinate,
                    distance: distance,
                    category: displayCat,
                    phoneNumber: item.phoneNumber,
                    url: item.url
                )
                return (restaurant, label)
            }
        } catch {
            return []
        }
    }

    /// Executes one level of scatter for a saturated node.
    ///
    /// Runs 4 cardinal searches (N/S/E/W) concurrently from the node's centre,
    /// each at half the node's radius. If adjacent cardinals are also saturated,
    /// diagonal fill points are searched as well. Returns all discovered results
    /// plus child `ScatterNode`s for any saturated sub-regions, which the
    /// orchestrator should enqueue for further scatter (up to `maxScatterDepth`).
    ///
    /// This method is deliberately non-recursive: it processes exactly one
    /// node and returns, allowing the orchestrator to interleave work across
    /// multiple locations between scatter levels.
    ///
    /// - Parameters:
    ///   - node: The scatter node to process (query, centre, radius, depth).
    ///   - userLocation: The user's actual location for distance calculation.
    ///   - maxRadius: Maximum distance from the user to keep results.
    /// - Returns: A `ScatterNodeResult` with results and pending child nodes.
    func executeScatterNode(
        _ node: ScatterNode,
        userLocation: CLLocation,
        maxRadius: Double
    ) async -> ScatterNodeResult {
        guard node.depth < Self.maxScatterDepth else {
            return ScatterNodeResult(results: [], childNodes: [])
        }

        let childRadius = node.radius * 0.5
        let offsetDistance = node.radius * 0.5

        let cardinalResults = await runCardinalSearches(
            for: node,
            childRadius: childRadius,
            offsetDistance: offsetDistance,
            userLocation: userLocation,
            maxRadius: maxRadius
        )

        var accumulated = cardinalResults.flatMap(\.result.results)
        let saturatedCardinals = Set(
            cardinalResults
                .filter { $0.result.rawCount >= Self.mkLocalSearchResultCap }
                .map(\.direction)
        )
        let diagonalPoints = Self.buildDiagonalPoints(
            from: saturatedCardinals,
            node: node,
            offsetDistance: offsetDistance
        )

        var childNodes: [ScatterNode] = []

        if !diagonalPoints.isEmpty {
            let diagResults = await runDiagonalSearches(
                at: diagonalPoints,
                node: node,
                childRadius: childRadius,
                userLocation: userLocation,
                maxRadius: maxRadius
            )
            for (idx, result) in diagResults.enumerated() {
                accumulated.append(contentsOf: result.results)
                if result.rawCount >= Self.mkLocalSearchResultCap {
                    childNodes.append(ScatterNode(
                        query: node.query,
                        label: node.label,
                        centre: diagonalPoints[idx].centre,
                        radius: childRadius,
                        depth: node.depth + 1
                    ))
                }
            }
        }

        // Enqueue saturated cardinal directions as child nodes
        for (dir, result) in cardinalResults where result.rawCount >= Self.mkLocalSearchResultCap {
            let centre = Self.offset(node.centre, direction: dir, metres: offsetDistance)
            childNodes.append(ScatterNode(
                query: node.query,
                label: node.label,
                centre: centre,
                radius: childRadius,
                depth: node.depth + 1
            ))
        }

        return ScatterNodeResult(results: accumulated, childNodes: childNodes)
    }

    // MARK: - Scatter Helpers

    /// Runs the four cardinal (N/S/E/W) searches for a scatter node concurrently.
    private func runCardinalSearches(
        for node: ScatterNode,
        childRadius: Double,
        offsetDistance: Double,
        userLocation: CLLocation,
        maxRadius: Double
    ) async -> [(direction: Cardinal, result: SearchResult)] {
        await withTaskGroup(of: (Cardinal, SearchResult).self) { group in
            for dir in Cardinal.allCases {
                group.addTask { [self] in
                    let centre = Self.offset(node.centre, direction: dir, metres: offsetDistance)
                    let region = MKCoordinateRegion(center: centre, radius: childRadius)
                    let result = await performSearch(
                        query: node.query,
                        label: node.label,
                        region: region,
                        location: userLocation,
                        radius: maxRadius
                    )
                    return (dir, result)
                }
            }
            var collected: [(Cardinal, SearchResult)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }
    }

    /// Returns the diagonal fill points between each pair of adjacent saturated cardinals.
    private static func buildDiagonalPoints(
        from saturatedCardinals: Set<Cardinal>,
        node: ScatterNode,
        offsetDistance: Double
    ) -> [(diagonal: Diagonal, centre: CLLocationCoordinate2D)] {
        let list = Array(saturatedCardinals)
        var points: [(Diagonal, CLLocationCoordinate2D)] = []
        for i in 0 ..< list.count {
            for j in (i + 1) ..< list.count {
                if let diag = diagonal(between: list[i], and: list[j]) {
                    let centre = offset(node.centre, diagonal: diag, metres: offsetDistance)
                    points.append((diag, centre))
                }
            }
        }
        return points
    }

    /// Runs diagonal searches concurrently for each fill point.
    private func runDiagonalSearches(
        at points: [(diagonal: Diagonal, centre: CLLocationCoordinate2D)],
        node: ScatterNode,
        childRadius: Double,
        userLocation: CLLocation,
        maxRadius: Double
    ) async -> [SearchResult] {
        await withTaskGroup(of: SearchResult.self) { group in
            for (_, centre) in points {
                group.addTask { [self] in
                    let region = MKCoordinateRegion(center: centre, radius: childRadius)
                    return await performSearch(
                        query: node.query,
                        label: node.label,
                        region: region,
                        location: userLocation,
                        radius: maxRadius
                    )
                }
            }
            var collected: [SearchResult] = []
            for await r in group {
                collected.append(r)
            }
            return collected
        }
    }

    /// Executes one batch of cuisine queries concurrently against the wide region.
    ///
    /// Identical in structure to `executeFocusedBatch` but used for the
    /// wide-pass phase (full network radius). Saturation is not tracked here
    /// since wide-pass scatter is not performed.
    ///
    /// - Parameters:
    ///   - queries: The `(query, label)` pairs to execute in this batch.
    ///   - region: The wide `MKCoordinateRegion` (sized to `networkRadius`).
    ///   - location: The user's location used for distance calculation.
    ///   - networkRadius: Maximum distance in meters — results beyond this are discarded.
    /// - Returns: Restaurant/label pairs discovered by this batch.
    func executeWideBatch(
        queries: [(query: String, label: String)],
        region: MKCoordinateRegion,
        location: CLLocation,
        networkRadius: Double
    ) async -> [(Restaurant, String)] {
        await withTaskGroup(of: SearchResult.self) { group in
            for cuisine in queries {
                group.addTask { [self] in
                    await performSearch(
                        query: cuisine.query,
                        label: cuisine.label,
                        region: region,
                        location: location,
                        radius: networkRadius
                    )
                }
            }
            var results: [(Restaurant, String)] = []
            for await r in group {
                results.append(contentsOf: r.results)
            }
            return results
        }
    }

    // MARK: - Cuisine Search

    /// Searches for restaurants matching specific cuisine labels.
    ///
    /// Use this when the user applies a cuisine filter — it re-runs
    /// targeted queries for those specific cuisines to find restaurants
    /// that may not have appeared in the initial broad search.
    ///
    /// - Parameters:
    ///   - cuisineLabels: Labels to search for (e.g. `["Yakiniku"]`).
    ///   - location: The center point for the search.
    ///   - radius: Search radius in meters.
    /// - Returns: Array of discovered restaurants sorted by distance.
    func searchCuisines(
        _ cuisineLabels: Set<String>,
        near location: CLLocation,
        radius: Double
    ) async -> [Restaurant] {
        let region = MKCoordinateRegion(center: location.coordinate, radius: radius)

        var queriesToRun: [(query: String, label: String)] = []
        for label in cuisineLabels {
            let lowered = label.lowercased()
            if let match = Self.cuisineQueries.first(where: { $0.label.lowercased() == lowered }) {
                queriesToRun.append(match)
            }
            queriesToRun.append((query: "\(label) restaurant", label: label))
            queriesToRun.append((query: label, label: label))
        }

        var allResults: [(Restaurant, String)] = []
        let batches = stride(from: 0, to: queriesToRun.count, by: Self.cuisineQueryBatchSize)
            .map { Array(queriesToRun[$0 ..< min($0 + Self.cuisineQueryBatchSize, queriesToRun.count)]) }

        for (idx, batch) in batches.enumerated() {
            let batchResult = await executeFocusedBatch(
                queries: batch,
                region: region,
                location: location,
                networkRadius: radius
            )
            allResults.append(contentsOf: batchResult.results)
            if idx < batches.count - 1 {
                try? await Task.sleep(nanoseconds: Self.cuisineSearchBatchDelayNanoseconds)
            }
        }

        return Self.deduplicate(allResults).sorted { $0.distance < $1.distance }
    }

    // MARK: - Deduplication

    /// Sorts results so specific labels come before generic, deduplicates,
    /// and returns the final list sorted by distance.
    static func deduplicateAndSort(_ results: [(Restaurant, String)]) -> [Restaurant] {
        let sorted = results.sorted { lhs, rhs in
            let lhsG = genericCategories.contains(lhs.1)
            let rhsG = genericCategories.contains(rhs.1)
            if lhsG, !rhsG { return false }
            if !lhsG, rhsG { return true }
            return false
        }
        return deduplicate(sorted).sorted { $0.distance < $1.distance }
    }

    /// Deduplicates restaurant results by name + proximity (within 50m).
    ///
    /// Same-name restaurants at different locations (chains) are kept.
    /// Generic labels (e.g. "Restaurant") are stripped from both the
    /// display `category` and `cuisineTags` so that only meaningful
    /// cuisine types remain.
    ///
    /// ## Complexity
    ///
    /// Uses a `[String: [Int]]` dictionary keyed by lowercased restaurant name to
    /// narrow the proximity check to same-name candidates only. For most inputs this
    /// runs in O(n) time; chains with many same-name locations add a small constant
    /// per chain. The previous O(n²) linear scan of the whole `unique` array has
    /// been eliminated.
    static func deduplicate(_ results: [(Restaurant, String)]) -> [Restaurant] {
        var unique: [Restaurant] = []
        // Maps lowercased restaurant name → indices in `unique` with that name.
        var nameIndex: [String: [Int]] = [:]

        for (restaurant, label) in results {
            let isGenericLabel = genericCategories.contains(label)
            let nameKey = restaurant.name.lowercased()

            // Narrow the proximity check to entries sharing the same name.
            let candidates = nameIndex[nameKey] ?? []
            let matchIdx = candidates.first { idx in
                let existing = unique[idx]
                return abs(existing.coordinate.latitude - restaurant.coordinate.latitude)
                    < Self.coordinateProximityThreshold
                    && abs(existing.coordinate.longitude - restaurant.coordinate.longitude)
                    < Self.coordinateProximityThreshold
            }

            if let idx = matchIdx {
                let existing = unique[idx]
                var mergedTags = existing.cuisineTags
                if !isGenericLabel { mergedTags.insert(label) }

                let newCategory: String? = if !isGenericLabel {
                    if existing.category == nil || genericCategories.contains(existing.category ?? "") {
                        label
                    } else {
                        existing.category
                    }
                } else {
                    existing.category
                }

                unique[idx] = Restaurant(
                    id: existing.id,
                    name: existing.name,
                    coordinate: existing.coordinate,
                    distance: existing.distance,
                    category: newCategory,
                    cuisineTags: mergedTags,
                    phoneNumber: existing.phoneNumber ?? restaurant.phoneNumber,
                    url: existing.url ?? restaurant.url
                )
                continue
            }

            let newIdx = unique.count
            let category: String? = isGenericLabel ? nil : label
            var tags: Set<String> = []
            if !isGenericLabel { tags.insert(label) }
            if let cat = restaurant.category, !genericCategories.contains(cat) { tags.insert(cat) }

            unique.append(Restaurant(
                id: restaurant.id,
                name: restaurant.name,
                coordinate: restaurant.coordinate,
                distance: restaurant.distance,
                category: category,
                cuisineTags: tags,
                phoneNumber: restaurant.phoneNumber,
                url: restaurant.url
            ))
            nameIndex[nameKey, default: []].append(newIdx)
        }

        return unique
    }

    // MARK: - Private Search Helpers

    /// Result from a single `MKLocalSearch` query.
    ///
    /// - `results`: Restaurant/label pairs that passed the radius filter.
    /// - `rawCount`: `response.mapItems.count` **before** the radius filter,
    ///   used to detect saturation (`rawCount == mkLocalSearchResultCap`).
    private typealias SearchResult = (results: [(Restaurant, String)], rawCount: Int)

    /// Performs a single `MKLocalSearch` query and returns results
    /// paired with the cuisine label that triggered the search.
    private func performSearch(
        query: String,
        label: String,
        region: MKCoordinateRegion,
        location: CLLocation,
        radius: Double
    ) async -> SearchResult {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            let rawCount = response.mapItems.count
            let filtered = response.mapItems.compactMap { item -> (Restaurant, String)? in
                guard let name = item.name else { return nil }
                let distance = location.distance(from: item.placemark.coordinate.asLocation)
                guard distance <= radius else { return nil }
                let displayCat = Self.displayName(for: item.pointOfInterestCategory)
                let restaurant = Restaurant(
                    id: UUID(),
                    name: name,
                    coordinate: item.placemark.coordinate,
                    distance: distance,
                    category: displayCat,
                    phoneNumber: item.phoneNumber,
                    url: item.url
                )
                return (restaurant, label)
            }
            return (results: filtered, rawCount: rawCount)
        } catch {
            return (results: [], rawCount: 0)
        }
    }

    // MARK: - Category Helpers

    /// Maps a POI category to the corresponding cuisine query label.
    ///
    /// Cafés and bakeries get their specific label; everything else
    /// gets the generic `"Restaurant"` (which will be stripped during
    /// deduplication).
    private static func poiCategoryLabel(for category: MKPointOfInterestCategory?) -> String {
        guard let category else { return "Restaurant" }
        switch category {
        case .cafe: return "Café"
        case .bakery: return "Bakery"
        default: return "Restaurant"
        }
    }

    /// Converts an `MKPointOfInterestCategory` to a human-readable name.
    private static func displayName(for category: MKPointOfInterestCategory?) -> String? {
        guard let category else { return nil }
        switch category {
        case .restaurant: return "Restaurant"
        case .cafe: return "Café"
        case .bakery: return "Bakery"
        case .brewery: return "Brewery"
        case .winery: return "Winery"
        case .foodMarket: return "Food Market"
        case .nightlife: return "Nightlife"
        default:
            let raw = category.rawValue
            if raw.hasPrefix("MKPOICategory") {
                let stripped = String(raw.dropFirst("MKPOICategory".count))
                return stripped.replacingOccurrences(
                    of: "([a-z])([A-Z])",
                    with: "$1 $2",
                    options: .regularExpression
                )
            }
            return raw
        }
    }
}
