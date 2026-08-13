import Foundation

public enum CompanionMode: String, Equatable, Sendable {
    case translate
    case improve
}

public enum SelectionSource: Equatable, Sendable {
    case accessibility
    case clipboardFallback
}

public enum AccessibilitySelection: Equatable, Sendable {
    case selected(String)
    case noSelection
    case permissionRequired
    case unsupported
}

public enum ClipboardFallback: Equatable, Sendable {
    case captured(String)
    case unchanged
    case unavailable
}

public enum InvocationUnavailableReason: Equatable, Sendable {
    case permissionRequired
    case noSelection
    case unsupported
}

public enum InvocationResult: Equatable, Sendable {
    case ready(mode: CompanionMode, text: String, source: SelectionSource)
    case unavailable(mode: CompanionMode, reason: InvocationUnavailableReason)
}

public struct InvocationCoordinator: Sendable {
    public init() {}

    public func resolve(
        mode: CompanionMode,
        accessibility: AccessibilitySelection,
        clipboardFallback: ClipboardFallback
    ) -> InvocationResult {
        if case let .selected(text) = accessibility {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .ready(mode: mode, text: trimmed, source: .accessibility)
            }
        }

        if case let .captured(text) = clipboardFallback {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .ready(mode: mode, text: trimmed, source: .clipboardFallback)
            }
        }

        switch accessibility {
        case .permissionRequired:
            return .unavailable(mode: mode, reason: .permissionRequired)
        case .unsupported:
            return .unavailable(mode: mode, reason: .unsupported)
        case .selected, .noSelection:
            return .unavailable(mode: mode, reason: .noSelection)
        }
    }
}
