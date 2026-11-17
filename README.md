# Row Frog

Weather, conditions and forecasts for rowers at their rowing club, with
webcam pictures where they are available later on.

For each club's launch point the app shows an hourly green / amber / red
"can we row?" light for the next 48 hours, and the conditions behind it:
wind, gusts, computed wave height, fog, thunderstorm risk, air and water
temperature, rain radar, ice cover, official weather warnings and daylight.
It started with the lakes south of Munich (Starnberger See first) and can
show rowing clubs across Germany, Austria and Switzerland, or a place of your
own.

The app is free. It is an iPhone and iPad app (iOS 18 or later) written in SwiftUI;
Android may follow later.

> **Name.** The app is called **Row Frog**, formerly "RowerWeather" (renamed
> in October 2026). The app and widget use the bundle IDs
> `com.rowfrog.RowFrog` and `com.rowfrog.RowFrog.Widget`, the app group
> `group.com.rowfrog.RowFrog` and links starting with `rowfrog://`. In the
> code the Xcode project is `RowFrog.xcodeproj` (targets `RowFrog`,
> `RowFrogWidget`, `RowFrogTests`, `RowFrogUITests`) and the Python package is `rowfrog`.

Hidden switches, test steps, launch arguments, workflows and the secrets they
need are in the **[handbook](docs/handbook.md)**.

## What the app does

**Safety notice.** Before anything else, a first start shows a "Before you
row" safety notice that has to be accepted; it cannot be skipped, and a new
version of it is asked for again. It opens in the phone's language. Across the app, "Advice only, you decide"
lines remind rowers that the app only advises and they decide. A forecast
older than 3 hours shows a grey light instead of green.

**Locations.** On first start the list is empty: a short tour explains the
app (11 pages, including your boats and rowing limits), then the user picks a
home base and more clubs. With location access
("While using") it suggests the 5 nearest clubs, otherwise 3 at random. The
search covers the clubs in Germany, Austria and Switzerland (see
[Club catalog](#club-catalog)) in one box, with country chips to narrow it,
and the clubs can also be browsed country by country, by water or by town.
The search also finds waters and towns, waters with the same name share one
row, and clubs whose water is not known are listed under their town.
Pages swipe left and right between saved locations, like the iOS Weather
app. The list shows each location's light and key numbers, with feels like under the temperature and an estimated water temperature in grey with ≈; swipe a row to
remove it or make it the home base. The saved list stays on the phone.
As in Apple Weather, the search field and the settings cog sit at the bottom
of the list (on iPad on its side the search is at the top of the side list and
the cog on the club page), a "…" menu at the top right
holds Edit, Browse by country and Add a place, and the big "Locations" title
shrinks into the bar once the list scrolls. Tapping a club opens its page.
On iPhone the club pages have a bottom bar with the settings cog and the boat
button on the left, the page dots (with one saved club, a round house button
instead) and the list button on the right, as in
Weather: a tap on a page dot moves one club towards it with a slide, and a
finger along the dots jumps. The website slides its club pages the same way,
and a club picked in its list zooms open from its row. On iPad a
sidebar button slides the list in over the page (upright) or away beside it
(on its side). Screens that only show something (settings, value pages, maps,
legends, sources and the like) close with a round X at the top left; editing
sheets keep Cancel and Done, and cards inside a screen (a tapped spot, a
turning point) close with a small grey X at their top right. App and website
match.

**Add a place.** A club, boathouse or spot on the water that no list has can
be put on the map. It stays on the phone, and its forecast is worked out on
the phone straight from Open-Meteo, since the published forecasts only cover
listed clubs (`ios/RowFrog/OwnPlaces.swift`). Only if the user turns it
on, the place is suggested for everyone's list: the Row Frog suggestions
service (a Cloudflare Worker in `cloudflare/suggestions/`) files it as a
GitHub issue, so no GitHub account is needed.

**Each location page** is a column of cards, in this order by default:

1. A top tile with the rowing light, which boat it is for and why it has that
   colour; air, water and wind, with waves, rain and visibility in the same
   three columns below (two or one when the text is too large for three), each with a short grey line ("Dry for 24 h");
   an official warnings status line and a daylight line. Tapping a value
   opens its chart. A value that sets the light amber or red shows its number
   in that colour, and cold water shows in blue while the life jacket badge
   is on; while daylight is the reason, the sunrise or sunset time takes the
   light's colour. Tapping "All values" under the sun line opens Current
   conditions inside the tile; tapping "Fewer values" closes it. Each club
   page starts closed and keeps its choice until the app restarts. Closed, a hidden value that counts for the light
   (thunderstorm, or ice when it matters) shows as one line under the sun line.
2. The official warnings card, only while a warning is issued (or the check
   failed).
3. Lake view (River or Canal view for river and canal clubs).
4. Next 48 hours, with a feels-like column and a day header that stays in
   place while scrolling; tapping an hour opens that hour's view. Each night's
   dark hours fold into one tinted line (lowest temperature, strongest wind,
   highest waves, all its rain), which opens on a tap. When the 48 hours end
   in the night, the table runs on to the sunrise hour with the coarser
   ICON-EU model; the night line says from when, and those hours carry ≈ in
   the opened night. The website does the same.
5. Satellite picture.
6. Forecast source, "How often data is updated" (a sheet with each value's
   source, how often that source updates and how often Row Frog fetches it)
   and credits.

The rain radar card is off by default (see Rain radar) and can be switched
on in Arrange this page. The launch point lives in the club header (see
Location). Settings › Club pages › Current conditions in the top tile
(on by default) can be turned off to show Current conditions as its own card
again, after the warnings. The website does the same.

"Arrange this page" at the end of the page reorders or hides cards, for all
clubs or only this one. Every card has an ⓘ button that explains its symbols;
the full legend is in Settings › Help. When a steadier boat of your own would
get a better light, the page suggests it.

**Current conditions.** Inside the opened top tile (or as its own card), tiles in two columns, each with a
small graphic: wind, gusts, waves, temperatures, rain, cloud, visibility,
pressure, humidity, UV index, sun and ice, among others. Tapping a tile opens
a detail view with a chart you can drag from yesterday to 7 days ahead, with
a line that shows the values at any time and dots for now ("Back to now",
or "Back to" the hour it was opened from, returns there), a unit switch at the
bottom (air pressure in hPa, mbar, bar, inHg or mmHg), the limit lines (named on the side away from now, ending before the axis numbers), wind arrows
every 3 hours, an "About the limits" note, advice for rowing and the data
source (`ios/RowFrog/ConditionsCard.swift`). The map sits in the same place
on every detail view; on the waves page it is the lake view's waves at the
chosen time, and a tap opens the lake view on that layer. Maps opened full
screen run to the top with floating buttons. Swipe between detail views,
use the arrow buttons (each shows the next value's symbol), or jump to another
from the menu in the title; tapping an entry in a chart's
legend switches its line on or off.

**Rowing limits.** Settings › Boats and limits chooses the limits the light
uses: *Small boats* (the default) or *Big boats*, or *My boats*, where each
boat has a name, a type (racing, training, gig or coastal) and a size and
rigging from 1x to 8+. Each own boat is kept at one or more clubs (its
"Kept at" list, the home base to start with) and counts only there; at a club
where the ticked boat is not kept, the light uses one of your boats kept there
(the one last picked there first), else small boats. Limits can be fine-tuned
per group and per boat. A separate choice sets which boat the lake map is coloured for, with a warning
when the map looks calmer than your boat. The phone works the light out
again for the chosen boat on the club page, the lake map and the widget
(`ios/RowFrog/Limits.swift`). The light at the launch point also counts the water
within 1 km of it (on rivers, 1 km up and down the stretch): when that water
is worse for your boat, a "nearby" reason says so, e.g. "Fog nearby: 300 m",
and the top tile shows that worst wind, wave or visibility value, in its
colour and marked "Nearby", in place of the launch point's own. The website
does the same.

**Cold water.** Cold water does not change the rowing light; the light shows
the weather. Instead a blue badge says in words what to do: "Life jacket on" below
15 °C water, against cold-water shock, and below 10 °C also "with partner
boat" (singles) or "stay near shore" (German "Weste tragen · ufernah
rudern"). The temperature stays on the water value below it, and the badge
wraps to a second line rather than shortening (`docs/decisions/0029`). The website
shows the same words. Below 10 °C the app's own wind and gust limits
are 1 m/s lower (your own limits stay as set, with a note), and below 4 °C
small boats get amber for near-freezing water. Lake maps and the satellite
picture draw the shore light blue below the life-jacket limit and deeper blue
below 10 °C; the satellite picture shows the badge too while its shore line
is on.

**Water temperature.** Each club reads the nearest measuring station on its
own water, from GKD Bayern, the German federal PEGELONLINE network or the
Swiss federal stations (BAFU, via api.existenz.ch); 85 clubs so far, listed
in `data/water-stations.json`. The water temperature view names the
station's operator and shows the station on a still map with its address. For lakes without a station the
backend works out a satellite estimate from Copernicus lake surface
temperatures and Landsat (through Microsoft's Planetary Computer, no extra
account), carried forward with the air temperatures; the top tile shows it
in grey as "Estimated", and the detail view names the satellite and the date
of the reading. Where there is no recent clear satellite view either, the
water temperature is estimated from the air temperatures alone, all year.
Where no station measures, the rowing light uses the estimate. A 7-day water
temperature forecast shows as a dashed line in the water chart, and the light
uses it for the later hours.

**Official warnings.** In Germany the page shows the official DWD warnings:
the lake warning (strong wind or storm, as the shore lights show it) where
DWD runs its lake warning service (23 lakes, among them Starnberger See,
Ammersee and Chiemsee), and DWD's weather warnings for the municipality,
which cover rivers and canals too. While one is issued it gets its own card
under the top tile, with the warnings grouped under "Now" and "Later";
otherwise the top tile's status line says there is none and when it was
checked, or that DWD could not be reached. When a check fails, the last good
one stands in for up to 3 hours, without the warnings that have ended since,
and the card says when it was checked; the website does the same. A warning that starts later or
only informs gets one line in the top tile that opens the card, and in the
club list it shows grey with an info sign and its start time; only warnings
that count for the light now or within 3 hours show amber there.
Warnings come from DWD's GeoServer (`backend/rowfrog/sources/dwd_warnings.py`)
and also set the hourly light, except frost, black ice, thaw, heat and cold
warnings, which are shown for information but leave the light and the lake map
alone. In English the app shows DWD's own English
text (from its English CAP files) with the German original below; where DWD
has no English version, only the event and headline are translated.
Each warning, in the app and on the website, ends with a link to the service
that issued it: DWD's warning page for the club's town or lake (plus its
WarnWetter app), GeoSphere Austria's map at the launch point, or MeteoSwiss's
hazards page (`backend/rowfrog/warning_links.py`).
Only at lakes that really have shore warning lights (`data/shore-lights.json`:
the Bavarian lakes, Lake Constance and Steinhuder Meer, but not, for example,
the Alster, Müritz or Dümmer) does the card explain both lights (40 and 90 flashes a minute) and
the season they run in; elsewhere it says there are no storm lights.

**Warnings in Austria and Switzerland.** Austrian clubs get GeoSphere
Austria's official warnings for their municipality
(`backend/rowfrog/sources/geosphere_warnings.py`), Swiss clubs MeteoSwiss's
regional warnings through MeteoAlarm (`backend/rowfrog/sources/meteoalarm.py`),
shown unaltered with their source. Both set the hourly light like DWD's.
Clubs on Lake Constance also get DWD's lake warning. Where no service covers a
place, the app says it cannot check the warnings there instead of saying there
are none.

**Lake view and route planning.** A tile opens a map of the whole lake with
waves, wind and the light for each part of the lake (fog, thunderstorms,
heavy rain and hail colour it too, as on the club page), and a spot you can
tap: its pin stays where you tapped and it shows the light, then waves, wind
and visibility, plus hail, thunderstorm or heavy rain while that makes it
amber or red; a value at amber or red takes that colour. The website shows
the spot the same way. In the lake tile the parts of the lake form a small table in the 48-hour
table's style: waves, wind (an arrow for its direction, then its speed) and
visibility, with the value that sets amber or red in that colour; another
reason, or a note such as "Fog near the shore, open water clear", follows a
part on its own line. Where the table does not fit (narrow phones, large
text) each part falls back to one line (`docs/decisions/0030`). The website
shows the same table. Wind, gusts, rain and visibility for each part of the lake and
for a tapped spot are blended from the forecast points around it (natural
neighbour), so values change smoothly across the lake and never go beyond
those points; hail and thunderstorms come from the nearest point. The website
blends the same way. Stacked layer buttons at the right switch between the light,
wind, waves and visibility (coloured by how foggy it is, shown when the
forecast has visibility for each point; wind, waves, visibility is the order
everywhere in the lake view), a slim colour strip above the panel opens the legend, a
button at the top puts Apple's satellite pictures under the lake (on the website a globe button
with MapTiler pictures, on its other maps too), and wind arrows get denser as you zoom in.
The arrows cover the whole map, on the satellite picture too: over land they
come from the weather map's wind, blended into the lake's arrows over the last
kilometre to the shore.
"Plan a route" checks a route on the lake against the
forecast for the time you start; a "Way back" choice picks one way (the
default), out and back or a loop. It shows
where and when it gets rough. The way out and the way back are drawn side
by side, and "Lake at the boat's time" adds a slider that shows the lake as
it will be where the boat is at each moment. Turning points are numbered
(overlapping ones hidden) and move with a plain
drag, sitting just above the finger with a magnifier and a dashed preview of
the route; tapping or pulling a stretch of the route adds a point there.
Points can be deleted, and a loop also closes when the route ends within 50 m
of the start. While planning, a compact panel holds the route's result, start
time, pace, the way back, undo and the saved routes, so the map keeps the
screen; when the panel opens or closes, or a route loads, the map fits the
route or lake above it. From 600 pt wide (iPad, iPhone on its side, Mac) the
panel is a card at the bottom left with the legend chip beside it and the lake
fitted next to it; upright iPhones keep the full-width panel. The website does
the same from 600 px. Where clubs share a launch point, the page's own club
stays on top. Routes are
saved on the phone. Every edit marks a saved route as changed, and undo goes
back step by step, to "saved" again; Save updates the open route and "Save as
new route" keeps it as it was (the website works the same way); "Manage routes" lists them with their length and whether
they are a loop, to rename, duplicate, delete or reorder. "Import a row" (in
the Routes menu) turns a row you already did into a
route: a rowing workout from Apple Health or a GPX, TCX or FIT file from
another app, with the real pace as the starting pace and the rowed track as
an optional line on the map. Health access is asked for only for this, and
everything stays on the phone (`ios/RowFrog/RowTrack.swift`).

**River and canal clubs.** River and canal clubs row on their own stretch
(256 sections cut out of OpenStreetMap, up to the next weir or lock), so the
lake view becomes a River or Canal view with pins at the stretch's ends, and
the satellite picture shows that stretch. In place of the ice tile a Current
tile shows the flow speed and the water level from the nearest PEGELONLINE
gauge, with a level chart and the pace upstream and downstream. "Plan a
route" counts its times with that current, faster downstream and slower
upstream, and warns where the boat would hardly make headway. Shipping
stopped turns the light red, high water amber (from the gauge's shipping
mark I where that comes first, otherwise mean high water); on rivers with
groynes an info line warns once the level is 1.5 m above mean water, when
groyne tips may be under water. The current turns it amber
from 1.5 m/s and red above 2.5 m/s, limits that can be set per boat like the
others (`backend/rowfrog/river.py`,
`ios/RowFrog/RiverCurrent.swift`).

**Rain radar.** The rain tile (titled "Precipitation"), the top tile's rain value and the rain detail
view read DWD's rain radar and 2-hour nowcast for the launch point, then the
forecast: "Light rain" now, with a line such as "Rain from 12:45" (forecast
rain starts at its hour and never before the radar's end, decision 0040; Open-Meteo sums the hour before
its time stamp, so the backend puts each hour's rain under the hour it fell, and the 13:00 row, the
48 hours, the charts and the widget all mean 13:00 to 14:00, decision 0043; a small
radar symbol marks the radar, no symbol the forecast; the symbol is struck through while the radar can't be
loaded; it is tried again soon and on pull to refresh) and small bars, thin for
the radar's quarter hours and paler for the forecast hours. Snow, hail,
drizzle and Schneeregen (rain and snow in the same hour, worked out on the Pi from
Open-Meteo's rain and snowfall near freezing, decision 0042) are named from the forecast. The detail chart starts with two hours of
radar bars, then a grey line labelled "Radar | Forecast" and paler forecast
bars, as in the tile (`docs/decisions/0045`), and its map shows the radar picture; a tap opens the radar map,
with DWD's colour legend and a switch to play the radar as a loop. Hours in the
48 hours less than two hours ahead use the radar too. The old rain radar card
can still be switched on in Arrange this page. The app reads the radar from DWD
directly (`ios/RowFrog/RainRadar.swift`).

**Weather maps.** From the detail views a map opens for wind (with arrows on
an even grid that adds arrows as you zoom in, longer in stronger wind),
gusts, air temperature, feels like, humidity, air pressure, visibility and the
rain forecast, made by the publishing job from DWD's ICON-D2 model (about 2 km)
for each hour of the forecast, with no Open-Meteo calls. Lightning in the last
hour and the UV index come live from DWD, fog and low cloud from the
EUMETSAT satellite (`ios/RowFrog/WeatherMap.swift`,
`backend/rowfrog/sources/icon_d2_maps.py`). In the detail view the map sits
under the chart (beside it in landscape) and follows the hour of the chart's
line; a chain button lets it keep its own time, and a tap opens it full
screen with a slim chart and a switch to play the hours as a loop. Maps open
about 50 km across around the club (rain and lightning 120 km) and load more
area as you zoom out.

**Battery.** The app keeps its battery use low: the radar only updates on the
page in front, readings and map pictures are reused, widgets redraw only when
something changed, and the launch point map is live only in its open sheet, or once its card is
tapped. A blurred background picture is blurred once, not on every frame, and
Add a place looks up the water only once the map stops moving. In Low Power
Mode the tiles, the page bar and the clock strip are drawn solid and the radar updates less often. The app does
nothing in the background; only the widgets load forecasts on their own.

**Refresh on return.** Coming back to the app after more than 10 minutes
loads the club page in front first, then every other saved club; a pull on a
club page does the same. The header names the weather model's run and when
the club's forecast was last updated ("Model run 06 UTC · updated 10:01",
`docs/decisions/0039`); the club list and the widgets show the same update
time, and when the run was ready and when the phone loaded it are in "How
often data is updated". The website shows the same header and sheet, and loads the club page again when you come back to
its tab after more than 10 minutes (it has no Refresh button).

**Data use.** Forecasts that have not changed are not downloaded again, and
the club list is kept on the phone for a day. Each club's last forecast is kept
too: after a fresh start, or without internet, it shows at once with
"Updating…", and stays with "Could not update: …" when the download fails
(the app gives up after 15 s without data, the website after 20 s; the
website does the same on its club pages and list, `docs/decisions/0044`).
A restart draws that last page, lake view and satellite picture included, in
its first frame; a first start shows grey stand-in cards with a sweeping light
until the forecast comes. The website draws its kept forecast before the page
and the same stand-in cards; its lake view and satellite picture still load
after it (`docs/decisions/0046`). With "Save mobile data" on
(while on mobile data) or in iOS Low Data Mode, satellite pictures load only
when tapped, the radar map steps in half hours and the radar (rain tile, top tile and
radar card) updates every 15 minutes.

**Ice cover.** Every forecast carries an ice estimate per lake for today and
the coming week (from May to October the ice tile is greyed out as "Off
season"): no ice, shore ice possible, ice forming, ice cover likely,
or drift ice on rivers. Likely ice turns the hourly light red; possible shore
or drift ice turns it amber. The estimate is a frost model over the last
three months of air temperature plus the forecast week
(`backend/rowfrog/ice.py`); a measured water temperature above 3 °C
overrides it. On larger lakes the Copernicus Lake Ice Extent satellite map
checks it, and the ice tile shows the latest pass, e.g. "Satellite, Today:
open water".

**Lowered lakes.** The Forggensee is let down in winter. While its level
(GKD gauge Roßhaupten) is below 779.8 m, a Water level tile takes the ice
tile's place, with the last week's levels in its detail view; the lake counts
as lowered (amber), and below 777.5 m as drained (red). The levels are set in
`data/lake-levels.json`. When the gauge cannot be read, the last good
level stands in for up to 24 hours. The tile draws the water in the shape of
the basin, with a dashed line for full and short marks for lowered and
drained. The website shows the tile too.

**Satellite pictures.** A card near the end of the page shows the latest
Sentinel-2 picture of the lake, with a line such as "Wednesday, 22 Oct ·
lake 25% cloudy" and an "i" that explains why a new picture
comes only every 2 to 5 days. A switch chooses between the latest pass
(clouds or not), the clearest one and, in cloudy weeks, a newer mostly clear
one; every picture shows the same area. When the latest pass has 90 % or
more cloud over the 2 × 2 km around the club, the card opens on the clearest
picture instead, with the latest one tap away; the website does the same. Chips draw the shore, clubs, saved
routes, wind and, in winter, the satellite ice map over it. Two more layers
colour the water with the lake view's wave heights or rowing light for the
chosen hour, one at a time; a legend explains them. While the whole lake is
red (official warning or darkness) or amber (the hour before sunset, warning), the
rowing light layer turns grey with red stripes, or shows amber stripes. Tap for full screen with
zoom, opening around the club or all saved routes; zoomed in, it loads
sharper 10 m tiles for that part of the lake. Pictures are kept on the
phone, so each pass loads only once.

**Forecast source.** A small line at the end of each club page names the
weather model the forecast comes from (today DWD's ICON models for every club,
`backend/rowfrog/weather_models.py`); tapping it explains the chain of
models from the first hours to the end of the forecast. When a model is
picked in the hidden developer options, the credits line names its provider
(MeteoSwiss, GeoSphere Austria or ECMWF) as well as DWD.

**Location.** The lake and town line under the club's name (and the
orange "Launch point not yet confirmed" line) opens the club's "Location"
sheet, sized to its content: a live map (Apple MapKit, no key needed) of the
launch point the forecast is for, which can be panned and zoomed, switched to
satellite pictures with the globe button, and made full screen by pulling the
sheet up or with the expand button; a note on which point the forecast is
for (the launch point, or the club's address while no launch point is set),
its name in Apple Maps (a tap opens Apple's place card) or the
not-confirmed note, its coordinates and "Open in
Maps". Settings › Club pages › Location in the club header (on by default)
can be turned off to bring back the Launch point map card on the page
instead, a still picture until tapped. On the website the place line opens
the Location sheet too, where "In OpenStreetMap as “…”" opens a small card
with the place's name, directions and its OpenStreetMap page.
For a club that has not confirmed its launch point, the sheet offers
"Suggest the launch point": move the map under the fixed oars and send. Only
the club and the point are sent; the suggestions service files it as a GitHub
issue, and the owner's `/accept` there adds it to the hand-checked points. The website
offers it too.
"Open in Maps" also offers directions to the club, in the map app chosen in
Settings: Apple Maps (the default; when it knows the club as a place, with
photos and opening hours, it opens that) or Google Maps, which opens in its
own app when installed.

**Maps** all mark clubs the same way: this page's club in blue, other clubs in
grey, with a house for the home base and a rower for any other club. Zoomed
out a club has one pin at its launch point (or its own point while none is
set). Zooming in moves the club's pin onto the club's place in Apple Maps, so
it covers Apple's own label and the club shows once; only when the clubhouse
checked by hand is more than 80 m from that place does the pin go there
instead. Where the launch point is set, crossed oars then mark it. The website
does the same with the club's place in OpenStreetMap.

**When an update fails,** the page keeps the last forecast and says why under
the club's name (no internet, server could not be reached, server refused
the download, no forecast for this club yet); when the forecast is also out of
date, both lines show. A tap explains whose side it is on and offers "Try
again". The website does the same.

**Home Screen menu.** Touching and holding the Row Frog icon offers the home
base, its lake view, its rain radar and the club opened last besides it
(`docs/decisions/0048`). The menu shows no weather, since iOS keeps it until
the app runs again. The website offers the same four as shortcuts of the
installed site in Chrome and Edge.

**Widgets.** Home-screen and lock-screen widgets show the rowing light first,
then the values in the top tile's order, each with its symbol. Each home-screen
widget picks its **Layout** (long-press › Edit Widget): **Fewer values** (the
default: the small one shows the light as a ring with short words, medium and
large add temperature, wind, waves and visibility), **All values beside the
light** (all six values in two columns) or, on the large one, **All values in a
row** under the full sentence. Under each hour the large and extra large
widgets show wind, waves and visibility with a small legend (only temperature
and wind where even a tighter layout doesn't fit, e.g. at very large text);
the medium one shows just the time, sky and light per hour. At night, as in
the 48-hour table, the dark hours after "Now" fold into one moon column up to
sunrise (a dimmed red dot on an indigo band, as in the app; in the large ones
with the night's worst values), then the morning hours follow. The day bars
share one clock axis with small hour labels; today's gone hours stay faint and
a tick marks now (`docs/decisions/0041`). **Marks** (on by default) put a check, ! or ×
in the light's dots and stripes or outlines on amber and red day bars, so the
light reads without colour. Values that set the light are coloured; the rain
value uses the rain radar for the next 2 hours ("From 11:20", "Until 11:40"),
and a thunderstorm within 6 hours takes its place. When the forecast is out of
date, every hour dot and day bar turns grey. The round lock-screen widget is
a daylight ring. Behind the values goes a sky in the weather's colours (the
default), the rowing light's colour, the club's app picture or another
picture, the satellite picture of the lake (the whole Sentinel picture, with
the club as near the middle as its edges allow), or plain white or black. Widgets
are app-only; the website has none.

**Settings** (cog in the bottom bar of the club pages and beside the search
of the location list on iPhone, at the top left of the club page on iPad)
works like the iOS Settings app: a "Rowing light for" boat picker at the top,
then one page per topic, each row showing its current value, and a search
field at the bottom.

- Boats and limits: the boat groups and My boats (tap a boat to use it for
  the rowing light, ⓘ for its type, limits and the clubs it is kept at; swipe
  to remove a boat or a club), and the fine-tuned limits (see
  [Rowing limits](#what-the-app-does)).
- Routes: every saved route, grouped by water, with the tools of Manage
  routes (rename, duplicate, delete, order within a water); a tap opens the
  route on its lake map. The website has the same page. "Share link" (in a
  route's menu) and the share button at the top (every route) make a
  rowfrog.com link; opened in a browser, it saves the routes there, once,
  and opens a single route on its lake map. The link carries name, water,
  way back and turning points, not a rowed track. "Export GPX" (in a
  route's menu, and in the lake map's Routes menu for the open route) saves
  the route as a GPX track for CrewNerd, Garmin or Strava, with the way back
  when rowed out and back; the website downloads the same file. "Standard
  pace /500 m" (2:30 unless changed) is the pace a new route starts with.
- Appearance: background pictures for all pages, single pages or single
  clubs (clear or blurred, frosted or solid tiles, your own photo or the
  satellite picture of the club's lake) and the app icon: the coxed double
  "rowing light" icon in light, dark and tinted, plus 10 alternates. Light
  or dark and turning the screen follow the iPhone, as Apple's guidelines
  ask. On club pages the picture fills the screen
  behind the status and page bars and fades between clubs while swiping.
  The top bar is clear at rest and shows a blur with the club's name once
  the page scrolls; the page bar floats as three Liquid Glass groups, with
  the current club's dot larger, and the lake map buttons look the same.
- Club pages: Current conditions in the top tile, the order of the cards for
  all clubs, Location in the club header, and a Maps section: how much area
  the weather maps open with ("Maps start": Close, Normal or Wide) and the
  map app for directions (Apple Maps or Google Maps).
- Widgets: a live preview of the widgets with the forecast, one size per
  page (swipe, with dots), the background for all widgets or per club (each
  widget can also pick its own when you edit it), and how often they update: every 30 minutes
  (default), every hour, every 2 hours, or only after using the app. Less
  often saves battery and data, but a new official warning reaches the widgets
  later.
- Language and units: the language (English or German) is set in the
  iPhone's Settings for Row Frog, and time and date follow the iPhone
  (including its 12/24-hour setting); units: wind in m/s, km/h, knots, mph or
  Beaufort; °C or °F; waves in m, cm or ft, and more.
- Battery and data: "Save mobile data" (see [Data use](#what-the-app-does))
  and the widget updates.
- Help: the safety notice, replay the tour, the full legend of symbols, and
  bring the one-time tips back. Tips point out features the first time they
  appear (a river or canal club added after the tour gets a one-time tip on
  its Current tile): one at a time, at most one new tip a day and none on the
  day of the tour, each with "Got it" and "No more tips"; a card's tip sits
  under its title, a control's tip in a bubble on it (`docs/decisions/0035`,
  app and website). After an update a "What's new" sheet shows once.
- About: the version with build number and commit ("0.1.0 (723) · 22a69ce",
  stamped by `scripts/build_number.sh`; the website's footer shows the same build),
  a privacy summary, the legal notice
  (Impressum, still with placeholders) and Reset (keeps saved locations, the
  home base and My boats; resets everything else, including the limits).
- Developer: hidden options for testing (see the handbook), including the
  app's own Light/Dark, Landscape, language and time and date formats.

The website's Settings have the same pages and follow the browser for looks,
language and time formats in the same way.

On a club page, the "For *boat*" line under the rowing light says which boat
the light is for. The boat button (in the bottom bar on iPhone; on iPad level
with the club's name, staying in the top bar once the page scrolls) opens the
boat picker; the same button sits at the top of the lake map and route
planning, and beside the legend in the satellite picture's full view while
Rowing light, Waves or Shore is on (the website does the same). It shows the chosen boat's class
(own boats in blue) or the group ("1–2", "4–8"). The picker shows the light
each boat kept there would get now, and your boats from other clubs under "At
other clubs", where a tap keeps the boat at this club too. The chosen boat applies to everything on screen: the
lake tile, the lake map, route planning and the satellite picture use its
limits too.

**Wide screens.** Phones on their side and the unfolded iPhone Duo get wide
layouts (two columns from 600 pt, a side list from 860 × 560 pt). In two
columns both end level: the 48 hours show whole (each night folded into one
line), the forecast source, Arrange this page and the credits go into the shorter
column, and the lake view and launch point maps there grow (at most one
screen tall each). From 1,200 pt of room a third column opens (no iPad gets
there; a Mac or a wide browser window does). The window sets the count, as if
the side list were shown, so sliding the list away or back never moves a card
to another column (`docs/decisions/0023`). The website does the same.

**iPad.** The app runs natively on iPad in all four orientations, with the
same wide layouts (side list 400 pt wide). The Landscape setting is hidden
there, since iPadOS turns apps anyway. A value's detail view opens full
screen, with the map beside the chart when the iPad is on its side. With a
background picture on a sideways iPad, one club picture fills the screen
behind the side list and the page; a satellite picture is centred on the
club's launch point. The list, cog and boat buttons at the top sit over the
column of cards, not at the window edges. The website's wide layout does the
same.

**Website.** [rowfrog.com/app](https://rowfrog.com/app) shows the forecasts
in a browser, for Android phones and computers. It is password-locked while
in testing, through its own login page that keeps the browser signed in for
90 days (Log out in Settings › About › Website login). It follows the app's list, club page and look, with a wide layout
for iPads and desktop browsers, and has nearly everything the app has: own
boats and limits, the lake view with route planning and row import (GPX, TCX
or FIT), value pages with chart and weather map, the satellite picture with its
layers, browsing by country and adding a place, Arrange this page, units,
appearance, background pictures, the tour (on a first visit with the
home base and more clubs to pick, as in the app) and the tips, the River and Canal view with the Current tile, and the rain radar in
the rain tile (the radar card is off by default, as in the app). What a visitor picks stays in their browser. On iPhone and iPad its text
follows the device's text size, as the app does. Added to the Home Screen, it opens straight on the forecasts, without the welcome page.

## Layout

| Path | What it is |
| --- | --- |
| `ios/` | SwiftUI iPhone and iPad app and widget. The Xcode project is generated from `project.yml` with XcodeGen. |
| `backend/` | Python (FastAPI) service that fetches the forecast, computes waves, the lake view and the traffic light, and serves the app. |
| `data/locations.json` | Lakes and clubs with confirmed launch points. Add a club or lake here; no code change is needed. |
| `data/catalogs/` | Clubs the app's search offers, one file per country and source (see [Club catalog](#club-catalog)). |
| `data/geocode.json` | Cached geocoding results for the catalog imports. |
| `data/outlines/` | Lake outlines (GeoJSON) for the wave calculation and lake view, made with `scripts/fetch_lake_outline.py`. |
| `data/water-stations.json` | The water temperature station each club reads (nearest on its own water). |
| `data/lake-depths.json` | Mean lake depths for the ice estimate. |
| `web/` | The website: start page, `app/` (the forecasts in the browser), legal pages and the password check (`functions/_middleware.js`). `scripts/build_web.py` builds it. |
| `cloudflare/` | Cloudflare Workers: `usage/` counts loads on `api.rowfrog.com` and serves the `/v1/` files from R2 while the Pi publishes, `suggestions/` turns place and launch point suggestions into GitHub issues, `timer/` starts the forecast run on time. |
| `testdata/api/v1/` | Sample API files (MRC 1880's forecast, the lake list and the country lists) that the backend, app and website tests all read, so a change to the format shows up in all three (see the handbook's Tests section). |
| `testdata/limits.json` | The app's starting boat limits that the backend, app and website tests all check, so the three give the same light. |
| `testdata/reasons.json` | Every reason the backend may send for an amber or red light; the backend test checks its modules and the sample files against it, and the app and website tests check each has a label and sentence (an unknown one shows "Other condition"). |
| `testdata/rules/` | Shared rule tables (lake view colours, route rules, the cold-water badge and shore) with expected values from a separate implementation, which the app and website tests both check. |
| `testdata/schema/v1/` | One JSON Schema per published `/v1` file; `frozen.json` lists the fields installed apps rely on, and a test fails when one goes or changes type. |
| `testdata/states/` | Cases that run each statechart (now the route editor, `ios/RowFrog/Charts/`) through the Swift and JavaScript readers alike. |
| `testdata/units.json` | The unit table (values shown in each unit, Beaufort forces at the limits, decimals) that the app and website tests both check. |
| `docs/handbook.md` | The handbook: hidden features, how to test them, launch arguments, workflows and secrets. |
| `docs/decisions/` | One short record per owner decision (date, decision, why, what was turned down, where in the code), with an index that says how to add one. |
| `docs/screenshots/` | Not in git: the "App screenshots" workflow writes here on the runner and attaches each set to its run as the "screenshots" download and to the branch `screenshots/<branch>` without history (see the handbook). |
| `scripts/` | Catalog imports, lake outlines, publishing, checks and background drawing. Finished research probes and their workflows are parked in `scripts/probes/`, with a note of where each result went. |
| `CREDITS.md` | Data sources, licences and the credits the app must show. |

## Club catalog

The app's search offers clubs in Germany, Austria and Switzerland, about 670
in all, from one file per country and source in `data/catalogs/`
(`<country>-<source>.json`):

| File | Clubs | Source | Made by |
| --- | --- | --- | --- |
| `de-drv` | 469 | German Rowing Association (DRV) club search, rudern.de | `scripts/import_drv.py`, **DRV club catalog** workflow (about 45 minutes) |
| `de-osm` | 3 | OpenStreetMap around the Bavarian lakes | `scripts/discover_clubs.py`, **Club catalog** workflow |
| `at-oerv` | 44 | Austrian Rowing Federation (ÖRV) club list, rudern.at | `scripts/import_oerv.py` |
| `at-osm` | 33 | OpenStreetMap, clubs the ÖRV list does not have | `scripts/import_osm_clubs.py` |
| `ch-swissrowing` | 76 | Swiss Rowing's club directory | `scripts/import_swissrowing.py`, only when started by hand with "Import Swiss Rowing" ticked |
| `ch-osm` | 45 | OpenStreetMap | `scripts/import_osm_clubs.py` |

The last four run in the **Austria and Switzerland club catalogs** workflow.
Each boathouse is geocoded (cached in `data/geocode.json`) and matched to the
lake or river it lies on; clubs on rivers get no wave calculation. Clubs
that row at more than one place get an extra entry per site from
`data/catalogs/extra-sites.json` (e.g. Pro Sport Berlin 24 (Gatow)), which
the imports keep on every run. Only club
facts are stored, no contact people, e-mail addresses or phone numbers. The
federations are credited in `CREDITS.md`, which also notes where permission
is still to be asked.

Addresses and launch points the owner checked on the satellite view (or
accepted from a suggestion) are kept
in `data/catalogs/hand-checked.json` (with `remove` for entries that are no
rowing clubs); the imports and Fix unknown waters apply it on every run.
`scripts/snap_launch_points.py` moves catalog launch points that lie up to
150 m outside their water onto its shore, leaving hand-checked points alone,
and a data test wants every launch point within 25 m of its lake outline.

Launch points from the catalogs are unconfirmed until a club is moved into
`data/locations.json`. When loading, `locations.json` always wins, then the
catalogs in the order above (a federation's list before OpenStreetMap); a
catalog club with the same id as an earlier club, or within 300 m of a club
from an earlier file, is left out as the same club. The app loads the clubs of
one country at a time.

## Run the backend

```sh
cd backend
pip install -e ".[dev]"
pytest
uvicorn rowfrog.api:app --reload
```

Then open http://localhost:8000/lakes,
http://localhost:8000/clubs/mrc-1880/forecast or
http://localhost:8000/lakes/starnberger-see/view.

Waves are only computed for lakes that have an outline. To add one:

```sh
python3 scripts/fetch_lake_outline.py starnberger-see "Starnberger See"
```

The **Missing lake outlines** workflow fetches every catalog lake that still
has none.

## Hosting

While GitHub is down (November 2026), a Raspberry Pi runs the forecasts, the
Model check and the Usage limits check from its own copy of `main`, and puts
each club's forecast online on Cloudflare R2 as soon as that club is built,
the clubs people use first. Since 14 Nov 2026 changes are merged on GitHub
again and the Pi's `main` follows GitHub's; the Pi's job files are in
`scripts/local/pi/`. The usage counter Worker serves the `/v1/` files from
that R2 bucket. The Mac deploys the website. The handbook section "While GitHub is down" has the
steps and the checks. The rest of this section describes the GitHub setup.

There is no server yet. The "Publish forecasts" workflow runs the backend on
GitHub and publishes its answers as files on GitHub Pages, at
https://api.rowfrog.com/v1/ (same paths as the API: `lakes/index`,
`clubs/<id>/forecast`, `lakes/<id>/view`, and the satellite pictures).
Every 30 minutes it refreshes the clubs people actually load (until the
usage counter is set up, the confirmed clubs in `data/locations.json` stand
in); every 6 hours, on the full hour at 04, 10, 16 and 22 UTC, it refreshes all clubs. A club nobody opened lately is
refreshed less often and its page says so; once opened, it is back to every
half hour from the next run. A Cloudflare Worker (`cloudflare/timer/`) starts
the run at :00 and :30; GitHub's own half-hour timer is only a backup, with its own queue so it
can't cancel a waiting run. DWD's local warnings for all clubs come in a couple of
bulk queries per run. Weather is only loaded again after
a weather model has a new run, which keeps the job within Open-Meteo's free
limit; for ICON-D2 each run first asks Open-Meteo's free `meta.json` whether
the new run has arrived, and the arrival times are kept at
`v1/status/model-runs` (last two weeks). A club forecast or lake view whose
content did not change keeps its published file (only its time stamp would
differ), so the app's next load gets a 304 and downloads nothing. When a station's water temperature fails to load, the last good reading
stands in for up to 6 hours. For clubs people use it also loads the 8-day outlook after each model
run (every 3 hours) for the charts in the condition details. The last
forecasts are kept between runs in the Actions cache.

Only `main` publishes to the live site. A branch can be published by running
the workflow by hand, which overwrites the live files until `main` publishes
again.

Release builds of the app read from there; Debug builds use a backend on the
Mac at localhost, except for the satellite pictures, which only the publishing
job makes and every build loads from `api.rowfrog.com`. To move to a server of our own, run
`uvicorn rowfrog.api:app` there and point the DNS record of
`api.rowfrog.com` at it; the app keeps its address.

## Run the app

On a Mac with Xcode 15 or later, install XcodeGen (`sudo port install
xcodegen` with MacPorts, or `brew install xcodegen`), then:

```sh
cd ios && xcodegen && open RowFrog.xcodeproj
```

Run the backend first; the simulator reaches it at `http://localhost:8000`
(set in `project.yml` as `RWAPIBaseURL`; the launch argument `-RWAPIBaseURL`
points a Debug build at another address, such as the published forecasts).

A checkout from before the October 2026 rename needs `xcodegen` run again
(the old `RowerWeather.xcodeproj` can be deleted) and the backend installed
again with `pip install -e ".[dev]"`, since the package is now `rowfrog`.

## Workflows

More detail, including the secrets each one needs, is in the
[handbook](docs/handbook.md).

| Workflow | What it does |
| --- | --- |
| **CI** (`ci.yml`) | Backend tests and the ruff lint, the Cloudflare Worker tests (`cloudflare/tests/`) the translation check and the website check (`scripts/check_web_parity.py`: every app text is on the website or listed as app-only in `web/app-only-texts.txt`) on every push to `main` and every pull request; the iOS build, unit tests and UI tests (taps through the first start, the settings and club list, and a conditions tile over frosted cards, against the published forecasts, and Apple's accessibility audit of the club page) run on pull requests that change `ios/`, in three jobs side by side. The one on the newest released Xcode (picked automatically from GitHub's runner images by `scripts/newest_xcode_runner.py`, 27.1 in October 2026) decides a merge; Xcode 26 and iOS 18 (Xcode 16.4) run for information only. When a new Xcode major version takes over, a reminder issue opens. Each run's summary page shows the test coverage. |
| **App size** (`app-size.yml`) | Builds the app as for the App Store (Release archive with the newest released Xcode, unsigned) and reports the installed size, the expected download and the largest files in the run summary (10.4 MB installed, about 10 MB to download in October 2026). Runs when iOS code lands on `main`, or by hand. |
| **App screenshots** (`screenshots.yml`) | Runs the backend with live data (Open-Meteo's answers recorded on a Linux runner and played back on the Mac, which can't reach it since 16 Nov 2026), starts the app in the iOS Simulator and attaches the screenshots to the run as its "screenshots" download, kept 14 days and never in a branch's history; each run also replaces the branch `screenshots/<branch>` with one commit of only that set and no history, so cloud threads can read the shots with git, and deletes the sets of branches that are gone (owner, 15 Nov 2026); each run starts from the newest download of the same branch, else main's. Long pages are shot screen by screen (`-p1`, `-p2`, …). Tutzinger RV gets a made-up lake storm warning, Seeclub Zürich and RV Albatros Klagenfurt a made-up thunderstorm warning, and the lake view a made-up south wind, all marked as samples in the app. Runs only by hand from the Actions tab, since it holds a Mac runner for a long time: once per pull request when it is ready for review, for the screens that changed (the `only` input), and a full set only when asked. It uses the same newest released Xcode as CI; the inputs `runner` and `xcode` pick another (e.g. `macos-26-intel` for Xcode 26), and `device` = `iPad`, `iPhone 13 mini` or `iPhone SE` shoots on that Simulator instead, into its own folder of the same set (`ipad/`, `iphone-13-mini/`, `iphone-se/`; the two small iPhones are the smallest screens the app supports). |
| **Publish forecasts** (`publish-backend.yml`) | Publishes the backend's answers to GitHub Pages, see [Hosting](#hosting). Installs the exact package versions in `backend/requirements-publish.txt`. Needs the secrets `CDSE_CLIENT_ID` and `CDSE_CLIENT_SECRET` for satellite pictures and ice. |
| **Satellite ice check** (`satellite-ice.yml`) | Tries the Copernicus ice maps and Sentinel-2 pictures for our lakes with the same secrets. Runs by hand or when its scripts change. |
| **Model check** (`model-check.yml`) | Twice a day stores every candidate weather model's forecast for the test points in `data/model-check/points.json` on the `model-check` branch and compares them with DWD station measurements. On Mondays the report is posted on the "Model check" issue, with a section on whether one run a day would be enough, "App vs measured" (how far the forecasts the app actually showed, lake squares included, were off; on the Pi, where the published files are at hand) and "On the lake vs on land" (wind and air temperature from the GKD buoy on the Ammersee, plus GKD lake water temperatures, logged from the first run on). Changes to its scripts start it only on `main`. |
| **Interpolation check** (`interpolation-check.yml`) | Compares how the lake view blends between forecast points (natural neighbour, `backend/rowfrog/interpolate.py` and `LakeInterpolation.swift`) with other methods, on made-up fields and the latest ICON-D2 run, and lists bias, errors and values outside the points' range in the run summary. Nothing is stored. By hand: every Monday (started by the recurring tasks) and after changing the blending code. |
| **Usage counter** (`usage-worker.yml`) | Deploys the Cloudflare Worker in `cloudflare/usage/` that counts club and lake loads on `api.rowfrog.com` (no IP addresses) and keeps the jobs' call totals. It also tags each `/v1/` file by its content, so a file that did not change answers 304 and is not downloaded again. Needs `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` and `USAGE_KEY`. |
| **Usage limits** (`budget-check.yml`) | Once a day compares the calls with Open-Meteo's and Copernicus' free limits and Cloudflare's free Worker and database limits and comments on the "Usage limits" issue at 70 % (warning) and 85 % (alert), plus a monthly summary. |
| **Austria and Switzerland club catalogs** (`alpine-catalogs.yml`) | Rebuilds the `at-*` and `ch-*` catalogs (Swiss Rowing only when ticked by hand). By hand, or when its scripts change on `main`. |
| **Merge Dependabot updates** (`dependabot-merge.yml`) | Dependabot (`.github/dependabot.yml`) opens one PR a month raising the pinned backend packages, and a PR for each security fix straight away. Once CI passes on such a PR that changes only those versions, this workflow merges it; any other PR, or one whose CI fails, stays open for a person. Monthly grouped PRs for the npm tools (`package.json`: Wrangler, Playwright) and the GitHub Actions versions also come, and always wait for a person. |
| **Forecast timer** (`timer-worker.yml`) | Deploys the Cloudflare Worker in `cloudflare/timer/` that starts Publish forecasts at :00 and :30. By hand with `deploy` ticked, and by itself when `cloudflare/timer/` changes on `main`. Needs `PUBLISH_TIMER_TOKEN`, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. |
| **Place suggestions** (`suggestions-worker.yml`) | Deploys the Cloudflare Worker that turns place and launch point suggestions into GitHub issues. Needs `SUGGESTIONS_GITHUB_TOKEN`, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. |
| **Accept launch point** (`accept-launch-point.yml`) | When the owner answers `/accept` (or `/accept lat, lon` for a nudged point) on an issue labelled "launch point suggestion", writes the point into `data/catalogs/hand-checked.json` and the club's catalog (`scripts/accept_launch_point.py`) and opens a pull request; once merged, the next forecast run brings it to the app. |
| **API check** (`api-check.yml`) | Shows how `api.rowfrog.com` answers (Cloudflare proxy, SSL mode, usage counter). Runs by hand. |
| **Live data check** (`live-check.yml`) | Downloads missing lake outlines from OpenStreetMap, checks club launch points against them and runs the forecast against live Open-Meteo and GKD data. Runs by hand, or when the club list or data sources change on `main`; new outlines are committed back. |
| **Water temperature stations** (`water-stations.yml`) | Lists the GKD Bayern, PEGELONLINE and Swiss BAFU stations, shows how `data/water-stations.json` would change and reads every station in it once. Nothing is stored; a changed list is committed by hand (see the handbook). By hand, or when its files change. |
| **Satellite water temperature check** (`water-temperature-probe.yml`) | Compares Copernicus, Landsat and the carried-forward estimate with GKD lake stations. By hand, or when the satellite water temperature code changes. |
| **Weather maps data check** (`weather-maps-probe.yml`) | Research only: what DWD (ICON-D2, GeoServer) and EUMETSAT offer for the weather maps. Nothing is stored. By hand, or when its script changes. |
| **River sections** (`river-sections.yml`) | Cuts each river and canal club's stretch out of OpenStreetMap (Geofabrik extracts of Germany, Austria and Switzerland) and commits `data/river-sections.json` and the section outlines. By hand, after river clubs or `data/river-section-overrides.json` change; takes about 40 minutes. |
| **River gauges** (`river-gauges.yml`) | Finds the PEGELONLINE gauge on each German river club's river (within 15 km) and commits `data/river-gauges.json` for the Current tile. By hand, after river clubs change. |
| **JPEG quality probe** (`jpeg-quality.yml`) | Research only: compares JPEG qualities for the satellite pictures (today 90) against lossless originals from Copernicus and keeps the originals on `refs/probe/jpeg-quality`. By hand, or when its script changes. |
| **Lake lights check** (`lake-lights-check.yml`) | Lists DWD's lake warning areas with their clubs and fails when one is missing from `data/shore-lights.json` or no longer at DWD. By hand each season, or when its script or that file changes. |
| **Austrian and Swiss warnings check** (`alpine-warnings-probe.yml`) | Research only: asks GeoSphere Austria, MeteoSwiss, MeteoAlarm and DWD what they publish for a few Austrian and Swiss clubs. Nothing is stored. By hand, or when its script changes. |
| **DRV club catalog** (`drv-catalog.yml`) | Rebuilds `data/catalogs/de-drv.json`. By hand, or when its script changes on `main`. |
| **Club catalog** (`club-catalog.yml`) | Rebuilds `data/catalogs/de-osm.json` from OpenStreetMap. By hand, or when its script changes on `main`. |
| **OSM club places** (`osm-club-places.yml`) | Finds each club's own place in OpenStreetMap (`scripts/osm_club_places.py`, into `data/catalogs/osm-places.json`), where the website's club pin moves once zoomed in. On the 12th of each month, by hand, and when its script changes. |
| **Missing lake outlines** (`missing-outlines.yml`) | Fetches the OpenStreetMap outline of every catalog lake that has none yet (`scripts/fetch_missing_outlines.py`, in 10 parallel parts) and commits the new `data/outlines` files; existing outlines are never changed. Lines marked "CHECK BY HAND" in its report were picked without a matching name. By hand, on `main`. |
| **Fix unknown waters** (`fix-unknown-waters.yml`) | Puts clubs the imports left under "Water near *town*" on the water checked by hand for them (`data/catalogs/water-fixes.json`) and moves their launch points to that water's shore. Runs when that file changes on `main`. |
| **Website** (`website.yml`) | Builds and deploys the website to Cloudflare Pages (project `rowfrog-web`) and checks that it refuses visitors without the password. Before deploying, a browser test opens the built site in Chromium, offline, with the sample API files and fails on any JavaScript error (safety notice, club page, every tile's value page, the list); `web/tests/browser/looks.test.mjs` also opens pages with a background picture and with the keyboard open. Runs when `web/`, the sample data in `testdata/`, `scripts/build_web.py`, the app icon (for the favicon and home-screen icons) or the app's German texts change on `main`; tests only on pull requests. Needs `SITE_USER`, `SITE_PASSWORD`, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`; the optional `MAPTILER_KEY` turns on the satellite pictures. |

## Traffic light defaults

For small racing boats (1x, 2x, 2-), the app's starting boat; see
`backend/rowfrog/score.py`. Other boats and limits the user changed are
worked out on the phone (`ios/RowFrog/Limits.swift`).

| Condition | Amber from | Red above |
| --- | --- | --- |
| Mean wind | 5.5 m/s (Bft 4) | 8 m/s (Bft 5) |
| Gusts | 8 m/s | 10.3 m/s (20 kn) |
| Wave height | 0.15 m | 0.25 m |
| Visibility | 1 km or less | under 500 m |
| Rain and hail | heavy rain, 4 mm per hour or more | hail |
| Water temperature | no change to the light under 15 °C (a blue life-jacket badge instead); under 10 °C wind and gust limits 1 m/s lower; under 4 °C amber for small boats (never red on its own) | – |
| Shore warning lights (DWD lake warning) | strong wind (40 flashes a minute) for all other boats | strong wind for small racing boats and training boats; storm (90 flashes a minute) for all |
| DWD weather warning for the place (frost, ice, thaw, heat and cold only inform) | minor (yellow) | moderate (orange) or above, or any thunderstorm |
| Ice | shore ice possible, or drift ice on a river | ice cover likely |
| Daylight | the last hour before sunset (decided to the minute; "now" counts down to sunset) | sun down, so the sunrise and sunset hours count as red; an hour in which the light changes shows a half-and-half dot |

## In progress

Not on `main` yet:

- Weather models chosen per region from the model check results, and a
  model choice in Settings for everyone. A test version of the picker is
  hidden behind the developer options (see the handbook).

Not built yet: webcams.

## Licence

Proprietary, all rights reserved. See `LICENSE`.
