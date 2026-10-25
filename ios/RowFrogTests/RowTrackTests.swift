import CoreLocation
import XCTest
@testable import RowFrog

final class RowTrackTests: XCTestCase {
    private let club = CLLocationCoordinate2D(latitude: 47.99667, longitude: 11.34745)

    func testReadsGPXTrackPoints() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx:gpx xmlns:gpx="http://www.topografix.com/GPX/1/1" version="1.1" creator="CrewNerd">
          <gpx:metadata><gpx:time>2026-10-12T07:00:00Z</gpx:time></gpx:metadata>
          <gpx:trk><gpx:trkseg>
            <gpx:trkpt lat="47.9967" lon="11.3475"><gpx:ele>584</gpx:ele><gpx:time>2026-10-12T07:30:00Z</gpx:time></gpx:trkpt>
            <gpx:trkpt lat="47.9900" lon="11.3440"><gpx:time>2026-10-12T07:33:10.500Z</gpx:time></gpx:trkpt>
            <gpx:trkpt lat="47.9800" lon="11.3400"><gpx:time>2026-10-12T07:38:00Z</gpx:time></gpx:trkpt>
          </gpx:trkseg></gpx:trk>
        </gpx:gpx>
        """
        let track = try TrackFile.read(Data(gpx.utf8))
        XCTAssertEqual(track.points.count, 3)
        XCTAssertEqual(track.points[1].lat, 47.99, accuracy: 1e-9)
        XCTAssertEqual(track.start, ISO8601DateFormatter().date(from: "2026-10-12T07:30:00Z"))
        XCTAssertNotNil(track.points[1].time)
    }

    func testReadsGPXRouteWithoutTrack() throws {
        let gpx = """
        <gpx version="1.1"><rte><rtept lat="47.99" lon="11.34"/><rtept lat="47.98" lon="11.33"/></rte></gpx>
        """
        let track = try TrackFile.read(Data(gpx.utf8))
        XCTAssertEqual(track.points.count, 2)
        XCTAssertNil(track.start)
    }

    func testReadsTCXTrackpoints() throws {
        let tcx = """
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities><Activity Sport="Other"><Lap StartTime="2026-10-12T07:30:00Z"><Track>
            <Trackpoint><Time>2026-10-12T07:30:00Z</Time><Position><LatitudeDegrees>47.9967</LatitudeDegrees><LongitudeDegrees>11.3475</LongitudeDegrees></Position></Trackpoint>
            <Trackpoint><Time>2026-10-12T07:30:05Z</Time><HeartRateBpm><Value>120</Value></HeartRateBpm></Trackpoint>
            <Trackpoint><Time>2026-10-12T07:35:00Z</Time><Position><LatitudeDegrees>47.9900</LatitudeDegrees><LongitudeDegrees>11.3440</LongitudeDegrees></Position></Trackpoint>
          </Track></Lap></Activity></Activities>
        </TrainingCenterDatabase>
        """
        let track = try TrackFile.read(Data(tcx.utf8))
        // The point without a position is left out.
        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.points[1].lon, 11.344, accuracy: 1e-9)
    }

    func testReadsFITRecords() throws {
        func le(_ value: UInt32, _ bytes: Int) -> [UInt8] { (0..<bytes).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) } }
        func semicircles(_ degrees: Double) -> UInt32 { UInt32(bitPattern: Int32((degrees * 2_147_483_648 / 180).rounded())) }
        var records: [UInt8] = []
        // Definition of local message 0 = record (20): timestamp, position_lat, position_long.
        records += [0x40, 0, 0] + le(20, 2) + [3, 253, 4, 0x86, 0, 4, 0x85, 1, 4, 0x85]
        let t0: UInt32 = 1_100_000_000
        for (k, (lat, lon)) in [(47.9967, 11.3475), (47.9900, 11.3440)].enumerated() {
            records += [0x00] + le(t0 + UInt32(k) * 60, 4) + le(semicircles(lat), 4) + le(semicircles(lon), 4)
        }
        // A record without a position (invalid value) is left out.
        records += [0x00] + le(t0 + 120, 4) + le(0x7FFF_FFFF, 4) + le(0x7FFF_FFFF, 4)
        let file = [14, 0x20] + le(2132, 2) + le(UInt32(records.count), 4) + Array(".FIT".utf8) + [0, 0] + records + [0, 0]
        XCTAssertTrue(TrackFile.isFIT(Data(file)))
        let track = try TrackFile.read(Data(file))
        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.points[0].lat, 47.9967, accuracy: 1e-6)
        XCTAssertEqual(track.points[1].lon, 11.3440, accuracy: 1e-6)
        XCTAssertEqual(track.start, FITReader.epoch.addingTimeInterval(TimeInterval(t0)))
    }

    func testRejectsAFileWithoutPoints() {
        XCTAssertThrowsError(try TrackFile.read(Data("<gpx></gpx>".utf8)))
        XCTAssertThrowsError(try TrackFile.read(Data("hello".utf8)))
    }

    func testOutAndBackRowBecomesAnOutAndBackRoute() throws {
        let turn = CLLocationCoordinate2D(latitude: 47.965, longitude: 11.331)
        // The recording starts 60 m from the launch point.
        let start = CLLocationCoordinate2D(latitude: 47.9962, longitude: 11.3472)
        let track = RouteImport.sampleTrack(along: [start, CLLocationCoordinate2D(latitude: 47.983, longitude: 11.338), turn], outAndBack: true)
        let route = try XCTUnwrap(RouteImport.route(from: track, lakeId: "starnberger-see", launchPoints: [Coordinate(lat: club.latitude, lon: club.longitude)]))
        XCTAssertTrue(route.outAndBack)
        XCTAssertEqual(route.points.first, Coordinate(lat: club.latitude, lon: club.longitude))
        XCTAssertLessThan(RoutePlanner.distance(try XCTUnwrap(route.coordinates.last), turn), 30)
        XCTAssertLessThan(route.points.count, 10)
        XCTAssertNotNil(route.track)
        XCTAssertEqual(route.importedFrom, .health)
    }

    func testLoopRowEndsAtTheStart() throws {
        let loop = [club,
                    CLLocationCoordinate2D(latitude: 47.985, longitude: 11.340),
                    CLLocationCoordinate2D(latitude: 47.970, longitude: 11.336),
                    CLLocationCoordinate2D(latitude: 47.965, longitude: 11.355),
                    CLLocationCoordinate2D(latitude: 47.985, longitude: 11.352),
                    CLLocationCoordinate2D(latitude: 47.9968, longitude: 11.3476)]
        let track = RouteImport.sampleTrack(along: loop, outAndBack: false)
        let route = try XCTUnwrap(RouteImport.route(from: track, lakeId: "starnberger-see", launchPoints: [Coordinate(lat: club.latitude, lon: club.longitude)]))
        XCTAssertFalse(route.outAndBack)
        XCTAssertTrue(RouteEdit.isLoop(route.coordinates))
    }

    func testPaceLeavesOutStops() throws {
        var track = RouteImport.sampleTrack(along: [club, CLLocationCoordinate2D(latitude: 47.965, longitude: 11.331)], outAndBack: false)
        XCTAssertEqual(try XCTUnwrap(track.paceSecondsPer500), 140, accuracy: 3)
        // Ten minutes standing at the end change nothing.
        let last = try XCTUnwrap(track.points.last)
        track.points.append(RowTrack.Point(lat: last.lat + 0.00001, lon: last.lon, time: last.time?.addingTimeInterval(600)))
        XCTAssertEqual(try XCTUnwrap(track.paceSecondsPer500), 140, accuracy: 3)
    }

    func testDropsGPSJumps() {
        let t = Date(timeIntervalSince1970: 0)
        let track = RowTrack(points: [RowTrack.Point(lat: 47.99, lon: 11.34, time: t),
                                      RowTrack.Point(lat: 48.10, lon: 11.34, time: t.addingTimeInterval(5)),
                                      RowTrack.Point(lat: 47.9905, lon: 11.34, time: t.addingTimeInterval(20))], source: .file)
        XCTAssertEqual(track.cleaned.points.count, 2)
    }

    func testTooShortRowMakesNoRoute() {
        let track = RowTrack(points: [RowTrack.Point(lat: 47.99, lon: 11.34, time: nil),
                                      RowTrack.Point(lat: 47.9905, lon: 11.34, time: nil)], source: .file)
        XCTAssertNil(RouteImport.route(from: track, lakeId: "x", launchPoints: []))
    }

    func testStraightLineSimplifiesToItsEnds() {
        let line = (0...50).map { CLLocationCoordinate2D(latitude: 47.9 + Double($0) * 0.001, longitude: 11.3) }
        XCTAssertEqual(RouteImport.simplify(line, toleranceM: 5).count, 2)
    }

    func testRoutesSavedBeforeImportStillLoad() throws {
        let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","lakeId":"l","points":[{"lat":47.9,"lon":11.3}],"outAndBack":true}]"#
        let routes = try JSONDecoder().decode([Route].self, from: Data(old.utf8))
        XCTAssertNil(routes.first?.track)
        XCTAssertEqual(routes.first?.name, "Old")
    }
}
