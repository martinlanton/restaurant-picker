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
