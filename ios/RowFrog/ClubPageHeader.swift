import SwiftUI
import TipKit

/// The top of a club page: home base, the club's name, the lake and town, a
/// note while the launch point is not yet confirmed, and when the forecast is
/// from. With the launch point in the header (Settings > Club pages), the lake
/// and town line opens the launch point in a sheet instead of the Launch point card.
///
/// Split off LocationPageView.swift (owner rule on very large files, 4 Nov 2026).
struct ClubPageHeader: View {
    let club: Club
    let lake: Lake?
    let isHome: Bool
    let forecasts: ForecastStore
    @Environment(\.surface) private var surface
    @Environment(\.pageMargins) private var pageMargins
    @Environment(\.titleSideRoom) private var titleSideRoom
    /// The refresh failure explained after a tap on its line.
    @State private var showingFailure: RefreshFailure?
    @State private var showingLaunchPoint = false
    @Environment(\.isCurrentPage) private var isCurrentPage
    @AppStorage(Tutorial.seenKey) private var tourSeen = false
    private var inHeader: Bool { AppSettings.shared.launchPointInHeader }

    var body: some View {
        VStack(spacing: 4) {
            if isHome {
                Label(tr("Home base"), systemImage: "house.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ClubTitle(club: club)
                .font(.largeTitle.bold())
                // Once the title is under the top bar, the bar shows the name instead.
                .onGeometryChange(for: Bool.self) { [top = pageMargins.top] proxy in
                    top > 0 && proxy.frame(in: .global).maxY < top + InlineClubTitle.height
                } action: { PageScroll.shared.update(club.id, titleGone: $0) }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: { y in
                    PageScroll.shared.update(club.id, titleMidY: y)
                }
                // The cog and the boat sit level with the name on either side.
                .padding(.horizontal, titleSideRoom)
            placeLine
            if !club.launchPointVerified {
                notConfirmedLine
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
                } else if forecasts.loading.contains(club.id) {
                    Label(tr("Updating…"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // The forecast's time is when the server worked it out; the load time is when it reached the phone.
                    Text(LocationPageView.updatedLine(forecast: updated, loaded: forecasts.loadedAt[club.id]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if forecast.isSlowRefresh {
                    // Opening the club counts it as used; the next server run renews it every half hour.
                    Label(tr("Nobody opened this club lately, so it updates less often. From the next server update, within about 30 minutes, it updates every half hour."), systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, surface.hasPicture ? 16 : 0)
        .padding(.vertical, surface.hasPicture ? 10 : 0)
        .labelBackground(surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 24)
        .alert(tr("Could not update"), isPresented: Binding(get: { showingFailure != nil }, set: { if !$0 { showingFailure = nil } }),
               presenting: showingFailure) { _ in
            Button(tr("Try again")) { Task { await forecasts.load(club.id, force: true) } }
            Button(tr("OK"), role: .cancel) {}
        } message: { failure in
            Text(failure.explanation)
        }
        .sheet(isPresented: $showingLaunchPoint) {
            LaunchPointSheet(club: club)
        }
        // Screenshot hook: `-RWOpenLaunchPoint YES` opens the launch point from the header
        // of the page in front.
        .task {
            guard UserDefaults.standard.bool(forKey: "RWOpenLaunchPoint"), inHeader, isCurrentPage else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            showingLaunchPoint = true
        }
    }

    private var place: String {
        [lake?.title, club.town].compactMap { $0 }.joined(separator: " · ")
    }

    /// The lake and town. With the launch point in the header, a button that opens
    /// the launch point's map, coordinates and Open in Maps.
    @ViewBuilder private var placeLine: some View {
        if inHeader {
            Button {
                showingLaunchPoint = true
                PlaceLineTip().invalidate(reason: .actionPerformed)
            } label: {
                Label {
                    Text(place) + Text(" ") + Text(Image(systemName: "chevron.right")).font(.footnote.weight(.semibold))
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .multilineTextAlignment(.center)
                .tapArea(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel(place)
            .accessibilityHint(tr("Shows the launch point on a map, with directions"))
            // Once, on the page in view, after the tour.
            .modifier(PlaceLineTipAnchor(shown: tourSeen && isCurrentPage))
            .id("launchpoint")
        } else {
            Text(place)
                .foregroundStyle(.secondary)
        }
    }

    /// The forecast may be for the wrong spot, so this stays at the top in both layouts;
    /// with the launch point in the header it opens the launch point too.
    @ViewBuilder private var notConfirmedLine: some View {
        let label = Label(tr("Launch point not yet confirmed"), systemImage: "mappin.slash")
            .font(.caption)
            .foregroundStyle(.orange)
        if inHeader {
            Button { showingLaunchPoint = true } label: {
                label.tapArea(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Shows the launch point on a map, with directions"))
        } else {
            label
        }
    }
}

/// `popoverTip` with an optional tip needs iOS 18.4, so the tip is attached only when it applies.
private struct PlaceLineTipAnchor: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        if shown {
            content.popoverTip(PlaceLineTip(), arrowEdge: .top)
        } else {
            content
        }
    }
}
