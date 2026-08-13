import AppKit
import Carbon
import XCTest
@testable import SideLingoCore

final class GlobalHotKeyRegistrationTests: XCTestCase {
    @MainActor
    func testRegistersAndUnregistersSystemWideHotKey() throws {
        _ = NSApplication.shared
        let token = try GlobalHotKeyRegistration(
            signature: 0x54455354,
            identifier: 991,
            keyCode: UInt32(kVK_ANSI_9),
            modifiers: UInt32(cmdKey | optionKey | controlKey)
        )

        XCTAssertTrue(token.isRegistered)
        token.unregister()
        XCTAssertFalse(token.isRegistered)
    }
}
