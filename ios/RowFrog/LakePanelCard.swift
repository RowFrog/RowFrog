import SwiftUI

// Split off LakeMapScreen.swift (owner's large-file rule) with the change that made the lake
// map's panel a card on wide screens: the card's numbers, the panel's chrome and CappedScroll
// (moved unchanged apart from dropping `private`).

/// Where the lake map's panel goes (owner's option B, 12 Nov 2026): across the bottom on an
/// upright iPhone; on every wider screen (iPad both ways, iPhone sideways, Mac) a card at the
/// bottom left, as in Apple Maps, with the legend chip beside it and the layer buttons at the
/// right. The app leads: the website copies these numbers (`LAKE_PANEL` in lakeview.js).
enum LakePanelLayout {
    /// A card from this width of the screen inside its safe area, in points; the club page's
    /// columns switch at the same width (ClubPageColumns).
    static let cardFromWidth: CGFloat = 600
    /// The card's width.
    static let cardWidth: CGFloat = 360
    /// The card's distance from the left and bottom edges (inside the safe area), and the
    /// legend chip's and layer buttons' distance from the bottom beside it.
    static let inset: CGFloat = 16
    /// Corner radius: the full-width panel rounds its top corners, the card all four.
    static let cornerRadius: CGFloat = 22
    /// Room the buttons at the top and the card's own lines (grabber, hour, hour strip) take
    /// above and around the card's scrolling part.
    static let cardChrome: CGFloat = 300
    /// The card's scrolling part is at least this tall, even on a phone turned sideways.
    static let minScroll: CGFloat = 120

    static func usesCard(width: CGFloat) -> Bool { width >= cardFromWidth }

    /// How tall the card's scrolling part may get on a screen this tall (inside its safe area).
    static func scrollHeight(screenHeight: CGFloat) -> CGFloat {
        max(screenHeight - cardChrome, minScroll)
    }
}

extension View {
    /// The panel's padding, material background and pull gesture: the full-width panel with
    /// rounded top corners down to the screen's edge, or the card with four rounded corners.
    func lakePanelChrome(card: Bool, expanded: Binding<Bool>) -> some View {
        modifier(LakePanelChrome(card: card, expanded: expanded))
    }
}

private struct LakePanelChrome: ViewModifier {
    let card: Bool
    @Binding var expanded: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal)
            .padding(.top, 6)
            .padding(.bottom, card ? 12 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if card {
                    RoundedRectangle(cornerRadius: LakePanelLayout.cornerRadius)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                } else {
                    UnevenRoundedRectangle(topLeadingRadius: LakePanelLayout.cornerRadius, topTrailingRadius: LakePanelLayout.cornerRadius)
                        .fill(.regularMaterial)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            // Pull up for everything, push down for the map.
            .gesture(DragGesture(minimumDistance: 20).onEnded { drag in
                if drag.translation.height < -30 { withAnimation(.snappy) { expanded = true } }
                if drag.translation.height > 30 { withAnimation(.snappy) { expanded = false } }
            })
    }
}

/// Its content as is, or (when enabled) in a scroll view no taller than
/// `maxHeight`, and only as tall as the content when that is shorter.
struct CappedScroll<Content: View>: View {
    let enabled: Bool
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        if enabled {
            ScrollView {
                content.background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { height = geo.size.height }
                            .onChange(of: geo.size.height) { _, new in height = new }
                    }
                }
            }
            .frame(height: min(max(height, 1), maxHeight))
            .scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

