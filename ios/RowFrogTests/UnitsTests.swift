import XCTest
@testable import RowFrog

/// Reads testdata/units.json, the table the website's units test reads too, so
/// the app and rowfrog.com show the same number in every unit.
final class UnitsTests: XCTestCase {
    private struct Table: Decodable {
        struct Conversion: Decodable { let kind, app, web: String; let metric, shown: Double }
        struct Digits: Decodable { let kind, app: String; let digits: Int; let changeDigits: Int? }
        let conversions: [Conversion]
        let beaufort: [[Double]]
        let digits: [Digits]
    }

    private static let table: Table = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "testdata/units.json")
        return try! JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
    }()

    private func convert(_ kind: String, _ unit: String, _ value: Double) -> Double? {
        switch kind {
        case "temperature": TemperatureUnit(rawValue: unit)?.convert(value)
        case "wind": SpeedUnit(rawValue: unit)?.convert(value)
        case "waves": WaveUnit(rawValue: unit)?.convert(value)
        case "rain": RainUnit(rawValue: unit)?.convert(value)
        case "distance": DistanceUnit(rawValue: unit)?.convert(value)
        case "pressure": PressureUnit(rawValue: unit)?.convert(value)
        default: nil
        }
    }

    func testConversionsMatchTheSharedTable() throws {
        for c in Self.table.conversions {
            let shown = try XCTUnwrap(convert(c.kind, c.app, c.metric), "no \(c.kind) unit \(c.app)")
            XCTAssertEqual(shown, c.shown, accuracy: 1e-3, "\(c.kind) \(c.metric) in \(c.app)")
        }
    }

    func testEveryUnitIsInTheTable() {
        let units: [(String, [String])] = [
            ("temperature", TemperatureUnit.allCases.map(\.rawValue)),
            ("wind", SpeedUnit.allCases.filter { $0 != .beaufort }.map(\.rawValue)),
            ("waves", WaveUnit.allCases.map(\.rawValue)),
            ("rain", RainUnit.allCases.map(\.rawValue)),
            ("distance", DistanceUnit.allCases.map(\.rawValue)),
            ("pressure", PressureUnit.allCases.map(\.rawValue)),
        ]
        for (kind, names) in units {
            for name in names {
                XCTAssertTrue(Self.table.conversions.contains { $0.kind == kind && $0.app == name },
                              "\(kind) \(name) missing from testdata/units.json")
            }
        }
    }

    func testBeaufortForceAtAndJustBelowEachLimit() {
        for row in Self.table.beaufort {
            XCTAssertEqual(SpeedUnit.beaufort(row[0]), Int(row[1]), "Beaufort at \(row[0]) m/s")
            XCTAssertEqual(SpeedUnit.beaufort.convert(row[0]), row[1], "Beaufort unit at \(row[0]) m/s")
        }
    }

    func testDecimalsMatchTheSharedTable() {
        for d in Self.table.digits {
            switch d.kind {
            case "waves": XCTAssertEqual(WaveUnit(rawValue: d.app)?.digits, d.digits, d.app)
            case "rain": XCTAssertEqual(RainUnit(rawValue: d.app)?.digits, d.digits, d.app)
            case "pressure":
                XCTAssertEqual(PressureUnit(rawValue: d.app)?.digits, d.digits, d.app)
                XCTAssertEqual(PressureUnit(rawValue: d.app)?.changeDigits, d.changeDigits, d.app)
            default: XCTFail("no decimals for \(d.kind)")
            }
        }
    }

    /// Decision 0060 (owner, 22 Nov 2026): mean and gust that round the same show once
    /// ("1 m/s", not "1–1 m/s"); hour tables keep both. web/tests/windspan.test.mjs checks the same.
    func testWindShowsOnceWhenMeanAndGustRoundTheSame() {
        XCTAssertEqual(Format.windRange(0.8, 1.3), Format.wind(1.3))
        XCTAssertEqual(Format.windSpan(0.8, 1.3), Format.windNumber(1.3))
        XCTAssertEqual(Format.windSpan(2, 5), "\(Format.windNumber(2))–\(Format.windNumber(5))")
        XCTAssertEqual(Format.windSpan(3, nil), Format.windNumber(3))
        XCTAssertEqual(Format.windSpan(nil, 4), "–")
        XCTAssertEqual(Format.windRange(nil, 4), "–")
        for step in 0...200 {
            let ms = Double(step) / 10
            for extra in [0, 0.2, 0.4, 0.6, 1.5, 3] {
                let same = Format.windNumber(ms) == Format.windNumber(ms + extra)
                XCTAssertEqual(Format.windSpan(ms, ms + extra).contains("–"), !same, "\(ms) / \(ms + extra)")
            }
        }
    }
}
