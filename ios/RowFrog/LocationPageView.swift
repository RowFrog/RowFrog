import SwiftUI
import TipKit

/// One full-screen location page: the rowing light now (with wind and
/// daylight), DWD warnings while one is issued, then the cards in the order
/// the user arranged (current conditions, lake view, the next 48 hours, launch
/// point, satellite picture, and the rain radar card when switched on), the
/// forecast source and credits.
struct LocationPageView: View {
    let club: Club
    let lake: Lake?
    let isHome: Bool
    let forecasts: ForecastStore
    @Environment(\.isCurrentPage) private var isCurrentPage
    /// All saved clubs, so a pull here refreshes the others too, after this one.
    var savedIDs: [String] = []
    @Environment(\.surface) private var surface
    @AppStorage(Tutorial.seenKey) private var tourSeen = false
    @State private var showHourlyTip = false
    @State private var showLaunchPointTip = false
    @State private var showConditionsTip = false
    @State private var showLakeViewTip = false
    @State private var arranging = UserDefaults.standard.bool(forKey: DefaultsKey.arrange)
    /// Where the hourly table and its day headers are on screen, for the header that stays at the top.
    /// Screen coordinates: in landscape the scroll view's own space leaves out the side inset,
    /// which put the header beside the table.
    /// Where the hourly table is while the page scrolls. Kept in its own object
    /// that only the sticky header reads, so scrolling redraws the header and
    /// not the whole page on every frame (which drained the battery).
    @State private var sticky = StickyHourly()
    /// The column count shown; worked out again once a resize rests (ClubPageColumns).
    @State private var columnCount: Int?
    /// Where the cards are in the scroll view, to keep the top one in place when the count changes.
    @State private var cardSpots = CardSpots()
    /// The page's width as if the side list were shown (nil: there is no side list).
    @Environment(\.widthBesideList) private var widthBesideList
    /// The 48 hours opened past the first 24 (only folded in two columns).
    @State private var hourlyOpen = false
    /// The 48 hours' height while folded, which the columns keep counting with when opened.
    @State private var foldedHourlyHeight: CGFloat?
    @State private var showRainRadarTip = false
    @State private var showSatelliteTip = false
    /// Heights of the map cards when last shown, kept for their stand-ins.
    @State private var mapHeights: [PageCard: CGFloat] = [:]

    /// "Forecast from 14:51 · loaded 15:39", or only the forecast's time when both
    /// are the same minute or nothing loaded yet. No "pull down to refresh": as in
    /// Apple's apps, the gesture goes without saying.
    static func updatedLine(forecast: Date, loaded: Date?) -> String {
        guard let loaded, Format.time(loaded) != Format.time(forecast) else {
            return tr("Forecast from %@", Format.time(forecast))
        }
        return tr("Forecast from %@ · loaded %@", Format.time(forecast), Format.time(loaded))
    }

    /// Whose satellite picture the page shows: the lake's or river section's, or for water
    /// without an outline (own places, rivers without a section) the 4 x 3 km around the club ("club-<id>").
    private func satelliteID(_ forecast: ClubForecast) -> String {
        lake?.hasOutline == false ? "club-\(club.id)" : forecast.lakeId
    }

    /// Pull to refresh also looks for new satellite passes; only their pictures download.
    private func refreshSatellite() async {
        guard let forecast = forecasts.forecasts[club.id] else { return }
        await SatellitePictureStore.shared.refresh(satelliteID(forecast))
    }

    /// Pull to refresh and coming back to the app also renew the lake view;
    /// an unchanged file costs only a short answer.
    private func refreshLakeView() async {
        guard lake?.hasOutline != false, let forecast = forecasts.forecasts[club.id] else { return }
        await LakeViewStore.shared.load(forecast.lakeId, force: true)
    }
    @State private var showSourceTip = false
    @State private var showRadarMapTip = false
    @State private var showHourViewTip = false
    private let radarMapTip = RadarMapTip()
    private let hourViewTip = HourViewTip()
    private let conditionsTip = ConditionsExtrasTip()
    private let lakeViewTip = LakeViewTip()
    private let rainRadarTip = RainRadarTip()
    private let satelliteTip = SatellitePictureTip()
    private let sourceTip = ForecastSourceTip()
    private let hourlyTip = HourlyTip()
    private let launchPointTip = LaunchPointTip()
    private let topTileTip = TopTileTip()
    private let allValuesTip = AllValuesTip()
    private let nearbyWaterTip = NearbyWaterTip()
    @State private var showNearbyWaterTip = false
    @State private var showAllValuesTip = false
    private let waterEstimateTip = WaterEstimateTip()
    private let waterLevelTip = WaterLevelTip()
    private let riverTip = RiverCurrentTip()
    @State private var showRiverTip = false
    @State private var showWaterLevelTip = false
    @State private var showWaterEstimateTip = false
    @State private var showTopTileTip = false
    @Environment(\.pageMargins) private var pageMargins

    /// The Why line counts the water within 1 km (#395); `-RWNearbyTip YES` shows its tip anyway.
    private static func hasNearbyReason(_ hour: ForecastHour) -> Bool {
        hour.reasons.contains { $0.condition == "nearby_water" } || UserDefaults.standard.bool(forKey: DefaultsKey.nearbyTip)
    }

    var body: some View {
        let forecast = forecasts.forecasts[club.id]
        GeometryReader { geometry in
            // Wide screens (an iPad, an iPhone on its side) put the cards below the
            // rowing light in two or three columns; phones upright keep one. The count
            // follows the width as if the side list were shown, so sliding it away only
            // widens the columns (owner's rule B, as on the website).
            let countWidth = widthBesideList ?? geometry.size.width
            let columns = columnCount ?? ClubPageColumns.count(width: countWidth)
            let twoColumns = columns > 1
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ClubPageHeader(club: club, lake: lake, isHome: isHome, forecasts: forecasts)
                            // Cards under the clock: the top blurs, as iOS's own bars do.
                            .onGeometryChange(for: Bool.self) { [top = pageMargins.top] proxy in
                                top > 0 && proxy.frame(in: .global).minY < top - 1
                            } action: { PageScroll.shared.update(club.id, scrolled: $0) }
                        if let forecast, let now = forecast.current() {
                            NowCard(hour: now, forecast: forecast, stale: forecast.isStale(), lakeName: lake?.title, town: club.town, club: club)
                                .id(AppSettings.shared.combinedTopTile ? "conditions" : "top")
                            if tourSeen && showNearbyWaterTip && Self.hasNearbyReason(now) {
                                TintedTipView(nearbyWaterTip)
                            } else if tourSeen && showTopTileTip {
                                TintedTipView(topTileTip)
                            } else if AppSettings.shared.combinedTopTile && tourSeen && showAllValuesTip {
                                TintedTipView(allValuesTip)
                            } else if AppSettings.shared.combinedTopTile {
                                // Current conditions is in the top tile: its tips follow it.
                                conditionsTips(forecast)
                            }
                            if let warnings = forecast.warnings, !warnings.checked || !warnings.localChecked || !warnings.items.isEmpty {
                                WarningsCard(warnings: warnings, lakeName: lake?.title, town: club.town, checkedAt: forecast.generatedAt)
                                    .id("warnings")
                            }
                            let cards = AppSettings.shared.pageCards(for: club.id)
                            Group {
                                if twoColumns {
                                    // The page's end goes into the shorter column too, and the maps
                                    // there grow, so both columns end level (BalancedColumns).
                                    // Never more columns than cards.
                                    BalancedColumns(columns: min(columns, max(2, cards.count)), tallestCard: geometry.size.height - 32) {
                                        ForEach(cards) { pageCard($0, forecast: forecast, now: now, twoColumns: true) }
                                        pageEnd(forecast)
                                    }
                                } else {
                                    ForEach(cards) { pageCard($0, forecast: forecast, now: now, twoColumns: false) }
                                }
                            }
                            // The satellite card is empty until its picture has loaded, and an
                            // empty view never runs its own .task, so the cards load it here.
                            .task(id: satelliteID(forecast)) { await SatellitePictureStore.shared.load(satelliteID(forecast)) }
                            if !twoColumns {
                                pageEnd(forecast)
                            }
                        } else if case let .noForecast(failure) = forecasts.status(club.id) {
                            ContentUnavailableView {
                                Label(tr("No forecast"), systemImage: "icloud.slash")
                            } description: {
                                Text(failure.explanation)
                            } actions: {
                                Button(tr("Try again")) { Task { await forecasts.load(club.id, force: true) } }
                            }
                        } else {
                            LoadingCards(cards: AppSettings.shared.pageCards(for: club.id))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                    // Screenshot hook: `-RWScrollTo bottom` scrolls to the page's end.
                    .overlay(alignment: .bottom) {
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: ClubPageColumns.pageWidth(columns: columns))
                    .frame(maxWidth: .infinity)
                    .onPreferenceChange(HourlyFrameKey.self) { frame in
                        if sticky.hourlyFrame != frame { sticky.hourlyFrame = frame }
                    }
                    .onPreferenceChange(DayTopKey.self) { tops in
                        if sticky.dayTops != tops { sticky.dayTops = tops }
                    }
                }
                .overlay(alignment: .top) {
                    // Below the club's name when the top bar shows it.
                    if let forecast {
                        stickyHourlyHeader(forecast)
                            .padding(.top, PageScroll.shared.titleGone.contains(club.id) ? InlineClubTitle.height : 0)
                    }
                }
                .environment(\.pageHeight, geometry.size.height)
                .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: DefaultsKey.scrollPage), ready: forecast != nil))
                .refreshable {
                    async let pictures: Void = refreshSatellite()
                    async let lakeView: Void = refreshLakeView()
                    async let radar: Void = RadarStore.shared.reload(club.launchPoint)
                    await forecasts.refresh(club.id, then: savedIDs)
                    await pictures
                    await lakeView
                    await radar
                }
                .followsRadar(club.launchPoint)
                // Back in the app: the page in front renews its lake view and satellite passes too.
                .onChange(of: forecasts.returns) {
                    guard isCurrentPage else { return }
                    Task {
                        async let pictures: Void = refreshSatellite()
                        await refreshLakeView()
                        await pictures
                    }
                }
                .tipVisibility(conditionsTip, $showConditionsTip)
                .tipVisibility(lakeViewTip, $showLakeViewTip)
                .tipVisibility(rainRadarTip, $showRainRadarTip)
                .tipVisibility(satelliteTip, $showSatelliteTip)
                .tipVisibility(sourceTip, $showSourceTip)
                .tipVisibility(hourlyTip, $showHourlyTip)
                .tipVisibility(launchPointTip, $showLaunchPointTip)
                .tipVisibility(topTileTip, $showTopTileTip)
                .tipVisibility(allValuesTip, $showAllValuesTip)
                .tipVisibility(nearbyWaterTip, $showNearbyWaterTip)
                .tipVisibility(waterEstimateTip, $showWaterEstimateTip)
                .tipVisibility(waterLevelTip, $showWaterLevelTip)
                .tipVisibility(riverTip, $showRiverTip)
                .tipVisibility(radarMapTip, $showRadarMapTip)
                .tipVisibility(hourViewTip, $showHourViewTip)
                .sheet(isPresented: $arranging) { ArrangePageSheet(club: club) }
                .coordinateSpace(.named(CardSpots.space))
                // A resize changes the count once it rests, keeping the top card where it was.
                .task(id: countWidth) {
                    guard let shown = columnCount else {
                        columnCount = columns
                        PageScroll.shared.update(club.id, pageWidth: ClubPageColumns.pageWidth(columns: columns))
                        return
                    }
                    // iPhones turn but are never resized by dragging: at once there.
                    if Orientation.isPad || ProcessInfo.processInfo.isiOSAppOnMac {
                        do { try await Task.sleep(for: ClubPageColumns.resizePause) } catch { return }
                    }
                    let count = ClubPageColumns.count(width: countWidth, current: shown)
                    guard count != shown else { return }
                    let top = isCurrentPage ? cardSpots.topCard(below: pageMargins.top) : nil
                    columnCount = count
                    PageScroll.shared.update(club.id, pageWidth: ClubPageColumns.pageWidth(columns: count))
                    if let top {
                        try? await Task.sleep(for: .milliseconds(50))
                        proxy.scrollTo(top.scrollID, anchor: .top)
                    }
                }
                .task {
                    await forecasts.load(club.id)
                    // Screenshot hook: `-RWHourlyOpen YES` opens the folded 48 hours, once
                    // their folded height is known, as a tap would.
                    if UserDefaults.standard.bool(forKey: DefaultsKey.hourlyOpen) {
                        try? await Task.sleep(for: .milliseconds(1500))
                        hourlyOpen = true
                    }
                    // Screenshot hook: `-RWScrollTo hourly` (or `warnings`, `radar`, `conditions`, `lakeview`,
                    // `launchpoint`, `satellite`, `source`, `arrange`, `hourly-1` for the table's second day,
                    // or `bottom` for the page's end)
                    // scrolls to that card.
                    if let target = UserDefaults.standard.string(forKey: DefaultsKey.scrollTo) {
                        // The lake view loads after the forecast and pushes the cards below it down,
                        // so for cards that may be below it scroll again once it has settled.
                        let early = ["warnings", "conditions"].contains(target)
                        for wait in early ? [300] : [2500, 3000, 3000] {
                            try? await Task.sleep(for: .milliseconds(wait))
                            proxy.scrollTo(target, anchor: target == "bottom" ? .bottom : .top)
                        }
                    }
                }
            }
            // On the swiping club pages the cards scroll on under the clock and the
            // floating buttons; keep clear of whichever the page is not already clear of.
            .safeAreaPadding(.top, max(0, pageMargins.top - geometry.safeAreaInsets.top))
            .safeAreaPadding(.bottom, max(0, pageMargins.bottom - geometry.safeAreaInsets.bottom))
        }
    }

    /// The forecast source, "Arrange this page" and the credits, at the page's end.
    private func pageEnd(_ forecast: ClubForecast) -> some View {
        VStack(spacing: 16) {
            sourceLine(forecast)
            Button {
                arranging = true
            } label: {
                Label(tr("Arrange this page"), systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .cardBackground(surface, cornerRadius: 18)
            }
            .id("arrange")
            UpdateCyclesButton(forecast: forecast)
            credits(forecast)
        }
        .frame(maxWidth: .infinity)
    }

    /// The map cards (radar, lake view, launch point, satellite) are the heaviest
    /// part of a page. The swipe paging keeps the neighbouring pages ready, so
    /// they draw these only on the page in front; elsewhere an empty stand-in of
    /// the same height keeps the page's length and scroll place.
    private func pageCard(_ card: PageCard, forecast: ClubForecast, now: ForecastHour, twoColumns: Bool) -> some View {
        drawnCard(card, forecast: forecast, now: now, twoColumns: twoColumns)
            // Into a plain store, not the view's state: scrolling redraws nothing.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CardSpots.space)) } action: { [cardSpots] in
                cardSpots.frames[card] = $0
            }
            // Set again outside that modifier, so the columns surely read them (BalancedColumns).
            .layoutValue(key: ColumnFiller.self, value: card == .lakeView || card == .launchPoint)
            .layoutValue(key: ColumnSortHeight.self, value: card == .hourly && hourlyOpen ? foldedHourlyHeight : nil)
    }

    @ViewBuilder
    private func drawnCard(_ card: PageCard, forecast: ClubForecast, now: ForecastHour, twoColumns: Bool) -> some View {
        if card.isMap && !isCurrentPage {
            // Before a card was first shown: about a map card's height; the
            // satellite card and a lake view without an outline may stay empty.
            let guess: CGFloat = card == .satellite || (card == .lakeView && lake?.hasOutline == false) ? 0 : 260
            Color.clear
                .frame(height: mapHeights[card] ?? guess)
                .layoutValue(key: ColumnFiller.self, value: card == .lakeView || card == .launchPoint)
                .accessibilityHidden(true)
        } else if card.isMap {
            fullCard(card, forecast: forecast, now: now, twoColumns: twoColumns)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mapHeights[card] = $0 }
        } else {
            fullCard(card, forecast: forecast, now: now, twoColumns: twoColumns)
        }
    }

    @ViewBuilder
    private func fullCard(_ card: PageCard, forecast: ClubForecast, now: ForecastHour, twoColumns: Bool) -> some View {
        switch card {
        case .radar:
            RainRadarCard(point: club.launchPoint, clubID: club.id)
                .id("radar")
        case .conditions:
            VStack(spacing: 16) {
                conditionsTips(forecast)
                ConditionsCard(forecast: forecast, hour: now, club: club)
            }
            .id("conditions")
        case .lakeView:
            if lake?.hasOutline != false {
                VStack(spacing: 16) {
                    if tourSeen && showLakeViewTip {
                        TintedTipView(lakeViewTip)
                    }
                    LakeViewCard(lakeID: forecast.lakeId, clubID: club.id, waterC: forecast.waterTemperature?.celsius ?? forecast.estimatedWaterC, water: lake?.water ?? .lake,
                                 currentMs: forecast.river?.now?.speedMs, daylight: forecast.daylight)
                }
                .id("lakeview")
                .layoutValue(key: ColumnFiller.self, value: true)
            }
        case .hourly:
            // Each tip sits above its card and scrolls with it.
            VStack(spacing: 16) {
                if tourSeen && showHourlyTip {
                    TintedTipView(hourlyTip)
                } else if tourSeen && showHourViewTip {
                    TintedTipView(hourViewTip)
                }
                // In two columns the table shows 24 hours until opened (ColumnFill.fold).
                let folds = twoColumns && AppSettings.shared.activeColumnFill == .fold
                HourlyCard(forecast: forecast, club: club, lake: lake, stale: forecast.isStale(),
                           folds: folds, foldsNights: AppSettings.shared.activeNightHours == .fold, open: $hourlyOpen)
                    .modifier(StickyHourlyCut(sticky: sticky))
            }
            .id("hourly")
            // Opened, the table still counts with its folded height, so no other card moves or grows.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if !hourlyOpen { foldedHourlyHeight = height }
            }
            .layoutValue(key: ColumnSortHeight.self, value: hourlyOpen ? foldedHourlyHeight : nil)
        case .launchPoint:
            VStack(spacing: 16) {
                if tourSeen && showLaunchPointTip {
                    TintedTipView(launchPointTip)
                }
                LaunchPointMapCard(club: club)
            }
            .id("launchpoint")
            .layoutValue(key: ColumnFiller.self, value: true)
        case .satellite:
            VStack(spacing: 16) {
                if tourSeen && showSatelliteTip {
                    TintedTipView(satelliteTip)
                }
                SatellitePictureCard(lakeID: satelliteID(forecast), clubID: club.id, water: lake?.water ?? .lake)
            }
            .id("satellite")
        }
    }

    /// Current conditions' tips, above its card or, inside the top tile, under that.
    /// One tip at a time: the radar's two follow the first. The water level
    /// and river current tips come first, as they only show at such waters.
    @ViewBuilder
    private func conditionsTips(_ forecast: ClubForecast) -> some View {
        if tourSeen && showWaterLevelTip && forecast.waterLevel?.isLowered == true {
            TintedTipView(waterLevelTip)
        } else if tourSeen && showRiverTip && forecast.river != nil {
            TintedTipView(riverTip)
        } else if tourSeen && showConditionsTip {
            TintedTipView(conditionsTip)
        } else if tourSeen && showRainRadarTip {
            TintedTipView(rainRadarTip)
        } else if tourSeen && showRadarMapTip {
            TintedTipView(radarMapTip)
        } else if tourSeen && showWaterEstimateTip && forecast.waterTemperature == nil && forecast.waterEstimate?.reading != nil {
            // Only where no station measures the water.
            TintedTipView(waterEstimateTip)
        }
    }

    /// The hourly table's header, kept at the top of the screen while the
    /// table is scrolled through, with the day being looked at.
    private func stickyHourlyHeader(_ forecast: ClubForecast) -> some View {
        StickyHourlyHeader(sticky: sticky)
    }
}

private extension LocationPageView {

    private func credits(_ forecast: ClubForecast) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(forecast.attribution, id: \.self) { Text(tr($0)) }
            if club.isOwnPlace {
                Text(tr("Your own place, kept on this iPhone. No waves, water temperature or warnings here."))
            } else if !club.launchPointVerified {
                switch club.source {
                case "drv":
                    Text(tr("Club data: Deutscher Ruderverband e.V. (rudern.de). Launch point geocoded with © OpenStreetMap contributors, ODbL"))
                case "oerv":
                    Text(tr("Club data: Österreichischer Ruderverband (rudern.at). Launch point geocoded with © OpenStreetMap contributors, ODbL"))
                case "swissrowing":
                    Text(tr("Club data: Swiss Rowing (swissrowing.ch). Launch point geocoded with © OpenStreetMap contributors, ODbL"))
                default:
                    Text(tr("Launch point from © OpenStreetMap contributors, ODbL"))
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(surface.hasPicture ? 12 : 0)
        .labelBackground(surface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func sourceLine(_ forecast: ClubForecast) -> some View {
        if let source = forecast.forecastSource {
            VStack(spacing: 16) {
                if tourSeen && showSourceTip {
                    TintedTipView(sourceTip)
                }
                ForecastSourceLine(
                    source: source,
                    choices: forecast.modelChoices ?? [],
                    selected: AppSettings.shared.pickedModel(for: club.id),
                    pickedModelMissing: forecasts.pickedModelMissing.contains(club.id)
                ) { model in
                    AppSettings.shared.pickedModels[club.id] = model
                    await forecasts.load(club.id, force: true)
                }
            }
            .id("source")
        }
    }

}

/// The rowing light now, why, and the values that matter most: air, water
/// and wind big; waves, rain, visibility (and ice when it matters) small;
/// whether DWD warns; and how much daylight is left.
/// How the "All values" row under the top tile sits (owner's pick A2, 6 Nov 2026: 34 pt in all,
/// half the old row). For A3 (28 pt) set above 4 and below 6; the tap area keeps 44 pt either way.
enum GripRow {
    /// Points between the sun line and the words.
    static let above: CGFloat = 6
    /// Points between the words and the tile's edge.
    static let below: CGFloat = 10
    /// How far the tap area reaches under the words (about 18 pt) to make 44 pt. It goes past the
    /// tile into the 16 pt gap before the next card, where a tap does nothing else.
    static let tapBelow: CGFloat = max(0, 44 - above - 18)
}

private struct NowCard: View {
    let hour: ForecastHour
    let forecast: ClubForecast
    var stale = false
    var lakeName: String?
    var town: String?
    /// A later hour shown from the hourly table: no warnings line, daylight at that time.
    var at: Date?
    /// The club, for the weather maps in the larger views.
    var club: Club?
    @State private var showingLights = UserDefaults.standard.string(forKey: DefaultsKey.legend) == "lights"
    @State private var showingWarnings = false
    @State private var showingDaylight = false
    /// A value of the tile tapped for its chart; swiping there stays within the tile's values.
    @State private var openCondition: Condition?
    /// The weather word's column beside the verdict, growing with the text size like the word.
    @ScaledMetric(relativeTo: .caption) private var skyWordWidth: CGFloat = 88

    private var water: WaterTemperature? { forecast.waterTemperature }
    /// The water at the shown hour: now the reading or estimate, later the water forecast.
    private var hourWaterC: Double? {
        let latest = water?.celsius ?? forecast.estimatedWaterC
        return at == nil ? latest : forecast.waterForecastC(on: hour.time) ?? latest
    }

    var body: some View {
        Card {
            // The verdict on one line beside the weather; one text style smaller where
            // that does not fit; and only where that does not fit either, the weather
            // moves under the verdict (owner's choice, option 6, 2 Nov 2026).
            ViewThatFits(in: .horizontal) {
                headlineRow(.title2.bold())
                headlineRow(.title3.bold())
                headlineStacked
            }
            if let kit = ColdWaterKit(waterC: hourWaterC, limits: AppSettings.shared.limits(at: forecast.clubId)) {
                opens(.waterTemperature) { ColdWaterBadge(kit: kit, estimated: water == nil) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                // The reasons read as one "Why: …" for VoiceOver; the warnings line below stays its own button.
                VStack(alignment: .leading, spacing: 6) {
                    if stale {
                        Label(tr("The forecast is more than 3 hours old. Check the conditions yourself before you go out."), systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                    if hour.reasons.isEmpty {
                        // The full sentence where it fits on one line, else the short one (owner's choice C, 30.10.2026).
                        ViewThatFits(in: .horizontal) {
                            Label(tr("All conditions are within the limits."), systemImage: "checkmark.circle")
                            Label(tr("All within the limits."), systemImage: "checkmark.circle")
                        }
                    } else {
                        ForEach(hour.reasons, id: \.self) { reason in
                            // Without a station the water is estimated, and the advice says so.
                            Label(water == nil && Condition.waterTemperature.reasonNames.contains(reason.condition)
                                  ? tr("Estimated: %@", reason.explanation) : forecast.explanation(reason, in: hour), systemImage: reason.symbol)
                                .foregroundStyle(reason.light == .red ? Color.red : Color.orange)
                        }
                    }
                    ForEach(hour.notes ?? [], id: \.self) { note in
                        Label(note.noteText(for: AppSettings.shared.boat(at: forecast.clubId)), systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    if let steadier = SteadierBoat.suggestion(for: hour, water: water?.celsius ?? forecast.estimatedWaterC, at: forecast.clubId) {
                        Label(steadier.light == .green
                              ? tr("A steadier boat helps: %@ would be green now.", steadier.boat.title)
                              : tr("A steadier boat helps: %@ would only need care now.", steadier.boat.title),
                              systemImage: "figure.rower")
                            .foregroundStyle(.tint)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(hour.reasons.isEmpty ? tr("Why: all conditions within the limits") : tr("Why: %@", hour.reasons.map { forecast.explanation($0, in: hour) }.joined(separator: " ")))
                if at == nil { warningsLine }
            }
            .font(.subheadline)
            .symbolRenderingMode(.hierarchical)
            AdviceOnlyNote()
            Divider()
            if combined, open {
                // Opened: the small values and the sun line become the tiles of Current conditions.
                ConditionTiles(forecast: forecast, hour: hour, club: club)
                    .transition(.opacity)
            } else {
                valueGrid
                    .transition(.opacity)
                if !combined {
                    iceLine
                }
                daylightLine
                    .transition(.opacity)
                if combined {
                    // What the closed tile hides but counts for the light, in the tile's own words.
                    ForEach(peeks) { condition in
                        opens(condition) { TilePeekLine(condition: condition, data: data) }
                            .transition(.opacity)
                    }
                }
            }
            if combined {
                openHandle
            }
        }
        .sheet(isPresented: $showingLights) { LegendSheet(part: .lights) }
        .sheet(isPresented: $showingWarnings) {
            if let warnings = forecast.warnings {
                NoWarningSheet(warnings: warnings, lakeName: lakeName, town: town, checkedAt: forecast.generatedAt)
            }
        }
        .detailCover(isPresented: $showingDaylight) {
            ConditionDetailView(condition: .daylight, data: ConditionData(forecast: forecast, now: hour, radar: radar), club: club)
        }
        .detailCover(item: $openCondition) { condition in
            ConditionDetailView(condition: condition, data: ConditionData(forecast: forecast, now: hour, radar: radar),
                                order: combined ? ConditionTiles.order(forecast) : tileValues, club: club)
        }
        .onChange(of: openCondition != nil) { _, open in if open { TopTileTip().invalidate(reason: .actionPerformed) } }
        .task {
            // Screenshot hook: `-RWOpenCondition wind` on a closed combined tile, whose tiles are not there to open it.
            guard combined, !open, at == nil, let raw = UserDefaults.standard.string(forKey: DefaultsKey.openCondition) else { return }
            let page = UserDefaults.standard.string(forKey: DefaultsKey.openClub)
            guard page == nil || page == forecast.clubId else { return }
            try? await Task.sleep(for: .milliseconds(500))
            openCondition = Condition(rawValue: raw)
        }
    }

    /// Air, water and wind, with the small values in three columns under them.
    /// Air, water and wind share one size, the second line a smaller one (owner, 5 Nov 2026).
    private var valueGrid: some View {
        TopTileGrid {
            VStack(alignment: .leading, spacing: 0) {
                opens(.temperature) {
                    TemperatureView(condition: .temperature, celsius: hour.temperatureC, size: 28)
                }
                if let feels = hour.apparentTemperatureC {
                    opens(.feelsLike) {
                        Label(tr("Feels like %@", Format.degrees(feels)), systemImage: Condition.feelsLike.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(tr("Feels like %@", Format.temperature(feels)) + ". " + (feelsLikeNote(hour) ?? ""))
                            .greyLine()
                    }
                }
            }
            // With the time of the reading underneath, so it lines up with the wind's unit line.
            opens(.waterTemperature) {
                if water == nil, let estimate = forecast.estimatedWaterC {
                    TemperatureView(condition: .waterTemperature, celsius: estimate, digits: 0, size: 28, caption: tr("Estimated"))
                        .foregroundStyle(.secondary)
                } else {
                    TemperatureView(condition: .waterTemperature, celsius: water?.celsius, digits: 1, size: 28,
                                    caption: water.map { tr("Measured %@", Format.time($0.measuredAt)) } ?? " ")
                }
            }
            opens(.wind) { WindView(hour: hour, size: 28, nearby: hour.nearbyCondition == .wind) }
            opens(.waves) {
                MetricView(title: tr("Waves"), symbol: Condition.waves.symbol, value: Format.waves(hour.shownWaveHeightM), size: 17,
                           caption: hour.nearbyCondition == .waves ? tr("Nearby") : wavesCaption)
            }
            opens(.precipitation) {
                MetricView(title: tr("Precipitation"), symbol: Condition.precipitation.symbol, value: rain.value, size: 17,
                           caption: rain.detail == tr("Dry next 24 h") ? tr("Dry for 24 h") : rain.detail,
                           mark: rain.fromRadar ? "dot.radiowaves.left.and.right" : nil)
            }
            opens(.visibility) {
                MetricView(title: tr("Visibility"), symbol: Condition.visibility.symbol, value: Format.distance(hour.shownVisibilityM), size: 17,
                           caption: hour.nearbyCondition == .visibility ? tr("Nearby") : data.visibilityDetail)
            }
        }
        .symbolRenderingMode(.hierarchical)
    }

    /// When ice matters (mostly mid-winter), it gets its own line under the row,
    /// so the row keeps its three columns under air, water and wind.
    @ViewBuilder private var iceLine: some View {
        if let ice = iceValue {
            opens(.ice) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Label(tr("Ice"), systemImage: Condition.ice.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(ice).valueFont(size: 17).causeTinted()
                    Text(iceDetail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
            }
            .symbolRenderingMode(.hierarchical)
        }
    }

    private var combined: Bool { AppSettings.shared.combinedTopTile }
    private var open: Bool { AppSettings.shared.topTileOpen }

    /// The values the closed tile does not show, while they count for the light; ice also
    /// whenever the ice line would show. The Current or Water level tile on rivers and
    /// lowered lakes takes the ice tile's place, so there it has no line either.
    private var peeks: [Condition] {
        let order = ConditionTiles.order(forecast)
        return [Condition.thunderstorm, .cloudCover, .humidity, .pressure, .uvIndex, .ice].filter { condition in
            guard order.contains(condition) else { return false }
            if condition == .ice, iceValue != nil { return true }
            // Screenshot hook: `-RWSamplePeek thunderstorm` shows that value's line, light or not.
            if UserDefaults.standard.string(forKey: DefaultsKey.samplePeek) == condition.rawValue { return true }
            return hour.light(for: condition.reasonNames).map { $0 != .green } ?? false
        }
    }

    /// The grip under the tile: tapped, it opens or closes the tiles.
    private var openHandle: some View {
        Button(action: toggleOpen) {
            // Words only, like Apple's own "Show more" rows (owner's pick G2, 5 Nov 2026).
            HStack(spacing: 4) {
                Text(open ? tr("Fewer values") : tr("All values"))
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            // Still 44 pt to tap, as Apple's guide asks: from the sun line down into the
            // empty tile edge and the gap below the tile.
            .tapArea(EdgeInsets(top: GripRow.above, leading: 0, bottom: GripRow.tapBelow, trailing: 0))
        }
        // The card's 10 pt row spacing and 14 pt edge, trimmed to the row's own room.
        .padding(.top, GripRow.above - 10)
        .padding(.bottom, GripRow.below - 14)
        // Tap only: a pull here took page swipes that start on this full-width row
        // (owner's report, 5 Nov 2026), so swipes always scroll the page.
        .buttonStyle(.plain)
        .accessibilityLabel(open ? tr("Fewer values") : tr("All values"))
        .accessibilityHint(open ? tr("Shows the short top tile again") : tr("Opens all values in the top tile"))
        .accessibilityIdentifier("top-tile-handle")
    }

    private func toggleOpen() {
        AllValuesTip().invalidate(reason: .actionPerformed)
        withAnimation(.smooth(duration: 0.35)) { AppSettings.shared.topTileOpen.toggle() }
    }

    /// The light, the verdict on one line, and the weather in a column of its own,
    /// its word on up to two lines.
    private func headlineRow(_ font: Font) -> some View {
        HStack(spacing: 10) {
            TrafficLightDot(light: hour.light, size: 36, stale: stale, halves: at == nil ? nil : forecast.dotHalves(for: hour, stale: stale))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(hour.light.title(stale: stale)).font(font).lineLimit(1).fixedSize()
                    LegendButton(showing: $showingLights)
                }
                boatLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 2) {
                skyIcon
                Text(data.sky.title).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: skyWordWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Where the verdict has no room beside the weather (large text sizes):
    /// the weather goes under it, so the verdict keeps its words whole.
    private var headlineStacked: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                TrafficLightDot(light: hour.light, size: 36, stale: stale, halves: at == nil ? nil : forecast.dotHalves(for: hour, stale: stale))
                VStack(alignment: .leading, spacing: 0) {
                    // Under the weather too, the verdict keeps one line as long as it can:
                    // one size smaller first; it wraps only at the very largest text sizes.
                    ViewThatFits(in: .horizontal) {
                        stackedTitle(.title2.bold(), oneLine: true)
                        stackedTitle(.title3.bold(), oneLine: true)
                        stackedTitle(.title3.bold(), oneLine: false)
                    }
                    boatLine
                }
            }
            HStack(spacing: 8) {
                skyIcon
                Text(data.sky.title).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.leading, 46)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stackedTitle(_ font: Font, oneLine: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(hour.light.title(stale: stale)).font(font)
                .lineLimit(oneLine ? 1 : nil)
                .fixedSize(horizontal: oneLine, vertical: !oneLine)
            LegendButton(showing: $showingLights)
        }
    }

    private var skyIcon: some View {
        SkyIcon(sky: data.sky, night: hour.sunUp == false).scaledSystemFont(size: 34, relativeTo: .largeTitle, maxGrowth: 1.35)
    }

    /// "For small boats" under the verdict: which boat the light is for, as
    /// plain text. The boat button beside the cog changes it (owner, 5 Nov 2026).
    /// It wraps rather than pushes the weather under the verdict, so a long
    /// boat name never decides the layout.
    private var boatLine: some View {
        Text(tr("For %@", AppSettings.shared.boat(at: forecast.clubId).inSentence))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    /// The values shown in this tile, in its order, for swiping between their views.
    private var tileValues: [Condition] {
        var values: [Condition] = [.temperature]
        if hour.apparentTemperatureC != nil { values.append(.feelsLike) }
        values += [.waterTemperature, .wind, .waves, .precipitation, .visibility]
        if iceValue != nil { values.append(.ice) }
        return values
    }

    /// A value of the tile as a button that opens its chart and details.
    private func opens(_ condition: Condition, @ViewBuilder _ content: () -> some View) -> some View {
        let light = condition.cause(in: hour)
        return Button { openCondition = condition } label: {
            content().contentShape(Rectangle()).environment(\.causeTint, light?.causeTint ?? coldTint(condition))
        }
            .buttonStyle(.plain)
            .accessibilityValue(light?.causeTint == nil ? "" : tr("Sets the light: %@", light?.title ?? ""))
            .accessibilityHint(tr("Opens a chart and more about this value"))
    }

    /// The cold-water blue on the water value while the Life jacket badge shows.
    private func coldTint(_ condition: Condition) -> Color? {
        guard condition == .waterTemperature else { return nil }
        return ColdWaterKit.valueTint(waterC: hourWaterC, limits: AppSettings.shared.limits(at: forecast.clubId))
    }

    /// Screenshot hook: `-RWSampleIce YES` shows the winter ice value, to check the row's fit.
    private var sampleIce: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.sampleIce) }
    private var iceValue: String? { sampleIce ? tr("Shore ice possible") : forecast.iceValue }
    /// The ice line's reason, shortened where the tile's words are long.
    private var iceDetail: String {
        let detail = sampleIce ? tr("Bays and harbours first") : forecast.ice?.detail ?? tr("Check the lake yourself")
        return detail == tr("Bays and harbours first") ? tr("Bays first") : detail
    }

    /// The waves line in fewer words than the tile's, so it fits under the value in German too.
    private var wavesCaption: String {
        guard let fetch = hour.fetchM else { return "" }
        return fetch < 50 ? tr("Offshore wind") : tr("%@ open water", Format.distance(fetch))
    }

    private var data: ConditionData { ConditionData(forecast: forecast, now: hour, radar: radar) }

    /// The rain tile's two lines, so the top tile always says the same.
    private var rain: (value: String, detail: String, fromRadar: Bool) { data.rainLines }

    /// DWD's radar at the launch point, read while the page is open.
    private var radar: RainRadar? { club.flatMap { RadarStore.shared.radar(at: $0.launchPoint) } }

    /// While DWD has no warning, one line says so; for a warning that starts later or
    /// does not count for the light, one line names it. The warnings card itself
    /// only shows while a warning is issued or DWD could not be checked.
    @ViewBuilder
    private var warningsLine: some View {
        if let warnings = forecast.warnings, warnings.checked, warnings.localChecked, warnings.items.isEmpty {
            Button { showingWarnings = true } label: {
                HStack(spacing: 6) {
                    Label(tr("No official warning"), systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("· " + tr("checked %@", Format.time(forecast.generatedAt)))
                        .foregroundStyle(.secondary)
                    Image(systemName: "info.circle").foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Shows what was checked and what the shore warning lights mean"))
        } else if let warnings = forecast.warnings, let headline = warnings.headline(), headline.urgency != .now {
            // A warning for later, or about frost or heat: said here (amber when it counts and starts
            // within hours, else grey), so the light and the warnings card tell the same story.
            // Counting warnings in force already are reasons above.
            let warning = headline.warning, soon = headline.urgency == .soon
            Button { showingWarnings = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: soon ? "exclamationmark.triangle.fill" : "info.circle")
                    Text(warning.counts
                         ? warning.shortLabel(at: .now)
                         : tr("%@ · not part of the rowing light", warning.shortLabel(at: .now)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(soon ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Opens the warnings"))
        }
    }

    /// One line with a small sun path: daylight left, or when it comes back.
    @ViewBuilder
    private var daylightLine: some View {
        if let sun = forecast.sunState(at: at ?? .now) {
            Button { showingDaylight = true } label: {
                HStack(spacing: 8) {
                    // Read left to right: what, then when, with the sunset or sunrise
                    // symbol in the text so it grows with the text size. One line
                    // where it fits, else two; VoiceOver reads the whole sentence.
                    switch sun {
                    case let .up(sunrise, sunset):
                        SunPath(sunrise: sunrise, sunset: sunset, at: at ?? .now, lineWidth: 1.5).frame(width: 44, height: 20)
                        let left = Format.duration(from: at ?? .now, to: sunset)
                        DaylightText(
                            line: Text("\(tr("Rowing until")) \(sunSymbol("sunset.fill")) \(sunTime(sunset))"),
                            rest: Text(tr("%@ left", left))
                        )
                            .accessibilityLabel(tr("Rowing until sunset at %@, %@ left", Format.time(sunset), left))
                    case let .down(sunrise, _):
                        Image(systemName: "moon.stars.fill").foregroundStyle(.secondary).frame(width: 44)
                        DaylightText(line: Text("\(tr("Rowing again from")) \(sunSymbol("sunrise.fill")) \(sunTime(sunrise))"))
                            .accessibilityLabel(tr("Rowing again from sunrise at %@", Format.time(sunrise)))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Condition.daylight.cause(in: hour).map { tr("Sets the light: %@", $0.title) } ?? "")
            .accessibilityHint(tr("Opens sunrise, sunset and daylight"))
        }
    }

    /// The sunset or sunrise time, in amber or red while daylight is what sets the light
    /// (owner's pick S1, 5 Nov 2026); the rest of the line stays as it is.
    private func sunTime(_ date: Date) -> Text {
        let time = Text(Format.time(date))
        guard let tint = Condition.daylight.cause(in: hour)?.causeTint else { return time }
        return time.foregroundStyle(tint)
    }

    /// A sunset or sunrise symbol to sit in the daylight line's text.
    private func sunSymbol(_ name: String) -> Text {
        Text(Image(systemName: name)).foregroundStyle(.orange)
    }
}

/// What the "No official warning" line opens: what was checked and the shore lights.
private struct NoWarningSheet: View {
    let warnings: Warnings
    let lakeName: String?
    let town: String?
    let checkedAt: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                WarningsCard(warnings: warnings, lakeName: lakeName, town: town, checkedAt: checkedAt, guideOpen: true)
                    .padding()
            }
            .navigationTitle(tr("Official warnings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The reminder that the light is advice and the rower decides, wherever a
/// decision to go out is made from the app.
struct AdviceOnlyNote: View {
    var body: some View {
        Label(tr("Advice only. You decide whether to go out. When in doubt, ask experienced rowers or stay ashore."), systemImage: "person.fill.questionmark")
            .font(.caption)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A temperature with the icon and word that say whether it is air or water.
struct TemperatureView: View {
    let condition: Condition
    let celsius: Double?
    var digits = 0
    var size: CGFloat
    /// A small line under the value, such as when it was measured.
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(condition == .temperature ? tr("Air") : tr("Water"), systemImage: condition.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Format.degrees(celsius, digits: digits))
                .valueFont(size: size)
                .causeTinted()
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .greyLine()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A grey line under a value that does not widen its column: it wraps within
/// the width the column is given, but counts as nothing when the column is measured.
private struct GreyLineLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let line = subviews.first else { return .zero }
        guard let width = proposal.width, width.isFinite else {
            return CGSize(width: 0, height: line.sizeThatFits(.unspecified).height)
        }
        return line.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

extension View {
    /// See `GreyLineLayout`.
    func greyLine() -> some View { GreyLineLayout { self } }
}

/// The top tile's values in three columns: air, water, wind above, the three
/// small values below. Each column is as wide as its titles and values (the
/// grey lines don't count): the left one starts at the left edge, the right one
/// ends at the right edge, the middle one has equal gaps to both. Each row reads level.
struct TopTileGrid: Layout {
    var rowSpacing: CGFloat = 10
    var gap: CGFloat = 8

    /// The frames last worked out, by width: measuring the tiles' text is
    /// slow, and the page asks for the same width many times in one pass.
    struct Cache {
        var width: CGFloat?
        var frames: [CGRect] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? subviews.prefix(3).reduce(0) { $0 + $1.sizeThatFits(.unspecified).width } + 2 * gap
        return CGSize(width: width, height: frames(width: width, subviews, &cache).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        for (view, frame) in zip(subviews, frames(width: bounds.width, subviews, &cache)) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    // The grid lines up with nothing outside it. Without these, every stack
    // around it asking for an alignment guide had SwiftUI place all the tiles
    // again to work it out, page after page; on the iPhone that froze the app
    // (watchdog reports with TopTileGrid.placeSubviews under explicitAlignment).
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? {
        nil
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? {
        nil
    }

    private func frames(width: CGFloat, _ subviews: Subviews, _ cache: inout Cache) -> [CGRect] {
        if cache.width != width {
            cache = Cache(width: width, frames: frames(width: width, subviews))
        }
        return cache.frames
    }

    private func frames(width: CGFloat, _ subviews: Subviews) -> [CGRect] {
        let top = Array(subviews.prefix(3)), bottom = Array(subviews.dropFirst(3))
        guard top.count == 3 else { return [] }
        // Each column's width from its titles and values, in both rows.
        let core = (0..<3).map { i in
            [top[i], i < bottom.count ? bottom[i] : nil].compactMap { $0 }.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        }
        // The middle column with equal gaps to its neighbours.
        let right = width - core[2]
        let xs = [0, core[0] + (right - core[0] - core[1]) / 2, right]
        let columns: [(x: CGFloat, width: CGFloat)] = [(0, xs[1] - gap), (xs[1], xs[2] - xs[1] - gap), (xs[2], width - xs[2])]
        // First row on the last baseline.
        let topDims = zip(top, columns).map { $0.dimensions(in: ProposedViewSize(width: $1.width, height: nil)) }
        let line = topDims.map { $0[.lastTextBaseline] }.max() ?? 0
        var result = zip(columns, topDims).map { CGRect(x: $0.x, y: line - $1[.lastTextBaseline], width: $0.width, height: $1.height) }
        let below = (result.map(\.maxY).max() ?? 0) + rowSpacing
        let dims = zip(bottom, columns).map { $0.dimensions(in: ProposedViewSize(width: $1.width, height: nil)) }
        let valueLine = dims.map { $0[VerticalAlignment.metricValue] }.max() ?? 0
        for (column, d) in zip(columns, dims) {
            result.append(CGRect(x: column.x, y: below + valueLine - d[VerticalAlignment.metricValue], width: column.width, height: d.height))
        }
        return result
    }
}

extension VerticalAlignment {
    private enum MetricValue: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.firstTextBaseline] }
    }
    /// The baseline of a `MetricView`'s value, so a row of them reads level.
    static let metricValue = VerticalAlignment(MetricValue.self)
}

/// A small dial like the Weather app's pressure gauge: an arc from 960 to
/// 1060 hPa with a mark at the current value and the trend arrow inside.
struct PressureGauge: View {
    let hpa: Double?
    let trend: PressureTrend?
    /// Bigger in the larger view, where the dial is bigger too.
    var arrowFont: Font = .caption.weight(.bold)
    private let range = 960.0...1060.0
    private let sweep = 0.75  // share of the circle the arc covers

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(135))
            if let hpa {
                let share = (min(max(hpa, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
                Circle()
                    .trim(from: max(0, share * sweep - 0.012), to: min(sweep, share * sweep + 0.012))
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))
            }
            Image(systemName: trend?.symbol ?? "minus")
                .font(arrowFont)
                .foregroundStyle(.secondary)
        }
        .padding(4)
        .accessibilityElement()
        .accessibilityLabel(tr("Pressure %@ hectopascal, %@", hpa.map { Format.number($0) } ?? "–", trend?.title ?? "–"))
    }
}

/// Columns of the hourly table, shared by the icon header and the rows.
enum HourColumn {
    /// Wider for "10:00 PM" than for "22:00".
    static var time: CGFloat { AppSettings.shared.activeTimeFormat.usesAMPM ? 64 : 44 }
    static let light: CGFloat = 14
    static let sky: CGFloat = 24
}

/// Where the hourly table is on the page.
private struct HourlyFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Where each day of the hourly table starts on the page.
private struct DayTopKey: PreferenceKey {
    static var defaultValue: [Date: CGFloat] = [:]
    static func reduce(value: inout [Date: CGFloat], nextValue: () -> [Date: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct HourlyCard: View {
    let forecast: ClubForecast
    let club: Club
    let lake: Lake?
    var stale = false
    /// Two columns: the table shows the first 24 hours and a button for the rest.
    var folds = false
    /// Each night as one line until tapped (NightFold).
    var foldsNights = true
    @Binding var open: Bool
    @State private var openHour: ForecastHour?
    /// The nights opened by a tap, by their first hour; all fold again when the page opens anew.
    @State private var openNights: Set<Date> = []

    /// How many hours a folded table shows.
    static let foldedHours = 24

    var body: some View {
        ScrollViewReader { proxy in
            table(proxy)
        }
    }

    private func table(_ proxy: ScrollViewProxy) -> some View {
        Card(title: tr("Next 48 hours"), symbol: "clock", legend: .hourly) {
            HourlyLegendHeader()
            ForEach(rows) { row in
                switch row {
                case let .day(day, index):
                    DayHeader(day: day, sun: sunDay(on: day))
                        // Screenshot hook: `-RWScrollTo hourly-1` scrolls to the second day.
                        .id("hourly-\(index)")
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(key: DayTopKey.self, value: [day: geo.frame(in: .global).minY])
                            }
                        }
                case let .hour(hour):
                    Button { openHour = hour } label: {
                        HourRow(hour: hour, stale: stale, halves: forecast.dotHalves(for: hour, stale: stale),
                                coarser: forecast.coarserModel(for: hour) != nil).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(tr("Opens this hour with all its values"))
                case let .night(night):
                    let opened = openNights.contains(night.id)
                    Button {
                        withAnimation(.snappy) {
                            if opened { openNights.remove(night.id) } else { openNights.insert(night.id) }
                        }
                    } label: {
                        NightRow(night: night, opened: opened, startsTable: night.start == firstHour, endsTable: night.end == tableEnd,
                                 coarser: coarser(in: night))
                    }
                    .buttonStyle(.plain)
                }
            }
            if folds && hiddenHours > 0 {
                foldButton(proxy)
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: HourlyFrameKey.self, value: geo.frame(in: .global))
            }
        }
        .sheet(item: $openHour) { hour in
            HourDetailSheet(forecast: forecast, club: club, lake: lake, hour: hour)
        }
        .onChange(of: openHour != nil) { _, open in if open { HourViewTip().invalidate(reason: .actionPerformed) } }
        .task {
            // Screenshot hook: `-RWOpenHour n` opens the n-th hour of the table.
            let n = UserDefaults.standard.integer(forKey: DefaultsKey.openHour)
            if n > 0, forecast.hours.indices.contains(n) {
                try? await Task.sleep(for: .milliseconds(800))
                openHour = forecast.hours.sorted { $0.time < $1.time }[n]
            }
        }
    }

    /// A line of the table: a day's header, an hour, or a folded night.
    private enum TableRow: Identifiable {
        case day(Date, index: Int)
        case hour(ForecastHour)
        case night(NightFold.Night)

        var id: String {
            switch self {
            case let .day(day, _): "day-\(day.timeIntervalSince1970)"
            case let .hour(hour): "hour-\(hour.time.timeIntervalSince1970)"
            case let .night(night): "night-\(night.start.timeIntervalSince1970)"
            }
        }
    }

    /// Opens the rest of the table, or folds it back to the first 24 hours. Folding
    /// keeps the button where it was on the screen, so the page does not jump on.
    private func foldButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.snappy) { open.toggle() }
            if !open {
                Task { @MainActor in proxy.scrollTo("hourly-fold", anchor: .bottom) }
            }
        } label: {
            Label(open ? tr("Show fewer hours") : tr("Show 24 more hours"),
                  systemImage: open ? "chevron.up" : "chevron.down")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .id("hourly-fold")
    }

    /// The hours past the first 24, left out while folded.
    private var hiddenHours: Int { max(0, forecast.hours.count - Self.foldedHours) }

    /// The hours the table shows: all, or the first 24 while folded.
    private var shownHours: [ForecastHour] {
        let hours = forecast.hours.sorted { $0.time < $1.time }
        return folds && !open ? Array(hours.prefix(Self.foldedHours)) : hours
    }

    /// The table's lines. A folded night sits after the evening it starts in; its day
    /// header after midnight comes with the next hour shown, or inside the opened night.
    private var rows: [TableRow] {
        let calendar = Calendar.current
        var rows: [TableRow] = []
        var lastDay: Date?
        var dayIndex = 0
        func add(_ hour: ForecastHour) {
            let day = calendar.startOfDay(for: hour.time)
            if day != lastDay {
                rows.append(.day(day, index: dayIndex))
                dayIndex += 1
                lastDay = day
            }
            rows.append(.hour(hour))
        }
        let parts = foldsNights ? NightFold.parts(shownHours, days: forecast.daylight ?? []) : shownHours.map(NightFold.Part.hour)
        for part in parts {
            switch part {
            case let .hour(hour):
                add(hour)
            case let .night(night):
                rows.append(.night(night))
                if openNights.contains(night.id) { night.hours.forEach(add) }
            }
        }
        return rows
    }

    private var firstHour: Date? { shownHours.first?.time }
    /// When the last hour of the whole forecast ends, so a night cut off there says "from".
    private var tableEnd: Date? { forecast.hours.map(\.time).max()?.addingTimeInterval(3600) }

    /// The night's first hour from a coarser model and that model, for the hint in its line.
    private func coarser(in night: NightFold.Night) -> (from: Date, part: ForecastSource.Part)? {
        for hour in night.hours {
            if let part = forecast.coarserModel(for: hour) { return (hour.time, part) }
        }
        return nil
    }

    private func sunDay(on day: Date) -> SunDay? {
        forecast.daylight?.first { Calendar.current.isDate($0.sunrise, inSameDayAs: day) }
    }
}

/// The hourly table's header as it stays at the top of the screen: the tile's
/// title and the day being looked at over the column icons.
struct HourlyStickyHeader: View {
    let day: Date?
    static let height: CGFloat = 74
    @Environment(\.surface) private var surface

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(tr("Next 48 hours").uppercased(), systemImage: "clock")
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 8)
                if let day { Text(Format.day(day)) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            HourlyLegendHeader()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .frame(height: Self.height, alignment: .top)
        // The tile's own colour. Rounded at the top like the tile, square at the
        // bottom where the rows start, so the header keeps its shape when it starts to stay.
        .cardBackground(surface, in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

/// The icon legend over the hourly table: one icon and unit per column.
private struct HourlyLegendHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock").frame(width: HourColumn.time, alignment: .leading)
                .accessibilityLabel(tr("Time"))
            Image(systemName: "circle.fill").font(.system(size: 8)).frame(width: HourColumn.light)
                .accessibilityLabel(tr("Rowing light"))
            Image(systemName: "cloud.sun").frame(width: HourColumn.sky)
                .accessibilityLabel(tr("Weather"))
            column(.temperature)
            column(.feelsLike)
            column(.wind)
            column(.waves)
            column(.precipitation)
            column(.visibility)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func column(_ c: Condition) -> some View {
        VStack(spacing: 1) {
            ConditionIcon(condition: c)
            Text(c.unit).font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.title)
    }
}

private struct DayHeader: View {
    let day: Date
    let sun: SunDay?

    var body: some View {
        HStack {
            Text(Format.day(day)).font(.subheadline.weight(.semibold))
            Spacer()
            if let sun {
                Label(Format.time(sun.sunrise), systemImage: "sunrise.fill")
                Label(Format.time(sun.sunset), systemImage: "sunset.fill")
            }
        }
        .font(.caption)
        .symbolRenderingMode(.hierarchical)
        .labelStyle(SunLabelStyle())
        .padding(.top, 8)
    }
}

/// One hour from the table with everything known about it: the rowing light
/// and main values, all the conditions tiles (rain from the radar while the
/// hour is within its 2 hours), and the lake map at that hour.
private struct HourDetailSheet: View {
    let forecast: ClubForecast
    let club: Club
    let lake: Lake?
    let hour: ForecastHour
    @Environment(\.dismiss) private var dismiss
    @State private var showingLakeMap = false
    @MainActor private var lakeViews: LakeViewStore { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Within the radar's 2 hours the rain values come from the radar, later from the forecast.
                    NowCard(hour: hour, forecast: forecast, at: hour.time, club: club)
                    if !AppSettings.shared.combinedTopTile {
                        ConditionsCard(forecast: forecast, hour: hour, club: club)
                    }
                    if lake?.hasOutline != false, lakeViews.views[forecast.lakeId, club: forecast.clubId] != nil {
                        Button { showingLakeMap = true } label: {
                            Label(tr("Lake map at %@", Format.dayTime(hour.time)), systemImage: "map")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle(Format.dayTime(hour.time))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
            .fullScreenCover(isPresented: $showingLakeMap) {
                if let view = lakeViews.views[forecast.lakeId, club: forecast.clubId] {
                    LakeMapScreen(view: view, clubID: club.id, at: hour.time)
                        .diagnosisNamed("lake map")
                }
            }
        }
    }
}

/// Screenshot hook: `-RWScrollPage n` scrolls the page down by n screens
/// (less a little overlap), stopping at the bottom, so a series of screenshots
/// covers the whole page.
struct ScreenshotScroll: ViewModifier {
    let page: Int
    let ready: Bool

    func body(content: Content) -> some View {
        if page > 0 {
            content.modifier(PagedScroll(page: page, ready: ready))
        } else {
            content
        }
    }
}

private struct PagedScroll: ViewModifier {
    let page: Int
    let ready: Bool
    @State private var position = ScrollPosition(edge: .top)
    @State private var size: (content: CGFloat, container: CGFloat) = (0, 0)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: [CGFloat].self) { [$0.contentSize.height, $0.containerSize.height] } action: { _, new in
                size = (new[0], new[1])
            }
            .task(id: ready) {
                guard ready else { return }
                // Wait for the page to be laid out, then scroll twice in case the
                // first request lands before the scroll view is ready.
                for _ in 0..<50 where size.content <= size.container {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                try? await Task.sleep(for: .seconds(1))
                for _ in 0..<2 {
                    // Bars cover about 150 points of the screen; overlap pages by a few rows.
                    // On a phone on its side that would leave little, so move at least 70 %.
                    let target = CGFloat(page) * max(size.container - 260, size.container * 0.7)
                    if target < size.content - size.container {
                        position.scrollTo(y: target)
                    } else {
                        position.scrollTo(edge: .bottom)
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}

/// Orange sun symbols, so the sunrise and sunset arrows show in light mode too.
struct SunLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(.orange)
            configuration.title
        }
    }
}

/// While the first forecast loads: the page's cards in their places, values
/// as dashes and the cards dimmed, so the page is there at once and fills in.
private struct LoadingCards: View {
    let cards: [PageCard]
    @Environment(\.surface) private var surface

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Circle().fill(.quaternary).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Loading the forecast…")).font(.title3.weight(.semibold))
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                Divider()
                HStack(alignment: .top) {
                    value(tr("Air"), Condition.temperature.symbol, "–°")
                    Spacer()
                    value(tr("Water"), Condition.waterTemperature.symbol, "–°")
                    Spacer()
                    value(tr("Wind"), Condition.wind.symbol, "–")
                }
            }
            .padding()
            .cardBackground(surface)
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 10) {
                    Label(card.title.uppercased(), systemImage: card.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 10).fill(.quaternary).frame(height: 60)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground(surface)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Loading the forecast…"))
    }

    private func value(_ title: String, _ symbol: String, _ dash: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(dash).valueFont(size: 40).foregroundStyle(.secondary)
        }
    }
}

/// The daylight line: on one row at full size where it fits. At the standard text
/// size and smaller it may shrink a little, to 85 % at most and only when it would
/// not fit otherwise; at larger text sizes, or when even that is too long, it wraps,
/// with the time left on its own row so "6 h 58 min" never breaks apart.
private struct DaylightText: View {
    let line: Text
    var rest: Text? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 15

    var body: some View {
        ViewThatFits(in: .horizontal) {
            oneRow.lineLimit(1)
            if typeSize <= .large {
                oneRow.font(.system(size: size * 0.95)).lineLimit(1)
                oneRow.font(.system(size: size * 0.9)).lineLimit(1)
                oneRow.font(.system(size: size * 0.85)).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                line.fixedSize(horizontal: false, vertical: true)
                rest?.fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var oneRow: Text {
        if let rest { Text("\(line) · \(rest)") } else { line }
    }
}
