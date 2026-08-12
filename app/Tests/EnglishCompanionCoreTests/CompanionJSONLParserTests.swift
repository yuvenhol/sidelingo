import XCTest
@testable import EnglishCompanionCore

final class CompanionJSONLParserTests: XCTestCase {
    func testEmitsFieldsAcrossArbitraryChunkBoundariesIncludingUTF8AndCRLF() throws {
        var parser = CompanionJSONLParser()

        XCTAssertEqual(try parser.append(#"{"f"#), [])
        XCTAssertEqual(
            try parser.append("ield\":\"primary\",\"value\":\"你好 🌍\"}\r"),
            []
        )
        XCTAssertEqual(
            try parser.append("\n\n{\"field\":\"secondaryTitle\",\"value\":\"含义确认\"}\n"),
            [
                CompanionOutputPartial(primary: "你好 🌍"),
                CompanionOutputPartial(primary: "你好 🌍", secondaryTitle: "含义确认"),
            ]
        )
        XCTAssertEqual(
            try parser.append(#"{"field":"secondary","value":"忠实回译"}"#),
            []
        )

        XCTAssertEqual(
            try parser.finish(),
            CompanionOutput(
                primary: "你好 🌍",
                secondaryTitle: "含义确认",
                secondary: "忠实回译"
            )
        )
    }

    func testEmitsPrimaryAsSoonAsItsCompleteLineArrives() throws {
        var parser = CompanionJSONLParser()

        XCTAssertEqual(
            try parser.append("{\"field\":\"primary\",\"value\":\"Ready\"}\n{\"field\":\"secondary"),
            [CompanionOutputPartial(primary: "Ready")]
        )
    }

    func testRejectsDuplicateOutOfOrderUnknownAndMissingFields() throws {
        let invalidResponses = [
            """
            {"field":"primary","value":"one"}
            {"field":"primary","value":"duplicate"}
            {"field":"secondary","value":"three"}
            """,
            """
            {"field":"secondaryTitle","value":"out of order"}
            {"field":"primary","value":"one"}
            {"field":"secondary","value":"three"}
            """,
            """
            {"field":"primary","value":"one"}
            {"field":"unknown","value":"two"}
            {"field":"secondary","value":"three"}
            """,
            """
            {"field":"primary","value":"one"}
            {"field":"secondaryTitle","value":"two"}
            """,
        ]

        for response in invalidResponses {
            XCTAssertThrowsError(try parse(response)) {
                XCTAssertEqual($0 as? CompanionJSONLParsingError, .invalidResponse)
            }
        }
    }

    func testRejectsMalformedRecordsNonStringValuesAndUnexpectedRecordKeys() {
        let invalidLines = [
            "not json\n",
            "{\"field\":\"primary\",\"value\":42}\n",
            "{\"field\":\"primary\",\"value\":\"one\",\"debug\":\"raw\"}\n",
            "{\"field\":\"primary\"}\n",
        ]

        for line in invalidLines {
            var parser = CompanionJSONLParser()
            XCTAssertThrowsError(try parser.append(line)) {
                XCTAssertEqual($0 as? CompanionJSONLParsingError, .invalidResponse)
            }
        }
    }

    func testRejectsAnyFourthNonBlankRecord() throws {
        var parser = CompanionJSONLParser()
        _ = try parser.append(
            """
            {"field":"primary","value":"one"}
            {"field":"secondaryTitle","value":"two"}
            {"field":"secondary","value":"three"}
            {"field":"primary","value":"four"}
            """
        )

        XCTAssertThrowsError(try parser.finish()) {
            XCTAssertEqual($0 as? CompanionJSONLParsingError, .invalidResponse)
        }
    }

    private func parse(_ response: String) throws -> CompanionOutput {
        var parser = CompanionJSONLParser()
        _ = try parser.append(response)
        return try parser.finish()
    }
}
