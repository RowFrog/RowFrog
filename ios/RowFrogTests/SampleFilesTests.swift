import XCTest
@testable import RowFrog

/// Reads the sample API files in testdata/api/v1, which the backend writes
/// through the same code as the published files (backend/tests/test_sample_files.py)
/// and the website's tests read too. A field the backend renames or drops
/// would otherwise only show up as a blank tile on the rower's phone.
final class SampleFilesTests: XCTestCase {
    /// Keys the app does not read on purpose, as "path.key".
    private static let notRead: Set<String> = [
        "forecast.daylight[].date",  // the day follows from sunrise and sunset
        "forecast.waterTemperature.station.distanceKm",  // the app shows distanceM
    ]

    private static let samples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "testdata/api/v1")

    private func sample(_ path: String) throws -> Data {
        try Data(contentsOf: Self.samples.appending(path: path))
    }

    func testSampleForecastDecodesWithEveryBlockFilled() throws {
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: sample("clubs/mrc-1880/forecast"))
        XCTAssertEqual(forecast.clubId, "mrc-1880")
        XCTAssertFalse(forecast.hours.isEmpty)
        XCTAssertFalse(forecast.outlook?.isEmpty ?? true)
        XCTAssertNotNil(forecast.waterTemperature?.station)
        XCTAssertFalse(forecast.waterTemperature?.history?.isEmpty ?? true)
        XCTAssertFalse(forecast.waterForecast?.isEmpty ?? true)
        XCTAssertNotNil(forecast.waterForecast?.first?.day, "water forecast dates in a form the app reads")
        XCTAssertEqual(forecast.warnings?.items.count, 2)
        XCTAssertEqual(forecast.warnings?.checked, true)
        XCTAssertNotNil(forecast.ice)
        XCTAssertNotNil(forecast.forecastSource)
        XCTAssertFalse(forecast.daylight?.isEmpty ?? true)
        XCTAssertFalse(forecast.radar?.steps.isEmpty ?? true)
        XCTAssertEqual(forecast.refresh?.used, true)
        XCTAssertNotNil(forecast.outlook?.first?.uvIndex)
        XCTAssertNotNil(forecast.hours.first?.pressureHpa)
    }

    func testEveryReasonInTheSampleHasALabel() throws {
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: sample("clubs/mrc-1880/forecast"))
        for reason in forecast.hours.flatMap(\.reasons) + (forecast.outlook ?? []).flatMap(\.reasons) {
            XCTAssertNotEqual(reason.label, reason.condition, "no label for \(reason.condition)")
        }
    }

    func testSampleLakesDecode() throws {
        let lakes = try APIClient.decoder.decode([Lake].self, from: sample("lakes/index"))
        XCTAssertTrue(lakes.flatMap(\.clubs).contains { $0.id == "mrc-1880" })
    }

    /// Decodes each file, writes it out again with the app's own types and
    /// lists every value the backend sends that the app dropped on the way:
    /// a key renamed on one side lands here even where the app treats the
    /// field as optional.
    func testAppReadsEveryValueTheBackendSends() throws {
        let encoder = JSONEncoder()
        let forecastData = try sample("clubs/mrc-1880/forecast")
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: forecastData)
        let lakesData = try sample("lakes/index")
        let lakes = try APIClient.decoder.decode([Lake].self, from: lakesData)

        var dropped = Set<String>()
        Self.compare(try JSONSerialization.jsonObject(with: forecastData),
                     try JSONSerialization.jsonObject(with: encoder.encode(forecast)), "forecast", &dropped)
        Self.compare(try JSONSerialization.jsonObject(with: lakesData),
                     try JSONSerialization.jsonObject(with: encoder.encode(lakes)), "lakes", &dropped)
        XCTAssertEqual(dropped.subtracting(Self.notRead).sorted(), [],
                       "the app drops these values from the backend; rename the field or add it to notRead")
    }

    private static func compare(_ sent: Any, _ kept: Any, _ path: String, _ dropped: inout Set<String>) {
        if let sent = sent as? [String: Any] {
            let kept = kept as? [String: Any] ?? [:]
            for (key, value) in sent where !(value is NSNull) {
                if let inner = kept[key] {
                    compare(value, inner, "\(path).\(key)", &dropped)
                } else {
                    dropped.insert("\(path).\(key)")
                }
            }
        } else if let sent = sent as? [Any] {
            let kept = kept as? [Any] ?? []
            for (i, value) in sent.enumerated() where i < kept.count {
                compare(value, kept[i], "\(path)[]", &dropped)
            }
        }
    }
}
