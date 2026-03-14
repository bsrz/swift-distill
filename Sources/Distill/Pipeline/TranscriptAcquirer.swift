import Foundation

public struct TranscriptAcquirer: TranscriptAcquiring {
    private let cookiesFromBrowser: String?
    private let transcriptionMethod: TranscriptionMethod
    private let whisperTranscriber: WhisperTranscriber?
    private let cloudTranscriber: WhisperCloudTranscriber?
    private let audioExtractor: AudioExtractor

    public init(
        cookiesFromBrowser: String? = nil,
        transcriptionMethod: TranscriptionMethod = .captions,
        whisperTranscriber: WhisperTranscriber? = nil,
        cloudTranscriber: WhisperCloudTranscriber? = nil
    ) {
        self.cookiesFromBrowser = cookiesFromBrowser
        self.transcriptionMethod = transcriptionMethod
        self.whisperTranscriber = whisperTranscriber
        self.cloudTranscriber = cloudTranscriber
        self.audioExtractor = AudioExtractor(cookiesFromBrowser: cookiesFromBrowser)
    }

    public func acquire(metadata: VideoMetadata) async throws -> Transcript {
        switch transcriptionMethod {
        case .captions:
            return try await acquireWithCaptionFallback(metadata: metadata)
        case .local:
            return try await acquireLocal(metadata: metadata)
        case .cloud:
            return try await acquireCloud(metadata: metadata)
        }
    }

    // MARK: - Captions (with automatic fallback to local)

    private func acquireWithCaptionFallback(metadata: VideoMetadata) async throws -> Transcript {
        // Try YouTube captions first
        do {
            return try await RetryHandler.withRetry {
                try await downloadCaptions(metadata: metadata)
            }
        } catch let error as DistillError where error.isCaptionUnavailable {
            // Captions not available — try local fallback if whisper is configured
            if let whisperTranscriber {
                return try await transcribeLocally(metadata: metadata, transcriber: whisperTranscriber)
            }
            throw error
        }
    }

    // MARK: - Forced Local

    private func acquireLocal(metadata: VideoMetadata) async throws -> Transcript {
        guard let whisperTranscriber else {
            throw DistillError.configurationError(
                "Local transcription requested but no whisper engine is available. Install mlx-whisper or whisper.cpp."
            )
        }
        return try await transcribeLocally(metadata: metadata, transcriber: whisperTranscriber)
    }

    // MARK: - Cloud

    private func acquireCloud(metadata: VideoMetadata) async throws -> Transcript {
        guard let cloudTranscriber else {
            throw DistillError.configurationError(
                "Cloud transcription requested but no OpenAI API key is configured. Set OPENAI_API_KEY."
            )
        }
        return try await transcribeViaCloud(metadata: metadata, transcriber: cloudTranscriber)
    }

    // MARK: - Caption Download (existing logic)

    private func downloadCaptions(metadata: VideoMetadata) async throws -> Transcript {
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

    // MARK: - Local Transcription

    private func transcribeLocally(metadata: VideoMetadata, transcriber: WhisperTranscriber) async throws -> Transcript {
        let audioPath = try await audioExtractor.extract(metadata: metadata)
        defer { try? FileManager.default.removeItem(at: audioPath.deletingLastPathComponent()) }

        return try await transcriber.transcribe(audioPath: audioPath)
    }

    // MARK: - Cloud Transcription

    private func transcribeViaCloud(metadata: VideoMetadata, transcriber: WhisperCloudTranscriber) async throws -> Transcript {
        let audioPath = try await audioExtractor.extract(metadata: metadata)
        defer { try? FileManager.default.removeItem(at: audioPath.deletingLastPathComponent()) }

        return try await RetryHandler.withRetry {
            try await transcriber.transcribe(audioPath: audioPath)
        }
    }
}
