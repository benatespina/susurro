import os

enum AppLogger {
	static let subsystem = "com.benatespina.susurro"
	static let app = Logger(subsystem: subsystem, category: "app")
	static let backend = Logger(subsystem: subsystem, category: "backend")
	static let selection = Logger(subsystem: subsystem, category: "selection")
	static let playback = Logger(subsystem: subsystem, category: "playback")
	static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
	static let claudeIntegration = Logger(subsystem: subsystem, category: "claudeIntegration")
	static let translation = Logger(subsystem: subsystem, category: "translation")
	static let publishing = Logger(subsystem: subsystem, category: "publishing")

	static func claudeSkipped(reason: String) {
		claudeIntegration.info("Skipped TTS: \(reason, privacy: .public)")
	}

	static func claudeSpoke(charCount: Int) {
		claudeIntegration.info("Spoke \(charCount, privacy: .public) chars from Claude turn")
	}
}
