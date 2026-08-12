import KeychainAccess
import XCTest
@testable import EnglishCompanionCore

final class KeychainCredentialStoreTests: XCTestCase {
    func testAdapterUsesThisDeviceOnlyAccessibilityAndInjectedStore() throws {
        let backend = KeychainBackendFake(value: "saved-key")
        var receivedService: String?
        var usesThisDeviceOnlyAccessibility = false
        let store = KeychainCredentialStore(
            service: "dev.kris.english-companion",
            makeStore: { service, accessibility in
                receivedService = service
                if case .afterFirstUnlockThisDeviceOnly = accessibility {
                    usesThisDeviceOnlyAccessibility = true
                }
                return backend
            }
        )

        XCTAssertEqual(try store.credential(for: .deepSeek), "saved-key")
        try store.setCredential("replacement-key", for: .deepSeek)
        try store.deleteCredential(for: .deepSeek)

        XCTAssertEqual(receivedService, "dev.kris.english-companion")
        XCTAssertTrue(usesThisDeviceOnlyAccessibility)
        XCTAssertEqual(backend.readKeys, ["deepseek"])
        XCTAssertEqual(backend.writtenKeys, ["deepseek"])
        XCTAssertEqual(backend.removedKeys, ["deepseek"])
    }
}

private final class KeychainBackendFake: @unchecked Sendable, KeychainValueStoring {
    private var value: String?
    private(set) var readKeys: [String] = []
    private(set) var writtenKeys: [String] = []
    private(set) var removedKeys: [String] = []

    init(value: String?) {
        self.value = value
    }

    func set(_ value: String, key: String) throws {
        writtenKeys.append(key)
        self.value = value
    }

    func get(_ key: String) throws -> String? {
        readKeys.append(key)
        return value
    }

    func remove(_ key: String) throws {
        removedKeys.append(key)
        value = nil
    }
}
