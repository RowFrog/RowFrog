import Foundation

/// The 48-hour table cut into rows and nights. Rowing is only advised while the
/// sun is up, so the dark hours of a night fold into one line. The hours the sun
/// sets or rises in keep their rows (their light changes inside them), as does the hour the table
/// starts with, even at night; a night of one hour stays a row.
enum NightFold {
    enum Part: Equatable {
        case hour(ForecastHour)
        case night(Night)
    }

    /// The parts of the table, in time order.
    static func parts(_ hours: [ForecastHour], days: [SunDay] = []) -> [Part] {
        var parts: [Part] = []
        var run: [ForecastHour] = []
        func endRun() {
            if run.count > 1 {
                parts.append(.night(Night(hours: run)))
            } else {
                parts += run.map(Part.hour)
            }
            run = []
        }
        for (index, hour) in hours.enumerated() {
            if index > 0 && isDark(hour, days: days) {
                run.append(hour)
            } else {
                endRun()
                parts.append(.hour(hour))
            }
        }
        endRun()
        return parts
    }

    /// Whether a night ending at `end` is whole: the sun rises in the hour after it. The backend
    /// finishes the table's last night up to that hour (finish_night, owner's option B), so such a
    /// night reads "17–07" even where it ends the table; only a night cut off earlier reads "17–".
    static func endsAtSunrise(_ end: Date, days: [SunDay]) -> Bool {
        days.contains { $0.sunrise >= end && $0.sunrise < end.addingTimeInterval(3600) }
    }

    /// Dark all hour: the sun is down and neither sets nor rises in it.
    static func isDark(_ hour: ForecastHour, days: [SunDay] = []) -> Bool {
        guard hour.sunUp == false, !hour.reasons.contains(where: { $0.condition == "twilight" }) else { return false }
        return days.isEmpty || DaylightRule.parts(from: hour.time, days: days).count == 1
    }

    /// One folded night: its hours and the values its line shows, each for the column it sits in.
    struct Night: Equatable, Identifiable {
        let hours: [ForecastHour]

        var id: Date { start }
        var start: Date { hours.first!.time }
        /// When the night's last hour ends.
        var end: Date { hours.last!.time.addingTimeInterval(3600) }

        /// The lowest temperature and feels-like temperature, °C.
        var lowestC: Double? { hours.compactMap(\.temperatureC).min() }
        var lowestFeelsLikeC: Double? { hours.compactMap(\.apparentTemperatureC).min() }
        /// The strongest wind and gust, m/s.
        var strongestWindMs: Double? { hours.compactMap(\.windSpeedMs).max() }
        var strongestGustMs: Double? { hours.compactMap(\.windGustMs).max() }
        /// The highest waves, m.
        var highestWavesM: Double? { hours.compactMap(\.waveHeightM).max() }
        /// All the rain, snow or hail of the night, mm.
        var rainMm: Double? {
            let amounts = hours.compactMap(\.precipitationMm)
            return amounts.isEmpty ? nil : amounts.reduce(0, +)
        }
        /// The poorest visibility, m, and the worst fog light of the night.
        var poorestVisibilityM: Double? { hours.compactMap(\.visibilityM).min() }
        var fogLight: Light? { hours.compactMap { $0.light(for: ["fog"]) }.max() }
        /// Whether it gets to freezing in the night.
        var frost: Bool { (lowestC ?? 1).rounded() <= 0 }
    }
}
