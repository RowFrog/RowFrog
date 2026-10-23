import Foundation

/// How a boat is built. Freeboard and width decide how much wind and how high
/// a wave a boat takes, so each type has its own starting limits.
enum BoatType: String, CaseIterable, Identifiable, Codable {
    case racing, training, gig, coastal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .racing: tr("Racing boat")
        case .training: tr("Training boat")
        case .gig: tr("Gig boat")
        case .coastal: tr("Coastal boat")
        }
    }

    var detail: String {
        switch self {
        case .racing: tr("Narrow and low, with the least side above the water")
        case .training: tr("Wider and steadier than a racing boat")
        case .gig: tr("Gig and touring boats, higher sides")
        case .coastal: tr("Coastal boats that drain themselves")
        }
    }
}

/// Size and rigging: how many rowers, sculling or sweep, with or without cox.
enum BoatClass: String, CaseIterable, Identifiable, Codable {
    case single = "1x", double = "2x", pair = "2-", quad = "4x", four = "4-", coxedFour = "4+", octuple = "8x", eight = "8+"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: tr("Single (1x)")
        case .double: tr("Double (2x)")
        case .pair: tr("Pair (2-)")
        case .quad: tr("Quad (4x)")
        case .four: tr("Four (4-)")
        case .coxedFour: tr("Coxed four (4+)")
        case .octuple: tr("Octuple (8x)")
        case .eight: tr("Eight (8+)")
        }
    }

    /// Fours and eights: longer, heavier and steadier.
    var isBig: Bool { ![.single, .double, .pair].contains(self) }
}

/// A boat the rowing light can be worked out for: the two groups every user
/// has, or one of the user's own boats.
struct Boat: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var type: BoatType
    var boatClass: BoatClass

    static let small = Boat(id: "small", name: "", type: .racing, boatClass: .single)
    static let big = Boat(id: "big", name: "", type: .racing, boatClass: .eight)
    static let groups = [small, big]

    init(id: String, name: String, type: BoatType, boatClass: BoatClass) {
        self.id = id
        self.name = name
        self.type = type
        self.boatClass = boatClass
    }

    private enum CodingKeys: String, CodingKey { case id, name, type, boatClass = "class" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try c.decodeIfPresent(BoatType.self, forKey: .type) ?? .racing
        boatClass = try c.decodeIfPresent(BoatClass.self, forKey: .boatClass) ?? .single
    }

    var isGroup: Bool { id == Self.small.id || id == Self.big.id }
    var isBig: Bool { boatClass.isBig }

    var title: String {
        switch id {
        case Self.small.id: tr("Small boats")
        case Self.big.id: tr("Big boats")
        default: name.trimmingCharacters(in: .whitespaces).isEmpty ? "\(type.title) \(boatClass.rawValue)" : name
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

    var detail: String {
        switch id {
        case Self.small.id: tr("Singles, doubles and pairs (1x, 2x, 2-)")
        case Self.big.id: tr("Fours and eights (4x, 4-, 4+, 8x, 8+)")
        default: tr("%@ · %@", type.title, boatClass.rawValue)
        }
    }
}

/// A rowing limit the user can fine-tune. Values are metric: m/s, m and °C.
enum RowingLimit: String, CaseIterable, Identifiable {
    case windAmber, windRed, gustAmber, gustRed, waveAmber, waveRed, lifeJacket
    var id: String { rawValue }

    /// Wind, gusts and waves: the limits that differ from boat to boat.
    static let boatDependent: [RowingLimit] = [.windAmber, .windRed, .gustAmber, .gustRed, .waveAmber, .waveRed]

    /// The app's limit for a boat; small racing boats' are the backend's
    /// (score.py). The others are estimates to be checked with experienced rowers.
    func standard(for boat: Boat) -> Double {
        switch (self, boat.type, boat.isBig) {
        case (.lifeJacket, _, _): 10
        case (.gustRed, _, _): 12.8  // 46 km/h, DWD's strong-wind warning
        // Racing boats, and big training boats, which are as steady as big racing boats.
        case (.windAmber, .racing, false): 5.5  // Beaufort 4
        case (.windRed, .racing, false): 8.0  // Beaufort 5
        case (.gustAmber, .racing, false): 8.0
        case (.waveAmber, .racing, false): 0.15
        case (.waveRed, .racing, false): 0.30
        case (.windAmber, .racing, true), (.windAmber, .training, true): 8.0
        case (.windRed, .racing, true), (.windRed, .training, true): 10.8  // Beaufort 6
        case (.gustAmber, .racing, true), (.gustAmber, .training, true): 10.8
        case (.waveAmber, .racing, true), (.waveAmber, .training, true): 0.25
        case (.waveRed, .racing, true), (.waveRed, .training, true): 0.45
        // Small training boats: wider than racing boats.
        case (.windAmber, .training, false): 6.5
        case (.windRed, .training, false): 9.0
        case (.gustAmber, .training, false): 9.0
        case (.waveAmber, .training, false): 0.20
        case (.waveRed, .training, false): 0.35
        // Gigs and coastal boats: higher sides, any size.
        case (.windAmber, .gig, _): 8.0
        case (.windRed, .gig, _): 10.8
        case (.gustAmber, .gig, _): 10.8
        case (.waveAmber, .gig, _): 0.35
        case (.waveRed, .gig, _): 0.60
        case (.windAmber, .coastal, _): 9.0
        case (.windRed, .coastal, _): 12.0
        case (.gustAmber, .coastal, _): 10.8
        case (.waveAmber, .coastal, _): 0.60
        case (.waveRed, .coastal, _): 1.0
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

    func value(_ limit: RowingLimit) -> Double { custom[limit] ?? limit.standard(for: boat) }
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
