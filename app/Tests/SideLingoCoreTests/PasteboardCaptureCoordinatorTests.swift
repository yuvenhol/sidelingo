import Foundation
import XCTest
@testable import SideLingoCore

final class PasteboardCaptureCoordinatorTests: XCTestCase {
    func testCapturesNewStableTextWithoutWritingToPasteboard() {
        let pasteboard = FakePasteboard()
        let coordinator = PasteboardCaptureCoordinator(
            pasteboard: pasteboard,
            sendCopy: {
                pasteboard.replaceWithCopiedText("selected text")
                return true
            }
        )

        XCTAssertEqual(coordinator.capture(timeout: 0), .captured(text: "selected text"))
        XCTAssertEqual(pasteboard.copyWriteCount, 1)
    }

    func testRejectsAnUnchangedClipboard() {
        let pasteboard = FakePasteboard()
        let coordinator = PasteboardCaptureCoordinator(pasteboard: pasteboard, sendCopy: { true })

        XCTAssertEqual(coordinator.capture(timeout: 0), .unchanged)
        XCTAssertEqual(pasteboard.stringReadCount, 0)
    }

    func testReportsConflictWhenClipboardChangesWhileTextIsRead() {
        let pasteboard = FakePasteboard()
        pasteboard.changeDuringStringRead = true
        let coordinator = PasteboardCaptureCoordinator(
            pasteboard: pasteboard,
            sendCopy: {
                pasteboard.replaceWithCopiedText("selected text")
                return true
            }
        )

        XCTAssertEqual(coordinator.capture(timeout: 0), .conflict)
    }

    func testReportsUnsupportedWhenCopyCommandCannotBeSent() {
        let pasteboard = FakePasteboard()
        let coordinator = PasteboardCaptureCoordinator(pasteboard: pasteboard, sendCopy: { false })

        XCTAssertEqual(coordinator.capture(timeout: 0), .unsupported)
    }

    func testMapsOnlyStableCapturedTextToInvocationFallback() {
        XCTAssertEqual(PasteboardCaptureOutcome.captured(text: "selected").clipboardFallback, .captured("selected"))
        XCTAssertEqual(PasteboardCaptureOutcome.unchanged.clipboardFallback, .unchanged)
        XCTAssertEqual(PasteboardCaptureOutcome.conflict.clipboardFallback, .unavailable)
        XCTAssertEqual(PasteboardCaptureOutcome.unsupported.clipboardFallback, .unavailable)
    }

    func testExposesTextFreeDiagnosticCategories() {
        XCTAssertEqual(PasteboardCaptureOutcome.captured(text: "selected").diagnosticCategory, "captured")
        XCTAssertEqual(PasteboardCaptureOutcome.unchanged.diagnosticCategory, "unchanged")
        XCTAssertEqual(PasteboardCaptureOutcome.conflict.diagnosticCategory, "conflict")
        XCTAssertEqual(PasteboardCaptureOutcome.unsupported.diagnosticCategory, "unsupported")
    }
}

private final class FakePasteboard: PasteboardAccess {
    var changeDuringStringRead = false
    private(set) var changeCount = 10
    private(set) var copyWriteCount = 0
    private(set) var stringReadCount = 0
    private var currentText: String?

    func string() -> String? {
        stringReadCount += 1
        if changeDuringStringRead {
            changeCount += 1
        }
        return currentText
    }

    func replaceWithCopiedText(_ text: String) {
        currentText = text
        copyWriteCount += 1
        changeCount += 1
    }
}
