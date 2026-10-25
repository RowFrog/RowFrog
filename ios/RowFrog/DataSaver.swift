import Foundation
import Network

/// Whether the app should go easy on data: always in iOS Low Data Mode, and on
/// mobile data (or a phone's hotspot) when "Save mobile data" is on in the
/// settings. Then satellite pictures wait for a tap, the radar map takes
/// half-hour steps and the rain radar card refreshes every 15 minutes.
/// Forecasts, warnings and the lake view always load.
@Observable
@MainActor
final class DataSaver {
    static let shared = DataSaver()
    /// iOS Low Data Mode, for Wi-Fi or mobile data.
    private(set) var lowDataMode = false
    /// Mobile data or a personal hotspot.
    private(set) var mobile = false
    @ObservationIgnored private let monitor = NWPathMonitor()

    /// Screenshot hook: `-RWSaveData YES` acts as if Low Data Mode were on.
    private let forced = UserDefaults.standard.bool(forKey: "RWSaveData")

    var saving: Bool { lowDataModeOn || (mobile && AppSettings.shared.saveMobileData) }
    /// Low Data Mode, or the screenshot hook standing in for it.
    var lowDataModeOn: Bool { forced || lowDataMode }

    private init() {
        monitor.pathUpdateHandler = { path in
            let constrained = path.isConstrained, expensive = path.isExpensive
            MainActor.assumeIsolated {
                DataSaver.shared.lowDataMode = constrained
                DataSaver.shared.mobile = expensive
            }
        }
        monitor.start(queue: .main)
    }
}
