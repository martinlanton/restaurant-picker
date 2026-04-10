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

    // MARK: - Rating Filter Tests

    @MainActor
    func testMinimumRatingFilterShowsRatedRestaurantsAtOrAbove() async {
        // Arrange
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        // Rate restaurants: Thai=2, Pizza=4, Sushi=5
        ratingStore.setRating(2, for: sampleRestaurants[0])
        ratingStore.setRating(4, for: sampleRestaurants[1])
        ratingStore.setRating(5, for: sampleRestaurants[2])

        // Act — minimum 4 stars
        viewModel.minimumRating = 4

        // Assert — Pizza(4) and Sushi(5) pass
        XCTAssertEqual(viewModel.filteredRestaurants.count, 2)
        let names = Set(viewModel.filteredRestaurants.map(\.name))
        XCTAssertTrue(names.contains("Pizza Shop"))
        XCTAssertTrue(names.contains("Sushi Bar"))
    }

    @MainActor
    func testMinimumRatingFilterExcludesUnratedRestaurants() async {
        // Arrange
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        // Only rate Thai=3, others unrated
        ratingStore.setRating(3, for: sampleRestaurants[0])

        // Act
        viewModel.minimumRating = 2

        // Assert — only Thai Place (rated 3 >= 2); unrated excluded
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Thai Place")
    }

    @MainActor
    func testNilMinimumRatingShowsAll() async {
        // Arrange
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        // Act
        viewModel.minimumRating = nil

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 3)
    }

    @MainActor
    func testMinimumRatingCombinesWithDistanceFilter() async {
        // Arrange
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)

        // Rate all highly
        ratingStore.setRating(5, for: sampleRestaurants[0])
        ratingStore.setRating(5, for: sampleRestaurants[1])
        ratingStore.setRating(5, for: sampleRestaurants[2])

        // Act — 5 star filter + 3km radius (Sushi Bar at 5500m excluded by distance)
        viewModel.minimumRating = 5
        viewModel.filterRadius = 3000

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 2)
    }

    @MainActor
    func testActiveFilterCountIncludesRating() async {
        // Arrange
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)

        // Act
        viewModel.selectedCuisines = ["Thai"]
        viewModel.minimumRating = 3

        // Assert — 1 cuisine include + 1 rating filter = 2
        XCTAssertEqual(viewModel.activeCuisineFilterCount, 2)
    }

    // MARK: - Weighted Selection Tests

    @MainActor
    func testRatingWeightValues() async {
        // Assert the quadratic weight table
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 1), 0.25, accuracy: 0.001)
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 2), 0.50, accuracy: 0.001)
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 3), 1.00, accuracy: 0.001)
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 4), 2.00, accuracy: 0.001)
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 5), 4.00, accuracy: 0.001)
    }

    @MainActor
    func testRatingWeightForUnratedIsOne() async {
        // Unrated restaurants should have weight 1.0 (same as 3 stars)
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: nil), 1.0, accuracy: 0.001)
    }

    @MainActor
    func testWeightedSelectionFavorsHigherRatings() async {
        // Arrange — one restaurant rated 5 (weight 4), one rated 1 (weight 0.25)
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let restaurants = [
            sampleRestaurants[0], // Thai Place
            sampleRestaurants[1], // Pizza Shop
        ]
        let viewModel = RestaurantViewModel(restaurants: restaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        ratingStore.setRating(1, for: restaurants[0]) // weight 0.25
        ratingStore.setRating(5, for: restaurants[1]) // weight 4.0

        // Act — run many selections
        var counts: [String: Int] = ["Thai Place": 0, "Pizza Shop": 0]
        for _ in 0 ..< 1000 {
            viewModel.selectRandomRestaurant()
            if let name = viewModel.selectedRestaurant?.name {
                counts[name, default: 0] += 1
            }
        }

        // Assert — Pizza Shop (weight 4.0) should be picked significantly more often
        // Expected ratio: ~4:0.25 = 16:1, so Pizza should get ~94% of picks
        let pizzaCount = counts["Pizza Shop"] ?? 0
        XCTAssertGreaterThan(pizzaCount, 800, "Pizza Shop (5 stars) should be picked >80% of the time, got \(pizzaCount)/1000")
    }

    @MainActor
    func testWeightedSelectionDisabledWhenRatingFilterActive() async {
        // Arrange — when minimumRating is set, selection should be uniform (no weighting)
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        // Rate all 5 stars so they all pass the filter
        for r in sampleRestaurants {
            ratingStore.setRating(5, for: r)
        }
        viewModel.minimumRating = 5

        // Act
        var counts: [String: Int] = [:]
        for _ in 0 ..< 900 {
            viewModel.selectRandomRestaurant()
            if let name = viewModel.selectedRestaurant?.name {
                counts[name, default: 0] += 1
            }
        }

        // Assert — all 3 should be picked at least some times (uniform)
        for name in ["Thai Place", "Pizza Shop", "Sushi Bar"] {
            XCTAssertGreaterThan(counts[name] ?? 0, 100, "\(name) should be picked >100/900 times in uniform selection")
        }
    }

    // MARK: - Rating Filter Options

    @MainActor
    func testRatingFilterOptions() async {
        // Assert the static options list
        let options = RestaurantViewModel.ratingFilterOptions
        XCTAssertEqual(options.count, 6)
        XCTAssertEqual(options[0].label, "All")
        XCTAssertNil(options[0].value)
        XCTAssertEqual(options[1].label, "1+")
        XCTAssertEqual(options[1].value, 1)
        XCTAssertEqual(options[4].label, "4+")
        XCTAssertEqual(options[4].value, 4)
        XCTAssertEqual(options[5].label, "5")
        XCTAssertEqual(options[5].value, 5)
    }

    // MARK: - Test Helpers

    private func makeTestDefaults() -> UserDefaults {
        let suite = "RestaurantViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
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

