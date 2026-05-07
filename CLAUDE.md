# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Project Setup
The `.xcodeproj` is generated from `project.yml` using XcodeGen:
```bash
xcodegen generate
```

### Build & Run
Open in Xcode and press **⌘R**. Requires a simulator or device with location services (set via Simulator → Features → Location).

### Tests
Run all tests from the command line:
```bash
xcodebuild test \
  -scheme RestaurantPicker \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' \
  CODE_SIGNING_ALLOWED=NO
```

### Formatting & Linting
CI enforces both — run before committing:
```bash
swiftformat .          # auto-format
swiftlint lint --strict
```

SwiftFormat settings: 4-space indent, 120-char max width, `--wraparguments before-first`, `--self remove`.  
SwiftLint: `force_unwrapping` is opt-in (enabled), `trailing_comma`/`trailing_whitespace`/`todo` are disabled, line length 120.

## Architecture

MVVM with protocol-based dependency injection throughout for testability.

### Data Flow

```
ContentView
  └── RestaurantViewModel (@MainActor, ObservableObject)
        ├── LocationManager / LocationManaging (protocol)
        ├── RatingStore
        └── SearchOrchestrator (actor)
              └── RestaurantSearchService (actor) / RestaurantSearching (protocol)
```

1. `RestaurantViewModel` resolves the effective location (map pin override or GPS), checks an in-memory location cache (50 m threshold, 2-week TTL), and if missed enqueues the location in `SearchOrchestrator`.
2. `SearchOrchestrator` runs a continuous actor-based loop executing work in three ordered phases:
   - **Phase 1 — Focused batches + POI search**: cuisine-query batches run against the focused region (user's filter radius). Saturated queries (≈25 MapKit results) spawn scatter nodes.
   - **Phase 2 — Scatter nodes**: depth-first cardinal + diagonal sub-region searches for each saturated cuisine query.
   - **Phase 3 — Wide-pass batches**: after all narrow-pass work finishes across all jobs, repeats cuisine batches over the full 10 km network radius.
3. After each batch `SearchOrchestrator` yields an `OrchestratorUpdate` on an `AsyncStream`. Updates for the current job update the live UI; updates for other jobs are silently merged into the location cache.
4. `RestaurantViewModel.handleOrchestratorUpdate` is `internal` (not `private`) so tests can inject synthetic updates without running a real orchestrator.

### Key design decisions

- **No cancellation**: `SearchOrchestrator` never cancels in-flight `MKLocalSearch` requests. A new `enqueueLocation` call pivots after the current batch finishes (~200 ms), avoiding MapKit rate-limit issues.
- **Location cache**: results are keyed by location (50 m threshold). Changing the distance filter or returning to a visited location hits the cache immediately; the refresh button clears it.
- **Search text vs. pick eligibility**: `searchText` filters `filteredRestaurants` (display only). `pickEligibleRestaurants` is never gated by search text so "Pick a Restaurant!" always draws from the full filtered pool.
- **Rating-weighted selection**: when no minimum-rating filter is active, random selection is weighted quadratically by user rating (1★=0.25 … 5★=4.0, unrated=1.0).
- **`searchDebounceInterval`**: `RestaurantViewModel` accepts `.zero` in its initializer to make `searchText` filtering synchronous — used in all unit tests to avoid awaiting run-loop ticks.

### Testing

Mocks live in `RestaurantPickerTests/`:
- `MockLocationManager` — conforms to `LocationManaging`
- `MockRestaurantSearchService` — conforms to `RestaurantSearching`

Tests that exercise `RestaurantViewModel` construct it with `searchDebounceInterval: .zero` and feed `OrchestratorUpdate` values directly to `handleOrchestratorUpdate` rather than starting a real orchestrator.

`SearchOrchestratorTests` calls `pickNextWork()` and the `setJob*` DEBUG helpers directly on the actor to verify scheduling logic in isolation.
