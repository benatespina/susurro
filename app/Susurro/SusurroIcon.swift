import AppKit

enum SusurroIcon {
    private static let canvasHeight: CGFloat = 22
    private static let scale: CGFloat = 3
    private static let horizontalMargin: CGFloat = 0

    static let iconWidth: CGFloat = {
        if let asset = NSImage(named: "MenuBarIcon") {
            let size = asset.size          // NSImage.size is in points
            guard size.height > 0 else { return emojiIconWidth() }
            return (canvasHeight * (size.width / size.height) * 2).rounded() / 2
        }
        return emojiIconWidth()
    }()

    // MARK: - Public

    static func template() -> NSImage {
        if let asset = NSImage(named: "MenuBarIcon") {
            asset.isTemplate = true
            return asset
        }
        return emojiTemplate()
    }

    // MARK: - Emoji fallback (used when the PNG asset is absent)

    private static func emojiIconWidth() -> CGFloat {
        let bounds = visualGlyphBounds()
        let rawWidth = bounds.width / scale + horizontalMargin
        return (rawWidth * 2).rounded() / 2
    }

    private static func visualGlyphBounds() -> CGRect {
        let fontSize = canvasHeight * 0.95 * scale
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
        let str = NSAttributedString(string: "🗣️", attributes: attrs)
        let line = CTLineCreateWithAttributedString(str as CFAttributedString)
        return CTLineGetImageBounds(line, nil)
    }

    private static func emojiTemplate() -> NSImage {
        let canvas = NSSize(width: iconWidth, height: canvasHeight)
        let pxW = Int(canvas.width * scale)
        let pxH = Int(canvas.height * scale)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxW,
            pixelsHigh: pxH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pxW * 4,
            bitsPerPixel: 32
        ) else {
            return NSImage(size: canvas)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pxW, height: pxH).fill()

        let fontSize = canvasHeight * 0.95 * scale
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
        let str = NSAttributedString(string: "🗣️", attributes: attrs)
        let glyphBounds = visualGlyphBounds()
        let verticalNudgeDown = 2.8 * scale
        let drawX = (CGFloat(pxW) - glyphBounds.width) / 2 - glyphBounds.minX
        let drawY = (CGFloat(pxH) - glyphBounds.height) / 2 - glyphBounds.minY - verticalNudgeDown
        str.draw(at: NSPoint(x: drawX, y: drawY))

        NSGraphicsContext.restoreGraphicsState()

        if let data = bitmap.bitmapData {
            let count = pxW * pxH * 4
            for i in stride(from: 0, to: count, by: 4) {
                data[i] = 0
                data[i + 1] = 0
                data[i + 2] = 0
            }
        }

        let image = NSImage(size: canvas)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }
}
