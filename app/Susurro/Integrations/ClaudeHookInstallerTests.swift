import Testing
import Foundation
@testable import Susurro

@Suite("ClaudeHookInstaller patch/unpatch")
struct ClaudeHookInstallerTests {
	let wrapperPath = "/Library/Application Support/Susurro/hooks/stop.sh"

	// 1. Patch empty settings -> valid hook structure
	@Test func patchEmptySettings() {
		let result = ClaudeHookInstaller.patch([:], wrapperPath: wrapperPath)

		let hooks = result["hooks"] as? [String: Any]
		#expect(hooks != nil)

		let stopArray = hooks?["Stop"] as? [[String: Any]]
		#expect(stopArray?.count == 1)

		let entry = stopArray?.first
		#expect(entry?["matcher"] as? String == "*")

		let innerHooks = entry?["hooks"] as? [[String: Any]]
		#expect(innerHooks?.count == 1)
		#expect(innerHooks?.first?["type"] as? String == "command")
		#expect(innerHooks?.first?["command"] as? String == wrapperPath)
	}

	// 2. Patch settings already containing our hook -> unchanged (idempotent)
	@Test func patchIdempotent() {
		let first = ClaudeHookInstaller.patch([:], wrapperPath: wrapperPath)
		let second = ClaudeHookInstaller.patch(first, wrapperPath: wrapperPath)

		let stopAfterFirst = (first["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
		let stopAfterSecond = (second["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
		#expect(stopAfterFirst?.count == 1)
		#expect(stopAfterSecond?.count == 1)
	}

	// 3. Patch settings with unrelated hooks.Stop entries -> ours appended, theirs preserved
	@Test func patchPreservesUnrelatedStopEntries() {
		let unrelated: [String: Any] = [
			"matcher": "*",
			"hooks": [["type": "command", "command": "/usr/local/bin/other-hook"] as [String: Any]]
		]
		let base: [String: Any] = ["hooks": ["Stop": [unrelated]]]

		let result = ClaudeHookInstaller.patch(base, wrapperPath: wrapperPath)
		let stopArray = (result["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]

		#expect(stopArray?.count == 2)

		let commands = stopArray?.compactMap { entry -> String? in
			(entry["hooks"] as? [[String: Any]])?.first?["command"] as? String
		}
		#expect(commands?.contains("/usr/local/bin/other-hook") == true)
		#expect(commands?.contains(wrapperPath) == true)
	}

	// 4. Patch settings with unrelated top-level keys -> top-level keys preserved
	@Test func patchPreservesTopLevelKeys() {
		let base: [String: Any] = ["someOtherKey": "someValue", "numericKey": 42]
		let result = ClaudeHookInstaller.patch(base, wrapperPath: wrapperPath)

		#expect(result["someOtherKey"] as? String == "someValue")
		#expect(result["numericKey"] as? Int == 42)
	}

	// 5. Unpatch settings with only our hook -> no hooks key remains
	@Test func unpatchRemovesHooksKey() {
		let patched = ClaudeHookInstaller.patch([:], wrapperPath: wrapperPath)
		let result = ClaudeHookInstaller.unpatch(patched, wrapperPath: wrapperPath)

		#expect(result["hooks"] == nil)
	}

	// 6. Unpatch with our hook + 2 unrelated hooks -> our hook removed, both unrelated preserved
	@Test func unpatchSurgical() {
		let unrelated1: [String: Any] = [
			"matcher": "*.py",
			"hooks": [["type": "command", "command": "/usr/local/bin/hook-a"] as [String: Any]]
		]
		let unrelated2: [String: Any] = [
			"matcher": "*.ts",
			"hooks": [["type": "command", "command": "/usr/local/bin/hook-b"] as [String: Any]]
		]
		let ours: [String: Any] = [
			"matcher": "*",
			"hooks": [["type": "command", "command": wrapperPath] as [String: Any]]
		]
		let base: [String: Any] = ["hooks": ["Stop": [unrelated1, ours, unrelated2]]]

		let result = ClaudeHookInstaller.unpatch(base, wrapperPath: wrapperPath)
		let stopArray = (result["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]

		#expect(stopArray?.count == 2)

		let commands = stopArray?.compactMap { entry -> String? in
			(entry["hooks"] as? [[String: Any]])?.first?["command"] as? String
		}
		#expect(commands?.contains("/usr/local/bin/hook-a") == true)
		#expect(commands?.contains("/usr/local/bin/hook-b") == true)
		#expect(commands?.contains(wrapperPath) == false)

		let matchers = stopArray?.compactMap { $0["matcher"] as? String }
		#expect(matchers?.contains("*.py") == true)
		#expect(matchers?.contains("*.ts") == true)
	}

	// 7. Unpatch: single outer Stop entry sharing multiple inner commands -> only ours removed
	@Test func unpatchPreservesUnrelatedInnerCommandsInSharedOuterEntry() {
		let mixed: [String: Any] = [
			"matcher": "*.py",
			"hooks": [
				["type": "command", "command": "/usr/local/bin/other"] as [String: Any],
				["type": "command", "command": wrapperPath] as [String: Any],
			]
		]
		let base: [String: Any] = ["hooks": ["Stop": [mixed]]]
		let result = ClaudeHookInstaller.unpatch(base, wrapperPath: wrapperPath)
		let stopArray = (result["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
		#expect(stopArray?.count == 1)
		let remaining = stopArray?.first?["hooks"] as? [[String: Any]]
		#expect(remaining?.count == 1)
		#expect(remaining?.first?["command"] as? String == "/usr/local/bin/other")
	}

	// 8. Unpatch: non-Stop hook types are untouched even if they point at wrapperPath
	@Test func unpatchLeavesNonStopHookTypesUntouched() {
		let preToolUseHook: [String: Any] = [
			"matcher": "*",
			"hooks": [["type": "command", "command": wrapperPath] as [String: Any]]
		]
		let base: [String: Any] = ["hooks": [
			"Stop": [["matcher": "*", "hooks": [["type": "command", "command": wrapperPath] as [String: Any]]] as [String: Any]],
			"PreToolUse": [preToolUseHook],
		]]
		let result = ClaudeHookInstaller.unpatch(base, wrapperPath: wrapperPath)
		let preToolArray = (result["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
		#expect(preToolArray?.count == 1)
		let cmd = (preToolArray?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
		#expect(cmd == wrapperPath)
	}

	// 9. Unpatch settings without our hook -> unchanged
	@Test func unpatchNoOp() {
		let unrelated: [String: Any] = [
			"matcher": "*",
			"hooks": [["type": "command", "command": "/usr/local/bin/other"] as [String: Any]]
		]
		let base: [String: Any] = [
			"someKey": "someValue",
			"hooks": ["Stop": [unrelated]]
		]

		let result = ClaudeHookInstaller.unpatch(base, wrapperPath: wrapperPath)
		let stopArray = (result["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]

		#expect(stopArray?.count == 1)
		#expect(result["someKey"] as? String == "someValue")
	}
}
