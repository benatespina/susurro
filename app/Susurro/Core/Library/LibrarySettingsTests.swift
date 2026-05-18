import Foundation
import Testing
@testable import Susurro

@Suite("LibrarySettings", .serialized)
@MainActor
struct LibrarySettingsTests {
    private static let ttlKey = "library.ttl.days"
    private static let autoPublishKey = "library.autoPublish"
    private static let libraryPlaybackRateKey = "library.playback.rate"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.ttlKey)
        UserDefaults.standard.removeObject(forKey: Self.autoPublishKey)
        UserDefaults.standard.removeObject(forKey: Self.libraryPlaybackRateKey)
        UserDefaults.standard.synchronize()
    }

    @Test func defaultTTLIs30Days() {
        defer {
            UserDefaults.standard.removeObject(forKey: Self.ttlKey)
            UserDefaults.standard.removeObject(forKey: Self.autoPublishKey)
        }
        let settings = LibrarySettings()
        #expect(settings.playedTTLDays == 30)
    }

    @Test func defaultAutoPublishIsTrue() {
        defer {
            UserDefaults.standard.removeObject(forKey: Self.ttlKey)
            UserDefaults.standard.removeObject(forKey: Self.autoPublishKey)
        }
        let settings = LibrarySettings()
        #expect(settings.autoPublishOnSynthesize == true)
    }

    @Test func settingTTLPersists() {
        defer {
            UserDefaults.standard.removeObject(forKey: Self.ttlKey)
            UserDefaults.standard.removeObject(forKey: Self.autoPublishKey)
        }
        let settings = LibrarySettings()
        settings.playedTTLDays = 7
        let stored = UserDefaults.standard.object(forKey: Self.ttlKey) as? Int
        #expect(stored == 7)
    }

    @Test func settingAutoPublishPersists() {
        defer {
            UserDefaults.standard.removeObject(forKey: Self.ttlKey)
            UserDefaults.standard.removeObject(forKey: Self.autoPublishKey)
        }
        let settings = LibrarySettings()
        settings.autoPublishOnSynthesize = false
        let stored = UserDefaults.standard.object(forKey: Self.autoPublishKey) as? Bool
        #expect(stored == false)
    }

    @Test func loadsPreviouslyStoredValues() {
        defer {
            UserDefaults.standard.removeObject(forKey: Self.ttlKey)
            UserDefaults.standard.removeObject(forKey: Self.autoPublishKey)
        }
        UserDefaults.standard.set(14, forKey: Self.ttlKey)
        UserDefaults.standard.set(false, forKey: Self.autoPublishKey)
        let settings = LibrarySettings()
        #expect(settings.playedTTLDays == 14)
        #expect(settings.autoPublishOnSynthesize == false)
    }

    @Test func libraryPlaybackRatePersists() {
        defer { UserDefaults.standard.removeObject(forKey: Self.libraryPlaybackRateKey) }
        let settings = LibrarySettings()
        settings.libraryPlaybackRate = 1.5
        let settings2 = LibrarySettings()
        #expect(settings2.libraryPlaybackRate == 1.5)
    }
}
