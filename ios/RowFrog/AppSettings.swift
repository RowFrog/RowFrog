import Foundation
import Observation
import SwiftUI

/// The user's preferences from the settings page, kept on the device.
/// Every key can also be set as a launch argument (e.g. `-RWLanguage de`),
/// which the screenshot workflow uses to show each state.
@Observable
final class AppSettings {
#if WIDGET_EXTENSION
    /// The widget reads the settings the app copies into the shared app group.
    /// Its process can live for days, so each new timeline reads them again (`reload`).
    private(set) static var shared = AppSettings(defaults: WidgetShared.defaults)

    static func reload() { shared = AppSettings(defaults: WidgetShared.defaults) }
#else
    static let shared = AppSettings()
#endif

    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: Keys.language) } }
    /// Whether the app turns with the phone; off keeps it upright.
    var allowsLandscape: Bool { didSet { defaults.set(allowsLandscape, forKey: Keys.landscape) } }

    var temperatureUnit: TemperatureUnit { didSet { defaults.set(temperatureUnit.rawValue, forKey: Keys.temperature) } }
    var windUnit: SpeedUnit { didSet { defaults.set(windUnit.rawValue, forKey: Keys.wind) } }
    var waveUnit: WaveUnit { didSet { defaults.set(waveUnit.rawValue, forKey: Keys.waves) } }
    var rainUnit: RainUnit { didSet { defaults.set(rainUnit.rawValue, forKey: Keys.rain) } }
    var distanceUnit: DistanceUnit { didSet { defaults.set(distanceUnit.rawValue, forKey: Keys.distance) } }
    var pressureUnit: PressureUnit { didSet { defaults.set(pressureUnit.rawValue, forKey: Keys.pressure) } }
    var timeFormat: TimeFormat { didSet { defaults.set(timeFormat.rawValue, forKey: Keys.timeFormat) } }
    var dateFormat: DateFormat { didSet { defaults.set(dateFormat.rawValue, forKey: Keys.dateFormat) } }
    /// How often the widgets load a new forecast on their own.
    var widgetUpdates: WidgetUpdates { didSet { defaults.set(widgetUpdates.rawValue, forKey: Keys.widgetUpdates) } }

    /// The user's own boats, besides the small and big boat groups.
    var myBoats: [Boat] { didSet { defaults.set(try? JSONEncoder().encode(myBoats), forKey: Keys.myBoats) } }
    /// The boat the rowing light is for; kept until the user picks another.
    var boatID: String { didSet { defaults.set(boatID, forKey: Keys.boat) } }
    /// Limits the user changed, per boat; a missing entry means the app's limit for the boat's type.
    var boatLimits: [String: [RowingLimit: Double]] {
        didSet {
            let plain = boatLimits.filter { !$0.value.isEmpty }
                .mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.rawValue, $0.value) }) }
            defaults.set(plain, forKey: Keys.boatLimits)
        }
    }
    /// The boat the lake map is coloured for, or `Self.followBoat` for the ticked one.
    var mapBoatID: String { didSet { defaults.set(mapBoatID, forKey: Keys.mapBoat) } }
    static let followBoat = "follow"

    /// Small boats, big boats, then the user's own.
    var boats: [Boat] { Boat.groups + myBoats }
    func boat(_ id: String) -> Boat? { boats.first { $0.id == id } }
    var selectedBoat: Boat { boat(boatID) ?? .small }
    func limits(for boat: Boat) -> RowingLimits { RowingLimits(boat: boat, custom: boatLimits[boat.id] ?? [:]) }
    /// The limits the rowing light uses.
    var limits: RowingLimits { limits(for: selectedBoat) }
    var mapBoat: Boat { mapBoatID == Self.followBoat ? selectedBoat : boat(mapBoatID) ?? .small }
    var mapLimits: RowingLimits { limits(for: mapBoat) }
    /// The map is coloured for a boat that takes more wind or waves than the
    /// ticked one, so it can look calmer than it is for the user.
    var mapLooksCalmer: Bool { mapLimits.allowsMore(than: limits) }

    /// Adds a boat and returns it.
    @discardableResult
    func addBoat(type: BoatType = .gig, boatClass: BoatClass = .quad) -> Boat {
        let boat = Boat(id: UUID().uuidString, name: "", type: type, boatClass: boatClass)
        myBoats.append(boat)
        return boat
    }

    /// Removes one of the user's boats; the ticked boat and the map fall back to small boats.
    func removeBoat(_ id: String) {
        myBoats.removeAll { $0.id == id }
        boatLimits[id] = nil
        if boatID == id { boatID = Boat.small.id }
        if mapBoatID == id { mapBoatID = Boat.small.id }
    }

    /// The picture behind every page, unless a page or club has its own.
    var allPagesBackground: BackgroundChoice { didSet { defaults.set(allPagesBackground.rawValue, forKey: Keys.background) } }
    /// Pictures for one kind of page; a missing entry means "same as all pages".
    var pageBackgrounds: [PageKind: BackgroundChoice] {
        didSet { defaults.set(Dictionary(uniqueKeysWithValues: pageBackgrounds.map { ($0.key.rawValue, $0.value.rawValue) }), forKey: Keys.pageBackgrounds) }
    }
    /// Pictures for one club's page; a missing entry means "same as club pages".
    var clubBackgrounds: [String: BackgroundChoice] {
        didSet { defaults.set(clubBackgrounds.mapValues(\.rawValue), forKey: Keys.clubBackgrounds) }
    }
    var blurBackground: Bool { didSet { defaults.set(blurBackground, forKey: Keys.blur) } }
    var tileStyle: TileStyle { didSet { defaults.set(tileStyle.rawValue, forKey: Keys.tileStyle) } }
    /// File names of the user's own pictures, newest first.
    var userPictures: [String] { didSet { defaults.set(userPictures, forKey: Keys.userPictures) } }

    /// The widgets' background, unless a club or a widget has its own.
    var widgetBackground: WidgetBackground { didSet { defaults.set(widgetBackground.rawValue, forKey: Keys.widgetBackground) } }
    /// A club's widgets' background; a missing entry means "same as all widgets".
    var clubWidgetBackgrounds: [String: WidgetBackground] {
        didSet { defaults.set(clubWidgetBackgrounds.mapValues(\.rawValue), forKey: Keys.clubWidgetBackgrounds) }
    }
    /// Pictures behind the widgets blurred.
    var blurWidgetPicture: Bool { didSet { defaults.set(blurWidgetPicture, forKey: Keys.widgetBlur) } }

    /// A club's widget background: its own, else the one for all widgets.
    func widgetBackground(for clubID: String) -> WidgetBackground { clubWidgetBackgrounds[clubID] ?? widgetBackground }

    /// Hidden developer options, switched on by tapping the version in the settings seven times.
    var developerOptions: Bool { didSet { defaults.set(developerOptions, forKey: Keys.developer) } }
    /// Weather models picked per club id while the developer options are on; missing = automatic.
    var pickedModels: [String: String] { didSet { defaults.set(pickedModels, forKey: Keys.pickedModels) } }

    /// The order of the cards on every club page, and the cards switched off.
    var pageLayout: PageLayout { didSet { defaults.set(try? JSONEncoder().encode(pageLayout), forKey: Keys.pageLayout) } }
    /// Clubs whose page has its own order; they keep it when the order for all clubs changes.
    var clubPageLayouts: [String: PageLayout] {
        didSet { defaults.set(try? JSONEncoder().encode(clubPageLayouts), forKey: Keys.clubPageLayouts) }
    }

    /// The card order for a club's page: its own, else the one for all clubs.
    func pageLayout(for clubID: String) -> PageLayout { clubPageLayouts[clubID] ?? pageLayout }

    /// The model to load for a club, or nil for the automatic choice.
    func pickedModel(for clubID: String) -> String? {
        developerOptions ? pickedModels[clubID] : nil
    }

    private let defaults: UserDefaults

    enum Keys {
        static let appearance = "RWAppearance"
        static let language = "RWLanguage"
        static let landscape = "RWAllowsLandscape"
        static let temperature = "RWUnitTemperature"
        static let wind = "RWUnitWind"
        static let waves = "RWUnitWaves"
        static let rain = "RWUnitRain"
        static let distance = "RWUnitDistance"
        static let pressure = "RWUnitPressure"
        static let timeFormat = "RWTimeFormat"
        static let dateFormat = "RWDateFormat"
        static let background = "RWBackground"
        static let pageBackgrounds = "RWBackgroundPages"
        static let clubBackgrounds = "RWBackgroundClubs"
        static let blur = "RWBackgroundBlur"
        static let tileStyle = "RWTileStyle"
        static let userPictures = "RWUserPictures"
        static let boat = "RWBoat"
        static let myBoats = "RWMyBoats"
        static let boatLimits = "RWBoatLimits"
        static let mapBoat = "RWMapBoat"
        static let developer = "RWDeveloperOptions"
        static let pickedModels = "RWPickedModels"
        static let pageLayout = "RWPageLayout"
        static let clubPageLayouts = "RWClubPageLayouts"
        static let widgetBackground = "RWWidgetBackground"
        static let clubWidgetBackgrounds = "RWWidgetBackgroundClubs"
        static let widgetBlur = "RWWidgetBackgroundBlur"
        static let widgetUpdates = "RWWidgetUpdates"

        static let all = [appearance, language, landscape, temperature, wind, waves, rain, distance, pressure, timeFormat, dateFormat,
                          background, pageBackgrounds, clubBackgrounds, blur, tileStyle, userPictures, boat, myBoats, boatLimits, mapBoat,
                          developer, pickedModels, pageLayout, clubPageLayouts, widgetBackground, clubWidgetBackgrounds, widgetBlur,
                          widgetUpdates]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        appearance = value(Keys.appearance, .device)
        language = value(Keys.language, .device)
        allowsLandscape = defaults.object(forKey: Keys.landscape) == nil || defaults.bool(forKey: Keys.landscape)
        temperatureUnit = value(Keys.temperature, .celsius)
        windUnit = value(Keys.wind, .metersPerSecond)
        waveUnit = value(Keys.waves, .meters)
        rainUnit = value(Keys.rain, .millimeters)
        distanceUnit = value(Keys.distance, .kilometers)
        pressureUnit = value(Keys.pressure, .hectopascals)
        timeFormat = value(Keys.timeFormat, .hours24)
        dateFormat = value(Keys.dateFormat, .device)
        widgetUpdates = value(Keys.widgetUpdates, .halfHour)
        // Launch arguments give the limits' numbers as text, e.g. `-RWBoatLimits '{small = {windAmber = 7;};}'`.
        if let data = defaults.data(forKey: Keys.myBoats) ?? defaults.string(forKey: Keys.myBoats)?.data(using: .utf8) {
            myBoats = (try? JSONDecoder().decode([Boat].self, from: data)) ?? []
        } else {
            // As a launch argument: `-RWMyBoats '({id = b1; name = Anna; type = gig; class = "4x";})'`.
            myBoats = (defaults.array(forKey: Keys.myBoats) as? [[String: String]] ?? []).compactMap { raw in
                guard let id = raw["id"], let type = raw["type"].flatMap(BoatType.init(rawValue:)),
                      let boatClass = raw["class"].flatMap(BoatClass.init(rawValue:)) else { return nil }
                return Boat(id: id, name: raw["name"] ?? "", type: type, boatClass: boatClass)
            }
        }
        boatID = defaults.string(forKey: Keys.boat) ?? Boat.small.id
        let saved = defaults.dictionary(forKey: Keys.boatLimits) ?? [:]
        boatLimits = saved.compactMapValues { raw -> [RowingLimit: Double]? in
            guard let limits = raw as? [String: Any] else { return nil }
            return Dictionary(uniqueKeysWithValues: limits.compactMap { key, raw in
                guard let limit = RowingLimit(rawValue: key),
                      let number = (raw as? Double) ?? (raw as? String).flatMap(Double.init) else { return nil }
                return (limit, number)
            })
        }
        mapBoatID = defaults.string(forKey: Keys.mapBoat) ?? Boat.small.id
        allPagesBackground = defaults.string(forKey: Keys.background).flatMap(BackgroundChoice.init(rawValue:)) ?? .noPicture
        let pages = defaults.dictionary(forKey: Keys.pageBackgrounds) as? [String: String] ?? [:]
        pageBackgrounds = Dictionary(uniqueKeysWithValues: pages.compactMap { key, raw in
            guard let page = PageKind(rawValue: key), let choice = BackgroundChoice(rawValue: raw) else { return nil }
            return (page, choice)
        })
        let clubs = defaults.dictionary(forKey: Keys.clubBackgrounds) as? [String: String] ?? [:]
        clubBackgrounds = clubs.compactMapValues(BackgroundChoice.init(rawValue:))
        blurBackground = defaults.bool(forKey: Keys.blur)
        tileStyle = value(Keys.tileStyle, .frosted)
        userPictures = defaults.stringArray(forKey: Keys.userPictures) ?? []
        widgetBackground = defaults.string(forKey: Keys.widgetBackground).flatMap(WidgetBackground.init(rawValue:)) ?? .sky
        clubWidgetBackgrounds = (defaults.dictionary(forKey: Keys.clubWidgetBackgrounds) as? [String: String] ?? [:])
            .compactMapValues(WidgetBackground.init(rawValue:))
        blurWidgetPicture = defaults.bool(forKey: Keys.widgetBlur)
        developerOptions = defaults.bool(forKey: Keys.developer)
        pickedModels = defaults.dictionary(forKey: Keys.pickedModels) as? [String: String] ?? [:]
        // As a launch argument the order is a comma-separated list, e.g. `-RWPageLayout "hourly,radar"`.
        pageLayout = defaults.data(forKey: Keys.pageLayout).flatMap { try? JSONDecoder().decode(PageLayout.self, from: $0) }
            ?? defaults.string(forKey: Keys.pageLayout).map(PageLayout.init(list:))
            ?? .standard
        clubPageLayouts = defaults.data(forKey: Keys.clubPageLayouts).flatMap { try? JSONDecoder().decode([String: PageLayout].self, from: $0) } ?? [:]
    }

    /// The language the app shows: the chosen one, or the phone's when it is German.
    var resolvedLanguage: AppLanguage {
        switch language {
        case .device: Self.deviceLanguage
        default: language
        }
    }

    /// German when the phone's first language the app knows is German. The
    /// whole list is looked at (not only its first entry), and the language
    /// iOS picked for the app, so a German phone also gets German on the very
    /// first screen.
    static var deviceLanguage: AppLanguage {
        let known = Locale.preferredLanguages.first { $0.hasPrefix("de") || $0.hasPrefix("en") }
            ?? Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
        return known?.hasPrefix("de") == true ? .german : .english
    }

    /// Locale for numbers and dates in the chosen language; "Device" keeps the phone's.
    var locale: Locale {
        switch language {
        case .device: .current
        case .english: Locale(identifier: "en_GB")
        case .german: Locale(identifier: "de_DE")
        }
    }

    /// The picture for a page: the club's own, else the page kind's, else the one for all pages.
    func background(for page: PageKind, clubID: String? = nil) -> BackgroundChoice {
        if page == .clubPages, let clubID, let own = clubBackgrounds[clubID] { return own }
        return pageBackgrounds[page] ?? allPagesBackground
    }

    /// Back to no pictures anywhere; the user's own pictures stay available to pick again.
    func removeAllBackgrounds() {
        allPagesBackground = .noPicture
        pageBackgrounds = [:]
        clubBackgrounds = [:]
        blurBackground = false
        tileStyle = .frosted
    }

    /// Factory settings: every preference back to its default, small boats
    /// ticked, every boat's limits back to the app's, and the user's pictures deleted.
    /// Saved locations and the home base are not settings and stay.
    func resetToFactorySettings() {
        for name in userPictures { BackgroundLibrary.deleteUserPicture(name) }
        let boats = myBoats
        for key in Keys.all { defaults.removeObject(forKey: key) }
        appearance = .device
        language = .device
        allowsLandscape = true
        temperatureUnit = .celsius
        windUnit = .metersPerSecond
        waveUnit = .meters
        rainUnit = .millimeters
        distanceUnit = .kilometers
        pressureUnit = .hectopascals
        timeFormat = .hours24
        dateFormat = .device
        widgetUpdates = .halfHour
        boatID = Boat.small.id
        boatLimits = [:]
        mapBoatID = Boat.small.id
        removeAllBackgrounds()
        widgetBackground = .sky
        clubWidgetBackgrounds = [:]
        blurWidgetPicture = false
        userPictures = []
        developerOptions = false
        pickedModels = [:]
        pageLayout = .standard
        clubPageLayouts = [:]
        // The assignments above write the defaults back; remove them so a later
        // change of the app's defaults reaches users who never chose.
        for key in Keys.all { defaults.removeObject(forKey: key) }
        // The user's boats are kept, like the saved locations.
        myBoats = boats
    }

    /// A picture the user removed can no longer be shown anywhere.
    func forgetUserPicture(_ name: String) {
        let gone = BackgroundChoice.custom(name)
        if allPagesBackground == gone { allPagesBackground = .noPicture }
        pageBackgrounds = pageBackgrounds.filter { $0.value != gone }
        clubBackgrounds = clubBackgrounds.filter { $0.value != gone }
        if widgetBackground == .picture(gone) { widgetBackground = .sky }
        clubWidgetBackgrounds = clubWidgetBackgrounds.filter { $0.value != .picture(gone) }
        userPictures.removeAll { $0 == name }
        BackgroundLibrary.deleteUserPicture(name)
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case device, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .device: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .device: tr("Device")
        case .light: tr("Light")
        case .dark: tr("Dark")
        }
    }

    var symbol: String {
        switch self {
        case .device: "iphone"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case device, english = "en", german = "de"
    var id: String { rawValue }

    /// Each language in its own words, so it can be found whatever the app shows.
    var title: String {
        switch self {
        case .device: tr("Device language")
        case .english: "English"
        case .german: "Deutsch"
        }
    }
}

/// The kinds of page a background picture can be set for.
enum PageKind: String, CaseIterable, Identifiable {
    case clubPages, list, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clubPages: tr("Club pages")
        case .list: tr("Location list")
        case .settings: tr("Settings")
        }
    }

    var symbol: String {
        switch self {
        case .clubPages: "house"
        case .list: "list.bullet"
        case .settings: "gearshape"
        }
    }
}

/// How often the widgets load a new forecast on their own. Less often saves
/// battery and data; a new DWD warning then reaches the widget later.
enum WidgetUpdates: String, CaseIterable, Identifiable {
    case halfHour, hour, twoHours
    /// Only when the app was open: the widget loads once as the user leaves the app.
    case appOpen
    var id: String { rawValue }

    var title: String {
        switch self {
        case .halfHour: tr("Every 30 minutes")
        case .hour: tr("Every hour")
        case .twoHours: tr("Every 2 hours")
        case .appOpen: tr("Only after using the app")
        }
    }

    /// The wait before the widget loads again on its own; nil for never.
    var interval: TimeInterval? {
        switch self {
        case .halfHour: 30 * 60
        case .hour: 3600
        case .twoHours: 2 * 3600
        case .appOpen: nil
        }
    }
}

/// How the cards look over a background picture.
enum TileStyle: String, CaseIterable, Identifiable {
    /// Frosted glass: the picture shows through, blurred, under a light rowing-light tint.
    case frosted
    /// Liquid Glass (iOS 26): clear glass that bends the picture at its edges.
    /// Earlier iOS versions show frosted glass instead.
    case glass
    /// Solid: no picture in the cards, which keep their full rowing-light shading.
    case solid
    var id: String { rawValue }

    var title: String {
        switch self {
        case .frosted: tr("Picture blurred")
        case .glass: tr("Liquid Glass")
        case .solid: tr("No picture")
        }
    }

    var surface: Surface {
        switch self {
        case .frosted: .frosted
        case .glass: .glass
        case .solid: .solid
        }
    }
}

enum BackgroundChoice: Hashable {
    case noPicture
    /// The newest clear Sentinel-2 picture of the club's lake (the home base's on other pages).
    case satellite
    /// One of the pictures that come with the app, by id.
    case sample(String)
    /// A picture the user added, by file name.
    case custom(String)

    init?(rawValue: String) {
        if rawValue == "none" { self = .noPicture; return }
        if rawValue == "satellite" { self = .satellite; return }
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "sample": self = .sample(parts[1])
        case "custom": self = .custom(parts[1])
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .noPicture: "none"
        case .satellite: "satellite"
        case let .sample(id): "sample:\(id)"
        case let .custom(name): "custom:\(name)"
        }
    }

    var title: String {
        switch self {
        case .noPicture: tr("No picture")
        case .satellite: tr("Satellite picture of the lake")
        case let .sample(id): BackgroundLibrary.sample(id)?.title ?? id
        case .custom: tr("Your picture")
        }
    }
}

/// What the widgets show behind their content.
enum WidgetBackground: Hashable {
    /// A sky in the colours of the weather and the time of day (the default).
    case sky
    /// Dark, washed in the rowing light's colour.
    case light
    /// The club page's picture from the app's background settings.
    case appPicture
    /// One of the sample pictures or the user's own.
    case picture(BackgroundChoice)
    /// The newest clear Sentinel-2 picture of the club's lake.
    case satellite
    /// Plain white or black, following light and dark mode.
    case system

    /// The choices that need no picture to be picked, in the order the settings list them.
    static let simple: [WidgetBackground] = [.sky, .light, .appPicture, .satellite, .system]

    init?(rawValue: String) {
        switch rawValue {
        case "sky": self = .sky
        case "light": self = .light
        case "app": self = .appPicture
        case "satellite": self = .satellite
        case "system": self = .system
        default:
            guard rawValue.hasPrefix("pic:"), let choice = BackgroundChoice(rawValue: String(rawValue.dropFirst(4))) else { return nil }
            self = .picture(choice)
        }
    }

    var rawValue: String {
        switch self {
        case .sky: "sky"
        case .light: "light"
        case .appPicture: "app"
        case .satellite: "satellite"
        case .system: "system"
        case let .picture(choice): "pic:\(choice.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .sky: tr("Weather sky")
        case .light: tr("Rowing light colour")
        case .appPicture: tr("Club page picture")
        case .satellite: tr("Satellite picture of the lake")
        case .system: tr("Plain, light or dark")
        case let .picture(choice): choice.title
        }
    }

    /// Whether the widget draws a picture the app prepares for it.
    var usesPicture: Bool {
        switch self {
        case .appPicture, .picture, .satellite: true
        default: false
        }
    }
}

// The club page card order lives here because the widget builds AppSettings too.

/// A card on a club page that the user can move or switch off. The rowing
/// light stays first and DWD warnings, while one is issued, right under it;
/// the forecast source and credits stay last.
enum PageCard: String, CaseIterable, Codable, Identifiable {
    case radar, conditions, lakeView, hourly, launchPoint, satellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .radar: tr("Rain radar")
        case .conditions: tr("Current conditions")
        case .lakeView: tr("Lake view")
        case .hourly: tr("Next 48 hours")
        case .launchPoint: tr("Launch point")
        case .satellite: tr("Satellite picture")
        }
    }

    var symbol: String {
        switch self {
        case .radar: "umbrella"
        case .conditions: "gauge.with.dots.needle.33percent"
        case .lakeView: "map"
        case .hourly: "clock"
        case .launchPoint: "mappin.and.ellipse"
        case .satellite: "globe.europe.africa"
        }
    }
}

/// The order of the cards on a club page and which are switched off.
struct PageLayout: Codable, Hashable {
    var order: [PageCard]
    var hidden: Set<PageCard> = []

    static let standard = PageLayout(order: [.conditions, .radar, .lakeView, .hourly, .launchPoint, .satellite])

    /// From a launch argument such as "hourly,radar"; cards left out follow in the standard order.
    init(list: String) {
        self.init(order: list.split(separator: ",").compactMap { PageCard(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }

    init(order: [PageCard], hidden: Set<PageCard> = []) {
        // Every card once; cards added in a later version join at the end.
        var seen = Set<PageCard>()
        self.order = (order + PageCard.allCases).filter { seen.insert($0).inserted }
        self.hidden = hidden
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown names (from a newer version) are skipped instead of failing.
        let order = try c.decode([String].self, forKey: .order).compactMap(PageCard.init(rawValue:))
        let hidden = try c.decodeIfPresent([String].self, forKey: .hidden)?.compactMap(PageCard.init(rawValue:)) ?? []
        self.init(order: order, hidden: Set(hidden))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order.map(\.rawValue), forKey: .order)
        try c.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
    }

    private enum CodingKeys: String, CodingKey { case order, hidden }

    var visible: [PageCard] { order.filter { !hidden.contains($0) } }
}
