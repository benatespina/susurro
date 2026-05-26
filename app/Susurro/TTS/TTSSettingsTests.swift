import Foundation
import Testing
@testable import Susurro

@Suite("TTSSettings")
@MainActor
struct TTSSettingsTests {
	private static let providerKey = "tts.provider"
	private static let translateToSpanishKey = "translation.toSpanish.enabled"

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

		// Pre-seed UserDefaults; verify TTSSettings reads it correctly.
		UserDefaults.standard.set(TTSProviderKind.azure.rawValue, forKey: Self.providerKey)
		let settings = TTSSettings()
		#expect(settings.provider == .azure)
	}

	@Test("TTSProviderKind.edge rawValue is 'edge'")
	func providerKindEdgeRawValue() {
		#expect(TTSProviderKind.edge.rawValue == "edge")
	}

	@Test("TTSProviderKind.azure rawValue is 'azure'")
	func providerKindAzureRawValue() {
		#expect(TTSProviderKind.azure.rawValue == "azure")
	}

	@Test("translateToSpanish defaults to false when key is absent")
	func translateToSpanishDefaultsFalse() {
		UserDefaults.standard.removeObject(forKey: Self.translateToSpanishKey)
		defer { UserDefaults.standard.removeObject(forKey: Self.translateToSpanishKey) }

		let settings = TTSSettings()
		#expect(settings.translateToSpanish == false)
	}

	@Test("translateToSpanish persists true via UserDefaults")
	func translateToSpanishPersistsTrue() {
		UserDefaults.standard.removeObject(forKey: Self.translateToSpanishKey)
		defer { UserDefaults.standard.removeObject(forKey: Self.translateToSpanishKey) }

		let settings = TTSSettings()
		settings.translateToSpanish = true
		#expect(UserDefaults.standard.bool(forKey: Self.translateToSpanishKey) == true)
	}

	@Test("TTSSettings round-trips translateToSpanish across instances")
	func translateToSpanishRoundTrips() {
		UserDefaults.standard.removeObject(forKey: Self.translateToSpanishKey)
		defer { UserDefaults.standard.removeObject(forKey: Self.translateToSpanishKey) }

		let writer = TTSSettings()
		writer.translateToSpanish = true

		let reader = TTSSettings()
		#expect(reader.translateToSpanish == true)
	}
}
