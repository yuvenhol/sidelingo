import AppKit
import XCTest
@testable import SideLingoCore

@MainActor
final class ApplicationMenuTests: XCTestCase {
    func testStandardEditMenuProvidesResponderChainPasteCommand() throws {
        let mainMenu = ApplicationMenuFactory.makeMainMenu(
            applicationName: SideLingoIdentity.productName
        )
        let applicationMenu = try XCTUnwrap(mainMenu.items.first?.submenu)
        let editMenu = try XCTUnwrap(mainMenu.items.first(where: { $0.title == "Edit" })?.submenu)
        let paste = try XCTUnwrap(editMenu.items.first(where: { $0.title == "Paste" }))

        XCTAssertEqual(mainMenu.items.first?.title, "SideLingo")
        XCTAssertEqual(applicationMenu.items.first?.title, "Quit SideLingo")
        XCTAssertEqual(paste.keyEquivalent, "v")
        XCTAssertEqual(paste.action.map(NSStringFromSelector), "paste:")
        XCTAssertNil(paste.target)
    }
}
