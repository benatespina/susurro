import Foundation

enum SSMLEscape {
    /// Escapes XML special characters: & < >
    /// Matches Python's xml.sax.saxutils.escape(text) with no extra entities —
    /// only &, <, > are escaped. Quotes pass through unchanged.
    static func escape(_ s: String) -> String {
        var out = s
        // Order matters: & must be first to avoid double-escaping
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        return out
    }

    /// Wraps value in quotes for use as an XML attribute.
    /// Matches Python's xml.sax.saxutils.quoteattr:
    ///   - If the value contains no single quote, wrap in single quotes.
    ///   - If the value contains no double quote, wrap in double quotes.
    ///   - Otherwise escape &, <, >, " and wrap in double quotes.
    static func quoteAttr(_ s: String) -> String {
        let hasSingle = s.contains("'")
        let hasDouble = s.contains("\"")

        if !hasSingle {
            // Wrap in single quotes; still escape &, <, >
            let inner = s
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "'\(inner)'"
        } else if !hasDouble {
            // Wrap in double quotes; still escape &, <, >
            let inner = s
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "\"\(inner)\""
        } else {
            // Both present: escape everything and wrap in double quotes
            var inner = s
            inner = inner.replacingOccurrences(of: "&", with: "&amp;")
            inner = inner.replacingOccurrences(of: "<", with: "&lt;")
            inner = inner.replacingOccurrences(of: ">", with: "&gt;")
            inner = inner.replacingOccurrences(of: "\"", with: "&quot;")
            return "\"\(inner)\""
        }
    }
}
