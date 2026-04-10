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

    // MARK: - Cuisine Filter Tests

    @MainActor
    func testAvailableCuisinesReturnsUniqueSortedCategories() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        let cuisines = viewModel.availableCuisines

        // Assert
        XCTAssertEqual(cuisines, ["Italian", "Japanese", "Thai"])
    }

    @MainActor
    func testAvailableCuisinesExcludesNilCategories() async {
        // Arrange
        let restaurants = sampleRestaurants + [
            Restaurant(
                id: UUID(),
                name: "Unknown Place",
                coordinate: .init(latitude: 40.7400, longitude: -74.0300),
                distance: 600,
                category: nil,
                phoneNumber: nil,
                url: nil
            ),
        ]
        let viewModel = RestaurantViewModel(restaurants: restaurants)

        // Act
        let cuisines = viewModel.availableCuisines

        // Assert — nil categories should not appear
        XCTAssertEqual(cuisines, ["Italian", "Japanese", "Thai"])
    }

    @MainActor
    func testFilterBySingleCuisine() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.selectedCuisines = ["Thai"]

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Thai Place")
    }

    @MainActor
    func testFilterByMultipleCuisines() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.selectedCuisines = ["Thai", "Japanese"]

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 2)
        let names = Set(viewModel.filteredRestaurants.map(\.name))
        XCTAssertTrue(names.contains("Thai Place"))
        XCTAssertTrue(names.contains("Sushi Bar"))
    }

    @MainActor
    func testEmptyCuisineSelectionShowsAllRestaurants() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.selectedCuisines = []

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 3)
    }

    @MainActor
    func testCuisineAndDistanceFiltersCombine() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act — "Japanese" (Sushi Bar) is at 5500m, radius 3000 should exclude it
        viewModel.selectedCuisines = ["Thai", "Japanese"]
        viewModel.filterRadius = 3000

        // Assert — only Thai Place (500m) passes both filters
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Thai Place")
    }

    @MainActor
    func testCuisineFilterIncludesRestaurantsWithNilCategory() async {
        // Arrange — a restaurant with nil category should show when no cuisine filter is active
        let restaurants = sampleRestaurants + [
            Restaurant(
                id: UUID(),
                name: "Mystery Spot",
                coordinate: .init(latitude: 40.7400, longitude: -74.0300),
                distance: 600,
                category: nil,
                phoneNumber: nil,
                url: nil
            ),
        ]
        let viewModel = RestaurantViewModel(restaurants: restaurants)
        viewModel.filterRadius = nil

        // Act — no cuisine filter
        viewModel.selectedCuisines = []

        // Assert — all 4 restaurants shown
        XCTAssertEqual(viewModel.filteredRestaurants.count, 4)
    }

    @MainActor
    func testCuisineFilterExcludesRestaurantsWithNilCategory() async {
        // Arrange
        let restaurants = sampleRestaurants + [
            Restaurant(
                id: UUID(),
                name: "Mystery Spot",
                coordinate: .init(latitude: 40.7400, longitude: -74.0300),
                distance: 600,
                category: nil,
                phoneNumber: nil,
                url: nil
            ),
        ]
        let viewModel = RestaurantViewModel(restaurants: restaurants)
        viewModel.filterRadius = nil

        // Act — filter by Thai only
        viewModel.selectedCuisines = ["Thai"]

        // Assert — only Thai Place, not Mystery Spot (nil category)
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Thai Place")
    }

    // MARK: - Exclude Cuisine Filter Tests

    @MainActor
    func testExcludeSingleCuisine() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.excludedCuisines = ["Thai"]

        // Assert — Thai Place excluded, 2 remain
        XCTAssertEqual(viewModel.filteredRestaurants.count, 2)
        let names = Set(viewModel.filteredRestaurants.map(\.name))
        XCTAssertFalse(names.contains("Thai Place"))
        XCTAssertTrue(names.contains("Pizza Shop"))
        XCTAssertTrue(names.contains("Sushi Bar"))
    }

    @MainActor
    func testExcludeMultipleCuisines() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.excludedCuisines = ["Thai", "Italian"]

        // Assert — only Sushi Bar (Japanese) remains
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Sushi Bar")
    }

    @MainActor
    func testEmptyExcludeShowsAllRestaurants() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.excludedCuisines = []

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 3)
    }

    @MainActor
    func testExcludeAndIncludeCombine() async {
        // Arrange — include Thai + Japanese, exclude Japanese
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.selectedCuisines = ["Thai", "Japanese"]
        viewModel.excludedCuisines = ["Japanese"]

        // Assert — only Thai Place: included by selectedCuisines, not excluded
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Thai Place")
    }

    @MainActor
    func testExcludeAndDistanceCombine() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act — exclude Thai, radius 3000 (excludes Sushi Bar at 5500)
        viewModel.excludedCuisines = ["Thai"]
        viewModel.filterRadius = 3000

        // Assert — only Pizza Shop (Italian, 2000m)
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Pizza Shop")
    }

    @MainActor
    func testExcludeDoesNotAffectNilCategoryWhenNoInclude() async {
        // Arrange — restaurant with nil category should NOT be excluded
        let restaurants = sampleRestaurants + [
            Restaurant(
                id: UUID(),
                name: "Mystery Spot",
                coordinate: .init(latitude: 40.7400, longitude: -74.0300),
                distance: 600,
                category: nil,
                phoneNumber: nil,
                url: nil
            ),
        ]
        let viewModel = RestaurantViewModel(restaurants: restaurants)
        viewModel.filterRadius = nil

        // Act — exclude Thai only
        viewModel.excludedCuisines = ["Thai"]

        // Assert — Mystery Spot (nil category) remains, Thai Place excluded
        XCTAssertEqual(viewModel.filteredRestaurants.count, 3)
        let names = Set(viewModel.filteredRestaurants.map(\.name))
        XCTAssertTrue(names.contains("Mystery Spot"))
        XCTAssertFalse(names.contains("Thai Place"))
    }

    // MARK: - Active Filter Count Tests

    @MainActor
    func testActiveCuisineFilterCountWithNoFilters() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Assert
        XCTAssertEqual(viewModel.activeCuisineFilterCount, 0)
    }

    @MainActor
    func testActiveCuisineFilterCountWithIncludeOnly() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.selectedCuisines = ["Thai", "Japanese"]

        // Assert
        XCTAssertEqual(viewModel.activeCuisineFilterCount, 2)
    }

    @MainActor
    func testActiveCuisineFilterCountWithExcludeOnly() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.excludedCuisines = ["Italian"]

        // Assert
        XCTAssertEqual(viewModel.activeCuisineFilterCount, 1)
    }

    @MainActor
    func testActiveCuisineFilterCountWithBoth() async {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.selectedCuisines = ["Thai"]
        viewModel.excludedCuisines = ["Italian", "Japanese"]

        // Assert
        XCTAssertEqual(viewModel.activeCuisineFilterCount, 3)
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

