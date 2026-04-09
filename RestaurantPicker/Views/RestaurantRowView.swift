import SwiftUI

/// A single row displaying restaurant information.
///
/// Shows the restaurant name, category (if available), and distance.
struct RestaurantRowView: View {
    /// The restaurant to display.
    let restaurant: Restaurant

    /// Whether this restaurant is currently selected.
    var isSelected: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(restaurant.name)
                    .font(.headline)
                    .foregroundColor(isSelected ? .accentColor : .primary)

                if let category = restaurant.category {
                    Text(category)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(restaurant.formattedDistance)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        RestaurantRowView(
            restaurant: Restaurant(
                id: UUID(),
                name: "Thai Cafe",
                coordinate: .init(latitude: 40.7128, longitude: -74.0060),
                distance: 350,
                category: "Thai",
                phoneNumber: nil,
                url: nil
            )
        )

        RestaurantRowView(
            restaurant: Restaurant(
                id: UUID(),
                name: "Pizza Palace",
                coordinate: .init(latitude: 40.7200, longitude: -74.0100),
                distance: 1250,
                category: "Italian",
                phoneNumber: nil,
                url: nil
            ),
            isSelected: true
        )
    }
    .padding()
}

