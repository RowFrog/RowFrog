import SwiftUI
import XCTest
@testable import RowFrog

/// Serves the sample forecast (testdata/api/v1, a full 10-day forecast) for
/// every club, moved so its first hour is the current one; anything else is
/// not found, as for a lake without a lake view.
private final class SampleForecastStub: URLProtocol {
    static var forecast = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isForecast = request.url!.lastPathComponent == "forecast"
        let response = HTTPURLResponse(url: request.url!, statusCode: isForecast ? 200 : 404, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if isForecast { client?.urlProtocol(self, didLoad: Self.forecast) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The speed guard: reading a full forecast and showing a club page with it
/// must not take far longer than it does today. The limits are several times
/// the slowest CI runner's times (see docs/handbook.md), so only a real slow
/// down fails, as when a change makes every hour's row work out the whole
/// forecast again.
@MainActor
final class SpeedGuardTests: XCTestCase {
    /// Seconds, generous on purpose: the Intel runners are slow and uneven.
    private static let decodeLimit = 1.0
    private static let lightsLimit = 1.0
    private static let pageLimit = 8.0

    private static let sampleFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "testdata/api/v1/clubs/mrc-1880/forecast")

    /// The sample with every time moved by the same amount, so its first hour is now.
    private static func movedSample() throws -> Data {
        let data = try Data(contentsOf: sampleFile)
        let first = try APIClient.decoder.decode(ClubForecast.self, from: data).hours[0].time
        let hour = Calendar.current.dateInterval(of: .hour, for: .now)!.start
        let shift = hour.timeIntervalSince(first)
        let iso = ISO8601DateFormatter()
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        let days = (shift / 86_400).rounded()
        func move(_ value: Any) -> Any {
            switch value {
            case let text as String:
                if text.count >= 20, let date = iso.date(from: text) {
                    return iso.string(from: date.addingTimeInterval(shift))
                }
                if text.count == 10, let date = day.date(from: text) {
                    return day.string(from: date.addingTimeInterval(days * 86_400))
                }
                return text
            case let list as [Any]: return list.map(move)
            case let object as [String: Any]: return object.mapValues(move)
            default: return value
            }
        }
        return try JSONSerialization.data(withJSONObject: move(try JSONSerialization.jsonObject(with: data)))
    }

    private func seconds(_ work: () throws -> Void) rethrows -> Double {
        let start = Date()
        try work()
        return Date().timeIntervalSince(start)
    }

    func testReadingTheFullForecastIsQuick() throws {
        let data = try Self.movedSample()
        let took = try seconds { for _ in 0..<10 { _ = try APIClient.decoder.decode(ClubForecast.self, from: data) } } / 10
        print("Speed guard: reading the forecast took \(took) s")
        XCTAssertLessThan(took, Self.decodeLimit, "reading the sample forecast took \(took) s")
    }

    func testWorkingOutTheLightsForAnotherBoatIsQuick() throws {
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Self.movedSample())
        let limits = AppSettings.shared.limits(at: "mrc-1880")
        // Worked out again from the forecast as sent, as after a change of boat or limits.
        let took = seconds { for _ in 0..<5 { _ = forecast.applying(limits).hours.map(\.light) } } / 5
        print("Speed guard: working out the lights took \(took) s")
        XCTAssertLessThan(took, Self.lightsLimit, "working out the lights took \(took) s")
    }

    func testClubPageWithAFullForecastShowsQuickly() async throws {
        SampleForecastStub.forecast = try Self.movedSample()
        let forecasts = store()
        await forecasts.load("mrc-1880")
        let club = Club(id: "mrc-1880", name: "Münchener Ruder-Club von 1880", shortName: "MRC 1880", address: "Starnberg",
                        website: nil, launchPoint: Coordinate(lat: 47.9995, lon: 11.3434), launchPointVerified: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        func show() -> Double {
            seconds {
                let host = UIHostingController(rootView: LocationPageView(club: club, lake: nil, isHome: true, forecasts: forecasts))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                CATransaction.flush()
            }
        }
        // The first page in the test run also pays for SwiftUI, fonts and
        // pictures loading once; the guard holds the second, the page's own work.
        let first = show()
        let took = show()
        print("Speed guard: showing the club page took \(took) s (the first time \(first) s)")
        XCTAssertLessThan(took, Self.pageLimit, "showing the club page took \(took) s")
        window.isHidden = true
    }

    private func store() -> ForecastStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SampleForecastStub.self]
        let api = APIClient(baseURL: URL(string: "https://example.invalid/v1")!,
                            session: URLSession(configuration: configuration), cache: nil)
        AppSettings.shared.pickedModels = [:]
        return ForecastStore(api: api)
    }
}
