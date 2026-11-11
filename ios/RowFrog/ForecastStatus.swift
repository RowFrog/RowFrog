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
enum ForecastLoad {
    /// Nothing to show yet; `lastFailure` is why the try before failed, if one
    /// did, so "No forecast" stays up while it tries again.
    case loading(lastFailure: RefreshFailure?)
    /// Nothing to show: the last try failed.
    case failed(RefreshFailure)
    /// A forecast to show, as the backend sent it, with when it reached the
    /// phone, whether a newer one is on its way, and why the last update failed.
    case shown(ClubForecast, loadedAt: Date, updating: Bool, failure: RefreshFailure?)

    var forecast: ClubForecast? {
        switch self {
        case let .shown(forecast, _, _, _): forecast
        case .loading, .failed: nil
        }
    }

    var loadedAt: Date? {
        switch self {
        case let .shown(_, loadedAt, _, _): loadedAt
        case .loading, .failed: nil
        }
    }

    var isLoading: Bool {
        switch self {
        case .loading: true
        case .failed: false
        case let .shown(_, _, updating, _): updating
        }
    }

    var failure: RefreshFailure? {
        switch self {
        case let .loading(lastFailure): lastFailure
        case let .failed(failure): failure
        case let .shown(_, _, _, failure): failure
        }
    }

    /// A load begins: what is shown stays, with its failure until one works.
    static func started(from state: ForecastLoad?) -> ForecastLoad {
        switch state {
        case nil: .loading(lastFailure: nil)
        case let .loading(lastFailure): .loading(lastFailure: lastFailure)
        case let .failed(failure): .loading(lastFailure: failure)
        case let .shown(forecast, loadedAt, _, failure): .shown(forecast, loadedAt: loadedAt, updating: true, failure: failure)
        }
    }

    /// The load failed: what is shown stays, with the reason.
    func failing(with failure: RefreshFailure) -> ForecastLoad {
        if case let .shown(forecast, loadedAt, _, _) = self {
            return .shown(forecast, loadedAt: loadedAt, updating: false, failure: failure)
        }
        return .failed(failure)
    }

    /// The load was called off (the view that asked went away): back to where
    /// it was, or nil when nothing was there before.
    func calledOff() -> ForecastLoad? {
        switch self {
        case let .loading(lastFailure): lastFailure.map(ForecastLoad.failed)
        case .failed: self
        case let .shown(forecast, loadedAt, _, failure): .shown(forecast, loadedAt: loadedAt, updating: false, failure: failure)
        }
    }
}
