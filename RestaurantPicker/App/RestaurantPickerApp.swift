import SwiftUI

/// Main entry point for the Restaurant Picker application.
///
/// This file sets up the app structure and the main window scene.
@main
struct RestaurantPickerApp: App {
    @StateObject private var ratingStore = RatingStore()
    @StateObject private var viewModel: RestaurantViewModel

    init() {
        let store = RatingStore()
        _ratingStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: RestaurantViewModel(ratingStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environmentObject(ratingStore)
        }
    }
}

