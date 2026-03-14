import Foundation

/// Generates an index note for a playlist linking to all individual summaries.
public struct IndexNoteWriter: Sendable {
    public init() {}

    public func write(
        playlistTitle: String,
        results: [VideoResult],
        to outputDir: String,
        filenameFormat: String
    ) throws {
        let date = currentDateString()
        let slug = SlugGenerator.generate(from: playlistTitle)
        let filename = filenameFormat
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{slug}", with: slug)
        let indexPath = "\(outputDir)/\(filename)-index.md"

        var content = """
        ---
        title: "\(playlistTitle.replacingOccurrences(of: "\"", with: "\\\""))"
        type: playlist-index
        created: \(date)
        videos: \(results.count)
        ---

        # \(playlistTitle)

        | # | Video | Status |
        |---|-------|--------|

        """

        for (index, result) in results.enumerated() {
            switch result {
            case .success(let pipelineResult):
                let noteFilename = URL(fileURLWithPath: pipelineResult.outputPath).lastPathComponent
                let noteLink = String(noteFilename.dropLast(3)) // Remove .md
                content += "| \(index + 1) | [[\(noteLink)]] | Saved |\n"
            case .failure(let url, let error):
                content += "| \(index + 1) | \(url) | Failed: \(error.prefix(40)) |\n"
            }
        }

        let succeeded = results.filter(\.isSuccess).count
        content += "\n**\(succeeded)/\(results.count)** videos summarized successfully.\n"

        // Create directory and write
        let dir = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(toFile: indexPath, atomically: true, encoding: .utf8)

        FileHandle.standardError.write(Data("  Index note: \(indexPath)\n".utf8))
    }

    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
