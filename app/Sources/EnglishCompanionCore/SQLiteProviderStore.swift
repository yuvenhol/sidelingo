import CSQLite
import Foundation

public struct ProviderSettings: Equatable, Sendable {
    public let provider: SupportedProvider
    public let model: String
    public let apiKey: String

    public init(provider: SupportedProvider, model: String, apiKey: String) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
    }
}

public protocol ProviderSettingsStore: Sendable {
    func load() throws -> ProviderSettings?
    func save(_ settings: ProviderSettings) throws
}

public struct SQLiteProviderStoreError: Error, Equatable, LocalizedError, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
    public var description: String { message }
}

enum SQLiteProviderSaveStepResult {
    case done
    case failure
}

public final class SQLiteProviderStore: ProviderSettingsStore, @unchecked Sendable {
    private var database: OpaquePointer?
    private let lock = NSLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let saveStep: (OpaquePointer) -> SQLiteProviderSaveStepResult

    public convenience init(path: String) throws {
        try self.init(path: path) { statement in
            sqlite3_step(statement) == SQLITE_DONE ? .done : .failure
        }
    }

    init(
        path: String,
        saveStep: @escaping (OpaquePointer) -> SQLiteProviderSaveStepResult
    ) throws {
        self.saveStep = saveStep
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw SQLiteProviderStoreError("create directory failed")
        }

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK else {
            sqlite3_close(database)
            database = nil
            throw SQLiteProviderStoreError("open failed")
        }

        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: path
            )
            try execute("""
                CREATE TABLE IF NOT EXISTS provider_settings (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    provider TEXT NOT NULL,
                    model TEXT NOT NULL,
                    api_key TEXT NOT NULL
                );
                """)
        } catch let error as SQLiteProviderStoreError {
            sqlite3_close(database)
            database = nil
            throw error
        } catch {
            sqlite3_close(database)
            database = nil
            throw SQLiteProviderStoreError("set permissions failed")
        }
    }

    deinit {
        sqlite3_close(database)
    }

    public func load() throws -> ProviderSettings? {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT provider, model, api_key FROM provider_settings WHERE id = 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteProviderStoreError("prepare load failed")
        }
        defer { sqlite3_finalize(statement) }

        switch sqlite3_step(statement) {
        case SQLITE_DONE:
            return nil
        case SQLITE_ROW:
            guard let providerText = sqlite3_column_text(statement, 0),
                  let modelText = sqlite3_column_text(statement, 1),
                  let apiKeyText = sqlite3_column_text(statement, 2),
                  let provider = SupportedProvider(rawValue: String(cString: providerText)) else {
                throw SQLiteProviderStoreError("invalid settings row")
            }
            return ProviderSettings(
                provider: provider,
                model: String(cString: modelText),
                apiKey: String(cString: apiKeyText)
            )
        default:
            throw SQLiteProviderStoreError("load failed")
        }
    }

    public func save(_ settings: ProviderSettings) throws {
        lock.lock()
        defer { lock.unlock() }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        var committed = false
        defer {
            if !committed {
                sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            }
        }

        let sql = """
            INSERT INTO provider_settings(id, provider, model, api_key)
            VALUES(1, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                provider = excluded.provider,
                model = excluded.model,
                api_key = excluded.api_key
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteProviderStoreError("prepare save failed")
        }
        defer { sqlite3_finalize(statement) }

        try bind(settings.provider.rawValue, index: 1, statement: statement)
        try bind(settings.model, index: 2, statement: statement)
        try bind(settings.apiKey, index: 3, statement: statement)
        guard saveStep(statement) == .done else {
            throw SQLiteProviderStoreError("save failed")
        }
        try execute("COMMIT")
        committed = true
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteProviderStoreError("database operation failed")
        }
    }

    private func bind(_ value: String, index: Int32, statement: OpaquePointer) throws {
        let status = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, transient)
        }
        guard status == SQLITE_OK else {
            throw SQLiteProviderStoreError("bind failed")
        }
    }
}
