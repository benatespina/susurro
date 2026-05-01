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

    func streamingTTSRequest(text: String, language: String?, startChunk: Int = 0) throws -> URLRequest {
        var request = URLRequest(
            url: baseURL.appending(path: "tts/stream"),
            timeoutInterval: 120
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: AnyEncodable] = ["text": AnyEncodable(text)]
        if let language {
            payload["language"] = AnyEncodable(language)
        }
        if startChunk > 0 {
            payload["start_chunk"] = AnyEncodable(startChunk)
        }
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    func fetchChunks(text: String, language: String?) async throws -> [String] {
        var request = URLRequest(
            url: baseURL.appending(path: "tts/chunks"),
            timeoutInterval: 30
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: String] = ["text": text]
        if let language { payload["language"] = language }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw BackendClientError.http(status: status, body: String(data: data, encoding: .utf8))
        }
        let decoded = try JSONDecoder().decode(ChunksResponse.self, from: data)
        return decoded.chunks
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
                AppLogger.backend.error("tts http failed status=\(statusCode, privacy: .public) body=\(body ?? "<nil>", privacy: .public)")
                throw BackendClientError.http(status: statusCode, body: body)
            }
            AppLogger.backend.info("tts ok status=200 bytes=\(data.count, privacy: .public)")
            return data
        } catch let error as BackendClientError {
            throw error
        } catch {
            AppLogger.backend.error("tts transport error: \(error.localizedDescription, privacy: .public)")
            throw BackendClientError.transport(error)
        }
    }

    func listPronunciations() async throws -> [String: [String: String]] {
        var request = URLRequest(
            url: baseURL.appending(path: "pronunciations"),
            timeoutInterval: 10
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw BackendClientError.http(status: status, body: String(data: data, encoding: .utf8))
        }
        return try JSONDecoder().decode([String: [String: String]].self, from: data)
    }

    func upsertPronunciation(language: String, word: String, replacement: String) async throws {
        var request = URLRequest(
            url: baseURL.appending(path: "pronunciations"),
            timeoutInterval: 10
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "language": language,
            "word": word,
            "replacement": replacement,
        ])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 204 else {
            throw BackendClientError.http(status: status, body: String(data: data, encoding: .utf8))
        }
    }

    func deletePronunciation(language: String, word: String) async throws {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw BackendClientError.http(status: 400, body: "could not encode word")
        }
        var request = URLRequest(
            url: baseURL.appending(path: "pronunciations/\(language)/\(encoded)"),
            timeoutInterval: 10
        )
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 204 else {
            throw BackendClientError.http(status: status, body: String(data: data, encoding: .utf8))
        }
    }

    func pronunciationCandidates(word: String, language: String) async throws -> [PronunciationCandidate] {
        var request = URLRequest(
            url: baseURL.appending(path: "pronunciations/candidates"),
            timeoutInterval: 10
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "word": word,
            "language": language,
        ])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw BackendClientError.http(status: status, body: String(data: data, encoding: .utf8))
        }
        let decoded = try JSONDecoder().decode(CandidatesResponse.self, from: data)
        return decoded.candidates
    }

    func previewSSML(ssml: String, language: String) async throws -> Data {
        var request = URLRequest(
            url: baseURL.appending(path: "tts/preview-ssml"),
            timeoutInterval: 30
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "ssml": ssml,
            "language": language,
        ])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw BackendClientError.http(status: status, body: String(data: data, encoding: .utf8))
        }
        return data
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

private struct ChunksResponse: Decodable {
    let chunks: [String]
    let language: String?
}

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        self._encode = value.encode
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

struct PronunciationCandidate: Codable, Sendable, Identifiable, Hashable {
    let kind: String
    let label: String
    let ssml: String

    var id: String { ssml }
}

private struct CandidatesResponse: Decodable {
    let candidates: [PronunciationCandidate]
}

enum BackendClientError: Error {
    case http(status: Int, body: String?)
    case unexpectedHealthBody(String)
    case decoding(Error)
    case transport(Error)
}
