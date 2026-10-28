import XCTest
@testable import RowFrog

/// Answers every forecast request with a small forecast and notes the club asked for.
private final class ForecastStub: URLProtocol {
    private static let lock = NSLock()
    private static var _asked: [String] = []
    static var asked: [String] {
        get { lock.withLock { _asked } }
        set { lock.withLock { _asked = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let parts = request.url!.pathComponents
        let club = parts[parts.firstIndex(of: "clubs")! + 1]
        Self.lock.withLock { Self._asked.append(club) }
        let json = """
        {"clubId": "\(club)", "lakeId": "starnberger-see", "generatedAt": "2026-10-28T13:51:00+00:00",
         "attribution": [], "hours": [], "daylight": []}
        """
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class RefreshOnReturnTests: XCTestCase {
    private func store() -> ForecastStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ForecastStub.self]
        let api = APIClient(baseURL: URL(string: "https://example.invalid/v1")!,
                            session: URLSession(configuration: configuration), cache: nil)
        return ForecastStore(api: api)
    }

    override func setUp() {
        super.setUp()
        ForecastStub.asked = []
        AppSettings.shared.pickedModels = [:]
    }

    func testTheShownClubLoadsFirstThenTheOthers() async {
        let forecasts = store()
        await forecasts.refreshOnReturn(first: ["b"], then: ["a", "b", "c"])
        XCTAssertEqual(ForecastStub.asked.first, "b")
        XCTAssertEqual(Set(ForecastStub.asked), ["a", "b", "c"])
        XCTAssertEqual(ForecastStub.asked.count, 3, "the shown club loads once")
        XCTAssertNotNil(forecasts.loadedAt["a"])
        XCTAssertTrue(forecasts.loading.isEmpty)
    }

    func testClubsLoadedInTheLastTenMinutesAreLeftAlone() async {
        let forecasts = store()
        await forecasts.load("a")
        ForecastStub.asked = []
        await forecasts.refreshOnReturn(first: ["a"], then: ["a", "b"])
        XCTAssertEqual(ForecastStub.asked, ["b"])
    }

    func testThePageSaysWhenTheForecastWasMadeAndWhenItLoaded() {
        let made = Date(timeIntervalSince1970: 1_800_000_000)
        let line = LocationPageView.updatedLine(forecast: made, loaded: made.addingTimeInterval(48 * 60))
        XCTAssertTrue(line.contains(Format.time(made)))
        XCTAssertTrue(line.contains(Format.time(made.addingTimeInterval(48 * 60))))
        XCTAssertFalse(LocationPageView.updatedLine(forecast: made, loaded: made.addingTimeInterval(10)).contains("·  ·"))
        XCTAssertEqual(LocationPageView.updatedLine(forecast: made, loaded: nil),
                       LocationPageView.updatedLine(forecast: made, loaded: made.addingTimeInterval(10)))
    }
}
