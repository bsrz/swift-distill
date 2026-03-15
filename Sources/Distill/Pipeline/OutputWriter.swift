import Foundation
import CryptoKit

public struct OutputWriter: OutputWriting {
    public init() {}

    public func write(summary: Summary, metadata: VideoMetadata, to outputPath: String, tags: [String]) throws {
        try write(summary: summary, metadata: metadata, to: outputPath, tags: tags, format: .markdown, overwrite: false)
    }

    public func write(
        summary: Summary,
        metadata: VideoMetadata,
        to outputPath: String,
        tags: [String],
        format: Configuration.OutputFormat,
        overwrite: Bool
    ) throws {
        let url = URL(fileURLWithPath: outputPath)
        let directory = url.deletingLastPathComponent()

        // Idempotency: compute hash from video ID + transcript content
        let hashInput = "\(metadata.id):\(summary.markdown)"
        let hash = SHA256.hash(data: Data(hashInput.utf8))
        let hashString = hash.prefix(16).map { String(format: "%02x", $0) }.joined()

        // Check existing file for matching hash (skip unless --overwrite)
        if !overwrite, FileManager.default.fileExists(atPath: outputPath) {
            let existing = try? String(contentsOfFile: outputPath, encoding: .utf8)
            if let existing, existing.contains("distill_hash: \(hashString)") {
                return // Already up to date
            }
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let content: String
        switch format {
        case .markdown:
            let frontmatter = buildFrontmatter(metadata: metadata, tags: tags, hash: hashString)
            content = "---\n\(frontmatter)---\n\n\(summary.markdown)\n"
        case .json:
            content = try buildJSON(summary: summary, metadata: metadata, tags: tags, hash: hashString)
        case .yaml:
            content = try buildYAML(summary: summary, metadata: metadata, tags: tags, hash: hashString)
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DistillError.outputWriteFailed(error.localizedDescription)
        }
    }

    private func buildFrontmatter(metadata: VideoMetadata, tags: [String], hash: String) -> String {
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
        distill_hash: \(hash)
        tags:
        \(tagLines)
        type: youtube-summary

        """
    }

    private func buildJSON(summary: Summary, metadata: VideoMetadata, tags: [String], hash: String) throws -> String {
        let obj: [String: Any] = [
            "title": metadata.title,
            "source": metadata.webpageURL,
            "channel": metadata.channel,
            "published": metadata.publishedDate,
            "duration": metadata.durationString,
            "distill_hash": hash,
            "tags": tags,
            "summary": summary.markdown,
            "tokens": [
                "input": summary.inputTokens,
                "output": summary.outputTokens
            ],
            "model": summary.model
        ]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func buildYAML(summary: Summary, metadata: VideoMetadata, tags: [String], hash: String) throws -> String {
        var seen = Set<String>()
        let uniqueTags = tags.filter { seen.insert($0.lowercased()).inserted }
        let tagLines = uniqueTags.map { "  - \($0)" }.joined(separator: "\n")

        let escapedSummary = summary.markdown
            .components(separatedBy: .newlines)
            .map { "  \($0)" }
            .joined(separator: "\n")

        return """
        title: "\(escapeFrontmatter(metadata.title))"
        source: \(metadata.webpageURL)
        channel: "\(escapeFrontmatter(metadata.channel))"
        published: \(metadata.publishedDate)
        duration: "\(metadata.durationString)"
        distill_hash: \(hash)
        tags:
        \(tagLines)
        model: \(summary.model)
        tokens:
          input: \(summary.inputTokens)
          output: \(summary.outputTokens)
        summary: |
        \(escapedSummary)

        """
    }

    private func escapeFrontmatter(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
