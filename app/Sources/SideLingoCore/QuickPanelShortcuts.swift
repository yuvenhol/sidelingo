public struct KeyboardShortcutDescriptor: Equatable, Sendable {
    public let key: Character
    public let usesCommandModifier: Bool

    public init(key: Character, usesCommandModifier: Bool) {
        self.key = key
        self.usesCommandModifier = usesCommandModifier
    }
}

public enum QuickPanelInputPresentation {
    public static let editorLineLimit = 1
    public static let centersControlsVertically = true
    public static let showsFullInputPreview = true
    public static let previewTitle = "INPUT"
    public static let panelHeight = 520.0
}

public enum QuickPanelResultPresentation {
    public static let textSelectionEnabled = true
    public static let copyButtonShortcut: KeyboardShortcutDescriptor? = nil
    public static let copyButtonKeycap: String? = nil

    public static func output(for partial: CompanionOutputPartial) -> CompanionOutput {
        CompanionOutput(
            primary: partial.primary ?? "",
            secondaryTitle: partial.secondaryTitle ?? "",
            secondary: partial.secondary ?? ""
        )
    }

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
