import SwiftUI

/// A sheet for filtering restaurants by cuisine type.
///
/// Provides two sections — **Include** (show only these cuisines) and
/// **Exclude** (hide these cuisines) — with chip-toggle controls.
/// A cuisine cannot be both included and excluded at the same time.
///
/// ## Usage
/// ```swift
/// CuisineFilterView(
///     availableCuisines: viewModel.availableCuisines,
///     selectedCuisines: $viewModel.selectedCuisines,
///     excludedCuisines: $viewModel.excludedCuisines
/// )
/// ```
struct CuisineFilterView: View {
    /// The list of cuisine names to display as options.
    let availableCuisines: [String]

    /// Cuisines to include (show only these). Empty = show all.
    @Binding var selectedCuisines: Set<String>

    /// Cuisines to exclude (hide these). Empty = exclude nothing.
    @Binding var excludedCuisines: Set<String>

    /// Minimum star rating filter. Nil = show all.
    @Binding var minimumRating: Int?

    @Environment(\.dismiss) private var dismiss

    /// Available rating filter options.
    private let ratingOptions = RestaurantViewModel.ratingFilterOptions

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Rating Section

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ratingOptions, id: \.label) { option in
                                chipButton(
                                    label: option.label,
                                    isActive: minimumRating == option.value,
                                    activeColor: .orange
                                ) {
                                    minimumRating = option.value
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Minimum Rating")
                } footer: {
                    Text(
                        "Filter by your personal star ratings. Unrated restaurants are hidden when a rating filter is active."
                    )
                }

                // MARK: - Include Section

                Section {
                    chipGrid(
                        cuisines: availableCuisines,
                        active: selectedCuisines,
                        activeColor: .accentColor
                    ) { cuisine in
                        toggleInclude(cuisine)
                    }
                } header: {
                    Text("Include Only")
                } footer: {
                    Text("Tap cuisines to show only those types. Leave empty to show all.")
                }

                // MARK: - Exclude Section

                Section {
                    chipGrid(
                        cuisines: availableCuisines,
                        active: excludedCuisines,
                        activeColor: .red
                    ) { cuisine in
                        toggleExclude(cuisine)
                    }
                } header: {
                    Text("Exclude")
                } footer: {
                    Text("Tap cuisines to hide those types.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        selectedCuisines = []
                        excludedCuisines = []
                        minimumRating = nil
                    }
                    .disabled(selectedCuisines.isEmpty && excludedCuisines.isEmpty && minimumRating == nil)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Toggles a cuisine in/out of the include set.
    /// Removes it from the exclude set if it was there.
    private func toggleInclude(_ cuisine: String) {
        if selectedCuisines.contains(cuisine) {
            selectedCuisines.remove(cuisine)
        } else {
            excludedCuisines.remove(cuisine)
            selectedCuisines.insert(cuisine)
        }
    }

    /// Toggles a cuisine in/out of the exclude set.
    /// Removes it from the include set if it was there.
    private func toggleExclude(_ cuisine: String) {
        if excludedCuisines.contains(cuisine) {
            excludedCuisines.remove(cuisine)
        } else {
            selectedCuisines.remove(cuisine)
            excludedCuisines.insert(cuisine)
        }
    }

    /// A flowing grid of chip buttons for a given cuisine list.
    private func chipGrid(
        cuisines: [String],
        active: Set<String>,
        activeColor: Color,
        action: @escaping (String) -> Void
    ) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(cuisines, id: \.self) { cuisine in
                chipButton(
                    label: cuisine,
                    isActive: active.contains(cuisine),
                    activeColor: activeColor
                ) {
                    action(cuisine)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// A single chip button with consistent styling.
    private func chipButton(
        label: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isActive ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? activeColor : Color.secondary.opacity(0.2))
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FlowLayout

/// A layout that wraps items horizontally, flowing to the next line when needed.
///
/// Used to display cuisine chips in a natural wrapping grid rather than
/// a single horizontal scroll.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return (positions, CGSize(width: maxWidth, height: totalHeight))
    }
}

// MARK: - Preview

#Preview {
    CuisineFilterView(
        availableCuisines: ["Thai", "Italian", "Japanese", "Mexican", "French", "Indian", "Chinese", "Korean"],
        selectedCuisines: .constant(["Thai", "Japanese"]),
        excludedCuisines: .constant(["Mexican"]),
        minimumRating: .constant(3)
    )
}
