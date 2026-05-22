import Foundation

struct BrowserCookie: Sendable, Equatable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresUTC: Int64
    let isSecure: Bool
    let isHTTPOnly: Bool

    func toHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]

        if expiresUTC != 0 {
            let unixSeconds = Double(expiresUTC / 1_000_000) - 11_644_473_600
            properties[.expires] = Date(timeIntervalSince1970: unixSeconds)
        }

        if isSecure {
            properties[.secure] = "TRUE"
        }

        if isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }

        return HTTPCookie(properties: properties)
    }
}
