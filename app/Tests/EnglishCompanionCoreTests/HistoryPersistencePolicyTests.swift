import XCTest
@testable import EnglishCompanionCore

final class HistoryPersistencePolicyTests: XCTestCase {
    func testDemoPresentationDoesNotAppendHistory() throws {
        var appendedRecords: [HistoryRecord] = []
        let record = HistoryRecord(
            mode: .translate,
            source: "fabricated demo input",
            result: "fabricated demo output",
            createdAt: 100
        )

        HistoryPersistencePolicy.record(record, presentation: .demo) {
            appendedRecords.append($0)
        }

        XCTAssertTrue(appendedRecords.isEmpty)
    }
}
