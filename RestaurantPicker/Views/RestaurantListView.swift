import SwiftUI

/// A scrollable list displaying nearby restaurants.
///
/// This view shows restaurants sorted by distance with their
/// name and distance from the user's location.
struct RestaurantListView: View {
    /// The list of restaurants to display.
    let restaurants: [Restaurant]

    /// The currently selected restaurant (to highlight).
    let selectedRestaurant: Restaurant?

    var body: some View {
        List(restaurants) { restaurant in
            RestaurantRowView(
                restaurant: restaurant,
                isSelected: restaurant.id == selectedRestaurant?.id
            )
        }
        .listStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    RestaurantListView(
        restaurants: [
            Restaurant(
                id: UUID(),
                name: "Thai Cafe",
                coordinate: .init(latitude: 40.7128, longitude: -74.0060),
                distance: 350,
                category: "Thai",
                phoneNumber: nil,
                url: nil
            ),
            Restaurant(
                id: UUID(),
                name: "Pizza Palace",
                coordinate: .init(latitude: 40.7200, longitude: -74.0100),
                distance: 1250,
                category: "Italian",
                phoneNumber: nil,
                url: nil
            ),
            Restaurant(
                id: UUID(),
                name: "Sushi Express",
                coordinate: .init(latitude: 40.7150, longitude: -74.0080),
                distance: 2800,
                category: "Japanese",
                phoneNumber: nil,
                url: nil
            )
        ],
        selectedRestaurant: nil
    )
}

