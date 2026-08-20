import CSQLite
import Foundation

public struct DictionaryEntry: Equatable, Sendable {
    public let word: String
    public let phonetic: String
    public let definition: String
    public let translation: String
    public let pos: String
    public let collins: Int?
    public let oxford: Bool
    public let tags: [String]
    public let bncRank: Int?
    public let frequencyRank: Int?
    public let exchange: String
    public let detail: String
    public let audio: String

    public init(
        word: String,
        phonetic: String,
        definition: String,
        translation: String,
        pos: String,
        collins: Int?,
        oxford: Bool,
        tags: [String],
        bncRank: Int?,
        frequencyRank: Int?,
        exchange: String,
        detail: String,
        audio: String
    ) {
        self.word = word
        self.phonetic = phonetic
        self.definition = definition
        self.translation = translation
        self.pos = pos
        self.collins = collins
        self.oxford = oxford
        self.tags = tags
        self.bncRank = bncRank
        self.frequencyRank = frequencyRank
        self.exchange = exchange
        self.detail = detail
        self.audio = audio
    }
}

public struct DictionaryLookup: Equatable, Sendable {
    public let query: String
    public let lemma: String
    public let entry: DictionaryEntry

    public init(query: String, lemma: String, entry: DictionaryEntry) {
        self.query = query
        self.lemma = lemma
        self.entry = entry
    }
}

public protocol DictionaryLookupProviding: Sendable {
    func lookup(_ query: String) throws -> DictionaryLookup?
}

public final class SQLiteDictionaryStore: DictionaryLookupProviding, @unchecked Sendable {
    private var database: OpaquePointer?
    private let lock = NSLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK else {
            let detail = database.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "unknown"
            sqlite3_close(database)
            database = nil
            throw SQLiteStoreError("dictionary open: \(detail)")
        }
    }

    deinit {
        sqlite3_close(database)
    }

    public func lookup(_ query: String) throws -> DictionaryLookup? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if let entry = try entry(matching: trimmed) {
            return try resolvedLookup(query: trimmed, entry: entry)
        }
        let normalized = Self.normalizedKey(trimmed)
        if !normalized.isEmpty, let entry = try entry(matchingNormalized: normalized) {
            return try resolvedLookup(query: trimmed, entry: entry)
        }
        guard let lemma = try lemma(for: trimmed),
              let entry = try entry(matching: lemma) else {
            return nil
        }
        return DictionaryLookup(query: trimmed, lemma: entry.word, entry: entry)
    }

    private func resolvedLookup(query: String, entry: DictionaryEntry) throws -> DictionaryLookup {
        if let exchangeLemma = Self.exchangeLemma(entry.exchange),
           exchangeLemma.caseInsensitiveCompare(entry.word) != .orderedSame {
            if let baseEntry = try self.entry(matching: exchangeLemma) {
                return DictionaryLookup(query: query, lemma: baseEntry.word, entry: baseEntry)
            }
            if let indexedLemma = try lemma(for: entry.word),
               let baseEntry = try self.entry(matching: indexedLemma) {
                return DictionaryLookup(query: query, lemma: baseEntry.word, entry: baseEntry)
            }
        }
        return DictionaryLookup(query: query, lemma: entry.word, entry: entry)
    }

    private static func exchangeLemma(_ exchange: String) -> String? {
        for component in exchange.split(separator: "/") {
            guard component.hasPrefix("0:") else { continue }
            let lemma = component.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
            return lemma.isEmpty ? nil : lemma
        }
        return nil
    }

    private func lemma(for form: String) throws -> String? {
        let sql = "SELECT lemma FROM lemmas WHERE form = ? COLLATE NOCASE LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw error("lemma prepare")
        }
        defer { sqlite3_finalize(statement) }
        try bind(form, index: 1, statement: statement)
        switch sqlite3_step(statement) {
        case SQLITE_DONE:
            return nil
        case SQLITE_ROW:
            return text(at: 0, statement: statement)
        default:
            throw error("lemma query")
        }
    }

    private func entry(matching word: String) throws -> DictionaryEntry? {
        try entry(
            sql: """
            SELECT word, phonetic, definition, translation, pos, collins, oxford,
                   tag, bnc, frq, exchange, detail, audio
            FROM entries
            WHERE word = ? COLLATE NOCASE
            LIMIT 1
            """,
            value: word
        )
    }

    private func entry(matchingNormalized normalized: String) throws -> DictionaryEntry? {
        try entry(
            sql: """
            SELECT word, phonetic, definition, translation, pos, collins, oxford,
                   tag, bnc, frq, exchange, detail, audio
            FROM entries
            WHERE normalized = ?1
              AND (SELECT COUNT(*) FROM entries WHERE normalized = ?1) = 1
            LIMIT 1
            """,
            value: normalized
        )
    }

    private func entry(sql: String, value: String) throws -> DictionaryEntry? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw error("dictionary prepare")
        }
        defer { sqlite3_finalize(statement) }
        try bind(value, index: 1, statement: statement)

        switch sqlite3_step(statement) {
        case SQLITE_DONE:
            return nil
        case SQLITE_ROW:
            return DictionaryEntry(
                word: text(at: 0, statement: statement),
                phonetic: text(at: 1, statement: statement),
                definition: text(at: 2, statement: statement),
                translation: text(at: 3, statement: statement),
                pos: text(at: 4, statement: statement),
                collins: positiveInteger(at: 5, statement: statement),
                oxford: sqlite3_column_int(statement, 6) != 0,
                tags: text(at: 7, statement: statement)
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init),
                bncRank: positiveInteger(at: 8, statement: statement),
                frequencyRank: positiveInteger(at: 9, statement: statement),
                exchange: text(at: 10, statement: statement),
                detail: text(at: 11, statement: statement),
                audio: text(at: 12, statement: statement)
            )
        default:
            throw error("dictionary query")
        }
    }

    private func text(at index: Int32, statement: OpaquePointer) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func positiveInteger(at index: Int32, statement: OpaquePointer) -> Int? {
        let value = Int(sqlite3_column_int64(statement, index))
        return value > 0 ? value : nil
    }

    private func bind(_ value: String, index: Int32, statement: OpaquePointer) throws {
        let status = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, transient)
        }
        guard status == SQLITE_OK else { throw error("dictionary bind") }
    }

    private static func normalizedKey(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private func error(_ operation: String) -> SQLiteStoreError {
        let detail = database.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "unknown"
        return SQLiteStoreError("\(operation): \(detail)")
    }
}
