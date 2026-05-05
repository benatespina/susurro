import CryptoKit
import Foundation
import Testing
@testable import Susurro

@Suite("EdgeAuthSigner")
struct EdgeAuthSignerTests {

    /// Independently computes the expected token for a fixed timestamp using
    /// the same algorithm as EdgeAuthSigner, without calling EdgeAuthSigner itself.
    private func expectedToken(unixTimestamp: Double) -> String {
        let winEpoch: Double = 11_644_473_600
        let boundary: Double = 300

        var ticks = unixTimestamp + winEpoch
        ticks -= ticks.truncatingRemainder(dividingBy: boundary)
        let ticksInt = Int64(ticks * 10_000_000)

        let input = "\(ticksInt)\(EdgeAuthSigner.trustedClientToken)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    @Test("produces known SHA-256 for fixed timestamp 2023-11-14T22:13:20Z")
    func knownDigestForFixedTimestamp() {
        // Date(timeIntervalSince1970: 1_700_000_000) = 2023-11-14T22:13:20Z
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let result = EdgeAuthSigner.signedToken(at: date)

        // Cross-verify: compute the expected value inline with the same formula
        let expected = expectedToken(unixTimestamp: 1_700_000_000)
        #expect(result == expected)

        // Also lock the concrete hex value captured from Python reference output
        #expect(result == "42301B335578FEFDAE2637DED1ABD614505D432559EC08032B82048483726AFF")
    }

    @Test("tokens 1 second apart are identical (same 5-minute bucket)")
    func oneSecondApartSameToken() {
        let date1 = Date(timeIntervalSince1970: 1_700_000_000)
        let date2 = Date(timeIntervalSince1970: 1_700_000_001)

        let token1 = EdgeAuthSigner.signedToken(at: date1)
        let token2 = EdgeAuthSigner.signedToken(at: date2)

        #expect(token1 == token2)
    }

    @Test("tokens 6 minutes apart are different (cross 5-minute boundary)")
    func sixMinutesApartDifferentToken() {
        let date1 = Date(timeIntervalSince1970: 1_700_000_000)
        let date2 = Date(timeIntervalSince1970: 1_700_000_000 + 360) // +6 minutes

        let token1 = EdgeAuthSigner.signedToken(at: date1)
        let token2 = EdgeAuthSigner.signedToken(at: date2)

        #expect(token1 != token2)
    }

    @Test("token is a 64-character upper-hex string")
    func tokenIsUpperHex64Chars() {
        let token = EdgeAuthSigner.signedToken(at: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(token.count == 64)
        #expect(token.allSatisfy { $0.isHexDigit && ($0.isLetter ? $0.isUppercase : true) })
    }
}
