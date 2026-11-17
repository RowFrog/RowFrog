import CoreLocation
import SwiftUI
import TipKit

/// The first-start tour and the one-time tips. The tour shows once after
/// install and again from the settings; each tip shows the first time its
/// feature is on screen, after the tour, until the user closes it.
enum Tutorial {
    /// Set once the tour was finished or skipped. `-RWTutorialSeen YES` skips it for screenshots.
    static let seenKey = "RWTutorialSeen"
    /// Set by "Show the tour again"; the tips come back at the next launch.
    private static let resetTipsKey = "RWResetTips"

    static var seen: Bool { UserDefaults.standard.bool(forKey: seenKey) }

    /// The tour covers what is new, so "What's new" is not shown after it.
    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
        WhatsNew.markSeen()
        // No tips on the day of the tour: it has just explained the page (TipPacing).
        TipPacing.tourEnded()
    }

    /// For "Show the tour again": the tour starts over and the tips return.
    static func replay() {
        UserDefaults.standard.set(false, forKey: seenKey)
        UserDefaults.standard.set(true, forKey: resetTipsKey)
    }

    /// "Show the tips again": only the closed one-time tips return, at the next
    /// start, since TipKit forgets them only before it is configured.
    static func replayTips() {
        UserDefaults.standard.set(true, forKey: resetTipsKey)
        TipPacing.resume()
    }

    static var tipsComingBack: Bool { UserDefaults.standard.bool(forKey: resetTipsKey) }

    /// Screenshot hooks: `-RWNoTips YES` hides every tip, `-RWShowTips YES` shows them all,
    /// `-RWLaterTips YES` shows the tips that follow a closed one (all values, hour view, water estimate, route stretch, weather map).
    static func configureTips() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: resetTipsKey) {
            // TipKit only forgets closed tips before it is configured.
            try? Tips.resetDatastore()
            defaults.removeObject(forKey: resetTipsKey)
        }
        if defaults.bool(forKey: DefaultsKey.noTips) { Tips.hideAllTipsForTesting() }
        if defaults.bool(forKey: DefaultsKey.showTips) { Tips.showAllTipsForTesting() }
        // `-RWBoatTip YES` shows the boats-at-other-clubs tip, with the others hidden.
        if defaults.bool(forKey: DefaultsKey.boatTip) { Tips.showTipsForTesting([BoatsElsewhereTip.self]) }
        // `-RWPlaceTip YES` shows the tip at the place line under the club's name.
        if defaults.bool(forKey: DefaultsKey.placeTip) { Tips.showTipsForTesting([PlaceLineTip.self]) }
        // `-RWSuggestTip YES` shows the tip at "Suggest the launch point" in the Location sheet.
        if defaults.bool(forKey: DefaultsKey.suggestTip) { Tips.showTipsForTesting([SuggestLaunchPointTip.self]) }
        // `-RWNearbyTip YES` shows the nearby-water tip under the top tile, also without such a reason.
        if defaults.bool(forKey: DefaultsKey.nearbyTip) { Tips.showTipsForTesting([NearbyWaterTip.self]) }
        // `-RWRiverTip YES` shows the river current tip on a river or canal club's page.
        if defaults.bool(forKey: DefaultsKey.riverTip) { Tips.showTipsForTesting([RiverCurrentTip.self]) }
        if defaults.bool(forKey: DefaultsKey.laterTips) {
            Tips.hideTipsForTesting([TopTileTip.self, HourlyTip.self, ConditionsExtrasTip.self, WayBackTip.self, ChartScrubTip.self])
            Tips.showTipsForTesting([AllValuesTip.self, HourViewTip.self, WaterEstimateTip.self, StretchPointTip.self, WeatherMapTip.self])
        }
        // One new tip a day at most (owner's pacing, 12 Nov 2026); tips for a rare case skip it (MomentTip).
        try? Tips.configure([.displayFrequency(.daily)])
        TipPacing.update()
    }
}

// MARK: - What's new

/// A sheet shown once after an update, to users who saw the tour before.
enum WhatsNew {
    /// Raise with every new list of points.
    static let version = 2
    /// `-RWWhatsNewSeen 1000` keeps the sheet away in screenshots.
    static let seenKey = "RWWhatsNewSeen"

    static var needsShowing: Bool {
        Tutorial.seen && UserDefaults.standard.integer(forKey: seenKey) < version
    }

    static func markSeen() { UserDefaults.standard.set(version, forKey: seenKey) }

    struct Point: Hashable {
        let symbol: String
        let text: String
    }

    /// The line under the title.
    static var headline: String { tr("New since you last looked:") }

    /// Version 2 (owner, 12 Nov 2026): what people who finished the tour before would miss.
    static var points: [Point] {
        [
            Point(symbol: "figure.rower", text: tr("The boat button on the club page switches the boat for the rowing light right there.")),
            Point(symbol: "scope", text: tr("The light also looks at the water within 1 km of the launch point; the Why line says when it is rougher out there.")),
            Point(symbol: "checkmark.seal", text: tr("In the Location sheet, the club's place card from Apple Maps, with photos and opening hours.")),
            Point(symbol: "mappin.and.ellipse", text: tr("No club near you? Add a place yourself with ⋯ in the list.")),
            Point(symbol: "bookmark", text: tr("Settings › Routes shows all your saved routes.")),
            Point(symbol: "arrow.uturn.backward", text: tr("Undo in the route editor takes back the last step.")),
            Point(symbol: "chevron.down", text: tr("On a value's page, tap its title to jump to another value.")),
            Point(symbol: "square.grid.2x2", text: tr("Widgets: pick a layout with fewer values or all six, and marks in the light's dots, under Edit Widget.")),
        ]
    }
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                    Text(tr("What's new"))
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity)
                    Text(WhatsNew.headline)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    ForEach(WhatsNew.points, id: \.self) { point in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: point.symbol)
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.tint)
                                .frame(width: 30)
                            Text(point.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            Button {
                dismiss()
            } label: {
                Text(tr("Continue")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Tour

/// The tour's pages. The two choice pages only show while there is no home base,
/// the river page only with a river or canal club in the list.
enum TourPage: Int, CaseIterable, Identifiable {
    case welcome, homeBase, moreClubs, rowingLight, conditions, warnings, boats, lake, locations, wideScreen, settings, river
    var id: Int { rawValue }

    /// The order they come in; `river` is last in the enum so `-RWTutorialPage n` keeps its numbers.
    static let order: [TourPage] = [.welcome, .homeBase, .moreClubs, .rowingLight, .conditions, .warnings, .boats, .lake, .river, .locations, .wideScreen, .settings]

    var isChoice: Bool { self == .homeBase || self == .moreClubs }

    var symbol: String {
        switch self {
        case .welcome: "figure.rower"
        case .homeBase: "house.fill"
        case .moreClubs: "plus.circle.fill"
        case .rowingLight: "light.beacon.max"
        case .conditions: "thermometer.and.liquid.waves"
        case .warnings: "exclamationmark.triangle.fill"
        case .boats: "figure.rower"
        case .lake: "map.fill"
        case .river: RiverConditions.symbol
        case .locations: "list.bullet"
        case .wideScreen: "rectangle.split.2x1"
        case .settings: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .welcome, .homeBase, .moreClubs, .locations: .blue
        case .rowingLight: .green
        case .conditions, .lake, .river: .teal
        case .warnings: .orange
        case .boats: .mint
        case .wideScreen: .indigo
        case .settings: .gray
        }
    }

    var title: String {
        switch self {
        case .welcome: tr("Welcome to Row Frog")
        case .homeBase: tr("Choose your home base")
        case .moreClubs: tr("Add more clubs")
        case .rowingLight: tr("The rowing light")
        case .conditions: tr("Conditions at a glance")
        case .warnings: tr("Official warnings")
        case .boats: tr("Your boats and limits")
        case .lake: tr("Lake view and routes")
        case .river: tr("Rivers and canals")
        case .locations: tr("Your locations")
        case .wideScreen: tr("Landscape and wide screens")
        case .settings: tr("Settings")
        }
    }

    var intro: String {
        switch self {
        case .welcome: tr("Weather and a rowing forecast for your club's launch point.")
        case .homeBase: tr("It opens first when you start the app. You can change it later.")
        case .moreClubs: tr("Add the other places you row, or skip this and add clubs later in the list.")
        case .rowingLight: tr("Every page starts with the rowing light for the hour ahead.")
        // With Current conditions inside the top tile (#315), it opens into all values.
        case .conditions: AppSettings.shared.combinedTopTile
            ? tr("The tile with the light shows what matters on the water. Tap “All values” under it for the rest.")
            : tr("Below the light you find what matters on the water.")
        case .warnings: tr("Official warnings come right under the rowing light.")
        case .boats: tr("The rowing light is worked out for one boat. Switch it with the boat button on the club page.")
        case .lake: tr("Below the current conditions, the Lake view shows the whole lake.")
        case .river: tr("A river or canal club gets its own two tiles.")
        case .locations: tr("Keep all the places you row in one list.")
        case .wideScreen: tr("Turn your iPhone sideways, or use a wide screen, to see more at once.")
        case .settings: tr("Open the settings with the cog at the top of the location list.")
        }
    }

    /// Symbol and text for each point on the page.
    var points: [TourPoint] {
        switch self {
        case .welcome: [
            TourPoint(symbol: "house.fill", text: tr("Your home base opens first when you start the app.")),
            TourPoint(symbol: "hand.draw", text: tr("To change it, open the list, swipe a club to the right and tap Home base.")),
        ]
        case .homeBase, .moreClubs: []
        case .rowingLight: [
            TourPoint(symbol: "text.bubble", text: tr("The \"Why\" line names what sets the light.")),
            TourPoint(symbol: "sun.horizon", text: tr("Rowing is only advised while the sun is up.")),
            TourPoint(symbol: "clock", text: tr("Each of the next 48 hours has its own light. Tap a night's line to see its hours.")),
            TourPoint(symbol: "umbrella", text: tr("The rain tile shows DWD's radar for the next two hours, then the forecast.")),
            TourPoint(symbol: "clock.badge.exclamationmark", text: tr("Grey instead of green: the forecast is over 3 hours old. Pull down to refresh.")),
            TourPoint(symbol: "person.fill.questionmark", text: tr("The light is advice. You decide, and when in doubt you stay ashore.")),
        ]
        case .conditions: [
            TourPoint(symbol: "snowflake", text: tr("In winter, the app estimates ice on the water from frost and water temperature, checked against satellite pictures on larger lakes. Always look at the water yourself.")),
            TourPoint(symbol: "cloud.sun", text: tr("The forecast comes from the weather model that does best for your lake. The line near the end of each page names it.")),
            TourPoint(symbol: "info.circle", text: tr("Tap ⓘ on a card to see what its icons and colours mean. Settings › Help has the full legend.")),
        ]
        case .warnings: [
            TourPoint(symbol: "water.waves", text: tr("Storm warnings for the lake and weather warnings for the town.")),
            TourPoint(symbol: "text.bubble", text: tr("A warning also appears in the Why line and on the location list.")),
            TourPoint(symbol: "light.beacon.max", text: tr("On the lake, also watch the storm warning lights on the shore. The warnings card explains what they mean.")),
            TourPoint(symbol: "arrow.up.arrow.down", text: tr("The light and the warnings always stay on top. Arrange this page, at the end of each page, sorts or hides the other cards.")),
        ]
        case .boats: [
            TourPoint(symbol: "checkmark", text: tr("Small boats are picked at first. Tap Big boats if you row a four or an eight.")),
            TourPoint(symbol: "list.bullet", text: tr("Add your own boats under My boats. When it is too rough for yours, the app names one that would be fine.")),
            TourPoint(symbol: "info.circle", text: tr("ⓘ next to a boat opens its limits.")),
            TourPoint(symbol: "map", text: tr("Pick the boat that colours the lake map.")),
            TourPoint(symbol: "thermometer.snowflake", text: tr("Below %@ water a blue life-jacket badge shows; the light stays about the weather. Below %@ the advice is stricter.", Format.temperature(RowingLimit.lifeJacket.standard(for: .small)), Format.temperature(RowingLimits.coldWaterC))),
        ]
        case .lake: [
            TourPoint(symbol: "map", text: tr("The Lake view shows the light, waves and wind across the whole lake. Tap it for the full map.")),
            TourPoint(symbol: "clock", text: tr("On the map, move through the hours in the strip at the bottom and tap the water for one spot.")),
            TourPoint(symbol: "point.topleft.down.to.point.bottomright.curvepath", text: tr("Plan a route: tap your turning points to see the light along the way and the best time to start.")),
            TourPoint(symbol: "bookmark", text: tr("Save the routes you row often in the Routes menu. Settings › Routes shows them all. Share routes as a link for a browser or as a GPX file for other apps.")),
            TourPoint(symbol: "globe.europe.africa", text: tr("Below it, the latest satellite picture of the lake, with a switch to the clearest one.")),
        ]
        case .river: [
            TourPoint(symbol: "map", text: tr("The River view or Canal view shows your stretch between weirs or locks, with markers where it ends.")),
            TourPoint(symbol: RiverConditions.symbol, text: tr("The Current tile shows the nearest gauge's flow speed, water level and trend. It is amber at high water or a fast current, red when shipping is stopped or the current is too strong.")),
            TourPoint(symbol: "water.waves", text: tr("High water starts at the gauge's shipping mark I, or at mean high water where the gauge has no mark.")),
            TourPoint(symbol: "hand.tap", text: tr("Tap it for the level chart and your pace upstream and downstream.")),
        ]
        case .locations: [
            TourPoint(symbol: "hand.draw", text: tr("Swipe left and right to move between your clubs. The house marks your home base.")),
            TourPoint(symbol: "magnifyingglass", text: tr("Search the list for a club and tap + to add it, or open ⋯ to browse by country or add a place of your own.")),
            TourPoint(symbol: "arrow.up.arrow.down", text: tr("Touch and hold a club, then drag to reorder.")),
            TourPoint(symbol: "trash", text: tr("Swipe a club in the list to the left to remove it.")),
            TourPoint(symbol: "arrow.clockwise", text: tr("Pull a page or the list down to refresh.")),
            TourPoint(symbol: "apps.iphone", text: tr("A Row Frog widget on your home or lock screen shows the rowing light and rain on the radar in the next two hours.")),
        ]
        case .wideScreen: [
            TourPoint(symbol: "sidebar.left", text: tr("The location list stays on the left, the club page on the right.")),
            TourPoint(symbol: "square.grid.2x2", text: tr("The cards on the club page sit in two columns.")),
        ] + (Orientation.isPad ? [
            TourPoint(symbol: "sidebar.left", text: tr("Hide the list with the sidebar button for a wider page.")),
        ] : [
            TourPoint(symbol: "gearshape", text: tr("Prefer portrait only? Use Rotation Lock in Control Centre.")),
        ])
        case .settings: [
            TourPoint(symbol: "globe", text: tr("English or German, as the iPhone's Settings set it for Row Frog.")),
            TourPoint(symbol: "ruler", text: tr("Units for temperature, wind, waves, rain, distances and air pressure.")),
            TourPoint(symbol: "photo", text: tr("Appearance: background pictures, also your own photos, and the app icon.")),
            TourPoint(symbol: "questionmark.circle", text: tr("Settings › Help shows this tour again.")),
        ]
        }
    }
}

struct TourPoint: Hashable {
    let symbol: String
    let text: String
}

/// The swipeable tour. On first start it includes choosing the home base and
/// more clubs. `-RWTutorialPage n` opens it on page n for screenshots.
struct TutorialView: View {
    let locations: LocationStore
    let reload: () async -> Void
    let finish: () -> Void
    @State private var pages: [TourPage]
    @State private var page: TourPage
    @State private var here = DeviceLocation()
    /// Each club choice's search, kept here so it stays when the device turns.
    @State private var searches: [TourPage: String] = [:]
    // The location question is a system alert. When it closes, the paged view can
    // jump back to its first page while `page` still says otherwise, so the pager
    // is rebuilt on the current page once the answer is in.
    @State private var pagerID = 0
    @Environment(\.scenePhase) private var scenePhase

    init(locations: LocationStore, reload: @escaping () async -> Void, finish: @escaping () -> Void) {
        self.locations = locations
        self.reload = reload
        self.finish = {
            TourProgress.clear()
            finish()
        }
        // A tour already running goes on where it was: on a first start the view
        // behind it changes once the home base is picked, which builds it again.
        let pages = TourProgress.pages ?? TourPage.order.filter { locations.homeID == nil || !$0.isChoice }
        let start = TourProgress.page ?? TourPage(rawValue: UserDefaults.standard.integer(forKey: DefaultsKey.tutorialPage)) ?? .welcome
        TourProgress.pages = pages
        _pages = State(initialValue: pages)
        _page = State(initialValue: pages.contains(start) ? start : pages[0])
    }

    var body: some View {
        // The river page comes and goes with the clubs picked on the first two pages.
        let hasRiver = locations.saved.contains { locations.lake(of: $0)?.section != nil }
        let pages = self.pages.filter { $0 != .river || hasRiver }
        let index = pages.firstIndex(of: page) ?? 0
        let isLast = index == pages.count - 1
        let needsHome = locations.homeID == nil
        let go = { (target: Int) in withAnimation { page = pages[max(0, min(pages.count - 1, target))] } }
        // Upright, Next and the dots sit under the pages; wider than tall, under the left column
        // (TourLayout.swift). Turning the device switches at once and keeps the page.
        GeometryReader { proxy in
            let columns = TourColumns(size: proxy.size)
            let bottom = VStack(spacing: 12) {
                TourDots(count: pages.count, index: index, go: go)
                Button {
                    if isLast { finish() } else { go(index + 1) }
                } label: {
                    Text(isLast ? tr("Let's row") : tr("Next"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(page == .homeBase && needsHome)
                .accessibilityIdentifier("tour-next")
            }
            .padding(.bottom, 8)
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    // Skipping still asks for a home base first.
                    Button(tr("Skip")) {
                        if needsHome { withAnimation { page = .homeBase } } else { finish() }
                    }
                    .opacity(isLast || page.isChoice ? 0 : 1)
                    .disabled(isLast || page.isChoice)
                    .accessibilityIdentifier("tour-skip")
                }
                .padding(.horizontal)
                TabView(selection: $page) {
                    ForEach(pages) { page in
                        Group {
                            if page.isChoice {
                                ClubChoicePage(page: page, locations: locations, near: here.coordinate, reload: reload,
                                           search: Binding(get: { searches[page] ?? "" }, set: { searches[page] = $0 }))
                            } else {
                                TourPageView(page: page)
                            }
                        }
                        .tag(page)
                    }
                }
                // Its own dots (TourDots), so on a wide screen they can sit under the left column.
                .tabViewStyle(.page(indexDisplayMode: .never))
                .id(pagerID)
                .onChange(of: scenePhase) { old, new in
                    if new == .active, old != .active, here.askedForPermission {
                        here.askedForPermission = false
                        pagerID += 1
                    }
                }
                // On an iPad the app can stay active under the location question.
                .onChange(of: here.answers) { pagerID += 1 }
                .task(id: page) {
                    // Ask for the location when choosing the home base, for clubs nearby.
                    if page == .homeBase { here.request() }
                }
                .onChange(of: page) {
                    TourProgress.page = page
                    // The river page says what the tip would: no tip later for a river club picked now.
                    if page == .river { RiverCurrentTip().invalidate(reason: .actionPerformed) }
                    // No swiping past the home base choice without one.
                    if locations.homeID == nil, page.rawValue > TourPage.homeBase.rawValue {
                        withAnimation { page = .homeBase }
                    }
                }
                if columns == nil {
                    bottom.padding(.horizontal)
                }
            }
            .overlay(alignment: .bottom) {
                if let columns {
                    bottom
                        .frame(width: columns.left)
                        .offset(x: -(columns.gap + columns.right) / 2)
                }
            }
            .environment(\.tourColumns, columns)
        }
        .padding(.top, 8)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .environment(\.locale, AppSettings.shared.locale)
    }
}

private struct TourPageView: View {
    let page: TourPage
    @Environment(\.tourColumns) private var columns

    var body: some View {
        if let columns {
            // Wide: the head in the middle of the left column, the content right at full height.
            HStack(alignment: .top, spacing: columns.gap) {
                TourSideColumn(columns: columns, alignment: .leading) {
                    head(leading: true, short: columns.short)
                }
                ScrollView {
                    content
                        .padding(.vertical, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: columns.right)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Upright: the whole page scrolls between Skip and the dots with Next.
            ScrollView {
                VStack(spacing: 20) {
                    head(leading: false, short: false)
                    content
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func head(leading: Bool, short: Bool) -> some View {
        VStack(alignment: leading ? .leading : .center, spacing: short ? 10 : 20) {
            Image(systemName: page.symbol)
                .font(.system(size: short ? 36 : 60))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(page.tint)
                .frame(height: short ? 44 : 76)
                .accessibilityHidden(true)
            VStack(alignment: leading ? .leading : .center, spacing: 8) {
                Text(page.title)
                    .font(short ? .title2.bold() : .title.bold())
                Text(page.intro)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(leading ? .leading : .center)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    private var content: some View {
        VStack(spacing: 20) {
            extra
            VStack(alignment: .leading, spacing: 10) {
                ForEach(page.points, id: \.text) { point in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: point.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(page.tint)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        Text(point.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// A small picture of the feature: the language choice, the three lights, the condition icons.
    @ViewBuilder private var extra: some View {
        switch page {
        case .welcome:
            // The app speaks the iPhone's language (Settings › Row Frog › Language);
            // its own choice is for the developer options only.
            if AppSettings.shared.developerOptions {
            VStack(spacing: 8) {
                Label(tr("Language"), systemImage: "globe")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker(tr("Language"), selection: Binding(get: { AppSettings.shared.language }, set: { AppSettings.shared.language = $0 })) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            }
        case .rowingLight:
            HStack(alignment: .top, spacing: 8) {
                ForEach([Light.green, .amber, .red], id: \.self) { light in
                    VStack(spacing: 8) {
                        TrafficLightDot(light: light, size: 30)
                        Text(light.title)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(light.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        case .conditions:
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
                ForEach(Condition.allCases) { condition in
                    HStack(spacing: 8) {
                        ConditionIcon(condition: condition)
                            .foregroundStyle(page.tint)
                            .frame(width: 24)
                        Text(condition.title)
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        case .homeBase, .moreClubs, .warnings, .boats, .lake, .river, .locations, .wideScreen, .settings:
            EmptyView()
        }
    }
}

// MARK: - Location for nearby clubs

/// Where a running tour is, kept outside the view so the tour goes on where it
/// was when it is built again.
private enum TourProgress {
    static var pages: [TourPage]?
    static var page: TourPage?

    static func clear() {
        pages = nil
        page = nil
    }
}

/// The device's location, asked for only while the app is in use and only to
/// suggest clubs nearby. Stays nil when the user says no.
@Observable
final class DeviceLocation: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: Coordinate?
    /// Set when the system alert asking for the location was shown.
    var askedForPermission = false
    /// Counts the answers to that alert.
    private(set) var answers = 0
    @ObservationIgnored private var waitingForAnswer = false
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            askedForPermission = true
            waitingForAnswer = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if waitingForAnswer, manager.authorizationStatus != .notDetermined {
            waitingForAnswer = false
            answers += 1
        }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        coordinate = Coordinate(lat: last.coordinate.latitude, lon: last.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension View {
    /// Keeps `visible` in step with whether the tip should show, so a closed
    /// tip leaves no empty space or row behind.
    func tipVisibility<T: Tip>(_ tip: T, _ visible: Binding<Bool>) -> some View {
        task {
            for await shouldDisplay in tip.shouldDisplayUpdates {
                withAnimation { visible.wrappedValue = shouldDisplay }
            }
        }
    }
}
