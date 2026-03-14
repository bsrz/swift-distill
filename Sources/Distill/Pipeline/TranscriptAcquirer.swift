import Foundation

public struct TranscriptAcquirer: TranscriptAcquiring {
    private let cookiesFromBrowser: String?

    public init(cookiesFromBrowser: String? = nil) {
        self.cookiesFromBrowser = cookiesFromBrowser
    }

    public func acquire(metadata: VideoMetadata) async throws -> Transcript {
        try await RetryHandler.withRetry {
            try await downloadAndParse(metadata: metadata)
        }
    }

    private func downloadAndParse(metadata: VideoMetadata) async throws -> Transcript {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("distill-\(metadata.id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var arguments = [
            "--write-auto-sub",
            "--write-sub",
            "--sub-lang", "en",
            "--sub-format", "vtt",
            "--skip-download",
            "--output", tempDir.appendingPathComponent("%(id)s").path,
        ]
        if let browser = cookiesFromBrowser {
            arguments += ["--cookies-from-browser", browser]
        }
        arguments.append(metadata.webpageURL)

        let result = try await Shell.run(
            executable: "yt-dlp",
            arguments: arguments,
            timeout: 60
        )

        guard result.exitCode == 0 else {
            throw DistillError.transcriptExtractionFailed(result.stderr)
        }

        // Find the VTT file
        let files = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )
        guard let vttFile = files.first(where: { $0.pathExtension == "vtt" }) else {
            throw DistillError.transcriptNotAvailable
        }

        let vttContent = try String(contentsOf: vttFile, encoding: .utf8)
        var transcript = VTTParser.parse(vttContent)

        // Determine source from filename
        let filename = vttFile.lastPathComponent
        let source: TranscriptSource = filename.contains(".en.vtt") && !metadata.hasSubtitles
            ? .youtubeAuto
            : .youtubeManual
        transcript = Transcript(segments: transcript.segments, source: source)

        return transcript
    }
}
