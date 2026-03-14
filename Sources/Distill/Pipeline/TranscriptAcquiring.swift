public protocol TranscriptAcquiring: Sendable {
    func acquire(metadata: VideoMetadata) async throws -> Transcript
}
