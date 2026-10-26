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

/// The medium widget with the chosen background and the home base's last
/// forecast the widgets loaded (none until a widget has run once).
private struct WidgetPreview: View {
    let background: WidgetBackground

    /// The home base's forecast as the widgets last saved it, for the samples.
    static var snapshot: RowingSnapshot {
        let shared = WidgetShared.defaults
        let home = shared.string(forKey: WidgetShared.homeKey) ?? WidgetShared.defaultHomeID
        let names = shared.dictionary(forKey: WidgetShared.namesKey) as? [String: String] ?? [:]
        let forecast = shared.data(forKey: WidgetShared.cacheKey(home)).flatMap { try? APIClient.decoder.decode(ClubForecast.self, from: $0) }
        return RowingSnapshot(date: .now, clubName: names[home] ?? "Row Frog", isHome: true, forecast: forecast?.applyingUserLimits())
    }

    var body: some View {
        let snapshot = Self.snapshot
        RowingWidgetView(snapshot: snapshot, family: .systemMedium, focus: .conditions, plain: background == .system)
            .padding(16)
            .frame(width: 338, height: 158)
            .background {
                WidgetBackdrop(background: background, snapshot: snapshot,
                               picture: WidgetBackgroundSwatch.picture(for: background, clubID: BackgroundLibrary.homeClubID))
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("Preview"))
    }
}
