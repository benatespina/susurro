import AppKit
import ApplicationServices

enum TextAppSource {
    private static let maxSearchDepth = 22
    private static let maxSearchNodes = 12000
    private static let minTextLength = 40
    private static let minStaticTextChunkLength = 2

    static func extractText(pid: pid_t, bundleID: String? = nil) -> (text: String, title: String?)? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 2.0)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &winRef
        ) == .success, let winRef else { return nil }
        let window = winRef as! AXUIElement // swiftlint:disable:this force_cast

        let rawTitle = readWindowTitle(window)
        let title = rawTitle.map { bundleID == "com.apple.mail" ? cleanTitle($0) : $0 }
        let collected = walkAndCollect(root: window)

        if let large = collected.bigTextValue {
            return (large.trimmingCharacters(in: .whitespacesAndNewlines), title)
        }
        let joined = collected.staticTextChunks
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.count >= minTextLength {
            return (joined, title)
        }
        return nil
    }

    private struct Collected {
        var bigTextValue: String?
        var staticTextChunks: [String]
    }

    private static func walkAndCollect(root: AXUIElement) -> Collected {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        var bigTextValue: String?
        var staticChunks: [String] = []

        while !queue.isEmpty, visited < maxSearchNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1

            let role = readRole(element)
            if role == "AXTextArea" || role == "AXTextField" {
                if let text = readValue(element), text.count >= minTextLength {
                    if bigTextValue == nil || text.count > (bigTextValue?.count ?? 0) {
                        bigTextValue = text
                    }
                }
            } else if role == "AXWebArea" {
                if let text = fullDocumentTextViaMarker(element), text.count >= minTextLength {
                    if bigTextValue == nil || text.count > (bigTextValue?.count ?? 0) {
                        bigTextValue = text
                    }
                    continue // marker gave us the full document text; skip redundant child walk
                }
            } else if role == "AXStaticText" {
                if let text = readValue(element), text.count >= minStaticTextChunkLength {
                    staticChunks.append(text)
                }
            }

            guard depth < maxSearchDepth else { continue }
            for child in children(of: element) {
                queue.append((child, depth + 1))
            }
        }
        return Collected(bigTextValue: bigTextValue, staticTextChunks: staticChunks)
    }

    /// Reads the full document text from a WebKit AXWebArea using the opaque
    /// AXTextMarker API. The marker range is treated as an opaque CFTypeRef
    /// throughout — never bridged to a concrete Swift type — mirroring the
    /// pattern used in SelectionReader.selectedTextWithMarker(from:).
    private static func fullDocumentTextViaMarker(_ element: AXUIElement) -> String? {
        var fullRangeRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerRangeForUIElement" as CFString,
            element as CFTypeRef,
            &fullRangeRef
        ) == .success, let fullRangeRef else { return nil }

        var stringRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            fullRangeRef,
            &stringRef
        ) == .success,
              let text = stringRef as? String
        else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Strips app-specific suffixes from window titles so library items get
    /// clean, human-readable titles. Currently handles Mail (" — Mail" suffix).
    private static func cleanTitle(_ title: String) -> String {
        let mailSuffix = " \u{2014} Mail"
        if title.hasSuffix(mailSuffix) {
            return String(title.dropLast(mailSuffix.count))
        }
        return title
    }

    private static func readRole(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &ref
        ) == .success else { return nil }
        return ref as? String
    }

    private static func readValue(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXValueAttribute as CFString, &ref
        ) == .success else { return nil }
        if let str = ref as? String { return str }
        if let attr = ref as? NSAttributedString { return attr.string }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &ref
        ) == .success, let array = ref as? [AXUIElement]
        else { return [] }
        return array
    }

    private static func readWindowTitle(_ window: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window, kAXTitleAttribute as CFString, &ref
        ) == .success else { return nil }
        return ref as? String
    }
}
