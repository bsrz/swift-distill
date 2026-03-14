public protocol OutputWriting: Sendable {
    func write(summary: Summary, metadata: VideoMetadata, to outputPath: String, tags: [String]) throws
}
