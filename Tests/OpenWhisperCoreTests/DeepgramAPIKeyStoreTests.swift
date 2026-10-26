import Foundation
import Testing
@testable import OpenWhisperCore

@Test func acceptsKeysThatCannotBreakTheSecurityCommand() {
    // Built at runtime so secret scanners don't take it for a real 40-character key.
    #expect(DeepgramAPIKeyStore.isValidKey(String(repeating: "0123456789abcdef", count: 3).prefix(40).description))
    #expect(DeepgramAPIKeyStore.isValidKey("token.with-dashes_and.dots"))
    #expect(!DeepgramAPIKeyStore.isValidKey(""))
    #expect(!DeepgramAPIKeyStore.isValidKey("has space"))
    #expect(!DeepgramAPIKeyStore.isValidKey("quote\"inside"))
    #expect(!DeepgramAPIKeyStore.isValidKey("new\nline"))
    #expect(!DeepgramAPIKeyStore.isValidKey("ñandú"))
    #expect(!DeepgramAPIKeyStore.isValidKey(String(repeating: "a", count: 513)))
}

/// Writes to the login keychain, so it runs only when asked to.
@Test func savesReplacesAndRemovesTheKeyInTheKeychain() throws {
    guard ProcessInfo.processInfo.environment["OPENWHISPER_RUN_KEYCHAIN_TESTS"] == "1" else { return }

    let store = DeepgramAPIKeyStore(service: "dev.openwhisper.tests.\(UUID().uuidString)")
    defer { try? store.delete() }

    #expect(store.read() == nil)

    try store.save("first0123")
    #expect(store.read() == "first0123")

    try store.save("second4567")
    #expect(store.read() == "second4567")

    try store.delete()
    #expect(store.read() == nil)
    try store.delete()

    #expect(throws: DeepgramAPIKeyStoreError.invalidKey) {
        try store.save("bad\" -w injected")
    }
}
