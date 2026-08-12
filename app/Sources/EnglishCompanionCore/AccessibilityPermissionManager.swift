@preconcurrency import ApplicationServices
import Foundation

public enum AccessibilityPermissionStatus: Equatable, Sendable {
    case granted
    case required
}

public struct AccessibilityPermissionManager: @unchecked Sendable {
    private let isTrusted: () -> Bool
    private let requestPrompt: () -> Bool

    public init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        requestPrompt: @escaping () -> Bool = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    ) {
        self.isTrusted = isTrusted
        self.requestPrompt = requestPrompt
    }

    public func status() -> AccessibilityPermissionStatus {
        isTrusted() ? .granted : .required
    }

    @discardableResult
    public func requestIfNeeded() -> AccessibilityPermissionStatus {
        if isTrusted() { return .granted }
        return requestPrompt() ? .granted : .required
    }
}
