import Foundation
import Network
import Testing
@testable import Susurro

// MARK: - Fake speaker

private actor FakeSpeaker: Speakable {
	private(set) var calls: [String] = []
	let shouldSucceed: Bool

	init(shouldSucceed: Bool = true) {
		self.shouldSucceed = shouldSucceed
	}

	func read(text: String) async -> Bool {
		if shouldSucceed {
			calls.append(text)
		}
		return shouldSucceed
	}

	func callCount() -> Int { calls.count }
	func lastCall() -> String? { calls.last }
}

// MARK: - Helpers

private func tempSocketPath() -> String {
	NSTemporaryDirectory() + "ipc-test-\(UUID().uuidString).sock"
}

@MainActor
private func makeSettings(autoReadEnabled: Bool) -> TTSSettings {
	let key = "claude.autoRead.enabled"
	UserDefaults.standard.set(autoReadEnabled, forKey: key)
	return TTSSettings()
}

private final class OnceResumer: @unchecked Sendable {
	private var continuation: CheckedContinuation<Data, Error>?
	private var connection: NWConnection?

	init(_ continuation: CheckedContinuation<Data, Error>, connection: NWConnection) {
		self.continuation = continuation
		self.connection = connection
	}

	func finish(_ result: Result<Data, Error>) {
		guard let cont = continuation else { return }
		continuation = nil
		connection?.cancel()
		connection = nil
		cont.resume(with: result)
	}
}

private func sendAndReceive(socketPath: String, payload: Data) async throws -> Data {
	try await withCheckedThrowingContinuation { continuation in
		let connection = NWConnection(
			to: NWEndpoint.unix(path: socketPath),
			using: NWParameters.tcp
		)
		let resumer = OnceResumer(continuation, connection: connection)

		connection.stateUpdateHandler = { connState in
			switch connState {
			case .ready:
				connection.send(content: payload, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
					if let error {
						resumer.finish(.failure(error))
						return
					}
					receiveAll(connection: connection) { result in
						resumer.finish(result)
					}
				})
			case .failed(let error):
				resumer.finish(.failure(error))
			case .cancelled:
				resumer.finish(.failure(URLError(.cancelled)))
			default:
				break
			}
		}

		connection.start(queue: .global(qos: .utility))
	}
}

private func receiveAll(connection: NWConnection, accumulated: Data = Data(), completion: @escaping (Result<Data, Error>) -> Void) {
	connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
		var data = accumulated
		if let content { data.append(content) }
		if isComplete || error != nil {
			completion(.success(data))
		} else {
			receiveAll(connection: connection, accumulated: data, completion: completion)
		}
	}
}

private func sendJSON(socketPath: String, object: [String: Any]) async throws -> [String: Any] {
	let payload = try JSONSerialization.data(withJSONObject: object)
	let responseData = try await sendAndReceive(socketPath: socketPath, payload: payload)
	guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
		throw URLError(.cannotParseResponse)
	}
	return json
}

// MARK: - Tests

@Suite("IPCServer", .serialized)
struct IPCServerTests {

	@Test("happy path: plain text speaks and returns spoke:true")
	func happyPath() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "read", "text": "Hello world"])
		#expect(resp["ok"] as? Bool == true)
		#expect(resp["spoke"] as? Bool == true)

		let count = await speaker.callCount()
		#expect(count == 1)
		let last = await speaker.lastCall()
		#expect(last == "Hello world")
	}

	@Test("filter returns empty: spoke:false, speaker not called")
	func filterEmpty() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		// Only a code block — filter will strip everything, leaving empty string
		let resp = try await sendJSON(socketPath: path, object: ["cmd": "read", "text": "```swift\nlet x = 1\n```"])
		#expect(resp["ok"] as? Bool == true)
		#expect(resp["spoke"] as? Bool == false)

		let count = await speaker.callCount()
		#expect(count == 0)
	}

	@Test("autoRead disabled: spoke:false, speaker not called")
	func autoReadDisabled() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: false)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "read", "text": "Hello world"])
		#expect(resp["ok"] as? Bool == true)
		#expect(resp["spoke"] as? Bool == false)

		let count = await speaker.callCount()
		#expect(count == 0)
	}

	@Test("unknown cmd: ok:false with error")
	func unknownCommand() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "speak", "text": "Hello"])
		#expect(resp["ok"] as? Bool == false)
		#expect(resp["error"] as? String == "unknown command")
	}

	@Test("malformed JSON: ok:false with error")
	func malformedJSON() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let badPayload = Data("not json at all {{{".utf8)
		let responseData = try await sendAndReceive(socketPath: path, payload: badPayload)
		let resp = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
		#expect(resp?["ok"] as? Bool == false)
		#expect(resp?["error"] as? String == "invalid json")
	}

	@Test("payload over 1 MB: ok:false payload too large")
	func payloadTooLarge() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let bigText = String(repeating: "A", count: 1_048_577)
		let bigPayload = try JSONSerialization.data(withJSONObject: ["cmd": "read", "text": bigText])
		let responseData = try await sendAndReceive(socketPath: path, payload: bigPayload)
		let resp = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
		#expect(resp?["ok"] as? Bool == false)
		#expect(resp?["error"] as? String == "payload too large")
	}

	@Test("two messages in quick succession both reach speaker")
	func twoMessagesInQuickSuccession() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		async let resp1 = sendJSON(socketPath: path, object: ["cmd": "read", "text": "First message"])
		try await Task.sleep(for: .milliseconds(200))
		async let resp2 = sendJSON(socketPath: path, object: ["cmd": "read", "text": "Second message"])

		let (r1, r2) = try await (resp1, resp2)
		#expect(r1["ok"] as? Bool == true)
		#expect(r1["spoke"] as? Bool == true)
		#expect(r2["ok"] as? Bool == true)
		#expect(r2["spoke"] as? Bool == true)

		try await Task.sleep(for: .milliseconds(100))
		let count = await speaker.callCount()
		#expect(count == 2)
	}

	@Test("stale socket from prior crash is replaced on start")
	func staleSocketIsReplacedOnStart() async throws {
		let path = tempSocketPath()
		try "stale".write(toFile: path, atomically: true, encoding: .utf8)
		#expect(FileManager.default.fileExists(atPath: path))

		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "read", "text": "Hello"])
		#expect(resp["ok"] as? Bool == true)
		#expect(resp["spoke"] as? Bool == true)
	}

	@Test("stop removes socket file")
	func stopRemovesSocketFile() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()

		try await Task.sleep(for: .milliseconds(50))
		#expect(FileManager.default.fileExists(atPath: path))

		await server.stop()
		#expect(!FileManager.default.fileExists(atPath: path))
	}

	@Test("cwd field is stored in lastSeenCwd")
	func cwdIsStoredAsLastSeenCwd() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(
			socketPath: path,
			object: ["cmd": "read", "text": "hello", "cwd": "/tmp/testproj"]
		)
		#expect(resp["ok"] as? Bool == true)

		let stored = await server.lastSeenCwd
		#expect(stored == "/tmp/testproj")
	}

	@Test("cwd field absent leaves lastSeenCwd nil")
	func cwdAbsentLeavesLastSeenCwdNil() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(
			socketPath: path,
			object: ["cmd": "read", "text": "hello"]
		)
		#expect(resp["ok"] as? Bool == true)

		let stored = await server.lastSeenCwd
		#expect(stored == nil)
	}

	@Test("cwd field updates lastSeenCwd on subsequent request")
	func cwdUpdatesOnSubsequentRequest() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		_ = try await sendJSON(
			socketPath: path,
			object: ["cmd": "read", "text": "first", "cwd": "/tmp/proj-a"]
		)
		_ = try await sendJSON(
			socketPath: path,
			object: ["cmd": "read", "text": "second", "cwd": "/tmp/proj-b"]
		)

		let stored = await server.lastSeenCwd
		#expect(stored == "/tmp/proj-b")
	}

	@Test("speaker failure: ok:false with playback failed error")
	func speakerFailure() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker(shouldSucceed: false)
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "read", "text": "Hello world"])
		#expect(resp["ok"] as? Bool == false)
		#expect(resp["error"] as? String == "playback failed")

		let count = await speaker.callCount()
		#expect(count == 0)
	}

	// MARK: - New command tests

	@Test("cmd health: returns ok:true with data.ready bool")
	func healthCommand() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let client = BackendClient(
			extractor: ArticleExtractor(),
			pronunciations: PronunciationStore(fileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "pron-\(UUID().uuidString).json"))
		)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings, client: client)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "health"])
		#expect(resp["ok"] as? Bool == true)
		let data = resp["data"] as? [String: Any]
		#expect(data != nil)
		#expect(data?["ready"] is Bool)
	}

	@Test("cmd tts: returns ok:true with audioBase64 for mocked provider")
	func ttsCommand() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let fixedAudio = Data([0xAA, 0xBB, 0xCC])
		let client = BackendClient(
			extractor: ArticleExtractor(),
			pronunciations: PronunciationStore(fileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "pron-\(UUID().uuidString).json")),
			ttsOverride: { _, _ in fixedAudio }
		)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings, client: client)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "tts", "text": "Hello"])
		#expect(resp["ok"] as? Bool == true)
		let data = resp["data"] as? [String: Any]
		#expect(data?["audioBase64"] as? String == fixedAudio.base64EncodedString())
		#expect(data?["mimeType"] as? String == "audio/mpeg")
	}

	@Test("cmd tts: missing text returns ok:false")
	func ttsCommandMissingText() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "tts"])
		#expect(resp["ok"] as? Bool == false)
	}

	@Test("cmd tts-stream: header + framed chunks + terminator")
	func ttsStreamCommand() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let fixedAudio = Data(repeating: 0xFF, count: 16)
		let client = BackendClient(
			extractor: ArticleExtractor(),
			pronunciations: PronunciationStore(fileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "pron-\(UUID().uuidString).json")),
			ttsOverride: { _, _ in fixedAudio }
		)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings, client: client)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let payload = try JSONSerialization.data(withJSONObject: ["cmd": "tts-stream", "text": "Hello stream"])
		let raw = try await sendAndReceive(socketPath: path, payload: payload)

		// Parse header line
		guard let newlineRange = raw.range(of: Data("\n".utf8)) else {
			Issue.record("No newline found in tts-stream response")
			return
		}
		let headerData = raw[raw.startIndex ..< newlineRange.lowerBound]
		let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any]
		#expect(header?["ok"] as? Bool == true)
		#expect(header?["stream"] as? Bool == true)

		// Parse framed body
		var pos = raw.index(after: newlineRange.lowerBound)
		var chunks: [Data] = []
		while pos < raw.endIndex {
			let remaining = raw.distance(from: pos, to: raw.endIndex)
			guard remaining >= 4 else { break }
			let lenBytes = raw[pos ..< raw.index(pos, offsetBy: 4)]
			let length = lenBytes.withUnsafeBytes { ptr in
				UInt32(bigEndian: ptr.loadUnaligned(as: UInt32.self))
			}
			if length == 0 {
				// terminator
				break
			}
			pos = raw.index(pos, offsetBy: 4)
			guard raw.distance(from: pos, to: raw.endIndex) >= Int(length) else { break }
			let chunk = raw[pos ..< raw.index(pos, offsetBy: Int(length))]
			chunks.append(Data(chunk))
			pos = raw.index(pos, offsetBy: Int(length))
		}

		#expect(!chunks.isEmpty)
		let totalBytes = chunks.reduce(0) { $0 + $1.count }
		#expect(totalBytes == fixedAudio.count)
	}

	@Test("cmd extract: missing url returns ok:false")
	func extractCommandMissingURL() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "extract"])
		#expect(resp["ok"] as? Bool == false)
	}

	@Test("cmd extract: invalid url returns ok:false")
	func extractCommandInvalidURL() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "extract", "url": "not-a-url"])
		#expect(resp["ok"] as? Bool == false)
	}

	@Test("cmd pron-list: returns ok:true with data dict")
	func pronListCommand() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let pronStore = PronunciationStore(fileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "pron-\(UUID().uuidString).json"))
		let client = BackendClient(extractor: ArticleExtractor(), pronunciations: pronStore)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings, client: client)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "pron-list"])
		#expect(resp["ok"] as? Bool == true)
		#expect(resp["data"] is [String: Any])
	}

	@Test("cmd pron-upsert: stores word and pron-delete removes it")
	func pronUpsertAndDeleteCommands() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let pronStore = PronunciationStore(fileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "pron-\(UUID().uuidString).json"))
		let client = BackendClient(extractor: ArticleExtractor(), pronunciations: pronStore)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings, client: client)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		// Upsert
		let upsertResp = try await sendJSON(socketPath: path, object: [
			"cmd": "pron-upsert",
			"language": "en",
			"word": "testword",
			"replacement": "<phoneme alphabet=\"ipa\" ph=\"tɛstwɜrd\">testword</phoneme>"
		])
		#expect(upsertResp["ok"] as? Bool == true)

		// Verify list contains it
		let listResp = try await sendJSON(socketPath: path, object: ["cmd": "pron-list"])
		let listData = listResp["data"] as? [String: [String: String]]
		#expect(listData?["en"]?["testword"] != nil)

		// Delete
		let deleteResp = try await sendJSON(socketPath: path, object: [
			"cmd": "pron-delete",
			"language": "en",
			"word": "testword"
		])
		#expect(deleteResp["ok"] as? Bool == true)
		let deleteData = deleteResp["data"] as? [String: Any]
		#expect(deleteData?["deleted"] as? Bool == true)
	}

	@Test("cmd pron-candidates: returns candidates array for es word")
	func pronCandidatesCommand() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let pronStore = PronunciationStore(fileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "pron-\(UUID().uuidString).json"))
		let client = BackendClient(extractor: ArticleExtractor(), pronunciations: pronStore)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings, client: client)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: [
			"cmd": "pron-candidates",
			"word": "API",
			"language": "es"
		])
		#expect(resp["ok"] as? Bool == true)
		let data = resp["data"] as? [String: Any]
		let candidates = data?["candidates"] as? [[String: Any]]
		#expect(candidates != nil)
		#expect((candidates?.count ?? 0) > 0)
	}

	@Test("cmd pron-preview: without Azure returns azure not configured error")
	func pronPreviewWithoutAzure() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		// Default client uses Edge provider, not Azure — preview should fail
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: [
			"cmd": "pron-preview",
			"ssml": "<phoneme alphabet=\"ipa\" ph=\"ˈei.pi.ai\">API</phoneme>",
			"language": "es"
		])
		#expect(resp["ok"] as? Bool == false)
		#expect(resp["error"] as? String == "azure not configured")
	}

	@Test("cmd stop: returns ok:true")
	func stopCommand() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "stop"])
		#expect(resp["ok"] as? Bool == true)
	}

	@Test("cmd unknown: returns ok:false with unknown command error")
	func unknownCommandExtended() async throws {
		let path = tempSocketPath()
		let speaker = FakeSpeaker()
		let settings = await makeSettings(autoReadEnabled: true)
		let server = IPCServer(socketPath: path, speaker: speaker, settings: settings)
		try await server.start()
		defer { Task { await server.stop() } }

		try await Task.sleep(for: .milliseconds(50))

		let resp = try await sendJSON(socketPath: path, object: ["cmd": "totally-unknown"])
		#expect(resp["ok"] as? Bool == false)
		#expect(resp["error"] as? String == "unknown command")
	}
}
