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

    /// Short label shown under the traffic light.
    var label: String {
        switch condition {
        case "lake_warning": "Lake storm warning"
        case "wind": "Wind"
        case "gusts": "Gusts"
        case "waves": "Waves"
        case "fog": "Fog"
        case "thunderstorm": "Thunderstorm risk"
        case "ice": "Ice"
        case "daylight": "Sun down"
        case "twilight": "Sunrise / sunset"
        case "cold_water": "Cold water"
        case "cool_water": "Cool water"
        default: condition
        }
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

    var id: Date { time }

    func with(reasons: [Reason], sunUp: Bool?) -> ForecastHour {
        ForecastHour(
            time: time, light: reasons.map(\.light).max() ?? .green, reasons: reasons,
            windSpeedMs: windSpeedMs, windGustMs: windGustMs, windFromDeg: windFromDeg,
            waveHeightM: waveHeightM, fetchM: fetchM, visibilityM: visibilityM,
            temperatureC: temperatureC, cloudCoverPct: cloudCoverPct, sunUp: sunUp
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
}

struct SunDay: Codable, Hashable {
    let sunrise: Date
    let sunset: Date
}

struct ClubForecast: Codable, Hashable {
    let clubId: String
    let lakeId: String
    let generatedAt: Date
    let waterTemperature: WaterTemperature?
    let attribution: [String]
    let daylight: [SunDay]?
    let hours: [ForecastHour]

    /// The first forecast hour as it stands at `date`. That hour began up to
    /// an hour ago, so "sunrise or sunset within the hour" is replaced by
    /// whether the sun is actually up now.
    func current(at date: Date = .now) -> ForecastHour? {
        guard let first = hours.first else { return nil }
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

enum SunState: Hashable {
    case up(sunrise: Date, sunset: Date)
    case down(nextSunrise: Date, nextSunset: Date)
}
