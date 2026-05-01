import ApplicationServices
import AppKit

struct Selection: Equatable, Sendable {
    let text: String
    let bounds: CGRect?
}

enum SelectionReader {
    private static let maxSearchDepth = 8
    private static let maxSearchNodes = 400

    static func current() -> Selection? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        activateAccessibility(appElement: appElement)

        var focusedRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        let focused: AXUIElement? = (focusedStatus == .success && focusedRef != nil)
            // swiftlint:disable:next force_cast
            ? (focusedRef! as! AXUIElement)
            : nil

        if let focused, let selection = readSelection(from: focused) {
            return selection
        }

        // Electron / Chromium apps (Claude, VS Code, Slack…) often expose selected text
        // on a descendant of the focused element (or under the focused window) rather than
        // on the focused element itself. Walk the subtree to find it.
        let roots: [AXUIElement] = [focused, focusedWindow(in: appElement), appElement].compactMap { $0 }
        for root in roots {
            if let element = findSelectionBearer(under: root),
               let selection = readSelection(from: element) {
                return selection
            }
        }

        return nil
    }

    // Chromium-based apps (Electron) build their AX tree lazily and only expose it
    // once an assistive client signals it needs accessibility — VoiceOver does this
    // implicitly; we have to do it explicitly. Setting AXManualAccessibility or
    // AXEnhancedUserInterface to true on the app element triggers tree construction.
    // Harmless on non-Electron apps that don't recognize the attributes.
    private static func activateAccessibility(appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private static func focusedWindow(in appElement: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref
        else { return nil }
        return (ref as! AXUIElement) // swiftlint:disable:this force_cast
    }

    static func cgRect(from value: AXValue) -> CGRect? {
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func readSelection(from element: AXUIElement) -> Selection? {
        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textRef) == .success,
              let text = textRef as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let bounds = readBounds(from: element)
        return Selection(text: text, bounds: bounds)
    }

    private static func findSelectionBearer(under root: AXUIElement) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < maxSearchNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1

            if hasNonEmptySelectedText(element) {
                return element
            }

            guard depth < maxSearchDepth else { continue }
            for child in children(of: element) {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    private static func hasNonEmptySelectedText(_ element: AXUIElement) -> Bool {
        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textRef) == .success,
              let text = textRef as? String
        else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let array = ref as? [AXUIElement]
        else { return [] }
        return array
    }

    private static func readBounds(from element: AXUIElement) -> CGRect? {
        var boundsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextBounds" as CFString, &boundsRef) == .success,
           let boundsRef,
           let rect = cgRect(from: boundsRef as! AXValue), // swiftlint:disable:this force_cast
           isUsable(rect) {
            return rect
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

        guard let rect = cgRect(from: paramBoundsRef as! AXValue), // swiftlint:disable:this force_cast
              isUsable(rect)
        else { return nil }
        return rect
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(rect) }
    }
}
