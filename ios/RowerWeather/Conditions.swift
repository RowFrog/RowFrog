import SwiftUI

/// The conditions the app shows, with the SF Symbol used for each.
/// The same icons head the hourly table and label the current conditions,
/// so the legend explains both.
enum Condition: String, CaseIterable, Identifiable {
    case temperature, wind, waves, waterTemperature, visibility, cloudCover, thunderstorm, ice, daylight

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .wind: "wind"
        case .waves: "water.waves"
        case .waterTemperature: "thermometer.and.liquid.waves"
        case .visibility: "cloud.fog"
        case .cloudCover: "cloud"
        case .thunderstorm: "cloud.bolt"
        case .ice: "snowflake"
        case .daylight: "sun.horizon"
        }
    }

    var title: String {
        switch self {
        case .temperature: "Air temperature"
        case .wind: "Wind and gusts"
        case .waves: "Waves"
        case .waterTemperature: "Water temperature"
        case .visibility: "Visibility (fog)"
        case .cloudCover: "Cloud cover"
        case .thunderstorm: "Thunderstorm risk"
        case .ice: "Ice cover"
        case .daylight: "Daylight"
        }
    }

    /// Unit shown under the icon in the hourly table header.
    var unit: String {
        switch self {
        case .temperature, .waterTemperature: "°C"
        case .wind: "m/s"
        case .waves: "m"
        case .visibility: "km"
        case .cloudCover: "%"
        case .thunderstorm, .ice, .daylight: ""
        }
    }

    var explanation: String {
        switch self {
        case .temperature: "Air temperature at 2 m."
        case .wind: "Mean wind – strongest gust, in m/s. The arrow points where the wind blows to."
        case .waves: "Estimated wave height at the launch point, from wind and open water upwind."
        case .waterTemperature: "Latest lake measurement. Below 15 °C, extra care; below 10 °C, cold water."
        case .visibility: "How far you can see. Fog below 1 km is amber, below 500 m red."
        case .cloudCover: "Share of the sky covered by cloud."
        case .thunderstorm: "Estimated from the forecast until DWD warnings are added."
        case .ice: "Not available yet. Check the lake yourself in winter."
        case .daylight: "Rowing is only advised while the sun is up. Hours with sunrise or sunset are amber, dark hours red."
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
        case .temperature, .cloudCover: []
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
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    static func number(_ value: Double?, digits: Int = 0) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func compass(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
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
