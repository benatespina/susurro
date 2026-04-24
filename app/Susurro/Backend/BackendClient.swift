import Foundation

struct BackendClient: Sendable {
    let baseURL: URL
    let token: String
    let session: URLSession

    init(lockfile: Lockfile, session: URLSession = .shared) {
        self.baseURL = URL(string: "http://127.0.0.1:\(lockfile.port)")!
        self.token = lockfile.token
        self.session = session
    }

    func health() async throws -> HealthStatus {
        var request = URLRequest(
            url: baseURL.appending(path: "health"),
            timeoutInterval: 5
        )
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        let body = try JSONDecoder().decode([String: String].self, from: data)
        let statusValue = body["status"] ?? ""

        switch (statusCode, statusValue) {
        case (200, "ready"):
            return .ready
        case (503, "loading"):
            return .loading
        default:
            let bodyString = String(data: data, encoding: .utf8)
            throw BackendClientError.unexpectedHealthBody(bodyString ?? "status=\(statusCode)")
        }
    }

    func tts(text: String, language: String?) async throws -> Data {
        var request = URLRequest(
            url: baseURL.appending(path: "tts"),
            timeoutInterval: 30
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: String] = ["text": text]
        if let language {
            payload["language"] = language
        }
        request.httpBody = try JSONEncoder().encode(payload)

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode == 200 else {
                let body = String(data: data, encoding: .utf8)
                throw BackendClientError.http(status: statusCode, body: body)
            }
            return data
        } catch let error as BackendClientError {
            throw error
        } catch {
            throw BackendClientError.transport(error)
        }
    }

    func stop() async throws {
        var request = URLRequest(
            url: baseURL.appending(path: "stop"),
            timeoutInterval: 5
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode == 204 else {
                let body = String(data: data, encoding: .utf8)
                throw BackendClientError.http(status: statusCode, body: body)
            }
        } catch let error as BackendClientError {
            throw error
        } catch {
            throw BackendClientError.transport(error)
        }
    }
}

enum HealthStatus: Sendable, Equatable { case ready, loading }

enum BackendClientError: Error {
    case http(status: Int, body: String?)
    case unexpectedHealthBody(String)
    case decoding(Error)
    case transport(Error)
}
