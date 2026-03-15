public protocol OutputWriting: Sendable {
    func write(summary: Summary, metadata: VideoMetadata, to outputPath: String, tags: [String]) throws
    func write(summary: Summary, metadata: VideoMetadata, to outputPath: String, tags: [String], format: Configuration.OutputFormat, overwrite: Bool) throws
}

extension OutputWriting {
    public func write(summary: Summary, metadata: VideoMetadata, to outputPath: String, tags: [String], format: Configuration.OutputFormat, overwrite: Bool) throws {
        try write(summary: summary, metadata: metadata, to: outputPath, tags: tags)
    }
}
