import SwiftUI

/// Main entry point for the Restaurant Picker application.
///
/// This file sets up the app structure and the main window scene.
@main
struct RestaurantPickerApp: App {
    @StateObject private var ratingStore = RatingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ratingStore)
        }
    }
}

