import XCTest
@testable import EnglishCompanionCore

final class CompanionFramedParserTests: XCTestCase {
    private let primaryMarker = "<<<ENGLISH_COMPANION::PRIMARY>>>"
    private let titleMarker = "<<<ENGLISH_COMPANION::SECONDARY_TITLE>>>"
    private let secondaryMarker = "<<<ENGLISH_COMPANION::SECONDARY>>>"
    private let endMarker = "<<<ENGLISH_COMPANION::END>>>"

    func testStreamsAllFieldsAcrossArbitraryMarkerBoundariesWithUTF8AndCRLF() throws {
        var parser = CompanionFramedParser()

        XCTAssertEqual(try parser.append("<<<ENGLISH_COMP"), [])
        XCTAssertEqual(try parser.append("ANION::PRIMARY>>>\r"), [])
        XCTAssertEqual(
            try parser.append("\n你"),
            [CompanionOutputPartial(primary: "你")]
        )
        XCTAssertEqual(
            try parser.append("好 🌍\r"),
            [CompanionOutputPartial(primary: "你好 🌍")]
        )
        XCTAssertEqual(
            try parser.append("\n<<<ENGLISH_COMPANION::SECONDARY_"),
            []
        )
        XCTAssertEqual(
            try parser.append("TITLE>>>\r\n含义"),
            [CompanionOutputPartial(primary: "你好 🌍", secondaryTitle: "含义")]
        )
        XCTAssertEqual(
            try parser.append("确认\r\n\(secondaryMarker)\r\n忠实"),
            [
                CompanionOutputPartial(primary: "你好 🌍", secondaryTitle: "含义确认"),
                CompanionOutputPartial(
                    primary: "你好 🌍",
                    secondaryTitle: "含义确认",
                    secondary: "忠实"
                ),
            ]
        )
        XCTAssertEqual(
            try parser.append("回译\r\n<<<ENGLISH_COMPANION::EN"),
            [
                CompanionOutputPartial(
                    primary: "你好 🌍",
                    secondaryTitle: "含义确认",
                    secondary: "忠实回译"
                )
            ]
        )
        XCTAssertEqual(try parser.append("D>>>\r\n  \t"), [])

        XCTAssertEqual(
            try parser.finish(),
            CompanionOutput(
                primary: "你好 🌍",
                secondaryTitle: "含义确认",
                secondary: "忠实回译"
            )
        )
    }

    func testEmitsEverySafeContentChunkCumulativelyForEachActiveField() throws {
        var parser = CompanionFramedParser()

        XCTAssertEqual(try parser.append("\(primaryMarker)\nPri"), [
            CompanionOutputPartial(primary: "Pri"),
        ])
        XCTAssertEqual(try parser.append("mary"), [
            CompanionOutputPartial(primary: "Primary"),
        ])
        XCTAssertEqual(try parser.append("\n\(titleMarker)\nTit"), [
            CompanionOutputPartial(primary: "Primary", secondaryTitle: "Tit"),
        ])
        XCTAssertEqual(try parser.append("le"), [
            CompanionOutputPartial(primary: "Primary", secondaryTitle: "Title"),
        ])
        XCTAssertEqual(try parser.append("\n\(secondaryMarker)\nSec"), [
            CompanionOutputPartial(primary: "Primary", secondaryTitle: "Title", secondary: "Sec"),
        ])
        XCTAssertEqual(try parser.append("ondary"), [
            CompanionOutputPartial(
                primary: "Primary",
                secondaryTitle: "Title",
                secondary: "Secondary"
            ),
        ])
        XCTAssertEqual(try parser.append("\n\(endMarker)"), [])
        _ = try parser.finish()
    }

    func testHandlesMultipleMarkersInOneChunkWithoutExposingFraming() throws {
        var parser = CompanionFramedParser()
        let updates = try parser.append(
            """
            \(primaryMarker)
            one
            \(titleMarker)
            two
            \(secondaryMarker)
            three
            \(endMarker)
            """
        )

        XCTAssertEqual(updates, [
            CompanionOutputPartial(primary: "one"),
            CompanionOutputPartial(primary: "one", secondaryTitle: "two"),
            CompanionOutputPartial(primary: "one", secondaryTitle: "two", secondary: "three"),
        ])
        XCTAssertFalse(updates.description.contains("<<<ENGLISH_COMPANION::"))
        XCTAssertEqual(
            try parser.finish(),
            CompanionOutput(primary: "one", secondaryTitle: "two", secondary: "three")
        )
    }

    func testBuffersPossibleMarkerPrefixInsteadOfExposingIt() throws {
        var parser = CompanionFramedParser()
        _ = try parser.append("\(primaryMarker)\nSafe")

        XCTAssertEqual(try parser.append(" content\n<<<ENGLISH_COMPAN"), [
            CompanionOutputPartial(primary: "Safe content"),
        ])
        XCTAssertEqual(try parser.append("ION::SECONDARY_TITLE>>>\nTitle"), [
            CompanionOutputPartial(primary: "Safe content", secondaryTitle: "Title"),
        ])
    }

    func testRejectsDuplicateOutOfOrderUnknownMissingAndMarkerTextInsideValues() throws {
        let invalidResponses = [
            framed(primaryMarker, "one", primaryMarker, "duplicate", secondaryMarker, "three", endMarker),
            framed(titleMarker, "out of order", primaryMarker, "one", secondaryMarker, "three", endMarker),
            framed(primaryMarker, "one", "<<<ENGLISH_COMPANION::UNKNOWN>>>", "two", secondaryMarker, "three", endMarker),
            framed(primaryMarker, "one", titleMarker, "two"),
            framed(primaryMarker, "one \(titleMarker) hidden", titleMarker, "two", secondaryMarker, "three", endMarker),
        ]

        for response in invalidResponses {
            XCTAssertThrowsError(try parse(response), "Expected rejection for \(response)") {
                XCTAssertEqual($0 as? CompanionFramedParsingError, .invalidResponse)
            }
        }
    }

    func testRejectsLeadingTextMissingLineBreaksAndTrailingNonWhitespaceAfterEnd() throws {
        let invalidResponses = [
            "leading\n" + validResponse,
            primaryMarker + "one\n" + titleMarker + "\ntwo\n" + secondaryMarker + "\nthree\n" + endMarker,
            validResponse + " provider-tail",
        ]

        for response in invalidResponses {
            XCTAssertThrowsError(try parse(response)) {
                XCTAssertEqual($0 as? CompanionFramedParsingError, .invalidResponse)
            }
        }
    }

    private var validResponse: String {
        framed(primaryMarker, "one", titleMarker, "two", secondaryMarker, "three", endMarker)
    }

    private func framed(_ pieces: String...) -> String {
        pieces.joined(separator: "\n")
    }

    private func parse(_ response: String) throws -> CompanionOutput {
        var parser = CompanionFramedParser()
        _ = try parser.append(response)
        return try parser.finish()
    }
}
