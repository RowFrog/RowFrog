import SwiftUI

/// Settings › Routes: every saved route, grouped by its water, with the same
/// tools as Manage routes (rename, duplicate, share link, delete, drag into
/// order within a water), and a link with every route for a browser. A tap opens the route on its lake map (owner's pick, 12 Nov 2026;
/// the website's renderAllRoutes).
struct AllRoutesView: View {
    let locations: LocationStore
    /// A saved route on the lake map, once its lake view has loaded.
    private struct Opened: Identifiable {
        let route: Route
        let view: LakeView
        let clubID: String?
        var id: Route.ID { route.id }
    }

    @State private var opened: Opened?
    @State private var loading: Route.ID?
    @State private var failed = false
    @State private var renaming: Route?
    @State private var newName = ""
    /// RouteStore is not observed; this redraws the list after a change.
    @State private var version = 0
    private let store = RouteStore.shared
    /// The pace route times are planned with, 2:30 /500 m unless the crew sets its own
    /// (owner, 14 Nov 2026). The lake map's stepper and an imported row change it too.
    @AppStorage(DefaultsKey.routePace) private var pace = 150.0

    var body: some View {
        let _ = version
        let lakes = Dictionary(grouping: store.routes, by: \.lakeId)
            .sorted { lakeName($0.key).localizedStandardCompare(lakeName($1.key)) == .orderedAscending }
        List {
            Section {
                Stepper(value: $pace, in: 90...240, step: 5) {
                    LabeledContent(tr("Standard pace /500 m")) {
                        Text(Format.pace(pace)).monospacedDigit()
                    }
                }
            } footer: {
                SectionFooter(tr("Route times on the lake maps start from this pace; the map's own stepper changes it too."))
            }
            .surfaceRows()
            if store.routes.isEmpty {
                Section {
                    ContentUnavailableView(tr("No saved routes"), systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                           description: Text(tr("Plan a route on the map and save it from the bookmark menu.")))
                }
                .listRowBackground(Color.clear)
            }
            ForEach(lakes, id: \.key) { entry in
                let lakeID = entry.key
                let routes = entry.value
                Section {
                    ForEach(routes) { route in
                        Button { open(route) } label: { row(route) }
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
                                Button(tr("Duplicate"), systemImage: "plus.square.on.square") {
                                    store.duplicate(route)
                                    version += 1
                                }
                                if let url = RouteLink.url(for: [route]) {
                                    ShareLink(item: url, subject: Text(route.name)) {
                                        Label(tr("Share link"), systemImage: "square.and.arrow.up")
                                    }
                                }
                                ShareLink(item: RouteGPXFile(route: route), preview: SharePreview(route.name)) {
                                    Label(tr("Export GPX"), systemImage: "doc.badge.arrow.up")
                                }
                                Button(tr("Delete"), systemImage: "trash", role: .destructive) { delete(route) }
                            }
                    }
                    .onMove { from, to in
                        store.move(on: lakeID, from: from, to: to)
                        version += 1
                    }
                    .onDelete { offsets in offsets.map { routes[$0] }.forEach(delete) }
                } header: {
                    Text(lakeName(lakeID))
                } footer: {
                    // The page's one footer, under the last water (as on the other Settings pages).
                    if lakeID == lakes.last?.key {
                        SectionFooter(tr("Every saved route, by water. Tap one to open it on its lake map."))
                    }
                }
                .surfaceRows()
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .navigationTitle(tr("Routes"))
        // Inline like every other Settings page: a large title overlapped the first water's name.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Every saved route in one link, to save them in a browser (RouteLink).
            if let url = RouteLink.url(for: store.routes) {
                ShareLink(item: url, subject: Text(tr("Routes"))) {
                    Label(tr("Share all routes"), systemImage: "square.and.arrow.up")
                }
            }
            EditButton().disabled(store.routes.isEmpty)
        }
        .fullScreenCover(item: $opened, onDismiss: { version += 1 }) { opened in
            LakeMapScreen(view: opened.view, clubID: opened.clubID, route: opened.route)
        }
        .alert(tr("No forecast"), isPresented: $failed) {
            Button(tr("OK"), role: .cancel) {}
        }
        .alert(tr("Rename route"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(tr("Name"), text: $newName)
            Button(tr("Save")) {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let route = renaming, !name.isEmpty {
                    store.rename(route, to: name)
                    version += 1
                }
            }
            Button(tr("Cancel"), role: .cancel) {}
        }
    }

    private func lakeName(_ id: String) -> String {
        locations.lakes.first { $0.id == id }?.name ?? id
    }

    private func row(_ route: Route) -> some View {
        HStack(spacing: 12) {
            Image(systemName: route.importedFrom != nil ? "figure.rower" : route.isLoop ? "arrow.triangle.capsulepath" : route.outAndBack ? "arrow.left.arrow.right" : "arrow.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                Text(ManageRoutesView.details(route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if loading == route.id { ProgressView() }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Loads the route's lake view, then opens the map from the page of a saved
    /// club on that water, else its first club.
    private func open(_ route: Route) {
        let lake = locations.lakes.first { $0.id == route.lakeId }
        let clubID = (lake?.clubs.first { locations.isSaved($0) } ?? lake?.clubs.first)?.id
        loading = route.id
        Task { @MainActor in
            await LakeViewStore.shared.load(route.lakeId)
            loading = nil
            if let view = LakeViewStore.shared.views[route.lakeId, club: clubID] {
                opened = Opened(route: route, view: view, clubID: clubID)
            } else {
                failed = true
            }
        }
    }

    private func startRenaming(_ route: Route) {
        newName = route.name
        renaming = route
    }

    private func delete(_ route: Route) {
        store.delete(route)
        version += 1
    }
}
