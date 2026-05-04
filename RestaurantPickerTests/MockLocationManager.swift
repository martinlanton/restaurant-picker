import Combine
import CoreLocation
@testable import RestaurantPicker

/// A fully-controllable test double for `LocationManaging`.
///
/// All properties are settable directly so tests can simulate GPS fixes,
/// authorization changes, and location-override transitions without
/// touching the real `CLLocationManager`.
@MainActor
final class MockLocationManager: LocationManaging {
    // MARK: - LocationManaging

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse

    var overrideLocation: CLLocation? {
        get { _overrideLocation }
        set {
            _overrideLocation = newValue
            overrideSubject.send(newValue)
        }
    }

    var effectiveLocation: CLLocation? {
        overrideLocation ?? currentLocation
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse ||
            authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied ||
            authorizationStatus == .restricted
    }

    var overrideLocationPublisher: AnyPublisher<CLLocation?, Never> {
        overrideSubject.eraseToAnyPublisher()
    }

    func requestAuthorization() {
        requestAuthorizationCallCount += 1
    }

    func requestLocation() {
        requestLocationCallCount += 1
    }

    func setOverrideLocation(_ location: CLLocation) {
        overrideLocation = location
    }

    func clearOverrideLocation() {
        overrideLocation = nil
    }

    // MARK: - Call-count tracking

    private(set) var requestAuthorizationCallCount = 0
    private(set) var requestLocationCallCount = 0

    // MARK: - Private

    private var _overrideLocation: CLLocation?
    private let overrideSubject = CurrentValueSubject<CLLocation?, Never>(nil)
}
