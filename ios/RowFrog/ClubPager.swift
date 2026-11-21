import SwiftUI

/// The club pages side by side, one screen wide each, swiped one at a time (as TourPager).
/// Pages are made as they come near, so many saved clubs cost no more than a few.
///
/// Not a paged TabView: each page holds its own navigation stack (for the soft top
/// edge, decision 0054), and fast swipes in the paged TabView made UIKit lay out one
/// page's bar with a neighbouring page's item and abort the app (build 1024,
/// 21 Nov 2026). A scroll view keeps every page as its own view.
struct ClubPager<Content: View>: View {
    let clubs: [Club]
    @Binding var selection: String
    @ViewBuilder let content: (Club) -> Content
    @State private var scrolled: String?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(clubs) { club in
                            content(club)
                                .frame(width: size.width, height: size.height)
                                // Only the page shown is read out, as in a paged TabView; the
                                // page dots switch clubs (and keep UI tests quick).
                                .accessibilityHidden(club.id != selection)
                                .id(club.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $scrolled)
                .frame(width: size.width, height: size.height)
                .onAppear {
                    scrolled = selection
                    reader.scrollTo(selection)
                }
                .onChange(of: scrolled) {
                    if let scrolled, scrolled != selection { selection = scrolled }
                }
                // A dot, the list or a link: the next page slides over, a page further away
                // shows at once (PageJump).
                .onChange(of: selection) { old, new in
                    guard scrolled != new else { return }
                    let ids = clubs.map(\.id)
                    if let a = ids.firstIndex(of: old), let b = ids.firstIndex(of: new), abs(a - b) == 1 {
                        withAnimation { scrolled = new }
                    } else {
                        var instant = Transaction()
                        instant.disablesAnimations = true
                        withTransaction(instant) { scrolled = new }
                    }
                }
                // A turn or the iPad's list shown or hidden keeps the page shown.
                .onChange(of: size) {
                    reader.scrollTo(selection)
                }
            }
        }
    }
}
