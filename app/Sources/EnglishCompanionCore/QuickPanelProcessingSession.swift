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
        guard case let .success(output) = state else { return false }
        return !output.primary.isEmpty
    }

    private let processor: any ProviderStreaming
    private let historyRecorder: (any HistoryRecording)?
    private var task: Task<Void, Never>?
    private var requestID = 0

    public init(
        processor: any ProviderStreaming,
        historyRecorder: (any HistoryRecording)? = nil
    ) {
        self.processor = processor
        self.historyRecorder = historyRecorder
    }

    public func submit(mode: CompanionMode, text: String) {
        task?.cancel()
        requestID += 1
        let submittedRequestID = requestID
        let processor = processor
        state = .streaming(CompanionOutputPartial())

        task = Task { [weak self] in
            do {
                let stream = try await processor.stream(mode: mode, text: text)
                var finalPartial: CompanionOutputPartial?
                for try await partial in stream {
                    guard let self, self.requestID == submittedRequestID else { return }
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
