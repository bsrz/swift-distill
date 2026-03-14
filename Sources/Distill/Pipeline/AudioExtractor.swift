import Foundation

/// Downloads the audio track from a YouTube video using yt-dlp.
public struct AudioExtractor: Sendable {
    private let cookiesFromBrowser: String?

    public init(cookiesFromBrowser: String? = nil) {
        self.cookiesFromBrowser = cookiesFromBrowser
    }

    /// Downloads audio to a temporary directory and returns the file path.
    public func extract(metadata: VideoMetadata) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("distill-audio-\(metadata.id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let outputTemplate = tempDir.appendingPathComponent("\(metadata.id).%(ext)s").path

        var arguments = [
            "--extract-audio",
            "--audio-format", "mp3",
            "--audio-quality", "4",
            "--output", outputTemplate,
        ]
        if let browser = cookiesFromBrowser {
            arguments += ["--cookies-from-browser", browser]
        }
        arguments.append(metadata.webpageURL)

        let result = try await Shell.run(
            executable: "yt-dlp",
            arguments: arguments,
            timeout: 300
        )

        guard result.exitCode == 0 else {
            throw DistillError.transcriptExtractionFailed(
                "Audio download failed: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
            )
        }

        // Find the downloaded mp3
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let audioFile = files.first(where: { $0.pathExtension == "mp3" }) else {
            throw DistillError.transcriptExtractionFailed("Audio file not found after download")
        }

        return audioFile
    }
}
