import Combine
import CoreLocation
import Foundation

/// Manages user location and authorization status.
///
/// This class handles requesting location permissions and tracking
/// the user's current location for restaurant search purposes.
/// Supports an optional location override so users can explore
/// restaurants in a different area via the map tab.
///
/// ## Usage
/// ```swift
/// let locationManager = LocationManager()
/// await locationManager.requestAuthorization()
/// if let location = locationManager.effectiveLocation {
///     print("Searching at \(location.coordinate)")
/// }
/// ```
@MainActor
final class LocationManager: NSObject, ObservableObject, LocationManaging {
    // MARK: - Published Properties

    /// The current location of the user.
    @Published var currentLocation: CLLocation?

    /// A manually-set location that overrides the GPS location.
    ///
    /// When non-nil, `effectiveLocation` returns this instead of the
    /// device GPS location. Set via the map tab's long-press gesture.
    @Published var overrideLocation: CLLocation?

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

    /// The location to use for restaurant searches.
    ///
    /// Returns `overrideLocation` if the user has placed a pin on the map,
    /// otherwise falls back to the device GPS location.
    var effectiveLocation: CLLocation? {
        overrideLocation ?? currentLocation
    }

    /// A publisher that emits whenever `overrideLocation` changes.
    ///
    /// Satisfies the `LocationManaging` protocol requirement so the ViewModel
    /// can observe override changes without coupling to `@Published` directly.
    var overrideLocationPublisher: AnyPublisher<CLLocation?, Never> {
        $overrideLocation.eraseToAnyPublisher()
    }

    /// Sets a manual location override from the map tab.
    ///
    /// - Parameter location: The coordinate the user selected on the map.
    func setOverrideLocation(_ location: CLLocation) {
        overrideLocation = location
    }

    /// Clears the location override, reverting to the device GPS location.
    func clearOverrideLocation() {
        overrideLocation = nil
    }

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
