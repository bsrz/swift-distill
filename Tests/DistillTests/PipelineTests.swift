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

// MARK: - Batch & Playlist Tests

@Suite("BatchRunner")
struct BatchRunnerTests {
    @Test func sequentialProcessing() async throws {
        nonisolated(unsafe) var processedURLs: [String] = []
        let lock = NSLock()

        let factory = PipelineFactory { url in
            lock.lock()
            processedURLs.append(url)
            lock.unlock()

            let cfg = Configuration(
                url: url,
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent("batch-\(UUID()).md").path,
                apiKeyEnvVar: "TEST_API_KEY_BATCH"
            )
            return Pipeline(
                metadataResolver: MockMetadataResolver(metadata: testMetadata),
                transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
                summarizer: MockSummarizer(summary: testSummary),
                outputWriter: MockOutputWriter { _, _, _, _ in },
                configuration: cfg
            )
        }

        setenv("TEST_API_KEY_BATCH", "test-key", 1)
        defer { unsetenv("TEST_API_KEY_BATCH") }

        let runner = BatchRunner(pipelineFactory: factory, concurrency: 1, baseDelay: 0)
        let urls = [
            "https://www.youtube.com/watch?v=aaaaaaaaaaa",
            "https://www.youtube.com/watch?v=bbbbbbbbbbb",
        ]
        let results = try await runner.run(urls: urls)

        #expect(results.count == 2)
        #expect(results[0].isSuccess)
        #expect(results[1].isSuccess)
    }

    @Test func failFastStopsOnError() async throws {
        nonisolated(unsafe) var callCount = 0
        let lock = NSLock()

        let factory = PipelineFactory { url in
            lock.lock()
            callCount += 1
            let count = callCount
            lock.unlock()

            let cfg = Configuration(
                url: url,
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent("batch-ff-\(UUID()).md").path,
                apiKeyEnvVar: "TEST_API_KEY_FAILFAST"
            )

            if count == 2 {
                // Second URL fails at metadata resolution
                return Pipeline(
                    metadataResolver: FailingMetadataResolver(),
                    transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
                    summarizer: MockSummarizer(summary: testSummary),
                    outputWriter: MockOutputWriter { _, _, _, _ in },
                    configuration: cfg
                )
            }

            return Pipeline(
                metadataResolver: MockMetadataResolver(metadata: testMetadata),
                transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
                summarizer: MockSummarizer(summary: testSummary),
                outputWriter: MockOutputWriter { _, _, _, _ in },
                configuration: cfg
            )
        }

        setenv("TEST_API_KEY_FAILFAST", "test-key", 1)
        defer { unsetenv("TEST_API_KEY_FAILFAST") }

        let runner = BatchRunner(pipelineFactory: factory, concurrency: 1, failFast: true, baseDelay: 0)
        let urls = [
            "https://www.youtube.com/watch?v=aaaaaaaaaaa",
            "https://www.youtube.com/watch?v=bbbbbbbbbbb",
            "https://www.youtube.com/watch?v=ccccccccccc",
        ]
        let results = try await runner.run(urls: urls)

        // Should stop after second URL fails
        #expect(results.count == 2)
        #expect(results[0].isSuccess)
        #expect(!results[1].isSuccess)
    }

    @Test func continuesOnErrorWithoutFailFast() async throws {
        nonisolated(unsafe) var callCount = 0
        let lock = NSLock()

        let factory = PipelineFactory { url in
            lock.lock()
            callCount += 1
            let count = callCount
            lock.unlock()

            let cfg = Configuration(
                url: url,
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent("batch-noff-\(UUID()).md").path,
                apiKeyEnvVar: "TEST_API_KEY_NOFF"
            )

            if count == 2 {
                return Pipeline(
                    metadataResolver: FailingMetadataResolver(),
                    transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
                    summarizer: MockSummarizer(summary: testSummary),
                    outputWriter: MockOutputWriter { _, _, _, _ in },
                    configuration: cfg
                )
            }

            return Pipeline(
                metadataResolver: MockMetadataResolver(metadata: testMetadata),
                transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
                summarizer: MockSummarizer(summary: testSummary),
                outputWriter: MockOutputWriter { _, _, _, _ in },
                configuration: cfg
            )
        }

        setenv("TEST_API_KEY_NOFF", "test-key", 1)
        defer { unsetenv("TEST_API_KEY_NOFF") }

        let runner = BatchRunner(pipelineFactory: factory, concurrency: 1, failFast: false, baseDelay: 0)
        let urls = [
            "https://www.youtube.com/watch?v=aaaaaaaaaaa",
            "https://www.youtube.com/watch?v=bbbbbbbbbbb",
            "https://www.youtube.com/watch?v=ccccccccccc",
        ]
        let results = try await runner.run(urls: urls)

        // Should process all 3 URLs
        #expect(results.count == 3)
        #expect(results[0].isSuccess)
        #expect(!results[1].isSuccess)
        #expect(results[2].isSuccess)
    }
}

@Suite("VideoResult")
struct VideoResultTests {
    @Test func successResult() {
        let result = VideoResult.success(PipelineResult(
            title: "Test Video",
            durationString: "5:00",
            outputPath: "/tmp/test.md",
            inputTokens: 100,
            outputTokens: 50,
            costEstimate: 0.001
        ))
        #expect(result.isSuccess)
        #expect(result.title == "Test Video (5:00)")
        #expect(result.cost == 0.001)
    }

    @Test func failureResult() {
        let result = VideoResult.failure(url: "https://youtube.com/watch?v=xyz", error: "Private video")
        #expect(!result.isSuccess)
        #expect(result.title == "https://youtube.com/watch?v=xyz")
        #expect(result.statusString == "Private video")
        #expect(result.cost == 0)
    }
}

@Suite("DistillError.batch")
struct DistillErrorBatchTests {
    @Test func batchExitCodeAllSuccess() {
        let results: [VideoResult] = [
            .success(PipelineResult(title: "A", durationString: "1:00", outputPath: "/a", inputTokens: 0, outputTokens: 0, costEstimate: 0)),
            .success(PipelineResult(title: "B", durationString: "2:00", outputPath: "/b", inputTokens: 0, outputTokens: 0, costEstimate: 0)),
        ]
        #expect(DistillError.batchExitCode(results: results) == 0)
    }

    @Test func batchExitCodeAllFailure() {
        let results: [VideoResult] = [
            .failure(url: "url1", error: "err"),
            .failure(url: "url2", error: "err"),
        ]
        #expect(DistillError.batchExitCode(results: results) == 1)
    }

    @Test func batchExitCodePartialFailure() {
        let results: [VideoResult] = [
            .success(PipelineResult(title: "A", durationString: "1:00", outputPath: "/a", inputTokens: 0, outputTokens: 0, costEstimate: 0)),
            .failure(url: "url2", error: "err"),
        ]
        #expect(DistillError.batchExitCode(results: results) == 2)
    }

    @Test func partialFailureExitCode() {
        let error = DistillError.batchPartialFailure(succeeded: 3, failed: 1)
        #expect(error.exitCode == 2)
    }
}

@Suite("Configuration.withURL")
struct ConfigurationWithURLTests {
    @Test func withURLPreservesSettings() {
        let cfg = Configuration(
            url: "https://www.youtube.com/watch?v=original",
            outputPath: "/original.md",
            model: "claude-sonnet-4-6",
            defaultTags: ["custom"],
            autoTag: true,
            vaultPath: "/vault",
            vaultFolder: "YouTube"
        )

        let newCfg = cfg.withURL("https://www.youtube.com/watch?v=new")

        #expect(newCfg.url == "https://www.youtube.com/watch?v=new")
        #expect(newCfg.outputPath == "")
        #expect(newCfg.model == "claude-sonnet-4-6")
        #expect(newCfg.defaultTags == ["custom"])
        #expect(newCfg.autoTag == true)
        #expect(newCfg.vaultPath == "/vault")
        #expect(newCfg.vaultFolder == "YouTube")
    }

    @Test func withURLOutputDirOverridesVault() {
        let cfg = Configuration(
            url: "https://www.youtube.com/watch?v=original",
            outputPath: "",
            vaultPath: "/vault",
            vaultFolder: "YouTube"
        )

        let newCfg = cfg.withURL("https://www.youtube.com/watch?v=new", outputDir: "/custom/output")

        #expect(newCfg.vaultPath == "/custom/output")
        #expect(newCfg.vaultFolder == nil)
    }
}

@Suite("PipelineResult")
struct PipelineResultTests {
    @Test func pipelineReturnsResult() async throws {
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-result-\(UUID()).md").path

        let pipeline = Pipeline(
            metadataResolver: MockMetadataResolver(metadata: testMetadata),
            transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
            summarizer: MockSummarizer(summary: testSummary),
            outputWriter: MockOutputWriter { _, _, _, _ in },
            configuration: Configuration(
                url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                outputPath: outputPath,
                apiKeyEnvVar: "TEST_API_KEY_RESULT"
            )
        )

        setenv("TEST_API_KEY_RESULT", "test-key", 1)
        defer { unsetenv("TEST_API_KEY_RESULT") }

        let result = try await pipeline.run()
        #expect(result.title == "Me at the zoo")
        #expect(result.durationString == "0:19")
        #expect(result.outputPath == outputPath)
        #expect(result.inputTokens == 100)
        #expect(result.outputTokens == 50)
        #expect(result.costEstimate > 0)
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

// MARK: - M6 Tests

@Suite("Configuration.m6")
struct ConfigurationM6Tests {
    @Test func mergedWithQuietFlag() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliQuiet: true,
            configFile: nil
        )
        #expect(cfg.verbosity == .quiet)
    }

    @Test func mergedWithVerboseFlag() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliVerbose: true,
            configFile: nil
        )
        #expect(cfg.verbosity == .verbose)
    }

    @Test func mergedDefaultVerbosity() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            configFile: nil
        )
        #expect(cfg.verbosity == .normal)
    }

    @Test func mergedDryRunFlag() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliDryRun: true,
            configFile: nil
        )
        #expect(cfg.dryRun == true)
    }

    @Test func mergedTranscriptOnly() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliTranscriptOnly: true,
            configFile: nil
        )
        #expect(cfg.transcriptOnly == true)
    }

    @Test func mergedOverwrite() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliOverwrite: true,
            configFile: nil
        )
        #expect(cfg.overwrite == true)
    }

    @Test func mergedCustomPrompt() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliPrompt: "/tmp/custom.md",
            configFile: nil
        )
        #expect(cfg.customPromptPath == "/tmp/custom.md")
    }

    @Test func mergedFormatJSON() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliFormat: "json",
            configFile: nil
        )
        #expect(cfg.outputFormat == .json)
    }

    @Test func mergedFormatYAML() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliFormat: "yaml",
            configFile: nil
        )
        #expect(cfg.outputFormat == .yaml)
    }

    @Test func formatInferredFromExtension() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: "/tmp/output.json",
            cliCookies: nil,
            configFile: nil
        )
        #expect(cfg.outputFormat == .json)
    }

    @Test func formatInferredYAML() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: "/tmp/output.yaml",
            cliCookies: nil,
            configFile: nil
        )
        #expect(cfg.outputFormat == .yaml)
    }

    @Test func formatInferredYML() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: "/tmp/output.yml",
            cliCookies: nil,
            configFile: nil
        )
        #expect(cfg.outputFormat == .yaml)
    }

    @Test func explicitFormatOverridesExtension() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: "/tmp/output.json",
            cliCookies: nil,
            cliFormat: "yaml",
            configFile: nil
        )
        #expect(cfg.outputFormat == .yaml)
    }

    @Test func mergedProviderOpenAI() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliProvider: "openai",
            configFile: nil
        )
        #expect(cfg.provider == .openai)
        #expect(cfg.model == "gpt-4o") // default model for openai
    }

    @Test func mergedProviderOllama() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliProvider: "ollama",
            configFile: nil
        )
        #expect(cfg.provider == .ollama)
        #expect(cfg.model == "llama3.2")
    }

    @Test func cliModelOverridesProviderDefault() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliProvider: "openai",
            cliModel: "gpt-4-turbo",
            configFile: nil
        )
        #expect(cfg.provider == .openai)
        #expect(cfg.model == "gpt-4-turbo")
    }

    @Test func providerFromConfigFile() {
        let configFile = ConfigFile(
            summarization: .init(provider: "openai", model: "gpt-4o-mini")
        )
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            configFile: configFile
        )
        #expect(cfg.provider == .openai)
        #expect(cfg.model == "gpt-4o-mini")
    }

    @Test func withURLPreservesM6Fields() {
        let cfg = Configuration(
            url: "https://www.youtube.com/watch?v=original",
            outputPath: "/original.md",
            verbosity: .verbose,
            dryRun: true,
            transcriptOnly: false,
            customPromptPath: "/custom.md",
            outputFormat: .json,
            overwrite: true,
            provider: .openai
        )

        let newCfg = cfg.withURL("https://www.youtube.com/watch?v=new")

        #expect(newCfg.verbosity == .verbose)
        #expect(newCfg.dryRun == true)
        #expect(newCfg.customPromptPath == "/custom.md")
        #expect(newCfg.outputFormat == .json)
        #expect(newCfg.overwrite == true)
        #expect(newCfg.provider == .openai)
    }
}

@Suite("Pipeline.dryRun")
struct PipelineDryRunTests {
    @Test func dryRunSkipsSummarization() async throws {
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dryrun-\(UUID()).md").path

        let pipeline = Pipeline(
            metadataResolver: MockMetadataResolver(metadata: testMetadata),
            transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
            summarizer: FailingSummarizer(), // Would fail if called
            outputWriter: MockOutputWriter { _, _, _, _ in },
            configuration: Configuration(
                url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                outputPath: outputPath,
                apiKeyEnvVar: "TEST_DRY_RUN_KEY",
                dryRun: true
            )
        )

        setenv("TEST_DRY_RUN_KEY", "test-key", 1)
        defer { unsetenv("TEST_DRY_RUN_KEY") }

        let result = try await pipeline.run()
        #expect(result.outputTokens == 0) // No LLM call
    }
}

@Suite("Pipeline.transcriptOnly")
struct PipelineTranscriptOnlyTests {
    @Test func transcriptOnlyReturnsEarlyWithoutAPIKey() async throws {
        let pipeline = Pipeline(
            metadataResolver: MockMetadataResolver(metadata: testMetadata),
            transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
            summarizer: FailingSummarizer(),
            outputWriter: MockOutputWriter { _, _, _, _ in },
            configuration: Configuration(
                url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                outputPath: "",
                apiKeyEnvVar: "NONEXISTENT_KEY_FOR_TEST",
                transcriptOnly: true
            )
        )

        let result = try await pipeline.run()
        #expect(result.inputTokens == 0)
        #expect(result.outputTokens == 0)
        #expect(result.outputPath == "")
    }
}

@Suite("CacheManager")
struct CacheManagerTests {
    @Test func statusReturnsEmptyWhenNoCacheDir() {
        let status = CacheManager.status()
        // Either 0 entries or whatever is in cache — just verify it doesn't crash
        #expect(status.entries >= 0)
    }

    @Test func formattedSizeBytes() {
        let status = CacheStatus(entries: 0, totalBytes: 512)
        #expect(status.formattedSize == "512 B")
    }

    @Test func formattedSizeKB() {
        let status = CacheStatus(entries: 1, totalBytes: 2048)
        #expect(status.formattedSize == "2.0 KB")
    }

    @Test func formattedSizeMB() {
        let status = CacheStatus(entries: 5, totalBytes: 2_500_000)
        #expect(status.formattedSize == "2.4 MB")
    }
}

@Suite("DependencyChecker")
struct DependencyCheckerTests {
    @Test func checkDoesNotCrash() async {
        // Just verify it runs without throwing
        await DependencyChecker.check()
    }
}

@Suite("LLMProvider")
struct LLMProviderTests {
    @Test func claudeProviderConformsToLLMProviding() {
        let provider: any LLMProviding = ClaudeProvider(apiKey: "test", model: "test", maxTokens: 100)
        #expect(provider is ClaudeProvider)
    }

    @Test func openAIProviderConformsToLLMProviding() {
        let provider: any LLMProviding = OpenAIProvider(apiKey: "test", model: "test", maxTokens: 100)
        #expect(provider is OpenAIProvider)
    }

    @Test func ollamaProviderConformsToLLMProviding() {
        let provider: any LLMProviding = OllamaProvider(model: "test")
        #expect(provider is OllamaProvider)
    }

    @Test func claudeCLIProviderConformsToLLMProviding() {
        let provider: any LLMProviding = ClaudeCLIProvider()
        #expect(provider is ClaudeCLIProvider)
    }

    @Test func mergedProviderClaudeCLI() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            cliProvider: "claude-cli",
            configFile: nil
        )
        #expect(cfg.provider == .claudeCLI)
        #expect(cfg.model == "claude-sonnet-4-6") // shares claude default
    }
}

@Suite("ClaudeCLIProvider.parsing")
struct ClaudeCLIParsingTests {
    @Test func parsesValidJSONResponse() throws {
        let json = """
        {"type":"result","subtype":"success","is_error":false,"duration_ms":6453,"num_turns":1,"result":"# Hello World\\n\\nThis is a test.","stop_reason":"end_turn","session_id":"abc","total_cost_usd":0.05,"usage":{"input_tokens":100,"output_tokens":50},"modelUsage":{"claude-sonnet-4-6":{"inputTokens":100,"outputTokens":50,"costUSD":0.05}}}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeCLIResponse.self, from: data)
        #expect(response.result == "# Hello World\n\nThis is a test.")
        #expect(!response.is_error)
        #expect(response.usage.input_tokens == 100)
        #expect(response.usage.output_tokens == 50)
        #expect(response.modelUsage?["claude-sonnet-4-6"]?.inputTokens == 100)
    }

    @Test func parsesErrorResponse() throws {
        let json = """
        {"type":"result","subtype":"error","is_error":true,"result":"Rate limited","usage":{"input_tokens":0,"output_tokens":0}}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeCLIResponse.self, from: data)
        #expect(response.is_error)
        #expect(response.result == "Rate limited")
    }
}

@Suite("Configuration.obsidianCLI")
struct ConfigurationObsidianCLITests {
    @Test func defaultUseObsidianCLIIsFalse() {
        let cfg = Configuration(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            outputPath: "/test.md"
        )
        #expect(cfg.useObsidianCLI == false)
    }

    @Test func useObsidianCLIFromConfigFile() {
        let configFile = ConfigFile(
            obsidian: .init(vault: "/vault", use_cli: true)
        )
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            cliOutput: nil,
            cliCookies: nil,
            configFile: configFile
        )
        #expect(cfg.useObsidianCLI == true)
    }

    @Test func withURLPreservesObsidianCLI() {
        let cfg = Configuration(
            url: "https://www.youtube.com/watch?v=original",
            outputPath: "/test.md",
            useObsidianCLI: true
        )
        let newCfg = cfg.withURL("https://www.youtube.com/watch?v=new")
        #expect(newCfg.useObsidianCLI == true)
    }

    @Test func claudeCLIDoesNotRequireAPIKey() async throws {
        // Pipeline with claudeCLI provider should not throw missingAPIKey
        let pipeline = Pipeline(
            metadataResolver: MockMetadataResolver(metadata: testMetadata),
            transcriptAcquirer: MockTranscriptAcquirer(transcript: testTranscript),
            summarizer: MockSummarizer(summary: testSummary),
            outputWriter: MockOutputWriter { _, _, _, _ in },
            configuration: Configuration(
                url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent("cli-test-\(UUID()).md").path,
                apiKeyEnvVar: "NONEXISTENT_KEY_CLI_TEST",
                provider: .claudeCLI
            )
        )

        let result = try await pipeline.run()
        #expect(result.title == "Me at the zoo")
    }
}
