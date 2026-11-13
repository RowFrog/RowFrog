import SwiftUI

/// The top of a full-screen map: close, the title and the map's own buttons
/// floating as glass over the map, which runs to the screen's top edge, as on
/// the lake view (LakeMapScreen.topBar). A navigation bar left a dark band over
/// the weather maps and the rain radar (owner, 13 Nov 2026).
struct MapTopBar<Trailing: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .floatingControl(Circle())
            .accessibilityLabel(tr("Close"))
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .floatingControl(Capsule())
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }
}

extension MapTopBar where Trailing == EmptyView {
    init(title: String, close: @escaping () -> Void) {
        self.init(title: title, close: close) { EmptyView() }
    }
}
