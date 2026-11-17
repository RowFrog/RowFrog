import SwiftUI
import UIKit

/// The Row Frog icon's long-press menu on the Home Screen (decision 0048, owner's
/// pick A, 17 Nov 2026): the home base, its lake view, its rain radar and the
/// club opened last besides it. No weather in the menu: iOS keeps the items until
/// the app runs again, so a rowing light there could be hours old. With no club
/// saved, the menu offers Add a club. iOS shows at most four of an app's items.
struct QuickAction: Equatable {
    let title: String
    let subtitle: String?
    let symbol: String
    let link: URL
}

enum QuickActions {
    /// A saved club as the menu needs it.
    struct Place: Equatable {
        let id: String
        let name: String
        /// The lake or river; nil when the catalogs don't name it.
        let water: String?
        /// "Lake view", "River view" or "Canal view"; nil when the water has no lake view.
        let viewTitle: String?
    }

    static let maxCount = 4

    /// The menu for the saved clubs, home base first (`LocationStore.saved`).
    /// `homeID` is nil while no club is the home base; `lastOpened` is the club
    /// shown last other than the first one.
    static func list(saved: [Place], homeID: String?, lastOpened: String?) -> [QuickAction] {
        guard let first = saved.first else {
            return [QuickAction(title: tr("Add a club"), subtitle: tr("Search for a rowing club or lake"),
                                symbol: "plus.circle", link: link("add"))]
        }
        let isHome = first.id == homeID
        let firstLine = isHome ? [tr("Home base"), first.water].compactMap { $0 }.joined(separator: " · ") : first.water
        var items = [QuickAction(title: first.name, subtitle: firstLine, symbol: isHome ? "house" : "figure.rower",
                                 link: link("club", first.id))]
        if let view = first.viewTitle {
            items.append(QuickAction(title: view, subtitle: first.water, symbol: "water.waves", link: link("lake", first.id)))
        }
        items.append(QuickAction(title: tr("Rain radar"), subtitle: tr("Around %@", first.name), symbol: "cloud.rain",
                                 link: link("radar", first.id)))
        let others = saved.dropFirst()
        if let last = others.first(where: { $0.id == lastOpened }) {
            items.append(QuickAction(title: last.name, subtitle: tr("Last opened"), symbol: "clock.arrow.circlepath",
                                     link: link("club", last.id)))
        } else if let next = others.first {
            items.append(QuickAction(title: next.name, subtitle: next.water, symbol: "figure.rower", link: link("club", next.id)))
        }
        return Array(items.prefix(maxCount))
    }

    /// rowfrog://club/<id>, rowfrog://lake/<id>, rowfrog://radar/<id> (the club's id) and rowfrog://add.
    static func link(_ kind: String, _ id: String? = nil) -> URL {
        var parts = URLComponents()
        parts.scheme = "rowfrog"
        parts.host = kind
        if let id { parts.path = "/" + id }
        return parts.url ?? URL(string: "rowfrog://\(kind)")!
    }

    /// The saved clubs with their water, for `list`.
    @MainActor
    static func places(_ locations: LocationStore) -> [Place] {
        locations.saved.map { club in
            let lake = locations.lake(of: club)
            let water = lake.flatMap { $0.waterUnknown ? nil : $0.title }
            return Place(id: club.id, name: club.displayName, water: water,
                         viewTitle: lake?.hasOutline == false ? nil : lake?.water.viewTitle)
        }
    }

    /// Notes the club on screen, so "Last opened" names it; the first club doesn't count.
    @MainActor
    static func noteShown(_ id: String, in locations: LocationStore) {
        guard !id.isEmpty, id != locations.saved.first?.id else { return }
        UserDefaults.standard.set(id, forKey: DefaultsKey.lastOpenedClub)
    }

    /// Hands the menu to iOS; called as the user leaves the app, as WidgetBridge.
    @MainActor
    static func publish(_ locations: LocationStore) {
        let items = list(saved: places(locations), homeID: locations.homeID,
                         lastOpened: UserDefaults.standard.string(forKey: DefaultsKey.lastOpenedClub))
        UIApplication.shared.shortcutItems = items.map { item in
            UIApplicationShortcutItem(type: "com.rowfrog.RowFrog.open", localizedTitle: item.title,
                                      localizedSubtitle: item.subtitle,
                                      icon: UIApplicationShortcutIcon(systemImageName: item.symbol),
                                      userInfo: [linkKey: item.link.absoluteString as NSString])
        }
    }

    static let linkKey = "link"

    static func link(of item: UIApplicationShortcutItem) -> URL? {
        (item.userInfo?[linkKey] as? String).flatMap(URL.init(string:))
    }
}

/// A menu item tapped on the Home Screen, until RootView opens it.
@MainActor
@Observable
final class QuickActionInbox {
    static let shared = QuickActionInbox()
    var pending: URL?

    func take() -> URL? {
        defer { pending = nil }
        return pending
    }
}

/// Gets the menu taps from iOS: on a cold start with the scene's options, otherwise
/// through `performActionFor` (RowFrogApp's AppDelegate names this class).
@MainActor
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem { deliver(item) }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        deliver(shortcutItem)
        return true
    }

    private func deliver(_ item: UIApplicationShortcutItem) {
        guard let url = QuickActions.link(of: item) else { return }
        QuickActionInbox.shared.pending = url
    }
}

/// What a menu item opens over the club page.
enum QuickOpen: Identifiable {
    case lake(lakeID: String, clubID: String)
    case radar(Club)

    var id: String {
        switch self {
        case .lake(let lake, let club): "lake|\(lake)|\(club)"
        case .radar(let club): "radar|\(club.id)"
        }
    }
}

/// The lake view from the menu: waits for the lake's view, as the lake view tile does.
struct QuickLakeScreen: View {
    let lakeID: String
    let clubID: String
    @Environment(\.dismiss) private var dismiss
    @MainActor private var store: LakeViewStore { .shared }

    var body: some View {
        if let view = store.views[lakeID, club: clubID] {
            LakeMapScreen(view: view, clubID: clubID)
        } else {
            NavigationStack {
                Group {
                    if store.failed(lakeID) {
                        ContentUnavailableView {
                            Label(tr("Lake view"), systemImage: "map")
                        } description: {
                            Text(tr("The lake view could not load. Try again later."))
                        } actions: {
                            Button(tr("Try again")) { Task { await store.load(lakeID, force: true) } }
                        }
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar { CloseToolbarItem { dismiss() } }
            }
            .task { await store.load(lakeID) }
        }
    }
}
