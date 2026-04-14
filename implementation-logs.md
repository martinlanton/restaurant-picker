# Implementation Log: Strip Generic Labels from Cuisine Tags

**Date**: 2026-04-12
**Author**: GitHub Copilot

## Overview

Restaurants in the main list were displaying generic POI category labels
("Restaurant", "Café", "Bakery") instead of specific cuisine types
("Thai", "Italian", "Yakiniku", etc.). This caused cuisine filters to fail
because the filters match against `cuisineTags`, which only contained generic
values for most restaurants.

The fix completely removes generic labels from both `cuisineTags` and the
display `category` field, so only meaningful cuisine types survive.

## Root Cause

Apple MapKit's `MKPointOfInterestCategory` only provides broad categories
(`.restaurant`, `.cafe`, `.bakery`). The `displayName(for:)` helper converted
these to strings like "Restaurant", which leaked into `cuisineTags` and
`category` through multiple code paths:

1. **`performPOISearch`** hardcoded `"Restaurant"` as the label for every result.
2. **`deduplicate`** added generic labels to `cuisineTags` and used them as `category`.
3. **Sorting** only deprioritised `"Restaurant"`, not other generic labels.
4. **The file was duplicated** (the entire actor defined twice from a prior edit).
5. **`genericCategories`** included "Café" and "Bakery" which are actually valid
   cuisine types users want to filter on.

## Changes Made

### RestaurantSearchService.swift (complete rewrite)

1. **Removed duplicate actor definition** — deleted the second copy (lines 427–851).

2. **Narrowed `genericCategories`** — removed "Café" and "Bakery" (valid cuisine types),
   keeping only truly generic labels: `"Restaurant"`, `"Food Market"`, `"Brewery"`,
   `"Winery"`, `"Nightlife"`. Changed from `private` to `static` (internal visibility)
   so the ViewModel can reference it.

3. **Rewrote `deduplicate()` to strip generics** — generic labels are never added to
   `cuisineTags` and never used as the display `category`. Restaurants found only
   by the generic "restaurant" query get `cuisineTags: {}` (empty) and `category: nil`.

4. **Fixed `performPOISearch`** — added `poiCategoryLabel(for:)` to derive the label
   from the actual POI category (`.cafe` → "Café", `.bakery` → "Bakery",
   others → "Restaurant"). Cafés and bakeries now get proper non-generic tags.

5. **Fixed sorting** — uses `genericCategories.contains()` instead of `== "Restaurant"`.

### RestaurantViewModel.swift

1. **Removed inline `genericCategories`** in `fetchCuisineSpecific` — now references
   `RestaurantSearchService.genericCategories` for consistency.

2. **Updated `allCuisines`** — filters out all `genericCategories` instead of just
   `"Restaurant"`.

## Design Decisions

### Decision 1: Remove "Café" and "Bakery" from genericCategories
- **Context**: Users want to filter by café/bakery as cuisine types.
- **Decision**: Only truly meaningless labels ("Restaurant", etc.) are generic.
  "Café" and "Bakery" are valid cuisine types from `cuisineQueries`.

### Decision 2: Restaurants with no cuisine info get empty tags
- **Context**: Restaurants found only by the generic "restaurant" query have no
  specific cuisine information from MapKit.
- **Decision**: These get `cuisineTags: {}` and `category: nil`. They appear in the
  unfiltered list but are excluded when a cuisine include filter is active.
  This is accurate — we genuinely don't know their cuisine type.

### Decision 3: Single source of truth for genericCategories
- **Context**: The set was duplicated inline in the ViewModel.
- **Decision**: Made `genericCategories` `static` (internal) on the search service.
  Both the service and ViewModel reference the same definition.

## Testing

- All 63 existing unit tests pass (12 RatingStore + 3 Restaurant + 48 ViewModel).
- Build succeeds, SwiftFormat and SwiftLint applied.

---

# Implementation Log: Expand Cuisine Queries

**Date**: 2026-04-12
**Author**: GitHub Copilot

## Overview

The `cuisineQueries` list only had ~57 entries, missing many common worldwide
cuisine types. Restaurants found by MapKit for these missing cuisines would
only get generic labels. This update adds ~50 new cuisine types and moves
non-cuisine labels ("Family Restaurant", "Food Court") to `genericCategories`.

## Changes Made

### RestaurantSearchService.swift

1. **Expanded `cuisineQueries` from ~57 to ~110 entries**, organized by region:
   - **East & Southeast Asian**: Filipino, Indonesian, Malaysian, Singaporean,
     Taiwanese, Pho, Boba Tea
   - **South & Central Asian**: Nepali, Pakistani, Tibetan, Afghan
   - **Middle Eastern & African**: Shawarma, Falafel, Kebab, Moroccan
   - **European**: German, British, Irish, Portuguese, Scandinavian, Polish,
     Hungarian, Austrian, Swiss, Belgian, Dutch, Georgian, Russian
   - **Americas**: Tex-Mex, Cajun, Creole, Soul Food, Hawaiian, Poke
   - **Casual & Quick Service**: Deli, Sandwich, Diner, Fried Chicken, Wings,
     Hot Dog
   - **Café, Bakery & Dessert**: Ice Cream, Dessert, Donuts, Juice Bar

2. **Added "Family Restaurant" and "Food Court" to `genericCategories`** —
   these are venue types, not cuisine types. They are now stripped from
   `cuisineTags` and `category` during deduplication, same as "Restaurant".

### Restaurant.swift

- Updated `cuisineTags` doc comment to clarify that generic labels are stripped.

### RestaurantViewModelTests.swift

- Extended `testAvailableCuisinesIsStaticAndSorted` to assert:
  - New cuisine labels are present (Filipino, Malaysian, German, Cajun, Poke,
    Kebab, Deli, Ice Cream)
  - All generic labels are excluded (Restaurant, Family Restaurant, Food Court)

## Design Decisions

### Decision: Keep "Family Restaurant" and "Food Court" as queries but mark generic
- **Context**: MapKit may return results for these queries, but the labels are
  venue types, not cuisine types.
- **Decision**: The queries remain in `cuisineQueries` (to discover restaurants
  in those venues), but their labels are in `genericCategories` so they are
  stripped during deduplication. A family restaurant found by both "family
  restaurant" and "italian restaurant" queries gets `category: "Italian"`.

## Testing

- Build succeeds.
- All 63 unit tests + 3 UI tests pass.
- SwiftFormat and SwiftLint applied to all changed files.

---

# Implementation Log: Map Tab for Custom Search Location

**Date**: 2026-04-14
**Author**: GitHub Copilot

## Overview

Added a **Map tab** that lets users long-press anywhere on a map to drop a pin
and search for restaurants at that location instead of the device GPS position.
The restaurant list automatically re-fetches when the pin is placed or cleared.

## Changes

### `LocationManager.swift` — Override location support
- Added `@Published var overrideLocation: CLLocation?` for the map pin location.
- Added computed `effectiveLocation` that returns `overrideLocation ?? currentLocation`.
- Added `setOverrideLocation(_:)` and `clearOverrideLocation()` methods.

### `RestaurantPickerApp.swift` — Hoisted LocationManager to app level
- `LocationManager` is now created as a `@StateObject` in the app entry point.
- Passed to `RestaurantViewModel` via init and injected as `.environmentObject`
  so both the restaurant tab and the map tab share the same instance.

### `RestaurantViewModel.swift` — Use effective location + auto-refresh
- `fetchNearbyRestaurants()` now uses `overrideLocation` when set, skipping
  GPS authorization/fix. Falls back to GPS when no override is active.
- `fetchCuisineSpecific()` uses `effectiveLocation` instead of `currentLocation`.
- Added Combine subscription (`observeOverrideLocation()`) that watches
  `$overrideLocation` and triggers a re-fetch when it changes.
- Deduplicates rapid changes (locations within 1m are treated as identical).

### `MapLocationView.swift` — New view
- Full-screen `Map` (iOS 18 SwiftUI Map API) centered on the effective location.
- **Long-press gesture** (via `LongPressGesture` sequenced with `DragGesture`)
  drops a red pin annotation and calls `setOverrideLocation`.
- Shows the user's real GPS position as a blue "My Location" marker when
  an override is active.
- Displays the pinned coordinate in a floating badge.
- **"Reset to My Location"** button clears the override and re-centres the map.
- Instruction hint ("Long-press to set a search location") when no pin is placed.

### `ContentView.swift` — TabView with two tabs
- Wrapped existing content in a `TabView` with:
  - **Restaurants** tab (fork.knife icon) — the original list/filter/decide UI.
  - **Map** tab (map icon) — the new `MapLocationView`.
- Added an **override location banner** at the top of the restaurant tab when
  a custom location is active, with a "Reset" button.
- Both tabs share `LocationManager` via `@EnvironmentObject`.

### `project.pbxproj`
- Added `MapLocationView.swift` file reference, group entry, and build phase.

### `master-prompt.md`
- Added `MapLocationView.swift` to the project structure.
- Added map tab feature to the Key Features list.

## How It Works

1. User taps the **Map** tab and sees a map centered on their GPS location.
2. User **long-presses** anywhere on the map to drop a red pin.
3. `LocationManager.overrideLocation` is set → the Combine subscription in
   `RestaurantViewModel` fires → `fetchNearbyRestaurants()` runs using the
   pinned location.
4. User switches to the **Restaurants** tab and sees results for the new area.
   A red banner confirms "Searching custom location" with a Reset button.
5. User taps **Reset** (on either tab) → `overrideLocation` is cleared →
   restaurants re-fetch using GPS.

## Testing

- Build succeeds.
- All 63 unit tests + 3 UI tests pass.
- SwiftFormat and SwiftLint applied to all changed files.
