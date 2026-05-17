import Foundation
import Testing
@testable import Susurro

// MARK: - Fake DriveAuth for token refresh simulation

final class FakeDriveAuth: DriveAuthing, @unchecked Sendable {
    var refreshCallCount = 0
    var refreshResult: (String, Date) = ("fresh-access-token", Date().addingTimeInterval(3600))

    func refreshAccessToken(
        clientID: String,
        clientSecret: String,
        refreshToken: String
    ) async throws -> (accessToken: String, expiry: Date) {
        refreshCallCount += 1
        return refreshResult
    }
}

// MARK: - Multi-response mock URLProtocol

final class MultiMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [(statusCode: Int, body: String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var index = 0

    static func reset(responses: [(statusCode: Int, body: String)]) {
        Self.responses = responses
        Self.requests = []
        Self.index = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession moves httpBody to httpBodyStream; reconstruct it for test inspection.
        var captured = request
        if let bodyStream = request.httpBodyStream {
            bodyStream.open()
            var bodyData = Data()
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while bodyStream.hasBytesAvailable {
                let bytesRead = bodyStream.read(&buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    bodyData.append(buffer, count: bytesRead)
                } else {
                    break
                }
            }
            bodyStream.close()
            captured = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest as URLRequest
            captured.httpBody = bodyData
        }
        MultiMockURLProtocol.requests.append(captured)

        let idx = min(MultiMockURLProtocol.index, MultiMockURLProtocol.responses.count - 1)
        MultiMockURLProtocol.index += 1
        let resp = MultiMockURLProtocol.responses[idx]

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: resp.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(resp.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeClientWithFreshToken(
    responses: [(statusCode: Int, body: String)]
) async -> DriveClient {
    MultiMockURLProtocol.reset(responses: responses)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MultiMockURLProtocol.self]
    let session = URLSession(configuration: config)

    let auth = await DriveAuth(urlSession: session)
    // Provide a config with a valid, non-expired access token so no refresh is triggered.
    let client = DriveClient(
        auth: auth,
        configProvider: {
            DriveConfig(
                clientID: "cid",
                clientSecret: "cs",
                refreshToken: "rtoken",
                accessToken: "fake-access-token",
                accessTokenExpiry: Date().addingTimeInterval(3600),
                folderID: "folder-id",
                feedFileID: nil
            )
        },
        urlSession: session
    )
    return client
}

final class ConfigBox: @unchecked Sendable {
    var value: DriveConfig?
}

private func makeClientWithExpiredToken(
    fakeAuth: FakeDriveAuth,
    responses: [(statusCode: Int, body: String)],
    box: ConfigBox
) -> DriveClient {
    MultiMockURLProtocol.reset(responses: responses)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MultiMockURLProtocol.self]
    let session = URLSession(configuration: config)

    // Provide a config with an expired access token; the client should refresh before the request.
    let client = DriveClient(
        auth: fakeAuth,
        configProvider: {
            DriveConfig(
                clientID: "cid",
                clientSecret: "cs",
                refreshToken: "old-refresh-token",
                accessToken: "expired-access-token",
                accessTokenExpiry: Date().addingTimeInterval(-60), // already expired
                folderID: "folder-id",
                feedFileID: nil
            )
        },
        configPersistor: { saved in box.value = saved },
        urlSession: session
    )
    return client
}

// MARK: - Tests

@Suite("DriveClient", .serialized)
struct DriveClientTests {

    @Test func createFolderPostsCorrectBodyAndParsesID() async throws {
        let client = await makeClientWithFreshToken(responses: [
            (200, #"{"id":"folder-abc","name":"TestFolder","mimeType":"application/vnd.google-apps.folder"}"#),
        ])
        let id = try await client.createFolder(name: "TestFolder", parentID: "root")
        #expect(id == "folder-abc")

        let request = MultiMockURLProtocol.requests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/drive/v3/files")
        let bodyJSON = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(bodyJSON?["name"] as? String == "TestFolder")
        #expect(bodyJSON?["mimeType"] as? String == "application/vnd.google-apps.folder")
        let parents = bodyJSON?["parents"] as? [String]
        #expect(parents == ["root"])
    }

    @Test func uploadFileBuildCorrectMultipartBody() async throws {
        let client = await makeClientWithFreshToken(responses: [
            (200, #"{"id":"file-xyz"}"#),
        ])
        let mp3Data = Data("fake mp3 bytes".utf8)
        let id = try await client.uploadFile(
            name: "test.mp3", mimeType: "audio/mpeg", data: mp3Data, parentID: "folder-id"
        )
        #expect(id == "file-xyz")

        let request = MultiMockURLProtocol.requests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/upload/drive/v3/files")

        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        #expect(contentType.contains("multipart/related"))
        #expect(contentType.contains("boundary"))

        let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(bodyString.contains("application/json"))
        #expect(bodyString.contains("audio/mpeg"))
        #expect(bodyString.contains("test.mp3"))
        #expect(bodyString.contains("fake mp3 bytes"))
    }

    @Test func updateFilePatchesRawBody() async throws {
        let client = await makeClientWithFreshToken(responses: [
            (200, #"{"id":"file-xyz"}"#),
        ])
        let data = Data("updated content".utf8)
        try await client.updateFile(fileID: "file-xyz", data: data, mimeType: "application/rss+xml")

        let request = MultiMockURLProtocol.requests[0]
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path.contains("file-xyz") == true)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/rss+xml")
        #expect(request.httpBody == data)
    }

    @Test func deleteFileOn404Succeeds() async throws {
        let client = await makeClientWithFreshToken(responses: [
            (404, #"{"error":{"code":404,"message":"File not found."}}"#),
        ])
        // Should not throw.
        try await client.deleteFile(fileID: "nonexistent-file")
    }

    @Test func deleteFileOn2xxSucceeds() async throws {
        let client = await makeClientWithFreshToken(responses: [
            (204, ""),
        ])
        try await client.deleteFile(fileID: "existing-file")
        #expect(MultiMockURLProtocol.requests[0].httpMethod == "DELETE")
    }

    @Test func setAnyoneWithLinkPostsToPermissionsEndpoint() async throws {
        let client = await makeClientWithFreshToken(responses: [
            (200, #"{"id":"perm-id","role":"reader","type":"anyone"}"#),
        ])
        try await client.setAnyoneWithLink(fileID: "file-abc")

        let request = MultiMockURLProtocol.requests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path.contains("permissions") == true)
        let bodyJSON = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(bodyJSON?["role"] as? String == "reader")
        #expect(bodyJSON?["type"] as? String == "anyone")
    }

    @Test func headFileReturns404AsNil() async throws {
        let client = await makeClientWithFreshToken(responses: [
            (404, #"{"error":{"code":404}}"#),
        ])
        let meta = try await client.headFile(fileID: "bad-id")
        #expect(meta == nil)
    }

    @Test func headFileParsesMetaOn200() async throws {
        let client = await makeClientWithFreshToken(responses: [
            (200, #"{"id":"file-abc","name":"test.mp3","size":"12345","mimeType":"audio/mpeg"}"#),
        ])
        let meta = try await client.headFile(fileID: "file-abc")
        #expect(meta?.id == "file-abc")
        #expect(meta?.name == "test.mp3")
        #expect(meta?.size == 12345)
        #expect(meta?.mimeType == "audio/mpeg")
    }

    @Test func nonTwoXXStatusThrowsHttpError() async throws {
        let client = await makeClientWithFreshToken(responses: [
            (500, #"{"error":"internal server error"}"#),
        ])
        do {
            _ = try await client.createFolder(name: "Foo", parentID: "root")
            Issue.record("Expected httpError to be thrown")
        } catch DriveError.httpError(let status, _) {
            #expect(status == 500)
        }
    }

    @Test func authorizationHeaderIsPresentOnRequests() async throws {
        let client = await makeClientWithFreshToken(responses: [
            (200, #"{"id":"folder-id"}"#),
        ])
        _ = try await client.createFolder(name: "Test", parentID: "root")
        let authHeader = MultiMockURLProtocol.requests[0].value(forHTTPHeaderField: "Authorization")
        #expect(authHeader == "Bearer fake-access-token")
    }

    @Test func expiredTokenTriggersRefreshAndUsesNewToken() async throws {
        let fakeAuth = FakeDriveAuth()
        let newToken = "fresh-access-token"
        let newExpiry = Date().addingTimeInterval(3600)
        fakeAuth.refreshResult = (newToken, newExpiry)

        let box = ConfigBox()
        let client = makeClientWithExpiredToken(
            fakeAuth: fakeAuth,
            responses: [
                (200, #"{"id":"file-abc","name":"test.mp3","size":"100","mimeType":"audio/mpeg"}"#),
            ],
            box: box
        )

        _ = try await client.headFile(fileID: "file-abc")

        // Refresh was called exactly once.
        #expect(fakeAuth.refreshCallCount == 1)

        // The updated config was persisted with the new token.
        #expect(box.value?.accessToken == newToken)

        // The actual Drive request carried the new bearer token.
        let authHeader = MultiMockURLProtocol.requests[0].value(forHTTPHeaderField: "Authorization")
        #expect(authHeader == "Bearer \(newToken)")
    }
}
