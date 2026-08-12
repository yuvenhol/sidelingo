import XCTest
@testable import EnglishCompanionCore

final class InvocationCoordinatorTests: XCTestCase {
    func testSelectedTextWinsAndCarriesExplicitMode() {
        let coordinator = InvocationCoordinator()

        let result = coordinator.resolve(
            mode: .translate,
            accessibility: .selected("  这个方案晚点回复。  "),
            clipboardFallback: .captured("stale clipboard")
        )

        XCTAssertEqual(result, .ready(mode: .translate, text: "这个方案晚点回复。", source: .accessibility))
    }

    func testUnchangedClipboardIsNeverAcceptedAsSelection() {
        let coordinator = InvocationCoordinator()

        let result = coordinator.resolve(
            mode: .improve,
            accessibility: .noSelection,
            clipboardFallback: .unchanged
        )

        XCTAssertEqual(result, .unavailable(mode: .improve, reason: .noSelection))
    }

    func testPermissionRequiredRemainsExplicitWithoutClipboardCapture() {
        let coordinator = InvocationCoordinator()

        let result = coordinator.resolve(
            mode: .translate,
            accessibility: .permissionRequired,
            clipboardFallback: .unavailable
        )

        XCTAssertEqual(result, .unavailable(mode: .translate, reason: .permissionRequired))
    }
}
