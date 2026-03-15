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
    public let verbosity: Verbosity
    public let dryRun: Bool
    public let transcriptOnly: Bool
    public let customPromptPath: String?
    public let outputFormat: OutputFormat
    public let overwrite: Bool
    public let provider: LLMProvider

    public enum ImageSyntax: String, Sendable {
        case markdown
        case wikilink
    }

    public enum Verbosity: Sendable {
        case normal
        case quiet
        case verbose
    }

    public enum OutputFormat: String, Sendable {
        case markdown
        case json
        case yaml
    }

    public enum LLMProvider: String, Sendable {
        case claude
        case openai
        case ollama
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
        openAIAPIKeyEnvVar: String = "OPENAI_API_KEY",
        verbosity: Verbosity = .normal,
        dryRun: Bool = false,
        transcriptOnly: Bool = false,
        customPromptPath: String? = nil,
        outputFormat: OutputFormat = .markdown,
        overwrite: Bool = false,
        provider: LLMProvider = .claude
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
        self.verbosity = verbosity
        self.dryRun = dryRun
        self.transcriptOnly = transcriptOnly
        self.customPromptPath = customPromptPath
        self.outputFormat = outputFormat
        self.overwrite = overwrite
        self.provider = provider
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

    /// Creates a new Configuration with a different URL and optional output directory override.
    /// Used for batch/playlist processing where each video gets its own config.
    public func withURL(_ newURL: String, outputDir: String? = nil) -> Configuration {
        return Configuration(
            url: newURL,
            outputPath: "",
            apiKeyEnvVar: apiKeyEnvVar,
            model: model,
            maxTokens: maxTokens,
            defaultTags: defaultTags,
            cookiesFromBrowser: cookiesFromBrowser,
            autoTag: autoTag,
            vaultPath: outputDir ?? vaultPath,
            vaultFolder: outputDir != nil ? nil : vaultFolder,
            filenameFormat: filenameFormat,
            framesEnabled: framesEnabled,
            frameConfig: frameConfig,
            attachmentsFolder: attachmentsFolder,
            imageSyntax: imageSyntax,
            transcriptionMethod: transcriptionMethod,
            whisperEngine: whisperEngine,
            whisperModel: whisperModel,
            transcriptionLanguage: transcriptionLanguage,
            openAIAPIKeyEnvVar: openAIAPIKeyEnvVar,
            verbosity: verbosity,
            dryRun: dryRun,
            transcriptOnly: transcriptOnly,
            customPromptPath: customPromptPath,
            outputFormat: outputFormat,
            overwrite: overwrite,
            provider: provider
        )
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
        cliQuiet: Bool = false,
        cliVerbose: Bool = false,
        cliDryRun: Bool = false,
        cliTranscriptOnly: Bool = false,
        cliPrompt: String? = nil,
        cliFormat: String? = nil,
        cliOverwrite: Bool = false,
        cliProvider: String? = nil,
        cliModel: String? = nil,
        configFile: ConfigFile?
    ) -> Configuration {
        let cfg = configFile

        let providerStr = cliProvider ?? cfg?.summarization?.provider ?? "claude"
        let provider = LLMProvider(rawValue: providerStr) ?? .claude

        let defaultModel: String
        switch provider {
        case .claude: defaultModel = "claude-sonnet-4-6"
        case .openai: defaultModel = "gpt-4o"
        case .ollama: defaultModel = "llama3.2"
        }

        let apiKeyEnvVar = cfg?.summarization?.api_key_env ?? "ANTHROPIC_API_KEY"
        let model = cliModel ?? cfg?.summarization?.model ?? defaultModel
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

        // Verbosity: --quiet and --verbose are mutually exclusive; CLI wins
        let verbosity: Verbosity
        if cliQuiet { verbosity = .quiet }
        else if cliVerbose { verbosity = .verbose }
        else { verbosity = .normal }

        // Output format: CLI --format overrides, or infer from file extension
        let outputFormat: OutputFormat
        if let fmt = cliFormat, let parsed = OutputFormat(rawValue: fmt) {
            outputFormat = parsed
        } else if let output = cliOutput, !output.isEmpty {
            let ext = (output as NSString).pathExtension.lowercased()
            switch ext {
            case "json": outputFormat = .json
            case "yaml", "yml": outputFormat = .yaml
            default: outputFormat = .markdown
            }
        } else {
            outputFormat = .markdown
        }

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
            openAIAPIKeyEnvVar: openAIAPIKeyEnvVar,
            verbosity: verbosity,
            dryRun: cliDryRun,
            transcriptOnly: cliTranscriptOnly,
            customPromptPath: cliPrompt,
            outputFormat: outputFormat,
            overwrite: cliOverwrite,
            provider: provider
        )
    }
}
