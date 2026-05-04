import AppKit
import ApplicationServices

enum BrowserURLSource {
    private static let maxSearchDepth = 12
    private static let maxSearchNodes = 1500

    static func currentURL(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        // Chromium-based browsers (Chrome, Brave, Edge, Arc, Vivaldi) do not build
        // their AX tree until an assistive client signals interest. Same trick as
        // SelectionReader uses for Electron apps.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

        guard let window = focusedWindow(in: appElement) else { return nil }

        if let url = findURLInSubtree(root: window) {
            return normalize(url)
        }
        if let url = readAddressBar(in: window) {
            return normalize(url)
        }
        return nil
    }

    private static func focusedWindow(in appElement: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &ref
        ) == .success, let ref else { return nil }
        return (ref as! AXUIElement) // swiftlint:disable:this force_cast
    }

    private static func findURLInSubtree(root: AXUIElement) -> String? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < maxSearchNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1

            if let url = readURLAttribute(element) {
                return url
            }

            guard depth < maxSearchDepth else { continue }
            for child in children(of: element) {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    private static func readURLAttribute(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, "AXURL" as CFString, &ref
        ) == .success, let ref else { return nil }
        if let url = ref as? URL { return url.absoluteString }
        if let str = ref as? String { return str }
        return nil
    }

    private static func readAddressBar(in window: AXUIElement) -> String? {
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        var firstURLLookingTextField: String?
        while !queue.isEmpty, visited < maxSearchNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1

            if isTextField(element) {
                let value = textFieldValue(element)
                if let value, !value.isEmpty, looksLikeURL(value) {
                    if firstURLLookingTextField == nil {
                        firstURLLookingTextField = value
                    }
                    if isAddressFieldHinted(element) {
                        return value
                    }
                }
            }

            guard depth < maxSearchDepth else { continue }
            for child in children(of: element) {
                queue.append((child, depth + 1))
            }
        }
        if let value = firstURLLookingTextField {
            return value
        }
        return nil
    }

    private static func isTextField(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &roleRef
        ) == .success, let role = roleRef as? String
        else { return false }
        return role == "AXTextField" || role == "AXComboBox"
    }

    private static func textFieldValue(_ element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXValueAttribute as CFString, &valueRef
        ) == .success else { return nil }
        return valueRef as? String
    }

    private static func looksLikeURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return true
        }
        if !trimmed.contains(" "), trimmed.contains("."), trimmed.count >= 4 {
            return true
        }
        return false
    }

    private static func isAddressFieldHinted(_ element: AXUIElement) -> Bool {
        URLBarFilter.isAddressBar(element)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &ref
        ) == .success, let array = ref as? [AXUIElement]
        else { return [] }
        return array
    }

    private static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            candidate = trimmed
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            candidate = "https://" + trimmed
        } else {
            return nil
        }
        guard let parsed = URL(string: candidate),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host?.isEmpty == false
        else { return nil }
        return parsed.absoluteString
    }
}
