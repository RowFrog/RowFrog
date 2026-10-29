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
}
