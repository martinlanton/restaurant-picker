import Combine
import CoreLocation
import Foundation

/// ViewModel for managing restaurant data and user interactions.
///
/// This class coordinates between the view layer and the `SearchOrchestrator`,
/// handling restaurant fetching, filtering, and random selection.
///
/// Restaurant results are **cached by location** so that changing the
/// distance filter or returning to a previously-visited location
/// never triggers a redundant network search. The refresh button
/// clears the cache for the current location and forces a re-fetch.
///
/// ## Search Model
///
/// A single `SearchOrchestrator` runs continuously in the background.
/// Calling `fetchNearbyRestaurants()` enqueues the resolved location into
/// the orchestrator rather than cancelling in-flight requests. The
/// orchestrator finishes any running `MKLocalSearch` batch (≈ 200 ms),
/// then pivots to the new location without rate-limit disruption.
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
    @Published var isLoading = false

    /// Whether additional batches are still loading after the first results appeared.
    @Published var isLoadingMore = false

    /// Error message if something goes wrong.
    @Published var errorMessage: String?

    /// Filter radius in meters. Set to nil to show all restaurants.
    @Published var filterRadius: Double? = 500 {
        didSet { applyFilter() }
    }

    /// Cuisines to include in the filtered list. Empty set means show all cuisines.
    @Published var selectedCuisines: Set<String> = [] {
        didSet {
            applyFilter()
            if !selectedCuisines.isEmpty {
                Task { await fetchCuisineSpecific(selectedCuisines) }
            }
        }
    }

    /// Cuisines to exclude from the filtered list. Empty set means exclude nothing.
    @Published var excludedCuisines: Set<String> = [] {
        didSet { applyFilter() }
    }

    /// Minimum star rating to include. Nil means show all (no rating filter).
    @Published var minimumRating: Int? {
        didSet { applyFilter() }
    }

    /// Text to filter restaurants by name or category. Empty = no text filter.
    @Published var searchText: String = "" {
        didSet { applyFilter() }
    }

    /// Whether to show the selected restaurant sheet.
    @Published var showSelectedRestaurant = false

    // MARK: - Dependencies

    private let locationManager: LocationManager
    private let searchService: RestaurantSearchService
    private(set) var ratingStore: RatingStore

    /// Cancellable for observing location override changes.
    private var overrideCancellable: AnyCancellable?

    /// Orchestrator that schedules all MapKit batch work.
    private let orchestrator: SearchOrchestrator

    /// Long-running task that consumes `orchestrator.updates`.
    private var orchestratorTask: Task<Void, Never>?

    /// ID of the orchestrator job that maps to the current UI location.
    ///
    /// Declared `internal` (not `private`) so unit tests can set it directly and
    /// feed synthetic `OrchestratorUpdate` values to `handleOrchestratorUpdate`.
    var currentSearchJobID: UUID?

    // MARK: - Search Cache

    /// A completed search result for a specific location.
    private struct SearchCacheEntry {
        let location: CLLocation
        let searchRadius: Double
        var restaurants: [Restaurant]
        let lastPrefetchDate: Date
    }

    /// Cache of search results keyed by location.
    private var searchCache: [SearchCacheEntry] = []

    /// Maximum distance (in metres) between two locations to consider
    /// them the same for caching purposes.
    private static let cacheSameLocationThreshold: Double = 50.0

    /// Time-to-live for cache entries (2 weeks).
    private static let cacheTTL: TimeInterval = 14 * 24 * 3600

    /// The search radius used for network calls. Always 10 km; UI filter applied client-side.
    private static let networkSearchRadius: Double = SearchOrchestrator.networkRadius

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
        let service = searchService ?? RestaurantSearchService()
        self.locationManager = locationManager ?? LocationManager()
        self.searchService = service
        self.ratingStore = ratingStore ?? RatingStore()
        self.orchestrator = SearchOrchestrator(searchService: service)
        observeOverrideLocation()
        startOrchestratorLoop()
    }

    /// Creates a new RestaurantViewModel with pre-loaded restaurants (for testing/previews).
    ///
    /// - Parameters:
    ///   - restaurants: Pre-loaded list of restaurants.
    ///   - ratingStore: Store for user ratings. Defaults to a new instance.
    @MainActor
    init(restaurants: [Restaurant], ratingStore: RatingStore? = nil) {
        let service = RestaurantSearchService()
        locationManager = LocationManager()
        searchService = service
        self.ratingStore = ratingStore ?? RatingStore()
        orchestrator = SearchOrchestrator(searchService: service)
        self.restaurants = restaurants
        filteredRestaurants = restaurants
    }

    // MARK: - Public Methods

    /// Fetches nearby restaurants based on the effective location.
    ///
    /// Uses the override location (map pin) if set, otherwise falls
    /// back to the device GPS location. On a cache hit for the resolved
    /// location, uses cached results immediately. On a miss, enqueues
    /// the location in `SearchOrchestrator` — no in-flight requests are
    /// cancelled; the orchestrator finishes the current batch first.
    func fetchNearbyRestaurants() async {
        isLoading = true
        errorMessage = nil

        let location: CLLocation

        if let override = locationManager.overrideLocation {
            location = override
        } else {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestAuthorization()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            guard locationManager.isAuthorized else {
                if locationManager.isDenied {
                    errorMessage = "Location access denied. Please enable location services in Settings."
                } else {
                    errorMessage = "Location access not yet authorized."
                }
                isLoading = false
                return
            }

            if locationManager.currentLocation == nil {
                locationManager.requestLocation()
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
        let focusRadius = filterRadius ?? 500

        // Cache hit — use stored results immediately without any network work
        if let cached = findCacheEntry(for: location, radius: radius) {
            restaurants = cached.restaurants
            applyFilter()
            errorMessage = nil
            isLoading = false
            isLoadingMore = false
            return
        }

        // Enqueue location in orchestrator — results arrive via handleOrchestratorUpdate
        currentSearchJobID = await orchestrator.enqueueLocation(
            location,
            focusRadius: focusRadius
        )
        // isLoading flips to false when the first update for currentSearchJobID arrives
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
        if let location = locationManager.effectiveLocation {
            searchCache.removeAll {
                $0.location.distance(from: location) < Self.cacheSameLocationThreshold
            }
        }
        await fetchNearbyRestaurants()
    }

    // MARK: - Orchestrator Loop

    /// Starts the long-running task that consumes `orchestrator.updates`.
    ///
    /// Called once from `init`. Runs on `@MainActor` so all UI mutations in
    /// `handleOrchestratorUpdate` are safe without extra hops.
    private func startOrchestratorLoop() {
        orchestratorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.orchestrator.start()
            for await update in self.orchestrator.updates {
                self.handleOrchestratorUpdate(update)
            }
        }
    }

    /// Processes one update from the orchestrator.
    ///
    /// - If the update belongs to `currentSearchJobID`, refreshes the live
    ///   restaurant list and manages the loading indicators.
    /// - Otherwise silently merges into the cache (background location work).
    ///
    /// Declared `internal` (not `private`) so unit tests can feed synthetic
    /// `OrchestratorUpdate` values without running a real orchestrator.
    func handleOrchestratorUpdate(_ update: OrchestratorUpdate) {
        if update.jobID == currentSearchJobID {
            restaurants = update.snapshot
            applyFilter()
            errorMessage = nil

            if isLoading {
                isLoading = false
                isLoadingMore = true
            }

            if update.isJobComplete {
                isLoadingMore = false
                if restaurants.isEmpty {
                    errorMessage = RestaurantSearchService.SearchError.noResults.localizedDescription
                }
                updateCache(
                    for: update.location,
                    radius: Self.networkSearchRadius,
                    restaurants: restaurants
                )
                scheduleBackgroundPrefetch(for: update.location)
            }
        } else {
            // Background job for a previous location — update cache silently
            mergeNewRestaurants(update.snapshot, for: update.location)
        }
    }

    /// Enqueues focused+scatter background prefetch jobs for filter radii that
    /// are larger than the current filter but not yet cached.
    ///
    /// Runs smallest-first so the most likely next radius is available soonest.
    /// Skips radii that already have a valid cache entry (no redundant work).
    /// The orchestrator processes these after all current-location narrow-pass
    /// work is exhausted, giving the live search permanent priority.
    ///
    /// - Parameter location: The location to prefetch (typically the just-completed
    ///   primary job's search centre).
    private func scheduleBackgroundPrefetch(for location: CLLocation) {
        let currentFocusRadius = filterRadius ?? 500
        let prefetchRadii: [Double] = [500, 1000, 2000, 5000]
            .filter { $0 > currentFocusRadius }
            .filter { radius in
                findCacheEntry(for: location, radius: Self.networkSearchRadius) == nil ||
                    !hasCoverageForFocusRadius(radius, at: location)
            }

        guard !prefetchRadii.isEmpty else { return }

        Task {
            for radius in prefetchRadii {
                await orchestrator.enqueueBackgroundPrefetch(
                    location: location,
                    focusRadius: radius
                )
            }
        }
    }

    /// Returns `true` if the cache already has results from a focused search
    /// at (or larger than) `focusRadius` for `location`.
    ///
    /// Used to avoid scheduling redundant background prefetch jobs.
    private func hasCoverageForFocusRadius(_ focusRadius: Double, at location: CLLocation) -> Bool {
        searchCache.contains { entry in
            entry.location.distance(from: location) < Self.cacheSameLocationThreshold &&
                entry.searchRadius >= focusRadius
        }
    }

    // MARK: - Cuisine-Specific Search

    /// Performs a targeted search for specific cuisines and merges results
    /// into the main restaurant list. Called when cuisine filters change.
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
    /// Expired entries are removed and return `nil`.
    private func findCacheEntry(for location: CLLocation, radius: Double) -> SearchCacheEntry? {
        let now = Date()
        searchCache.removeAll { entry in
            entry.location.distance(from: location) < Self.cacheSameLocationThreshold &&
                now.timeIntervalSince(entry.lastPrefetchDate) > Self.cacheTTL
        }

        return searchCache.first { entry in
            entry.searchRadius >= radius &&
                entry.location.distance(from: location) < Self.cacheSameLocationThreshold
        }
    }

    /// Updates or creates a cache entry for the given location.
    private func updateCache(for location: CLLocation, radius: Double, restaurants: [Restaurant]) {
        let now = Date()
        if let idx = searchCache.firstIndex(where: {
            $0.location.distance(from: location) < Self.cacheSameLocationThreshold
        }) {
            let merged = Self.mergeRestaurantLists(
                existing: searchCache[idx].restaurants, new: restaurants
            )
            searchCache[idx] = SearchCacheEntry(
                location: location,
                searchRadius: max(radius, searchCache[idx].searchRadius),
                restaurants: merged,
                lastPrefetchDate: now
            )
        } else {
            searchCache.append(SearchCacheEntry(
                location: location, searchRadius: radius, restaurants: restaurants,
                lastPrefetchDate: now
            ))
        }
    }

    // MARK: - Restaurant Merging

    /// Merges new restaurant results into the master list and updates the UI.
    ///
    /// If the location matches the current effective location, updates the live
    /// `restaurants` list and applies filters. Otherwise only updates the cache.
    private func mergeNewRestaurants(_ newResults: [Restaurant], for location: CLLocation) {
        let isCurrentLocation: Bool = if let effective = locationManager.effectiveLocation {
            effective.distance(from: location) < Self.cacheSameLocationThreshold
        } else {
            true
        }

        if isCurrentLocation {
            var merged = restaurants
            var changed = false

            for restaurant in newResults {
                let key = restaurant.name.lowercased()
                if let existingIndex = merged.firstIndex(where: { existing in
                    existing.name.lowercased() == key &&
                        abs(existing.coordinate.latitude - restaurant.coordinate.latitude) < 0.0005 &&
                        abs(existing.coordinate.longitude - restaurant.coordinate.longitude) < 0.0005
                }) {
                    let existing = merged[existingIndex]
                    let mergedTags = existing.cuisineTags.union(restaurant.cuisineTags)

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
                    merged.append(restaurant)
                    changed = true
                }
            }

            if changed {
                restaurants = merged.sorted { $0.distance < $1.distance }
                applyFilter()
                updateCache(for: location, radius: Self.networkSearchRadius, restaurants: restaurants)
            }
        } else {
            updateCache(for: location, radius: Self.networkSearchRadius, restaurants: newResults)
        }
    }

    /// Merges two restaurant lists, deduplicating by name + proximity.
    ///
    /// Declared `internal` (not `private`) so unit tests can verify the
    /// deduplication and sort behaviour in isolation.
    static func mergeRestaurantLists(
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
            .dropFirst()
            .removeDuplicates { lhs, rhs in
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

        if let radius = filterRadius {
            result = result.filter { $0.distance <= radius }
        }

        if !selectedCuisines.isEmpty {
            result = result.filter { !$0.cuisineTags.isDisjoint(with: selectedCuisines) }
        }

        if !excludedCuisines.isEmpty {
            result = result.filter { $0.cuisineTags.isDisjoint(with: excludedCuisines) }
        }

        if let minRating = minimumRating {
            if minRating == -1 {
                result = result.filter { ratingStore.rating(for: $0) == nil }
            } else {
                result = result.filter { restaurant in
                    guard let rating = ratingStore.rating(for: restaurant) else { return false }
                    return rating >= minRating
                }
            }
        }

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
    private func weightedRandomElement(from restaurants: [Restaurant]) -> Restaurant? {
        let weights = restaurants.map { Self.ratingWeight(for: ratingStore.rating(for: $0)) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return restaurants.randomElement() }

        var random = Double.random(in: 0 ..< totalWeight)
        for (index, weight) in weights.enumerated() {
            random -= weight
            if random < 0 { return restaurants[index] }
        }
        return restaurants.last
    }

    /// Normalizes a string for search comparison.
    static func normalizeForSearch(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }
}

// MARK: - Cuisine Filter

extension RestaurantViewModel {
    /// Static list of cuisine categories available for filtering.
    static let allCuisines: [String] = RestaurantSearchService.cuisineQueries
        .map(\.label)
        .filter { !RestaurantSearchService.genericCategories.contains($0) }
        .sorted()

    /// Unique, sorted list of cuisine categories available for filtering.
    var availableCuisines: [String] { Self.allCuisines }

    /// Total number of active filters (cuisine includes + excludes + rating).
    var activeCuisineFilterCount: Int {
        selectedCuisines.count + excludedCuisines.count + (minimumRating != nil ? 1 : 0)
    }
}

// MARK: - Rating Weights

extension RestaurantViewModel {
    /// Quadratic weight for a given star rating.
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
        ("All", nil),
    ]
}
