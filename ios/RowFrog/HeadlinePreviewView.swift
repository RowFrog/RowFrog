import SwiftUI

/// Screenshot hook `-RWHeadlinePreview YES`: the club page's top row (rowing
/// light, verdict, weather word) for each way of keeping the verdict on one
/// line, with the longest weather words, at the text size set on the device
/// (`-UIPreferredContentSizeCategoryName`). Preview only, not reachable from the app's UI.
struct HeadlinePreviewView: View {
    private enum Option: CaseIterable {
        case today, both, fitted, fittedShort

        var title: String {
            switch self {
            case .today: "Today"
            case .both: "Option 3: weather word on two lines + shorter German"
            case .fitted: "Option 4: tighter row, verdict one text style smaller when needed"
            case .fittedShort: "Option 5: as 4 with shorter German verdicts"
            }
        }

        var style: Headline.Style {
            switch self {
            case .today: .today
            case .both: .twoLineWord
            case .fitted, .fittedShort: .fitted
            }
        }

        var shortWords: Bool { self == .both || self == .fittedShort }
    }

    /// Light, the sky shown with it, and the short German verdict (nil = unchanged).
    private let rows: [(light: Light, sky: Sky, stale: Bool, short: String?)] = [
        (.green, .partlyCloudy, false, nil),
        (.amber, .freezingRain, false, "Vorsichtig rudern"),
        (.red, .hail, false, "Nicht rudern"),
        (.green, .partlyCloudy, true, "Veraltet"),
    ]

    private var german: Bool { AppSettings.shared.resolvedLanguage == .german }
    @Environment(\.dynamicTypeSize) private var typeSize

    private var sizeName: String {
        switch typeSize {
        case .large: "Default text size"
        case .xxxLarge: "Largest normal text size (XXXL)"
        case .accessibility3: "Larger accessibility text size (Accessibility L)"
        default: "Text size \(typeSize)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Verdict headline").font(.largeTitle.bold()).padding(.top, 24)
                Text(sizeName).font(.subheadline).foregroundStyle(.secondary)
                // In English option 5 is option 4: only German words change.
                ForEach(Option.allCases.filter { german || $0 != .fittedShort }, id: \.self) { option in
                    Text(option.title).font(.headline).padding(.top, 8)
                    ForEach(rows.indices, id: \.self) { i in
                        let row = rows[i]
                        let title = row.light.title(stale: row.stale)
                        Card {
                            Headline(light: row.light, stale: row.stale, sky: row.sky,
                                     title: option.shortWords && german ? row.short ?? title : title,
                                     style: option.style)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: "RWScrollPage"), ready: true))
    }

    /// As NowCard's top row.
    fileprivate struct Headline: View {
        enum Style { case today, twoLineWord, fitted }

        let light: Light
        let stale: Bool
        let sky: Sky
        let title: String
        let style: Style
        @Environment(\.dynamicTypeSize) private var typeSize
        /// The weather word's column, growing with the text size like the word itself.
        @ScaledMetric(relativeTo: .caption) private var wordWidth: CGFloat = 88

        var body: some View {
            if style == .fitted && typeSize.isAccessibilitySize {
                stacked
            } else {
                row
            }
        }

        /// Light, verdict, then the weather: the verdict takes the room first, at
        /// title 2; when that does not fit on one line, at title 3 (one text style
        /// smaller, so it still grows with the text size); only then on two lines.
        private var row: some View {
            HStack(spacing: style == .fitted ? 10 : 14) {
                TrafficLightDot(light: light, size: 36, stale: stale)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        if style == .fitted {
                            ViewThatFits(in: .horizontal) {
                                Text(title).font(.title2.bold()).lineLimit(1).fixedSize()
                                Text(title).font(.title3.bold()).lineLimit(1).fixedSize()
                                Text(title).font(.title3.bold())
                            }
                        } else {
                            Text(title).font(.title2.bold())
                        }
                        info
                    }
                    boat
                }
                .frame(maxWidth: style == .fitted ? .infinity : nil, alignment: .leading)
                .layoutPriority(style == .fitted ? 1 : 0)
                if style != .fitted { Spacer(minLength: 0) }
                VStack(spacing: 2) {
                    SkyIcon(sky: sky).font(.system(size: 34))
                    if style == .today {
                        Text(sky.title).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(sky.title).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(width: wordWidth)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        /// At the accessibility text sizes the row has no room for three columns,
        /// so the weather moves under the verdict, as Apple's guide suggests.
        private var stacked: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    TrafficLightDot(light: light, size: 36, stale: stale)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(title).font(.title2.bold())
                            info
                        }
                        boat
                    }
                }
                HStack(spacing: 8) {
                    SkyIcon(sky: sky).font(.system(size: 34))
                    Text(sky.title).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.leading, 46)
            }
        }

        private var info: some View {
            Image(systemName: "info.circle").font(.subheadline).foregroundStyle(.tint)
        }

        private var boat: some View {
            HStack(spacing: 3) {
                Text(tr("For %@", AppSettings.shared.selectedBoat.inSentence))
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
