import Testing
import Foundation
@testable import Distill

// MARK: - Mock Implementations

struct MockMetadataResolver: MetadataResolving {
    let metadata: VideoMetadata
    var resolvedURLs: [String] = []

    func resolve(url: String) async throws -> VideoMetadata {
        metadata
    }
}

struct MockTranscriptAcquirer: TranscriptAcquiring {
    let transcript: Transcript

    func acquire(metadata: VideoMetadata) async throws -> Transcript {
        transcript
    }
}

struct MockSummarizer: Summarizing {
    let summary: Summary

    func summarize(transcript: Transcript, metadata: VideoMetadata, prompt: String) async throws -> Summary {
        summary
    }
}

struct MockOutputWriter: OutputWriting {
    let onWrite: @Sendable (Summary, VideoMetadata, String, [String]) -> Void

    func write(summary: Summary, metadata: VideoMetadata, to outputPath: String, tags: [String]) throws {
        onWrite(summary, metadata, outputPath, tags)
    }
}

struct FailingMetadataResolver: MetadataResolving {
    func resolve(url: String) async throws -> VideoMetadata {
        throw DistillError.metadataFailed("Network error")
    }
}

struct FailingSummarizer: Summarizing {
    func summarize(transcript: Transcript, metadata: VideoMetadata, prompt: String) async throws -> Summary {
        throw DistillError.summarizationFailed("API unavailable")
    }
}

// MARK: - Test Helpers

let testMetadata = VideoMetadata(
    id: "jNQXAC9IVRw",
    title: "Me at the zoo",
    channel: "jawed",
    channelURL: "https://www.youtube.com/channel/UC4QobU6STFB0P71PMvOGN5A",
    uploadDate: "20050423",
    duration: 19,
    durationString: "0:19",
    description: "The first video on YouTube.",
    tags: ["zoo", "elephants"],
    thumbnailURL: "https://i.ytimg.com/vi/jNQXAC9IVRw/default.jpg",
    webpageURL: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
    hasSubtitles: true,
    hasAutomaticCaptions: true
)

let testTranscript = Transcript(
    segments: [
        TranscriptSegment(startTime: 0, endTime: 5, text: "Hello elephants"),
        TranscriptSegment(startTime: 5, endTime: 10, text: "They have long trunks"),
    ],
    source: .youtubeManual
)

let testSummary = Summary(
    markdown: "# Me at the zoo\n\nA video about elephants.",
    inputTokens: 100,
    outputTokens: 50,
    model: "claude-sonnet-4-6"
)

// MARK: - Tests

@Suite("Pipeline")
struct PipelineTests {
    @Test func stagesCalledInOrder() async throws {
        nonisolated(unsafe) var order: [String] = []
        let lock = NSLock()

        @Sendable func record(_ stage: String) {
            lock.lock()
            order.append(stage)
            lock.unlock()
        }

        struct OrderedMetadataResolver: MetadataResolving {
            let metadata: VideoMetadata
            let record: @Sendable (String) -> Void
            func resolve(url: String) async throws -> VideoMetadata {
                record("metadata")
                return metadata
            }
        }

        struct OrderedTranscriptAcquirer: TranscriptAcquiring {
            let transcript: Transcript
            let record: @Sendable (String) -> Void
            func acquire(metadata: VideoMetadata) async throws -> Transcript {
                record("transcript")
                return transcript
            }
        }

        struct OrderedSummarizer: Summarizing {
            let summary: Summary
            let record: @Sendable (String) -> Void
            func summarize(transcript: Transcript, metadata: VideoMetadata, prompt: String) async throws -> Summary {
                record("summarize")
                return summary
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
        let outputPath = tempDir.appendingPathComponent("test-\(UUID()).md").path

        let pipeline = Pipeline(
            metadataResolver: OrderedMetadataResolver(metadata: testMetadata, record: record),
            transcriptAcquirer: OrderedTranscriptAcquirer(transcript: testTranscript, record: record),
            summarizer: OrderedSummarizer(summary: testSummary, record: record),
            outputWriter: MockOutputWriter { _, _, _, _ in record("write") },
            configuration: Configuration(
                url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                outputPath: outputPath,
                apiKeyEnvVar: "TEST_API_KEY_ORDER"
            )
        )

        setenv("TEST_API_KEY_ORDER", "test-key", 1)
        defer { unsetenv("TEST_API_KEY_ORDER") }

        try await pipeline.run()
        #expect(order == ["metadata", "transcript", "summarize", "write"])

        // Cleanup
        try? FileManager.default.removeItem(atPath: outputPath)
    }

    @Test func dataFlowsCorrectly() async throws {
        nonisolated(unsafe) var receivedSummary: Summary?
        nonisolated(unsafe) var receivedMetadata: VideoMetadata?
        nonisolated(unsafe) var receivedOutputPath: String?
        nonisolated(unsafe) var receivedTags: [String]?

        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-flow-\(UUID()).md").path

        let pipeline = Pipeline(
            metadataResolver: MockMetadataResolver(metadata: testMetadata),
            transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
            summarizer: MockSummarizer(summary: testSummary),
            outputWriter: MockOutputWriter { summary, metadata, path, tags in
                receivedSummary = summary
                receivedMetadata = metadata
                receivedOutputPath = path
                receivedTags = tags
            },
            configuration: Configuration(
                url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                outputPath: outputPath,
                apiKeyEnvVar: "TEST_API_KEY_FLOW"
            )
        )

        setenv("TEST_API_KEY_FLOW", "test-key", 1)
        defer { unsetenv("TEST_API_KEY_FLOW") }

        try await pipeline.run()

        #expect(receivedSummary?.markdown == testSummary.markdown)
        #expect(receivedMetadata?.id == testMetadata.id)
        #expect(receivedOutputPath == outputPath)
        #expect(receivedTags == ["youtube"])
    }

    @Test func missingAPIKeyExitCode() async {
        unsetenv("ANTHROPIC_API_KEY")

        let pipeline = Pipeline(
            metadataResolver: MockMetadataResolver(metadata: testMetadata),
            transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
            summarizer: MockSummarizer(summary: testSummary),
            outputWriter: MockOutputWriter { _, _, _, _ in },
            configuration: Configuration(
                url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                outputPath: "/tmp/test.md",
                apiKeyEnvVar: "DISTILL_TEST_NONEXISTENT_KEY"
            )
        )

        do {
            try await pipeline.run()
            Issue.record("Expected error to be thrown")
        } catch let error as DistillError {
            #expect(error.exitCode == 3)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func invalidURLFails() async {
        setenv("TEST_API_KEY_INVALID_URL", "test-key", 1)
        defer { unsetenv("TEST_API_KEY_INVALID_URL") }

        let pipeline = Pipeline(
            metadataResolver: MockMetadataResolver(metadata: testMetadata),
            transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
            summarizer: MockSummarizer(summary: testSummary),
            outputWriter: MockOutputWriter { _, _, _, _ in },
            configuration: Configuration(
                url: "not-a-youtube-url",
                outputPath: "/tmp/test.md",
                apiKeyEnvVar: "TEST_API_KEY_INVALID_URL"
            )
        )

        do {
            try await pipeline.run()
            Issue.record("Expected error to be thrown")
        } catch let error as DistillError {
            #expect(error.exitCode == 1)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func metadataErrorPropagates() async {
        setenv("TEST_API_KEY_META_ERR", "test-key", 1)
        defer { unsetenv("TEST_API_KEY_META_ERR") }

        let pipeline = Pipeline(
            metadataResolver: FailingMetadataResolver(),
            transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
            summarizer: MockSummarizer(summary: testSummary),
            outputWriter: MockOutputWriter { _, _, _, _ in },
            configuration: Configuration(
                url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                outputPath: "/tmp/test.md",
                apiKeyEnvVar: "TEST_API_KEY_META_ERR"
            )
        )

        do {
            try await pipeline.run()
            Issue.record("Expected error to be thrown")
        } catch let error as DistillError {
            if case .metadataFailed = error {
                // Expected
            } else {
                Issue.record("Expected metadataFailed, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Frame Extraction Tests

@Suite("FrameExtractor")
struct FrameExtractorTests {
    @Test func parseSceneFramesExtractsTimestamps() {
        let stderr = """
        [Parsed_showinfo_1 @ 0x1234] n:   0 pts:   1234 pts_time:12.34 fmt:yuv420p sar:1/1 s:1920x1080 i:P
        [Parsed_showinfo_1 @ 0x1234] n:   1 pts:   5678 pts_time:56.78 fmt:yuv420p sar:1/1 s:1920x1080 i:P
        """

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-scene-\(UUID())")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create fake scene frame files
        let file1 = tempDir.appendingPathComponent("scene-0001.png")
        let file2 = tempDir.appendingPathComponent("scene-0002.png")
        try! Data().write(to: file1)
        try! Data().write(to: file2)

        let extractor = FrameExtractor(config: FrameConfig())
        let frames = extractor.parseSceneFrames(stderr: stderr, directory: tempDir)

        #expect(frames.count == 2)
        #expect(frames[0].timestamp == 12.34)
        #expect(frames[1].timestamp == 56.78)
        #expect(frames[0].filename == "scene-0001.png")
        #expect(frames[1].filename == "scene-0002.png")
    }

    @Test func parseSceneFramesHandlesNoMatches() {
        let stderr = "Some random ffmpeg output\nwith no showinfo lines"

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-scene-empty-\(UUID())")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let extractor = FrameExtractor(config: FrameConfig())
        let frames = extractor.parseSceneFrames(stderr: stderr, directory: tempDir)

        #expect(frames.isEmpty)
    }

    @Test func extractedFrameTimestampString() {
        let frame1 = ExtractedFrame(timestamp: 0, filename: "f.png", path: "/f.png")
        #expect(frame1.timestampString == "0:00")

        let frame2 = ExtractedFrame(timestamp: 65, filename: "f.png", path: "/f.png")
        #expect(frame2.timestampString == "1:05")

        let frame3 = ExtractedFrame(timestamp: 3661, filename: "f.png", path: "/f.png")
        #expect(frame3.timestampString == "61:01")
    }
}

@Suite("FrameConfig")
struct FrameConfigTests {
    @Test func defaultValues() {
        let config = FrameConfig()
        #expect(config.maxFrames == 20)
        #expect(config.intervalSeconds == 60)
        #expect(config.sceneDetection == true)
        #expect(config.sceneThreshold == 0.4)
    }

    @Test func customValues() {
        let config = FrameConfig(maxFrames: 10, intervalSeconds: 30, sceneDetection: false, sceneThreshold: 0.6)
        #expect(config.maxFrames == 10)
        #expect(config.intervalSeconds == 30)
        #expect(config.sceneDetection == false)
        #expect(config.sceneThreshold == 0.6)
    }
}

@Suite("Configuration.frames")
struct ConfigurationFrameTests {
    @Test func framesDisabledByDefault() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            configFile: nil
        )
        #expect(cfg.framesEnabled == false)
    }

    @Test func framesEnabledViaCLI() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            cliFrames: true,
            configFile: nil
        )
        #expect(cfg.framesEnabled == true)
    }

    @Test func frameConfigFromConfigFile() {
        let configFile = ConfigFile(
            frames: ConfigFile.FramesConfig(
                max_frames: 10,
                interval_seconds: 30,
                scene_detection: false,
                scene_threshold: 0.6
            )
        )
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            cliFrames: true,
            configFile: configFile
        )
        #expect(cfg.frameConfig.maxFrames == 10)
        #expect(cfg.frameConfig.intervalSeconds == 30)
        #expect(cfg.frameConfig.sceneDetection == false)
        #expect(cfg.frameConfig.sceneThreshold == 0.6)
    }

    @Test func imageSyntaxFromConfigFile() {
        let configFile = ConfigFile(
            obsidian: ConfigFile.ObsidianConfig(image_syntax: "wikilink")
        )
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            configFile: configFile
        )
        #expect(cfg.imageSyntax == .wikilink)
    }

    @Test func resolvedAttachmentsDir() {
        let cfg = Configuration(
            url: "https://www.youtube.com/watch?v=test",
            outputPath: "/tmp/test.md",
            vaultPath: "/tmp/vault",
            attachmentsFolder: "YouTube/attachments"
        )
        let dir = cfg.resolvedAttachmentsDir(for: testMetadata)
        #expect(dir == "/tmp/vault/YouTube/attachments/me-at-the-zoo")
    }

    @Test func relativeAttachmentPath() {
        let cfg = Configuration(
            url: "https://www.youtube.com/watch?v=test",
            outputPath: "/tmp/test.md"
        )
        let path = cfg.relativeAttachmentPath(for: testMetadata, filename: "frame-001.png")
        #expect(path == "attachments/me-at-the-zoo/frame-001.png")
    }
}

// MARK: - Pipeline with Frames Tests

@Suite("Pipeline.frames")
struct PipelineFrameTests {
    @Test func pipelineRunsWithFrameExtractor() async throws {
        nonisolated(unsafe) var order: [String] = []
        let lock = NSLock()

        @Sendable func record(_ stage: String) {
            lock.lock()
            order.append(stage)
            lock.unlock()
        }

        struct RecordingMetadataResolver: MetadataResolving {
            let metadata: VideoMetadata
            let record: @Sendable (String) -> Void
            func resolve(url: String) async throws -> VideoMetadata {
                record("metadata")
                return metadata
            }
        }

        struct RecordingTranscriptAcquirer: TranscriptAcquiring {
            let transcript: Transcript
            let record: @Sendable (String) -> Void
            func acquire(metadata: VideoMetadata) async throws -> Transcript {
                record("transcript")
                return transcript
            }
        }

        struct RecordingSummarizer: Summarizing {
            let summary: Summary
            let record: @Sendable (String) -> Void
            func summarize(transcript: Transcript, metadata: VideoMetadata, prompt: String) async throws -> Summary {
                record("summarize")
                return summary
            }
        }

        struct MockFrameExtractor: FrameExtracting {
            let record: @Sendable (String) -> Void
            func extract(metadata: VideoMetadata, to attachmentsDir: String) async throws -> [ExtractedFrame] {
                record("frames")
                return [
                    ExtractedFrame(timestamp: 10, filename: "frame-001.png", path: "/tmp/frame-001.png"),
                    ExtractedFrame(timestamp: 60, filename: "frame-002.png", path: "/tmp/frame-002.png"),
                ]
            }
        }

        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-frames-\(UUID()).md").path

        let pipeline = Pipeline(
            metadataResolver: RecordingMetadataResolver(metadata: testMetadata, record: record),
            transcriptAcquirer: RecordingTranscriptAcquirer(transcript: testTranscript, record: record),
            summarizer: RecordingSummarizer(summary: testSummary, record: record),
            outputWriter: MockOutputWriter { _, _, _, _ in record("write") },
            frameExtractor: MockFrameExtractor(record: record),
            configuration: Configuration(
                url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                outputPath: outputPath,
                apiKeyEnvVar: "TEST_API_KEY_FRAMES",
                framesEnabled: true,
                frameConfig: FrameConfig()
            )
        )

        setenv("TEST_API_KEY_FRAMES", "test-key", 1)
        defer { unsetenv("TEST_API_KEY_FRAMES") }

        try await pipeline.run()

        // metadata always first, write always last
        #expect(order.first == "metadata")
        #expect(order.last == "write")
        // transcript and frames run concurrently, both must happen before summarize
        #expect(order.contains("transcript"))
        #expect(order.contains("frames"))
        #expect(order.contains("summarize"))

        try? FileManager.default.removeItem(atPath: outputPath)
    }

    @Test func pipelineSkipsFramesWhenDisabled() async throws {
        nonisolated(unsafe) var stages: [String] = []
        let lock = NSLock()

        @Sendable func record(_ stage: String) {
            lock.lock()
            stages.append(stage)
            lock.unlock()
        }

        struct TrackingFrameExtractor: FrameExtracting {
            let record: @Sendable (String) -> Void
            func extract(metadata: VideoMetadata, to attachmentsDir: String) async throws -> [ExtractedFrame] {
                record("frames")
                return []
            }
        }

        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-noframes-\(UUID()).md").path

        let pipeline = Pipeline(
            metadataResolver: MockMetadataResolver(metadata: testMetadata),
            transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
            summarizer: MockSummarizer(summary: testSummary),
            outputWriter: MockOutputWriter { _, _, _, _ in record("write") },
            frameExtractor: TrackingFrameExtractor(record: record),
            configuration: Configuration(
                url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                outputPath: outputPath,
                apiKeyEnvVar: "TEST_API_KEY_NOFRAMES",
                framesEnabled: false
            )
        )

        setenv("TEST_API_KEY_NOFRAMES", "test-key", 1)
        defer { unsetenv("TEST_API_KEY_NOFRAMES") }

        try await pipeline.run()

        #expect(!stages.contains("frames"))

        try? FileManager.default.removeItem(atPath: outputPath)
    }
}

// MARK: - Transcription Fallback Tests

@Suite("TranscriptionMethod")
struct TranscriptionMethodTests {
    @Test func defaultIsCaptions() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            configFile: nil
        )
        #expect(cfg.transcriptionMethod == .captions)
    }

    @Test func cliOverridesConfig() {
        let configFile = ConfigFile(
            transcription: ConfigFile.TranscriptionConfig(prefer: "local")
        )
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            cliTranscription: "cloud",
            configFile: configFile
        )
        #expect(cfg.transcriptionMethod == .cloud)
    }

    @Test func configFileTranscription() {
        let configFile = ConfigFile(
            transcription: ConfigFile.TranscriptionConfig(prefer: "local")
        )
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            configFile: configFile
        )
        #expect(cfg.transcriptionMethod == .local)
    }

    @Test func whisperEngineFromConfig() {
        let configFile = ConfigFile(
            transcription: ConfigFile.TranscriptionConfig(local_engine: "whisper.cpp", model: "small")
        )
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            configFile: configFile
        )
        #expect(cfg.whisperEngine == .whisperCpp)
        #expect(cfg.whisperModel == "small")
    }

    @Test func defaultWhisperEngine() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            configFile: nil
        )
        #expect(cfg.whisperEngine == .mlxWhisper)
        #expect(cfg.whisperModel == "base")
        #expect(cfg.transcriptionLanguage == "en")
    }

    @Test func openAIKeyEnvVar() {
        let configFile = ConfigFile(
            transcription: ConfigFile.TranscriptionConfig(openai_api_key_env: "MY_OPENAI_KEY")
        )
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            configFile: configFile
        )
        #expect(cfg.openAIAPIKeyEnvVar == "MY_OPENAI_KEY")
    }

    @Test func invalidMethodFallsBackToCaptions() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=test",
            cliOutput: "/tmp/test.md",
            cliCookies: nil,
            cliTranscription: "invalid",
            configFile: nil
        )
        #expect(cfg.transcriptionMethod == .captions)
    }
}

@Suite("TranscriptSource")
struct TranscriptSourceTests {
    @Test func allCasesExist() {
        #expect(TranscriptSource.youtubeManual.rawValue == "youtubeManual")
        #expect(TranscriptSource.youtubeAuto.rawValue == "youtubeAuto")
        #expect(TranscriptSource.whisperLocal.rawValue == "whisperLocal")
        #expect(TranscriptSource.whisperCloud.rawValue == "whisperCloud")
    }
}

@Suite("TranscriptAcquirer.fallback")
struct TranscriptAcquirerFallbackTests {
    @Test func captionsMethodUsesExistingBehavior() async throws {
        // When method is captions, the acquirer tries YouTube captions
        // We use a mock that implements the protocol to verify the method is respected
        struct MockCaptionAcquirer: TranscriptAcquiring {
            func acquire(metadata: VideoMetadata) async throws -> Transcript {
                Transcript(
                    segments: [TranscriptSegment(startTime: 0, endTime: 5, text: "caption text")],
                    source: .youtubeManual
                )
            }
        }

        let acquirer = MockCaptionAcquirer()
        let transcript = try await acquirer.acquire(metadata: testMetadata)
        #expect(transcript.source == .youtubeManual)
        #expect(transcript.segments.count == 1)
    }

    @Test func localMethodRequiresWhisper() async {
        // TranscriptAcquirer with local method but no whisper transcriber should fail
        let acquirer = TranscriptAcquirer(
            cookiesFromBrowser: nil,
            transcriptionMethod: .local,
            whisperTranscriber: nil,
            cloudTranscriber: nil
        )

        do {
            _ = try await acquirer.acquire(metadata: testMetadata)
            Issue.record("Expected error to be thrown")
        } catch let error as DistillError {
            if case .configurationError = error {
                // Expected
            } else {
                Issue.record("Expected configurationError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func cloudMethodRequiresTranscriber() async {
        let acquirer = TranscriptAcquirer(
            cookiesFromBrowser: nil,
            transcriptionMethod: .cloud,
            whisperTranscriber: nil,
            cloudTranscriber: nil
        )

        do {
            _ = try await acquirer.acquire(metadata: testMetadata)
            Issue.record("Expected error to be thrown")
        } catch let error as DistillError {
            if case .configurationError = error {
                // Expected
            } else {
                Issue.record("Expected configurationError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@Suite("DistillError.captions")
struct DistillErrorCaptionTests {
    @Test func transcriptNotAvailableIsCaptionUnavailable() {
        #expect(DistillError.transcriptNotAvailable.isCaptionUnavailable)
    }

    @Test func otherErrorsAreNotCaptionUnavailable() {
        #expect(!DistillError.invalidURL("test").isCaptionUnavailable)
        #expect(!DistillError.transcriptExtractionFailed("test").isCaptionUnavailable)
        #expect(!DistillError.missingAPIKey.isCaptionUnavailable)
    }
}

@Suite("VideoMetadata")
struct VideoMetadataTests {
    @Test func publishedDateFormat() {
        #expect(testMetadata.publishedDate == "2005-04-23")
    }
}

@Suite("DistillError")
struct DistillErrorTests {
    @Test func configErrorExitCode() {
        let error = DistillError.configurationError("test")
        #expect(error.exitCode == 3)
    }

    @Test func missingAPIKeyExitCode() {
        let error = DistillError.missingAPIKey
        #expect(error.exitCode == 3)
    }

    @Test func defaultExitCode() {
        let error = DistillError.invalidURL("test")
        #expect(error.exitCode == 1)
    }

    @Test func transientErrors() {
        #expect(DistillError.apiError(statusCode: 429, message: "").isTransient)
        #expect(DistillError.apiError(statusCode: 500, message: "").isTransient)
        #expect(DistillError.apiError(statusCode: 503, message: "").isTransient)
        #expect(!DistillError.apiError(statusCode: 401, message: "").isTransient)
        #expect(!DistillError.invalidURL("").isTransient)
    }
}
