# Restaurant Picker iOS App

An iOS application that helps users randomly select nearby restaurants. The app uses Apple MapKit to discover restaurants within a configurable distance radius and allows users to randomly pick one with a single tap.

## Features

- 📍 **Location-based search**: Automatically finds restaurants near your current location
- 📏 **Distance filtering**: Filter restaurants by distance (500m, 1km, 2km, 5km, 10km, or all)
- 🎲 **Random selection**: Tap the "Pick a Restaurant!" button to randomly select a restaurant
- 📞 **Quick actions**: Call the restaurant or get directions in Apple Maps
- 🗺️ **Apple MapKit integration**: Uses native MapKit for restaurant discovery

## Requirements

- iOS 17.0+
- Xcode 15+
- Swift 5.9+

## Project Structure

```
RestaurantPicker/
├── App/
│   ├── RestaurantPickerApp.swift    # App entry point
│   └── ContentView.swift            # Main view composing all UI elements
├── Models/
│   └── Restaurant.swift             # Restaurant data model
├── ViewModels/
│   └── RestaurantViewModel.swift    # Business logic and state management
├── Views/
│   ├── RestaurantListView.swift     # Scrollable list of restaurants
│   ├── RestaurantRowView.swift      # Individual restaurant row
│   ├── DistanceFilterView.swift     # Distance filter control
│   ├── DecideButtonView.swift       # Random selection button
│   └── SelectedRestaurantView.swift # Selected restaurant details sheet
├── Services/
│   ├── LocationManager.swift        # User location management
│   └── RestaurantSearchService.swift # MapKit restaurant search
└── Utilities/
    └── Extensions.swift             # Helper extensions
```

## Setup

### Creating the Xcode Project

Since this is a source-only package, you need to create an Xcode project:

1. Open Xcode
2. Create a new iOS App project:
   - **Product Name**: RestaurantPicker
   - **Team**: Your development team
   - **Organization Identifier**: com.yourcompany
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Minimum Deployment**: iOS 17.0

3. Replace the generated files with the files from this folder structure

4. Add the `Info.plist` entries or copy the provided `Info.plist`

### Location Permissions

The app requires location permission to work. The `Info.plist` includes:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Restaurant Picker needs your location to find nearby restaurants.</string>
```

## Usage

1. **Launch the app** - It will request location permission on first launch
2. **Grant location access** - The app needs this to find nearby restaurants
3. **View restaurants** - Restaurants appear sorted by distance
4. **Filter by distance** - Use the filter at the top to narrow results
5. **Pick a restaurant** - Tap "Pick a Restaurant!" for a random selection
6. **Take action** - Call the restaurant or get directions from the result sheet

## Architecture

The app follows the **MVVM (Model-View-ViewModel)** architecture:

- **Model** (`Restaurant`): Simple data structure for restaurant information
- **View** (SwiftUI views): Declarative UI components
- **ViewModel** (`RestaurantViewModel`): Manages state, business logic, and coordinates services
- **Services**: Handle external concerns (location, MapKit search)

## API Used

The app uses **Apple MapKit's MKLocalSearch** API to discover restaurants:

- No API key required
- Free to use
- Native iOS integration
- Rich POI (Points of Interest) data

## Testing

Run tests with:
- `Cmd+U` in Xcode
- Or via command line:
  ```bash
  xcodebuild test \
    -scheme RestaurantPicker \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0'
  ```

## Contributing

1. Follow Swift API Design Guidelines
2. Use SwiftFormat for code formatting
3. Use SwiftLint for linting
4. Write tests for new functionality
5. Document public APIs with Swift doc comments

## License

MIT License - See LICENSE file in the root directory.

