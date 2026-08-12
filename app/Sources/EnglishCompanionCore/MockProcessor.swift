import Foundation

public struct CompanionOutput: Equatable, Sendable {
    public let primary: String
    public let secondaryTitle: String
    public let secondary: String

    public init(primary: String, secondaryTitle: String, secondary: String) {
        self.primary = primary
        self.secondaryTitle = secondaryTitle
        self.secondary = secondary
    }
}

public struct MockProcessor: Sendable {
    public init() {}

    public func process(mode: CompanionMode, text: String) -> CompanionOutput {
        switch mode {
        case .translate:
            return CompanionOutput(
                primary: "Let me take another look at this and get back to you later.",
                secondaryTitle: "中文回译 · MEANING CHECK",
                secondary: "让我再看一下这个，晚点再回复你。"
            )
        case .improve:
            return CompanionOutput(
                primary: "Is there anything you need from our side?",
                secondaryTitle: "DETAILED CHANGES",
                secondary: "Added ‘you’ as the subject of the relative clause and changed ‘our end’ to the more natural ‘our side’."
            )
        }
    }
}
