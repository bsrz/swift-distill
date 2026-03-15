import Foundation

/// Checks that external dependencies are installed and reports version info.
public struct DependencyChecker: Sendable {
    public struct Dependency: Sendable {
        let name: String
        let executable: String
        let versionFlag: String
        let minVersion: String
        let installHint: String
    }

    private static let dependencies: [Dependency] = [
        Dependency(name: "yt-dlp", executable: "yt-dlp", versionFlag: "--version", minVersion: "2024.01", installHint: "brew install yt-dlp"),
        Dependency(name: "ffmpeg", executable: "ffmpeg", versionFlag: "-version", minVersion: "6.0", installHint: "brew install ffmpeg"),
        Dependency(name: "mlx-whisper", executable: "mlx_whisper", versionFlag: "--version", minVersion: "0.1", installHint: "pip install mlx-whisper"),
        Dependency(name: "whisper.cpp", executable: "whisper-cpp", versionFlag: "--version", minVersion: "1.5", installHint: "brew install whisper-cpp"),
    ]

    public static func check() async {
        let stderr = FileHandle.standardError

        func write(_ s: String) {
            stderr.write(Data("\(s)\n".utf8))
        }

        write("Dependency Check")
        write("================\n")

        for dep in dependencies {
            let result = await checkOne(dep)
            switch result {
            case .found(let version):
                if versionLessThan(version, dep.minVersion) {
                    write("  ⚠ \(dep.name) \(version) — minimum recommended: \(dep.minVersion)+")
                } else {
                    write("  ✓ \(dep.name) \(version)")
                }
            case .notFound:
                write("  ✗ \(dep.name) — not found")
                write("    Install with: \(dep.installHint)")
            }
        }
        write("")
    }

    private enum CheckResult {
        case found(String)
        case notFound
    }

    private static func checkOne(_ dep: Dependency) async -> CheckResult {
        do {
            // Use a login shell so the user's full PATH (including /opt/homebrew/bin, etc.) is available
            let result = try await Shell.run(
                executable: "/bin/zsh",
                arguments: ["-l", "-c", "\(dep.executable) \(dep.versionFlag) 2>&1"],
                timeout: 10
            )
            if result.exitCode == 0 {
                let version = extractVersion(from: result.stdout + result.stderr)
                return .found(version)
            }
            return .notFound
        } catch {
            return .notFound
        }
    }

    private static func extractVersion(from output: String) -> String {
        // Try to find a version number pattern like "2024.01.01" or "6.1.1" or "0.3.2"
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if let match = line.firstMatch(of: #/(\d+\.[\d.]+)/#) {
                return String(match.1)
            }
        }
        return "unknown"
    }

    private static func versionLessThan(_ version: String, _ minimum: String) -> Bool {
        guard version != "unknown" else { return false }
        let v = version.components(separatedBy: ".").compactMap { Int($0) }
        let m = minimum.components(separatedBy: ".").compactMap { Int($0) }
        for i in 0..<max(v.count, m.count) {
            let a = i < v.count ? v[i] : 0
            let b = i < m.count ? m[i] : 0
            if a < b { return true }
            if a > b { return false }
        }
        return false
    }
}
