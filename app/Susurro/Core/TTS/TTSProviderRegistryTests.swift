import Foundation
import Testing
@testable import Susurro

// MARK: - Stub provider

actor StubProvider: TTSProvider {
    var warmupCalls = 0
    var warmupError: Error?

    func setWarmupError(_ error: Error?) {
        warmupError = error
    }

    func warmup() async throws {
        warmupCalls += 1
        if let e = warmupError { throw e }
    }

    func synthesize(text: String, language: String) async throws -> Data { Data() }

    nonisolated func synthesizeStream(text: String, language: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    nonisolated func synthesizeChunks(_ chunks: [String], language: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    nonisolated func synthesizeChunked(text: String, language: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func synthesizePreview(ssml: String, language: String) async throws -> Data { Data() }
}

// MARK: - Tests

@Suite("TTSProviderRegistry", .serialized)
@MainActor
struct TTSProviderRegistryTests {

    @Test("swapCallsWarmupOnce — warmup called exactly once on swap")
    func swapCallsWarmupOnce() async throws {
        let stub = StubProvider()
        let registry = TTSProviderRegistry(
            makeEdge: { stub },
            makeAzure: { stub },
            keyProvider: { "fake-key" },
            regionProvider: { "eastus" }
        )

        await registry.swap(to: .edge)

        let calls = await stub.warmupCalls
        #expect(calls == 1)
    }

    @Test("swapToAzureWithoutKeyFallsBackToEdge — nil key triggers fallback + azureConfigurationRequired")
    func swapToAzureWithoutKeyFallsBackToEdge() async throws {
        let edgeStub = StubProvider()
        let azureStub = StubProvider()

        let registry = TTSProviderRegistry(
            makeEdge: { edgeStub },
            makeAzure: { azureStub },
            keyProvider: { nil },
            regionProvider: { "eastus" }
        )

        await registry.swap(to: .azure)

        // No Azure warmup because we short-circuited on missing key.
        let azureCalls = await azureStub.warmupCalls
        #expect(azureCalls == 0)
        // Fell back to Edge.
        let edgeCalls = await edgeStub.warmupCalls
        #expect(edgeCalls == 1)
        #expect(registry.azureConfigurationRequired == true)
    }

    @Test("warmupSuccessSetsIsReady — isReady becomes true after warmup succeeds")
    func warmupSuccessSetsIsReady() async throws {
        let stub = StubProvider()
        let registry = TTSProviderRegistry(
            makeEdge: { stub },
            makeAzure: { stub },
            keyProvider: { "key" },
            regionProvider: { "eastus" }
        )

        await registry.warmup()

        #expect(registry.isReady == true)
    }

    @Test("warmupAzureNotConfiguredFallsBackToEdge — azureNotConfigured on swap causes edge fallback")
    func warmupAzureNotConfiguredFallsBackToEdge() async throws {
        let edgeStub = StubProvider()
        let azureStub = StubProvider()
        await azureStub.setWarmupError(BackendError.azureNotConfigured)

        // Registry with valid credentials so it doesn't short-circuit on nil key,
        // but the Azure stub throws .azureNotConfigured from warmup itself.
        let registry = TTSProviderRegistry(
            makeEdge: { edgeStub },
            makeAzure: { azureStub },
            keyProvider: { "key" },
            regionProvider: { "eastus" }
        )

        // Swap to Azure — warmup throws .azureNotConfigured → fallback to Edge.
        await registry.swap(to: .azure)

        #expect(registry.azureConfigurationRequired == true)
        // Edge warmup was called for the fallback.
        let edgeCalls = await edgeStub.warmupCalls
        #expect(edgeCalls >= 1)
    }
}
