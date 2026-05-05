import Testing
@testable import Susurro

@Suite struct SSMLEscapeTests {

    @Test func escapeAmpersand() {
        #expect(SSMLEscape.escape("a & b") == "a &amp; b")
    }

    @Test func escapeLessThan() {
        #expect(SSMLEscape.escape("a < b") == "a &lt; b")
    }

    @Test func escapeGreaterThan() {
        #expect(SSMLEscape.escape("a > b") == "a &gt; b")
    }

    @Test func escapeQuotesPassThrough() {
        // escape() matches Python xml.sax.saxutils.escape() with no extra entities:
        // double and single quotes are NOT escaped.
        #expect(SSMLEscape.escape("don't & say \"hi\"") == "don't &amp; say \"hi\"")
    }

    @Test func escapeAllThreeSpecials() {
        #expect(SSMLEscape.escape("a & b < c > d") == "a &amp; b &lt; c &gt; d")
    }

    @Test func escapePlainTextUnchanged() {
        #expect(SSMLEscape.escape("hello world") == "hello world")
    }

    @Test func quoteAttrNoSingleQuote() {
        // No single quote → wrap in single quotes
        let result = SSMLEscape.quoteAttr("hello world")
        #expect(result == "'hello world'")
    }

    @Test func quoteAttrNoDoubleQuote() {
        // Has single quote but no double quote → wrap in double quotes
        let result = SSMLEscape.quoteAttr("it's fine")
        #expect(result == "\"it's fine\"")
    }

    @Test func quoteAttrBothQuotes() {
        // Has both → escape " and wrap in double quotes
        let result = SSMLEscape.quoteAttr("say \"it's\" done")
        #expect(result == "\"say &quot;it's&quot; done\"")
    }

    @Test func quoteAttrRoundTripsIPA() {
        // IPA strings should not contain quotes — wrap in single quotes
        let ipa = "ˈapi"
        let result = SSMLEscape.quoteAttr(ipa)
        #expect(result.hasPrefix("'"))
        #expect(result.hasSuffix("'"))
        #expect(result.contains(ipa))
    }
}
