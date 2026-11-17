import XCTest
@testable import RowFrog

/// Fails every request as if the phone had no internet, and counts them.
private final class OfflineStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

/// Started without internet, the club page shows the forecast kept from the
/// last download with the reason the update failed, as after a return to the
/// app (owner's screenshots, 16 Nov 2026), instead of "No forecast".
@MainActor
final class KeptForecastTests: XCTestCase {
    private var folder: URL!
    private let base = URL(string: "https://api.rowfrog.com/v1")!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        AppSettings.shared.pickedModels = [:]
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func api() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineStub.self]
        return APIClient(baseURL: base, session: URLSession(configuration: configuration), cache: KeptFiles(folder: folder))
    }

    /// A forecast file as the server sends it, with one hour starting `hourFromNow`.
    private func keep(club: String, hourFromNow: TimeInterval, keptAgo: TimeInterval) throws {
        let time = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(hourFromNow))
        let json = """
        {"clubId": "\(club)", "lakeId": "starnberger-see", "generatedAt": "\(ISO8601DateFormatter().string(from: .now.addingTimeInterval(-keptAgo)))",
         "attribution": [], "daylight": [],
         "hours": [{"time": "\(time)", "light": "green", "reasons": [], "windSpeedMs": 2, "temperatureC": 10}]}
        """
        let url = base.appending(path: "clubs/\(club)/forecast")
        let files = KeptFiles(folder: folder)
        files.keep(Data(json.utf8), etag: #"W/"k-1""#, for: url)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-keptAgo)],
                                              ofItemAtPath: folder.appending(path: "api.rowfrog.com_v1_clubs_\(club)_forecast.body").path)
    }

    func testColdStartOfflineShowsTheKeptForecastWithTheReason() async throws {
        try keep(club: "mrc-1880", hourFromNow: 1800, keptAgo: 1800)
        let forecasts = ForecastStore(api: api())
        await forecasts.load("mrc-1880")
        XCTAssertEqual(forecasts.forecast("mrc-1880")?.clubId, "mrc-1880")
        XCTAssertEqual(forecasts.status("mrc-1880"), .updateFailed(.offline, outOfDate: false))
        // When it came, not now: a return to the app loads it again.
        let loaded = try XCTUnwrap(forecasts.loadedAt["mrc-1880"])
        XCTAssertEqual(loaded.timeIntervalSinceNow, -1800, accuracy: 5)
        XCTAssertTrue(forecasts.loading.isEmpty)
    }

    func testWithoutAKeptForecastItStillSaysNoForecast() async {
        let forecasts = ForecastStore(api: api())
        await forecasts.load("mrc-1880")
        XCTAssertNil(forecasts.forecast("mrc-1880"))
        XCTAssertEqual(forecasts.status("mrc-1880"), .noForecast(.offline))
    }

    func testAKeptForecastWhoseHoursAreAllPastIsNotShown() async throws {
        try keep(club: "mrc-1880", hourFromNow: -2 * 3600, keptAgo: 3 * 86400)
        let kept = await api().keptForecast(clubID: "mrc-1880")
        XCTAssertNil(kept)
    }

    /// Cold start (decision 0046): the kept forecast is there before the first
    /// frame, marked as updating, and the page's first load still downloads.
    func testColdStartShowsTheKeptForecastBeforeTheFirstLoad() async throws {
        try keep(club: "mrc-1880", hourFromNow: 1800, keptAgo: 600)
        let forecasts = ForecastStore(api: api())
        forecasts.primeKept("mrc-1880")
        XCTAssertEqual(forecasts.forecast("mrc-1880")?.clubId, "mrc-1880")
        XCTAssertEqual(forecasts.status("mrc-1880"), .updating)
        // The first load is not skipped although a forecast shows: offline, it ends with the reason.
        await forecasts.load("mrc-1880")
        XCTAssertEqual(forecasts.status("mrc-1880"), .updateFailed(.offline, outOfDate: false))
    }

    func testColdStartWithNothingKeptLeavesTheStandInCards() {
        let forecasts = ForecastStore(api: api())
        forecasts.primeKept("mrc-1880")
        XCTAssertNil(forecasts.forecast("mrc-1880"))
        XCTAssertTrue(forecasts.loading.isEmpty)
    }

    func testAnyKeptFileReadsStraightAway() throws {
        let url = base.appending(path: "countries/index")
        KeptFiles(folder: folder).keep(Data(#"[{"code": "de"}]"#.utf8), etag: "", for: url)
        let kept: [[String: String]]? = api().keptNow("countries/index")
        XCTAssertEqual(kept?.first?["code"], "de")
        let missing: [[String: String]]? = api().keptNow("countries/at/lakes")
        XCTAssertNil(missing)
    }

    func testDownloadsGiveUpWithinFifteenSecondsOfSilence() {
        XCTAssertEqual(APIClient.session.configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(APIClient.session.configuration.timeoutIntervalForResource, 60)
    }
}
