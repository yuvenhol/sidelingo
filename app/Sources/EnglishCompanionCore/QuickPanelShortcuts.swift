public struct KeyboardShortcutDescriptor: Equatable, Sendable {
    public let key: Character
    public let usesCommandModifier: Bool

    public init(key: Character, usesCommandModifier: Bool) {
        self.key = key
        self.usesCommandModifier = usesCommandModifier
    }
}

public enum QuickPanelResultPresentation {
    public static let textSelectionEnabled = true
    public static let copyButtonShortcut: KeyboardShortcutDescriptor? = nil
    public static let copyButtonKeycap: String? = nil

    public static func primaryTitle(mode: CompanionMode, inputUnavailable: Bool) -> String {
        if inputUnavailable { return "INPUT REQUIRED" }
        switch mode {
        case .translate:
            return "TRANSLATION"
        case .improve:
            return "IMPROVED · READY TO SEND"
        }
    }
}
