import SwiftUI
import UIKit

extension View {
    /// The system font at a set size that still follows the text size people
    /// pick, as Apple's guide asks of all text: the size is what it is at the
    /// standard text size and grows or shrinks with the text style it goes with.
    /// Light only where the text is large; small light text is hard to read.
    /// Big numbers grow by at most `maxGrowth`, so they keep room for the
    /// words beside them, which matter more at large text sizes.
    func scaledSystemFont(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body,
                          maxGrowth: CGFloat = .infinity) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, style: style, maxGrowth: maxGrowth))
    }

    /// A value's number, as on the top tile and in the list: light from 20 pt,
    /// regular below, and growing with the text size by at most a third.
    func valueFont(size: CGFloat) -> some View {
        scaledSystemFont(size: size, weight: size >= 20 ? .light : .regular,
                         relativeTo: size >= 28 ? .largeTitle : size >= 20 ? .title2 : .body, maxGrowth: 1.35)
    }
}

private struct ScaledSystemFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let style: Font.TextStyle
    let maxGrowth: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let scaled = UIFontMetrics(forTextStyle: style.uiTextStyle).scaledValue(for: size, compatibleWith: traits)
        content.font(.system(size: min(scaled, size * maxGrowth), weight: weight))
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
