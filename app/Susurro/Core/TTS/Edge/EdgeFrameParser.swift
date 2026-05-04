import Foundation

/// Parses text and binary WebSocket frames sent by the Microsoft Edge TTS service.
///
/// The Edge TTS protocol sends two kinds of frames:
/// - **Text frames**: plain-text headers followed by `\r\n\r\n` and a JSON/SSML body.
/// - **Binary frames**: a 2-byte big-endian header-length prefix, ASCII headers,
///   and raw audio bytes.
enum EdgeFrameParser {

    // MARK: - Text frames

    /// Parses a text WebSocket frame into its path, header map, and body.
    ///
    /// Frame structure:
    /// ```
    /// Header1:Value1\r\n
    /// Header2:Value2\r\n
    /// \r\n
    /// <body>
    /// ```
    ///
    /// - Parameter s: The raw text frame string.
    /// - Returns: A tuple of `(path, headers, body)` where `path` is the value of the
    ///   `Path` header and `headers` is a map of all header key/value pairs.
    static func parseTextFrame(_ s: String) -> (path: String, headers: [String: String], body: String) {
        // Split header section from body on \r\n\r\n, fall back to \n\n
        let separator: String
        let components: [String]
        if s.contains("\r\n\r\n") {
            separator = "\r\n\r\n"
            components = s.components(separatedBy: separator)
        } else {
            separator = "\n\n"
            components = s.components(separatedBy: separator)
        }

        let headerSection = components.first ?? ""
        let body = components.dropFirst().joined(separator: separator)

        // Parse header lines: split on \r\n or \n
        let headerLines: [String]
        if headerSection.contains("\r\n") {
            headerLines = headerSection.components(separatedBy: "\r\n")
        } else {
            headerLines = headerSection.components(separatedBy: "\n")
        }

        var headers: [String: String] = [:]
        for line in headerLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Split on first ':' only
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex ..< colonIndex])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let path = headers["Path"] ?? ""
        return (path: path, headers: headers, body: body)
    }

    // MARK: - Binary frames

    /// Parses a binary WebSocket frame into its path, header map, and audio payload.
    ///
    /// Binary frame structure:
    /// ```
    /// [2 bytes big-endian header length][<headerLen> bytes ASCII headers][audio bytes]
    /// ```
    ///
    /// - Parameter data: The raw binary frame.
    /// - Returns: A tuple of `(path, headers, audio)` or `nil` if the frame is malformed.
    static func parseBinaryFrame(_ data: Data) -> (path: String?, headers: [String: String], audio: Data)? {
        guard data.count >= 2 else { return nil }

        // First 2 bytes: big-endian header length
        let headerLen = Int(data[0]) << 8 | Int(data[1])
        guard data.count >= 2 + headerLen else { return nil }

        let headerBytes = data[2 ..< 2 + headerLen]
        let audio = data[(2 + headerLen)...]

        guard let headerString = String(bytes: headerBytes, encoding: .ascii) else { return nil }

        // Parse header lines separated by \r\n
        var headers: [String: String] = [:]
        let lines = headerString.components(separatedBy: "\r\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex ..< colonIndex])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let path = headers["Path"]
        return (path: path, headers: headers, audio: Data(audio))
    }
}
