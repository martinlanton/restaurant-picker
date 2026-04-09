import SwiftUI

/// A prominent button for triggering random restaurant selection.
///
/// This button is designed to be placed at the bottom of the screen
/// and provides visual feedback when tapped.
struct DecideButtonView: View {
    /// The action to perform when the button is tapped.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "dice")
                    .font(.title2)
                Text("Pick a Restaurant!")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        DecideButtonView {
            print("Button tapped!")
        }
        .padding()
    }
}

