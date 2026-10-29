import XCTest
@testable import RowFrog

/// River sections: each river club's stretch is a water of its own (backend data/river-sections.json).
final class RiverSectionTests: XCTestCase {
    private let json = """
    [{"id": "river-main-offenbach", "name": "Main", "center": {"lat": 50.1, "lon": 8.72}, "country": "de",
      "kind": "river", "section": {"place": "Offenbach", "waterway": "river", "lengthKm": 14.5},
      "hasOutline": true, "clubs": []},
     {"id": "river-dortmund-ems-kanal-muenster", "name": "Dortmund-Ems-Kanal", "center": {"lat": 51.95, "lon": 7.64},
      "kind": "river", "section": {"place": "Münster", "waterway": "canal", "lengthKm": 20}, "clubs": []},
     {"id": "starnberger-see", "name": "Starnberger See", "center": {"lat": 47.9, "lon": 11.3}, "kind": "lake", "clubs": []},
     {"id": "ammersee", "name": "Ammersee", "center": {"lat": 48.0, "lon": 11.1}, "clubs": []}]
    """

    func testSectionsDecodeAndNameTheirView() throws {
        let lakes = try JSONDecoder().decode([Lake].self, from: Data(json.utf8))
        XCTAssertEqual(lakes.map(\.water), [.river, .canal, .lake, .lake])  // older backends send no kind
        XCTAssertEqual(lakes[0].listTitle, "Main · Offenbach")
        XCTAssertEqual(lakes[0].title, "Main")
        XCTAssertEqual(lakes[2].listTitle, "Starnberger See")
        XCTAssertEqual(lakes[0].water.viewTitle, tr("River view"))
        XCTAssertEqual(lakes[1].water.viewTitle, tr("Canal view"))
        XCTAssertEqual(lakes[2].water.viewTitle, tr("Lake view"))
    }

    func testSectionEndsNameWhatEndsTheStretch() {
        let at = Coordinate(lat: 50.1, lon: 8.8)
        XCTAssertEqual(SectionEnd(km: 7.3, end: "weir/lock", what: "lock Offenbach", at: at).title, tr("Lock") + " Offenbach")
        XCTAssertEqual(SectionEnd(km: 3.0, end: "weir/lock", what: "weir", at: at).title, tr("Weir"))
        XCTAssertEqual(SectionEnd(km: 9.1, end: "river", what: "Main joins", at: at).title, tr("%@ joins", "Main"))
        XCTAssertEqual(SectionEnd(km: 8.2, end: "km sign", what: "river km 42", at: at).title, tr("River km %@", "42"))
        XCTAssertTrue(SectionEnd(km: 7.3, end: "weir/lock", what: "lock", at: at).isBarrier)
        XCTAssertFalse(SectionEnd(km: 12, end: "cap", what: "", at: at).isBarrier)
    }

    func testRiverBlockDecodesAndPaceFollowsTheCurrent() throws {
        let json = """
        {"gauge": {"name": "Köln", "water": "Rhein", "riverKm": 688.0, "lat": 50.94, "lon": 6.96, "distanceKm": 1.9,
                   "meanCm": 300, "meanHighCm": 700, "shippingStopsCm": 830, "meanDischarge": 2100},
         "limits": {"currentAmberMs": 1.5, "currentRedMs": 2.5}, "attribution": "WSV PEGELONLINE, DL-DE Zero 2.0",
         "now": {"time": "2026-10-28T16:15:00+01:00", "levelCm": 850, "trend": "rising", "state": "shipping_stopped",
                 "discharge": 6200, "speedMs": 2.1, "speedMeasured": false, "light": "red",
                 "history": [{"time": "2026-10-28T15:00:00+01:00", "levelCm": 845}, {"time": "2026-10-28T16:00:00+01:00", "levelCm": 850}]}}
        """
        let river = try APIClient.decoder.decode(RiverConditions.self, from: Data(json.utf8))
        XCTAssertEqual(river.now?.light, .red)
        XCTAssertEqual(river.now?.stateTitle, tr("Shipping stopped"))
        XCTAssertEqual(river.gauge?.shippingStopsCm, 830)
        // 2:30 /500 m is 3.33 m/s in still water; 1 m/s against makes 2.33 m/s over ground.
        XCTAssertEqual(RiverFormat.pace(150, current: 1.0, downstream: false)!, 500 / (500.0 / 150 - 1), accuracy: 0.01)
        XCTAssertEqual(RiverFormat.pace(150, current: 1.0, downstream: true)!, 500 / (500.0 / 150 + 1), accuracy: 0.01)
        XCTAssertNil(RiverFormat.pace(150, current: 3.4, downstream: false), "no headway against a current faster than the boat")
        let none = try APIClient.decoder.decode(RiverConditions.self, from: Data(#"{"gauge": null, "now": null}"#.utf8))
        XCTAssertNil(none.gauge)
    }

    func testLakeLevelBlockDecodesAndShowsOnlyWhileLowered() throws {
        let json = """
        {"gauge": "Roßhaupten Seepegel", "fullM": 780.6, "loweredBelowM": 779.8, "drainedBelowM": 777.5,
         "attribution": "Gewässerkundlicher Dienst Bayern, CC BY 4.0",
         "now": {"time": "2026-12-10T13:00:00+01:00", "levelM": 776.4, "belowFullM": 4.2, "state": "drained", "trend": "falling",
                 "light": "red", "history": [{"time": "2026-12-10T12:00:00+01:00", "levelM": 776.45}, {"time": "2026-12-10T13:00:00+01:00", "levelM": 776.4}]}}
        """
        let level = try APIClient.decoder.decode(LakeLevel.self, from: Data(json.utf8))
        XCTAssertTrue(level.isLowered)
        XCTAssertEqual(level.now?.light, .red)
        XCTAssertEqual(level.now?.stateTitle, tr("Drained"))
        XCTAssertEqual(Reason(condition: "lake_drained", light: .red).symbol, LakeLevel.symbol)
        let full = try APIClient.decoder.decode(LakeLevel.self, from: Data(#"{"gauge": "X", "fullM": 780.6, "loweredBelowM": 779.8, "drainedBelowM": 777.5, "now": null}"#.utf8))
        XCTAssertFalse(full.isLowered, "without a reading the ice tile stays")
    }
}
