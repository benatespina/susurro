import Foundation
import Network
import os

protocol Speakable: Sendable {
	func read(text: String) async
}

extension PlaybackCoordinator: Speakable {}

actor IPCServer {
	private let socketPath: String
	private let speaker: any Speakable
	private let settings: TTSSettings
	private var listener: NWListener?
	private(set) var lastSeenCwd: String?

	func getLastSeenCwd() async -> String? { lastSeenCwd }

	private static let maxPayload = 1_048_576

	init(socketPath: String, speaker: any Speakable, settings: TTSSettings) {
		self.socketPath = socketPath
		self.speaker = speaker
		self.settings = settings
	}

	func start() throws {
		let socketURL = URL(fileURLWithPath: socketPath)
		try? FileManager.default.createDirectory(
			at: socketURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try? FileManager.default.removeItem(atPath: socketPath)

		let params = NWParameters.tcp
		params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)

		let listener = try NWListener(using: params)
		self.listener = listener

		listener.newConnectionHandler = { [weak self] connection in
			guard let self else { return }
			Task { await self.handle(connection: connection) }
		}

		let path = socketPath
		listener.stateUpdateHandler = { state in
			switch state {
			case .failed(let error):
				AppLogger.app.error("IPCServer listener failed: \(error, privacy: .public)")
			case .ready:
				AppLogger.app.info("IPCServer listening at \(path, privacy: .public)")
			default:
				break
			}
		}

		listener.start(queue: .global(qos: .utility))
	}

	func stop() {
		listener?.cancel()
		listener = nil
		try? FileManager.default.removeItem(atPath: socketPath)
	}

	private enum ReceiveResult {
		case data(Data)
		case tooLarge
		case empty
	}

	private func handle(connection: NWConnection) async {
		connection.start(queue: .global(qos: .utility))

		let result = await receiveAll(connection: connection)

		let response: Data
		switch result {
		case .data(let payload):
			response = await process(payload: payload)
		case .tooLarge:
			response = errorResponse("payload too large")
		case .empty:
			response = errorResponse("invalid json")
		}

		await send(response, on: connection)
		connection.cancel()
	}

	private func receiveAll(connection: NWConnection) async -> ReceiveResult {
		final class Box: @unchecked Sendable {
			var data = Data()
			var done = false
			var tooLarge = false
		}
		let box = Box()
		return await withCheckedContinuation { continuation in
			func step() {
				connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxPayload + 1) { content, _, isComplete, error in
					guard !box.done else { return }
					if let content { box.data.append(content) }
					if box.data.count > Self.maxPayload {
						box.done = true
						box.tooLarge = true
						continuation.resume(returning: .tooLarge)
						return
					}
					if isComplete || error != nil {
						box.done = true
						continuation.resume(returning: box.data.isEmpty ? .empty : .data(box.data))
						return
					}
					step()
				}
			}
			step()
		}
	}

	private func process(payload: Data) async -> Data {
		guard let body = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
			  let cmd = body["cmd"] as? String
		else {
			return errorResponse("invalid json")
		}

		guard cmd == "read" else {
			return errorResponse("unknown command")
		}

		guard let text = body["text"] as? String else {
			return errorResponse("invalid json")
		}

		if let cwd = body["cwd"] as? String, !cwd.isEmpty {
			lastSeenCwd = cwd
		}

		let autoReadEnabled = await MainActor.run { settings.autoReadEnabled }
		guard autoReadEnabled else {
			AppLogger.claudeSkipped(reason: "global toggle off")
			return spokeResponse(false)
		}

		let filtered = ClaudeTextFilter.filter(text)
		guard !filtered.isEmpty else {
			AppLogger.claudeSkipped(reason: "filter empty")
			return spokeResponse(false)
		}

		await speaker.read(text: filtered)
		AppLogger.claudeSpoke(charCount: filtered.count)
		return spokeResponse(true)
	}

	private func send(_ data: Data, on connection: NWConnection) async {
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			connection.send(content: data, completion: .contentProcessed { _ in
				continuation.resume()
			})
		}
	}

	private func errorResponse(_ message: String) -> Data {
		let obj: [String: Any] = ["ok": false, "error": message]
		return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
	}

	private func spokeResponse(_ spoke: Bool) -> Data {
		let obj: [String: Any] = ["ok": true, "spoke": spoke]
		return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
	}
}
