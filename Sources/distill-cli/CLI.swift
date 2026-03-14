import ArgumentParser
import Distill
import Foundation

@main
struct CLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "distill",
        abstract: "Distill the essence of any YouTube video into your Obsidian vault.",
        subcommands: [Distill.self, Batch.self, Playlist.self, Init.self, Setup.self],
        defaultSubcommand: Distill.self
    )
}

// MARK: - Shared Options

struct SharedOptions: ParsableArguments {
    @Option(name: .long, help: "Browser to read cookies from for yt-dlp (e.g. brave, chrome, firefox).")
    var cookiesFromBrowser: String?

    @Option(name: .long, help: "Path to config file (default: ~/.distill/config.yaml).")
    var config: String?

    @Flag(name: .long, help: "Extract key frames from the video (requires ffmpeg).")
    var frames: Bool = false

    @Option(name: .long, help: "Transcription method: captions, local, cloud (default: captions).")
    var transcription: String?
}

// MARK: - distill <url> (default subcommand)

struct Distill: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "distill",
        abstract: "Summarize a YouTube video."
    )

    @Argument(help: "YouTube video URL to distill.")
    var url: String

    @Option(name: .long, help: "Output file path for the markdown summary.")
    var output: String?

    @OptionGroup var shared: SharedOptions

    mutating func run() async throws {
        let configFile = try loadConfigFile(path: shared.config)

        let cfg = Configuration.merged(
            url: url,
            cliOutput: output,
            cliCookies: shared.cookiesFromBrowser,
            cliFrames: shared.frames,
            cliTranscription: shared.transcription,
            configFile: configFile
        )

        guard let apiKey = cfg.apiKey, !apiKey.isEmpty else {
            printError(DistillError.missingAPIKey)
            throw ExitCode(DistillError.missingAPIKey.exitCode)
        }

        let pipeline = try buildPipeline(url: url, cfg: cfg, apiKey: apiKey)

        do {
            try await pipeline.run()
        } catch let error as DistillError {
            printError(error)
            throw ExitCode(error.exitCode)
        }
    }
}

// MARK: - distill batch <file>

struct Batch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch",
        abstract: "Process multiple YouTube URLs from a text file."
    )

    @Argument(help: "Path to a text file with one YouTube URL per line.")
    var file: String

    @Option(name: .long, help: "Output directory for markdown summaries.")
    var output: String?

    @Option(name: .long, help: "Number of videos to process in parallel (default: 1).")
    var concurrency: Int = 1

    @Flag(name: .long, help: "Stop processing on first error.")
    var failFast: Bool = false

    @OptionGroup var shared: SharedOptions

    mutating func run() async throws {
        let urls = try loadURLsFromFile(file)
        guard !urls.isEmpty else {
            printError(DistillError.configurationError("No URLs found in \(file)"))
            throw ExitCode(3)
        }

        logStderr("Batch: \(urls.count) URLs, concurrency: \(concurrency)\n")

        let configFile = try loadConfigFile(path: shared.config)
        let baseCfg = Configuration.merged(
            url: "",
            cliOutput: nil,
            cliCookies: shared.cookiesFromBrowser,
            cliFrames: shared.frames,
            cliTranscription: shared.transcription,
            configFile: configFile
        )

        guard let apiKey = baseCfg.apiKey, !apiKey.isEmpty else {
            printError(DistillError.missingAPIKey)
            throw ExitCode(DistillError.missingAPIKey.exitCode)
        }

        let outputDir = output
        let factory = PipelineFactory { url in
            let cfg = baseCfg.withURL(url, outputDir: outputDir)
            return try buildPipeline(url: url, cfg: cfg, apiKey: apiKey)
        }

        let runner = BatchRunner(
            pipelineFactory: factory,
            concurrency: concurrency,
            failFast: failFast
        )

        let results = try await runner.run(urls: urls)
        StatusTable.print(results: results, title: "Batch Results")

        let exitCode = DistillError.batchExitCode(results: results)
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }
}

// MARK: - distill playlist <url>

struct Playlist: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "playlist",
        abstract: "Process all videos in a YouTube playlist."
    )

    @Argument(help: "YouTube playlist URL.")
    var url: String

    @Option(name: .long, help: "Output directory for markdown summaries.")
    var output: String?

    @Option(name: .long, help: "Number of videos to process in parallel (default: 1).")
    var concurrency: Int = 1

    @Flag(name: .long, help: "Stop processing on first error.")
    var failFast: Bool = false

    @OptionGroup var shared: SharedOptions

    mutating func run() async throws {
        let configFile = try loadConfigFile(path: shared.config)
        let baseCfg = Configuration.merged(
            url: "",
            cliOutput: nil,
            cliCookies: shared.cookiesFromBrowser,
            cliFrames: shared.frames,
            cliTranscription: shared.transcription,
            configFile: configFile
        )

        guard let apiKey = baseCfg.apiKey, !apiKey.isEmpty else {
            printError(DistillError.missingAPIKey)
            throw ExitCode(DistillError.missingAPIKey.exitCode)
        }

        // Resolve playlist
        logStderr("Resolving playlist...\n")
        let resolver = PlaylistResolver(cookiesFromBrowser: baseCfg.cookiesFromBrowser)
        let playlistInfo: PlaylistInfo
        do {
            playlistInfo = try await resolver.resolve(url: url)
        } catch let error as DistillError {
            printError(error)
            throw ExitCode(error.exitCode)
        }

        logStderr("Playlist: \(playlistInfo.title) (\(playlistInfo.videoURLs.count) videos)\n")

        let outputDir = output
        let factory = PipelineFactory { url in
            let cfg = baseCfg.withURL(url, outputDir: outputDir)
            return try buildPipeline(url: url, cfg: cfg, apiKey: apiKey)
        }

        let runner = BatchRunner(
            pipelineFactory: factory,
            concurrency: concurrency,
            failFast: failFast
        )

        let results = try await runner.run(urls: playlistInfo.videoURLs)
        StatusTable.print(results: results, title: playlistInfo.title)

        // Generate index note
        let indexOutputDir: String
        if let dir = outputDir {
            indexOutputDir = dir
        } else if let vault = baseCfg.vaultPath {
            let expanded = NSString(string: vault).expandingTildeInPath
            let folder = baseCfg.vaultFolder ?? "YouTube"
            indexOutputDir = "\(expanded)/\(folder)"
        } else {
            indexOutputDir = FileManager.default.currentDirectoryPath
        }

        do {
            try IndexNoteWriter().write(
                playlistTitle: playlistInfo.title,
                results: results,
                to: indexOutputDir,
                filenameFormat: baseCfg.filenameFormat
            )
        } catch {
            logStderr("Warning: Failed to write index note: \(error.localizedDescription)\n")
        }

        let exitCode = DistillError.batchExitCode(results: results)
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }
}

// MARK: - distill init

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a starter config file at ~/.distill/config.yaml."
    )

    @Option(name: .long, help: "Path to your Obsidian vault.")
    var vault: String?

    func run() throws {
        let configPath = ConfigLoader.defaultConfigPath

        if FileManager.default.fileExists(atPath: configPath.path) {
            print("Config already exists at \(configPath.path)")
            print("Edit it directly or delete it and run `distill init` again.")
            return
        }

        let configDir = ConfigLoader.defaultConfigDir
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let content = ConfigLoader.starterConfig(vault: vault)
        try content.write(to: configPath, atomically: true, encoding: .utf8)

        print("Created config at \(configPath.path)")
        print("Edit it to configure your Obsidian vault path and preferences.")
    }
}

// MARK: - distill setup

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Interactive guided setup for distill."
    )

    mutating func run() async throws {
        print("distill setup")
        print("=============\n")

        // 1. Vault path
        print("Where is your Obsidian vault?")
        print("  (press Enter for ~/Documents/Obsidian)")
        let vaultInput = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        let vault = vaultInput.isEmpty ? "~/Documents/Obsidian" : vaultInput

        // 2. Folder
        print("\nWhich folder inside the vault for YouTube summaries?")
        print("  (press Enter for YouTube)")
        let folderInput = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        let folder = folderInput.isEmpty ? "YouTube" : folderInput

        // 3. API key env var
        print("\nWhich environment variable holds your Anthropic API key?")
        print("  (press Enter for ANTHROPIC_API_KEY)")
        let apiKeyEnvInput = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        let apiKeyEnv = apiKeyEnvInput.isEmpty ? "ANTHROPIC_API_KEY" : apiKeyEnvInput

        // Check if key exists
        if let key = ProcessInfo.processInfo.environment[apiKeyEnv], !key.isEmpty {
            print("  Found API key in \(apiKeyEnv)")
        } else {
            print("  No value found in \(apiKeyEnv). Set it before running distill.")
        }

        // 4. Cookies
        print("\nDo you need browser cookies for yt-dlp? (e.g. brave, chrome, firefox)")
        print("  (press Enter to skip)")
        let cookiesInput = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        let cookies: String? = cookiesInput.isEmpty ? nil : cookiesInput

        // 5. Auto-tag
        print("\nEnable automatic tag generation via LLM? (y/N)")
        let autoTagInput = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let autoTag = autoTagInput == "y" || autoTagInput == "yes"

        // Build config
        var yaml = """
        # distill configuration

        obsidian:
          vault: "\(vault)"
          folder: \(folder)
          filename_format: "{date}-{slug}"

        tags:
          default:
            - youtube
          auto_tag: \(autoTag)

        summarization:
          provider: claude
          model: claude-sonnet-4-6
          api_key_env: \(apiKeyEnv)
          max_tokens: 8192
        """

        if let cookies {
            yaml += "\n\ncookies_from_browser: \(cookies)"
        }

        yaml += "\n"

        // Write config
        let configDir = ConfigLoader.defaultConfigDir
        let configPath = ConfigLoader.defaultConfigPath
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)

        // Create vault folder if it doesn't exist
        let expandedVault = NSString(string: vault).expandingTildeInPath
        let vaultFolder = URL(fileURLWithPath: expandedVault).appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)

        print("\nConfig written to \(configPath.path)")
        print("Created \(vaultFolder.path)")
        print("\nYou can now run: distill <youtube-url>")
    }
}

// MARK: - Helpers

private func loadConfigFile(path: String?) throws -> ConfigFile? {
    do {
        return try ConfigLoader.load(from: path)
    } catch {
        FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
        throw ExitCode(3)
    }
}

private func buildPipeline(url: String, cfg: Configuration, apiKey: String) throws -> Pipeline {
    let provider = ClaudeProvider(
        apiKey: apiKey,
        model: cfg.model,
        maxTokens: cfg.maxTokens
    )

    let tagGenerator: TagGenerator? = cfg.autoTag ? TagGenerator(provider: provider) : nil
    let frameExtractor: FrameExtractor? = cfg.framesEnabled
        ? FrameExtractor(config: cfg.frameConfig, cookiesFromBrowser: cfg.cookiesFromBrowser)
        : nil

    let whisperTranscriber: WhisperTranscriber? = (cfg.transcriptionMethod == .local || cfg.transcriptionMethod == .captions)
        ? WhisperTranscriber(engine: cfg.whisperEngine, model: cfg.whisperModel, language: cfg.transcriptionLanguage)
        : nil

    let cloudTranscriber: WhisperCloudTranscriber?
    if cfg.transcriptionMethod == .cloud {
        guard let openAIKey = ProcessInfo.processInfo.environment[cfg.openAIAPIKeyEnvVar], !openAIKey.isEmpty else {
            throw DistillError.configurationError("Cloud transcription requires \(cfg.openAIAPIKeyEnvVar) to be set.")
        }
        cloudTranscriber = WhisperCloudTranscriber(apiKey: openAIKey, language: cfg.transcriptionLanguage)
    } else {
        cloudTranscriber = nil
    }

    return Pipeline(
        metadataResolver: MetadataResolver(cookiesFromBrowser: cfg.cookiesFromBrowser),
        transcriptAcquirer: TranscriptAcquirer(
            cookiesFromBrowser: cfg.cookiesFromBrowser,
            transcriptionMethod: cfg.transcriptionMethod,
            whisperTranscriber: whisperTranscriber,
            cloudTranscriber: cloudTranscriber
        ),
        summarizer: Summarizer(provider: provider),
        outputWriter: OutputWriter(),
        tagGenerator: tagGenerator,
        frameExtractor: frameExtractor,
        configuration: cfg
    )
}

private func loadURLsFromFile(_ path: String) throws -> [String] {
    let expandedPath = NSString(string: path).expandingTildeInPath
    let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
    return content
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

func printError(_ error: DistillError) {
    FileHandle.standardError.write(Data("Error: \(error.errorDescription!)\n".utf8))
    if let suggestion = error.suggestion {
        FileHandle.standardError.write(Data("Suggestion: \(suggestion)\n".utf8))
    }
}

func logStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
