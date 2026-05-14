import Foundation
import Testing
@testable import Susurro

@Suite("MP3Concatenator")
struct MP3ConcatenatorTests {

    // A minimal valid MP3 frame: 0xFF 0xFB is a common MPEG1 Layer-3 header.
    // 0xFB = 1111_1011 → high nibble 0xF0, valid sync.
    private func makeValidFrame(filler: UInt8 = 0xAA, length: Int = 104) -> Data {
        var d = Data([0xFF, 0xFB, 0x90, 0x44])
        d.append(Data(repeating: filler, count: length - 4))
        return d
    }

    // A junk chunk that does NOT start with a frame sync.
    private func makeJunkChunk() -> Data {
        Data([0x00, 0x01, 0x02, 0x03] + Array(repeating: 0xAA, count: 96))
    }

    // MARK: - Empty input

    @Test func emptyInputProducesEmptyData() {
        let result = MP3Concatenator.concatenate([])
        #expect(result.isEmpty)
    }

    @Test func emptyInputWritesEmptyFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp3")
        try MP3Concatenator.write([], to: tmp)
        let data = try Data(contentsOf: tmp)
        #expect(data.isEmpty)
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Valid frames

    @Test func threeValidFramesConcatenateCleanly() {
        let frame = makeValidFrame()
        let chunks = [frame, frame, frame]
        let result = MP3Concatenator.concatenate(chunks)
        #expect(result.count == frame.count * 3)
    }

    // MARK: - Empty chunk skipping

    @Test func emptyChunkIsSkipped() {
        let frame = makeValidFrame()
        let chunks: [Data] = [frame, Data(), frame]
        let result = MP3Concatenator.concatenate(chunks)
        #expect(result.count == frame.count * 2)
    }

    // MARK: - Junk leading chunk skipping

    @Test func junkLeadingChunkIsSkipped() {
        let frame = makeValidFrame()
        let junk = makeJunkChunk()
        let chunks: [Data] = [junk, frame, frame]
        let result = MP3Concatenator.concatenate(chunks)
        // Only the two valid frames should be present.
        #expect(result.count == frame.count * 2)
        // And the result starts with the valid frame sync.
        #expect(result.first == 0xFF)
    }

    // MARK: - write creates parent directory

    @Test func writeCreatesParentDirectoryIfMissing() throws {
        let nested = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)    // non-existent directory
            .appendingPathComponent("audio")
            .appendingPathComponent("test.mp3")

        let frame = makeValidFrame()
        try MP3Concatenator.write([frame], to: nested)

        let written = try Data(contentsOf: nested)
        #expect(written == frame)

        // Cleanup
        let parent = nested.deletingLastPathComponent().deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
    }

    // MARK: - Sync byte variations

    @Test func frameWithHighNibble0xE0IsAccepted() {
        // 0xFF 0xE0 = MPEG 2.5 / free bitrate — still a valid sync.
        var d = Data([0xFF, 0xE0, 0x90, 0x00])
        d.append(Data(repeating: 0, count: 96))
        let result = MP3Concatenator.concatenate([d])
        #expect(result == d)
    }
}
