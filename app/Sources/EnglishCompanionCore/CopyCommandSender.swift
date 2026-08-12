import CoreGraphics

public struct CopyCommandSender {
    private let postKeyEvent: (CGKeyCode, Bool, CGEventFlags) -> Bool

    public init() {
        postKeyEvent = CopyCommandSender.postSystemKeyEvent
    }

    public init(postKeyEvent: @escaping (CGKeyCode, Bool, CGEventFlags) -> Bool) {
        self.postKeyEvent = postKeyEvent
    }

    public func send() -> Bool {
        let flags: CGEventFlags = [.maskCommand]
        let keyDownPosted = postKeyEvent(8, true, flags)
        let keyUpPosted = postKeyEvent(8, false, flags)
        return keyDownPosted && keyUpPosted
    }

    private static func postSystemKeyEvent(
        keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags
    ) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            return false
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        return true
    }
}
