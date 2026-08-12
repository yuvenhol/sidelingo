import Combine
import Foundation

@MainActor
public final class ProviderSettingsViewModel: ObservableObject {
    @Published public var model: String
    @Published public var apiKey = ""
    @Published public var statusMessage: String?

    private let settingsService: ProviderSettingsService

    public init(
        settingsRepository: any ProviderSettingsRepository,
        settingsService: ProviderSettingsService
    ) {
        model = settingsRepository.load()?.model ?? "deepseek-chat"
        self.settingsService = settingsService
    }

    public func prepareForPresentation() {
        dismiss()
    }

    public func dismiss() {
        apiKey = ""
        statusMessage = nil
    }

    public func save() {
        let submittedAPIKey = apiKey
        apiKey = ""

        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedModel.isEmpty else {
            statusMessage = "Model is required."
            return
        }
        do {
            try settingsService.save(
                ProviderConfiguration(provider: .deepSeek, model: selectedModel),
                apiKey: submittedAPIKey
            )
            model = selectedModel
            statusMessage = "DeepSeek settings saved."
        } catch ProviderSettingsError.apiKeyRequired {
            statusMessage = "Enter a DeepSeek API key before saving."
        } catch {
            statusMessage = "Could not save the API key."
        }
    }
}
