import XCTest
@testable import EnglishCompanionCore

final class AccessibilityPermissionManagerTests: XCTestCase {
    func testReportsGrantedWithoutPromptingWhenAlreadyTrusted() {
        var promptCount = 0
        let manager = AccessibilityPermissionManager(
            isTrusted: { true },
            requestPrompt: { promptCount += 1; return true }
        )

        XCTAssertEqual(manager.requestIfNeeded(), .granted)
        XCTAssertEqual(promptCount, 0)
    }

    func testRequestsSystemPromptWhenPermissionIsMissing() {
        var promptCount = 0
        let manager = AccessibilityPermissionManager(
            isTrusted: { false },
            requestPrompt: { promptCount += 1; return false }
        )

        XCTAssertEqual(manager.requestIfNeeded(), .required)
        XCTAssertEqual(promptCount, 1)
    }
}
