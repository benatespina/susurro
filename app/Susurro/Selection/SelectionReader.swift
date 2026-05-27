import ApplicationServices
import AppKit

struct Selection: Equatable, Sendable {
    let text: String
    let bounds: CGRect?
}

enum SelectionReader {
    private static let maxSearchDepth = 10
    private static let maxSearchNodes = 400

    static func current() -> Selection? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 2.0)
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

        guard let focused else { return nil }

        if URLBarFilter.isAddressBar(focused) {
            return nil
        }

        // Try the focused element directly first; if it doesn't carry the selection
        // itself, walk its subtree. Walking only under the focused element avoids
        // returning stale selections from unrelated parts of the same window (e.g.
        // another browser tab, another text field). Trade-off: Electron apps where
        // the focused element is a generic container rather than a text element will
        // not detect selection — acceptable given the stale-selection bugs that arise
        // from wider walks.
        if let selection = readSelection(from: focused) {
            return selection
        }
        if let element = findSelectionBearer(under: focused),
           let selection = readSelection(from: element) {
            return selection
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

    static func cgRect(from value: AXValue) -> CGRect? {
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return rect
    }

    // MARK: - Unified selection predicate

    /// Returns true if the element carries a non-empty selected text via either
    /// the plain kAXSelectedTextAttribute or the WebKit AXTextMarker path.
    /// Used during BFS so that AXWebArea elements are discoverable, and as a
    /// fast check before the more expensive readSelection call.
    private static func elementHasNonEmptySelection(_ element: AXUIElement) -> Bool {
        var textRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textRef) == .success,
           let text = textRef as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return selectedTextWithMarker(from: element) != nil
    }

    // MARK: - Plain-attribute path

    private static func readSelection(from element: AXUIElement) -> Selection? {
        // Plain attribute path (standard AppKit / most apps)
        var textRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textRef) == .success,
           let text = textRef as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let bounds = readBounds(from: element)
            return Selection(text: text, bounds: bounds)
        }

        // WebKit / AXWebArea path (Mail, Safari, App Store, WKWebView)
        if let (text, markerRange) = selectedTextWithMarker(from: element) {
            let bounds = markerBounds(from: element, range: markerRange)
            return Selection(text: text, bounds: bounds)
        }

        return nil
    }

    // MARK: - WebKit AXTextMarker helpers

    /// Reads the selected text from a WebKit AXWebArea element using the opaque
    /// AXTextMarker API. The marker range is treated as an opaque CFTypeRef
    /// throughout — it is never bridged to a concrete Swift type.
    ///
    /// Returns the trimmed non-empty text and the opaque marker range (needed for
    /// bounds resolution), or nil if the element does not carry a marker selection.
    private static func selectedTextWithMarker(from element: AXUIElement) -> (text: String, markerRange: CFTypeRef)? {
        var markerRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &markerRangeRef
        ) == .success,
              let markerRange = markerRangeRef
        else { return nil }

        var stringRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            markerRange,
            &stringRef
        ) == .success,
              let text = stringRef as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return (text, markerRange)
    }

    /// Resolves screen bounds for a selection described by an opaque AXTextMarker
    /// range, reusing the existing cgRect(from:) and isUsable(_:) helpers.
    /// Returns nil on any failure; PanelController already falls back to positionNearMouse.
    private static func markerBounds(from element: AXUIElement, range markerRange: CFTypeRef) -> CGRect? {
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &boundsRef
        ) == .success,
              let boundsRef
        else { return nil }

        guard let rect = cgRect(from: boundsRef as! AXValue), // swiftlint:disable:this force_cast
              isUsable(rect)
        else { return nil }
        return rect
    }

    // MARK: - BFS

    private static func findSelectionBearer(under root: AXUIElement) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < maxSearchNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1

            if elementHasNonEmptySelection(element) {
                return element
            }

            guard depth < maxSearchDepth else { continue }
            for child in children(of: element) {
                queue.append((child, depth + 1))
            }
        }
        return nil
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
