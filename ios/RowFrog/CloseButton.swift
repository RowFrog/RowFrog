import SwiftUI

/// Closes a screen or sheet that is only looked at: the round X at the top left,
/// as iOS 26's close role (owner's pick A, 12 Nov 2026, docs/decisions/0023).
/// Sheets that edit something keep Cancel and Done; cards inside a screen close
/// with `CardCloseButton` at their own top right.
struct CloseToolbarItem: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            CloseButton(action: action)
        }
    }
}

/// The X itself, for a toolbar.
struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close, action: action)
                .accessibilityIdentifier("close")
        } else {
            Button(action: action) {
                Image(systemName: "xmark").fontWeight(.semibold)
            }
            .accessibilityLabel(tr("Close"))
            .accessibilityIdentifier("close")
        }
    }
}

/// Closes a card inside a screen (a tapped spot, a route point): a grey round X
/// at the card's top right, as Maps' place cards.
struct CardCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Close"))
    }
}
