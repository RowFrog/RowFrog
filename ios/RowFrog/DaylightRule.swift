import Foundation

/// The daylight part of the rowing light, decided to the minute (owner's pick D, 6 Nov 2026):
/// green while the sun is up, amber in the last hour before sunset, red with the sun down.
/// The backend (`forecast._daylight`) gives each hour the strictest of its minutes, so an hour
/// row is never more relaxed than "now" in it; "now" takes the light of this minute, and an hour
/// in which the light changes draws its dot half and half (`TrafficLightDot.halves`).
/// The website does the same in logic.js (`daylightAt`, `daylightHalves`).
enum DaylightRule {
    /// As SUNSET_WINDOW in backend/rowfrog/forecast.py.
    static let sunsetWindow: TimeInterval = 60 * 60
    /// A part of an hour shorter than this is left out of its dot, unless it is the strictest part,
    /// so a few relaxed minutes at the edge never show and a stricter few always do.
    static let shortestPart: TimeInterval = 10 * 60
    /// The reasons the daylight gives: "sunset_soon" is the app's own, for "now" in the last hour.
    static let reasonNames: Set<String> = ["daylight", "twilight", "sunset_soon"]

    /// The daylight light at one moment.
    static func light(at t: Date, days: [SunDay]) -> Light {
        for d in days where d.sunrise <= t && t < d.sunset {
            return t >= d.sunset.addingTimeInterval(-sunsetWindow) ? .amber : .green
        }
        return .red
    }

    struct Part: Hashable {
        let light: Light
        let from: Date
        let to: Date
    }

    /// The hour from `start`, cut where the daylight light changes.
    static func parts(from start: Date, days: [SunDay]) -> [Part] {
        let end = start.addingTimeInterval(3600)
        let inside = days.flatMap { [$0.sunrise, $0.sunset.addingTimeInterval(-sunsetWindow), $0.sunset] }
            .filter { $0 > start && $0 < end }
        let cuts = ([start] + inside).sorted()
        var parts: [Part] = []
        for (i, cut) in cuts.enumerated() {
            let to = i + 1 < cuts.count ? cuts[i + 1] : end
            let light = light(at: cut, days: days)
            if let last = parts.last, last.light == light {
                parts[parts.count - 1] = Part(light: light, from: last.from, to: to)
            } else {
                parts.append(Part(light: light, from: cut, to: to))
            }
        }
        return parts
    }

    /// The lights an hour's dot starts and ends with, or nil when it does not change.
    /// `floor` is the hour's light from everything but the daylight: neither half is below it.
    /// `before` and `after` are the same for the hours either side (owner's pick B, 6 Nov 2026):
    /// the better half can never be better than the weather of the hour it touches (nor stricter
    /// than the other half), so a red day
    /// never shows an amber half at sunset, nor a red morning a green half at sunrise.
    /// The stricter half is never changed.
    static func halves(from start: Date, days: [SunDay], floor: Light, before: Light = .green, after: Light = .green) -> DotHalves? {
        let all = parts(from: start, days: days)
        let top = all.map(\.light).max() ?? .green
        let kept = all.filter { $0.to.timeIntervalSince($0.from) >= shortestPart || $0.light == top }
        guard let first = kept.first, let last = kept.last else { return nil }
        var left = max(first.light, floor)
        var right = max(last.light, floor)
        // Held to its neighbour, the better half never gets stricter than the other half.
        if left < right { left = min(max(left, before), right) } else if right < left { right = min(max(right, after), left) }
        return left == right ? nil : DotHalves(start: left, end: right)
    }

    /// The light of an hour from everything but the daylight.
    static func weather(_ hour: ForecastHour?) -> Light {
        hour?.reasons.filter { !reasonNames.contains($0.condition) }.map(\.light).max() ?? .green
    }
}

/// The two halves of a dot for an hour in which the light changes: left the light it starts with.
struct DotHalves: Hashable {
    let start: Light
    let end: Light
}

extension ClubForecast {
    /// The half-and-half dot for an hour row or the hour view; nil for one colour.
    func dotHalves(for hour: ForecastHour, stale: Bool = false) -> DotHalves? {
        guard !stale, let days = daylight, !days.isEmpty,
              hour.reasons.contains(where: { DaylightRule.reasonNames.contains($0.condition) }) else { return nil }
        let near = { (offset: TimeInterval) in self.hours.first { $0.time == hour.time.addingTimeInterval(offset) } }
        return DaylightRule.halves(from: hour.time, days: days, floor: DaylightRule.weather(hour),
                                   before: DaylightRule.weather(near(-3600)), after: DaylightRule.weather(near(3600)))
    }
}
