public protocol MetadataResolving: Sendable {
    func resolve(url: String) async throws -> VideoMetadata
}
