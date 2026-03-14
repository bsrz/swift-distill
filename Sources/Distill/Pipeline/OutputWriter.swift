import Foundation

public struct OutputWriter: OutputWriting {
    public init() {}

    public func write(summary: Summary, metadata: VideoMetadata, to outputPath: String, tags: [String]) throws {
        let frontmatter = buildFrontmatter(metadata: metadata, tags: tags)
        let content = "---\n\(frontmatter)---\n\n\(summary.markdown)\n"

        let url = URL(fileURLWithPath: outputPath)
        let directory = url.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DistillError.outputWriteFailed(error.localizedDescription)
        }
    }

    private func buildFrontmatter(metadata: VideoMetadata, tags: [String]) -> String {
        let allTags = tags + metadata.tags.prefix(5)
        let tagLine = allTags.map { "  - \($0)" }.joined(separator: "\n")

        return """
        title: "\(escapeFrontmatter(metadata.title))"
        channel: "\(escapeFrontmatter(metadata.channel))"
        published: \(metadata.publishedDate)
        duration: \(metadata.durationString)
        url: \(metadata.webpageURL)
        tags:
        \(tagLine)

        """
    }

    private func escapeFrontmatter(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
