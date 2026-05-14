import Foundation
import Testing
@testable import Susurro

@Suite("DriveConfig", .serialized)
struct DriveConfigTests {

    @Test func loadReturnsNilWhenClientIDMissing() {
        defer { DriveConfig.clear() }
        DriveConfig.save(DriveConfig(
            clientID: "",
            clientSecret: "secret",
            refreshToken: nil,
            accessToken: nil,
            accessTokenExpiry: nil,
            folderID: nil,
            feedFileID: nil
        ))
        // After saving with empty clientID, Keychain.set with empty string deletes the entry.
        #expect(DriveConfig.load() == nil)
    }

    @Test func loadReturnsNilWhenClientSecretMissing() {
        defer { DriveConfig.clear() }
        DriveConfig.save(DriveConfig(
            clientID: "client-id",
            clientSecret: "",
            refreshToken: nil,
            accessToken: nil,
            accessTokenExpiry: nil,
            folderID: nil,
            feedFileID: nil
        ))
        #expect(DriveConfig.load() == nil)
    }

    @Test func roundTripMinimal() throws {
        defer { DriveConfig.clear() }
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

    @Test func roundTripFull() throws {
        defer { DriveConfig.clear() }
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
        #expect(url.absoluteString == "https://drive.google.com/uc?export=download&id=FILE123")
    }

    @Test func enclosureURLHasCorrectForm() {
        let url = DriveConfig.enclosureURL(forFileID: "abc-def")
        #expect(url.absoluteString == "https://drive.google.com/uc?export=download&id=abc-def")
    }

    @Test func clearDeletesAllEntries() {
        DriveConfig.save(DriveConfig(
            clientID: "cid", clientSecret: "cs", refreshToken: "rt",
            accessToken: "at", accessTokenExpiry: Date(), folderID: "fid", feedFileID: "ffid"
        ))
        DriveConfig.clear()
        #expect(DriveConfig.load() == nil)
    }
}
