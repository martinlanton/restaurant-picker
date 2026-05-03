import CoreLocation
@testable import RestaurantPicker
import XCTest

/// Tests for `RestaurantSearchService` static deduplication helpers.
///
/// The `deduplicate(_:)` and `deduplicateAndSort(_:)` methods are pure static
/// functions with no network I/O, making them straightforward to unit test.
final class RestaurantSearchServiceTests: XCTestCase {
    // MARK: - Test Helpers

    /// Builds a minimal `Restaurant` for use in deduplication tests.
    ///
    /// - Parameters:
    ///   - name: Restaurant name.
    ///   - lat: Latitude (default 40.7128 — New York City).
    ///   - lon: Longitude (default -74.0060).
    ///   - distance: Distance from the user in metres (default 500).
    ///   - category: MapKit category string, if any.
    private func makeRestaurant(
        name: String,
        lat: Double = 40.7128,
        lon: Double = -74.0060,
        distance: Double = 500,
        category: String? = nil
    ) -> Restaurant {
        Restaurant(
            id: UUID(),
            name: name,
            coordinate: .init(latitude: lat, longitude: lon),
            distance: distance,
            category: category,
            cuisineTags: [],
            phoneNumber: nil,
            url: nil
        )
    }

    // MARK: - deduplicate(_:) Tests

    func testDeduplicateEmptyInputReturnsEmpty() {
        // Act
        let result = RestaurantSearchService.deduplicate([])

        // Assert
        XCTAssertTrue(result.isEmpty)
    }

    func testDeduplicateUniqueRestaurantsPreservesAll() {
        // Arrange — two different restaurants at different coordinates
        let r1 = makeRestaurant(name: "Thai Place", lat: 40.71)
        let r2 = makeRestaurant(name: "Pizza Shop", lat: 40.72)
        let input: [(Restaurant, String)] = [(r1, "Thai"), (r2, "Italian")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert
        XCTAssertEqual(result.count, 2)
        let names = Set(result.map(\.name))
        XCTAssertTrue(names.contains("Thai Place"))
        XCTAssertTrue(names.contains("Pizza Shop"))
    }

    func testDeduplicateSameNameAndProximityCombinesIntoOne() {
        // Arrange — same name, same coordinates → duplicate
        let r1 = makeRestaurant(name: "Ramen Bar")
        let r2 = makeRestaurant(name: "Ramen Bar") // identical coords
        let input: [(Restaurant, String)] = [(r1, "Ramen"), (r2, "Japanese")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert — combined into one
        XCTAssertEqual(result.count, 1)
    }

    func testDeduplicateSameNameDifferentLocationKeepsBoth() {
        // Arrange — chain scenario: same name at well-separated coordinates
        let r1 = makeRestaurant(name: "McDonald's", lat: 40.71, lon: -74.00)
        let r2 = makeRestaurant(name: "McDonald's", lat: 41.00, lon: -74.00) // ~32 km away
        let input: [(Restaurant, String)] = [(r1, "Burger"), (r2, "Burger")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert — both branches of the chain are kept
        XCTAssertEqual(result.count, 2)
    }

    func testDeduplicateMergesCuisineTags() {
        // Arrange — same place found by two different cuisine queries
        let r1 = makeRestaurant(name: "Fusion Place")
        let r2 = makeRestaurant(name: "Fusion Place") // same coords
        let input: [(Restaurant, String)] = [(r1, "Japanese"), (r2, "Korean")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert — single entry with both tags
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].cuisineTags.contains("Japanese"))
        XCTAssertTrue(result[0].cuisineTags.contains("Korean"))
    }

    func testDeduplicateGenericLabelNotAddedToCuisineTags() {
        // Arrange — "Restaurant" is a generic category and must be stripped
        let r1 = makeRestaurant(name: "Local Eatery")
        let input: [(Restaurant, String)] = [(r1, "Restaurant")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].cuisineTags.isEmpty, "Generic label must not appear in cuisineTags")
    }

    func testDeduplicateGenericLabelProducesNilCategory() {
        // Arrange
        let r1 = makeRestaurant(name: "Local Eatery")
        let input: [(Restaurant, String)] = [(r1, "Restaurant")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert — generic label must not become the display category
        XCTAssertNil(result[0].category)
    }

    func testDeduplicateSpecificLabelUpgradesGenericCategory() {
        // Arrange — first result has generic label, second has specific label
        let r1 = makeRestaurant(name: "Bangkok Palace")
        let r2 = makeRestaurant(name: "Bangkok Palace") // same location
        let input: [(Restaurant, String)] = [(r1, "Restaurant"), (r2, "Thai")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert — category upgraded from generic to "Thai"
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].category, "Thai")
    }

    func testDeduplicateSpecificCategoryNotReplacedByGenericLabel() {
        // Arrange — specific label arrives first, generic label arrives second
        let r1 = makeRestaurant(name: "Bangkok Palace")
        let r2 = makeRestaurant(name: "Bangkok Palace") // same location
        let input: [(Restaurant, String)] = [(r1, "Thai"), (r2, "Restaurant")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert — specific "Thai" category is preserved
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].category, "Thai")
    }

    func testDeduplicateGenericLabelNotAddedWhenMergingIntoExistingEntry() {
        // Arrange — first specific entry exists, second is generic for same place
        let r1 = makeRestaurant(name: "Seoul Kitchen")
        let r2 = makeRestaurant(name: "Seoul Kitchen") // same location
        let input: [(Restaurant, String)] = [(r1, "Korean"), (r2, "Family Restaurant")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert — "Family Restaurant" must not be added to cuisineTags
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(
            result[0].cuisineTags.contains("Family Restaurant"),
            "Generic label must not be merged into cuisineTags"
        )
        XCTAssertTrue(result[0].cuisineTags.contains("Korean"))
    }

    func testDeduplicatePreservesPhoneNumberFromFirstEntry() {
        // Arrange — first occurrence has a phone number
        let r1 = Restaurant(
            id: UUID(),
            name: "Noodle House",
            coordinate: .init(latitude: 40.71, longitude: -74.00),
            distance: 300,
            category: "Noodle",
            cuisineTags: [],
            phoneNumber: "555-1234",
            url: nil
        )
        let r2 = makeRestaurant(name: "Noodle House") // same location, no phone
        let input: [(Restaurant, String)] = [(r1, "Noodle"), (r2, "Chinese")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].phoneNumber, "555-1234")
    }

    func testDeduplicateFallsBackToSecondPhoneNumberWhenFirstIsNil() {
        // Arrange — first occurrence has no phone number, second does
        let r1 = makeRestaurant(name: "Noodle House")
        let r2 = Restaurant(
            id: UUID(),
            name: "Noodle House",
            coordinate: .init(latitude: 40.7128, longitude: -74.0060), // same coords as r1
            distance: 300,
            category: "Chinese",
            cuisineTags: [],
            phoneNumber: "555-9876",
            url: nil
        )
        let input: [(Restaurant, String)] = [(r1, "Noodle"), (r2, "Chinese")]

        // Act
        let result = RestaurantSearchService.deduplicate(input)

        // Assert — phone falls back to the second entry's value
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].phoneNumber, "555-9876")
    }

    // MARK: - deduplicateAndSort(_:) Tests

    func testDeduplicateAndSortOrdersByDistanceAscending() {
        // Arrange — near and far restaurants
        let near = makeRestaurant(name: "Near Place", lat: 40.71, distance: 200)
        let far = makeRestaurant(name: "Far Place", lat: 40.72, distance: 3000)
        let input: [(Restaurant, String)] = [(far, "Thai"), (near, "Italian")]

        // Act
        let result = RestaurantSearchService.deduplicateAndSort(input)

        // Assert
        XCTAssertEqual(result.first?.name, "Near Place")
        XCTAssertEqual(result.last?.name, "Far Place")
    }

    func testDeduplicateAndSortPreservesSpecificCategoryOverGeneric() {
        // Arrange — same place matched by both a specific and a generic query
        let r1 = makeRestaurant(name: "Spice Garden")
        let r2 = makeRestaurant(name: "Spice Garden") // same coords
        // Specific label sorted before generic so it arrives first in deduplicate
        let input: [(Restaurant, String)] = [(r1, "Restaurant"), (r2, "Indian")]

        // Act
        let result = RestaurantSearchService.deduplicateAndSort(input)

        // Assert — deduplicated to one entry with the specific category
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].category, "Indian")
    }

    func testDeduplicateAndSortReturnsEmptyForEmptyInput() {
        // Act & Assert
        XCTAssertTrue(RestaurantSearchService.deduplicateAndSort([]).isEmpty)
    }
}
