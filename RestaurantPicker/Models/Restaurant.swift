import CoreLocation
import Foundation

/// A restaurant discovered via MapKit search.
///
/// This struct represents a restaurant location with its associated metadata
/// including name, coordinates, and distance from the user's current location.
///
/// ## Usage
/// ```swift
/// let restaurant = Restaurant(
///     id: UUID(),
///     name: "Thai Cafe",
///     coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
///     distance: 500
/// )
/// ```
struct Restaurant: Identifiable, Equatable {
    /// Unique identifier for the restaurant.
    let id: UUID

    /// Display name of the restaurant.
    let name: String

    /// Geographic coordinates of the restaurant.
    let coordinate: CLLocationCoordinate2D

    /// Distance from user's current location in meters.
    let distance: Double

    /// Category of the restaurant (e.g., "Thai", "Italian").
    let category: String?

    /// Phone number if available.
    let phoneNumber: String?

    /// URL for more information.
    let url: URL?

    // MARK: - Equatable

    static func == (lhs: Restaurant, rhs: Restaurant) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.distance == rhs.distance &&
            lhs.category == rhs.category &&
            lhs.phoneNumber == rhs.phoneNumber &&
            lhs.url == rhs.url
    }

    // MARK: - Convenience

    /// Formatted distance string for display.
    var formattedDistance: String {
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
}
