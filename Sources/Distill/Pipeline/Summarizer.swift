import Foundation

public struct Summarizer: Summarizing {
    private let provider: ClaudeProvider

    public init(provider: ClaudeProvider) {
        self.provider = provider
    }

    public func summarize(transcript: Transcript, metadata: VideoMetadata, prompt: String) async throws -> Summary {
        return try await provider.complete(prompt: prompt)
    }
}
