import Foundation

public struct Configuration: Sendable {
    public let url: String
    public let outputPath: String
    public let apiKeyEnvVar: String
    public let model: String
    public let maxTokens: Int
    public let defaultTags: [String]
    public let cookiesFromBrowser: String?

    public var apiKey: String? {
        ProcessInfo.processInfo.environment[apiKeyEnvVar]
    }

    public init(
        url: String,
        outputPath: String,
        apiKeyEnvVar: String = "ANTHROPIC_API_KEY",
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 8192,
        defaultTags: [String] = ["youtube"],
        cookiesFromBrowser: String? = nil
    ) {
        self.url = url
        self.outputPath = outputPath
        self.apiKeyEnvVar = apiKeyEnvVar
        self.model = model
        self.maxTokens = maxTokens
        self.defaultTags = defaultTags
        self.cookiesFromBrowser = cookiesFromBrowser
    }
}
