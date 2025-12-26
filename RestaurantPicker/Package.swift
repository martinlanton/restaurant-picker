// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RestaurantPicker",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "RestaurantPicker",
            targets: ["RestaurantPicker"]
        )
    ],
    targets: [
        .target(
            name: "RestaurantPicker",
            path: "RestaurantPicker",
            sources: [
                "App/RestaurantPickerApp.swift",
                "App/ContentView.swift",
                "Models/Restaurant.swift",
                "ViewModels/RestaurantViewModel.swift",
                "Views/RestaurantListView.swift",
                "Views/RestaurantRowView.swift",
                "Views/DistanceFilterView.swift",
                "Views/DecideButtonView.swift",
                "Views/SelectedRestaurantView.swift",
                "Services/LocationManager.swift",
                "Services/RestaurantSearchService.swift",
                "Utilities/Extensions.swift"
            ]
        ),
        .testTarget(
            name: "RestaurantPickerTests",
            dependencies: ["RestaurantPicker"],
            path: "RestaurantPickerTests"
        )
    ]
)

