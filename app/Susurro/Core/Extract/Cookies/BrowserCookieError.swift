enum BrowserCookieError: Error, Equatable {
    case noBrowserDetected
    case onlySafariDetected
    case databaseUnavailable(BrowserSource)
    case keychainDenied(BrowserSource)
    case keychainNotFound(BrowserSource)
    case decryptionFailed(BrowserSource)
    case noXSessionCookies(BrowserSource)
}
