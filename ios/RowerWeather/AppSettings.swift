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
    static let shared = AppSettings(defaults: WidgetShared.defaults)
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
    var timeFormat: TimeFormat { didSet { defaults.set(timeFormat.rawValue, forKey: Keys.timeFormat) } }
    var dateFormat: DateFormat { didSet { defaults.set(dateFormat.rawValue, forKey: Keys.dateFormat) } }

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
        static let timeFormat = "RWTimeFormat"
        static let dateFormat = "RWDateFormat"
        static let background = "RWBackground"
        static let pageBackgrounds = "RWBackgroundPages"
        static let clubBackgrounds = "RWBackgroundClubs"
        static let blur = "RWBackgroundBlur"
        static let tileStyle = "RWTileStyle"
        static let userPictures = "RWUserPictures"

        static let all = [appearance, language, landscape, temperature, wind, waves, rain, distance, timeFormat, dateFormat,
                          background, pageBackgrounds, clubBackgrounds, blur, tileStyle, userPictures]
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
        timeFormat = value(Keys.timeFormat, .hours24)
        dateFormat = value(Keys.dateFormat, .device)
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
    }

    /// The language the app shows: the chosen one, or the phone's when it is German.
    var resolvedLanguage: AppLanguage {
        switch language {
        case .device: Locale.preferredLanguages.first?.hasPrefix("de") == true ? .german : .english
        default: language
        }
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

    /// Factory settings: every preference back to its default and the user's pictures deleted.
    /// Saved locations and the home base are not settings and stay.
    func resetToFactorySettings() {
        for name in userPictures { BackgroundLibrary.deleteUserPicture(name) }
        for key in Keys.all { defaults.removeObject(forKey: key) }
        appearance = .device
        language = .device
        allowsLandscape = true
        temperatureUnit = .celsius
        windUnit = .metersPerSecond
        waveUnit = .meters
        rainUnit = .millimeters
        distanceUnit = .kilometers
        timeFormat = .hours24
        dateFormat = .device
        removeAllBackgrounds()
        userPictures = []
        // The assignments above write the defaults back; remove them so a later
        // change of the app's defaults reaches users who never chose.
        for key in Keys.all { defaults.removeObject(forKey: key) }
    }

    /// A picture the user removed can no longer be shown anywhere.
    func forgetUserPicture(_ name: String) {
        let gone = BackgroundChoice.custom(name)
        if allPagesBackground == gone { allPagesBackground = .noPicture }
        pageBackgrounds = pageBackgrounds.filter { $0.value != gone }
        clubBackgrounds = clubBackgrounds.filter { $0.value != gone }
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

/// How the cards look over a background picture.
enum TileStyle: String, CaseIterable, Identifiable {
    /// Frosted glass: the picture shows through, blurred, under a light rowing-light tint.
    case frosted
    /// Solid: no picture in the cards, which keep their full rowing-light shading.
    case solid
    var id: String { rawValue }

    var title: String {
        switch self {
        case .frosted: tr("Picture blurred")
        case .solid: tr("No picture")
        }
    }
}

enum BackgroundChoice: Hashable {
    case noPicture
    /// One of the pictures that come with the app, by id.
    case sample(String)
    /// A picture the user added, by file name.
    case custom(String)

    init?(rawValue: String) {
        if rawValue == "none" { self = .noPicture; return }
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
        case let .sample(id): "sample:\(id)"
        case let .custom(name): "custom:\(name)"
        }
    }

    var title: String {
        switch self {
        case .noPicture: tr("No picture")
        case let .sample(id): BackgroundLibrary.sample(id)?.title ?? id
        case .custom: tr("Your picture")
        }
    }
}
