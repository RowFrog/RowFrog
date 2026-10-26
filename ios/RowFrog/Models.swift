import Foundation

/// Mirrors the backend's JSON (see backend/rowfrog/api.py).

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
    /// ISO country code in lower case, e.g. "at"; older backends send none (Germany).
    var country: String? = nil
    /// The state or canton where the source names one, e.g. "Wien".
    var region: String? = nil

    var displayName: String { shortName ?? name }

    /// A place the user put on the map, kept only on this iPhone (see OwnPlaces.swift).
    var isOwnPlace: Bool { id.hasPrefix(OwnPlace.idPrefix) }
    var countryCode: String { country ?? "de" }

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
    var country: String? = nil

    /// The name to show. Clubs whose water the catalogs don't name sit under
    /// "Water near <town>", which reads in the app's language.
    var title: String {
        let prefix = "Water near "
        return name.hasPrefix(prefix) ? tr("Water near %@", String(name.dropFirst(prefix.count))) : name
    }

    /// The catalogs didn't name the club's water ("Water near <town>").
    var waterUnknown: Bool { name.hasPrefix("Water near ") }

    /// The country list's name: the water, or the town when the water isn't known,
    /// so such a club sorts under its town's letter.
    var listTitle: String { waterUnknown ? String(name.dropFirst("Water near ".count)) : name }

    /// "Starnberger See · Starnberg"; just the town when the water isn't known,
    /// rather than "Water near Aken · Aken".
    static func place(_ lake: Lake?, town: String?) -> String {
        let water = lake?.waterUnknown == true && town != nil ? nil : lake?.title
        return [water, town].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A country the club search covers (GET countries/index).
struct Country: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let nameDe: String
    /// How many clubs the country's file holds.
    let clubs: Int
    /// The box around the country's clubs.
    let bounds: Bounds

    var id: String { code }

    var localizedName: String { AppSettings.shared.resolvedLanguage == .german ? nameDe : name }

    /// The flag emoji, from the two letters of the code.
    var flag: String { Self.flag(code) }

    static func flag(_ code: String) -> String {
        String(code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(Character.init))
    }

    struct Bounds: Codable, Hashable {
        let south: Double
        let west: Double
        let north: Double
        let east: Double

        /// Rough distance in km from `point` to the box, 0 inside it.
        func distance(to point: Coordinate) -> Double {
            let lat = min(max(point.lat, south), north)
            let lon = min(max(point.lon, west), east)
            let x = (point.lon - lon) * cos(point.lat * .pi / 180)
            let y = point.lat - lat
            return (x * x + y * y).squareRoot() * 111.2
        }
    }
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
        case "weather_warning": tr("Official weather warning")
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
        case "cold_water": tr("Very cold water")
        case "cool_water": tr("Cold-water shock possible")
        default: condition
        }
    }

    private var baseExplanation: String {
        switch condition {
        case "lake_warning": tr("DWD has issued a storm warning for the lake; its warning lights flash 90 times a minute.")
        case "lake_strong_wind": tr("DWD has issued a strong-wind warning for the lake; its warning lights flash 40 times a minute.")
        case "single_cold": tr("In a single, row with a coach boat or a partner boat while the water is this cold.")
        case "freezing_water": tr("The water is below %@. You are strongly advised not to go out, at least not in a small boat.", Format.temperature(RowingLimits.freezingWaterC))
        case "weather_warning": tr("An official weather warning is out for this place.")
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
        case "cold_water": tr("Very cold water, below %@: wear a life jacket, stay near the shore and don't row alone.", Format.temperature(RowingLimits.coldWaterC))
        case "cool_water": tr("Water is below %@: a capsize can cause cold-water shock. We advise a life jacket.", Format.temperature(15))
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
    /// Where the station is; older backends send none.
    var station: WaterStation? = nil
}

/// The station that measures the water temperature.
struct WaterStation: Codable, Hashable {
    /// "gkd" (Gewässerkundlicher Dienst Bayern), "pegelonline" (federal
    /// waterways, Germany) or "bafu" (Swiss federal stations); older backends send none.
    var network: String?
    var name: String?
    var lat: Double?
    var lon: Double?
    /// From the club's launch point, in metres.
    var distanceM: Double?
    /// The station's page at the Gewässerkundlicher Dienst Bayern.
    var url: URL?

    /// Who runs the station, for the detail sheet's source line.
    var operatorName: String {
        switch network {
        case "pegelonline": tr("PEGELONLINE, the federal waterways and shipping administration (WSV)")
        case "bafu": tr("Swiss Federal Office for the Environment (BAFU)")
        default: tr("Gewässerkundlicher Dienst Bayern (LfU)")
        }
    }

    var coordinate: Coordinate? {
        guard let lat, let lon else { return nil }
        return Coordinate(lat: lat, lon: lon)
    }
}

struct WaterReading: Codable, Hashable {
    let time: Date
    let celsius: Double
}

/// One day of the water forecast: the date as the backend writes it ("2026-10-27").
struct WaterDay: Codable, Hashable {
    let date: String
    let celsius: Double

    /// Midday of that day in the phone's time zone, so it sits inside the day anywhere nearby.
    var day: Date? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
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
    /// "dwd" or "geosphere"; missing from older backends, which had DWD only.
    var source: String? = nil

    var id: String { [kind, area, event, onset?.description ?? "", headline].joined(separator: "|") }
    var isDWD: Bool { (source ?? "dwd") == "dwd" }
    /// Short name of the service that issued it, for labels.
    var serviceShort: String { warningServiceShort(source) }
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
    /// Whose weather warnings count for the place and whether they were checked;
    /// missing from older backends, which checked DWD for every club.
    var local: LocalWarnings? = nil

    var checked: Bool { status == "ok" }
    /// False where the app reads no warning service for the place (Switzerland
    /// for now), so "no warning" must not be said.
    var localChecked: Bool { local?.checked ?? true }
    /// True while the place's warnings are DWD's (Germany, and older backends).
    var isDWD: Bool { (local?.source ?? "dwd") == "dwd" }
}

/// The weather service that warns for a place (DWD, GeoSphere Austria, MeteoSwiss).
struct LocalWarnings: Codable, Hashable {
    /// "dwd", "geosphere" or "meteoswiss"; missing from the first backends with `local`.
    var source: String? = nil
    let service: String?
    let url: String?
    let checked: Bool
}

/// "DWD", "GeoSphere" or "MeteoSwiss", for labels such as "GeoSphere warning: Wind".
func warningServiceShort(_ source: String?) -> String {
    switch source {
    case "geosphere": "GeoSphere"
    case "meteoswiss": "MeteoSwiss"
    default: "DWD"
    }
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
    /// The model the user picked instead of the automatic choice (a hidden test).
    var picked: String? = nil
    let parts: [Part]
}

/// A weather model that can be picked instead of the automatic choice, for
/// the confirmed clubs only (a test behind the developer options).
struct ModelChoice: Codable, Hashable, Identifiable {
    let id: String
    let model: String
    let provider: String
    let resolutionKm: Double
    let hours: Int
    /// "ok" or "notAdvised".
    let advice: String
    let note: String

    var notAdvised: Bool { advice == "notAdvised" }
}

extension ClubForecast {
    /// Without a station: the newest satellite reading carried forward to
    /// today with the air temperatures, else the water worked out from the air
    /// temperatures of the last weeks (the backend's, or the ice model's).
    var estimatedWaterC: Double? {
        guard waterTemperature == nil else { return nil }
        if let waterEstimate { return waterEstimate.celsius }
        if let waterModelC { return waterModelC }
        guard let ice, ice.basis == "model" || ice.basis == "satellite" else { return nil }
        return ice.waterTemperatureC
    }

    /// The ice value for the top tile and the widgets, only when it matters:
    /// the estimate says more than open water, or the water is cold enough to freeze.
    var iceValue: String? {
        if let ice, ice.status != "unavailable", ice.status != "open" { return ice.title }
        if let c = waterTemperature?.celsius, c < 8 { return ice.map(\.title) ?? tr("No data yet") }
        return nil
    }
}

/// Without a station: a satellite reading of the lake's surface temperature
/// carried forward to today with the daily air temperatures (backend water_estimate.py).
struct WaterEstimate: Codable, Hashable {
    let celsius: Double
    /// "satellite".
    let basis: String
    let reading: SatelliteWaterReading
}

struct SatelliteWaterReading: Codable, Hashable {
    /// "copernicus-lswt" (Sentinel-3, a 10-day mean) or "landsat" (one pass).
    let source: String
    /// "landsat-8" or "landsat-9"; none for Copernicus.
    var platform: String? = nil
    /// Local calendar day, "yyyy-MM-dd"; the middle of the period for Copernicus.
    let date: String
    /// The 10-day period of a Copernicus file, "yyyy-MM-dd".
    var from: String? = nil
    var to: String? = nil
    let celsius: Double

    /// "Landsat 9" or "Copernicus (Sentinel-3)".
    var satelliteName: String {
        if source == "landsat" {
            return platform.map { $0.replacingOccurrences(of: "landsat-", with: "Landsat ") } ?? "Landsat"
        }
        return tr("Copernicus (Sentinel-3)")
    }

    /// "Wed 9 Oct", or for Copernicus "1 Oct – 10 Oct".
    var when: String {
        let day: (String) -> String = { text in IceSatellite.parser.date(from: text).map { Format.day($0) } ?? text }
        if let from, let to { return day(from) + " – " + day(to) }
        return day(date)
    }
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
    /// Other models this club's forecast can come from; empty for most clubs.
    var modelChoices: [ModelChoice]? = nil
    let daylight: [SunDay]?
    var hours: [ForecastHour]
    /// Yesterday and the next 7 days, for the charts behind the conditions tiles.
    var outlook: [ForecastHour]? = nil
    /// DWD's rain radar at the launch point for the widget, for the clubs people use.
    var radar: RainRadar? = nil
    /// How often the backend renews this club; missing without the usage counter.
    var refresh: Refresh? = nil
    /// Without a station, for lakes the satellites see; missing from older backends.
    var waterEstimate: WaterEstimate? = nil
    /// Without a station or a recent satellite reading: worked out from the air
    /// temperatures alone, all year; missing from older backends.
    var waterModelC: Double? = nil
    /// Today's water carried on with the forecast air, one value per day (lakes
    /// only); missing from older backends.
    var waterForecast: [WaterDay]? = nil

    /// The forecast water for the day of `date`, nil past the forecast.
    func waterForecastC(on date: Date) -> Double? {
        waterForecast?.first { $0.day.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }?.celsius
    }

    /// The backend publishes every half hour; after this the forecast counts as out of date.
    static let staleAfter: TimeInterval = 3 * 3600

    /// True when the forecast is older than `staleAfter` at `date`: the app
    /// then warns and shows grey instead of green. `-RWStaleForecast YES`
    /// makes every forecast out of date, for screenshots.
    func isStale(at date: Date = .now) -> Bool {
        UserDefaults.standard.bool(forKey: "RWStaleForecast") || date.timeIntervalSince(generatedAt) > Self.staleAfter
    }

    /// True for a club nobody opened lately: its file comes every 6 hours and
    /// its weather every 12 until the next half-hourly run takes it up.
    /// `-RWSlowRefresh YES` shows it on every club, for screenshots.
    var isSlowRefresh: Bool {
        UserDefaults.standard.bool(forKey: "RWSlowRefresh") || refresh?.used == false
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

    /// A reason's sentence for `hour`; "sunrise or sunset in this hour" says
    /// which, and when.
    func explanation(_ reason: Reason, in hour: ForecastHour) -> String {
        guard reason.condition == "twilight", let days = daylight else { return reason.explanation }
        let end = hour.time.addingTimeInterval(3600)
        if let rise = days.map(\.sunrise).first(where: { $0 >= hour.time && $0 < end }) {
            return tr("Sunrise at %@ in this hour.", Format.time(rise))
        }
        if let set = days.map(\.sunset).first(where: { $0 >= hour.time && $0 < end }) {
            return tr("Sunset at %@ in this hour.", Format.time(set))
        }
        return reason.explanation
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
/// (see backend/rowfrog/ice.py). It never says ice is safe to walk on.
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

/// The months the backend works out ice for (ICE_MONTHS in backend/rowfrog/ice.py).
enum IceSeason {
    static let months: Set<Int> = [11, 12, 1, 2, 3, 4]

    /// Out of season: the backend said so, or sent nothing in a month without ice.
    static func isOff(_ ice: IceEstimate?, at date: Date = .now) -> Bool {
        if let ice, ice.status != "unavailable" { return ice.basis == "season" }
        return !months.contains(Calendar.current.component(.month, from: date))
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

    static let parser: DateFormatter = {
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

/// Rain at the launch point from DWD's radar: now and DWD's nowcast for the
/// next two hours. The app reads it from DWD every 5 minutes while a club page
/// is open (RadarClient); the backend adds it to the forecast files of the
/// clubs people use every 30 minutes, for the widget's radar line.
/// Source: WMS layer dwd:Niederschlagsradar (RV product, 1 km), read at the
/// launch point with GetFeatureInfo; no rain comes back as a tiny negative value.
struct RadarStep: Codable, Hashable {
    let time: Date
    let mmPerHour: Double
}

/// The backend renews the clubs people opened in the last 7 days every half
/// hour (weather after every model run, 3 hours), the others less often.
struct Refresh: Codable, Hashable {
    let used: Bool
    let fileEveryHours: Double
    let weatherEveryHours: Double
}

struct RainRadar: Codable, Hashable {
    /// The radar picture the nowcast starts from.
    let reference: Date
    /// Now and every 15 minutes up to two hours ahead.
    let steps: [RadarStep]

    static let rainFrom = 0.1  // mm/h; less is noise or drizzle that does not count

    var rainingNow: Bool { (steps.first?.mmPerHour ?? 0) >= Self.rainFrom }
    var firstRain: RadarStep? { steps.first { $0.mmPerHour >= Self.rainFrom } }
    var dryAgain: RadarStep? {
        guard rainingNow else { return nil }
        return steps.first { $0.mmPerHour < Self.rainFrom }
    }
    var peak: Double { steps.map(\.mmPerHour).max() ?? 0 }

    /// The steps from `date` on, for the widget's later entries; none once
    /// fewer than 30 minutes of the nowcast are left.
    func ahead(of date: Date) -> RainRadar? {
        let left = steps.filter { $0.time > date.addingTimeInterval(-7.5 * 60) }
        guard left.count >= 3 else { return nil }
        return RainRadar(reference: reference, steps: left)
    }

    /// One line, e.g. "Light rain from 21:30".
    var summary: String {
        guard let first = firstRain else { return tr("No rain in the next 2 hours") }
        if rainingNow {
            if let dry = dryAgain { return tr("%@ now, dry from %@", Self.intensity(peak), Format.time(dry.time)) }
            return tr("%@ for the next 2 hours", Self.intensity(peak))
        }
        return tr("%@ from %@", Self.intensity(peak), Format.time(first.time))
    }

    static func intensity(_ mmPerHour: Double) -> String {
        switch mmPerHour {
        case ..<2.5: tr("Light rain")
        case ..<10: tr("Rain")
        default: tr("Heavy rain")
        }
    }
}
