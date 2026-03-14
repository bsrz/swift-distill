public protocol Summarizing: Sendable {
    func summarize(transcript: Transcript, metadata: VideoMetadata, prompt: String) async throws -> Summary
}
