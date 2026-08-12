import Foundation
import XCTest
@testable import EnglishCompanionCore

final class KeychainCredentialStoreTests: XCTestCase {
    func testRoundTripsAndDeletesTemporarySecret() throws {
        let service = "dev.kris.english-companion-spike.tests.\(UUID().uuidString)"
        let store = KeychainCredentialStore(service: service)
        let account = "openai"
        defer { try? store.delete(account: account) }

        try store.set("temporary-secret", account: account)
        XCTAssertEqual(try store.get(account: account), "temporary-secret")

        try store.delete(account: account)
        XCTAssertNil(try store.get(account: account))
    }
}
