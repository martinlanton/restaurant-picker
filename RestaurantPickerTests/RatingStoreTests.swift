import CoreLocation
@testable import RestaurantPicker
import XCTest

/// Tests for RatingStore persistence functionality.
final class RatingStoreTests: XCTestCase {
    private var store: RatingStore!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Use an ephemeral suite so tests don't pollute real UserDefaults.
        defaults = UserDefaults(suiteName: "RatingStoreTests")!
        defaults.removePersistentDomain(forName: "RatingStoreTests")
        store = RatingStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "RatingStoreTests")
        defaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Key Generation

    func testKeyIsConsistentForSameRestaurant() {
        // Arrange
        let restaurant = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)

        // Act
        let key1 = RatingStore.key(for: restaurant)
        let key2 = RatingStore.key(for: restaurant)

        // Assert
        XCTAssertEqual(key1, key2)
    }

    func testKeyDiffersForDifferentRestaurants() {
        // Arrange
        let restaurant1 = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)
        let restaurant2 = makeRestaurant(name: "Pizza Shop", lat: 40.7200, lon: -74.0100)

        // Act
        let key1 = RatingStore.key(for: restaurant1)
        let key2 = RatingStore.key(for: restaurant2)

        // Assert
        XCTAssertNotEqual(key1, key2)
    }

    func testKeySameForDifferentIDs() {
        // Arrange — same name + coordinate but different UUIDs
        let restaurant1 = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)
        let restaurant2 = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)

        // Assert — key is based on name + location, not UUID
        XCTAssertEqual(RatingStore.key(for: restaurant1), RatingStore.key(for: restaurant2))
    }

    // MARK: - Save & Retrieve

    func testNoRatingReturnsNil() {
        // Arrange
        let restaurant = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)

        // Act
        let rating = store.rating(for: restaurant)

        // Assert
        XCTAssertNil(rating)
    }

    func testSaveAndRetrieveRating() {
        // Arrange
        let restaurant = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)

        // Act
        store.setRating(4, for: restaurant)
        let rating = store.rating(for: restaurant)

        // Assert
        XCTAssertEqual(rating, 4)
    }

    func testUpdateRating() {
        // Arrange
        let restaurant = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)
        store.setRating(3, for: restaurant)

        // Act
        store.setRating(5, for: restaurant)
        let rating = store.rating(for: restaurant)

        // Assert
        XCTAssertEqual(rating, 5)
    }

    func testRemoveRatingBySettingNil() {
        // Arrange
        let restaurant = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)
        store.setRating(4, for: restaurant)

        // Act
        store.setRating(nil, for: restaurant)
        let rating = store.rating(for: restaurant)

        // Assert
        XCTAssertNil(rating)
    }

    func testRatingsAreIndependentPerRestaurant() {
        // Arrange
        let restaurant1 = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)
        let restaurant2 = makeRestaurant(name: "Pizza Shop", lat: 40.7200, lon: -74.0100)

        // Act
        store.setRating(5, for: restaurant1)
        store.setRating(2, for: restaurant2)

        // Assert
        XCTAssertEqual(store.rating(for: restaurant1), 5)
        XCTAssertEqual(store.rating(for: restaurant2), 2)
    }

    func testRatingClampsToValidRange() {
        // Arrange
        let restaurant = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)

        // Act & Assert — ratings should be clamped to 0...5
        store.setRating(-1, for: restaurant)
        XCTAssertEqual(store.rating(for: restaurant), 0)

        store.setRating(6, for: restaurant)
        XCTAssertEqual(store.rating(for: restaurant), 5)
    }

    // MARK: - Rejected (0) Rating Tests

    func testSaveAndRetrieveRejectedRating() {
        // Arrange
        let restaurant = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)

        // Act
        store.setRating(0, for: restaurant)
        let rating = store.rating(for: restaurant)

        // Assert — 0 means rejected, distinct from nil (unrated)
        XCTAssertEqual(rating, 0)
    }

    func testRejectedRatingIsDistinctFromUnrated() {
        // Arrange
        let restaurant = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)

        // Act
        store.setRating(0, for: restaurant)

        // Assert — not nil (that would mean unrated)
        XCTAssertNotNil(store.rating(for: restaurant))
        XCTAssertEqual(store.rating(for: restaurant), 0)
    }

    func testClearRejectedRating() {
        // Arrange
        let restaurant = makeRestaurant(name: "Thai Place", lat: 40.7128, lon: -74.0060)
        store.setRating(0, for: restaurant)

        // Act
        store.setRating(nil, for: restaurant)

        // Assert
        XCTAssertNil(store.rating(for: restaurant))
    }

    // MARK: - Helpers

    private func makeRestaurant(name: String, lat: Double, lon: Double) -> Restaurant {
        Restaurant(
            id: UUID(),
            name: name,
            coordinate: .init(latitude: lat, longitude: lon),
            distance: 500,
            category: "Thai",
            phoneNumber: nil,
            url: nil
        )
    }
}
