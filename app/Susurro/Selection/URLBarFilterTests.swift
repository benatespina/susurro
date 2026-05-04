import Testing
import ApplicationServices
@testable import Susurro

@Suite("URLBarFilter")
struct URLBarFilterTests {
    @Test("isAddressBar does not crash when called with system-wide focused element")
    func isAddressBarSmokeTest() {
        let systemWide = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &ref
        ) == .success, let ref else { return }
        // swiftlint:disable:next force_cast
        let element = ref as! AXUIElement
        _ = URLBarFilter.isAddressBar(element)
    }
}
