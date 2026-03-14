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
        // Deduplicate tags preserving order
        var seen = Set<String>()
        let uniqueTags = tags.filter { seen.insert($0.lowercased()).inserted }
        let tagLines = uniqueTags.map { "  - \($0)" }.joined(separator: "\n")

        let today = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        return """
        title: "\(escapeFrontmatter(metadata.title))"
        source: \(metadata.webpageURL)
        channel: "\(escapeFrontmatter(metadata.channel))"
        published: \(metadata.publishedDate)
        summarized: \(today)
        duration: "\(metadata.durationString)"
        tags:
        \(tagLines)
        type: youtube-summary

        """
    }

    private func escapeFrontmatter(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
