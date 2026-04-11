import CoreLocation
import Foundation

/// ViewModel for managing restaurant data and user interactions.
///
/// This class coordinates between the view layer and services,
/// handling restaurant fetching, filtering, and random selection.
///
/// ## Usage
/// ```swift
/// @StateObject private var viewModel = RestaurantViewModel()
///
/// // Fetch restaurants
/// await viewModel.fetchNearbyRestaurants()
///
/// // Filter by distance
/// viewModel.filterRadius = 2000
///
/// // Select random restaurant
/// viewModel.selectRandomRestaurant()
/// ```
@MainActor
final class RestaurantViewModel: ObservableObject {
    // MARK: - Published Properties

    /// All fetched restaurants before filtering.
    @Published private(set) var restaurants: [Restaurant] = []

    /// Restaurants filtered by the current radius.
    @Published private(set) var filteredRestaurants: [Restaurant] = []

    /// The currently selected restaurant (from random selection).
    @Published var selectedRestaurant: Restaurant?

    /// Whether a restaurant search is in progress.
    @Published private(set) var isLoading = false

    /// Error message if something goes wrong.
    @Published var errorMessage: String?

    /// Filter radius in meters. Set to nil to show all restaurants.
    @Published var filterRadius: Double? = 1000 {
        didSet {
            applyFilter()
        }
    }

    /// Cuisines to include in the filtered list. Empty set means show all cuisines.
    @Published var selectedCuisines: Set<String> = [] {
        didSet {
            applyFilter()
        }
    }

    /// Cuisines to exclude from the filtered list. Empty set means exclude nothing.
    @Published var excludedCuisines: Set<String> = [] {
        didSet {
            applyFilter()
        }
    }

    /// Minimum star rating to include. Nil means show all (no rating filter).
    /// Pyramidal: setting 2 shows restaurants rated 2, 3, 4, and 5.
    @Published var minimumRating: Int? = nil {
        didSet {
            applyFilter()
        }
    }

    /// Text to filter restaurants by name or category. Empty = no text filter.
    @Published var searchText: String = "" {
        didSet {
            applyFilter()
        }
    }

    /// Whether to show the selected restaurant sheet.
    @Published var showSelectedRestaurant = false

    // MARK: - Dependencies

    private let locationManager: LocationManager
    private let searchService: RestaurantSearchService
    private(set) var ratingStore: RatingStore

    // MARK: - Initialization

    /// Creates a new RestaurantViewModel with dependencies.
    ///
    /// - Parameters:
    ///   - locationManager: Manager for user location. Defaults to a new instance.
    ///   - searchService: Service for searching restaurants. Defaults to a new instance.
    ///   - ratingStore: Store for user ratings. Defaults to a new instance.
    @MainActor
    init(
        locationManager: LocationManager? = nil,
        searchService: RestaurantSearchService? = nil,
        ratingStore: RatingStore? = nil
    ) {
        self.locationManager = locationManager ?? LocationManager()
        self.searchService = searchService ?? RestaurantSearchService()
        self.ratingStore = ratingStore ?? RatingStore()
    }

    /// Creates a new RestaurantViewModel with pre-loaded restaurants (for testing/previews).
    ///
    /// - Parameters:
    ///   - restaurants: Pre-loaded list of restaurants.
    ///   - ratingStore: Store for user ratings. Defaults to a new instance.
    @MainActor
    init(restaurants: [Restaurant], ratingStore: RatingStore? = nil) {
        self.locationManager = LocationManager()
        self.searchService = RestaurantSearchService()
        self.ratingStore = ratingStore ?? RatingStore()
        self.restaurants = restaurants
        self.filteredRestaurants = restaurants
    }

    // MARK: - Public Methods

    /// Fetches nearby restaurants based on the user's current location.
    ///
    /// This method first requests location authorization if needed,
    /// then searches for restaurants within the current filter radius.
    func fetchNearbyRestaurants() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        // Request location authorization if not determined
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAuthorization()
            // Wait a moment for the user to respond
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Check authorization status
        guard locationManager.isAuthorized else {
            if locationManager.isDenied {
                errorMessage = "Location access denied. Please enable location services in Settings."
            } else {
                errorMessage = "Location access not yet authorized."
            }
            isLoading = false
            return
        }

        // Request current location if needed
        if locationManager.currentLocation == nil {
            locationManager.requestLocation()
            // Wait for location
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        guard let location = locationManager.currentLocation else {
            errorMessage = "Unable to determine your location."
            isLoading = false
            return
        }

        // Search for restaurants with a wide radius; the UI filter narrows what is shown.
        do {
            let results = try await searchService.searchRestaurants(near: location, radius: 10000)
            restaurants = results
            applyFilter()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Selects a random restaurant from the filtered list.
    ///
    /// When no rating filter is active (`minimumRating == nil`), restaurants
    /// are weighted by their user rating using a quadratic scale:
    /// 1★=0.25, 2★=0.5, 3★=1.0, 4★=2.0, 5★=4.0, unrated=1.0.
    /// When a rating filter is active, selection is uniform.
    func selectRandomRestaurant() {
        guard !filteredRestaurants.isEmpty else {
            errorMessage = "No restaurants available to choose from."
            return
        }

        if minimumRating == nil {
            selectedRestaurant = weightedRandomElement(from: filteredRestaurants)
        } else {
            // Uniform selection when any rating filter (including unrated) is active
            selectedRestaurant = filteredRestaurants.randomElement()
        }
        showSelectedRestaurant = true
    }

    /// Clears the current selection.
    func clearSelection() {
        selectedRestaurant = nil
        showSelectedRestaurant = false
    }

    /// Refreshes the restaurant list.
    func refresh() async {
        await fetchNearbyRestaurants()
    }

    // MARK: - Private Methods

    /// Applies the distance, cuisine, and rating filters to the restaurants list.
    private func applyFilter() {
        var result = restaurants

        // Apply distance filter
        if let radius = filterRadius {
            result = result.filter { $0.distance <= radius }
        }

        // Apply include cuisine filter
        if !selectedCuisines.isEmpty {
            result = result.filter { restaurant in
                guard let category = restaurant.category else { return false }
                return selectedCuisines.contains(category)
            }
        }

        // Apply exclude cuisine filter
        if !excludedCuisines.isEmpty {
            result = result.filter { restaurant in
                guard let category = restaurant.category else { return true }
                return !excludedCuisines.contains(category)
            }
        }

        // Apply minimum rating filter (pyramidal) or unrated-only filter
        if let minRating = minimumRating {
            if minRating == -1 {
                // Unrated only — show restaurants with nil rating
                result = result.filter { restaurant in
                    ratingStore.rating(for: restaurant) == nil
                }
            } else {
                // Pyramidal — show restaurants rated >= minRating (excludes 0/rejected and nil/unrated)
                result = result.filter { restaurant in
                    guard let rating = ratingStore.rating(for: restaurant) else { return false }
                    return rating >= minRating
                }
            }
        }

        // Apply search text filter
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let query = Self.normalizeForSearch(trimmed)
            result = result.filter { restaurant in
                Self.normalizeForSearch(restaurant.name).contains(query) ||
                    (restaurant.category.map { Self.normalizeForSearch($0).contains(query) } ?? false)
            }
        }

        filteredRestaurants = result
    }

    /// Selects a random restaurant weighted by user rating.
    ///
    /// Uses the quadratic weight table from `ratingWeight(for:)`.
    private func weightedRandomElement(from restaurants: [Restaurant]) -> Restaurant? {
        let weights = restaurants.map { restaurant -> Double in
            let rating = ratingStore.rating(for: restaurant)
            return Self.ratingWeight(for: rating)
        }

        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return restaurants.randomElement() }

        var random = Double.random(in: 0 ..< totalWeight)
        for (index, weight) in weights.enumerated() {
            random -= weight
            if random < 0 {
                return restaurants[index]
            }
        }

        return restaurants.last
    }

    /// Normalizes a string for search comparison.
    ///
    /// Lowercases and replaces smart/curly quotes with straight equivalents
    /// so that keyboard-produced characters match stored restaurant names.
    static func normalizeForSearch(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2018}", with: "'") // left single curly quote
            .replacingOccurrences(of: "\u{2019}", with: "'") // right single curly quote
            .replacingOccurrences(of: "\u{201C}", with: "\"") // left double curly quote
            .replacingOccurrences(of: "\u{201D}", with: "\"") // right double curly quote
    }
}

// MARK: - Cuisine Filter

extension RestaurantViewModel {
    /// Unique, sorted list of cuisine categories available in the current restaurant set.
    var availableCuisines: [String] {
        restaurants
            .compactMap(\.category)
            .reduce(into: Set<String>()) { $0.insert($1) }
            .sorted()
    }

    /// Total number of active filters (cuisine includes + excludes + rating).
    var activeCuisineFilterCount: Int {
        selectedCuisines.count + excludedCuisines.count + (minimumRating != nil ? 1 : 0)
    }
}

// MARK: - Rating Weights

extension RestaurantViewModel {
    /// Quadratic weight for a given star rating.
    ///
    /// 3 stars is the baseline (weight 1.0). The scale is quadratic:
    /// - 0 (rejected) → 0.00
    /// - 1★ → 0.25
    /// - 2★ → 0.50
    /// - 3★ → 1.00
    /// - 4★ → 2.00
    /// - 5★ → 4.00
    /// - nil (unrated) → 1.00
    static func ratingWeight(for rating: Int?) -> Double {
        guard let rating else { return 1.0 }
        switch rating {
        case 0: return 0.00
        case 1: return 0.25
        case 2: return 0.50
        case 3: return 1.00
        case 4: return 2.00
        case 5: return 4.00
        default: return 1.0
        }
    }

    /// Available rating filter options for the UI.
    /// -1 is a sentinel for "unrated only".
    static let ratingFilterOptions: [(label: String, value: Int?)] = [
        ("All", nil),
        ("Unrated", -1),
        ("1+", 1),
        ("2+", 2),
        ("3+", 3),
        ("4+", 4),
        ("5", 5),
    ]
}

// MARK: - Distance Filter Options

extension RestaurantViewModel {
    /// Available distance filter options.
    static let distanceOptions: [(label: String, value: Double?)] = [
        ("500 m", 500),
        ("1 km", 1000),
        ("2 km", 2000),
        ("5 km", 5000),
        ("10 km", 10000),
        ("All", nil)
    ]
}

