import SwiftUI

/// Main entry point for the Restaurant Picker application.
///
/// This file sets up the app structure and the main window scene.
/// The `LocationManager` is created here and shared with both
/// the view model and the map tab via environment object.
@main
struct RestaurantPickerApp: App {
    @StateObject private var ratingStore: RatingStore
    @StateObject private var locationManager: LocationManager
    @StateObject private var viewModel: RestaurantViewModel

    init() {
        let store = RatingStore()
        let locManager = LocationManager()
        _ratingStore = StateObject(wrappedValue: store)
        _locationManager = StateObject(wrappedValue: locManager)
        _viewModel = StateObject(
            wrappedValue: RestaurantViewModel(
                locationManager: locManager,
                ratingStore: store
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environmentObject(ratingStore)
                .environmentObject(locationManager)
        }
    }
}
