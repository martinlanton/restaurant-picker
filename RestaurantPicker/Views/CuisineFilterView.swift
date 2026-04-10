import SwiftUI

/// A control for filtering restaurants by cuisine type.
///
/// Displays a horizontally scrollable row of cuisine chips.
/// Tapping a chip toggles it on/off (multi-select). When no
/// cuisines are selected, all restaurants are shown.
///
/// ## Usage
/// ```swift
/// CuisineFilterView(
///     availableCuisines: viewModel.availableCuisines,
///     selectedCuisines: $viewModel.selectedCuisines
/// )
/// ```
struct CuisineFilterView: View {
    /// The list of cuisine names to display as chips.
    let availableCuisines: [String]

    /// The currently selected cuisines (multi-select).
    @Binding var selectedCuisines: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cuisine")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All" chip — clears the selection
                    chipButton(label: "All", isActive: selectedCuisines.isEmpty) {
                        selectedCuisines = []
                    }

                    ForEach(availableCuisines, id: \.self) { cuisine in
                        chipButton(label: cuisine, isActive: selectedCuisines.contains(cuisine)) {
                            toggleCuisine(cuisine)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Toggles a cuisine in or out of the selected set.
    private func toggleCuisine(_ cuisine: String) {
        if selectedCuisines.contains(cuisine) {
            selectedCuisines.remove(cuisine)
        } else {
            selectedCuisines.insert(cuisine)
        }
    }

    /// A single chip button with consistent styling.
    private func chipButton(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isActive ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        CuisineFilterView(
            availableCuisines: ["Thai", "Italian", "Japanese", "Mexican", "French"],
            selectedCuisines: .constant([])
        )
        CuisineFilterView(
            availableCuisines: ["Thai", "Italian", "Japanese", "Mexican", "French"],
            selectedCuisines: .constant(["Thai", "Japanese"])
        )
    }
    .padding()
}
