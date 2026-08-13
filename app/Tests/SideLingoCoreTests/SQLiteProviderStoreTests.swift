import Foundation
import XCTest
@testable import SideLingoCore

final class SQLiteProviderStoreTests: XCTestCase {
    func testPersistsOneCompleteProviderSettingsValueAcrossReopen() throws {
        let fixture = try TemporaryProviderDatabase()
        defer { fixture.remove() }
        let expected = ProviderSettings(
            provider: .deepSeek,
            model: "test-model-v1",
            apiKey: "dummy-api-key-alpha"
        )

        do {
            let store = try SQLiteProviderStore(path: fixture.path)
            XCTAssertNil(try store.load())
            try store.save(expected)
            XCTAssertEqual(try store.load(), expected)
        }

        let reopened = try SQLiteProviderStore(path: fixture.path)
        XCTAssertEqual(try reopened.load(), expected)
    }

    func testAPIKeyIsIntentionallyPlaintextInDatabaseFile() throws {
        let fixture = try TemporaryProviderDatabase()
        defer { fixture.remove() }
        let plaintextKey = "dummy-plaintext-proof-4E357A55-2D23"

        do {
            let store = try SQLiteProviderStore(path: fixture.path)
            try store.save(
                ProviderSettings(
                    provider: .deepSeek,
                    model: "test-model",
                    apiKey: plaintextKey
                )
            )
        }

        let bytes = try Data(contentsOf: URL(fileURLWithPath: fixture.path))
        XCTAssertNotNil(bytes.range(of: Data(plaintextKey.utf8)))
    }

    func testUpsertUpdatesModelAndKeyAsOneCompleteValue() throws {
        let fixture = try TemporaryProviderDatabase()
        defer { fixture.remove() }
        let store = try SQLiteProviderStore(path: fixture.path)
        try store.save(
            ProviderSettings(provider: .deepSeek, model: "old-model", apiKey: "dummy-old-key")
        )

        let replacement = ProviderSettings(
            provider: .deepSeek,
            model: "new-model",
            apiKey: "dummy-new-key"
        )
        try store.save(replacement)

        XCTAssertEqual(try store.load(), replacement)
    }

    func testDatabaseFileUsesOwnerReadWritePermissions() throws {
        let fixture = try TemporaryProviderDatabase()
        defer { fixture.remove() }
        _ = try SQLiteProviderStore(path: fixture.path)

        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testSaveErrorNeverContainsSubmittedAPIKey() throws {
        let fixture = try TemporaryProviderDatabase()
        defer { fixture.remove() }
        let secret = "dummy-secret-must-not-escape-9B5A"
        let store = try SQLiteProviderStore(path: fixture.path, saveStep: { _ in .failure })

        XCTAssertThrowsError(
            try store.save(
                ProviderSettings(provider: .deepSeek, model: "test-model", apiKey: secret)
            )
        ) { error in
            XCTAssertFalse(String(describing: error).contains(secret))
            XCTAssertFalse((error as? LocalizedError)?.errorDescription?.contains(secret) == true)
        }
    }
}

private struct TemporaryProviderDatabase {
    let directory: URL
    let path: String

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidelingo-provider-\(UUID().uuidString)", isDirectory: true)
        path = directory.appendingPathComponent("provider.sqlite").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
