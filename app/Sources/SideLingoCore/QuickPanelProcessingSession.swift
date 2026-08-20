import Combine
import Foundation

public protocol HistoryRecording: Sendable {
    func append(_ record: HistoryRecord) throws
}

extension SQLiteHistoryStore: HistoryRecording {}

public enum QuickPanelProcessingState: Equatable, Sendable {
    case idle
    case streaming(CompanionOutputPartial)
    case success(CompanionOutput)
    case dictionary(DictionaryLookup)
    case error(String)
}

@MainActor
public final class QuickPanelProcessingSession: ObservableObject {
    @Published public private(set) var state: QuickPanelProcessingState = .idle

    public var isInputEditable: Bool {
        if case .streaming = state { return false }
        return true
    }

    public var isCopyEnabled: Bool {
        switch state {
        case let .success(output):
            !output.primary.isEmpty
        case let .dictionary(lookup):
            !lookup.entry.translation.isEmpty
        default:
            false
        }
    }

    private let processor: any ProviderStreaming
    private let dictionary: (any DictionaryLookupProviding)?
    private let historyRecorder: (any HistoryRecording)?
    private var task: Task<Void, Never>?
    private var requestID = 0

    public init(
        processor: any ProviderStreaming,
        dictionary: (any DictionaryLookupProviding)? = nil,
        historyRecorder: (any HistoryRecording)? = nil
    ) {
        self.processor = processor
        self.dictionary = dictionary
        self.historyRecorder = historyRecorder
    }

    public func submit(mode: CompanionMode, text: String) {
        task?.cancel()
        requestID += 1
        let submittedRequestID = requestID
        let processor = processor
        let dictionary = dictionary
        let historyRecorder = historyRecorder
        state = .streaming(CompanionOutputPartial())

        task = Task { [weak self] in
            if mode == .translate, let dictionary {
                let lookup = try? await Task.detached(priority: .userInitiated) {
                    try dictionary.lookup(text)
                }.value
                guard let self, self.requestID == submittedRequestID else { return }
                if let lookup,
                   !lookup.entry.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.state = .dictionary(lookup)
                    let record = HistoryRecord(
                        mode: mode,
                        source: text,
                        result: lookup.entry.translation,
                        createdAt: Date().timeIntervalSince1970,
                        kind: .dictionary,
                        dictionaryLemma: lookup.lemma
                    )
                    try? historyRecorder?.append(record)
                    self.task = nil
                    return
                }
            }
            do {
                let stream = try await processor.stream(mode: mode, text: text)
                var finalPartial: CompanionOutputPartial?
                for try await partial in stream {
                    guard let self, self.requestID == submittedRequestID else { return }
                    guard !CompanionFramedProtocol.containsMarker(in: partial) else {
                        throw ProviderProcessingError.invalidResponse
                    }
                    finalPartial = partial
                    self.state = .streaming(partial)
                }
                guard let self, self.requestID == submittedRequestID else { return }
                guard let primary = finalPartial?.primary,
                      let secondaryTitle = finalPartial?.secondaryTitle,
                      let secondary = finalPartial?.secondary else {
                    throw ProviderProcessingError.invalidResponse
                }
                let output = CompanionOutput(
                    primary: primary,
                    secondaryTitle: secondaryTitle,
                    secondary: secondary
                )
                self.state = .success(output)
                let record = HistoryRecord(
                    mode: mode,
                    source: text,
                    result: output.primary,
                    createdAt: Date().timeIntervalSince1970
                )
                try? self.historyRecorder?.append(record)
                self.task = nil
            } catch {
                guard let self, self.requestID == submittedRequestID else { return }
                self.state = .error(Self.message(for: error))
                self.task = nil
            }
        }
    }

    public func cancel() {
        requestID += 1
        task?.cancel()
        task = nil
        state = .idle
    }

    private static func message(for error: Error) -> String {
        if let providerError = error as? ProviderProcessingError,
           let description = providerError.errorDescription,
           !description.isEmpty {
            return description
        }
        return "Processing failed."
    }
}
