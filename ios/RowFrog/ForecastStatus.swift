import Foundation

/// What a club page says about its forecast, one state at a time.
///
/// The list is written down once, in testdata/states/forecast-status.json,
/// which the app's tests (ForecastStatusTests) and the website's
/// (web/tests/forecaststatus.test.mjs, logic.js forecastStatus) both read, so
/// the two cannot drift apart again. Before, each screen worked the state out
/// from separate lists in its own order, and the app and the website
/// disagreed when a forecast was out of date and its update failed.
/// Change this, logic.js and the table together.
enum ForecastStatus: Equatable {
    /// Nothing to show yet: stand-in cards.
    case loading
    /// Nothing to show, and loading failed: the reason and Try again.
    case noForecast(RefreshFailure)
    /// Shown and fresh: "Forecast from … · loaded …".
    case current
    /// Shown, and a newer one is on its way.
    case updating
    /// Shown, but older than ClubForecast.staleAfter.
    case outOfDate
    /// Shown, but the last update failed; the reason is a tap away.
    case updateFailed(RefreshFailure, outOfDate: Bool)

    /// The one place that decides the order (owner, 11 Nov 2026: out of date
    /// and a failed update both show).
    static func of(hasForecast: Bool, outOfDate: Bool, loading: Bool, failure: RefreshFailure?) -> ForecastStatus {
        guard hasForecast else { return failure.map(ForecastStatus.noForecast) ?? .loading }
        if let failure { return .updateFailed(failure, outOfDate: outOfDate) }
        if outOfDate { return .outOfDate }
        return loading ? .updating : .current
    }

    /// The shown forecast is too old to trust: the out-of-date line shows.
    var isOutOfDate: Bool {
        switch self {
        case .outOfDate, .updateFailed(_, outOfDate: true): true
        default: false
        }
    }

    /// The state's name in testdata/states/forecast-status.json.
    var name: String {
        switch self {
        case .loading: "loading"
        case .noForecast: "noForecast"
        case .current: "current"
        case .updating: "updating"
        case .outOfDate: "outOfDate"
        case .updateFailed(_, let outOfDate): outOfDate ? "outOfDateAndUpdateFailed" : "updateFailed"
        }
    }
}

extension ForecastStore {
    /// The state of a club's forecast as the page shows it.
    func status(_ clubID: String, at date: Date = .now) -> ForecastStatus {
        let shown = forecast(clubID)
        return .of(hasForecast: shown != nil, outOfDate: shown?.isStale(at: date) ?? false,
                   loading: loading.contains(clubID), failure: failures[clubID])
    }
}

/// Where one club's forecast is in the store: one state at a time. Before,
/// ForecastStore kept four separate lists (forecasts, load times, clubs
/// loading, failures) that every change had to keep in step by hand.
/// No entry in the store means nothing was asked for yet.
typealias ForecastLoad = Loadable<ClubForecast, RefreshFailure>

extension Loadable where Value == ClubForecast {
    var forecast: ClubForecast? { value }
}
