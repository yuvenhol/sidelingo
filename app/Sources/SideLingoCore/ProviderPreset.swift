import Foundation

public enum SupportedProvider: String, CaseIterable, Codable, Sendable {
    case deepSeek = "deepseek"
}

public enum ProviderPreset {
    public static func baseURL(for provider: SupportedProvider) -> URL {
        switch provider {
        case .deepSeek:
            URL(string: "https://api.deepseek.com")!
        }
    }

    public static func defaultModel(for provider: SupportedProvider) -> String {
        switch provider {
        case .deepSeek:
            // Stable alias documented at https://api-docs.deepseek.com/
            "deepseek-v4-flash"
        }
    }
}

public enum ProviderSettingsError: Error, Equatable {
    case apiKeyRequired
}

public struct ProviderSettingsService: Sendable {
    private let store: any ProviderSettingsStore

    public init(store: any ProviderSettingsStore) {
        self.store = store
    }

    public func load() throws -> ProviderSettings? {
        try store.load()
    }

    public func save(
        provider: SupportedProvider,
        model: String,
        apiKey: String
    ) throws {
        let submittedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyToStore: String
        if submittedKey.isEmpty {
            guard let existing = try store.load(),
                  existing.provider == provider,
                  !existing.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderSettingsError.apiKeyRequired
            }
            keyToStore = existing.apiKey
        } else {
            keyToStore = submittedKey
        }

        try store.save(
            ProviderSettings(provider: provider, model: model, apiKey: keyToStore)
        )
    }
}
