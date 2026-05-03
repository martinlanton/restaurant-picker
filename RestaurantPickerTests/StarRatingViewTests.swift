import SwiftUI
@testable import RestaurantPicker
import XCTest

/// Unit tests for `StarRatingView` logic helpers.
///
/// These tests verify the computed icon name and colour used by the
/// reject button across every possible rating state (nil, 0, 1–5).
/// They act as a regression guard: if the visual contract ever changes
/// unintentionally, these tests will fail before the change ships.
final class StarRatingViewTests: XCTestCase {
    // MARK: - Reject Icon System Name

    /// The reject button must always use the "nosign" SF Symbol.
    /// Visual differentiation between rejected and non-rejected states
    /// is handled purely by colour, not by switching to a different icon.
    func testRejectIconSystemNameIsNosign() {
        XCTAssertEqual(StarRatingView.rejectIconSystemName, "nosign")
    }

    // MARK: - Reject Button Colour

    func testRejectButtonColorIsRedWhenRejected() {
        // Arrange & Act
        let color = StarRatingView.rejectButtonColor(for: 0)

        // Assert — rating 0 (rejected) → red
        XCTAssertEqual(color, Color.red)
    }

    func testRejectButtonColorIsGreyWhenUnrated() {
        // Arrange & Act
        let color = StarRatingView.rejectButtonColor(for: nil)

        // Assert — nil (unrated) → greyed out
        XCTAssertEqual(color, Color.gray.opacity(0.3))
    }

    func testRejectButtonColorIsGreyForOneStar() {
        let color = StarRatingView.rejectButtonColor(for: 1)
        XCTAssertEqual(color, Color.gray.opacity(0.3))
    }

    func testRejectButtonColorIsGreyForFiveStars() {
        let color = StarRatingView.rejectButtonColor(for: 5)
        XCTAssertEqual(color, Color.gray.opacity(0.3))
    }

    /// Exhaustively checks that every non-rejected state (nil + 1…5)
    /// produces the greyed-out colour — only rating 0 should be red.
    func testRejectButtonColorIsGreyForAllNonRejectedStates() {
        let nonRejected: [Int?] = [nil, 1, 2, 3, 4, 5]
        for rating in nonRejected {
            XCTAssertEqual(
                StarRatingView.rejectButtonColor(for: rating),
                Color.gray.opacity(0.3),
                "Expected grey for rating \(String(describing: rating))"
            )
        }
    }

    func testRejectButtonColorIsRedOnlyForRatingZero() {
        XCTAssertEqual(StarRatingView.rejectButtonColor(for: 0), Color.red)
        XCTAssertNotEqual(StarRatingView.rejectButtonColor(for: nil), Color.red)
        XCTAssertNotEqual(StarRatingView.rejectButtonColor(for: 1), Color.red)
    }
}
