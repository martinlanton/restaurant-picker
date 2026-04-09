import XCTest

/// UI Tests for the Restaurant Picker app.
final class RestaurantPickerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testDecideButtonExists() throws {
        // The decide button should be visible
        let decideButton = app.buttons["Pick a Restaurant!"]
        XCTAssertTrue(decideButton.waitForExistence(timeout: 5))
    }

    func testNavigationTitleDisplayed() throws {
        // The navigation title should be displayed
        let navTitle = app.navigationBars["Restaurant Picker"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
    }

    func testDistanceFilterExists() throws {
        // Distance filter options should be visible
        let maxDistanceLabel = app.staticTexts["Max Distance"]
        XCTAssertTrue(maxDistanceLabel.waitForExistence(timeout: 5))
    }
}

