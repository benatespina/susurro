import AppKit

enum PanelPositioner {
    static let panelOffset: CGFloat = 8

    /// Computes the panel's bottom-left position (NSWindow origin) given the selection rect.
    ///
    /// `selectionRect` from AX uses a **top-left** origin in the global screen coordinate space.
    /// NSWindow uses a **bottom-left** origin. We convert here.
    ///
    /// Placement: prefer below the selection, horizontally centered. If the panel
    /// would clip below the visible frame, place it above the selection instead.
    static func position(
        for selectionRect: CGRect,
        panelSize: CGSize,
        on screen: NSScreen
    ) -> CGPoint {
        // AX bounds use top-left origin; convert to Cocoa bottom-left.
        let cocoaSelectionBottom = screen.frame.maxY - selectionRect.maxY
        let cocoaSelectionTop = screen.frame.maxY - selectionRect.minY

        let x = selectionRect.midX - panelSize.width / 2
        let yBelow = cocoaSelectionBottom - panelSize.height - panelOffset
        let yAbove = cocoaSelectionTop + panelOffset

        let visible = screen.visibleFrame
        let preferAbove = yBelow < visible.minY
        let y = preferAbove ? yAbove : yBelow

        return clamp(CGPoint(x: x, y: y), panelSize: panelSize, on: screen)
    }

    /// Fallback position near the mouse cursor when selection bounds are unavailable.
    static func positionNearMouse(
        panelSize: CGSize,
        on screen: NSScreen
    ) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let x = mouse.x - panelSize.width / 2
        let y = mouse.y - panelSize.height - panelOffset
        return clamp(CGPoint(x: x, y: y), panelSize: panelSize, on: screen)
    }

    private static func clamp(_ point: CGPoint, panelSize: CGSize, on screen: NSScreen) -> CGPoint {
        let frame = screen.visibleFrame
        let clampedX = point.x.clamped(to: frame.minX ... frame.maxX - panelSize.width)
        let clampedY = point.y.clamped(to: frame.minY ... frame.maxY - panelSize.height)
        return CGPoint(x: clampedX, y: clampedY)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
