import CoreLocation
import Foundation
import SwiftUI

/// A local-only store for user restaurant ratings.
///
/// Persists ratings to `UserDefaults` so they survive app restarts.
/// Ratings are keyed by restaurant name + coordinate (not UUID) so
/// the same physical restaurant retains its rating across searches.
///
/// An in-memory cache is kept in sync with `UserDefaults` so that
/// reads (e.g. during filter passes over hundreds of restaurants)
/// never touch the disk layer. The cache is pre-loaded at init time
/// by scanning all `UserDefaults` keys with the `restaurant_rating_`
/// prefix, and is updated synchronously on every `setRating` call.
///
/// ## Usage
/// ```swift
/// let store = RatingStore()
/// store.setRating(4, for: restaurant)
/// let rating = store.rating(for: restaurant)  // 4
/// ```
final class RatingStore: ObservableObject {
    // MARK: - Constants

    /// Prefix for all rating keys in UserDefaults.
    private static let keyPrefix = "restaurant_rating_"

    // MARK: - Dependencies

    private let defaults: UserDefaults

    // MARK: - In-Memory Cache

    /// All ratings currently persisted, keyed by the same string produced by `key(for:)`.
    ///
    /// A key present in this dictionary means the restaurant is rated (0–5).
    /// A key absent from this dictionary means the restaurant is unrated.
    /// The cache is the source of truth for reads; `UserDefaults` is the
    /// source of truth for persistence across launches.
    private var ratingCache: [String: Int]

    // MARK: - Initialization

    /// Creates a RatingStore backed by the given UserDefaults suite.
    ///
    /// Pre-loads all existing ratings into the in-memory cache on init so that
    /// subsequent `rating(for:)` calls never hit `UserDefaults` directly.
    ///
    /// - Parameter defaults: The UserDefaults instance to use. Defaults to `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Pre-load all persisted ratings into the cache in one pass.
        let prefix = Self.keyPrefix
        ratingCache = defaults.dictionaryRepresentation()
            .filter { $0.key.hasPrefix(prefix) }
            .compactMapValues { $0 as? Int }
    }

    // MARK: - Public Methods

    /// Returns the user's rating for a restaurant, or nil if not rated.
    ///
    /// Reads from the in-memory cache — no `UserDefaults` access at call time.
    ///
    /// - Parameter restaurant: The restaurant to look up.
    /// - Returns: An integer rating from 0 to 5 (0 = rejected), or nil (unrated).
    func rating(for restaurant: Restaurant) -> Int? {
        ratingCache[Self.key(for: restaurant)]
    }

    /// Saves or removes a user rating for a restaurant.
    ///
    /// Ratings are clamped to the range 0...5. 0 means "rejected".
    /// Pass nil to remove the rating (back to unrated).
    /// Updates both the in-memory cache and `UserDefaults` atomically.
    ///
    /// - Parameters:
    ///   - rating: The rating (0–5) or nil to clear.
    ///   - restaurant: The restaurant to rate.
    func setRating(_ rating: Int?, for restaurant: Restaurant) {
        let key = Self.key(for: restaurant)
        if let rating {
            let clamped = min(max(rating, 0), 5)
            ratingCache[key] = clamped
            defaults.set(clamped, forKey: key)
        } else {
            ratingCache.removeValue(forKey: key)
            defaults.removeObject(forKey: key)
        }
        objectWillChange.send()
    }

    /// Returns a SwiftUI `Binding` that reads and writes the rating for a restaurant.
    ///
    /// Use this to eliminate the duplicated `ratingBinding` computed property
    /// that would otherwise appear in every view displaying a `StarRatingView`.
    ///
    /// - Parameter restaurant: The restaurant to bind the rating to.
    /// - Returns: A `Binding<Int?>` backed by this store.
    func ratingBinding(for restaurant: Restaurant) -> Binding<Int?> {
        Binding(
            get: { self.rating(for: restaurant) },
            set: { self.setRating($0, for: restaurant) }
        )
    }

    // MARK: - Key Generation

    /// Generates a stable storage key for a restaurant based on name + coordinate.
    ///
    /// Uses name and rounded coordinates so the same physical restaurant
    /// produces the same key regardless of UUID or minor coordinate drift.
    ///
    /// - Parameter restaurant: The restaurant.
    /// - Returns: A deterministic string key.
    static func key(for restaurant: Restaurant) -> String {
        let lat = String(format: "%.4f", restaurant.coordinate.latitude)
        let lon = String(format: "%.4f", restaurant.coordinate.longitude)
        let name = restaurant.name.lowercased().trimmingCharacters(in: .whitespaces)
        return "\(keyPrefix)\(name)_\(lat)_\(lon)"
    }
}
