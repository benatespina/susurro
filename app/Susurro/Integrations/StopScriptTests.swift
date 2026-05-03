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
