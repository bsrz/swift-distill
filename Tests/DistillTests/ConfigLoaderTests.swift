import Testing
import Foundation
@testable import Distill

@Suite("ConfigLoader")
struct ConfigLoaderTests {
    @Test func parseValidConfig() throws {
        let yaml = """
        obsidian:
          vault: "~/Documents/Obsidian"
          folder: YouTube
          filename_format: "{date}-{slug}"

        tags:
          default:
            - youtube
            - video
          auto_tag: true

        summarization:
          provider: claude
          model: claude-sonnet-4-6
          api_key_env: ANTHROPIC_API_KEY
          max_tokens: 4096

        cookies_from_browser: brave
        """

        let config = try ConfigLoader.parse(yaml)
        #expect(config.obsidian?.vault == "~/Documents/Obsidian")
        #expect(config.obsidian?.folder == "YouTube")
        #expect(config.obsidian?.filename_format == "{date}-{slug}")
        #expect(config.tags?.default == ["youtube", "video"])
        #expect(config.tags?.auto_tag == true)
        #expect(config.summarization?.provider == "claude")
        #expect(config.summarization?.model == "claude-sonnet-4-6")
        #expect(config.summarization?.api_key_env == "ANTHROPIC_API_KEY")
        #expect(config.summarization?.max_tokens == 4096)
        #expect(config.cookies_from_browser == "brave")
    }

    @Test func parseMinimalConfig() throws {
        let yaml = """
        obsidian:
          vault: ~/Vault
        """
        let config = try ConfigLoader.parse(yaml)
        #expect(config.obsidian?.vault == "~/Vault")
        #expect(config.obsidian?.folder == nil)
        #expect(config.tags == nil)
        #expect(config.summarization == nil)
    }

    @Test func parseEmptyConfig() throws {
        let config = try ConfigLoader.parse("")
        #expect(config.obsidian == nil)
    }

    @Test func badYAMLSyntaxThrows() {
        #expect(throws: DistillError.self) {
            try ConfigLoader.parse("obsidian:\n  vault: [unterminated", path: "test.yaml")
        }
    }

    @Test func wrongTypeThrows() {
        let yaml = """
        summarization:
          max_tokens: "not a number"
        """
        #expect(throws: DistillError.self) {
            try ConfigLoader.parse(yaml, path: "test.yaml")
        }
    }

    @Test func loadFromNonexistentPathReturnsNil() throws {
        let config = try ConfigLoader.load(from: "/tmp/nonexistent-distill-config-\(UUID()).yaml")
        #expect(config == nil)
    }

    @Test func starterConfigIsValidYAML() throws {
        let yaml = ConfigLoader.starterConfig(vault: "~/MyVault")
        let config = try ConfigLoader.parse(yaml)
        #expect(config.obsidian?.vault == "~/MyVault")
        #expect(config.tags?.default == ["youtube"])
    }
}

@Suite("Configuration.merged")
struct ConfigurationMergedTests {
    @Test func cliOverridesConfig() {
        let configFile = ConfigFile(
            obsidian: .init(vault: "~/Vault", folder: "Videos", filename_format: nil),
            tags: .init(default: ["video"], auto_tag: true),
            summarization: .init(provider: "claude", model: "claude-haiku-4-5", api_key_env: nil, max_tokens: nil),
            cookies_from_browser: "chrome"
        )

        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=abc",
            cliOutput: "/tmp/override.md",
            cliCookies: "brave",
            configFile: configFile
        )

        // CLI wins over config
        #expect(cfg.outputPath == "/tmp/override.md")
        #expect(cfg.cookiesFromBrowser == "brave")

        // Config values used
        #expect(cfg.model == "claude-haiku-4-5")
        #expect(cfg.defaultTags == ["video"])
        #expect(cfg.autoTag == true)
        #expect(cfg.vaultPath == "~/Vault")
    }

    @Test func defaultsWhenNoConfig() {
        let cfg = Configuration.merged(
            url: "https://www.youtube.com/watch?v=abc",
            cliOutput: nil,
            cliCookies: nil,
            configFile: nil
        )

        #expect(cfg.model == "claude-sonnet-4-6")
        #expect(cfg.maxTokens == 8192)
        #expect(cfg.defaultTags == ["youtube"])
        #expect(cfg.autoTag == false)
        #expect(cfg.apiKeyEnvVar == "ANTHROPIC_API_KEY")
        #expect(cfg.vaultPath == nil)
        #expect(cfg.cookiesFromBrowser == nil)
    }

    @Test func resolvedOutputPathFromVault() {
        let cfg = Configuration(
            url: "https://www.youtube.com/watch?v=abc",
            outputPath: "",
            vaultPath: "/tmp/TestVault",
            vaultFolder: "YouTube",
            filenameFormat: "{date}-{slug}"
        )

        let metadata = VideoMetadata(
            id: "abc",
            title: "My Test Video",
            channel: "Test",
            channelURL: "",
            uploadDate: "20260314",
            duration: 60,
            durationString: "1:00",
            description: "",
            tags: [],
            thumbnailURL: "",
            webpageURL: "https://www.youtube.com/watch?v=abc",
            hasSubtitles: false,
            hasAutomaticCaptions: false
        )

        let path = cfg.resolvedOutputPath(for: metadata)
        #expect(path.hasPrefix("/tmp/TestVault/YouTube/"))
        #expect(path.hasSuffix("-my-test-video.md"))
    }

    @Test func explicitOutputOverridesVault() {
        let cfg = Configuration(
            url: "https://www.youtube.com/watch?v=abc",
            outputPath: "/tmp/explicit.md",
            vaultPath: "/tmp/TestVault",
            vaultFolder: "YouTube"
        )

        let metadata = VideoMetadata(
            id: "abc", title: "Test", channel: "", channelURL: "",
            uploadDate: "20260314", duration: 60, durationString: "1:00",
            description: "", tags: [], thumbnailURL: "",
            webpageURL: "", hasSubtitles: false, hasAutomaticCaptions: false
        )

        #expect(cfg.resolvedOutputPath(for: metadata) == "/tmp/explicit.md")
    }
}
