import CoreLocation
import Foundation
import MapKit

// MARK: - CLLocationCoordinate2D Extensions

extension CLLocationCoordinate2D: Equatable {
    /// Checks if two coordinates are equal.
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    /// The coordinate wrapped in a `CLLocation`.
    ///
    /// Avoids repeating the boilerplate
    /// `CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)`
    /// at every MapKit call site.
    var asLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
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

// MARK: - MKCoordinateRegion Extensions

extension MKCoordinateRegion {
    /// Creates a square region centred on `centre` with a half-side of `radius` metres.
    ///
    /// Uses `latitudinalMeters: radius * 2, longitudinalMeters: radius * 2` so
    /// the region's total span is `2 × radius` in each direction — the same
    /// convention used throughout the app's search primitives.
    ///
    /// - Parameters:
    ///   - centre: The geographic centre of the region.
    ///   - radius: Half the side length in metres.
    init(center centre: CLLocationCoordinate2D, radius: Double) {
        self.init(
            center: centre,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
    }
}
