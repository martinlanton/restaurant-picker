import SwiftUI

// MARK: - Filter Mode

private enum FilterMode: String, CaseIterable {
    case include = "Include"
    case exclude = "Exclude"
}

// MARK: - CuisineFilterView

/// A sheet for filtering restaurants by cuisine type using a two-level hierarchy.
///
/// The top level shows continents and countries as peers. Tapping an expandable
/// row reveals its leaf cuisine chips inline via `DisclosureGroup`.
///
/// - Continents expand to show every country label AND every regional cuisine
///   under those countries, all as flat chips.
/// - Countries expand to show only their own regional sub-cuisines.
/// - Countries with no sub-cuisines are simple leaf toggles.
///
/// A segmented picker at the top switches between Include and Exclude mode.
/// A tri-state indicator on each parent row reflects how many of its leaves
/// are currently active.
struct CuisineFilterView: View {
    // MARK: - Properties

    /// Cuisines to include (show only these). Empty = show all.
    @Binding var selectedCuisines: Set<String>

    /// Cuisines to exclude (hide these). Empty = exclude nothing.
    @Binding var excludedCuisines: Set<String>

    /// Minimum star rating filter. Nil = show all.
    @Binding var minimumRating: Int?

    @Environment(\.dismiss) private var dismiss

    @State private var filterMode: FilterMode = .include
    @State private var expandedRegions: Set<String> = []

    private let ratingOptions = RestaurantViewModel.ratingFilterOptions

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                ratingSection
                cuisineSection
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
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    private var ratingSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ratingOptions, id: \.label) { option in
                        chipButton(
                            label: option.label,
                            isActive: minimumRating == option.value,
                            activeColor: .orange
                        ) { minimumRating = option.value }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Minimum Rating")
        } footer: {
            Text("Unrated restaurants are hidden when a rating filter is active.")
        }
    }

    private var cuisineSection: some View {
        Section {
            // Include / Exclude mode picker
            Picker("Mode", selection: $filterMode) {
                ForEach(FilterMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // Hierarchy rows
            ForEach(CuisineHierarchy.regions) { region in
                regionRow(region)
            }
        } header: {
            Text("Cuisine")
        } footer: {
            Text(filterMode == .include
                ? "Include: show only selected cuisines. Empty = show all."
                : "Exclude: hide selected cuisines.")
        }
    }

    // MARK: - Region Row

    @ViewBuilder
    private func regionRow(_ region: CuisineRegion) -> some View {
        if region.isLeaf {
            // Simple leaf toggle (country with no sub-cuisines)
            leafToggleRow(
                label: region.name,
                cuisine: bareLabel(region.name)
            )
        } else {
            expandableRow(region)
        }
    }

    /// A full-width tappable row for an expandable continent or country.
    private func expandableRow(_ region: CuisineRegion) -> some View {
        let isExpanded = expandedRegions.contains(region.name)
        let leaves = region.isContinent ? continentLeaves(region) : region.allCuisines
        let activeSet = activeSetForMode()
        let state = triState(leaves: leaves, activeSet: activeSet)

        return VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedRegions.remove(region.name)
                    } else {
                        expandedRegions.insert(region.name)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Text(region.name)
                        .foregroundColor(.primary)

                    Spacer()

                    triStateIndicator(state: state, activeColor: activeColor())

                    // "Select All / None" button
                    Button {
                        toggleAll(leaves: leaves, state: state)
                    } label: {
                        Text(state == .all ? "None" : "All")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            // Expanded content
            if isExpanded {
                if region.isContinent {
                    continentExpandedContent(region)
                } else {
                    countryExpandedContent(region.allCuisines)
                }
            }
        }
    }

    /// Expanded view for a continent: chips for every leaf (countries + regionals).
    private func continentExpandedContent(_ region: CuisineRegion) -> some View {
        let leaves = continentLeaves(region)
        return chipGrid(cuisines: leaves)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    /// Expanded view for a country: chips for its regional sub-cuisines only.
    private func countryExpandedContent(_ cuisines: [String]) -> some View {
        chipGrid(cuisines: cuisines)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    /// A simple row for a leaf country (no sub-cuisines).
    private func leafToggleRow(label: String, cuisine: String) -> some View {
        let activeSet = activeSetForMode()
        let isActive = activeSet.contains(cuisine)
        return Button {
            toggle(cuisine: cuisine)
        } label: {
            HStack {
                Text(label)
                    .foregroundColor(.primary)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(activeColor())
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chip Grid

    private func chipGrid(cuisines: [String]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(cuisines, id: \.self) { cuisine in
                let activeSet = activeSetForMode()
                chipButton(
                    label: cuisine,
                    isActive: activeSet.contains(cuisine),
                    activeColor: activeColor()
                ) { toggle(cuisine: cuisine) }
            }
        }
    }

    // MARK: - Chip Button

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

    // MARK: - Tri-state Indicator

    private enum TriState { case none, some, all }

    private func triState(leaves: [String], activeSet: Set<String>) -> TriState {
        let active = leaves.filter { activeSet.contains($0) }.count
        if active == 0 { return .none }
        if active == leaves.count { return .all }
        return .some
    }

    @ViewBuilder
    private func triStateIndicator(state: TriState, activeColor: Color) -> some View {
        switch state {
        case .none:
            Image(systemName: "circle")
                .foregroundColor(.secondary.opacity(0.5))
        case .some:
            Image(systemName: "circle.lefthalf.filled")
                .foregroundColor(activeColor)
        case .all:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(activeColor)
        }
    }

    // MARK: - Helpers

    /// All leaf labels for a continent: country labels + all regional sub-cuisines.
    private func continentLeaves(_ region: CuisineRegion) -> [String] {
        var leaves: [String] = []
        for group in region.groups {
            // Add the country/group name itself as a leaf if it's a country (has cuisines or is standalone)
            leaves.append(group.name)
            // Add all regional sub-cuisines (skip if they duplicate the group name)
            for cuisine in group.cuisines where cuisine != group.name {
                if !leaves.contains(cuisine) {
                    leaves.append(cuisine)
                }
            }
        }
        return leaves
    }

    private func activeSetForMode() -> Set<String> {
        filterMode == .include ? selectedCuisines : excludedCuisines
    }

    private func activeColor() -> Color {
        filterMode == .include ? .accentColor : .red
    }

    /// Strips the flag emoji prefix from region names to get the bare cuisine label.
    /// e.g. "🇹🇭 Thai" → "Thai", "🌏 Asia" → "Asia"
    private func bareLabel(_ name: String) -> String {
        // Drop leading emoji + space
        let components = name.components(separatedBy: " ")
        if components.count > 1 {
            return components.dropFirst().joined(separator: " ")
        }
        return name
    }

    private func toggle(cuisine: String) {
        if filterMode == .include {
            if selectedCuisines.contains(cuisine) {
                selectedCuisines.remove(cuisine)
            } else {
                excludedCuisines.remove(cuisine)
                selectedCuisines.insert(cuisine)
            }
        } else {
            if excludedCuisines.contains(cuisine) {
                excludedCuisines.remove(cuisine)
            } else {
                selectedCuisines.remove(cuisine)
                excludedCuisines.insert(cuisine)
            }
        }
    }

    private func toggleAll(leaves: [String], state: TriState) {
        if state == .all {
            // Deselect all leaves
            for leaf in leaves {
                if filterMode == .include {
                    selectedCuisines.remove(leaf)
                } else {
                    excludedCuisines.remove(leaf)
                }
            }
        } else {
            // Select all leaves
            for leaf in leaves {
                if filterMode == .include {
                    excludedCuisines.remove(leaf)
                    selectedCuisines.insert(leaf)
                } else {
                    selectedCuisines.remove(leaf)
                    excludedCuisines.insert(leaf)
                }
            }
        }
    }
}

// MARK: - FlowLayout

/// A layout that wraps items horizontally, flowing to the next line when needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
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

        return (positions, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}

// MARK: - Preview

#Preview {
    CuisineFilterView(
        selectedCuisines: .constant(["Sushi", "Ramen", "Thai"]),
        excludedCuisines: .constant(["Pizza"]),
        minimumRating: .constant(nil)
    )
}
