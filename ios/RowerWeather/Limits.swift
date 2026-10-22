import Foundation

/// The kind of boat a rower takes out. Bigger boats sit higher and steadier,
/// so they get higher wind and wave limits.
enum BoatClass: String, CaseIterable, Identifiable {
    case small, big
    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: tr("Small boats")
        case .big: tr("Big boats")
        }
    }

    var detail: String {
        switch self {
        case .small: tr("Singles, doubles and pairs (1x, 2x, 2-)")
        case .big: tr("Fours and eights (4x, 4-, 4+, 8+)")
        }
    }
}

/// A rowing limit the user can fine-tune. Values are metric: m/s, m and °C.
enum RowingLimit: String, CaseIterable, Identifiable {
    case windAmber, windRed, gustAmber, gustRed, waveAmber, waveRed, lifeJacket
    var id: String { rawValue }

    /// The app's limit for a boat class; the small-boat values are the
    /// backend's (score.py).
    func standard(for boat: BoatClass) -> Double {
        switch (self, boat) {
        case (.windAmber, .small): 5.5  // Beaufort 4
        case (.windAmber, .big): 8.0  // Beaufort 5
        case (.windRed, .small): 8.0
        case (.windRed, .big): 10.8  // Beaufort 6
        case (.gustAmber, .small): 8.0
        case (.gustAmber, .big): 10.8
        case (.gustRed, _): 12.8  // 46 km/h, DWD's strong-wind warning
        case (.waveAmber, .small): 0.15
        case (.waveAmber, .big): 0.25
        case (.waveRed, .small): 0.30
        case (.waveRed, .big): 0.45
        case (.lifeJacket, _): 10
        }
    }

    var title: String {
        switch self {
        case .windAmber: tr("Wind: row with care from")
        case .windRed: tr("Wind: stay ashore above")
        case .gustAmber: tr("Gusts: row with care from")
        case .gustRed: tr("Gusts: stay ashore above")
        case .waveAmber: tr("Waves: row with care from")
        case .waveRed: tr("Waves: stay ashore above")
        case .lifeJacket: tr("Life jacket below")
        }
    }

    var condition: Condition {
        switch self {
        case .windAmber, .windRed, .gustAmber, .gustRed: .wind
        case .waveAmber, .waveRed: .waves
        case .lifeJacket: .waterTemperature
        }
    }

    var step: Double {
        switch self {
        case .windAmber, .windRed, .gustAmber, .gustRed: 0.5
        case .waveAmber, .waveRed: 0.05
        case .lifeJacket: 1
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .windAmber, .windRed: 2...15
        case .gustAmber, .gustRed: 4...20
        case .waveAmber, .waveRed: 0.05...1
        case .lifeJacket: 4...20
        }
    }

    /// The value in the user's units; wind keeps its decimal so 5.5 m/s does not read as 6.
    func format(_ value: Double) -> String {
        switch self {
        case .windAmber, .windRed, .gustAmber, .gustRed:
            let unit = AppSettings.shared.windUnit
            guard unit != .beaufort else { return Format.wind(value) }
            let v = unit.convert(value)
            return "\(Format.number(v, digits: abs(v - v.rounded()) < 0.05 ? 0 : 1)) \(unit.symbol)"
        case .waveAmber, .waveRed:
            return Format.waves(value)
        case .lifeJacket:
            return Format.temperature(value)
        }
    }
}

/// The limits in use: the app's for the chosen boat class, with the user's own changes.
struct RowingLimits: Equatable {
    var boat: BoatClass = .small
    var custom: [RowingLimit: Double] = [:]

    /// What the backend's rowing light already uses.
    static let standard = RowingLimits()

    func value(_ limit: RowingLimit) -> Double { custom[limit] ?? limit.standard(for: boat) }
    func isMine(_ limit: RowingLimit) -> Bool { custom[limit] != nil }
}

extension ForecastHour {
    /// Reasons whose limits the user can change; the app works them out again.
    static let limitReasons: Set<String> = ["wind", "gusts", "waves", "cold_water", "cool_water"]

    /// This hour with wind, gusts, waves and water checked against `limits`.
    /// Where the user's own limit is looser than the app's, a note says the
    /// value is above the app's limit, so the advice is never lost.
    func applying(_ limits: RowingLimits, waterC: Double?) -> ForecastHour {
        var reasons = self.reasons.filter { !Self.limitReasons.contains($0.condition) }
        var notes: [Reason] = []
        func check(_ name: String, _ value: Double?, _ amber: RowingLimit, _ red: RowingLimit) {
            guard let value else { return }
            let light: Light? = value > limits.value(red) ? .red : value >= limits.value(amber) ? .amber : nil
            if let light {
                reasons.append(Reason(condition: name, light: light, mine: limits.isMine(light == .red ? red : amber) ? true : nil))
            }
            let usual: Light? = value > red.standard(for: limits.boat) ? .red : value >= amber.standard(for: limits.boat) ? .amber : nil
            if let usual, usual > (light ?? .green) {
                notes.append(Reason(condition: name, light: usual))
            }
        }
        check("wind", windSpeedMs, .windAmber, .windRed)
        check("gusts", windGustMs, .gustAmber, .gustRed)
        check("waves", waveHeightM, .waveAmber, .waveRed)
        if let water = waterC, water < 15 {
            let cold = water < limits.value(.lifeJacket)
            reasons.append(Reason(condition: cold ? "cold_water" : "cool_water", light: .amber,
                                  mine: cold && limits.isMine(.lifeJacket) ? true : nil))
            if !cold && water < RowingLimit.lifeJacket.standard(for: limits.boat) {
                notes.append(Reason(condition: "cold_water", light: .amber))
            }
        }
        var hour = self
        hour.notes = notes.isEmpty ? nil : notes
        return hour.with(reasons: reasons.sorted { $0.light > $1.light }, sunUp: sunUp)
    }
}

extension ClubForecast {
    /// The forecast with the user's boat and limits; unchanged with the app's own.
    func applying(_ limits: RowingLimits) -> ClubForecast {
        guard limits != .standard else { return self }
        var copy = self
        let water = waterTemperature?.celsius
        copy.hours = hours.map { $0.applying(limits, waterC: water) }
        copy.outlook = outlook?.map { $0.applying(limits, waterC: water) }
        return copy
    }

    /// With the limits chosen in the settings.
    func applyingUserLimits() -> ClubForecast { applying(AppSettings.shared.limits) }
}
