import Foundation

enum ClaudeHookInstallerError: Error, LocalizedError {
	case invalidJSON(String)
	case writeFailure(String)

	var errorDescription: String? {
		switch self {
		case .invalidJSON(let detail):
			return "~/.claude/settings.json is not valid JSON and will not be modified. Detail: \(detail)"
		case .writeFailure(let detail):
			return "Failed to write ~/.claude/settings.json: \(detail)"
		}
	}
}

enum ClaudeHookInstaller {
	static var wrapperInstallPath: String {
		let support = FileManager.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		return support.appending(path: "Susurro/hooks/stop.sh").path
	}

	private static var settingsURL: URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appending(path: ".claude/settings.json")
	}

	static func isInstalled() -> Bool {
		guard let settings = try? readSettings() else { return false }
		let path = wrapperInstallPath
		return containsOurHook(settings, wrapperPath: path)
	}

	static func install() throws {
		let path = wrapperInstallPath
		try installWrapper()
		let settings = try readOrCreateSettings()
		let patched = patch(settings, wrapperPath: path)
		try writeSettings(patched)
	}

	static func uninstall() throws {
		let path = wrapperInstallPath
		var settings = try readOrCreateSettings()
		settings = unpatch(settings, wrapperPath: path)
		try writeSettings(settings)
	}

	// MARK: - Internal helpers exposed for testing

	static func patch(_ settings: [String: Any], wrapperPath: String) -> [String: Any] {
		if containsOurHook(settings, wrapperPath: wrapperPath) {
			return settings
		}

		var result = settings
		if result["hooks"] != nil, !(result["hooks"] is [String: Any]) {
			return settings
		}
		var hooks = result["hooks"] as? [String: Any] ?? [:]
		if hooks["Stop"] != nil, !(hooks["Stop"] is [[String: Any]]) {
			return settings
		}
		var stopArray = hooks["Stop"] as? [[String: Any]] ?? []

		let ourEntry: [String: Any] = [
			"matcher": "*",
			"hooks": [["type": "command", "command": wrapperPath] as [String: Any]]
		]
		stopArray.append(ourEntry)
		hooks["Stop"] = stopArray
		result["hooks"] = hooks
		return result
	}

	static func unpatch(_ settings: [String: Any], wrapperPath: String) -> [String: Any] {
		var result = settings
		guard var hooks = result["hooks"] as? [String: Any] else { return result }
		guard var stopArray = hooks["Stop"] as? [[String: Any]] else { return result }

		stopArray = stopArray.compactMap { entry -> [String: Any]? in
			guard var innerHooks = entry["hooks"] as? [[String: Any]] else { return entry }
			innerHooks = innerHooks.filter { hook in
				(hook["command"] as? String) != wrapperPath
			}
			if innerHooks.isEmpty { return nil }
			var updated = entry
			updated["hooks"] = innerHooks
			return updated
		}

		if stopArray.isEmpty {
			hooks.removeValue(forKey: "Stop")
		} else {
			hooks["Stop"] = stopArray
		}

		if hooks.isEmpty {
			result.removeValue(forKey: "hooks")
		} else {
			result["hooks"] = hooks
		}
		return result
	}

	// MARK: - Private

	private static func containsOurHook(_ settings: [String: Any], wrapperPath: String) -> Bool {
		guard let hooks = settings["hooks"] as? [String: Any],
			  let stopArray = hooks["Stop"] as? [[String: Any]] else { return false }
		for entry in stopArray {
			if let innerHooks = entry["hooks"] as? [[String: Any]] {
				if innerHooks.contains(where: { ($0["command"] as? String) == wrapperPath }) {
					return true
				}
			}
		}
		return false
	}

	private static func readSettings() throws -> [String: Any]? {
		let url = settingsURL
		guard FileManager.default.fileExists(atPath: url.path) else { return nil }
		let data = try Data(contentsOf: url)
		guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw ClaudeHookInstallerError.invalidJSON("File exists but is not a JSON object")
		}
		return obj
	}

	private static func readOrCreateSettings() throws -> [String: Any] {
		let url = settingsURL
		if !FileManager.default.fileExists(atPath: url.path) {
			return [:]
		}
		let data = try Data(contentsOf: url)
		if data.isEmpty { return [:] }
		guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw ClaudeHookInstallerError.invalidJSON("File exists but is not a JSON object — refusing to overwrite")
		}
		return obj
	}

	private static func writeSettings(_ settings: [String: Any]) throws {
		let url = settingsURL
		let dir = url.deletingLastPathComponent()
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

		// First-install backup: copy settings.json to settings.json.susurro-bak if it exists
		// and no backup yet exists (preserve the pristine original).
		let bakURL = url.deletingLastPathComponent().appending(path: "settings.json.susurro-bak")
		if FileManager.default.fileExists(atPath: url.path) &&
		   !FileManager.default.fileExists(atPath: bakURL.path) {
			try FileManager.default.copyItem(at: url, to: bakURL)
		}

		let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])

		// Atomic write: write to a per-call temp file (UUID avoids races between
		// concurrent install/uninstall calls sharing the same directory), then rename.
		let tmpURL = url.deletingLastPathComponent()
			.appending(path: "settings.json.susurro-tmp-\(UUID().uuidString)")
		do {
			try data.write(to: tmpURL, options: .atomic)
			_ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
		} catch {
			// Clean up temp file on failure
			try? FileManager.default.removeItem(at: tmpURL)
			throw ClaudeHookInstallerError.writeFailure(error.localizedDescription)
		}
	}

	private static func installWrapper() throws {
		let fm = FileManager.default
		let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		let hooksDir = support.appending(path: "Susurro/hooks")
		try fm.createDirectory(at: hooksDir, withIntermediateDirectories: true)

		// Source: stop.sh in app bundle Resources/hooks/
		guard let bundleSource = Bundle.main.url(forResource: "stop", withExtension: "sh") else {
			throw ClaudeHookInstallerError.writeFailure("stop.sh not found in app bundle Resources/")
		}

		let dest = hooksDir.appending(path: "stop.sh")
		if fm.fileExists(atPath: dest.path) {
			try fm.removeItem(at: dest)
		}
		try fm.copyItem(at: bundleSource, to: dest)

		// Make executable
		try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
	}
}
