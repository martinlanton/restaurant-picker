import MapKit
import SwiftUI

/// A detail view displaying full restaurant information.
///
/// Shows the restaurant name, category, distance, phone number,
/// and website, along with action buttons to call or open in Maps.
///
/// Designed to be pushed via `NavigationLink` from the restaurant list.
struct RestaurantDetailView: View {
    /// The restaurant to display.
    let restaurant: Restaurant

    @EnvironmentObject private var ratingStore: RatingStore

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header icon
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                    .padding(.top, 24)

                // Restaurant name
                Text(restaurant.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // User rating
                VStack(spacing: 4) {
                    Text("Your Rating")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    StarRatingView(
                        rating: ratingBinding,
                        isInteractive: true,
                        starSize: 28,
                        displayMode: .full
                    )
                }

                // Info section
                VStack(spacing: 12) {
                    if let category = restaurant.category {
                        DetailRow(icon: "fork.knife", label: "Cuisine", value: category)
                    }

                    DetailRow(icon: "location", label: "Distance", value: restaurant.formattedDistance)

                    if let phoneNumber = restaurant.phoneNumber {
                        DetailRow(icon: "phone", label: "Phone", value: phoneNumber)
                    }

                    if let url = restaurant.url {
                        DetailRow(icon: "globe", label: "Website", value: url.host ?? url.absoluteString)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Action buttons
                VStack(spacing: 12) {
                    if let phoneNumber = restaurant.phoneNumber {
                        Button {
                            callRestaurant(phoneNumber: phoneNumber)
                        } label: {
                            Label("Call Restaurant", systemImage: "phone.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }

                    Button {
                        openInMaps()
                    } label: {
                        Label("Open in Maps", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    if let url = restaurant.url {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Label("Visit Website", systemImage: "safari.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Restaurant Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Private Methods

    private func callRestaurant(phoneNumber: String) {
        let cleaned = phoneNumber.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        if let url = URL(string: "tel://\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: restaurant.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = restaurant.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
        ])
    }

    private var ratingBinding: Binding<Int?> {
        Binding(
            get: { ratingStore.rating(for: restaurant) },
            set: { ratingStore.setRating($0, for: restaurant) }
        )
    }
}

// MARK: - Detail Row

/// A single row of restaurant detail information.
private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RestaurantDetailView(
            restaurant: Restaurant(
                id: UUID(),
                name: "Amazing Thai Kitchen",
                coordinate: .init(latitude: 40.7128, longitude: -74.0060),
                distance: 750,
                category: "Thai",
                phoneNumber: "+1-555-123-4567",
                url: URL(string: "https://example.com")
            )
        )
    }
    .environmentObject(RatingStore())
}
