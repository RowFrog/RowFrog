import Foundation

/// The river at a river club (backend: the forecast's "river" block, see
/// backend/rowfrog/river.py): the nearest gauge's water level and the current.
/// On river clubs the Current tile takes the ice tile's place.
/// In RiverModels.swift (not RiverCurrent.swift) so the widget, which shares
/// Models.swift, compiles it too.
struct RiverConditions: Codable, Hashable {
    /// The symbol of the Current tile and of the river reasons.
    static let symbol = "arrow.right.circle"
    /// How long the gauge's reading counts in the forecast (river.py GAUGE_HOURS).
    static let gaugeHours = 24.0

    /// Missing where no federal gauge is on the club's river nearby.
    let gauge: RiverGauge?
    /// Missing without a gauge or when its last reading is too old.
    var now: RiverReading?
    var limits: CurrentLimits? = nil
    var attribution: String? = nil

    /// With the current limits of the user's boat: the tile's light and the limits it names.
    func applying(_ limits: RowingLimits) -> RiverConditions {
        var copy = self
        let amber = limits.value(.currentAmber), red = limits.value(.currentRed)
        copy.limits = CurrentLimits(currentAmberMs: amber, currentRedMs: red)
        if var now {
            let level: Light = now.state == "shipping_stopped" ? .red : now.state == "high" ? .amber : .green
            now.light = max(level, limits.light(now.speedMs, .currentAmber, .currentRed))
            copy.now = now
        }
        return copy
    }
}

struct RiverGauge: Codable, Hashable {
    let name: String
    let water: String
    var riverKm: Double? = nil
    let lat: Double
    let lon: Double
    let distanceKm: Double
    /// Mean water, mean high water and the level at which shipping stops, in cm at the gauge.
    var meanCm: Double? = nil
    var meanHighCm: Double? = nil
    var shippingStopsCm: Double? = nil
    /// Mean discharge in m³/s.
    var meanDischarge: Double? = nil
}

struct CurrentLimits: Codable, Hashable {
    let currentAmberMs: Double
    let currentRedMs: Double
}

struct RiverReading: Codable, Hashable {
    let time: Date
    let levelCm: Double?
    /// "rising", "falling", "steady" or "".
    let trend: String
    /// "normal", "raised", "high", "shipping_stopped" or "" without the gauge's marks.
    let state: String
    let discharge: Double?
    /// Mid-river, measured at the gauge or estimated from the discharge.
    let speedMs: Double?
    let speedMeasured: Bool
    var light: Light
    let history: [RiverLevel]

    var stateTitle: String {
        switch state {
        case "normal": tr("Normal water")
        case "raised": tr("Raised water")
        case "high": tr("High water")
        case "shipping_stopped": tr("Shipping stopped")
        default: tr("Water level")
        }
    }

    var trendTitle: String? {
        switch trend {
        case "rising": tr("rising")
        case "falling": tr("falling")
        case "steady": tr("steady")
        default: nil
        }
    }

    var trendSymbol: String {
        switch trend {
        case "rising": "arrow.up.right"
        case "falling": "arrow.down.right"
        default: "arrow.right"
        }
    }
}

struct RiverLevel: Codable, Hashable {
    let time: Date
    let levelCm: Double
}

enum RiverFormat {
    /// "1.3 m/s" (always m/s: flow speeds are given so on rivers).
    static func speed(_ ms: Double?) -> String {
        guard let ms else { return "–" }
        return Format.number(ms, digits: 1) + " m/s"
    }

    /// "3.20 m" for a gauge level in cm.
    static func level(_ cm: Double?) -> String {
        guard let cm else { return "–" }
        return Format.number(cm / 100, digits: 2) + " m"
    }

    /// Time per 500 m over ground at a still-water pace, with the current
    /// helping (downstream) or against (upstream); nil when the boat cannot make way.
    static func pace(_ secondsPer500: Double, current: Double, downstream: Bool) -> Double? {
        let speed = 500 / secondsPer500 + (downstream ? current : -current)
        return speed > 0.2 ? 500 / speed : nil
    }
}

