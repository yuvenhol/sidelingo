import Carbon
import SideLingoCore
import Foundation

private let sideLingoHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    return monitor.receive(event)
}

final class GlobalHotKeyMonitor {
    private var handlerReference: EventHandlerRef?
    private var registrations: [GlobalHotKeyRegistration] = []
    private var actions: [UInt32: () -> Void] = [:]

    init() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            sideLingoHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )
        guard status == noErr else { throw GlobalHotKeyError(status: status) }
    }

    func register(
        identifier: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) throws {
        let registration = try GlobalHotKeyRegistration(
            signature: 0x534C474F,
            identifier: identifier,
            keyCode: keyCode,
            modifiers: modifiers
        )
        registrations.append(registration)
        actions[identifier] = action
    }

    fileprivate func receive(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        actions[hotKeyID.id]?()
        return noErr
    }

    deinit {
        registrations.forEach { $0.unregister() }
        if let handlerReference { RemoveEventHandler(handlerReference) }
    }
}
