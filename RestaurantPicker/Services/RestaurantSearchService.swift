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
                return "Search failed: \(error.localizedDescription)"
            case .noResults:
                return "No restaurants found in this area."
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
        // Generic catch-all (label stripped during deduplication)
        ("restaurant", "Restaurant"),
        ("family restaurant", "Family Restaurant"),
        ("food court", "Food Court"),

        // MARK: Japanese
        ("japanese restaurant", "Japanese"),
        ("sushi restaurant", "Sushi"),
        ("ramen restaurant", "Ramen"),
        ("udon restaurant", "Udon"),
        ("soba restaurant", "Soba"),
        ("tempura restaurant", "Tempura"),
        ("tonkatsu restaurant", "Tonkatsu"),
        ("yakiniku restaurant", "Yakiniku"),
        ("izakaya", "Izakaya"),
        ("washoku restaurant", "Washoku"),
        ("okonomiyaki restaurant", "Okonomiyaki"),
        ("takoyaki restaurant", "Takoyaki"),
        ("gyudon restaurant", "Gyudon"),
        ("donburi restaurant", "Donburi"),
        ("teppanyaki restaurant", "Teppanyaki"),
        ("kaiseki restaurant", "Kaiseki"),
        ("kushikatsu restaurant", "Kushikatsu"),
        ("yoshoku restaurant", "Yoshoku"),

        // MARK: East & Southeast Asian
        ("chinese restaurant", "Chinese"),
        ("dim sum restaurant", "Dim Sum"),
        ("korean restaurant", "Korean"),
        ("thai restaurant", "Thai"),
        ("vietnamese restaurant", "Vietnamese"),
        ("pho restaurant", "Pho"),
        ("filipino restaurant", "Filipino"),
        ("indonesian restaurant", "Indonesian"),
        ("malaysian restaurant", "Malaysian"),
        ("singaporean restaurant", "Singaporean"),
        ("taiwanese restaurant", "Taiwanese"),
        ("boba tea", "Boba Tea"),

        // MARK: South & Central Asian
        ("indian restaurant", "Indian"),
        ("curry restaurant", "Curry"),
        ("nepali restaurant", "Nepali"),
        ("pakistani restaurant", "Pakistani"),
        ("tibetan restaurant", "Tibetan"),
        ("afghan restaurant", "Afghan"),

        // MARK: Middle Eastern & African
        ("middle eastern restaurant", "Middle Eastern"),
        ("lebanese restaurant", "Lebanese"),
        ("turkish restaurant", "Turkish"),
        ("shawarma restaurant", "Shawarma"),
        ("falafel restaurant", "Falafel"),
        ("kebab restaurant", "Kebab"),
        ("moroccan restaurant", "Moroccan"),
        ("ethiopian restaurant", "Ethiopian"),
        ("african restaurant", "African"),

        // MARK: European
        ("italian restaurant", "Italian"),
        ("pizza restaurant", "Pizza"),
        ("pasta restaurant", "Pasta"),
        ("french restaurant", "French"),
        ("spanish restaurant", "Spanish"),
        ("tapas restaurant", "Tapas"),
        ("greek restaurant", "Greek"),
        ("mediterranean restaurant", "Mediterranean"),
        ("german restaurant", "German"),
        ("british restaurant", "British"),
        ("irish restaurant", "Irish"),
        ("portuguese restaurant", "Portuguese"),
        ("scandinavian restaurant", "Scandinavian"),
        ("polish restaurant", "Polish"),
        ("hungarian restaurant", "Hungarian"),
        ("austrian restaurant", "Austrian"),
        ("swiss restaurant", "Swiss"),
        ("belgian restaurant", "Belgian"),
        ("dutch restaurant", "Dutch"),
        ("georgian restaurant", "Georgian"),
        ("russian restaurant", "Russian"),

        // MARK: Americas
        ("american restaurant", "American"),
        ("burger restaurant", "Burger"),
        ("steakhouse", "Steakhouse"),
        ("mexican restaurant", "Mexican"),
        ("tex-mex restaurant", "Tex-Mex"),
        ("brazilian restaurant", "Brazilian"),
        ("peruvian restaurant", "Peruvian"),
        ("caribbean restaurant", "Caribbean"),
        ("cajun restaurant", "Cajun"),
        ("creole restaurant", "Creole"),
        ("soul food restaurant", "Soul Food"),
        ("hawaiian restaurant", "Hawaiian"),
        ("poke restaurant", "Poke"),

        // MARK: Casual & Quick Service
        ("seafood restaurant", "Seafood"),
        ("bbq restaurant", "BBQ"),
        ("noodle restaurant", "Noodle"),
        ("dumpling restaurant", "Dumpling"),
        ("deli", "Deli"),
        ("sandwich shop", "Sandwich"),
        ("diner", "Diner"),
        ("fried chicken restaurant", "Fried Chicken"),
        ("wings restaurant", "Wings"),
        ("hot dog restaurant", "Hot Dog"),

        // MARK: Dietary
        ("vegetarian restaurant", "Vegetarian"),
        ("vegan restaurant", "Vegan"),

        // MARK: Breakfast & Brunch
        ("breakfast restaurant", "Breakfast"),
        ("brunch restaurant", "Brunch"),

        // MARK: Café, Bakery & Dessert
        ("cafe restaurant", "Café"),
        ("bakery", "Bakery"),
        ("ice cream shop", "Ice Cream"),
        ("dessert restaurant", "Dessert"),
        ("donut shop", "Donuts"),
        ("smoothie juice bar", "Juice Bar"),
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

    // MARK: - Public Methods

    /// Searches for restaurants near a location.
    ///
    /// Runs multiple cuisine-specific searches in parallel to overcome
    /// the ~25 result limit per `MKLocalSearch` query, then deduplicates
    /// results by name and proximity.
    ///
    /// - Parameters:
    ///   - location: The center point for the search.
    ///   - radius: Search radius in meters. Defaults to 5000 (5km).
    /// - Returns: Array of discovered restaurants sorted by distance.
    /// - Throws: `SearchError` if all searches fail or return no results.
    func searchRestaurants(
        near location: CLLocation,
        radius: Double = 5000
    ) async throws -> [Restaurant] {
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )

        // Run all cuisine searches concurrently, plus a POI category search.
        // Collect cuisine results and POI results separately so cuisine-specific
        // labels take priority during deduplication.
        let cuisineResults = await withTaskGroup(
            of: [(Restaurant, String)].self
        ) { group in
            for cuisine in Self.cuisineQueries {
                group.addTask { [self] in
                    await self.performSearch(
                        query: cuisine.query,
                        label: cuisine.label,
                        region: region,
                        location: location,
                        radius: radius
                    )
                }
            }

            var combined: [(Restaurant, String)] = []
            for await results in group {
                combined.append(contentsOf: results)
            }
            return combined
        }

        // Supplemental: POI category-based search (no natural language).
        // Discovers restaurants that may not match any cuisine keyword.
        let poiResults = await performPOISearch(
            region: region,
            location: location,
            radius: radius
        )

        // Cuisine-specific results first (sorted so specific labels come
        // before generic ones), then POI results — dedup keeps the first
        // occurrence, so specific labels win over generic ones.
        let sortedCuisine = cuisineResults.sorted { lhs, rhs in
            let lhsGeneric = Self.genericCategories.contains(lhs.1)
            let rhsGeneric = Self.genericCategories.contains(rhs.1)
            if lhsGeneric, !rhsGeneric { return false }
            if !lhsGeneric, rhsGeneric { return true }
            return false // stable order otherwise
        }
        let allResults = sortedCuisine + poiResults

        // Deduplicate by name + proximity (within 50m)
        let unique = Self.deduplicate(allResults)

        if unique.isEmpty {
            throw SearchError.noResults
        }

        return unique.sorted { $0.distance < $1.distance }
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

        let allResults = await withTaskGroup(
            of: [(Restaurant, String)].self
        ) { group in
            for cuisine in queriesToRun {
                group.addTask { [self] in
                    await self.performSearch(
                        query: cuisine.query,
                        label: cuisine.label,
                        region: region,
                        location: location,
                        radius: radius
                    )
                }
            }

            var combined: [(Restaurant, String)] = []
            for await results in group {
                combined.append(contentsOf: results)
            }
            return combined
        }

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

                let newCategory: String?
                if !isGenericLabel {
                    // Incoming label is specific — upgrade if needed
                    if existing.category == nil
                        || genericCategories.contains(
                            existing.category ?? ""
                        ) {
                        newCategory = label
                    } else {
                        newCategory = existing.category
                    }
                } else {
                    newCategory = existing.category
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
