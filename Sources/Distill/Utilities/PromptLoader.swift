import Foundation

public struct PromptLoader: Sendable {
    public static func loadDefault() throws -> String {
        guard let url = Bundle.module.url(forResource: "default-prompt", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw DistillError.configurationError("Default prompt not found in bundle.")
        }
        return content
    }

    public static func render(
        template: String,
        title: String,
        channel: String,
        duration: String,
        transcript: String,
        frames: String = "",
        language: String = "en"
    ) -> String {
        template
            .replacingOccurrences(of: "{{title}}", with: title)
            .replacingOccurrences(of: "{{channel}}", with: channel)
            .replacingOccurrences(of: "{{duration}}", with: duration)
            .replacingOccurrences(of: "{{transcript}}", with: transcript)
            .replacingOccurrences(of: "{{frames}}", with: frames)
            .replacingOccurrences(of: "{{language}}", with: language)
    }
}
