import SwiftUI

/// The weather in an hour as the iOS Weather app shows it: a coloured
/// symbol (sun, cloud, rain, hail ...) and a word. Built from the WMO weather
/// code DWD's model gives; without one, from cloud cover and precipitation.
enum Sky: CaseIterable {
    case clear, mostlyClear, partlyCloudy, cloudy, fog, drizzle, rain, showers, heavyRain,
         freezingRain, snow, thunderstorm, hail

    init(code: Int?, cloudCoverPct: Double?, precipitationMm: Double?) {
        switch code {
        case 0: self = .clear
        case 1: self = .mostlyClear
        case 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57, 66, 67: self = .freezingRain
        case 61, 63: self = .rain
        case 80, 81: self = .showers
        case 65, 82: self = .heavyRain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95: self = .thunderstorm
        case 96, 99: self = .hail
        default:
            let rain = precipitationMm ?? 0
            let cloud = cloudCoverPct ?? 0
            if rain >= 4 { self = .heavyRain }
            else if rain >= 0.1 { self = .rain }
            else if cloud >= 80 { self = .cloudy }
            else if cloud >= 40 { self = .partlyCloudy }
            else if cloud >= 15 { self = .mostlyClear }
            else { self = .clear }
        }
    }

    init(hour: ForecastHour) {
        self.init(code: hour.weatherCode, cloudCoverPct: hour.cloudCoverPct, precipitationMm: hour.precipitationMm)
    }

    /// SF Symbol; night variants show a moon.
    func symbol(night: Bool = false) -> String {
        switch self {
        case .clear: night ? "moon.stars.fill" : "sun.max.fill"
        case .mostlyClear: night ? "moon.fill" : "sun.max.fill"
        case .partlyCloudy: night ? "cloud.moon.fill" : "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain, .showers: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .freezingRain: "cloud.sleet.fill"
        case .snow: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.fill"
        case .hail: "cloud.hail.fill"
        }
    }

    /// Colours for the symbol's layers: the cloud first, then sun, moon, rain,
    /// snow, hail or lightning. The Weather app's multicolour symbols draw
    /// clouds white, which vanishes on the app's light cards, so clouds are gray.
    func colors(night: Bool = false) -> (Color, Color) {
        let cloud = Color(.systemGray)
        let sun = Color.yellow
        let moon = Color.indigo
        switch self {
        case .clear, .mostlyClear: return night ? (moon, sun) : (sun, sun)
        case .partlyCloudy: return (cloud, night ? moon : sun)
        case .cloudy, .fog: return (cloud, cloud)
        case .drizzle, .rain, .showers, .heavyRain: return (cloud, .blue)
        case .freezingRain, .snow, .hail: return (cloud, .cyan)
        case .thunderstorm: return (cloud, sun)
        }
    }

    var title: String {
        switch self {
        case .clear: tr("Clear")
        case .mostlyClear: tr("Mostly clear")
        case .partlyCloudy: tr("Partly cloudy")
        case .cloudy: tr("Cloudy")
        case .fog: tr("Fog")
        case .drizzle: tr("Drizzle")
        case .rain: tr("Rain")
        case .showers: tr("Showers")
        case .heavyRain: tr("Heavy rain")
        case .freezingRain: tr("Freezing rain")
        case .snow: tr("Snow")
        case .thunderstorm: tr("Thunderstorm")
        case .hail: tr("Thunderstorm with hail")
        }
    }

    /// What falls, for the precipitation value: "Rain", "Hail", "Snow" ... or nil when nothing does.
    var precipitationKind: String? {
        switch self {
        case .drizzle: tr("Drizzle")
        case .rain, .showers, .heavyRain, .thunderstorm: tr("Rain")
        case .freezingRain: tr("Freezing rain")
        case .snow: tr("Snow")
        case .hail: tr("Hail")
        default: nil
        }
    }
}

struct SkyIcon: View {
    let sky: Sky
    var night = false

    var body: some View {
        let colors = sky.colors(night: night)
        Image(systemName: sky.symbol(night: night))
            .symbolRenderingMode(.palette)
            .foregroundStyle(colors.0, colors.1)
            .accessibilityLabel(sky.title)
    }
}

/// "Rain 0.4 mm", "Hail 2.1 mm", or nil when nothing falls.
func precipitationText(_ hour: ForecastHour) -> String? {
    let sky = Sky(hour: hour)
    guard let mm = hour.precipitationMm else { return sky.precipitationKind ?? "–" }
    if mm < 0.05 && sky.precipitationKind == nil { return nil }
    return "\(sky.precipitationKind ?? tr("Rain")) \(Format.rain(mm))"
}

extension ForecastHour {
    /// Something falls in this hour: 0.1 mm or more, or a weather code that
    /// names it (drizzle under 0.1 mm), so the rain tile never says dry beside
    /// a drizzle symbol.
    var isWet: Bool { (precipitationMm ?? 0) >= 0.1 || Sky(hour: self).precipitationKind != nil }
}
