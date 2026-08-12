import Combine
import Foundation

public protocol HistoryRecording: Sendable {
    func append(_ record: HistoryRecord) throws
}

extension SQLiteHistoryStore: HistoryRecording {}

public enum QuickPanelProcessingState: Equatable, Sendable {
    case idle
    case loading
    case success(CompanionOutput)
    case error(String)
}

@MainActor
public final class QuickPanelProcessingSession: ObservableObject {
    @Published public private(set) var state: QuickPanelProcessingState = .idle

    public var isInputEditable: Bool {
        state != .loading
    }

    private let processor: any ProviderProcessing
    private let historyRecorder: (any HistoryRecording)?
    private var task: Task<Void, Never>?
    private var requestID = 0

    public init(
        processor: any ProviderProcessing,
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
        state = .loading

        task = Task { [weak self] in
            do {
                let output = try await processor.process(mode: mode, text: text)
                guard let self, self.requestID == submittedRequestID else { return }
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
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        let description = String(describing: error)
        return description.isEmpty ? "Processing failed." : description
    }
}
