import Foundation

// MARK: - Errors

enum DriveError: Error, Sendable {
    case notConfigured
    case noAccessToken
    case httpError(status: Int, body: String)
}

// MARK: - Models

struct DriveFileMeta: Sendable, Equatable {
    let id: String
    let name: String
    let size: Int64?
    let mimeType: String?
}

// MARK: - Protocol for testability

protocol DriveUploading: Sendable {
    func createFolder(name: String, parentID: String) async throws -> String
    func uploadFile(name: String, mimeType: String, data: Data, parentID: String) async throws -> String
    func updateFile(fileID: String, data: Data, mimeType: String) async throws
    func deleteFile(fileID: String) async throws
    func setAnyoneWithLink(fileID: String) async throws
    func headFile(fileID: String) async throws -> DriveFileMeta?
}

// MARK: - DriveClient

actor DriveClient: DriveUploading {

    // MARK: - Dependencies

    private let auth: DriveAuth
    private let configProvider: @Sendable () -> DriveConfig?
    private let urlSession: URLSession

    // MARK: - Init

    init(
        auth: DriveAuth,
        configProvider: @escaping @Sendable () -> DriveConfig?,
        urlSession: URLSession = .shared
    ) {
        self.auth = auth
        self.configProvider = configProvider
        self.urlSession = urlSession
    }

    // MARK: - Public API

    func createFolder(name: String, parentID: String = "root") async throws -> String {
        let token = try await accessToken()
        let url = URL(string: "https://www.googleapis.com/drive/v3/files")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "parents": [parentID],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try checkHTTPStatus(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let fileID = json?["id"] as? String else {
            throw DriveError.httpError(status: -1, body: "Missing id in createFolder response")
        }
        return fileID
    }

    func uploadFile(name: String, mimeType: String, data: Data, parentID: String) async throws -> String {
        let token = try await accessToken()
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!

        let boundary = "susurro-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/related; boundary=\"\(boundary)\"", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let metadataJSON = try JSONSerialization.data(withJSONObject: ["name": name, "parents": [parentID]])
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await urlSession.data(for: request)
        try checkHTTPStatus(response, data: responseData)

        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        guard let fileID = json?["id"] as? String else {
            throw DriveError.httpError(status: -1, body: "Missing id in uploadFile response")
        }
        return fileID
    }

    func updateFile(fileID: String, data: Data, mimeType: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let (responseData, response) = try await urlSession.data(for: request)
        try checkHTTPStatus(response, data: responseData)
    }

    func deleteFile(fileID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (responseData, response) = try await urlSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            return  // Idempotent — already deleted
        }
        try checkHTTPStatus(response, data: responseData)
    }

    func setAnyoneWithLink(fileID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)/permissions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["role": "reader", "type": "anyone"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await urlSession.data(for: request)
        try checkHTTPStatus(response, data: responseData)
    }

    func headFile(fileID: String) async throws -> DriveFileMeta? {
        let token = try await accessToken()
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?fields=id,name,size,mimeType")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            return nil
        }
        try checkHTTPStatus(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String, let name = json?["name"] as? String else {
            throw DriveError.httpError(status: -1, body: "Missing required fields in headFile response")
        }

        let sizeString = json?["size"] as? String
        let size: Int64? = sizeString.flatMap { Int64($0) }
        let mimeType = json?["mimeType"] as? String

        return DriveFileMeta(id: id, name: name, size: size, mimeType: mimeType)
    }

    // MARK: - Private: access token management

    private func accessToken() async throws -> String {
        guard let config = configProvider() else { throw DriveError.notConfigured }
        guard let refreshToken = config.refreshToken else { throw DriveError.noAccessToken }

        // Return cached token if still valid.
        if let token = config.accessToken,
           let expiry = config.accessTokenExpiry,
           expiry > Date() {
            return token
        }

        // Refresh the token.
        let (newToken, newExpiry) = try await auth.refreshAccessToken(
            clientID: config.clientID,
            clientSecret: config.clientSecret,
            refreshToken: refreshToken
        )

        // Persist updated token.
        let updated = DriveConfig(
            clientID: config.clientID,
            clientSecret: config.clientSecret,
            refreshToken: config.refreshToken,
            accessToken: newToken,
            accessTokenExpiry: newExpiry,
            folderID: config.folderID,
            feedFileID: config.feedFileID
        )
        DriveConfig.save(updated)
        return newToken
    }

    // MARK: - Private: HTTP status check

    private func checkHTTPStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(1024), encoding: .utf8) ?? ""
            throw DriveError.httpError(status: http.statusCode, body: body)
        }
    }
}
