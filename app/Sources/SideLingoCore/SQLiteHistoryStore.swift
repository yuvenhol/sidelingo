import CSQLite
import Foundation

public enum HistoryResultKind: String, Equatable, Sendable {
    case translation
    case improvement
    case dictionary
}

public struct HistoryRecord: Equatable, Sendable {
    public let mode: CompanionMode
    public let source: String
    public let result: String
    public let createdAt: Double
    public let kind: HistoryResultKind
    public let dictionaryLemma: String?

    public init(
        mode: CompanionMode,
        source: String,
        result: String,
        createdAt: Double,
        kind: HistoryResultKind? = nil,
        dictionaryLemma: String? = nil
    ) {
        self.mode = mode
        self.source = source
        self.result = result
        self.createdAt = createdAt
        self.kind = kind ?? (mode == .improve ? .improvement : .translation)
        self.dictionaryLemma = dictionaryLemma
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
                created_at REAL NOT NULL,
                result_kind TEXT NOT NULL,
                dictionary_lemma TEXT
            );
            """)
        try migrateResultMetadataIfNeeded()
    }

    deinit {
        sqlite3_close(database)
    }

    public func append(_ record: HistoryRecord) throws {
        let sql = """
        INSERT INTO history(mode, source, result, created_at, result_kind, dictionary_lemma)
        VALUES(?, ?, ?, ?, ?, ?)
        """
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
        try bind(record.kind.rawValue, index: 5, statement: statement)
        if let lemma = record.dictionaryLemma {
            try bind(lemma, index: 6, statement: statement)
        } else if sqlite3_bind_null(statement, 6) != SQLITE_OK {
            throw error("bind dictionary lemma")
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error("insert")
        }
    }

    public func recent(limit: Int) throws -> [HistoryRecord] {
        let sql = """
        SELECT mode, source, result, created_at, result_kind, dictionary_lemma
        FROM history
        ORDER BY created_at DESC, id DESC
        LIMIT ?
        """
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
                  let kindCString = sqlite3_column_text(statement, 4),
                  let mode = CompanionMode(rawValue: String(cString: modeCString)),
                  let kind = HistoryResultKind(rawValue: String(cString: kindCString)) else {
                throw SQLiteStoreError("invalid row")
            }
            let dictionaryLemma = sqlite3_column_text(statement, 5)
                .map { String(cString: $0) }
            records.append(
                HistoryRecord(
                    mode: mode,
                    source: String(cString: sourceCString),
                    result: String(cString: resultCString),
                    createdAt: sqlite3_column_double(statement, 3),
                    kind: kind,
                    dictionaryLemma: dictionaryLemma
                )
            )
        }
    }

    private func migrateResultMetadataIfNeeded() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "PRAGMA table_info(history)", -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw error("prepare history schema")
            }
            var columns: Set<String> = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let name = sqlite3_column_text(statement, 1) {
                    columns.insert(String(cString: name))
                }
            }
            sqlite3_finalize(statement)

            if !columns.contains("result_kind") {
                try execute("ALTER TABLE history ADD COLUMN result_kind TEXT NOT NULL DEFAULT 'translation'")
            }
            try execute("""
                UPDATE history
                SET result_kind = 'improvement'
                WHERE mode = 'improve' AND result_kind = 'translation'
                """)
            if !columns.contains("dictionary_lemma") {
                try execute("ALTER TABLE history ADD COLUMN dictionary_lemma TEXT")
            }
            try execute("PRAGMA user_version = 1")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
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
