import XCTest
@testable import RowFrog

/// The Home Screen menu, owner's pick A (decision 0048): home base, lake view,
/// rain radar and the club opened last; Add a club while none is saved.
final class QuickActionsTests: XCTestCase {
    private let home = QuickActions.Place(id: "mrc", name: "MRC 1880", water: "Starnberger See", viewTitle: "Lake view")
    private let ammersee = QuickActions.Place(id: "arc", name: "ARC", water: "Ammersee", viewTitle: "Lake view")
    private let tegernsee = QuickActions.Place(id: "trv", name: "TRV", water: "Tegernsee", viewTitle: "Lake view")

    private func links(_ items: [QuickAction]) -> [String] { items.map(\.link.absoluteString) }

    func testWithoutClubsTheMenuOffersAddAClub() {
        let items = QuickActions.list(saved: [], homeID: nil, lastOpened: nil)
        XCTAssertEqual(links(items), ["rowfrog://add"])
    }

    func testHomeBaseLakeViewRadarAndTheClubOpenedLast() {
        let items = QuickActions.list(saved: [home, ammersee, tegernsee], homeID: "mrc", lastOpened: "trv")
        XCTAssertEqual(links(items), ["rowfrog://club/mrc", "rowfrog://lake/mrc", "rowfrog://radar/mrc", "rowfrog://club/trv"])
        XCTAssertEqual(items.map(\.symbol), ["house", "water.waves", "cloud.rain", "clock.arrow.circlepath"])
        XCTAssertEqual(items[0].title, "MRC 1880")
        XCTAssertEqual(items[3].subtitle, tr("Last opened"))
    }

    func testWithoutALastClubTheNextSavedClubIsShown() {
        let items = QuickActions.list(saved: [home, ammersee], homeID: "mrc", lastOpened: "gone")
        XCTAssertEqual(items.last?.link.absoluteString, "rowfrog://club/arc")
        XCTAssertEqual(items.last?.subtitle, "Ammersee")
    }

    func testOneClubGivesThreeItems() {
        let items = QuickActions.list(saved: [home], homeID: "mrc", lastOpened: nil)
        XCTAssertEqual(links(items), ["rowfrog://club/mrc", "rowfrog://lake/mrc", "rowfrog://radar/mrc"])
    }

    func testWaterWithoutALakeViewLeavesItOut() {
        let river = QuickActions.Place(id: "mrc", name: "MRC 1880", water: nil, viewTitle: nil)
        let items = QuickActions.list(saved: [river, ammersee], homeID: "mrc", lastOpened: nil)
        XCTAssertEqual(links(items), ["rowfrog://club/mrc", "rowfrog://radar/mrc", "rowfrog://club/arc"])
        XCTAssertEqual(items[0].subtitle, tr("Home base"))
    }

    func testNeverMoreThanFourItems() {
        let items = QuickActions.list(saved: [home, ammersee, tegernsee], homeID: "mrc", lastOpened: "arc")
        XCTAssertLessThanOrEqual(items.count, QuickActions.maxCount)
    }

    func testIdsAreKeptInTheLink() {
        let own = QuickActions.Place(id: "own-1 a", name: "Bootshaus", water: nil, viewTitle: nil)
        let url = QuickActions.list(saved: [own], homeID: nil, lastOpened: nil)[0].link
        XCTAssertEqual(url.host(), "club")
        XCTAssertEqual(url.pathComponents.last, "own-1 a")
    }
}
