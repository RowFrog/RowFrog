import Foundation

struct APIClient {
    let baseURL: URL
    var session: URLSession = .shared

    static func fromBundle(_ bundle: Bundle = .main) -> APIClient {
        let raw = bundle.object(forInfoDictionaryKey: "RWAPIBaseURL") as? String ?? "http://localhost:8000"
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
        try await get("lakes")
    }

    func forecast(clubID: String) async throws -> ClubForecast {
        try await get("clubs/\(clubID)/forecast")
    }

#if !WIDGET_EXTENSION
    // The widget doesn't show the lake view, so it leaves out LakeView.swift.
    func lakeView(lakeID: String) async throws -> LakeView {
        try await get("lakes/\(lakeID)/view")
    }
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
