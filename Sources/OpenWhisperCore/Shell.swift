import Foundation

public struct ShellResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum ShellError: Error, LocalizedError, Equatable {
    case launchFailed(String)
    case failed(executable: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .failed(let executable, let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "\(executable) exited with status \(exitCode)."
            }
            return "\(executable) exited with status \(exitCode): \(detail)"
        }
    }
}

public struct Shell {
    public static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = executableURL
                    process.arguments = arguments
                    if let environment {
                        process.environment = environment
                    }

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    try process.run()
                    process.waitUntilExit()

                    let stdout = String(
                        data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    let stderr = String(
                        data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""

                    let result = ShellResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    )

                    guard result.exitCode == 0 else {
                        throw ShellError.failed(
                            executable: executableURL.path,
                            exitCode: result.exitCode,
                            stderr: stderr
                        )
                    }

                    continuation.resume(returning: result)
                } catch let error as ShellError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(
                        throwing: ShellError.launchFailed(error.localizedDescription)
                    )
                }
            }
        }
    }
}
