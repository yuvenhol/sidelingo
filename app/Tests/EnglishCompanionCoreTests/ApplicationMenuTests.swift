import AppKit
import XCTest
@testable import EnglishCompanionCore

@MainActor
final class ApplicationMenuTests: XCTestCase {
    func testStandardEditMenuProvidesResponderChainPasteCommand() throws {
        let mainMenu = ApplicationMenuFactory.makeMainMenu(applicationName: "English Companion")
        let editMenu = try XCTUnwrap(mainMenu.items.first(where: { $0.title == "Edit" })?.submenu)
        let paste = try XCTUnwrap(editMenu.items.first(where: { $0.title == "Paste" }))

        XCTAssertEqual(paste.keyEquivalent, "v")
        XCTAssertEqual(paste.action.map(NSStringFromSelector), "paste:")
        XCTAssertNil(paste.target)
    }
}
