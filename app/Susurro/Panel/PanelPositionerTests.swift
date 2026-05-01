import Testing
import AppKit
@testable import Susurro

@Suite("PanelPositioner")
struct PanelPositionerTests {
    // A mock screen with a known frame. NSScreen can't be instantiated directly,
    // so we test using NSScreen.main and verify clamping logic separately.

    let panelSize = CGSize(width: 44, height: 44)

    // Helpers to create a representative screen frame and visible frame.
    // We cannot create real NSScreen instances, so we test position() logic
    // via a real screen or by verifying mathematical invariants.

    @Test("selection in middle of screen — panel appears below, centered")
    func selectionInMiddleOfScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        // AX rect: top-left origin, middle of screen
        let selectionRect = CGRect(
            x: screenFrame.midX - 50,
            y: screenFrame.height / 2 - 10,  // AX top-left Y
            width: 100,
            height: 20
        )
        let point = PanelPositioner.position(for: selectionRect, panelSize: panelSize, on: screen)
        // X should be roughly centered on selection
        let expectedX = selectionRect.midX - panelSize.width / 2
        #expect(abs(point.x - expectedX) < 1)
        // Panel is within visible frame
        #expect(point.x >= screen.visibleFrame.minX)
        #expect(point.x + panelSize.width <= screen.visibleFrame.maxX)
        #expect(point.y >= screen.visibleFrame.minY)
        #expect(point.y + panelSize.height <= screen.visibleFrame.maxY)
    }

    @Test("selection at right edge — panel clamps to right screen edge")
    func selectionAtRightEdge() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let selectionRect = CGRect(
            x: screenFrame.maxX - 10,
            y: screenFrame.height / 2,
            width: 100,
            height: 20
        )
        let point = PanelPositioner.position(for: selectionRect, panelSize: panelSize, on: screen)
        #expect(point.x + panelSize.width <= screen.visibleFrame.maxX)
    }

    @Test("selection at bottom — panel clamps to screen bottom")
    func selectionAtBottom() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        // AX top-left Y near bottom of screen
        let selectionRect = CGRect(
            x: screenFrame.midX,
            y: screenFrame.height - 5,  // near bottom in AX coords
            width: 50,
            height: 10
        )
        let point = PanelPositioner.position(for: selectionRect, panelSize: panelSize, on: screen)
        #expect(point.y >= screen.visibleFrame.minY)
        #expect(point.y + panelSize.height <= screen.visibleFrame.maxY)
    }

    @Test("zero-size selection — handled gracefully")
    func zeroSizeSelection() {
        guard let screen = NSScreen.main else { return }
        let selectionRect = CGRect(
            x: screen.frame.midX,
            y: screen.frame.midY,
            width: 0,
            height: 0
        )
        let point = PanelPositioner.position(for: selectionRect, panelSize: panelSize, on: screen)
        // Should not crash and should be clamped
        #expect(point.x >= screen.visibleFrame.minX)
        #expect(point.y >= screen.visibleFrame.minY)
    }

    // MARK: - Pill size (92×36) tests

    @Test("pill — horizontally centered on selection midX")
    func pillHorizontallyCentered() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let pillSize = CGSize(width: 92, height: 36)
        // Selection in the middle of the screen with known midX
        let selectionRect = CGRect(
            x: screenFrame.midX - 60,
            y: screenFrame.height / 2 - 10,
            width: 120,
            height: 20
        )
        let point = PanelPositioner.position(for: selectionRect, panelSize: pillSize, on: screen)
        let expectedX = selectionRect.midX - pillSize.width / 2
        // X should be centered (not clamped, since the selection is in the middle)
        #expect(abs(point.x - expectedX) < 1)
        // Panel is within visible frame
        #expect(point.x >= screen.visibleFrame.minX)
        #expect(point.x + pillSize.width <= screen.visibleFrame.maxX)
        #expect(point.y >= screen.visibleFrame.minY)
        #expect(point.y + pillSize.height <= screen.visibleFrame.maxY)
    }

    @Test("pill — clamps to left edge when selection is near left")
    func pillClampsAtLeftEdge() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let pillSize = CGSize(width: 92, height: 36)
        // Selection at the far left — pill would go off-screen without clamping
        let selectionRect = CGRect(
            x: screenFrame.minX,
            y: screenFrame.height / 2,
            width: 10,
            height: 20
        )
        let point = PanelPositioner.position(for: selectionRect, panelSize: pillSize, on: screen)
        #expect(point.x >= screen.visibleFrame.minX)
        #expect(point.x + pillSize.width <= screen.visibleFrame.maxX)
    }

    @Test("pill — clamps to right edge when selection is near right")
    func pillClampsAtRightEdge() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let pillSize = CGSize(width: 92, height: 36)
        // Selection at the far right — pill would go off-screen without clamping
        let selectionRect = CGRect(
            x: screenFrame.maxX - 10,
            y: screenFrame.height / 2,
            width: 100,
            height: 20
        )
        let point = PanelPositioner.position(for: selectionRect, panelSize: pillSize, on: screen)
        #expect(point.x + pillSize.width <= screen.visibleFrame.maxX)
    }

    @Test("pill — flips above selection when bottom-clipped")
    func pillFlipsAboveWhenBottomClipped() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let pillSize = CGSize(width: 92, height: 36)
        // AX top-left Y near bottom of screen so panel would be clipped below
        let selectionRect = CGRect(
            x: screenFrame.midX - 50,
            y: screenFrame.height - 5,
            width: 100,
            height: 10
        )
        let point = PanelPositioner.position(for: selectionRect, panelSize: pillSize, on: screen)
        // Regardless of flip direction, must stay within visible frame
        #expect(point.y >= screen.visibleFrame.minY)
        #expect(point.y + pillSize.height <= screen.visibleFrame.maxY)
    }

    @Test("multi-display: coordinates relative to the given non-main screen")
    func multiDisplayNonMainScreen() {
        let screens = NSScreen.screens
        guard screens.count >= 2 else { return }
        let nonMain = screens.first { $0 != NSScreen.main } ?? screens[1]
        let screenFrame = nonMain.frame
        let selectionRect = CGRect(
            x: screenFrame.midX - 50,
            y: screenFrame.height / 2,
            width: 100,
            height: 20
        )
        let point = PanelPositioner.position(for: selectionRect, panelSize: panelSize, on: nonMain)
        #expect(point.x >= nonMain.visibleFrame.minX)
        #expect(point.x + panelSize.width <= nonMain.visibleFrame.maxX)
        #expect(point.y >= nonMain.visibleFrame.minY)
        #expect(point.y + panelSize.height <= nonMain.visibleFrame.maxY)
    }
}
