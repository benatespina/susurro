import Foundation
import Testing
@testable import Susurro

@Suite("LibraryItem")
struct LibraryItemTests {

    // MARK: - Codable round-trips

    @Test func roundTripPending() throws {
        let item = makeItem(status: .pending)
        let decoded = try roundTrip(item)
        #expect(decoded == item)
        #expect(decoded.status == .pending)
    }

    @Test func roundTripExtracting() throws {
        let item = makeItem(status: .extracting)
        let decoded = try roundTrip(item)
        #expect(decoded.status == .extracting)
    }

    @Test func roundTripSynthesizingWithProgress() throws {
        let item = makeItem(status: .synthesizing(progress: 0.42))
        let decoded = try roundTrip(item)
        #expect(decoded.status == .synthesizing(progress: 0.42))
    }

    @Test func roundTripSynthesizingNoProgress() throws {
        let item = makeItem(status: .synthesizing(progress: nil))
        let decoded = try roundTrip(item)
        #expect(decoded.status == .synthesizing(progress: nil))
    }

    @Test func roundTripUploading() throws {
        let item = makeItem(status: .uploading)
        let decoded = try roundTrip(item)
        #expect(decoded.status == .uploading)
    }

    @Test func roundTripReady() throws {
        let item = makeItem(status: .ready)
        let decoded = try roundTrip(item)
        #expect(decoded.status == .ready)
    }

    @Test func roundTripPlayed() throws {
        let item = makeItem(status: .played)
        let decoded = try roundTrip(item)
        #expect(decoded.status == .played)
    }

    @Test func roundTripArchived() throws {
        let item = makeItem(status: .archived)
        let decoded = try roundTrip(item)
        #expect(decoded.status == .archived)
    }

    @Test func roundTripFailed() throws {
        let item = makeItem(status: .failed(reason: "no network"))
        let decoded = try roundTrip(item)
        #expect(decoded.status == .failed(reason: "no network"))
    }

    // MARK: - URL-kind item

    @Test func urlKindCarriesSourceURL() throws {
        let item = LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: nil,
            sourceURL: "https://example.com/article",
            sourceKind: .url,
            rawText: nil,
            status: .pending,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil
        )
        let decoded = try roundTrip(item)
        #expect(decoded.sourceKind == .url)
        #expect(decoded.sourceURL == "https://example.com/article")
        #expect(decoded.rawText == nil)
    }

    @Test func textKindCarriesRawText() throws {
        let item = LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: nil,
            sourceURL: nil,
            sourceKind: .text,
            rawText: "This is some raw text to synthesize.",
            status: .pending,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil
        )
        let decoded = try roundTrip(item)
        #expect(decoded.sourceKind == .text)
        #expect(decoded.rawText == "This is some raw text to synthesize.")
        #expect(decoded.sourceURL == nil)
    }

    // MARK: - JSON stability with sortedKeys

    @Test func jsonOutputIsStableAcrossEncodings() throws {
        let item = makeItem(status: .pending)
        let encoder = makeEncoder()
        let data1 = try encoder.encode(item)
        let data2 = try encoder.encode(item)
        #expect(data1 == data2)
    }

    @Test func sortedKeysProducesConsistentOutput() throws {
        let item = makeItem(status: .failed(reason: "timeout"))
        let encoder = makeEncoder()
        let data = try encoder.encode(item)
        let json = try #require(String(data: data, encoding: .utf8))
        // With sortedKeys the "audioFilename" key should come before "byteSize"
        let audioRange = json.range(of: "audioFilename")
        let byteRange = json.range(of: "byteSize")
        if let ar = audioRange, let br = byteRange {
            #expect(ar.lowerBound < br.lowerBound)
        }
    }

    // MARK: - Helpers

    private func makeItem(status: LibraryItemStatus) -> LibraryItem {
        LibraryItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Test Item",
            sourceURL: "https://example.com",
            sourceKind: .url,
            rawText: nil,
            status: status,
            audioFilename: nil,
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil
        )
    }

    private func roundTrip(_ item: LibraryItem) throws -> LibraryItem {
        let encoder = makeEncoder()
        let decoder = makeDecoder()
        let data = try encoder.encode(item)
        return try decoder.decode(LibraryItem.self, from: data)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
