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
        BackgroundLibrary.pointByClub = Dictionary(locations.saved.map { ($0.id, $0.launchPoint) }, uniquingKeysWith: { a, _ in a })
        Task { await withBackgroundTime("widget pictures") { await preparePictures(locations) } }
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
        values[WidgetShared.appLanguageKey] = AppSettings.deviceLanguage.rawValue
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

    /// Runs work that starts as the user leaves the app, and asks iOS for the
    /// time to finish it: without that, iOS paused the app in the middle of
    /// making the widget pictures (network, scaling, blur, files the widget
    /// reads too), and coming back to the app later was killed by iOS's
    /// watchdog (2026-10-29 and 2026-11-04, each time with a widget on the
    /// home screen). The diagnosis log tells when it starts and ends.
    @MainActor
    static func withBackgroundTime(_ name: String, _ work: () async -> Void) async {
        final class Holder { var id = UIBackgroundTaskIdentifier.invalid }
        let task = Holder()
        task.id = UIApplication.shared.beginBackgroundTask(withName: name) {
            DiagnosisLog.note("\(name) cut short by iOS")
            UIApplication.shared.endBackgroundTask(task.id)
            task.id = .invalid
        }
        DiagnosisLog.note("\(name) started")
        await work()
        DiagnosisLog.note("\(name) done")
        if task.id != .invalid {
            UIApplication.shared.endBackgroundTask(task.id)
            task.id = .invalid
        }
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
        guard let folder = WidgetPictures.folder, await hasWidgets() else { return }
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
                // "focus|": made once again after the update, so the club's place gets saved too.
                let key = "focus|\(choice.rawValue)|\(settings.blurWidgetPicture)"
                if key != shared.string(forKey: WidgetPictures.sourceKey(club.id, .picture)),
                   let image = BackgroundLibrary.image(for: choice, clubID: club.id) {
                    changed = write(image, to: WidgetPictures.file(club.id, .picture)) || changed
                    // The club page's satellite picture is the whole lake: the widget then needs the
                    // club's place as the satellite background has it, or it shows the lake's middle.
                    if let spot = BackgroundLibrary.focus(of: image) {
                        shared.set([Double(spot.x), Double(spot.y)], forKey: WidgetPictures.focusKey(club.id, .picture))
                    } else {
                        shared.removeObject(forKey: WidgetPictures.focusKey(club.id, .picture))
                    }
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
                // The whole picture and the club's place in it: each widget fills its width and shows
                // the club as near its middle as the picture allows, so a club at the end of a lake
                // sits at the top (owner 2026-11-12); a square cut lost it on the medium widget.
                let spot = BackgroundLibrary.place(of: club.launchPoint, in: picture.bbox)
                let key = "whole|\(url.absoluteString)|\(settings.blurWidgetPicture)|\(spot.map { "\($0.x),\($0.y)" } ?? "middle")"
                if key != shared.string(forKey: WidgetPictures.sourceKey(club.id, .satellite)), let image = await store.image(url) {
                    changed = write(image, to: WidgetPictures.file(club.id, .satellite)) || changed
                    if let spot { shared.set([Double(spot.x), Double(spot.y)], forKey: WidgetPictures.focusKey(club.id)) }
                    else { shared.removeObject(forKey: WidgetPictures.focusKey(club.id)) }
                    shared.set(key, forKey: WidgetPictures.sourceKey(club.id, .satellite))
                }
            }
        }
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Whether any Row Frog widget is on the home or lock screen.
    private static func hasWidgets() async -> Bool {
        await withCheckedContinuation { done in
            WidgetCenter.shared.getCurrentConfigurations { result in
                done.resume(returning: !((try? result.get()) ?? []).isEmpty)
            }
        }
    }

    /// Scaled to the largest widget (about 1100 × 1150 pixels on a big iPhone),
    /// blurred when set, and saved as JPEG.
    private static func write(_ image: UIImage, to file: URL?) -> Bool {
        guard let file else { return false }
        var small = BackgroundLibrary.scaled(image, maxSide: 1200)
        // Blurred on the processor, not the graphics chip: this runs as the app
        // goes into the background, where iOS does not let apps use the GPU.
        if AppSettings.shared.blurWidgetPicture { small = BackgroundLibrary.blurred(small, onProcessor: true) }
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
    /// The home base's lake picture and the club's place in it, as the widget's satellite background shows it.
    @State private var satellite: UIImage?
    @State private var satelliteFocus: UnitPoint?
    @State private var satelliteTried = false

    private let homeID = UserDefaults.standard.string(forKey: DefaultsKey.homeClub) ?? WidgetShared.defaultHomeID

    @Environment(\.colorScheme) private var colorScheme

    /// The widget sizes of the device it runs on (owner's C1, 14 Nov 2026), so the small iPhones'
    /// shots show whether a layout fits: small, medium, large and extra large (iPad only).
    private let sizes = WidgetSizes.forScreen(UIScreen.main.bounds.size)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if failed {
                    Text("The forecast could not be loaded.").foregroundStyle(.secondary)
                }
                let snapshot = galleryNight ? nightSnapshot
                    : RowingSnapshot(date: .now, clubName: "MRC 1880", isHome: true, forecast: forecast)
                caption(sizes.name)
                // Each size in its layouts (Edit Widget > Layout): fewer values first, the default.
                caption("Small: fewer values")
                widget(snapshot, .systemSmall, sizes.small)
                caption("Small: all values")
                widget(snapshot, .systemSmall, sizes.small, layout: .beside)
                caption("Medium: fewer values")
                widget(snapshot, .systemMedium, sizes.medium)
                caption("Medium: all values")
                widget(snapshot, .systemMedium, sizes.medium, layout: .beside)
                caption("Medium, good rowing times: fewer values")
                widget(snapshot, .systemMedium, sizes.medium, focus: .windows)
                caption("Medium, good rowing times: all values")
                widget(snapshot, .systemMedium, sizes.medium, focus: .windows, layout: .beside)
                caption("Large: fewer values")
                widget(snapshot, .systemLarge, sizes.large)
                caption("Large: all values in a row")
                widget(snapshot, .systemLarge, sizes.large, layout: .below)
                caption("Large: all values beside the light")
                widget(snapshot, .systemLarge, sizes.large, layout: .beside)
                caption("Small and medium without marks")
                widget(snapshot, .systemSmall, sizes.small, marks: false)
                widget(snapshot, .systemMedium, sizes.medium, focus: .windows, marks: false)
                caption("Extra large (iPad only)")
                let xl = sizes.extraLarge
                // Real size on the iPad; shrunk to the screen on an iPhone.
                let fit = UIDevice.current.userInterfaceIdiom == .pad ? 1 : min(1, sizes.medium.width / xl.width)
                widget(snapshot, .systemExtraLarge, xl)
                    .scaleEffect(fit, anchor: .topLeading)
                    .frame(width: xl.width * fit, height: xl.height * fit, alignment: .topLeading)
                caption("Lock screen")
                HStack(spacing: 12) {
                    accessory(snapshot, .accessoryCircular, CGSize(width: 76, height: 76))
                    accessory(snapshot, .accessoryRectangular, CGSize(width: 172, height: 76))
                }
                accessory(snapshot, .accessoryInline, CGSize(width: 300, height: 26))
                caption("Without a connection")
                widget(RowingSnapshot(date: .now, clubName: "MRC 1880", isHome: true, forecast: nil), .systemSmall, sizes.small)
                // Settings > Widgets > Background: each choice on the medium widget.
                ForEach(backgrounds, id: \.0) { item in
                    caption("Background: " + item.1)
                    widget(snapshot, .systemMedium, sizes.medium, focus: .conditions, background: item.0)
                }
            }
            .padding()
        }
        // A light or a dark home screen, as the device's mode (the widgets follow it too).
        .background(
            LinearGradient(colors: colorScheme == .dark
                               ? [Color(red: 0.09, green: 0.13, blue: 0.22), Color(red: 0.2, green: 0.12, blue: 0.24)]
                               : [Color(red: 0.62, green: 0.79, blue: 0.96), Color(red: 0.91, green: 0.85, blue: 0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: DefaultsKey.scrollPage), ready: (forecast != nil || failed) && satelliteTried))
        .task {
            await loadSatellite()
            satelliteTried = true
        }
        .task {
            do { forecast = try await api.forecast(clubID: homeID).applyingUserLimits() } catch { failed = true }
            // `-RWWidgetRadar YES`: light rain on the radar from 30 minutes on, for the radar line.
            if UserDefaults.standard.bool(forKey: DefaultsKey.widgetRadar), forecast != nil {
                let now = Date.now
                forecast?.radar = RainRadar(reference: now, steps: stride(from: 0, through: 120, by: 15).map {
                    RadarStep(time: now.addingTimeInterval(Double($0) * 60), mmPerHour: $0 >= 30 && $0 <= 90 ? 1.2 : 0)
                })
            }
        }
    }

    /// `-RWWidgetNight YES`: every widget as at 01:30 of the coming night, to show the
    /// night folded into one column up to sunrise. The forecast counts as fresh then.
    private var galleryNight: Bool { UserDefaults.standard.bool(forKey: "RWWidgetNight") }

    private var nightSnapshot: RowingSnapshot {
        let night = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 1, minute: 30), matchingPolicy: .nextTime) ?? .now
        var shifted = forecast
        shifted?.generatedAt = night.addingTimeInterval(-30 * 60)
        return RowingSnapshot(date: night, clubName: "MRC 1880", isHome: true, forecast: shifted)
    }

    /// The picture WidgetBridge.preparePictures writes for the satellite background, with the club's place.
    private func loadSatellite() async {
        guard let lake = (try? await api.lakes())?.first(where: { $0.clubs.contains { $0.id == homeID } }),
              let club = lake.clubs.first(where: { $0.id == homeID }) else { return }
        let store = SatellitePictureStore.shared
        await store.load(lake.id)
        guard let picture = store.pictures[lake.id], let shot = picture.clearest ?? picture.mostlyClear ?? picture.latest,
              let url = store.url(lake.id, file: shot.image, date: shot.date) else { return }
        satellite = await store.image(url)
        satelliteFocus = BackgroundLibrary.place(of: club.launchPoint, in: picture.bbox).map { UnitPoint(x: $0.x, y: $0.y) }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.primary.opacity(0.7))
    }

    private var backgrounds: [(WidgetBackground, String)] {
        [(.sky, "weather sky"), (.light, "rowing light colour"), (.picture(BackgroundLibrary.samples[3].choice), "picture"),
         (.satellite, "satellite"), (.system, "plain")]
    }

    private func widget(_ snapshot: RowingSnapshot, _ family: WidgetFamily, _ size: CGSize, focus: WidgetFocus = .hourly,
                        background: WidgetBackground = .sky, layout: WidgetLayout = .fewer, marks: Bool = true) -> some View {
        RowingWidgetView(snapshot: snapshot, family: family, focus: focus, plain: background == .system, layout: layout, marks: marks)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(WidgetBackdrop(background: background, snapshot: snapshot,
                                       picture: background == .satellite ? satellite : WidgetBackgroundSwatch.picture(for: background, clubID: homeID),
                                       focus: background == .satellite ? satelliteFocus : nil))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            // Which fit step the large and extra large widgets landed on (owner, 14 Nov 2026).
            .environment(\.showsWidgetFitStep, true)
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

/// Home Screen widget sizes in points by screen size, from Apple's Human Interface Guidelines
/// (Widgets > Specifications). Screens not in the table use the nearest smaller one.
struct WidgetSizes {
    let name: String
    let small: CGSize
    let medium: CGSize
    let large: CGSize
    /// iPad only; on an iPhone the iPad Pro 11" size, for the gallery's last row.
    let extraLarge: CGSize

    private static func phone(_ name: String, _ small: CGFloat, _ wide: CGFloat, _ tall: CGFloat) -> WidgetSizes {
        WidgetSizes(name: name, small: CGSize(width: small, height: small), medium: CGSize(width: wide, height: small),
                    large: CGSize(width: wide, height: tall), extraLarge: CGSize(width: 715, height: 342))
    }

    private static func pad(_ name: String, _ small: CGFloat, _ wide: CGFloat, _ extra: CGFloat) -> WidgetSizes {
        WidgetSizes(name: name, small: CGSize(width: small, height: small), medium: CGSize(width: wide, height: small),
                    large: CGSize(width: wide, height: wide), extraLarge: CGSize(width: extra, height: wide))
    }

    static func forScreen(_ screen: CGSize) -> WidgetSizes {
        let width = min(screen.width, screen.height), height = max(screen.width, screen.height)
        if UIDevice.current.userInterfaceIdiom == .pad {
            if width >= 1024 { return pad("Widget sizes: iPad 13\"", 170, 378.5, 795) }
            if width >= 820 { return pad("Widget sizes: iPad 11\"", 155, 342, 715) }
            return pad("Widget sizes: iPad mini", 141, 305.5, 634.5)
        }
        if width >= 428 { return phone("Widget sizes: iPhone Pro Max / Plus (\(Int(width)) pt)", 170, 364, 382) }
        if width >= 414 { return phone("Widget sizes: iPhone (414 pt)", 169, 360, 379) }
        // The 6.3" Pro (402 pt): the sizes the gallery used before (364 × 382 large).
        if width >= 402 { return phone("Widget sizes: iPhone Pro (\(Int(width)) pt)", 170, 364, 382) }
        if width >= 390 { return phone("Widget sizes: iPhone (\(Int(width)) pt)", 158, 338, 354) }
        if height >= 812 { return phone("Widget sizes: iPhone 13 mini (375 × 812 pt)", 155, 329, 345) }
        return phone("Widget sizes: iPhone SE (375 × 667 pt)", 148, 321, 324)
    }
}
