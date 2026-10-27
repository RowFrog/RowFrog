import UIKit
import XCTest
@testable import RowFrog

final class ModelDecodingTests: XCTestCase {
    func testDecodesBackendForecast() throws {
        let json = """
        {"clubId": "mrc-1880", "lakeId": "starnberger-see",
         "generatedAt": "2026-10-18T11:20:00+00:00",
         "attribution": ["Weather: Deutscher Wetterdienst (DWD) via Open-Meteo, CC BY 4.0"],
         "hours": [{"time": "2026-10-18T07:00:00+00:00", "light": "red",
                    "reasons": [{"condition": "waves", "light": "red"}],
                    "windSpeedMs": 9.0, "windGustMs": 14.0, "windFromDeg": 0,
                    "waveHeightM": 0.45, "fetchM": 9900, "visibilityM": 20000,
                    "temperatureC": 7.0, "cloudCoverPct": 80, "sunUp": true}],
         "daylight": [{"date": "2026-10-18", "sunrise": "2026-10-18T05:35:00+00:00",
                       "sunset": "2026-10-18T16:21:00+00:00"}]}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        XCTAssertEqual(forecast.hours.first?.light, .red)
        XCTAssertEqual(forecast.hours.first?.reasons.first?.label, "Waves")
        XCTAssertEqual(forecast.hours.first?.sunUp, true)

        let noon = ISO8601DateFormatter().date(from: "2026-10-18T10:00:00Z")!
        let evening = ISO8601DateFormatter().date(from: "2026-10-18T19:00:00Z")!
        guard case let .up(_, sunset) = forecast.sunState(at: noon) else { return XCTFail("sun should be up") }
        XCTAssertEqual(Format.time(sunset).count, 5)  // 24-hour "HH:mm"
        XCTAssertNil(forecast.sunState(at: evening))  // no next sunrise in the data
    }

    func testCurrentHourUsesTheSunNowNotTheWholeHour() throws {
        let json = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T16:00:00+00:00", "attribution": [],
         "daylight": [{"date": "2026-10-18", "sunrise": "2026-10-18T05:35:00+00:00", "sunset": "2026-10-18T16:21:00+00:00"},
                      {"date": "2026-10-19", "sunrise": "2026-10-19T05:37:00+00:00", "sunset": "2026-10-19T16:19:00+00:00"}],
         "hours": [{"time": "2026-10-18T16:00:00+00:00", "light": "amber",
                    "reasons": [{"condition": "twilight", "light": "amber"}]}]}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        let before = ISO8601DateFormatter().date(from: "2026-10-18T16:10:00Z")!
        let after = ISO8601DateFormatter().date(from: "2026-10-18T16:40:00Z")!
        XCTAssertEqual(forecast.current(at: before)?.light, .green)
        XCTAssertEqual(forecast.current(at: after)?.light, .red)
        XCTAssertEqual(forecast.current(at: after)?.reasons.first?.label, "Sun down")
    }

    func testOlderForecastShowsTheHourNowAndIsOutOfDate() throws {
        let json = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T08:00:00+00:00", "attribution": [],
         "hours": [{"time": "2026-10-18T08:00:00+00:00", "light": "green", "reasons": []},
                   {"time": "2026-10-18T09:00:00+00:00", "light": "amber", "reasons": []},
                   {"time": "2026-10-18T10:00:00+00:00", "light": "red", "reasons": []}]}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        let ten = ISO8601DateFormatter().date(from: "2026-10-18T10:30:00Z")!
        XCTAssertEqual(forecast.current(at: ten)?.light, .red)
        XCTAssertFalse(forecast.isStale(at: ten))
        XCTAssertTrue(forecast.isStale(at: ten.addingTimeInterval(3600)))
    }

    func testDecodesIceEstimate() throws {
        let json = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2027-01-20T11:20:00+00:00", "attribution": [], "hours": [],
         "ice": {"status": "frozen", "light": "red", "thicknessCm": 12.4, "waterTemperatureC": 0.0, "basis": "model",
                 "frostDegreeDays7": 42.0, "days": [{"date": "2027-01-20", "status": "frozen", "thicknessCm": 12.4}]}}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        XCTAssertEqual(forecast.ice?.light, .red)
        XCTAssertEqual(forecast.ice?.title, "Ice cover likely")
        XCTAssertEqual(forecast.ice?.detail, "About 12 cm, estimated")
        XCTAssertEqual(forecast.ice?.days?.first?.date, "2027-01-20")

        let unavailable = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2027-01-20T11:20:00+00:00", "attribution": [], "hours": [],
         "ice": {"status": "unavailable", "light": null, "days": []}}
        """
        let without = try APIClient.decoder.decode(ClubForecast.self, from: Data(unavailable.utf8))
        XCTAssertNil(without.ice?.light)
        XCTAssertNil(without.ice?.thicknessCm)

        let seen = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2027-01-20T11:20:00+00:00", "attribution": [], "hours": [],
         "ice": {"status": "edges", "light": "amber", "basis": "satellite", "days": [],
                 "satellite": {"date": "2027-01-18", "seenShare": 0.7, "iceShare": 0.02}}}
        """
        let satellite = try APIClient.decoder.decode(ClubForecast.self, from: Data(seen.utf8))
        XCTAssertEqual(satellite.ice?.satellite?.seenShare, 0.7)
        XCTAssertTrue(satellite.ice?.detail.hasSuffix(": open water") ?? false)
    }

    func testDecodesSatelliteWaterEstimateAndStationNetwork() throws {
        let json = """
        {"clubId": "x", "lakeId": "simssee", "generatedAt": "2026-10-18T11:20:00+00:00", "attribution": [], "hours": [],
         "waterTemperature": null,
         "ice": {"status": "open", "light": "green", "waterTemperatureC": 9.0, "basis": "model", "days": []},
         "waterEstimate": {"celsius": 13.4, "basis": "satellite",
                           "reading": {"source": "landsat", "platform": "landsat-9", "date": "2026-10-09",
                                       "from": null, "to": null, "celsius": 15.1}}}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        // The satellite estimate wins over the ice model's water temperature.
        XCTAssertEqual(forecast.estimatedWaterC, 13.4)
        XCTAssertEqual(forecast.waterEstimate?.reading.satelliteName, "Landsat 9")

        let lswt = SatelliteWaterReading(source: "copernicus-lswt", date: "2026-10-15", from: "2026-10-11", to: "2026-10-20", celsius: 12.0)
        XCTAssertEqual(lswt.satelliteName, "Copernicus (Sentinel-3)")
        XCTAssertTrue(lswt.when.contains(" – "))

        let measured = """
        {"clubId": "x", "lakeId": "river-main", "generatedAt": "2026-10-18T11:20:00+00:00", "attribution": [], "hours": [],
         "waterTemperature": {"celsius": 12.7, "measuredAt": "2026-10-18T11:00:00+00:00",
                              "station": {"network": "pegelonline", "name": "Frankfurt Osthafen", "distanceKm": 3.1, "distanceM": 3100}},
         "waterEstimate": null}
        """
        let river = try APIClient.decoder.decode(ClubForecast.self, from: Data(measured.utf8))
        XCTAssertNil(river.estimatedWaterC)
        XCTAssertEqual(river.waterTemperature?.station?.network, "pegelonline")
        XCTAssertTrue(river.waterTemperature?.station?.operatorName.hasPrefix("PEGELONLINE") ?? false)
        XCTAssertTrue(WaterStation().operatorName.hasPrefix("Gewässerkundlicher Dienst"))
    }

    func testDecodesForecastWithoutDaylight() throws {
        let json = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T11:20:00+00:00", "attribution": [],
         "hours": [{"time": "2026-10-18T07:00:00+00:00", "light": "green", "reasons": []}]}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        XCTAssertNil(forecast.daylight)
        XCTAssertNil(forecast.hours.first?.sunUp)
    }

    func testDecodesForecastSource() throws {
        let json = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T11:20:00+00:00", "attribution": [], "hours": [],
         "forecastSource": {"region": "germany", "parts": [{"model": "ICON-D2", "provider": "Deutscher Wetterdienst (DWD)",
                                                             "resolutionKm": 2.2, "fromHour": 0, "toHour": 48}]}}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        XCTAssertEqual(forecast.forecastSource?.parts.first?.model, "ICON-D2")
        XCTAssertEqual(forecast.forecastSource?.parts.first?.providerShort, "DWD")
        XCTAssertNil(try APIClient.decoder.decode(ClubForecast.self, from: Data(#"{"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T11:20:00+00:00", "attribution": [], "hours": []}"#.utf8)).forecastSource)
    }

    func testDecodesRefreshAndFlagsClubsNobodyOpened() throws {
        let base = #"{"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T11:20:00+00:00", "attribution": [], "hours": []"#
        let slow = try APIClient.decoder.decode(ClubForecast.self, from: Data((base + #", "refresh": {"used": false, "fileEveryHours": 6, "weatherEveryHours": 12}}"#).utf8))
        XCTAssertEqual(slow.refresh, Refresh(used: false, fileEveryHours: 6, weatherEveryHours: 12))
        XCTAssertTrue(slow.isSlowRefresh)
        let used = try APIClient.decoder.decode(ClubForecast.self, from: Data((base + #", "refresh": {"used": true, "fileEveryHours": 0.5, "weatherEveryHours": 3}}"#).utf8))
        XCTAssertFalse(used.isSlowRefresh)
        XCTAssertFalse(try APIClient.decoder.decode(ClubForecast.self, from: Data((base + "}").utf8)).isSlowRefresh, "no tip without the usage counter")
    }

    func testDecodesPickedModelAndChoices() throws {
        let json = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T11:20:00+00:00", "attribution": [], "hours": [],
         "forecastSource": {"region": "germany", "picked": "ecmwf_ifs025",
                            "parts": [{"model": "IFS", "provider": "ECMWF", "resolutionKm": 25, "fromHour": 0, "toHour": 48}]},
         "modelChoices": [{"id": "ecmwf_ifs025", "model": "IFS", "provider": "ECMWF", "resolutionKm": 25, "hours": 240,
                           "advice": "notAdvised", "note": "Very coarse grid."}]}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        XCTAssertEqual(forecast.forecastSource?.picked, "ecmwf_ifs025")
        XCTAssertEqual(forecast.modelChoices?.first?.notAdvised, true)
    }

    func testDecodesWarnings() throws {
        let json = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T11:20:00+00:00", "attribution": [], "hours": [],
         "warnings": {"status": "ok", "lakeArea": "Starnberger See",
                      "items": [{"kind": "lake", "area": "Starnberger See", "event": "STURM", "severity": "severe",
                                 "headline": "Sturmwarnung", "description": "Sturmböen um 65 km/h.", "instruction": null,
                                 "onset": "2026-10-18T12:00:00+00:00", "expires": null, "sample": false}]}}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        let warning = try XCTUnwrap(forecast.warnings?.items.first)
        XCTAssertTrue(warning.isLake)
        XCTAssertNil(warning.expires)
        XCTAssertEqual(warning.shortLabel, "DWD lake warning")
        XCTAssertEqual(Reason(condition: "lake_warning", light: .red).label, "DWD storm warning")
    }

    func testWarningsOutsideGermanyAreNotChecked() throws {
        let json = """
        {"status": "ok", "lakeArea": null, "items": [],
         "local": {"service": "MeteoSwiss", "url": "https://www.meteoswiss.admin.ch/weather/hazards/hazard-map.html", "checked": false}}
        """
        let warnings = try APIClient.decoder.decode(Warnings.self, from: Data(json.utf8))
        XCTAssertFalse(warnings.localChecked)
        XCTAssertEqual(warnings.local?.service, "MeteoSwiss")
        let older = try APIClient.decoder.decode(Warnings.self, from: Data(#"{"status": "ok", "lakeArea": null, "items": []}"#.utf8))
        XCTAssertTrue(older.localChecked, "older backends checked DWD for every club")
    }

    func testDecodesEnglishWarningText() throws {
        let json = """
        {"kind": "local", "area": "Starnberg", "event": "WINDBÖEN", "severity": "minor",
         "headline": "Amtliche WARNUNG vor WINDBÖEN", "description": "Es treten Windböen auf.", "instruction": null,
         "onset": null, "expires": null,
         "english": {"event": "wind gusts", "headline": "Official WARNING of WIND GUSTS",
                     "description": "There is a risk of wind gusts.", "instruction": null, "official": true}}
        """
        let warning = try APIClient.decoder.decode(DWDWarning.self, from: Data(json.utf8))
        XCTAssertEqual(warning.english?.headline, "Official WARNING of WIND GUSTS")
        XCTAssertEqual(warning.english?.official, true)
    }

    func testSkyFromWeatherCode() {
        XCTAssertEqual(Sky(code: 96, cloudCoverPct: 100, precipitationMm: 3).precipitationKind, "Hail")
        XCTAssertEqual(Sky(code: 2, cloudCoverPct: 50, precipitationMm: 0).symbol(night: true), "cloud.moon.fill")
        // Without a code, cloud cover and precipitation decide.
        XCTAssertEqual(Sky(code: nil, cloudCoverPct: 95, precipitationMm: 0), .cloudy)
        XCTAssertEqual(Sky(code: nil, cloudCoverPct: 95, precipitationMm: 0.6), .rain)
    }

    func testLightOrdering() {
        XCTAssertLessThan(Light.green, Light.amber)
        XCTAssertEqual([Light.amber, .red, .green].max(), .red)
    }

    func testDecodesSatellitePictures() throws {
        let json = """
        {"bbox": [11.24, 47.82, 11.37, 48.0], "width": 600, "height": 1280,
         "latest": {"date": "2026-10-21", "lakeCloud": 0.35, "image": "satellite-latest.jpg"},
         "clearest": {"date": "2026-10-12", "lakeCloud": 0.02, "image": "satellite-clearest.jpg"},
         "attribution": "Contains modified Copernicus Sentinel data 2026",
         "checkedAt": "2026-10-23T22:00:00+00:00", "searchVersion": 3}
        """
        let picture = try APIClient.decoder.decode(SatellitePicture.self, from: Data(json.utf8))
        XCTAssertTrue(picture.hasChoice)
        XCTAssertEqual(picture.kinds, [.latest, .clearest])
        XCTAssertEqual(picture.shot(.clearest)?.lakeCloud, 0.02)
        XCTAssertNil(picture.ice)

        let one = """
        {"latest": {"date": "2026-10-21", "lakeCloud": 0.0, "image": "satellite-latest.jpg"},
         "clearest": {"date": "2026-10-21", "lakeCloud": 0.0, "image": "satellite-clearest.jpg"}}
        """
        XCTAssertFalse(try APIClient.decoder.decode(SatellitePicture.self, from: Data(one.utf8)).hasChoice)
    }

    func testPictureBrightnessTellsCloudFromWater() throws {
        // Left half white (cloud), right half black (water).
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let map = try XCTUnwrap(PictureBrightness(image))
        XCTAssertTrue(map.isBright(around: CGPoint(x: 0.25, y: 0.5), radius: 0.05))
        XCTAssertFalse(map.isBright(around: CGPoint(x: 0.75, y: 0.5), radius: 0.05))
        // Off the picture's edge it looks at the nearest part.
        XCTAssertTrue(map.isBright(around: CGPoint(x: -0.2, y: 1.3), radius: 0.01))
    }

    func testDecodesSharpTilesAndPlacesThem() throws {
        let json = """
        {"bbox": [9.0, 47.4, 9.8, 47.8], "width": 1280, "height": 716,
         "sharp": {"width": 2500, "height": 1100, "tile": 1024, "rows": 2, "columns": 3},
         "latest": {"date": "2026-10-21", "lakeCloud": 0.1, "image": "satellite-latest.jpg",
                    "tiles": "satellite-latest-tiles", "overview": "satellite-latest-overview.jpg"},
         "clearest": {"date": "2026-10-12", "lakeCloud": 0.0, "image": "satellite-clearest.jpg"}}
        """
        let picture = try APIClient.decoder.decode(SatellitePicture.self, from: Data(json.utf8))
        XCTAssertEqual(picture.latest?.tiles, "satellite-latest-tiles")
        XCTAssertEqual(picture.latest?.overview, "satellite-latest-overview.jpg")
        XCTAssertNil(picture.clearest?.tiles)
        let sharp = try XCTUnwrap(picture.sharp)
        let size = CGSize(width: 250, height: 110)
        XCTAssertEqual(sharp.rect(row: 0, column: 0, in: size), CGRect(x: 0, y: 0, width: 102.4, height: 102.4))
        // The last tile is cut off at the picture's right and bottom edges.
        let last = sharp.rect(row: 1, column: 2, in: size)
        XCTAssertEqual(last.maxX, 250, accuracy: 0.001)
        XCTAssertEqual(last.maxY, 110, accuracy: 0.001)
        XCTAssertEqual(last.minX, 204.8, accuracy: 0.001)
    }
}
