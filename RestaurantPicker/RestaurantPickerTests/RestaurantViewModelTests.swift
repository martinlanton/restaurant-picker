import CoreLocation
import XCTest
@testable import RestaurantPicker

/// Tests for RestaurantViewModel functionality.
final class RestaurantViewModelTests: XCTestCase {
    // MARK: - Test Data

    private let sampleRestaurants = [
        Restaurant(
            id: UUID(),
            name: "Thai Place",
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 500,
            category: "Thai",
            phoneNumber: nil,
            url: nil
        ),
        Restaurant(
            id: UUID(),
            name: "Pizza Shop",
            coordinate: .init(latitude: 40.7200, longitude: -74.0100),
            distance: 2000,
            category: "Italian",
            phoneNumber: nil,
            url: nil
        ),
        Restaurant(
            id: UUID(),
            name: "Sushi Bar",
            coordinate: .init(latitude: 40.7300, longitude: -74.0200),
            distance: 5500,
            category: "Japanese",
            phoneNumber: nil,
            url: nil
        )
    ]

    // MARK: - Filter Tests

    @MainActor
    func testFilteringByDistance() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.filterRadius = 1000

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Thai Place")
    }

    @MainActor
    func testFilteringWithLargerRadius() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.filterRadius = 3000

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 2)
    }

    @MainActor
    func testNoFilterShowsAllRestaurants() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.filterRadius = nil

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 3)
    }

    // MARK: - Random Selection Tests

    @MainActor
    func testRandomSelectionReturnsRestaurant() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.selectRandomRestaurant()

        // Assert
        XCTAssertNotNil(viewModel.selectedRestaurant)
        XCTAssertTrue(viewModel.showSelectedRestaurant)
    }

    @MainActor
    func testRandomSelectionFromFilteredList() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = 1000

        // Act
        viewModel.selectRandomRestaurant()

        // Assert
        XCTAssertNotNil(viewModel.selectedRestaurant)
        XCTAssertEqual(viewModel.selectedRestaurant?.name, "Thai Place")
    }

    @MainActor
    func testRandomSelectionWithEmptyList() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: [])

        // Act
        viewModel.selectRandomRestaurant()

        // Assert
        XCTAssertNil(viewModel.selectedRestaurant)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Clear Selection Tests

    @MainActor
    func testClearSelection() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.selectRandomRestaurant()

        // Precondition
        XCTAssertNotNil(viewModel.selectedRestaurant)

        // Act
        viewModel.clearSelection()

        // Assert
        XCTAssertNil(viewModel.selectedRestaurant)
        XCTAssertFalse(viewModel.showSelectedRestaurant)
    }
}

// MARK: - Restaurant Model Tests

final class RestaurantTests: XCTestCase {
    func testFormattedDistanceInMeters() {
        // Arrange
        let restaurant = Restaurant(
            id: UUID(),
            name: "Test",
            coordinate: .init(latitude: 0, longitude: 0),
            distance: 350,
            category: nil,
            phoneNumber: nil,
            url: nil
        )

        // Assert
        XCTAssertEqual(restaurant.formattedDistance, "350 m")
    }

    func testFormattedDistanceInKilometers() {
        // Arrange
        let restaurant = Restaurant(
            id: UUID(),
            name: "Test",
            coordinate: .init(latitude: 0, longitude: 0),
            distance: 2500,
            category: nil,
            phoneNumber: nil,
            url: nil
        )

        // Assert
        XCTAssertEqual(restaurant.formattedDistance, "2.5 km")
    }

    func testRestaurantEquality() {
        // Arrange
        let id = UUID()
        let restaurant1 = Restaurant(
            id: id,
            name: "Thai Place",
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 500,
            category: "Thai",
            phoneNumber: nil,
            url: nil
        )
        let restaurant2 = Restaurant(
            id: id,
            name: "Thai Place",
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 500,
            category: "Thai",
            phoneNumber: nil,
            url: nil
        )

        // Assert
        XCTAssertEqual(restaurant1, restaurant2)
    }
}

