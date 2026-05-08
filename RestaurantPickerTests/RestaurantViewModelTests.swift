import CoreLocation
@testable import RestaurantPicker
import XCTest

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
            cuisineTags: ["Thai"],
            phoneNumber: nil,
            url: nil
        ),
        Restaurant(
            id: UUID(),
            name: "Pizza Shop",
            coordinate: .init(latitude: 40.7200, longitude: -74.0100),
            distance: 2000,
            category: "Italian",
            cuisineTags: ["Italian"],
            phoneNumber: nil,
            url: nil
        ),
        Restaurant(
            id: UUID(),
            name: "Sushi Bar",
            coordinate: .init(latitude: 40.7300, longitude: -74.0200),
            distance: 5500,
            category: "Japanese",
            cuisineTags: ["Japanese"],
            phoneNumber: nil,
            url: nil
        ),
    ]

    // MARK: - Default State Tests

    @MainActor
    func testDefaultFilterRadiusIs500m() {
        // The ViewModel must start with a 500 m radius so nearby searches are the
        // default experience without the user having to configure anything.
        let vm = RestaurantViewModel(
            locationManager: MockLocationManager(),
            searchService: MockRestaurantSearchService()
        )
        XCTAssertEqual(vm.filterRadius, 500)
    }

    @MainActor
    func testDefaultFilterRadiusAppliedToIncomingResults() {
        // Restaurants beyond 500 m must be filtered out of the display list when
        // the ViewModel is freshly initialised (no explicit filterRadius set).
        let locationManager = MockLocationManager()
        locationManager.currentLocation = CLLocation(latitude: 40.7128, longitude: -74.0060)
        let vm = RestaurantViewModel(
            locationManager: locationManager,
            searchService: MockRestaurantSearchService()
        )

        let nearRestaurant = Restaurant(
            id: UUID(), name: "Near Place",
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 400, category: nil, cuisineTags: [], phoneNumber: nil, url: nil
        )
        let farRestaurant = Restaurant(
            id: UUID(), name: "Far Place",
            coordinate: .init(latitude: 40.7200, longitude: -74.0100),
            distance: 600, category: nil, cuisineTags: [], phoneNumber: nil, url: nil
        )

        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.handleOrchestratorUpdate(OrchestratorUpdate(
            jobID: jobID,
            location: CLLocation(latitude: 40.7128, longitude: -74.0060),
            snapshot: [nearRestaurant, farRestaurant],
            isJobComplete: false
        ))

        XCTAssertEqual(vm.filteredRestaurants.count, 1)
        XCTAssertEqual(vm.filteredRestaurants.first?.name, "Near Place")
    }

    // MARK: - Filter Tests

    @MainActor
    func testFilteringByDistance() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.filterRadius = 1000

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Thai Place")
    }

    @MainActor
    func testFilteringWithLargerRadius() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.filterRadius = 3000

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 2)
    }

    @MainActor
    func testNoFilterShowsAllRestaurants() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.filterRadius = nil

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 3)
    }

    // MARK: - Random Selection Tests

    @MainActor
    func testRandomSelectionReturnsRestaurant() {
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
    func testRandomSelectionFromFilteredList() {
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
    func testRandomSelectionWithEmptyList() {
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
    func testClearSelection() {
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
    func testAvailableCuisinesIsStaticAndSorted() {
        // Arrange — availableCuisines should be the same regardless of restaurant data
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        let cuisines = viewModel.availableCuisines

        // Assert — derived from cuisineQueries, sorted, excluding generic labels
        XCTAssertFalse(cuisines.isEmpty)
        XCTAssertEqual(cuisines, cuisines.sorted())

        // Generic labels must be excluded
        XCTAssertFalse(cuisines.contains("Restaurant"))
        XCTAssertFalse(cuisines.contains("Family Restaurant"))
        XCTAssertFalse(cuisines.contains("Food Court"))

        // Original cuisines still present
        XCTAssertTrue(cuisines.contains("Japanese"))
        XCTAssertTrue(cuisines.contains("Italian"))
        XCTAssertTrue(cuisines.contains("Yakiniku"))

        // Newly added cuisines present
        XCTAssertTrue(cuisines.contains("Filipino"))
        XCTAssertTrue(cuisines.contains("Malaysian"))
        XCTAssertTrue(cuisines.contains("Korean"))
        XCTAssertTrue(cuisines.contains("German"))
        XCTAssertTrue(cuisines.contains("Cajun"))
        XCTAssertTrue(cuisines.contains("Poke"))
        XCTAssertTrue(cuisines.contains("Kebab"))
        XCTAssertTrue(cuisines.contains("Deli"))
        XCTAssertTrue(cuisines.contains("Ice Cream"))
    }

    @MainActor
    func testAvailableCuisinesDoesNotDependOnRestaurantData() {
        // Arrange — empty restaurant list should still have all cuisines
        let viewModel = RestaurantViewModel(restaurants: [])

        // Act
        let cuisines = viewModel.availableCuisines

        // Assert
        XCTAssertFalse(cuisines.isEmpty)
        XCTAssertTrue(cuisines.contains("Thai"))
    }

    @MainActor
    func testFilterBySingleCuisine() {
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
    func testFilterByMultipleCuisines() {
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
    func testEmptyCuisineSelectionShowsAllRestaurants() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.selectedCuisines = []

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 3)
    }

    @MainActor
    func testCuisineAndDistanceFiltersCombine() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act — "Japanese" (Sushi Bar) is at 5500m, radius 3000 should exclude it
        viewModel.selectedCuisines = ["Thai", "Japanese"]
        viewModel.filterRadius = 3000

        // Assert — only Thai Place (500m) passes both filters
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Thai Place")
    }

    // MARK: - Multi-Tag Cuisine Filter Tests

    @MainActor
    func testIncludeFilterMatchesFirstOfMultipleTags() {
        // A restaurant tagged ["Thai", "Japanese"] appears when include filter selects "Thai"
        let fusionRestaurant = Restaurant(
            id: UUID(),
            name: "Thai-Japanese Fusion",
            coordinate: .init(latitude: 40.7400, longitude: -74.0300),
            distance: 600,
            category: "Thai",
            cuisineTags: ["Thai", "Japanese"],
            phoneNumber: nil,
            url: nil
        )
        let viewModel = RestaurantViewModel(restaurants: [fusionRestaurant])
        viewModel.filterRadius = nil
        viewModel.selectedCuisines = ["Thai"]
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
    }

    @MainActor
    func testIncludeFilterMatchesSecondOfMultipleTags() {
        // A restaurant tagged ["Thai", "Japanese"] appears when include filter selects "Japanese"
        let fusionRestaurant = Restaurant(
            id: UUID(),
            name: "Thai-Japanese Fusion",
            coordinate: .init(latitude: 40.7400, longitude: -74.0300),
            distance: 600,
            category: "Thai",
            cuisineTags: ["Thai", "Japanese"],
            phoneNumber: nil,
            url: nil
        )
        let viewModel = RestaurantViewModel(restaurants: [fusionRestaurant])
        viewModel.filterRadius = nil
        viewModel.selectedCuisines = ["Japanese"]
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
    }

    @MainActor
    func testIncludeFilterHidesRestaurantWhenNoTagMatches() {
        // A restaurant tagged ["Thai", "Japanese"] is hidden when include filter selects an unrelated cuisine
        let fusionRestaurant = Restaurant(
            id: UUID(),
            name: "Thai-Japanese Fusion",
            coordinate: .init(latitude: 40.7400, longitude: -74.0300),
            distance: 600,
            category: "Thai",
            cuisineTags: ["Thai", "Japanese"],
            phoneNumber: nil,
            url: nil
        )
        let viewModel = RestaurantViewModel(restaurants: [fusionRestaurant])
        viewModel.filterRadius = nil
        viewModel.selectedCuisines = ["Italian"]
        XCTAssertEqual(viewModel.filteredRestaurants.count, 0)
    }

    @MainActor
    func testExcludeFilterHidesRestaurantWhenOneTagMatches() {
        // A restaurant tagged ["Thai", "Japanese"] is excluded when one of its tags is in the exclude list
        let fusionRestaurant = Restaurant(
            id: UUID(),
            name: "Thai-Japanese Fusion",
            coordinate: .init(latitude: 40.7400, longitude: -74.0300),
            distance: 600,
            category: "Thai",
            cuisineTags: ["Thai", "Japanese"],
            phoneNumber: nil,
            url: nil
        )
        let viewModel = RestaurantViewModel(restaurants: [fusionRestaurant])
        viewModel.filterRadius = nil
        viewModel.excludedCuisines = ["Japanese"]
        XCTAssertEqual(viewModel.filteredRestaurants.count, 0)
    }

    @MainActor
    func testExcludeFilterKeepsRestaurantWhenNoTagMatches() {
        // A restaurant tagged ["Thai", "Japanese"] remains visible when the exclude filter targets a different cuisine
        let fusionRestaurant = Restaurant(
            id: UUID(),
            name: "Thai-Japanese Fusion",
            coordinate: .init(latitude: 40.7400, longitude: -74.0300),
            distance: 600,
            category: "Thai",
            cuisineTags: ["Thai", "Japanese"],
            phoneNumber: nil,
            url: nil
        )
        let viewModel = RestaurantViewModel(restaurants: [fusionRestaurant])
        viewModel.filterRadius = nil
        viewModel.excludedCuisines = ["Italian"]
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
    }

    @MainActor
    func testExcludeWinsWhenIncludeAndExcludeEachMatchDifferentTag() {
        // A restaurant tagged ["Thai", "Japanese"] is excluded when include matches "Thai" but exclude matches "Japanese"
        let fusionRestaurant = Restaurant(
            id: UUID(),
            name: "Thai-Japanese Fusion",
            coordinate: .init(latitude: 40.7400, longitude: -74.0300),
            distance: 600,
            category: "Thai",
            cuisineTags: ["Thai", "Japanese"],
            phoneNumber: nil,
            url: nil
        )
        let viewModel = RestaurantViewModel(restaurants: [fusionRestaurant])
        viewModel.filterRadius = nil
        viewModel.selectedCuisines = ["Thai"]
        viewModel.excludedCuisines = ["Japanese"]
        XCTAssertEqual(viewModel.filteredRestaurants.count, 0)
    }

    @MainActor
    func testCuisineFilterIncludesRestaurantsWithNilCategory() {
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
    func testCuisineFilterExcludesRestaurantsWithNilCategory() {
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
    func testExcludeSingleCuisine() {
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
    func testExcludeMultipleCuisines() {
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
    func testEmptyExcludeShowsAllRestaurants() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.excludedCuisines = []

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 3)
    }

    @MainActor
    func testExcludeAndIncludeCombine() {
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
    func testExcludeAndDistanceCombine() {
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
    func testExcludeDoesNotAffectNilCategoryWhenNoInclude() {
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
    func testActiveCuisineFilterCountWithNoFilters() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Assert
        XCTAssertEqual(viewModel.activeCuisineFilterCount, 0)
    }

    @MainActor
    func testActiveCuisineFilterCountWithIncludeOnly() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.selectedCuisines = ["Thai", "Japanese"]

        // Assert
        XCTAssertEqual(viewModel.activeCuisineFilterCount, 2)
    }

    @MainActor
    func testActiveCuisineFilterCountWithExcludeOnly() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act
        viewModel.excludedCuisines = ["Italian"]

        // Assert
        XCTAssertEqual(viewModel.activeCuisineFilterCount, 1)
    }

    @MainActor
    func testActiveCuisineFilterCountWithBoth() {
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
    func testMinimumRatingFilterShowsRatedRestaurantsAtOrAbove() {
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
    func testMinimumRatingFilterExcludesUnratedRestaurants() {
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
    func testNilMinimumRatingShowsAll() {
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
    func testMinimumRatingCombinesWithDistanceFilter() {
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
    func testActiveFilterCountIncludesRating() {
        // Arrange
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)

        // Act
        viewModel.selectedCuisines = ["Thai"]
        viewModel.minimumRating = 3

        // Assert — 1 cuisine include + 1 rating filter = 2
        XCTAssertEqual(viewModel.activeCuisineFilterCount, 2)
    }

    @MainActor
    func testRatingAndCuisineIncludeFilterCombine() {
        // Arrange — Thai Place rated 2, others rated higher; include Thai only
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        ratingStore.setRating(2, for: sampleRestaurants[0]) // Thai = 2 stars
        ratingStore.setRating(4, for: sampleRestaurants[1]) // Italian = 4 stars
        ratingStore.setRating(5, for: sampleRestaurants[2]) // Japanese = 5 stars

        // Act — only Thai included, but Thai's rating (2) is below the minimum (3)
        viewModel.selectedCuisines = ["Thai"]
        viewModel.minimumRating = 3

        // Assert — nothing passes both filters
        XCTAssertEqual(viewModel.filteredRestaurants.count, 0)
    }

    @MainActor
    func testRatingAndCuisineExcludeFilterCombine() {
        // Arrange — all rated 4 stars; exclude Italian
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        ratingStore.setRating(4, for: sampleRestaurants[0]) // Thai = 4 stars
        ratingStore.setRating(4, for: sampleRestaurants[1]) // Italian = 4 stars
        ratingStore.setRating(4, for: sampleRestaurants[2]) // Japanese = 4 stars

        // Act
        viewModel.excludedCuisines = ["Italian"]
        viewModel.minimumRating = 3

        // Assert — Italian excluded even though it meets the rating requirement
        XCTAssertEqual(viewModel.filteredRestaurants.count, 2)
        let names = Set(viewModel.filteredRestaurants.map(\.name))
        XCTAssertFalse(names.contains("Pizza Shop"))
        XCTAssertTrue(names.contains("Thai Place"))
        XCTAssertTrue(names.contains("Sushi Bar"))
    }

    // MARK: - Weighted Selection Tests

    @MainActor
    func testRatingWeightValues() {
        // Assert the quadratic weight table
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 1), 0.25, accuracy: 0.001)
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 2), 0.50, accuracy: 0.001)
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 3), 1.00, accuracy: 0.001)
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 4), 2.00, accuracy: 0.001)
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 5), 4.00, accuracy: 0.001)
    }

    @MainActor
    func testRatingWeightForUnratedIsOne() {
        // Unrated restaurants should have weight 1.0 (same as 3 stars)
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: nil), 1.0, accuracy: 0.001)
    }

    @MainActor
    func testWeightedSelectionFavorsHigherRatings() {
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
        XCTAssertGreaterThan(
            pizzaCount,
            800,
            "Pizza Shop (5 stars) should be picked >80% of the time, got \(pizzaCount)/1000"
        )
    }

    @MainActor
    func testWeightedSelectionDisabledWhenRatingFilterActive() {
        // Arrange — when minimumRating is set, selection should be uniform (no weighting)
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        // Rate all 5 stars so they all pass the filter
        for restaurant in sampleRestaurants {
            ratingStore.setRating(5, for: restaurant)
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
    func testRatingFilterOptions() {
        // Assert the static options list includes Unrated
        let options = RestaurantViewModel.ratingFilterOptions
        XCTAssertEqual(options.count, 7)
        XCTAssertEqual(options[0].label, "All")
        XCTAssertNil(options[0].value)
        XCTAssertEqual(options[1].label, "Unrated")
        XCTAssertEqual(options[1].value, -1)
        XCTAssertEqual(options[2].label, "1+")
        XCTAssertEqual(options[2].value, 1)
        XCTAssertEqual(options[5].label, "4+")
        XCTAssertEqual(options[5].value, 4)
        XCTAssertEqual(options[6].label, "5")
        XCTAssertEqual(options[6].value, 5)
    }

    // MARK: - Rejected (0) Rating Tests

    @MainActor
    func testRejectedRatingWeightIsZero() {
        // Rejected restaurants should have weight 0 — never picked randomly
        XCTAssertEqual(RestaurantViewModel.ratingWeight(for: 0), 0.0, accuracy: 0.001)
    }

    @MainActor
    func testRejectedRestaurantsExcludedFromStarFilter() {
        // Arrange — rejected restaurants should not appear even with 1+ filter
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        ratingStore.setRating(0, for: sampleRestaurants[0]) // Thai = rejected
        ratingStore.setRating(3, for: sampleRestaurants[1]) // Pizza = 3 stars
        ratingStore.setRating(5, for: sampleRestaurants[2]) // Sushi = 5 stars

        // Act
        viewModel.minimumRating = 1

        // Assert — rejected (0) does NOT pass >=1 filter
        XCTAssertEqual(viewModel.filteredRestaurants.count, 2)
        let names = Set(viewModel.filteredRestaurants.map(\.name))
        XCTAssertFalse(names.contains("Thai Place"))
    }

    // MARK: - Unrated-Only Filter Tests

    @MainActor
    func testUnratedOnlyFilterShowsOnlyUnratedRestaurants() {
        // Arrange
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        // Rate Thai and Pizza, leave Sushi unrated
        ratingStore.setRating(3, for: sampleRestaurants[0])
        ratingStore.setRating(0, for: sampleRestaurants[1]) // rejected

        // Act — minimumRating = -1 means "unrated only"
        viewModel.minimumRating = -1

        // Assert — only Sushi Bar (unrated) shown
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Sushi Bar")
    }

    @MainActor
    func testUnratedFilterExcludesRejectedRestaurants() {
        // Arrange — rejected (0) is NOT unrated (nil)
        let ratingStore = RatingStore(defaults: makeTestDefaults())
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants, ratingStore: ratingStore)
        viewModel.filterRadius = nil

        ratingStore.setRating(0, for: sampleRestaurants[0]) // rejected
        ratingStore.setRating(0, for: sampleRestaurants[1]) // rejected
        // Sushi unrated (nil)

        // Act
        viewModel.minimumRating = -1

        // Assert — only Sushi Bar
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Sushi Bar")
    }

    // MARK: - Search Text Filter Tests

    @MainActor
    func testSearchTextFiltersByName() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.searchText = "Pizza"

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Pizza Shop")
    }

    @MainActor
    func testSearchTextIsCaseInsensitive() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.searchText = "sushi"

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Sushi Bar")
    }

    @MainActor
    func testSearchTextPartialMatch() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.searchText = "sh"

        // Assert — matches "Pizza Shop" and "Sushi Bar"
        XCTAssertEqual(viewModel.filteredRestaurants.count, 2)
        let names = Set(viewModel.filteredRestaurants.map(\.name))
        XCTAssertTrue(names.contains("Pizza Shop"))
        XCTAssertTrue(names.contains("Sushi Bar"))
    }

    @MainActor
    func testEmptySearchTextShowsAll() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.searchText = ""

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 3)
    }

    @MainActor
    func testSearchTextCombinesWithDistanceFilter() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)

        // Act — "Bar" matches Sushi Bar (5500m), radius 3000 excludes it
        viewModel.searchText = "Bar"
        viewModel.filterRadius = 3000

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 0)
    }

    @MainActor
    func testSearchTextMatchesCategory() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.searchText = "Italian"

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Pizza Shop")
    }

    @MainActor
    func testWhitespaceOnlySearchTextShowsAll() {
        // Arrange
        let viewModel = RestaurantViewModel(restaurants: sampleRestaurants)
        viewModel.filterRadius = nil

        // Act
        viewModel.searchText = "   "

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 3)
    }

    @MainActor
    func testSearchTextMatchesWithSmartApostrophe() {
        // Arrange — restaurant with a straight apostrophe in the name
        let restaurants = [
            Restaurant(
                id: UUID(),
                name: "Tad's Steakhouse",
                coordinate: .init(latitude: 40.7128, longitude: -74.0060),
                distance: 500,
                category: "American",
                phoneNumber: nil,
                url: nil
            ),
            sampleRestaurants[1],
        ]
        let viewModel = RestaurantViewModel(restaurants: restaurants)
        viewModel.filterRadius = nil

        // Act — type with a curly/smart right single quote (what iOS keyboard produces)
        viewModel.searchText = "Tad\u{2019}s"

        // Assert — should still match "Tad's Steakhouse"
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Tad's Steakhouse")
    }

    @MainActor
    func testSearchTextMatchesStraightApostropheAgainstSmartQuoteName() {
        // Arrange — restaurant with a smart apostrophe in the name
        let restaurants = [
            Restaurant(
                id: UUID(),
                name: "Tad\u{2019}s Steakhouse",
                coordinate: .init(latitude: 40.7128, longitude: -74.0060),
                distance: 500,
                category: "American",
                phoneNumber: nil,
                url: nil
            ),
            sampleRestaurants[1],
        ]
        let viewModel = RestaurantViewModel(restaurants: restaurants)
        viewModel.filterRadius = nil

        // Act — type with a straight apostrophe
        viewModel.searchText = "Tad's"

        // Assert — should still match
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
        XCTAssertTrue(viewModel.filteredRestaurants.first?.name.contains("Tad") ?? false)
    }

    @MainActor
    func testSearchTextMatchesCurlyDoubleQuoteAgainstStraightQuoteName() {
        // Arrange — restaurant name uses straight double quotes
        let restaurants = [
            Restaurant(
                id: UUID(),
                name: "\"The Best\" Cafe",
                coordinate: .init(latitude: 40.7128, longitude: -74.0060),
                distance: 500,
                category: "American",
                phoneNumber: nil,
                url: nil
            ),
            sampleRestaurants[1],
        ]
        let viewModel = RestaurantViewModel(restaurants: restaurants)
        viewModel.filterRadius = nil

        // Act — iOS keyboard may produce left/right curly double quotes (U+201C / U+201D)
        viewModel.searchText = "\u{201C}The Best\u{201D}"

        // Assert — normalisation converts curly quotes → straight so it matches
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
    }

    @MainActor
    func testSearchTextMatchesStraightDoubleQuoteAgainstCurlyQuoteName() {
        // Arrange — restaurant name uses curly double quotes
        let restaurants = [
            Restaurant(
                id: UUID(),
                name: "\u{201C}The Best\u{201D} Cafe",
                coordinate: .init(latitude: 40.7128, longitude: -74.0060),
                distance: 500,
                category: "American",
                phoneNumber: nil,
                url: nil
            ),
            sampleRestaurants[1],
        ]
        let viewModel = RestaurantViewModel(restaurants: restaurants)
        viewModel.filterRadius = nil

        // Act — user types with a straight double quote
        viewModel.searchText = "\"The Best\""

        // Assert
        XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
    }

    // MARK: - Test Helpers

    private func makeTestDefaults() -> UserDefaults {
        let suite = "RestaurantViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? UserDefaults.standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

// MARK: - mergeRestaurantLists Tests

/// Tests for `RestaurantViewModel.mergeRestaurantLists(existing:new:)`.
///
/// These tests run entirely in memory — no networking, no location services.
@MainActor
final class MergeRestaurantListsTests: XCTestCase {
    // MARK: - Helpers

    private func makeRestaurant(
        name: String,
        lat: Double = 40.7128,
        lon: Double = -74.0060,
        distance: Double = 500
    ) -> Restaurant {
        Restaurant(
            id: UUID(),
            name: name,
            coordinate: .init(latitude: lat, longitude: lon),
            distance: distance,
            category: nil,
            cuisineTags: [],
            phoneNumber: nil,
            url: nil
        )
    }

    // MARK: - Tests

    func testMergeWithEmptyNewListReturnsExisting() {
        // Arrange
        let existing = [makeRestaurant(name: "Thai Place")]

        // Act
        let result = RestaurantViewModel.mergeRestaurantLists(existing: existing, new: [])

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "Thai Place")
    }

    func testMergeWithEmptyExistingAddsAllNew() {
        // Arrange
        let new = [makeRestaurant(name: "Pizza Shop"), makeRestaurant(name: "Sushi Bar", lat: 40.72)]

        // Act
        let result = RestaurantViewModel.mergeRestaurantLists(existing: [], new: new)

        // Assert
        XCTAssertEqual(result.count, 2)
    }

    func testMergeDeduplicatesByNameAndProximity() {
        // Arrange — same name + same coords in both lists → should not duplicate
        let existing = [makeRestaurant(name: "Thai Place")]
        let new = [makeRestaurant(name: "Thai Place")] // identical coord (default)

        // Act
        let result = RestaurantViewModel.mergeRestaurantLists(existing: existing, new: new)

        // Assert — only one entry
        XCTAssertEqual(result.count, 1)
    }

    func testMergeKeepsDifferentLocationsWithSameName() {
        // Arrange — chain: same name at different coordinates
        let existing = [makeRestaurant(name: "Starbucks", lat: 40.71, lon: -74.00)]
        let new = [makeRestaurant(name: "Starbucks", lat: 41.00, lon: -74.00)] // far away

        // Act
        let result = RestaurantViewModel.mergeRestaurantLists(existing: existing, new: new)

        // Assert — both branches of the chain kept
        XCTAssertEqual(result.count, 2)
    }

    func testMergeResultIsSortedByDistanceAscending() {
        // Arrange
        let existing = [makeRestaurant(name: "Far Place", distance: 3000)]
        let new = [makeRestaurant(name: "Near Place", lat: 40.72, distance: 200)]

        // Act
        let result = RestaurantViewModel.mergeRestaurantLists(existing: existing, new: new)

        // Assert
        XCTAssertEqual(result.first?.name, "Near Place")
        XCTAssertEqual(result.last?.name, "Far Place")
    }

    func testMergeAddsTrulyNewRestaurants() {
        // Arrange
        let existing = [makeRestaurant(name: "Thai Place")]
        let new = [makeRestaurant(name: "Pizza Shop", lat: 40.72)]

        // Act
        let result = RestaurantViewModel.mergeRestaurantLists(existing: existing, new: new)

        // Assert
        XCTAssertEqual(result.count, 2)
        let names = Set(result.map(\.name))
        XCTAssertTrue(names.contains("Thai Place"))
        XCTAssertTrue(names.contains("Pizza Shop"))
    }
}

// MARK: - handleOrchestratorUpdate Tests

/// Tests for `RestaurantViewModel.handleOrchestratorUpdate(_:)`.
///
/// `handleOrchestratorUpdate` is driven directly (without a running orchestrator)
/// by setting `currentSearchJobID` and calling the method with a synthetic
/// `OrchestratorUpdate`.
@MainActor
final class HandleOrchestratorUpdateTests: XCTestCase {
    // MARK: - Helpers

    private let baseLocation = CLLocation(latitude: 40.7128, longitude: -74.0060)

    private func makeSampleRestaurants() -> [Restaurant] {
        [
            Restaurant(
                id: UUID(),
                name: "Thai Place",
                coordinate: .init(latitude: 40.7128, longitude: -74.0060),
                distance: 300,
                category: "Thai",
                cuisineTags: ["Thai"],
                phoneNumber: nil,
                url: nil
            ),
            Restaurant(
                id: UUID(),
                name: "Pizza Shop",
                coordinate: .init(latitude: 40.72, longitude: -74.006),
                distance: 1500,
                category: "Italian",
                cuisineTags: ["Italian"],
                phoneNumber: nil,
                url: nil
            ),
        ]
    }

    private func makeUpdate(
        jobID: UUID,
        snapshot: [Restaurant] = [],
        isComplete: Bool = false,
        location: CLLocation? = nil
    ) -> OrchestratorUpdate {
        OrchestratorUpdate(
            jobID: jobID,
            location: location ?? CLLocation(latitude: 40.7128, longitude: -74.0060),
            snapshot: snapshot,
            isJobComplete: isComplete
        )
    }

    // MARK: - Current-Job Tests

    func testUpdateForCurrentJobSetsRestaurants() {
        // Arrange
        let vm = RestaurantViewModel(restaurants: [])
        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.isLoading = true
        let snapshot = makeSampleRestaurants()

        // Act
        vm.handleOrchestratorUpdate(makeUpdate(jobID: jobID, snapshot: snapshot))

        // Assert
        XCTAssertEqual(vm.restaurants.count, snapshot.count)
    }

    func testUpdateForCurrentJobClearsErrorMessage() {
        // Arrange
        let vm = RestaurantViewModel(restaurants: [])
        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.errorMessage = "Previous error"

        // Act
        vm.handleOrchestratorUpdate(makeUpdate(jobID: jobID, snapshot: makeSampleRestaurants()))

        // Assert
        XCTAssertNil(vm.errorMessage)
    }

    func testFirstUpdateForCurrentJobSetsIsLoadingFalseAndIsLoadingMoreTrue() {
        // Arrange
        let vm = RestaurantViewModel(restaurants: [])
        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.isLoading = true

        // Act
        vm.handleOrchestratorUpdate(makeUpdate(jobID: jobID, snapshot: makeSampleRestaurants()))

        // Assert
        XCTAssertFalse(vm.isLoading, "isLoading should flip to false after first update")
        XCTAssertTrue(vm.isLoadingMore, "isLoadingMore should become true while search is still running")
    }

    func testCompleteUpdateForCurrentJobClearsIsLoadingMore() {
        // Arrange — simulate that the first update already cleared isLoading
        let vm = RestaurantViewModel(restaurants: [])
        let jobID = UUID()
        vm.currentSearchJobID = jobID
        vm.isLoadingMore = true

        // Act — complete update
        vm.handleOrchestratorUpdate(
            makeUpdate(jobID: jobID, snapshot: makeSampleRestaurants(), isComplete: true)
        )

        // Assert
        XCTAssertFalse(vm.isLoadingMore, "isLoadingMore should be false once the job is complete")
    }

    func testCompleteUpdateWithEmptySnapshotSetsErrorMessage() {
        // Arrange
        let vm = RestaurantViewModel(restaurants: [])
        let jobID = UUID()
        vm.currentSearchJobID = jobID

        // Act — complete update with no restaurants
        vm.handleOrchestratorUpdate(makeUpdate(jobID: jobID, snapshot: [], isComplete: true))

        // Assert
        XCTAssertNotNil(vm.errorMessage, "An error message should be set when no restaurants are found")
    }

    func testCompleteUpdateWithNonEmptySnapshotDoesNotSetErrorMessage() {
        // Arrange
        let vm = RestaurantViewModel(restaurants: [])
        let jobID = UUID()
        vm.currentSearchJobID = jobID

        // Act
        vm.handleOrchestratorUpdate(
            makeUpdate(jobID: jobID, snapshot: makeSampleRestaurants(), isComplete: true)
        )

        // Assert
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Non-Current-Job Tests

    func testUpdateForOtherJobDoesNotClearOrSetErrorMessage() {
        // Arrange — viewModel has an existing error; a background-job update should not clear it
        let vm = RestaurantViewModel(restaurants: [])
        vm.currentSearchJobID = UUID() // will not match the update's jobID
        vm.errorMessage = "Existing error"

        let otherJobID = UUID()
        let newRestaurant = Restaurant(
            id: UUID(),
            name: "Background Find",
            coordinate: .init(latitude: 40.75, longitude: -73.99),
            distance: 5000,
            category: "Burger",
            cuisineTags: ["Burger"],
            phoneNumber: nil,
            url: nil
        )

        // Act — update from a background (non-current) job
        vm.handleOrchestratorUpdate(makeUpdate(jobID: otherJobID, snapshot: [newRestaurant]))

        // Assert — the non-current path does NOT touch errorMessage
        XCTAssertEqual(
            vm.errorMessage,
            "Existing error",
            "Non-current-job update must not modify the live errorMessage"
        )
    }

    func testUpdateForOtherJobDoesNotChangeIsLoadingState() {
        // Arrange
        let vm = RestaurantViewModel(restaurants: [])
        let currentJobID = UUID()
        vm.currentSearchJobID = currentJobID
        vm.isLoading = true

        // Act — update for a different job
        vm.handleOrchestratorUpdate(makeUpdate(jobID: UUID(), snapshot: makeSampleRestaurants()))

        // Assert — isLoading unchanged because only the current-job path manages isLoading
        XCTAssertTrue(vm.isLoading)
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

    func testFormattedDistanceAtExactlyOneKilometer() {
        // The boundary condition: distance < 1000 shows metres, so exactly 1000 m
        // must display as kilometres.
        let restaurant = Restaurant(
            id: UUID(),
            name: "Test",
            coordinate: .init(latitude: 0, longitude: 0),
            distance: 1000,
            category: nil,
            phoneNumber: nil,
            url: nil
        )

        XCTAssertEqual(restaurant.formattedDistance, "1.0 km")
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
