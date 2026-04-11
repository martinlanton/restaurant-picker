import SwiftUI

/// The main content view of the Restaurant Picker app.
///
/// This view composes the restaurant list, distance filter, and
/// the decide button into a cohesive user interface.
struct ContentView: View {
    @EnvironmentObject private var ratingStore: RatingStore
    @ObservedObject var viewModel: RestaurantViewModel

    /// Whether the filter sheet is presented.
    @State private var showCuisineFilter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                        Text("\(viewModel.filteredRestaurants.count) restaurant\(viewModel.filteredRestaurants.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .sheet(isPresented: $showCuisineFilter) {
                CuisineFilterView(
                    availableCuisines: viewModel.availableCuisines,
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
                Task {
                    await viewModel.refresh()
                }
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
}

// MARK: - Preview

#Preview {
    let store = RatingStore()
    ContentView(viewModel: RestaurantViewModel(ratingStore: store))
        .environmentObject(store)
}
