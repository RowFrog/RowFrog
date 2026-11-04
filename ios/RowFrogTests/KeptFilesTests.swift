import XCTest
@testable import RowFrog

/// Answers from a list the test fills, and records what the app asked.
final class StubProtocol: URLProtocol {
    static var answers: [(status: Int, headers: [String: String], body: Data)] = []
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard !Self.answers.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let answer = Self.answers.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class KeptFilesTests: XCTestCase {
    private var folder: URL!
    private var api: APIClient!
    private let countries = Data(#"[{"code":"de","name":"Germany","nameDe":"Deutschland","clubs":474,"bounds":{"south":47.5,"west":6.4,"north":54.8,"east":14.6}}]"#.utf8)

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        api = APIClient(baseURL: URL(string: "https://api.rowfrog.com/v1")!, session: URLSession(configuration: configuration),
                        cache: KeptFiles(folder: folder))
        StubProtocol.answers = []
        StubProtocol.requests = []
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testUnchangedFileIsNotDownloadedAgain() async throws {
        StubProtocol.answers = [(200, ["ETag": #"W/"abc-1""#], countries), (304, [:], Data())]
        let cache = KeptFiles(folder: folder)
        let url = URL(string: "https://api.rowfrog.com/v1/countries/index")!
        _ = try await api.countries()
        // Old enough to be asked for again.
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-2 * APIClient.catalogAge)],
                                              ofItemAtPath: folder.appending(path: "api.rowfrog.com_v1_countries_index.body").path)
        XCTAssertGreaterThan(try XCTUnwrap(cache.copy(of: url)).age, APIClient.catalogAge)
        let again = try await api.countries()
        XCTAssertEqual(again.map(\.code), ["de"])
        XCTAssertEqual(StubProtocol.requests.count, 2)
        XCTAssertNil(StubProtocol.requests[0].value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(StubProtocol.requests[1].value(forHTTPHeaderField: "If-None-Match"), #"W/"abc-1""#)
        // The 304 makes the copy new again.
        XCTAssertLessThan(try XCTUnwrap(cache.copy(of: url)).age, 60)
    }

    func testCatalogIsKeptForADay() async throws {
        StubProtocol.answers = [(200, ["ETag": #"W/"abc-1""#], countries)]
        _ = try await api.countries()
        let again = try await api.countries()
        XCTAssertEqual(again.map(\.code), ["de"])
        XCTAssertEqual(StubProtocol.requests.count, 1)
    }

    func testOldCatalogServesWhenTheServerAnswersWithAnError() async throws {
        StubProtocol.answers = [(200, ["ETag": #"W/"abc-1""#], countries), (503, [:], Data("busy".utf8)), (200, [:], Data("<html>".utf8))]
        _ = try await api.countries()
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-2 * APIClient.catalogAge)],
                                              ofItemAtPath: folder.appending(path: "api.rowfrog.com_v1_countries_index.body").path)
        // A server error, then an answer that isn't the file: the old copy serves both times.
        let afterError = try await api.countries()
        XCTAssertEqual(afterError.map(\.code), ["de"])
        let afterGarble = try await api.countries()
        XCTAssertEqual(afterGarble.map(\.code), ["de"])
        XCTAssertEqual(StubProtocol.requests.count, 3)
    }

    func testOldCatalogServesWhenOffline() async throws {
        StubProtocol.answers = [(200, ["ETag": #"W/"abc-1""#], countries)]
        _ = try await api.countries()
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-2 * APIClient.catalogAge)],
                                              ofItemAtPath: folder.appending(path: "api.rowfrog.com_v1_countries_index.body").path)
        // No answers left: the stub fails as if offline.
        let again = try await api.countries()
        XCTAssertEqual(again.map(\.code), ["de"])
        XCTAssertEqual(StubProtocol.requests.count, 2)
    }

    func testForecastIsAlwaysAskedForAndNotServedOffline() async throws {
        StubProtocol.answers = [(404, [:], Data())]
        do {
            _ = try await api.forecast(clubID: "nowhere")
            XCTFail("a missing forecast must not load")
        } catch {}
        XCTAssertNil(KeptFiles(folder: folder).copy(of: URL(string: "https://api.rowfrog.com/v1/clubs/nowhere/forecast")!))
    }

    // The widgets (WidgetForecasts): files in their own folder, one download per 15 minutes.

    private static let sampleForecast: Data = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "testdata/api/v1/clubs/mrc-1880/forecast")
        return try! Data(contentsOf: url)
    }()
    private let forecastFile = "api.rowfrog.com_v1_clubs_mrc-1880_forecast.body"

    func testWidgetsShareARecentForecast() async throws {
        StubProtocol.answers = [(200, ["ETag": #"W/"f-1""#], Self.sampleForecast)]
        let first = await WidgetForecasts.load("mrc-1880", api: api)
        let second = await WidgetForecasts.load("mrc-1880", api: api)
        XCTAssertEqual(first?.clubId, "mrc-1880")
        XCTAssertEqual(second?.clubId, "mrc-1880")
        XCTAssertEqual(StubProtocol.requests.count, 1)
    }

    func testWidgetAsksAgainWithTheETagAfterAQuarterHour() async throws {
        StubProtocol.answers = [(200, ["ETag": #"W/"f-1""#], Self.sampleForecast), (304, [:], Data())]
        _ = await WidgetForecasts.load("mrc-1880", api: api)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-WidgetForecasts.reuseFor - 60)],
                                              ofItemAtPath: folder.appending(path: forecastFile).path)
        let again = await WidgetForecasts.load("mrc-1880", api: api)
        XCTAssertEqual(again?.clubId, "mrc-1880")
        XCTAssertEqual(StubProtocol.requests.count, 2)
        XCTAssertEqual(StubProtocol.requests[1].value(forHTTPHeaderField: "If-None-Match"), #"W/"f-1""#)
    }

    func testWidgetShowsTheLastForecastOffline() async throws {
        StubProtocol.answers = [(200, [:], Self.sampleForecast)]
        _ = await WidgetForecasts.load("mrc-1880", api: api)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-6 * 3600)],
                                              ofItemAtPath: folder.appending(path: forecastFile).path)
        // No answers left: the stub fails as if offline. Kept without an ETag too.
        let offline = await WidgetForecasts.load("mrc-1880", api: api)
        XCTAssertEqual(offline?.clubId, "mrc-1880")
        XCTAssertEqual(WidgetForecasts.lastKept("mrc-1880", api: api)?.clubId, "mrc-1880")
        XCTAssertNil(StubProtocol.requests[1].value(forHTTPHeaderField: "If-None-Match"))
    }

    func testOwnPlaceForecastIsKeptAsAFile() throws {
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Self.sampleForecast)
        let id = OwnPlace.idPrefix + "test"
        XCTAssertNil(WidgetForecasts.lastKept(id, api: api))
        WidgetForecasts.keep(forecast, for: id, api: api)
        XCTAssertEqual(WidgetForecasts.lastKept(id, api: api)?.hours.count, forecast.hours.count)
    }

    func testOldCopiesInTheSharedSettingsAreDropped() throws {
        let name = "test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("old".utf8), forKey: "RWWidgetForecast-mrc-1880")
        defaults.set(Date.now, forKey: "RWWidgetLoaded-mrc-1880")
        defaults.set("mrc-1880", forKey: WidgetShared.homeKey)
        WidgetForecasts.dropOldCopies(defaults)
        XCTAssertNil(defaults.object(forKey: "RWWidgetForecast-mrc-1880"))
        XCTAssertNil(defaults.object(forKey: "RWWidgetLoaded-mrc-1880"))
        XCTAssertEqual(defaults.string(forKey: WidgetShared.homeKey), "mrc-1880")
    }
}
