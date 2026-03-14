public protocol FrameExtracting: Sendable {
    func extract(metadata: VideoMetadata, to attachmentsDir: String) async throws -> [ExtractedFrame]
}
