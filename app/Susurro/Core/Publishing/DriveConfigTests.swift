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
}
