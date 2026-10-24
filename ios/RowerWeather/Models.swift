import Foundation

/// Mirrors the backend's JSON (see backend/rowerweather/api.py).

struct Coordinate: Codable, Hashable {
    let lat: Double
    let lon: Double
}

struct Club: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Short name for titles, e.g. "MRC 1880"; older backends send none.
    let shortName: String?
    let address: String
    let website: URL?
    let launchPoint: Coordinate
    let launchPointVerified: Bool
    /// Where an unconfirmed club comes from: "drv" (the German Rowing
    /// Association's club list) or "osm" (OpenStreetMap); nil when confirmed.
    var source: String? = nil
    /// The DRV abbreviation, e.g. "BRG".
    var abbreviation: String? = nil

    var displayName: String { shortName ?? name }

    /// The town from the address, e.g. "Starnberg".
    var town: String? {
        guard let last = address.split(separator: ",").last else { return nil }
        let words = last.split(separator: " ")
        let town = words.drop(while: { $0.allSatisfy(\.isNumber) }).joined(separator: " ")
        return town.isEmpty ? nil : town
    }
}

struct Lake: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let center: Coordinate
    let clubs: [Club]
    /// Whether the backend has the lake's outline, which the lake view needs; older backends send none.
    var hasOutline: Bool? = nil
}

enum Light: String, Codable, Comparable {
    case green, amber, red

    private var rank: Int {
        switch self {
        case .green: 0
        case .amber: 1
        case .red: 2
        }
    }

    static func < (lhs: Light, rhs: Light) -> Bool { lhs.rank < rhs.rank }
}

struct Reason: Codable, Hashable {
    let condition: String
    let light: Light
    /// Set by the app when the user's own limit decided this reason.
    var mine: Bool? = nil

    /// Short label shown under the traffic light.
    var label: String {
        mine == true ? tr("%@ (your limit)", baseLabel) : baseLabel
    }

    /// One sentence saying why this condition changes the advice.
    var explanation: String {
        mine == true ? baseExplanation + " " + tr("You set this limit yourself.") : baseExplanation
    }

    /// For a note: the value is within the user's own limit but above the app's.
    var noteText: String {
        if condition == "cold_margin" {
            return tr("Cold water: the app lowers its wind and gust limits by %@ below %@. Your own limits stay as you set them, so take extra care.",
                      Format.wind(RowingLimits.coldWindMarginMs), Format.temperature(RowingLimits.coldWaterC))
        }
        return tr("%@: above the app's usual limit for %@, within yours. Take extra care.", baseLabel, AppSettings.shared.selectedBoat.inSentence)
    }

    private var baseLabel: String {
        switch condition {
        case "lake_warning": tr("DWD storm warning")
        case "lake_strong_wind": tr("DWD strong-wind warning")
        case "single_cold": tr("Single in cold water")
        case "freezing_water": tr("Near-freezing water")
        case "weather_warning": tr("DWD weather warning")
        case "wind": tr("Wind")
        case "gusts": tr("Gusts")
        case "waves": tr("Waves")
        case "fog": tr("Fog")
        case "heavy_rain": tr("Heavy rain")
        case "hail": tr("Hail")
        case "thunderstorm": tr("Thunderstorm risk")
        case "ice": tr("Ice")
        case "daylight": tr("Sun down")
        case "twilight": tr("Sunrise / sunset")
        case "cold_water": tr("Cold water")
        case "cool_water": tr("Cool water")
        default: condition
        }
    }

    private var baseExplanation: String {
        switch condition {
        case "lake_warning": tr("DWD has issued a storm warning for the lake; its warning lights flash 90 times a minute.")
        case "lake_strong_wind": tr("DWD has issued a strong-wind warning for the lake; its warning lights flash 40 times a minute.")
        case "single_cold": tr("In a single, row with a coach boat or a partner boat while the water is this cold.")
        case "freezing_water": tr("The water is below %@. You are strongly advised not to go out, at least not in a small boat.", Format.temperature(RowingLimits.freezingWaterC))
        case "weather_warning": tr("DWD has issued a weather warning for this place.")
        case "wind": tr("Mean wind is above the limit.")
        case "gusts": tr("Gusts are above the limit.")
        case "waves": tr("Waves at the launch point are too high.")
        case "fog": tr("Visibility is poor (fog or mist).")
        case "heavy_rain": tr("Heavy rain of %@ or more in the hour.", Format.rain(4))
        case "hail": tr("Hail is forecast with a thunderstorm.")
        case "thunderstorm": tr("Thunderstorms are possible.")
        case "ice": light == .red ? tr("Ice on the lake is likely (estimate).") : tr("Thin ice at the shore or drift ice is possible (estimate).")
        case "daylight": tr("The sun is down. Rowing is only advised in daylight.")
        case "twilight": tr("Sunrise or sunset falls in this hour.")
        case "cold_water": tr("Water is below %@, so a capsize is dangerous.", Format.temperature(AppSettings.shared.limits.value(.lifeJacket)))
        case "cool_water": tr("Water is below %@. Take extra care.", Format.temperature(15))
        default: condition
        }
    }

    /// The condition whose icon stands for this reason.
    var symbol: String {
        if condition.hasSuffix("_warning") { return "exclamationmark.triangle.fill" }
        return (Condition.allCases.first { $0.reasonNames.contains(condition) } ?? .wind).symbol
    }
}

struct ForecastHour: Codable, Identifiable, Hashable {
    let time: Date
    let light: Light
    let reasons: [Reason]
    let windSpeedMs: Double?
    let windGustMs: Double?
    let windFromDeg: Double?
    let waveHeightM: Double?
    let fetchM: Double?
    let visibilityM: Double?
    let temperatureC: Double?
    let cloudCoverPct: Double?
    /// Whether the sun is up in the middle of this hour.
    let sunUp: Bool?
    /// Rain, snow or hail in this hour, in mm.
    var precipitationMm: Double? = nil
    /// WMO weather code; see Sky.
    var weatherCode: Int? = nil
    /// How warm it feels, in °C (wind chill, humidity, sun).
    var apparentTemperatureC: Double? = nil
    /// Relative humidity in %, and the dew point in °C.
    var humidityPct: Double? = nil
    var dewPointC: Double? = nil
    /// Air pressure at sea level, in hPa.
    var pressureHpa: Double? = nil
    /// Low, middle and high cloud in % (all cloud is cloudCoverPct).
    var cloudCoverLowPct: Double? = nil
    var cloudCoverMidPct: Double? = nil
    var cloudCoverHighPct: Double? = nil
    /// WHO UV index.
    var uvIndex: Double? = nil
    /// Energy for thunderstorms (CAPE), in J/kg.
    var capeJkg: Double? = nil
    /// Set by the app: conditions above the app's usual limit but within the user's own.
    var notes: [Reason]? = nil

    var id: Date { time }

    func with(reasons: [Reason], sunUp: Bool?) -> ForecastHour {
        ForecastHour(
            time: time, light: reasons.map(\.light).max() ?? .green, reasons: reasons,
            windSpeedMs: windSpeedMs, windGustMs: windGustMs, windFromDeg: windFromDeg,
            waveHeightM: waveHeightM, fetchM: fetchM, visibilityM: visibilityM,
            temperatureC: temperatureC, cloudCoverPct: cloudCoverPct, sunUp: sunUp,
            precipitationMm: precipitationMm, weatherCode: weatherCode,
            apparentTemperatureC: apparentTemperatureC,
            humidityPct: humidityPct, dewPointC: dewPointC, pressureHpa: pressureHpa,
            cloudCoverLowPct: cloudCoverLowPct, cloudCoverMidPct: cloudCoverMidPct, cloudCoverHighPct: cloudCoverHighPct,
            uvIndex: uvIndex, capeJkg: capeJkg, notes: notes
        )
    }

    /// The worst light among these conditions in this hour, or nil when they are all fine.
    func light(for conditions: Set<String>) -> Light? {
        reasons.filter { conditions.contains($0.condition) }.map(\.light).max()
    }
}

struct WaterTemperature: Codable, Hashable {
    let celsius: Double
    let measuredAt: Date
    /// Earlier readings of the station, one per hour, oldest first.
    var history: [WaterReading]? = nil
}

struct WaterReading: Codable, Hashable {
    let time: Date
    let celsius: Double
}

struct SunDay: Codable, Hashable {
    let sunrise: Date
    let sunset: Date
}

/// An official DWD warning: for the lake (strong wind or storm, shown by the
/// shore lights) or for the place (thunderstorm, gusts, frost, fog ...).
struct DWDWarning: Codable, Hashable, Identifiable {
    let kind: String
    let area: String
    let event: String
    /// "minor", "moderate", "severe" or "extreme", as DWD's levels 1 to 4.
    let severity: String
    let headline: String
    let description: String
    let instruction: String?
    let onset: Date?
    let expires: Date?
    /// A made-up warning for the screenshots, never from DWD.
    var sample: Bool? = nil
    /// The warning in English: DWD's own English text where it publishes one
    /// (official), else only the event and headline translated.
    var english: EnglishWarningText? = nil

    var id: String { [kind, area, event, onset?.description ?? "", headline].joined(separator: "|") }
    var isLake: Bool { kind == "lake" }
}

struct EnglishWarningText: Codable, Hashable {
    let event: String
    let headline: String
    let description: String?
    let instruction: String?
    let official: Bool
}

struct Warnings: Codable, Hashable {
    /// "ok" when DWD was checked, "unavailable" when it could not be reached.
    let status: String
    /// DWD's lake warning area for this launch point, nil when the water is not covered.
    let lakeArea: String?
    let items: [DWDWarning]

    var checked: Bool { status == "ok" }
}

/// Which weather models a forecast comes from: the best local model for the
/// first hours, then longer-range ones (backend weather_models.py).
struct ForecastSource: Codable, Hashable {
    struct Part: Codable, Hashable {
        let model: String
        let provider: String
        let resolutionKm: Double
        let fromHour: Int
        let toHour: Int

        /// "DWD" from "Deutscher Wetterdienst (DWD)".
        var providerShort: String {
            guard let open = provider.lastIndex(of: "("), let close = provider.lastIndex(of: ")"), open < close else { return provider }
            return String(provider[provider.index(after: open)..<close])
        }
    }

    let region: String
    let parts: [Part]
}

struct ClubForecast: Codable, Hashable {
    let clubId: String
    let lakeId: String
    let generatedAt: Date
    let waterTemperature: WaterTemperature?
    /// Missing from older backends.
    var warnings: Warnings? = nil
    /// Missing from older backends.
    var ice: IceEstimate? = nil
    let attribution: [String]
    /// Missing from older backends.
    var forecastSource: ForecastSource? = nil
    let daylight: [SunDay]?
    var hours: [ForecastHour]
    /// Yesterday and the next 7 days, for the charts behind the conditions tiles.
    var outlook: [ForecastHour]? = nil

    /// The backend publishes every half hour; after this the forecast counts as out of date.
    static let staleAfter: TimeInterval = 3 * 3600

    /// True when the forecast is older than `staleAfter` at `date`: the app
    /// then warns and shows grey instead of green. `-RWStaleForecast YES`
    /// makes every forecast out of date, for screenshots.
    func isStale(at date: Date = .now) -> Bool {
        UserDefaults.standard.bool(forKey: "RWStaleForecast") || date.timeIntervalSince(generatedAt) > Self.staleAfter
    }

    /// How much the pressure changes from this hour to `hours` later, in hPa.
    func pressureChange(after hour: ForecastHour, hours: Int = 3) -> Double? {
        guard let i = self.hours.firstIndex(where: { $0.time == hour.time }), i + hours < self.hours.count,
              let now = hour.pressureHpa, let later = self.hours[i + hours].pressureHpa else { return nil }
        return later - now
    }

    /// The forecast hour as it stands at `date`. That hour began up to
    /// an hour ago, so "sunrise or sunset within the hour" is replaced by
    /// whether the sun is actually up now.
    func current(at date: Date = .now) -> ForecastHour? {
        // An older forecast still starts hours ago: take the hour `date` falls in.
        guard let first = hours.last(where: { $0.time <= date }) ?? hours.first else { return nil }
        guard let sun = sunState(at: date), first.reasons.contains(where: { $0.condition == "twilight" }) else { return first }
        var reasons = first.reasons.filter { $0.condition != "twilight" }
        var sunUp = true
        if case .down = sun {
            sunUp = false
            reasons.insert(Reason(condition: "daylight", light: .red), at: 0)
        }
        return first.with(reasons: reasons, sunUp: sunUp)
    }

    /// Where the sun stands at `date`: up until sunset, or down until the next sunrise.
    func sunState(at date: Date) -> SunState? {
        guard let days = daylight?.sorted(by: { $0.sunrise < $1.sunrise }) else { return nil }
        if let today = days.first(where: { $0.sunrise <= date && date < $0.sunset }) {
            return .up(sunrise: today.sunrise, sunset: today.sunset)
        }
        if let next = days.first(where: { $0.sunrise > date }) {
            return .down(nextSunrise: next.sunrise, nextSunset: next.sunset)
        }
        return nil
    }
}

/// The backend's ice estimate for the lake, from frost and water temperature
/// (see backend/rowerweather/ice.py). It never says ice is safe to walk on.
struct IceEstimate: Codable, Hashable {
    /// "open", "edges" (thin ice at the shore possible), "forming", "frozen",
    /// "drift_ice" (rivers) or "unavailable".
    let status: String
    let light: Light?
    var thicknessCm: Double? = nil
    /// Measured where the lake has a station, else modelled.
    var waterTemperatureC: Double? = nil
    /// "season" (no ice this month), "measured" (the water is too warm),
    /// "satellite" (the satellite picture corrected the model) or "model".
    var basis: String? = nil
    var days: [IceDay]? = nil
    /// The latest satellite picture that saw the lake (larger lakes only).
    var satellite: IceSatellite? = nil

    var title: String {
        switch status {
        case "open": tr("No ice")
        case "edges": tr("Shore ice possible")
        case "forming": tr("Ice forming")
        case "frozen": tr("Ice cover likely")
        case "drift_ice": tr("Drift ice possible")
        default: tr("No data")
        }
    }

    /// One line on how the estimate was made.
    var detail: String {
        if let cm = thicknessCm, cm > 0 {
            return tr("About %@ cm, estimated", Format.number(cm))
        }
        if let satellite, basis == "satellite" || basis == "model" {
            return satellite.summary
        }
        switch basis {
        case "season": return tr("No ice this time of year")
        case "measured": return tr("Water %@, too warm for ice", Format.temperature(waterTemperatureC, digits: 1))
        case "model": return status == "edges" ? tr("Bays and harbours first") : tr("Estimated from frost")
        default: return tr("Check the lake yourself")
        }
    }
}

/// Copernicus Lake Ice Extent: what a cloud-free satellite pass saw of the lake.
struct IceSatellite: Codable, Hashable {
    /// Local calendar day, "yyyy-MM-dd".
    let date: String
    /// Share of the lake that was seen (not under cloud), 0...1.
    let seenShare: Double
    /// Share of the seen part that was ice, 0...1.
    let iceShare: Double

    /// "Satellite, Today: open water" or "Satellite, Mon 20 Jan: 60 % ice".
    var summary: String {
        let day = Self.parser.date(from: date).map { Format.day($0) } ?? date
        if iceShare < 0.1 { return tr("Satellite, %@: open water", day) }
        return tr("Satellite, %@: %@ %% ice", day, Format.number(iceShare * 100))
    }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct IceDay: Codable, Hashable {
    /// Local calendar day, "yyyy-MM-dd".
    let date: String
    let status: String
    var thicknessCm: Double? = nil
}

enum SunState: Hashable {
    case up(sunrise: Date, sunset: Date)
    case down(nextSunrise: Date, nextSunset: Date)
}
