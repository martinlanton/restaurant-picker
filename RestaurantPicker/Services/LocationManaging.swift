import Combine
import CoreLocation

// MARK: - LocationManaging

/// Defines the contract for providing the user's current and effective location.
///
/// Adopting this protocol allows `RestaurantViewModel` to be initialised with
/// a test double instead of the real `CLLocationManager`-backed `LocationManager`.
///
/// ## Adoption
/// ```swift
/// @MainActor
/// final class MockLocationManager: LocationManaging {
///     var currentLocation: CLLocation? = nil
///     var overrideLocation: CLLocation? = nil
///     // ...
/// }
/// ```
@MainActor
protocol LocationManaging: AnyObject {
    /// The most recently received GPS location, or `nil` if not yet available.
    var currentLocation: CLLocation? { get }

    /// A manually-set location that overrides the GPS location.
    ///
    /// When non-nil, `effectiveLocation` returns this value instead of
    /// `currentLocation`.
    var overrideLocation: CLLocation? { get }

    /// The current `CLAuthorizationStatus` for this app.
    var authorizationStatus: CLAuthorizationStatus { get }

    /// The location to use for restaurant searches.
    ///
    /// Returns `overrideLocation` if set, otherwise `currentLocation`.
    var effectiveLocation: CLLocation? { get }

    /// `true` when the app has "when in use" or "always" location access.
    var isAuthorized: Bool { get }

    /// `true` when the user has explicitly denied or restricted location access.
    var isDenied: Bool { get }

    /// A publisher that emits whenever `overrideLocation` changes.
    ///
    /// Used by `RestaurantViewModel` to re-trigger searches when the user
    /// sets or clears the map-pin override. Exposed as a publisher rather
    /// than a `@Published` wrapper so protocol conformers are not required
    /// to use `@Published` internally.
    var overrideLocationPublisher: AnyPublisher<CLLocation?, Never> { get }

    /// Requests "when in use" location authorisation from the system.
    func requestAuthorization()

    /// Requests a single one-time location update.
    func requestLocation()

    /// Sets a manual location override from the map tab.
    ///
    /// - Parameter location: The coordinate the user selected on the map.
    func setOverrideLocation(_ location: CLLocation)

    /// Clears the location override, reverting to the device GPS location.
    func clearOverrideLocation()
}
