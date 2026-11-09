import XCTest
@testable import HUDNavigator

final class SmokeTests: XCTestCase {
    func testCoreIsCompiledIntoApp() {
        XCTAssertEqual(BuiltInContent.themes.count, 7)
    }
}
