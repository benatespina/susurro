import CryptoKit
import Foundation

/// Generates the `Sec-MS-GEC` token required by the Microsoft Edge TTS WebSocket endpoint.
///
/// The algorithm mirrors the Python `edge-tts` library's `DRM.generate_sec_ms_gec()`:
/// 1. Get current Unix timestamp (seconds since 1970-01-01).
/// 2. Add the Windows epoch offset so the result is Windows file time in seconds.
/// 3. Round down to the nearest 5-minute (300-second) boundary.
/// 4. Multiply by 10,000,000 to convert from seconds to 100-nanosecond intervals
///    (Windows FILETIME format).
/// 5. SHA-256 hash of `"\(ticks)\(trustedClientToken)"` encoded as ASCII.
/// 6. Return the digest as an upper-case hex string.
enum EdgeAuthSigner {

    /// Public token used by all Edge TTS clients (matches `TRUSTED_CLIENT_TOKEN` in edge-tts).
    static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"

    /// `Sec-MS-GEC-Version` header value. Bump when Microsoft rotates the expected version.
    // Pin to plan version. Upstream edge-tts uses 1-143.0.3650.75 as of 2026-05.
    // Bump only when Microsoft starts rejecting requests with the older version.
    static let secMSGECVersion = "1-130.0.2849.68"

    /// Windows epoch offset: seconds between 1601-01-01 and 1970-01-01.
    private static let winEpochSeconds: Double = 11_644_473_600

    /// 5-minute boundary in seconds.
    private static let boundarySeconds: Double = 300

    /// Generates a signed token for the given point in time.
    ///
    /// - Parameter date: The reference instant. Defaults to `Date()` (now).
    /// - Returns: Upper-hex SHA-256 digest usable as `Sec-MS-GEC` header value.
    static func signedToken(at date: Date = Date()) -> String {
        // Step 1+2: Unix seconds → Windows file time seconds
        var ticks = date.timeIntervalSince1970 + winEpochSeconds

        // Step 3: Round down to nearest 5-minute boundary (matching Python's modulo subtraction)
        ticks -= ticks.truncatingRemainder(dividingBy: boundarySeconds)

        // Step 4: Convert to 100-nanosecond intervals (10,000,000 per second)
        // Use a precise integer to avoid floating-point drift
        let ticksInt = Int64(ticks * 10_000_000)

        // Step 5: SHA-256 of "\(ticksInt)\(trustedClientToken)" as ASCII bytes
        let input = "\(ticksInt)\(trustedClientToken)"
        let digest = SHA256.hash(data: Data(input.utf8))

        // Step 6: Upper-hex encoding
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}
