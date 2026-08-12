import Foundation
import XCTest
@testable import EnglishCompanionCore

final class ProviderConfigurationTests: XCTestCase {
    func testFirstSliceAllowsOnlyTheFixedDeepSeekPreset() throws {
        XCTAssertEqual(SupportedProvider.allCases, [.deepSeek])
        XCTAssertEqual(
            ProviderPreset.baseURL(for: .deepSeek),
            URL(string: "https://api.deepseek.com")
        )

        let configuration = ProviderConfiguration(provider: .deepSeek, model: "deepseek-chat")
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any]
        )
        XCTAssertEqual(Set(encoded.keys), ["provider", "model"])
        XCTAssertNil(encoded["baseURL"])
    }

    func testUserDefaultsRepositoryPersistsOnlyProviderAndModel() throws {
        let suiteName = "ProviderConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsProviderSettingsRepository(
            defaults: defaults,
            keyPrefix: "provider-test"
        )
        let configuration = ProviderConfiguration(provider: .deepSeek, model: "custom-model")

        repository.save(configuration)

        XCTAssertEqual(repository.load(), configuration)
        XCTAssertEqual(defaults.string(forKey: "provider-test.provider"), "deepseek")
        XCTAssertEqual(defaults.string(forKey: "provider-test.model"), "custom-model")
        XCTAssertNil(defaults.object(forKey: "provider-test.apiKey"))
        XCTAssertNil(defaults.object(forKey: "provider-test.baseURL"))
    }

    func testBlankKeyWithoutExistingCredentialIsRejectedBeforeSavingSettings() {
        let settings = InMemorySettingsRepository()
        let credentials = CredentialRepositorySpy(existing: nil)
        let service = ProviderSettingsService(
            settingsRepository: settings,
            credentialRepository: credentials
        )

        XCTAssertThrowsError(
            try service.save(
                ProviderConfiguration(provider: .deepSeek, model: "deepseek-chat"),
                apiKey: "   "
            )
        ) { error in
            XCTAssertEqual(error as? ProviderSettingsError, .apiKeyRequired)
        }
        XCTAssertNil(settings.load())
        XCTAssertEqual(credentials.setCallCount, 0)
    }

    func testBlankKeyPreservesExistingCredential() throws {
        let settings = InMemorySettingsRepository()
        let credentials = CredentialRepositorySpy(existing: "existing-key")
        let service = ProviderSettingsService(
            settingsRepository: settings,
            credentialRepository: credentials
        )

        try service.save(
            ProviderConfiguration(provider: .deepSeek, model: "deepseek-chat"),
            apiKey: "   "
        )

        XCTAssertEqual(settings.load()?.model, "deepseek-chat")
        XCTAssertEqual(credentials.setCallCount, 0)
        XCTAssertEqual(try credentials.credential(for: .deepSeek), "existing-key")
    }
}

private final class InMemorySettingsRepository: @unchecked Sendable, ProviderSettingsRepository {
    private var configuration: ProviderConfiguration?

    func load() -> ProviderConfiguration? { configuration }
    func save(_ configuration: ProviderConfiguration) { self.configuration = configuration }
}

private final class CredentialRepositorySpy: @unchecked Sendable, ProviderCredentialRepository {
    private var value: String?
    private(set) var setCallCount = 0

    init(existing: String? = nil) {
        value = existing
    }

    func credential(for provider: SupportedProvider) throws -> String? { value }

    func setCredential(_ credential: String, for provider: SupportedProvider) throws {
        setCallCount += 1
        value = credential
    }
}
