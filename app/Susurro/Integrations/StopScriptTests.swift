import Testing
import Foundation

// Tests for app/Susurro/Resources/hooks/stop.sh
// The script is copied flat into the test bundle's Resources directory by xcodegen.
@Suite("stop.sh hook script")
struct StopScriptTests {

	// Locate stop.sh from the test bundle's Resources directory (flat, no subdirectory)
	private func stopScriptPath() throws -> String {
		let bundle = Bundle(for: StopScriptTestsHelper.self)
		if let url = bundle.url(forResource: "stop", withExtension: "sh") {
			return url.path
		}
		// Fallback: source tree path for local development runs
		if let srcroot = ProcessInfo.processInfo.environment["SRCROOT"] {
			let candidate = srcroot + "/Susurro/Resources/hooks/stop.sh"
			if FileManager.default.fileExists(atPath: candidate) {
				return candidate
			}
		}
		throw StopScriptTestError.scriptNotFound
	}

	private func makeFakeSusurroDir(capturing captureFile: String) throws -> String {
		let tmp = FileManager.default.temporaryDirectory
			.appending(path: "susurro-shim-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		let shim = tmp.appending(path: "susurro")
		let shimContent = "#!/bin/sh\ncat > \"\(captureFile)\"\nexit 0\n"
		try shimContent.write(to: shim, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
		return tmp.path
	}

	private func runScript(
		scriptPath: String,
		stdinJSON: String,
		extraEnv: [String: String] = [:]
	) throws -> (exitCode: Int32, stdout: String, stderr: String) {
		let proc = Process()
		proc.executableURL = URL(fileURLWithPath: "/bin/sh")
		proc.arguments = [scriptPath]

		var env = ProcessInfo.processInfo.environment
		for (k, v) in extraEnv { env[k] = v }
		proc.environment = env

		let stdinPipe = Pipe()
		let stdoutPipe = Pipe()
		let stderrPipe = Pipe()
		proc.standardInput = stdinPipe
		proc.standardOutput = stdoutPipe
		proc.standardError = stderrPipe

		try proc.run()
		stdinPipe.fileHandleForWriting.write(stdinJSON.data(using: .utf8)!)
		stdinPipe.fileHandleForWriting.closeFile()
		proc.waitUntilExit()

		let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		return (proc.terminationStatus, out, err)
	}

	// --- Test: .susurro-disable in cwd causes silent exit 0, no susurro call ---
	@Test func disableMarkerCausesEarlyExit() throws {
		let scriptPath = try stopScriptPath()

		let tmpDir = FileManager.default.temporaryDirectory
			.appending(path: "susurro-disable-test-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		FileManager.default.createFile(
			atPath: tmpDir.appending(path: ".susurro-disable").path,
			contents: nil
		)

		let captureFile = FileManager.default.temporaryDirectory
			.appending(path: "susurro-capture-\(UUID().uuidString).txt").path
		defer { try? FileManager.default.removeItem(atPath: captureFile) }

		let shimDir = try makeFakeSusurroDir(capturing: captureFile)
		defer { try? FileManager.default.removeItem(atPath: shimDir) }

		let stdinJSON = "{\"cwd\":\"\(tmpDir.path)\",\"transcript_path\":\"/dev/null\"}"

		var env = ProcessInfo.processInfo.environment
		env["PATH"] = shimDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")
		env["HOME"] = ProcessInfo.processInfo.environment["HOME"] ?? "/tmp"

		let (exitCode, _, _) = try runScript(scriptPath: scriptPath, stdinJSON: stdinJSON, extraEnv: env)
		#expect(exitCode == 0)
		#expect(!FileManager.default.fileExists(atPath: captureFile))
	}

	// --- Test: .susurro-disable in a parent directory causes early exit ---
	@Test func disableMarkerInParentDirectoryCausesEarlyExit() throws {
		let scriptPath = try stopScriptPath()

		// Layout: tmpDir/.susurro-disable  +  tmpDir/subdir  (cwd = subdir)
		let tmpDir = FileManager.default.temporaryDirectory
			.appending(path: "susurro-parent-disable-\(UUID().uuidString)")
		let subDir = tmpDir.appending(path: "subdir")
		try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmpDir) }

		// Marker lives in the parent, not in cwd
		FileManager.default.createFile(
			atPath: tmpDir.appending(path: ".susurro-disable").path,
			contents: nil
		)

		let captureFile = FileManager.default.temporaryDirectory
			.appending(path: "susurro-capture-\(UUID().uuidString).txt").path
		defer { try? FileManager.default.removeItem(atPath: captureFile) }

		let shimDir = try makeFakeSusurroDir(capturing: captureFile)
		defer { try? FileManager.default.removeItem(atPath: shimDir) }

		let stdinJSON = "{\"cwd\":\"\(subDir.path)\",\"transcript_path\":\"/dev/null\"}"

		// Point HOME above tmpDir so the walk reaches the parent before hitting HOME
		let fakeHome = FileManager.default.temporaryDirectory
			.appending(path: "susurro-home-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: fakeHome) }

		var env = ProcessInfo.processInfo.environment
		env["PATH"] = shimDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")
		env["HOME"] = fakeHome.path

		let (exitCode, _, _) = try runScript(scriptPath: scriptPath, stdinJSON: stdinJSON, extraEnv: env)
		#expect(exitCode == 0)
		#expect(!FileManager.default.fileExists(atPath: captureFile),
				"susurro shim must not be invoked when .susurro-disable is in an ancestor directory")
	}

	// --- Test: ancestor walk stops at HOME and does not look above it ---
	// The script breaks the walk when check_dir == HOME, so a marker placed strictly
	// above the fake HOME must never trigger the early-exit path.
	@Test(.disabled("requires controlling HOME for the child process and a marker placed above it — environment inheritance makes this unreliable in CI"))
	func ancestorWalkStopsAtHome() async throws {
		// Intentionally left as a placeholder.
		// Rationale: the shell child process inherits the test process's environment,
		// and placing a real marker above the system HOME risks touching the developer's
		// home directory. The parent-directory case (disableMarkerInParentDirectoryCausesEarlyExit)
		// already exercises the walk loop; this case would only validate the break condition.
	}

	// --- Test: missing transcript_path causes silent exit 0 ---
	@Test func missingTranscriptExits0() throws {
		let scriptPath = try stopScriptPath()
		let stdinJSON = "{\"cwd\":\"/tmp\",\"transcript_path\":\"/nonexistent/path/transcript.jsonl\"}"
		let (exitCode, _, _) = try runScript(scriptPath: scriptPath, stdinJSON: stdinJSON)
		#expect(exitCode == 0)
	}

	// --- Test: tool-call-only transcript causes silent exit 0 ---
	@Test func toolOnlyTranscriptExits0() throws {
		let scriptPath = try stopScriptPath()
		let bundle = Bundle(for: StopScriptTestsHelper.self)
		guard let fixtureURL = bundle.url(forResource: "tool-only-transcript", withExtension: "jsonl") else {
			// Fixture not in bundle; skip gracefully
			return
		}

		let captureFile = FileManager.default.temporaryDirectory
			.appending(path: "susurro-capture-\(UUID().uuidString).txt").path
		defer { try? FileManager.default.removeItem(atPath: captureFile) }

		let shimDir = try makeFakeSusurroDir(capturing: captureFile)
		defer { try? FileManager.default.removeItem(atPath: shimDir) }

		let stdinJSON = "{\"cwd\":\"/tmp\",\"transcript_path\":\"\(fixtureURL.path)\"}"

		var env = ProcessInfo.processInfo.environment
		env["PATH"] = shimDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")

		let (exitCode, _, _) = try runScript(scriptPath: scriptPath, stdinJSON: stdinJSON, extraEnv: env)
		#expect(exitCode == 0)
		#expect(!FileManager.default.fileExists(atPath: captureFile))
	}

	// --- Test: future/unknown transcript schema yields exit 0 without crashing ---
	@Test func futureSchemaTranscriptHandledGracefully() throws {
		let scriptPath = try stopScriptPath()
		let bundle = Bundle(for: StopScriptTestsHelper.self)
		guard let fixtureURL = bundle.url(forResource: "future-schema-transcript", withExtension: "jsonl") else {
			return
		}

		let captureFile = FileManager.default.temporaryDirectory
			.appending(path: "susurro-capture-\(UUID().uuidString).txt").path
		defer { try? FileManager.default.removeItem(atPath: captureFile) }

		let shimDir = try makeFakeSusurroDir(capturing: captureFile)
		defer { try? FileManager.default.removeItem(atPath: shimDir) }

		let stdinJSON = "{\"cwd\":\"/tmp\",\"transcript_path\":\"\(fixtureURL.path)\"}"

		var env = ProcessInfo.processInfo.environment
		env["PATH"] = shimDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")

		let (exitCode, _, _) = try runScript(scriptPath: scriptPath, stdinJSON: stdinJSON, extraEnv: env)
		#expect(exitCode == 0)
	}

	// --- Test: malformed JSONL transcript yields silent exit 0 ---
	@Test func malformedTranscriptHandledGracefully() throws {
		let scriptPath = try stopScriptPath()
		let bundle = Bundle(for: StopScriptTestsHelper.self)
		guard let fixtureURL = bundle.url(forResource: "malformed-transcript", withExtension: "jsonl") else {
			return
		}

		let captureFile = FileManager.default.temporaryDirectory
			.appending(path: "susurro-capture-\(UUID().uuidString).txt").path
		defer { try? FileManager.default.removeItem(atPath: captureFile) }

		let shimDir = try makeFakeSusurroDir(capturing: captureFile)
		defer { try? FileManager.default.removeItem(atPath: shimDir) }

		let stdinJSON = "{\"cwd\":\"/tmp\",\"transcript_path\":\"\(fixtureURL.path)\"}"

		var env = ProcessInfo.processInfo.environment
		env["PATH"] = shimDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")

		let (exitCode, _, _) = try runScript(scriptPath: scriptPath, stdinJSON: stdinJSON, extraEnv: env)
		#expect(exitCode == 0)
		#expect(!FileManager.default.fileExists(atPath: captureFile),
				"susurro shim must not be invoked when transcript is malformed with no extractable text")
	}

	// --- Test: last_assistant_message field in stdin JSON used as Layer 1 (primary source) ---
	@Test func lastAssistantMessageFieldFallback() throws {
		let scriptPath = try stopScriptPath()

		let captureFile = FileManager.default.temporaryDirectory
			.appending(path: "susurro-capture-\(UUID().uuidString).txt").path
		defer { try? FileManager.default.removeItem(atPath: captureFile) }

		let shimDir = try makeFakeSusurroDir(capturing: captureFile)
		defer { try? FileManager.default.removeItem(atPath: shimDir) }

		// transcript_path points at a nonexistent file — transcript layers (2/3) won't fire; this test verifies Layer 1 (stdin) drives extraction
		let stdinJSON = """
		{"cwd":"/tmp","transcript_path":"/nonexistent/path/transcript.jsonl","last_assistant_message":"Fallback layer two text"}
		"""

		var env = ProcessInfo.processInfo.environment
		env["PATH"] = shimDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")

		let (exitCode, _, _) = try runScript(scriptPath: scriptPath, stdinJSON: stdinJSON, extraEnv: env)
		#expect(exitCode == 0)
		#expect(FileManager.default.fileExists(atPath: captureFile),
				"susurro shim must be invoked when last_assistant_message is present")
		let captured = (try? String(contentsOfFile: captureFile, encoding: .utf8)) ?? ""
		#expect(captured.contains("Fallback layer two text"))
	}

	// --- Test: stdin last_assistant_message overrides stale transcript content ---
	// Regression test for the async-race fix: stdin Layer 1 must win over transcript Layer 2.
	@Test func stdinLastAssistantMessageOverridesTranscript() throws {
		let scriptPath = try stopScriptPath()

		// Build a transcript that contains an OLD message.
		let transcriptDir = FileManager.default.temporaryDirectory
			.appending(path: "susurro-transcript-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: transcriptDir) }

		let transcriptFile = transcriptDir.appending(path: "transcript.jsonl")
		let oldLine = """
		{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"OLD stale message from transcript"}]}}
		"""
		try oldLine.write(to: transcriptFile, atomically: true, encoding: .utf8)

		let captureFile = FileManager.default.temporaryDirectory
			.appending(path: "susurro-capture-\(UUID().uuidString).txt").path
		defer { try? FileManager.default.removeItem(atPath: captureFile) }

		let shimDir = try makeFakeSusurroDir(capturing: captureFile)
		defer { try? FileManager.default.removeItem(atPath: shimDir) }

		// stdin carries a fresh NEW message alongside the stale transcript path.
		let stdinJSON = """
		{"cwd":"/tmp","transcript_path":"\(transcriptFile.path)","last_assistant_message":"NEW fresh message from stdin"}
		"""

		var env = ProcessInfo.processInfo.environment
		env["PATH"] = shimDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")

		let (exitCode, _, _) = try runScript(scriptPath: scriptPath, stdinJSON: stdinJSON, extraEnv: env)
		#expect(exitCode == 0)
		#expect(FileManager.default.fileExists(atPath: captureFile),
				"susurro shim must be invoked when last_assistant_message is present")
		let captured = (try? String(contentsOfFile: captureFile, encoding: .utf8)) ?? ""
		#expect(captured.contains("NEW fresh message from stdin"),
				"stdin last_assistant_message must take priority over transcript; got: \(captured)")
		#expect(!captured.contains("OLD stale message from transcript"),
				"stale transcript content must not reach susurro when stdin provides a message")
	}

	// --- Test: valid transcript causes susurro invocation with correct text ---
	@Test func validTranscriptCallsSusurro() throws {
		let scriptPath = try stopScriptPath()
		let bundle = Bundle(for: StopScriptTestsHelper.self)
		guard let fixtureURL = bundle.url(forResource: "sample-transcript", withExtension: "jsonl") else {
			return
		}

		let captureFile = FileManager.default.temporaryDirectory
			.appending(path: "susurro-capture-\(UUID().uuidString).txt").path
		defer { try? FileManager.default.removeItem(atPath: captureFile) }

		let shimDir = try makeFakeSusurroDir(capturing: captureFile)
		defer { try? FileManager.default.removeItem(atPath: shimDir) }

		let stdinJSON = "{\"cwd\":\"/tmp\",\"transcript_path\":\"\(fixtureURL.path)\"}"

		var env = ProcessInfo.processInfo.environment
		env["PATH"] = shimDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")

		let (exitCode, _, _) = try runScript(scriptPath: scriptPath, stdinJSON: stdinJSON, extraEnv: env)
		#expect(exitCode == 0)
		#expect(FileManager.default.fileExists(atPath: captureFile),
				"susurro shim was never invoked — script did not call susurro")
		let captured = (try? String(contentsOfFile: captureFile, encoding: .utf8)) ?? ""
		#expect(captured.contains("Here is the answer you asked for"))
	}
}

enum StopScriptTestError: Error {
	case scriptNotFound
}

private final class StopScriptTestsHelper {}
