import Foundation

/// Local transcription using mlx-whisper or whisper.cpp.
public struct WhisperTranscriber: Sendable {
    private let engine: WhisperEngine
    private let model: String
    private let language: String

    public init(engine: WhisperEngine, model: String = "base", language: String = "en") {
        self.engine = engine
        self.model = model
        self.language = language
    }

    /// Transcribes an audio file to a Transcript using the configured whisper engine.
    public func transcribe(audioPath: URL) async throws -> Transcript {
        switch engine {
        case .mlxWhisper:
            return try await transcribeWithMLX(audioPath: audioPath)
        case .whisperCpp:
            return try await transcribeWithWhisperCpp(audioPath: audioPath)
        }
    }

    // MARK: - mlx-whisper

    private func transcribeWithMLX(audioPath: URL) async throws -> Transcript {
        let outputDir = audioPath.deletingLastPathComponent()

        let result = try await Shell.run(
            executable: "mlx_whisper",
            arguments: [
                audioPath.path,
                "--model", model,
                "--language", language,
                "--output_format", "vtt",
                "--output_dir", outputDir.path,
            ],
            timeout: 600
        )

        guard result.exitCode == 0 else {
            throw DistillError.transcriptExtractionFailed(
                "mlx-whisper failed: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
            )
        }

        // mlx_whisper outputs <filename>.vtt in the output dir
        let vttFile = try findVTTFile(in: outputDir)
        let vttContent = try String(contentsOf: vttFile, encoding: .utf8)
        let transcript = VTTParser.parse(vttContent)
        return Transcript(segments: transcript.segments, source: .whisperLocal)
    }

    // MARK: - whisper.cpp

    private func transcribeWithWhisperCpp(audioPath: URL) async throws -> Transcript {
        let outputDir = audioPath.deletingLastPathComponent()
        let outputPrefix = outputDir.appendingPathComponent("transcript").path

        // whisper.cpp expects a WAV file, so convert first
        let wavPath = outputDir.appendingPathComponent("audio.wav")
        let convertResult = try await Shell.run(
            executable: "ffmpeg",
            arguments: [
                "-i", audioPath.path,
                "-ar", "16000",
                "-ac", "1",
                "-c:a", "pcm_s16le",
                wavPath.path,
            ],
            timeout: 120
        )

        guard convertResult.exitCode == 0 else {
            throw DistillError.transcriptExtractionFailed(
                "Audio conversion to WAV failed: \(convertResult.stderr)"
            )
        }

        let result = try await Shell.run(
            executable: "whisper-cpp",
            arguments: [
                "-m", resolveWhisperCppModel(),
                "-f", wavPath.path,
                "-l", language,
                "-ovtt",
                "-of", outputPrefix,
            ],
            timeout: 600
        )

        guard result.exitCode == 0 else {
            throw DistillError.transcriptExtractionFailed(
                "whisper.cpp failed: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
            )
        }

        let vttPath = URL(fileURLWithPath: outputPrefix + ".vtt")
        let vttContent = try String(contentsOf: vttPath, encoding: .utf8)
        let transcript = VTTParser.parse(vttContent)
        return Transcript(segments: transcript.segments, source: .whisperLocal)
    }

    private func resolveWhisperCppModel() -> String {
        // whisper.cpp models are typically at ~/.local/share/whisper.cpp/models/ggml-<model>.bin
        // or /usr/local/share/whisper.cpp/models/ggml-<model>.bin (Homebrew)
        let homeModels = NSString(string: "~/.local/share/whisper.cpp/models/ggml-\(model).bin").expandingTildeInPath
        if FileManager.default.fileExists(atPath: homeModels) {
            return homeModels
        }

        let brewModels = "/usr/local/share/whisper.cpp/models/ggml-\(model).bin"
        if FileManager.default.fileExists(atPath: brewModels) {
            return brewModels
        }

        let armBrewModels = "/opt/homebrew/share/whisper.cpp/models/ggml-\(model).bin"
        if FileManager.default.fileExists(atPath: armBrewModels) {
            return armBrewModels
        }

        // Fall back to the model name — whisper.cpp may resolve it
        return "ggml-\(model).bin"
    }

    private func findVTTFile(in directory: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let vtt = files.first(where: { $0.pathExtension == "vtt" }) else {
            throw DistillError.transcriptExtractionFailed("Whisper did not produce a VTT file")
        }
        return vtt
    }
}
