import AppKit
import Foundation

public protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    func string() -> String?
}

public enum PasteboardCaptureOutcome: Equatable, Sendable {
    case captured(text: String)
    case unchanged
    case conflict
    case unsupported

    public var diagnosticCategory: String {
        switch self {
        case .captured:
            "captured"
        case .unchanged:
            "unchanged"
        case .conflict:
            "conflict"
        case .unsupported:
            "unsupported"
        }
    }

    public var clipboardFallback: ClipboardFallback {
        switch self {
        case let .captured(text): .captured(text)
        case .unchanged: .unchanged
        case .conflict, .unsupported: .unavailable
        }
    }
}

public struct PasteboardCaptureCoordinator {
    private let pasteboard: PasteboardAccess
    private let sendCopy: () -> Bool
    private let sleep: (TimeInterval) -> Void

    public init(
        pasteboard: PasteboardAccess,
        sendCopy: @escaping () -> Bool,
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.pasteboard = pasteboard
        self.sendCopy = sendCopy
        self.sleep = sleep
    }

    public func capture(timeout: TimeInterval = 0.3, pollInterval: TimeInterval = 0.01) -> PasteboardCaptureOutcome {
        let baselineChangeCount = pasteboard.changeCount
        guard sendCopy() else { return .unsupported }

        let deadline = Date().addingTimeInterval(max(0, timeout))
        while pasteboard.changeCount == baselineChangeCount {
            guard Date() < deadline else { return .unchanged }
            sleep(min(pollInterval, max(0, deadline.timeIntervalSinceNow)))
        }

        let capturedChangeCount = pasteboard.changeCount
        let capturedText = pasteboard.string()
        guard pasteboard.changeCount == capturedChangeCount else { return .conflict }
        guard let text = capturedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .unsupported
        }
        return .captured(text: text)
    }
}

public final class SystemPasteboardAccess: PasteboardAccess {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int { pasteboard.changeCount }

    public func string() -> String? {
        pasteboard.string(forType: .string)
    }
}
