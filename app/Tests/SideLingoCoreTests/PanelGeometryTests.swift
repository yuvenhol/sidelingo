import AppKit
import XCTest
@testable import SideLingoCore

final class PanelGeometryTests: XCTestCase {
    func testCentersPanelInsideVisibleFrame() {
        let visible = NSRect(x: 100, y: 40, width: 1400, height: 900)

        let frame = PanelGeometry.centeredFrame(
            size: NSSize(width: 720, height: 460),
            visibleFrame: visible
        )

        XCTAssertEqual(frame, NSRect(x: 440, y: 260, width: 720, height: 460))
    }

    func testClampsOversizedPanelToVisibleFrame() {
        let visible = NSRect(x: 20, y: 30, width: 600, height: 400)

        let frame = PanelGeometry.centeredFrame(
            size: NSSize(width: 720, height: 460),
            visibleFrame: visible
        )

        XCTAssertEqual(frame, visible)
    }
}
