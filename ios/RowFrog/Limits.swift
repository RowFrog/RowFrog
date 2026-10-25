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
    /// (score.py). From the research in the thread "Boat sizes and rowing
    /// limits", approved by the owner on 2026-10-23; to be checked with
    /// experienced rowers before release.
    func standard(for boat: Boat) -> Double {
        switch (self, boat.type, boat.isBig) {
        // Cold-water shock starts at about 15 °C (owner decision 2026-10-25);
        // the stricter rules stay at `RowingLimits.coldWaterC`.
        case (.lifeJacket, _, _): 15
        // Small racing boats: ~7 cm of side.
        case (.windAmber, .racing, false): 5.5  // Beaufort 4, the first whitecaps
        case (.windRed, .racing, false): 8.0  // Beaufort 5
        case (.gustAmber, .racing, false): 8.0
        case (.gustRed, .racing, false): 10.3  // 20 kn
        case (.waveAmber, .racing, false): 0.15
        case (.waveRed, .racing, false): 0.25
        // Big racing boats, and big training boats, which are as steady.
        case (.windAmber, .racing, true), (.windAmber, .training, true): 8.0
        case (.windRed, .racing, true), (.windRed, .training, true): 10.8  // Beaufort 6, the strong-wind warning
        case (.gustAmber, .racing, true), (.gustAmber, .training, true): 10.8
        case (.gustRed, .racing, true), (.gustRed, .training, true): 12.8  // 46 km/h
        case (.waveAmber, .racing, true), (.waveAmber, .training, true): 0.25
        case (.waveRed, .racing, true), (.waveRed, .training, true): 0.40
        // Small training boats: wider than racing boats.
        case (.windAmber, .training, false): 6.5
        case (.windRed, .training, false): 9.0
        case (.gustAmber, .training, false): 9.0
        case (.gustRed, .training, false): 11.0
        case (.waveAmber, .training, false): 0.20
        case (.waveRed, .training, false): 0.35
        // Gigs: ~18-20 cm of side, but an open gig sinks when swamped.
        case (.windAmber, .gig, _): 8.0
        case (.windRed, .gig, _): 10.8
        case (.gustAmber, .gig, _): 10.8
        case (.gustRed, .gig, _): 12.8
        case (.waveAmber, .gig, _): 0.30
        case (.waveRed, .gig, _): 0.50
        // Coastal boats: built for Beaufort 4 and 0.5 m waves, and self-bailing.
        case (.windAmber, .coastal, _): 8.0
        case (.windRed, .coastal, _): 12.0
        case (.gustAmber, .coastal, _): 10.8
        case (.gustRed, .coastal, _): 12.8
        case (.waveAmber, .coastal, _): 0.50
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
    /// Taken off the app's wind and gust limits in cold water; the user's own stay.
    var coldMargin: Double = 0

    /// What the backend's rowing light already uses.
    static let standard = RowingLimits()
    /// Below this water temperature ("very cold"): singles with a coach or partner
    /// boat, and the app's wind and gust limits lowered by `coldWindMarginMs` (DRV).
    /// The life jacket is advised from the `lifeJacket` limit (15 °C) down.
    static let coldWaterC = 10.0
    static let coldWindMarginMs = 1.0
    /// Below this, small boats are strongly advised to stay ashore.
    static let freezingWaterC = 4.0

    func value(_ limit: RowingLimit) -> Double {
        if let mine = custom[limit] { return mine }
        let isWind = [.windAmber, .windRed, .gustAmber, .gustRed].contains(limit)
        return limit.standard(for: boat) - (isWind ? coldMargin : 0)
    }
    func isMine(_ limit: RowingLimit) -> Bool { custom[limit] != nil }

    /// These limits for water of `celsius`: in cold water the app's wind and gust limits drop.
    func forWater(_ celsius: Double?) -> RowingLimits {
        var copy = self
        copy.coldMargin = (celsius ?? 99) < Self.coldWaterC ? Self.coldWindMarginMs : 0
        return copy
    }

    /// The boat may be a single, so cold water calls for a coach or partner boat.
    var maybeSingle: Bool { boat.id == Boat.small.id || boat.boatClass == .single }
    /// The lake's strong-wind light: red for small racing and training boats, amber for the rest.
    var strongWindLight: Light { !boat.isBig && [.racing, .training].contains(boat.type) ? .red : .amber }

    /// The same limits and rules as the backend's small boats, whatever the boat is called.
    var matchesStandard: Bool {
        RowingLimit.allCases.allSatisfy { value($0) == Self.standard.value($0) }
            && maybeSingle && strongWindLight == .red
    }

    /// Whether these limits let any wind, gust or wave pass that `other` already flags.
    func allowsMore(than other: RowingLimits) -> Bool {
        RowingLimit.boatDependent.contains { value($0) > other.value($0) + 1e-9 }
    }

    /// The light for a value against an amber and a red limit, as in score.py.
    func light(_ value: Double?, _ amber: RowingLimit, _ red: RowingLimit) -> Light {
        guard let value else { return .green }
        return value > self.value(red) ? .red : value >= self.value(amber) ? .amber : .green
    }

    /// Reasons that depend on the boat but not on a measured value: the lake's
    /// strong-wind light and the advice for singles.
    func boatReasons(_ reasons: [Reason]) -> [Reason] {
        reasons.compactMap { reason in
            switch reason.condition {
            case "lake_strong_wind": Reason(condition: reason.condition, light: strongWindLight)
            case "single_cold": maybeSingle ? reason : nil
            default: reason
            }
        }
    }
}

extension ForecastHour {
    /// Reasons the app works out again for the user's boat and limits.
    static let limitReasons: Set<String> = ["wind", "gusts", "waves", "cold_water", "cool_water", "single_cold", "freezing_water"]

    /// This hour with wind, gusts, waves and water checked against `limits`.
    /// Where the user's own limit is looser than the app's, a note says the
    /// value is above the app's limit, so the advice is never lost.
    func applying(_ chosen: RowingLimits, waterC: Double?) -> ForecastHour {
        let limits = chosen.forWater(waterC)
        var reasons = limits.boatReasons(self.reasons.filter { !Self.limitReasons.contains($0.condition) })
        var notes: [Reason] = []
        let usualLimits = RowingLimits(boat: limits.boat).forWater(waterC)
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
            // Below 15 °C cold-water shock is possible (life jacket advised), below 10 °C the water is very cold.
            let cold = water < RowingLimits.coldWaterC
            reasons.append(Reason(condition: cold ? "cold_water" : "cool_water", light: .amber))
            if water < RowingLimits.coldWaterC {
                if limits.maybeSingle { reasons.append(Reason(condition: "single_cold", light: .amber)) }
                // The user's own wind limits do not drop with the water; say so.
                if [RowingLimit.windAmber, .windRed, .gustAmber, .gustRed].contains(where: limits.isMine) {
                    notes.append(Reason(condition: "cold_margin", light: .amber))
                }
            }
            if water < RowingLimits.freezingWaterC {
                reasons.append(Reason(condition: "freezing_water", light: .amber))
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
