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
    /// - Returns: A stream of progressively larger restaurant snapshots.
    func searchRestaurants(
        near location: CLLocation,
        radius: Double = 5000
    ) -> AsyncThrowingStream<[Restaurant], Error> {
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )

        return AsyncThrowingStream { continuation in
            Task { [self] in
                var accumulated: [(Restaurant, String)] = []
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
                    // Run this batch concurrently
                    let batchResults = await withTaskGroup(
                        of: [(Restaurant, String)].self
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
                        var results: [(Restaurant, String)] = []
                        for await r in group {
                            results.append(contentsOf: r)
                        }
                        return results
                    }
                    accumulated.append(contentsOf: batchResults)

                    // After the first batch, also merge POI results if ready
                    if batchIdx == 0 {
                        let poiResults = await poiTask.value
                        accumulated.append(contentsOf: poiResults)
                    }

                    // Sort so specific labels come before generic, then dedup
                    let sorted = accumulated.sorted { lhs, rhs in
                        let lhsG = Self.genericCategories.contains(lhs.1)
                        let rhsG = Self.genericCategories.contains(rhs.1)
                        if lhsG, !rhsG { return false }
                        if !lhsG, rhsG { return true }
                        return false
                    }
                    let snapshot = Self.deduplicate(sorted)
                        .sorted { $0.distance < $1.distance }

                    continuation.yield(snapshot)

                    // Delay between batches (skip after last)
                    if batchIdx < batches.count - 1 {
                        try? await Task.sleep(nanoseconds: delayNs)
                    }
                }

                // If we never yielded anything, throw noResults
                let finalSorted = accumulated.sorted { lhs, rhs in
                    let lhsG = Self.genericCategories.contains(lhs.1)
                    let rhsG = Self.genericCategories.contains(rhs.1)
                    if lhsG, !rhsG { return false }
                    if !lhsG, rhsG { return true }
                    return false
                }
                let final = Self.deduplicate(finalSorted)
                if final.isEmpty {
                    continuation.finish(throwing: SearchError.noResults)
                } else {
                    continuation.finish()
                }
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
                of: [(Restaurant, String)].self
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
                var results: [(Restaurant, String)] = []
                for await r in group {
                    results.append(contentsOf: r)
                }
                return results
            }
            combined.append(contentsOf: batchResults)
            if batch.last?.query != batches.last?.last?.query {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }

        return combined
    }

    /// Performs a single `MKLocalSearch` query and returns results
    /// paired with the cuisine label that triggered the search.
    private func performSearch(
        query: String,
        label: String,
        region: MKCoordinateRegion,
        location: CLLocation,
        radius: Double
    ) async -> [(Restaurant, String)] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest

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
