import Foundation
import Testing
@testable import Susurro

@Suite("EdgeFrameParser")
struct EdgeFrameParserTests {

    // MARK: - Text frame tests

    @Test("parses a typical turn.start text frame")
    func parseTurnStartTextFrame() {
        let frame = "X-RequestId:abc\r\nContent-Type:application/json; charset=utf-8\r\nPath:turn.start\r\n\r\n{}"
        let (path, headers, body) = EdgeFrameParser.parseTextFrame(frame)

        #expect(path == "turn.start")
        #expect(headers["X-RequestId"] == "abc")
        #expect(headers["Content-Type"] == "application/json; charset=utf-8")
        #expect(headers["Path"] == "turn.start")
        #expect(body == "{}")
    }

    @Test("parses a turn.end text frame with no leading headers")
    func parseTurnEndTextFrame() {
        let frame = "Path:turn.end\r\n\r\n"
        let (path, headers, body) = EdgeFrameParser.parseTextFrame(frame)

        #expect(path == "turn.end")
        #expect(headers["Path"] == "turn.end")
        #expect(body.isEmpty)
    }

    @Test("parses a frame using LF-only separators as fallback")
    func parseFrameWithLFSeparator() {
        let frame = "Path:audio.metadata\n\n{\"data\":1}"
        let (path, headers, _) = EdgeFrameParser.parseTextFrame(frame)
        #expect(path == "audio.metadata")
    }

    @Test("handles header values with colons (e.g. Content-Type)")
    func parsesHeaderValueContainingColon() {
        let frame = "Path:response\r\nContent-Type:application/json; charset=utf-8\r\n\r\nbody"
        let (_, headers, _) = EdgeFrameParser.parseTextFrame(frame)
        #expect(headers["Content-Type"] == "application/json; charset=utf-8")
    }

    // MARK: - Binary frame tests

    @Test("parses a well-formed binary audio frame")
    func parsesBinaryAudioFrame() {
        // Build header bytes
        let headerStr = "Path:audio\r\nX-StreamId:1\r\n"
        let headerBytes = headerStr.data(using: .ascii)!
        let headerLen = UInt16(headerBytes.count)

        // Assemble frame: 2 bytes length + header + 256 audio bytes
        var frameData = Data()
        frameData.append(UInt8(headerLen >> 8))    // high byte
        frameData.append(UInt8(headerLen & 0xFF))  // low byte
        frameData.append(contentsOf: headerBytes)
        frameData.append(contentsOf: Data(repeating: 0xAA, count: 256))

        let result = EdgeFrameParser.parseBinaryFrame(frameData)

        #expect(result != nil)
        #expect(result?.path == "audio")
        #expect(result?.headers["X-StreamId"] == "1")
        #expect(result?.audio.count == 256)
    }

    @Test("returns nil for empty data")
    func returnsNilForEmptyData() {
        let result = EdgeFrameParser.parseBinaryFrame(Data())
        #expect(result == nil)
    }

    @Test("returns nil for data shorter than 2 bytes")
    func returnsNilForSingleByte() {
        let result = EdgeFrameParser.parseBinaryFrame(Data([0x00]))
        #expect(result == nil)
    }

    @Test("returns nil when declared header length exceeds available data")
    func returnsNilForHeaderLengthExceedingData() {
        // Declare 100-byte header but only provide 10 bytes total
        var data = Data()
        data.append(0x00)
        data.append(0x64) // header length = 100
        data.append(contentsOf: Data(repeating: 0x41, count: 10)) // only 10 bytes
        let result = EdgeFrameParser.parseBinaryFrame(data)
        #expect(result == nil)
    }

    @Test("parses binary frame with zero-length audio (e.g. end sentinel)")
    func parsesBinaryFrameWithNoAudio() {
        let headerStr = "Path:audio\r\n"
        let headerBytes = headerStr.data(using: .ascii)!
        let headerLen = UInt16(headerBytes.count)

        var frameData = Data()
        frameData.append(UInt8(headerLen >> 8))
        frameData.append(UInt8(headerLen & 0xFF))
        frameData.append(contentsOf: headerBytes)
        // No audio bytes appended

        let result = EdgeFrameParser.parseBinaryFrame(frameData)
        #expect(result != nil)
        #expect(result?.path == "audio")
        #expect(result?.audio.count == 0)
    }
}
