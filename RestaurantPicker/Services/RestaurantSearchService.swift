import CoreLocation
import Foundation
import MapKit

/// Service for searching restaurants using Apple MapKit.
///
/// This service uses `MKLocalSearch` to discover nearby restaurants
/// based on the user's location and a specified search radius.
///
/// ## Usage
/// ```swift
/// let service = RestaurantSearchService()
/// let restaurants = try await service.searchRestaurants(
///     near: userLocation,
///     radius: 2000
/// )
/// ```
actor RestaurantSearchService {
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
        ("pancake restaurant", "Pancakes")
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
        "Food Market", "Brewery", "Winery", "Nightlife"
    ]

    // MARK: - Constants

    /// Apple's undocumented per-query result cap for `MKLocalSearch`.
    ///
    /// When a query returns exactly this many items, the category is likely
    /// saturated and additional results exist beyond what was returned.
    /// Used by adaptive scatter to decide when to re-query from offset centres.
    private static let mkLocalSearchResultCap = 25

    /// Maximum recursion depth for adaptive scatter searches.
    ///
    /// At depth 3 the worst-case additional queries per cuisine label is ~29.
    /// Radii at each depth: R → R/2 → R/4 → R/8.
    private static let maxScatterDepth = 3

    // MARK: - Scatter Types

    /// Cardinal direction used for scatter search offsets.
    private enum Cardinal: CaseIterable {
        case north, south, east, west
    }

    /// Diagonal direction inferred from two adjacent saturated cardinals.
    private enum Diagonal {
        case northEast, northWest, southEast, southWest
    }

    /// A search node representing a centre point + radius at a given recursion depth.
    private struct SearchNode {
        let centre: CLLocationCoordinate2D
        let radius: Double
        let depth: Int
    }

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
        let latDelta = metres / 111_320.0
        let lngDelta = metres / (111_320.0 * cos(coord.latitude * .pi / 180.0))
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
        let component = metres / sqrt(2.0) // 45° projection
        let latDelta = component / 111_320.0
        let lngDelta = component / (111_320.0 * cos(coord.latitude * .pi / 180.0))
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

    // MARK: - Public Methods

    /// Searches for restaurants near a location, yielding results progressively.
    ///
    /// Returns an `AsyncThrowingStream` that yields an accumulated, deduplicated
    /// restaurant snapshot after each batch completes. The POI category search
    /// runs concurrently alongside the first cuisine batch so its results appear
    /// early. The stream finishes after all batches complete.
    ///
    /// - Parameters:
    ///   - location: The center point for the search.
    ///   - radius: Search radius in meters. Defaults to 5000 (5km).
    ///     This is the maximum distance filter applied to individual results.
    ///   - scatterRadius: The radius used for adaptive scatter depth-0 nodes.
    ///     Defaults to `radius`. Pass the user's filter radius (e.g. 500m) to
    ///     concentrate scatter in the area the user is actually viewing.
    ///     Depth progression: scatterRadius → /2 → /4 → /8.
    /// - Returns: A stream of progressively larger restaurant snapshots.
    func searchRestaurants(
        near location: CLLocation,
        radius: Double = 5000,
        scatterRadius: Double? = nil
    ) -> AsyncThrowingStream<[Restaurant], Error> {
        let effectiveScatterRadius = scatterRadius ?? radius
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )

        return AsyncThrowingStream { continuation in
            let innerTask = Task { [self] in
                var accumulated: [(Restaurant, String)] = []
                var allSaturated: [(query: String, label: String)] = []
                let batchSize = 15
                let delayNs: UInt64 = 50_000_000
                let queries = Self.cuisineQueries
                let batches: [[(query: String, label: String)]] = stride(
                    from: 0, to: queries.count, by: batchSize
                ).map { Array(queries[$0 ..< min($0 + batchSize, queries.count)]) }

                // Fire POI search concurrently — it will be merged after batch 1
                let poiTask = Task { [self] in
                    await performPOISearch(
                        region: region,
                        location: location,
                        radius: radius
                    )
                }

                for (batchIdx, batch) in batches.enumerated() {
                    // Exit early if the stream consumer was cancelled
                    guard !Task.isCancelled else { break }

                    // Run this batch concurrently, collecting per-query SearchResults
                    let batchSearchResults: [(query: String, label: String, result: SearchResult)] =
                        await withTaskGroup(
                            of: (String, String, SearchResult).self
                        ) { group in
                            for cuisine in batch {
                                group.addTask { [self] in
                                    let r = await performSearch(
                                        query: cuisine.query,
                                        label: cuisine.label,
                                        region: region,
                                        location: location,
                                        radius: radius
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

                    // Merge batch results into accumulator
                    for item in batchSearchResults {
                        accumulated.append(contentsOf: item.result.results)
                    }

                    // After the first batch, also merge POI results
                    if batchIdx == 0 {
                        let poiResults = await poiTask.value
                        accumulated.append(contentsOf: poiResults)
                    }

                    // Yield a snapshot (user sees results fast)
                    let snapshot = Self.deduplicateAndSort(accumulated)
                    continuation.yield(snapshot)

                    // Collect saturated queries for scatter (run after all batches)
                    for item in batchSearchResults where item.result.rawCount >= Self.mkLocalSearchResultCap {
                        allSaturated.append((query: item.query, label: item.label))
                    }

                    // Delay between batches (skip after last)
                    if batchIdx < batches.count - 1 {
                        try? await Task.sleep(nanoseconds: delayNs)
                    }
                }

                // --- Scatter phase: run AFTER all batches to avoid rate-limit starvation ---
                // Scatter queries are batched (5 at a time) with delays to stay
                // within MapKit rate limits.
                if !allSaturated.isEmpty, !Task.isCancelled {
                    let scatterBatchSize = 5
                    let scatterBatches = stride(from: 0, to: allSaturated.count, by: scatterBatchSize).map {
                        Array(allSaturated[$0 ..< min($0 + scatterBatchSize, allSaturated.count)])
                    }

                    for (scatterIdx, scatterBatch) in scatterBatches.enumerated() {
                        guard !Task.isCancelled else { break }

                        let scatterResults = await withTaskGroup(
                            of: [(Restaurant, String)].self
                        ) { group in
                            for item in scatterBatch {
                                group.addTask { [self] in
                                    let node = SearchNode(
                                        centre: location.coordinate,
                                        radius: effectiveScatterRadius,
                                        depth: 0
                                    )
                                    return await scatterIfSaturated(
                                        query: item.query,
                                        label: item.label,
                                        node: node,
                                        userLocation: location,
                                        maxRadius: radius
                                    )
                                }
                            }
                            var combined: [(Restaurant, String)] = []
                            for await r in group {
                                combined.append(contentsOf: r)
                            }
                            return combined
                        }

                        if !scatterResults.isEmpty {
                            accumulated.append(contentsOf: scatterResults)
                            let scatterSnapshot = Self.deduplicateAndSort(accumulated)
                            continuation.yield(scatterSnapshot)
                        }

                        // Delay between scatter batches (skip after last)
                        if scatterIdx < scatterBatches.count - 1 {
                            try? await Task.sleep(nanoseconds: delayNs)
                        }
                    }
                }

                // If we never yielded anything, throw noResults
                let final = Self.deduplicateAndSort(accumulated)
                if final.isEmpty {
                    continuation.finish(throwing: SearchError.noResults)
                } else {
                    continuation.finish()
                }
            }

            // Cancel the inner task when the stream consumer stops listening
            continuation.onTermination = { @Sendable _ in
                innerTask.cancel()
            }
        }
    }

    /// Searches for restaurants matching specific cuisine labels.
    ///
    /// Use this when the user applies a cuisine filter — it re-runs
    /// targeted queries for those specific cuisines to find restaurants
    /// that may not have appeared in the initial broad search.
    ///
    /// - Parameters:
    ///   - cuisineLabels: Labels to search for (e.g. ["Yakiniku"]).
    ///   - location: The center point for the search.
    ///   - radius: Search radius in meters.
    /// - Returns: Array of discovered restaurants sorted by distance.
    func searchCuisines(
        _ cuisineLabels: Set<String>,
        near location: CLLocation,
        radius: Double
    ) async -> [Restaurant] {
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )

        var queriesToRun: [(query: String, label: String)] = []
        for label in cuisineLabels {
            let lowered = label.lowercased()
            if let match = Self.cuisineQueries.first(
                where: { $0.label.lowercased() == lowered }
            ) {
                queriesToRun.append(match)
            }
            queriesToRun.append(
                (query: "\(label) restaurant", label: label)
            )
            queriesToRun.append((query: label, label: label))
        }

        let allResults = await performBatchedSearches(
            queries: queriesToRun,
            region: region,
            location: location,
            radius: radius
        )

        return Self.deduplicate(allResults)
            .sorted { $0.distance < $1.distance }
    }

    // MARK: - Deduplication

    /// Sorts results so specific labels come before generic, deduplicates,
    /// and returns the final list sorted by distance.
    private static func deduplicateAndSort(
        _ results: [(Restaurant, String)]
    ) -> [Restaurant] {
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
    private static func deduplicate(
        _ results: [(Restaurant, String)]
    ) -> [Restaurant] {
        var unique: [Restaurant] = []

        for (restaurant, label) in results {
            let isGenericLabel = genericCategories.contains(label)
            let key = restaurant.name.lowercased()

            if let idx = unique.firstIndex(where: { existing in
                existing.name.lowercased() == key
                    && abs(
                        existing.coordinate.latitude
                            - restaurant.coordinate.latitude
                    ) < 0.0005
                    && abs(
                        existing.coordinate.longitude
                            - restaurant.coordinate.longitude
                    ) < 0.0005
            }) {
                // Duplicate — merge tag and maybe upgrade category
                let existing = unique[idx]
                var mergedTags = existing.cuisineTags
                if !isGenericLabel {
                    mergedTags.insert(label)
                }

                let newCategory: String? = if !isGenericLabel {
                    // Incoming label is specific — upgrade if needed
                    if existing.category == nil
                        || genericCategories.contains(
                            existing.category ?? ""
                        ) {
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
                    phoneNumber: existing.phoneNumber
                        ?? restaurant.phoneNumber,
                    url: existing.url ?? restaurant.url
                )
                continue
            }

            // New restaurant
            let category: String? = isGenericLabel ? nil : label
            var tags: Set<String> = []
            if !isGenericLabel {
                tags.insert(label)
            }
            // Also include the POI displayName if it is not generic
            if let cat = restaurant.category,
               !genericCategories.contains(cat) {
                tags.insert(cat)
            }

            let categorized = Restaurant(
                id: restaurant.id,
                name: restaurant.name,
                coordinate: restaurant.coordinate,
                distance: restaurant.distance,
                category: category,
                cuisineTags: tags,
                phoneNumber: restaurant.phoneNumber,
                url: restaurant.url
            )
            unique.append(categorized)
        }

        return unique
    }

    // MARK: - Search Helpers

    /// Runs search queries in batches to avoid MapKit rate limiting.
    ///
    /// Firing all ~150 queries simultaneously causes Apple's servers to
    /// throttle most of them, returning empty results silently. Running
    /// queries in groups of `batchSize` with a short `delayNanoseconds`
    /// pause between groups keeps total throughput high while staying
    /// within rate limits.
    ///
    /// - Parameters:
    ///   - queries: All `(query, label)` pairs to execute.
    ///   - region: The MapKit search region.
    ///   - location: The user's location for distance calculation.
    ///   - radius: Maximum distance in meters.
    ///   - batchSize: Number of concurrent requests per batch. Defaults to 15.
    ///   - delayNanoseconds: Pause between batches. Defaults to 50ms.
    private func performBatchedSearches(
        queries: [(query: String, label: String)],
        region: MKCoordinateRegion,
        location: CLLocation,
        radius: Double,
        batchSize: Int = 15,
        delayNanoseconds: UInt64 = 50_000_000
    ) async -> [(Restaurant, String)] {
        var combined: [(Restaurant, String)] = []
        let batches = stride(from: 0, to: queries.count, by: batchSize).map {
            Array(queries[$0 ..< min($0 + batchSize, queries.count)])
        }

        for batch in batches {
            let batchResults = await withTaskGroup(
                of: SearchResult.self
            ) { group in
                for cuisine in batch {
                    group.addTask { [self] in
                        await performSearch(
                            query: cuisine.query,
                            label: cuisine.label,
                            region: region,
                            location: location,
                            radius: radius
                        )
                    }
                }
                var results: [SearchResult] = []
                for await r in group {
                    results.append(r)
                }
                return results
            }
            for result in batchResults {
                combined.append(contentsOf: result.results)
            }
            if batch.last?.query != batches.last?.last?.query {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }

        return combined
    }

    // MARK: - Adaptive Scatter

    /// Recursively searches from offset centres for a saturated query.
    ///
    /// When a query returns `mkLocalSearchResultCap` results, there are
    /// likely more nearby restaurants that didn't make the top-25. This
    /// method re-runs the query from 4 cardinal offset points (N/S/E/W)
    /// at half the parent radius. If adjacent cardinals are also saturated,
    /// a diagonal fill point is added between them (at the same radius as
    /// the parent). All saturated points recurse up to `maxScatterDepth`.
    ///
    /// - Parameters:
    ///   - query: The natural language query string.
    ///   - label: The cuisine label for this query.
    ///   - node: The parent search node (centre, radius, depth).
    ///   - userLocation: The user's actual location for distance calculation.
    ///   - maxRadius: Maximum distance from the user to keep results.
    /// - Returns: All additional results discovered by scatter searches.
    private func scatterIfSaturated(
        query: String,
        label: String,
        node: SearchNode,
        userLocation: CLLocation,
        maxRadius: Double
    ) async -> [(Restaurant, String)] {
        guard node.depth < Self.maxScatterDepth else { return [] }

        let childRadius = node.radius * 0.5
        let offsetDistance = node.radius * 0.5

        // Fire N/S/E/W concurrently
        let cardinalResults: [(Cardinal, SearchResult)] = await withTaskGroup(
            of: (Cardinal, SearchResult).self
        ) { group in
            for dir in Cardinal.allCases {
                group.addTask { [self] in
                    let centre = Self.offset(node.centre, direction: dir, metres: offsetDistance)
                    let region = MKCoordinateRegion(
                        center: centre,
                        latitudinalMeters: childRadius * 2,
                        longitudinalMeters: childRadius * 2
                    )
                    let result = await performSearch(
                        query: query,
                        label: label,
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

        // Collect results and identify saturated cardinals
        var accumulated: [(Restaurant, String)] = []
        var saturatedCardinals: Set<Cardinal> = []

        for (dir, result) in cardinalResults {
            accumulated.append(contentsOf: result.results)
            if result.rawCount >= Self.mkLocalSearchResultCap {
                saturatedCardinals.insert(dir)
            }
        }

        // Diagonal fill: for each pair of adjacent saturated cardinals, add diagonal
        var diagonalPoints: [(Diagonal, CLLocationCoordinate2D)] = []
        let saturatedList = Array(saturatedCardinals)
        for i in 0 ..< saturatedList.count {
            for j in (i + 1) ..< saturatedList.count {
                if let diag = Self.diagonal(between: saturatedList[i], and: saturatedList[j]) {
                    let centre = Self.offset(node.centre, diagonal: diag, metres: offsetDistance)
                    diagonalPoints.append((diag, centre))
                }
            }
        }

        // Fire diagonal searches concurrently
        if !diagonalPoints.isEmpty {
            let diagResults: [SearchResult] = await withTaskGroup(
                of: SearchResult.self
            ) { group in
                for (_, centre) in diagonalPoints {
                    group.addTask { [self] in
                        let region = MKCoordinateRegion(
                            center: centre,
                            latitudinalMeters: childRadius * 2,
                            longitudinalMeters: childRadius * 2
                        )
                        return await performSearch(
                            query: query,
                            label: label,
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

            // Collect diagonal results; saturated diagonals also recurse
            for (idx, result) in diagResults.enumerated() {
                accumulated.append(contentsOf: result.results)
                if result.rawCount >= Self.mkLocalSearchResultCap {
                    let childNode = SearchNode(
                        centre: diagonalPoints[idx].1,
                        radius: childRadius,
                        depth: node.depth + 1
                    )
                    let deeper = await scatterIfSaturated(
                        query: query,
                        label: label,
                        node: childNode,
                        userLocation: userLocation,
                        maxRadius: maxRadius
                    )
                    accumulated.append(contentsOf: deeper)
                }
            }
        }

        // Recurse on saturated cardinal points
        for (dir, result) in cardinalResults where result.rawCount >= Self.mkLocalSearchResultCap {
            let centre = Self.offset(node.centre, direction: dir, metres: offsetDistance)
            let childNode = SearchNode(
                centre: centre,
                radius: childRadius,
                depth: node.depth + 1
            )
            let deeper = await scatterIfSaturated(
                query: query,
                label: label,
                node: childNode,
                userLocation: userLocation,
                maxRadius: maxRadius
            )
            accumulated.append(contentsOf: deeper)
        }

        return accumulated
    }

    /// Result from a single `MKLocalSearch` query.
    ///
    /// - `results`: Restaurant/label pairs that passed the radius filter.
    /// - `rawCount`: `response.mapItems.count` **before** the radius filter,
    ///   used to detect saturation (`rawCount == mkLocalSearchResultCap`).
    private typealias SearchResult = (
        results: [(Restaurant, String)],
        rawCount: Int
    )

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

                let itemLoc = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                let distance = location.distance(from: itemLoc)
                guard distance <= radius else { return nil }

                let displayCat = Self.displayName(
                    for: item.pointOfInterestCategory
                )
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

    /// Performs a POI category-based search for restaurants.
    ///
    /// Uses `MKLocalPointsOfInterestRequest` with `.restaurant`, `.cafe`,
    /// and `.bakery` filters. Each result's label is derived from its
    /// actual POI category so cafés and bakeries get proper tags.
    private func performPOISearch(
        region: MKCoordinateRegion,
        location: CLLocation,
        radius: Double
    ) async -> [(Restaurant, String)] {
        let request = MKLocalPointsOfInterestRequest(
            coordinateRegion: region
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: [.restaurant, .cafe, .bakery]
        )

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()

            return response.mapItems.compactMap { item in
                guard let name = item.name else { return nil }

                let itemLoc = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                let distance = location.distance(from: itemLoc)
                guard distance <= radius else { return nil }

                let label = Self.poiCategoryLabel(
                    for: item.pointOfInterestCategory
                )
                let displayCat = Self.displayName(
                    for: item.pointOfInterestCategory
                )
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

    // MARK: - Category Helpers

    /// Maps a POI category to the corresponding cuisine query label.
    ///
    /// Cafés and bakeries get their specific label; everything else
    /// gets the generic `"Restaurant"` (which will be stripped during
    /// deduplication).
    private static func poiCategoryLabel(
        for category: MKPointOfInterestCategory?
    ) -> String {
        guard let category else { return "Restaurant" }
        switch category {
        case .cafe: return "Café"
        case .bakery: return "Bakery"
        default: return "Restaurant"
        }
    }

    /// Converts an `MKPointOfInterestCategory` to a human-readable name.
    private static func displayName(
        for category: MKPointOfInterestCategory?
    ) -> String? {
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
                let stripped = String(
                    raw.dropFirst("MKPOICategory".count)
                )
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
