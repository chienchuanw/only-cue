import SwiftUI
import XCTest
@testable import OnlyCue

final class SidebarVisibilityTests: XCTestCase {

    // MARK: - visibility(isCollapsed:)

    func test_visibility_collapsed_isDetailOnly() {
        XCTAssertEqual(SidebarVisibility.visibility(isCollapsed: true), .detailOnly)
    }

    func test_visibility_notCollapsed_isAll() {
        XCTAssertEqual(SidebarVisibility.visibility(isCollapsed: false), .all)
    }

    // MARK: - isCollapsed(_:)

    func test_isCollapsed_detailOnly_isTrue() {
        XCTAssertTrue(SidebarVisibility.isCollapsed(.detailOnly))
    }

    func test_isCollapsed_all_isFalse() {
        XCTAssertFalse(SidebarVisibility.isCollapsed(.all))
    }

    func test_isCollapsed_doubleColumn_isFalse() {
        XCTAssertFalse(SidebarVisibility.isCollapsed(.doubleColumn))
    }

    func test_isCollapsed_automatic_isFalse() {
        XCTAssertFalse(SidebarVisibility.isCollapsed(.automatic))
    }

    // MARK: - Round-trip

    func test_roundTrip_collapsed() {
        XCTAssertTrue(SidebarVisibility.isCollapsed(SidebarVisibility.visibility(isCollapsed: true)))
    }

    func test_roundTrip_notCollapsed() {
        XCTAssertFalse(SidebarVisibility.isCollapsed(SidebarVisibility.visibility(isCollapsed: false)))
    }
}
