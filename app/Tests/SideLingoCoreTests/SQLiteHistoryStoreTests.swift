import CSQLite
import Foundation
import XCTest
@testable import SideLingoCore

final class SQLiteHistoryStoreTests: XCTestCase {
    func testPersistsDictionaryKindAndLemma() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidelingo-dictionary-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteHistoryStore(path: directory.appendingPathComponent("history.sqlite").path)

        try store.append(.init(
            mode: .translate,
            source: "relocated",
            result: "搬迁",
            createdAt: 100,
            kind: .dictionary,
            dictionaryLemma: "relocate"
        ))

        let record = try XCTUnwrap(store.recent(limit: 1).first)
        XCTAssertEqual(record.kind, .dictionary)
        XCTAssertEqual(record.dictionaryLemma, "relocate")
    }

    func testMigratesLegacyHistoryRowsWithoutLosingThem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidelingo-legacy-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("history.sqlite").path
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &database), SQLITE_OK)
        let sql = """
        CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mode TEXT NOT NULL,
            source TEXT NOT NULL,
            result TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        INSERT INTO history(mode, source, result, created_at)
        VALUES('improve', 'old', 'better', 1);
        """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let store = try SQLiteHistoryStore(path: path)
        let record = try XCTUnwrap(store.recent(limit: 1).first)

        XCTAssertEqual(record.source, "old")
        XCTAssertEqual(record.kind, .improvement)
        XCTAssertNil(record.dictionaryLemma)
    }

    func testRepairsPartiallyAppliedLegacyResultKindMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidelingo-partial-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("history.sqlite").path
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &database), SQLITE_OK)
        let sql = """
        CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mode TEXT NOT NULL,
            source TEXT NOT NULL,
            result TEXT NOT NULL,
            created_at REAL NOT NULL,
            result_kind TEXT NOT NULL DEFAULT 'translation'
        );
        INSERT INTO history(mode, source, result, created_at)
        VALUES('improve', 'old', 'better', 1);
        """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let record = try XCTUnwrap(SQLiteHistoryStore(path: path).recent(limit: 1).first)

        XCTAssertEqual(record.kind, .improvement)
        XCTAssertNil(record.dictionaryLemma)
    }

    func testThrowsWhenRecentQueryEndsWithSQLiteStepError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidelingo-step-error-\(UUID().uuidString)", isDirectory: true)
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
            .appendingPathComponent("sidelingo-spike-\(UUID().uuidString)", isDirectory: true)
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
