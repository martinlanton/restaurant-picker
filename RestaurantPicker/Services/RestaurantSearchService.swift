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
            case .searchFailed(let error):
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
    private static let cuisineQueries: [(query: String, label: String)] = [
        ("restaurant", "Restaurant"),
        ("chinese restaurant", "Chinese"),
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
        ("curry restaurant", "Curry"),
        ("gyudon restaurant", "Gyudon"),
        ("donburi restaurant", "Donburi"),
        ("teppanyaki restaurant", "Teppanyaki"),
        ("kaiseki restaurant", "Kaiseki"),
        ("kushikatsu restaurant", "Kushikatsu"),
        ("yoshoku restaurant", "Yoshoku"),
        ("family restaurant", "Family Restaurant"),
        ("korean restaurant", "Korean"),
        ("thai restaurant", "Thai"),
        ("vietnamese restaurant", "Vietnamese"),
        ("indian restaurant", "Indian"),
        ("italian restaurant", "Italian"),
        ("pizza restaurant", "Pizza"),
        ("pasta restaurant", "Pasta"),
        ("mexican restaurant", "Mexican"),
        ("french restaurant", "French"),
        ("mediterranean restaurant", "Mediterranean"),
        ("greek restaurant", "Greek"),
        ("turkish restaurant", "Turkish"),
        ("lebanese restaurant", "Lebanese"),
        ("american restaurant", "American"),
        ("burger restaurant", "Burger"),
        ("steakhouse", "Steakhouse"),
        ("seafood restaurant", "Seafood"),
        ("vegetarian restaurant", "Vegetarian"),
        ("vegan restaurant", "Vegan"),
        ("breakfast restaurant", "Breakfast"),
        ("brunch restaurant", "Brunch"),
        ("cafe restaurant", "Café"),
        ("bakery", "Bakery"),
        ("bbq restaurant", "BBQ"),
        ("tapas restaurant", "Tapas"),
        ("spanish restaurant", "Spanish"),
        ("ethiopian restaurant", "Ethiopian"),
        ("peruvian restaurant", "Peruvian"),
        ("brazilian restaurant", "Brazilian"),
        ("caribbean restaurant", "Caribbean"),
        ("middle eastern restaurant", "Middle Eastern"),
        ("african restaurant", "African"),
        ("dim sum restaurant", "Dim Sum"),
        ("noodle restaurant", "Noodle"),
        ("dumpling restaurant", "Dumpling"),
        ("food court", "Food Court"),
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
    func searchRestaurants(near location: CLLocation, radius: Double = 5000) async throws -> [Restaurant] {
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )

        // Run all cuisine searches concurrently, plus a POI category search
        let allResults = await withTaskGroup(of: [(Restaurant, String)].self) { group in
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

            // Supplemental: POI category-based search (no natural language)
            // Discovers restaurants that may not match any cuisine keyword
            group.addTask { [self] in
                await self.performPOISearch(
                    region: region,
                    location: location,
                    radius: radius
                )
            }

            var combined: [(Restaurant, String)] = []
            for await results in group {
                combined.append(contentsOf: results)
            }
            return combined
        }

        // Deduplicate by name + proximity (within 50m)
        // Same-name restaurants at different locations (chains) are kept.
        var unique: [Restaurant] = []

        for (restaurant, label) in allResults {
            let key = restaurant.name.lowercased()
            let isDuplicate = unique.contains { existing in
                existing.name.lowercased() == key &&
                    abs(existing.coordinate.latitude - restaurant.coordinate.latitude) < 0.0005 &&
                    abs(existing.coordinate.longitude - restaurant.coordinate.longitude) < 0.0005
            }
            if isDuplicate {
                continue
            }

            // Use the cuisine label if it came from a specific query, otherwise fallback
            let category = label == "Restaurant" ? restaurant.category : label
            let categorized = Restaurant(
                id: restaurant.id,
                name: restaurant.name,
                coordinate: restaurant.coordinate,
                distance: restaurant.distance,
                category: category,
                phoneNumber: restaurant.phoneNumber,
                url: restaurant.url
            )
            unique.append(categorized)
        }

        if unique.isEmpty {
            throw SearchError.noResults
        }

        return unique.sorted { $0.distance < $1.distance }
    }

    // MARK: - Private Methods

    /// Performs a single MKLocalSearch query and returns the results.
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

            return response.mapItems.compactMap { item -> (Restaurant, String)? in
                guard let name = item.name else { return nil }

                let itemLocation = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                let distance = location.distance(from: itemLocation)

                guard distance <= radius else { return nil }

                let displayCategory = Self.displayName(for: item.pointOfInterestCategory)

                let restaurant = Restaurant(
                    id: UUID(),
                    name: name,
                    coordinate: item.placemark.coordinate,
                    distance: distance,
                    category: displayCategory,
                    phoneNumber: item.phoneNumber,
                    url: item.url
                )
                return (restaurant, label)
            }
        } catch {
            // Individual query failures are non-fatal; other queries may succeed.
            return []
        }
    }

    /// Performs a POI category-based search for restaurants.
    ///
    /// Uses `MKLocalPointsOfInterestRequest` with a `.restaurant` filter
    /// to discover restaurants that may not match natural language queries.
    private func performPOISearch(
        region: MKCoordinateRegion,
        location: CLLocation,
        radius: Double
    ) async -> [(Restaurant, String)] {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery])

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()

            return response.mapItems.compactMap { item -> (Restaurant, String)? in
                guard let name = item.name else { return nil }

                let itemLocation = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                let distance = location.distance(from: itemLocation)

                guard distance <= radius else { return nil }

                let displayCategory = Self.displayName(for: item.pointOfInterestCategory)

                let restaurant = Restaurant(
                    id: UUID(),
                    name: name,
                    coordinate: item.placemark.coordinate,
                    distance: distance,
                    category: displayCategory,
                    phoneNumber: item.phoneNumber,
                    url: item.url
                )
                return (restaurant, "Restaurant")
            }
        } catch {
            return []
        }
    }

    /// Converts an `MKPointOfInterestCategory` to a human-readable display name.
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
