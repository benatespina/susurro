import Foundation
import Testing
@testable import Susurro

struct ReleaseCheckerTests {
    private let checker = ReleaseChecker()

    // MARK: - compareVersion

    @Test func compareVersion_currentLowerThanLatest() {
        #expect(checker.compareVersion(current: "0.2.0", latest: "0.3.0") == .orderedAscending)
    }

    @Test func compareVersion_currentEqualToLatest() {
        #expect(checker.compareVersion(current: "0.3.0", latest: "0.3.0") == .orderedSame)
    }

    @Test func compareVersion_currentHigherThanLatest() {
        #expect(checker.compareVersion(current: "0.4.0", latest: "0.3.0") == .orderedDescending)
    }

    @Test func compareVersion_ignoresPrereleaseSuffix() {
        // "0.3.0-beta.1" normalizes to "0.3.0" — equal to "0.3.0"
        #expect(checker.compareVersion(current: "0.3.0", latest: "0.3.0-beta.1") == .orderedSame)
    }

    @Test func compareVersion_handlesLeadingV() {
        #expect(checker.compareVersion(current: "v0.2.0", latest: "0.3.0") == .orderedAscending)
    }

    @Test func compareVersion_handlesPaddedComponents() {
        // "1.0" pads to "1.0.0" — equal to "1.0.0"
        #expect(checker.compareVersion(current: "1.0", latest: "1.0.0") == .orderedSame)
    }

    @Test func compareVersion_garbageInputReturnsSame() {
        #expect(checker.compareVersion(current: "abc", latest: "0.3.0") == .orderedSame)
    }

    // MARK: - shouldCheckNow

    @Test func shouldCheckNow_firstLaunch_returnsTrue() {
        let settings = UpdateSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        #expect(checker.shouldCheckNow(now: Date(), settings: settings) == true)
    }

    @Test func shouldCheckNow_lessThan24h_returnsFalse() {
        let now = Date()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        var settings = UpdateSettings(defaults: defaults)
        settings.lastCheckDate = now.addingTimeInterval(-3600) // 1 hour ago
        #expect(checker.shouldCheckNow(now: now, settings: settings) == false)
    }

    @Test func shouldCheckNow_moreThan24h_returnsTrue() {
        let now = Date()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        var settings = UpdateSettings(defaults: defaults)
        settings.lastCheckDate = now.addingTimeInterval(-90000) // 25 hours ago
        #expect(checker.shouldCheckNow(now: now, settings: settings) == true)
    }

    @Test func shouldCheckNow_exactly24h_returnsTrue() {
        let now = Date()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        var settings = UpdateSettings(defaults: defaults)
        settings.lastCheckDate = now.addingTimeInterval(-86400) // exactly 24h ago
        #expect(checker.shouldCheckNow(now: now, settings: settings) == true)
    }

    // MARK: - parseReleaseInfo

    @Test func parseReleaseInfo_validJSON() throws {
        let json = #"""
        {
          "tag_name": "v0.3.0",
          "name": "Susurro v0.3.0",
          "html_url": "https://github.com/benatespina/susurro/releases/tag/v0.3.0",
          "published_at": "2026-04-15T10:30:00Z"
        }
        """#
        let data = Data(json.utf8)
        let info = try checker.parseReleaseInfo(from: data)
        #expect(info.tagName == "v0.3.0")
        #expect(info.normalizedVersion == "0.3.0")
        #expect(info.htmlURL == URL(string: "https://github.com/benatespina/susurro/releases/tag/v0.3.0")!)
        #expect(info.publishedAt != nil)
        #expect(info.displayName == "Susurro v0.3.0")
    }

    @Test func parseReleaseInfo_missingPublishedAt() throws {
        let json = #"""
        {
          "tag_name": "v0.3.0",
          "name": "Susurro v0.3.0",
          "html_url": "https://github.com/benatespina/susurro/releases/tag/v0.3.0"
        }
        """#
        let data = Data(json.utf8)
        let info = try checker.parseReleaseInfo(from: data)
        #expect(info.publishedAt == nil)
    }

    @Test func parseReleaseInfo_missingName_fallsBackToTag() throws {
        let json = #"""
        {
          "tag_name": "v0.3.0",
          "html_url": "https://github.com/benatespina/susurro/releases/tag/v0.3.0",
          "published_at": "2026-04-15T10:30:00Z"
        }
        """#
        let data = Data(json.utf8)
        let info = try checker.parseReleaseInfo(from: data)
        #expect(info.displayName == "v0.3.0")
    }

    @Test func parseReleaseInfo_invalidJSON_throws() {
        let data = Data("not json".utf8)
        #expect(throws: (any Error).self) {
            try checker.parseReleaseInfo(from: data)
        }
    }
}
