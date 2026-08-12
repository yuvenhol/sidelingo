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
}

public struct ProviderConfiguration: Codable, Equatable, Sendable {
    public let provider: SupportedProvider
    public let model: String

    public init(provider: SupportedProvider, model: String) {
        self.provider = provider
        self.model = model
    }
}

public protocol ProviderSettingsRepository: Sendable {
    func load() -> ProviderConfiguration?
    func save(_ configuration: ProviderConfiguration)
}

public protocol ProviderCredentialRepository: Sendable {
    func credential(for provider: SupportedProvider) throws -> String?
    func setCredential(_ credential: String, for provider: SupportedProvider) throws
}

public final class UserDefaultsProviderSettingsRepository: ProviderSettingsRepository, @unchecked Sendable {
    private let defaults: UserDefaults
    private let providerKey: String
    private let modelKey: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "provider") {
        self.defaults = defaults
        providerKey = "\(keyPrefix).provider"
        modelKey = "\(keyPrefix).model"
    }

    public func load() -> ProviderConfiguration? {
        guard let rawProvider = defaults.string(forKey: providerKey),
              let provider = SupportedProvider(rawValue: rawProvider),
              let model = defaults.string(forKey: modelKey) else {
            return nil
        }
        return ProviderConfiguration(provider: provider, model: model)
    }

    public func save(_ configuration: ProviderConfiguration) {
        defaults.set(configuration.provider.rawValue, forKey: providerKey)
        defaults.set(configuration.model, forKey: modelKey)
    }
}

public enum ProviderSettingsError: Error, Equatable {
    case apiKeyRequired
}

public struct ProviderSettingsService: Sendable {
    private let settingsRepository: any ProviderSettingsRepository
    private let credentialRepository: any ProviderCredentialRepository

    public init(
        settingsRepository: any ProviderSettingsRepository,
        credentialRepository: any ProviderCredentialRepository
    ) {
        self.settingsRepository = settingsRepository
        self.credentialRepository = credentialRepository
    }

    public func save(_ configuration: ProviderConfiguration, apiKey: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            guard let existing = try credentialRepository.credential(for: configuration.provider),
                  !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderSettingsError.apiKeyRequired
            }
        } else {
            try credentialRepository.setCredential(trimmedKey, for: configuration.provider)
        }
        settingsRepository.save(configuration)
    }
}
