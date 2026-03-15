import Foundation

public struct TagGenerator: TagGenerating {
    private let provider: any LLMProviding

    public init(provider: any LLMProviding) {
        self.provider = provider
    }

    public func generate(from transcript: Transcript, metadata: VideoMetadata) async throws -> [String] {
        let prompt = """
        Analyze the following YouTube video and generate relevant tags for categorization.

        Title: \(metadata.title)
        Channel: \(metadata.channel)
        Description: \(metadata.description)

        Transcript excerpt (first 2000 characters):
        \(String(transcript.fullText.prefix(2000)))

        Return ONLY a JSON array of lowercase, hyphenated tags (3-8 tags). \
        Focus on the main topics, technologies, and themes. Example: ["swift-concurrency", "ios-development", "async-await"]

        JSON array:
        """

        let summary = try await provider.complete(prompt: prompt)
        return parseTags(from: summary.markdown)
    }

    private func parseTags(from response: String) -> [String] {
        // Extract JSON array from response
        guard let start = response.firstIndex(of: "["),
              let end = response.lastIndex(of: "]") else {
            return []
        }

        let jsonString = String(response[start...end])
        guard let data = jsonString.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return tags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
    }
}
