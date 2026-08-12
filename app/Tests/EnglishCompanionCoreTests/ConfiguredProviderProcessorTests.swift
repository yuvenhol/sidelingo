import XCTest
@testable import EnglishCompanionCore

final class ConfiguredProviderProcessorTests: XCTestCase {
    func testMissingSettingsReturnsConfigurationRequiredWithoutBuildingProvider() async {
        let store = ProcessorSettingsStore(settings: nil)
        let factory = ProviderFactorySpy()
        let processor = ConfiguredProviderProcessor(
            settingsStore: store,
            makeProcessor: factory.make
        )

        await assertConfigurationRequired(processor)
        XCTAssertEqual(factory.callCount, 0)
    }

    func testMissingOrBlankKeyReturnsConfigurationRequired() async {
        for key in ["", "   "] {
            let factory = ProviderFactorySpy()
            let processor = ConfiguredProviderProcessor(
                settingsStore: ProcessorSettingsStore(
                    settings: ProviderSettings(
                        provider: .deepSeek,
                        model: "deepseek-chat",
                        apiKey: key
                    )
                ),
                makeProcessor: factory.make
            )

            await assertConfigurationRequired(processor)
            XCTAssertEqual(factory.callCount, 0)
        }
    }

    func testConfiguredRequestBuildsTheSupportedProvider() async throws {
        let store = ProcessorSettingsStore(
            settings: ProviderSettings(
                provider: .deepSeek,
                model: "selected-model",
                apiKey: "dummy-stored-key"
            )
        )
        let factory = ProviderFactorySpy()
        let processor = ConfiguredProviderProcessor(
            settingsStore: store,
            makeProcessor: factory.make
        )

        let output = try await processor.process(mode: .translate, text: "Input")

        XCTAssertEqual(output.primary, "processed")
        XCTAssertEqual(factory.providers, [.deepSeek])
        XCTAssertEqual(factory.models, ["selected-model"])
        XCTAssertEqual(factory.apiKeys, ["dummy-stored-key"])
        XCTAssertEqual(factory.callCount, 1)
        XCTAssertEqual(store.loadCallCount, 1)
    }

    private func assertConfigurationRequired(_ processor: ConfiguredProviderProcessor) async {
        do {
            _ = try await processor.process(mode: .translate, text: "Input")
            XCTFail("Expected configuration-required error")
        } catch {
            XCTAssertEqual(error as? ProviderProcessingError, .configurationRequired)
        }
    }
}

private final class ProcessorSettingsStore: @unchecked Sendable, ProviderSettingsStore {
    let settings: ProviderSettings?
    private(set) var loadCallCount = 0

    init(settings: ProviderSettings?) { self.settings = settings }

    func load() throws -> ProviderSettings? {
        loadCallCount += 1
        return settings
    }

    func save(_ settings: ProviderSettings) throws {}
}

private final class ProviderFactorySpy: @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var providers: [SupportedProvider] = []
    private(set) var models: [String] = []
    private(set) var apiKeys: [String] = []

    func make(provider: SupportedProvider, apiKey: String, model: String) -> any ProviderStreaming {
        callCount += 1
        providers.append(provider)
        models.append(model)
        apiKeys.append(apiKey)
        return SuccessfulProcessor()
    }
}

private struct SuccessfulProcessor: ProviderStreaming {
    func stream(
        mode: CompanionMode,
        text: String
    ) async throws -> AsyncThrowingStream<CompanionOutputPartial, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                CompanionOutputPartial(
                    primary: "processed",
                    secondaryTitle: "title",
                    secondary: "secondary"
                )
            )
            continuation.finish()
        }
    }
}
