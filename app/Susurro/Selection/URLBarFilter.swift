import ApplicationServices

enum URLBarFilter {
    private static let keywords = ["address", "url", "location", "omnibox", "urlbar"]

    static func isAddressBar(_ element: AXUIElement) -> Bool {
        guard roleMatches(element) else { return false }
        let identifier = stringAttribute(element, kAXIdentifierAttribute as String) ?? ""
        let description = stringAttribute(element, kAXDescriptionAttribute as String) ?? ""
        let combined = (identifier + " " + description).lowercased()
        return keywords.contains { combined.contains($0) }
    }

    private static func roleMatches(_ element: AXUIElement) -> Bool {
        guard let role = stringAttribute(element, kAXRoleAttribute as String) else { return false }
        return role == "AXTextField" || role == "AXComboBox"
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
