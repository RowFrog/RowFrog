import SwiftUI
import WidgetKit

/// Settings > Widgets: what the widgets show behind their content, for all
/// widgets and per club, and how often they load. A widget can also have its own, in its edit menu.
struct WidgetSettingsView: View {
    let locations: LocationStore
    @Binding var path: [SettingsRoute]

    var body: some View {
        @Bindable var settings = AppSettings.shared
        ScrollViewReader { proxy in
            Form {
                Section {
                    WidgetPreview(background: settings.widgetBackground)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                .id("preview")

                Section {
                    ForEach(WidgetBackground.simple, id: \.self) { background in
                        Button { settings.widgetBackground = background } label: {
                            row(background, selected: settings.widgetBackground == background)
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink(value: SettingsRoute.picker(.widgets(nil))) {
                        row(pictureChoice(settings.widgetBackground), selected: isPicture(settings.widgetBackground), title: tr("Another picture"))
                    }
                } header: {
                    SectionTitle(tr("All widgets"), symbol: "rectangle.3.group")
                } footer: {
                    SectionFooter(tr("The weather sky changes with the weather and the time of day. Pictures are darkened at the bottom so the text stays readable."))
                }
                .surfaceRows()
                .id("all")

                Section {
                    Toggle(isOn: $settings.blurWidgetPicture) {
                        Label(tr("Blur the picture"), systemImage: "drop.halffull")
                    }
                } footer: {
                    SectionFooter(tr("For the club page picture, your own pictures and the satellite picture."))
                }
                .surfaceRows()
                .id("blur")

                if !locations.saved.isEmpty {
                    Section {
                        ForEach(locations.saved) { club in
                            clubRow(club)
                        }
                    } header: {
                        SectionTitle(tr("Single clubs"), symbol: "figure.rower")
                    } footer: {
                        SectionFooter(tr("A club's own background shows on all its widgets. To give one widget its own, touch and hold it on the home screen and choose Edit Widget."))
                    }
                    .surfaceRows()
                    .id("clubs")
                }

                Section {
                    Picker(selection: $settings.widgetUpdates) {
                        ForEach(WidgetUpdates.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label(tr("Widget updates"), systemImage: "apps.iphone")
                    }
                } header: {
                    SectionTitle(tr("Updates"), symbol: "arrow.triangle.2.circlepath")
                } footer: {
                    SectionFooter(tr("Row Frog itself does nothing in the background: iOS pauses it moments after you leave it, and it never follows your location. Only the widgets load a new forecast on their own. Less often saves battery and data, but a new official warning reaches the widgets later. Only after using the app: the widgets load once as you leave the app."))
                }
                .surfaceRows()
                .id("updates")
            }
            .scrollContentBackground(.hidden)
            .pageBackground(.settings)
            .navigationTitle(tr("Widgets"))
            .navigationBarTitleDisplayMode(.inline)
            .screenshotSections(["preview", "all", "blur", "clubs", "updates"], proxy: proxy)
        }
        // The widgets show the change when the user is back on the home screen.
        .onChange(of: settings.widgetBackground) { WidgetBridge.publish(locations) }
        .onChange(of: settings.clubWidgetBackgrounds) { WidgetBridge.publish(locations) }
        .onChange(of: settings.blurWidgetPicture) { WidgetBridge.publish(locations) }
    }

    private func row(_ background: WidgetBackground, selected: Bool, title: String? = nil) -> some View {
        HStack(spacing: 12) {
            WidgetBackgroundSwatch(background: background)
                .frame(width: 56, height: 30)
            Text(title ?? background.title)
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func isPicture(_ background: WidgetBackground) -> Bool {
        if case .picture = background { true } else { false }
    }

    /// The chosen picture, or the first sample to show what "another picture" means.
    private func pictureChoice(_ background: WidgetBackground) -> WidgetBackground {
        isPicture(background) ? background : .picture(BackgroundLibrary.samples[0].choice)
    }

    @ViewBuilder
    private func menuLabel(_ title: String, ticked: Bool) -> some View {
        if ticked { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func clubRow(_ club: Club) -> some View {
        let settings = AppSettings.shared
        let own = settings.clubWidgetBackgrounds[club.id]
        return Menu {
            Button {
                settings.clubWidgetBackgrounds[club.id] = nil
            } label: {
                menuLabel(tr("Same as all widgets"), ticked: own == nil)
            }
            ForEach(WidgetBackground.simple, id: \.self) { background in
                Button {
                    settings.clubWidgetBackgrounds[club.id] = background
                } label: {
                    menuLabel(background.title, ticked: own == background)
                }
            }
            Button(tr("Another picture") + "…") {
                path.append(.picker(.widgets(club.id)))
            }
        } label: {
            HStack(spacing: 12) {
                WidgetBackgroundSwatch(background: own ?? settings.widgetBackground, clubID: club.id)
                    .frame(width: 56, height: 30)
                    .opacity(own == nil ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(club.displayName).foregroundStyle(.primary)
                    Text(own?.title ?? tr("Same as all widgets"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }
}

/// A small sample of a widget background for the settings rows.
struct WidgetBackgroundSwatch: View {
    let background: WidgetBackground
    var clubID: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        WidgetBackdrop(background: background, snapshot: WidgetPreview.snapshot, picture: Self.picture(for: background, clubID: clubID))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
            .accessibilityHidden(true)
    }

    /// The picture a picture background shows, from the app's own pictures.
    static func picture(for background: WidgetBackground, clubID: String?) -> UIImage? {
        let settings = AppSettings.shared
        switch background {
        case .appPicture:
            let choice = settings.background(for: .clubPages, clubID: clubID)
            return BackgroundLibrary.image(for: choice, clubID: clubID, thumbnail: true)
                ?? BackgroundLibrary.image(for: BackgroundLibrary.samples[0].choice, thumbnail: true)
        case let .picture(choice): return BackgroundLibrary.image(for: choice, clubID: clubID, thumbnail: true)
        case .satellite: return BackgroundLibrary.image(for: .satellite, clubID: clubID, thumbnail: true)
        default: return nil
        }
    }
}

/// The widgets with the chosen background, one per page to swipe through
/// with dots under them: small, medium (conditions, good times), large and
/// the lock screen. They show the home base's last forecast the widgets
/// saved, or one the preview loads itself when no widget has run yet.
private struct WidgetPreview: View {
    let background: WidgetBackground
    @State private var loaded: ClubForecast?
    /// Why the preview's own load failed, shown under the widget instead of its name.
    @State private var failure: String?
    @State private var page = 1

    private static var homeID: String {
        WidgetShared.defaults.string(forKey: WidgetShared.homeKey) ?? WidgetShared.defaultHomeID
    }

    /// The home base's forecast as the widgets last saved it, for the samples;
    /// one the preview loaded itself wins, as it is newer.
    static var snapshot: RowingSnapshot { snapshot(loaded: nil) }

    private static func snapshot(loaded: ClubForecast?) -> RowingSnapshot {
        let shared = WidgetShared.defaults
        let names = shared.dictionary(forKey: WidgetShared.namesKey) as? [String: String] ?? [:]
        let saved = shared.data(forKey: WidgetShared.cacheKey(homeID)).flatMap { try? APIClient.decoder.decode(ClubForecast.self, from: $0) }
        return RowingSnapshot(date: .now, clubName: names[homeID] ?? "Row Frog", isHome: true, forecast: (loaded ?? saved)?.applyingUserLimits())
    }

    private struct Page {
        let title: String
        let family: WidgetFamily
        let size: CGSize
        var focus: WidgetFocus = .hourly
    }

    // Sizes on a 6.3" iPhone, in points, as in the widget gallery.
    private let pages = [
        Page(title: tr("Small"), family: .systemSmall, size: CGSize(width: 170, height: 170)),
        Page(title: tr("Medium"), family: .systemMedium, size: CGSize(width: 338, height: 158), focus: .conditions),
        Page(title: tr("Medium: good rowing times"), family: .systemMedium, size: CGSize(width: 338, height: 158), focus: .windows),
        Page(title: tr("Large"), family: .systemLarge, size: CGSize(width: 338, height: 354)),
        Page(title: tr("Lock screen"), family: .accessoryRectangular, size: CGSize(width: 172, height: 76)),
    ]

    /// Tall enough for the large widget at three quarters of its size.
    private static let height: CGFloat = 270

    var body: some View {
        let snapshot = Self.snapshot(loaded: loaded)
        VStack(spacing: 6) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    widget(pages[index], snapshot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: Self.height)
            Text(failure ?? pages[page].title)
                .font(.caption)
                .foregroundStyle(.secondary)
            dots
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Preview"))
        .accessibilityValue(pages[page].title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page = min(page + 1, pages.count - 1)
            case .decrement: page = max(page - 1, 0)
            @unknown default: break
            }
        }
        .task {
            // No widget has saved a forecast yet, or only one whose hours are over:
            // the preview loads the home base's itself.
            guard Self.snapshot.current == nil else { return }
            do {
                loaded = try await APIClient.fromBundle().forecast(clubID: Self.homeID)
                failure = nil
            } catch is CancellationError {
            } catch {
                #if DEBUG
                failure = tr("The forecast could not be loaded.") + " " + String(describing: error)
                #else
                failure = tr("The forecast could not be loaded.")
                #endif
            }
        }
    }

    @ViewBuilder
    private func widget(_ page: Page, _ snapshot: RowingSnapshot) -> some View {
        if page.family == .accessoryRectangular {
            HStack(spacing: 12) {
                RowingWidgetView(snapshot: snapshot, family: .accessoryCircular)
                    .frame(width: 76, height: 76)
                RowingWidgetView(snapshot: snapshot, family: .accessoryRectangular)
                    .frame(width: page.size.width, height: page.size.height)
            }
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .padding(10)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        } else {
            let scale = min(1, Self.height / (page.size.height + 16))
            RowingWidgetView(snapshot: snapshot, family: page.family, focus: page.focus, plain: background == .system)
                .padding(16)
                .frame(width: page.size.width, height: page.size.height)
                .background {
                    WidgetBackdrop(background: background, snapshot: snapshot,
                                   picture: WidgetBackgroundSwatch.picture(for: background, clubID: BackgroundLibrary.homeClubID))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .scaleEffect(scale)
                .frame(width: page.size.width * scale, height: page.size.height * scale)
        }
    }

    /// Which widget shows and how many there are; a tap on a dot goes there.
    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: index == page ? 8 : 6, height: index == page ? 8 : 6)
                    .onTapGesture { withAnimation { page = index } }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: page)
    }
}
