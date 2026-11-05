import MapKit
import SwiftUI

/// A launch point suggested for a club whose club has not confirmed its own:
/// the point the user moved the map to, sent to the Row Frog service
/// (cloudflare/suggestions, kind "launchPoint"), which files it as a public
/// GitHub issue. The owner checks it and answers "/accept"; the workflow
/// "Accept launch point" puts it into the hand-checked list. Only the club and
/// the point are sent, never the user's own location.
struct LaunchPointSuggestion: Equatable {
    let club: Club
    let point: Coordinate

    /// The body for the service.
    func request(api: APIClient) throws -> URLRequest {
        struct Body: Encodable { let name: String, kind: String, club: String, lat: Double, lon: Double }
        var request = URLRequest(url: api.baseURL.appending(path: "suggestions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(
            name: String(club.name.prefix(80)), kind: "launchPoint", club: club.id, lat: point.lat, lon: point.lon))
        return request
    }

    /// A prefilled GitHub issue with the same lines, for when the service cannot
    /// take it. The user sends it from the page that opens.
    var issueURL: URL? {
        let lat = String(format: "%.6f", point.lat), lon = String(format: "%.6f", point.lon)
        let body = """
        Suggested from the app: where this club's boats go on the water.

        - Club: `\(club.name)`
        - Club id: `\(club.id)`
        - Launch point: \(lat), \(lon)
        """
        var parts = URLComponents(string: "https://github.com/RowFrog/RowFrog/issues/new")
        parts?.queryItems = [
            URLQueryItem(name: "title", value: "Launch point suggestion: \(club.name)"),
            URLQueryItem(name: "labels", value: "launch point suggestion"),
            URLQueryItem(name: "body", value: body),
        ]
        return parts?.url
    }

    /// Sends it; true when the service took it.
    func send(api: APIClient) async -> Bool {
        guard let request = try? request(api: api),
              let (_, response) = try? await api.session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// Clubs the user already sent a launch point for, so the sheet thanks
    /// them instead of asking again. Kept on this iPhone only.
    static let sentKey = "RWSuggestedLaunchPoints"

    static func wasSent(forID id: String) -> Bool {
        UserDefaults.standard.stringArray(forKey: sentKey)?.contains(id) == true
    }

    static func markSent(forID id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: sentKey) ?? []
        if !ids.contains(id) { ids.append(id) }
        UserDefaults.standard.set(ids, forKey: sentKey)
    }

    /// Whether the Location sheet offers it: a club from the lists whose club
    /// has not confirmed the launch point.
    static func isOffered(for club: Club) -> Bool {
        !club.launchPointVerified && !club.isOwnPlace
    }
}

/// Move the map under the fixed oars until they sit where the club's boats
/// go on the water, then send. Opens on today's forecast point, close in on
/// satellite pictures.
struct SuggestLaunchPointView: View {
    let club: Club
    @State private var camera: MapCameraPosition
    @State private var center: Coordinate
    @State private var satellite = true
    @State private var sending = false
    @State private var failed = false
    @State private var location = DeviceLocation()
    @State private var wantsLocation = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(club: Club) {
        self.club = club
        _center = State(initialValue: club.launchPoint)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon),
            latitudinalMeters: 400, longitudinalMeters: 400)))
    }

    private var start: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)
    }

    /// How far the point is from today's forecast point, so the user sees it moved.
    private var moved: CLLocationDistance {
        CLLocation(latitude: center.lat, longitude: center.lon)
            .distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack {
                        Map(position: $camera) {
                            // Today's forecast point, so the user sees where they start from.
                            Annotation("", coordinate: start) {
                                Circle().fill(.white.opacity(0.9)).frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(.gray, lineWidth: 1))
                            }
                        }
                        .mapStyle(satellite ? .imagery : .standard)
                        .onMapCameraChange(frequency: .continuous) { context in
                            center = Coordinate(lat: context.region.center.latitude, lon: context.region.center.longitude)
                        }
                        // The oars stay in the middle; the map moves under them.
                        Image(systemName: ClubMarks.launchSymbol)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.accentColor))
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .frame(height: 340)
                    .listRowInsets(EdgeInsets())
                    Toggle(tr("Satellite view"), isOn: $satellite)
                    Button(tr("Where I am"), systemImage: "location") {
                        wantsLocation = true
                        location.request()
                    }
                } header: {
                    Text(tr("Move the map until the oars sit where the club's boats go on the water"))
                } footer: {
                    Text(moved < 5
                        ? tr("The white dot is where the forecast is worked out today.")
                        : tr("%@ from where the forecast is worked out today (white dot).", Self.distanceText(moved)))
                }
                Section {
                    Text(tr("Only the club and this point are sent to us, never where you are. The suggestion becomes a public issue on GitHub; we check it on the satellite view before the forecast uses it."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if failed {
                        Label(tr("It could not be sent. You can send it from GitHub instead."), systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(tr("Suggest the launch point"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button(failed ? tr("Open GitHub") : tr("Send"), action: send)
                    }
                }
            }
            // "Where I am": the map goes to the user; the position stays on this iPhone.
            .onChange(of: location.coordinate) {
                guard wantsLocation, let here = location.coordinate else { return }
                wantsLocation = false
                withAnimation {
                    camera = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: here.lat, longitude: here.lon),
                        latitudinalMeters: 300, longitudinalMeters: 300))
                }
            }
        }
    }

    static func distanceText(_ metres: CLLocationDistance) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = metres < 1000 ? 0 : 1
        formatter.locale = AppSettings.shared.locale
        return formatter.string(from: Measurement(value: metres.rounded(), unit: UnitLength.meters))
    }

    private func send() {
        let suggestion = LaunchPointSuggestion(club: club, point: center)
        if failed {
            if let url = suggestion.issueURL { openURL(url) }
            LaunchPointSuggestion.markSent(forID: club.id)
            dismiss()
            return
        }
        sending = true
        Task {
            let ok = await suggestion.send(api: .fromBundle())
            sending = false
            if ok {
                LaunchPointSuggestion.markSent(forID: club.id)
                dismiss()
            } else {
                failed = true
            }
        }
    }
}
