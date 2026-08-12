import XCTest
@testable import EnglishCompanionCore

final class MockProcessorTests: XCTestCase {
    func testTranslateProducesSlackStyleEnglishAndMeaningCheck() {
        let output = MockProcessor().process(
            mode: .translate,
            text: "这个方案我需要再看一下，晚点回复你。"
        )

        XCTAssertEqual(output.primary, "Let me take another look at this and get back to you later.")
        XCTAssertEqual(output.secondaryTitle, "中文回译 · MEANING CHECK")
        XCTAssertEqual(output.secondary, "让我再看一下这个，晚点再回复你。")
    }

    func testImproveProducesNaturalEnglishAndExplanation() {
        let output = MockProcessor().process(
            mode: .improve,
            text: "Is there anything need from our end?"
        )

        XCTAssertEqual(output.primary, "Is there anything you need from our side?")
        XCTAssertEqual(output.secondaryTitle, "DETAILED CHANGES")
        XCTAssertTrue(output.secondary.contains("you"))
    }
}
