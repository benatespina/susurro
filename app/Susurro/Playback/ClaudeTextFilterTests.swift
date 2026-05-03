import Testing
@testable import Susurro

@Suite struct ClaudeTextFilterTests {

	// MARK: - Fenced code blocks

	@Test func stripsFencedCodeBlock() {
		let input = "Here is some code:\n```swift\nlet x = 1\n```\nDone."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("let x"))
		#expect(!result.contains("```"))
		#expect(result.contains("Done"))
	}

	@Test func stripsFencedCodeBlockWithBlankLinesInside() {
		let input = "Before.\n```\nline1\n\nline2\n```\nAfter."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("line1"))
		#expect(!result.contains("line2"))
		#expect(result.contains("Before"))
		#expect(result.contains("After"))
	}

	@Test func stripsFencedCodeBlockNoLanguageTag() {
		let input = "```\necho hello\n```"
		let result = ClaudeTextFilter.filter(input)
		#expect(result == "")
	}

	// MARK: - Inline code

	@Test func stripsInlineCode() {
		let input = "Run `ls -la` to list files."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("`"))
		#expect(!result.contains("ls -la"))
		#expect(result.contains("to list files"))
	}

	@Test func preservesApostrophesInProse() {
		let input = "You don't need to worry about it."
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("don't"))
	}

	@Test func preservesApostrophesAlongsideInlineCode() {
		let input = "It's fine to use `foo` here."
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("It's"))
		#expect(!result.contains("`"))
	}

	// MARK: - URLs

	@Test func stripsHttpURL() {
		let input = "See https://example.com/docs for details."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("https://"))
		#expect(result.contains("for details"))
	}

	@Test func stripsHttpsURL() {
		let input = "Visit https://www.apple.com now."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("apple.com"))
	}

	@Test func stripsFileURL() {
		let input = "Opened file://localhost/tmp/foo.txt successfully."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("file://"))
		#expect(result.contains("successfully"))
	}

	// MARK: - Markdown links

	@Test func keepsLinkTextDiscardsURL() {
		let input = "Check the [documentation](https://example.com/docs) for more."
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("documentation"))
		#expect(!result.contains("https://example.com"))
		#expect(!result.contains("]("))
	}

	@Test func keepsLinkTextWhenURLStripped() {
		let input = "See [release notes](https://github.com/foo/bar/releases) here."
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("release notes"))
		#expect(result.contains("here"))
	}

	// MARK: - File paths

	@Test func stripsAbsolutePath() {
		let input = "The file /usr/local/bin/swiftc was found."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("/usr/local"))
		#expect(result.contains("was found"))
	}

	@Test func stripsTildeRelativePath() {
		let input = "Config lives at ~/Library/Application Support."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("~/Library"))
	}

	@Test func stripsDotRelativePath() {
		let input = "Run ./build.sh to compile."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("./build.sh"))
		#expect(result.contains("to compile"))
	}

	@Test func stripsDotDotRelativePath() {
		let input = "Import from ../shared/utils."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("../shared"))
	}

	@Test func doesNotStripFractionInProse() {
		let input = "About 1/2 of the users reported this issue."
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("1/2"))
	}

	// MARK: - CLI flags

	@Test func stripsDoubleDashFlag() {
		let input = "Pass --verbose to the command."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("--verbose"))
	}

	@Test func stripsSingleDashFlagAdjacentToIdentifier() {
		let input = "Use -n 10 to limit output."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("-n"))
		#expect(result.contains("to limit output"))
	}

	@Test func doesNotStripHyphenInCompoundWord() {
		let input = "This is a well-known issue."
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("well-known"))
	}

	// MARK: - Markdown structure

	@Test func stripsHashHeaders() {
		let input = "# Introduction\nThis is the intro.\n## Section\nMore text."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains("#"))
		#expect(result.contains("Introduction"))
		#expect(result.contains("Section"))
	}

	@Test func stripsBulletList() {
		let input = "Steps:\n- First step\n- Second step\n* Third step"
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("First step"))
		#expect(result.contains("Second step"))
		#expect(result.contains("Third step"))
	}

	@Test func stripsNumberedList() {
		let input = "1. Do this\n2. Then that\n3. Finally this"
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("Do this"))
		#expect(result.contains("Then that"))
	}

	@Test func stripsBold() {
		let input = "This is **important** text."
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("important"))
		#expect(!result.contains("**"))
	}

	@Test func stripsItalic() {
		let input = "This is *emphasized* and _also emphasized_."
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("emphasized"))
		#expect(!result.contains("*emphasized*"))
		#expect(!result.contains("_also emphasized_"))
	}

	@Test func stripsBlockquotePrefix() {
		let input = "> This is a quote.\n> Spanning two lines."
		let result = ClaudeTextFilter.filter(input)
		#expect(!result.contains(">"))
		#expect(result.contains("This is a quote"))
		#expect(result.contains("Spanning two lines"))
	}

	// MARK: - Empty result

	@Test func returnsEmptyForCodeOnlyInput() {
		let input = "```python\nprint('hello')\n```"
		let result = ClaudeTextFilter.filter(input)
		#expect(result == "")
	}

	@Test func returnsEmptyForWhitespaceOnlyAfterFilter() {
		let input = "   \n\n   "
		let result = ClaudeTextFilter.filter(input)
		#expect(result == "")
	}

	@Test func returnsNonEmptyForMixedProseAndCode() {
		let input = "Here is the answer.\n```swift\nlet x = 1\n```"
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("Here is the answer"))
	}

	@Test func returnsProseForShortToolCallWithInlineCode() {
		let input = "I'll run `ls` now."
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("run"))
		#expect(!result.contains("`"))
	}

	// MARK: - Golden fixtures

	@Test func goldenMixedClaudeResponse() {
		let input = """
		# Summary

		Here's what I found in your codebase. The main issue is in **PlaybackCoordinator** \
		where the async task isn't cancelled properly.

		## Fix

		Update the method like this:

		```swift
		func stop() async {
		    currentTask?.cancel()
		    currentTask = nil
		}
		```

		You can also check the [documentation](https://developer.apple.com/documentation) \
		for `Task.cancel()`. The file lives at /Users/me/project/PlaybackCoordinator.swift.

		- Make sure to call `await` before `stop()`
		- This is a well-known Swift concurrency pattern

		> Note: this applies to *all* cancellable tasks.
		"""
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("PlaybackCoordinator"))
		#expect(result.contains("async task"))
		#expect(result.contains("well-known"))
		#expect(!result.contains("```"))
		#expect(!result.contains("**"))
		#expect(!result.contains("developer.apple.com"))
		#expect(!result.contains("/Users/me"))
	}

	@Test func goldenCodeOnlyResponse() {
		let input = "```bash\nnpm install\nnpm run build\n```"
		let result = ClaudeTextFilter.filter(input)
		#expect(result == "")
	}

	@Test func goldenProseOnlyResponse() {
		let input = "The quick brown fox jumps over the lazy dog. It's a classic sentence used in typography."
		let result = ClaudeTextFilter.filter(input)
		#expect(result.contains("quick brown fox"))
		#expect(result.contains("It's"))
	}

	@Test func goldenToolCallOnlyShortResponse() {
		let input = "```\nls -la\n```"
		let result = ClaudeTextFilter.filter(input)
		#expect(result == "")
	}

	// MARK: - Idempotency

	@Test func idempotentOnMixedClaudeResponse() {
		let input = """
		# Title

		Some **bold** prose with `inline code` and a [link](https://example.com).

		```swift
		let x = 1
		```

		- bullet one
		- bullet two

		> A blockquote note.
		"""
		let once = ClaudeTextFilter.filter(input)
		let twice = ClaudeTextFilter.filter(once)
		#expect(once == twice)
	}

	@Test func idempotentOnCodeOnlyResponse() {
		let input = "```\nsome code\n```"
		let once = ClaudeTextFilter.filter(input)
		let twice = ClaudeTextFilter.filter(once)
		#expect(once == twice)
	}

	@Test func idempotentOnProseOnlyResponse() {
		let input = "This is plain prose. No special markdown here, just words."
		let once = ClaudeTextFilter.filter(input)
		let twice = ClaudeTextFilter.filter(once)
		#expect(once == twice)
	}
}
