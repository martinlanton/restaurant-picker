import SwiftUI

/// A 5-star rating control for restaurants.
///
/// Displays 5 tappable stars. When no rating is set, stars appear
/// slightly greyed out. When rated, filled stars show yellow with
/// a white stroke, and empty stars show the background color with
/// a white stroke.
///
/// ## Usage
/// ```swift
/// StarRatingView(rating: $rating)
/// StarRatingView(rating: .constant(3), isInteractive: false)
/// ```
struct StarRatingView: View {
    /// The current rating (1–5), or nil if not yet rated.
    @Binding var rating: Int?

    /// Whether the user can tap to change the rating.
    var isInteractive: Bool = true

    /// The size of each star.
    var starSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1 ... 5, id: \.self) { index in
                starView(for: index)
                    .onTapGesture {
                        guard isInteractive else { return }
                        if rating == index {
                            // Tap same star again to clear
                            rating = nil
                        } else {
                            rating = index
                        }
                    }
            }
        }
    }

    // MARK: - Private Methods

    /// Returns the appropriate star view for a given position.
    @ViewBuilder
    private func starView(for index: Int) -> some View {
        if let currentRating = rating {
            if index <= currentRating {
                // Filled star — yellow fill, white stroke
                Image(systemName: "star.fill")
                    .font(.system(size: starSize))
                    .foregroundColor(.yellow)
                    .overlay(
                        Image(systemName: "star")
                            .font(.system(size: starSize))
                            .foregroundColor(.white.opacity(0.6))
                    )
            } else {
                // Empty star in a rated restaurant — background color, white stroke
                Image(systemName: "star")
                    .font(.system(size: starSize))
                    .foregroundColor(.white.opacity(0.6))
            }
        } else {
            // No rating — greyed out stars
            Image(systemName: "star")
                .font(.system(size: starSize))
                .foregroundColor(.gray.opacity(0.3))
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // No rating
        StarRatingView(rating: .constant(nil))

        // 3 star rating
        StarRatingView(rating: .constant(3))

        // 5 star rating
        StarRatingView(rating: .constant(5))

        // Larger, non-interactive
        StarRatingView(rating: .constant(4), isInteractive: false, starSize: 24)
    }
    .padding()
    .background(Color(.systemBackground))
}
