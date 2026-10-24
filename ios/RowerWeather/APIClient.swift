import Foundation

struct APIClient {
    let baseURL: URL
    var session: URLSession = .shared

    static func fromBundle(_ bundle: Bundle = .main) -> APIClient {
        let raw = bundle.object(forInfoDictionaryKey: "RWAPIBaseURL") as? String ?? "http://localhost:8000"
        return APIClient(baseURL: URL(string: raw)!)
    }

    /// The published files, also in Debug builds that talk to the backend on the Mac.
    static func published(_ bundle: Bundle = .main) -> APIClient {
        let raw = bundle.object(forInfoDictionaryKey: "RWPublishedBaseURL") as? String ?? "https://api.rowfrog.com/v1"
        return APIClient(baseURL: URL(string: raw)!)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(text)"))
        }
        return decoder
    }()

    func lakes() async throws -> [Lake] {
        // "lakes/index" rather than "lakes": the published files keep lakes/<id>/view beside it.
        try await get("lakes/index")
    }

    /// The countries the club search covers; older backends have none (then `lakes()` holds every club).
    func countries() async throws -> [Country] {
        try await get("countries/index")
    }

    /// One country's waters with that country's clubs.
    func lakes(country: String) async throws -> [Lake] {
        try await get("countries/\(country)/lakes")
    }

    func forecast(clubID: String) async throws -> ClubForecast {
        try await get("clubs/\(clubID)/forecast")
    }

#if !WIDGET_EXTENSION
    // The widget doesn't show the lake view, so it leaves out LakeView.swift.
    func lakeView(lakeID: String) async throws -> LakeView {
        try await get("lakes/\(lakeID)/view")
    }

    /// The latest cloud-free satellite picture of the lake, where the backend has one.
    func satellitePicture(lakeID: String) async throws -> SatellitePicture {
        try await get("lakes/\(lakeID)/satellite")
    }

    func url(_ path: String) -> URL { baseURL.appending(path: path) }
#endif

    private func get<T: Decodable>(_ path: String) async throws -> T {
        // Published files are cached for minutes by GitHub Pages; never add a local cache on top.
        let request = URLRequest(url: baseURL.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try Self.decoder.decode(T.self, from: data)
    }
}
