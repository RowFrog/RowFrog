import Foundation

/// Units the user can pick for each value. The backend always sends metric
/// values (°C, m/s, m, mm, m); they are converted only for display.

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }

    var symbol: String { self == .celsius ? "°C" : "°F" }
    var title: String { self == .celsius ? tr("Celsius") : tr("Fahrenheit") }

    func convert(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }
}

enum SpeedUnit: String, CaseIterable, Identifiable {
    case metersPerSecond, kilometersPerHour, knots, milesPerHour, beaufort
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .metersPerSecond: "m/s"
        case .kilometersPerHour: "km/h"
        case .knots: "kn"
        case .milesPerHour: "mph"
        case .beaufort: "Bft"
        }
    }

    var title: String {
        switch self {
        case .metersPerSecond: tr("Metres per second")
        case .kilometersPerHour: tr("Kilometres per hour")
        case .knots: tr("Knots")
        case .milesPerHour: tr("Miles per hour")
        case .beaufort: tr("Beaufort")
        }
    }

    func convert(_ ms: Double) -> Double {
        switch self {
        case .metersPerSecond: ms
        case .kilometersPerHour: ms * 3.6
        case .knots: ms * 3600 / 1852
        case .milesPerHour: ms * 3600 / 1609.344
        case .beaufort: Double(Self.beaufort(ms))
        }
    }

    /// Upper limits of Beaufort 0 to 11 in m/s; above the last is 12.
    private static let beaufortLimits = [0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7]

    static func beaufort(_ ms: Double) -> Int {
        beaufortLimits.firstIndex { ms < $0 } ?? 12
    }
}

enum WaveUnit: String, CaseIterable, Identifiable {
    case meters, centimeters, feet
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .meters: "m"
        case .centimeters: "cm"
        case .feet: "ft"
        }
    }

    var title: String {
        switch self {
        case .meters: tr("Metres")
        case .centimeters: tr("Centimetres")
        case .feet: tr("Feet")
        }
    }

    var digits: Int {
        switch self {
        case .meters: 2
        case .centimeters: 0
        case .feet: 1
        }
    }

    func convert(_ meters: Double) -> Double {
        switch self {
        case .meters: meters
        case .centimeters: meters * 100
        case .feet: meters / 0.3048
        }
    }
}

enum RainUnit: String, CaseIterable, Identifiable {
    case millimeters, inches
    var id: String { rawValue }

    var symbol: String { self == .millimeters ? "mm" : "in" }
    var title: String { self == .millimeters ? tr("Millimetres") : tr("Inches") }
    var digits: Int { self == .millimeters ? 1 : 2 }

    func convert(_ mm: Double) -> Double {
        self == .millimeters ? mm : mm / 25.4
    }
}

/// For visibility and the open water upwind.
enum DistanceUnit: String, CaseIterable, Identifiable {
    case kilometers, miles, nauticalMiles
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .kilometers: "km"
        case .miles: "mi"
        case .nauticalMiles: tr("NM")
        }
    }

    var title: String {
        switch self {
        case .kilometers: tr("Kilometres")
        case .miles: tr("Miles")
        case .nauticalMiles: tr("Nautical miles")
        }
    }

    func convert(_ meters: Double) -> Double {
        switch self {
        case .kilometers: meters / 1000
        case .miles: meters / 1609.344
        case .nauticalMiles: meters / 1852
        }
    }
}

enum TimeFormat: String, CaseIterable, Identifiable {
    /// The phone's 12- or 24-hour setting.
    case device
    case hours24
    case hours12
    var id: String { rawValue }

    var title: String {
        switch self {
        case .device: tr("Device")
        case .hours24: tr("24-hour")
        case .hours12: tr("12-hour")
        }
    }

    func string(from date: Date) -> String {
        Self.formatters[self]!.string(from: date)
    }

    private static let formatters: [TimeFormat: DateFormatter] = Dictionary(uniqueKeysWithValues: allCases.map { format in
        let f = DateFormatter()
        switch format {
        case .device:
            f.locale = .current
            f.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "HH:mm"
        case .hours24:
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm"
        case .hours12:
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "h:mm a"
        }
        return (format, f)
    })
}

/// How days are written, e.g. over each day of the hourly forecast.
enum DateFormat: String, CaseIterable, Identifiable {
    /// The phone's style for the app's language.
    case device
    /// "Monday, 19 October"
    case long
    /// "Mon, 19 Oct"
    case short
    /// "Mon 19.10.2026"
    case dayMonthYear
    /// "Mon 10/19/2026"
    case monthDayYear
    /// "Mon 2026-10-19"
    case iso
    var id: String { rawValue }

    var title: String {
        switch self {
        case .device: tr("Device")
        case .long: tr("Long")
        case .short: tr("Short")
        case .dayMonthYear: tr("Day.Month.Year")
        case .monthDayYear: tr("Month/Day/Year")
        case .iso: "ISO 8601"
        }
    }

    func string(from date: Date, locale: Locale) -> String {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        switch self {
        case .device: return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale))
        case .long: return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        case .short: return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
        case .dayMonthYear: return "\(weekday) \(Self.fixed("dd.MM.yyyy", date))"
        case .monthDayYear: return "\(weekday) \(Self.fixed("MM/dd/yyyy", date))"
        case .iso: return "\(weekday) \(Self.fixed("yyyy-MM-dd", date))"
        }
    }

    private static func fixed(_ pattern: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

/// Values in the user's units. Without a unit the number alone, for the
/// hourly table whose header names the unit.
extension Format {
    private static var settings: AppSettings { .shared }

    /// "12°", the unit implied, as the Weather app shows temperatures.
    static func degrees(_ celsius: Double?, digits: Int = 0) -> String {
        guard let celsius else { return "–" }
        return "\(number(settings.temperatureUnit.convert(celsius), digits: digits))°"
    }

    /// "12 °C" or "54 °F".
    static func temperature(_ celsius: Double?, digits: Int = 0) -> String {
        guard let celsius else { return "–" }
        return "\(number(settings.temperatureUnit.convert(celsius), digits: digits)) \(settings.temperatureUnit.symbol)"
    }

    static func windNumber(_ ms: Double?) -> String {
        guard let ms else { return "–" }
        return number(settings.windUnit.convert(ms))
    }

    /// "5 m/s", "10 kn", "3 Bft".
    static func wind(_ ms: Double?) -> String {
        guard ms != nil else { return "–" }
        return "\(windNumber(ms)) \(settings.windUnit.symbol)"
    }

    /// Mean wind and strongest gust, "3–5 m/s".
    static func windRange(_ speed: Double?, _ gust: Double?) -> String {
        guard speed != nil else { return "–" }
        return "\(windNumber(speed))–\(windNumber(gust)) \(settings.windUnit.symbol)"
    }

    static func wavesNumber(_ m: Double?) -> String {
        guard let m else { return "–" }
        return number(settings.waveUnit.convert(m), digits: settings.waveUnit.digits)
    }

    static func waves(_ m: Double?) -> String {
        guard m != nil else { return "–" }
        return "\(wavesNumber(m)) \(settings.waveUnit.symbol)"
    }

    static func rainNumber(_ mm: Double?) -> String {
        guard let mm else { return "–" }
        return number(settings.rainUnit.convert(mm), digits: settings.rainUnit.digits)
    }

    static func rain(_ mm: Double?) -> String {
        guard mm != nil else { return "–" }
        return "\(rainNumber(mm)) \(settings.rainUnit.symbol)"
    }

    /// Distance with one decimal below 10, e.g. "2.4 km", "12 km".
    static func distanceNumber(_ meters: Double?) -> String {
        guard let meters else { return "–" }
        let value = settings.distanceUnit.convert(meters)
        return number(value, digits: value < 10 ? 1 : 0)
    }

    static func distance(_ meters: Double?) -> String {
        guard meters != nil else { return "–" }
        return "\(distanceNumber(meters)) \(settings.distanceUnit.symbol)"
    }
}
