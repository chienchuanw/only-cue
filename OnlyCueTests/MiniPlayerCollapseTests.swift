import XCTest
@testable import OnlyCue

final class MiniPlayerCollapseTests: XCTestCase {

    func test_close_collapsesWhenMiniVisible() {
        XCTAssertEqual(MiniPlayerCollapse.onMainWindowClose(miniVisible: true), .collapseToMini)
    }

    func test_close_closesDocumentWhenMiniHidden() {
        XCTAssertEqual(MiniPlayerCollapse.onMainWindowClose(miniVisible: false), .closeDocument)
    }

    func test_miniClose_restoresMainWhenHidden() {
        XCTAssertEqual(MiniPlayerCollapse.onMiniClose(mainWindowHidden: true), .restoreMainWindow)
    }

    func test_miniClose_justClosesWhenMainVisible() {
        XCTAssertEqual(MiniPlayerCollapse.onMiniClose(mainWindowHidden: false), .justCloseMini)
    }
}
