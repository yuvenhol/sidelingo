import Carbon
import Foundation

public struct GlobalHotKeyError: Error, Equatable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }
}

public final class GlobalHotKeyRegistration: @unchecked Sendable {
    private var reference: EventHotKeyRef?

    public private(set) var isRegistered = false

    public init(
        signature: OSType,
        identifier: UInt32,
        keyCode: UInt32,
        modifiers: UInt32
    ) throws {
        var hotKeyReference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard status == noErr, let hotKeyReference else {
            throw GlobalHotKeyError(status: status)
        }
        reference = hotKeyReference
        isRegistered = true
    }

    public func unregister() {
        guard let reference else { return }
        UnregisterEventHotKey(reference)
        self.reference = nil
        isRegistered = false
    }

    deinit {
        if let reference {
            UnregisterEventHotKey(reference)
        }
    }
}
