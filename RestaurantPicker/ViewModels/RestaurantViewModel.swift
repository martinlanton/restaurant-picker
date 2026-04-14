import Combine
import CoreLocation
import Foundation

/// ViewModel for managing restaurant data and user interactions.
///
/// This class coordinates between the view layer and services,
/// handling restaurant fetching, filtering, and random selection.
///
/// Restaurant results are **cached by location** so that changing the
/// distance filter or returning to a previously-visited location
/// never triggers a redundant network search. The refresh button
/// clears the cache for the current location and forces a re-fetch.
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

    /// Whether additional batches are still loading after the first results appeared.
    @Published private(set) var isLoadingMore = false

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
            // Trigger a targeted re-search for selected cuisines to find
            // restaurants that may not have appeared in the initial broad search
            if !selectedCuisines.isEmpty {
                Task { await fetchCuisineSpecific(selectedCuisines) }
            }
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
    @Published var minimumRating: Int? {
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

    /// Cancellable for observing location override changes.
    private var overrideCancellable: AnyCancellable?

    /// The currently running search task, cancelled when a new search starts.
    private var searchTask: Task<Void, Never>?

    // MARK: - Search Cache

    /// A completed search result for a specific location.
    /// All restaurants ever found near this location are accumulated here.
    private struct SearchCacheEntry {
        let location: CLLocation
        let searchRadius: Double
        var restaurants: [Restaurant]
    }

    /// Cache of search results keyed by location.
    /// New search results merge into existing entries within 50m.
    private var searchCache: [SearchCacheEntry] = []

    /// Maximum distance (in metres) between two locations to consider
    /// them the same for caching purposes.
    private static let cacheSameLocationThreshold: Double = 50.0

    /// The search radius used for `searchRestaurants` network calls.
    /// Always 10km. The UI `filterRadius` is applied client-side on top of this.
    private static let networkSearchRadius: Double = 10000

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
        observeOverrideLocation()
    }

    /// Creates a new RestaurantViewModel with pre-loaded restaurants (for testing/previews).
    ///
    /// - Parameters:
    ///   - restaurants: Pre-loaded list of restaurants.
    ///   - ratingStore: Store for user ratings. Defaults to a new instance.
    @MainActor
    init(restaurants: [Restaurant], ratingStore: RatingStore? = nil) {
        locationManager = LocationManager()
        searchService = RestaurantSearchService()
        self.ratingStore = ratingStore ?? RatingStore()
        self.restaurants = restaurants
        filteredRestaurants = restaurants
    }

    // MARK: - Public Methods

    /// Fetches nearby restaurants based on the effective location.
    ///
    /// Uses the override location (map pin) if set, otherwise falls
    /// back to the device GPS location. Requests authorization and
    /// GPS fix only when no override is active.
    ///
    /// If a search for the same location (within 50m) and radius is
    /// already cached, the cached results are used immediately without
    /// any network requests. Otherwise cancels any in-progress search
    /// and starts a new one.
    func fetchNearbyRestaurants() async {
        // Cancel any in-progress search so it stops consuming rate limits
        searchTask?.cancel()
        searchTask = nil

        isLoading = true
        errorMessage = nil

        // When an override location is set (map pin), skip authorization
        // and GPS — use the override directly.
        let location: CLLocation

        if let override = locationManager.overrideLocation {
            location = override
        } else {
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

            guard let gpsLocation = locationManager.currentLocation else {
                errorMessage = "Unable to determine your location."
                isLoading = false
                return
            }
            location = gpsLocation
        }

        let radius = Self.networkSearchRadius

        // Check cache — if we already searched this location, use cached results
        if let cached = findCacheEntry(for: location, radius: radius) {
            restaurants = cached.restaurants
            applyFilter()
            errorMessage = nil
            isLoading = false
            isLoadingMore = false
            return
        }

        // No cache hit — run the search in a cancellable task
        let task = Task { [weak self] in
            guard let self else { return }
            await runProgressiveSearch(location: location, radius: radius)
        }
        searchTask = task
        await task.value
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

    /// Refreshes the restaurant list by clearing the cache for the current
    /// location and re-fetching from scratch.
    func refresh() async {
        // Remove cache entry for current location so we re-fetch
        if let location = locationManager.effectiveLocation {
            searchCache.removeAll { entry in
                entry.location.distance(from: location) < Self.cacheSameLocationThreshold
            }
        }
        await fetchNearbyRestaurants()
    }

    // MARK: - Progressive Search

    /// Runs the progressive search stream and merges results into the cache.
    ///
    /// The scatter radius is set to the user's current filter radius (or 500m
    /// default) so adaptive scatter concentrates on the area being viewed.
    /// The network search radius (10km) is used as the maxRadius distance filter.
    private func runProgressiveSearch(location: CLLocation, radius: Double) async {
        let scatterRadius = filterRadius ?? 500
        let stream = await searchService.searchRestaurants(
            near: location,
            radius: radius,
            scatterRadius: scatterRadius
        )
        var receivedAny = false

        do {
            for try await snapshot in stream {
                // Check for cancellation between yields
                guard !Task.isCancelled else { break }

                restaurants = snapshot
                applyFilter()
                errorMessage = nil

                if !receivedAny {
                    // First batch arrived — stop the full-screen spinner,
                    // switch to the subtle "loading more" indicator.
                    receivedAny = true
                    isLoading = false
                    isLoadingMore = true
                }
            }
        } catch {
            if !receivedAny {
                errorMessage = error.localizedDescription
            }
        }

        // Store final result in cache (only if not cancelled and we have results)
        if !Task.isCancelled, !restaurants.isEmpty {
            updateCache(for: location, radius: radius, restaurants: restaurants)
        }

        isLoading = false
        isLoadingMore = false
    }

    // MARK: - Cuisine-Specific Search

    /// Performs a targeted search for specific cuisines and merges results
    /// into the main restaurant list. Called when cuisine filters change.
    ///
    /// For restaurants already in the list, merges cuisine tags and upgrades
    /// the display category. For new restaurants, appends them.
    private func fetchCuisineSpecific(_ cuisines: Set<String>) async {
        guard let location = locationManager.effectiveLocation else { return }

        let results = await searchService.searchCuisines(
            cuisines, near: location, radius: Self.networkSearchRadius
        )
        guard !results.isEmpty else { return }

        mergeNewRestaurants(results, for: location)
    }

    // MARK: - Cache Helpers

    /// Finds a cache entry matching the given location and radius.
    ///
    /// A match requires the entry's search radius to be >= the requested
    /// radius AND the distance between locations to be < 50m.
    private func findCacheEntry(for location: CLLocation, radius: Double) -> SearchCacheEntry? {
        searchCache.first { entry in
            entry.searchRadius >= radius &&
                entry.location.distance(from: location) < Self.cacheSameLocationThreshold
        }
    }

    /// Updates or creates a cache entry for the given location.
    ///
    /// If an entry already exists within 50m, merges the new restaurants
    /// into it and keeps the larger search radius. Otherwise creates a new entry.
    private func updateCache(for location: CLLocation, radius: Double, restaurants: [Restaurant]) {
        if let idx = searchCache.firstIndex(where: { entry in
            entry.location.distance(from: location) < Self.cacheSameLocationThreshold
        }) {
            let merged = Self.mergeRestaurantLists(
                existing: searchCache[idx].restaurants, new: restaurants
            )
            searchCache[idx] = SearchCacheEntry(
                location: location,
                searchRadius: max(radius, searchCache[idx].searchRadius),
                restaurants: merged
            )
        } else {
            searchCache.append(SearchCacheEntry(
                location: location, searchRadius: radius, restaurants: restaurants
            ))
        }
    }

    // MARK: - Restaurant Merging

    /// Merges new restaurant results into the master list and updates the UI.
    ///
    /// Deduplicates by name + proximity (within 50m). For duplicates, merges
    /// cuisine tags and upgrades the display category if the new one is more
    /// specific. Also updates the cache entry for the given location.
    private func mergeNewRestaurants(_ newResults: [Restaurant], for location: CLLocation) {
        var merged = restaurants
        var changed = false

        for restaurant in newResults {
            let key = restaurant.name.lowercased()
            if let existingIndex = merged.firstIndex(where: { existing in
                existing.name.lowercased() == key &&
                    abs(existing.coordinate.latitude - restaurant.coordinate.latitude) < 0.0005 &&
                    abs(existing.coordinate.longitude - restaurant.coordinate.longitude) < 0.0005
            }) {
                // Already in the list — merge cuisine tags
                let existing = merged[existingIndex]
                let mergedTags = existing.cuisineTags.union(restaurant.cuisineTags)

                // Upgrade display category if new one is more specific
                let displayCategory: String? = if let newCat = restaurant.category,
                                                  !RestaurantSearchService.genericCategories.contains(newCat),
                                                  RestaurantSearchService.genericCategories
                                                  .contains(existing.category ?? "") {
                    newCat
                } else {
                    existing.category
                }

                if mergedTags != existing.cuisineTags || displayCategory != existing.category {
                    merged[existingIndex] = Restaurant(
                        id: existing.id,
                        name: existing.name,
                        coordinate: existing.coordinate,
                        distance: existing.distance,
                        category: displayCategory,
                        cuisineTags: mergedTags,
                        phoneNumber: existing.phoneNumber ?? restaurant.phoneNumber,
                        url: existing.url ?? restaurant.url
                    )
                    changed = true
                }
            } else {
                // New restaurant — append
                merged.append(restaurant)
                changed = true
            }
        }

        if changed {
            restaurants = merged.sorted { $0.distance < $1.distance }
            applyFilter()

            // Also update cache
            updateCache(for: location, radius: Self.networkSearchRadius, restaurants: restaurants)
        }
    }

    /// Merges two restaurant lists, deduplicating by name + proximity.
    private static func mergeRestaurantLists(
        existing: [Restaurant],
        new: [Restaurant]
    ) -> [Restaurant] {
        var merged = existing
        for restaurant in new {
            let key = restaurant.name.lowercased()
            let isDuplicate = merged.contains { existing in
                existing.name.lowercased() == key &&
                    abs(existing.coordinate.latitude - restaurant.coordinate.latitude) < 0.0005 &&
                    abs(existing.coordinate.longitude - restaurant.coordinate.longitude) < 0.0005
            }
            if !isDuplicate {
                merged.append(restaurant)
            }
        }
        return merged.sorted { $0.distance < $1.distance }
    }

    // MARK: - Private Methods

    /// Subscribes to `locationManager.overrideLocation` changes and
    /// triggers a restaurant re-fetch whenever the override is set or cleared.
    private func observeOverrideLocation() {
        overrideCancellable = locationManager.$overrideLocation
            .dropFirst() // skip the initial nil value
            .removeDuplicates { lhs, rhs in
                // Treat two locations within 1m as identical to avoid redundant fetches
                guard let lhs, let rhs else { return lhs == nil && rhs == nil }
                return lhs.distance(from: rhs) < 1
            }
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.fetchNearbyRestaurants()
                }
            }
    }

    /// Applies the distance, cuisine, and rating filters to the restaurants list.
    private func applyFilter() {
        var result = restaurants

        // Apply distance filter
        if let radius = filterRadius {
            result = result.filter { $0.distance <= radius }
        }

        // Apply include cuisine filter (matches against cuisineTags)
        if !selectedCuisines.isEmpty {
            result = result.filter { restaurant in
                !restaurant.cuisineTags.isDisjoint(with: selectedCuisines)
            }
        }

        // Apply exclude cuisine filter (matches against cuisineTags)
        if !excludedCuisines.isEmpty {
            result = result.filter { restaurant in
                restaurant.cuisineTags.isDisjoint(with: excludedCuisines)
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
    /// Static list of cuisine categories available for filtering.
    ///
    /// Derived from the search service's cuisine queries. This ensures
    /// filter options are always present regardless of which restaurants
    /// were discovered in the current search.
    static let allCuisines: [String] = RestaurantSearchService.cuisineQueries
        .map(\.label)
        .filter { !RestaurantSearchService.genericCategories.contains($0) }
        .sorted()

    /// Unique, sorted list of cuisine categories available for filtering.
    /// Uses the static list so filters never disappear.
    var availableCuisines: [String] {
        Self.allCuisines
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
        ("5", 5)
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
