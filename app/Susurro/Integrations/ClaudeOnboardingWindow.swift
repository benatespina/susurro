import AppKit

@MainActor
enum ClaudeOnboarding {
	private static let shownKey = "claude.onboarding.shown"

	static func showIfFirstInstall() {
		guard !UserDefaults.standard.bool(forKey: shownKey) else { return }
		OnboardingWindowController.shared.showWindow(nil)
	}

	static func markShown() {
		UserDefaults.standard.set(true, forKey: shownKey)
	}
}

@MainActor
private final class OnboardingWindowController: NSWindowController {
	static let shared = OnboardingWindowController()

	private init() {
		let panel = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
			styleMask: [.titled, .closable, .hudWindow],
			backing: .buffered,
			defer: false
		)
		panel.title = "Susurro × Claude Code"
		panel.isReleasedWhenClosed = false
		panel.center()
		panel.level = .floating

		let contentView = NSView(frame: panel.contentView!.bounds)
		contentView.autoresizingMask = [.width, .height]

		let label = NSTextField(wrappingLabelWithString:
			"Susurro is now connected to Claude Code. Open a Claude Code session and send a message — Susurro will read Claude's response aloud (skipping code blocks). Use the menu to toggle Auto-read or disable per-project."
		)
		label.frame = NSRect(x: 16, y: 48, width: 388, height: 112)
		label.autoresizingMask = [.width]
		contentView.addSubview(label)

		let button = NSButton(title: "Got it", target: nil, action: #selector(gotItClicked(_:)))
		button.bezelStyle = .rounded
		button.frame = NSRect(x: 326, y: 12, width: 78, height: 28)
		button.autoresizingMask = [.minXMargin]
		button.keyEquivalent = "\r"
		contentView.addSubview(button)

		panel.contentView = contentView
		super.init(window: panel)
		button.target = self
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError() }

	@objc private func gotItClicked(_ sender: Any?) {
		ClaudeOnboarding.markShown()
		window?.close()
	}
}
