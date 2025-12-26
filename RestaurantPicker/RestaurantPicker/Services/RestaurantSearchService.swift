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

    // MARK: - Public Methods

    /// Searches for restaurants near a location.
    ///
    /// Uses MapKit's `MKLocalSearch` to discover nearby restaurants
    /// and filters them based on the provided radius.
    ///
    /// - Parameters:
    ///   - location: The center point for the search.
    ///   - radius: Search radius in meters. Defaults to 5000 (5km).
    /// - Returns: Array of discovered restaurants sorted by distance.
    /// - Throws: `SearchError` if the search fails or returns no results.
    ///
    /// ## Example
    /// ```swift
    /// let restaurants = try await searchService.searchRestaurants(
    ///     near: userLocation,
    ///     radius: 2000
    /// )
    /// for restaurant in restaurants {
    ///     print("\(restaurant.name) - \(restaurant.formattedDistance)")
    /// }
    /// ```
    func searchRestaurants(near location: CLLocation, radius: Double = 5000) async throws -> [Restaurant] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurants"
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()

            let restaurants = response.mapItems.compactMap { item -> Restaurant? in
                guard let name = item.name else { return nil }

                let itemLocation = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                let distance = location.distance(from: itemLocation)

                return Restaurant(
                    id: UUID(),
                    name: name,
                    coordinate: item.placemark.coordinate,
                    distance: distance,
                    category: item.pointOfInterestCategory?.rawValue,
                    phoneNumber: item.phoneNumber,
                    url: item.url
                )
            }
            .filter { $0.distance <= radius }
            .sorted { $0.distance < $1.distance }

            return restaurants
        } catch {
            throw SearchError.searchFailed(underlying: error)
        }
    }
}

