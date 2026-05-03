import MapKit
import SwiftUI

/// A sheet view displaying the selected restaurant details.
///
/// Shows the restaurant name, category, distance, and provides
/// options to call the restaurant or open it in Maps.
struct SelectedRestaurantView: View {
    /// The restaurant that was selected.
    let restaurant: Restaurant

    /// Action to dismiss the sheet.
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Celebration icon
                Image(systemName: "party.popper")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                    .padding(.top, 32)

                // Restaurant name
                Text(restaurant.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Category and distance
                VStack(spacing: 8) {
                    if let category = restaurant.category {
                        Label(category, systemImage: "fork.knife")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    Label(restaurant.formattedDistance, systemImage: "location")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    if let phoneNumber = restaurant.phoneNumber {
                        Button {
                            callRestaurant(phoneNumber: phoneNumber)
                        } label: {
                            Label("Call Restaurant", systemImage: "phone")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }

                    Button {
                        restaurant.openInMaps()
                    } label: {
                        Label("Open in Maps", systemImage: "map")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button {
                        dismiss()
                        onDismiss()
                    } label: {
                        Text("Pick Again")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Your Restaurant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
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
}


// MARK: - Preview

#Preview {
    SelectedRestaurantView(
        restaurant: Restaurant(
            id: UUID(),
            name: "Amazing Thai Kitchen",
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: 750,
            category: "Thai",
            phoneNumber: "+1-555-123-4567",
            url: nil
        ),
        onDismiss: {}
    )
}
