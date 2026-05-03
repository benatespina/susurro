import Foundation

enum CLIInstallerError: Error, LocalizedError {
	case appTranslocation
	case bundleNotFound
	case noWritableInstallDir
	case notOurSymlink

	var errorDescription: String? {
		switch self {
		case .appTranslocation:
			return "Move Susurro.app to /Applications first, then try again."
		case .bundleNotFound:
			return "Could not locate the susurro CLI inside the app bundle."
		case .noWritableInstallDir:
			return "Neither /opt/homebrew/bin nor /usr/local/bin is writable. Run the app with administrator privileges or manually symlink the CLI."
		case .notOurSymlink:
			return "The existing 'susurro' at the install path does not point to this app's CLI. Remove it manually first."
		}
	}
}

enum CLIInstaller {
	static func cliBundlePath() -> String {
		Bundle.main.bundlePath
			.appending("/Contents/Resources/bin/susurro")
	}

	static func defaultInstallPath() -> String {
		homebrewBinPath().appending("/susurro")
	}

	static func isInstalled() -> Bool {
		let installPath = defaultInstallPath()
		let fm = FileManager.default
		guard fm.fileExists(atPath: installPath) else { return false }
		guard let dest = try? fm.destinationOfSymbolicLink(atPath: installPath) else { return false }
		return dest == cliBundlePath()
	}

	static func install() throws {
		let bundlePath = Bundle.main.bundlePath
		if bundlePath.contains("AppTranslocation") {
			throw CLIInstallerError.appTranslocation
		}

		let cliSource = cliBundlePath()
		guard FileManager.default.fileExists(atPath: cliSource) else {
			throw CLIInstallerError.bundleNotFound
		}

		let binDir = homebrewBinPath()
		guard FileManager.default.isWritableFile(atPath: binDir) else {
			throw CLIInstallerError.noWritableInstallDir
		}

		let linkPath = binDir.appending("/susurro")
		let fm = FileManager.default

		if fm.fileExists(atPath: linkPath) {
			if let existing = try? fm.destinationOfSymbolicLink(atPath: linkPath),
			   existing != cliSource {
				throw CLIInstallerError.notOurSymlink
			}
			try fm.removeItem(atPath: linkPath)
		}

		try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: cliSource)
	}

	static func uninstall() throws {
		let linkPath = defaultInstallPath()
		let fm = FileManager.default
		guard fm.fileExists(atPath: linkPath) else { return }

		if let existing = try? fm.destinationOfSymbolicLink(atPath: linkPath),
		   existing != cliBundlePath() {
			throw CLIInstallerError.notOurSymlink
		}

		try fm.removeItem(atPath: linkPath)
	}

	private static func homebrewBinPath() -> String {
		let applesilicon = "/opt/homebrew/bin"
		let intel = "/usr/local/bin"
		let fm = FileManager.default
		if fm.fileExists(atPath: applesilicon) && fm.isWritableFile(atPath: applesilicon) {
			return applesilicon
		}
		return intel
	}
}
