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

    static func markSeen() { UserDefaults.standard.set(true, forKey: seenKey) }

    /// For "Show the tour again": the tour starts over and the tips return.
    static func replay() {
        UserDefaults.standard.set(false, forKey: seenKey)
        UserDefaults.standard.set(true, forKey: resetTipsKey)
    }

    /// Screenshot hooks: `-RWNoTips YES` hides every tip, `-RWShowTips YES` shows them all.
    static func configureTips() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: resetTipsKey) {
            // TipKit only forgets closed tips before it is configured.
            try? Tips.resetDatastore()
            defaults.removeObject(forKey: resetTipsKey)
        }
        if defaults.bool(forKey: "RWNoTips") { Tips.hideAllTipsForTesting() }
        if defaults.bool(forKey: "RWShowTips") { Tips.showAllTipsForTesting() }
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

// MARK: - Tour

/// The tour's pages, in order.
enum TourPage: Int, CaseIterable, Identifiable {
    case welcome, rowingLight, conditions, warnings, locations, settings
    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .welcome: "figure.rower"
        case .rowingLight: "light.beacon.max"
        case .conditions: "thermometer.and.liquid.waves"
        case .warnings: "exclamationmark.triangle.fill"
        case .locations: "list.bullet"
        case .settings: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .welcome, .locations: .blue
        case .rowingLight: .green
        case .conditions: .teal
        case .warnings: .orange
        case .settings: .gray
        }
    }

    var title: String {
        switch self {
        case .welcome: tr("Welcome to RowerWeather")
        case .rowingLight: tr("The rowing light")
        case .conditions: tr("Conditions at a glance")
        case .warnings: tr("DWD warnings")
        case .locations: tr("Your locations")
        case .settings: tr("Settings")
        }
    }

    var intro: String {
        switch self {
        case .welcome: tr("Weather and a rowing forecast for your club's launch point.")
        case .rowingLight: tr("Every page starts with the rowing light for the hour ahead.")
        case .conditions: tr("Below the light you find what matters on the water.")
        case .warnings: tr("Warnings from the Deutscher Wetterdienst come right under the rowing light.")
        case .locations: tr("Keep all the places you row in one list.")
        case .settings: tr("Open the settings with the cog at the top of the location list.")
        }
    }

    /// Symbol and text for each point on the page.
    var points: [TourPoint] {
        switch self {
        case .welcome: [
            TourPoint(symbol: "house.fill", text: tr("Your home base opens first. At the start that is MRC 1880.")),
            TourPoint(symbol: "hand.draw", text: tr("To change it, open the list, swipe a club to the right and tap Home base.")),
        ]
        case .rowingLight: [
            TourPoint(symbol: "text.bubble", text: tr("The line starting with \"Why\" names the conditions that set the light.")),
            TourPoint(symbol: "sun.horizon", text: tr("Rowing is only advised while the sun is up. The daylight card shows the time left until sunset.")),
            TourPoint(symbol: "clock", text: tr("The next 48 hours each have their own light, so you can plan your outing.")),
        ]
        case .conditions: [
            TourPoint(symbol: "info.circle", text: tr("Open the Legend at the bottom of each page to see what every icon and colour means.")),
        ]
        case .warnings: [
            TourPoint(symbol: "water.waves", text: tr("Lake storm warnings for the lake and weather warnings for the town.")),
            TourPoint(symbol: "text.bubble", text: tr("A warning also appears in the Why line and on the location list.")),
            TourPoint(symbol: "light.beacon.max", text: tr("On the lake, also watch the storm warning lights on the shore.")),
        ]
        case .locations: [
            TourPoint(symbol: "hand.draw", text: tr("Swipe left and right to move between your clubs. The house marks your home base.")),
            TourPoint(symbol: "magnifyingglass", text: tr("Search the list for any club in the DRV club directory and tap + to add it.")),
            TourPoint(symbol: "arrow.up.arrow.down", text: tr("Touch and hold a club, then drag to reorder.")),
            TourPoint(symbol: "trash", text: tr("Swipe a club in the list to the left to remove it.")),
            TourPoint(symbol: "arrow.clockwise", text: tr("Pull a page or the list down to refresh.")),
        ]
        case .settings: [
            TourPoint(symbol: "globe", text: tr("Language: English or German.")),
            TourPoint(symbol: "ruler", text: tr("Units for temperature, wind, waves, rain and distances.")),
            TourPoint(symbol: "circle.lefthalf.filled", text: tr("Light, dark or like your phone.")),
            TourPoint(symbol: "photo", text: tr("Background pictures, including your own photos.")),
            TourPoint(symbol: "questionmark.circle", text: tr("You can watch this tour again in the settings.")),
        ]
        }
    }
}

struct TourPoint: Hashable {
    let symbol: String
    let text: String
}

/// The swipeable tour. `-RWTutorialPage n` opens it on page n for screenshots.
struct TutorialView: View {
    let finish: () -> Void
    @State private var page = TourPage(rawValue: UserDefaults.standard.integer(forKey: "RWTutorialPage")) ?? .welcome

    var body: some View {
        let isLast = page == TourPage.allCases.last
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button(tr("Skip"), action: finish)
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
            }
            .padding(.horizontal)
            TabView(selection: $page) {
                ForEach(TourPage.allCases) { page in
                    TourPageView(page: page).tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if isLast {
                    finish()
                } else if let next = TourPage(rawValue: page.rawValue + 1) {
                    withAnimation { page = next }
                }
            } label: {
                Text(isLast ? tr("Let's row") : tr("Next"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .environment(\.locale, AppSettings.shared.locale)
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
                VStack(alignment: .leading, spacing: 14) {
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
                    .padding(.vertical, 12)
                    .background(light.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        case .conditions:
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
                ForEach([Condition.temperature, .feelsLike, .waterTemperature, .wind, .waves, .precipitation, .visibility, .daylight]) { condition in
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
        case .warnings, .locations, .settings:
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
