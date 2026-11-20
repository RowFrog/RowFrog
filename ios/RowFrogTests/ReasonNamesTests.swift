import XCTest
@testable import RowFrog

/// Reads testdata/reasons.json, every reason the backend may send; the backend's
/// (test_reason_names.py) and the website's (web/tests/reasons.test.mjs) tests read it
/// too. The owner saw "nearby_water" as raw text on an old build (12 Nov 2026).
final class ReasonNamesTests: XCTestCase {
    private struct List: Decodable {
        let reasons: [String]
        let order: [String]
        let topics: [String: [String]]
    }

    private static let list: List = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "testdata/reasons.json")
        return try! JSONDecoder().decode(List.self, from: Data(contentsOf: url))
    }()

    private func reasons() -> [Reason] {
        Self.list.reasons.flatMap { name -> [Reason] in
            var topics: [String?] = [nil]
            if let listed = Self.list.topics[name] { topics = listed.map { Optional($0) } }
            return topics.map { Reason(condition: name, light: .amber, topic: $0, value: 1) }
        }
    }

    func testEveryListedReasonHasALabelAndASentence() {
        let unknown = Reason(condition: "not_a_reason", light: .amber)
        XCTAssertFalse(reasons().isEmpty)
        for reason in reasons() {
            let what = "\(reason.condition)/\(reason.topic ?? "")"
            XCTAssertNotEqual(reason.label, reason.condition, what)
            XCTAssertNotEqual(reason.label, unknown.label, what)
            XCTAssertNotEqual(reason.explanation, reason.condition, what)
            XCTAssertNotEqual(reason.explanation, unknown.explanation, what)
        }
    }

    /// One order for the server, the app and the website (owner, 20 Nov 2026).
    func testTheOrderIsTheListedOne() {
        XCTAssertEqual(Reason.order, Self.list.order)
        XCTAssertTrue(Set(Self.list.reasons).subtracting(["nearby_water"]).isSubset(of: Set(Reason.order)))
    }

    /// The owner's screenshot of 20 Nov 2026 listed the amber sunset above the red wind.
    func testRedComesFirstThenTheMoreDangerousAndDaylightLast() {
        let reasons = [
            Reason(condition: "sunset_soon", light: .amber), Reason(condition: "wind", light: .red),
            Reason(condition: "weather_warning", light: .amber, topic: "wind"), Reason(condition: "gusts", light: .red),
            Reason(condition: "brand_new_reason", light: .amber), Reason(condition: "nearby_water", light: .red, topic: "fog"),
        ]
        XCTAssertEqual(reasons.ordered().map(\.condition),
                       ["nearby_water", "gusts", "wind", "weather_warning", "brand_new_reason", "sunset_soon"])
    }

    func testAReasonNewerThanTheBuildNeverShowsItsRawName() {
        let reason = Reason(condition: "brand_new_reason", light: .amber)
        XCTAssertNotEqual(reason.label, "brand_new_reason")
        XCTAssertNotEqual(reason.explanation, "brand_new_reason")
    }
}
