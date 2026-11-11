/// Names of values the app keeps in UserDefaults, or reads there as launch
/// arguments (`-RWScrollPage 2`), that more than one place uses. One name
/// here instead of the same string typed in several files, so a typo can't
/// silently read nothing. The settings have their own list (AppSettings.Keys).
/// The widget compiles this file too.
enum DefaultsKey {
    // Kept between launches
    /// The rowing pace for route times, seconds per 500 m.
    static let routePace = "RWRoutePace"
    /// Whether the rain radar plays as a loop.
    static let radarLoop = "RWRadarLoop"
    /// The home base's club id.
    static let homeClub = "RWHomeClub"

    // Launch arguments for screenshots and UI tests (see docs/handbook.md)
    static let scrollPage = "RWScrollPage"
    static let openClub = "RWOpenClub"
    static let chartSelect = "RWChartSelect"
    static let staleForecast = "RWStaleForecast"
    static let forecastFailure = "RWForecastFailure"
    static let noForecast = "RWNoForecast"
    static let showSettings = "RWShowSettings"
    static let sampleRadar = "RWSampleRadar"
    static let radarLoading = "RWRadarLoading"
    static let radarFailed = "RWRadarFailed"
    static let importRows = "RWImportRows"
    static let addPlace = "RWAddPlace"
    static let browse = "RWBrowse"
    static let savedRoutes = "RWSavedRoutes"
    static let routePoint = "RWRoutePoint"
    static let boatAt = "RWBoatAt"
}
