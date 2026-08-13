import CSQLite
import Foundation

public struct HistoryRecord: Equatable, Sendable {
    public let mode: CompanionMode
    public let source: String
    public let result: String
    public let createdAt: Double

    public init(mode: CompanionMode, source: String, result: String, createdAt: Double) {
        self.mode = mode
        self.source = source
        self.result = result
        self.createdAt = createdAt
    }
}

public struct SQLiteStoreError: Error, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

enum SQLiteQueryStepResult {
    case row
    case done
    case failure
}

public final class SQLiteHistoryStore: @unchecked Sendable {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let queryStep: (OpaquePointer) -> SQLiteQueryStepResult

    public convenience init(path: String) throws {
        try self.init(path: path) { statement in
            switch sqlite3_step(statement) {
            case SQLITE_ROW: .row
            case SQLITE_DONE: .done
            default: .failure
            }
        }
    }

    init(path: String, queryStep: @escaping (OpaquePointer) -> SQLiteQueryStepResult) throws {
        self.queryStep = queryStep
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            throw SQLiteStoreError("open failed")
        }
        try execute("""
            CREATE TABLE IF NOT EXISTS history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                mode TEXT NOT NULL,
                source TEXT NOT NULL,
                result TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """)
    }

    deinit {
        sqlite3_close(database)
    }

    public func append(_ record: HistoryRecord) throws {
        let sql = "INSERT INTO history(mode, source, result, created_at) VALUES(?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw error("prepare insert")
        }
        defer { sqlite3_finalize(statement) }

        try bind(record.mode.rawValue, index: 1, statement: statement)
        try bind(record.source, index: 2, statement: statement)
        try bind(record.result, index: 3, statement: statement)
        guard sqlite3_bind_double(statement, 4, record.createdAt) == SQLITE_OK else {
            throw error("bind timestamp")
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error("insert")
        }
    }

    public func recent(limit: Int) throws -> [HistoryRecord] {
        let sql = "SELECT mode, source, result, created_at FROM history ORDER BY created_at DESC, id DESC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw error("prepare query")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int64(statement, 1, Int64(max(0, limit))) == SQLITE_OK else {
            throw error("bind limit")
        }

        var records: [HistoryRecord] = []
        while true {
            switch queryStep(statement) {
            case .done:
                return records
            case .failure:
                throw error("query")
            case .row:
                break
            }
            guard let modeCString = sqlite3_column_text(statement, 0),
                  let sourceCString = sqlite3_column_text(statement, 1),
                  let resultCString = sqlite3_column_text(statement, 2),
                  let mode = CompanionMode(rawValue: String(cString: modeCString)) else {
                throw SQLiteStoreError("invalid row")
            }
            records.append(
                HistoryRecord(
                    mode: mode,
                    source: String(cString: sourceCString),
                    result: String(cString: resultCString),
                    createdAt: sqlite3_column_double(statement, 3)
                )
            )
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw error("execute")
        }
    }

    private func bind(_ value: String, index: Int32, statement: OpaquePointer) throws {
        let status = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, transient)
        }
        guard status == SQLITE_OK else {
            throw error("bind text")
        }
    }

    private func error(_ operation: String) -> SQLiteStoreError {
        let detail = database.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "unknown"
        return SQLiteStoreError("\(operation): \(detail)")
    }
}
