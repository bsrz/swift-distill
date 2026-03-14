public protocol TagGenerating: Sendable {
    func generate(from transcript: Transcript, metadata: VideoMetadata) async throws -> [String]
}
