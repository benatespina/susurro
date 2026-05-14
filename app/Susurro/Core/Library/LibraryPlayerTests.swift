import AVFoundation
import Foundation
import Testing
@testable import Susurro

@Suite("LibraryPlayer")
@MainActor
struct LibraryPlayerTests {

    private func makeTinyMP3URL() throws -> URL {
        let bundle = Bundle(for: LibraryPlayerTestHelper.self)
        if let url = bundle.url(forResource: "tiny", withExtension: "mp3") {
            return url
        }
        // Fallback: locate relative to this source file's bundle resources directory.
        // In unit-test bundles with BUNDLE_LOADER the fixture is in the test bundle.
        throw TestError.fixtureNotFound
    }

    private func makeItem() -> LibraryItem {
        LibraryItem(
            id: UUID(),
            createdAt: Date(),
            title: "Test",
            sourceURL: nil,
            sourceKind: .text,
            rawText: nil,
            status: .ready,
            audioFilename: "tiny.mp3",
            durationSeconds: nil,
            byteSize: nil,
            lastError: nil,
            playedAt: nil,
            driveFileID: nil
        )
    }

    @Test func playSetNowPlayingIDAndIsPlaying() throws {
        let player = LibraryPlayer()
        let item = makeItem()
        let url = try makeTinyMP3URL()
        player.play(item: item, audioURL: url)
        #expect(player.nowPlayingID == item.id)
        #expect(player.isPlaying == true)
    }

    @Test func pauseFlipsIsPlayingFalse() throws {
        let player = LibraryPlayer()
        let item = makeItem()
        let url = try makeTinyMP3URL()
        player.play(item: item, audioURL: url)
        player.pause()
        #expect(player.isPlaying == false)
        #expect(player.nowPlayingID == item.id)
    }

    @Test func resumeFlipsIsPlayingTrue() throws {
        let player = LibraryPlayer()
        let item = makeItem()
        let url = try makeTinyMP3URL()
        player.play(item: item, audioURL: url)
        player.pause()
        player.resume()
        #expect(player.isPlaying == true)
    }

    @Test func stopClearsNowPlayingIDAndResetsTimes() throws {
        let player = LibraryPlayer()
        let item = makeItem()
        let url = try makeTinyMP3URL()
        player.play(item: item, audioURL: url)
        player.stop()
        #expect(player.nowPlayingID == nil)
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
        #expect(player.duration == 0)
    }

    @Test func setRateUpdatesPlaybackRate() {
        let player = LibraryPlayer()
        player.setRate(1.5)
        #expect(player.playbackRate == 1.5)
    }

    @Test func playingSecondItemSupersedingFirst() throws {
        let player = LibraryPlayer()
        let item1 = makeItem()
        let item2 = makeItem()
        let url = try makeTinyMP3URL()
        player.play(item: item1, audioURL: url)
        #expect(player.nowPlayingID == item1.id)
        player.play(item: item2, audioURL: url)
        #expect(player.nowPlayingID == item2.id)
        #expect(player.isPlaying == true)
    }

    enum TestError: Error {
        case fixtureNotFound
    }
}

// Used purely to anchor `Bundle(for:)` lookups to the correct test bundle.
final class LibraryPlayerTestHelper: NSObject {}
