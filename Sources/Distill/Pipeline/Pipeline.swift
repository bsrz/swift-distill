import Foundation

public struct Pipeline: Sendable {
    private let metadataResolver: any MetadataResolving
    private let transcriptAcquirer: any TranscriptAcquiring
    private let summarizer: any Summarizing
    private let outputWriter: any OutputWriting
    private let configuration: Configuration

    public init(
        metadataResolver: any MetadataResolving,
        transcriptAcquirer: any TranscriptAcquiring,
        summarizer: any Summarizing,
        outputWriter: any OutputWriting,
        configuration: Configuration
    ) {
        self.metadataResolver = metadataResolver
        self.transcriptAcquirer = transcriptAcquirer
        self.summarizer = summarizer
        self.outputWriter = outputWriter
        self.configuration = configuration
    }

    public func run() async throws {
        // 1. Validate URL
        let videoID = try URLValidator.validate(configuration.url)
        log("Video ID: \(videoID)")

        // 2. Check API key
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw DistillError.missingAPIKey
        }

        // 3. Resolve metadata
        let metadataSpinner = Spinner(message: "Fetching video metadata...")
        await metadataSpinner.start()
        let metadata: VideoMetadata
        do {
            metadata = try await metadataResolver.resolve(url: configuration.url)
            await metadataSpinner.succeed("Fetched metadata: \(metadata.title)")
        } catch {
            await metadataSpinner.fail("Failed to fetch metadata")
            throw error
        }

        // 4. Acquire transcript
        let transcriptSpinner = Spinner(message: "Extracting transcript...")
        await transcriptSpinner.start()
        let transcript: Transcript
        do {
            transcript = try await transcriptAcquirer.acquire(metadata: metadata)
            await transcriptSpinner.succeed("Extracted transcript (\(transcript.segments.count) segments, \(transcript.source.rawValue))")
        } catch {
            await transcriptSpinner.fail("Failed to extract transcript")
            throw error
        }

        // 5. Summarize
        let summarySpinner = Spinner(message: "Summarizing with \(configuration.model)...")
        await summarySpinner.start()
        let summary: Summary
        do {
            let prompt = try PromptLoader.loadDefault()
            summary = try await summarizer.summarize(
                transcript: transcript,
                metadata: metadata,
                prompt: prompt
            )
            await summarySpinner.succeed("Summarization complete")
        } catch {
            await summarySpinner.fail("Summarization failed")
            throw error
        }

        // Cost estimate (Sonnet pricing: $3/M input, $15/M output)
        let costEstimate = Double(summary.inputTokens * 3 + summary.outputTokens * 15) / 1_000_000.0
        log("Tokens: \(summary.inputTokens) in / \(summary.outputTokens) out (~$\(String(format: "%.4f", costEstimate)))")

        // 6. Write output
        let writeSpinner = Spinner(message: "Writing output...")
        await writeSpinner.start()
        do {
            try outputWriter.write(
                summary: summary,
                metadata: metadata,
                to: configuration.outputPath,
                tags: configuration.defaultTags
            )
            await writeSpinner.succeed("Written to \(configuration.outputPath)")
        } catch {
            await writeSpinner.fail("Failed to write output")
            throw error
        }

        // 7. Print output path
        print(configuration.outputPath)
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("  \(message)\n".utf8))
    }
}
