import XCTest
@testable import EnglishCompanionCore

final class QuickPanelShortcutTests: XCTestCase {
    func testResultPresentationEnablesTextSelection() {
        XCTAssertTrue(QuickPanelResultPresentation.textSelectionEnabled)
    }

    func testCopyButtonDoesNotClaimSelectionAwareCommandC() {
        XCTAssertNil(QuickPanelResultPresentation.copyButtonShortcut)
        XCTAssertNil(QuickPanelResultPresentation.copyButtonKeycap)
    }
}
