import Foundation

let args = CommandLine.arguments.dropFirst()

func printUsage() {
	print("""
	Usage:
	  susurro read --stdin [--cwd <path>]   Read text from stdin and send to Susurro
	  susurro --version                     Print version and exit
	  susurro --help                        Print this help and exit
	""")
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

	// Parse optional --cwd <path>
	var cwd: String? = nil
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

default:
	if let unknown = args.first {
		fputs("error: unknown command '\(unknown)'\n", stderr)
	} else {
		fputs("error: no command specified\n", stderr)
	}
	printUsage()
	exit(2)
}
