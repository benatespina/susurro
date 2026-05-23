import Foundation
import Testing
import SQLite3
@testable import Susurro

@Suite struct SQLiteCookieReaderTests {

    /// Build a minimal Chromium-style cookies SQLite at the given URL with the given rows.
    static func makeFixture(at url: URL, rows: [(host: String, name: String, encValue: Data, path: String, expires: Int64, secure: Bool, httpOnly: Bool)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw SQLiteCookieReaderError.openFailed(-1)
        }
        defer { sqlite3_close(db) }

        let createSQL = """
        CREATE TABLE cookies (
            host_key TEXT,
            name TEXT,
            value TEXT,
            encrypted_value BLOB,
            path TEXT,
            expires_utc INTEGER,
            is_secure INTEGER,
            is_httponly INTEGER
        )
        """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteCookieReaderError.openFailed(-2)
        }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for row in rows {
            var stmt: OpaquePointer?
            let insertSQL = "INSERT INTO cookies (host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly) VALUES (?, ?, '', ?, ?, ?, ?, ?)"
            sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, row.host, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.name, -1, SQLITE_TRANSIENT)
            _ = row.encValue.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 3, ptr.baseAddress, Int32(row.encValue.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_text(stmt, 4, row.path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 5, row.expires)
            sqlite3_bind_int(stmt, 6, row.secure ? 1 : 0)
            sqlite3_bind_int(stmt, 7, row.httpOnly ? 1 : 0)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    @Test func filtersToXDomainsOnly() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sqlite-reader-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try Self.makeFixture(at: tmp, rows: [
            (host: ".x.com", name: "auth_token", encValue: Data([0xAA, 0xBB]), path: "/", expires: 13_350_000_000_000_000, secure: true, httpOnly: true),
            (host: ".twitter.com", name: "ct0", encValue: Data([0xCC, 0xDD]), path: "/", expires: 13_350_000_000_000_000, secure: true, httpOnly: false),
            (host: ".google.com", name: "SID", encValue: Data([0xEE, 0xFF]), path: "/", expires: 13_350_000_000_000_000, secure: true, httpOnly: true),
        ])

        let rows = try SQLiteCookieReader.readCookies(databaseURL: tmp, hostFilter: ["%.x.com", "%.twitter.com"])
        #expect(rows.count == 2)
        let hosts = Set(rows.map { $0.host })
        #expect(hosts == Set([".x.com", ".twitter.com"]))
        let xRow = rows.first { $0.host == ".x.com" }!
        #expect(xRow.name == "auth_token")
        #expect(xRow.encryptedValue == Data([0xAA, 0xBB]))
        #expect(xRow.isSecure == true)
        #expect(xRow.isHTTPOnly == true)
    }

    @Test func emptyHostFilterReturnsAllRows() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sqlite-empty-filter-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try Self.makeFixture(at: tmp, rows: [
            (host: ".x.com", name: "auth_token", encValue: Data([0xAA]), path: "/", expires: 0, secure: true, httpOnly: true),
            (host: ".google.com", name: "SID", encValue: Data([0xBB]), path: "/", expires: 0, secure: true, httpOnly: true),
        ])

        let rows = try SQLiteCookieReader.readCookies(databaseURL: tmp, hostFilter: [])
        #expect(rows.count == 2)
    }

    @Test func missingDatabaseThrows() {
        let nonexistent = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent-\(UUID().uuidString).sqlite")
        do {
            _ = try SQLiteCookieReader.readCookies(databaseURL: nonexistent, hostFilter: ["%.x.com"])
            Issue.record("Expected throw")
        } catch let error as SQLiteCookieReaderError {
            #expect(error == .databaseNotFound)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
