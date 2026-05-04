import Foundation
import Testing
@testable import Susurro

@Suite("TTSSettings")
@MainActor
struct TTSSettingsTests {
	private static let autoReadKey = "claude.autoRead.enabled"
	private static let providerKey = "tts.provider"

	@Test("autoReadEnabled defaults to false when key is absent")
	func autoReadEnabledDefaultsFalse() {
		UserDefaults.standard.removeObject(forKey: Self.autoReadKey)
		defer { UserDefaults.standard.removeObject(forKey: Self.autoReadKey) }

		let settings = TTSSettings()
		#expect(settings.autoReadEnabled == false)
	}

	@Test("autoReadEnabled persists true via UserDefaults")
	func autoReadEnabledPersistsTrue() {
		UserDefaults.standard.removeObject(forKey: Self.autoReadKey)
		defer { UserDefaults.standard.removeObject(forKey: Self.autoReadKey) }

		let settings = TTSSettings()
		settings.autoReadEnabled = true
		#expect(UserDefaults.standard.bool(forKey: Self.autoReadKey) == true)
	}

	@Test("autoReadEnabled persists false via UserDefaults")
	func autoReadEnabledPersistsFalse() {
		UserDefaults.standard.set(true, forKey: Self.autoReadKey)
		defer { UserDefaults.standard.removeObject(forKey: Self.autoReadKey) }

		let settings = TTSSettings()
		settings.autoReadEnabled = false
		#expect(UserDefaults.standard.bool(forKey: Self.autoReadKey) == false)
	}

	@Test("TTSSettings round-trips autoReadEnabled across instances")
	func autoReadEnabledRoundTrips() {
		UserDefaults.standard.removeObject(forKey: Self.autoReadKey)
		defer { UserDefaults.standard.removeObject(forKey: Self.autoReadKey) }

		let writer = TTSSettings()
		writer.autoReadEnabled = true

		let reader = TTSSettings()
		#expect(reader.autoReadEnabled == true)
	}

	@Test("provider defaults to edge")
	func providerDefaultsToEdge() {
		UserDefaults.standard.removeObject(forKey: Self.providerKey)
		defer { UserDefaults.standard.removeObject(forKey: Self.providerKey) }

		let settings = TTSSettings()
		#expect(settings.provider == TTSProviderKind.edge)
	}

	@Test("provider persists to UserDefaults")
	func providerPersistsToUserDefaults() {
		UserDefaults.standard.removeObject(forKey: Self.providerKey)
		defer { UserDefaults.standard.removeObject(forKey: Self.providerKey) }

		let settings = TTSSettings()
		settings.provider = .azure
		#expect(UserDefaults.standard.string(forKey: Self.providerKey) == TTSProviderKind.azure.rawValue)
	}

	@Test("TTSProviderKind.edge rawValue is 'edge'")
	func providerKindEdgeRawValue() {
		#expect(TTSProviderKind.edge.rawValue == "edge")
	}

	@Test("TTSProviderKind.azure rawValue is 'azure'")
	func providerKindAzureRawValue() {
		#expect(TTSProviderKind.azure.rawValue == "azure")
	}
}
