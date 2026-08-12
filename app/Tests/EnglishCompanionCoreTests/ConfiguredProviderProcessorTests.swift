import XCTest
@testable import EnglishCompanionCore

final class ConfiguredProviderProcessorTests: XCTestCase {
    func testMissingSettingsReturnsConfigurationRequiredWithoutBuildingProvider() async {
        let settings = ProcessorSettingsRepository(configuration: nil)
        let credentials = ProcessorCredentialRepository(value: "unused")
        let factory = ProviderFactorySpy()
        let processor = ConfiguredProviderProcessor(
            settingsRepository: settings,
            credentialRepository: credentials,
            makeProcessor: factory.make
        )

        await assertConfigurationRequired(processor)
        XCTAssertEqual(factory.callCount, 0)
    }

    func testMissingOrBlankKeyReturnsConfigurationRequired() async {
        let configuration = ProviderConfiguration(provider: .deepSeek, model: "deepseek-chat")
        for key in [nil, "", "   "] {
            let factory = ProviderFactorySpy()
            let processor = ConfiguredProviderProcessor(
                settingsRepository: ProcessorSettingsRepository(configuration: configuration),
                credentialRepository: ProcessorCredentialRepository(value: key),
                makeProcessor: factory.make
            )

            await assertConfigurationRequired(processor)
            XCTAssertEqual(factory.callCount, 0)
        }
    }

    func testConfiguredRequestBuildsTheSupportedProvider() async throws {
        let configuration = ProviderConfiguration(provider: .deepSeek, model: "selected-model")
        let factory = ProviderFactorySpy()
        let processor = ConfiguredProviderProcessor(
            settingsRepository: ProcessorSettingsRepository(configuration: configuration),
            credentialRepository: ProcessorCredentialRepository(value: "stored-key"),
            makeProcessor: factory.make
        )

        let output = try await processor.process(mode: .translate, text: "Input")

        XCTAssertEqual(output.primary, "processed")
        XCTAssertEqual(factory.providers, [.deepSeek])
        XCTAssertEqual(factory.models, ["selected-model"])
        XCTAssertEqual(factory.callCount, 1)
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

private final class ProcessorSettingsRepository: @unchecked Sendable, ProviderSettingsRepository {
    let configuration: ProviderConfiguration?
    init(configuration: ProviderConfiguration?) { self.configuration = configuration }
    func load() -> ProviderConfiguration? { configuration }
    func save(_ configuration: ProviderConfiguration) {}
}

private final class ProcessorCredentialRepository: @unchecked Sendable, ProviderCredentialRepository {
    let value: String?
    init(value: String?) { self.value = value }
    func credential(for provider: SupportedProvider) throws -> String? { value }
    func setCredential(_ credential: String, for provider: SupportedProvider) throws {}
}

private final class ProviderFactorySpy: @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var providers: [SupportedProvider] = []
    private(set) var models: [String] = []

    func make(provider: SupportedProvider, apiKey: String, model: String) -> any ProviderProcessing {
        callCount += 1
        providers.append(provider)
        models.append(model)
        return SuccessfulProcessor()
    }
}

private struct SuccessfulProcessor: ProviderProcessing {
    func process(mode: CompanionMode, text: String) async throws -> CompanionOutput {
        CompanionOutput(primary: "processed", secondaryTitle: "title", secondary: "secondary")
    }
}
