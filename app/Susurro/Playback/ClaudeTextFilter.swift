import Foundation

enum ClaudeTextFilter {
	static func filter(_ text: String) -> String {
		var result = text

		result = stripFencedCodeBlocks(result)
		result = stripInlineCode(result)
		result = stripMarkdownLinks(result)
		result = stripURLs(result)
		result = stripPaths(result)
		result = stripCLIFlags(result)
		result = collapseMarkdownStructure(result)
		result = collapseWhitespace(result)

		guard result.contains(where: { $0.isLetter }) else { return "" }
		return result
	}

	private static func stripFencedCodeBlocks(_ text: String) -> String {
		let pattern = #"```[^\n]*\n[\s\S]*?```"#
		return replace(pattern, in: text, with: "")
	}

	private static func stripInlineCode(_ text: String) -> String {
		let pattern = #"`[^`]+`"#
		return replace(pattern, in: text, with: "")
	}

	private static func stripMarkdownLinks(_ text: String) -> String {
		let pattern = #"\[([^\]]*)\]\([^)]*\)"#
		return replace(pattern, in: text, with: "$1")
	}

	private static func stripURLs(_ text: String) -> String {
		let pattern = #"(?:https?|file)://\S+"#
		return replace(pattern, in: text, with: "")
	}

	private static func stripPaths(_ text: String) -> String {
		let pattern = #"(?<![a-zA-Z0-9])(?:~|\.|\.\.)?/(?:[a-zA-Z0-9_.\-]+/)*[a-zA-Z0-9_.\-]+"#
		return replace(pattern, in: text, with: "")
	}

	private static func stripCLIFlags(_ text: String) -> String {
		let pattern = #"(?<!\w)--[a-zA-Z][a-zA-Z0-9\-]*|-[a-zA-Z](?=\s+[a-zA-Z0-9_\-/])"#
		return replace(pattern, in: text, with: "")
	}

	private static func collapseMarkdownStructure(_ text: String) -> String {
		var result = text

		result = replace(#"^#{1,6}\s+"#, options: [.anchorsMatchLines], in: result, with: "")
		result = replace(#"^>\s?"#, options: [.anchorsMatchLines], in: result, with: "")
		result = replace(#"^[ \t]*(?:\d+\.|[-*])\s+"#, options: [.anchorsMatchLines], in: result, with: "")
		result = replace(#"\*\*(.+?)\*\*"#, in: result, with: "$1")
		result = replace(#"__(.+?)__"#, in: result, with: "$1")
		result = replace(#"\*(.+?)\*"#, in: result, with: "$1")
		result = replace(#"_(.+?)_"#, in: result, with: "$1")

		return result
	}

	private static func collapseWhitespace(_ text: String) -> String {
		var result = replace(#"\n{3,}"#, in: text, with: "\n\n")
		result = replace(#"[ \t]+"#, in: result, with: " ")
		return result.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func replace(
		_ pattern: String,
		options: NSRegularExpression.Options = [],
		in text: String,
		with template: String
	) -> String {
		guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
			return text
		}
		let range = NSRange(text.startIndex..., in: text)
		return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
	}
}
