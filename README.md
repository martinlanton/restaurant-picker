# Restaurant Picker 🍽️

An iOS app that helps you decide where to eat by randomly selecting from nearby restaurants. Built with SwiftUI and Apple MapKit.

## Features

- **Discover nearby restaurants** using Apple Maps data
- **Filter by distance** — 500m, 1km, 2km, 5km, 10km, or show all
- **Random selection** — tap "Pick a Restaurant!" and let the app decide for you
- **Restaurant details** — see the category, distance, phone number, and website
- **Call or navigate** — call the restaurant directly or open directions in Apple Maps
- **Multi-cuisine search** — searches 36 cuisine types in parallel to find more restaurants than a single MapKit query returns

## Screenshots

<!-- Add screenshots here -->

## Requirements

- iOS 17.0+
- Xcode 16.0+
- Swift 5.9+

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/restaurant-picker.git
cd restaurant-picker
```

### 2. Generate the Xcode project

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml`.

```bash
brew install xcodegen
xcodegen generate
```

### 3. Open in Xcode

```bash
open RestaurantPicker.xcodeproj
```

### 4. Configure signing

In Xcode, select the **RestaurantPicker** target → **Signing & Capabilities** → set your **Development Team**.

### 5. Build and run

Select your device or simulator and press **⌘R**.

> **Note**: The app requires location permissions to find nearby restaurants. When running on a simulator, you can set a simulated location via **Features → Location** in the Simulator menu.

## Architecture

The project follows the **MVVM** (Model-View-ViewModel) pattern:

```
RestaurantPicker/
├── App/
│   ├── RestaurantPickerApp.swift    # App entry point
│   └── ContentView.swift            # Main view composition
├── Models/
│   └── Restaurant.swift             # Restaurant data model
├── ViewModels/
│   └── RestaurantViewModel.swift    # Business logic & state
├── Views/
│   ├── RestaurantListView.swift     # Scrollable restaurant list
│   ├── RestaurantRowView.swift      # Single restaurant row
│   ├── SelectedRestaurantView.swift # Selection result sheet
│   ├── DistanceFilterView.swift     # Distance filter control
│   └── DecideButtonView.swift       # Random pick button
├── Services/
│   ├── LocationManager.swift        # CoreLocation wrapper
│   └── RestaurantSearchService.swift # MapKit search (parallel queries)
└── Utilities/
    └── Extensions.swift             # Helper extensions
```

### Data Flow

1. **ContentView** creates a `RestaurantViewModel` as a `@StateObject`
2. On appear, the ViewModel requests location permission and fetches restaurants
3. `RestaurantSearchService` runs 36 cuisine-specific `MKLocalSearch` queries in parallel
4. Results are deduplicated and sorted by distance
5. The user filters by distance and taps "Pick a Restaurant!" to get a random selection

## Running Tests

### In Xcode

Press **⌘U** to run all tests.

### From the command line

```bash
xcodebuild test \
  -scheme RestaurantPicker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Code Quality

### SwiftFormat

```bash
brew install swiftformat
swiftformat .
```

### SwiftLint

```bash
brew install swiftlint
swiftlint
```

## Known Limitations

- **Apple MapKit returns ~25 results per query**. The app mitigates this by running parallel cuisine-specific searches, but coverage depends on Apple Maps data for your area.
- **Restaurant categories** are derived from the search query that found them (e.g., "Thai", "Italian") since MapKit's `pointOfInterestCategory` returns generic values.

## License

See [LICENSE](LICENSE) for details.
