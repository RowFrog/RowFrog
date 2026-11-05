import MapKit
import SwiftUI

/// Where the forecast is for: the club's launch point on a map, with its
/// coordinates and a button to open it in Apple Maps. The map is a still
/// picture until tapped, since a live map on every club page costs battery.
/// The page shows it as a card when the launch point is not in the header
/// (Settings > Club pages); otherwise the header opens it as a sheet.
struct LaunchPointMapCard: View {
    let club: Club

    var body: some View {
        Card(title: tr("Launch point"), symbol: "mappin.and.ellipse") {
            // Taller when the club page's columns need it filled (BalancedColumns).
            LaunchPointDetails(club: club, mapHeight: 220, mapMaxHeight: .infinity)
        }
        .font(.subheadline)
    }
}

/// "Location": the launch point opened from the club page's header, with the
/// same map, note, coordinates and Open in Maps as the card. It comes up only as far as its
/// content needs and can be pulled up to full height.
struct LaunchPointSheet: View {
    let club: Club
    @Environment(\.dismiss) private var dismiss
    /// Everything but the map, measured; until it is known, a guess close to a phone's.
    @State private var restHeight: CGFloat = 150
    @State private var detent: PresentationDetent = .height(LaunchPointSheet.mapHeight + 150 + LaunchPointSheet.barHeight)

    /// Room for the title bar above the content.
    static let barHeight: CGFloat = 64
    /// The map's height while the sheet is only as high as it needs.
    static let mapHeight: CGFloat = 320

    private var fitted: PresentationDetent { .height(Self.mapHeight + restHeight + Self.barHeight) }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // Pulled up to full height, the map takes all the room the rest leaves.
                let map = detent == .large ? max(Self.mapHeight, geometry.size.height - restHeight) : Self.mapHeight
                ScrollView {
                    LaunchPointDetails(club: club, mapHeight: map, mapMaxHeight: map, startsLive: true)
                        .padding()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            let rest = height - map
                            if abs(rest - restHeight) > 1 { restHeight = rest }
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .animation(.smooth, value: detent)
            }
            .navigationTitle(tr("Location"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // The same as pulling the sheet up or down.
                    Button {
                        withAnimation(.smooth) { detent = detent == .large ? fitted : .large }
                    } label: {
                        Image(systemName: detent == .large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(detent == .large ? tr("Smaller map") : tr("Map full screen"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
        // As far up as the content needs; pulled up, the map fills the screen.
        // Larger text sizes reach full height and scroll.
        .presentationDetents([fitted, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: restHeight) { if detent != .large { detent = fitted } }
        // Screenshot hook: `-RWLaunchPointFull YES` opens it at full height.
        .onAppear { if UserDefaults.standard.bool(forKey: "RWLaunchPointFull") { detent = .large } }
    }
}

/// The map, the note on what it is for, and the coordinates with Open in Maps.
struct LaunchPointDetails: View {
    let club: Club
    let mapHeight: CGFloat
    let mapMaxHeight: CGFloat
    /// Live from the start: in the sheet nothing scrolls under it, so a still
    /// picture first would only cost a tap.
    let startsLive: Bool

    /// Back at the preset view whenever the page shows again or the club changes.
    @State private var position: MapCameraPosition = .automatic
    @State private var moved = false
    /// Flipped on every refit: setting the same region again is no change to
    /// SwiftUI, so a map that grew would otherwise keep its old scale.
    @State private var refit = false
    /// The club's own place in Apple Maps, when it has one.
    @State private var place: MKMapItem?
    /// Where the clubhouse is, when the launch point is set and the clubhouse apart from it.
    private var clubhouse: CLLocationCoordinate2D? { ClubMarks.clubhouse(of: club) }
    /// The map's size in points, for how far apart the two pins are on screen.
    @State private var mapSize: CGSize = .zero
    /// Zoomed in far enough that the clubhouse and launch point get a pin each.
    @State private var split = false
    /// The span the map shows, so the pins can split when the clubhouse is found after the map settled.
    @State private var span: MKCoordinateSpan?
    /// Apple's satellite pictures instead of the map, remembered for every launch point.
    @AppStorage("RWLaunchImagery") private var imagery = false
    /// The live map after a tap; a still picture again once the page is swiped away.
    @State private var live = UserDefaults.standard.bool(forKey: "RWLiveLaunchMap")

    init(club: Club, mapHeight: CGFloat, mapMaxHeight: CGFloat, startsLive: Bool = false) {
        self.club = club
        self.mapHeight = mapHeight
        self.mapMaxHeight = mapMaxHeight
        self.startsLive = startsLive
        _live = State(initialValue: startsLive || UserDefaults.standard.bool(forKey: "RWLiveLaunchMap"))
    }
    @Environment(\.isCurrentPage) private var isCurrentPage
    @Environment(\.openURL) private var openURL
    private var mapApp: MapApp { AppSettings.shared.mapApp }

    private var home: MKCoordinateRegion {
        // Screenshot hook: `-RWLaunchSpan 300` opens the map closer in.
        let span = UserDefaults.standard.double(forKey: "RWLaunchSpan")
        let metres = (span > 0 ? span : 1500) + (refit ? 0.01 : 0)
        return MKCoordinateRegion(center: coordinate, latitudinalMeters: metres, longitudinalMeters: metres)
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if live {
                    liveMap
                } else {
                    Button { live = true } label: {
                        LaunchPointSnapshot(coordinate: coordinate, region: home, symbol: LocationStore.markSymbol(for: club.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(tr("Shows a map you can move"))
                }
            }
            .frame(minHeight: mapHeight, idealHeight: mapHeight, maxHeight: mapMaxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onChange(of: isCurrentPage) { if !isCurrentPage { live = startsLive } }
            .onChange(of: club.id) { live = startsLive }
            .accessibilityLabel(tr("Map of the launch point of %@", club.displayName))

            forecastPointLine
            if mapApp == .apple, let name = place?.name {
                Label(tr("In Apple Maps as \u{201C}%@\u{201D}", name), systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(String(format: tr("%.5f° N, %.5f° E"), club.launchPoint.lat, club.launchPoint.lon))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Menu {
                    // Apple Maps' own page of the club offers the route with one tap,
                    // so the extra row is only there when the club has no such page.
                    if mapApp == .apple, place != nil {
                        Button(tr("The club in Apple Maps"), systemImage: "building.2") { place?.openInMaps() }
                    } else {
                        Button(tr("Directions to the club"), systemImage: "car") { Task { await openClubInMaps() } }
                    }
                    Button(tr("Launch point on the map"), systemImage: "mappin.and.ellipse") { openInMaps() }
                } label: {
                    // The bordered look drawn here, so the 44 pt tap area around it counts.
                    Label(tr("Open in Maps"), systemImage: "map")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .tapArea(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                }
                .font(.caption.weight(.semibold))
            }
        }
        .task(id: club.id) {
            place = club.isOwnPlace ? nil : await ClubPlaces.shared.place(for: club)
            split = false
        }
    }

    /// Which point this club's forecast is for, said for this club. It doesn't
    /// change with the zoom, so the sheet keeps its height as the pins split and join.
    @ViewBuilder private var forecastPointLine: some View {
        if club.hasLaunchPoint {
            if clubhouse != nil {
                Label(tr("The forecast, waves and warnings are for the launch point (oars), not the clubhouse."), systemImage: ClubMarks.launchSymbol)
            } else {
                Label(tr("The forecast, waves and warnings are for the club's launch point."), systemImage: ClubMarks.launchSymbol)
            }
        } else {
            Label(club.source == "drv"
                  ? tr("No launch point set yet: the forecast, waves and warnings are for the club's address.")
                  : tr("No launch point set yet: the forecast, waves and warnings are for the club's place on OpenStreetMap."),
                  systemImage: "mappin.slash")
                .foregroundStyle(.orange)
        }
    }

    /// Whether the two pins are far enough apart on screen to show both (`ClubMarks`).
    static func shouldSplit(_ clubhouse: CLLocationCoordinate2D, from launch: CLLocationCoordinate2D,
                            span: MKCoordinateSpan, size: CGSize, now: Bool) -> Bool {
        guard size.width > 0, size.height > 0, span.latitudeDelta > 0, span.longitudeDelta > 0 else { return false }
        let dx: Double = (clubhouse.longitude - launch.longitude) / span.longitudeDelta * Double(size.width)
        let dy: Double = (clubhouse.latitude - launch.latitude) / span.latitudeDelta * Double(size.height)
        return ClubMarks.shouldSplit(apart: CGFloat((dx * dx + dy * dy).squareRoot()), now: now)
    }

    /// A drag on the map moves the map; outside it the page scrolls.
    private var liveMap: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            // Zoomed out one pin, as on every map; zoomed in, the club's pin moves to
            // the clubhouse and oars mark the launch point the forecast is for.
            Marker(club.displayName, systemImage: LocationStore.markSymbol(for: club.id), coordinate: split ? clubhouse ?? coordinate : coordinate)
                .tint(.blue)
            if split {
                Marker(tr("Launch point"), systemImage: ClubMarks.launchSymbol, coordinate: coordinate)
                    .tint(.blue)
            }
        }
        .mapStyle(imagery ? .imagery(elevation: .flat) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
        .onMapCameraChange(frequency: .continuous) { context in
            span = context.region.span
            updateSplit()
        }
        .onChange(of: mapSize) { updateSplit() }
        .onMapCameraChange(frequency: .onEnd) { context in
            let span = context.region.span
            let centre = CLLocation(latitude: context.region.center.latitude, longitude: context.region.center.longitude)
            let shifted: Bool = centre.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) > 30
            // MapKit fits the home region by one side only, so a taller or wider map
            // (the sheet pulled up) still counts as home while either side matches.
            let latOff: Double = abs(span.latitudeDelta - home.span.latitudeDelta) / home.span.latitudeDelta
            let lonOff: Double = abs(span.longitudeDelta - home.span.longitudeDelta) / home.span.longitudeDelta
            let zoomed: Bool = min(latOff, lonOff) > 0.1
            moved = shifted || zoomed || context.camera.heading.magnitude > 1
        }
        .overlay(alignment: .topLeading) {
            if moved {
                Button { reset(animated: true) } label: {
                    Image(systemName: "scope")
                        .font(.footnote.weight(.semibold))
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(tr("Back to the launch point"))
            }
        }
        // Map or Apple's satellite pictures, as in the lake map; remembered.
        .overlay(alignment: .topTrailing) {
            Button { imagery.toggle() } label: {
                Image(systemName: imagery ? "map" : "globe.europe.africa")
                    .font(.footnote.weight(.semibold))
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .tapArea(6)
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel(imagery ? tr("Show the map") : tr("Show satellite pictures"))
        }
        .onAppear { reset(animated: false) }
        .onChange(of: club.id) { reset(animated: false) }
        // A taller map (the sheet pulled up) keeps MapKit's scale; refit it to the
        // launch point unless the user had moved it.
        .onChange(of: mapHeight) { if !moved { reset(animated: true) } }
    }

    /// Directions to the club's address, since the launch point at the water
    /// has no address to drive to. Falls back to the launch point when Maps
    /// can't find the address.
    @MainActor private func openClubInMaps() async {
        if mapApp == .google {
            // Google finds the club by its name and address; a place of the user's own without one is its point.
            let address = club.address.trimmingCharacters(in: .whitespaces)
            let destination = address.isEmpty ? "\(club.launchPoint.lat),\(club.launchPoint.lon)" : "\(club.displayName), \(address)"
            openInGoogle(app: MapApp.googleAppDirections(to: destination), web: MapApp.googleDirections(to: destination))
            return
        }
        // The club's own place in Apple Maps is the best target when there is one.
        if let place {
            place.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = club.address
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            openInMaps()
            return
        }
        item.name = club.displayName
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    /// Google Maps' app when it is installed, else Google Maps in the browser.
    private func openInGoogle(app: URL?, web: URL?) {
        if let app, UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web {
            openURL(web)
        }
    }

    private func updateSplit() {
        guard let clubhouse, let span else { return }
        let now = Self.shouldSplit(clubhouse, from: coordinate, span: span, size: mapSize, now: split)
        if now != split { withAnimation(.smooth) { split = now } }
    }

    private func reset(animated: Bool) {
        refit.toggle()
        if animated {
            withAnimation { position = .region(home) }
        } else {
            position = .region(home)
        }
        moved = false
    }

    private func openInMaps() {
        if mapApp == .google {
            let point = "\(club.launchPoint.lat),\(club.launchPoint.lon)"
            openInGoogle(app: MapApp.googleAppSearch(point), web: MapApp.googleSearch(point))
            return
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = club.displayName
        item.openInMaps(launchOptions: [MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate)])
    }
}

/// A map as a still picture, made once per place, size and light or dark
/// look, with a mark in the middle: the launch point's (and the water station's).
/// Still pictures cost no battery while the page scrolls; a tap shows the live map.
struct LaunchPointSnapshot: View {
    let coordinate: CLLocationCoordinate2D
    let region: MKCoordinateRegion
    /// The club mark used on every map (LocationStore.markSymbol), or another place's symbol.
    let symbol: String
    var tint: Color = .blue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        GeometryReader { geometry in
            let key = "\(coordinate.latitude),\(coordinate.longitude),\(region.span.latitudeDelta),\(Int(geometry.size.width)),\(Int(geometry.size.height)),\(colorScheme == .dark)" as NSString
            ZStack {
                if let image {
                    Image(uiImage: image).resizable()
                } else {
                    Color(.secondarySystemBackground)
                }
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task(id: key) {
                if let cached = Self.cache.object(forKey: key) {
                    image = cached
                    return
                }
                guard geometry.size.width > 0 else { return }
                let options = MKMapSnapshotter.Options()
                options.region = region
                options.size = geometry.size
                options.scale = displayScale
                options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
                options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
                options.pointOfInterestFilter = .excludingAll
                if let snapshot = try? await MKMapSnapshotter(options: options).start() {
                    Self.cache.setObject(snapshot.image, forKey: key)
                    image = snapshot.image
                }
            }
        }
    }
}
