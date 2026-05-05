import Foundation
import Network
import os

protocol Speakable: Sendable {
	func read(text: String) async -> Bool
}

extension PlaybackCoordinator: Speakable {}

actor IPCServer {
	private let socketPath: String
	private let speaker: any Speakable
	private let settings: TTSSettings
	private let client: BackendClient
	private var listener: NWListener?
	private(set) var lastSeenCwd: String?

	private static let maxPayload = 1_048_576

	init(
		socketPath: String,
		speaker: any Speakable,
		settings: TTSSettings,
		client: BackendClient = .shared
	) {
		self.socketPath = socketPath
		self.speaker = speaker
		self.settings = settings
		self.client = client
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
		switch result {
		case .data(let payload):
			await dispatch(payload: payload, on: connection)
		case .tooLarge:
			await sendOnce(errorResponse("payload too large"), on: connection)
		case .empty:
			await sendOnce(errorResponse("empty payload"), on: connection)
		}
		connection.cancel()
	}

	private func receiveAll(connection: NWConnection) async -> ReceiveResult {
		final class Box: @unchecked Sendable {
			var data = Data()
			var done = false
		}
		let box = Box()
		return await withCheckedContinuation { continuation in
			func step() {
				connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxPayload + 1) { content, _, isComplete, error in
					guard !box.done else { return }
					if let content { box.data.append(content) }
					if box.data.count > Self.maxPayload {
						box.done = true
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

	// MARK: - Dispatcher

	private func dispatch(payload: Data, on connection: NWConnection) async {
		guard let body = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
			  let cmd = body["cmd"] as? String
		else {
			await sendOnce(errorResponse("invalid json"), on: connection)
			return
		}
		switch cmd {
		case "read":
			await sendOnce(await handleRead(body: body), on: connection)
		case "health":
			await sendOnce(await handleHealth(), on: connection)
		case "tts":
			await sendOnce(await handleTTS(body: body), on: connection)
		case "tts-stream":
			await handleTTSStream(body: body, on: connection)
		case "extract":
			await sendOnce(await handleExtract(body: body), on: connection)
		case "pron-list":
			await sendOnce(await handlePronList(), on: connection)
		case "pron-upsert":
			await sendOnce(await handlePronUpsert(body: body), on: connection)
		case "pron-delete":
			await sendOnce(await handlePronDelete(body: body), on: connection)
		case "pron-candidates":
			await sendOnce(await handlePronCandidates(body: body), on: connection)
		case "pron-preview":
			await sendOnce(await handlePronPreview(body: body), on: connection)
		case "stop":
			await sendOnce(await handleStop(), on: connection)
		default:
			await sendOnce(errorResponse("unknown command"), on: connection)
		}
	}

	// MARK: - Command Handlers

	private func handleRead(body: [String: Any]) async -> Data {
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

		let spoke = await speaker.read(text: filtered)
		if spoke {
			AppLogger.claudeSpoke(charCount: filtered.count)
			return spokeResponse(true)
		} else {
			AppLogger.claudeSkipped(reason: "playback failed")
			return errorResponse("playback failed")
		}
	}

	private func handleHealth() async -> Data {
		let status = await client.health()
		let ready = status == .ready
		return okResponse(data: ["ready": ready])
	}

	private func handleTTS(body: [String: Any]) async -> Data {
		guard let text = body["text"] as? String else {
			return errorResponse("missing text")
		}
		let language = body["language"] as? String
		do {
			let audioData = try await client.tts(text: text, language: language)
			let base64 = audioData.base64EncodedString()
			return okResponse(data: ["audioBase64": base64, "mimeType": "audio/mpeg"])
		} catch {
			return errorResponse(error.localizedDescription)
		}
	}

	private func handleTTSStream(body: [String: Any], on connection: NWConnection) async {
		guard let text = body["text"] as? String else {
			await sendOnce(errorResponse("missing text"), on: connection)
			return
		}
		let language = body["language"] as? String

		let header = "{\"ok\":true,\"stream\":true}\n"
		guard let headerData = header.data(using: .utf8) else { return }
		await send(headerData, on: connection)

		do {
			for try await chunk in client.streamingTTS(text: text, language: language) {
				let length = UInt32(chunk.count).bigEndian
				var frame = Data(capacity: 4 + chunk.count)
				withUnsafeBytes(of: length) { frame.append(contentsOf: $0) }
				frame.append(chunk)
				await send(frame, on: connection)
			}
		} catch {
			AppLogger.app.error("IPCServer tts-stream error: \(error, privacy: .public)")
			// Close without terminator — caller handles short reads
			return
		}

		// Write terminator
		await send(Data([0x00, 0x00, 0x00, 0x00]), on: connection)
	}

	private func handleExtract(body: [String: Any]) async -> Data {
		guard let url = body["url"] as? String else {
			return errorResponse("missing url")
		}
		do {
			let article = try await client.extract(url: url)
			var dataDict: [String: Any] = [
				"text": article.text,
				"url": article.url
			]
			if let title = article.title { dataDict["title"] = title }
			if let lang = article.language { dataDict["language"] = lang }
			return okResponse(data: dataDict)
		} catch {
			return errorResponse(error.localizedDescription)
		}
	}

	private func handlePronList() async -> Data {
		let all = await client.listPronunciations()
		return okResponse(data: all)
	}

	private func handlePronUpsert(body: [String: Any]) async -> Data {
		guard let language = body["language"] as? String,
			  let word = body["word"] as? String,
			  let replacement = body["replacement"] as? String
		else {
			return errorResponse("missing language, word, or replacement")
		}
		do {
			try await client.upsertPronunciation(language: language, word: word, replacement: replacement)
			return okResponse(data: [:])
		} catch {
			return errorResponse(error.localizedDescription)
		}
	}

	private func handlePronDelete(body: [String: Any]) async -> Data {
		guard let language = body["language"] as? String,
			  let word = body["word"] as? String
		else {
			return errorResponse("missing language or word")
		}
		do {
			let deleted = try await client.deletePronunciation(language: language, word: word)
			return okResponse(data: ["deleted": deleted])
		} catch {
			return errorResponse(error.localizedDescription)
		}
	}

	private func handlePronCandidates(body: [String: Any]) async -> Data {
		guard let word = body["word"] as? String,
			  let language = body["language"] as? String
		else {
			return errorResponse("missing word or language")
		}
		let candidates = await client.pronunciationCandidates(word: word, language: language)
		do {
			let encoded = try JSONEncoder().encode(candidates)
			guard let arr = try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]] else {
				return errorResponse("encoding error")
			}
			return okResponse(data: ["candidates": arr])
		} catch {
			return errorResponse(error.localizedDescription)
		}
	}

	private func handlePronPreview(body: [String: Any]) async -> Data {
		guard let ssml = body["ssml"] as? String,
			  let language = body["language"] as? String
		else {
			return errorResponse("missing ssml or language")
		}
		do {
			let audioData = try await client.previewSSML(ssml: ssml, language: language)
			let base64 = audioData.base64EncodedString()
			return okResponse(data: ["audioBase64": base64, "mimeType": "audio/mpeg"])
		} catch BackendError.azureNotConfigured {
			return errorResponse("azure not configured")
		} catch {
			return errorResponse(error.localizedDescription)
		}
	}

	private func handleStop() async -> Data {
		client.stop()
		return okResponse(data: [:])
	}

	// MARK: - Send Helpers

	private func sendOnce(_ data: Data, on connection: NWConnection) async {
		await send(data, on: connection)
	}

	private func send(_ data: Data, on connection: NWConnection) async {
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			connection.send(content: data, completion: .contentProcessed { _ in
				continuation.resume()
			})
		}
	}

	// MARK: - Response Helpers

	private func errorResponse(_ message: String) -> Data {
		let obj: [String: Any] = ["ok": false, "error": message]
		return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
	}

	private func spokeResponse(_ spoke: Bool) -> Data {
		let obj: [String: Any] = ["ok": true, "spoke": spoke]
		return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
	}

	private func okResponse(data: [String: Any]) -> Data {
		let obj: [String: Any] = ["ok": true, "data": data]
		return (try? JSONSerialization.data(withJSONObject: obj)) ?? (try? JSONSerialization.data(withJSONObject: ["ok": true])) ?? Data()
	}
}
