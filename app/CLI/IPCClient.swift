import Foundation
import Network

enum IPCClientError: Error {
	case connectionFailed(String)
	case timeout
	case badResponse
}

let socketPath: String = {
	let appSupport = FileManager.default
		.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
	return appSupport.appendingPathComponent("Susurro/ipc.sock").path
}()

// MARK: - Argument Parsing Utilities

func parseFlag(_ flag: String, in args: [String]) -> String? {
	guard let idx = args.firstIndex(of: flag) else { return nil }
	let valueIdx = args.index(after: idx)
	guard valueIdx < args.endIndex else { return nil }
	let candidate = args[valueIdx]
	guard !candidate.hasPrefix("--") else { return nil }
	return candidate
}

// MARK: - Public API

func sendRead(text: String, cwd: String? = nil) throws -> [String: Any] {
	var body: [String: Any] = ["cmd": "read", "text": text]
	if let cwd, !cwd.isEmpty { body["cwd"] = cwd }
	return try sendCommand(payload: body)
}

func sendHealth() throws -> [String: Any] {
	try sendCommand(payload: ["cmd": "health"])
}

func sendTTS(text: String, language: String?) throws -> [String: Any] {
	var body: [String: Any] = ["cmd": "tts", "text": text]
	if let language { body["language"] = language }
	return try sendCommand(payload: body)
}

func sendTTSStream(text: String, language: String?, into output: FileHandle) throws -> Bool {
	var body: [String: Any] = ["cmd": "tts-stream", "text": text]
	if let language { body["language"] = language }
	let payload = try JSONSerialization.data(withJSONObject: body)

	if !FileManager.default.fileExists(atPath: socketPath) {
		wakeApp()
	}

	let deadline = Date().addingTimeInterval(3.0)
	var delay: Double = 0.2

	while Date() < deadline {
		do {
			return try connectAndStream(payload: payload, into: output)
		} catch {
			let remaining = deadline.timeIntervalSinceNow
			if remaining <= 0 { break }
			Thread.sleep(forTimeInterval: min(delay, remaining))
			delay = min(delay * 2, 0.8)
		}
	}

	throw IPCClientError.timeout
}

func sendExtract(url: String) throws -> [String: Any] {
	try sendCommand(payload: ["cmd": "extract", "url": url])
}

func sendPronList() throws -> [String: Any] {
	try sendCommand(payload: ["cmd": "pron-list"])
}

func sendPronUpsert(language: String, word: String, replacement: String) throws -> [String: Any] {
	try sendCommand(payload: [
		"cmd": "pron-upsert",
		"language": language,
		"word": word,
		"replacement": replacement
	])
}

func sendPronDelete(language: String, word: String) throws -> [String: Any] {
	try sendCommand(payload: ["cmd": "pron-delete", "language": language, "word": word])
}

func sendPronCandidates(word: String, language: String) throws -> [String: Any] {
	try sendCommand(payload: ["cmd": "pron-candidates", "word": word, "language": language])
}

func sendPronPreview(ssml: String, language: String) throws -> [String: Any] {
	try sendCommand(payload: ["cmd": "pron-preview", "ssml": ssml, "language": language])
}

func sendStop() throws -> [String: Any] {
	try sendCommand(payload: ["cmd": "stop"])
}

// MARK: - Private helpers

private func sendCommand(payload: [String: Any]) throws -> [String: Any] {
	let data = try JSONSerialization.data(withJSONObject: payload)

	if !FileManager.default.fileExists(atPath: socketPath) {
		wakeApp()
	}

	let deadline = Date().addingTimeInterval(3.0)
	var delay: Double = 0.2

	while Date() < deadline {
		do {
			return try connectAndSend(payload: data)
		} catch {
			let remaining = deadline.timeIntervalSinceNow
			if remaining <= 0 { break }
			Thread.sleep(forTimeInterval: min(delay, remaining))
			delay = min(delay * 2, 0.8)
		}
	}

	throw IPCClientError.timeout
}

private func wakeApp() {
	let p = Process()
	p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
	p.arguments = ["-g", "-j", "-a", "Susurro"]
	try? p.run()
	Thread.sleep(forTimeInterval: 0.2)
}

private final class TransferBox: @unchecked Sendable {
	var result: Result<Data, Error> = .failure(IPCClientError.connectionFailed("not started"))
}

private func connectAndSend(payload: Data) throws -> [String: Any] {
	let semaphore = DispatchSemaphore(value: 0)
	let box = TransferBox()

	let connection = NWConnection(
		to: NWEndpoint.unix(path: socketPath),
		using: NWParameters.tcp
	)

	connection.stateUpdateHandler = { state in
		switch state {
		case .ready:
			connection.send(
				content: payload,
				contentContext: .finalMessage,
				isComplete: true,
				completion: .contentProcessed { sendErr in
					if let sendErr {
						box.result = .failure(IPCClientError.connectionFailed(sendErr.localizedDescription))
						connection.cancel()
						semaphore.signal()
						return
					}
					receiveAll(connection: connection) { receiveResult in
						box.result = receiveResult
						connection.cancel()
						semaphore.signal()
					}
				}
			)
		case .failed(let error):
			box.result = .failure(IPCClientError.connectionFailed(error.localizedDescription))
			semaphore.signal()
		case .cancelled:
			if case .failure = box.result {} else {
				box.result = .failure(IPCClientError.connectionFailed("cancelled"))
			}
			semaphore.signal()
		default:
			break
		}
	}

	connection.start(queue: .global(qos: .userInitiated))

	let timeout = DispatchTime.now() + .milliseconds(2500)
	if semaphore.wait(timeout: timeout) == .timedOut {
		connection.cancel()
		throw IPCClientError.timeout
	}

	let data = try box.result.get()
	guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
		throw IPCClientError.badResponse
	}
	return json
}

private func connectAndStream(payload: Data, into output: FileHandle) throws -> Bool {
	let semaphore = DispatchSemaphore(value: 0)
	let box = TransferBox()

	let connection = NWConnection(
		to: NWEndpoint.unix(path: socketPath),
		using: NWParameters.tcp
	)

	connection.stateUpdateHandler = { state in
		switch state {
		case .ready:
			connection.send(
				content: payload,
				contentContext: .finalMessage,
				isComplete: true,
				completion: .contentProcessed { sendErr in
					if let sendErr {
						box.result = .failure(IPCClientError.connectionFailed(sendErr.localizedDescription))
						connection.cancel()
						semaphore.signal()
						return
					}
					receiveAllRaw(connection: connection) { receiveResult in
						box.result = receiveResult
						connection.cancel()
						semaphore.signal()
					}
				}
			)
		case .failed(let error):
			box.result = .failure(IPCClientError.connectionFailed(error.localizedDescription))
			semaphore.signal()
		case .cancelled:
			if case .failure = box.result {} else {
				box.result = .failure(IPCClientError.connectionFailed("cancelled"))
			}
			semaphore.signal()
		default:
			break
		}
	}

	connection.start(queue: .global(qos: .userInitiated))

	let timeout = DispatchTime.now() + .milliseconds(30000)
	if semaphore.wait(timeout: timeout) == .timedOut {
		connection.cancel()
		throw IPCClientError.timeout
	}

	let raw = try box.result.get()
	return try parseAndWriteStream(raw: raw, into: output)
}

private func parseAndWriteStream(raw: Data, into output: FileHandle) throws -> Bool {
	// Parse header line: {"ok":true,"stream":true}\n
	guard let newlineRange = raw.range(of: Data("\n".utf8)) else {
		throw IPCClientError.badResponse
	}
	let headerData = raw[raw.startIndex ..< newlineRange.lowerBound]
	guard let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
		  header["ok"] as? Bool == true,
		  header["stream"] as? Bool == true
	else {
		// Might be an error response
		if let errorResp = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
			if errorResp["ok"] as? Bool == false {
				return false
			}
		}
		throw IPCClientError.badResponse
	}

	// Parse framed chunks
	var pos = raw.index(after: newlineRange.lowerBound)
	while pos < raw.endIndex {
		let remaining = raw.distance(from: pos, to: raw.endIndex)
		guard remaining >= 4 else { break }
		let lenBytes = raw[pos ..< raw.index(pos, offsetBy: 4)]
		let length = lenBytes.withUnsafeBytes { ptr in
			UInt32(bigEndian: ptr.loadUnaligned(as: UInt32.self))
		}
		if length == 0 {
			// Terminator — clean end
			return true
		}
		pos = raw.index(pos, offsetBy: 4)
		guard raw.distance(from: pos, to: raw.endIndex) >= Int(length) else {
			// Short read — server closed without terminator (error path)
			return false
		}
		let chunk = Data(raw[pos ..< raw.index(pos, offsetBy: Int(length))])
		output.write(chunk)
		pos = raw.index(pos, offsetBy: Int(length))
	}

	// Reached end without seeing [0,0,0,0] terminator
	return false
}

private func receiveAll(
	connection: NWConnection,
	accumulated: Data = Data(),
	completion: @escaping @Sendable (Result<Data, Error>) -> Void
) {
	connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
		var data = accumulated
		if let content { data.append(content) }
		if isComplete {
			completion(.success(data))
		} else if let error {
			completion(.failure(IPCClientError.connectionFailed(error.localizedDescription)))
		} else {
			receiveAll(connection: connection, accumulated: data, completion: completion)
		}
	}
}

private func receiveAllRaw(
	connection: NWConnection,
	accumulated: Data = Data(),
	completion: @escaping @Sendable (Result<Data, Error>) -> Void
) {
	connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
		var data = accumulated
		if let content { data.append(content) }
		if isComplete {
			completion(.success(data))
		} else if let error {
			completion(.failure(IPCClientError.connectionFailed(error.localizedDescription)))
		} else {
			receiveAllRaw(connection: connection, accumulated: data, completion: completion)
		}
	}
}
