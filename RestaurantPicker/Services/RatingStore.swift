import CoreLocation
import Foundation

/// A local-only store for user restaurant ratings.
///
/// Persists ratings to `UserDefaults` so they survive app restarts.
/// Ratings are keyed by restaurant name + coordinate (not UUID) so
/// the same physical restaurant retains its rating across searches.
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

    // MARK: - Initialization

    /// Creates a RatingStore backed by the given UserDefaults suite.
    ///
    /// - Parameter defaults: The UserDefaults instance to use. Defaults to `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public Methods

    /// Returns the user's rating for a restaurant, or nil if not rated.
    ///
    /// - Parameter restaurant: The restaurant to look up.
    /// - Returns: An integer rating from 0 to 5 (0 = rejected), or nil (unrated).
    func rating(for restaurant: Restaurant) -> Int? {
        let key = Self.key(for: restaurant)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    /// Saves or removes a user rating for a restaurant.
    ///
    /// Ratings are clamped to the range 0...5. 0 means "rejected".
    /// Pass nil to remove the rating (back to unrated).
    ///
    /// - Parameters:
    ///   - rating: The rating (0–5) or nil to clear.
    ///   - restaurant: The restaurant to rate.
    func setRating(_ rating: Int?, for restaurant: Restaurant) {
        let key = Self.key(for: restaurant)
        if let rating {
            let clamped = min(max(rating, 0), 5)
            defaults.set(clamped, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        objectWillChange.send()
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
