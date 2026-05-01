import AppKit
import SwiftUI

/// Read-only selectable text bridge to NSTextView. Preserves native selection,
/// kerning, hyphenation, copy, VoiceOver. Adds:
///   - tap (no drag, no selection) → `onTapEmpty` for seek
///   - right-click on selection → "Fix pronunciation of '<word>'" menu item
struct SelectableTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let lineSpacing: CGFloat
    let onTapEmpty: () -> Void
    let onFixPronunciation: (String) -> Void

    func makeNSView(context: Context) -> TapAwareTextView {
        let textView = TapAwareTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = false
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.onTapEmpty = onTapEmpty
        textView.onFixPronunciation = onFixPronunciation
        applyContent(to: textView)
        return textView
    }

    func updateNSView(_ textView: TapAwareTextView, context: Context) {
        textView.onTapEmpty = onTapEmpty
        textView.onFixPronunciation = onFixPronunciation
        applyContent(to: textView)
        textView.invalidateIntrinsicContentSize()
    }

    private func applyContent(to textView: NSTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraph,
            ]
        )
        textView.textStorage?.setAttributedString(attributed)
    }
}

final class TapAwareTextView: NSTextView {
    var onTapEmpty: (() -> Void)?
    var onFixPronunciation: ((String) -> Void)?

    private var pendingTapWorkItem: DispatchWorkItem?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let container = textContainer else {
            return super.intrinsicContentSize
        }
        // Ensure layout is computed for the current container size.
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: ceil(used.height) + textContainerInset.height * 2
        )
    }

    override func layout() {
        super.layout()
        // Width changed; container size depends on view width when widthTracksTextView=true.
        invalidateIntrinsicContentSize()
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func mouseDown(with event: NSEvent) {
        // NSTextView spins its own event loop inside super.mouseDown to handle
        // drag selection, consuming the mouseUp before it reaches a subclass
        // override. So we let super run to completion and inspect post-state.
        pendingTapWorkItem?.cancel()
        super.mouseDown(with: event)

        // Multi-click (double/triple) selects word/line natively; do not seek.
        guard event.clickCount == 1 else { return }
        // Drag-selection leaves a non-empty selection; do not seek.
        guard selectedRange().length == 0 else { return }

        // Defer single-tap → seek by doubleClickInterval so a follow-up
        // double-click can cancel the pending seek.
        let workItem = DispatchWorkItem { [weak self] in
            self?.onTapEmpty?()
        }
        pendingTapWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + NSEvent.doubleClickInterval,
            execute: workItem
        )
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let selected = selectedText()
        guard !selected.isEmpty else { return menu }
        let title = "Fix pronunciation of \"\(displayPreview(of: selected))\"…"
        let item = NSMenuItem(
            title: title,
            action: #selector(invokeFixPronunciation(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = selected
        menu.insertItem(item, at: 0)
        menu.insertItem(NSMenuItem.separator(), at: 1)
        return menu
    }

    @objc private func invokeFixPronunciation(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        onFixPronunciation?(value)
    }

    private func selectedText() -> String {
        let range = selectedRange()
        guard range.length > 0,
              let storage = textStorage,
              range.location + range.length <= storage.length
        else { return "" }
        return storage.attributedSubstring(from: range).string
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func displayPreview(of value: String, max: Int = 30) -> String {
        if value.count <= max { return value }
        let prefix = value.prefix(max - 1)
        return "\(prefix)…"
    }
}
