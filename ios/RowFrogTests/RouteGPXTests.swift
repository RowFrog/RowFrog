import XCTest
@testable import RowFrog

/// The GPX export; web/tests/routegpx.test.mjs expects the same text from the website.
final class RouteGPXTests: XCTestCase {
    func testOutAndBackRouteWritesTheWayBackToo() {
        let route = Route(name: "Ufer & <Insel>", lakeId: "starnberger-see",
                          points: [Coordinate(lat: 47.9312345, lon: 11.3123456), Coordinate(lat: 47.94, lon: 11.32), Coordinate(lat: 47.95, lon: 11.31)],
                          outAndBack: true)
        XCTAssertEqual(RouteGPX.text(route), """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Row Frog" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>Ufer &amp; &lt;Insel&gt;</name></metadata>
          <trk>
            <name>Ufer &amp; &lt;Insel&gt;</name>
            <type>rowing</type>
            <trkseg>
              <trkpt lat="47.93123" lon="11.31235"/>
              <trkpt lat="47.94000" lon="11.32000"/>
              <trkpt lat="47.95000" lon="11.31000"/>
              <trkpt lat="47.94000" lon="11.32000"/>
              <trkpt lat="47.93123" lon="11.31235"/>
            </trkseg>
          </trk>
        </gpx>

        """)
    }

    func testFileNameDropsCharactersFileSystemsRefuse() {
        XCTAssertEqual(RouteGPX.fileName(Route(name: "A/B: C?", lakeId: "x", points: [], outAndBack: false)), "A B  C.gpx")
        XCTAssertEqual(RouteGPX.fileName(Route(name: "  ", lakeId: "x", points: [], outAndBack: false)), "Route.gpx")
    }

    func testTheExportReadsBackAsATrack() throws {
        let route = Route(name: "Kurz", lakeId: "x", points: [Coordinate(lat: 48, lon: 11.1), Coordinate(lat: 48.01, lon: 11.12)], outAndBack: false)
        let track = try TrackFile.read(Data(RouteGPX.text(route).utf8))
        XCTAssertEqual(track.points.count, 2)
    }
}
