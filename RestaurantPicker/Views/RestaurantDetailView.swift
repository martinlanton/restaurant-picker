import MapKit
import SwiftUI

/// A detail view displaying restaurant information.
///
/// Shows the restaurant name, user star rating, an "Open in Maps" button,
/// and Apple's built-in detail card (with Tabelog ratings, hours, price, etc.).
///
/// The top section is fixed; Apple's detail card fills the remaining
/// screen space and handles its own scrolling naturally.
///
/// Designed to be pushed via `NavigationLink` from the restaurant list.
struct RestaurantDetailView: View {
    /// The restaurant to display.
    let restaurant: Restaurant

    @EnvironmentObject private var ratingStore: RatingStore

    var body: some View {
        VStack(spacing: 0) {
            // Fixed top section
            VStack(spacing: 12) {
                // Restaurant name
                Text(restaurant.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 12)

                // User rating
                HStack(spacing: 8) {
                    Text("Your Rating")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    StarRatingView(
                        rating: ratingBinding,
                        isInteractive: true,
                        starSize: 22,
                        displayMode: .full
                    )
                }

                // Open in Maps button
                Button {
                    restaurant.openInMaps()
                } label: {
                    Label("Open in Maps", systemImage: "map.fill")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(.systemBackground))

            Divider()

            // Apple's built-in detail card — fills remaining space
            AppleMapItemDetailView(restaurant: restaurant)
        }
        .navigationTitle("Restaurant Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Private Methods

    private var ratingBinding: Binding<Int?> {
        ratingStore.ratingBinding(for: restaurant)
    }
}

// MARK: - Apple Map Item Detail

/// A SwiftUI view that resolves a restaurant to a full `MKMapItem` via search,
/// then displays Apple's built-in detail card.
struct AppleMapItemDetailView: View {
    let restaurant: Restaurant

    /// Search radius (in metres) used when resolving a restaurant to an `MKMapItem`.
    private static let resolveSearchRadius: Double = 100

    @State private var resolvedItem: MKMapItem?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let item = resolvedItem {
                MapItemDetailRepresentable(mapItem: item)
            } else if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading details...")
                    Spacer()
                }
            } else {
                VStack {
                    Spacer()
                    Text("Details not available")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .task {
            await resolveMapItem()
        }
    }

    /// Searches for the restaurant by name near its coordinate to get
    /// the real `MKMapItem` with full Apple metadata.
    private func resolveMapItem() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = restaurant.name
        request.region = MKCoordinateRegion(
            center: restaurant.coordinate,
            radius: Self.resolveSearchRadius
        )
        request.resultTypes = .pointOfInterest

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            let target = restaurant.coordinate.asLocation
            resolvedItem = response.mapItems.first { item in
                guard let name = item.name else { return false }
                return name.lowercased() == restaurant.name.lowercased()
                    && target.distance(from: item.placemark.coordinate.asLocation)
                    < Self.resolveSearchRadius
            } ?? response.mapItems.first
        } catch {
            let placemark = MKPlacemark(coordinate: restaurant.coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = restaurant.name
            item.phoneNumber = restaurant.phoneNumber
            item.url = restaurant.url
            resolvedItem = item
        }

        isLoading = false
    }
}

// MARK: - MKMapItemDetailViewController Wrapper

/// A simple `UIViewControllerRepresentable` for `MKMapItemDetailViewController`.
/// The controller manages its own scrolling and fills whatever space is given.
private struct MapItemDetailRepresentable: UIViewControllerRepresentable {
    let mapItem: MKMapItem

    func makeUIViewController(context: Context) -> MKMapItemDetailViewController {
        MKMapItemDetailViewController(mapItem: mapItem)
    }

    func updateUIViewController(_ uiViewController: MKMapItemDetailViewController, context: Context) {}
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
