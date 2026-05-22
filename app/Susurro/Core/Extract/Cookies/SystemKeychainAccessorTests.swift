import Foundation
import Testing
@testable import Susurro

@Suite struct SystemKeychainAccessorTests {
    @Test func notFoundForNonexistentService() {
        let accessor = SystemKeychainAccessor()
        do {
            _ = try accessor.encryptionKeyData(
                service: "__susurro_nonexistent_test_service_xyz__",
                account: "__susurro_nonexistent_test_account_xyz__"
            )
            Issue.record("Expected throw for nonexistent service")
        } catch let error as KeychainAccessError {
            #expect(error == .notFound)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
