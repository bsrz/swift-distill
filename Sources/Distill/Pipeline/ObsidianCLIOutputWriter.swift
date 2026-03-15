import Foundation
import CryptoKit

public struct ObsidianCLIOutputWriter: OutputWriting {
    private let vaultName: String?

    public init(vaultName: String? = nil) {
        self.vaultName = vaultName
    }

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
        // Compute idempotency hash
        let hashInput = "\(metadata.id):\(summary.markdown)"
        let hash = SHA256.hash(data: Data(hashInput.utf8))
        let hashString = hash.prefix(16).map { String(format: "%02x", $0) }.joined()

        // Build the full note content (frontmatter + body)
        let content: String
        switch format {
        case .markdown:
            content = buildMarkdownContent(summary: summary, metadata: metadata, tags: tags, hash: hashString)
        case .json, .yaml:
            // For non-markdown formats, fall back to direct file write
            let fallback = OutputWriter()
            try fallback.write(summary: summary, metadata: metadata, to: outputPath, tags: tags, format: format, overwrite: overwrite)
            return
        }

        // Derive the note path relative to vault root from the absolute outputPath
        let filename = (outputPath as NSString).lastPathComponent
        let noteName = (filename as NSString).deletingPathExtension

        // Determine the folder path within the vault
        // outputPath is like /path/to/vault/YouTube/2025-03-14-slug.md
        // We need the path relative to vault root: YouTube/2025-03-14-slug.md
        let relativePath = resolveRelativePath(outputPath: outputPath)

        // Escape content for shell: use newline encoding
        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Build the obsidian create command
        var arguments = ["create"]
        if let vault = vaultName {
            arguments.append("vault=\(vault)")
        }

        if let relativePath {
            arguments.append("path=\(relativePath)")
        } else {
            arguments.append("name=\(noteName)")
        }

        if overwrite {
            arguments.append("overwrite")
        }
        arguments.append("silent")

        // Write content to a temp file and use it, since content may be very large
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("distill-\(UUID().uuidString).md")
        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Use shell to pipe content via stdin
        let shellCommand: String
        if let vault = vaultName {
            if let relativePath {
                shellCommand = "cat '\(tempFile.path)' | obsidian create vault=\"\(vault)\" path=\"\(relativePath)\" overwrite silent content=\"$(cat '\(tempFile.path)')\""
            } else {
                shellCommand = "obsidian create vault=\"\(vault)\" name=\"\(noteName)\" overwrite silent content=\"$(cat '\(tempFile.path)')\""
            }
        } else {
            if let relativePath {
                shellCommand = "obsidian create path=\"\(relativePath)\" overwrite silent content=\"$(cat '\(tempFile.path)')\""
            } else {
                shellCommand = "obsidian create name=\"\(noteName)\" overwrite silent content=\"$(cat '\(tempFile.path)')\""
            }
        }

        // Execute via login shell to find obsidian in PATH
        do {
            let result = try syncRun(command: shellCommand)
            if result != 0 {
                // Fall back to direct file write
                let fallback = OutputWriter()
                try fallback.write(summary: summary, metadata: metadata, to: outputPath, tags: tags, format: format, overwrite: overwrite)
            }
        } catch {
            // Fall back to direct file write if obsidian CLI fails
            let fallback = OutputWriter()
            try fallback.write(summary: summary, metadata: metadata, to: outputPath, tags: tags, format: format, overwrite: overwrite)
        }
    }

    // MARK: - Private

    private func buildMarkdownContent(summary: Summary, metadata: VideoMetadata, tags: [String], hash: String) -> String {
        var seen = Set<String>()
        let uniqueTags = tags.filter { seen.insert($0.lowercased()).inserted }
        let tagLines = uniqueTags.map { "  - \($0)" }.joined(separator: "\n")

        let today = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        let frontmatter = """
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

        return "---\n\(frontmatter)---\n\n\(summary.markdown)\n"
    }

    private func resolveRelativePath(outputPath: String) -> String? {
        // Try to extract the path relative to a vault by looking for common patterns
        // The outputPath is absolute, e.g. /Users/x/Documents/Obsidian/YouTube/note.md
        // We want: YouTube/note.md
        let components = outputPath.components(separatedBy: "/")
        // Look for the component after the vault root by finding known folder patterns
        // Simple heuristic: return the last 2 components (folder/file.md)
        if components.count >= 2 {
            let folder = components[components.count - 2]
            let file = components[components.count - 1]
            return "\(folder)/\(file)"
        }
        return nil
    }

    private func escapeFrontmatter(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func syncRun(command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
