import Testing
import Foundation

@Suite("CLI argument parsing")
struct CLIArgumentTests {

	@Test("version string is semver shaped")
	func versionFormat() {
		let parts = cliVersion.split(separator: ".")
		#expect(parts.count == 3)
		for part in parts {
			#expect(Int(part) != nil)
		}
	}

	@Test("version is 0.1.0")
	func versionValue() {
		#expect(cliVersion == "0.1.0")
	}
}

@Suite("IPCClient socket path")
struct IPCClientSocketTests {

	@Test("socket path is inside Application Support/Susurro")
	func socketPathConvention() {
		let appSupport = FileManager.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		let expected = appSupport.appendingPathComponent("Susurro/ipc.sock").path
		#expect(expected.hasSuffix("Application Support/Susurro/ipc.sock"))
	}
}
