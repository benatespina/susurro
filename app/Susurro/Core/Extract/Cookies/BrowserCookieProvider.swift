import Foundation

protocol BrowserCookieProvider: Sendable {
    func cookies(forDomain domain: String) async throws -> [HTTPCookie]
}
