import AppKit
import Foundation

enum AppRelauncher {
    @MainActor
    static func relaunch() {
        let appPath = Bundle.main.bundleURL.path
        let script = "sleep 0.4; /usr/bin/open '\(shellEscaped(appPath))'"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()

        NSApp.terminate(nil)
    }

    private static func shellEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }
}
