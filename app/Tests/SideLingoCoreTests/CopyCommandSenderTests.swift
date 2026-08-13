import CoreGraphics
import XCTest
@testable import SideLingoCore

final class CopyCommandSenderTests: XCTestCase {
    func testSendsCommandCKeyDownAndKeyUp() {
        var events: [(CGKeyCode, Bool, CGEventFlags)] = []
        let sender = CopyCommandSender { keyCode, keyDown, flags in
            events.append((keyCode, keyDown, flags))
            return true
        }

        XCTAssertTrue(sender.send())
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].0, 8)
        XCTAssertTrue(events[0].1)
        XCTAssertTrue(events[0].2.contains(.maskCommand))
        XCTAssertEqual(events[1].0, 8)
        XCTAssertFalse(events[1].1)
        XCTAssertTrue(events[1].2.contains(.maskCommand))
    }

    func testFailsWhenEitherKeyEventCannotBePosted() {
        var eventNumber = 0
        let sender = CopyCommandSender { _, _, _ in
            eventNumber += 1
            return eventNumber == 1
        }

        XCTAssertFalse(sender.send())
    }
}
