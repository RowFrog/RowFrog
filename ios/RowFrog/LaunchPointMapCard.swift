import MapKit
import SwiftUI

/// Where the forecast is for: the club's launch point on a map, with its
/// coordinates and a button to open it in Apple Maps.
struct LaunchPointMapCard: View {
    let club: Club

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)
    }

    var body: some View {
        Card(title: tr("Launch point"), symbol: "mappin.and.ellipse") {
            // Zoom only, so a drag over the map still scrolls the page.
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)), interactionModes: [.zoom]) {
                Marker(club.displayName, systemImage: "figure.rower", coordinate: coordinate)
                    .tint(.blue)
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(tr("Map of the launch point of %@", club.displayName))

            Text(tr("The forecast, waves and warnings are for this point."))
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
                Button(tr("Open in Maps"), systemImage: "map") { openInMaps() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            }
        }
        .font(.subheadline)
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = club.displayName
        item.openInMaps(launchOptions: [MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate)])
    }
}
