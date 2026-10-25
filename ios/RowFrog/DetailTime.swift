import SwiftUI
import Observation

/// The hour a detail sheet shows, shared by its chart and its weather map,
/// and kept while swiping from one value to the next.
///
/// The chart's blue line is `hour`; the big number above the chart is the
/// value at that hour. The map shows `mapHour`: the same hour while linked,
/// its own while unlinked (chain button on the map). Hours count from the
/// hour the sheet was opened at (now, or the hour picked in the 48 hours).
@Observable
final class DetailTime {
    /// The chart's blue line.
    private(set) var hour: Double
    /// The map's own hour while unlinked. Read `shownMapHour` for the map.
    private(set) var mapHour: Double
    /// Whether the map follows the chart. Remembered across sheets.
    private(set) var linked: Bool
    /// The hours that have a map for the value shown, set by the map;
    /// nil when the value has no map that follows the chart.
    var mapHours: [Double]?

    /// The left edge of the chart's visible 24 hours, so a swipe to the next
    /// value keeps the chart where it was. Not observed: it changes on every
    /// frame of a drag.
    @ObservationIgnored var scrollX = DetailTime.start

    /// Where the visible 24 hours start when a sheet opens: an hour before the opened hour.
    static let start = -1.0
    static let linkKey = "RWMapTimeLinked"

    init() {
        // Screenshot hook: `-RWChartSelect 5` puts the blue line five hours on.
        let selected = UserDefaults.standard.object(forKey: "RWChartSelect") != nil
            ? UserDefaults.standard.double(forKey: "RWChartSelect").rounded() : 0
        hour = selected
        mapHour = selected
        if selected > 20 { scrollX = selected - 8 }
        // bool(forKey:) also reads a launch argument's "NO", which is a string.
        linked = UserDefaults.standard.object(forKey: Self.linkKey) == nil || UserDefaults.standard.bool(forKey: Self.linkKey)
    }

    /// The hour the map shows.
    var shownMapHour: Double { linked ? hour : mapHour }

    /// The map's picture for the shown hour: the nearest hour that has one,
    /// which past the last map is the last one.
    var mapFrameHour: Double? {
        guard let hours = mapHours, !hours.isEmpty else { return nil }
        let x = shownMapHour
        return hours.min { abs($0 - x) < abs($1 - x) }
    }

    /// Whether the map's hour lies outside the hours that have maps.
    var mapOutOfRange: Bool {
        guard let hours = mapHours, let first = hours.first, let last = hours.last else { return false }
        return shownMapHour < first - 0.5 || shownMapHour > last + 0.5
    }

    /// From the chart: a hold and slide, or a tap on "Back to".
    func setChart(_ x: Double) {
        let x = x.rounded()
        if hour != x { hour = x }
    }

    /// From the map's slider or play button. Linked, the chart follows.
    func setMap(_ x: Double) {
        if linked { setChart(x) } else if mapHour != x { mapHour = x }
    }

    /// The chain button. Linking again brings the chart to the map's hour.
    func setLinked(_ on: Bool) {
        guard on != linked else { return }
        if on { setChart(mapHour) } else { mapHour = hour }
        linked = on
        UserDefaults.standard.set(on, forKey: Self.linkKey)
    }

    /// "Back to now" or "Back to <hour>": the chart, and the map while linked.
    func back() {
        scrollX = Self.start
        setChart(0)
    }
}

extension ConditionData {
    /// The same forecast seen from another hour (hours from the shown one),
    /// for the big number at the chart's blue line. Itself at 0.
    func at(_ x: Double) -> ConditionData {
        guard abs(x) >= 0.5,
              let hour = timeline.min(by: { abs(self.x($0.time) - x) < abs(self.x($1.time) - x) }),
              hour.time != now.time
        else { return self }
        return ConditionData(forecast: forecast, now: hour)
    }
}
