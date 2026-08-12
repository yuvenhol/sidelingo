import Foundation
import SwiftOpenAI

// SwiftOpenAI 4.5.1 predates Swift 6 Sendable annotations for this value-type request.
extension ChatCompletionParameters: @retroactive @unchecked Sendable {}
extension ChatCompletionChunkObject: @retroactive @unchecked Sendable {}

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

public protocol ProviderStreaming: Sendable {
    func stream(
        mode: CompanionMode,
        text: String
    ) async throws -> AsyncThrowingStream<CompanionOutputPartial, Error>
}

public protocol ChatCompletionStreaming: Sendable {
    func streamedChat(
        parameters: ChatCompletionParameters
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error>
}

public final class SwiftOpenAIChatCompletionStreamingService: ChatCompletionStreaming, @unchecked Sendable {
    private let service: any OpenAIService

    public init(service: any OpenAIService) {
        self.service = service
    }

    public func streamedChat(
        parameters: ChatCompletionParameters
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        try await service.startStreamedChat(parameters: parameters)
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

public struct DeepSeekProviderProcessor: ProviderProcessing, ProviderStreaming {
    private let model: String
    private let streamingService: any ChatCompletionStreaming

    public init(model: String, streamingService: any ChatCompletionStreaming) {
        self.model = model
        self.streamingService = streamingService
    }

    public init(apiKey: String, model: String) {
        let session = ProviderURLSessionFactory.makeRedirectRejectingSession()
        let baseHTTPClient = URLSessionHTTPClientAdapter(urlSession: session)
        let httpClient = CancellationSafeHTTPClient(
            base: baseHTTPClient,
            cancelTransport: { session.invalidateAndCancel() }
        )
        let service = OpenAIServiceFactory.service(
            apiKey: apiKey,
            overrideBaseURL: ProviderPreset.baseURL(for: .deepSeek).absoluteString,
            httpClient: httpClient,
            debugEnabled: false
        )
        self.init(
            model: model,
            streamingService: SwiftOpenAIChatCompletionStreamingService(service: service)
        )
    }

    public func process(mode: CompanionMode, text: String) async throws -> CompanionOutput {
        try await completedOutput(mode: mode, text: text)
    }

    public func stream(
        mode: CompanionMode,
        text: String
    ) async throws -> AsyncThrowingStream<CompanionOutputPartial, Error> {
        let source = try await streamingService.streamedChat(
            parameters: Self.parameters(model: model, mode: mode, text: text)
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = CompanionJSONLParser()
                var lastUpdate: CompanionOutputPartial?
                do {
                    for try await chunk in source {
                        try Task.checkCancellation()
                        guard let content = chunk.choices?.first?.delta?.content else { continue }
                        for update in try parser.append(content) {
                            lastUpdate = update
                            continuation.yield(update)
                        }
                    }
                    let output = try parser.finish()
                    let complete = CompanionOutputPartial(
                        primary: output.primary,
                        secondaryTitle: output.secondaryTitle,
                        secondary: output.secondary
                    )
                    if lastUpdate != complete {
                        continuation.yield(complete)
                    }
                    continuation.finish()
                } catch is CompanionJSONLParsingError {
                    continuation.finish(throwing: ProviderProcessingError.invalidResponse)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func parameters(
        model: String,
        mode: CompanionMode,
        text: String
    ) -> ChatCompletionParameters {
        ChatCompletionParameters(
            messages: [
                .init(role: .system, content: .text(Self.systemPrompt(for: mode))),
                .init(role: .user, content: .text(text)),
            ],
            model: Model.custom(model)
        )
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
        Return exactly three JSONL records in this exact order, one record per line:
        {"field":"primary","value":"..."}
        {"field":"secondaryTitle","value":"..."}
        {"field":"secondary","value":"..."}
        Replace each ... with the requested string value. No markdown. Do not add commentary, blank records, or other fields.
        """
    }
}

public final class ConfiguredProviderProcessor: ProviderProcessing, ProviderStreaming, @unchecked Sendable {
    public typealias ProcessorFactory = (
        _ provider: SupportedProvider,
        _ apiKey: String,
        _ model: String
    ) -> any ProviderStreaming

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
        try await completedOutput(mode: mode, text: text)
    }

    public func stream(
        mode: CompanionMode,
        text: String
    ) async throws -> AsyncThrowingStream<CompanionOutputPartial, Error> {
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
        ).stream(mode: mode, text: text)
    }
}

private extension ProviderStreaming {
    func completedOutput(mode: CompanionMode, text: String) async throws -> CompanionOutput {
        let updates = try await stream(mode: mode, text: text)
        var finalPartial: CompanionOutputPartial?
        for try await update in updates {
            finalPartial = update
        }
        guard let primary = finalPartial?.primary,
              let secondaryTitle = finalPartial?.secondaryTitle,
              let secondary = finalPartial?.secondary else {
            throw ProviderProcessingError.invalidResponse
        }
        return CompanionOutput(
            primary: primary,
            secondaryTitle: secondaryTitle,
            secondary: secondary
        )
    }
}
