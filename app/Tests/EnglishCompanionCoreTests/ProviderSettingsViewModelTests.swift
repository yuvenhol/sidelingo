import XCTest
@testable import EnglishCompanionCore

@MainActor
final class ProviderSettingsViewModelTests: XCTestCase {
    func testNewSettingsDefaultToLatestDeepSeekFlashAlias() {
        let settings = SettingsRepositorySpy()
        let credentials = FailingCredentialRepository()
        let viewModel = ProviderSettingsViewModel(
            settingsRepository: settings,
            settingsService: ProviderSettingsService(
                settingsRepository: settings,
                credentialRepository: credentials
            )
        )

        XCTAssertEqual(viewModel.model, "deepseek-v4-flash")
    }

    func testDismissClearsTransientAPIKeyAndStatus() {
        let settings = SettingsRepositorySpy()
        let credentials = FailingCredentialRepository()
        let viewModel = ProviderSettingsViewModel(
            settingsRepository: settings,
            settingsService: ProviderSettingsService(
                settingsRepository: settings,
                credentialRepository: credentials
            )
        )
        viewModel.apiKey = "transient-test-value"
        viewModel.statusMessage = "temporary status"

        viewModel.dismiss()

        XCTAssertEqual(viewModel.apiKey, "")
        XCTAssertNil(viewModel.statusMessage)
    }

    func testFailedSaveClearsTransientAPIKeyAndDoesNotSaveSettings() {
        let settings = SettingsRepositorySpy()
        let credentials = FailingCredentialRepository()
        let viewModel = ProviderSettingsViewModel(
            settingsRepository: settings,
            settingsService: ProviderSettingsService(
                settingsRepository: settings,
                credentialRepository: credentials
            )
        )
        viewModel.model = "deepseek-chat"
        viewModel.apiKey = "transient-test-value"

        viewModel.save()

        XCTAssertEqual(viewModel.apiKey, "")
        XCTAssertEqual(viewModel.statusMessage, "Could not save the API key.")
        XCTAssertNil(settings.load())
    }
}

private enum TestCredentialError: Error {
    case unavailable
}

private final class SettingsRepositorySpy: @unchecked Sendable, ProviderSettingsRepository {
    private var configuration: ProviderConfiguration?

    func load() -> ProviderConfiguration? { configuration }
    func save(_ configuration: ProviderConfiguration) { self.configuration = configuration }
}

private final class FailingCredentialRepository: @unchecked Sendable, ProviderCredentialRepository {
    func credential(for provider: SupportedProvider) throws -> String? { nil }

    func setCredential(_ credential: String, for provider: SupportedProvider) throws {
        throw TestCredentialError.unavailable
    }
}
