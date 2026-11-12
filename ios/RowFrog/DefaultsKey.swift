/// Names of values the app keeps in UserDefaults, or reads there as launch
/// arguments (`-RWScrollPage 2`). One name here instead of a string typed in
/// the file that reads it, so a typo can't silently read nothing, and so every
/// screenshot and test switch the app reads is in this one list (how to use
/// them: docs/handbook.md, "Launch arguments"). The switches are not limited to
/// Debug builds. The settings have their own list (AppSettings.Keys). The
/// widget compiles this file too.
enum DefaultsKey {
    // Kept between launches
    /// The rowing pace for route times, seconds per 500 m.
    static let routePace = "RWRoutePace"
    /// Whether the rain radar plays as a loop.
    static let radarLoop = "RWRadarLoop"
    /// The home base's club id.
    static let homeClub = "RWHomeClub"
    /// The club search lists a country's clubs by town instead of by name.
    static let countryListByTown = "RWCountryListByTown"
    /// Satellite pictures under the map in Add a place.
    static let addPlaceImagery = "RWAddPlaceImagery"
    /// The lake view shows an imported row's track.
    static let showTrack = "RWShowTrack"
    /// Apple's satellite pictures under the lake view.
    static let lakeImagery = "RWLakeImagery"
    /// Satellite pictures under the launch point map.
    static let launchImagery = "RWLaunchImagery"

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

    // Screenshot and test switches: Start and data
    /// `<url>`: read forecasts from there instead of the build's address (UI tests).
    static let apiBaseURL = "RWAPIBaseURL"
    /// Forget everything saved, as after a new install.
    static let freshStart = "RWFreshStart"
    /// The three confirmed clubs with MRC 1880 as home base.
    static let demoClubs = "RWDemoClubs"
    /// Skip the first-start safety notice.
    static let safetyAccepted = "RWSafetyAccepted"
    /// Act as if Low Data Mode were on.
    static let saveData = "RWSaveData"
    /// Show the "updates less often" tip on every club.
    static let slowRefresh = "RWSlowRefresh"

    // Screenshot and test switches: Galleries instead of the app
    /// Show the symbol gallery.
    static let iconGallery = "RWIconGallery"
    /// Show the conditions preview.
    static let conditionsPreview = "RWConditionsPreview"
    /// Show the widget gallery.
    static let widgetGallery = "RWWidgetGallery"
    /// Made-up light rain on the widget's radar line (with the widget gallery).
    static let widgetRadar = "RWWidgetRadar"

    // Screenshot and test switches: Tour and tips
    /// `n`: open the first-start tour at page n.
    static let tutorialPage = "RWTutorialPage"
    /// The tour's home base page picks the first suggestion by itself.
    static let tourAutoHome = "RWTourAutoHome"
    /// Hide every one-time tip.
    static let noTips = "RWNoTips"
    /// Show every one-time tip.
    static let showTips = "RWShowTips"
    /// Show the boats-kept-elsewhere tip.
    static let boatTip = "RWBoatTip"
    /// Show the place line tip.
    static let placeTip = "RWPlaceTip"
    /// Show the suggest-a-launch-point tip.
    static let suggestTip = "RWSuggestTip"
    /// Show the nearby-water tip (and its reason line).
    static let nearbyTip = "RWNearbyTip"
    /// Show the tips that come later (all values, radar map, hour view, …).
    static let laterTips = "RWLaterTips"

    // Screenshot and test switches: Club list and layout
    /// Turn the phone on its side.
    static let landscape = "RWLandscape"
    /// Start with the list beside the page slid away (iPad).
    static let sideListHidden = "RWSideListHidden"
    /// `Name;lat;lon`: add that own place (once) and open it.
    static let ownPlace = "RWOwnPlace"
    /// `<text>`: open the club search with this text filled in.
    static let search = "RWSearch"
    /// Open the club list.
    static let showList = "RWShowList"
    /// The club list starts in edit mode.
    static let editList = "RWEditList"
    /// `<text>`: a country's club list starts with this search.
    static let countryFilter = "RWCountryFilter"

    // Screenshot and test switches: Club page
    /// `<card>`: scroll the club page to that card (see the handbook).
    static let scrollTo = "RWScrollTo"
    /// Open "Arrange this page".
    static let arrange = "RWArrange"
    /// Open the folded 48-hour table.
    static let hourlyOpen = "RWHourlyOpen"
    /// `n`: open the hour view of the table's n-th hour.
    static let openHour = "RWOpenHour"
    /// `lights`: open the rowing light legend from the top tile.
    static let legend = "RWLegend"
    /// `<name>`: open that value's detail view.
    static let openCondition = "RWOpenCondition"
    /// `<condition>`: show that value's line in the closed top tile.
    static let samplePeek = "RWSamplePeek"
    /// A made-up "Shore ice possible" line in the top tile.
    static let sampleIce = "RWSampleIce"
    /// `wind,thunderstorm,…`: colour those values as if they set the light amber.
    static let sampleCause = "RWSampleCause"
    /// `fog|wind|waves`: worse water near the launch point in the first six hours.
    static let sampleNearby = "RWSampleNearby"
    /// A detail view opens with its limits shown.
    static let limitInfo = "RWLimitInfo"
    /// The shore warning lights part of the warnings card starts open.
    static let shoreLights = "RWShoreLights"
    /// Open the update cycles sheet of the page in front.
    static let openUpdates = "RWOpenUpdates"
    /// Open the forecast source sheet.
    static let openForecastSource = "RWOpenForecastSource"

    // Screenshot and test switches: Maps and pictures
    /// Open the rain radar map from the radar card.
    static let openRadarMap = "RWOpenRadarMap"
    /// `<layer>`: open the weather map from the open detail view.
    static let openWeatherMap = "RWOpenWeatherMap"
    /// Open the satellite picture full screen.
    static let openSatellite = "RWOpenSatellite"
    /// `n`: the full satellite picture n times closer.
    static let satelliteZoom = "RWSatelliteZoom"
    /// Open the launch point sheet from the header of the page in front.
    static let openLaunchPoint = "RWOpenLaunchPoint"
    /// The launch point sheet at full height.
    static let launchPointFull = "RWLaunchPointFull"
    /// The launch point card's live map instead of its still picture.
    static let liveLaunchMap = "RWLiveLaunchMap"
    /// `metres`: the launch point map's span (default 1500).
    static let launchSpan = "RWLaunchSpan"
    /// Also open "Suggest the launch point".
    static let suggestLaunchPoint = "RWSuggestLaunchPoint"

    // Screenshot and test switches: Lake view and routes
    /// Open the lake view.
    static let openLakeView = "RWOpenLakeView"
    /// The lake view opens with its legend.
    static let lakeLegend = "RWLakeLegend"
    /// `twilight|cold|dark`: the whole-lake light of every hour.
    static let lakeWide = "RWLakeWide"
    /// `n`: the lake view opens n hours on.
    static let lakeHour = "RWLakeHour"
    /// `<layer>`: the lake view's layer.
    static let lakeLayer = "RWLakeLayer"
    /// `lat,lon`: a picked spot in the lake view.
    static let lakeSpot = "RWLakeSpot"
    /// `lat,lon;lat,lon;…`: open route mode with these points.
    static let route = "RWRoute"
    /// Row the route out and back.
    static let outAndBack = "RWOutAndBack"
    /// `expanded`: the lake view's panel starts open.
    static let panel = "RWPanel"
    /// Import a made-up row along the route.
    static let importedRoute = "RWImportedRoute"

    // Screenshot and test switches: Settings
    /// `<page>`: open that Settings page, with the pages on the way.
    static let settingsPage = "RWSettingsPage"
    /// `<text>`: open the settings with the search filled in.
    static let settingsSearch = "RWSettingsSearch"
    /// Open the New boat sheet (with the limits page).
    static let newBoat = "RWNewBoat"
}
