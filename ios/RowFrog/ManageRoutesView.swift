import SwiftUI

/// All saved routes on a lake, from the route menus: each with its length and
/// whether it is a loop or rowed out and back. Tap one to open it; rename,
/// duplicate, delete and drag into order.
struct ManageRoutesView: View {
    let lakeID: String
    /// The route open on the map, marked in the list.
    let current: Route.ID?
    let open: (Route) -> Void
    /// Tells the map when the open route was deleted or renamed.
    let changed: (Route.ID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Route?
    @State private var newName = ""
    private let store = RouteStore.shared

    var body: some View {
        let routes = store.routes(on: lakeID)
        NavigationStack {
            List {
                ForEach(routes) { route in
                    Button {
                        open(route)
                        dismiss()
                    } label: {
                        row(route)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(tr("Delete"), systemImage: "trash", role: .destructive) { delete(route) }
                    }
                    .swipeActions(edge: .leading) {
                        Button(tr("Rename"), systemImage: "pencil") { startRenaming(route) }
                            .tint(.orange)
                    }
                    .contextMenu {
                        Button(tr("Rename"), systemImage: "pencil") { startRenaming(route) }
                        Button(tr("Duplicate"), systemImage: "plus.square.on.square") { store.duplicate(route) }
                        Button(tr("Delete"), systemImage: "trash", role: .destructive) { delete(route) }
                    }
                }
                .onMove { store.move(on: lakeID, from: $0, to: $1) }
                .onDelete { offsets in offsets.map { routes[$0] }.forEach(delete) }
            }
            .overlay {
                if routes.isEmpty {
                    ContentUnavailableView(tr("No saved routes"), systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                           description: Text(tr("Plan a route on the map and save it from the bookmark menu.")))
                }
            }
            .navigationTitle(tr("Manage routes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton().disabled(routes.isEmpty) }
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
            .alert(tr("Rename route"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(tr("Name"), text: $newName)
                Button(tr("Save")) {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if let route = renaming, !name.isEmpty {
                        store.rename(route, to: name)
                        changed(route.id)
                    }
                }
                Button(tr("Cancel"), role: .cancel) {}
            }
        }
    }

    private func row(_ route: Route) -> some View {
        HStack(spacing: 12) {
            Image(systemName: route.importedFrom != nil ? "figure.rower" : route.isLoop ? "arrow.triangle.capsulepath" : route.outAndBack ? "arrow.left.arrow.right" : "arrow.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                Text(details(route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if route.id == current {
                Text(tr("Open"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func details(_ route: Route) -> String {
        let shape = route.isLoop ? tr("Loop") : route.outAndBack ? tr("Out and back") : tr("One way")
        var text = "\(Format.distance(route.lengthM)) · \(shape)"
        // A row brought in from Apple Health or a file.
        if route.importedFrom != nil {
            text += " · " + (route.rowedAt.map { tr("rowed %@", Format.day($0)) } ?? tr("rowed"))
        }
        return text
    }

    private func startRenaming(_ route: Route) {
        newName = route.name
        renaming = route
    }

    private func delete(_ route: Route) {
        store.delete(route)
        changed(route.id)
    }
}
