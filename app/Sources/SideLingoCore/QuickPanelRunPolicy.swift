import Foundation

public struct QuickPanelRunRequest: Equatable, Sendable {
    public let text: String
    public let sourceLabel: String

    public init(text: String, sourceLabel: String) {
        self.text = text
        self.sourceLabel = sourceLabel
    }
}

public enum QuickPanelRunPolicy {
    public static func request(for input: String) -> QuickPanelRunRequest? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return QuickPanelRunRequest(text: text, sourceLabel: "Typed")
    }
}
