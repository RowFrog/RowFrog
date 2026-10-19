import SwiftUI

/// Screenshot hook `-RWIconGallery YES`: every icon the app uses on one page,
/// and candidates for a new visibility icon shown next to the rain and fog
/// symbols they must not be confused with. Not reachable from the app's UI.
struct IconGalleryView: View {
    /// Candidates for the visibility icon; the first is the one in use.
    static let visibilityCandidates: [(symbol: String, note: String)] = [
        ("cloud.fog", "In use now"),
        ("eye", "Eye"),
        ("eye.fill", "Eye, filled"),
        ("binoculars", "Binoculars"),
        ("binoculars.fill", "Binoculars, filled"),
        ("sun.haze", "Haze"),
        ("arrow.left.and.right", "Distance"),
    ]

    /// Other icons in the app and where they appear.
    private let otherIcons: [(symbol: String, meaning: String)] = [
        ("house.fill", "Home base"),
        ("exclamationmark.triangle.fill", "DWD weather warning"),
        ("light.beacon.max.fill", "DWD lake warning"),
        ("checkmark.shield.fill", "No warning"),
        ("sunrise.fill", "Sunrise"),
        ("sunset.fill", "Sunset"),
        ("location.north.fill", "Wind direction"),
        ("figure.rower", "Launch point on the map"),
        ("mappin.slash", "Launch point not confirmed"),
        ("map", "Open in Maps"),
        ("clock", "Next 48 hours"),
        ("info.circle", "Legend"),
        ("list.bullet", "Location list"),
        ("wifi.slash", "No connection"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Icons").font(.largeTitle.bold()).padding(.top, 24)

                Card(title: "Visibility: current and candidates", symbol: "eye") {
                    Text("Each candidate in a list-row column, between water and ice, with the rain icon below it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Self.visibilityCandidates, id: \.symbol) { candidate in
                        Divider()
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: candidate.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 30))
                                .foregroundStyle(.blue)
                                .frame(width: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.note).font(.subheadline.weight(.semibold))
                                Text(candidate.symbol).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 6) {
                                Label("0.1 km", systemImage: candidate.symbol)
                                Label("Dry", systemImage: Condition.precipitation.symbol)
                                Label("–", systemImage: Condition.ice.symbol).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }

                Card(title: "Conditions", symbol: "gauge.with.dots.needle.33percent") {
                    ForEach(Condition.allCases, id: \.self) { condition in
                        row(Image(systemName: condition.symbol).symbolRenderingMode(.hierarchical), condition.title, condition.symbol)
                    }
                }

                Card(title: "Weather symbols (day, night)", symbol: "cloud.sun") {
                    ForEach(Sky.allCases, id: \.self) { sky in
                        HStack(spacing: 14) {
                            SkyIcon(sky: sky).frame(width: 30)
                            SkyIcon(sky: sky, night: true).frame(width: 30)
                            Text(sky.title)
                            Spacer()
                        }
                        .font(.title3)
                    }
                }

                Card(title: "Other icons", symbol: "square.grid.2x2") {
                    ForEach(otherIcons, id: \.symbol) { icon in
                        row(Image(systemName: icon.symbol).symbolRenderingMode(.hierarchical), icon.meaning, icon.symbol)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: "RWScrollPage"), ready: true))
    }

    private func row(_ image: some View, _ title: String, _ symbol: String) -> some View {
        HStack(spacing: 14) {
            image.font(.title3).foregroundStyle(.blue).frame(width: 34)
            Text(title).font(.subheadline)
            Spacer()
            Text(symbol).font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
    }
}
