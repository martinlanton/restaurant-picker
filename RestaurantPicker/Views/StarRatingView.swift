import SwiftUI

/// A 5-star rating control for restaurants with an optional reject button.
///
/// Displays 5 tappable stars and optionally a reject button (red ⊘ icon).
/// - Rating `nil`: unrated — stars greyed out, reject icon greyed out
/// - Rating `1–5`: star-rated — filled yellow stars, reject icon greyed out
/// - Rating `0`: rejected — red ⊘ icon shown prominently
///
/// ## Usage
/// ```swift
/// // Row view — compact, shows either stars or reject icon
/// StarRatingView(rating: $rating, isInteractive: false, starSize: 12, displayMode: .compact)
///
/// // Detail view — full, always shows both stars and reject icon
/// StarRatingView(rating: $rating, isInteractive: true, starSize: 28, displayMode: .full)
/// ```
struct StarRatingView: View {
    /// The current rating: nil = unrated, 0 = rejected, 1–5 = star rating.
    @Binding var rating: Int?

    /// Whether the user can tap to change the rating.
    var isInteractive: Bool = true

    /// The size of each star.
    var starSize: CGFloat = 14

    /// How to display the rating controls.
    /// - `compact`: shows either stars OR reject icon (for list rows)
    /// - `full`: always shows both stars AND reject icon (for detail view)
    var displayMode: DisplayMode = .compact

    enum DisplayMode {
        case compact
        case full
    }

    var body: some View {
        HStack(spacing: starSize * 0.3) {
            if displayMode == .full {
                // Full mode: always show stars + reject icon
                starsRow
                rejectButton
            } else {
                // Compact mode: show reject icon if rejected, otherwise stars
                if rating == 0 {
                    rejectButton
                } else {
                    starsRow
                }
            }
        }
    }

    // MARK: - Private Views

    private var starsRow: some View {
        HStack(spacing: 2) {
            ForEach(1 ... 5, id: \.self) { index in
                starView(for: index)
                    .onTapGesture {
                        guard isInteractive else { return }
                        if rating == index {
                            rating = nil
                        } else {
                            rating = index
                        }
                    }
            }
        }
    }

    private var rejectButton: some View {
        Image(systemName: rating == 0 ? "nosign" : "nosign")
            .font(.system(size: starSize))
            .foregroundColor(rejectColor)
            .onTapGesture {
                guard isInteractive else { return }
                if rating == 0 {
                    rating = nil
                } else {
                    rating = 0
                }
            }
    }

    private var rejectColor: Color {
        if rating == 0 {
            return .red
        } else {
            return .gray.opacity(0.3)
        }
    }

    /// Returns the appropriate star view for a given position.
    @ViewBuilder
    private func starView(for index: Int) -> some View {
        let currentRating = rating ?? -1 // -1 means unrated for display purposes
        if currentRating > 0, index <= currentRating {
            // Filled star — yellow fill, white stroke
            Image(systemName: "star.fill")
                .font(.system(size: starSize))
                .foregroundColor(.yellow)
                .overlay(
                    Image(systemName: "star")
                        .font(.system(size: starSize))
                        .foregroundColor(.white.opacity(0.6))
                )
        } else if currentRating > 0 {
            // Empty star in a rated restaurant — white stroke
            Image(systemName: "star")
                .font(.system(size: starSize))
                .foregroundColor(.white.opacity(0.6))
        } else {
            // No rating or rejected — greyed out stars
            Image(systemName: "star")
                .font(.system(size: starSize))
                .foregroundColor(.gray.opacity(0.3))
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // No rating — compact
        StarRatingView(rating: .constant(nil), displayMode: .compact)

        // 3 star rating — compact
        StarRatingView(rating: .constant(3), displayMode: .compact)

        // Rejected — compact (shows only red icon)
        StarRatingView(rating: .constant(0), displayMode: .compact)

        // No rating — full
        StarRatingView(rating: .constant(nil), displayMode: .full)

        // 3 star rating — full
        StarRatingView(rating: .constant(3), displayMode: .full)

        // Rejected — full (shows greyed stars + red icon)
        StarRatingView(rating: .constant(0), displayMode: .full)

        // Larger, interactive, full
        StarRatingView(rating: .constant(4), isInteractive: true, starSize: 28, displayMode: .full)
    }
    .padding()
    .background(Color(.systemBackground))
}
