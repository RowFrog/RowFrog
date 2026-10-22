import PhotosUI
import SwiftUI
import TipKit

/// Pages pushed inside the settings.
enum SettingsRoute: Hashable {
    case backgrounds
    case limits
    case picker(BackgroundTarget)

    /// Screenshot hook: `-RWSettingsPage backgrounds`, `picker-all`,
    /// `picker-page:list` or `picker-club:<id>` opens that page.
    static func fromLaunchArguments() -> [SettingsRoute] {
        guard let page = UserDefaults.standard.string(forKey: "RWSettingsPage") else { return [] }
        if page == "backgrounds" { return [.backgrounds] }
        if page == "limits" { return [.limits] }
        if page == "picker-all" { return [.backgrounds, .picker(.all)] }
        if page.hasPrefix("picker-page:"), let kind = PageKind(rawValue: String(page.dropFirst("picker-page:".count))) {
            return [.backgrounds, .picker(.page(kind))]
        }
        if page.hasPrefix("picker-club:") {
            return [.backgrounds, .picker(.club(String(page.dropFirst("picker-club:".count))))]
        }
        return []
    }
}

/// What a background picture is picked for.
enum BackgroundTarget: Hashable {
    case all
    case page(PageKind)
    case club(String)
}

/// The settings page, opened with the cog on the location list.
struct SettingsView: View {
    let locations: LocationStore
    @State private var path = SettingsRoute.fromLaunchArguments()
    @State private var confirmingReset = false
    @State private var showingTour = false
    @State private var showResetTip = false
    private let resetTip = FactoryResetTip()

    private var limitsSummary: String {
        let settings = AppSettings.shared
        let changed = settings.customLimits.count
        return changed == 0 ? settings.boatClass.title : tr("%@ · %@ changed", settings.boatClass.title, "\(changed)")
    }
    @State private var showAppIconTip = false
    private let appIconTip = AppIconTip()
    @State private var appIcon = AppIcons.current
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = AppSettings.shared
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        AppearancePicker(selection: $settings.appearance)
                        Toggle(isOn: $settings.allowsLandscape) {
                            Label(tr("Landscape"), systemImage: "rectangle.landscape.rotate")
                        }
                    } header: {
                        SectionTitle(tr("Appearance"), symbol: "circle.lefthalf.filled")
                    } footer: {
                        SectionFooter(tr("Landscape on: the app turns with the phone and shows the cards in two columns. Off: it stays upright."))
                    }
                    .surfaceRows()
                    .id("appearance")

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
                        UnitRow(condition: .precipitation, title: tr("Rain, hail, snow"), selection: $settings.rainUnit)
                        UnitRow(condition: .visibility, title: tr("Visibility and distances"), selection: $settings.distanceUnit)
                    } header: {
                        SectionTitle(tr("Units"), symbol: "ruler")
                    } footer: {
                        SectionFooter(tr("Cloud cover stays in percent."))
                    }
                    .surfaceRows()
                    .id("units")

                    Section {
                        NavigationLink(value: SettingsRoute.limits) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr("Your boat and limits"))
                                Text(limitsSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        SectionTitle(tr("Rowing limits"), symbol: "figure.rower")
                    } footer: {
                        SectionFooter(tr("When the rowing light turns amber or red. Big boats get higher wind and wave limits, and you can fine-tune each limit."))
                    }
                    .surfaceRows()
                    .id("limits")

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
                    } header: {
                        SectionTitle(tr("Background"), symbol: "photo")
                    }
                    .surfaceRows()
                    .id("background")

                    Section {
                        Button {
                            Tutorial.replay()
                            showingTour = true
                        } label: {
                            Label(tr("Show the tour again"), systemImage: "questionmark.circle")
                        }
                    } header: {
                        SectionTitle(tr("Help"), symbol: "questionmark.circle")
                    } footer: {
                        SectionFooter(tr("The one-time tips come back the next time you open the app."))
                    }
                    .surfaceRows()
                    .id("help")

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
                        SectionFooter(tr("Appearance, units, language, background pictures, the app icon, your boat and your rowing limits go back to how the app came. Your locations and home base stay."))
                    }
                    .surfaceRows()
                    .id("reset")

                    Section {
                        LabeledContent(tr("Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    }
                    .surfaceRows()
                }
                .scrollContentBackground(.hidden)
                .pageBackground(.settings)
                .navigationTitle(tr("Settings"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done")) { dismiss() }
                    }
                }
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .backgrounds:
                        BackgroundSettingsView(locations: locations)
                    case .limits:
                        RowingLimitsView()
                    case let .picker(target):
                        BackgroundPickerView(target: target, locations: locations)
                    }
                }
                .confirmationDialog(tr("Reset all settings?"), isPresented: $confirmingReset, titleVisibility: .visible) {
                    Button(tr("Reset"), role: .destructive) {
                        AppSettings.shared.resetToFactorySettings()
                        Task {
                            try? await AppIcons.select(AppIcons.primary)
                            appIcon = AppIcons.current
                        }
                    }
                    Button(tr("Cancel"), role: .cancel) {}
                } message: {
                    Text(tr("Appearance, units, language, background pictures and the app icon go back to how the app came, and your own pictures are deleted from the app. Your boat and any limits you changed go back to the app's limits too. Your locations and home base stay."))
                }
                .screenshotSections(["appearance", "units", "limits", "datetime", "background", "help", "appicon", "reset"], proxy: proxy)
                .tipVisibility(appIconTip, $showAppIconTip)
                .tipVisibility(resetTip, $showResetTip)
                .fullScreenCover(isPresented: $showingTour) {
                    TutorialView(locations: locations, reload: {}) {
                        Tutorial.markSeen()
                        showingTour = false
                    }
                }
            }
        }
    }

    /// 14:30 today, to show each time format.
    private static var sampleTime: Date {
        Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: .now) ?? .now
    }

    private var backgroundSummary: String {
        let settings = AppSettings.shared
        let own = settings.pageBackgrounds.count + settings.clubBackgrounds.count
        let all = tr("All pages: %@", settings.allPagesBackground.title)
        return own == 0 ? all : all + " · " + tr("%@ with their own", String(own))
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
private struct UnitRow<Unit: Hashable & Identifiable & CaseIterable>: View where Unit.AllCases: RandomAccessCollection, Unit: UnitDisplay {
    let condition: Condition
    let title: String
    @Binding var selection: Unit

    var body: some View {
        LabeledContent {
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(Unit.allCases) { unit in
                        Text("\(unit.symbol) · \(unit.title)").tag(unit)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.symbol).monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                ConditionIcon(condition: condition).foregroundStyle(Color.accentColor)
            }
        }
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
                    SectionFooter(tr("Picture blurred: the picture shows through the tiles like frosted glass. No picture: the tiles stay solid and keep the full rowing-light shading."))
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
        let surface: Surface = image == nil ? .plain : (settings.tileStyle == .frosted ? .frosted : .solid)
        VStack(spacing: 10) {
            Text("MRC 1880")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(surface.label, in: Capsule())
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
            .background(surface.card, in: RoundedRectangle(cornerRadius: 12))
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
                    option(BackgroundChoice.noPicture, title: tr("No picture"))
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
        }
    }

    /// "Same as …" for targets that can take the picture from the level above.
    private var inheritedTitle: String? {
        switch target {
        case .all: nil
        case .page: tr("Same as all pages")
        case .club: tr("Same as club pages")
        }
    }

    private var current: BackgroundChoice? {
        let settings = AppSettings.shared
        switch target {
        case .all: return settings.allPagesBackground
        case let .page(page): return settings.pageBackgrounds[page]
        case let .club(id): return settings.clubBackgrounds[id]
        }
    }

    private func select(_ choice: BackgroundChoice?) {
        let settings = AppSettings.shared
        switch target {
        case .all: settings.allPagesBackground = choice ?? .noPicture
        case let .page(page): settings.pageBackgrounds[page] = choice
        case let .club(id): settings.clubBackgrounds[id] = choice
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

/// A section header that stays readable over a background picture.
/// The boat class and the limits the rowing light uses, each fine-tunable.
struct RowingLimitsView: View {
    var body: some View {
        @Bindable var settings = AppSettings.shared
        Form {
            Section {
                Picker(selection: $settings.boatClass) {
                    ForEach(BoatClass.allCases) { boat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(boat.title)
                            Text(boat.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(boat)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                SectionTitle(tr("Your boat"), symbol: "figure.rower")
            } footer: {
                SectionFooter(tr("Big boats sit higher and steadier, so the app allows more wind and higher waves for them."))
            }
            .surfaceRows()

            Section {
                ForEach(RowingLimit.allCases) { limit in
                    LimitRow(limit: limit)
                }
                if !settings.customLimits.isEmpty {
                    Button(tr("Use the app's limits again")) { settings.customLimits = [:] }
                }
            } header: {
                SectionTitle(tr("Fine-tune the limits"), symbol: "slider.horizontal.3")
            } footer: {
                SectionFooter(tr("A limit you change shows as “your limit” on the rowing light. When a value is above the app's usual limit but within yours, the app still says so. DWD warnings, thunderstorms, fog, hail and darkness always count."))
            }
            .surfaceRows()
        }
        .scrollContentBackground(.hidden)
        .pageBackground(.settings)
        .navigationTitle(tr("Rowing limits"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One limit with buttons to raise or lower it; the app's value is shown beside a changed one.
private struct LimitRow: View {
    let limit: RowingLimit

    var body: some View {
        let settings = AppSettings.shared
        let value = settings.limits.value(limit)
        let usual = limit.standard(for: settings.boatClass)
        let mine = settings.limits.isMine(limit)
        Stepper {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(limit.title, systemImage: limit.condition.symbol)
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
        if abs(clamped - limit.standard(for: settings.boatClass)) < limit.step / 2 {
            settings.customLimits[limit] = nil
        } else {
            settings.customLimits[limit] = clamped
        }
    }
}

private struct SectionTitle: View {
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
            .background(surface.label, in: Capsule())
    }
}

private struct SectionFooter: View {
    let text: String
    @Environment(\.surface) private var surface

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .padding(surface.hasPicture ? 8 : 0)
            .background(surface.label, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A form row's background: frosted over a picture with frosted tiles, else the usual.
private struct SurfaceRowBackground: View {
    @Environment(\.surface) private var surface

    var body: some View {
        Rectangle().fill(surface == .frosted ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
    }
}

private extension View {
    /// Frosted rows when the page has a picture and the tiles are frosted.
    func surfaceRows() -> some View { listRowBackground(SurfaceRowBackground()) }

    /// Screenshot hook: `-RWScrollPage n` scrolls a form to its n-th section, so
    /// a series of screenshots covers the whole page.
    func screenshotSections(_ ids: [String], proxy: ScrollViewProxy) -> some View {
        task {
            let page = UserDefaults.standard.integer(forKey: "RWScrollPage")
            guard page > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            proxy.scrollTo(ids[min(page, ids.count - 1)], anchor: .top)
        }
    }
}
