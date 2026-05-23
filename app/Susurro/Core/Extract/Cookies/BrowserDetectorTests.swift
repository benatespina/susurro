import Foundation
import Testing
@testable import Susurro

@Suite struct BrowserDetectorTests {
    @Test func bundleIdentifierMappings() {
        #expect(BrowserDetector.source(forBundleIdentifier: "com.google.Chrome") == .chrome)
        #expect(BrowserDetector.source(forBundleIdentifier: "company.thebrowser.Browser") == .arc)
        #expect(BrowserDetector.source(forBundleIdentifier: "com.brave.Browser") == .brave)
        #expect(BrowserDetector.source(forBundleIdentifier: "com.microsoft.edgemac") == .edge)
    }

    @Test func unknownBundleIdentifierReturnsNil() {
        #expect(BrowserDetector.source(forBundleIdentifier: "com.apple.Safari") == nil)
        #expect(BrowserDetector.source(forBundleIdentifier: "org.mozilla.firefox") == nil)
        #expect(BrowserDetector.source(forBundleIdentifier: "garbage") == nil)
    }

    @Test func installedBrowsersIsSubsetOfAllCases() {
        let installed = BrowserDetector.installedBrowsers()
        for source in installed {
            #expect(BrowserSource.allCases.contains(source))
        }
    }
}
