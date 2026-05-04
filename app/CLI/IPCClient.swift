import Foundation
import Network

enum IPCClientError: Error {
	case connectionFailed(String)
	case timeout
	case badResponse
}

private let socketPath: String = {
	let appSupport = FileManager.default
		.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
	return appSupport.appendingPathComponent("Susurro/ipc.sock").path
}()

func sendRead(text: String, cwd: String? = nil) throws -> [String: Any] {
	var body: [String: Any] = ["cmd": "read", "text": text]
	if let cwd, !cwd.isEmpty { body["cwd"] = cwd }
	let payload = try JSONSerialization.data(withJSONObject: body)

	if !FileManager.default.fileExists(atPath: socketPath) {
		wakeApp()
	}

	let deadline = Date().addingTimeInterval(3.0)
	var delay: Double = 0.2

	while Date() < deadline {
		do {
			return try connectAndSend(payload: payload)
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
