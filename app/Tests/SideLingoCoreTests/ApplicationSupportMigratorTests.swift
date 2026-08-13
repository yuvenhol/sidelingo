import Foundation
import XCTest
@testable import SideLingoCore

final class ApplicationSupportMigratorTests: XCTestCase {
    func testRemovesStaleStagingWhenLegacyDirectoryNoLongerExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let canonical = root.appendingPathComponent("SideLingo", isDirectory: true)
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        let staging = canonical.appendingPathComponent(".provider.sqlite.sidelingo-migration")
        try write("stale-main", to: staging)
        try write("stale-journal", to: URL(fileURLWithPath: staging.path + "-journal"))

        try ApplicationSupportMigrator().migrate(in: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path + "-journal"))
    }

    func testMovesLegacyDirectoryWhenCanonicalDirectoryDoesNotExist() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("EnglishCompanion", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: legacy.appendingPathComponent("history.sqlite"))
        try Data("keep".utf8).write(to: legacy.appendingPathComponent("notes.txt"))

        try ApplicationSupportMigrator().migrate(in: root)

        let canonical = root.appendingPathComponent("SideLingo", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(try Data(contentsOf: canonical.appendingPathComponent("history.sqlite")), Data("history".utf8))
        XCTAssertEqual(try Data(contentsOf: canonical.appendingPathComponent("notes.txt")), Data("keep".utf8))
    }

    func testBacksUpMissingDatabaseWithoutOverwritingCurrentDatabaseOrCopyingSidecars() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("EnglishCompanion", isDirectory: true)
        let canonical = root.appendingPathComponent("SideLingo", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)

        let expectedHistory = HistoryRecord(
            mode: .translate,
            source: "legacy source",
            result: "legacy result",
            createdAt: 42
        )
        do {
            let history = try SQLiteHistoryStore(
                path: legacy.appendingPathComponent("history.sqlite").path
            )
            try history.append(expectedHistory)
        }
        try write("legacy-journal", to: legacy.appendingPathComponent("history.sqlite-journal"))

        let preservedProviderFiles = [
            "provider.sqlite",
            "provider.sqlite-wal",
            "provider.sqlite-shm",
            "provider.sqlite-journal",
        ]
        for name in preservedProviderFiles {
            try write("legacy-\(name)", to: legacy.appendingPathComponent(name))
        }
        try write("current-provider", to: canonical.appendingPathComponent("provider.sqlite"))
        let staleProviderStaging = canonical.appendingPathComponent(
            ".provider.sqlite.sidelingo-migration"
        )
        try write("stale-provider-staging", to: staleProviderStaging)
        try write(
            "stale-provider-journal",
            to: URL(fileURLWithPath: staleProviderStaging.path + "-journal")
        )
        try write("unknown", to: legacy.appendingPathComponent("notes.txt"))

        try ApplicationSupportMigrator().migrate(in: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleProviderStaging.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: staleProviderStaging.path + "-journal")
        )

        let migratedHistory = try SQLiteHistoryStore(
            path: canonical.appendingPathComponent("history.sqlite").path
        )
        XCTAssertEqual(try migratedHistory.recent(limit: 1), [expectedHistory])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("history.sqlite").path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: canonical.appendingPathComponent("history.sqlite-journal").path
            )
        )
        XCTAssertEqual(try text(at: canonical.appendingPathComponent("provider.sqlite")), "current-provider")
        for name in preservedProviderFiles {
            XCTAssertEqual(
                try text(at: legacy.appendingPathComponent(name)),
                "legacy-\(name)"
            )
            if name != "provider.sqlite" {
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: canonical.appendingPathComponent(name).path)
                )
            }
        }
        XCTAssertEqual(try text(at: legacy.appendingPathComponent("notes.txt")), "unknown")
    }

    func testBackupFailureRemovesCanonicalFragmentsAndRetryPreservesLegacyFamily() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("EnglishCompanion", isDirectory: true)
        let canonical = root.appendingPathComponent("SideLingo", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        let familyNames = [
            "provider.sqlite",
            "provider.sqlite-wal",
            "provider.sqlite-shm",
            "provider.sqlite-journal",
        ]
        for name in familyNames {
            try write("legacy-\(name)", to: legacy.appendingPathComponent(name))
        }

        var attemptedDestination: URL?
        var destinationPermissionsAtBackupStart: Int?
        let failingMigrator = ApplicationSupportMigrator { _, destination in
            attemptedDestination = destination
            let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
            destinationPermissionsAtBackupStart = (attributes?[.posixPermissions] as? NSNumber)?.intValue
            try Data("partial-main".utf8).write(to: destination)
            try Data("partial-journal".utf8).write(
                to: URL(fileURLWithPath: destination.path + "-journal")
            )
            throw InjectedBackupError.failed
        }

        XCTAssertThrowsError(try failingMigrator.migrate(in: root))
        XCTAssertEqual(destinationPermissionsAtBackupStart.map { $0 & 0o777 }, 0o600)
        let stagingDatabase = try XCTUnwrap(attemptedDestination)
        XCTAssertEqual(stagingDatabase.lastPathComponent, ".provider.sqlite.sidelingo-migration")
        for suffix in ["", "-wal", "-shm", "-journal"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDatabase.path + suffix))
        }
        for name in familyNames {
            XCTAssertEqual(try text(at: legacy.appendingPathComponent(name)), "legacy-\(name)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.appendingPathComponent(name).path))
        }

        try write("stale-staging", to: stagingDatabase)
        try write(
            "stale-staging-journal",
            to: URL(fileURLWithPath: stagingDatabase.path + "-journal")
        )

        let retryingMigrator = ApplicationSupportMigrator { source, destination in
            try Data(contentsOf: source).write(to: destination)
        }
        try retryingMigrator.migrate(in: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDatabase.path))
        for suffix in ["-wal", "-shm", "-journal"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDatabase.path + suffix))
        }
        XCTAssertEqual(
            try text(at: canonical.appendingPathComponent("provider.sqlite")),
            "legacy-provider.sqlite"
        )
        for name in familyNames {
            XCTAssertEqual(try text(at: legacy.appendingPathComponent(name)), "legacy-\(name)")
        }
        for name in familyNames where name != "provider.sqlite" {
            XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.appendingPathComponent(name).path))
        }
    }

    func testMigrationIsIdempotentAfterPartialMerge() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("EnglishCompanion", isDirectory: true)
        let canonical = root.appendingPathComponent("SideLingo", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        try write("legacy-history", to: legacy.appendingPathComponent("history.sqlite"))
        try write("legacy-provider", to: legacy.appendingPathComponent("provider.sqlite"))
        try write("current-provider", to: canonical.appendingPathComponent("provider.sqlite"))

        let migrator = ApplicationSupportMigrator { source, destination in
            try Data(contentsOf: source).write(to: destination)
        }
        try migrator.migrate(in: root)
        try migrator.migrate(in: root)

        XCTAssertEqual(try text(at: canonical.appendingPathComponent("history.sqlite")), "legacy-history")
        XCTAssertEqual(try text(at: legacy.appendingPathComponent("history.sqlite")), "legacy-history")
        XCTAssertEqual(try text(at: canonical.appendingPathComponent("provider.sqlite")), "current-provider")
        XCTAssertEqual(try text(at: legacy.appendingPathComponent("provider.sqlite")), "legacy-provider")
    }

    func testRejectsCanonicalOrphanSidecarWithoutMovingLegacyDatabaseFamily() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("EnglishCompanion", isDirectory: true)
        let canonical = root.appendingPathComponent("SideLingo", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        try write("legacy-history", to: legacy.appendingPathComponent("history.sqlite"))
        try write("legacy-wal", to: legacy.appendingPathComponent("history.sqlite-wal"))
        try write("current-orphan-wal", to: canonical.appendingPathComponent("history.sqlite-wal"))

        XCTAssertThrowsError(try ApplicationSupportMigrator().migrate(in: root))
        XCTAssertEqual(try text(at: legacy.appendingPathComponent("history.sqlite")), "legacy-history")
        XCTAssertEqual(try text(at: legacy.appendingPathComponent("history.sqlite-wal")), "legacy-wal")
        XCTAssertEqual(
            try text(at: canonical.appendingPathComponent("history.sqlite-wal")),
            "current-orphan-wal"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.appendingPathComponent("history.sqlite").path))
    }

    func testPropagatesMigrationFailureWithoutRemovingLegacyFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("EnglishCompanion", isDirectory: true)
        let canonical = root.appendingPathComponent("SideLingo")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try write("legacy-history", to: legacy.appendingPathComponent("history.sqlite"))
        try write("not-a-directory", to: canonical)

        XCTAssertThrowsError(try ApplicationSupportMigrator().migrate(in: root)) {
            XCTAssertEqual(
                $0 as? ApplicationSupportMigrationError,
                .canonicalPathIsNotDirectory
            )
        }
        XCTAssertEqual(try text(at: legacy.appendingPathComponent("history.sqlite")), "legacy-history")
        XCTAssertEqual(try text(at: canonical), "not-a-directory")
    }

    private func write(_ value: String, to url: URL) throws {
        try Data(value.utf8).write(to: url)
    }

    private func text(at url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }
}

private enum InjectedBackupError: Error {
    case failed
}
