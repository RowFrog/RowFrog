import SwiftUI

/// What a cold start shows first (decision 0046). The app reads what the last
/// visit showed of the first page (the club catalog, the home base's forecast,
/// its lake view and satellite picture, and the page's background picture)
/// before it draws its first frame, so the page opens complete with
/// "Updating…" while the new data loads. iOS keeps the launch screen up for
/// these few milliseconds. Before, the page showed a spinner, then stand-in
/// cards, then the kept forecast, and the lake view and pictures came last
/// (owner's screen recording, 16 Nov 2026).
///
/// With nothing kept (the first start, or a club never opened), the stand-in
/// cards show, with a light sweep (LoadingCards).
@MainActor
enum ColdStart {
    static func prime(locations: LocationStore, forecasts: ForecastStore, api: APIClient) {
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.stayLoading) else { return }
        locations.primeCatalog(api)
        guard let club = locations.saved.first else { return }
        forecasts.primeKept(club.id)
        if let forecast = forecasts.forecasts[club.id] {
            LakeViewStore.shared.primeKept(forecast.lakeId)
            let lake = locations.lake(of: club)
            // As LocationPageView.satelliteID: a river stretch without an outline has the club's own picture.
            SatellitePictureStore.shared.primeKept(lake?.hasOutline == false ? "club-\(club.id)" : forecast.lakeId, clubID: club.id)
        }
        // The page's picture, which otherwise is read off the main thread and fades in later.
        let choice = AppSettings.shared.background(for: .clubPages, clubID: club.id)
        if case .satellite = choice { return }
        _ = BackgroundLibrary.image(for: choice, clubID: club.id)
    }
}
