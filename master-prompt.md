# Master Prompt: Restaurant Picker iOS

## Project Overview

This repository implements an iOS application that helps users randomly select nearby restaurants. The app displays restaurants within a configurable distance radius using Apple MapKit, and allows users to randomly pick one with a single tap.

**Key Features**:
- Display restaurants from Apple Maps within a specified radius
- Multi-cuisine parallel search (36 cuisine-specific queries) for broader coverage
- Filter restaurants by distance (configurable)
- Include or exclude cuisine types via a filter sheet
- Tap any restaurant to view details, call, or get directions in Apple Maps
- Random selection with visual feedback
- User ratings (1–5 stars) stored locally on device via UserDefaults
- Simple, intuitive single-button interface
- Native iOS experience with SwiftUI

### Why Apple MapKit Over Google Maps

- **No API key required** - simpler setup and no billing concerns
- **Better iOS integration** - native performance and seamless UX
- **Privacy focused** - aligns with Apple ecosystem values
- **Free** - no usage limits or billing required
- **Rich restaurant data** - comprehensive POI (Points of Interest) database
- **Built-in** - no external SDK dependencies


## iOS Architecture

### Technology Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Minimum iOS**: iOS 17.0+
- **IDE**: Xcode 16+
- **Architecture**: MVVM (Model-View-ViewModel)
- **Maps**: Apple MapKit (parallel multi-cuisine MKLocalSearch for restaurant discovery)
- **Location**: CoreLocation

### Project Structure

```
RestaurantPicker/
├── RestaurantPicker/
│   ├── App/
│   │   ├── RestaurantPickerApp.swift
│   │   └── ContentView.swift
│   ├── Models/
│   │   └── Restaurant.swift
│   ├── ViewModels/
│   │   └── RestaurantViewModel.swift
│   ├── Views/
│   │   ├── RestaurantListView.swift
│   │   ├── RestaurantRowView.swift
│   │   ├── RestaurantDetailView.swift
│   │   ├── SelectedRestaurantView.swift
│   │   ├── DistanceFilterView.swift
│   │   ├── CuisineFilterView.swift
│   │   ├── StarRatingView.swift
│   │   └── DecideButtonView.swift
│   ├── Services/
│   │   ├── LocationManager.swift
│   │   ├── RestaurantSearchService.swift
│   │   └── RatingStore.swift
│   └── Utilities/
│       └── Extensions.swift
├── RestaurantPickerTests/
│   ├── RestaurantViewModelTests.swift
│   └── RatingStoreTests.swift
└── RestaurantPickerUITests/
    └── RestaurantPickerUITests.swift
```

### MVVM Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         View Layer                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ ContentView │  │ ListView    │  │ DecideButtonView    │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         │         ┌──────┴──────┐              │             │
│         │         │  DetailView │              │             │
│         │         └─────────────┘              │             │
│         │    ┌──────────────────────┐          │             │
│         │    │ SelectedRestaurantView│          │             │
│         │    └──────────────────────┘          │             │
│         └────────────────┬─────────────────────┘             │
│                          │ @StateObject / @ObservedObject    │
├──────────────────────────┼───────────────────────────────────┤
│                   ViewModel Layer                            │
│              ┌───────────┴───────────┐                       │
│              │  RestaurantViewModel  │                       │
│              │  - restaurants: []    │                       │
│              │  - selectedRestaurant │                       │
│              │  - isLoading          │                       │
│              │  - filterRadius       │                       │
│              │  - selectedCuisines   │                       │
│              │  - excludedCuisines   │                       │
│              │  - minimumRating      │                       │
│              └───────────┬───────────┘                       │
│                          │                                   │
├──────────────────────────┼───────────────────────────────────┤
│                    Service Layer                             │
│    ┌─────────────────────┼─────────────────────┐             │
│    │                     │                     │             │
│    ▼                     ▼                     ▼             │
│ ┌──────────────┐  ┌─────────────┐  ┌───────────────────┐    │
│ │LocationManager│  │SearchService│  │   MapKit API      │    │
│ └──────────────┘  └─────────────┘  └───────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```


## Tooling and Infrastructure

- Use Xcode as the primary IDE
- Use Swift Package Manager (SPM) for dependencies
- Use SwiftLint for linting
- Use SwiftFormat for code formatting
- Don't introduce new tools without strong justification

### Formatting: SwiftFormat

This project uses **SwiftFormat** for consistent code formatting.

**Installation**:
```bash
# Install via Homebrew
brew install swiftformat
```

**Commands**:
```bash
# Format all Swift files
swiftformat .

# Check formatting without modifying (CI mode)
swiftformat --lint .

# Format specific file
swiftformat RestaurantPicker/ViewModels/RestaurantViewModel.swift
```

**Configuration** (`.swiftformat`):
```
--indent 4
--maxwidth 120
--wraparguments before-first
--wrapcollections before-first
--self remove
--stripunusedargs closure-only
```

### Linting: SwiftLint

This project uses **SwiftLint** for enforcing Swift style and conventions.

**Installation**:
```bash
# Install via Homebrew
brew install swiftlint
```

**Commands**:
```bash
# Run linter
swiftlint

# Auto-fix correctable issues
swiftlint --fix

# Analyze specific file
swiftlint lint --path RestaurantPicker/ViewModels/
```

**Configuration** (`.swiftlint.yml`):
```yaml
disabled_rules:
  - trailing_whitespace
  - todo

opt_in_rules:
  - empty_count
  - closure_spacing
  - force_unwrapping

line_length: 120

identifier_name:
  min_length: 2
  excluded:
    - id
    - x
    - y

excluded:
  - DerivedData
  - .build
```

### Testing: XCTest

This project uses **XCTest** as the native testing framework.

**Running Tests in Xcode**:
- `Cmd+U` - Run all tests
- `Cmd+Ctrl+U` - Run test under cursor
- Product → Test → Select specific test

**Running Tests via Command Line**:
```bash
# Run all tests
xcodebuild test \
  -scheme RestaurantPicker \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0'

# Run with code coverage
xcodebuild test \
  -scheme RestaurantPicker \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0' \
  -enableCodeCoverage YES
```

### Documentation: DocC

This project uses **DocC** for generating documentation from code comments.

**Building Documentation**:
```bash
# Build documentation in Xcode
Product → Build Documentation (Ctrl+Shift+Cmd+D)

# Command line
xcodebuild docbuild \
  -scheme RestaurantPicker \
  -derivedDataPath ./DerivedData \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Documentation Style**: **MUST use Swift documentation comments** (triple-slash `///` or `/** */`).

## Code Quality Principles

All code contributions MUST adhere to the highest standards of software craftsmanship:

### Core Beliefs

- **Incremental progress over big changes** - Small changes that compile and pass tests
- **Learning from existing code** - Study and plan before implementing
- **Pragmatic over dogmatic** - Adapt to project reality
- **Clear intent over clever code** - Be boring and obvious

**NEVER**:
- Make assumptions - verify with existing code
- Disable tests instead of fixing them
- Force unwrap optionals without justification

**ALWAYS**:
- Fix tests that break or when implementation changes
- Update plan documentation as you go
- Learn from existing implementations
- Stop after 3 failed attempts and reassess
- Handle optionals safely with `guard let` or `if let`

### 1. Clean Code Principles (Robert C. Martin)

#### Naming Conventions (Swift)
- **Types**: UpperCamelCase (`RestaurantViewModel`, `LocationManager`)
- **Functions/Methods**: lowerCamelCase (`fetchRestaurants()`, `selectRandom()`)
- **Variables/Properties**: lowerCamelCase (`selectedRestaurant`, `filterRadius`)
- **Constants**: lowerCamelCase (`maxDistance`, `defaultRadius`)
- **Enum cases**: lowerCamelCase (`case notDetermined`, `case authorized`)
- **Protocols**: UpperCamelCase, often ending in `-able`, `-ible`, or `-ing` (`Identifiable`, `ObservableObject`)

- **Avoid disinformation**: Don't use names that vary in small ways
- **Make meaningful distinctions**: Avoid noise words (e.g., `RestaurantInfo` vs `RestaurantData`)
- **Use pronounceable names**: `generationTimestamp` not `genymdhms`
- **Use searchable names**: Single-letter names only for local variables in short closures

#### Functions
- **Small**: Functions should be small (ideally 5-20 lines)
- **Do one thing**: Functions should do ONE thing, do it well, and do it only
- **One level of abstraction**: Don't mix levels of abstraction in a single function
- **Descriptive names**: Long descriptive names are better than short enigmatic ones
- **Few arguments**: Ideal is zero (niladic), acceptable is one or two, avoid three or more
- **No side effects**: Functions should not modify state unexpectedly
- **Command Query Separation**: Functions should either DO something or ANSWER something, not both
- **Documentation required**: All public types, methods, and functions MUST have documentation comments
- **Extract till you drop**: If a function has sections with comments, extract those sections

#### Comments
- **Prefer self-documenting code over comments**
- **Good comments**: Documentation comments (///), explanation of intent, clarification, warning of consequences, TODO comments, MARK comments for organization
- **Bad comments**: Mumbling, redundant comments, misleading comments, journal comments, noise comments, commented-out code
- **Use MARK comments**: Organize code sections with `// MARK: - Section Name`

#### Formatting
- **Vertical formatting**: Files should be 200-500 lines (ideally)
- **Newspaper metaphor**: Most important concepts first, details increase as you read down
- **Vertical density**: Related code should appear vertically dense (close together)
- **Vertical distance**: Concepts that are closely related should be kept vertically close
- **Horizontal formatting**: Lines should be 80-120 characters (max 120)
- **Indentation**: Use 4 spaces (Swift standard)

#### Error Handling
- **Use Swift's error handling** (`throws`, `do-catch`, `try?`, `try!`)
- **Prefer `Result` type** for async operations where appropriate
- **Provide context with errors**: Create custom error types with descriptive cases
- **Handle optionals safely**: Use `guard let`, `if let`, or nil-coalescing
- **Avoid force unwrapping**: Never use `!` unless absolutely necessary and documented
- **Use `@MainActor`**: For UI-related async operations

#### Simplicity

- **Single responsibility** per function/class/struct
- **Avoid premature abstractions**
- **No clever tricks** - choose the boring solution
- If you need to explain it, it's too complex
- **Prefer value types**: Use `struct` over `class` when possible

### 2. Design Patterns (Gang of Four)

When appropriate, use established design patterns from the "Gang of Four" book.

#### **Pattern Usage Guidelines:**
- **Interfaces over singletons** - Enable testing and flexibility
- **Explicit over implicit** - Clear data flow and dependencies
- Don't force patterns - use them when they solve a real problem
- Document pattern usage in code comments
- Prefer composition over inheritance
- Program to interfaces, not implementations

#### Learn the Codebase
- Find similar features/components
- Identify common patterns and conventions
- Use same libraries/utilities when possible
- Follow existing test patterns


### 3. Test-Driven Development (TDD)

Follow the **Three Laws of TDD** (Uncle Bob):

1. **You may not write production code until you have written a failing unit test**
2. **You may not write more of a unit test than is sufficient to fail**
3. **You may not write more production code than is sufficient to pass the currently failing test**
4. **You may not write more than one failing test at a time**

#### TDD Cycle (Red-Green-Refactor)
1. **Red**: Write a failing test
2. **Green**: Write minimal code to make the test pass
3. **Refactor**: Clean up code while keeping tests green

#### Test Quality (FIRST Principles)
- **F**ast: Tests should run quickly
- **I**ndependent: Tests should not depend on each other
- **R**epeatable: Tests should produce same results in any environment
- **S**elf-validating: Tests should have boolean output (pass/fail)
- **T**imely: Write tests before production code

#### Test Structure (Arrange-Act-Assert)
```swift
func testRestaurantFilteringByDistance() {
    // Arrange: Set up test data
    let restaurants = [
        Restaurant(id: UUID(), name: "Thai Place", coordinate: .init(latitude: 40.7128, longitude: -74.0060), distance: 500),
        Restaurant(id: UUID(), name: "Pizza Shop", coordinate: .init(latitude: 40.7200, longitude: -74.0100), distance: 2000)
    ]
    let viewModel = RestaurantViewModel(restaurants: restaurants)
    
    // Act: Execute the function
    viewModel.filterByDistance(maxDistance: 1000)
    
    // Assert: Verify the result
    XCTAssertEqual(viewModel.filteredRestaurants.count, 1)
    XCTAssertEqual(viewModel.filteredRestaurants.first?.name, "Thai Place")
}
```

#### Test Creation Guidelines
- Write unit tests for all functionalities and features
- Use descriptive test names that explain what is being tested
- Tests should be easy to read and understand
- Tests should be fast and should isolate specific behaviors
- It's okay (and often preferable) to have tests that test several layers in order to test the end features that users will interact with

### 4. Swift-Specific Guidelines

#### Style
- **Imports**: System frameworks first, then third-party, then local (separated by blank lines)
- **Access control**: Use `private`, `fileprivate`, `internal`, `public` appropriately
- **Type inference**: Let Swift infer types when obvious, be explicit when not
- **Trailing closures**: Use trailing closure syntax for the last closure argument
- **Guard statements**: Use `guard` for early exits, `if let` for scoped usage
- **String interpolation**: Use `\(variable)` for string formatting
- **Protocol conformance**: Separate protocol implementations with `// MARK: - ProtocolName` and extensions

#### Swift Best Practices
- **Prefer `let` over `var`** - immutability by default
- **Use `struct` over `class`** - value types when possible
- **Protocol-oriented programming** - favor protocols over inheritance
- **Async/await** - use modern concurrency over completion handlers
- **Combine or async/await** - for reactive data flows
- **@MainActor** - for UI updates from async contexts
- **Leverage SwiftUI** - use declarative UI patterns


## Documentation Requirements

### 1. Code Documentation - Swift Documentation Comments

**CRITICAL**: All public APIs MUST have documentation comments using `///` (single-line) or `/** */` (multi-line).

**Type Documentation Example**:
```swift
/// A restaurant discovered via MapKit search.
///
/// This struct represents a restaurant location with its associated metadata
/// including name, coordinates, and distance from the user's current location.
///
/// ## Usage
/// ```swift
/// let restaurant = Restaurant(
///     id: UUID(),
///     name: "Thai Cafe",
///     coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
///     distance: 500
/// )
/// ```
struct Restaurant: Identifiable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distance: Double
}
```

**Function Documentation Example**:
```swift
/// Fetches restaurants within a specified radius of the user's location.
///
/// This method uses MapKit's `MKLocalSearch` to discover nearby restaurants
/// and filters them based on the provided radius.
///
/// - Parameters:
///   - location: The user's current location.
///   - radius: The search radius in meters. Defaults to 5000 (5km).
/// - Returns: An array of restaurants sorted by distance from nearest to farthest.
/// - Throws: `LocationError.serviceUnavailable` if MapKit search fails.
///
/// ## Example
/// ```swift
/// let restaurants = try await searchService.fetchRestaurants(
///     near: userLocation,
///     radius: 2000
/// )
/// ```
func fetchRestaurants(near location: CLLocation, radius: Double = 5000) async throws -> [Restaurant] {
    // Implementation
}
```

**Swift Documentation Sections** (in order):
1. **Summary** (one line description)
2. **Discussion** (extended description, separated by blank line)
3. **Parameters**: Function/method parameters
4. **Returns**: Return value description
5. **Throws**: Errors that can be thrown
6. **Note**: Additional notes
7. **Warning**: Warnings for users
8. **Example**: Usage examples with code blocks

**Key Rules**:
- First line is a short summary
- Blank line separates summary from discussion
- Use `-` for parameter/returns/throws sections
- Code examples use triple backticks with `swift` language identifier
- Use `##` for subsection headers within documentation

### 2. Implementation Logs

For EVERY significant implementation or modification, create/update the `implementation-logs.md` file.

**Template**:
```markdown
# Implementation Log: [Feature Name]

**Date**: YYYY-MM-DD
**Author**: [Your Name/Agent ID]
**Related Issue**: #XXX
**Related PR**: #XXX

## Overview
Brief description of what was implemented and why.

## Design Decisions

### Decision 1: [Title]
- **Context**: Why this decision was needed
- **Options Considered**:
  1. Option A: pros/cons
  2. Option B: pros/cons
- **Decision**: What was chosen and why
- **Consequences**: Trade-offs accepted
```

### 3. README.md

The README should include:
- Project description and purpose
- Installation instructions
- Basic usage examples
- How to add/modify restaurants
- How to run tests

### 4. Code Comments

- Use comments to explain **why**, not **what**
- Comment complex logic or non-obvious decisions
- Keep comments up-to-date with code changes

## Git Workflow

### Commit Messages

Follow Conventional Commits specification:

```
<type>(<scope>): <short summary>

<detailed description>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code refactoring
- `perf`: Performance improvement
- `test`: Adding or updating tests
- `chore`: Build process, dependencies, tooling

**Example**:
```
feat(filtering): add support for multiple include tags

Allow users to filter restaurants by multiple included cuisine tags.
When multiple tags are provided in the include parameter, restaurants
matching any of the tags will be considered.

This provides more flexibility for users who want to select from
multiple preferred cuisines.

Closes #23
```

### Branch Naming
- `feature/short-description`
- `bugfix/short-description`
- `hotfix/short-description`
- `refactor/short-description`
- `docs/short-description`

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] New feature
- [ ] Bug fix
- [ ] Breaking change
- [ ] Documentation update
- [ ] Implementation log created
- [ ] Mermaid diagrams updated

## Checklist
- [ ] Code follows clean code principles
- [ ] Self-reviewed code
- [ ] Commented hard-to-understand areas
- [ ] Updated documentation
- [ ] Added/updated tests
- [ ] All tests pass locally
- [ ] No linting errors (SwiftLint)
- [ ] Code formatted (SwiftFormat)
- [ ] Documentation comments added for public APIs

## Performance Impact
Describe performance changes (if applicable)

## Testing
Describe testing performed

## Related Issues
Fixes #XXX
```

## Code Review Checklist

Before approving any code, verify:

### Clean Code
- [ ] Names are intention-revealing and follow Swift conventions
- [ ] Functions are small (5-20 lines) and do one thing
- [ ] No more than 3 function arguments
- [ ] No side effects
- [ ] Appropriate abstraction levels
- [ ] No redundant comments
- [ ] Error handling uses Swift's `throws`/`do-catch` or `Result`
- [ ] No magic numbers (use named constants)
- [ ] Optionals handled safely (no force unwrapping without justification)

### Design Patterns
- [ ] Appropriate patterns used (not forced)
- [ ] Composition favored over inheritance
- [ ] SOLID principles followed
- [ ] DRY (Don't Repeat Yourself)
- [ ] YAGNI (You Aren't Gonna Need It)
- [ ] All public APIs have documentation comments

### Testing
- [ ] All tests pass
- [ ] New code has tests
- [ ] Tests follow AAA pattern
- [ ] Edge cases covered
- [ ] Test names are descriptive
- [ ] Minimum 80% coverage for ViewModels

### Code Quality (SwiftLint/SwiftFormat)
- [ ] `swiftformat .` - Code is formatted
- [ ] `swiftlint` - No linting errors
- [ ] Documentation follows Swift conventions

### Performance
- [ ] No obvious performance issues
- [ ] Memory usage considered (no retain cycles)
- [ ] @MainActor used appropriately for UI updates
- [ ] Async operations don't block main thread

### Documentation
- [ ] Documentation comments complete for public APIs
- [ ] Complex algorithms explained
- [ ] README updated if needed

### Swift Style
- [ ] Swift API Design Guidelines followed
- [ ] Access control appropriate (`private`, `internal`, `public`)
- [ ] Value types (`struct`) preferred over reference types (`class`)
- [ ] Modern Swift features used (async/await, etc.)

## CI/CD Pipeline

### Pre-commit Hooks

**Install pre-commit** (optional but recommended):
```bash
brew install pre-commit
pre-commit install
```

**Configuration** (`.pre-commit-config.yaml`):
```yaml
repos:
  - repo: local
    hooks:
      - id: swiftlint
        name: SwiftLint
        entry: swiftlint lint --strict
        language: system
        types: [swift]
      - id: swiftformat
        name: SwiftFormat
        entry: swiftformat --lint
        language: system
        types: [swift]
```

### GitHub Actions CI

**Configuration** (`.github/workflows/ci.yml`):
```yaml
name: iOS CI

on: [push, pull_request]

jobs:
  build-and-test:
    runs-on: macos-14
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Select Xcode version
        run: sudo xcode-select -s /Applications/Xcode_15.2.app
      
      - name: Install SwiftLint
        run: brew install swiftlint
      
      - name: Install SwiftFormat
        run: brew install swiftformat
      
      - name: SwiftLint
        run: swiftlint lint --strict
      
      - name: SwiftFormat Check
        run: swiftformat --lint .
      
      - name: Build
        run: |
          xcodebuild build \
            -scheme RestaurantPicker \
            -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.2' \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO
      
      - name: Run Tests
        run: |
          xcodebuild test \
            -scheme RestaurantPicker \
            -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.2' \
            -enableCodeCoverage YES \
            CODE_SIGNING_ALLOWED=NO
      
      - name: Generate Coverage Report
        run: |
          xcrun xccov view --report --json \
            $(find ~/Library/Developer/Xcode/DerivedData -name "*.xcresult" | head -1) \
            > coverage.json
        continue-on-error: true
```

## Refactoring Guidelines

When refactoring code:

1. **Ensure tests pass before starting**: Never refactor broken code
2. **Make small, incremental changes**: Commit after each successful refactor
3. **Keep tests green**: Run tests after every change
4. **Extract functions**: If code has multiple levels of abstraction, extract helper functions
5. **Rename for clarity**: Use meaningful, descriptive names
6. **Remove duplication**: Apply DRY principle carefully
7. **Simplify conditionals**: Extract complex conditions into well-named functions
8. **Add tests if missing**: Write tests before refactoring untested code

**Refactoring Techniques**:
- **Extract Function**: Pull complex logic into separate functions
- **Rename**: Improve variable, function, or class names
- **Extract Variable**: Name intermediate values for clarity
- **Inline**: Remove unnecessary indirection
- **Replace Magic Numbers**: Use named constants

## Agent Responsibilities

As an AI agent working on this codebase, you MUST:

### 1. Before Making Changes
- [ ] Review existing code
- [ ] Understand current functionality
- [ ] Identify affected components
- [ ] Plan changes with clean code in mind
- [ ] Write tests first (TDD)
- [ ] Ensure tests fail initially

### 2. During Implementation
- [ ] Run `swiftformat .` and `swiftlint --fix` regularly
- [ ] Run formatter: `swiftformat .`
- [ ] Run linter: `swiftlint`
- [ ] Build project: `xcodebuild build -scheme RestaurantPicker`
- [ ] Implement minimal code to pass tests
- [ ] Refactor for clarity and maintainability
- [ ] Ensure existing tests pass at every step of refactoring and implementation
- [ ] Ask for help if unsure about design decisions or if existing tests prevent implementation
- [ ] Create/update implementation log with Mermaid diagrams
- [ ] Build DocC documentation: `Ctrl+Shift+Cmd+D` in Xcode
- [ ] Document design decisions in implementation logs
- [ ] Use meaningful names following Swift conventions
- [ ] Add comprehensive documentation comments
- [ ] Comment complex algorithms
- [ ] Create Mermaid diagrams for complex changes
- [ ] Follow existing code patterns
- [ ] Consider performance implications
- [ ] All new code has documentation comments
- [ ] Implementation log created with date, overview, and decisions
- [ ] Mermaid diagrams created:
  - Architecture diagrams for structural changes
  - Sequence diagrams for complex interactions
  - Class/struct diagrams for new types
  - Flowcharts for algorithms

### 3. After Implementation
- [ ] Run all tests and ensure they pass: `Cmd+U` in Xcode
- [ ] Run formatter: `swiftformat .`
- [ ] Run linter: `swiftlint`
- [ ] DocC documentation regenerated and verified
- [ ] Update relevant documentation
- [ ] Add usage examples in documentation comments
- [ ] Self-review code against checklist

### 4. Communication
- [ ] Use clear, concise commit messages
- [ ] Document design decisions
- [ ] Explain trade-offs made
- [ ] Note any technical debt created
- [ ] Highlight breaking changes

### 5. Documentation Requirements
- [ ] All new public APIs have documentation comments
- [ ] Examples added to documentation
- [ ] README.md updated if user-facing changes

## Project-Specific Guidelines

### Restaurant Data Structure

Restaurant model must follow this structure:

```swift
/// A restaurant discovered via MapKit search.
struct Restaurant: Identifiable, Equatable {
    /// Unique identifier for the restaurant.
    let id: UUID
    
    /// Display name of the restaurant.
    let name: String
    
    /// Geographic coordinates of the restaurant.
    let coordinate: CLLocationCoordinate2D
    
    /// Distance from user's current location in meters.
    let distance: Double
    
    /// Category of the restaurant (e.g., "Thai", "Italian").
    let category: String?
    
    /// Phone number if available.
    let phoneNumber: String?
    
    /// URL for more information.
    let url: URL?
}
```

### Distance Filtering

Understanding how distance filtering works:

```swift
// Default radius is 5km (5000 meters)
viewModel.filterRadius = 5000

// Filter to show only restaurants within 1km
viewModel.filterRadius = 1000

// Show all restaurants (no distance filter)
viewModel.filterRadius = nil
```

### Cuisine Filtering

Users can filter by including or excluding cuisine types. The available cuisines
are derived dynamically from the fetched restaurant categories. Both filters are
accessed through a filter icon in the navigation bar that opens a sheet.

```swift
// Available cuisines (computed from current restaurants)
viewModel.availableCuisines  // e.g., ["Italian", "Japanese", "Thai"]

// Include filter — show only these cuisines (empty = show all)
viewModel.selectedCuisines = ["Thai"]
viewModel.selectedCuisines = ["Thai", "Japanese"]
viewModel.selectedCuisines = []  // show all

// Exclude filter — hide these cuisines (empty = exclude nothing)
viewModel.excludedCuisines = ["Italian"]
viewModel.excludedCuisines = []  // exclude nothing

// Active filter count for badge display
viewModel.activeCuisineFilterCount  // selectedCuisines.count + excludedCuisines.count
```

A cuisine cannot be both included and excluded — toggling one automatically
removes it from the other. Distance, include, and exclude filters all combine —
a restaurant must pass **all three** to appear in the list.

### User Ratings

Users can rate restaurants 1–5 stars. Ratings are stored locally on device
using `UserDefaults` via `RatingStore` and are never shared.

```swift
let store = RatingStore()

// Save a rating
store.setRating(4, for: restaurant)

// Retrieve a rating (nil if not rated)
let rating = store.rating(for: restaurant)  // 4

// Remove a rating
store.setRating(nil, for: restaurant)
```

Ratings are keyed by restaurant name + coordinate (not UUID) so the same
physical restaurant retains its rating across app launches and searches.

- **Row view**: 5 small read-only stars (12pt) to the right of the cuisine category
- **Detail view**: 5 larger tappable stars (28pt) for rating interaction
- **No rating**: stars appear greyed out
- **Rated**: filled stars are yellow with a white stroke; empty stars have a white stroke

#### Rating Filtering

Users can filter restaurants by minimum star rating via the filter sheet.
The filter is pyramidal — selecting "2+" shows restaurants rated 2, 3, 4, and 5.
Unrated restaurants are hidden when a rating filter is active.

```swift
viewModel.minimumRating = 3   // shows 3, 4, 5 star restaurants
viewModel.minimumRating = nil // shows all (no rating filter)
```

Options: `All`, `1+`, `2+`, `3+`, `4+`, `5`

#### Weighted Random Selection

When no rating filter is active, random selection is weighted by rating
using a quadratic scale centred on 3★ = 1.0:

| Rating | Weight |
|--------|--------|
| 1★     | 0.25   |
| 2★     | 0.50   |
| 3★     | 1.00   |
| 4★     | 2.00   |
| 5★     | 4.00   |
| Unrated| 1.00   |

When a rating filter **is** active, selection is uniform (equal probability).

### Random Selection

The random selection algorithm:

```swift
/// Selects a random restaurant from the filtered list.
///
/// - Returns: A randomly selected restaurant, or nil if no restaurants available.
func selectRandomRestaurant() -> Restaurant? {
    guard !filteredRestaurants.isEmpty else { return nil }
    return filteredRestaurants.randomElement()
}
```

### MapKit Search

The app searches for nearby restaurants using parallel cuisine-specific queries
to overcome `MKLocalSearch`'s ~25 result limit per query:

```swift
/// Searches for restaurants near a location.
///
/// Runs 36 cuisine-specific searches in parallel (e.g., "thai restaurant",
/// "italian restaurant", etc.) then deduplicates results by name + proximity.
///
/// - Parameters:
///   - location: The center point for the search.
///   - radius: Search radius in meters.
/// - Returns: Array of discovered restaurants sorted by distance.
func searchRestaurants(near location: CLLocation, radius: Double) async throws -> [Restaurant] {
    let region = MKCoordinateRegion(
        center: location.coordinate,
        latitudinalMeters: radius * 2,
        longitudinalMeters: radius * 2
    )

    let allResults = await withTaskGroup(of: [(Restaurant, String)].self) { group in
        for cuisine in Self.cuisineQueries {
            group.addTask {
                await self.performSearch(
                    query: cuisine.query,
                    label: cuisine.label,
                    region: region,
                    location: location,
                    radius: radius
                )
            }
        }
        // ... collect and return combined results
    }

    // Deduplicate by name + proximity, assign cuisine label as category
    // ... return unique results sorted by distance
}
```

### Location Permissions

Handle location permission states appropriately:

```swift
enum LocationAuthorizationStatus {
    case notDetermined
    case denied
    case authorized
}

// Always request "When In Use" permission, not "Always"
locationManager.requestWhenInUseAuthorization()
```

### SwiftUI View Structure

Main view hierarchy:

```swift
struct ContentView: View {
    @StateObject private var viewModel = RestaurantViewModel()
    @State private var showCuisineFilter = false
    
    var body: some View {
        NavigationStack {
            VStack {
                // Distance filter control
                DistanceFilterView(radius: $viewModel.filterRadius)
                
                // Restaurant list — tapping a row pushes RestaurantDetailView
                RestaurantListView(
                    restaurants: viewModel.filteredRestaurants,
                    selectedRestaurant: viewModel.selectedRestaurant
                )
                
                // Random selection button
                DecideButton {
                    viewModel.selectRandomRestaurant()
                }
            }
            .navigationTitle("Restaurant Picker")
            .toolbar {
                // Cuisine filter icon — opens sheet, shows badge when active
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showCuisineFilter = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            // Cuisine filter sheet with Include/Exclude sections
            .sheet(isPresented: $showCuisineFilter) {
                CuisineFilterView(
                    availableCuisines: viewModel.availableCuisines,
                    selectedCuisines: $viewModel.selectedCuisines,
                    excludedCuisines: $viewModel.excludedCuisines
                )
            }
            // Random selection result presented as a sheet
            .sheet(isPresented: $viewModel.showSelectedRestaurant) {
                if let restaurant = viewModel.selectedRestaurant {
                    SelectedRestaurantView(restaurant: restaurant) {
                        viewModel.clearSelection()
                    }
                }
            }
        }
        .task {
            await viewModel.fetchNearbyRestaurants()
        }
    }
}
```

#### Navigation Flow
- **List → Detail**: `RestaurantListView` wraps each row in a `NavigationLink`
  that pushes `RestaurantDetailView` (shows info, call, Maps, website buttons).
- **Filter Icon → Sheet**: Toolbar filter icon opens `CuisineFilterView` as a
  half/full-height sheet with Include/Exclude sections and a Reset button.
- **Random Pick → Sheet**: The "Pick a Restaurant!" button triggers
  `SelectedRestaurantView` as a modal sheet with celebration UI and a
  "Pick Again" button.
