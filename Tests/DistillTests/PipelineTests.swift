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
