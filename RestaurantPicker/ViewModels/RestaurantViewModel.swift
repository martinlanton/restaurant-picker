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
    @Published var filterRadius: Double? = 5000 {
        didSet {
            applyFilter()
        }
    }

    /// Whether to show the selected restaurant sheet.
    @Published var showSelectedRestaurant = false

    // MARK: - Dependencies

    private let locationManager: LocationManager
    private let searchService: RestaurantSearchService

    // MARK: - Initialization

    /// Creates a new RestaurantViewModel with dependencies.
    ///
    /// - Parameters:
    ///   - locationManager: Manager for user location. Defaults to a new instance.
    ///   - searchService: Service for searching restaurants. Defaults to a new instance.
    @MainActor
    init(
        locationManager: LocationManager? = nil,
        searchService: RestaurantSearchService? = nil
    ) {
        self.locationManager = locationManager ?? LocationManager()
        self.searchService = searchService ?? RestaurantSearchService()
    }

    /// Creates a new RestaurantViewModel with pre-loaded restaurants (for testing/previews).
    ///
    /// - Parameter restaurants: Pre-loaded list of restaurants.
    @MainActor
    init(restaurants: [Restaurant]) {
        self.locationManager = LocationManager()
        self.searchService = RestaurantSearchService()
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
    /// Updates `selectedRestaurant` with a randomly chosen restaurant
    /// and sets `showSelectedRestaurant` to true to display the result.
    func selectRandomRestaurant() {
        guard !filteredRestaurants.isEmpty else {
            errorMessage = "No restaurants available to choose from."
            return
        }
        selectedRestaurant = filteredRestaurants.randomElement()
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

    /// Applies the distance filter to the restaurants list.
    private func applyFilter() {
        guard let radius = filterRadius else {
            filteredRestaurants = restaurants
            return
        }
        filteredRestaurants = restaurants.filter { $0.distance <= radius }
    }
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

