import Combine
import CoreLocation
@testable import RestaurantPicker
import XCTest

/// Tests for `LocationManager` computed properties and override logic.
///
/// Tests avoid triggering real `CLLocationManager` callbacks; instead they
/// exercise the logic that is fully under the class's own control:
/// `effectiveLocation`, `setOverrideLocation`, `clearOverrideLocation`,
/// `isAuthorized`, `isDenied`, and `overrideLocationPublisher`.
@MainActor
final class LocationManagerTests: XCTestCase {
    private var manager: LocationManager!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        manager = LocationManager()
    }

    override func tearDown() {
        cancellables.removeAll()
        manager = nil
        super.tearDown()
    }

    // MARK: - effectiveLocation

    func testEffectiveLocationIsNilWhenBothCurrentAndOverrideAreNil() {
        // Both are nil on fresh init (no GPS fix, no override).
        XCTAssertNil(manager.currentLocation)
        XCTAssertNil(manager.overrideLocation)
        XCTAssertNil(manager.effectiveLocation)
    }

    func testEffectiveLocationReturnsOverrideWhenOverrideIsSet() {
        // Arrange
        let pin = CLLocation(latitude: 48.8566, longitude: 2.3522) // Paris

        // Act
        manager.setOverrideLocation(pin)

        // Assert — override takes priority even when currentLocation is nil
        XCTAssertEqual(manager.effectiveLocation?.coordinate.latitude, pin.coordinate.latitude)
        XCTAssertEqual(manager.effectiveLocation?.coordinate.longitude, pin.coordinate.longitude)
    }

    func testEffectiveLocationReturnsOverrideEvenWhenCurrentLocationExists() {
        // Both values set — override must win.
        let gps = CLLocation(latitude: 40.7128, longitude: -74.0060) // New York
        let pin = CLLocation(latitude: 51.5074, longitude: -0.1278) // London

        // Simulate a GPS fix by writing to the published property directly
        // (requires access via @testable import).
        manager.currentLocation = gps
        manager.setOverrideLocation(pin)

        XCTAssertEqual(manager.effectiveLocation?.coordinate.latitude, pin.coordinate.latitude)
    }

    func testEffectiveLocationFallsBackToCurrentLocationAfterOverrideCleared() {
        // Arrange
        let gps = CLLocation(latitude: 40.7128, longitude: -74.0060)
        manager.currentLocation = gps
        manager.setOverrideLocation(CLLocation(latitude: 51.5074, longitude: -0.1278))

        // Act — clear the pin
        manager.clearOverrideLocation()

        // Assert — falls back to GPS
        XCTAssertEqual(manager.effectiveLocation?.coordinate.latitude, gps.coordinate.latitude)
    }

    // MARK: - setOverrideLocation / clearOverrideLocation

    func testSetOverrideLocationStoresTheCoordinate() {
        let location = CLLocation(latitude: 35.6762, longitude: 139.6503) // Tokyo
        manager.setOverrideLocation(location)

        XCTAssertNotNil(manager.overrideLocation)
        XCTAssertEqual(manager.overrideLocation?.coordinate.latitude, location.coordinate.latitude)
        XCTAssertEqual(manager.overrideLocation?.coordinate.longitude, location.coordinate.longitude)
    }

    func testClearOverrideLocationNilsTheOverride() {
        manager.setOverrideLocation(CLLocation(latitude: 35.6762, longitude: 139.6503))
        manager.clearOverrideLocation()

        XCTAssertNil(manager.overrideLocation)
    }

    // MARK: - isAuthorized

    func testIsNotAuthorizedWhenStatusIsNotDetermined() {
        // The initial status published by LocationManager.init() is .notDetermined
        // (the @Published default) before CLLocationManager fires its first callback.
        manager.authorizationStatus = .notDetermined
        XCTAssertFalse(manager.isAuthorized)
    }

    func testIsAuthorizedWhenStatusIsAuthorizedWhenInUse() {
        manager.authorizationStatus = .authorizedWhenInUse
        XCTAssertTrue(manager.isAuthorized)
    }

    func testIsAuthorizedWhenStatusIsAuthorizedAlways() {
        manager.authorizationStatus = .authorizedAlways
        XCTAssertTrue(manager.isAuthorized)
    }

    func testIsNotAuthorizedWhenStatusIsDenied() {
        manager.authorizationStatus = .denied
        XCTAssertFalse(manager.isAuthorized)
    }

    func testIsNotAuthorizedWhenStatusIsRestricted() {
        manager.authorizationStatus = .restricted
        XCTAssertFalse(manager.isAuthorized)
    }

    // MARK: - isDenied

    func testIsDeniedWhenStatusIsDenied() {
        manager.authorizationStatus = .denied
        XCTAssertTrue(manager.isDenied)
    }

    func testIsDeniedWhenStatusIsRestricted() {
        manager.authorizationStatus = .restricted
        XCTAssertTrue(manager.isDenied)
    }

    func testIsNotDeniedWhenStatusIsNotDetermined() {
        manager.authorizationStatus = .notDetermined
        XCTAssertFalse(manager.isDenied)
    }

    func testIsNotDeniedWhenStatusIsAuthorized() {
        manager.authorizationStatus = .authorizedWhenInUse
        XCTAssertFalse(manager.isDenied)
    }

    // MARK: - overrideLocationPublisher

    func testOverrideLocationPublisherEmitsNilInitially() {
        let expectation = expectation(description: "Publisher emits initial nil value")
        manager.overrideLocationPublisher
            .first()
            .sink { value in
                XCTAssertNil(value)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1)
    }

    func testOverrideLocationPublisherEmitsNewValueWhenOverrideIsSet() {
        let expectation = expectation(description: "Publisher emits the set location")
        let pin = CLLocation(latitude: 48.8566, longitude: 2.3522)

        manager.overrideLocationPublisher
            .dropFirst() // skip the initial nil
            .first()
            .sink { value in
                XCTAssertEqual(value?.coordinate.latitude, pin.coordinate.latitude)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        manager.setOverrideLocation(pin)
        wait(for: [expectation], timeout: 1)
    }

    func testOverrideLocationPublisherEmitsNilWhenOverrideCleared() {
        // Set a pin first, then clear it and observe the nil emission.
        manager.setOverrideLocation(CLLocation(latitude: 48.8566, longitude: 2.3522))

        let expectation = expectation(description: "Publisher emits nil after clear")

        manager.overrideLocationPublisher
            .dropFirst() // skip the currently-set value
            .first()
            .sink { value in
                XCTAssertNil(value)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        manager.clearOverrideLocation()
        wait(for: [expectation], timeout: 1)
    }
}
