import UIKit
import XCTest
@testable import RowerWeather

final class AppIconsTests: XCTestCase {
    func testNumbersAndNamesAreUnique() {
        XCTAssertEqual(AppIcons.all.map(\.number), Array(1...AppIcons.all.count))
        XCTAssertEqual(Set(AppIcons.all.map(\.name)).count, AppIcons.all.count)
    }

    func testPrimaryIconHasNoAlternateName() {
        XCTAssertEqual(AppIcons.primary.number, 9)
        XCTAssertNil(AppIcons.primary.alternateIconName)
        XCTAssertEqual(AppIcons.all.compactMap(\.alternateIconName).count, AppIcons.all.count - 1)
    }

    func testEveryIconHasAPreview() {
        for option in AppIcons.all {
            XCTAssertNotNil(UIImage(named: "IconPreview-\(option.name)"), option.name)
        }
    }
}
