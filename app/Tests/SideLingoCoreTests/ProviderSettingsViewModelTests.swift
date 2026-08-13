import XCTest
@testable import SideLingoCore

@MainActor
final class ProviderSettingsViewModelTests: XCTestCase {
    func testNewSettingsDefaultToLatestDeepSeekFlashAlias() {
        let store = ProviderSettingsStoreSpy()
        let viewModel = ProviderSettingsViewModel(
            settingsService: ProviderSettingsService(store: store)
        )

        XCTAssertEqual(viewModel.model, "deepseek-v4-flash")
    }

    func testExistingSettingsLoadStoredModelWithoutLoadingKeyIntoSecureField() {
        let store = ProviderSettingsStoreSpy(
            settings: ProviderSettings(
                provider: .deepSeek,
                model: "stored-model",
                apiKey: "dummy-stored-key"
            )
        )

        let viewModel = ProviderSettingsViewModel(
            settingsService: ProviderSettingsService(store: store)
        )

        XCTAssertEqual(viewModel.model, "stored-model")
        XCTAssertEqual(viewModel.apiKey, "")
    }

    func testDismissClearsTransientAPIKeyAndStatus() {
        let store = ProviderSettingsStoreSpy()
        let viewModel = ProviderSettingsViewModel(
            settingsService: ProviderSettingsService(store: store)
        )
        viewModel.apiKey = "transient-test-value"
        viewModel.statusMessage = "temporary status"

        viewModel.dismiss()

        XCTAssertEqual(viewModel.apiKey, "")
        XCTAssertNil(viewModel.statusMessage)
    }

    func testFailedSaveClearsTransientAPIKeyAndDoesNotSaveSettings() {
        let store = ProviderSettingsStoreSpy()
        store.saveError = TestProviderSettingsError.unavailable
        let viewModel = ProviderSettingsViewModel(
            settingsService: ProviderSettingsService(store: store)
        )
        viewModel.model = "deepseek-chat"
        viewModel.apiKey = "transient-test-value"

        viewModel.save()

        XCTAssertEqual(viewModel.apiKey, "")
        XCTAssertEqual(viewModel.statusMessage, "Could not save provider settings.")
        XCTAssertEqual(store.savedValues, [])
    }

    func testSuccessfulSaveClearsTransientAPIKey() {
        let store = ProviderSettingsStoreSpy()
        let viewModel = ProviderSettingsViewModel(
            settingsService: ProviderSettingsService(store: store)
        )
        viewModel.model = "deepseek-chat"
        viewModel.apiKey = "dummy-new-key"

        viewModel.save()

        XCTAssertEqual(viewModel.apiKey, "")
        XCTAssertEqual(viewModel.statusMessage, "DeepSeek settings saved.")
        XCTAssertEqual(store.savedValues.last?.apiKey, "dummy-new-key")
    }

    func testModelValidationFailureClearsTransientAPIKey() {
        let store = ProviderSettingsStoreSpy()
        let viewModel = ProviderSettingsViewModel(
            settingsService: ProviderSettingsService(store: store)
        )
        viewModel.model = "  "
        viewModel.apiKey = "dummy-transient-key"

        viewModel.save()

        XCTAssertEqual(viewModel.apiKey, "")
        XCTAssertEqual(viewModel.statusMessage, "Model is required.")
        XCTAssertEqual(store.savedValues, [])
    }

    func testPrepareForPresentationClearsTransientAPIKeyAndStatus() {
        let viewModel = ProviderSettingsViewModel(
            settingsService: ProviderSettingsService(store: ProviderSettingsStoreSpy())
        )
        viewModel.apiKey = "dummy-transient-key"
        viewModel.statusMessage = "temporary"

        viewModel.prepareForPresentation()

        XCTAssertEqual(viewModel.apiKey, "")
        XCTAssertNil(viewModel.statusMessage)
    }
}

private enum TestProviderSettingsError: Error {
    case unavailable
}
