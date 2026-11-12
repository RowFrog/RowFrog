import SwiftUI
import TipKit

/// How the one-time tips are paced (owner, 12 Nov 2026; the website does the same in tour.js):
/// one tip on a screen, at most one new tip a day (`.displayFrequency(.daily)`), none on the
/// day of the tour, closing one never brings the next at once, and "No more tips" stops them.
/// Tips for a rare case or for the moment of use (`MomentTip`) skip the daily limit and the
/// quiet first day, but still stop with "No more tips".
enum TipPacing {
    /// False on the day of the tour and after "No more tips": the paced tips wait.
    @Parameter static var awake: Bool = false
    /// False after "No more tips": every tip waits.
    @Parameter static var on: Bool = true

    /// The day the tour was last finished or skipped.
    static let tourDayKey = "RWTourDay"
    /// Set by "No more tips", cleared by "Show the tips again".
    static let offKey = "RWTipsOff"

    /// Called when the tour ends: the paced tips start the next day.
    static func tourEnded(_ now: Date = .now) {
        UserDefaults.standard.set(now, forKey: tourDayKey)
        update(now)
    }

    /// At launch, after TipKit is configured, and each time the app comes back to the front.
    static func update(_ now: Date = .now) {
        let defaults = UserDefaults.standard
        let off = defaults.bool(forKey: offKey)
        on = !off
        awake = !off && !isTourDay(defaults.object(forKey: tourDayKey) as? Date, now)
    }

    /// True while it is still the calendar day of the tour.
    static func isTourDay(_ tourDay: Date?, _ now: Date) -> Bool {
        guard let tourDay else { return false }
        return Calendar.current.isDate(tourDay, inSameDayAs: now)
    }

    /// "No more tips".
    @MainActor static func stop() {
        UserDefaults.standard.set(true, forKey: offKey)
        update()
    }

    /// "Show the tips again" also undoes "No more tips".
    static func resume() {
        UserDefaults.standard.removeObject(forKey: offKey)
    }

    /// The two buttons every tip gets: "Got it" closes it, "No more tips" closes it and stops the rest.
    static func actions(_ tip: some Tip) -> [Tips.Action] {
        [
            Tips.Action(id: "got-it", title: tr("Got it")) { tip.invalidate(reason: .tipClosed) },
            Tips.Action(id: "no-more-tips", title: tr("No more tips")) {
                tip.invalidate(reason: .tipClosed)
                TipPacing.stop()
            },
        ]
    }
}

/// A tip under the pacing: one new a day, from the day after the tour.
protocol PacedTip: Tip {}

extension PacedTip {
    var rules: [Rule] { [#Rule(TipPacing.$awake) { $0 }] }
    var actions: [Action] { TipPacing.actions(self) }
}

/// A tip for a rare case or the moment of use (owner's exceptions: water level in winter, water
/// nearby, cold water, boats at other clubs, the river current, and the route editor's tips while
/// editing): shows when it applies, also on the day of the tour, and besides the daily tip.
protocol MomentTip: Tip {}

extension MomentTip {
    var rules: [Rule] { [#Rule(TipPacing.$on) { $0 }] }
    var options: [any TipOption] { [Tips.IgnoresDisplayFrequency(true)] }
    var actions: [Action] { TipPacing.actions(self) }
}
