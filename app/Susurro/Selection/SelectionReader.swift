import ApplicationServices
import AppKit

struct Selection: Equatable, Sendable {
    let text: String
    let bounds: CGRect?
}

enum SelectionReader {
    static func current() -> Selection? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(pid)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef
        else { return nil }
        // CFTypeRef bridge — AXUIElement is a CF type, unconditional cast is correct
        let focused = focusedRef as! AXUIElement // swiftlint:disable:this force_cast

        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &textRef) == .success,
              let text = textRef as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let bounds = readBounds(from: focused)
        return Selection(text: text, bounds: bounds)
    }

    static func cgRect(from value: AXValue) -> CGRect? {
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func readBounds(from element: AXUIElement) -> CGRect? {
        var boundsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextBounds" as CFString, &boundsRef) == .success,
           let boundsRef {
            return cgRect(from: boundsRef as! AXValue) // swiftlint:disable:this force_cast
        }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef
        else { return nil }

        var paramBoundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &paramBoundsRef
        ) == .success,
              let paramBoundsRef
        else { return nil }

        return cgRect(from: paramBoundsRef as! AXValue) // swiftlint:disable:this force_cast
    }
}
