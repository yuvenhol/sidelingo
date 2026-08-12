import Foundation
import SwiftOpenAI

// SwiftOpenAI 4.5.1 predates Swift 6 Sendable annotations for this value-type request.
extension ChatCompletionParameters: @retroactive @unchecked Sendable {}

public enum ProviderProcessingError: Error, Equatable {
    case configurationRequired
    case invalidResponse
}

extension ProviderProcessingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .configurationRequired:
            "Configure the DeepSeek model and API key in Settings."
        case .invalidResponse:
            "DeepSeek returned an invalid response."
        }
    }
}

public protocol ProviderProcessing: Sendable {
    func process(mode: CompanionMode, text: String) async throws -> CompanionOutput
}

public protocol ChatCompletionSubmitting: Sendable {
    func assistantContent(parameters: ChatCompletionParameters) async throws -> String?
}

public final class SwiftOpenAIChatCompletionService: ChatCompletionSubmitting, @unchecked Sendable {
    private let service: any OpenAIService

    public init(service: any OpenAIService) {
        self.service = service
    }

    public func assistantContent(parameters: ChatCompletionParameters) async throws -> String? {
        let response = try await service.startChat(parameters: parameters)
        return response.choices?.first?.message?.content
    }
}

public final class RedirectRejectingURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum ProviderURLSessionFactory {
    public static func makeRedirectRejectingSession() -> URLSession {
        URLSession(
            configuration: .ephemeral,
            delegate: RedirectRejectingURLSessionDelegate(),
            delegateQueue: nil
        )
    }
}

public struct DeepSeekProviderProcessor: ProviderProcessing {
    private let model: String
    private let service: any ChatCompletionSubmitting

    public init(model: String, service: any ChatCompletionSubmitting) {
        self.model = model
        self.service = service
    }

    public init(apiKey: String, model: String) {
        let session = ProviderURLSessionFactory.makeRedirectRejectingSession()
        let httpClient = URLSessionHTTPClientAdapter(urlSession: session)
        let service = OpenAIServiceFactory.service(
            apiKey: apiKey,
            overrideBaseURL: ProviderPreset.baseURL(for: .deepSeek).absoluteString,
            httpClient: httpClient,
            debugEnabled: false
        )
        self.init(model: model, service: SwiftOpenAIChatCompletionService(service: service))
    }

    public func process(mode: CompanionMode, text: String) async throws -> CompanionOutput {
        let parameters = ChatCompletionParameters(
            messages: [
                .init(role: .system, content: .text(Self.systemPrompt(for: mode))),
                .init(role: .user, content: .text(text)),
            ],
            model: Model.custom(model),
            responseFormat: ResponseFormat.jsonObject
        )
        guard let content = try await service.assistantContent(parameters: parameters) else {
            throw ProviderProcessingError.invalidResponse
        }
        do {
            return try CompanionOutputDecoder.decode(content)
        } catch {
            throw ProviderProcessingError.invalidResponse
        }
    }

    private static func systemPrompt(for mode: CompanionMode) -> String {
        let task = switch mode {
        case .translate:
            """
            Translate according to the input language. For Chinese input, put concise natural ready-to-send English in primary, \
            a Chinese meaning-check label in secondaryTitle, and a faithful Chinese back-translation in secondary. \
            For English input, put a natural Chinese translation in primary, a suggested English reply label in secondaryTitle, \
            and one concise suggested English reply in secondary. Preserve names, numbers, technical identifiers, facts, tone, \
            and commitment strength. Do not invent details.
            """
        case .improve:
            """
            Improve English, Chinese, or mixed-language input while preserving meaning. For English, return natural ready-to-send \
            English. For Chinese, improve the Chinese without translating it. For mixed-language input, produce coherent English \
            while preserving project names, commands, URLs, abbreviations, and other technical identifiers. Put the result in primary, \
            a concise changes label in secondaryTitle, and useful grammar, naturalness, and tone explanations in secondary.
            """
        }
        return """
        \(task)
        Return one JSON object with exactly these three string fields: primary, secondaryTitle, secondary.
        Do not add markdown, commentary, or any other fields.
        """
    }
}

public final class ConfiguredProviderProcessor: ProviderProcessing, @unchecked Sendable {
    public typealias ProcessorFactory = (
        _ provider: SupportedProvider,
        _ apiKey: String,
        _ model: String
    ) -> any ProviderProcessing

    private let settingsRepository: any ProviderSettingsRepository
    private let credentialRepository: any ProviderCredentialRepository
    private let makeProcessor: ProcessorFactory

    public init(
        settingsRepository: any ProviderSettingsRepository,
        credentialRepository: any ProviderCredentialRepository,
        makeProcessor: @escaping ProcessorFactory = { provider, apiKey, model in
            switch provider {
            case .deepSeek:
                DeepSeekProviderProcessor(apiKey: apiKey, model: model)
            }
        }
    ) {
        self.settingsRepository = settingsRepository
        self.credentialRepository = credentialRepository
        self.makeProcessor = makeProcessor
    }

    public func process(mode: CompanionMode, text: String) async throws -> CompanionOutput {
        guard let configuration = settingsRepository.load(),
              !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let apiKey = try credentialRepository.credential(for: configuration.provider),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderProcessingError.configurationRequired
        }
        return try await makeProcessor(
            configuration.provider,
            apiKey,
            configuration.model
        ).process(mode: mode, text: text)
    }
}
