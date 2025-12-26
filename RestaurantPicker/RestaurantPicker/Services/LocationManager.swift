import CoreLocation
import Foundation

/// Manages user location and authorization status.
///
/// This class handles requesting location permissions and tracking
/// the user's current location for restaurant search purposes.
///
/// ## Usage
/// ```swift
/// let locationManager = LocationManager()
/// await locationManager.requestAuthorization()
/// if let location = locationManager.currentLocation {
///     print("User is at \(location.coordinate)")
/// }
/// ```
@MainActor
final class LocationManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    /// The current location of the user.
    @Published var currentLocation: CLLocation?

    /// The current authorization status.
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Error message if location services fail.
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let manager = CLLocationManager()

    // MARK: - Initialization

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Public Methods

    /// Requests location authorization from the user.
    ///
    /// Requests "When In Use" authorization, which is sufficient for
    /// searching nearby restaurants while the app is in the foreground.
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Requests the user's current location.
    ///
    /// This triggers a one-time location update. The result will be
    /// published to the `currentLocation` property.
    func requestLocation() {
        manager.requestLocation()
    }

    /// Checks if location services are authorized.
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Checks if authorization has been denied.
    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            currentLocation = locations.last
            errorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus

            if isAuthorized {
                requestLocation()
            }
        }
    }
}

