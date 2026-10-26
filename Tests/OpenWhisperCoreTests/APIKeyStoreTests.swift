import Foundation
import Testing
@testable import OpenWhisperCore

@Test func acceptsKeysThatCannotBreakTheSecurityCommand() {
    // Built at runtime so secret scanners don't take it for a real 40-character key.
    #expect(APIKeyStore.isValidKey(String(repeating: "0123456789abcdef", count: 3).prefix(40).description))
    #expect(APIKeyStore.isValidKey("token.with-dashes_and.dots"))
    #expect(!APIKeyStore.isValidKey(""))
    #expect(!APIKeyStore.isValidKey("has space"))
    #expect(!APIKeyStore.isValidKey("quote\"inside"))
    #expect(!APIKeyStore.isValidKey("new\nline"))
    #expect(!APIKeyStore.isValidKey("ñandú"))
    #expect(!APIKeyStore.isValidKey(String(repeating: "a", count: 513)))
}

/// Writes to the login keychain, so it runs only when asked to.
@Test func savesReplacesAndRemovesTheKeyInTheKeychain() throws {
    guard ProcessInfo.processInfo.environment["OPENWHISPER_RUN_KEYCHAIN_TESTS"] == "1" else { return }

    let store = APIKeyStore(service: "dev.openwhisper.tests.\(UUID().uuidString)", label: "OpenWhisper test key")
    defer { try? store.delete() }

    #expect(store.read() == nil)

    try store.save("first0123")
    #expect(store.read() == "first0123")

    try store.save("second4567")
    #expect(store.read() == "second4567")

    // OpenAI keys are longer than the 128 characters the password prompt of `security` takes.
    let longKey = "sk-proj-" + String(repeating: "aB3_-", count: 32)
    try store.save(longKey)
    #expect(store.read() == longKey)

    try store.delete()
    #expect(store.read() == nil)
    try store.delete()

    #expect(throws: APIKeyStoreError.invalidKey) {
        try store.save("bad\" -w injected")
    }
}
