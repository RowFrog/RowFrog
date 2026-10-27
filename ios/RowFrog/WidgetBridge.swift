import SwiftUI
import WidgetKit

/// Copies what the widget needs into the shared app group and asks it to
/// redraw: the home base, the saved clubs and their names, and the settings
/// (units, language, time format). Only when something changed, or for
/// widgets that load only after the app was used: every redraw makes each
/// widget load its forecast again.
enum WidgetBridge {
    static func publish(_ locations: LocationStore) {
        BackgroundLibrary.lakeByClub = locations.lakesByClub.mapValues(\.id)
        BackgroundLibrary.homeClubID = locations.homeID
        Task { await preparePictures(locations) }
        let shared = WidgetShared.defaults
        let saved = locations.saved
        var values: [String: Any] = [:]
        if !saved.isEmpty {
            values[WidgetShared.homeKey] = locations.homeID
            values[WidgetShared.savedKey] = saved.map(\.id)
            values[WidgetShared.namesKey] = Dictionary(saved.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        }
        values[WidgetShared.ownPlacesKey] = Dictionary(locations.ownPlaces.map { ($0.id, [$0.coordinate.lat, $0.coordinate.lon]) },
                                                       uniquingKeysWith: { a, _ in a })
        for key in AppSettings.Keys.all {
            values[key] = UserDefaults.standard.object(forKey: key)
        }
        // Sorted keys, so the same values always give the same bytes.
        let fingerprint = try? JSONSerialization.data(withJSONObject: values.compactMapValues(jsonSafe), options: [.sortedKeys])
        // Widgets that load only after the app was used get a new forecast as the
        // user leaves it, at most every 15 minutes.
        let lastReload = shared.object(forKey: reloadedKey) as? Date ?? .distantPast
        let due = AppSettings.shared.widgetUpdates == .appOpen && Date.now.timeIntervalSince(lastReload) > 15 * 60
        if let fingerprint, fingerprint == shared.data(forKey: fingerprintKey), !due { return }
        for (key, value) in values { shared.set(value, forKey: key) }
        for key in AppSettings.Keys.all where values[key] == nil { shared.removeObject(forKey: key) }
        if !saved.isEmpty, locations.homeID == nil { shared.removeObject(forKey: WidgetShared.homeKey) }
        shared.set(fingerprint, forKey: fingerprintKey)
        shared.set(Date.now, forKey: reloadedKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static let fingerprintKey = "RWWidgetPublished"
    private static let reloadedKey = "RWWidgetReloaded"

    /// Makes the small background pictures the widgets load, once per change:
    /// each saved club's picture (the one chosen for its widgets, else its club
    /// page's) and its lake's satellite picture, scaled to the largest widget
    /// and blurred once when the setting says so. Only for clubs whose widgets
    /// show a picture, or whose widget asked for one in its own settings.
    /// Nothing while no widget is on the home or lock screen.
    @MainActor
    static func preparePictures(_ locations: LocationStore) async {
        guard let folder = WidgetPictures.folder,
              let widgets = try? await WidgetCenter.shared.currentConfigurations(), !widgets.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = AppSettings.shared
        let shared = WidgetShared.defaults
        var changed = false
        for club in locations.saved {
            let background = settings.widgetBackground(for: club.id)
            func wanted(_ kind: WidgetPictures.Kind) -> Bool { shared.bool(forKey: WidgetPictures.wantedKey(club.id, kind)) }

            // The picture: a chosen one, else the club page's; the satellite choice goes through the satellite file.
            var choice = settings.background(for: .clubPages, clubID: club.id)
            if case let .picture(own) = background { choice = own }
            if background.usesPicture && background != .satellite || wanted(.picture) {
                let key = "\(choice.rawValue)|\(settings.blurWidgetPicture)"
                if key != shared.string(forKey: WidgetPictures.sourceKey(club.id, .picture)),
                   let image = BackgroundLibrary.image(for: choice, clubID: club.id) {
                    changed = write(image, to: WidgetPictures.file(club.id, .picture)) || changed
                    shared.set(key, forKey: WidgetPictures.sourceKey(club.id, .picture))
                } else if choice == .noPicture, let file = WidgetPictures.file(club.id, .picture),
                          FileManager.default.fileExists(atPath: file.path) {
                    try? FileManager.default.removeItem(at: file)
                    shared.removeObject(forKey: WidgetPictures.sourceKey(club.id, .picture))
                    changed = true
                }
            }

            if background == .satellite || wanted(.satellite), let lake = locations.lakesByClub[club.id]?.id {
                let store = SatellitePictureStore.shared
                await store.load(lake)
                guard let picture = store.pictures[lake], let shot = picture.clearest ?? picture.mostlyClear ?? picture.latest,
                      let url = store.url(lake, file: shot.image, date: shot.date) else { continue }
                let key = "\(url.absoluteString)|\(settings.blurWidgetPicture)"
                if key != shared.string(forKey: WidgetPictures.sourceKey(club.id, .satellite)), let image = await store.image(url) {
                    changed = write(image, to: WidgetPictures.file(club.id, .satellite)) || changed
                    shared.set(key, forKey: WidgetPictures.sourceKey(club.id, .satellite))
                }
            }
        }
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Scaled to the largest widget (about 1100 × 1150 pixels on a big iPhone),
    /// blurred when set, and saved as JPEG.
    private static func write(_ image: UIImage, to file: URL?) -> Bool {
        guard let file else { return false }
        var small = BackgroundLibrary.scaled(image, maxSide: 1200)
        if AppSettings.shared.blurWidgetPicture { small = BackgroundLibrary.blurred(small) }
        guard let data = small.jpegData(compressionQuality: 0.8) else { return false }
        return (try? data.write(to: file, options: .atomic)) != nil
    }

    /// A settings value as JSON can hold it; dates and data as text.
    private static func jsonSafe(_ value: Any) -> Any? {
        switch value {
        case let date as Date: return date.timeIntervalSince1970
        case let data as Data: return data.base64EncodedString()
        case let array as [Any]: return array.compactMap(jsonSafe)
        case let dictionary as [String: Any]: return dictionary.compactMapValues(jsonSafe)
        default: return JSONSerialization.isValidJSONObject([value]) ? value : String(describing: value)
        }
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
                // Settings > Widgets > Background: each choice on the medium widget.
                ForEach(backgrounds, id: \.0) { item in
                    caption("Background: " + item.1)
                    widget(snapshot, .systemMedium, sizes[1].1, focus: .conditions, background: item.0)
                }
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
            do { forecast = try await api.forecast(clubID: homeID).applyingUserLimits() } catch { failed = true }
            // `-RWWidgetRadar YES`: light rain on the radar from 30 minutes on, for the radar line.
            if UserDefaults.standard.bool(forKey: "RWWidgetRadar"), forecast != nil {
                let now = Date.now
                forecast?.radar = RainRadar(reference: now, steps: stride(from: 0, through: 120, by: 15).map {
                    RadarStep(time: now.addingTimeInterval(Double($0) * 60), mmPerHour: $0 >= 30 && $0 <= 90 ? 1.2 : 0)
                })
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.black.opacity(0.7))
    }

    private var backgrounds: [(WidgetBackground, String)] {
        [(.sky, "weather sky"), (.light, "rowing light colour"), (.picture(BackgroundLibrary.samples[3].choice), "picture"),
         (.satellite, "satellite"), (.system, "plain")]
    }

    private func widget(_ snapshot: RowingSnapshot, _ family: WidgetFamily, _ size: CGSize, focus: WidgetFocus = .hourly,
                        background: WidgetBackground = .sky) -> some View {
        RowingWidgetView(snapshot: snapshot, family: family, focus: focus, plain: background == .system)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(WidgetBackdrop(background: background, snapshot: snapshot,
                                       picture: WidgetBackgroundSwatch.picture(for: background, clubID: homeID)))
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
