import Foundation

public struct Pipeline: Sendable {
    private let metadataResolver: any MetadataResolving
    private let transcriptAcquirer: any TranscriptAcquiring
    private let summarizer: any Summarizing
    private let outputWriter: any OutputWriting
    private let tagGenerator: (any TagGenerating)?
    private let frameExtractor: (any FrameExtracting)?
    private let configuration: Configuration

    public init(
        metadataResolver: any MetadataResolving,
        transcriptAcquirer: any TranscriptAcquiring,
        summarizer: any Summarizing,
        outputWriter: any OutputWriting,
        tagGenerator: (any TagGenerating)? = nil,
        frameExtractor: (any FrameExtracting)? = nil,
        configuration: Configuration
    ) {
        self.metadataResolver = metadataResolver
        self.transcriptAcquirer = transcriptAcquirer
        self.summarizer = summarizer
        self.outputWriter = outputWriter
        self.tagGenerator = tagGenerator
        self.frameExtractor = frameExtractor
        self.configuration = configuration
    }

    @discardableResult
    public func run() async throws -> PipelineResult {
        // 1. Validate URL
        let videoID = try URLValidator.validate(configuration.url)
        log("Video ID: \(videoID)")

        // 2. Check API key
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw DistillError.missingAPIKey
        }
        _ = apiKey

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

        // 4. Acquire transcript + extract frames (concurrently if --frames)
        let transcript: Transcript
        let frames: [ExtractedFrame]

        if configuration.framesEnabled, let frameExtractor {
            let result = try await acquireTranscriptAndFrames(
                metadata: metadata,
                frameExtractor: frameExtractor
            )
            transcript = result.transcript
            frames = result.frames
        } else {
            transcript = try await acquireTranscript(metadata: metadata)
            frames = []
        }

        // 5. Generate tags (if enabled)
        var tags = configuration.defaultTags
        if configuration.autoTag, let tagGenerator {
            let tagSpinner = Spinner(message: "Generating tags...")
            await tagSpinner.start()
            do {
                let generatedTags = try await tagGenerator.generate(from: transcript, metadata: metadata)
                tags += generatedTags
                await tagSpinner.succeed("Generated \(generatedTags.count) tags")
            } catch {
                await tagSpinner.fail("Tag generation failed (continuing with default tags)")
            }
        }

        // 6. Build frames table for prompt
        let framesPromptSection = buildFramesPromptSection(frames: frames, metadata: metadata)

        // 7. Summarize
        let summarySpinner = Spinner(message: "Summarizing with \(configuration.model)...")
        await summarySpinner.start()
        let summary: Summary
        do {
            let prompt = try PromptLoader.loadDefault()
            let renderedPrompt = PromptLoader.render(
                template: prompt,
                title: metadata.title,
                channel: metadata.channel,
                duration: metadata.durationString,
                transcript: transcript.fullText,
                frames: framesPromptSection,
                language: "en"
            )
            summary = try await summarizer.summarize(
                transcript: transcript,
                metadata: metadata,
                prompt: renderedPrompt
            )
            await summarySpinner.succeed("Summarization complete")
        } catch {
            await summarySpinner.fail("Summarization failed")
            throw error
        }

        // Cost estimate (Sonnet pricing: $3/M input, $15/M output)
        let costEstimate = Double(summary.inputTokens * 3 + summary.outputTokens * 15) / 1_000_000.0
        log("Tokens: \(summary.inputTokens) in / \(summary.outputTokens) out (~$\(String(format: "%.4f", costEstimate)))")

        // 8. Resolve output path
        let outputPath = configuration.resolvedOutputPath(for: metadata)
        guard !outputPath.isEmpty else {
            throw DistillError.configurationError(
                "No output path. Use --output or configure obsidian.vault in ~/.distill/config.yaml"
            )
        }

        // 9. Write output
        let writeSpinner = Spinner(message: "Writing output...")
        await writeSpinner.start()
        do {
            try outputWriter.write(
                summary: summary,
                metadata: metadata,
                to: outputPath,
                tags: tags
            )
            await writeSpinner.succeed("Written to \(outputPath)")
        } catch {
            await writeSpinner.fail("Failed to write output")
            throw error
        }

        // 10. Print output path to stdout
        print(outputPath)

        return PipelineResult(
            title: metadata.title,
            durationString: metadata.durationString,
            outputPath: outputPath,
            inputTokens: summary.inputTokens,
            outputTokens: summary.outputTokens,
            costEstimate: costEstimate
        )
    }

    // MARK: - Private

    private func acquireTranscript(metadata: VideoMetadata) async throws -> Transcript {
        let spinner = Spinner(message: "Extracting transcript...")
        await spinner.start()
        do {
            let transcript = try await transcriptAcquirer.acquire(metadata: metadata)
            await spinner.succeed("Extracted transcript (\(transcript.segments.count) segments, \(transcript.source.rawValue))")
            return transcript
        } catch {
            await spinner.fail("Failed to extract transcript")
            throw error
        }
    }

    /// Run transcript acquisition and frame extraction concurrently via TaskGroup.
    /// If transcript fails, frame extraction is cancelled.
    private func acquireTranscriptAndFrames(
        metadata: VideoMetadata,
        frameExtractor: any FrameExtracting
    ) async throws -> (transcript: Transcript, frames: [ExtractedFrame]) {
        enum StageResult: Sendable {
            case transcript(Transcript)
            case frames([ExtractedFrame])
        }

        let attachmentsDir = configuration.resolvedAttachmentsDir(for: metadata)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("distill-frames").path

        return try await withThrowingTaskGroup(of: StageResult.self) { group in
            // Transcript task
            group.addTask {
                let spinner = Spinner(message: "Extracting transcript...")
                await spinner.start()
                do {
                    let transcript = try await self.transcriptAcquirer.acquire(metadata: metadata)
                    await spinner.succeed("Extracted transcript (\(transcript.segments.count) segments, \(transcript.source.rawValue))")
                    return .transcript(transcript)
                } catch {
                    await spinner.fail("Failed to extract transcript")
                    throw error
                }
            }

            // Frame extraction task
            group.addTask {
                return .frames(try await frameExtractor.extract(metadata: metadata, to: attachmentsDir))
            }

            var transcript: Transcript?
            var frames: [ExtractedFrame] = []

            for try await result in group {
                switch result {
                case .transcript(let t):
                    transcript = t
                case .frames(let f):
                    frames = f
                }
            }

            guard let transcript else {
                throw DistillError.transcriptNotAvailable
            }

            return (transcript, frames)
        }
    }

    private func buildFramesPromptSection(frames: [ExtractedFrame], metadata: VideoMetadata) -> String {
        guard !frames.isEmpty else { return "" }

        let syntax = configuration.imageSyntax
        let syntaxNote = syntax == .wikilink
            ? "Use Obsidian wikilink syntax for images: ![[path/filename.png]]"
            : "Use standard markdown syntax for images: ![alt text](path/filename.png)"

        var section = """
        ## Extracted Frames

        The following frames were extracted from the video. \(syntaxNote)
        Choose the most relevant frames and place them inline within your section summaries.

        | Timestamp | Filename |
        |-----------|----------|

        """

        for frame in frames {
            let relativePath = configuration.relativeAttachmentPath(for: metadata, filename: frame.filename)
            section += "| \(frame.timestampString) | \(relativePath) |\n"
        }

        return section
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("  \(message)\n".utf8))
    }
}
