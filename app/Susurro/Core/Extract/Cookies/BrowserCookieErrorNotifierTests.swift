import Foundation
import Testing
@testable import Susurro

@MainActor
@Suite struct BrowserCookieErrorNotifierTests {
    @Test func actionableErrorMarksShown() {
        let notifier = BrowserCookieErrorNotifier()
        #expect(notifier.hasShownThisSession == false)
        notifier.notify(.noBrowserDetected)
        #expect(notifier.hasShownThisSession == true)
        notifier.resetForTesting()
    }

    @Test func nonActionableErrorDoesNotMarkShown() {
        let notifier = BrowserCookieErrorNotifier()
        notifier.notify(.decryptionFailed(.chrome))
        #expect(notifier.hasShownThisSession == false)
        notifier.notify(.databaseUnavailable(.chrome))
        #expect(notifier.hasShownThisSession == false)
        notifier.notify(.keychainNotFound(.chrome))
        #expect(notifier.hasShownThisSession == false)
        notifier.resetForTesting()
    }

    @Test func secondNotifyDoesNotReopen() {
        let notifier = BrowserCookieErrorNotifier()
        notifier.notify(.noBrowserDetected)
        let firstFlag = notifier.hasShownThisSession
        notifier.notify(.keychainDenied(.chrome))
        // Window state unchanged; just verify the flag doesn't toggle off
        #expect(notifier.hasShownThisSession == firstFlag)
        notifier.resetForTesting()
    }

    @Test func allActionableErrorsTrigger() {
        let cases: [BrowserCookieError] = [
            .onlySafariDetected,
            .noBrowserDetected,
            .keychainDenied(.chrome),
            .noXSessionCookies(.chrome),
        ]
        for c in cases {
            let notifier = BrowserCookieErrorNotifier()
            notifier.notify(c)
            #expect(notifier.hasShownThisSession == true, "Failed for \(c)")
            notifier.resetForTesting()
        }
    }
}
