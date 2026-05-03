# Implementation Log: Priority-Queue Search Orchestrator (Steps 1–6)

**Date**: 2026-05-03
**Author**: GitHub Copilot

## Overview

Replaced the cancel-and-restart search model with a single long-running
`SearchOrchestrator` actor that owns a priority-sorted queue of `SearchJob`
values. Each job captures full resumable state for one location. The
orchestrator picks the next atomic unit of work (one `withTaskGroup` batch,
≈ 200 ms), executes it, updates job state, then picks again — so in-flight
`MKLocalSearch` requests always complete before switching locations.

## Steps Implemented

### Step 1 — Batch primitives on RestaurantSearchService

Added four internal batch-execution methods to `RestaurantSearchService`:

- **`executeFocusedBatch`** — runs a slice of cuisine queries against the
  focused region; returns `FocusedBatchResult` (results + saturated queries).
- **`executePOISearch`** — runs a single `MKLocalPointsOfInterestRequest`
  over the wide region.
- **`executeScatterNode`** — runs one level of N/S/E/W + diagonal scatter
  for a saturated node; returns `ScatterNodeResult` (results + child nodes).
- **`executeWideBatch`** — runs a slice of cuisine queries against the wide
  region; no saturation tracking.

Also promoted `SearchNode` → `ScatterNode` as an `internal` struct, and
added `FocusedBatchResult` and `ScatterNodeResult` result types.

### Step 2 — SearchOrchestrator.swift with three core types

**`ScatterNode`** (internal struct, lives on `RestaurantSearchService`) —
mirrors the old private `SearchNode`: `query`, `label`, `centre`, `radius`,
`depth`.

**`SearchJob`** (internal struct) — captures all state for one search location:
- Identity: `id`, `location`, `focusRadius`, `networkRadius`
- Phase 1: `nextFocusedBatchIndex`, `poiSearchDone`
- Phase 2: `pendingScatterNodes: [ScatterNode]`
- Phase 3: `widePassBatchIndex: Int?` (nil = not started)
- Accumulator: `accumulated: [(Restaurant, String)]`
- Derived: `focusedRegion`, `wideRegion`, `isNarrowPassComplete`

**`SearchOrchestrator`** (actor) — drives the run loop:
- `jobs: [SearchJob]` — all active jobs (no enforced array order; priority is
  computed dynamically)
- `currentJobID: UUID?` — ID of the user's current location job
- `updates: AsyncStream<OrchestratorUpdate>` — stream of snapshots yielded
  after each completed batch; `nonisolated` so it can be iterated from any
  actor context
- `start()` — kicks off the internal run loop in a detached Task
- `enqueueLocation(_:focusRadius:) -> UUID` — public entry point for
  location changes

### Step 3 — pickNextWork() scheduling

`pickNextWork()` is a pure synchronous method implementing four priority rules
in order. It calls `removeCompletedJobs()` first, then `jobsSortedByPriority()`
to get a distance-ordered view of all jobs:

| Rule | Condition | Work returned |
|------|-----------|---------------|
| 1 | Job with `!poiSearchDone` | `.poiSearch(jobID:)` |
| 1 (cont.) | Job with pending focused batches | `.focusedBatch(jobID:batchIndex:)` |
| 2 | Job with non-empty `pendingScatterNodes` | `.scatterNode(jobID:)` |
| 3a | All narrow work done; job with started wide-pass | `.wideBatch(jobID:batchIndex:)` |
| 3b | All narrow work done; current job eligible for wide-pass | starts wide-pass, returns `.wideBatch` |

`jobsSortedByPriority()` always places `currentJobID`'s job first; other
jobs are sorted by ascending distance to the current location.

`removeCompletedJobs()` evicts jobs when:
- Narrow pass complete AND `focusRadius >= networkRadius` (no wide-pass needed), OR
- Narrow pass complete AND wide-pass finished, OR
- Narrow pass complete AND NOT current AND wide-pass never started (it never will)

### Step 4 — enqueueLocation(_:focusRadius:)

`enqueueLocation` implements the following contract:

1. **Promote within 50 m** — if an existing job's location is within
   `sameLocationThreshold` (50 m) of `location`, that job is promoted to
   `currentJobID` (preserving all accumulated state and any in-progress
   wide-pass). `signalWorkAvailable()` is called and the existing job's UUID
   is returned.

2. **Fresh job for a new location** — otherwise a new `SearchJob` is created
   with `widePassBatchIndex = nil`, appended to `jobs`, set as `currentJobID`,
   and the run loop is signalled.

3. **Wide-pass eligibility rule on demotion** — the outgoing current job's
   `widePassBatchIndex` is left untouched:
   - `nil` → stays `nil`; Rule 3b will never start it (only applies to
     `currentJobID`).
   - non-`nil` → survives; Rule 3a resumes it after all narrow work across
     all jobs is exhausted.

4. **Demoted jobs re-sorted** — `jobsSortedByPriority()` re-evaluates order
   at every `pickNextWork()` call using distance to the new `currentJobID`,
   so no explicit sort is needed on enqueue.

## Design Decisions

### Decision 1: Dynamic priority sort instead of sorted insertion

- **Context**: Inserting a new job "at the front" is conceptually simpler but
  requires explicit re-sorting or index maintenance when `currentJobID` changes.
- **Decision**: `jobsSortedByPriority()` computes order on-demand. The extra
  O(n log n) sort runs at most once per batch (≈ 200 ms cadence) and `n` is
  always very small (≤ 5 jobs in practice).

### Decision 2: Wide-pass not started for demoted jobs

- **Context**: Starting a wide-pass for every demoted job would quadruple
  MapKit usage on frequent location changes.
- **Decision**: Rule 3b only starts a wide-pass for `currentJobID`. A demoted
  job with `widePassBatchIndex == nil` is eventually evicted by
  `removeCompletedJobs()` — it never gets a wide-pass.

### Decision 3: nonisolated updates stream

- **Context**: `AsyncStream` iteration requires no actor isolation but the
  `ViewModel` runs on `@MainActor`.
- **Decision**: `updates` is declared `nonisolated let` so it can be passed
  to and iterated from any actor context without an extra hop.

## Testing

All 69 existing tests pass. Build succeeded. SwiftFormat clean.

---

# Implementation Log: Priority-Queue Search Orchestrator (Step 5 — ViewModel Refactor)

**Date**: 2026-05-03
**Author**: GitHub Copilot

## Overview

Completed the ViewModel refactor to drive all search work through
`SearchOrchestrator`. Removed the old cancel-and-restart model, the explicit
`backgroundPrefetchTask` / `prefetchQueue`, and `PrefetchJob`. Background
prefetch for other filter radii is now enqueued as low-priority
`SearchJob`s via the orchestrator — the same mechanism used for user-driven
searches, with no special-case scheduler in the ViewModel.

## Changes

### SearchOrchestrator.swift

1. **`isBackgroundPrefetch: Bool` on `SearchJob`** — distinguishes user-driven
   jobs from background prefetch jobs. `enqueueLocation` skips background jobs
   during the 50 m promotion check so they are never accidentally elevated to
   the current UI job.

2. **`enqueueBackgroundPrefetch(location:focusRadius:)`** — creates a new
   `SearchJob` with `isBackgroundPrefetch = true` without updating
   `currentJobID`. The job is queued and processed after all narrow-pass work
   for higher-priority jobs is exhausted. Its updates are routed to the cache
   rather than the live UI by `handleOrchestratorUpdate` (jobID ≠ currentSearchJobID
   branch).

### RestaurantViewModel.swift

3. **Single `orchestratorTask`** — started once in `init` via
   `startOrchestratorLoop()`. Runs forever, consuming `orchestrator.updates`.
   No `searchTask`, `backgroundPrefetchTask`, or `prefetchQueue`.

4. **`fetchNearbyRestaurants`** — resolves the location (override or GPS),
   checks the cache, and calls `orchestrator.enqueueLocation(_:focusRadius:)`.
   No `Task.cancel()` calls — the orchestrator finishes the current batch
   (≈ 200 ms) before pivoting to the new location.

5. **`handleOrchestratorUpdate`** — routes updates by `jobID`:
   - `jobID == currentSearchJobID` → updates `restaurants`, calls `applyFilter()`,
     manages `isLoading`/`isLoadingMore`, writes cache on `isJobComplete`.
   - Else → calls `mergeNewRestaurants` which updates cache and, if the location
     matches the effective location, also updates the live `restaurants` list.

6. **`scheduleBackgroundPrefetch(for:)`** — called when the primary job
   completes. Enqueues background jobs (smallest-first) for standard focus
   radii (500 m, 1 km, 2 km, 5 km) larger than the current `filterRadius`
   that are not yet in the cache. Each background job runs Phase 1 (focused
   batches) + Phase 2 (scatter) for its focus radius, providing better scatter
   coverage for the radii the user is likely to switch to next. Phase 3
   (wide-pass at 10 km) is NOT repeated — it was already completed by the
   primary job.

7. **`hasCoverageForFocusRadius(_:at:)`** — checks the cache to prevent
   redundant background jobs for radii already fully cached.

8. **Removed**: `startBackgroundPrefetch`, `processPrefetchQueue`,
   `runProgressiveSearch`, `PrefetchJob`, `backgroundPrefetchTask`,
   `prefetchQueue`.

## Background Prefetch Lifecycle

```
Primary job (500 m focus) completes
  └─ scheduleBackgroundPrefetch enqueues: 1 km, 2 km, 5 km jobs
       (all isBackgroundPrefetch = true, never currentJobID)

Orchestrator runs background jobs after all narrow work:
  1 km focused+scatter → mergeNewRestaurants → cache updated, UI merged
  2 km focused+scatter → mergeNewRestaurants → cache updated, UI merged
  5 km focused+scatter → mergeNewRestaurants → cache updated, UI merged

User changes filterRadius to 2 km → applyFilter() shows already-merged results
```

## Design Decisions

### Decision 1: isBackgroundPrefetch flag vs separate queue

- **Context**: `enqueueLocation` promotes any job within 50 m to `currentJobID`.
  A background prefetch job at the same coordinates would be incorrectly
  promoted to the current UI job.
- **Decision**: Added `isBackgroundPrefetch: Bool` to `SearchJob`. `enqueueLocation`
  skips jobs with this flag. The flag is minimal — it's the only special-casing
  needed in the orchestrator.
- **Consequences**: Background jobs never become the current job, even if the
  user's location exactly matches a background prefetch location.

### Decision 2: No wide-pass for background prefetch jobs

- **Context**: The primary job already runs a wide-pass at 10 km covering all
  restaurants within the network radius.
- **Decision**: Background prefetch jobs are evicted by `removeCompletedJobs`
  after their narrow pass since `widePassBatchIndex == nil` and `id != currentJobID`.
  Re-running the wide-pass for each background radius would triple MapKit usage
  with no benefit.

### Decision 3: Smallest-first scheduling

- **Context**: If the user widens the filter, they're most likely to go to
  the next larger radius (500 m → 1 km → 2 km).
- **Decision**: Background radii are enqueued smallest-first so the most likely
  next radius is cached soonest.

## Testing

All 69 tests pass. Build succeeded. SwiftFormat clean.

---

 # Implementation Log: Background Prefetch All Radii with Priority Queue & TTL

**Date**: 2026-04-16
**Author**: GitHub Copilot

## Overview

After the primary search (500m focused + scatter + 10km wide) completes,
background prefetch runs the full 3-phase search for each remaining radius
(1km, 2km, 5km, 10km) smallest-first. On location change, the new location's
prefetch takes priority but old-location jobs continue at lower priority.
Cache entries carry a 2-week TTL; expired entries are fully cleared.

## Changes

### RestaurantViewModel.swift

1. **`lastPrefetchDate: Date` on `SearchCacheEntry`** — set to `Date()` in
   `updateCache`. `findCacheEntry` removes entries older than 2 weeks before
   returning, triggering a fresh search on next access.

2. **`cacheTTL = 14 * 24 * 3600`** (2 weeks) — entries older than this are
   fully cleared (all restaurants purged) to ensure closed restaurants don't
   persist and new restaurants are discovered.

3. **`PrefetchJob` struct** — `(location, focusRadius, priority)`. Priority 0
   = current/new location, priority 1 = previous location. Queue sorted by
   priority ascending, then focusRadius ascending (smallest first).

4. **`startBackgroundPrefetch(for:)`** — demotes existing jobs for other
   locations to priority 1, builds new priority-0 jobs for radii not yet
   cached, sorts the queue, cancels and restarts `backgroundPrefetchTask`.

5. **`processPrefetchQueue()`** — processes jobs sequentially: runs
   `searchRestaurants(near:radius:focusRadius:)` for each, consumes the
   stream silently, merges results via `mergeNewRestaurants`, 200ms delay
   between jobs. Checks `Task.isCancelled` between jobs.

6. **`hasValidCacheEntry(for:focusRadius:)`** — checks if a non-expired
   cache entry already covers a given focus radius. Used to skip redundant
   prefetch jobs.

7. **`mergeNewRestaurants` location check** — if the merge location doesn't
   match the current effective location (background prefetch for a previous
   location), only the cache is updated — the UI `restaurants` list is not
   touched.

8. **`refresh()`** — now cancels `backgroundPrefetchTask`, clears
   `prefetchQueue`, and removes all cache entries for the current location
   before re-fetching.

9. **`runProgressiveSearch`** — calls `startBackgroundPrefetch(for:)` after
   the primary search completes and `isLoadingMore` is set to false.

## Prefetch Order

For default 500m filter radius: 1km → 2km → 5km → 10km (smallest first).
Each prefetch runs all 3 phases (focused + scatter + wide). Deduplication
handles overlap with previously discovered restaurants.

## Location Change Behaviour

1. User changes location via map pin
2. `fetchNearbyRestaurants` cancels the primary `searchTask`
3. New primary search runs at 500m for the new location
4. After completing, `startBackgroundPrefetch` demotes old-location jobs
   to priority 1, adds new-location jobs at priority 0
5. New location's radii process first (1km, 2km, 5km, 10km)
6. Old location's remaining radii continue after

## Testing

All tests pass. Build succeeded. SwiftFormat + SwiftLint clean.

---

# Implementation Log: Focused-Region Search + 3-Phase Architecture

**Date**: 2026-04-14
**Author**: GitHub Copilot

## Overview

Restaurant discovery was limited because the initial MKLocalSearch queries
used a 10km region while scatter only probed ~1km. MKLocalSearch returns
the 25 "most relevant" results biased towards the region centre, so the
scatter's 1km sub-regions returned mostly the same restaurants as the
original 10km query. Fixed by using the user's filter radius as the search
region for BOTH initial queries and scatter.

## Root Cause

- Initial queries: region = 10km × 10km. MapKit returns 25 results from this
  huge area, biased to the centre.
- Scatter: fires from 500m offsets (for 1km filter) with 500m × 500m sub-regions.
  These tiny regions are subsets of the original 10km region, so MapKit often
  returns the same top-25 restaurants — scatter barely found new ones.
- Additionally, scatter running inline between batches (prior fix moved it after)
  was exhausting rate limits, causing batches 2–10 to return nothing.

## Changes

### RestaurantSearchService.swift

1. **Renamed `scatterRadius` → `focusRadius`** to reflect that it now controls
   both the initial query region AND the scatter radius.

2. **3-phase search architecture**:
   - **Phase 1 (Focused)**: All 150+ queries use `focusedRegion` (filter-radius-
     sized). In a 1km filter, the search region is 2km × 2km. MapKit's 25-result
     cap now applies to this small area, making saturation detection accurate.
   - **Phase 2 (Scatter)**: Saturated queries from Phase 1 trigger adaptive
     scatter within the same focus radius. Since both the initial query and
     scatter use the same region scale, scatter genuinely discovers new
     restaurants in adjacent sub-regions.
   - **Phase 3 (Wide)**: All queries re-run with the full 10km region to
     pre-cache distant restaurants for when the user widens the filter.
     Only runs if `focusRadius < radius`.

3. **POI search uses wide region** — the category-based POI search always
   uses the full 10km region since it's a single query and doesn't suffer
   from the 25-result bias as much.

### RestaurantViewModel.swift

4. **`focusRadius` parameter** — passes `filterRadius ?? 500` as `focusRadius`.

## Testing

All 66 tests pass. Build succeeded. SwiftFormat + SwiftLint clean.

---

# Implementation Log: Search Caching, Cancellation & Scatter Radius Fix

**Date**: 2026-04-14
**Author**: GitHub Copilot

## Overview

Three problems fixed: (1) changing the distance filter or location during
a search caused redundant network requests, (2) old searches weren't cancelled
and competed for MapKit rate limits, (3) scatter operated at 10km scale instead
of the user's filter radius.

## Changes

### RestaurantSearchService.swift

1. **`scatterRadius` parameter on `searchRestaurants`** — new optional param
   (defaults to `radius`). The ViewModel passes the user's filter radius (e.g.
   500m) so the depth-0 scatter node uses 500m, giving depth progression:
   500m → 250m → 125m → 62.5m. The `maxRadius` distance filter on individual
   results stays at 10km so all results are cached regardless of current filter.

2. **`onTermination` handler on `AsyncThrowingStream`** — the inner `Task`
   is stored in a variable and cancelled via `continuation.onTermination` when
   the stream consumer stops listening. This stops MapKit queries immediately
   when a new search starts.

3. **`Task.isCancelled` check** in the batch loop — exits early between
   batches to avoid wasted work.

### RestaurantViewModel.swift

4. **`searchTask: Task<Void, Never>?`** — stores the current search task.
   `fetchNearbyRestaurants` cancels it before starting a new search.

5. **`SearchCacheEntry` + cache system** — results are cached by location
   (50m threshold). On cache hit: restaurants load instantly from cache,
   `applyFilter()` runs, no network calls. Cache entries store
   `(location, searchRadius, restaurants)`.

6. **`findCacheEntry(for:radius:)`** — matches if `searchRadius >= radius`
   AND `distance < 50m`. Returns cached restaurants.

7. **`updateCache(for:radius:restaurants:)`** — merges new results into
   existing entries or creates new ones. Keeps the larger search radius.

8. **`mergeNewRestaurants(_:for:)`** — shared helper for dedup-merging
   new restaurants into the master list + cache. Used by both
   `runProgressiveSearch` and `fetchCuisineSpecific`.

9. **`refresh()`** — clears cache entries within 50m of current location
   before re-fetching, forcing a fresh network search.

10. **`runProgressiveSearch`** — extracted from `fetchNearbyRestaurants`.
    Passes `filterRadius ?? 500` as the scatter radius. Stores results
    in cache on completion (only if not cancelled).

11. **`networkSearchRadius = 10_000`** — named constant replacing the
    hardcoded 10000. Used consistently across all search calls.

## Scatter Radius Depth Progression

| Filter Radius | Depth 0 | Depth 1 | Depth 2 | Depth 3 |
|---|---|---|---|---|
| 500m | 500m | 250m | 125m | 62.5m |
| 1km | 1km | 500m | 250m | 125m |
| 2km | 2km | 1km | 500m | 250m |
| 5km | 5km | 2.5km | 1.25km | 625m |

## Testing

All 66 tests pass. Build succeeded. SwiftFormat + SwiftLint clean.

---

# Implementation Log: Adaptive Recursive Scatter Search

**Date**: 2026-04-14
**Author**: GitHub Copilot

## Overview

Queries that return exactly 25 results (MapKit's per-query cap) are now
automatically re-run from offset centre points. The scatter is recursive:
saturated offset points subdivide further, and diagonals are filled between
adjacent saturated cardinals. This self-calibrating approach discovers 2–3×
more restaurants in dense urban areas while adding zero extra queries in
sparse locations.

## Changes

### RestaurantSearchService.swift

1. **`mkLocalSearchResultCap = 25` named constant** — Apple's undocumented
   per-query result limit. Makes saturation detection self-documenting and
   trivial to update if Apple changes the cap.

2. **`maxScatterDepth = 3`** — bounds worst-case recursion. At depth 3,
   radii progress R → R/2 → R/4 → R/8. Max ~29 extra queries per label.

3. **`SearchResult` typealias** — `performSearch` now returns
   `(results: [(Restaurant, String)], rawCount: Int)` where `rawCount` is
   `response.mapItems.count` captured *before* the `distance <= radius`
   filter. This is the saturation signal.

4. **`SearchNode` struct** — `(centre, radius, depth)` representing one
   scatter point in the recursive tree.

5. **Cardinal/Diagonal enums + offset helpers** — compute child centres
   at N/S/E/W (cardinal) or NE/NW/SE/SW (diagonal) offsets using
   approximate metric-to-degree conversion.

6. **`scatterIfSaturated` recursive method** — given a saturated query +
   parent SearchNode:
   - Fires N/S/E/W at `radius × 0.5` offset with `radius × 0.5` region
   - Identifies saturated cardinals
   - **Diagonal fill rule**: for each pair of adjacent saturated cardinals
     (e.g. N+E → NE), adds a diagonal point at the *same* radius as the
     parent, checks it for saturation
   - Recurses on all saturated points with `depth + 1`, up to `maxScatterDepth`

7. **Wired into `searchRestaurants` stream** — after each batch completes,
   saturated queries (`rawCount >= cap`) trigger `scatterIfSaturated`
   concurrently. Scatter results merge into the accumulator and an updated
   snapshot is yielded. The first yield (before any scatter) is unchanged,
   preserving the ~400ms perceived load time.

8. **`deduplicateAndSort` convenience method** — extracts the repeated
   sort-specific-first + deduplicate + sort-by-distance pattern into a
   single reusable method.

### Callers updated

- `performBatchedSearches` — updated to handle `SearchResult` tuple,
  extracting `.results` for the accumulator.

## Design Decisions

### Pre-filter rawCount for saturation detection
`rawCount` is `response.mapItems.count` before the radius guard. A query
near a boundary might return 25 items from MapKit but only 3 pass the
radius filter — the category is sparse, but using the pre-filter count
correctly detects MapKit hit its cap.

### Diagonal fill at parent radius
Diagonal points use the same radius as their parent (not halved). They
fill the gap *between* two known-dense cardinal regions rather than
subdividing a single region, so they need the same coverage area.

### Scatter runs after the initial yield
Each batch yields a snapshot *before* scatter runs. Scatter results
are yielded as a second snapshot for that batch. This keeps perceived
first-result time unchanged at ~400ms.

## Testing

All 66 tests pass. Build succeeded. SwiftFormat + SwiftLint clean.

---

# Implementation Log: Progressive Loading + Priority Batching

**Date**: 2026-04-14
**Author**: GitHub Copilot

## Overview

Restaurant search results now stream progressively — the list populates within
~400ms instead of waiting ~6–7s for all 150+ queries to complete. Queries are
priority-ordered so the first batch returns results anywhere in the world.

## Changes

### RestaurantSearchService.swift

1. **Priority-ordered `cuisineQueries`**: Universally high-yield queries
   (restaurant, café, pizza, sushi, ramen, burger, Chinese, Italian, Thai, etc.)
   are now in the first batch of 15. Niche/regional queries (washoku, kushikatsu,
   fondue, Georgian, etc.) run last.

2. **Tuned batching**: `batchSize` 10→15, `delayNanoseconds` 100ms→50ms.
   Total wall-clock time reduced from ~6–7s to ~4–5s on a good network.

3. **`searchRestaurants` returns `AsyncThrowingStream<[Restaurant], Error>`**:
   Each batch yields a progressively larger deduplicated snapshot. The POI
   category search runs concurrently with batch 1 and its results are merged
   into the first yield. The stream finishes after all batches complete, or
   throws `SearchError.noResults` if the final accumulation is empty.

### RestaurantViewModel.swift

4. **`isLoadingMore` published property**: `true` while subsequent batches
   are still running after the first results have appeared.

5. **`fetchNearbyRestaurants` consumes the stream**: `for try await snapshot in stream`.
   After the first yield, `isLoading` becomes `false` (hides the full-screen
   spinner) and `isLoadingMore` becomes `true`. Each snapshot replaces
   `restaurants` and re-applies filters. Both flags become `false` when the
   stream ends.

### ContentView.swift

6. **"finding more…" indicator**: The restaurant count line shows
   "· finding more…" text next to the count while `isLoadingMore` is `true`.

## Testing

All 66 tests pass. Build succeeded. SwiftFormat + SwiftLint clean.

---

# Implementation Log: Hierarchical Cuisine Filter UI + Expanded Queries

**Date**: 2026-04-14
**Author**: GitHub Copilot

## Overview

The flat chip-grid cuisine filter was replaced with a two-level hierarchical
filter. Users can now browse cuisines grouped by continent and country, making
the filter sheet far less crowded while giving access to ~150 cuisine types.
~40 new cuisine queries were also added to improve restaurant discovery.

## Changes

### RestaurantSearchService.swift — ~40 new cuisine queries

New queries added (grouped by region):

- **Japanese**: Yakitori, Shabu-Shabu
- **Chinese**: Cantonese, Szechuan, Hotpot, Dumpling (moved from Casual)
- **Korean**: Korean BBQ, Korean Fried Chicken
- **Vietnamese**: Pho (already existed), Bánh Mì
- **South Asian**: Biryani, Sri Lankan
- **Middle Eastern**: Persian, Israeli, Egyptian, South African
- **European**: Crêperie, Fish & Chips, Gastropub, Pub, Fondue, Waffles
- **Americas**: Tacos, Colombian, Argentinian, Venezuelan, Cuban, Diner, Donuts, Wings, Hot Dog (moved from Casual)
- **Dietary**: Halal, Kosher, Organic
- **General**: BBQ, Deli, Waffles, Pancakes, Wine Bar

Sections reorganised to reflect actual groupings (e.g. Wings/Hot Dog/Diner/Donuts
now under Americas rather than Casual & Quick Service).

### CuisineHierarchy.swift — new file in Models/

Defines a purely visual two-level grouping for the filter UI.
No impact on search logic, filtering, or data model.

Two structs:
- `CuisineGroup`: `name` + `cuisines: [String]` (leaf labels)
- `CuisineRegion`: `name` + `isContinent: Bool` + `groups: [CuisineGroup]`

One static `CuisineHierarchy.regions: [CuisineRegion]` array defines the full
hierarchy:

**Top-level order**: 🌏 Asia, 🇯🇵 Japanese … (all Asian countries), 🌍 Middle East & Africa, Lebanese … (all ME/Africa countries), 🌍 Europe, 🇮🇹 Italian … (all European countries), 🌎 Americas, 🇺🇸 American … (all Americas countries), 🥗 Dietary, 🍽 General.

**Continent leaves** = all group names + all their sub-cuisines (flat).
**Country leaves** = only that country's regional sub-cuisines.
**Leaf countries** (no sub-cuisines) = simple toggle rows with no expand arrow.

### CuisineFilterView.swift — complete rewrite

Old: flat chip grid for all available cuisines.
New: two-level hierarchical filter with:

- **Segmented Include/Exclude picker** at the top of the cuisine section
- **Expandable rows** (chevron + expand/collapse on tap) for continents and
  countries that have sub-cuisines
- **Leaf toggle rows** for countries with no sub-cuisines (e.g. Thai, Greek)
- **Chip grid** (`FlowLayout`) inside each expanded section
- **Tri-state indicator** on each expandable row: ○ none / ◐ partial / ✓ all
- **"All / None" button** on each expandable row to select/deselect all leaves
- Multiple sections can be open simultaneously; everything stays on one screen

`availableCuisines` parameter removed — the view reads from `CuisineHierarchy`
directly. `FlowLayout` struct unchanged.

### ContentView.swift

Removed `availableCuisines:` parameter from `CuisineFilterView(...)` call.

## Testing

All 66 tests pass (63 unit + 3 UI). Build succeeded. SwiftFormat + SwiftLint applied.

---

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

---

# Implementation Log: Priority-Queue Orchestrator — Step 6 (Tests)

**Date**: 2026-05-03
**Author**: GitHub Copilot

## Overview

Completed step 6 of the Priority-Queue Search Orchestrator plan: added
`SearchOrchestratorTests.swift` with comprehensive scheduling tests, fixed
project file references so all new files compile correctly, and added internal
test-helper methods to `SearchOrchestrator` to allow actor-isolated state
mutation from test code without violating Swift concurrency rules.

## Changes

### SearchOrchestratorTests.swift

New test suite covering:

- **enqueueLocation** — returns a UUID, sets `currentJobID`, promotes existing
  jobs within the 50 m threshold, creates new jobs beyond the threshold, updates
  `currentJobID` on new location.
- **enqueueBackgroundPrefetch** — does not change `currentJobID`, adds a job,
  marks the job `isBackgroundPrefetch = true`.
- **Location-doesn't-promote-background** — enqueuing a user location at the
  same coordinates as an existing background job creates a fresh user-driven
  job rather than promoting the background one.
- **pickNextWork scheduling** — nil when no jobs, POI search first, focused
  batch after POI done, scatter node after all focused batches, wide-pass starts
  for current job after narrow pass complete, wide-pass does NOT start for
  non-current jobs, current job prioritised over older jobs.
- **Wide-pass survival** — a started wide-pass survives location change and
  remains in the jobs array with its batch index intact.
- **Eviction** — a demoted job with no started wide-pass is evicted once its
  narrow pass completes.
- **Distance ordering** — current job is always served first regardless of
  insertion order.

### SearchOrchestrator.swift

Added four internal test-helper methods (tagged "Intended for use in unit
tests only"):

- `setJobPoiSearchDone(_:forJobID:)`
- `setJobNextFocusedBatchIndex(_:forJobID:)`
- `setJobPendingScatterNodes(_:forJobID:)`
- `setJobWidePassBatchIndex(_:forJobID:)`

These allow tests to set up specific job states without starting the run loop
or making real MapKit requests, while respecting Swift actor-isolation rules
(tests call these `async` methods which hop onto the actor to perform the
mutation safely).

Also changed `BatchWork` enum from `private` to `internal` so
`pickNextWork()` (which is `internal` for test access) can return it without
a compiler visibility error.

### project.pbxproj

Added missing `PBXFileReference`, `PBXBuildFile`, group membership, and
`Sources` build-phase entries for `SearchOrchestrator.swift` (main target)
and `SearchOrchestratorTests.swift` (test target).

## Test Results

All 80 unit tests + 3 UI tests pass (`** TEST SUCCEEDED **`).
