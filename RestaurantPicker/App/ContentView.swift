import SwiftUI

/// The main content view of the Restaurant Picker app.
///
/// Presents a `TabView` with two tabs:
/// - **Restaurants**: the restaurant list, filters, and decide button.
/// - **Map**: a full-screen map for setting a custom search location.
///
/// When the user drops a pin on the map tab, the restaurant list
/// automatically re-fetches using the pinned location.
struct ContentView: View {
    @EnvironmentObject private var ratingStore: RatingStore
    @EnvironmentObject private var locationManager: LocationManager
    @ObservedObject var viewModel: RestaurantViewModel

    /// Whether the filter sheet is presented.
    @State private var showCuisineFilter = false

    var body: some View {
        TabView {
            restaurantTab
                .tabItem {
                    Label("Restaurants", systemImage: "fork.knife")
                }

            MapLocationView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
        }
    }

    // MARK: - Restaurant Tab

    /// The full restaurant list tab content.
    private var restaurantTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Override location banner
                if locationManager.overrideLocation != nil {
                    overrideBanner
                }

                // Distance filter with cuisine filter button
                HStack(alignment: .bottom, spacing: 16) {
                    cuisineFilterButton

                    DistanceFilterView(selectedRadius: $viewModel.filterRadius)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Restaurant count
                if !viewModel.isLoading, viewModel.errorMessage == nil {
                    HStack {
                        Text(
                            "\(viewModel.filteredRestaurants.count) restaurant\(viewModel.filteredRestaurants.count == 1 ? "" : "s")"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        if viewModel.isLoadingMore {
                            Text("· finding more…")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }

                // Main content area
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(message: error)
                } else if viewModel.filteredRestaurants.isEmpty {
                    emptyView
                } else {
                    restaurantList
                }

                // Decide button at bottom
                DecideButtonView {
                    viewModel.selectRandomRestaurant()
                }
                .padding()
                .disabled(viewModel.filteredRestaurants.isEmpty)
            }
            .navigationTitle("Restaurant Picker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        requestRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .sheet(isPresented: $showCuisineFilter) {
                CuisineFilterView(
                    selectedCuisines: $viewModel.selectedCuisines,
                    excludedCuisines: $viewModel.excludedCuisines,
                    minimumRating: $viewModel.minimumRating
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $viewModel.showSelectedRestaurant) {
                if let restaurant = viewModel.selectedRestaurant {
                    SelectedRestaurantView(restaurant: restaurant) {
                        viewModel.clearSelection()
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search restaurants")
        .task {
            await viewModel.fetchNearbyRestaurants()
        }
    }

    // MARK: - Override Banner

    /// A banner displayed when the user has set a custom search location.
    private var overrideBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.red)
            Text("Searching custom location")
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Button("Reset") {
                locationManager.clearOverrideLocation()
            }
            .font(.caption)
            .fontWeight(.semibold)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }

    // MARK: - View Components

    /// A button that opens the cuisine filter sheet.
    /// Styled to match the distance filter chips.
    /// Shows a badge with the active filter count when filters are applied.
    private var cuisineFilterButton: some View {
        Button {
            showCuisineFilter = true
        } label: {
            Image(systemName: viewModel.activeCuisineFilterCount > 0
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .font(.system(size: 32))
                .frame(width: 52, height: 52)
                .background(
                    viewModel.activeCuisineFilterCount > 0
                        ? Color.accentColor
                        : Color.secondary.opacity(0.2)
                )
                .foregroundColor(
                    viewModel.activeCuisineFilterCount > 0
                        ? .white
                        : .primary
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if viewModel.activeCuisineFilterCount > 0 {
                Text("\(viewModel.activeCuisineFilterCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Color.red)
                    .clipShape(Circle())
                    .offset(x: 8, y: -8)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Finding nearby restaurants...")
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Button("Try Again") {
                requestRefresh()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "fork.knife")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No restaurants found")
                .font(.headline)
            Text("Try increasing the distance or adjusting cuisine filters")
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var restaurantList: some View {
        RestaurantListView(
            restaurants: viewModel.filteredRestaurants,
            selectedRestaurant: viewModel.selectedRestaurant
        )
    }

    /// Schedules a refresh on the view model, encapsulating the `Task` boilerplate.
    private func requestRefresh() {
        Task {
            await viewModel.refresh()
        }
    }
}

// MARK: - Preview

#Preview {
    let store = RatingStore()
    ContentView(viewModel: RestaurantViewModel(ratingStore: store))
        .environmentObject(store)
        .environmentObject(LocationManager())
}
