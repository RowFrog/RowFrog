import SwiftUI

/// The conditions the app shows, with the SF Symbol used for each.
/// The same icons head the hourly table and label the current conditions,
/// so the legend explains both.
enum Condition: String, CaseIterable, Identifiable {
    case temperature, feelsLike, wind, waves, waterTemperature, precipitation, visibility, cloudCover, thunderstorm, ice, daylight

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .feelsLike: "thermometer.variable.and.figure"
        case .wind: "wind"
        case .waves: "water.waves"
        case .waterTemperature: "thermometer.and.liquid.waves"
        case .precipitation: "cloud.rain"
        case .visibility: "binoculars"
        case .cloudCover: "cloud"
        case .thunderstorm: "cloud.bolt"
        case .ice: "snowflake"
        case .daylight: "sun.horizon"
        }
    }

    var title: String {
        switch self {
        case .temperature: tr("Air temperature")
        case .feelsLike: tr("Feels like")
        case .wind: tr("Wind and gusts")
        case .waves: tr("Waves")
        case .waterTemperature: tr("Water temperature")
        case .precipitation: tr("Rain, hail, snow")
        case .visibility: tr("Visibility (fog)")
        case .cloudCover: tr("Cloud cover")
        case .thunderstorm: tr("Thunderstorm risk")
        case .ice: tr("Ice cover")
        case .daylight: tr("Daylight")
        }
    }

    /// Unit shown under the icon in the hourly table header.
    var unit: String {
        switch self {
        case .temperature, .feelsLike, .waterTemperature: AppSettings.shared.temperatureUnit.symbol
        case .wind: AppSettings.shared.windUnit.symbol
        case .waves: AppSettings.shared.waveUnit.symbol
        case .precipitation: AppSettings.shared.rainUnit.symbol
        case .visibility: AppSettings.shared.distanceUnit.symbol
        case .cloudCover: "%"
        case .thunderstorm, .ice, .daylight: ""
        }
    }

    var explanation: String {
        switch self {
        case .temperature: tr("Air temperature at 2 m.")
        case .feelsLike: tr("How warm or cold it feels on the water, from air temperature, wind, humidity and sun.")
        case .wind: tr("Mean wind – strongest gust, in %@. The arrow points where the wind blows to.", unit)
        case .waves: tr("Estimated wave height at the launch point, from wind and open water upwind.")
        case .waterTemperature: tr("Latest lake measurement. Below %@, extra care; below %@, cold water.", Format.temperature(15), Format.temperature(10))
        case .precipitation: tr("What falls in the hour (rain, drizzle, snow, hail) and how much, in %@. Hail comes with thunderstorms.", unit)
        case .visibility: tr("How far you can see. Fog below %@ is amber, below %@ red.", Format.distance(1000), Format.distance(500))
        case .cloudCover: tr("Share of the sky covered by cloud.")
        case .thunderstorm: tr("Estimated from the forecast. DWD thunderstorm warnings for the place appear under DWD warnings.")
        case .ice: tr("Not available yet. Check the lake yourself in winter.")
        case .daylight: tr("Rowing is only advised while the sun is up. Hours with sunrise or sunset are amber, dark hours red.")
        }
    }

    /// Backend reason names that belong to this condition.
    var reasonNames: Set<String> {
        switch self {
        case .wind: ["wind", "gusts", "lake_warning"]
        case .waves: ["waves"]
        case .waterTemperature: ["cold_water", "cool_water"]
        case .visibility: ["fog"]
        case .thunderstorm: ["thunderstorm"]
        case .ice: ["ice"]
        case .daylight: ["daylight", "twilight"]
        case .temperature, .feelsLike, .cloudCover, .precipitation: []
        }
    }
}

struct ConditionIcon: View {
    let condition: Condition

    var body: some View {
        Image(systemName: condition.symbol)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel(condition.title)
    }
}

enum Format {
    /// 24-hour clock as used in Germany, whatever the phone's region.
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return tr("Today") }
        if calendar.isDateInTomorrow(date) { return tr("Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale))
    }

    /// "Today 21:00", "Tomorrow 03:00" or "Mon 21:00".
    static func dayTime(_ date: Date, calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDateInToday(date) {
            day = tr("Today")
        } else if calendar.isDateInTomorrow(date) {
            day = tr("Tomorrow")
        } else {
            day = date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        }
        return "\(day) \(time(date))"
    }

    static func number(_ value: Double?, digits: Int = 0) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    /// Numbers and dates follow the language chosen in the settings.
    static var locale: Locale { AppSettings.shared.locale }

    static func compass(_ degrees: Double) -> String {
        let points = AppSettings.shared.resolvedLanguage == .german
            ? ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
            : ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return points[Int((degrees / 45).rounded()) % 8]
    }

    static func duration(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()
}
