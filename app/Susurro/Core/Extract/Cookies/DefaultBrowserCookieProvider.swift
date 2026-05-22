import Foundation
import os.log

actor DefaultBrowserCookieProvider: BrowserCookieProvider {
    private let adapterFactory: @Sendable (BrowserSource) -> ChromiumCookieAdapter
    private let defaultBrowser: @Sendable () -> BrowserSource?
    private let isSafariOnly: @Sendable () -> Bool
    private let installedBrowsers: @Sendable () -> [BrowserSource]
    private let logger = Logger(subsystem: "com.benatespina.susurro", category: "BrowserCookieProvider")

    init(
        keychain: any KeychainAccessor,
        adapterFactory: (@Sendable (BrowserSource) -> ChromiumCookieAdapter)? = nil,
        defaultBrowser: @escaping @Sendable () -> BrowserSource? = BrowserDetector.defaultBrowser,
        isSafariOnly: @escaping @Sendable () -> Bool = BrowserDetector.isSafariOnly,
        installedBrowsers: @escaping @Sendable () -> [BrowserSource] = BrowserDetector.installedBrowsers
    ) {
        self.adapterFactory = adapterFactory ?? { source in
            ChromiumCookieAdapter(source: source, keychain: keychain)
        }
        self.defaultBrowser = defaultBrowser
        self.isSafariOnly = isSafariOnly
        self.installedBrowsers = installedBrowsers
    }

    func cookies(forDomain domain: String) async throws -> [HTTPCookie] {
        let installed = installedBrowsers()
        if installed.isEmpty {
            if isSafariOnly() {
                throw BrowserCookieError.onlySafariDetected
            }
            throw BrowserCookieError.noBrowserDetected
        }

        // Build ordered candidate list: default first (if known and installed), then the
        // fallback sequence chrome->arc->brave->edge, deduped, filtered to installed.
        var ordered: [BrowserSource] = []
        if let def = defaultBrowser(), installed.contains(def) {
            ordered.append(def)
        }
        for source in [BrowserSource.chrome, .arc, .brave, .edge] where installed.contains(source) && !ordered.contains(source) {
            ordered.append(source)
        }

        var lastTried: BrowserSource?
        for source in ordered {
            lastTried = source
            let adapter = adapterFactory(source)
            do {
                let browserCookies = try await adapter.cookies(forDomain: domain)
                let httpCookies = browserCookies.compactMap { $0.toHTTPCookie() }
                if hasMinimumXSessionCookies(httpCookies) {
                    return httpCookies
                }
                logger.info("Browser \(source.displayName, privacy: .public) had no auth_token+ct0 pair; trying next.")
            } catch {
                logger.warning("Adapter for \(source.displayName, privacy: .public) failed: \(String(describing: error))")
                continue
            }
        }

        throw BrowserCookieError.noXSessionCookies(lastTried ?? .chrome)
    }

    /// X session requires at least `auth_token` and `ct0`.
    private func hasMinimumXSessionCookies(_ cookies: [HTTPCookie]) -> Bool {
        let names = Set(cookies.map(\.name))
        return names.contains("auth_token") && names.contains("ct0")
    }
}
