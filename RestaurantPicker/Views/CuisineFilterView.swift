import SwiftUI

// MARK: - Filter Mode

private enum FilterMode: String, CaseIterable {
    case include = "Include"
    case exclude = "Exclude"
}

// MARK: - CuisineFilterView

/// A sheet for filtering restaurants by cuisine type using a two-level hierarchy.
///
/// All top-level regions (continents + countries) are shown as a flowing chip
/// cloud. Chips that have sub-cuisines show a small chevron. Tapping one opens
/// its sub-cuisine chips inline below the cloud, indented to signal nesting.
/// Only one top-level region can be open at a time.
struct CuisineFilterView: View {
    // MARK: - Properties

    @Binding var selectedCuisines: Set<String>
    @Binding var excludedCuisines: Set<String>
    @Binding var minimumRating: Int?

    @Environment(\.dismiss) private var dismiss

    @State private var filterMode: FilterMode = .include
    @State private var openRegion: String?

    private let ratingOptions = RestaurantViewModel.ratingFilterOptions
    private let chipSpacing: CGFloat = 8

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

    // MARK: - Rating Section

    private var ratingSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: chipSpacing) {
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

    // MARK: - Cuisine Section

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

            // Single list row that contains the entire chip cloud + inline expansion
            chipCloudRow
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowSeparator(.hidden)

        } header: {
            Text("Cuisine")
        } footer: {
            Text(filterMode == .include
                ? "Include: show only selected cuisines. Empty = show all."
                : "Exclude: hide selected cuisines.")
        }
    }

    // MARK: - Chip Cloud

    /// Uses RowInjectingLayout: a custom Layout that wraps chips into rows and
    /// injects the sub-panel view (the last child) after the row containing
    /// the open chip — all in a single layout pass, no measurement tricks needed.
    private var chipCloudRow: some View {
        let regions = CuisineHierarchy.regions
        // Index of the open region among all regions (-1 = none open)
        let openIdx = regions.firstIndex(where: { $0.name == openRegion }) ?? -1
        let hasPanel = openIdx >= 0 &&
            !(regions[openIdx].isLeaf) &&
            openRegion != nil

        return RowInjectingLayout(
            chipCount: regions.count,
            injectAfterChipIndex: hasPanel ? openIdx : -1,
            spacing: chipSpacing
        ) {
            // Chip subviews (indices 0 ..< regions.count)
            ForEach(regions) { region in
                regionChip(region)
            }
            // Sub-panel subview (index == regions.count), always present but
            // hidden when nothing is open so Layout always has the same child count.
            if let name = openRegion,
               let region = regions.first(where: { $0.name == name }),
               hasPanel
            {
                subCuisinePanel(for: region)
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    // MARK: - Region Chip

    /// Renders a single top-level cuisine region as a tappable chip.
    ///
    /// Leaf regions toggle their single cuisine directly; non-leaf regions
    /// expand/collapse an inline sub-cuisine panel.
    private func regionChip(_ region: CuisineRegion) -> some View {
        let isOpen = openRegion == region.name
        let isLeaf = region.isLeaf
        let activeSet = activeSetForMode()
        let leaves = leafCuisines(for: region)
        let isActive = isLeaf
            ? activeSet.contains(bareLabel(region.name))
            : (!leaves.isEmpty && leaves.allSatisfy { activeSet.contains($0) })
        let someActive = !isLeaf && leaves.contains(where: { activeSet.contains($0) })
        let color = activeColor()

        return Button {
            if isLeaf {
                toggle(cuisine: bareLabel(region.name))
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    openRegion = isOpen ? nil : region.name
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(region.name)
                    .font(.subheadline)
                    .fontWeight((isActive || someActive || isOpen) ? .semibold : .regular)
                if !isLeaf {
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(chipBg(isActive: isActive, someActive: someActive, isOpen: isOpen, color: color))
            .foregroundColor(chipFg(isActive: isActive, someActive: someActive, isOpen: isOpen, color: color))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    chipBorder(isActive: isActive, someActive: someActive, isOpen: isOpen, color: color),
                    lineWidth: 1.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sub-cuisine Panel

    /// Renders the expanded sub-cuisine panel for a non-leaf region.
    ///
    /// Includes a "Select all / Deselect all" header and individual chips
    /// for each leaf cuisine belonging to the region.
    /// Renders the expanded sub-cuisine panel for a non-leaf region.
    ///
    /// Includes a "Select all / Deselect all" header and individual chips
    /// for each leaf cuisine belonging to the region.
    private func subCuisinePanel(for region: CuisineRegion) -> some View {
        let leaves = leafCuisines(for: region)
        let activeSet = activeSetForMode()
        let state = triState(leaves: leaves, activeSet: activeSet)
        let color = activeColor()

        return VStack(alignment: .leading, spacing: 8) {
            // Top divider + "All / None" header
            HStack {
                // Visual indent line
                Rectangle()
                    .fill(color.opacity(0.4))
                    .frame(width: 2)
                    .cornerRadius(1)

                HStack {
                    Text(bareLabel(region.name))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        toggleAll(leaves: leaves, state: state)
                    } label: {
                        Text(state == .all ? "Deselect all" : "Select all")
                            .font(.caption)
                            .foregroundColor(color)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 20)

            // Sub-cuisine chips
            FlowLayout(spacing: chipSpacing) {
                ForEach(leaves, id: \.self) { cuisine in
                    chipButton(
                        label: cuisine,
                        isActive: activeSet.contains(cuisine),
                        activeColor: color
                    ) { toggle(cuisine: cuisine) }
                }
            }
        }
        .padding(.top, 10)
        .padding(.leading, 14)
        .padding(.bottom, 4)
    }

    // MARK: - Chip Styling

    /// Background fill for a chip based on its active/open state.
    private func chipBg(isActive: Bool, someActive: Bool, isOpen: Bool, color: Color) -> Color {
        if isActive { return color }
        if someActive || isOpen { return color.opacity(0.12) }
        return Color.secondary.opacity(0.15)
    }

    /// Foreground (text/icon) colour for a chip based on its active/open state.
    private func chipFg(isActive: Bool, someActive: Bool, isOpen: Bool, color: Color) -> Color {
        isActive ? .white : (someActive || isOpen ? color : .primary)
    }

    /// Stroke border colour for a chip based on its active/open state.
    private func chipBorder(isActive: Bool, someActive: Bool, isOpen: Bool, color: Color) -> Color {
        (isActive || (!someActive && !isOpen)) ? .clear : color.opacity(0.5)
    }

    /// Creates a styled pill button used for both cuisine chips and rating chips.
    ///
    /// - Parameters:
    ///   - label: Display text for the chip.
    ///   - isActive: Whether the chip is currently selected.
    ///   - activeColor: Accent colour used when selected.
    ///   - action: Closure to invoke when the chip is tapped.
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
                .background(isActive ? activeColor : Color.secondary.opacity(0.15))
                .foregroundColor(isActive ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tri-state

    /// Describes how many leaves in a region are currently active.
    private enum TriState { case none, some, all }

    /// Returns the tri-state for a group of leaf cuisines against the active set.
    ///
    /// - Parameters:
    ///   - leaves: All leaf cuisine labels for the region.
    ///   - activeSet: The currently selected (or excluded) set.
    /// - Returns: `.none`, `.some`, or `.all` depending on how many are active.
    private func triState(leaves: [String], activeSet: Set<String>) -> TriState {
        let n = leaves.filter { activeSet.contains($0) }.count
        return n == 0 ? .none : n == leaves.count ? .all : .some
    }

    // MARK: - Helpers

    /// Returns the flat list of leaf cuisines for a region, handling the
    /// continent vs country distinction.
    private func leafCuisines(for region: CuisineRegion) -> [String] {
        region.isContinent ? continentLeaves(region) : region.allCuisines
    }

    /// Builds the ordered leaf-cuisine list for a continent region, placing
    /// each country's name first followed by its sub-cuisines.
    private func continentLeaves(_ region: CuisineRegion) -> [String] {
        var out: [String] = []
        for group in region.groups {
            out.append(group.name)
            for c in group.cuisines where c != group.name && !out.contains(c) {
                out.append(c)
            }
        }
        return out
    }

    /// Returns the currently active cuisine set for the selected filter mode.
    private func activeSetForMode() -> Set<String> {
        filterMode == .include ? selectedCuisines : excludedCuisines
    }

    /// Returns the accent colour for the current filter mode.
    ///
    /// Include mode uses the app accent colour; exclude mode uses red.
    private func activeColor() -> Color {
        filterMode == .include ? .accentColor : .red
    }

    /// Strips the leading flag emoji from a region name, returning the plain label.
    ///
    /// For example `"🇯🇵 Japanese"` → `"Japanese"`, `"Japanese"` → `"Japanese"`.
    private func bareLabel(_ name: String) -> String {
        let p = name.components(separatedBy: " ")
        return p.count > 1 ? p.dropFirst().joined(separator: " ") : name
    }

    /// Toggles a single cuisine between selected, excluded, and unset,
    /// respecting the current filter mode.
    /// Toggles a single cuisine between selected, excluded, and unset,
    /// respecting the current filter mode.
    private func toggle(cuisine: String) {
        if filterMode == .include {
            if selectedCuisines.contains(cuisine) { selectedCuisines.remove(cuisine) }
            else { excludedCuisines.remove(cuisine); selectedCuisines.insert(cuisine) }
        } else {
            if excludedCuisines.contains(cuisine) { excludedCuisines.remove(cuisine) }
            else { selectedCuisines.remove(cuisine); excludedCuisines.insert(cuisine) }
        }
    }

    /// Toggles all leaf cuisines for a region on or off.
    ///
    /// When the current state is `.all` every leaf is deselected; otherwise every
    /// leaf is added to the active set (and removed from the opposing set).
    private func toggleAll(leaves: [String], state: TriState) {
        for leaf in leaves {
            if state == .all {
                if filterMode == .include { selectedCuisines.remove(leaf) } else { excludedCuisines.remove(leaf) }
            } else {
                if filterMode == .include { excludedCuisines.remove(leaf); selectedCuisines.insert(leaf) }
                else { selectedCuisines.remove(leaf); excludedCuisines.insert(leaf) }
            }
        }
    }
}

// MARK: - RowInjectingLayout

/// A custom Layout that:
/// 1. Wraps its first `chipCount` children into rows (like FlowLayout).
/// 2. Places its last child (the sub-panel) at full width immediately
///    after the row that contains chip at index `injectAfterChipIndex`.
/// 3. When `injectAfterChipIndex` is -1 the panel child is given zero size.
private struct RowInjectingLayout: Layout {
    let chipCount: Int
    let injectAfterChipIndex: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            let size = result.sizes[i]
            subviews[i].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(size)
            )
        }
    }

    // MARK: Core layout

    private struct LayoutResult {
        var origins: [CGPoint]
        var sizes: [CGSize]
        var totalSize: CGSize
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxW = proposal.width ?? 320
        let chips = subviews.prefix(chipCount)
        let panel = subviews.count > chipCount ? subviews[chipCount] : nil

        // Measure all chips
        let chipSizes = chips.map { $0.sizeThatFits(.unspecified) }

        // Build rows
        var rows: [[Int]] = [] // row → [chip index]
        var currentRow: [Int] = []
        var currentX: CGFloat = 0

        for (i, size) in chipSizes.enumerated() {
            let needed = currentRow.isEmpty ? size.width : size.width + spacing
            if currentX + needed > maxW, !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = [i]
                currentX = size.width
            } else {
                currentRow.append(i)
                currentX += needed
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        // Measure panel (full width, or zero if not injecting)
        let panelSize: CGSize = if let panel, injectAfterChipIndex >= 0 {
            panel.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
        } else {
            .zero
        }

        // Which row contains injectAfterChipIndex?
        let injectAfterRow: Int? = injectAfterChipIndex >= 0
            ? rows.firstIndex(where: { $0.contains(injectAfterChipIndex) })
            : nil

        // Assign origins
        var origins = [CGPoint](repeating: .zero, count: subviews.count)
        var sizes = [CGSize](repeating: .zero, count: subviews.count)
        var y: CGFloat = 0

        for (rowIdx, row) in rows.enumerated() {
            let rowHeight = row.map { chipSizes[$0].height }.max() ?? 0
            var x: CGFloat = 0
            for chipIdx in row {
                origins[chipIdx] = CGPoint(x: x, y: y)
                sizes[chipIdx] = chipSizes[chipIdx]
                x += chipSizes[chipIdx].width + spacing
            }
            y += rowHeight

            // Inject panel after this row if needed
            if rowIdx == injectAfterRow {
                y += spacing
                if subviews.count > chipCount {
                    origins[chipCount] = CGPoint(x: 0, y: y)
                    sizes[chipCount] = panelSize
                    y += panelSize.height
                }
            }

            if rowIdx < rows.count - 1 { y += spacing }
        }

        return LayoutResult(
            origins: origins,
            sizes: sizes,
            totalSize: CGSize(width: maxW, height: y)
        )
    }
}

// MARK: - FlowLayout

/// A simple wrapping flow layout that places children left-to-right,
/// wrapping to the next line when a child would exceed the available width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (i, pos) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxW = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
            positions.append(CGPoint(x: x, y: y))
            lineH = max(lineH, s.height)
            x += s.width + spacing
        }
        return (positions, CGSize(width: maxW, height: y + lineH))
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
