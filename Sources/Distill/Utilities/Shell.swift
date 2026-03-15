import Foundation

public struct ShellResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public struct Shell: Sendable {
    public static func run(
        executable: String,
        arguments: [String] = [],
        stdin: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 120
    ) async throws -> ShellResult {
        // Find the executable path
        let executablePath: String
        if executable.hasPrefix("/") {
            executablePath = executable
        } else {
            let whichResult = try await runProcess(
                executablePath: "/usr/bin/which",
                arguments: [executable],
                timeout: 5
            )
            guard whichResult.exitCode == 0 else {
                throw DistillError.toolNotFound(executable)
            }
            executablePath = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return try await runProcess(
            executablePath: executablePath,
            arguments: arguments,
            stdin: stdin,
            environment: environment,
            timeout: timeout
        )
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        stdin: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval
    ) async throws -> ShellResult {
        // Run blocking I/O off the cooperative thread pool
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            if let environment {
                process.environment = environment
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Set up stdin if provided
            if let stdinContent = stdin {
                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                let stdinData = Data(stdinContent.utf8)
                stdinPipe.fileHandleForWriting.write(stdinData)
                stdinPipe.fileHandleForWriting.closeFile()
            }

            // Set up timeout
            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning {
                        process.interrupt()
                    }
                }
            }
            timer.resume()

            try process.run()

            // Read pipes BEFORE waitUntilExit to avoid deadlock when
            // the child fills the pipe buffer.
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            process.waitUntilExit()
            timer.cancel()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            return ShellResult(
                stdout: stdout,
                stderr: stderr,
                exitCode: process.terminationStatus
            )
        }.value
    }
}
