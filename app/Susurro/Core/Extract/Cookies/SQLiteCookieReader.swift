import Foundation
import SQLite3

struct RawCookieRow: Sendable, Equatable {
    let host: String
    let name: String
    let plaintextValue: String       // value column (often empty)
    let encryptedValue: Data         // encrypted_value column
    let path: String
    let expiresUTC: Int64
    let isSecure: Bool
    let isHTTPOnly: Bool
}

enum SQLiteCookieReaderError: Error, Equatable {
    case databaseNotFound
    case copyFailed
    case openFailed(Int32)
    case prepareFailed(Int32)
    case stepFailed(Int32)
}

struct SQLiteCookieReader {
    /// Read rows matching any of the `hostFilter` LIKE patterns from a Chromium cookies SQLite DB.
    /// The source DB is copied to a temp path first to avoid lock contention with a running browser.
    static func readCookies(databaseURL: URL, hostFilter: [String]) throws -> [RawCookieRow] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: databaseURL.path) else {
            throw SQLiteCookieReaderError.databaseNotFound
        }

        let tempDir = fm.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("susurro-cookies-\(UUID().uuidString).sqlite")
        defer { try? fm.removeItem(at: tempURL) }

        do {
            try fm.copyItem(at: databaseURL, to: tempURL)
        } catch {
            throw SQLiteCookieReaderError.copyFailed
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(tempURL.path, &db, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw SQLiteCookieReaderError.openFailed(openResult)
        }
        defer { sqlite3_close(db) }

        // Build WHERE clause only when a filter is provided; empty filter selects all rows.
        let whereClause: String
        if hostFilter.isEmpty {
            whereClause = ""
        } else {
            let placeholders = Array(repeating: "host_key LIKE ?", count: hostFilter.count).joined(separator: " OR ")
            whereClause = "WHERE \(placeholders)"
        }
        let sql = """
        SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly
        FROM cookies
        \(whereClause)
        """

        var stmt: OpaquePointer?
        let prepResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepResult == SQLITE_OK, let stmt else {
            sqlite3_finalize(stmt)
            throw SQLiteCookieReaderError.prepareFailed(prepResult)
        }
        defer { sqlite3_finalize(stmt) }

        // SQLITE_TRANSIENT so SQLite copies the strings
        if !hostFilter.isEmpty {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (i, pattern) in hostFilter.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), pattern, -1, SQLITE_TRANSIENT)
            }
        }

        var rows: [RawCookieRow] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            if step != SQLITE_ROW {
                throw SQLiteCookieReaderError.stepFailed(step)
            }

            func textColumn(_ idx: Int32) -> String {
                guard let cString = sqlite3_column_text(stmt, idx) else { return "" }
                return String(cString: cString)
            }
            func blobColumn(_ idx: Int32) -> Data {
                guard let blobPtr = sqlite3_column_blob(stmt, idx) else { return Data() }
                let length = Int(sqlite3_column_bytes(stmt, idx))
                return Data(bytes: blobPtr, count: length)
            }

            let row = RawCookieRow(
                host: textColumn(0),
                name: textColumn(1),
                plaintextValue: textColumn(2),
                encryptedValue: blobColumn(3),
                path: textColumn(4),
                expiresUTC: sqlite3_column_int64(stmt, 5),
                isSecure: sqlite3_column_int(stmt, 6) != 0,
                isHTTPOnly: sqlite3_column_int(stmt, 7) != 0
            )
            rows.append(row)
        }

        return rows
    }
}
