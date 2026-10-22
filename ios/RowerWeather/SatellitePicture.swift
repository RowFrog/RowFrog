import SwiftUI

/// The latest cloud-free Sentinel-2 picture of a lake, published by the backend
/// (backend/rowerweather/sources/sentinel2.py) next to the lake view:
/// lakes/<id>/satellite describes it, lakes/<id>/satellite.jpg is the picture.
struct SatellitePicture: Decodable, Hashable {
    /// When the satellite took it; missing when no cloud-free picture was found in the last 30 days.
    var taken: Date?
    /// Share of the lake under cloud, 0...1.
    var lakeCloud: Double?
    var width: Int?
    var height: Int?
    /// File name beside the description, "satellite.jpg".
    var image: String?
    var attribution: String?

    var aspectRatio: CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 1.6 }
        return CGFloat(width) / CGFloat(height)
    }
}

/// Satellite pictures change every few days at most, so one load per lake and app start is enough.
@MainActor
@Observable
final class SatellitePictureStore {
    static let shared = SatellitePictureStore(api: .fromBundle())

    private(set) var pictures: [String: SatellitePicture] = [:]
    private(set) var missing: Set<String> = []
    let api: APIClient

    nonisolated init(api: APIClient) { self.api = api }

    func load(_ lakeID: String) async {
        guard pictures[lakeID] == nil, !missing.contains(lakeID) else { return }
        do {
            let picture = try await api.satellitePicture(lakeID: lakeID)
            if picture.taken != nil, picture.image != nil {
                pictures[lakeID] = picture
            } else {
                missing.insert(lakeID)
            }
        } catch {
            missing.insert(lakeID)
        }
    }

    /// The picture's address; the time it was taken keeps caches from showing an older one.
    func imageURL(_ lakeID: String) -> URL? {
        guard let picture = pictures[lakeID], let image = picture.image, let taken = picture.taken else { return nil }
        var components = URLComponents(url: api.url("lakes/\(lakeID)/\(image)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "t", value: String(Int(taken.timeIntervalSince1970)))]
        return components?.url
    }
}

/// "Satellite picture": the lake from space, as Sentinel-2 last saw it without
/// clouds. Tap for the full-screen picture. Hidden when there is none.
struct SatellitePictureCard: View {
    let lakeID: String
    @MainActor private var store: SatellitePictureStore { .shared }
    @State private var showingFull = false

    var body: some View {
        Group {
            if let picture = store.pictures[lakeID], let url = store.imageURL(lakeID) {
                Card(title: tr("Satellite picture"), symbol: "globe.europe.africa") {
                    Button { showingFull = true } label: {
                        image(url, picture: picture)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    caption(picture)
                }
                .fullScreenCover(isPresented: $showingFull) {
                    SatellitePictureScreen(url: url, picture: picture)
                }
            }
        }
        .task { await store.load(lakeID) }
    }

    private func image(_ url: URL, picture: SatellitePicture) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15).overlay { ProgressView() }
            }
        }
        .aspectRatio(picture.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(tr("Satellite picture of the lake"))
    }

    @ViewBuilder
    private func caption(_ picture: SatellitePicture) -> some View {
        if let taken = picture.taken {
            Text(tr("Sentinel-2, %@", Format.day(taken)))
                .font(.subheadline)
        }
        if let attribution = picture.attribution {
            Text(attribution)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// The picture on its own, filling the screen, with pinch to zoom.
struct SatellitePictureScreen: View {
    let url: URL
    let picture: SatellitePicture
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .aspectRatio(picture.aspectRatio, contentMode: .fit)
                .frame(width: UIScreen.main.bounds.width * scale * pinch)
            }
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = min(6, max(1, scale * value.magnification)) }
            )
            .background(.black)
            .navigationTitle(picture.taken.map { tr("Sentinel-2, %@", Format.day($0)) } ?? tr("Satellite picture"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
    }
}
