import Foundation
import Testing
@testable import Susurro

@Suite("DriveConfig", .serialized)
struct DriveConfigTests {

    /// Keychain is process-wide; snapshot and restore so tests don't trash a real Drive setup.
    private static let touchedAccounts: [String] = [
        DriveConfig.Account.clientID,
        DriveConfig.Account.clientSecret,
        DriveConfig.Account.refreshToken,
        DriveConfig.Account.accessToken,
        DriveConfig.Account.accessTokenExpiry,
        DriveConfig.Account.folderID,
        DriveConfig.Account.feedFileID,
    ]

    /// Per-test isolation: a fresh UserDefaults suite plus a Keychain snapshot/restore.
    private static func withIsolatedStorage<T>(_ body: () throws -> T) rethrows -> T {
        let suiteName = "test.DriveConfig.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let previousDefaults = DriveConfig.defaults
        DriveConfig.defaults = suite

        let keychainSnapshot: [String: String] = Dictionary(uniqueKeysWithValues: touchedAccounts.map {
            ($0, Keychain.string(for: $0) ?? "")
        })
        for account in touchedAccounts {
            Keychain.set("", for: account)
        }

        defer {
            for (account, value) in keychainSnapshot {
                Keychain.set(value, for: account)
            }
            DriveConfig.defaults = previousDefaults
            suite.removePersistentDomain(forName: suiteName)
        }
        return try body()
    }

    @Test func loadReturnsNilWhenClientIDMissing() {
        Self.withIsolatedStorage {
            DriveConfig.save(DriveConfig(
                clientID: "",
                clientSecret: "secret",
                refreshToken: nil,
                accessToken: nil,
                accessTokenExpiry: nil,
                folderID: nil,
                feedFileID: nil
            ))
            // Saving with empty clientID leaves UserDefaults storing "" — load() treats that as missing.
            #expect(DriveConfig.load() == nil)
        }
    }

    @Test func loadSucceedsWithEmptyClientSecret() throws {
        try Self.withIsolatedStorage {
            DriveConfig.save(DriveConfig(
                clientID: "client-id",
                clientSecret: "",
                refreshToken: nil,
                accessToken: nil,
                accessTokenExpiry: nil,
                folderID: nil,
                feedFileID: nil
            ))
            let loaded = try #require(DriveConfig.load())
            #expect(loaded.clientID == "client-id")
            #expect(loaded.clientSecret == "")
        }
    }

    @Test func roundTripMinimal() throws {
        try Self.withIsolatedStorage {
            let config = DriveConfig(
                clientID: "test-client-id",
                clientSecret: "test-client-secret",
                refreshToken: nil,
                accessToken: nil,
                accessTokenExpiry: nil,
                folderID: nil,
                feedFileID: nil
            )
            DriveConfig.save(config)
            let loaded = try #require(DriveConfig.load())
            #expect(loaded.clientID == config.clientID)
            #expect(loaded.clientSecret == config.clientSecret)
            #expect(loaded.refreshToken == nil)
            #expect(loaded.accessToken == nil)
            #expect(loaded.accessTokenExpiry == nil)
            #expect(loaded.folderID == nil)
            #expect(loaded.feedFileID == nil)
        }
    }

    @Test func roundTripFull() throws {
        try Self.withIsolatedStorage {
            let expiry = Date(timeIntervalSince1970: 1_700_000_000)
            let config = DriveConfig(
                clientID: "cid",
                clientSecret: "csecret",
                refreshToken: "rtoken",
                accessToken: "atoken",
                accessTokenExpiry: expiry,
                folderID: "folder-abc",
                feedFileID: "feed-xyz"
            )
            DriveConfig.save(config)
            let loaded = try #require(DriveConfig.load())
            #expect(loaded.clientID == "cid")
            #expect(loaded.clientSecret == "csecret")
            #expect(loaded.refreshToken == "rtoken")
            #expect(loaded.accessToken == "atoken")
            #expect(loaded.folderID == "folder-abc")
            #expect(loaded.feedFileID == "feed-xyz")

            // Expiry round-trips to within 1 second due to ISO 8601 second precision.
            let loadedExpiry = try #require(loaded.accessTokenExpiry)
            #expect(abs(loadedExpiry.timeIntervalSince(expiry)) < 1.0)
        }
    }

    @Test func clientIDAndFolderIDStoredInUserDefaults() throws {
        try Self.withIsolatedStorage {
            DriveConfig.save(DriveConfig(
                clientID: "cid", clientSecret: "cs", refreshToken: nil,
                accessToken: nil, accessTokenExpiry: nil, folderID: "fid", feedFileID: nil
            ))
            #expect(DriveConfig.defaults.string(forKey: DriveConfig.UserDefaultsKey.clientID) == "cid")
            #expect(DriveConfig.defaults.string(forKey: DriveConfig.UserDefaultsKey.folderID) == "fid")
        }
    }

    @Test func migratesLegacyKeychainClientIDAndFolderID() throws {
        try Self.withIsolatedStorage {
            // Pre-seed legacy Keychain entries, UserDefaults empty.
            Keychain.set("legacy-cid", for: DriveConfig.Account.clientID)
            Keychain.set("legacy-folder", for: DriveConfig.Account.folderID)
            Keychain.set("legacy-secret", for: DriveConfig.Account.clientSecret)

            let loaded = try #require(DriveConfig.load())
            #expect(loaded.clientID == "legacy-cid")
            #expect(loaded.folderID == "legacy-folder")
            #expect(loaded.clientSecret == "legacy-secret")

            // UserDefaults now owns the values.
            #expect(DriveConfig.defaults.string(forKey: DriveConfig.UserDefaultsKey.clientID) == "legacy-cid")
            #expect(DriveConfig.defaults.string(forKey: DriveConfig.UserDefaultsKey.folderID) == "legacy-folder")

            // Legacy Keychain entries for these fields are cleared.
            #expect(Keychain.string(for: DriveConfig.Account.clientID) == nil)
            #expect(Keychain.string(for: DriveConfig.Account.folderID) == nil)
        }
    }

    @Test func migrationDoesNotRunWhenUserDefaultsAlreadyHasClientID() throws {
        try Self.withIsolatedStorage {
            DriveConfig.defaults.set("modern-cid", forKey: DriveConfig.UserDefaultsKey.clientID)
            // Stale legacy Keychain entry must be ignored, not pulled in.
            Keychain.set("legacy-cid", for: DriveConfig.Account.clientID)

            let loaded = try #require(DriveConfig.load())
            #expect(loaded.clientID == "modern-cid")
            // Legacy Keychain entry remains untouched (migration didn't run).
            #expect(Keychain.string(for: DriveConfig.Account.clientID) == "legacy-cid")
        }
    }

    @Test func roundTripAfterMigration() throws {
        try Self.withIsolatedStorage {
            Keychain.set("legacy-cid", for: DriveConfig.Account.clientID)
            Keychain.set("legacy-folder", for: DriveConfig.Account.folderID)
            Keychain.set("legacy-secret", for: DriveConfig.Account.clientSecret)

            // First load triggers migration.
            _ = DriveConfig.load()

            // Second load reads from UserDefaults exclusively for clientID/folderID.
            let loaded = try #require(DriveConfig.load())
            #expect(loaded.clientID == "legacy-cid")
            #expect(loaded.folderID == "legacy-folder")
            #expect(loaded.clientSecret == "legacy-secret")
        }
    }

    @Test func isConnectedReflectsRefreshToken() {
        let connected = DriveConfig(
            clientID: "cid", clientSecret: "cs", refreshToken: "rt",
            accessToken: nil, accessTokenExpiry: nil, folderID: nil, feedFileID: nil
        )
        let notConnected = DriveConfig(
            clientID: "cid", clientSecret: "cs", refreshToken: nil,
            accessToken: nil, accessTokenExpiry: nil, folderID: nil, feedFileID: nil
        )
        #expect(connected.isConnected == true)
        #expect(notConnected.isConnected == false)
    }

    @Test func hasFolderReflectsFolderID() {
        let withFolder = DriveConfig(
            clientID: "cid", clientSecret: "cs", refreshToken: nil,
            accessToken: nil, accessTokenExpiry: nil, folderID: "abc", feedFileID: nil
        )
        let withoutFolder = DriveConfig(
            clientID: "cid", clientSecret: "cs", refreshToken: nil,
            accessToken: nil, accessTokenExpiry: nil, folderID: nil, feedFileID: nil
        )
        #expect(withFolder.hasFolder == true)
        #expect(withoutFolder.hasFolder == false)
    }

    @Test func feedURLReturnsNilWhenNoFeedFileID() {
        let config = DriveConfig(
            clientID: "cid", clientSecret: "cs", refreshToken: nil,
            accessToken: nil, accessTokenExpiry: nil, folderID: nil, feedFileID: nil
        )
        #expect(config.feedURL() == nil)
    }

    @Test func feedURLReturnsCorrectForm() throws {
        let config = DriveConfig(
            clientID: "cid", clientSecret: "cs", refreshToken: nil,
            accessToken: nil, accessTokenExpiry: nil, folderID: nil, feedFileID: "FILE123"
        )
        let url = try #require(config.feedURL())
        #expect(url.absoluteString == "https://drive.usercontent.google.com/download?id=FILE123&export=download&authuser=0&confirm=t")
    }

    @Test func enclosureURLHasCorrectForm() {
        let url = DriveConfig.enclosureURL(forFileID: "abc-def")
        #expect(url.absoluteString == "https://drive.usercontent.google.com/download?id=abc-def&export=download&authuser=0&confirm=t")
    }

    @Test func clearDeletesAllEntries() {
        Self.withIsolatedStorage {
            DriveConfig.save(DriveConfig(
                clientID: "cid", clientSecret: "cs", refreshToken: "rt",
                accessToken: "at", accessTokenExpiry: Date(), folderID: "fid", feedFileID: "ffid"
            ))
            DriveConfig.clear()
            #expect(DriveConfig.load() == nil)
        }
    }

    @Test func clearTokensOnlyKeepsClientIDAndFolder() throws {
        try Self.withIsolatedStorage {
            DriveConfig.save(DriveConfig(
                clientID: "cid", clientSecret: "cs", refreshToken: "rt",
                accessToken: "at", accessTokenExpiry: Date(), folderID: "fid", feedFileID: "ffid"
            ))
            DriveConfig.clearTokensOnly()
            let loaded = try #require(DriveConfig.load())
            #expect(loaded.clientID == "cid")
            #expect(loaded.folderID == "fid")
            #expect(loaded.feedFileID == "ffid")
            #expect(loaded.isConnected == false)
            #expect(loaded.accessToken == nil || loaded.accessToken == "")
            #expect(loaded.accessTokenExpiry == nil)
        }
    }

    // MARK: - copying(refreshToken:accessToken:accessTokenExpiry:folderID:)

    @Test func copyingWithNewTokensPreservesFeedFileID() {
        let original = DriveConfig(
            clientID: "cid", clientSecret: "cs", refreshToken: "old-rt",
            accessToken: "old-at", accessTokenExpiry: nil, folderID: "folder-1", feedFileID: "feed-abc"
        )
        let updated = original.copying(
            refreshToken: "new-rt",
            accessToken: "new-at",
            accessTokenExpiry: nil
        )
        #expect(updated.clientID == "cid")
        #expect(updated.clientSecret == "cs")
        #expect(updated.refreshToken == "new-rt")
        #expect(updated.accessToken == "new-at")
        #expect(updated.folderID == "folder-1")
        #expect(updated.feedFileID == "feed-abc")
    }

    @Test func copyingWithNewTokensAndFolderIDPreservesFeedFileID() {
        let original = DriveConfig(
            clientID: "cid", clientSecret: "cs", refreshToken: "old-rt",
            accessToken: "old-at", accessTokenExpiry: nil, folderID: nil, feedFileID: "feed-xyz"
        )
        let updated = original.copying(
            refreshToken: "new-rt",
            accessToken: "new-at",
            accessTokenExpiry: nil,
            folderID: "new-folder"
        )
        #expect(updated.folderID == "new-folder")
        #expect(updated.feedFileID == "feed-xyz")
    }

    @Test func copyingWithNewTokensWhenNoFeedFileIDRemainsNil() {
        let original = DriveConfig(
            clientID: "cid", clientSecret: "cs", refreshToken: "old-rt",
            accessToken: "old-at", accessTokenExpiry: nil, folderID: "fid", feedFileID: nil
        )
        let updated = original.copying(
            refreshToken: "new-rt",
            accessToken: "new-at",
            accessTokenExpiry: nil
        )
        #expect(updated.feedFileID == nil)
    }

    // MARK: - Reconnect persistence (acceptance criteria 1, 2, 4)

    /// AC1: feedFileID survives a reconnect when one was previously persisted.
    @Test func reconnectPreservesFeedFileID() throws {
        try Self.withIsolatedStorage {
            // Simulate a connected state with a known feedFileID.
            DriveConfig.save(DriveConfig(
                clientID: "cid", clientSecret: "", refreshToken: "old-rt",
                accessToken: "old-at", accessTokenExpiry: nil, folderID: "fid", feedFileID: "feed-stable"
            ))

            // Simulate what connectDrive() does: read prior, build new config with prior feedFileID.
            let prior = DriveConfig.load()
            let priorFeedFileID = prior?.feedFileID
            let priorFolderID = prior?.folderID

            // New OAuth tokens arrive (e.g. after re-auth).
            let reconnected = DriveConfig(
                clientID: "cid", clientSecret: "", refreshToken: "new-rt",
                accessToken: "new-at", accessTokenExpiry: nil, folderID: priorFolderID,
                feedFileID: priorFeedFileID
            )
            DriveConfig.save(reconnected)

            let loaded = try #require(DriveConfig.load())
            #expect(loaded.feedFileID == "feed-stable")
            #expect(loaded.refreshToken == "new-rt")
            #expect(loaded.folderID == "fid")
        }
    }

    /// AC2: first-time connect (no prior feedFileID) leaves feedFileID nil.
    @Test func firstTimeConnectLeavesfeedFileIDNil() throws {
        try Self.withIsolatedStorage {
            // No prior config at all.
            let priorFeedFileID = DriveConfig.load()?.feedFileID  // nil
            let priorFolderID = DriveConfig.load()?.folderID      // nil

            let connected = DriveConfig(
                clientID: "cid", clientSecret: "", refreshToken: "rt",
                accessToken: "at", accessTokenExpiry: nil, folderID: priorFolderID,
                feedFileID: priorFeedFileID
            )
            DriveConfig.save(connected)

            let loaded = try #require(DriveConfig.load())
            #expect(loaded.feedFileID == nil)
            #expect(loaded.isConnected == true)
        }
    }

    /// AC4: clicking Connect twice does not wipe feedFileID on the second click.
    @Test func doubleConnectPreservesFeedFileID() throws {
        try Self.withIsolatedStorage {
            // First connect (no prior).
            let firstPriorFeedFileID = DriveConfig.load()?.feedFileID
            DriveConfig.save(DriveConfig(
                clientID: "cid", clientSecret: "", refreshToken: "rt1",
                accessToken: "at1", accessTokenExpiry: nil, folderID: "fid",
                feedFileID: firstPriorFeedFileID
            ))

            // Simulate publishing sets feedFileID.
            DriveConfig.save(DriveConfig(
                clientID: "cid", clientSecret: "", refreshToken: "rt1",
                accessToken: "at1", accessTokenExpiry: nil, folderID: "fid", feedFileID: "feed-stable"
            ))

            // Second connect: read prior from Keychain, preserve feedFileID.
            let secondPrior = DriveConfig.load()
            let secondPriorFeedFileID = secondPrior?.feedFileID
            let secondPriorFolderID = secondPrior?.folderID

            let secondConnect = DriveConfig(
                clientID: "cid", clientSecret: "", refreshToken: "rt2",
                accessToken: "at2", accessTokenExpiry: nil, folderID: secondPriorFolderID,
                feedFileID: secondPriorFeedFileID
            )
            DriveConfig.save(secondConnect)

            let loaded = try #require(DriveConfig.load())
            #expect(loaded.feedFileID == "feed-stable")
            #expect(loaded.refreshToken == "rt2")
        }
    }

    /// AC3 (code verification): clearTokensOnly does not touch feedFileID.
    @Test func clearTokensOnlyDoesNotTouchFeedFileID() throws {
        try Self.withIsolatedStorage {
            DriveConfig.save(DriveConfig(
                clientID: "cid", clientSecret: "cs", refreshToken: "rt",
                accessToken: "at", accessTokenExpiry: Date(), folderID: "fid", feedFileID: "feed-stable"
            ))
            DriveConfig.clearTokensOnly()
            let loaded = try #require(DriveConfig.load())
            #expect(loaded.feedFileID == "feed-stable")
        }
    }
}
