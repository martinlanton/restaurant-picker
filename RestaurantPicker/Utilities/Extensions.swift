import CoreLocation
import Foundation

// MARK: - CLLocationCoordinate2D Extensions

extension CLLocationCoordinate2D: Equatable {
    /// Checks if two coordinates are equal.
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - Double Extensions

extension Double {
    /// Formats the distance in a human-readable format.
    ///
    /// - Returns: A string like "350 m" or "1.5 km"
    var formattedAsDistance: String {
        if self < 1000 {
            String(format: "%.0f m", self)
        } else {
            String(format: "%.1f km", self / 1000)
        }
    }
}

// MARK: - Optional Extensions

extension Double? {
    /// Formats an optional distance value.
    ///
    /// - Returns: The formatted distance or "Any" if nil.
    var formattedAsDistanceFilter: String {
        guard let value = self else { return "Any" }
        return value.formattedAsDistance
    }
}
