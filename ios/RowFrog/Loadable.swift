import Foundation

/// Where one download is, one state at a time, the same for every store that
/// loads something per key (a club's forecast, a lake view, …). Before, each
/// store kept separate lists (what came, when, what is loading, what failed)
/// that every change had to keep in step by hand, and each did it a little
/// differently. No entry in a store means nothing was asked for yet.
///
/// The moves (`started`, `failing`, `calledOff`) are plain functions, so the
/// tests (LoadableTests, ForecastLoadTests) check them without a network.
enum Loadable<Value, Failure> {
    /// Nothing to show yet; `lastFailure` is why the try before failed, if one
    /// did, so the failure stays up while it tries again.
    case loading(lastFailure: Failure?)
    /// Nothing to show: the last try failed.
    case failed(Failure)
    /// Something to show, with when it reached the phone, whether a newer one
    /// is on its way, and why the last update failed.
    case shown(Value, loadedAt: Date, updating: Bool, failure: Failure?)

    /// What there is to show.
    var value: Value? {
        switch self {
        case let .shown(value, _, _, _): value
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

    var failure: Failure? {
        switch self {
        case let .loading(lastFailure): lastFailure
        case let .failed(failure): failure
        case let .shown(_, _, _, failure): failure
        }
    }

    /// The last try failed (with or without something to show).
    var hasFailed: Bool { failure != nil }

    /// A load begins: what is shown stays, with its failure until one works.
    static func started(from state: Loadable?) -> Loadable {
        switch state {
        case nil: .loading(lastFailure: nil)
        case let .loading(lastFailure): .loading(lastFailure: lastFailure)
        case let .failed(failure): .loading(lastFailure: failure)
        case let .shown(value, loadedAt, _, failure): .shown(value, loadedAt: loadedAt, updating: true, failure: failure)
        }
    }

    /// The load worked.
    static func loaded(_ value: Value, at date: Date = .now) -> Loadable {
        .shown(value, loadedAt: date, updating: false, failure: nil)
    }

    /// The load failed: what is shown stays, with the reason.
    func failing(with failure: Failure) -> Loadable {
        if case let .shown(value, loadedAt, _, _) = self {
            return .shown(value, loadedAt: loadedAt, updating: false, failure: failure)
        }
        return .failed(failure)
    }

    /// The load was called off (the view that asked went away): back to where
    /// it was, or nil when nothing was there before.
    func calledOff() -> Loadable? {
        switch self {
        case let .loading(lastFailure): lastFailure.map(Loadable.failed)
        case .failed: self
        case let .shown(value, loadedAt, _, failure): .shown(value, loadedAt: loadedAt, updating: false, failure: failure)
        }
    }
}
