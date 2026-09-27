import OpenWhisperObjC

/// Swift cannot catch Objective-C exceptions. If one escapes into AppKit's run loop, AppKit swallows
/// it but the unwound main queue never runs again, so OpenWhisper freezes until it is relaunched.
enum ObjCException {
    static func catching<T>(_ body: () throws -> T) throws -> T {
        var result: Result<T, Error>?

        try OWObjCExceptionCatcher.perform {
            result = Result { try body() }
        }

        return try result!.get()
    }
}
