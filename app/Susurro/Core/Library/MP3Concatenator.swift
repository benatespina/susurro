import Foundation
import os

enum MP3Concatenator {

    /// Returns a `Data` containing all valid MP3 frames from `chunks` concatenated together.
    ///
    /// A chunk is considered valid if its first two bytes satisfy the MP3 frame-sync pattern:
    /// the first byte is `0xFF` and the high nibble of the second byte is `0xF` or `0xE`
    /// (i.e. `0xFF 0xFx` or `0xFF 0xEx`).  Empty chunks and chunks that do not start
    /// with a sync word are logged and skipped.
    static func concatenate(_ chunks: [Data]) -> Data {
        var result = Data()
        for (index, chunk) in chunks.enumerated() {
            guard !chunk.isEmpty else {
                AppLogger.app.debug("MP3Concatenator: skipping empty chunk at index \(index, privacy: .public)")
                continue
            }
            guard isValidMP3Frame(chunk) else {
                AppLogger.app.debug("MP3Concatenator: skipping non-sync chunk at index \(index, privacy: .public) (first byte: 0x\(String(format: "%02X", chunk[chunk.startIndex]), privacy: .public))")
                continue
            }
            result.append(chunk)
        }
        return result
    }

    /// Concatenates `chunks` and writes the result atomically to `url`.
    /// Creates parent directories as needed.
    static func write(_ chunks: [Data], to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = concatenate(chunks)
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Private

    private static func isValidMP3Frame(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let byte0 = data[data.startIndex]
        let byte1 = data[data.startIndex + 1]
        guard byte0 == 0xFF else { return false }
        let highNibble = byte1 & 0xF0
        return highNibble == 0xF0 || highNibble == 0xE0
    }
}
