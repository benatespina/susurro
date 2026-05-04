import Testing
@testable import Susurro

@Suite struct ChunkerTests {

    @Test func shortTextYieldsOneChunk() {
        let chunks = Chunker.chunk("Hello world.")
        #expect(chunks.count == 1)
        #expect(chunks[0] == "Hello world.")
    }

    @Test func manySentencesYieldMultipleChunks() {
        // Build enough sentences to exceed 350 chars
        var sentences: [String] = []
        for i in 1...20 {
            sentences.append("This is sentence number \(i) and it has some content in it.")
        }
        let text = sentences.joined(separator: " ")
        let chunks = Chunker.chunk(text)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.count <= Chunker.maxChars)
        }
    }

    @Test func longSentenceWithCommasGetsSplit() {
        // A single very long sentence with comma separators
        let parts = (1...25).map { "item number \($0) which has some extra content here" }
        let text = parts.joined(separator: ", ") + "."
        #expect(text.count > Chunker.maxChars)
        let chunks = Chunker.chunk(text)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.count <= Chunker.maxChars)
        }
    }

    @Test func commaLessLongSentenceGetsHardSliced() {
        let longWord = String(repeating: "a", count: 800)
        let chunks = Chunker.chunk(longWord)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.count <= Chunker.maxChars)
        }
    }

    @Test func ellipsisRecognizedAsSentenceBreak() {
        // Build two long sentences separated by ellipsis so they exceed maxChars together
        let first = String(repeating: "a", count: 200) + "\u{2026}"
        let second = String(repeating: "b", count: 200) + "."
        let text = first + " " + second
        let chunks = Chunker.chunk(text)
        // Should recognize the ellipsis as a sentence break and emit >= 2 chunks
        #expect(chunks.count >= 2)
    }

    @Test func whitespaceGetsTrimmed() {
        let chunks = Chunker.chunk("  Hello world.   ")
        #expect(chunks.count == 1)
        #expect(chunks[0] == "Hello world.")
    }

    @Test func emptyTextYieldsNoChunks() {
        #expect(Chunker.chunk("").isEmpty)
        #expect(Chunker.chunk("   ").isEmpty)
    }

    @Test func chunksAreNonEmpty() {
        let text = "One sentence. Another sentence here. And a final one too."
        let chunks = Chunker.chunk(text)
        for chunk in chunks {
            #expect(!chunk.isEmpty)
        }
    }
}
