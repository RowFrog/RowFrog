import Foundation

/// The order the reasons of an hour are listed in (owner, 20 Nov 2026): red before amber,
/// and within one colour the more dangerous first, by one fixed list. Daylight always comes
/// last: it only says when to be back. Unknown names sit just before daylight; the water
/// within 1 km ("nearby_water") ranks as what it is about (its topic). The backend
/// (score.py REASON_ORDER) and the website (logic.js REASON_ORDER) use the same list,
/// and testdata/reasons.json holds it for the tests of all three.
extension Reason {
    static let order: [String] = [
        "lake_warning", "lake_strong_wind", "thunderstorm", "hail", "ice",
        "freezing_water", "cold_water", "single_cold", "cool_water",
        "fog", "gusts", "wind", "waves",
        "shipping_stopped", "high_water", "current",
        "weather_warning", "heavy_rain", "lake_drained", "lake_lowered",
        "daylight", "twilight", "sunset_soon",
    ]

    /// This reason's place within its colour; smaller comes first.
    var rank: Double {
        let name = condition == "nearby_water" ? (topic ?? "") : condition
        if let i = Self.order.firstIndex(of: name) { return Double(i) }
        return Double(Self.order.firstIndex(of: "daylight") ?? Self.order.count) - 0.5
    }
}

extension Array where Element == Reason {
    /// Red first, then amber; within one colour by `Reason.rank`; equal ones keep their order.
    func ordered() -> [Reason] {
        enumerated().sorted { a, b in
            if a.element.light != b.element.light { return a.element.light > b.element.light }
            if a.element.rank != b.element.rank { return a.element.rank < b.element.rank }
            return a.offset < b.offset
        }.map(\.element)
    }
}
