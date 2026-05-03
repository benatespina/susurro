import Foundation
import Network
import Testing
@testable import Susurro

// MARK: - Fake speaker

private actor FakeSpeaker: Speakable {
	private(set) var calls: [String] = []

	func read(text: String) async {
		calls.append(text)
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
}
