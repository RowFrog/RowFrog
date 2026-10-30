import PhotosUI
import SwiftUI
import TipKit

/// Pages pushed inside the settings.
enum SettingsRoute: Hashable {
    case appearance
    case clubPages
    case language
    case data
    case help
    case about
    case developer
    case backgrounds
    case widgets
    case limits
    case boat(String)
    case picker(BackgroundTarget)
    case safety
    case impressum
    case privacy

    /// Screenshot hook: `-RWSettingsPage appearance`, `clubpages`, `language`, `data`, `help`,
    /// `about`, `developer`, `backgrounds`, `widgets`, `limits`, `boat:<id>`, `safety`, `impressum`,
    /// `privacy`, `picker-all`, `picker-page:list` or `picker-club:<id>` opens that page, with the
    /// pages on the way to it. `-RWSettingsSearch <text>` fills the search field.
    static func fromLaunchArguments() -> [SettingsRoute] {
        guard let page = UserDefaults.standard.string(forKey: "RWSettingsPage") else { return [] }
        let backgrounds: [SettingsRoute] = [.clubPages, .backgrounds]
        switch page {
        case "appearance": return [.appearance]
        case "clubpages": return [.clubPages]
        case "language": return [.language]
        case "data": return [.data]
        case "help": return [.help]
        case "about": return [.about]
        case "developer": return [.developer]
        case "backgrounds": return backgrounds
        case "widgets": return [.widgets]
        case "safety": return [.about, .safety]
        case "impressum": return [.about, .impressum]
        case "privacy": return [.about, .privacy]
        case "limits": return [.limits]
        case "picker-all": return backgrounds + [.picker(.all)]
        default: break
        }
        if page.hasPrefix("boat:") { return [.limits, .boat(String(page.dropFirst("boat:".count)))] }
        if page.hasPrefix("picker-page:"), let kind = PageKind(rawValue: String(page.dropFirst("picker-page:".count))) {
            return backgrounds + [.picker(.page(kind))]
        }
        if page.hasPrefix("picker-club:") {
            return backgrounds + [.picker(.club(String(page.dropFirst("picker-club:".count))))]
        }
        return []
    }
}

/// What a background picture is picked for.
enum BackgroundTarget: Hashable {
    case all
    case page(PageKind)
    case club(String)
    /// The widgets' picture: for all widgets (nil) or one club's.
    case widgets(String?)
}

/// The settings, opened with the cog, as in the iOS Settings app: a short list of topics, each
/// opening its own page, with the boat for the rowing light right at the top
/// and a search field at the bottom.
struct SettingsView: View {
    let locations: LocationStore
    @State private var path: [SettingsRoute]
    @State private var search = UserDefaults.standard.string(forKey: "RWSettingsSearch") ?? ""
    @FocusState private var searching: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `path` opens a page at once, as Boats and limits from a club page's boat menu.
    init(locations: LocationStore, path: [SettingsRoute] = []) {
        self.locations = locations
        _path = State(initialValue: path.isEmpty ? SettingsRoute.fromLaunchArguments() : path)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                if search.trimmingCharacters(in: .whitespaces).isEmpty {
                    topics
                } else {
                    results
                }
            }
            .scrollContentBackground(.hidden)
            .pageBackground(.settings)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SettingsSearchField(text: $search, focused: $searching)
            }
            .navigationTitle(tr("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .appearance:
                    AppearanceSettingsView()
                case .clubPages:
                    ClubPagesSettingsView()
                case .language:
                    LanguageSettingsView()
                case .data:
                    DataSettingsView()
                case .help:
                    HelpSettingsView(locations: locations)
                case .about:
                    AboutSettingsView()
                case .developer:
                    DeveloperSettingsView()
                case .backgrounds:
                    BackgroundSettingsView(locations: locations)
                case .widgets:
                    WidgetSettingsView(locations: locations, path: $path)
                case .limits:
                    RowingLimitsView(path: $path)
                case let .boat(id):
                    BoatLimitsView(boatID: id)
                case let .picker(target):
                    BackgroundPickerView(target: target, locations: locations)
                case .safety:
                    SafetyNoticeSettingsView()
                case .impressum:
                    ImpressumView()
                case .privacy:
                    PrivacySummaryView()
                }
            }
        }
    }

    @ViewBuilder
    private var topics: some View {
        @Bindable var settings = AppSettings.shared
        Section {
            let boats = Picker(selection: $settings.boatID) {
                ForEach(settings.boats) { boat in
                    Text(boat.title).tag(boat.id)
                }
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "figure.rower", color: .green)
                    Text(tr("Rowing light for"))
                }
            }
            if typeSize.isAccessibilitySize {
                // The boat under the name, as in the rows below; beside it, it was cut short.
                Menu { boats } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: "figure.rower", color: .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Rowing light for")).foregroundStyle(.primary)
                            Text(settings.boats.first { $0.id == settings.boatID }?.title ?? "")
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(Color.accentColor)
                    }
                    .contentShape(Rectangle())
                }
            } else {
                boats
            }
            topic(.boats, value: limitsSummary)
        } footer: {
            SectionFooter(tr("The boat the rowing light is worked out for, on every club page and in the widgets."))
        }
        .surfaceRows()

        Section {
            topic(.appearance, value: settings.appearance.title)
            topic(.clubPages, value: settings.allPagesBackground.title)
            topic(.widgets, value: settings.widgetUpdates.title)
        }
        .surfaceRows()

        Section {
            topic(.language, value: "\(settings.resolvedLanguage.title) · \(settings.temperatureUnit.symbol)")
            topic(.data, value: DataSaver.shared.saving ? tr("Saving data") : nil)
        }
        .surfaceRows()

        Section {
            topic(.help)
            topic(.about, value: SettingsTopic.version)
            if settings.developerOptions {
                topic(.developer)
            }
        }
        .surfaceRows()
    }

    private func topic(_ topic: SettingsTopic, value: String? = nil) -> some View {
        NavigationLink(value: topic.route) {
            SettingsRow(topic: topic, value: value)
        }
    }

    private var limitsSummary: String? {
        let changed = AppSettings.shared.limits.custom.count
        return changed == 0 ? nil : tr("%@ changed", "\(changed)")
    }

    /// Every setting whose name, or its page's, has the typed words, in both languages.
    @ViewBuilder
    private var results: some View {
        let found = SettingsSearch.entries(developer: AppSettings.shared.developerOptions)
            .filter { $0.matches(search) }
        if found.isEmpty {
            Section {
                Text(tr("No settings found for “%@”.", search.trimmingCharacters(in: .whitespaces)))
                    .foregroundStyle(.secondary)
            }
            .surfaceRows()
        } else {
            Section {
                ForEach(found) { entry in
                    Button {
                        searching = false
                        path = entry.path
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(symbol: entry.topic.symbol, color: entry.topic.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr(entry.title)).foregroundStyle(Color.primary)
                                Text(entry.topic.title)
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                }
            }
            .surfaceRows()
        }
    }
}

/// The topics on the first settings page, each with its own page.
enum SettingsTopic: CaseIterable {
    case boats, appearance, clubPages, widgets, language, data, help, about, developer

    var title: String {
        switch self {
        case .boats: tr("Boats and limits")
        case .appearance: tr("Appearance")
        case .clubPages: tr("Club pages")
        case .widgets: tr("Widgets")
        case .language: tr("Language and units")
        case .data: tr("Battery and data")
        case .help: tr("Help")
        case .about: tr("About")
        case .developer: tr("Developer")
        }
    }

    var symbol: String {
        switch self {
        case .boats: "slider.horizontal.3"
        case .appearance: "circle.lefthalf.filled"
        case .clubPages: "rectangle.stack"
        case .widgets: "rectangle.3.group"
        case .language: "globe"
        case .data: "battery.75percent"
        case .help: "questionmark"
        case .about: "info"
        case .developer: "hammer"
        }
    }

    var color: Color {
        switch self {
        case .boats: .teal
        case .appearance: .blue
        case .clubPages: .indigo
        case .widgets: .orange
        case .language: .gray
        case .data: .green
        case .help: .blue
        case .about: .gray
        case .developer: .brown
        }
    }

    var route: SettingsRoute {
        switch self {
        case .boats: .limits
        case .appearance: .appearance
        case .clubPages: .clubPages
        case .widgets: .widgets
        case .language: .language
        case .data: .data
        case .help: .help
        case .about: .about
        case .developer: .developer
        }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }
}

/// A white symbol on a coloured square, as in the iOS Settings app.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

private struct SettingsRow: View {
    let topic: SettingsTopic
    let value: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At the accessibility text sizes the value goes under the name, as in
        // iOS Settings; side by side, both were cut short.
        let stacked = typeSize.isAccessibilitySize
        HStack(spacing: 12) {
            SettingsIcon(symbol: topic.symbol, color: topic.color)
            (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 8))) {
                Text(topic.title)
                if !stacked { Spacer(minLength: 0) }
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(stacked ? nil : 1)
                }
            }
            if stacked { Spacer(minLength: 0) }
        }
    }
}

/// The search field at the bottom of the first settings page, where iOS has it.
private struct SettingsSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(tr("Search"), text: $text)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel(tr("Clear"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glass(in: Capsule())
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

/// What the settings search finds: every setting, with the pages to open for it.
struct SettingsSearch: Identifiable {
    /// English, shown through `tr`.
    let title: String
    let topic: SettingsTopic
    var path: [SettingsRoute]
    /// More words to find it by, in English and German.
    var words: [String] = []

    var id: String { title + topic.title }

    init(_ title: String, _ topic: SettingsTopic, path: [SettingsRoute]? = nil, words: [String] = []) {
        self.title = title
        self.topic = topic
        self.path = path ?? [topic.route]
        self.words = words
    }

    func matches(_ query: String) -> Bool {
        let parts = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return false }
        let haystack = ([title, German.table[title] ?? "", topic.title] + words).joined(separator: " ")
        return parts.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    static func entries(developer: Bool) -> [SettingsSearch] {
        var all = [
            SettingsSearch("Rowing light for", .boats, path: [], words: ["boat", "Boot", "Ampel"]),
            SettingsSearch("Your boat", .boats, words: ["small", "big", "klein", "groß", "Boot"]),
            SettingsSearch("My boats", .boats, words: ["Meine Boote", "gig", "add", "hinzufügen"]),
            SettingsSearch("Fine-tune the limits", .boats, words: ["limit", "Grenze", "wind", "gusts", "Böen", "waves", "Wellen", "water temperature", "Wassertemperatur"]),
            SettingsSearch("Lake map colours", .boats, words: ["lake view", "Seeansicht", "route", "Karte"]),
            SettingsSearch("Appearance", .appearance, words: ["light", "dark", "hell", "dunkel", "mode", "Modus"]),
            SettingsSearch("App icon", .appearance, words: ["App-Symbol", "home screen", "Home-Bildschirm"]),
            SettingsSearch("Order of the club page cards", .clubPages, words: ["arrange", "anordnen", "Reihenfolge", "Karten"]),
            SettingsSearch("Background pictures", .clubPages, path: [.clubPages, .backgrounds], words: ["photo", "Foto", "Bild", "Hintergrund"]),
            SettingsSearch("In the tiles", .clubPages, path: [.clubPages, .backgrounds], words: ["tiles", "Kacheln", "frosted", "blur", "unscharf", "solid"]),
            SettingsSearch("Open places in", .clubPages, words: ["Apple Maps", "Apple Karten", "Google Maps", "map app", "Karten-App", "directions", "Route"]),
            SettingsSearch("Maps start", .clubPages, words: ["map zoom", "Kartenzoom", "weather map", "Wetterkarte", "close", "nah", "wide", "weit"]),
            SettingsSearch("Widget background", .widgets, words: ["sky", "Himmel", "picture", "Bild", "satellite", "Satellit"]),
            SettingsSearch("Widget updates", .widgets, words: ["refresh", "aktualisieren", "battery", "Akku"]),
            SettingsSearch("Language", .language, words: ["Sprache", "English", "Deutsch", "German", "Englisch"]),
            SettingsSearch("Air and water temperature", .language, words: ["unit", "Einheit", "Celsius", "Fahrenheit"]),
            SettingsSearch("Wind and gusts", .language, words: ["unit", "Einheit", "km/h", "knots", "Knoten", "Beaufort", "m/s"]),
            SettingsSearch("Waves", .language, words: ["unit", "Einheit", "cm"]),
            SettingsSearch("Precipitation", .language, words: ["unit", "Einheit", "mm", "Regen", "rain", "snow", "Schnee", "hail", "Hagel"]),
            SettingsSearch("Visibility and distances", .language, words: ["unit", "Einheit", "km", "miles", "Meilen"]),
            SettingsSearch("Air pressure", .language, words: ["unit", "Einheit", "hPa", "Luftdruck"]),
            SettingsSearch("Time", .language, words: ["Uhrzeit", "12", "24", "format"]),
            SettingsSearch("Date", .language, words: ["Datum", "format"]),
            SettingsSearch("Save mobile data", .data, words: ["Low Data Mode", "Datensparmodus", "satellite", "radar"]),
            SettingsSearch("Battery", .data, words: ["Akku", "Low Power Mode", "Stromsparmodus", "background", "Hintergrund"]),
            SettingsSearch("Show the tour again", .help, words: ["tutorial", "Einführung", "tips", "Tipps"]),
            SettingsSearch("Show the tips again", .help, words: ["Tipps", "hints", "Hinweise"]),
            SettingsSearch("Legend: what the symbols mean", .help, words: ["Legende", "symbols", "Symbole"]),
            SettingsSearch("Version", .about),
            SettingsSearch("Safety notice", .about, path: [.about, .safety], words: ["Sicherheit", "disclaimer"]),
            SettingsSearch("Privacy", .about, path: [.about, .privacy], words: ["Datenschutz"]),
            SettingsSearch("Legal notice", .about, path: [.about, .impressum], words: ["Impressum", "imprint"]),
            SettingsSearch("Reset to factory settings", .about, words: ["reset", "zurücksetzen", "Werkseinstellungen"]),
        ]
        // The iPad has no Landscape setting.
        if !Orientation.isPad, let appearance = all.firstIndex(where: { $0.title == "Appearance" }) {
            all.insert(SettingsSearch("Landscape", .appearance, words: ["Querformat", "rotate", "drehen", "columns", "Spalten"]), at: appearance + 1)
        }
        if developer {
            all.append(SettingsSearch("Developer options", .developer, words: ["Entwickler", "weather model", "Wettermodell"]))
        }
        return all
    }
}

/// Settings > Appearance: light or dark, landscape and the app icon.
private struct AppearanceSettingsView: View {
    @State private var appIcon = AppIcons.current
    @State private var showAppIconTip = false
    private let appIconTip = AppIconTip()

    var body: some View {
        @Bindable var settings = AppSettings.shared
        ScrollViewReader { proxy in
            Form {
                Section {
                    AppearancePicker(selection: $settings.appearance)
                } footer: {
                    SectionFooter(tr("Dark uses less battery on iPhones with an OLED screen, which most models since the iPhone X have."))
                }
                .surfaceRows()
                .id("appearance")

                if !Orientation.isPad {
                    Section {
                        Toggle(isOn: $settings.allowsLandscape) {
                            Label(tr("Landscape"), systemImage: "rectangle.landscape.rotate")
                        }
                    } footer: {
                        SectionFooter(tr("On: the app turns with the phone and shows the cards in two columns. Off: it stays upright."))
                    }
                    .surfaceRows()
                    .id("landscape")
                }

                Section {
                    if showAppIconTip {
                        TipView(appIconTip)
                    }
                    AppIconPicker(selected: $appIcon)
                } header: {
                    SectionTitle(tr("App icon"), symbol: "app.badge")
                } footer: {
                    SectionFooter(tr("The icon on your home screen. iOS asks you to confirm the change."))
                }
                .surfaceRows()
                .id("appicon")
            }
            .scrollContentBackground(.hidden)
            .pageBackground(.settings)
            .navigationTitle(tr("Appearance"))
            .navigationBarTitleDisplayMode(.inline)
            .tipVisibility(appIconTip, $showAppIconTip)
            .onAppear { appIcon = AppIcons.current }
            .screenshotSections(["appearance", "landscape", "appicon"], proxy: proxy)
        }
    }
}

/// Settings > Club pages: the order of the cards and the background pictures.
private struct ClubPagesSettingsView: View {
    @State private var arrangingPages = false

    var body: some View {
        @Bindable var settings = AppSettings.shared
        Form {
            Section {
                Button { arrangingPages = true } label: {
                    Label(tr("Order of the club page cards"), systemImage: "arrow.up.arrow.down")
                }
            } footer: {
                SectionFooter(tr("The order set here is for all clubs. A club can have its own from \"Arrange this page\" at the end of its page."))
            }
            .surfaceRows()

            Section {
                NavigationLink(value: SettingsRoute.backgrounds) {
                    HStack(spacing: 12) {
                        BackgroundThumbnail(choice: settings.allPagesBackground, width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Background pictures"))
                            Text(backgroundSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                SectionFooter(tr("Pictures for all pages, single pages or single clubs, and how the tiles look over them."))
            }
            .surfaceRows()

            Section {
                LabeledContent(tr("Maps start")) {
                    Picker(tr("Maps start"), selection: $settings.mapStartZoom) {
                        ForEach(MapStartZoom.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } header: {
                SectionTitle(tr("Weather maps"), symbol: "map")
            } footer: {
                SectionFooter(mapZoomFooter)
            }
            .surfaceRows()

            Section {
                Picker(tr("Open places in"), selection: $settings.mapApp) {
                    ForEach(MapApp.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                SectionTitle(tr("Map app"), symbol: "map.circle")
            } footer: {
                SectionFooter(tr("Opens the club's directions and launch point from the Launch point card. Google Maps opens in its app when it is installed, else in the browser."))
            }
            .surfaceRows()
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .navigationTitle(tr("Club pages"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $arrangingPages) { ArrangePageSheet(club: nil) }
    }

    /// The spans the maps open with, e.g. "50 km around the club; rain and lightning 120 km."
    private var mapZoomFooter: String {
        let local = Format.distance(WeatherMapLayer.wind.startSpanKm * 1000)
        let wide = Format.distance(WeatherMapLayer.rain.startSpanKm * 1000)
        return tr("The weather maps in the detail views open %@ across around the club, rain and lightning %@. Zooming out loads more.", local, wide)
    }

    private var backgroundSummary: String {
        let settings = AppSettings.shared
        let own = settings.pageBackgrounds.count + settings.clubBackgrounds.count
        let all = tr("All pages: %@", settings.allPagesBackground.title)
        return own == 0 ? all : all + " · " + tr("%@ with their own", String(own))
    }
}

/// Settings > Language and units: language, units, date and time.
private struct LanguageSettingsView: View {
    var body: some View {
        @Bindable var settings = AppSettings.shared
        ScrollViewReader { proxy in
            Form {
                Section {
                    Picker(selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    SectionTitle(tr("Language"), symbol: "globe")
                }
                .surfaceRows()
                .id("language")

                Section {
                    UnitRow(condition: .temperature, title: tr("Air and water temperature"), selection: $settings.temperatureUnit)
                    UnitRow(condition: .wind, title: tr("Wind and gusts"), selection: $settings.windUnit)
                    UnitRow(condition: .waves, title: tr("Waves"), selection: $settings.waveUnit)
                    UnitRow(condition: .precipitation, title: tr("Precipitation"), selection: $settings.rainUnit)
                    UnitRow(condition: .visibility, title: tr("Visibility and distances"), selection: $settings.distanceUnit)
                    UnitRow(condition: .pressure, title: tr("Air pressure"), selection: $settings.pressureUnit)
                } header: {
                    SectionTitle(tr("Units"), symbol: "ruler")
                } footer: {
                    SectionFooter(tr("Cloud cover stays in percent."))
                }
                .surfaceRows()
                .id("units")

                Section {
                    FormatRow(title: tr("Time"), symbol: "clock", selection: $settings.timeFormat) { format in
                        format.string(from: Self.sampleTime)
                    }
                    FormatRow(title: tr("Date"), symbol: "calendar", selection: $settings.dateFormat) { format in
                        format.string(from: .now, locale: AppSettings.shared.locale)
                    }
                } header: {
                    SectionTitle(tr("Date and time"), symbol: "calendar.badge.clock")
                } footer: {
                    SectionFooter(tr("Device follows the phone's settings. Today and tomorrow are always written as words."))
                }
                .surfaceRows()
                .id("datetime")
            }
            .scrollContentBackground(.hidden)
            .pageBackground(.settings)
            .navigationTitle(tr("Language and units"))
            .navigationBarTitleDisplayMode(.inline)
            .screenshotSections(["language", "units", "datetime"], proxy: proxy)
        }
    }

    /// 14:30 today, to show each time format.
    private static var sampleTime: Date {
        Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: .now) ?? .now
    }
}

/// Settings > Battery and data: saving mobile data, and what runs in the background.
private struct DataSettingsView: View {
    @State private var showSaveDataTip = false
    private let saveDataTip = SaveDataTip()

    var body: some View {
        @Bindable var settings = AppSettings.shared
        Form {
            Section {
                if showSaveDataTip {
                    TipView(saveDataTip)
                }
                Toggle(isOn: $settings.saveMobileData) {
                    Label(tr("Save mobile data"), systemImage: "antenna.radiowaves.left.and.right")
                }
                if DataSaver.shared.saving {
                    Label(DataSaver.shared.lowDataModeOn ? tr("Low Data Mode is on: the app is saving data now.") : tr("On mobile data: the app is saving data now."),
                          systemImage: "leaf")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SectionTitle(tr("Data use"), symbol: "arrow.up.arrow.down.circle")
            } footer: {
                SectionFooter(tr("On mobile data, satellite pictures load only when you tap them, the radar map shows half-hour steps and the rain radar updates every 15 minutes. Forecasts and warnings always load. In iOS Low Data Mode the app always saves data, also on Wi-Fi."))
            }
            .surfaceRows()

            Section {
                NavigationLink(value: SettingsRoute.widgets) {
                    LabeledContent {
                        Text(settings.widgetUpdates.title)
                    } label: {
                        Label(tr("Widget updates"), systemImage: "apps.iphone")
                    }
                }
            } header: {
                SectionTitle(tr("Battery"), symbol: "battery.75percent")
            } footer: {
                SectionFooter(tr("Row Frog itself does nothing in the background: iOS pauses it moments after you leave it, and it never follows your location. Only the widgets load a new forecast on their own. Dark appearance and club pages without a picture use less battery too; in Low Power Mode the tiles are always solid."))
            }
            .surfaceRows()
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .navigationTitle(tr("Battery and data"))
        .navigationBarTitleDisplayMode(.inline)
        .tipVisibility(saveDataTip, $showSaveDataTip)
        .onChange(of: settings.saveMobileData) { if settings.saveMobileData { saveDataTip.invalidate(reason: .actionPerformed) } }
    }
}

/// Settings > Help: the tour and the legend.
private struct HelpSettingsView: View {
    let locations: LocationStore
    @State private var showingTour = false
    @State private var showingLegend = false
    @State private var tipsComingBack = Tutorial.tipsComingBack

    var body: some View {
        Form {
            Section {
                Button {
                    Tutorial.replay()
                    showingTour = true
                } label: {
                    Label(tr("Show the tour again"), systemImage: "questionmark.circle")
                }
                Button {
                    Tutorial.replayTips()
                    tipsComingBack = true
                } label: {
                    Label(tipsComingBack ? tr("Tips come back next time you open the app") : tr("Show the tips again"),
                          systemImage: tipsComingBack ? "checkmark.circle" : "lightbulb")
                }
                .disabled(tipsComingBack)
                Button { showingLegend = true } label: {
                    Label(tr("Legend: what the symbols mean"), systemImage: "info.circle")
                }
            } footer: {
                SectionFooter(tr("The one-time tips come back the next time you open the app."))
            }
            .surfaceRows()
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .navigationTitle(tr("Help"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLegend) { LegendSheet(part: .all) }
        .fullScreenCover(isPresented: $showingTour) {
            TutorialView(locations: locations, reload: {}) {
                Tutorial.markSeen()
                showingTour = false
            }
        }
    }
}

/// Settings > About: the version (seven taps show the developer options),
/// the legal texts and the factory reset.
private struct AboutSettingsView: View {
    @State private var confirmingReset = false
    @State private var showResetTip = false
    private let resetTip = FactoryResetTip()

    var body: some View {
        @Bindable var settings = AppSettings.shared
        Form {
            Section {
                LabeledContent(tr("Version"), value: SettingsTopic.version)
                    .contentShape(Rectangle())
                    // Hidden: seven taps show the developer options.
                    .onTapGesture(count: 7) { settings.developerOptions = true }
            }
            .surfaceRows()

            Section {
                NavigationLink(value: SettingsRoute.safety) {
                    Label(tr("Safety notice"), systemImage: "exclamationmark.shield")
                }
                NavigationLink(value: SettingsRoute.privacy) {
                    Label(tr("Privacy"), systemImage: "hand.raised")
                }
                NavigationLink(value: SettingsRoute.impressum) {
                    Label(tr("Legal notice"), systemImage: "building.columns")
                }
            } header: {
                SectionTitle(tr("Legal"), symbol: "doc.text")
            }
            .surfaceRows()

            Section {
                if showResetTip {
                    TipView(resetTip)
                }
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Label(tr("Reset to factory settings"), systemImage: "arrow.counterclockwise")
                }
            } footer: {
                SectionFooter(tr("Appearance, units, language, background pictures and the app icon go back to how the app came. Small boats are ticked again and every boat's limits go back to the app's. Your locations, home base and boats stay."))
            }
            .surfaceRows()
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .navigationTitle(tr("About"))
        .navigationBarTitleDisplayMode(.inline)
        .tipVisibility(resetTip, $showResetTip)
        .confirmationDialog(tr("Reset all settings?"), isPresented: $confirmingReset, titleVisibility: .visible) {
            Button(tr("Reset"), role: .destructive) {
                AppSettings.shared.resetToFactorySettings()
                Task { try? await AppIcons.select(AppIcons.primary) }
            }
            Button(tr("Cancel"), role: .cancel) {}
        } message: {
            Text(tr("Appearance, units, language, background pictures, the order of the club page cards and the app icon go back to how the app came, and your own pictures are deleted from the app. Small boats are ticked again, the lake map is coloured for small boats, and every limit you changed goes back to the app's. Your locations, home base and boats stay."))
        }
    }
}

/// Settings > Developer, shown after seven taps on the version.
private struct DeveloperSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = AppSettings.shared
        Form {
            Section {
                Toggle(isOn: $settings.developerOptions) {
                    Label(tr("Developer options"), systemImage: "hammer")
                }
                Button {
                    settings.pickedModels = [:]
                } label: {
                    Label(tr("All clubs back to the automatic model"), systemImage: "arrow.uturn.backward")
                }
                .disabled(settings.pickedModels.isEmpty)
            } footer: {
                SectionFooter(tr("Test: on a confirmed club's page, tap the forecast line at the bottom to pick another weather model. Switched off, every club uses the automatic model again. Tap the version seven times to show this again."))
            }
            .surfaceRows()
            Section {
                Picker(tr("Club page columns"), selection: $settings.columnFill) {
                    ForEach(ColumnFill.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                SectionFooter(tr("On wide screens, how the two columns of a club page end level. Fold the 48 hours: the table shows 24 hours until opened. Always 48 hours: the whole table, so columns may end further apart. Switching the developer options off goes back to folding."))
            }
            .surfaceRows()
            Section {
                ShareLink(item: DiagnosisLog.url) {
                    Label(tr("Share diagnosis log"), systemImage: "stethoscope")
                }
                .disabled(!DiagnosisLog.exists)
            } footer: {
                SectionFooter(tr("If iOS closed Row Frog as you came back to it, share this log with the developers. It lists the last steps in and out of the app, with times, and iOS's own reports. It stays on the phone until you share it."))
            }
            .surfaceRows()
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .navigationTitle(tr("Developer"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.developerOptions) { if !settings.developerOptions { dismiss() } }
    }
}

/// All app icons in a grid; the one on the home screen is ticked.
private struct AppIconPicker: View {
    @Binding var selected: AppIconOption
    @State private var failed = false

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(AppIcons.all) { option in
                Button {
                    Task {
                        do {
                            try await AppIcons.select(option)
                            selected = AppIcons.current
                        } catch {
                            failed = true
                        }
                    }
                } label: {
                    VStack(spacing: 6) {
                        option.previewImage
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13.5, style: .continuous)
                                    .strokeBorder(option == selected ? Color.accentColor : Color.secondary.opacity(0.25),
                                                  lineWidth: option == selected ? 3 : 0.5)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if option == selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .symbolRenderingMode(.multicolor)
                                        .font(.title3)
                                        .background(Circle().fill(.background))
                                        .offset(x: 6, y: 6)
                                }
                            }
                        Text(option.title)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(option == selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
        .alert(tr("The icon could not be changed."), isPresented: $failed) {
            Button(tr("OK"), role: .cancel) {}
        }
    }
}

/// Device, light and dark, as on the iPhone's display settings.
private struct AppearancePicker: View {
    @Binding var selection: Appearance

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Appearance.allCases) { option in
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 8) {
                        preview(option)
                        Text(option.title).font(.subheadline)
                        Image(systemName: selection == option ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selection == option ? Color.accentColor : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }

    /// A small phone screen in the option's colours, with its symbol.
    private func preview(_ option: Appearance) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        return ZStack {
            switch option {
            case .light: shape.fill(Color(white: 0.95))
            case .dark: shape.fill(Color(white: 0.12))
            case .device:
                shape.fill(LinearGradient(stops: [.init(color: Color(white: 0.95), location: 0.5), .init(color: Color(white: 0.12), location: 0.5)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            Image(systemName: option.symbol)
                .font(.title2)
                .foregroundStyle(option == .dark ? Color.yellow : option == .light ? Color.orange : Color.accentColor)
                .padding(6)
                .background(option == .device ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear), in: Circle())
        }
        .frame(width: 58, height: 92)
        .overlay(shape.stroke(Color.secondary.opacity(0.4)))
    }
}

/// A value's icon and name, and a menu with the units it can be shown in.
struct UnitRow<Unit: Hashable & Identifiable & CaseIterable>: View where Unit.AllCases: RandomAccessCollection, Unit: UnitDisplay {
    let condition: Condition
    let title: String
    @Binding var selection: Unit

    var body: some View {
        // The whole row opens the menu, as a picker row in iOS Settings; only
        // the unit at the end did before, so a tap on the row seemed to do nothing.
        Menu {
            Picker(title, selection: $selection) {
                ForEach(Unit.allCases) { unit in
                    Text("\(unit.symbol) · \(unit.title)").tag(unit)
                }
            }
        } label: {
            HStack {
                Label {
                    Text(title).foregroundStyle(.primary)
                } icon: {
                    ConditionIcon(condition: condition).foregroundStyle(Color.accentColor)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(selection.symbol).monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(selection.title)
    }
}

/// A time or date format: its name and icon, the current choice as an example,
/// and a menu with every format written out.
private struct FormatRow<Option: Hashable & Identifiable & CaseIterable>: View where Option.AllCases: RandomAccessCollection {
    let title: String
    let symbol: String
    @Binding var selection: Option
    let example: (Option) -> String

    var body: some View {
        LabeledContent {
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(Option.allCases) { format in
                        Text("\(name(format)) · \(example(format))").tag(format)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(example(selection)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(Color.accentColor)
            }
        }
    }

    private func name(_ format: Option) -> String {
        (format as? TimeFormat)?.title ?? (format as? DateFormat)?.title ?? ""
    }
}

protocol UnitDisplay {
    var symbol: String { get }
    var title: String { get }
}

extension TemperatureUnit: UnitDisplay {}
extension SpeedUnit: UnitDisplay {}
extension WaveUnit: UnitDisplay {}
extension RainUnit: UnitDisplay {}
extension DistanceUnit: UnitDisplay {}
extension PressureUnit: UnitDisplay {}

// MARK: - Background pictures

/// Where background pictures are set: for all pages, for a kind of page or a
/// club, how they look, and back to no pictures.
struct BackgroundSettingsView: View {
    let locations: LocationStore
    @State private var confirmingRemove = false
    @State private var showTip = false
    private let tip = BackgroundsTip()

    var body: some View {
        @Bindable var settings = AppSettings.shared
        ScrollViewReader { proxy in
            Form {
                if showTip {
                    Section {
                        TipView(tip)
                    }
                }

                Section {
                    BackgroundPreview()
                        .listRowInsets(EdgeInsets())
                } footer: {
                    SectionFooter(tr("Preview of the club pages with the picture for all pages."))
                }
                .id("preview")

                Section {
                    NavigationLink(value: SettingsRoute.picker(.all)) {
                        BackgroundRow(title: tr("All pages"), symbol: "square.stack", choice: settings.allPagesBackground)
                    }
                } header: {
                    SectionTitle(tr("All pages"), symbol: "square.stack")
                }
                .surfaceRows()
                .id("all")

                Section {
                    ForEach(PageKind.allCases) { page in
                        NavigationLink(value: SettingsRoute.picker(.page(page))) {
                            BackgroundRow(title: page.title, symbol: page.symbol, choice: settings.pageBackgrounds[page],
                                          inherited: tr("Same as all pages"))
                        }
                    }
                } header: {
                    SectionTitle(tr("Single pages"), symbol: "rectangle.portrait.on.rectangle.portrait")
                } footer: {
                    SectionFooter(tr("A picture set here replaces the one for all pages on that page."))
                }
                .surfaceRows()
                .id("pages")

                Section {
                    ForEach(locations.saved) { club in
                        NavigationLink(value: SettingsRoute.picker(.club(club.id))) {
                            BackgroundRow(title: club.displayName, symbol: club.id == locations.homeID ? "house.fill" : "figure.rower",
                                          choice: settings.clubBackgrounds[club.id], inherited: tr("Same as club pages"))
                        }
                    }
                } header: {
                    SectionTitle(tr("Single clubs"), symbol: "figure.rower")
                } footer: {
                    SectionFooter(tr("A club's own picture shows only on that club's page."))
                }
                .surfaceRows()
                .id("clubs")

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(tr("Picture"), systemImage: "photo")
                        Picker(tr("Picture"), selection: $settings.blurBackground) {
                            Text(tr("Clear")).tag(false)
                            Text(tr("Blurred")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label(tr("In the tiles"), systemImage: "rectangle.grid.1x2")
                        Picker(tr("In the tiles"), selection: $settings.tileStyle) {
                            ForEach(TileStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                } header: {
                    SectionTitle(tr("Look"), symbol: "slider.horizontal.3")
                } footer: {
                    SectionFooter(tr("Picture blurred: the picture shows through the tiles like frosted glass. No picture: the tiles stay solid and keep the full rowing-light shading. No picture also saves battery, as blurred tiles are drawn again while the page scrolls; in Low Power Mode the tiles are always solid."))
                }
                .surfaceRows()
                .id("look")

                Section {
                    Button(role: .destructive) {
                        confirmingRemove = true
                    } label: {
                        Label(tr("Remove all background pictures"), systemImage: "trash")
                    }
                } footer: {
                    SectionFooter(tr("Back to the factory setting: no picture on any page. Your own pictures stay available to pick again."))
                }
                .surfaceRows()
                .id("remove")
            }
            .scrollContentBackground(.hidden)
            .pageBackground(.settings)
            .navigationTitle(tr("Background pictures"))
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(tr("Remove all background pictures?"), isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button(tr("Remove"), role: .destructive) { AppSettings.shared.removeAllBackgrounds() }
                Button(tr("Cancel"), role: .cancel) {}
            }
            .screenshotSections(["preview", "pages", "clubs", "look", "remove"], proxy: proxy)
            .tipVisibility(tip, $showTip)
        }
    }
}

/// One place a picture can be set, with its thumbnail and what it shows now.
private struct BackgroundRow: View {
    let title: String
    let symbol: String
    /// nil when the place takes its picture from the level above.
    let choice: BackgroundChoice?
    var inherited: String = ""

    var body: some View {
        HStack(spacing: 12) {
            BackgroundThumbnail(choice: choice, width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .labelStyle(.titleAndIcon)
                Text(choice?.title ?? inherited)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A small picture, a crossed-out frame for "no picture", or a dashed one for "same as above".
struct BackgroundThumbnail: View {
    let choice: BackgroundChoice?
    var width: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width / 6)
        Group {
            if let choice, let image = BackgroundLibrary.image(for: choice, thumbnail: true) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if choice == nil {
                Image(systemName: "arrow.turn.left.up")
                    .font(.system(size: width * 0.4))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.tertiarySystemFill))
            } else {
                Image(systemName: "nosign")
                    .font(.system(size: width * 0.4))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            }
        }
        .frame(width: width, height: width * 2.16)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: choice == nil ? [3] : [])))
        .accessibilityHidden(true)
    }
}

/// A small club page with the picture for all pages and the chosen look.
private struct BackgroundPreview: View {
    var body: some View {
        let settings = AppSettings.shared
        let image = BackgroundLibrary.image(for: settings.background(for: .clubPages))
        let surface: Surface = image == nil ? .plain : settings.tileStyle.surface
        VStack(spacing: 10) {
            Text("MRC 1880")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .labelBackground(surface, in: Capsule())
            HStack(spacing: 10) {
                sampleTile(.green)
                sampleTile(.amber)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(tr("Current conditions").uppercased(), systemImage: "gauge.with.dots.needle.33percent")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Label(Format.wind(4), systemImage: Condition.wind.symbol)
                    Spacer()
                    Label(Format.waves(0.12), systemImage: Condition.waves.symbol)
                }
                .font(.caption)
            }
            .padding(10)
            .cardBackground(surface, cornerRadius: 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .background {
            if let image {
                BackgroundPicture(image: image, blurred: settings.blurBackground)
            } else {
                Color(.systemGroupedBackground)
            }
        }
        .clipped()
        .environment(\.surface, surface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Preview"))
    }

    private func sampleTile(_ light: Light) -> some View {
        HStack(spacing: 6) {
            TrafficLightDot(light: light, size: 12)
            Text(light.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(Format.degrees(14)).font(.title3.weight(.light))
        }
        .padding(10)
        .background { TintedCardBackground(tint: light.color, cornerRadius: 12) }
    }
}

/// Picks the picture for one target: the samples that come with the app,
/// the user's own pictures, a new one from Photos, no picture, or (except for
/// all pages) the same as the level above.
struct BackgroundPickerView: View {
    let target: BackgroundTarget
    let locations: LocationStore
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var photoError: String?

    private let columns = [GridItem(.adaptive(minimum: 98), spacing: 12)]

    var body: some View {
        let settings = AppSettings.shared
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 16) {
                    if let inherited = inheritedTitle {
                        option(nil, title: inherited)
                    }
                    option(BackgroundChoice.noPicture, title: isWidgets ? tr("Weather sky") : tr("No picture"))
                    option(BackgroundChoice.satellite, title: tr("Satellite picture of the lake"))
                    PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.accentColor.opacity(0.12))
                                if loadingPhoto {
                                    ProgressView()
                                } else {
                                    Image(systemName: "photo.badge.plus").font(.title)
                                }
                            }
                            .frame(height: 98 * 2.16 * 0.62)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                            Text(tr("Your own photo")).font(.caption).multilineTextAlignment(.center)
                        }
                    }
                    .buttonStyle(.plain)
                    ForEach(settings.userPictures, id: \.self) { name in
                        option(.custom(name), title: tr("Your picture"))
                            .contextMenu {
                                Button(tr("Delete picture"), systemImage: "trash", role: .destructive) {
                                    settings.forgetUserPicture(name)
                                }
                            }
                    }
                }
                Text(tr("Samples")).font(.headline)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(BackgroundLibrary.samples) { sample in
                        option(sample.choice, title: sample.title)
                    }
                }
                if !settings.userPictures.isEmpty {
                    Text(tr("Touch and hold one of your pictures to delete it."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: "RWScrollPage"), ready: true))
        .pageBackground(.settings)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await add(item) }
        }
        .alert(tr("Could not use this photo"), isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button(tr("OK")) {}
        } message: {
            Text(photoError ?? "")
        }
    }

    private var title: String {
        switch target {
        case .all: tr("All pages")
        case let .page(page): page.title
        case let .club(id): locations.catalog.first { $0.id == id }?.displayName ?? tr("Club")
        case let .widgets(id): id.flatMap { id in locations.catalog.first { $0.id == id }?.displayName } ?? tr("Widgets")
        }
    }

    private var isWidgets: Bool {
        if case .widgets = target { true } else { false }
    }

    /// "Same as …" for targets that can take the picture from the level above.
    private var inheritedTitle: String? {
        switch target {
        case .all: nil
        case .page: tr("Same as all pages")
        case .club: tr("Same as club pages")
        case let .widgets(id): id == nil ? nil : tr("Same as all widgets")
        }
    }

    private var current: BackgroundChoice? {
        let settings = AppSettings.shared
        switch target {
        case .all: return settings.allPagesBackground
        case let .page(page): return settings.pageBackgrounds[page]
        case let .club(id): return settings.clubBackgrounds[id]
        case let .widgets(id):
            guard let background = id.map({ settings.clubWidgetBackgrounds[$0] }) ?? settings.widgetBackground else { return nil }
            switch background {
            case let .picture(choice): return choice
            case .sky: return .noPicture
            case .satellite: return .satellite
            // Picked on the widget page (light colour, club page picture, plain): no tile here is ticked.
            default: return .custom("")
            }
        }
    }

    private func select(_ choice: BackgroundChoice?) {
        let settings = AppSettings.shared
        switch target {
        case .all: settings.allPagesBackground = choice ?? .noPicture
        case let .page(page): settings.pageBackgrounds[page] = choice
        case let .club(id): settings.clubBackgrounds[id] = choice
        case let .widgets(id):
            let background: WidgetBackground? = switch choice {
            case nil: nil
            case .noPicture?: .sky
            case .satellite?: .satellite
            case let other?: .picture(other)
            }
            if let id { settings.clubWidgetBackgrounds[id] = background } else { settings.widgetBackground = background ?? .sky }
        }
    }

    /// A thumbnail with its name; a tick marks the one in use.
    private func option(_ choice: BackgroundChoice?, title: String) -> some View {
        let selected = current == choice
        return Button { select(choice) } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    BackgroundThumbnail(choice: choice ?? inheritedChoice, width: 98 * 0.62)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            if choice == nil {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    .padding(-4)
                                    .frame(width: 98 * 0.62)
                            }
                        }
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: -8, y: 6)
                    }
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(selected ? .semibold : .regular)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What "same as …" shows now, for its thumbnail.
    private var inheritedChoice: BackgroundChoice? {
        let settings = AppSettings.shared
        switch target {
        case .all: return nil
        case .page: return settings.allPagesBackground
        case .club: return settings.background(for: .clubPages)
        case .widgets: return nil
        }
    }

    private func add(_ item: PhotosPickerItem) async {
        loadingPhoto = true
        defer {
            loadingPhoto = false
            photo = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadNoSuchFile) }
            let name = try BackgroundLibrary.addUserPicture(data)
            AppSettings.shared.userPictures.insert(name, at: 0)
            select(.custom(name))
        } catch {
            photoError = tr("The photo could not be loaded. Try another one.")
        }
    }
}

// MARK: - Shared pieces

/// The boats the rowing light can be for: small boats, big boats and the
/// user's own. Each has its own limits, behind the slider button.
struct RowingLimitsView: View {
    @Binding var path: [SettingsRoute]
    @State private var showBoatsTip = false
    private let boatsTip = MyBoatsTip()

    var body: some View {
        @Bindable var settings = AppSettings.shared
        ScrollViewReader { proxy in
            Form {
                Section {
                    if showBoatsTip {
                        TipView(boatsTip)
                    }
                    ForEach(Boat.groups) { boat in
                        BoatRow(boat: boat) { path.append(.boat(boat.id)) }
                    }
                } header: {
                    SectionTitle(tr("Your boat"), symbol: "figure.rower")
                } footer: {
                    SectionFooter(tr("The rowing light is for the boat with the tick, until you pick another. Big boats sit higher and steadier, so the app allows more wind and higher waves for them. Tap the sliders to fine-tune a boat's limits."))
                }
                .surfaceRows()

                Section {
                    ForEach(settings.myBoats) { boat in
                        BoatRow(boat: boat) { path.append(.boat(boat.id)) }
                    }
                    .onDelete { offsets in
                        for id in offsets.map({ settings.myBoats[$0].id }) { settings.removeBoat(id) }
                    }
                    Button {
                        path.append(.boat(settings.addBoat().id))
                    } label: {
                        Label(tr("Add a boat"), systemImage: "plus.circle")
                    }
                } header: {
                    SectionTitle(tr("My boats"), symbol: "list.bullet")
                } footer: {
                    SectionFooter(tr("Add the boats you can row, such as the club's gig. Each has limits for its type. When it is too rough for the ticked boat, the app says which of your boats would be fine."))
                }
                .surfaceRows()

                Section {
                    Picker(selection: $settings.mapBoatID) {
                        Text(tr("Same as the ticked boat")).tag(AppSettings.followBoat)
                        ForEach(settings.boats) { boat in
                            Text(boat.title).tag(boat.id)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if settings.mapLooksCalmer {
                        Label(tr("The map uses the limits for %@, which are higher than those for %@. The map points this out too.", settings.mapBoat.inSentence, settings.selectedBoat.inSentence),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    SectionTitle(tr("Lake map colours"), symbol: "map")
                } footer: {
                    SectionFooter(tr("The boat whose limits colour the lake view and route planning."))
                }
                .surfaceRows()
                .id("map")
            }
            .task {
                // Screenshot hook: `-RWLimitsScroll map` shows the lake map section.
                if UserDefaults.standard.string(forKey: "RWLimitsScroll") == "map" {
                    try? await Task.sleep(for: .milliseconds(600))
                    proxy.scrollTo("map", anchor: .top)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .tipVisibility(boatsTip, $showBoatsTip)
        .navigationTitle(tr("Rowing limits"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A boat to tick, with a button to its limits.
private struct BoatRow: View {
    let boat: Boat
    let openLimits: () -> Void

    var body: some View {
        let settings = AppSettings.shared
        let changed = !(settings.boatLimits[boat.id] ?? [:]).isEmpty
        HStack(spacing: 12) {
            Button {
                settings.boatID = boat.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(boat.title).foregroundStyle(.primary)
                        Text(changed ? tr("%@ · your limits", boat.detail) : boat.detail)
                            .font(.caption)
                            .foregroundStyle(changed ? Color.orange : Color.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if settings.selectedBoat.id == boat.id {
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: openLimits) {
                Image(systemName: "slider.horizontal.3")
                    .padding(6)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(tr("Limits for %@", boat.title))
        }
    }
}

/// One boat's name, type and limits.
struct BoatLimitsView: View {
    let boatID: String
    @State private var showColdTip = false
    private let coldTip = ColdWaterTip()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = AppSettings.shared
        let boat = settings.boat(boatID) ?? .small
        Form {
            if !boat.isGroup, let index = settings.myBoats.firstIndex(where: { $0.id == boatID }) {
                Section {
                    TextField(tr("Name, e.g. the boat's name"), text: $settings.myBoats[index].name)
                    Picker(tr("Type"), selection: $settings.myBoats[index].type) {
                        ForEach(BoatType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    Picker(tr("Size and rigging"), selection: $settings.myBoats[index].boatClass) {
                        ForEach(BoatClass.allCases) { boatClass in
                            Text(boatClass.title).tag(boatClass)
                        }
                    }
                } header: {
                    SectionTitle(tr("Boat"), symbol: "figure.rower")
                } footer: {
                    SectionFooter(boat.type.detail)
                }
                .surfaceRows()
            }

            Section {
                if showColdTip {
                    TipView(coldTip)
                }
                ForEach(RowingLimit.allCases) { limit in
                    LimitRow(limit: limit, boat: boat)
                }
                if !(settings.boatLimits[boat.id] ?? [:]).isEmpty {
                    Button(tr("Use the app's limits again")) { settings.boatLimits[boat.id] = nil }
                }
            } header: {
                SectionTitle(tr("Fine-tune the limits"), symbol: "slider.horizontal.3")
            } footer: {
                SectionFooter(tr("A limit you change shows as “your limit” on the rowing light. When a value is above the app's usual limit but within yours, the app still says so. Official warnings, thunderstorms, fog, hail and darkness always count.")
                              + " " + tr("Below %@ water the app lowers its own wind and gust limits by %@. Limits you set yourself stay as they are, and the rowing light then reminds you to take extra care.",
                                         Format.temperature(RowingLimits.coldWaterC), Format.wind(RowingLimits.coldWindMarginMs)))
            }
            .surfaceRows()

            if !boat.isGroup {
                Section {
                    Button(tr("Remove this boat"), role: .destructive) {
                        dismiss()
                        settings.removeBoat(boat.id)
                    }
                }
                .surfaceRows()
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .tipVisibility(coldTip, $showColdTip)
        .navigationTitle(boat.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One limit with buttons to raise or lower it; the app's value is shown beside a changed one.
private struct LimitRow: View {
    let limit: RowingLimit
    let boat: Boat

    var body: some View {
        let limits = AppSettings.shared.limits(for: boat)
        let value = limits.value(limit)
        let usual = limit.standard(for: boat)
        let mine = limits.isMine(limit)
        Stepper {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(limit.title, systemImage: limit.symbol)
                        .symbolRenderingMode(.hierarchical)
                    Text(mine ? tr("Your limit · the app's: %@", limit.format(usual)) : tr("The app's limit"))
                        .font(.caption)
                        .foregroundStyle(mine ? Color.orange : Color.secondary)
                }
                Spacer(minLength: 4)
                Text(limit.format(value)).monospacedDigit().fontWeight(.semibold)
            }
        } onIncrement: {
            set(value + limit.step)
        } onDecrement: {
            set(value - limit.step)
        }
    }

    private func set(_ new: Double) {
        let settings = AppSettings.shared
        let clamped = min(max((new / limit.step).rounded() * limit.step, limit.range.lowerBound), limit.range.upperBound)
        var custom = settings.boatLimits[boat.id] ?? [:]
        custom[limit] = abs(clamped - limit.standard(for: boat)) < limit.step / 2 ? nil : clamped
        settings.boatLimits[boat.id] = custom.isEmpty ? nil : custom
    }
}

/// A section header that stays readable over a background picture.
struct SectionTitle: View {
    let text: String
    let symbol: String
    @Environment(\.surface) private var surface

    init(_ text: String, symbol: String) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        Label(text, systemImage: symbol)
            .padding(.horizontal, surface.hasPicture ? 8 : 0)
            .padding(.vertical, surface.hasPicture ? 3 : 0)
            .labelBackground(surface, in: Capsule())
    }
}

struct SectionFooter: View {
    let text: String
    @Environment(\.surface) private var surface

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .padding(surface.hasPicture ? 8 : 0)
            .labelBackground(surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A form row's background: frosted over a picture with frosted tiles, else the usual.
private struct SurfaceRowBackground: View {
    @Environment(\.surface) private var surface

    var body: some View {
        if surface == .frosted {
            FrostedFill(shape: Rectangle())
        } else {
            Rectangle().fill(Color(.secondarySystemGroupedBackground))
        }
    }
}

extension View {
    /// Frosted rows when the page has a picture and the tiles are frosted.
    func surfaceRows() -> some View { listRowBackground(SurfaceRowBackground()) }

    /// Screenshot hook: `-RWScrollPage n` scrolls a form to its n-th section, so
    /// a series of screenshots covers the whole page.
    func screenshotSections(_ ids: [String], proxy: ScrollViewProxy) -> some View {
        task {
            let page = UserDefaults.standard.integer(forKey: "RWScrollPage")
            guard page > 0 else { return }
            // Scrolled twice: on a slow simulator the first try can come before
            // the form has laid out its rows and does nothing.
            for _ in 0..<2 {
                try? await Task.sleep(for: .seconds(2))
                proxy.scrollTo(ids[min(page, ids.count - 1)], anchor: .top)
            }
        }
    }
}
