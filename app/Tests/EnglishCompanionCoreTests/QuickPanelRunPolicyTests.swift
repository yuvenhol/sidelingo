import XCTest
@testable import EnglishCompanionCore

final class QuickPanelRunPolicyTests: XCTestCase {
    func testEmptyInputDoesNotCreateRunRequest() {
        XCTAssertNil(QuickPanelRunPolicy.request(for: ""))
    }

    func testWhitespaceOnlyInputDoesNotCreateRunRequest() {
        XCTAssertNil(QuickPanelRunPolicy.request(for: " \n\t "))
    }

    func testNonEmptyInputCreatesTrimmedTypedRunRequest() {
        XCTAssertEqual(
            QuickPanelRunPolicy.request(for: "  Please help. \n"),
            QuickPanelRunRequest(text: "Please help.", sourceLabel: "Typed")
        )
    }
}
