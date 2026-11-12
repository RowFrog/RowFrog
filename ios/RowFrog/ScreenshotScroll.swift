import SwiftUI

// Split off LocationPageView.swift unchanged.

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
