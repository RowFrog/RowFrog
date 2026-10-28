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
}
