import ApplicationServices
import Foundation

public struct AXSelectedTextProvider: @unchecked Sendable {
    private let isTrusted: () -> Bool

    public init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.isTrusted = isTrusted
    }

    public func capture(frontmostPID: pid_t?) -> AccessibilitySelection {
        guard isTrusted() else { return .permissionRequired }
        guard let frontmostPID else { return .noSelection }

        let application = AXUIElementCreateApplication(frontmostPID)
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedStatus == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return focusedStatus == .attributeUnsupported ? .unsupported : .noSelection
        }

        let focusedElement = unsafeDowncast(focusedValue, to: AXUIElement.self)
        var selectedValue: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        guard selectedStatus == .success else {
            return selectedStatus == .attributeUnsupported ? .unsupported : .noSelection
        }
        guard let selectedText = selectedValue as? String,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .noSelection
        }
        return .selected(selectedText)
    }
}
