import Testing
import ApplicationServices
@testable import Susurro

@Suite("SelectionReader")
struct SelectionReaderTests {
    @Test("cgRect(from:) extracts a known CGRect from AXValue")
    func cgRectFromAXValue() throws {
        var expected = CGRect(x: 10, y: 20, width: 300, height: 50)
        let axValue = AXValueCreate(.cgRect, &expected)
        let result = try #require(SelectionReader.cgRect(from: axValue!))
        #expect(result == expected)
    }

    @Test("cgRect(from:) returns nil for wrong AXValue type")
    func cgRectFromWrongType() {
        var point = CGPoint(x: 5, y: 10)
        let axValue = AXValueCreate(.cgPoint, &point)
        let result = SelectionReader.cgRect(from: axValue!)
        #expect(result == nil)
    }

    @Test("current() does not crash when called")
    func currentDoesNotCrash() {
        // This is a smoke test — we can't control AX state in unit tests.
        // We just verify it doesn't throw or crash.
        let _ = SelectionReader.current()
    }
}
