import XCTest
@testable import EnglishCompanionCore

final class QuickPanelShortcutTests: XCTestCase {
    func testTranslatePrimaryTitleIsDirectionNeutral() {
        XCTAssertEqual(
            QuickPanelResultPresentation.primaryTitle(mode: .translate, inputUnavailable: false),
            "TRANSLATION"
        )
    }

    func testResultPresentationEnablesTextSelection() {
        XCTAssertTrue(QuickPanelResultPresentation.textSelectionEnabled)
    }

    func testCopyButtonDoesNotClaimSelectionAwareCommandC() {
        XCTAssertNil(QuickPanelResultPresentation.copyButtonShortcut)
        XCTAssertNil(QuickPanelResultPresentation.copyButtonKeycap)
    }
}
