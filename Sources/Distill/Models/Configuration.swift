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
    public let framesEnabled: Bool
    public let frameConfig: FrameConfig
    public let attachmentsFolder: String
    public let imageSyntax: ImageSyntax
    public let transcriptionMethod: TranscriptionMethod
    public let whisperEngine: WhisperEngine
    public let whisperModel: String
    public let transcriptionLanguage: String
    public let openAIAPIKeyEnvVar: String

    public enum ImageSyntax: String, Sendable {
        case markdown
        case wikilink
    }

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
        filenameFormat: String = "{date}-{slug}",
        framesEnabled: Bool = false,
        frameConfig: FrameConfig = FrameConfig(),
        attachmentsFolder: String = "YouTube/attachments",
        imageSyntax: ImageSyntax = .markdown,
        transcriptionMethod: TranscriptionMethod = .captions,
        whisperEngine: WhisperEngine = .mlxWhisper,
        whisperModel: String = "base",
        transcriptionLanguage: String = "en",
        openAIAPIKeyEnvVar: String = "OPENAI_API_KEY"
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
        self.framesEnabled = framesEnabled
        self.frameConfig = frameConfig
        self.attachmentsFolder = attachmentsFolder
        self.imageSyntax = imageSyntax
        self.transcriptionMethod = transcriptionMethod
        self.whisperEngine = whisperEngine
        self.whisperModel = whisperModel
        self.transcriptionLanguage = transcriptionLanguage
        self.openAIAPIKeyEnvVar = openAIAPIKeyEnvVar
    }

    /// Resolves the final output path.
    public func resolvedOutputPath(for metadata: VideoMetadata) -> String {
        if !outputPath.isEmpty {
            return outputPath
        }

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

    /// Resolves the attachments directory for frames.
    public func resolvedAttachmentsDir(for metadata: VideoMetadata) -> String? {
        guard let vault = vaultPath else { return nil }
        let expandedVault = NSString(string: vault).expandingTildeInPath
        let slug = SlugGenerator.generate(from: metadata.title)
        return "\(expandedVault)/\(attachmentsFolder)/\(slug)"
    }

    /// Returns the relative path from the markdown file to an attachment.
    public func relativeAttachmentPath(for metadata: VideoMetadata, filename: String) -> String {
        let slug = SlugGenerator.generate(from: metadata.title)
        // Relative from YouTube/ folder to YouTube/attachments/slug/
        return "attachments/\(slug)/\(filename)"
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
        cliFrames: Bool = false,
        cliTranscription: String? = nil,
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
        let attachmentsFolder = cfg?.obsidian?.attachments ?? "YouTube/attachments"
        let imageSyntaxStr = cfg?.obsidian?.image_syntax ?? "markdown"
        let imageSyntax = ImageSyntax(rawValue: imageSyntaxStr) ?? .markdown

        let frameConfig = FrameConfig(
            maxFrames: cfg?.frames?.max_frames ?? 20,
            intervalSeconds: cfg?.frames?.interval_seconds ?? 60,
            sceneDetection: cfg?.frames?.scene_detection ?? true,
            sceneThreshold: cfg?.frames?.scene_threshold ?? 0.4
        )

        // Transcription: CLI overrides config
        let transcriptionStr = cliTranscription ?? cfg?.transcription?.prefer ?? "captions"
        let transcriptionMethod = TranscriptionMethod(rawValue: transcriptionStr) ?? .captions
        let whisperEngineStr = cfg?.transcription?.local_engine ?? "mlx-whisper"
        let whisperEngine = WhisperEngine(rawValue: whisperEngineStr) ?? .mlxWhisper
        let whisperModel = cfg?.transcription?.model ?? "base"
        let transcriptionLanguage = cfg?.transcription?.language ?? "en"
        let openAIAPIKeyEnvVar = cfg?.transcription?.openai_api_key_env ?? "OPENAI_API_KEY"

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
            filenameFormat: filenameFormat,
            framesEnabled: cliFrames,
            frameConfig: frameConfig,
            attachmentsFolder: attachmentsFolder,
            imageSyntax: imageSyntax,
            transcriptionMethod: transcriptionMethod,
            whisperEngine: whisperEngine,
            whisperModel: whisperModel,
            transcriptionLanguage: transcriptionLanguage,
            openAIAPIKeyEnvVar: openAIAPIKeyEnvVar
        )
    }
}
