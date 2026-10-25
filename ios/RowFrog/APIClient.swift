import Foundation

/// The server answered, but not with the file: 404, 500 and so on.
struct HTTPStatusError: Error {
    let code: Int
}

struct APIClient {
    let baseURL: URL
    var session: URLSession = .shared
    /// The last copy of each file, so an unchanged one is not downloaded again; nil = none.
    var cache: KeptFiles? = .shared

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

    /// The club catalog changes when clubs are added, not with the weather:
    /// it is asked for again after a day, and the kept copy serves when offline.
    static let catalogAge: TimeInterval = 24 * 3600

    func lakes() async throws -> [Lake] {
        // "lakes/index" rather than "lakes": the published files keep lakes/<id>/view beside it.
        try await get("lakes/index", keepFor: Self.catalogAge)
    }

    /// The countries the club search covers; older backends have none (then `lakes()` holds every club).
    func countries() async throws -> [Country] {
        try await get("countries/index", keepFor: Self.catalogAge)
    }

    /// One country's waters with that country's clubs.
    func lakes(country: String) async throws -> [Lake] {
        try await get("countries/\(country)/lakes", keepFor: Self.catalogAge)
    }

    /// `model` is a model the user picked (developer options); nil = the automatic choice.
    func forecast(clubID: String, model: String? = nil) async throws -> ClubForecast {
        if let model { return try await get("clubs/\(clubID)/models/\(model)/forecast") }
        return try await get("clubs/\(clubID)/forecast")
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

    /// A published file. Forecasts are always asked for, but with the kept copy's
    /// ETag, so an unchanged file answers "304 Not Modified" (a few hundred bytes)
    /// instead of coming again. With `keepFor`, a kept copy younger than that is
    /// used without asking, and an older one when the server can't be reached.
    private func get<T: Decodable>(_ path: String, keepFor: TimeInterval? = nil) async throws -> T {
        let url = baseURL.appending(path: path)
        let kept = cache?.copy(of: url)
        if let kept, let keepFor, kept.age < keepFor, let value = try? Self.decoder.decode(T.self, from: kept.data) {
            return value
        }
        // The system's own cache stays out: it would hold files up to GitHub's 10 minutes.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        if let kept { request.setValue(kept.etag, forHTTPHeaderField: "If-None-Match") }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if keepFor != nil, let kept, let value = try? Self.decoder.decode(T.self, from: kept.data) { return value }
            throw error
        }
        let http = response as? HTTPURLResponse
        if http?.statusCode == 304, let kept {
            if let value = try? Self.decoder.decode(T.self, from: kept.data) {
                cache?.touch(url)
                return value
            }
            // Kept by an older app that read it differently: fetch it whole.
            cache?.remove(url)
            return try await get(path, keepFor: keepFor)
        }
        if let http, !(200..<300).contains(http.statusCode) {
            throw HTTPStatusError(code: http.statusCode)
        }
        let value = try Self.decoder.decode(T.self, from: data)
        if let etag = http?.value(forHTTPHeaderField: "ETag") { cache?.keep(data, etag: etag, for: url) }
        return value
    }
}

/// The last copy of each published file with its ETag, in Caches/API (the
/// system may clear it when space runs low; the files then just load again).
struct KeptFiles: Sendable {
    let folder: URL
    static let shared = KeptFiles(folder: URL.cachesDirectory.appending(path: "API", directoryHint: .isDirectory))

    struct Copy {
        let data: Data
        let etag: String
        /// Since it was downloaded or the server last said it is unchanged.
        let age: TimeInterval
    }

    func copy(of url: URL) -> Copy? {
        let body = file(url, "body")
        guard let data = try? Data(contentsOf: body),
              let etag = try? String(contentsOf: file(url, "etag"), encoding: .utf8),
              let modified = (try? FileManager.default.attributesOfItem(atPath: body.path))?[.modificationDate] as? Date else { return nil }
        return Copy(data: data, etag: etag, age: Date.now.timeIntervalSince(modified))
    }

    func keep(_ data: Data, etag: String, for url: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file(url, "body"), options: .atomic)
        try? etag.write(to: file(url, "etag"), atomically: true, encoding: .utf8)
    }

    /// The server said the copy is unchanged: it counts as new again.
    func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file(url, "body").path)
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: file(url, "body"))
        try? FileManager.default.removeItem(at: file(url, "etag"))
    }

    /// "api.rowfrog.com_v1_clubs_mrc-1880_forecast.body"
    private func file(_ url: URL, _ kind: String) -> URL {
        let name = ((url.host() ?? "") + url.path()).map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return folder.appending(path: String(name) + "." + kind)
    }
}
