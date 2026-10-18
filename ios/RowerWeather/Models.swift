import Foundation

/// Mirrors the backend's JSON (see backend/rowerweather/api.py).

struct Coordinate: Codable, Hashable {
    let lat: Double
    let lon: Double
}

struct Club: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let website: URL?
    let launchPoint: Coordinate
    let launchPointVerified: Bool
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
        case "daylight": "Dark"
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

    var id: Date { time }
}

struct WaterTemperature: Codable, Hashable {
    let celsius: Double
    let measuredAt: Date
}

struct ClubForecast: Codable, Hashable {
    let clubId: String
    let lakeId: String
    let generatedAt: Date
    let waterTemperature: WaterTemperature?
    let attribution: [String]
    let hours: [ForecastHour]
}
