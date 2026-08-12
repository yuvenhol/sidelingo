import Foundation
import XCTest
@testable import EnglishCompanionCore

final class SQLiteHistoryStoreTests: XCTestCase {
    func testThrowsWhenRecentQueryEndsWithSQLiteStepError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("english-companion-step-error-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SQLiteHistoryStore(
            path: directory.appendingPathComponent("history.sqlite").path,
            queryStep: { _ in .failure }
        )

        XCTAssertThrowsError(try store.recent(limit: 10)) { error in
            XCTAssertTrue((error as? SQLiteStoreError)?.message.hasPrefix("query:") == true)
        }
    }

    func testPersistsAndReadsUTF8HistoryInNewestFirstOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("english-companion-spike-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("history.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SQLiteHistoryStore(path: path.path)
        try store.append(.init(mode: .translate, source: "这个方案晚点回复。", result: "I'll get back to you later.", createdAt: 100))
        try store.append(.init(mode: .improve, source: "Is there anything need?", result: "Is there anything you need?", createdAt: 200))

        let records = try store.recent(limit: 10)

        XCTAssertEqual(records.map(\.mode), [.improve, .translate])
        XCTAssertEqual(records.last?.source, "这个方案晚点回复。")
        XCTAssertEqual(records.last?.result, "I'll get back to you later.")
    }
}
