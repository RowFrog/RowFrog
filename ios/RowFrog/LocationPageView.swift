import SwiftUI
import TipKit

/// One full-screen location page: the rowing light now (with wind and
/// daylight), DWD warnings while one is issued, then the cards in the order
/// the user arranged (current conditions, rain radar, lake view, the next
/// 48 hours, launch point, satellite picture), the forecast source and credits.
struct LocationPageView: View {
    let club: Club
    let lake: Lake?
    let isHome: Bool
    let forecasts: ForecastStore
    @Environment(\.surface) private var surface
    @AppStorage(Tutorial.seenKey) private var tourSeen = false
    @State private var showHourlyTip = false
    @State private var showLaunchPointTip = false
    @State private var showConditionsTip = false
    @State private var showLakeViewTip = false
    @State private var arranging = UserDefaults.standard.bool(forKey: "RWArrange")
    /// Where the hourly table and its day headers are on screen, for the header that stays at the top.
    /// Screen coordinates: in landscape the scroll view's own space leaves out the side inset,
    /// which put the header beside the table.
    /// Where the hourly table is while the page scrolls. Kept in its own object
    /// that only the sticky header reads, so scrolling redraws the header and
    /// not the whole page on every frame (which drained the battery).
    @State private var sticky = StickyHourly()
    /// The refresh failure explained after a tap on its line.
    @State private var showingFailure: RefreshFailure?
    @State private var showRainRadarTip = false
    @State private var showSatelliteTip = false
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
    private let waterEstimateTip = WaterEstimateTip()
    @State private var showWaterEstimateTip = false
    @State private var showTopTileTip = false

    var body: some View {
        let forecast = forecasts.forecasts[club.id]
        GeometryReader { geometry in
            // Wide screens (an unfolded iPhone Duo, an iPhone on its side) put the
            // cards below the rowing light in two columns; phones upright keep one.
            let twoColumns = geometry.size.width >= Self.twoColumnWidth
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        if let forecast, let now = forecast.current() {
                            NowCard(hour: now, forecast: forecast, stale: forecast.isStale(), lakeName: lake?.name, town: club.town, club: club)
                            if tourSeen && showTopTileTip {
                                TipView(topTileTip)
                            }
                            if let warnings = forecast.warnings, !warnings.checked || !warnings.items.isEmpty {
                                WarningsCard(warnings: warnings, lakeName: lake?.name, town: club.town, checkedAt: forecast.generatedAt)
                                    .id("warnings")
                            }
                            let cards = AppSettings.shared.pageLayout(for: club.id).visible
                            Group {
                                if twoColumns {
                                    BalancedColumns {
                                        ForEach(cards) { pageCard($0, forecast: forecast, now: now) }
                                    }
                                } else {
                                    ForEach(cards) { pageCard($0, forecast: forecast, now: now) }
                                }
                            }
                            // The satellite card is empty until its picture has loaded, and an
                            // empty view never runs its own .task, so the cards load it here.
                            .task(id: forecast.lakeId) { await SatellitePictureStore.shared.load(forecast.lakeId) }
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
                            credits(forecast)
                        } else if let failure = forecasts.failures[club.id] {
                            ContentUnavailableView {
                                Label(tr("No forecast"), systemImage: "icloud.slash")
                            } description: {
                                Text(failure.explanation)
                            } actions: {
                                Button(tr("Try again")) { Task { await forecasts.load(club.id, force: true) } }
                            }
                        } else {
                            ProgressView().padding(.top, 40)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                    .frame(maxWidth: Self.maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .onPreferenceChange(HourlyFrameKey.self) { frame in
                        if sticky.hourlyFrame != frame { sticky.hourlyFrame = frame }
                    }
                    .onPreferenceChange(DayTopKey.self) { tops in
                        if sticky.dayTops != tops { sticky.dayTops = tops }
                    }
                }
                .overlay(alignment: .top) {
                    if let forecast { stickyHourlyHeader(forecast) }
                }
                .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: "RWScrollPage"), ready: forecast != nil))
                .refreshable { await forecasts.load(club.id, force: true) }
                .tipVisibility(conditionsTip, $showConditionsTip)
                .tipVisibility(lakeViewTip, $showLakeViewTip)
                .tipVisibility(rainRadarTip, $showRainRadarTip)
                .tipVisibility(satelliteTip, $showSatelliteTip)
                .tipVisibility(sourceTip, $showSourceTip)
                .tipVisibility(hourlyTip, $showHourlyTip)
                .tipVisibility(launchPointTip, $showLaunchPointTip)
                .tipVisibility(topTileTip, $showTopTileTip)
                .tipVisibility(waterEstimateTip, $showWaterEstimateTip)
                .tipVisibility(radarMapTip, $showRadarMapTip)
                .tipVisibility(hourViewTip, $showHourViewTip)
                .sheet(isPresented: $arranging) { ArrangePageSheet(club: club) }
                .task {
                    await forecasts.load(club.id)
                    // Screenshot hook: `-RWScrollTo hourly` (or `warnings`, `radar`, `conditions`, `lakeview`,
                    // `launchpoint`, `satellite`, `source`, `arrange`, or `hourly-1` for the table's second day)
                    // scrolls to that card.
                    if let target = UserDefaults.standard.string(forKey: "RWScrollTo") {
                        // The lake view loads after the forecast and pushes the cards below it down,
                        // so for cards that may be below it scroll again once it has settled.
                        let early = ["warnings", "conditions"].contains(target)
                        for wait in early ? [300] : [2500, 3000, 3000] {
                            try? await Task.sleep(for: .milliseconds(wait))
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pageCard(_ card: PageCard, forecast: ClubForecast, now: ForecastHour) -> some View {
        switch card {
        case .radar:
            VStack(spacing: 16) {
                // The map tip follows once the radar tip is closed.
                if tourSeen && showRainRadarTip {
                    TipView(rainRadarTip)
                } else if tourSeen && showRadarMapTip {
                    TipView(radarMapTip)
                }
                RainRadarCard(point: club.launchPoint, clubID: club.id)
            }
            .id("radar")
        case .conditions:
            VStack(spacing: 16) {
                if tourSeen && showConditionsTip {
                    TipView(conditionsTip)
                } else if tourSeen && showWaterEstimateTip && forecast.waterTemperature == nil && forecast.waterEstimate?.reading != nil {
                    // Only where no station measures the water.
                    TipView(waterEstimateTip)
                }
                ConditionsCard(forecast: forecast, hour: now, club: club)
            }
            .id("conditions")
        case .lakeView:
            if lake?.hasOutline != false {
                VStack(spacing: 16) {
                    if tourSeen && showLakeViewTip {
                        TipView(lakeViewTip)
                    }
                    LakeViewCard(lakeID: forecast.lakeId, clubID: club.id)
                }
                .id("lakeview")
            }
        case .hourly:
            // Each tip sits above its card and scrolls with it.
            VStack(spacing: 16) {
                if tourSeen && showHourlyTip {
                    TipView(hourlyTip)
                } else if tourSeen && showHourViewTip {
                    TipView(hourViewTip)
                }
                HourlyCard(forecast: forecast, club: club, lake: lake, stale: forecast.isStale())
                    .modifier(StickyHourlyCut(sticky: sticky))
            }
            .id("hourly")
        case .launchPoint:
            VStack(spacing: 16) {
                if tourSeen && showLaunchPointTip {
                    TipView(launchPointTip)
                }
                LaunchPointMapCard(club: club)
            }
            .id("launchpoint")
        case .satellite:
            if lake?.hasOutline != false {
                VStack(spacing: 16) {
                    if tourSeen && showSatelliteTip {
                        TipView(satelliteTip)
                    }
                    SatellitePictureCard(lakeID: forecast.lakeId, clubID: club.id)
                }
                .id("satellite")
            }
        }
    }

    /// The hourly table's header, kept at the top of the screen while the
    /// table is scrolled through, with the day being looked at.
    private func stickyHourlyHeader(_ forecast: ClubForecast) -> some View {
        StickyHourlyHeader(sticky: sticky)
    }
}

/// Where the hourly table and its days are on the screen.
@Observable
private final class StickyHourly {
    var hourlyFrame: CGRect = .zero
    var dayTops: [Date: CGFloat] = [:]
    /// Where the header stays on the screen, in global coordinates.
    var top: CGFloat = 0

    /// Whether the header is staying at the top.
    func isShowing(at top: CGFloat) -> Bool {
        hourlyFrame.height > 0 && hourlyFrame.minY + 40 < top && hourlyFrame.maxY > top
    }

    /// How far up the last rows have pushed the header (0 or less).
    func push(at top: CGFloat) -> CGFloat {
        min(0, hourlyFrame.maxY - top - HourlyStickyHeader.height)
    }
}

/// While the header stays, the tile ends at it: the rows scroll away under the
/// header instead of showing beside its rounded corners, as in the Weather app.
private struct StickyHourlyCut: ViewModifier {
    let sticky: StickyHourly

    func body(content: Content) -> some View {
        let showing = sticky.isShowing(at: sticky.top)
        let cut = showing ? max(0, sticky.top + sticky.push(at: sticky.top) - sticky.hourlyFrame.minY) : 0
        // Rounded at the cut like the header's top, so nothing of the tile shows
        // beside the header's corners.
        let radius: CGFloat = showing ? 16 : 0
        content.mask(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius).padding(.top, cut)
        }
    }
}

/// The hourly table's header while the table is under the top of the screen.
private struct StickyHourlyHeader: View {
    let sticky: StickyHourly

    var body: some View {
        let hourlyFrame = sticky.hourlyFrame, dayTops = sticky.dayTops
        GeometryReader { geo in
            let top = geo.frame(in: .global).minY
            let height = HourlyStickyHeader.height
            Color.clear
                .onAppear { sticky.top = top }
                .onChange(of: top) { _, new in sticky.top = new }
            if sticky.isShowing(at: top) {
                let day = dayTops.filter { $0.value <= top + height }.max { $0.value < $1.value }?.key
                    ?? dayTops.keys.min()
                // At the end of the table the last rows push the header up and away,
                // instead of it vanishing while rows are still under it.
                let push = sticky.push(at: top)
                HourlyStickyHeader(day: day)
                    .frame(width: hourlyFrame.width)
                    // Cut to the tile's shape, so its square bottom corners round off
                    // with the tile's own corners as it leaves.
                    .mask(alignment: .top) {
                        RoundedRectangle(cornerRadius: 16)
                            .frame(height: hourlyFrame.height)
                            .offset(y: hourlyFrame.minY - top - push)
                    }
                    .offset(x: hourlyFrame.minX - geo.frame(in: .global).minX, y: push)
                    .transition(.opacity)
            }
        }
        // Not clipped: when the last rows push the header up, it slides on under
        // the status bar together with the tile's cut edge.
        .frame(height: HourlyStickyHeader.height)
        .allowsHitTesting(false)
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
        .background(surface.label, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func sourceLine(_ forecast: ClubForecast) -> some View {
        if let source = forecast.forecastSource {
            VStack(spacing: 16) {
                if tourSeen && showSourceTip {
                    TipView(sourceTip)
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

    /// From this width (in points) the page shows two columns of cards.
    static let twoColumnWidth: CGFloat = 600
    /// Keeps lines readable on very wide screens.
    static let maxContentWidth: CGFloat = 1000

    private var header: some View {
        VStack(spacing: 4) {
            if isHome {
                Label(tr("Home base"), systemImage: "house.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(club.displayName)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text([lake?.name, club.town].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
            if !club.launchPointVerified {
                Label(tr("Launch point not yet confirmed"), systemImage: "mappin.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let forecast = forecasts.forecasts[club.id] {
                let updated = forecast.generatedAt
                if forecast.isStale() {
                    // Old data must not look current: say so plainly, with the day.
                    Label(tr("Forecast out of date: from %@. Pull down to refresh, and check the conditions yourself.", Format.dayTime(updated)), systemImage: "clock.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else if let failure = forecasts.failures[club.id] {
                    // Tap for why, whose side it is on, and what helps.
                    Button { showingFailure = failure } label: {
                        Label {
                            Text(tr("Could not update: %@. Showing data from %@.", failure.short, Format.time(updated)))
                                + Text(" ") + Text(Image(systemName: "info.circle"))
                        } icon: {
                            Image(systemName: "wifi.exclamationmark")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(tr("Updated %@ · Pull down to refresh", Format.time(updated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if forecast.isSlowRefresh {
                    // Opening the club counts it as used; the next server run renews it every half hour.
                    Label(tr("Nobody opened this club lately, so it updates less often. From the next server run, within about 30 minutes, it updates every half hour."), systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, surface.hasPicture ? 16 : 0)
        .padding(.vertical, surface.hasPicture ? 10 : 0)
        .background(surface.label, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 24)
        .alert(tr("Could not update"), isPresented: Binding(get: { showingFailure != nil }, set: { if !$0 { showingFailure = nil } }),
               presenting: showingFailure) { _ in
            Button(tr("Try again")) { Task { await forecasts.load(club.id, force: true) } }
            Button(tr("OK"), role: .cancel) {}
        } message: { failure in
            Text(failure.explanation)
        }
    }
}

struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    /// Shows an ⓘ in the title row that opens this part of the legend.
    var legend: LegendPart? = nil
    @ViewBuilder var content: Content
    @Environment(\.surface) private var surface
    @State private var showingLegend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack {
                    Label(title.uppercased(), systemImage: symbol ?? "")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if legend != nil {
                        Spacer(minLength: 0)
                        LegendButton(showing: $showingLegend)
                    }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(surface)
        .sheet(isPresented: $showingLegend) {
            if let legend { LegendSheet(part: legend) }
        }
    }
}

/// The ⓘ that opens a card's part of the legend.
struct LegendButton: View {
    @Binding var showing: Bool

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle").font(.subheadline)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityLabel(tr("What the symbols mean"))
    }
}

/// The rowing light now, why, and the values that matter most: air, water
/// and wind big; waves, rain, visibility (and ice when it matters) small;
/// whether DWD warns; and how much daylight is left.
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
    @State private var showingLights = UserDefaults.standard.string(forKey: "RWLegend") == "lights"
    @State private var showingWarnings = false
    @State private var showingDaylight = false
    /// A value of the tile tapped for its chart; swiping there stays within the tile's values.
    @State private var openCondition: Condition?

    private var water: WaterTemperature? { forecast.waterTemperature }

    var body: some View {
        Card {
            HStack(spacing: 14) {
                TrafficLightDot(light: hour.light, size: 36, stale: stale)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(hour.light.title(stale: stale)).font(.title2.bold())
                        LegendButton(showing: $showingLights)
                    }
                    if at == nil {
                        // Tapped: pick another boat, with the light each would get now.
                        BoatMenu(hour: hour, waterC: water?.celsius) {
                            HStack(spacing: 3) {
                                Text(tr("For %@", AppSettings.shared.selectedBoat.inSentence))
                                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel(tr("For %@", AppSettings.shared.selectedBoat.inSentence))
                        .accessibilityHint(tr("Picks another boat for the rowing light."))
                    } else {
                        Text(tr("For %@", AppSettings.shared.selectedBoat.inSentence))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    SkyIcon(sky: Sky(hour: hour), night: hour.sunUp == false).font(.system(size: 34))
                    Text(Sky(hour: hour).title).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if stale {
                    Label(tr("The forecast is more than 3 hours old. Check the conditions yourself before you go out."), systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                if hour.reasons.isEmpty {
                    Label(tr("All conditions are within the limits."), systemImage: "checkmark.circle")
                } else {
                    ForEach(hour.reasons, id: \.self) { reason in
                        Label(reason.explanation, systemImage: reason.symbol)
                            .foregroundStyle(reason.light == .red ? Color.red : Color.orange)
                    }
                }
                ForEach(hour.notes ?? [], id: \.self) { note in
                    Label(note.noteText, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                if let steadier = SteadierBoat.suggestion(for: hour, water: water?.celsius) {
                    Label(steadier.light == .green
                          ? tr("A steadier boat helps: %@ would be green now.", steadier.boat.title)
                          : tr("A steadier boat helps: %@ would only need care now.", steadier.boat.title),
                          systemImage: "figure.rower")
                        .foregroundStyle(.tint)
                }
                if at == nil { warningsLine }
            }
            .font(.subheadline)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel(hour.reasons.isEmpty ? tr("Why: all conditions within the limits") : tr("Why: %@", hour.reasons.map(\.explanation).joined(separator: " ")))
            AdviceOnlyNote()
            Divider()
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    opens(.temperature) {
                        TemperatureView(condition: .temperature, celsius: hour.temperatureC, size: 44)
                    }
                    if let feels = hour.apparentTemperatureC {
                        opens(.feelsLike) {
                            Label(tr("Feels like %@", Format.degrees(feels)), systemImage: Condition.feelsLike.symbol)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(tr("Feels like %@", Format.temperature(feels)) + ". " + (feelsLikeNote(hour) ?? ""))
                        }
                    }
                }
                Spacer()
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
                Spacer()
                opens(.wind) { WindView(hour: hour, size: 28) }
            }
            HStack(alignment: .top) {
                opens(.waves) {
                    MetricView(title: tr("Waves"), symbol: Condition.waves.symbol, value: Format.waves(hour.waveHeightM), size: 17)
                }
                Spacer()
                opens(.precipitation) {
                    MetricView(title: tr("Rain, hail"), symbol: Condition.precipitation.symbol, value: precipitationText(hour) ?? tr("None"), size: 17)
                }
                Spacer()
                opens(.visibility) {
                    MetricView(title: tr("Visibility"), symbol: Condition.visibility.symbol, value: Format.distance(hour.visibilityM), size: 17)
                }
                if let ice = iceValue {
                    Spacer()
                    opens(.ice) { MetricView(title: tr("Ice"), symbol: Condition.ice.symbol, value: ice, size: 17) }
                }
            }
            .symbolRenderingMode(.hierarchical)
            daylightLine
        }
        .sheet(isPresented: $showingLights) { LegendSheet(part: .lights) }
        .sheet(isPresented: $showingWarnings) {
            if let warnings = forecast.warnings {
                NoWarningSheet(warnings: warnings, lakeName: lakeName, town: town, checkedAt: forecast.generatedAt)
            }
        }
        .sheet(isPresented: $showingDaylight) {
            ConditionDetailView(condition: .daylight, data: ConditionData(forecast: forecast, now: hour), club: club)
        }
        .sheet(item: $openCondition) { condition in
            ConditionDetailView(condition: condition, data: ConditionData(forecast: forecast, now: hour), order: tileValues, club: club)
        }
        .onChange(of: openCondition != nil) { _, open in if open { TopTileTip().invalidate(reason: .actionPerformed) } }
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
        Button { openCondition = condition } label: { content().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Opens a chart and more about this value"))
    }

    private var iceValue: String? { forecast.iceValue }

    /// While DWD has no warning, one line says so; the warnings card itself
    /// only shows while a warning is issued or DWD could not be checked.
    @ViewBuilder
    private var warningsLine: some View {
        if let warnings = forecast.warnings, warnings.checked, warnings.items.isEmpty {
            Button { showingWarnings = true } label: {
                HStack(spacing: 6) {
                    Label(tr("No DWD warning"), systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("· " + tr("checked %@", Format.time(forecast.generatedAt)))
                        .foregroundStyle(.secondary)
                    Image(systemName: "info.circle").foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Shows what was checked and what the shore warning lights mean"))
        }
    }

    /// One line with a small sun path: daylight left, or when it comes back.
    @ViewBuilder
    private var daylightLine: some View {
        if let sun = forecast.sunState(at: at ?? .now) {
            Button { showingDaylight = true } label: {
                HStack(spacing: 8) {
                    switch sun {
                    case let .up(sunrise, sunset):
                        SunPath(sunrise: sunrise, sunset: sunset, lineWidth: 1.5).frame(width: 44, height: 20)
                        Text(tr("Sunset %@ · %@ of daylight left", Format.time(sunset), Format.duration(from: at ?? .now, to: sunset)))
                    case let .down(sunrise, _):
                        Image(systemName: "moon.stars.fill").foregroundStyle(.secondary).frame(width: 44)
                        Text(tr("Sun is down · rowing advised again from %@", Format.time(sunrise)))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Opens sunrise, sunset and daylight"))
        }
    }
}

/// Wind now as mean–gust with an arrow pointing where the wind blows.
private struct WindView: View {
    let hour: ForecastHour
    var size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(tr("Wind"), systemImage: Condition.wind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(hour.windSpeedMs.map { "\(Format.windNumber($0))–\(Format.windNumber(hour.windGustMs))" } ?? "–")
                    .font(.system(size: size, weight: .light))
                if let from = hour.windFromDeg {
                    Image(systemName: "arrow.up")
                        .font(.system(size: size * 0.6, weight: .semibold))
                        .rotationEffect(.degrees(from + 180))
                }
            }
            Text(AppSettings.shared.windUnit.symbol + (hour.windFromDeg.map { " · " + tr("from %@", Format.compass($0)) } ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the "No DWD warning" line opens: what was checked and the shore lights.
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
            .navigationTitle(tr("DWD warnings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
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
                .font(.system(size: size, weight: .light))
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A value with the icon and word that say what it is, matching TemperatureView.
struct MetricView: View {
    let title: String
    let symbol: String
    let value: String
    var size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: size, weight: .light))
        }
        .accessibilityElement(children: .combine)
    }
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
private enum Column {
    /// Wider for "10:00 PM" than for "22:00".
    static var time: CGFloat { AppSettings.shared.timeFormat.usesAMPM ? 64 : 44 }
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
    @State private var openHour: ForecastHour?

    var body: some View {
        Card(title: tr("Next 48 hours"), symbol: "clock", legend: .hourly) {
            HourlyLegendHeader()
            ForEach(Array(days.enumerated()), id: \.element.id) { index, group in
                DayHeader(day: group.day, sun: sunDay(on: group.day))
                    // Screenshot hook: `-RWScrollTo hourly-1` scrolls to the second day.
                    .id("hourly-\(index)")
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: DayTopKey.self, value: [group.day: geo.frame(in: .global).minY])
                        }
                    }
                ForEach(group.hours) { hour in
                    Button { openHour = hour } label: {
                        HourRow(hour: hour, stale: stale).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(tr("Opens this hour with all its values"))
                }
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
            let n = UserDefaults.standard.integer(forKey: "RWOpenHour")
            if n > 0, forecast.hours.indices.contains(n) {
                try? await Task.sleep(for: .milliseconds(800))
                openHour = forecast.hours.sorted { $0.time < $1.time }[n]
            }
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let hours: [ForecastHour]
        var id: Date { day }
    }

    private var days: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: forecast.hours) { calendar.startOfDay(for: $0.time) }
        return grouped.keys.sorted().map { DayGroup(day: $0, hours: grouped[$0]!.sorted { $0.time < $1.time }) }
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
        // The tile's own colour; material only where the tile itself is glass.
        // Rounded at the top like the tile, square at the bottom where the rows start,
        // so the header keeps its shape when it starts to stay.
        .background(surface == .glass ? AnyShapeStyle(.regularMaterial) : surface.card,
                    in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

/// The icon legend over the hourly table: one icon and unit per column.
private struct HourlyLegendHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock").frame(width: Column.time, alignment: .leading)
                .accessibilityLabel(tr("Time"))
            Image(systemName: "circle.fill").font(.system(size: 8)).frame(width: Column.light)
                .accessibilityLabel(tr("Rowing light"))
            Image(systemName: "cloud.sun").frame(width: Column.sky)
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

private struct HourRow: View {
    let hour: ForecastHour
    var stale = false

    var body: some View {
        let dark = hour.sunUp == false
        HStack(spacing: 6) {
            Text(Format.time(hour.time))
                .frame(width: Column.time, alignment: .leading)
            TrafficLightDot(light: hour.light, size: 12, stale: stale).frame(width: Column.light)
            SkyIcon(sky: Sky(hour: hour), night: dark)
                .font(.callout)
                .frame(width: Column.sky)
            cell(Format.degrees(hour.temperatureC).replacingOccurrences(of: "°", with: ""))
            cell(Format.degrees(hour.apparentTemperatureC).replacingOccurrences(of: "°", with: ""))
                .foregroundStyle(.secondary)
            cell(hour.windSpeedMs.map { "\(Format.windNumber($0))–\(Format.windNumber(hour.windGustMs))" } ?? "–")
            cell(Format.wavesNumber(hour.waveHeightM))
            cell(Format.rainNumber(hour.precipitationMm))
                .foregroundStyle((hour.precipitationMm ?? 0) >= 0.1 ? Color.blue : .primary)
            cell(Format.distanceNumber(hour.visibilityM))
                .foregroundStyle(hour.light(for: ["fog"]).map(\.color) ?? .primary)
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .opacity(dark ? 0.6 : 1)
        .padding(.vertical, 2)
    }

    private func cell(_ text: String) -> some View {
        Text(text).frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// One hour from the table with everything known about it: the rowing light
/// and main values, all the conditions tiles, the rain radar while the hour
/// is within its 2 hours, and the lake map at that hour.
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
                    NowCard(hour: hour, forecast: forecast, at: hour.time, club: club)
                    // The radar reaches 2 hours ahead; later hours have the forecast rain in the tiles.
                    if hour.time.timeIntervalSinceNow < 2 * 3600 {
                        RainRadarCard(point: club.launchPoint, clubID: club.id)
                    }
                    ConditionsCard(forecast: forecast, hour: hour, club: club)
                    if lake?.hasOutline != false, lakeViews.views[forecast.lakeId] != nil {
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
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
            .fullScreenCover(isPresented: $showingLakeMap) {
                if let view = lakeViews.views[forecast.lakeId] {
                    LakeMapScreen(view: view, clubID: club.id, at: hour.time)
                }
            }
        }
    }
}

/// Which part of the legend a card's ⓘ opens; `.all` in the settings.
enum LegendPart: String {
    case lights, conditions, hourly, all
}

/// The legend, or the part of it one card needs.
struct LegendSheet: View {
    let part: LegendPart
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if part == .lights || part == .all { lights }
                    if part == .all { Divider() }
                    if part == .conditions || part == .all { symbols; conditionIcons(Condition.tileOrder) }
                    if part == .all { Divider() }
                    if part == .hourly || part == .all { columns }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
        }
        .presentationDetents(part == .all ? [.large] : [.medium, .large])
    }

    private var title: String {
        switch part {
        case .lights: tr("Rowing light")
        case .conditions: tr("Weather symbols")
        case .hourly: tr("The columns")
        case .all: tr("Legend")
        }
    }

    private var lights: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([Light.green, .amber, .red], id: \.self) { light in
                HStack(alignment: .top, spacing: 10) {
                    TrafficLightDot(light: light).frame(width: 24)
                    Text(light.title).font(.subheadline)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                TrafficLightDot(light: .green, stale: true).frame(width: 24)
                Text(tr("Forecast out of date: more than 3 hours old. Amber and red still show.")).font(.subheadline)
            }
            AdviceOnlyNote()
        }
    }

    private var symbols: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Weather symbols")).font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(Sky.allCases, id: \.self) { sky in
                    HStack(spacing: 8) {
                        SkyIcon(sky: sky).frame(width: 24)
                        Text(sky.title).font(.caption)
                    }
                }
            }
            Text(tr("At night the sun becomes a moon and the row is dimmed.")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func conditionIcons(_ conditions: [Condition]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(conditions) { c in
                HStack(alignment: .top, spacing: 10) {
                    ConditionIcon(condition: c).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.unit.isEmpty ? c.title : "\(c.title) (\(c.unit))").font(.subheadline.weight(.semibold))
                        Text(c.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The hourly table's columns from left to right.
    private var columns: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock").frame(width: 24)
                Text(tr("Time; the hour starts here.")).font(.subheadline)
            }
            HStack(alignment: .top, spacing: 10) {
                TrafficLightDot(light: .green, size: 12).frame(width: 24)
                Text(tr("Rowing light for your boat in that hour.")).font(.subheadline)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "cloud.sun").frame(width: 24)
                Text(tr("Weather symbol; it also shows how cloudy it is.")).font(.subheadline)
            }
            conditionIcons([.temperature, .feelsLike, .wind, .waves, .precipitation, .visibility])
            Text(tr("Hours after sunset are dimmed. Tap an hour to see all its values.")).font(.caption).foregroundStyle(.secondary)
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
        if #available(iOS 18.0, *), page > 0 {
            content.modifier(PagedScroll(page: page, ready: ready))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
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
