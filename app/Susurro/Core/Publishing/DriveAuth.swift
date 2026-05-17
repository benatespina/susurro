import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

// MARK: - Error types

enum DriveAuthError: Error, Sendable {
    case userCancelled
    case invalidCallback
    case tokenExchangeFailed(String)
    case refreshFailed(String)
}

// MARK: - DriveAuth

@MainActor
final class DriveAuth: NSObject, ASWebAuthenticationPresentationContextProviding, Sendable {

    // MARK: - Dependencies

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - PKCE

    struct PKCE: Sendable {
        let verifier: String
        let challenge: String

        nonisolated static func generate() -> PKCE {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let verifier = Data(bytes).base64URLEncodedString()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
            return PKCE(verifier: verifier, challenge: challenge)
        }
    }

    // MARK: - Public API

    func connect(
        clientID: String,
        clientSecret: String
    ) async throws -> (refreshToken: String, accessToken: String, expiry: Date) {
        let pkce = PKCE.generate()
        let authorizeURL = DriveAuth.buildAuthorizeURL(clientID: clientID, challenge: pkce.challenge)

        let callbackURL = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: "com.benatespina.susurro"
            ) { @Sendable url, error in
                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: DriveAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: DriveAuthError.tokenExchangeFailed(error.localizedDescription))
                    }
                    return
                }
                guard let url else {
                    continuation.resume(throwing: DriveAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        else {
            throw DriveAuthError.invalidCallback
        }

        // Surface Google's error description when the user denies access.
        if let oauthError = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let description = components.queryItems?.first(where: { $0.name == "error_description" })?.value
            throw DriveAuthError.tokenExchangeFailed(description ?? oauthError)
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw DriveAuthError.invalidCallback
        }

        let request = DriveAuth.buildTokenRequest(
            clientID: clientID,
            clientSecret: clientSecret,
            code: code,
            codeVerifier: pkce.verifier,
            grantType: "authorization_code",
            refreshToken: nil
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(1024), encoding: .utf8) ?? ""
            throw DriveAuthError.tokenExchangeFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(body)")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refreshToken = tokenResponse.refreshToken else {
            throw DriveAuthError.tokenExchangeFailed("No refresh_token in response")
        }

        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn) - 60)
        return (refreshToken: refreshToken, accessToken: tokenResponse.accessToken, expiry: expiry)
    }

    func refreshAccessToken(
        clientID: String,
        clientSecret: String,
        refreshToken: String
    ) async throws -> (accessToken: String, expiry: Date) {
        let request = DriveAuth.buildTokenRequest(
            clientID: clientID,
            clientSecret: clientSecret,
            code: nil,
            codeVerifier: nil,
            grantType: "refresh_token",
            refreshToken: refreshToken
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(1024), encoding: .utf8) ?? ""
            throw DriveAuthError.refreshFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(body)")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn) - 60)
        return (accessToken: tokenResponse.accessToken, expiry: expiry)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? ASPresentationAnchor()
        }
    }

    // MARK: - Internal URL builders (testable)

    nonisolated static func buildAuthorizeURL(clientID: String, challenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "com.benatespina.susurro:/oauth/callback"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    nonisolated static func buildTokenRequest(
        clientID: String,
        clientSecret: String,
        code: String?,
        codeVerifier: String?,
        grantType: String,
        refreshToken: String?
    ) -> URLRequest {
        var params: [String: String] = [
            "client_id": clientID,
            "grant_type": grantType,
            "redirect_uri": "com.benatespina.susurro:/oauth/callback",
        ]
        if !clientSecret.isEmpty { params["client_secret"] = clientSecret }
        if let code { params["code"] = code }
        if let codeVerifier { params["code_verifier"] = codeVerifier }
        if let refreshToken { params["refresh_token"] = refreshToken }

        let bodyString = params
            .map { "\($0.key.urlEncoded)=\($0.value.urlEncoded)" }
            .sorted()
            .joined(separator: "&")

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(bodyString.utf8)
        return request
    }

    // MARK: - Private: token response model

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }
}

// MARK: - Data + base64url

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - String URL encoding helper

private extension String {
    /// Percent-encodes a value for use as an `application/x-www-form-urlencoded` field.
    /// `.urlQueryAllowed` still admits `&`, `=`, `+`, `#`, etc., which would corrupt form bodies.
    /// We use `.alphanumerics` plus the unreserved characters defined by RFC 3986 §2.3.
    var urlEncoded: String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return addingPercentEncoding(withAllowedCharacters: unreserved) ?? self
    }
}
