import Foundation
import XCTest
@testable import SideLingoCore

final class CompanionOutputTests: XCTestCase {
    func testDecodesTheThreeProductOwnedFields() throws {
        let content = #"{"primary":"Ready to send.","secondaryTitle":"Meaning check","secondary":"可以发送。"}"#

        let output = try CompanionOutputDecoder.decode(content)

        XCTAssertEqual(
            output,
            CompanionOutput(
                primary: "Ready to send.",
                secondaryTitle: "Meaning check",
                secondary: "可以发送。"
            )
        )
    }

    func testRejectsMissingOrAdditionalFields() {
        XCTAssertThrowsError(
            try CompanionOutputDecoder.decode(#"{"primary":"One","secondary":"Two"}"#)
        )
        XCTAssertThrowsError(
            try CompanionOutputDecoder.decode(
                #"{"primary":"One","secondaryTitle":"Title","secondary":"Two","debug":"not allowed"}"#
            )
        )
    }
}
