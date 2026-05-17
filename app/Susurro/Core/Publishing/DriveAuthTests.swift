import CryptoKit
import Foundation
import Testing
@testable import Susurro

@Suite("DriveAuth", .serialized)
struct DriveAuthTests {

    // MARK: - PKCE

    @Test func pkceVerifierIsURLSafeAndLongEnough() {
        let pkce = DriveAuth.PKCE.generate()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        #expect(pkce.verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
        // base64url of 32 bytes = 43 characters (no padding)
        #expect(pkce.verifier.count >= 43)
    }

    @Test func pkceChallengeSHA256MatchesVerifier() throws {
        let pkce = DriveAuth.PKCE.generate()
        // challenge = base64url(SHA256(verifier))
        let expectedDigest = SHA256.hash(data: Data(pkce.verifier.utf8))
        let expected = Data(expectedDigest).base64URLEncodedString()
        #expect(pkce.challenge == expected)
    }

    @Test func pkceChallengeSHA256IsThirtyTwoBytes() throws {
        let pkce = DriveAuth.PKCE.generate()
        // Decode base64url back and verify it is 32 bytes.
        var padded = pkce.challenge
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder != 0 { padded += String(repeating: "=", count: 4 - remainder) }
        let decoded = try #require(Data(base64Encoded: padded))
        #expect(decoded.count == 32)
    }

    @Test func pkceIsDifferentEachCall() {
        let pkce1 = DriveAuth.PKCE.generate()
        let pkce2 = DriveAuth.PKCE.generate()
        #expect(pkce1.verifier != pkce2.verifier)
        #expect(pkce1.challenge != pkce2.challenge)
    }

    // MARK: - Authorize URL builder

    @Test func buildAuthorizeURLContainsRequiredParams() throws {
        let url = DriveAuth.buildAuthorizeURL(clientID: "my-client", challenge: "abc123")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "accounts.google.com")
        #expect(components.path == "/o/oauth2/v2/auth")

        let items = components.queryItems ?? []
        func value(for name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(value(for: "client_id") == "my-client")
        #expect(value(for: "code_challenge") == "abc123")
        #expect(value(for: "code_challenge_method") == "S256")
        #expect(value(for: "response_type") == "code")
        #expect(value(for: "access_type") == "offline")
        #expect(value(for: "prompt") == "consent")
        let scope = try #require(value(for: "scope"))
        #expect(scope.contains("drive.file"))
        let redirectURI = try #require(value(for: "redirect_uri"))
        #expect(redirectURI.hasPrefix("com.benatespina.susurro"))
    }

    // MARK: - Token request builder

    @Test func buildTokenRequestForAuthorizationCode() {
        let request = DriveAuth.buildTokenRequest(
            clientID: "cid",
            clientSecret: "cs",
            code: "auth-code",
            codeVerifier: "verifier-abc",
            grantType: "authorization_code",
            refreshToken: nil
        )
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("client_id=cid"))
        #expect(body.contains("client_secret=cs"))
        #expect(body.contains("code=auth-code"))
        #expect(body.contains("code_verifier=verifier-abc"))
    }

    @Test func buildTokenRequestForRefresh() {
        let request = DriveAuth.buildTokenRequest(
            clientID: "cid",
            clientSecret: "cs",
            code: nil,
            codeVerifier: nil,
            grantType: "refresh_token",
            refreshToken: "rtoken"
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=rtoken"))
        #expect(!body.contains("code="))
        #expect(!body.contains("code_verifier="))
    }

    // MARK: - Token refresh (mock URLSession)

    @Test func refreshAccessTokenParsesSuccessResponse() async throws {
        let json = """
        {"access_token":"new-access","expires_in":3600}
        """
        let mockSession = URLSession.mock(response: json, statusCode: 200)
        let auth = await DriveAuth(urlSession: mockSession)

        let (accessToken, expiry) = try await auth.refreshAccessToken(
            clientID: "cid",
            clientSecret: "cs",
            refreshToken: "rtoken"
        )
        #expect(accessToken == "new-access")
        // Expiry should be approximately 3600 - 60 = 3540 seconds from now.
        let delta = expiry.timeIntervalSinceNow
        #expect(delta > 3530 && delta < 3550)
    }

    @Test func refreshAccessTokenThrowsOnNon2xx() async throws {
        let json = """
        {"error":"invalid_grant","error_description":"Token has been expired or revoked."}
        """
        let mockSession = URLSession.mock(response: json, statusCode: 400)
        let auth = await DriveAuth(urlSession: mockSession)

        do {
            _ = try await auth.refreshAccessToken(
                clientID: "cid",
                clientSecret: "cs",
                refreshToken: "bad-token"
            )
            Issue.record("Expected refreshFailed to be thrown")
        } catch DriveAuthError.refreshFailed(let msg) {
            #expect(msg.contains("400"))
        }
    }

    // MARK: - Data base64url

    @Test func base64URLEncodesCorrectly() {
        // Known input: bytes that produce + and / in standard base64
        let data = Data([0xFB, 0xFF, 0xFE])  // produces +//+ in standard base64
        let encoded = data.base64URLEncodedString()
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
    }
}

// MARK: - Mock URLSession helper

extension URLSession {
    static func mock(response body: String, statusCode: Int) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.responseBody = Data(body.utf8)
        MockURLProtocol.responseStatusCode = statusCode
        return URLSession(configuration: config)
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseBody: Data = Data()
    nonisolated(unsafe) static var responseStatusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockURLProtocol.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
