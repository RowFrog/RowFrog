import Foundation

/// The 48-hour table cut into rows and nights. Rowing is only advised while the
/// sun is up, so the dark hours of a night fold into one line. The hours the sun
/// sets or rises in keep their rows (amber "twilight"), as does the hour the table
/// starts with, even at night; a night of one hour stays a row.
enum NightFold {
    enum Part: Equatable {
        case hour(ForecastHour)
        case night(Night)
    }

    /// The parts of the table, in time order.
    static func parts(_ hours: [ForecastHour]) -> [Part] {
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
            if index > 0 && isDark(hour) {
                run.append(hour)
            } else {
                endRun()
                parts.append(.hour(hour))
            }
        }
        endRun()
        return parts
    }

    /// Dark all hour: the sun is down and neither sets nor rises in it.
    static func isDark(_ hour: ForecastHour) -> Bool {
        hour.sunUp == false && !hour.reasons.contains { $0.condition == "twilight" }
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
