import Foundation

let args = Array(CommandLine.arguments.dropFirst())

func printUsage() {
	print("""
	Usage:
	  susurro read --stdin [--cwd <path>]                    Read text from stdin
	  susurro health                                         Check backend health
	  susurro tts (--text <text> | --stdin) [--lang <lang>] Synthesize TTS to stdout (MP3)
	  susurro extract <url>                                  Extract article text as JSON
	  susurro pronunciations list                            List stored pronunciations
	  susurro pronunciations add --lang <l> --word <w> --replacement <r>  Add/update entry
	  susurro pronunciations remove --lang <l> --word <w>   Remove entry
	  susurro pronunciations candidates --lang <l> --word <w>  List candidates as JSON
	  susurro pronunciations preview --lang <l> --ssml <s>  Preview SSML (MP3 to stdout)
	  susurro stop                                           Stop current playback
	  susurro --version                                      Print version and exit
	  susurro --help                                         Print this help and exit
	""")
}

func printJSON(_ obj: [String: Any]) {
	if let data = try? JSONSerialization.data(withJSONObject: obj),
	   let str = String(data: data, encoding: .utf8) {
		print(str)
	}
}

func readStdin() -> String {
	var lines: [String] = []
	if let first = readLine(strippingNewline: false) {
		lines.append(first)
	}
	while let line = readLine(strippingNewline: false) {
		lines.append(line)
	}
	return lines.joined()
}

switch args.first {
case "--version":
	print("susurro \(cliVersion)")
	exit(0)

case "--help":
	printUsage()
	exit(0)

case "read":
	let remaining = Array(args.dropFirst())
	guard remaining.contains("--stdin") else {
		fputs("error: 'read' requires --stdin\n", stderr)
		printUsage()
		exit(2)
	}

	var cwd: String?
	if let cwdIndex = remaining.firstIndex(of: "--cwd") {
		let valueIndex = remaining.index(after: cwdIndex)
		if valueIndex < remaining.endIndex {
			let candidate = remaining[valueIndex]
			if candidate.hasPrefix("--") {
				fputs("error: --cwd requires a path argument\n", stderr)
				exit(2)
			}
			cwd = candidate
		}
	}

	let text = readLine(strippingNewline: false) ?? ""
	var lines = [text]
	while let line = readLine(strippingNewline: false) {
		lines.append(line)
	}
	let input = lines.joined()
	guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
		fputs("error: stdin is empty\n", stderr)
		exit(2)
	}

	do {
		let response = try sendRead(text: input, cwd: cwd)
		let data = try JSONSerialization.data(withJSONObject: response)
		print(String(data: data, encoding: .utf8) ?? "{}")
		let ok = response["ok"] as? Bool ?? false
		exit(ok ? 0 : 1)
	} catch IPCClientError.timeout {
		fputs("error: could not connect to Susurro within timeout\n", stderr)
		exit(1)
	} catch {
		fputs("error: \(error.localizedDescription)\n", stderr)
		exit(1)
	}

case "health":
	do {
		let resp = try sendHealth()
		printJSON(resp)
		exit(resp["ok"] as? Bool == true ? 0 : 1)
	} catch IPCClientError.timeout {
		fputs("error: could not connect to Susurro within timeout\n", stderr)
		exit(1)
	} catch {
		fputs("error: \(error.localizedDescription)\n", stderr)
		exit(1)
	}

case "tts":
	let remaining = Array(args.dropFirst())
	let lang = parseFlag("--lang", in: remaining)

	let text: String
	if remaining.contains("--stdin") {
		let input = readStdin()
		guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			fputs("error: stdin is empty\n", stderr)
			exit(2)
		}
		text = input
	} else if let textFlag = parseFlag("--text", in: remaining) {
		text = textFlag
	} else {
		fputs("error: tts requires --text <text> or --stdin\n", stderr)
		printUsage()
		exit(2)
	}

	do {
		let ok = try sendTTSStream(text: text, language: lang, into: FileHandle.standardOutput)
		exit(ok ? 0 : 1)
	} catch IPCClientError.timeout {
		fputs("error: could not connect to Susurro within timeout\n", stderr)
		exit(1)
	} catch {
		fputs("error: \(error.localizedDescription)\n", stderr)
		exit(1)
	}

case "extract":
	guard let url = args.dropFirst().first else {
		fputs("error: extract requires <url>\n", stderr)
		printUsage()
		exit(2)
	}
	do {
		let resp = try sendExtract(url: url)
		printJSON(resp)
		exit(resp["ok"] as? Bool == true ? 0 : 1)
	} catch IPCClientError.timeout {
		fputs("error: could not connect to Susurro within timeout\n", stderr)
		exit(1)
	} catch {
		fputs("error: \(error.localizedDescription)\n", stderr)
		exit(1)
	}

case "pronunciations":
	let subArgs = Array(args.dropFirst())
	switch subArgs.first {
	case "list":
		do {
			let resp = try sendPronList()
			printJSON(resp)
			exit(resp["ok"] as? Bool == true ? 0 : 1)
		} catch IPCClientError.timeout {
			fputs("error: could not connect to Susurro within timeout\n", stderr)
			exit(1)
		} catch {
			fputs("error: \(error.localizedDescription)\n", stderr)
			exit(1)
		}

	case "add":
		guard let lang = parseFlag("--lang", in: subArgs),
			  let word = parseFlag("--word", in: subArgs),
			  let replacement = parseFlag("--replacement", in: subArgs)
		else {
			fputs("error: pronunciations add requires --lang, --word, --replacement\n", stderr)
			printUsage()
			exit(2)
		}
		do {
			let resp = try sendPronUpsert(language: lang, word: word, replacement: replacement)
			printJSON(resp)
			exit(resp["ok"] as? Bool == true ? 0 : 1)
		} catch IPCClientError.timeout {
			fputs("error: could not connect to Susurro within timeout\n", stderr)
			exit(1)
		} catch {
			fputs("error: \(error.localizedDescription)\n", stderr)
			exit(1)
		}

	case "remove":
		guard let lang = parseFlag("--lang", in: subArgs),
			  let word = parseFlag("--word", in: subArgs)
		else {
			fputs("error: pronunciations remove requires --lang and --word\n", stderr)
			printUsage()
			exit(2)
		}
		do {
			let resp = try sendPronDelete(language: lang, word: word)
			printJSON(resp)
			exit(resp["ok"] as? Bool == true ? 0 : 1)
		} catch IPCClientError.timeout {
			fputs("error: could not connect to Susurro within timeout\n", stderr)
			exit(1)
		} catch {
			fputs("error: \(error.localizedDescription)\n", stderr)
			exit(1)
		}

	case "candidates":
		guard let lang = parseFlag("--lang", in: subArgs),
			  let word = parseFlag("--word", in: subArgs)
		else {
			fputs("error: pronunciations candidates requires --lang and --word\n", stderr)
			printUsage()
			exit(2)
		}
		do {
			let resp = try sendPronCandidates(word: word, language: lang)
			printJSON(resp)
			exit(resp["ok"] as? Bool == true ? 0 : 1)
		} catch IPCClientError.timeout {
			fputs("error: could not connect to Susurro within timeout\n", stderr)
			exit(1)
		} catch {
			fputs("error: \(error.localizedDescription)\n", stderr)
			exit(1)
		}

	case "preview":
		guard let lang = parseFlag("--lang", in: subArgs),
			  let ssml = parseFlag("--ssml", in: subArgs)
		else {
			fputs("error: pronunciations preview requires --lang and --ssml\n", stderr)
			printUsage()
			exit(2)
		}
		do {
			let resp = try sendPronPreview(ssml: ssml, language: lang)
			if resp["ok"] as? Bool == true,
			   let data = resp["data"] as? [String: Any],
			   let base64 = data["audioBase64"] as? String,
			   let audioData = Data(base64Encoded: base64) {
				FileHandle.standardOutput.write(audioData)
				exit(0)
			} else {
				printJSON(resp)
				exit(1)
			}
		} catch IPCClientError.timeout {
			fputs("error: could not connect to Susurro within timeout\n", stderr)
			exit(1)
		} catch {
			fputs("error: \(error.localizedDescription)\n", stderr)
			exit(1)
		}

	default:
		if let unknown = subArgs.first {
			fputs("error: unknown pronunciations subcommand '\(unknown)'\n", stderr)
		} else {
			fputs("error: pronunciations requires a subcommand\n", stderr)
		}
		printUsage()
		exit(2)
	}

case "stop":
	do {
		let resp = try sendStop()
		printJSON(resp)
		exit(0)
	} catch IPCClientError.timeout {
		fputs("error: could not connect to Susurro within timeout\n", stderr)
		exit(1)
	} catch {
		fputs("error: \(error.localizedDescription)\n", stderr)
		exit(1)
	}

default:
	if let unknown = args.first {
		fputs("error: unknown command '\(unknown)'\n", stderr)
	} else {
		fputs("error: no command specified\n", stderr)
	}
	printUsage()
	exit(2)
}
