import CSQLite
import Foundation

public struct ApplicationSupportMigrator {
    typealias DatabaseBackup = (_ source: URL, _ destination: URL) throws -> Void

    public static let legacyDirectoryName = "EnglishCompanion"

    private static let managedSQLiteDatabaseNames = [
        "history.sqlite",
        "provider.sqlite",
    ]

    private static let sqliteFamilySuffixes = [
        "",
        "-wal",
        "-shm",
        "-journal",
    ]

    private let fileManager: FileManager
    private let backupDatabase: DatabaseBackup

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        backupDatabase = SQLiteDatabaseBackup.copy
    }

    init(
        fileManager: FileManager = .default,
        backupDatabase: @escaping DatabaseBackup
    ) {
        self.fileManager = fileManager
        self.backupDatabase = backupDatabase
    }

    public func migrate(in applicationSupportDirectory: URL) throws {
        let legacyDirectory = applicationSupportDirectory.appendingPathComponent(
            Self.legacyDirectoryName,
            isDirectory: true
        )
        var legacyIsDirectory: ObjCBool = false
        let legacyExists = fileManager.fileExists(
            atPath: legacyDirectory.path,
            isDirectory: &legacyIsDirectory
        ) && legacyIsDirectory.boolValue

        let canonicalDirectory = applicationSupportDirectory.appendingPathComponent(
            SideLingoIdentity.applicationSupportDirectoryName,
            isDirectory: true
        )
        var canonicalIsDirectory: ObjCBool = false
        let canonicalExists = fileManager.fileExists(
            atPath: canonicalDirectory.path,
            isDirectory: &canonicalIsDirectory
        )
        if canonicalExists && !canonicalIsDirectory.boolValue {
            throw ApplicationSupportMigrationError.canonicalPathIsNotDirectory
        }

        if canonicalExists {
            do {
                try removeStagingFamilies(from: canonicalDirectory)
            } catch {
                throw ApplicationSupportMigrationError.stagingCleanupFailed
            }
        }

        guard legacyExists else {
            return
        }
        guard canonicalExists else {
            try fileManager.moveItem(at: legacyDirectory, to: canonicalDirectory)
            return
        }

        for databaseName in Self.managedSQLiteDatabaseNames {
            let stagingDatabaseName = Self.stagingDatabaseName(for: databaseName)
            let sourceDatabase = legacyDirectory.appendingPathComponent(databaseName)
            let destinationDatabase = canonicalDirectory.appendingPathComponent(databaseName)
            guard fileManager.fileExists(atPath: sourceDatabase.path),
                  !fileManager.fileExists(atPath: destinationDatabase.path) else {
                continue
            }

            let destinationFamily = Self.databaseFamilyURLs(
                named: databaseName,
                in: canonicalDirectory
            )
            if destinationFamily.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
                throw ApplicationSupportMigrationError.canonicalDatabaseFamilyConflict
            }

            let stagingDatabase = canonicalDirectory.appendingPathComponent(
                stagingDatabaseName
            )

            do {
                guard fileManager.createFile(
                    atPath: stagingDatabase.path,
                    contents: nil,
                    attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
                ) else {
                    throw ApplicationSupportMigrationError.stagingCreationFailed
                }
                try backupDatabase(sourceDatabase, stagingDatabase)
                try fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: Int16(0o600))],
                    ofItemAtPath: stagingDatabase.path
                )
                try removeDatabaseSidecars(
                    named: stagingDatabaseName,
                    from: canonicalDirectory
                )
                try fileManager.moveItem(
                    at: stagingDatabase,
                    to: destinationDatabase
                )
            } catch {
                do {
                    try removeDatabaseFamily(
                        named: stagingDatabaseName,
                        from: canonicalDirectory
                    )
                } catch {
                    throw ApplicationSupportMigrationError.stagingCleanupFailed
                }
                throw error
            }
        }
    }

    private static func stagingDatabaseName(for databaseName: String) -> String {
        ".\(databaseName).sidelingo-migration"
    }

    private static func databaseFamilyURLs(named databaseName: String, in directory: URL) -> [URL] {
        sqliteFamilySuffixes.map {
            directory.appendingPathComponent(databaseName + $0)
        }
    }

    private func removeStagingFamilies(from directory: URL) throws {
        for databaseName in Self.managedSQLiteDatabaseNames {
            try removeDatabaseFamily(
                named: Self.stagingDatabaseName(for: databaseName),
                from: directory
            )
        }
    }

    private func removeDatabaseFamily(named databaseName: String, from directory: URL) throws {
        for member in Self.databaseFamilyURLs(named: databaseName, in: directory) {
            if fileManager.fileExists(atPath: member.path) {
                try fileManager.removeItem(at: member)
            }
        }
    }

    private func removeDatabaseSidecars(named databaseName: String, from directory: URL) throws {
        for member in Self.databaseFamilyURLs(named: databaseName, in: directory).dropFirst() {
            if fileManager.fileExists(atPath: member.path) {
                try fileManager.removeItem(at: member)
            }
        }
    }
}

public enum ApplicationSupportMigrationError: Error, Equatable {
    case canonicalPathIsNotDirectory
    case canonicalDatabaseFamilyConflict
    case databaseBackupFailed
    case stagingCleanupFailed
    case stagingCreationFailed
}

private enum SQLiteDatabaseBackup {
    static func copy(source: URL, destination: URL) throws {
        var sourceDatabase: OpaquePointer?
        let sourceFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(source.path, &sourceDatabase, sourceFlags, nil) == SQLITE_OK,
              let sourceDatabase else {
            sqlite3_close(sourceDatabase)
            throw ApplicationSupportMigrationError.databaseBackupFailed
        }

        var destinationDatabase: OpaquePointer?
        let destinationFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(
            destination.path,
            &destinationDatabase,
            destinationFlags,
            nil
        ) == SQLITE_OK, let destinationDatabase else {
            sqlite3_close(destinationDatabase)
            sqlite3_close(sourceDatabase)
            throw ApplicationSupportMigrationError.databaseBackupFailed
        }

        _ = sqlite3_busy_timeout(sourceDatabase, 5_000)
        _ = sqlite3_busy_timeout(destinationDatabase, 5_000)

        guard let backup = sqlite3_backup_init(
            destinationDatabase,
            "main",
            sourceDatabase,
            "main"
        ) else {
            sqlite3_close(destinationDatabase)
            sqlite3_close(sourceDatabase)
            throw ApplicationSupportMigrationError.databaseBackupFailed
        }

        let stepStatus = sqlite3_backup_step(backup, -1)
        let finishStatus = sqlite3_backup_finish(backup)
        let destinationCloseStatus = sqlite3_close(destinationDatabase)
        let sourceCloseStatus = sqlite3_close(sourceDatabase)

        guard stepStatus == SQLITE_DONE,
              finishStatus == SQLITE_OK,
              destinationCloseStatus == SQLITE_OK,
              sourceCloseStatus == SQLITE_OK else {
            throw ApplicationSupportMigrationError.databaseBackupFailed
        }
    }
}
