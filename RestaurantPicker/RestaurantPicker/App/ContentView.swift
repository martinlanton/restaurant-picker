import SwiftUI

/// The main content view of the Restaurant Picker app.
///
/// This view composes the restaurant list, distance filter, and
/// the decide button into a cohesive user interface.
struct ContentView: View {
    @StateObject private var viewModel = RestaurantViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Distance filter
                DistanceFilterView(selectedRadius: $viewModel.filterRadius)
                    .padding(.horizontal)
                    .padding(.top, 8)

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
            .sheet(isPresented: $viewModel.showSelectedRestaurant) {
                if let restaurant = viewModel.selectedRestaurant {
                    SelectedRestaurantView(restaurant: restaurant) {
                        viewModel.clearSelection()
                    }
                }
            }
        }
        .task {
            await viewModel.fetchNearbyRestaurants()
        }
    }

    // MARK: - View Components

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
            Text("Try increasing the distance filter")
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
    ContentView()
}

