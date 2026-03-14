import Foundation

public struct Configuration: Sendable {
    public let url: String
    public let outputPath: String
    public let apiKeyEnvVar: String
    public let model: String
    public let maxTokens: Int
    public let defaultTags: [String]
    public let cookiesFromBrowser: String?
    public let autoTag: Bool
    public let vaultPath: String?
    public let vaultFolder: String?
    public let filenameFormat: String

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
        cookiesFromBrowser: String? = nil,
        autoTag: Bool = false,
        vaultPath: String? = nil,
        vaultFolder: String? = nil,
        filenameFormat: String = "{date}-{slug}"
    ) {
        self.url = url
        self.outputPath = outputPath
        self.apiKeyEnvVar = apiKeyEnvVar
        self.model = model
        self.maxTokens = maxTokens
        self.defaultTags = defaultTags
        self.cookiesFromBrowser = cookiesFromBrowser
        self.autoTag = autoTag
        self.vaultPath = vaultPath
        self.vaultFolder = vaultFolder
        self.filenameFormat = filenameFormat
    }

    /// Resolves the final output path. If `outputPath` was explicitly set, use it.
    /// Otherwise, build from vault + folder + filename format + metadata.
    public func resolvedOutputPath(for metadata: VideoMetadata) -> String {
        // If user gave an explicit --output, use it as-is
        if !outputPath.isEmpty {
            return outputPath
        }

        // Build from vault config
        guard let vault = vaultPath else {
            return outputPath
        }

        let expandedVault = NSString(string: vault).expandingTildeInPath
        let date = currentDateString()
        let slug = SlugGenerator.generate(from: metadata.title)
        let filename = filenameFormat
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{slug}", with: slug)

        var components = [expandedVault]
        if let folder = vaultFolder, !folder.isEmpty {
            components.append(folder)
        }
        components.append("\(filename).md")

        return components.joined(separator: "/")
    }

    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Merge CLI options over a config file, falling back to defaults.
    public static func merged(
        url: String,
        cliOutput: String?,
        cliCookies: String?,
        configFile: ConfigFile?
    ) -> Configuration {
        let cfg = configFile

        let apiKeyEnvVar = cfg?.summarization?.api_key_env ?? "ANTHROPIC_API_KEY"
        let model = cfg?.summarization?.model ?? "claude-sonnet-4-6"
        let maxTokens = cfg?.summarization?.max_tokens ?? 8192
        let defaultTags = cfg?.tags?.default ?? ["youtube"]
        let autoTag = cfg?.tags?.auto_tag ?? false
        let vaultPath = cfg?.obsidian?.vault
        let vaultFolder = cfg?.obsidian?.folder ?? "YouTube"
        let filenameFormat = cfg?.obsidian?.filename_format ?? "{date}-{slug}"
        let cookies = cliCookies ?? cfg?.cookies_from_browser

        return Configuration(
            url: url,
            outputPath: cliOutput ?? "",
            apiKeyEnvVar: apiKeyEnvVar,
            model: model,
            maxTokens: maxTokens,
            defaultTags: defaultTags,
            cookiesFromBrowser: cookies,
            autoTag: autoTag,
            vaultPath: vaultPath,
            vaultFolder: vaultFolder,
            filenameFormat: filenameFormat
        )
    }
}
