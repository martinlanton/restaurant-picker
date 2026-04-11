import SwiftUI

/// A control for filtering restaurants by distance.
///
/// Displays a segmented picker allowing users to select
/// a maximum distance for restaurant filtering.
struct DistanceFilterView: View {
    /// The currently selected radius in meters, or nil for all.
    @Binding var selectedRadius: Double?

    /// Available distance filter options.
    private let options = RestaurantViewModel.distanceOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Max Distance")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.label) { option in
                        Button {
                            selectedRadius = option.value
                        } label: {
                            Text(option.label)
                                .font(.subheadline)
                                .fontWeight(isSelected(option.value) ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected(option.value)
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.2)
                                )
                                .foregroundColor(
                                    isSelected(option.value)
                                        ? .white
                                        : .primary
                                )
                                .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    private func isSelected(_ value: Double?) -> Bool {
        selectedRadius == value
    }
}

// MARK: - Preview

#Preview {
    VStack {
        DistanceFilterView(selectedRadius: .constant(5000))
        DistanceFilterView(selectedRadius: .constant(nil))
    }
    .padding()
}
