import SwiftUI
import TipKit

// The one-time tips (TipKit), split off Tutorial.swift unchanged. Where each shows: the
// views that attach them; how they are switched on for screenshots: Tutorial.configureTips.

struct HourlyTip: Tip {
    var title: Text { Text(tr("Plan your outing")) }
    var message: Text? { Text(tr("Each hour has its own rowing light. The icons on top name the columns, and rows after dark are dimmed.")) }
    var image: Image? { Image(systemName: "clock") }
}

/// At the lake and town line under the club's name, while it opens the map (launch point in the header).
struct PlaceLineTip: Tip {
    var title: Text { Text(tr("Where the forecast is for")) }
    var message: Text? { Text(tr("Tap the place to see on a map the spot the forecast is for, with directions.")) }
    var image: Image? { Image(systemName: "mappin.and.ellipse") }
}

/// At "Suggest the launch point" in the Location sheet, for clubs whose club hasn't confirmed it.
/// The button goes once a suggestion was sent, and the tip with it.
struct SuggestLaunchPointTip: Tip {
    var title: Text { Text(tr("Know the launch point?")) }
    var message: Text? { Text(tr("Know where this club's boats go on the water? Suggest the launch point.")) }
    var image: Image? { Image(systemName: ClubMarks.launchSymbol) }
}

struct LaunchPointTip: Tip {
    var title: Text { Text(tr("Where the forecast is for")) }
    var message: Text? { Text(tr("Wind, waves and warnings are worked out for this launch point. Tap Open in Maps for directions.")) }
    var image: Image? { Image(systemName: "mappin.and.ellipse") }
}

struct BackgroundsTip: Tip {
    var title: Text { Text(tr("One picture or many")) }
    var message: Text? { Text(tr("Pick a picture for all pages, a different one for single pages, or give a club its own. Under Look, choose whether the tiles show the picture or stay solid.")) }
    var image: Image? { Image(systemName: "photo.on.rectangle") }
}

struct FactoryResetTip: Tip {
    var title: Text { Text(tr("What a reset does")) }
    var message: Text? { Text(tr("Settings, units, boat limits and background pictures go back to how the app came, and your own pictures are deleted. Your clubs, boats and home base stay.")) }
    var image: Image? { Image(systemName: "arrow.counterclockwise") }
}

struct ConditionsExtrasTip: Tip {
    var title: Text { Text(tr("More on the air")) }
    var message: Text? { Text(tr("Feels like now covers wind chill and heat. Humidity shows the dew point underneath, and the gauge shows the air pressure and where it is heading.")) }
    var image: Image? { Image(systemName: "gauge.with.dots.needle.33percent") }
}

struct AppIconTip: Tip {
    var title: Text { Text(tr("Pick your app icon")) }
    var message: Text? { Text(tr("Choose the icon Row Frog shows on your home screen.")) }
    var image: Image? { Image(systemName: "app.badge") }
}

/// In the settings only, by the owner's wish: no tour step.
struct SaveDataTip: Tip {
    var title: Text { Text(tr("Out on mobile data?")) }
    var message: Text? { Text(tr("Switch on Save mobile data: satellite pictures then load only when you tap them and the radar needs fewer downloads. Forecasts and warnings always load.")) }
    var image: Image? { Image(systemName: "antenna.radiowaves.left.and.right") }
}

struct LakeViewTip: Tip {
    var title: Text { Text(tr("Look across the lake")) }
    var message: Text? { Text(tr("Tap the map to see the rowing light, waves and wind for the whole lake, hour by hour. Tap the water for the details of one spot.")) }
    var image: Image? { Image(systemName: "map") }
}

struct RainRadarTip: Tip {
    var title: Text { Text(tr("Rain on the way?")) }
    var message: Text? { Text(tr("For the next two hours the rain tile reads the radar of the Deutscher Wetterdienst at the launch point, in 15-minute steps, and the forecast after that. The radar updates every few minutes.")) }
    var image: Image? { Image(systemName: "umbrella") }
}

struct RadarMapTip: Tip {
    var title: Text { Text(tr("Rain radar map")) }
    var message: Text? { Text(tr("Open the rain tile: for the next two hours its map shows the radar. Tap the map to play it, or drag the slider from an hour ago to two hours ahead.")) }
    var image: Image? { Image(systemName: "map") }
}

struct HourViewTip: Tip {
    var title: Text { Text(tr("One hour in full")) }
    var message: Text? { Text(tr("Tap an hour to see all its conditions and the lake map at that time.")) }
    var image: Image? { Image(systemName: "hand.tap") }
}

struct SatellitePictureTip: Tip {
    var title: Text { Text(tr("Satellite picture")) }
    var message: Text? { Text(tr("The latest picture from the Sentinel-2 satellites, which pass over every 2 to 5 days, so it can be a few days old and show clouds. Clearest shows the most recent picture with a clear view of the lake. Draw the shore, clubs, your routes, the wind, the waves, the rowing light or the ice map over it.")) }
    var image: Image? { Image(systemName: "globe.europe.africa") }
}

struct ForecastSourceTip: Tip {
    var title: Text { Text(tr("Where the forecast comes from")) }
    var message: Text? { Text(tr("The app picks the weather model that does best for this lake. Tap the line to see which one.")) }
    var image: Image? { Image(systemName: "cloud.sun") }
}

struct MyBoatsTip: Tip {
    var title: Text { Text(tr("Which boat do you row?")) }
    var message: Text? { Text(tr("Tap the boat the rowing light is for. ⓘ opens its limits, and below you can add your own boats.")) }
    var image: Image? { Image(systemName: "figure.rower") }
}

struct ColdWaterTip: Tip {
    var title: Text { Text(tr("Cold water")) }
    var message: Text? { Text(tr("A capsize in water below %@ gets dangerous within minutes. The app then lowers its own wind and gust limits by %@. Limits you set stay as they are, with a reminder on the rowing light.", Format.temperature(RowingLimits.coldWaterC), Format.wind(RowingLimits.coldWindMarginMs))) }
    var image: Image? { Image(systemName: "thermometer.snowflake") }
}

/// Under the top tile, the first time its Why line has a "… nearby" reason (#395).
struct NearbyWaterTip: Tip {
    var title: Text { Text(tr("Water nearby")) }
    var message: Text? { Text(tr("The light also looks at the water within 1 km of the launch point. If it is rougher or foggier out there, the Why line says so.")) }
    var image: Image? { Image(systemName: "scope") }
}

/// After "Tap a value": the grip that opens Current conditions inside the top tile.
struct AllValuesTip: Tip {
    var title: Text { Text(tr("All values in the top tile")) }
    var message: Text? { Text(tr("Tap \"All values\" under the tile to see every value there. Tap \"Fewer values\" to close it.")) }
    var image: Image? { Image(systemName: "rectangle.expand.vertical") }
}

struct TopTileTip: Tip {
    var title: Text { Text(tr("Tap a value")) }
    var message: Text? {
        Text(AppSettings.shared.combinedTopTile
             ? tr("Tap a value in the tile above to open its chart; swiping there goes through all values. \"All values\" under the tile opens the rest.")
             : tr("Tap a value in the tile above to open its chart. Swiping there goes through only this tile's values."))
    }
    var image: Image? { Image(systemName: "hand.tap") }
}

/// Only on a lake let down for the winter (Forggensee), once its Water level tile shows.
struct WaterLevelTip: Tip {
    var title: Text { Text(tr("Water level in winter")) }
    var message: Text? { Text(tr("Forggensee is let down every winter. While it is lowered, the Water level tile below takes the place of the ice estimate. Tap it for the last week's levels.")) }
    var image: Image? { Image(systemName: LakeLevel.symbol) }
}

/// On a river or canal club's page, for a club added after the tour (the tour's river page closes it).
struct RiverCurrentTip: Tip {
    var title: Text { Text(tr("Current on the river")) }
    var message: Text? { Text(tr("The Current tile shows the nearest gauge's flow speed, water level and trend. Tap it for the level chart and your pace upstream and downstream.")) }
    var image: Image? { Image(systemName: RiverConditions.symbol) }
}

struct WaterEstimateTip: Tip {
    var title: Text { Text(tr("Water temperature from space")) }
    var message: Text? { Text(tr("No station measures the water here, so the app takes the last satellite reading of the lake and carries it forward with the air temperatures since. Tap the water tile for the satellite and its date.")) }
    var image: Image? { Image(systemName: "thermometer.and.liquid.waves") }
}

struct ChartScrubTip: Tip {
    var title: Text { Text(tr("Read any hour")) }
    var message: Text? { Text(tr("Hold the chart, then slide along it to read the value at each hour.")) }
    var image: Image? { Image(systemName: "hand.draw") }
}

/// On a club page where one of the user's own boats is kept at another club.
struct BoatsElsewhereTip: Tip {
    var title: Text { Text(tr("Your boats at other clubs")) }
    var message: Text? { Text(tr("Your boats show at the clubs where they are kept. At a regatta, tap a boat under “At other clubs” to take it along.")) }
    var image: Image? { Image(systemName: "arrow.down.circle") }
}

struct RoutePlanningTip: Tip {
    var title: Text { Text(tr("Plan a route")) }
    var message: Text? { Text(tr("Tap here, then tap your turning points on the water. You see the light along the route and the best time to start.")) }
    var image: Image? { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath") }
}

struct RoutePanelTip: Tip {
    var title: Text { Text(tr("More or less panel")) }
    var message: Text? { Text(tr("Pull up for details, push down for more map.")) }
    var image: Image? { Image(systemName: "rectangle.bottomhalf.inset.filled") }
}

struct CloseLoopTip: Tip {
    var title: Text { Text(tr("Row a loop")) }
    var message: Text? { Text(tr("Close the loop: tap within 50 m of your club, or pick Loop under the way back.")) }
    var image: Image? { Image(systemName: "arrow.triangle.capsulepath") }
}

struct TurningPointTip: Tip {
    var title: Text { Text(tr("Change a turning point")) }
    var message: Text? { Text(tr("Drag a point to move it, or delete just this one.")) }
    var image: Image? { Image(systemName: "hand.draw") }
}

struct BoatTimeTip: Tip {
    var title: Text { Text(tr("Lake at the boat's time")) }
    var message: Text? { Text(tr("Move the boat along your route to see the lake at the time you get there.")) }
    var image: Image? { Image(systemName: "figure.rower") }
}

struct StretchPointTip: Tip {
    var title: Text { Text(tr("Add a point on the way")) }
    var message: Text? { Text(tr("Tap a stretch of your route to add a turning point there, or pull the stretch to add one and move it at once.")) }
    var image: Image? { Image(systemName: "point.3.connected.trianglepath.dotted") }
}

struct OneWayTip: Tip {
    var title: Text { Text(tr("One way or out and back")) }
    var message: Text? { Text(tr("New routes go one way. Pick Out and back under the way back to row the same way back.")) }
    var image: Image? { Image(systemName: "arrow.uturn.backward") }
}

struct RowImportTip: Tip {
    var title: Text { Text(tr("Import a row")) }
    var message: Text? { Text(tr("Rowed it before? Bring in a row from Apple Health or a GPX, TCX or FIT file (CrewNerd, Garmin, Strava) in the Routes menu, and plan with your real route and pace.")) }
    var image: Image? { Image(systemName: "square.and.arrow.down.on.square") }
}

struct WeatherMapTip: Tip {
    var title: Text { Text(tr("Weather on the map")) }
    var message: Text? { Text(tr("The map shows this weather around the lake. Press play to watch it move, or open it full screen with the arrows.")) }
    var image: Image? { Image(systemName: "map") }
}

struct MapLinkTip: Tip {
    /// Set once the weather map tip above the card is closed, so the two don't show together.
    @Parameter static var mapTipClosed: Bool = false

    var rules: [Rule] { [#Rule(Self.$mapTipClosed) { $0 }] }
    var title: Text { Text(tr("Chart and map together")) }
    var message: Text? { Text(tr("The map shows the hour of the chart's blue line. Tap the chain to give the map its own time, and again to link them.")) }
    var image: Image? { Image(systemName: "link") }
}
