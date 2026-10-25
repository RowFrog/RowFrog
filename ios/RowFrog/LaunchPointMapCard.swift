import MapKit
import SwiftUI

/// Where the forecast is for: the club's launch point on a map, with its
/// coordinates and a button to open it in Apple Maps.
struct LaunchPointMapCard: View {
    let club: Club

    /// Back at the preset view whenever the page shows again or the club changes.
    @State private var position: MapCameraPosition = .automatic
    @State private var moved = false
    /// The club's own place in Apple Maps, when it has one.
    @State private var place: MKMapItem?

    private var home: MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)
    }

    var body: some View {
        Card(title: tr("Launch point"), symbol: "mappin.and.ellipse") {
            // A drag on the map moves the map; outside it the page scrolls.
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                Marker(club.displayName, systemImage: "figure.rower", coordinate: coordinate)
                    .tint(.blue)
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .onEnd) { context in
                moved = CLLocation(latitude: context.region.center.latitude, longitude: context.region.center.longitude)
                    .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) > 30
                    || abs(context.region.span.latitudeDelta - home.span.latitudeDelta) > home.span.latitudeDelta * 0.1
                    || context.camera.heading.magnitude > 1
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
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear { reset(animated: false) }
            .onChange(of: club.id) { reset(animated: false) }
            .accessibilityLabel(tr("Map of the launch point of %@", club.displayName))

            Text(tr("The forecast, waves and warnings are for this point."))
            if let name = place?.name {
                Label(tr("In Apple Maps as \u{201C}%@\u{201D}", name), systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !club.launchPointVerified {
                Label(club.source == "drv" ? tr("Not yet confirmed by the club; taken from the club's address.") : tr("Not yet confirmed by the club; taken from OpenStreetMap."), systemImage: "mappin.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Text(String(format: tr("%.5f° N, %.5f° E"), club.launchPoint.lat, club.launchPoint.lon))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Menu {
                    if place != nil {
                        Button(tr("The club in Apple Maps"), systemImage: "building.2") { place?.openInMaps() }
                    }
                    Button(tr("Directions to the club"), systemImage: "car") { Task { await openClubInMaps() } }
                    Button(tr("Launch point on the map"), systemImage: "mappin.and.ellipse") { openInMaps() }
                } label: {
                    Label(tr("Open in Maps"), systemImage: "map")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
        .font(.subheadline)
        .task(id: club.id) {
            place = club.isOwnPlace ? nil : await ClubPlaces.shared.place(for: club)
        }
    }

    /// Directions to the club's address, since the launch point at the water
    /// has no address to drive to. Falls back to the launch point when Maps
    /// can't find the address.
    @MainActor private func openClubInMaps() async {
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

    private func reset(animated: Bool) {
        if animated {
            withAnimation { position = .region(home) }
        } else {
            position = .region(home)
        }
        moved = false
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = club.displayName
        item.openInMaps(launchOptions: [MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate)])
    }
}
