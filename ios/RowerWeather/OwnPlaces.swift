import Foundation

/// A club, boathouse or spot on the water that the user put on the map
/// because no list has it. It is kept only on this iPhone; the user can
/// choose to suggest it for everyone's list (a GitHub issue for now).
struct OwnPlace: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case club, boathouse, water

        var title: String {
            switch self {
            case .club: tr("Club")
            case .boathouse: tr("Boathouse")
            case .water: tr("Place on the water")
            }
        }
    }

    static let idPrefix = "own-"

    let id: String
    var name: String
    var kind: Kind
    var website: URL?
    /// Where the user launches: the forecast is for this point.
    var coordinate: Coordinate
    /// The lake or river nearby from the club list, if one is close.
    var waterName: String?
    /// Whether the user chose to suggest it for everyone; never without the toggle.
    var shared: Bool
    let added: Date

    init(name: String, kind: Kind, website: URL?, coordinate: Coordinate, waterName: String?, shared: Bool, added: Date = .now) {
        id = Self.idPrefix + UUID().uuidString.lowercased()
        self.name = name
        self.kind = kind
        self.website = website
        self.coordinate = coordinate
        self.waterName = waterName
        self.shared = shared
        self.added = added
    }

    /// The place as a club, so the list, the pages and the widget treat it like any other.
    var club: Club {
        Club(id: id, name: name, shortName: name, address: "", website: website,
             launchPoint: coordinate, launchPointVerified: true, source: "own")
    }

    var lake: Lake {
        Lake(id: "\(id)-water", name: waterName ?? tr("Your own place"), center: coordinate, clubs: [club], hasOutline: false)
    }

    /// A prefilled GitHub issue that suggests the place for the shared list.
    /// The user sends it from the page that opens; nothing is sent without that.
    var suggestionURL: URL? {
        var parts = URLComponents(string: "https://github.com/RowFrog/RowFrog/issues/new")
        let body = """
        Suggested from the app for the shared club list.

        - Name: \(name)
        - Kind: \(kind.rawValue)
        - Position: \(String(format: "%.5f", coordinate.lat)), \(String(format: "%.5f", coordinate.lon))
        - Water: \(waterName ?? "not known")
        - Website: \(website?.absoluteString ?? "none")
        """
        parts?.queryItems = [
            URLQueryItem(name: "title", value: "Place suggestion: \(name)"),
            URLQueryItem(name: "labels", value: "place suggestion"),
            URLQueryItem(name: "body", value: body),
        ]
        return parts?.url
    }

    /// The suggestion for the Row Frog service (cloudflare/suggestions), which
    /// files it as a GitHub issue, so the user needs no GitHub account.
    func suggestionRequest(api: APIClient, country: String?) throws -> URLRequest {
        struct Body: Encodable {
            let name: String, kind: String, lat: Double, lon: Double
            let water: String?, website: String?, country: String?
        }
        var request = URLRequest(url: api.url("suggestions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(
            name: name, kind: kind.rawValue, lat: coordinate.lat, lon: coordinate.lon,
            water: waterName, website: website?.absoluteString, country: country
        ))
        return request
    }

    /// Sends the suggestion; if the service cannot take it, the prefilled
    /// GitHub page opens instead, as before.
    func suggest(api: APIClient, country: String?, open: @escaping (URL) -> Void) async {
        do {
            let (_, response) = try await api.session.data(for: suggestionRequest(api: api, country: country))
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) { return }
        } catch {}
        if let url = suggestionURL { await MainActor.run { open(url) } }
    }
}

/// The forecast for an own place, worked out on the iPhone: the published
/// forecasts only cover the clubs in the lists, and an own place must not
/// appear in public files. The phone asks Open-Meteo itself (the same DWD
/// ICON models as the backend) and applies the backend's rowing-light rules
/// for wind, gusts, fog, thunderstorms and daylight (backend/rowerweather/score.py).
/// Without a lake outline there are no waves, and there are no water
/// temperature, ice or DWD warnings.
enum PlaceForecaster {
    // The backend's own credit line, so it is translated the same way.
    static let attribution = "Weather: Deutscher Wetterdienst (DWD) via Open-Meteo, CC BY 4.0"

    // score.Thresholds and forecast.py's thunderstorm signal.
    static let windAmber = 5.5, windRed = 8.0
    static let gustAmber = 8.0, gustRed = 12.8
    static let visibilityAmber = 1000.0, visibilityRed = 500.0
    static let capeAmber = 500.0, capeRed = 1000.0, convectiveRainMm = 1.0

    static let hourly = [
        "temperature_2m", "wind_speed_10m", "wind_gusts_10m", "wind_direction_10m", "cloud_cover",
        "visibility", "precipitation", "weather_code", "apparent_temperature", "relative_humidity_2m",
        "dew_point_2m", "pressure_msl", "cape", "is_day",
    ]

    static func url(for point: Coordinate) -> URL {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", point.lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", point.lon)),
            URLQueryItem(name: "hourly", value: hourly.joined(separator: ",")),
            URLQueryItem(name: "models", value: "icon_seamless"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "forecast_hours", value: "48"),
        ]
        return parts.url!
    }

    static func load(_ club: Club, session: URLSession = .shared, now: Date = .now) async throws -> ClubForecast {
        let (data, response) = try await session.data(from: url(for: club.launchPoint))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try forecast(club, openMeteo: data, now: now)
    }

    struct Payload: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]?
            let wind_speed_10m: [Double?]?
            let wind_gusts_10m: [Double?]?
            let wind_direction_10m: [Double?]?
            let cloud_cover: [Double?]?
            let visibility: [Double?]?
            let precipitation: [Double?]?
            let weather_code: [Double?]?
            let apparent_temperature: [Double?]?
            let relative_humidity_2m: [Double?]?
            let dew_point_2m: [Double?]?
            let pressure_msl: [Double?]?
            let cape: [Double?]?
            let is_day: [Double?]?
        }

        let hourly: Hourly
    }

    static func forecast(_ club: Club, openMeteo data: Data, now: Date = .now) throws -> ClubForecast {
        let h = try JSONDecoder().decode(Payload.self, from: data).hourly
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        func at(_ column: [Double?]?, _ i: Int) -> Double? {
            guard let column, i < column.count else { return nil }
            return column[i]
        }
        let times = h.time.compactMap(parser.date(from:))
        let p = club.launchPoint
        let days = times.isEmpty ? [] : Sun.days(from: times[0], to: times[times.count - 1], lat: p.lat, lon: p.lon)
        let hours = times.indices.map { i -> ForecastHour in
            let wind = at(h.wind_speed_10m, i)
            let gust = at(h.wind_gusts_10m, i)
            let visibility = at(h.visibility, i)
            let isDay = at(h.is_day, i).map { $0 > 0 }
            let (daylightName, daylight, sunUp) = Self.daylight(start: times[i], days: days, isDay: isDay)
            var reasons: [Reason] = []
            func add(_ name: String, _ light: Light) { if light > .green { reasons.append(Reason(condition: name, light: light)) } }
            add("wind", rising(wind ?? 0, windAmber, windRed))
            add("gusts", rising(gust ?? 0, gustAmber, gustRed))
            add("thunderstorm", thunderstorm(cape: at(h.cape, i), rain: at(h.precipitation, i)))
            add(daylightName, daylight)
            if let visibility {
                if visibility < visibilityRed { add("fog", .red) } else if visibility <= visibilityAmber { add("fog", .amber) }
            }
            reasons.sort { $0.light > $1.light }
            return ForecastHour(
                time: times[i], light: reasons.map(\.light).max() ?? .green, reasons: reasons,
                windSpeedMs: wind, windGustMs: gust, windFromDeg: at(h.wind_direction_10m, i),
                waveHeightM: nil, fetchM: nil, visibilityM: visibility,
                temperatureC: at(h.temperature_2m, i), cloudCoverPct: at(h.cloud_cover, i), sunUp: sunUp,
                precipitationMm: at(h.precipitation, i), weatherCode: at(h.weather_code, i).map { Int($0) },
                apparentTemperatureC: at(h.apparent_temperature, i),
                humidityPct: at(h.relative_humidity_2m, i), dewPointC: at(h.dew_point_2m, i),
                pressureHpa: at(h.pressure_msl, i)
            )
        }
        return ClubForecast(
            clubId: club.id, lakeId: "\(club.id)-water", generatedAt: now, waterTemperature: nil,
            attribution: [attribution],
            daylight: days,
            hours: hours
        )
    }

    static func rising(_ value: Double, _ amber: Double, _ red: Double) -> Light {
        value > red ? .red : value >= amber ? .amber : .green
    }

    static func thunderstorm(cape: Double?, rain: Double?) -> Light {
        let cape = cape ?? 0
        if cape >= capeRed, (rain ?? 0) >= convectiveRainMm { return .red }
        return cape >= capeAmber ? .amber : .green
    }

    /// As forecast._daylight: green with the sun up all hour, amber ("twilight")
    /// with sunrise or sunset inside it, red in the dark.
    static func daylight(start: Date, days: [SunDay], isDay: Bool?) -> (String, Light, Bool?) {
        guard !days.isEmpty else { return ("daylight", isDay == false ? .red : .green, isDay) }
        let end = start.addingTimeInterval(3600)
        let middle = start.addingTimeInterval(1800)
        let sunUp = days.contains { $0.sunrise <= middle && middle < $0.sunset }
        if days.contains(where: { $0.sunrise <= start && end <= $0.sunset }) { return ("daylight", .green, sunUp) }
        if days.contains(where: { day in [day.sunrise, day.sunset].contains { start < $0 && $0 < end } }) {
            return ("twilight", .amber, sunUp)
        }
        return ("daylight", .red, sunUp)
    }
}

/// Sunrise and sunset, as backend/rowerweather/sun.py (NOAA's sunrise equation).
enum Sun {
    static func day(_ day: Date, lat: Double, lon: Double) -> SunDay? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let j2000Date = utc.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        let n = Double(utc.dateComponents([.day], from: j2000Date, to: utc.startOfDay(for: day)).day ?? 0)
        let rad = Double.pi / 180
        let meanSolar = n - lon / 360
        let m = (357.5291 + 0.98560028 * meanSolar).truncatingRemainder(dividingBy: 360) * rad
        let centre = 1.9148 * sin(m) + 0.0200 * sin(2 * m) + 0.0003 * sin(3 * m)
        let eclipticLon = (m / rad + centre + 180 + 102.9372).truncatingRemainder(dividingBy: 360) * rad
        let transit = 2_451_545.0 + meanSolar + 0.0053 * sin(m) - 0.0069 * sin(2 * eclipticLon)
        let declination = asin(sin(eclipticLon) * sin(23.4397 * rad))
        let phi = lat * rad
        let cosHourAngle = (sin(-0.833 * rad) - sin(phi) * sin(declination)) / (cos(phi) * cos(declination))
        guard (-1...1).contains(cosHourAngle) else { return nil }
        let halfDay = acos(cosHourAngle) / rad / 360
        let noon2000 = j2000Date.addingTimeInterval(12 * 3600)
        func date(_ j: Double) -> Date { noon2000.addingTimeInterval((j - 2_451_545.0) * 86_400) }
        return SunDay(sunrise: date(transit - halfDay), sunset: date(transit + halfDay))
    }

    /// Every day from the one before `start` to the one after `end` (UTC dates).
    static func days(from start: Date, to end: Date, lat: Double, lon: Double) -> [SunDay] {
        var out: [SunDay] = []
        var d = start.addingTimeInterval(-86_400)
        while d <= end.addingTimeInterval(86_400) {
            if let s = day(d, lat: lat, lon: lon) { out.append(s) }
            d = d.addingTimeInterval(86_400)
        }
        return out
    }
}
