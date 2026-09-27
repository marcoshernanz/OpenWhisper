import Foundation
import Testing
import OpenWhisperObjC

@Test func objectiveCExceptionsBecomeSwiftErrors() {
    do {
        try OWObjCExceptionCatcher.perform {
            NSException(
                name: NSExceptionName("com.apple.coreaudio.avfaudio"),
                reason: "Failed to create tap due to format mismatch",
                userInfo: nil
            ).raise()
        }
        Issue.record("Expected the exception to be reported as an error")
    } catch let error as NSError {
        #expect(error.domain == OWObjCExceptionErrorDomain)
        #expect(error.localizedDescription == "Failed to create tap due to format mismatch")
        #expect(error.userInfo[OWObjCExceptionNameKey] as? String == "com.apple.coreaudio.avfaudio")
    }
}

@Test func blocksThatDoNotRaiseRunNormally() throws {
    var didRun = false

    try OWObjCExceptionCatcher.perform {
        didRun = true
    }

    #expect(didRun)
}
