import Foundation
import XCTest
@testable import SideLingoCore

final class ProviderSettingsTests: XCTestCase {
    func testFirstSliceAllowsOnlyTheFixedDeepSeekPreset() {
        XCTAssertEqual(SupportedProvider.allCases, [.deepSeek])
        XCTAssertEqual(
            ProviderPreset.baseURL(for: .deepSeek),
            URL(string: "https://api.deepseek.com")
        )
        XCTAssertEqual(ProviderPreset.defaultModel(for: .deepSeek), "deepseek-v4-flash")
    }

    func testBlankKeyWithoutExistingSettingsIsRejectedBeforeSaving() {
        let store = ProviderSettingsStoreSpy(settings: nil)
        let service = ProviderSettingsService(store: store)

        XCTAssertThrowsError(
            try service.save(provider: .deepSeek, model: "deepseek-chat", apiKey: "   ")
        ) { error in
            XCTAssertEqual(error as? ProviderSettingsError, .apiKeyRequired)
        }
        XCTAssertEqual(store.savedValues, [])
    }

    func testBlankKeyPreservesExistingKeyWhileUpdatingTheCompleteRow() throws {
        let store = ProviderSettingsStoreSpy(
            settings: ProviderSettings(
                provider: .deepSeek,
                model: "old-model",
                apiKey: "dummy-existing-key"
            )
        )
        let service = ProviderSettingsService(store: store)

        try service.save(provider: .deepSeek, model: "new-model", apiKey: "  \n")

        XCTAssertEqual(
            store.savedValues,
            [
                ProviderSettings(
                    provider: .deepSeek,
                    model: "new-model",
                    apiKey: "dummy-existing-key"
                )
            ]
        )
    }

    func testNonblankKeyUpdatesProviderModelAndKeyTogether() throws {
        let store = ProviderSettingsStoreSpy(
            settings: ProviderSettings(
                provider: .deepSeek,
                model: "old-model",
                apiKey: "dummy-old-key"
            )
        )
        let service = ProviderSettingsService(store: store)

        try service.save(provider: .deepSeek, model: "new-model", apiKey: "  dummy-new-key  ")

        XCTAssertEqual(
            store.savedValues.last,
            ProviderSettings(
                provider: .deepSeek,
                model: "new-model",
                apiKey: "dummy-new-key"
            )
        )
    }
}

final class ProviderSettingsStoreSpy: @unchecked Sendable, ProviderSettingsStore {
    var settings: ProviderSettings?
    var loadError: Error?
    var saveError: Error?
    private(set) var loadCallCount = 0
    private(set) var savedValues: [ProviderSettings] = []

    init(settings: ProviderSettings? = nil) {
        self.settings = settings
    }

    func load() throws -> ProviderSettings? {
        loadCallCount += 1
        if let loadError { throw loadError }
        return settings
    }

    func save(_ settings: ProviderSettings) throws {
        if let saveError { throw saveError }
        savedValues.append(settings)
        self.settings = settings
    }
}
