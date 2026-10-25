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
    }

    /// For "Show the tour again": the tour starts over and the tips return.
    static func replay() {
        UserDefaults.standard.set(false, forKey: seenKey)
        UserDefaults.standard.set(true, forKey: resetTipsKey)
    }

    /// Screenshot hooks: `-RWNoTips YES` hides every tip, `-RWShowTips YES` shows them all,
    /// `-RWLaterTips YES` shows the tips that follow a closed one (radar map, hour view, water estimate, route stretch).
    static func configureTips() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: resetTipsKey) {
            // TipKit only forgets closed tips before it is configured.
            try? Tips.resetDatastore()
            defaults.removeObject(forKey: resetTipsKey)
        }
        if defaults.bool(forKey: "RWNoTips") { Tips.hideAllTipsForTesting() }
        if defaults.bool(forKey: "RWShowTips") { Tips.showAllTipsForTesting() }
        if defaults.bool(forKey: "RWLaterTips") {
            Tips.hideTipsForTesting([RainRadarTip.self, HourlyTip.self, ConditionsExtrasTip.self, CloseLoopTip.self])
            Tips.showTipsForTesting([RadarMapTip.self, HourViewTip.self, WaterEstimateTip.self, StretchPointTip.self])
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

// MARK: - What's new

/// A sheet shown once after an update, to users who saw the tour before.
enum WhatsNew {
    /// Raise with every new list of points.
    static let version = 1
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

    static var points: [Point] {
        [
            Point(symbol: "arrow.left.arrow.right", text: tr("The way out and the way back lie side by side, each coloured for the time you row it.")),
            Point(symbol: "figure.rower", text: tr("Lake at the boat's time: move the boat along your route and see the lake when you get there.")),
            Point(symbol: "arrow.triangle.capsulepath", text: tr("Row a loop: tap within 50 m of your club, or use Close loop.")),
            Point(symbol: "hand.draw", text: tr("Tap a turning point to delete just that one, or drag it to move it.")),
            Point(symbol: "map", text: tr("Open in Maps now gives directions to the club's address.")),
            Point(symbol: "rectangle.bottomhalf.inset.filled", text: tr("The panel under the lake map is smaller. Pull it up for the details.")),
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
                    Text(tr("Route planning on the lake map got better."))
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

/// The tour's pages, in order. The two choice pages only show while there is no home base.
enum TourPage: Int, CaseIterable, Identifiable {
    case welcome, homeBase, moreClubs, rowingLight, conditions, warnings, boats, lake, locations, wideScreen, settings
    var id: Int { rawValue }

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
        case .locations: "list.bullet"
        case .wideScreen: "rectangle.split.2x1"
        case .settings: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .welcome, .homeBase, .moreClubs, .locations: .blue
        case .rowingLight: .green
        case .conditions, .lake: .teal
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
        case .warnings: tr("DWD warnings")
        case .boats: tr("Your boats and limits")
        case .lake: tr("Lake view and routes")
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
        case .conditions: tr("Below the light you find what matters on the water.")
        case .warnings: tr("Warnings from the Deutscher Wetterdienst come right under the rowing light.")
        case .boats: tr("The rowing light is worked out for one boat. Set it in Settings › Rowing limits.")
        case .lake: tr("Below the current conditions, the Lake view shows the whole lake.")
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
            TourPoint(symbol: "clock", text: tr("Each of the next 48 hours has its own light.")),
            TourPoint(symbol: "umbrella", text: tr("The rain radar shows rain for the next two hours.")),
            TourPoint(symbol: "clock.badge.exclamationmark", text: tr("Grey instead of green: the forecast is over 3 hours old. Pull down to refresh.")),
            TourPoint(symbol: "person.fill.questionmark", text: tr("The light is advice. You decide, and when in doubt you stay ashore.")),
        ]
        case .conditions: [
            TourPoint(symbol: "thermometer.variable.and.figure", text: tr("Feels like: colder with wind chill, warmer with humidity and heat.")),
            TourPoint(symbol: "humidity", text: tr("Humidity, with the dew point underneath.")),
            TourPoint(symbol: "gauge.with.dots.needle.33percent", text: tr("Air pressure on a gauge, with its trend for the hours ahead.")),
            TourPoint(symbol: "snowflake", text: tr("In winter, the app estimates ice on the water from frost and water temperature, checked against satellite pictures on larger lakes. Always look at the water yourself.")),
            TourPoint(symbol: "cloud.sun", text: tr("The forecast comes from the weather model that does best for your lake. The line near the end of each page names it.")),
            TourPoint(symbol: "info.circle", text: tr("Tap ⓘ on a card to see what its icons and colours mean. Settings › Help has the full legend.")),
        ]
        case .warnings: [
            TourPoint(symbol: "water.waves", text: tr("Lake storm warnings for the lake and weather warnings for the town.")),
            TourPoint(symbol: "text.bubble", text: tr("A warning also appears in the Why line and on the location list.")),
            TourPoint(symbol: "light.beacon.max", text: tr("On the lake, also watch the storm warning lights on the shore. The warnings card explains what they mean.")),
            TourPoint(symbol: "arrow.up.arrow.down", text: tr("The light and the warnings always stay on top. Arrange this page, at the end of each page, sorts or hides the other cards.")),
        ]
        case .boats: [
            TourPoint(symbol: "checkmark", text: tr("Small boats are ticked at first. Tick Big boats if you row a four or an eight.")),
            TourPoint(symbol: "list.bullet", text: tr("Add your own boats under My boats. When it is too rough for yours, the app names one that would be fine.")),
            TourPoint(symbol: "slider.horizontal.3", text: tr("The sliders next to a boat open its limits.")),
            TourPoint(symbol: "map", text: tr("Pick the boat that colours the lake map.")),
            TourPoint(symbol: "thermometer.snowflake", text: tr("Below %@ water the app advises a life jacket; below %@ it is stricter.", Format.temperature(RowingLimit.lifeJacket.standard(for: .small)), Format.temperature(RowingLimits.coldWaterC))),
        ]
        case .lake: [
            TourPoint(symbol: "map", text: tr("The Lake view shows the light, waves and wind across the whole lake. Tap it for the full map.")),
            TourPoint(symbol: "clock", text: tr("On the map, move through the hours in the strip at the bottom and tap the water for one spot.")),
            TourPoint(symbol: "point.topleft.down.to.point.bottomright.curvepath", text: tr("Plan a route: tap your turning points to see the light along the way and the best time to start.")),
            TourPoint(symbol: "bookmark", text: tr("Save the routes you row often in the Routes menu.")),
            TourPoint(symbol: "globe.europe.africa", text: tr("Below it, the latest satellite picture of the lake, with a switch to the clearest one.")),
        ]
        case .locations: [
            TourPoint(symbol: "hand.draw", text: tr("Swipe left and right to move between your clubs. The house marks your home base.")),
            TourPoint(symbol: "magnifyingglass", text: tr("Search the list for any club in Germany, Austria or Switzerland and tap + to add it.")),
            TourPoint(symbol: "arrow.up.arrow.down", text: tr("Touch and hold a club, then drag to reorder.")),
            TourPoint(symbol: "trash", text: tr("Swipe a club in the list to the left to remove it.")),
            TourPoint(symbol: "arrow.clockwise", text: tr("Pull a page or the list down to refresh.")),
            TourPoint(symbol: "apps.iphone", text: tr("A Row Frog widget on your home or lock screen shows the rowing light and rain on the radar in the next two hours.")),
        ]
        case .wideScreen: [
            TourPoint(symbol: "sidebar.left", text: tr("The location list stays on the left, the club page on the right.")),
            TourPoint(symbol: "square.grid.2x2", text: tr("The cards on the club page sit in two columns.")),
            TourPoint(symbol: "gearshape", text: tr("Prefer portrait only? Switch landscape off in the settings.")),
        ]
        case .settings: [
            TourPoint(symbol: "globe", text: tr("Language: English or German.")),
            TourPoint(symbol: "ruler", text: tr("Units for temperature, wind, waves, rain, distances and air pressure.")),
            TourPoint(symbol: "circle.lefthalf.filled", text: tr("Light, dark or like your phone.")),
            TourPoint(symbol: "photo", text: tr("Background pictures, including your own photos.")),
            TourPoint(symbol: "app.badge", text: tr("Your choice of app icon.")),
            TourPoint(symbol: "questionmark.circle", text: tr("You can watch this tour again in the settings.")),
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
    // The location question is a system alert. When it closes, the paged view can
    // jump back to its first page while `page` still says otherwise, so the pager
    // is rebuilt on the current page once the answer is in.
    @State private var pagerID = 0
    @Environment(\.scenePhase) private var scenePhase

    init(locations: LocationStore, reload: @escaping () async -> Void, finish: @escaping () -> Void) {
        self.locations = locations
        self.reload = reload
        self.finish = finish
        let pages = TourPage.allCases.filter { locations.homeID == nil || !$0.isChoice }
        let start = TourPage(rawValue: UserDefaults.standard.integer(forKey: "RWTutorialPage")) ?? .welcome
        _pages = State(initialValue: pages)
        _page = State(initialValue: pages.contains(start) ? start : pages[0])
    }

    var body: some View {
        let index = pages.firstIndex(of: page) ?? 0
        let isLast = index == pages.count - 1
        let needsHome = locations.homeID == nil
        VStack(spacing: 12) {
            HStack {
                Spacer()
                // Skipping still asks for a home base first.
                Button(tr("Skip")) {
                    if needsHome { withAnimation { page = .homeBase } } else { finish() }
                }
                .opacity(isLast || page.isChoice ? 0 : 1)
                .disabled(isLast || page.isChoice)
            }
            .padding(.horizontal)
            TabView(selection: $page) {
                ForEach(pages) { page in
                    Group {
                        if page.isChoice {
                            ClubChoicePage(page: page, locations: locations, near: here.coordinate, reload: reload)
                        } else {
                            TourPageView(page: page)
                        }
                    }
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .id(pagerID)
            .onChange(of: scenePhase) { old, new in
                if new == .active, old != .active, here.askedForPermission {
                    here.askedForPermission = false
                    pagerID += 1
                }
            }
            .task(id: page) {
                // Ask for the location when choosing the home base, for clubs nearby.
                if page == .homeBase { here.request() }
            }
            .onChange(of: page) {
                // No swiping past the home base choice without one.
                if locations.homeID == nil, page.rawValue > TourPage.homeBase.rawValue {
                    withAnimation { page = .homeBase }
                }
            }
            Button {
                if isLast {
                    finish()
                } else {
                    withAnimation { page = pages[index + 1] }
                }
            } label: {
                Text(isLast ? tr("Let's row") : tr("Next"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(page == .homeBase && needsHome)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .environment(\.locale, AppSettings.shared.locale)
    }
}

/// Picking the home base, or adding more clubs: suggestions first, then any
/// club in the catalog by search.
private struct ClubChoicePage: View {
    let page: TourPage
    let locations: LocationStore
    let near: Coordinate?
    let reload: () async -> Void
    @State private var search = ""

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Image(systemName: page.symbol)
                    .font(.system(size: 36))
                    .foregroundStyle(page.tint)
                    .accessibilityHidden(true)
                Text(page.title).font(.title2.bold())
                Text(page.intro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("Search clubs, lakes or towns"), text: $search)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(tr("Cancel"))
                }
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            List {
                if locations.catalog.isEmpty {
                    if locations.catalogFailed {
                        ContentUnavailableView {
                            Label(tr("No connection"), systemImage: "wifi.slash")
                        } description: {
                            Text(tr("Could not load the rowing locations."))
                        } actions: {
                            Button(tr("Try again")) { Task { await reload() } }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } else if search.isEmpty {
                    if page == .moreClubs, !locations.saved.isEmpty {
                        Section(tr("In your list")) {
                            ForEach(locations.saved) { row($0) }
                        }
                    }
                    let suggestions = locations.suggestions(near: near).filter { page == .homeBase || !locations.isSaved($0) }
                    Section {
                        ForEach(suggestions) { row($0) }
                    } header: {
                        if !suggestions.isEmpty { Text(near == nil ? tr("Suggestions") : tr("Near you")) }
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("Search by club, lake or town to find any club in Germany, Austria or Switzerland."))
                            Text(tr("Clubs nobody has opened for a while update less often at first. After you add one, it is up to date within about 30 minutes."))
                        }
                    }
                } else {
                    let results = locations.search(search)
                    if results.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                    ForEach(results.prefix(50)) { row($0) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            // Room for the page dots.
            .padding(.bottom, 36)
        }
        .padding(.top, 8)
    }

    private func row(_ club: Club) -> some View {
        let isHome = club.id == locations.homeID
        let saved = locations.isSaved(club)
        return Button {
            if page == .homeBase {
                locations.replaceHome(with: club)
            } else if !saved {
                locations.add(club)
            } else if !isHome {
                locations.remove(club)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(club.name).foregroundStyle(Color.primary)
                    Text([locations.lake(of: club)?.name, club.town].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Group {
                    if isHome {
                        Image(systemName: "house.fill").foregroundStyle(.blue)
                            .accessibilityLabel(tr("Home base"))
                    } else if page == .homeBase {
                        Image(systemName: "circle").foregroundStyle(.secondary)
                    } else if saved {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            .accessibilityLabel(tr("In your list"))
                    } else {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                            .accessibilityLabel(tr("Add %@", club.displayName))
                    }
                }
                .font(.title3)
            }
        }
    }
}

private struct TourPageView: View {
    let page: TourPage

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: page.symbol)
                    .font(.system(size: 60))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(page.tint)
                    .frame(height: 76)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(page.title)
                        .font(.title.bold())
                    Text(page.intro)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
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
            .padding(.horizontal)
            .padding(.top, 16)
            // Room for the page dots.
            .padding(.bottom, 48)
        }
    }

    /// A small picture of the feature: the language choice, the three lights, the condition icons.
    @ViewBuilder private var extra: some View {
        switch page {
        case .welcome:
            VStack(spacing: 8) {
                Label(tr("Language"), systemImage: "globe")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker(tr("Language"), selection: Binding(get: { AppSettings.shared.language }, set: { AppSettings.shared.language = $0 })) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
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
        case .homeBase, .moreClubs, .warnings, .boats, .lake, .locations, .wideScreen, .settings:
            EmptyView()
        }
    }
}

// MARK: - One-time tips

struct HourlyTip: Tip {
    var title: Text { Text(tr("Plan your outing")) }
    var message: Text? { Text(tr("Each hour has its own rowing light. The icons on top name the columns, and rows after dark are dimmed.")) }
    var image: Image? { Image(systemName: "clock") }
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
    var message: Text? { Text(tr("Appearance, units, language and background pictures go back to how the app came, and your own pictures are deleted. Your locations and home base stay.")) }
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
    var message: Text? { Text(tr("The radar of the Deutscher Wetterdienst shows rain at the launch point for the next two hours, in 15-minute steps. It updates every few minutes.")) }
    var image: Image? { Image(systemName: "umbrella") }
}

struct RadarMapTip: Tip {
    var title: Text { Text(tr("Rain radar map")) }
    var message: Text? { Text(tr("Tap the card for the radar map. Play it, or drag the slider from an hour ago to two hours ahead.")) }
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
    var message: Text? { Text(tr("Tick the boat the rowing light is for. The sliders open its limits, and below you can add your own boats.")) }
    var image: Image? { Image(systemName: "figure.rower") }
}

struct ColdWaterTip: Tip {
    var title: Text { Text(tr("Cold water")) }
    var message: Text? { Text(tr("A capsize in water below %@ gets dangerous within minutes. The app then lowers its own wind and gust limits by %@. Limits you set stay as they are, with a reminder on the rowing light.", Format.temperature(RowingLimits.coldWaterC), Format.wind(RowingLimits.coldWindMarginMs))) }
    var image: Image? { Image(systemName: "thermometer.snowflake") }
}

struct TopTileTip: Tip {
    var title: Text { Text(tr("Tap a value")) }
    var message: Text? { Text(tr("Tap a value in the tile above to open its chart. Swiping there goes through only this tile's values.")) }
    var image: Image? { Image(systemName: "hand.tap") }
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
    var message: Text? { Text(tr("Close the loop: tap within 50 m of your club, or use Close loop.")) }
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
    var message: Text? { Text(tr("New routes go one way. Turn on Out and back to row the same way back.")) }
    var image: Image? { Image(systemName: "arrow.uturn.backward") }
}

struct RowImportTip: Tip {
    var title: Text { Text(tr("Import a row")) }
    var message: Text? { Text(tr("Rowed it before? Bring in a row from Apple Health or a GPX, TCX or FIT file (CrewNerd, Garmin, Strava) in the bookmark menu, and plan with your real route and pace.")) }
    var image: Image? { Image(systemName: "square.and.arrow.down.on.square") }
}

// MARK: - Location for nearby clubs

/// The device's location, asked for only while the app is in use and only to
/// suggest clubs nearby. Stays nil when the user says no.
@Observable
final class DeviceLocation: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: Coordinate?
    /// Set when the system alert asking for the location was shown.
    var askedForPermission = false
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
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
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
