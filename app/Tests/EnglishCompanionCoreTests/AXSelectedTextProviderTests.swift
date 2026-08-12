import XCTest
@testable import EnglishCompanionCore

final class AXSelectedTextProviderTests: XCTestCase {
    func testReturnsPermissionRequiredBeforeQueryingAnotherApp() {
        let provider = AXSelectedTextProvider(isTrusted: { false })

        XCTAssertEqual(provider.capture(frontmostPID: 123), .permissionRequired)
    }

    func testMissingFrontmostApplicationReturnsNoSelection() {
        let provider = AXSelectedTextProvider(isTrusted: { true })

        XCTAssertEqual(provider.capture(frontmostPID: nil), .noSelection)
    }
}
