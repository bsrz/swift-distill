import ArgumentParser
import Distill
import Foundation

@main
struct CLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "distill",
        abstract: "Distill the essence of any YouTube video into your Obsidian vault."
    )

    @Argument(help: "YouTube video URL to distill.")
    var url: String

    @Option(name: .long, help: "Output file path for the markdown summary.")
    var output: String

    @Option(name: .long, help: "Browser to read cookies from for yt-dlp (e.g. brave, chrome, firefox).")
    var cookiesFromBrowser: String?

    mutating func run() async throws {
        let config = Configuration(url: url, outputPath: output, cookiesFromBrowser: cookiesFromBrowser)

        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            FileHandle.standardError.write(Data("Error: \(DistillError.missingAPIKey.errorDescription!)\n".utf8))
            FileHandle.standardError.write(Data("Suggestion: \(DistillError.missingAPIKey.suggestion!)\n".utf8))
            throw ExitCode(DistillError.missingAPIKey.exitCode)
        }

        let provider = ClaudeProvider(
            apiKey: apiKey,
            model: config.model,
            maxTokens: config.maxTokens
        )

        let pipeline = Pipeline(
            metadataResolver: MetadataResolver(cookiesFromBrowser: config.cookiesFromBrowser),
            transcriptAcquirer: TranscriptAcquirer(cookiesFromBrowser: config.cookiesFromBrowser),
            summarizer: Summarizer(provider: provider),
            outputWriter: OutputWriter(),
            configuration: config
        )

        do {
            try await pipeline.run()
        } catch let error as DistillError {
            FileHandle.standardError.write(Data("Error: \(error.errorDescription!)\n".utf8))
            if let suggestion = error.suggestion {
                FileHandle.standardError.write(Data("Suggestion: \(suggestion)\n".utf8))
            }
            throw ExitCode(error.exitCode)
        }
    }
}
