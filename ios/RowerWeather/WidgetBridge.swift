import SwiftUI
import WidgetKit

/// Copies what the widget needs into the shared app group and asks it to
/// redraw: the home base, the saved clubs and their names, and the settings
/// (units, language, time format).
enum WidgetBridge {
    static func publish(_ locations: LocationStore) {
        let shared = WidgetShared.defaults
        let saved = locations.saved
        if !saved.isEmpty {
            shared.set(locations.homeID, forKey: WidgetShared.homeKey)
            shared.set(saved.map(\.id), forKey: WidgetShared.savedKey)
            shared.set(Dictionary(saved.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a }), forKey: WidgetShared.namesKey)
        }
        shared.set(Dictionary(locations.ownPlaces.map { ($0.id, [$0.coordinate.lat, $0.coordinate.lon]) }, uniquingKeysWith: { a, _ in a }),
                   forKey: WidgetShared.ownPlacesKey)
        for key in AppSettings.Keys.all {
            shared.set(UserDefaults.standard.object(forKey: key), forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Screenshot hook `-RWWidgetGallery YES`: the widget in every size with the
/// home base's live forecast, as it would look on the home and lock screens.
/// Not reachable from the app's UI.
struct WidgetGalleryView: View {
    let api: APIClient
    @State private var forecast: ClubForecast?
    @State private var failed = false

    private let homeID = UserDefaults.standard.string(forKey: "RWHomeClub") ?? WidgetShared.defaultHomeID

    // Widget sizes on a 6.3" iPhone, in points; extra large is the iPad's.
    private let sizes: [(WidgetFamily, CGSize, String)] = [
        (.systemSmall, CGSize(width: 170, height: 170), "Small"),
        (.systemMedium, CGSize(width: 364, height: 170), "Medium"),
        (.systemLarge, CGSize(width: 364, height: 382), "Large"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if failed {
                    Text("The forecast could not be loaded.").foregroundStyle(.secondary)
                }
                let snapshot = RowingSnapshot(date: .now, clubName: "MRC 1880", isHome: true, forecast: forecast)
                ForEach(sizes.indices, id: \.self) { index in
                    caption(sizes[index].2)
                    widget(snapshot, sizes[index].0, sizes[index].1)
                }
                caption("Medium: conditions")
                widget(snapshot, .systemMedium, sizes[1].1, focus: .conditions)
                caption("Medium: good rowing times")
                widget(snapshot, .systemMedium, sizes[1].1, focus: .windows)
                caption("Large: good rowing times first")
                widget(snapshot, .systemLarge, sizes[2].1, focus: .windows)
                caption("Extra large (iPad only)")
                widget(snapshot, .systemExtraLarge, CGSize(width: 715, height: 354))
                    .scaleEffect(364 / 715, anchor: .topLeading)
                    .frame(width: 364, height: 354 * 364 / 715, alignment: .topLeading)
                caption("Lock screen")
                HStack(spacing: 12) {
                    accessory(snapshot, .accessoryCircular, CGSize(width: 76, height: 76))
                    accessory(snapshot, .accessoryRectangular, CGSize(width: 172, height: 76))
                }
                accessory(snapshot, .accessoryInline, CGSize(width: 300, height: 26))
                caption("Without a connection")
                widget(RowingSnapshot(date: .now, clubName: "MRC 1880", isHome: true, forecast: nil), .systemSmall, sizes[0].1)
            }
            .padding()
        }
        .background(
            LinearGradient(colors: [Color(red: 0.62, green: 0.79, blue: 0.96), Color(red: 0.91, green: 0.85, blue: 0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: "RWScrollPage"), ready: forecast != nil || failed))
        .task {
            do { forecast = try await api.forecast(clubID: homeID) } catch { failed = true }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.black.opacity(0.7))
    }

    private func widget(_ snapshot: RowingSnapshot, _ family: WidgetFamily, _ size: CGSize, focus: WidgetFocus = .hourly) -> some View {
        RowingWidgetView(snapshot: snapshot, family: family, focus: focus)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(WidgetSky(snapshot: snapshot))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private func accessory(_ snapshot: RowingSnapshot, _ family: WidgetFamily, _ size: CGSize) -> some View {
        RowingWidgetView(snapshot: snapshot, family: family)
            .frame(width: size.width, height: size.height)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .padding(6)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }
}
