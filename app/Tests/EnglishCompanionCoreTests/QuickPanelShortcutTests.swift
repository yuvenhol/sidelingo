import XCTest
@testable import EnglishCompanionCore

final class QuickPanelShortcutTests: XCTestCase {
    func testInputPresentationUsesCenteredSingleLineEditorAndFullPreview() {
        XCTAssertEqual(QuickPanelInputPresentation.editorLineLimit, 1)
        XCTAssertTrue(QuickPanelInputPresentation.centersControlsVertically)
        XCTAssertTrue(QuickPanelInputPresentation.showsFullInputPreview)
        XCTAssertEqual(QuickPanelInputPresentation.previewTitle, "INPUT")
        XCTAssertGreaterThan(QuickPanelInputPresentation.panelHeight, 414)
    }

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

    func testStreamingPartialMapsOnlyAvailableTypedFieldsForDisplay() {
        let partial = CompanionOutputPartial(
            primary: "Visible now",
            secondaryTitle: "MEANING CHECK"
        )

        XCTAssertEqual(
            QuickPanelResultPresentation.output(for: partial),
            CompanionOutput(
                primary: "Visible now",
                secondaryTitle: "MEANING CHECK",
                secondary: ""
            )
        )
    }
}
