import Foundation

/// Which tip the club page shows (owner's pacing, 12 Nov 2026): one at a time. A tip for a rare
/// case (water nearby, water level in winter, river current) goes first; otherwise the first paced
/// tip in this order whose place is on the page and that TipKit would show today. Split off
/// LocationPageView.swift, which keeps the tips' state and draws them.
enum ClubPageTip: CaseIterable {
    case nearbyWater, waterLevel, riverCurrent
    case topTile, allValues, placeLine, hourly, lakeView, launchPoint, conditions, hourView, satellite, rainRadar, source, waterEstimate

    /// What the page knows about each tip: would TipKit show it, and is its place on the page.
    struct Spot {
        let tip: ClubPageTip
        let shows: Bool
        let placed: Bool
    }

    /// The tip to show, or nil. `all` (screenshot hooks `-RWShowTips`, `-RWLaterTips`) shows every
    /// tip that would show, as before the pacing, so each tip can still be photographed.
    static func pick(_ spots: [Spot]) -> ClubPageTip? {
        let order = Self.allCases
        return spots
            .filter { $0.shows && $0.placed }
            .min { order.firstIndex(of: $0.tip)! < order.firstIndex(of: $1.tip)! }?
            .tip
    }

    /// The one tip a screenshot asks for (`-RWClubTip topTile`): the page shows only it, as in use.
    static var only: ClubPageTip? {
        let defaults = UserDefaults.standard
        // The one-tip hooks name their tip too, so another tip can't take the page's turn.
        if defaults.bool(forKey: DefaultsKey.placeTip) { return .placeLine }
        if defaults.bool(forKey: DefaultsKey.riverTip) { return .riverCurrent }
        if defaults.bool(forKey: DefaultsKey.nearbyTip) { return .nearbyWater }
        guard let name = defaults.string(forKey: DefaultsKey.clubTip) else { return nil }
        return allCases.first { "\($0)" == name }
    }

    /// The screenshot hooks that show tips regardless of the pacing.
    static var showsAll: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: DefaultsKey.showTips) || defaults.bool(forKey: DefaultsKey.laterTips)
    }

    /// The Why line counts the water within 1 km (#395); `-RWNearbyTip YES` shows its tip anyway.
    static func hasNearbyReason(_ hour: ForecastHour) -> Bool {
        hour.reasons.contains { $0.condition == "nearby_water" } || UserDefaults.standard.bool(forKey: DefaultsKey.nearbyTip)
    }
}
