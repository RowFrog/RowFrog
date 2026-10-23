import Foundation

/// A kind of boat. Freeboard and width decide how much wind and how high a
/// wave a boat takes, so each type has its own starting limits.
enum BoatType: String, CaseIterable, Identifiable, Codable {
    case racingSmall, racingBig, trainingSingle, gig, coastal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .racingSmall: tr("Racing boat, small")
        case .racingBig: tr("Racing boat, big")
        case .trainingSingle: tr("Training single")
        case .gig: tr("Gig boat")
        case .coastal: tr("Coastal boat")
        }
    }

    var detail: String {
        switch self {
        case .racingSmall: tr("Singles, doubles and pairs (1x, 2x, 2-)")
        case .racingBig: tr("Fours and eights (4x, 4-, 4+, 8+)")
        case .trainingSingle: tr("A wider learner or training single")
        case .gig: tr("Gig and touring boats, higher sides")
        case .coastal: tr("Coastal boats that drain themselves")
        }
    }
}

/// A boat the rowing light can be worked out for: the two groups every user
/// has, or one of the user's own boats.
struct Boat: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var type: BoatType

    static let small = Boat(id: "small", name: "", type: .racingSmall)
    static let big = Boat(id: "big", name: "", type: .racingBig)
    static let groups = [small, big]

    var isGroup: Bool { id == Self.small.id || id == Self.big.id }

    var title: String {
        switch id {
        case Self.small.id: tr("Small boats")
        case Self.big.id: tr("Big boats")
        default: name.trimmingCharacters(in: .whitespaces).isEmpty ? type.title : name
        }
    }

    /// The boat inside a sentence: "for small boats", "for Anna".
    var inSentence: String {
        switch id {
        case Self.small.id: tr("small boats")
        case Self.big.id: tr("big boats")
        default: title
        }
    }

    var detail: String { isGroup ? type.detail : type.title }
}

/// A rowing limit the user can fine-tune. Values are metric: m/s, m and °C.
enum RowingLimit: String, CaseIterable, Identifiable {
    case windAmber, windRed, gustAmber, gustRed, waveAmber, waveRed, lifeJacket
    var id: String { rawValue }

    /// Wind, gusts and waves: the limits that differ from boat to boat.
    static let boatDependent: [RowingLimit] = [.windAmber, .windRed, .gustAmber, .gustRed, .waveAmber, .waveRed]

    /// The app's limit for a boat type; the small racing boats' are the
    /// backend's (score.py). The others are estimates to be checked with
    /// experienced rowers.
    func standard(for type: BoatType) -> Double {
        switch (self, type) {
        case (.windAmber, .racingSmall): 5.5  // Beaufort 4
        case (.windAmber, .trainingSingle): 6.5
        case (.windAmber, .racingBig), (.windAmber, .gig): 8.0  // Beaufort 5
        case (.windAmber, .coastal): 9.0
        case (.windRed, .racingSmall): 8.0
        case (.windRed, .trainingSingle): 9.0
        case (.windRed, .racingBig), (.windRed, .gig): 10.8  // Beaufort 6
        case (.windRed, .coastal): 12.0
        case (.gustAmber, .racingSmall): 8.0
        case (.gustAmber, .trainingSingle): 9.0
        case (.gustAmber, _): 10.8
        case (.gustRed, _): 12.8  // 46 km/h, DWD's strong-wind warning
        case (.waveAmber, .racingSmall): 0.15
        case (.waveAmber, .trainingSingle): 0.20
        case (.waveAmber, .racingBig): 0.25
        case (.waveAmber, .gig): 0.35
        case (.waveAmber, .coastal): 0.60
        case (.waveRed, .racingSmall): 0.30
        case (.waveRed, .trainingSingle): 0.35
        case (.waveRed, .racingBig): 0.45
        case (.waveRed, .gig): 0.60
        case (.waveRed, .coastal): 1.0
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
        case .waveAmber, .waveRed: 0.05...1.5
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

/// The limits for one boat: the app's for its type, with the user's own changes.
struct RowingLimits: Equatable {
    var boat: Boat = .small
    var custom: [RowingLimit: Double] = [:]

    /// What the backend's rowing light already uses.
    static let standard = RowingLimits()

    func value(_ limit: RowingLimit) -> Double { custom[limit] ?? limit.standard(for: boat.type) }
    func isMine(_ limit: RowingLimit) -> Bool { custom[limit] != nil }
    /// The same wind, gust and wave limits as the backend's, whatever the boat is called.
    var matchesStandard: Bool { RowingLimit.allCases.allSatisfy { value($0) == Self.standard.value($0) } }

    /// Whether these limits let any wind, gust or wave pass that `other` already flags.
    func allowsMore(than other: RowingLimits) -> Bool {
        RowingLimit.boatDependent.contains { value($0) > other.value($0) + 1e-9 }
    }

    /// The light for a value against an amber and a red limit, as in score.py.
    func light(_ value: Double?, _ amber: RowingLimit, _ red: RowingLimit) -> Light {
        guard let value else { return .green }
        return value > self.value(red) ? .red : value >= self.value(amber) ? .amber : .green
    }
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
        let usualLimits = RowingLimits(boat: limits.boat)
        func check(_ name: String, _ value: Double?, _ amber: RowingLimit, _ red: RowingLimit) {
            let light = limits.light(value, amber, red)
            if light > .green {
                reasons.append(Reason(condition: name, light: light, mine: limits.isMine(light == .red ? red : amber) ? true : nil))
            }
            let usual = usualLimits.light(value, amber, red)
            if usual > light {
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
            if !cold && water < RowingLimit.lifeJacket.standard(for: limits.boat.type) {
                notes.append(Reason(condition: "cold_water", light: .amber))
            }
        }
        var hour = self
        hour.notes = notes.isEmpty ? nil : notes
        return hour.with(reasons: reasons.sorted { $0.light > $1.light }, sunUp: sunUp)
    }
}

extension ClubForecast {
    /// The forecast with a boat's limits; unchanged with the app's own.
    func applying(_ limits: RowingLimits) -> ClubForecast {
        guard !limits.matchesStandard else { return self }
        var copy = self
        let water = waterTemperature?.celsius
        copy.hours = hours.map { $0.applying(limits, waterC: water) }
        copy.outlook = outlook?.map { $0.applying(limits, waterC: water) }
        return copy
    }

    /// With the boat and limits chosen in the settings.
    func applyingUserLimits() -> ClubForecast { applying(AppSettings.shared.limits) }
}

/// One of the user's own boats that would get better advice than the ticked
/// one this hour, for "Too rough for small boats. Your gig would be fine."
struct SteadierBoat: Equatable {
    let boat: Boat
    let light: Light

    /// The calmest of the user's boats for `hour`, when it beats the ticked boat.
    static func suggestion(for hour: ForecastHour, water: Double?, settings: AppSettings = .shared) -> SteadierBoat? {
        guard hour.light > .green else { return nil }
        let candidates = settings.myBoats.filter { $0.id != settings.selectedBoat.id }
            .map { SteadierBoat(boat: $0, light: hour.applying(settings.limits(for: $0), waterC: water).light) }
            .filter { $0.light < hour.light }
        return candidates.min { $0.light < $1.light }
    }
}
