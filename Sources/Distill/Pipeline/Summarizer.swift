import Foundation

public struct Summarizer: Summarizing {
    private let provider: ClaudeProvider

    public init(provider: ClaudeProvider) {
        self.provider = provider
    }

    public func summarize(transcript: Transcript, metadata: VideoMetadata, prompt: String) async throws -> Summary {
        let renderedPrompt = PromptLoader.render(
            template: prompt,
            title: metadata.title,
            channel: metadata.channel,
            duration: metadata.durationString,
            transcript: transcript.fullText,
            frames: "",
            language: "en"
        )

        return try await provider.complete(prompt: renderedPrompt)
    }
}
