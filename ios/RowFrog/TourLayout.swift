import SwiftUI

/// How the tour sits on the screen (owner's pick A + C, 17 Nov 2026, decision 0049). Upright, a page
/// fills the screen: its head, the part that scrolls, then the dots and Next, always in sight. Wider
/// than tall (an iPad or an iPhone on its side), the head goes left with the dots and Next under it,
/// and the list or the page's content right, at full height. Turning the device switches at once,
/// on the same page, with the search and the clubs picked kept. The website does the same
/// (style.css, .tour).
struct TourColumns: Equatable {
    let left: CGFloat
    let gap: CGFloat
    let right: CGFloat
    /// Little height (an iPhone on its side): a smaller icon and title.
    let short: Bool

    /// The room under the left column for the dots and Next.
    static let bottom: CGFloat = 104

    /// Nil while the screen is upright or narrow: the pages then stack.
    init?(size: CGSize) {
        guard size.width > size.height, size.width >= 560 else { return nil }
        // Both columns together stay narrow enough for comfortable lines: at most 400 + 48 + 560 pt.
        let room = size.width - 32
        gap = min(48, max(20, size.width * 0.04))
        left = min(400, (room - gap) * 0.42)
        right = min(560, room - gap - left)
        short = size.height < 500
    }

    var width: CGFloat { left + gap + right }
}

extension EnvironmentValues {
    /// The tour's two columns, nil while the pages stack.
    @Entry var tourColumns: TourColumns? = nil
}

/// The left column on a wide screen: the page's head, scrolling only when it does not fit, above
/// the room for the dots and Next.
struct TourSideColumn<Content: View>: View {
    let columns: TourColumns
    /// Centred for the pages that tell, at the top (level with the list) for a club choice.
    let alignment: Alignment
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: alignment)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: columns.left)
        .padding(.bottom, TourColumns.bottom)
    }
}

/// The tour's page dots, its own so they can sit under the left column on a wide screen. A tap on
/// a dot goes to that page, as on the website.
struct TourDots: View {
    let count: Int
    let index: Int
    let go: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture { go(i) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Tour"))
        .accessibilityValue(tr("Page %@ of %@", "\(index + 1)", "\(count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if index + 1 < count { go(index + 1) }
            case .decrement: if index > 0 { go(index - 1) }
            @unknown default: break
            }
        }
        .accessibilityIdentifier("tour-dots")
    }
}
