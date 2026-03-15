import Foundation

public struct Summarizer: Summarizing {
    private let provider: any LLMProviding

    public init(provider: any LLMProviding) {
        self.provider = provider
    }

    public func summarize(transcript: Transcript, metadata: VideoMetadata, prompt: String) async throws -> Summary {
        return try await provider.complete(prompt: prompt)
    }
}
